$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-location/test-support.ps1')
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-xlsx/test-support.ps1')
. (Join-Path $PSScriptRoot 'lib/benefit-evidence/convert-html-source-observation.ps1')
. (Join-Path $PSScriptRoot 'lib/benefit-evidence/convert-mma-jsonp-source-observation.ps1')
. (Join-Path $PSScriptRoot 'lib/benefit-evidence/convert-xlsx-source-observation.ps1')
$locatorPath = Join-Path $PSScriptRoot 'lib/benefit-evidence/find-business-evidence-slice.ps1'
if (-not (Test-Path -LiteralPath $locatorPath)) { throw 'Business evidence locator is missing' }
. $locatorPath

function New-LocatorObservation {
    param([string]$Html)
    return ConvertTo-BenefitHtmlObservation -Document (New-ScopeTestDocument -Html $Html)
}

$business = New-ScopeTestBusiness
$exact = New-LocatorObservation -Html (Get-ScopeTestHtml)
$located = Find-BenefitBusinessEvidence -Observation $exact -Business $business -CanonicalPhone '02-0000-0012'
Assert-ScopeEqual $located.OperationalStatus 'COMPLETE' 'Complete observation keeps its operational status'
Assert-ScopeEqual $located.Status 'LOCATED' 'Exact explicit name and full address locate one row'
Assert-ScopeEqual @($located.Slices).Count 1 'Located result yields one narrow slice'
Assert-ScopeEqual $located.Slices[0].EvidenceReference 'HTML_TABLE_1_ROW_2' 'Selection preserves the original physical reference'
Assert-ScopeTrue ($located.Slices[0].RawEvidenceText -notmatch '테스트가게 B|30%') 'A selected slice excludes another business row'

$strongAndNameOnly = '<table><tr><th>업소명</th><th>주소</th><th>전화번호</th></tr><tr><td>테스트가게 A</td><td>서울특별시 마포구 테스트로 12</td><td>02-0000-0012</td></tr><tr><td>테스트가게 A</td><td></td><td></td></tr></table>'
$strongAndNameOnlyResult = Find-BenefitBusinessEvidence -Observation (New-LocatorObservation -Html $strongAndNameOnly) -Business $business -CanonicalPhone '02-0000-0012'
Assert-ScopeEqual $strongAndNameOnlyResult.Status 'AMBIGUOUS' 'A same-name candidate without corroboration remains an unresolved alternative'
Assert-ScopeEqual @($strongAndNameOnlyResult.Slices).Count 0 'An unexcluded name-only alternative prevents a usable slice'

foreach ($numbers in @(@('12','23'),@('26','23'),@('902','904'))) {
    $syntheticSource = New-LocatorObservation -Html ((Get-ScopeTestHtml).Replace('테스트로 12', "테스트로 $($numbers[0])"))
    $syntheticTarget = New-ScopeTestBusiness -Building $numbers[1]
    $syntheticResult = Find-BenefitBusinessEvidence -Observation $syntheticSource -Business $syntheticTarget -CanonicalPhone '02-0000-0012'
    Assert-ScopeTrue ($syntheticResult.Status -ne 'LOCATED') "Synthetic source $($numbers[0]) / target $($numbers[1]) building conflict must override name and phone agreement"
}

$wrongBuilding = '<table><tr><th>업소명</th><th>주소</th><th>전화번호</th></tr><tr><td>테스트가게 A</td><td>서울특별시 마포구 테스트로 99</td><td>02-0000-0012</td></tr></table>'
$wrongBuildingResult = Find-BenefitBusinessEvidence -Observation (New-LocatorObservation -Html $wrongBuilding) -Business $business -CanonicalPhone '02-0000-0012'
Assert-ScopeEqual $wrongBuildingResult.Status 'AMBIGUOUS' 'A matching phone cannot override an explicit building conflict'
Assert-ScopeTrue (@($wrongBuildingResult.Diagnostics | Where-Object { $_.Code -eq 'LOCATOR_IDENTITY_CONFLICT' }).Count -gt 0) 'Identity conflict remains auditable'

$duplicates = '<table><tr><th>업소명</th><th>주소</th></tr><tr><td>테스트가게 A</td><td>서울특별시 마포구 테스트로 12</td></tr><tr><td>테스트가게 A</td><td>서울특별시 마포구 테스트로 12</td></tr></table>'
$duplicateResult = Find-BenefitBusinessEvidence -Observation (New-LocatorObservation -Html $duplicates) -Business $business
Assert-ScopeEqual $duplicateResult.Status 'AMBIGUOUS' 'Multiple corroborated same-name rows are not safely selectable'
Assert-ScopeEqual @($duplicateResult.Slices).Count 0 'Ambiguity never yields a usable slice'

$noPhone = '<table><tr><th>업소명</th><th>주소</th></tr><tr><td>테스트가게 A</td><td>서울특별시 마포구 테스트로 12</td></tr></table>'
$noPhoneResult = Find-BenefitBusinessEvidence -Observation (New-LocatorObservation -Html $noPhone) -Business $business
Assert-ScopeEqual $noPhoneResult.Status 'LOCATED' 'A full address can corroborate identity without a phone'
$emptyPhone = '<table><tr><th>업소명</th><th>전화번호</th></tr><tr><td>테스트가게 A</td><td>abc</td></tr></table>'
$emptyPhoneResult = Find-BenefitBusinessEvidence -Observation (New-LocatorObservation -Html $emptyPhone) -Business $business -CanonicalPhone '---'
Assert-ScopeEqual $emptyPhoneResult.Status 'AMBIGUOUS' 'Two empty normalized phone values cannot become strong corroboration'

$differentExplicitName = '<table><tr><th>업소명</th><th>주소</th><th>전화번호</th></tr><tr><td>다른 가게</td><td>서울특별시 마포구 테스트로 12</td><td>02-0000-0012</td></tr></table>'
$differentNameResult = Find-BenefitBusinessEvidence -Observation (New-LocatorObservation -Html $differentExplicitName) -Business $business -CanonicalPhone '02-0000-0012'
Assert-ScopeEqual $differentNameResult.Status 'NOT_FOUND' 'A different explicit business name is not silently promoted by address or phone'
Assert-ScopeTrue (@($differentNameResult.Diagnostics | Where-Object { $_.Code -eq 'LOCATOR_IDENTITY_CONFLICT' }).Count -eq 1) 'Address or phone agreement with a different explicit name remains reviewable'

$branchBusinessRow = New-ScopeTestRow -Name '테스트 식당 (양주점)' -Building '12'
$branchBusiness = ConvertTo-NormalizedBusiness -Row $branchBusinessRow -SourceRowNumber 2
$branchConflict = '<table><tr><th>사업장명</th><th>주소</th><th>지점명</th></tr><tr><td>테스트 식당 양주점</td><td>서울특별시 마포구 테스트로 12</td><td>신양주점</td></tr></table>'
$branchResult = Find-BenefitBusinessEvidence -Observation (New-LocatorObservation -Html $branchConflict) -Business $branchBusiness
Assert-ScopeEqual $branchResult.Status 'AMBIGUOUS' 'Different explicit branch identities are a hard conflict'
Assert-ScopeTrue (@($branchResult.Diagnostics | Where-Object { $_.Code -eq 'LOCATOR_IDENTITY_CONFLICT' }).Count -gt 0) 'Branch conflict is retained for review'

$floorBusinessRow = New-ScopeTestRow -Name '층수 가게' -Building '12 2층 201호'
$floorBusiness = ConvertTo-NormalizedBusiness -Row $floorBusinessRow -SourceRowNumber 2
$floorConflict = '<table><tr><th>업소명</th><th>주소</th></tr><tr><td>층수 가게</td><td>서울특별시 마포구 테스트로 12 3층 301호</td></tr></table>'
$floorResult = Find-BenefitBusinessEvidence -Observation (New-LocatorObservation -Html $floorConflict) -Business $floorBusiness
Assert-ScopeEqual $floorResult.Status 'AMBIGUOUS' 'Different explicit floor or unit identities are a hard conflict'

$absent = Find-BenefitBusinessEvidence -Observation $exact -Business (New-ScopeTestBusiness -Name '없는 가게')
Assert-ScopeEqual $absent.Status 'NOT_FOUND' 'Only a complete observation may establish absence'

$partialObservation = New-LocatorObservation -Html ((Get-ScopeTestHtml) -replace '<td>30% 할인</td>', '')
$partial = Find-BenefitBusinessEvidence -Observation $partialObservation -Business $business
Assert-ScopeEqual $partial.OperationalStatus 'PARTIAL' 'Partial parsing must propagate operational state'
Assert-ScopeTrue ($null -eq $partial.Status) 'Partial parsing must not claim NOT_FOUND'
Assert-ScopeEqual @($partial.Slices).Count 0 'Partial parsing cannot expose a usable slice'
Assert-ScopeTrue (@($partial.Diagnostics | Where-Object { $_.Code -eq $partialObservation.Diagnostics[0].Code -and $_.EvidenceReference -eq $partialObservation.Diagnostics[0].EvidenceReference }).Count -eq 1) 'Location result must preserve the parser diagnostic and physical reference'

$reverse = '<table><tr><th>업소명</th><th>주소</th><th>할인</th></tr><tr><td>테스트가게 B</td><td>서울특별시 마포구 테스트로 99</td><td>10% 할인</td></tr><tr><td>테스트가게 A</td><td>서울특별시 마포구 테스트로 12</td><td>10% 할인</td></tr></table>'
$reverseResult = Find-BenefitBusinessEvidence -Observation (New-LocatorObservation -Html $reverse) -Business $business
Assert-ScopeEqual $reverseResult.Status 'LOCATED' 'Same discount for another business has no selection role'
Assert-ScopeEqual $reverseResult.Slices[0].EvidenceReference 'HTML_TABLE_1_ROW_3' 'Selection follows business identity rather than row order'

$mmaFixtureRoot = Join-Path $PSScriptRoot 'testdata/benefit-evidence-mma'
$mmaListText = Get-Content -Raw -LiteralPath (Join-Path $mmaFixtureRoot 'mma-list.fixture.jsonp')
$tourBusinessRow = [pscustomobject]@{
    업소명='(유)투투여행사'; 시도='서울특별시'; 시군구='테스트구'; 소재지도로명주소='서울특별시 테스트구 여행로 2789'; 소재지지번주소=''
    업소전화번호='02-2789-0000'; 할인정보=''; 적용대상=''; 이용조건=''; 인증방법=''; 출처유형='병무청 공식 자료'; 출처URL='https://www.mma.go.kr/about/udgg/list.do?mc=mma0003357'; 최근확인일='2026-09-25'
}
$tourBusiness = ConvertTo-NormalizedBusiness -Row $tourBusinessRow -SourceRowNumber 2
$mmaListDocument = New-BenefitSourceDocument -SourceRowNumber 2 -Url 'https://open.mma.go.kr/caisGGGS/mmanrsrListAjaxJsonCallNew.json?callback=MmaTestList' -SourceFormat JSONP -FetchStatus COMPLETE -Text $mmaListText -ObservedAt '2026-09-25T00:00:00Z'
$mmaObservation = ConvertTo-MmaJsonpListObservation -Document $mmaListDocument -ExpectedCallback MmaTestList
$mmaLocated = Find-BenefitBusinessEvidence -Observation $mmaObservation -Business $tourBusiness -CanonicalPhone '02-2789-0000'
Assert-ScopeEqual $mmaLocated.Status LOCATED 'MMA list identity can locate one record'
Assert-ScopeEqual $mmaLocated.Slices[0].StructuredFields.InstitutionCode 2789 'Located MMA record carries institution code'
Assert-ScopeEqual $mmaLocated.Slices[0].ScopeType JSON_OBJECT 'Located MMA record remains a JSONP object slice'

$mmaAmbiguousText = $mmaListText -replace '\]\}\);\s*$', ',{"udgigwan_cd":"9992","udgigwan_yhnm":"(유)투투여행사","addr":"","udgigwan_telno":"","udggeopjong_gbnm":"여행사"}]});'
$mmaAmbiguousDocument = New-BenefitSourceDocument -SourceRowNumber 2 -Url $mmaListDocument.Url -SourceFormat JSONP -FetchStatus COMPLETE -Text $mmaAmbiguousText -ObservedAt $mmaListDocument.ObservedAt
$mmaAmbiguous = Find-BenefitBusinessEvidence -Observation (ConvertTo-MmaJsonpListObservation -Document $mmaAmbiguousDocument -ExpectedCallback MmaTestList) -Business $tourBusiness -CanonicalPhone '02-2789-0000'
Assert-ScopeEqual $mmaAmbiguous.Status AMBIGUOUS 'Same normalized MMA business name without corroboration remains ambiguous'
Assert-ScopeEqual @($mmaAmbiguous.Slices).Count 0 'Ambiguous MMA list candidates expose no usable slice'

$mmaConflictText = 'MmaTestList({"success":true,"list":[{"udgigwan_cd":"9993","udgigwan_yhnm":"(유)투투여행사","addr":"서울특별시 다른구 충돌로 1","udgigwan_telno":"02-2789-0000","udggeopjong_gbnm":"여행사"}]});'
$mmaConflictDocument = New-BenefitSourceDocument -SourceRowNumber 2 -Url $mmaListDocument.Url -SourceFormat JSONP -FetchStatus COMPLETE -Text $mmaConflictText -ObservedAt $mmaListDocument.ObservedAt
$mmaConflict = Find-BenefitBusinessEvidence -Observation (ConvertTo-MmaJsonpListObservation -Document $mmaConflictDocument -ExpectedCallback MmaTestList) -Business $tourBusiness -CanonicalPhone '02-2789-0000'
Assert-ScopeTrue ($mmaConflict.Status -ne 'LOCATED') 'Explicit MMA address conflict cannot be selected despite name and phone agreement'

$mmaCodeOnlyText = 'MmaTestList({"success":true,"list":[{"udgigwan_cd":"2789","udgigwan_yhnm":"다른 여행사","addr":"서울특별시 테스트구 여행로 2789","udgigwan_telno":"02-2789-0000","udggeopjong_gbnm":"여행사"}]});'
$mmaCodeOnlyDocument = New-BenefitSourceDocument -SourceRowNumber 2 -Url $mmaListDocument.Url -SourceFormat JSONP -FetchStatus COMPLETE -Text $mmaCodeOnlyText -ObservedAt $mmaListDocument.ObservedAt
$mmaCodeOnly = Find-BenefitBusinessEvidence -Observation (ConvertTo-MmaJsonpListObservation -Document $mmaCodeOnlyDocument -ExpectedCallback MmaTestList) -Business $tourBusiness -CanonicalPhone '02-2789-0000'
Assert-ScopeEqual $mmaCodeOnly.Status NOT_FOUND 'Institution code alone cannot override a different business identity'

$xlsxBusinessRow = [pscustomobject]@{
    업소명='가마골 백숙'; 시도='경기도'; 시군구='양주시'; 소재지도로명주소='양주시 장흥면 북한산로 1028'; 소재지지번주소=''
    업소전화번호='031-861-4800'; 할인정보=''; 적용대상=''; 이용조건=''; 인증방법=''; 출처유형='지자체 공식 자료'; 출처URL='https://city.example.go.kr/benefits.xlsx'; 최근확인일='2026-09-26'
}
$xlsxBusiness = ConvertTo-NormalizedBusiness -Row $xlsxBusinessRow -SourceRowNumber 2
$xlsxDocument = New-BenefitSourceDocument -SourceRowNumber 2 -Url 'https://city.example.go.kr/benefits.xlsx' -SourceFormat XLSX -FetchStatus COMPLETE -Text '' -Bytes (New-XlsxTestBytes) -ObservedAt '2026-09-26T00:00:00Z'
$xlsxConverted = ConvertTo-BenefitXlsxObservation -Document $xlsxDocument
$xlsxLocated = Find-BenefitBusinessEvidence -Observation $xlsxConverted -Business $xlsxBusiness -CanonicalPhone '031-861-4800' -XlsxValidationIndex $xlsxConverted.XlsxValidationIndex
Assert-ScopeEqual $xlsxLocated.Status LOCATED 'XLSX rows reuse the deterministic identity matcher'
Assert-ScopeEqual $xlsxLocated.Slices[0].EvidenceReference XLSX_SHEET_1_ROW_22 'XLSX locator preserves the physical row reference'
Assert-ScopeEqual $xlsxLocated.Slices[0].FieldReferences.BenefitDescription.CellReference F22 'XLSX locator preserves benefit-cell provenance'
$xlsxLocatedWithAttachedIndex = Find-BenefitBusinessEvidence -Observation $xlsxConverted -Business $xlsxBusiness -CanonicalPhone '031-861-4800'
Assert-ScopeEqual $xlsxLocatedWithAttachedIndex.Status LOCATED 'XLSX locator reuses its attached snapshot-bound validation index without a reparse'
$xlsxIrrelevantUnsupportedDocument = New-BenefitSourceDocument -SourceRowNumber 2 -Url 'https://city.example.go.kr/irrelevant-unsupported.xlsx' -SourceFormat XLSX -FetchStatus COMPLETE -Text '' -Bytes (New-XlsxTestBytes -UnrelatedUnsupportedRow) -ObservedAt '2026-09-26T00:00:00Z'
$xlsxIrrelevantUnsupported = Find-BenefitBusinessEvidence -Observation (ConvertTo-BenefitXlsxObservation -Document $xlsxIrrelevantUnsupportedDocument) -Business $xlsxBusiness -CanonicalPhone '031-861-4800'
Assert-ScopeEqual $xlsxIrrelevantUnsupported.OperationalStatus COMPLETE 'An isolated irrelevant XLSX row does not poison the observation status'
Assert-ScopeEqual $xlsxIrrelevantUnsupported.Status LOCATED 'An isolated irrelevant XLSX row does not prevent a valid candidate slice'
$xlsxUnmappedUnsupportedDocument = New-BenefitSourceDocument -SourceRowNumber 2 -Url 'https://city.example.go.kr/unmapped-unsupported.xlsx' -SourceFormat XLSX -FetchStatus COMPLETE -Text '' -Bytes (New-XlsxTestBytes -UnmappedUnsupportedCell) -ObservedAt '2026-09-26T00:00:00Z'
$xlsxUnmappedUnsupported = Find-BenefitBusinessEvidence -Observation (ConvertTo-BenefitXlsxObservation -Document $xlsxUnmappedUnsupportedDocument) -Business $xlsxBusiness -CanonicalPhone '031-861-4800'
Assert-ScopeEqual $xlsxUnmappedUnsupported.Status LOCATED 'An unsupported unmapped cell does not prevent the valid XLSX row from locating'
$xlsxDuplicateDocument = New-BenefitSourceDocument -SourceRowNumber 2 -Url 'https://city.example.go.kr/duplicates.xlsx' -SourceFormat XLSX -FetchStatus COMPLETE -Text '' -Bytes (New-XlsxTestBytes -DuplicateBusinessNameCell) -ObservedAt '2026-09-26T00:00:00Z'
$xlsxDuplicate = Find-BenefitBusinessEvidence -Observation (ConvertTo-BenefitXlsxObservation -Document $xlsxDuplicateDocument) -Business $xlsxBusiness -CanonicalPhone '031-861-4800'
Assert-ScopeEqual $xlsxDuplicate.Status AMBIGUOUS 'Duplicate XLSX name candidates cannot be selected by one strong row'
Assert-ScopeEqual @($xlsxDuplicate.Slices).Count 0 'Ambiguous XLSX identity yields no slice'
$xlsxAbsent = Find-BenefitBusinessEvidence -Observation $xlsxConverted -Business (ConvertTo-NormalizedBusiness -Row ([pscustomobject]@{ 업소명='없는 가게'; 시도='경기도'; 시군구='양주시'; 소재지도로명주소='양주시 장흥면 북한산로 1028'; 소재지지번주소=''; 업소전화번호='031-861-4800'; 할인정보=''; 적용대상=''; 이용조건=''; 인증방법=''; 출처유형='지자체 공식 자료'; 출처URL='https://city.example.go.kr/benefits.xlsx'; 최근확인일='2026-09-26' }) -SourceRowNumber 2) -CanonicalPhone '031-861-4800'
Assert-ScopeEqual $xlsxAbsent.Status NOT_FOUND 'Absent XLSX identity is not a lifecycle conclusion'
$xlsxUnsupportedDocument = New-BenefitSourceDocument -SourceRowNumber 2 -Url 'https://city.example.go.kr/no-identity.xlsx' -SourceFormat XLSX -FetchStatus COMPLETE -Text '' -Bytes (New-XlsxTestBytes -NoIdentityHeader) -ObservedAt '2026-09-26T00:00:00Z'
$xlsxUnsupported = Find-BenefitBusinessEvidence -Observation (ConvertTo-BenefitXlsxObservation -Document $xlsxUnsupportedDocument) -Business $xlsxBusiness -CanonicalPhone '031-861-4800'
Assert-ScopeEqual $xlsxUnsupported.OperationalStatus UNSUPPORTED 'Unsupported XLSX structure preserves an operational rather than semantic outcome'
Assert-ScopeTrue ($null -eq $xlsxUnsupported.Status) 'Unsupported XLSX structure cannot claim NOT_FOUND'
$otherXlsxDocument = New-BenefitSourceDocument -SourceRowNumber 2 -Url 'https://city.example.go.kr/other.xlsx' -SourceFormat XLSX -FetchStatus COMPLETE -Text '' -Bytes (New-XlsxTestBytes -Name '다른 가게') -ObservedAt '2026-09-26T00:00:00Z'
$otherXlsxIndex = (ConvertTo-BenefitXlsxObservation -Document $otherXlsxDocument).XlsxValidationIndex
Assert-ScopeThrows { Find-BenefitBusinessEvidence -Observation $xlsxConverted -Business $xlsxBusiness -CanonicalPhone '031-861-4800' -XlsxValidationIndex $otherXlsxIndex } 'The locator rejects a validation index from another XLSX snapshot'

Write-Host 'Business evidence locator tests passed.'

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-location/test-support.ps1')
. (Join-Path $PSScriptRoot 'lib/benefit-evidence/convert-html-source-observation.ps1')
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

Write-Host 'Business evidence locator tests passed.'

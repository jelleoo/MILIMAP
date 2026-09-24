$ErrorActionPreference = 'Stop'

$contractPath = Join-Path $PSScriptRoot 'lib/benefit-verification-contracts.ps1'
$bindingPath = Join-Path $PSScriptRoot 'lib/benefit-source/bind-benefit-source.ps1'
. $contractPath
if (Test-Path -LiteralPath $bindingPath) { . $bindingPath }

function Assert-Equal {
    param([AllowNull()]$Actual, [AllowNull()]$Expected, [Parameter(Mandatory)][string]$Message)
    if ($Actual -cne $Expected) { throw "$Message (expected: $Expected, actual: $Actual)" }
}

function Assert-True {
    param([bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Throws {
    param([Parameter(Mandatory)][scriptblock]$Action, [Parameter(Mandatory)][string]$Message)
    $threw = $false
    try { & $Action } catch { $threw = $true }
    if (-not $threw) { throw $Message }
}

function New-TestBusiness {
    param([int]$SourceRowNumber = 2)
    return New-NormalizedBusiness -SourceRowNumber $SourceRowNumber -OriginalName '테스트 식당 양주점' -NormalizedName '테스트식당양주점' -BaseName '테스트 식당' -BranchName '양주점' -OriginalRoadAddress '경기도 양주시 고암동 테스트로 22-25' -PreferredAddress '경기도 양주시 고암동 테스트로 22-25' -Province '경기도' -City '양주시' -Dong '고암동' -RoadName '테스트로' -BuildingMain '22' -BuildingSub '25' -AddressParseStatus 'COMPLETE'
}

function New-TestQualifiedSource {
    param([string]$Text, [int]$SourceRowNumber = 2)
    $candidate = New-BenefitSourceCandidate -SourceRowNumber $SourceRowNumber -Url 'https://city.example.go.kr/benefit' -SourceKind 'PUBLIC_OFFICIAL' -SourceLabel 'fixture' -DiscoveryMethod 'TEST' -ObservedAt '2026-09-24T00:00:00Z'
    $document = New-BenefitSourceDocument -SourceRowNumber $SourceRowNumber -Url $candidate.Url -SourceFormat 'HTML' -FetchStatus 'COMPLETE' -ContentType 'text/html' -Text $Text -ObservedAt '2026-09-24T00:00:00Z'
    return New-QualifiedBenefitSource -Candidate $candidate -Document $document -OfficialityStatus 'VERIFIED_OFFICIAL' -CurrentnessStatus 'UNKNOWN'
}

$business = New-TestBusiness

$addressStrong = Get-BenefitBusinessBinding -Source (New-TestQualifiedSource -Text '사업장명: 테스트 식당 양주점; 주소: 경기도 양주시 고암동 테스트로 22-25') -Business $business -CanonicalPhone '031-123-4567'
Assert-BoundBenefitSource $addressStrong
Assert-Equal $addressStrong.BusinessBindingStatus 'STRONG' 'Compatible business name plus full address binds strongly'
Assert-True ($addressStrong.BindingEvidence -contains 'FULL_ADDRESS_MATCH') 'Strong address binding preserves exact signal'

$branchStrong = Get-BenefitBusinessBinding -Source (New-TestQualifiedSource -Text '사업장명: 테스트 식당 양주점; 지점: 양주점') -Business $business -CanonicalPhone ''
Assert-Equal $branchStrong.BusinessBindingStatus 'STRONG' 'Compatible business name plus explicit branch binds strongly'
Assert-True ($branchStrong.BindingEvidence -contains 'BRANCH_MATCH') 'Strong branch binding preserves exact signal'

foreach ($wrongBranch in @('신양주점', '양주점2호점', '파주양주점')) {
    $result = Get-BenefitBusinessBinding -Source (New-TestQualifiedSource -Text "사업장명: 테스트 식당 양주점; 지점: $wrongBranch") -Business $business -CanonicalPhone ''
    Assert-Equal $result.BusinessBindingStatus 'CONFLICT' "Different explicit branch must conflict in binding: $wrongBranch"
    Assert-True ($result.ReasonCodes -contains 'BUSINESS_BINDING_CONFLICT') "Different explicit branch preserves binding conflict reason: $wrongBranch"
}

$phoneStrong = Get-BenefitBusinessBinding -Source (New-TestQualifiedSource -Text '사업장명: 테스트 식당 양주점; 전화: 031-123-4567') -Business $business -CanonicalPhone '031-123-4567'
Assert-Equal $phoneStrong.BusinessBindingStatus 'STRONG' 'Compatible business name plus canonical phone binds strongly'
Assert-True ($phoneStrong.BindingEvidence -contains 'PHONE_MATCH') 'Strong phone binding preserves exact signal'

$unattributedPhone = Get-BenefitBusinessBinding -Source (New-TestQualifiedSource -Text '테스트 식당 양주점 이용안내; 전화: 031-999-9999') -Business $business -CanonicalPhone '031-123-4567'
Assert-Equal $unattributedPhone.BusinessBindingStatus 'AMBIGUOUS' 'Phone mismatch without an explicit business identity must not conflict'

$phoneAbsent = Get-BenefitBusinessBinding -Source (New-TestQualifiedSource -Text '사업장명: 테스트 식당 양주점; 주소: 경기도 양주시 고암동 테스트로 22-25') -Business $business -CanonicalPhone '031-123-4567'
Assert-Equal $phoneAbsent.BusinessBindingStatus 'STRONG' 'Absent source phone must not conflict with an otherwise strong binding'

$explicitNameConflict = Get-BenefitBusinessBinding -Source (New-TestQualifiedSource -Text '사업장명: 다른 식당; 주소: 경기도 양주시 고암동 테스트로 22-25; 안내: 테스트 식당 양주점과 공동 이벤트 진행') -Business $business -CanonicalPhone ''
Assert-Equal $explicitNameConflict.BusinessBindingStatus 'CONFLICT' 'Explicit business name must outrank incidental canonical-name prose'
Assert-True ($explicitNameConflict.ReasonCodes -contains 'BUSINESS_BINDING_CONFLICT') 'Explicit business-name conflict preserves binding conflict reason'

$nameOnly = Get-BenefitBusinessBinding -Source (New-TestQualifiedSource -Text '사업장명: 테스트 식당 양주점') -Business $business -CanonicalPhone ''
Assert-Equal $nameOnly.BusinessBindingStatus 'AMBIGUOUS' 'Name-only source remains ambiguous'
Assert-True ($nameOnly.ReasonCodes -contains 'BUSINESS_BINDING_AMBIGUOUS') 'Name-only binding preserves ambiguity reason'

$plausible = Get-BenefitBusinessBinding -Source (New-TestQualifiedSource -Text '사업장명: 테스트 식당 양주점; 소재지: 경기도 양주시') -Business $business -CanonicalPhone ''
Assert-Equal $plausible.BusinessBindingStatus 'PLAUSIBLE' 'Compatible name plus partial locality is plausible but not strong'

foreach ($conflictCase in @(
    @{ Text='사업장명: 다른 식당; 주소: 경기도 양주시 고암동 테스트로 22-25'; Name='incompatible business identity' },
    @{ Text='사업장명: 테스트 식당 양주점; 지점: 파주점'; Name='wrong explicit branch' },
    @{ Text='사업장명: 테스트 식당 양주점; 주소: 경기도 양주시 고암동 테스트로 99'; Name='wrong building number' },
    @{ Text='사업장명: 테스트 식당 양주점; 주소: 경기도 파주시 금촌동 테스트로 22-25'; Name='incompatible locality' },
    @{ Text='사업장명: 테스트 식당 양주점; 지점: 파주점; 주소: 경기도 양주시 고암동 테스트로 22-25'; Name='hard conflict outranks compatible name and address' }
)) {
    $result = Get-BenefitBusinessBinding -Source (New-TestQualifiedSource -Text $conflictCase.Text) -Business $business -CanonicalPhone ''
    Assert-Equal $result.BusinessBindingStatus 'CONFLICT' "Explicit $($conflictCase.Name) must conflict"
    Assert-True ($result.ReasonCodes -contains 'BUSINESS_BINDING_CONFLICT') "Conflict reason preserved for $($conflictCase.Name)"
}

$roadConflict = Get-BenefitBusinessBinding -Source (New-TestQualifiedSource -Text '사업장명: 테스트 식당 양주점; 지점: 양주점; 주소: 경기도 양주시 고암동 다른로 22-25') -Business $business -CanonicalPhone ''
Assert-Equal $roadConflict.BusinessBindingStatus 'CONFLICT' 'Different explicit road name must conflict despite compatible name and branch'
Assert-True ($roadConflict.BindingEvidence -contains 'ROAD_NAME_CONFLICT') 'Road-name conflict must remain reviewable evidence'

$buildingSubConflict = Get-BenefitBusinessBinding -Source (New-TestQualifiedSource -Text '사업장명: 테스트 식당 양주점; 지점: 양주점; 주소: 경기도 양주시 고암동 테스트로 22-99') -Business $business -CanonicalPhone ''
Assert-Equal $buildingSubConflict.BusinessBindingStatus 'CONFLICT' 'Different explicit building sub-number must conflict despite compatible name and branch'
Assert-True ($buildingSubConflict.BindingEvidence -contains 'BUILDING_SUB_CONFLICT') 'Building-sub conflict must remain reviewable evidence'

$districtBusiness = New-NormalizedBusiness -SourceRowNumber 2 -OriginalName '테스트 식당' -NormalizedName '테스트식당' -BaseName '테스트 식당' -OriginalRoadAddress '서울특별시 강남구 테스트로 22' -PreferredAddress '서울특별시 강남구 테스트로 22' -Province '서울특별시' -District '강남구' -RoadName '테스트로' -BuildingMain '22' -AddressParseStatus 'COMPLETE'
$districtConflict = Get-BenefitBusinessBinding -Source (New-TestQualifiedSource -Text '사업장명: 테스트 식당; 주소: 서울특별시 마포구 테스트로 22') -Business $districtBusiness -CanonicalPhone ''
Assert-Equal $districtConflict.BusinessBindingStatus 'CONFLICT' 'Different explicit district must conflict when both addresses provide a district'
Assert-True ($districtConflict.BindingEvidence -contains 'DISTRICT_CONFLICT') 'District conflict must remain reviewable evidence'

$sourceRowMismatch = New-TestQualifiedSource -Text '사업장명: 테스트 식당 양주점' -SourceRowNumber 3
Assert-Throws { Get-BenefitBusinessBinding -Source $sourceRowMismatch -Business $business -CanonicalPhone '' } 'Binding must fail closed when qualified source and business source rows differ'

# A1.3 scoped binding: the original document remains authoritative, while
# identity is consumed only from the A1.2-selected physical row.
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-location/test-support.ps1')
. (Join-Path $PSScriptRoot 'lib/benefit-evidence/convert-html-source-observation.ps1')
. (Join-Path $PSScriptRoot 'lib/benefit-evidence/find-business-evidence-slice.ps1')
$scopedDocument = New-ScopeTestDocument
$scopedObservation = ConvertTo-BenefitHtmlObservation -Document $scopedDocument
$scopedBusiness = New-ScopeTestBusiness
$scopedLocation = Find-BenefitBusinessEvidence -Observation $scopedObservation -Business $scopedBusiness -CanonicalPhone '02-0000-0012'
$scopedSlice = $scopedLocation.Slices[0]
$scopedCandidate = New-BenefitSourceCandidate -SourceRowNumber 2 -Url $scopedDocument.Url -SourceKind PUBLIC_OFFICIAL -SourceLabel 'fixture' -DiscoveryMethod TEST -ObservedAt '2026-09-24T00:00:00Z'
$scopedQualified = New-QualifiedBenefitSource -Candidate $scopedCandidate -Document $scopedDocument -OfficialityStatus VERIFIED_OFFICIAL -CurrentnessStatus UNKNOWN
$scopedBound = Get-BenefitBusinessBinding -Source $scopedQualified -Business $scopedBusiness -CanonicalPhone '02-0000-0012' -EvidenceSlice $scopedSlice
Assert-Equal $scopedBound.BusinessBindingStatus 'STRONG' 'A located row binds strongly from its observed name and address'
Assert-Throws { Get-BenefitBusinessBinding -Source $scopedQualified -Business $scopedBusiness -EvidenceSlice $null } 'An explicitly supplied null slice must not enable legacy binding'
$forgedSlice = $scopedSlice
$forgedSlice.StructuredFields['Address'] = '서울특별시 마포구 테스트로 99'
Assert-Throws { Get-BenefitBusinessBinding -Source $scopedQualified -Business $scopedBusiness -CanonicalPhone '02-0000-0012' -EvidenceSlice $forgedSlice } 'A forged scoped slice must fail original-document provenance validation'
$buildingDocument = New-ScopeTestDocument -Html '<table><tr><th>업소명</th><th>주소</th><th>전화번호</th></tr><tr><td>테스트가게 A</td><td>서울특별시 마포구 테스트로 99</td><td>02-0000-0012</td></tr></table>'
$buildingObservation = ConvertTo-BenefitHtmlObservation -Document $buildingDocument
$buildingSlice = New-RelevantBenefitEvidenceSlice -Observation $buildingObservation -Unit $buildingObservation.ContentUnits[0]
$buildingCandidate = New-BenefitSourceCandidate -SourceRowNumber 2 -Url $buildingDocument.Url -SourceKind PUBLIC_OFFICIAL -SourceLabel fixture -DiscoveryMethod TEST -ObservedAt '2026-09-24T00:00:00Z'
$buildingQualified = New-QualifiedBenefitSource -Candidate $buildingCandidate -Document $buildingDocument -OfficialityStatus VERIFIED_OFFICIAL -CurrentnessStatus UNKNOWN
Assert-Equal (Get-BenefitBusinessBinding -Source $buildingQualified -Business $scopedBusiness -CanonicalPhone '02-0000-0012' -EvidenceSlice $buildingSlice).BusinessBindingStatus 'CONFLICT' 'Scoped phone agreement cannot override a building conflict'
$branchBusiness = ConvertTo-NormalizedBusiness -Row (New-ScopeTestRow -Name '테스트 식당 (양주점)' -Building '12') -SourceRowNumber 2
$branchDocument = New-ScopeTestDocument -Html '<table><tr><th>사업장명</th><th>주소</th><th>지점명</th></tr><tr><td>테스트 식당 양주점</td><td>서울특별시 마포구 테스트로 12</td><td>신양주점</td></tr></table>'
$branchObservation = ConvertTo-BenefitHtmlObservation -Document $branchDocument
$branchSlice = New-RelevantBenefitEvidenceSlice -Observation $branchObservation -Unit $branchObservation.ContentUnits[0]
$branchCandidate = New-BenefitSourceCandidate -SourceRowNumber 2 -Url $branchDocument.Url -SourceKind PUBLIC_OFFICIAL -SourceLabel fixture -DiscoveryMethod TEST -ObservedAt '2026-09-24T00:00:00Z'
$branchQualified = New-QualifiedBenefitSource -Candidate $branchCandidate -Document $branchDocument -OfficialityStatus VERIFIED_OFFICIAL -CurrentnessStatus UNKNOWN
Assert-Equal (Get-BenefitBusinessBinding -Source $branchQualified -Business $branchBusiness -EvidenceSlice $branchSlice).BusinessBindingStatus 'CONFLICT' 'Scoped explicit branch conflict cannot bind strongly'
$floorBusiness = ConvertTo-NormalizedBusiness -Row (New-ScopeTestRow -Name '층수 가게' -Building '12 2층 201호') -SourceRowNumber 2
$floorDocument = New-ScopeTestDocument -Html '<table><tr><th>업소명</th><th>주소</th></tr><tr><td>층수 가게</td><td>서울특별시 마포구 테스트로 12 3층 301호</td></tr></table>'
$floorObservation = ConvertTo-BenefitHtmlObservation -Document $floorDocument
$floorSlice = New-RelevantBenefitEvidenceSlice -Observation $floorObservation -Unit $floorObservation.ContentUnits[0]
$floorCandidate = New-BenefitSourceCandidate -SourceRowNumber 2 -Url $floorDocument.Url -SourceKind PUBLIC_OFFICIAL -SourceLabel fixture -DiscoveryMethod TEST -ObservedAt '2026-09-24T00:00:00Z'
$floorQualified = New-QualifiedBenefitSource -Candidate $floorCandidate -Document $floorDocument -OfficialityStatus VERIFIED_OFFICIAL -CurrentnessStatus UNKNOWN
Assert-Equal (Get-BenefitBusinessBinding -Source $floorQualified -Business $floorBusiness -EvidenceSlice $floorSlice).BusinessBindingStatus 'CONFLICT' 'Scoped explicit floor and unit conflict cannot bind strongly'
$unknownPhoneSlice = (Find-BenefitBusinessEvidence -Observation $scopedObservation -Business $scopedBusiness -CanonicalPhone '02-0000-0012').Slices[0]
$unknownPhoneResult = Get-BenefitBusinessBinding -Source $scopedQualified -Business $scopedBusiness -CanonicalPhone '전화번호미상' -EvidenceSlice $unknownPhoneSlice
Assert-Equal $unknownPhoneResult.BusinessBindingStatus 'CONFLICT' 'A supplied nonempty canonical phone that cannot match must not silently disable scoped phone conflict'

Write-Host 'Benefit business binding tests passed.'

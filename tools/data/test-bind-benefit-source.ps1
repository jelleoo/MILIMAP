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

$phoneStrong = Get-BenefitBusinessBinding -Source (New-TestQualifiedSource -Text '사업장명: 테스트 식당 양주점; 전화: 031-123-4567') -Business $business -CanonicalPhone '031-123-4567'
Assert-Equal $phoneStrong.BusinessBindingStatus 'STRONG' 'Compatible business name plus canonical phone binds strongly'
Assert-True ($phoneStrong.BindingEvidence -contains 'PHONE_MATCH') 'Strong phone binding preserves exact signal'

$unattributedPhone = Get-BenefitBusinessBinding -Source (New-TestQualifiedSource -Text '테스트 식당 양주점 이용안내; 전화: 031-999-9999') -Business $business -CanonicalPhone '031-123-4567'
Assert-Equal $unattributedPhone.BusinessBindingStatus 'AMBIGUOUS' 'Phone mismatch without an explicit business identity must not conflict'

$phoneAbsent = Get-BenefitBusinessBinding -Source (New-TestQualifiedSource -Text '사업장명: 테스트 식당 양주점; 주소: 경기도 양주시 고암동 테스트로 22-25') -Business $business -CanonicalPhone '031-123-4567'
Assert-Equal $phoneAbsent.BusinessBindingStatus 'STRONG' 'Absent source phone must not conflict with an otherwise strong binding'

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

$sourceRowMismatch = New-TestQualifiedSource -Text '사업장명: 테스트 식당 양주점' -SourceRowNumber 3
Assert-Throws { Get-BenefitBusinessBinding -Source $sourceRowMismatch -Business $business -CanonicalPhone '' } 'Binding must fail closed when qualified source and business source rows differ'

Write-Host 'Benefit business binding tests passed.'

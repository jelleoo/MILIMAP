$ErrorActionPreference = 'Stop'

$contractPath = Join-Path $PSScriptRoot 'lib/benefit-verification-contracts.ps1'
$qualificationPath = Join-Path $PSScriptRoot 'lib/benefit-source/qualify-official-benefit-source.ps1'
. $contractPath
if (Test-Path -LiteralPath $qualificationPath) { . $qualificationPath }

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

function New-TestCandidate {
    param([string]$Url, [string]$SourceKind = 'PUBLIC_OFFICIAL', [int]$SourceRowNumber = 2)
    return New-BenefitSourceCandidate -SourceRowNumber $SourceRowNumber -Url $Url -SourceKind $SourceKind -SourceLabel 'fixture' -DiscoveryMethod 'TEST' -ObservedAt '2026-09-24T00:00:00Z'
}

function New-TestDocument {
    param([string]$Url, [string]$Text = '사업장명: 테스트 식당 양주점', [string]$FetchStatus = 'COMPLETE', [int]$SourceRowNumber = 2)
    return New-BenefitSourceDocument -SourceRowNumber $SourceRowNumber -Url $Url -SourceFormat 'HTML' -FetchStatus $FetchStatus -ContentType 'text/html' -Text $Text -ObservedAt '2026-09-24T00:00:00Z'
}

$business = New-TestBusiness

$goKrCandidate = New-TestCandidate -Url 'https://city.example.go.kr/benefit'
$goKrDocument = New-TestDocument -Url $goKrCandidate.Url
$goKr = Get-QualifiedBenefitSource -Candidate $goKrCandidate -Document $goKrDocument -Business $business
Assert-QualifiedBenefitSource $goKr
Assert-Equal $goKr.OfficialityStatus 'VERIFIED_OFFICIAL' 'Successful exact .go.kr document must be verified official'
Assert-Equal $goKr.CurrentnessStatus 'UNKNOWN' 'Officiality must not assert currentness'

foreach ($lookalike in @('https://city.example.go.kr.evil/benefit', 'https://evilgo.kr/benefit')) {
    $candidate = New-TestCandidate -Url $lookalike
    $result = Get-QualifiedBenefitSource -Candidate $candidate -Document (New-TestDocument -Url $candidate.Url) -Business $business
    Assert-Equal $result.OfficialityStatus 'UNVERIFIED' "Only an exact .go.kr hostname suffix is public official: $lookalike"
    Assert-True ($result.ReasonCodes -contains 'SOURCE_OFFICIALITY_UNRESOLVED') "Unverified public hostname preserves reason: $lookalike"
}

$nonGovernment = New-TestCandidate -Url 'https://public.example.org/benefit'
$nonGovernmentResult = Get-QualifiedBenefitSource -Candidate $nonGovernment -Document (New-TestDocument -Url $nonGovernment.Url) -Business $business
Assert-Equal $nonGovernmentResult.OfficialityStatus 'UNVERIFIED' 'Other public domains remain unresolved without an approved registry'
Assert-True ($nonGovernmentResult.ReasonCodes -contains 'SOURCE_OFFICIALITY_UNRESOLVED') 'Unresolved public domain preserves officiality reason'

$failedGoKr = Get-QualifiedBenefitSource -Candidate $goKrCandidate -Document (New-TestDocument -Url $goKrCandidate.Url -FetchStatus 'FAILED') -Business $business
Assert-Equal $failedGoKr.OfficialityStatus 'UNVERIFIED' 'Failed .go.kr fetch must not verify official hosting'
Assert-True ($failedGoKr.ReasonCodes -contains 'SOURCE_OFFICIALITY_UNRESOLVED') 'Failed document preserves unresolved officiality reason'

$businessCandidate = New-TestCandidate -Url 'https://business.example.com/benefit' -SourceKind 'BUSINESS_WEBSITE'
$nameOnly = Get-QualifiedBenefitSource -Candidate $businessCandidate -Document (New-TestDocument -Url $businessCandidate.Url -Text '사업장명: 테스트 식당 양주점') -Business $business
Assert-Equal $nameOnly.OfficialityStatus 'UNVERIFIED' 'Business name alone cannot verify an official business website'
Assert-True ($nameOnly.ReasonCodes -contains 'SOURCE_OFFICIALITY_UNRESOLVED') 'Name-only website preserves unresolved officiality reason'

$addressVerified = Get-QualifiedBenefitSource -Candidate $businessCandidate -Document (New-TestDocument -Url $businessCandidate.Url -Text '사업장명: 테스트 식당 양주점; 주소: 경기도 양주시 고암동 테스트로 22-25') -Business $business
Assert-Equal $addressVerified.OfficialityStatus 'VERIFIED_OFFICIAL' 'Compatible name plus full address verifies business website'

$branchVerified = Get-QualifiedBenefitSource -Candidate $businessCandidate -Document (New-TestDocument -Url $businessCandidate.Url -Text '사업장명: 테스트 식당 양주점; 지점: 양주점') -Business $business
Assert-Equal $branchVerified.OfficialityStatus 'VERIFIED_OFFICIAL' 'Compatible name plus explicit branch verifies business website'

$phoneUnverified = Get-QualifiedBenefitSource -Candidate $businessCandidate -Document (New-TestDocument -Url $businessCandidate.Url -Text '사업장명: 테스트 식당 양주점; 전화: 031-123-4567') -Business $business
Assert-Equal $phoneUnverified.OfficialityStatus 'UNVERIFIED' 'Unverified phone alone cannot qualify a business website'
Assert-True ($phoneUnverified.ReasonCodes -contains 'SOURCE_OFFICIALITY_UNRESOLVED') 'Phone-only website preserves unresolved officiality reason'

foreach ($qualificationConflict in @(
    @{ Text='사업장명: 테스트 식당 양주점; 주소: 경기도 양주시 고암동 테스트로 22-25; 지점: 파주점'; Name='wrong branch despite matching address' },
    @{ Text='사업장명: 테스트 식당 양주점; 지점: 양주점; 주소: 경기도 양주시 고암동 다른로 99'; Name='incompatible road/building despite matching branch' },
    @{ Text='사업장명: 테스트 식당 양주점; 지점: 양주점; 주소: 경기도 파주시 금촌동 테스트로 22-25'; Name='incompatible locality despite matching branch' }
)) {
    $result = Get-QualifiedBenefitSource -Candidate $businessCandidate -Document (New-TestDocument -Url $businessCandidate.Url -Text $qualificationConflict.Text) -Business $business
    Assert-Equal $result.OfficialityStatus 'REJECTED' "Clear $($qualificationConflict.Name) must reject business website qualification"
    Assert-True ($result.ReasonCodes -contains 'SOURCE_CONFLICT') "Clear $($qualificationConflict.Name) preserves source conflict reason"
}

$identityConflict = Get-QualifiedBenefitSource -Candidate $businessCandidate -Document (New-TestDocument -Url $businessCandidate.Url -Text '사업장명: 다른 식당; 주소: 경기도 양주시 고암동 테스트로 22-25') -Business $business
Assert-True ($identityConflict.OfficialityStatus -ne 'VERIFIED_OFFICIAL') 'Hard business identity conflict cannot verify a business website'

$mismatchedDocument = New-TestDocument -Url $goKrCandidate.Url -SourceRowNumber 3
Assert-Throws { Get-QualifiedBenefitSource -Candidate $goKrCandidate -Document $mismatchedDocument -Business $business } 'Qualification must fail closed when candidate/document source rows differ'

$unrelatedDocument = New-TestDocument -Url 'https://unrelated.example.com/benefit'
Assert-Throws { Get-QualifiedBenefitSource -Candidate $goKrCandidate -Document $unrelatedDocument -Business $business } 'Qualification must fail closed when candidate/document URLs differ'

Write-Host 'Official benefit source qualification tests passed.'

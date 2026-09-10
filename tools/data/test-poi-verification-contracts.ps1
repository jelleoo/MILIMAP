$ErrorActionPreference = 'Stop'

$libraryPath = Join-Path $PSScriptRoot 'lib\poi-verification-contracts.ps1'
. $libraryPath

function Assert-Equal {
    param([AllowNull()]$Actual, [AllowNull()]$Expected, [Parameter(Mandatory)][string]$Message)
    if ($Actual -ne $Expected) { throw "$Message (expected: $Expected, actual: $Actual)" }
}
function Assert-True {
    param([bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw $Message }
}
function Assert-NoThrow {
    param([Parameter(Mandatory)][scriptblock]$Action, [Parameter(Mandatory)][string]$Message)
    try { & $Action } catch { throw "$Message ($($_.Exception.Message))" }
}
function Assert-Throws {
    param([Parameter(Mandatory)][scriptblock]$Action, [Parameter(Mandatory)][string]$Message)
    $threw = $false
    try { & $Action } catch { $threw = $true }
    if (-not $threw) { throw $Message }
}

# Primitives
$definition = Get-PoiVerificationContractDefinition
Assert-Equal $definition.ContractVersion 1 'Contract version must be 1'
Assert-True ($definition.Classification -contains 'GREEN') 'GREEN classification must be defined'
Assert-True ($definition.Provider -contains 'NAVER_API_HUB_LOCAL') 'NAVER provider must be defined'
Assert-NoThrow { Assert-PoiContractTypeAndVersion ([pscustomobject]@{ ContractType='NormalizedBusiness'; ContractVersion=1 }) 'NormalizedBusiness' } 'Supported type/version must pass'
Assert-Throws { Assert-PoiContractTypeAndVersion ([pscustomobject]@{ ContractType='WrongType'; ContractVersion=1 }) 'NormalizedBusiness' } 'Unexpected type must throw'
Assert-Throws { Assert-PoiContractTypeAndVersion ([pscustomobject]@{ ContractType='NormalizedBusiness'; ContractVersion=2 }) 'NormalizedBusiness' } 'Unsupported version must throw'

$validCodes = @(
    @{ Category='AddressParseStatus'; Value='COMPLETE' },
    @{ Category='QueryAttemptStatus'; Value='SUCCESS' },
    @{ Category='DiscoveryStatus'; Value='PARTIAL' },
    @{ Category='EvaluationStatus'; Value='INCOMPLETE' },
    @{ Category='Classification'; Value='YELLOW' },
    @{ Category='Provider'; Value='NAVER_API_HUB_LOCAL' },
    @{ Category='ProductionAction'; Value='NONE' },
    @{ Category='Warning'; Value='BRANCH_UNCERTAIN' },
    @{ Category='Reason'; Value='NO_CANDIDATE' },
    @{ Category='Conflict'; Value='BUILDING_NUMBER_CONFLICT' },
    @{ Category='QueryStrategy'; Value='NAME_FULL_ADDRESS' }
)
foreach ($case in $validCodes) { Assert-NoThrow { Assert-PoiAllowedCode $case.Category $case.Value } "Valid code must pass: $($case.Category)/$($case.Value)" }
Assert-Throws { Assert-PoiAllowedCode 'Classification' 'BLUE' } 'Invalid classification must throw'
Assert-Throws { Assert-PoiAllowedCode 'UnknownCategory' 'ANY' } 'Unknown category must throw'
Assert-NoThrow { Assert-PoiCoordinatePair $null $null } 'Absent coordinate pair must pass'
Assert-NoThrow { Assert-PoiCoordinatePair ([double]37.5665) ([double]126.9780) } 'Valid coordinate pair must pass'
Assert-Throws { Assert-PoiCoordinatePair ([double]37.5665) $null } 'Half coordinate pair must throw'
Assert-Throws { Assert-PoiCoordinatePair '37.5665' '126.9780' } 'Coordinate strings must throw'
Assert-Throws { Assert-PoiCoordinatePair ([double]32.9) ([double]126.9780) } 'Out-of-range latitude must throw'

# Supporting records
$queryAttempt = New-PoiQueryAttempt -StrategyCode 'NAME_FULL_ADDRESS' -Query '테스트 카페 서울 마포구 월드컵북로 1' -QueryOrder 1 -Status 'SUCCESS' -ResultCount 1
Assert-NoThrow { Assert-PoiQueryAttempt $queryAttempt } 'Valid query attempt must pass'
Assert-Throws { Assert-PoiQueryAttempt (New-PoiQueryAttempt -StrategyCode 'NAME_FULL_ADDRESS' -Query 'q' -QueryOrder 0 -Status 'SUCCESS' -ResultCount 1) } 'QueryOrder must be 1-based'
Assert-Throws { Assert-PoiQueryAttempt (New-PoiQueryAttempt -StrategyCode 'NAME_FULL_ADDRESS' -Query 'q' -QueryOrder 1 -Status 'FAILED' -ResultCount 1 -ErrorCode 'HTTP_ERROR') } 'Failed query cannot report results'

$discoveryEvidence = New-PoiDiscoveryEvidence -StrategyCode 'NAME_FULL_ADDRESS' -Query '테스트 카페 서울 마포구 월드컵북로 1' -QueryOrder 1 -ResultPosition 1 -ResultCount 1
Assert-NoThrow { Assert-PoiDiscoveryEvidence $discoveryEvidence } 'Valid discovery evidence must pass'
Assert-Throws { Assert-PoiDiscoveryEvidence (New-PoiDiscoveryEvidence -StrategyCode 'NAME_FULL_ADDRESS' -Query '' -QueryOrder 1 -ResultPosition 1 -ResultCount 1) } 'Discovery evidence query must not be empty'

$matchEvidence = New-PoiMatchEvidence -EvidenceCode 'BUILDING_NUMBER_MATCH' -CandidateKey 'candidate-1' -CanonicalValue '1' -CandidateValue '1' -Matched $true
Assert-NoThrow { Assert-PoiMatchEvidence $matchEvidence } 'Valid match evidence must pass'

# NormalizedBusiness
$business = New-NormalizedBusiness -SourceRowNumber 2 -OriginalName '테스트 카페' -NormalizedName '테스트카페' -OriginalRoadAddress ' 서울특별시 마포구 월드컵북로 1 ' -PreferredAddress '서울특별시 마포구 월드컵북로 1' -Province '서울' -District '마포구' -RoadName '월드컵북로' -BuildingMain '1' -AddressParseStatus 'COMPLETE'
Assert-NoThrow { Assert-NormalizedBusiness $business } 'Valid normalized business must pass'
Assert-Equal $business.OriginalLotAddress '' 'Missing optional text must become empty string'
Assert-True ($business.NormalizationWarnings -is [array]) 'Warnings must always be an array'
Assert-Throws { Assert-NormalizedBusiness (New-NormalizedBusiness -SourceRowNumber 1 -OriginalName 'x' -NormalizedName 'x' -AddressParseStatus 'UNPARSED') } 'Source row must be greater than one'
Assert-Throws { Assert-NormalizedBusiness (New-NormalizedBusiness -SourceRowNumber 2 -OriginalName 'x' -NormalizedName 'x' -OriginalRoadAddress '서울시 A로 1' -PreferredAddress '서울시 A로 999' -AddressParseStatus 'PARTIAL') } 'Synthetic preferred address must throw'

# Candidate
$candidate = New-PoiCandidate -CandidateKey 'candidate-1' -Provider 'NAVER_API_HUB_LOCAL' -OriginalName '테스트 카페' -NormalizedName '테스트카페' -RoadAddress '서울특별시 마포구 월드컵북로 1' -Latitude ([double]37.5665) -Longitude ([double]126.9780) -DiscoveredBy @($discoveryEvidence)
Assert-NoThrow { Assert-PoiCandidate $candidate } 'Valid POI candidate must pass'
Assert-Throws { Assert-PoiCandidate (New-PoiCandidate -CandidateKey '' -Provider 'NAVER_API_HUB_LOCAL' -OriginalName 'x' -NormalizedName 'x' -DiscoveredBy @($discoveryEvidence)) } 'Candidate key must not be empty'
Assert-Throws { Assert-PoiCandidate (New-PoiCandidate -CandidateKey 'c' -Provider 'NAVER_API_HUB_LOCAL' -OriginalName 'x' -NormalizedName 'x' -DiscoveredBy @()) } 'Discovered candidate must retain discovery evidence'

# Discovery batch
$completeBatch = New-PoiDiscoveryBatch -SourceRowNumber 2 -Status 'COMPLETE' -Candidates @($candidate) -QueryAttempts @($queryAttempt)
Assert-NoThrow { Assert-PoiDiscoveryBatch $completeBatch } 'Complete discovery batch must pass'
$emptyCompleteAttempt = New-PoiQueryAttempt -StrategyCode 'NAME_FULL_ADDRESS' -Query '없는 업소 서울' -QueryOrder 1 -Status 'SUCCESS' -ResultCount 0
$emptyComplete = New-PoiDiscoveryBatch -SourceRowNumber 2 -Status 'COMPLETE' -Candidates @() -QueryAttempts @($emptyCompleteAttempt)
Assert-NoThrow { Assert-PoiDiscoveryBatch $emptyComplete } 'Completed zero-result discovery must pass'
$failedAttempt = New-PoiQueryAttempt -StrategyCode 'NAME_FULL_ADDRESS' -Query '테스트' -QueryOrder 1 -Status 'FAILED' -ResultCount 0 -ErrorCode 'HTTP_ERROR'
Assert-Throws { Assert-PoiDiscoveryBatch (New-PoiDiscoveryBatch -SourceRowNumber 2 -Status 'COMPLETE' -Candidates @() -QueryAttempts @($failedAttempt)) } 'Complete batch cannot contain failed attempt'
$failedBatch = New-PoiDiscoveryBatch -SourceRowNumber 2 -Status 'FAILED' -Candidates @() -QueryAttempts @($failedAttempt)
Assert-NoThrow { Assert-PoiDiscoveryBatch $failedBatch } 'Failed discovery batch must remain representable'

# Match result
$green = New-PoiMatchResult -SourceRowNumber 2 -EvaluationStatus 'COMPLETE' -Classification 'GREEN' -SelectedCandidate $candidate -RankedCandidateKeys @('candidate-1') -ReasonCodes @('SINGLE_STRONG_CANDIDATE') -Evidence @($matchEvidence) -EvaluatedCandidateCount 1 -SurvivingCandidateCount 1
Assert-NoThrow { Assert-PoiMatchResult $green } 'Valid GREEN must pass'
Assert-Equal $green.ProductionAction 'NONE' 'Production action must default to NONE'
Assert-Throws { Assert-PoiMatchResult (New-PoiMatchResult -SourceRowNumber 2 -EvaluationStatus 'COMPLETE' -Classification 'GREEN' -SelectedCandidate $null -EvaluatedCandidateCount 0 -SurvivingCandidateCount 0) } 'GREEN requires selected candidate'
Assert-Throws { Assert-PoiMatchResult (New-PoiMatchResult -SourceRowNumber 2 -EvaluationStatus 'INCOMPLETE' -Classification 'GREEN' -SelectedCandidate $candidate -EvaluatedCandidateCount 1 -SurvivingCandidateCount 1) } 'GREEN cannot be incomplete'

$red = New-PoiMatchResult -SourceRowNumber 2 -EvaluationStatus 'COMPLETE' -Classification 'RED' -SelectedCandidate $null -ReasonCodes @('NO_CANDIDATE') -EvaluatedCandidateCount 0 -SurvivingCandidateCount 0
Assert-NoThrow { Assert-PoiMatchResult $red } 'Valid RED must pass'
Assert-Throws { Assert-PoiMatchResult (New-PoiMatchResult -SourceRowNumber 2 -EvaluationStatus 'COMPLETE' -Classification 'RED' -SelectedCandidate $candidate -EvaluatedCandidateCount 1 -SurvivingCandidateCount 0) } 'RED cannot select candidate'
Assert-Throws { Assert-PoiMatchResult (New-PoiMatchResult -SourceRowNumber 2 -EvaluationStatus 'INCOMPLETE' -Classification 'RED' -EvaluatedCandidateCount 0 -SurvivingCandidateCount 0) } 'Incomplete evaluation cannot be RED'

$yellow = New-PoiMatchResult -SourceRowNumber 2 -EvaluationStatus 'INCOMPLETE' -Classification 'YELLOW' -ReasonCodes @('DISCOVERY_FAILED') -EvaluatedCandidateCount 0 -SurvivingCandidateCount 0
Assert-NoThrow { Assert-PoiMatchResult $yellow } 'Incomplete YELLOW must pass'
Assert-Throws { Assert-PoiMatchResult (New-PoiMatchResult -SourceRowNumber 2 -EvaluationStatus 'COMPLETE' -Classification 'YELLOW' -EvaluatedCandidateCount 1 -SurvivingCandidateCount 2) } 'Survivors cannot exceed evaluated candidates'
Assert-Throws { Assert-PoiMatchResult (New-PoiMatchResult -SourceRowNumber 2 -EvaluationStatus 'COMPLETE' -Classification 'YELLOW' -ProductionAction 'WRITE' -EvaluatedCandidateCount 0 -SurvivingCandidateCount 0) } 'Production action other than NONE must throw'

Write-Host 'POI verification contract tests passed.'

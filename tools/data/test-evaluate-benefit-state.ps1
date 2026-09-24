$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/benefit-verification-contracts.ps1')
$evaluationPath = Join-Path $PSScriptRoot 'lib/benefit-verification/evaluate-benefit-state.ps1'
if (Test-Path -LiteralPath $evaluationPath) { . $evaluationPath }

function Assert-Equal { param([AllowNull()]$Actual, [AllowNull()]$Expected, [Parameter(Mandatory)][string]$Message); if ($Actual -cne $Expected) { throw "$Message (expected: $Expected, actual: $Actual)" } }
function Assert-True { param([bool]$Condition, [Parameter(Mandatory)][string]$Message); if (-not $Condition) { throw $Message } }
function New-TestBenefit { New-CanonicalBenefitRecord -SourceRowNumber 2 -BusinessName '테스트 식당' -BenefitDescription '10% 할인' -EligibleTarget '현역 장병' -UsageCondition '상시' -VerificationMethod '군인 신분증 확인' }
function New-TestSource {
    param([string]$Binding='STRONG', [string[]]$ReasonCodes=@(), [string]$Officiality='VERIFIED_OFFICIAL')
    $candidate = New-BenefitSourceCandidate -SourceRowNumber 2 -Url 'https://city.example.go.kr/benefit' -SourceKind 'PUBLIC_OFFICIAL' -SourceLabel 'fixture' -DiscoveryMethod 'TEST' -ObservedAt '2026-09-24T00:00:00Z'
    $document = New-BenefitSourceDocument -SourceRowNumber 2 -Url $candidate.Url -SourceFormat 'HTML' -FetchStatus 'COMPLETE' -ContentType 'text/html' -Text 'fixture' -ObservedAt '2026-09-24T00:00:00Z'
    $qualified = New-QualifiedBenefitSource -Candidate $candidate -Document $document -OfficialityStatus $Officiality -CurrentnessStatus 'UNKNOWN'
    New-BoundBenefitSource -QualifiedSource $qualified -BusinessBindingStatus $Binding -ReasonCodes $ReasonCodes
}
function New-TestClaim {
    param([string]$ClaimType, [string]$Result, [string]$Value='fixture', [string[]]$ReasonCodes=@())
    $validated = New-ValidatedBenefitClaim -ClaimType $ClaimType -Value $Value -ValidationStatus 'VALIDATED' -EvidenceText "근거: $Value" -EvidenceReference 'fixture:1' -SourceUrl 'https://city.example.go.kr/benefit'
    New-BenefitClaimVerification -ClaimType $ClaimType -EvidenceValue $Value -Result $Result -ValidatedClaim $validated -ReasonCodes $ReasonCodes
}

$benefit = New-TestBenefit
$strong = New-TestSource
$complete = [pscustomobject]@{ DiscoveryStatus='COMPLETE'; ExtractionStatus='COMPLETE' }
$existence = New-TestClaim -ClaimType 'BENEFIT_EXISTENCE' -Result 'CONFIRMED' -Value '혜택 제공'
$current = New-TestClaim -ClaimType 'CURRENT_APPLICABILITY' -Result 'CONFIRMED' -Value '현재 적용'
$description = New-TestClaim -ClaimType 'BENEFIT_DESCRIPTION' -Result 'CONFIRMED' -Value '10% 할인'
$target = New-TestClaim -ClaimType 'ELIGIBLE_TARGET' -Result 'CONFIRMED' -Value '현역 장병'
$usage = New-TestClaim -ClaimType 'USAGE_CONDITION' -Result 'CONFIRMED' -Value '상시'
$method = New-TestClaim -ClaimType 'VERIFICATION_METHOD' -Result 'CONFIRMED' -Value '군인 신분증 확인'
$unknownUsage = New-BenefitClaimVerification -ClaimType 'USAGE_CONDITION' -Result 'UNKNOWN' -ReasonCodes @('CLAIM_UNKNOWN')
$unknownMethod = New-BenefitClaimVerification -ClaimType 'VERIFICATION_METHOD' -Result 'UNKNOWN' -ReasonCodes @('CLAIM_UNKNOWN')

$operationalFailure = Invoke-BenefitStateEvaluation -Benefit $benefit -Sources @() -ClaimResults @() -OperationalStatus ([pscustomobject]@{ DiscoveryStatus='FAILED'; ExtractionStatus='FAILED' })
Assert-Equal $operationalFailure.BenefitState 'NEEDS_VERIFICATION' 'Operational failure must never become ended'
Assert-Equal $operationalFailure.ProductionAction 'NONE' 'Operational failure remains shadow only'

$bindingConflict = Invoke-BenefitStateEvaluation -Benefit $benefit -Sources @(New-TestSource -Binding 'CONFLICT' -ReasonCodes @('BUSINESS_BINDING_CONFLICT')) -ClaimResults @($existence, $current) -OperationalStatus $complete
Assert-Equal $bindingConflict.BenefitState 'NEEDS_VERIFICATION' 'Binding conflict must fail closed'
Assert-Equal $bindingConflict.ReviewClass 'RED' 'Binding conflict must be red'
Assert-True ($bindingConflict.ReasonCodes -contains 'BUSINESS_BINDING_CONFLICT') 'Binding conflict reason must be preserved'

$ambiguous = Invoke-BenefitStateEvaluation -Benefit $benefit -Sources @(New-TestSource -Binding 'AMBIGUOUS' -ReasonCodes @('BUSINESS_BINDING_AMBIGUOUS')) -ClaimResults @($existence, $current, $description, $target, $usage, $method) -OperationalStatus $complete
Assert-Equal $ambiguous.BenefitState 'NEEDS_VERIFICATION' 'Ambiguous binding must not become active'
Assert-True ($ambiguous.ReviewClass -ne 'GREEN') 'Ambiguous binding must not be green'

$explicitEnd = New-TestClaim -ClaimType 'CURRENT_APPLICABILITY' -Result 'ENDED' -Value '혜택 종료' -ReasonCodes @('EXPLICIT_DISCONTINUATION')
$ended = Invoke-BenefitStateEvaluation -Benefit $benefit -Sources @($strong) -ClaimResults @($explicitEnd) -OperationalStatus $complete
Assert-Equal $ended.BenefitState 'ENDED' 'Explicit validated ending with strong binding must end'
Assert-Equal $ended.ReviewClass 'GREEN' 'Strong explicit ending can be green fast review'
Assert-Equal $ended.ProductionAction 'NONE' 'Ended result remains shadow only'

$noEnd = Invoke-BenefitStateEvaluation -Benefit $benefit -Sources @($strong) -ClaimResults @() -OperationalStatus ([pscustomobject]@{ DiscoveryStatus='COMPLETE'; ExtractionStatus='FAILED' })
Assert-Equal $noEnd.BenefitState 'NEEDS_VERIFICATION' 'Fetch or extraction failure without explicit ending must not end'

$noCurrent = Invoke-BenefitStateEvaluation -Benefit $benefit -Sources @($strong) -ClaimResults @($existence) -OperationalStatus $complete
Assert-Equal $noCurrent.BenefitState 'NEEDS_VERIFICATION' 'Missing confirmed current applicability must fail closed'
Assert-True ($noCurrent.ReasonCodes -contains 'CURRENTNESS_INSUFFICIENT') 'Missing current applicability must retain currentness reason'

$activeIncomplete = Invoke-BenefitStateEvaluation -Benefit $benefit -Sources @($strong) -ClaimResults @($existence, $current, $description, $target, $unknownUsage, $unknownMethod) -OperationalStatus $complete
Assert-Equal $activeIncomplete.BenefitState 'ACTIVE' 'Confirmed lifecycle with incomplete detail may remain active'
Assert-Equal $activeIncomplete.ReviewClass 'YELLOW' 'Incomplete detail must be yellow'
Assert-True ($activeIncomplete.ReasonCodes -contains 'DETAIL_INCOMPLETE') 'Incomplete detail reason must be present'

$activeComplete = Invoke-BenefitStateEvaluation -Benefit $benefit -Sources @($strong) -ClaimResults @($existence, $current, $description, $target, $usage, $method, (New-BenefitClaimVerification -ClaimType 'VALID_UNTIL' -Result 'UNKNOWN' -ReasonCodes @('CLAIM_UNKNOWN'))) -OperationalStatus $complete
Assert-Equal $activeComplete.BenefitState 'ACTIVE' 'Unknown lifecycle dates alone must not downgrade a complete active result'
Assert-Equal $activeComplete.ReviewClass 'GREEN' 'Complete current detail must be green'

$unverified = Invoke-BenefitStateEvaluation -Benefit $benefit -Sources @(New-TestSource -Officiality 'UNVERIFIED') -ClaimResults @($existence, $current, $description, $target, $usage, $method) -OperationalStatus $complete
Assert-Equal $unverified.BenefitState 'NEEDS_VERIFICATION' 'Unverified source must not produce an active result'
Assert-True ($unverified.ReasonCodes -contains 'SOURCE_OFFICIALITY_UNRESOLVED') 'Unverified source must preserve officiality insufficiency'

$unsupportedNotApplicable = New-BenefitClaimVerification -ClaimType 'USAGE_CONDITION' -Result 'NOT_APPLICABLE'
$unsupportedMethodNotApplicable = New-BenefitClaimVerification -ClaimType 'VERIFICATION_METHOD' -Result 'NOT_APPLICABLE'
$unsupportedNotApplicableEvaluation = Invoke-BenefitStateEvaluation -Benefit $benefit -Sources @($strong) -ClaimResults @($existence, $current, $description, $target, $unsupportedNotApplicable, $unsupportedMethodNotApplicable) -OperationalStatus $complete
Assert-Equal $unsupportedNotApplicableEvaluation.BenefitState 'ACTIVE' 'Unsupported not-applicable detail must not alter lifecycle state'
Assert-Equal $unsupportedNotApplicableEvaluation.ReviewClass 'YELLOW' 'Unsupported not-applicable detail must not qualify for green'
Assert-True ($unsupportedNotApplicableEvaluation.ReasonCodes -contains 'DETAIL_INCOMPLETE') 'Unsupported not-applicable detail must retain incomplete-detail reason'

$changedDescription = New-TestClaim -ClaimType 'BENEFIT_DESCRIPTION' -Result 'CHANGED' -Value '20% 할인' -ReasonCodes @('MATERIAL_CHANGE')
$changedGreen = Invoke-BenefitStateEvaluation -Benefit $benefit -Sources @($strong) -ClaimResults @($existence, $current, $changedDescription, $target, $usage, $method) -OperationalStatus $complete
Assert-Equal $changedGreen.BenefitState 'CHANGED' 'Validated material change must change state'
Assert-Equal $changedGreen.ReviewClass 'GREEN' 'Complete changed detail must be green'
Assert-True ($changedGreen.ReasonCodes -contains 'MATERIAL_CHANGE') 'Material change reason must be present'

$changedYellow = Invoke-BenefitStateEvaluation -Benefit $benefit -Sources @($strong) -ClaimResults @($existence, $current, $changedDescription, $target, $unknownUsage, $unknownMethod) -OperationalStatus $complete
Assert-Equal $changedYellow.BenefitState 'CHANGED' 'Incomplete changed detail must retain changed state'
Assert-Equal $changedYellow.ReviewClass 'YELLOW' 'Incomplete changed detail must be yellow'

$claimConflict = New-TestClaim -ClaimType 'BENEFIT_DESCRIPTION' -Result 'CONFLICT' -Value '20% 할인' -ReasonCodes @('SOURCE_CONFLICT')
$sourceConflict = Invoke-BenefitStateEvaluation -Benefit $benefit -Sources @($strong) -ClaimResults @($claimConflict) -OperationalStatus $complete
Assert-Equal $sourceConflict.BenefitState 'NEEDS_VERIFICATION' 'Unresolved contradictory claims must fail closed'
Assert-Equal $sourceConflict.ReviewClass 'RED' 'Unresolved contradictory claims must be red'
Assert-True ($sourceConflict.ReasonCodes -contains 'SOURCE_CONFLICT') 'Unresolved contradictory claims must preserve source conflict'

# Review regression helpers: explicit source URL provenance.
function New-TestSourceAtUrl {
    param([Parameter(Mandatory)][string]$Url, [string]$Binding='STRONG', [string]$Officiality='VERIFIED_OFFICIAL')
    $candidate = New-BenefitSourceCandidate -SourceRowNumber 2 -Url $Url -SourceKind 'PUBLIC_OFFICIAL' -SourceLabel 'fixture' -DiscoveryMethod 'TEST' -ObservedAt '2026-09-24T00:00:00Z'
    $document = New-BenefitSourceDocument -SourceRowNumber 2 -Url $Url -SourceFormat 'HTML' -FetchStatus 'COMPLETE' -ContentType 'text/html' -Text 'fixture' -ObservedAt '2026-09-24T00:00:00Z'
    $qualified = New-QualifiedBenefitSource -Candidate $candidate -Document $document -OfficialityStatus $Officiality -CurrentnessStatus 'UNKNOWN'
    New-BoundBenefitSource -QualifiedSource $qualified -BusinessBindingStatus $Binding
}
function New-TestClaimAtUrl {
    param([Parameter(Mandatory)][string]$Url, [string]$ClaimType, [string]$Result, [string]$Value='fixture', [string[]]$ReasonCodes=@())
    $validated = New-ValidatedBenefitClaim -ClaimType $ClaimType -Value $Value -ValidationStatus 'VALIDATED' -EvidenceText "근거: $Value" -EvidenceReference 'fixture:provenance' -SourceUrl $Url
    New-BenefitClaimVerification -ClaimType $ClaimType -EvidenceValue $Value -Result $Result -ValidatedClaim $validated -ReasonCodes $ReasonCodes
}

$urlA = 'https://city.example.go.kr/benefit-a'
$urlB = 'https://city.example.go.kr/benefit-b'
$sourceA = New-TestSourceAtUrl -Url $urlA
$sourceB = New-TestSourceAtUrl -Url $urlB

$existenceA = New-TestClaimAtUrl -Url $urlA -ClaimType 'BENEFIT_EXISTENCE' -Result 'CONFIRMED' -Value '혜택 제공'
$currentB = New-TestClaimAtUrl -Url $urlB -ClaimType 'CURRENT_APPLICABILITY' -Result 'CONFIRMED' -Value '현재 적용'
$descriptionA = New-TestClaimAtUrl -Url $urlA -ClaimType 'BENEFIT_DESCRIPTION' -Result 'CONFIRMED' -Value '10% 할인'
$targetA = New-TestClaimAtUrl -Url $urlA -ClaimType 'ELIGIBLE_TARGET' -Result 'CONFIRMED' -Value '현역 장병'
$usageA = New-TestClaimAtUrl -Url $urlA -ClaimType 'USAGE_CONDITION' -Result 'CONFIRMED' -Value '상시'
$methodA = New-TestClaimAtUrl -Url $urlA -ClaimType 'VERIFICATION_METHOD' -Result 'CONFIRMED' -Value '군인 신분증 확인'

$activeProvenanceMismatch = Invoke-BenefitStateEvaluation -Benefit $benefit -Sources @($sourceA) -ClaimResults @($existenceA, $currentB, $descriptionA, $targetA, $usageA, $methodA) -OperationalStatus $complete
Assert-Equal $activeProvenanceMismatch.BenefitState 'NEEDS_VERIFICATION' 'Lifecycle claims from an unmatched source must not produce ACTIVE'
Assert-True ($activeProvenanceMismatch.ReviewClass -ne 'GREEN') 'Lifecycle provenance mismatch must not be green'

$endedFromB = New-TestClaimAtUrl -Url $urlB -ClaimType 'CURRENT_APPLICABILITY' -Result 'ENDED' -Value '혜택 종료' -ReasonCodes @('EXPLICIT_DISCONTINUATION')
$endedProvenanceMismatch = Invoke-BenefitStateEvaluation -Benefit $benefit -Sources @($sourceA) -ClaimResults @($endedFromB) -OperationalStatus $complete
Assert-True ($endedProvenanceMismatch.BenefitState -ne 'ENDED') 'Explicit ending from an unmatched source must not produce ENDED'

$currentA = New-TestClaimAtUrl -Url $urlA -ClaimType 'CURRENT_APPLICABILITY' -Result 'CONFIRMED' -Value '현재 적용'
$changedFromB = New-TestClaimAtUrl -Url $urlB -ClaimType 'BENEFIT_DESCRIPTION' -Result 'CHANGED' -Value '20% 할인' -ReasonCodes @('MATERIAL_CHANGE')
$changedProvenanceMismatch = Invoke-BenefitStateEvaluation -Benefit $benefit -Sources @($sourceA) -ClaimResults @($existenceA, $currentA, $changedFromB, $targetA, $usageA, $methodA) -OperationalStatus $complete
Assert-True ($changedProvenanceMismatch.BenefitState -ne 'CHANGED') 'Material change from an unmatched source must not produce CHANGED'

$descriptionB = New-TestClaimAtUrl -Url $urlB -ClaimType 'BENEFIT_DESCRIPTION' -Result 'CONFIRMED' -Value '10% 할인'
$targetB = New-TestClaimAtUrl -Url $urlB -ClaimType 'ELIGIBLE_TARGET' -Result 'CONFIRMED' -Value '현역 장병'
$usageB = New-TestClaimAtUrl -Url $urlB -ClaimType 'USAGE_CONDITION' -Result 'CONFIRMED' -Value '상시'
$methodB = New-TestClaimAtUrl -Url $urlB -ClaimType 'VERIFICATION_METHOD' -Result 'CONFIRMED' -Value '군인 신분증 확인'
$validComposite = Invoke-BenefitStateEvaluation -Benefit $benefit -Sources @($sourceA, $sourceB) -ClaimResults @($existenceA, $currentA, $descriptionB, $targetB, $usageB, $methodB) -OperationalStatus $complete
Assert-Equal $validComposite.BenefitState 'ACTIVE' 'Claims from multiple matching safe sources may participate together'
Assert-Equal $validComposite.ReviewClass 'GREEN' 'Complete multi-source safe evidence may remain green'

$validityEnd = New-TestClaimAtUrl -Url $urlA -ClaimType 'VALID_UNTIL' -Result 'ENDED' -Value '2026-09-01' -ReasonCodes @('EXPLICIT_VALIDITY_END')
$validityEnded = Invoke-BenefitStateEvaluation -Benefit $benefit -Sources @($sourceA) -ClaimResults @($validityEnd) -OperationalStatus $complete
Assert-Equal $validityEnded.BenefitState 'ENDED' 'Explicit validity end from a matching safe source must end'
Assert-True ($validityEnded.ReasonCodes -contains 'EXPLICIT_VALIDITY_END') 'Explicit validity end reason must be preserved'
Assert-True ($validityEnded.ReasonCodes -notcontains 'EXPLICIT_DISCONTINUATION') 'Validity end must not be rewritten as discontinuation'
Assert-True ($ended.ReasonCodes -contains 'EXPLICIT_DISCONTINUATION') 'Explicit discontinuation reason must remain preserved'

Write-Host 'Benefit state evaluation tests passed.'


$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/history/history-contracts.ps1')
$projectionPath = Join-Path $PSScriptRoot 'lib/history/phase3-review-audit.ps1'
if (Test-Path -LiteralPath $projectionPath) { . $projectionPath }

function Assert-Equal {
    param($Actual,$Expected,[string]$Message)
    if ($Actual -cne $Expected) { throw "$Message (expected: $Expected, actual: $Actual)" }
}

function Assert-Throws {
    param([scriptblock]$Action,[string]$Message)
    $threw = $false
    try { & $Action } catch { $threw = $true }
    if (-not $threw) { throw $Message }
}

$routeCases = @(
    @{ Candidates=@(); Expected='RECORD_ONLY' }
    @{ Candidates=@('BASELINE_ESTABLISHED'); Expected='RECORD_ONLY' }
    @{ Candidates=@('EVIDENCE_CHANGE_ONLY'); Expected='RECORD_ONLY' }
    @{ Candidates=@('LOCATION_CHANGE_SUSPECTED'); Expected='HUMAN_DOMAIN_REVIEW' }
    @{ Candidates=@('LOCATION_ABSENCE_SUSPECTED'); Expected='HUMAN_DOMAIN_REVIEW' }
    @{ Candidates=@('BENEFIT_CHANGE_SUSPECTED'); Expected='HUMAN_DOMAIN_REVIEW' }
    @{ Candidates=@('BENEFIT_ABSENCE_SUSPECTED'); Expected='HUMAN_DOMAIN_REVIEW' }
    @{ Candidates=@('CANONICAL_INPUT_CHANGED'); Expected='AUDIT_VERIFICATION' }
    @{ Candidates=@('PROCESSOR_OUTPUT_CHANGED'); Expected='OPERATIONAL_DIAGNOSTIC' }
    @{ Candidates=@('OPERATIONAL_FAILURE'); Expected='OPERATIONAL_DIAGNOSTIC' }
    @{ Candidates=@('COMPARISON_UNAVAILABLE'); Expected='OPERATIONAL_DIAGNOSTIC' }
)
foreach ($case in $routeCases) {
    Assert-Equal (Get-Phase3ReviewRoute -ChangeCandidates $case.Candidates) $case.Expected "Route for $($case.Candidates -join ',')"
}

$unchanged = @('BENEFIT_ABSENCE_SUSPECTED','BENEFIT_CHANGE_SUSPECTED')
Assert-Equal (Get-Phase3ReviewRoute -ChangeCandidates $unchanged) 'HUMAN_DOMAIN_REVIEW' 'Same-category candidates are accepted'
Assert-Equal ($unchanged -join ',') 'BENEFIT_ABSENCE_SUSPECTED,BENEFIT_CHANGE_SUSPECTED' 'Routing preserves input candidate order'
Assert-Throws { Get-Phase3ReviewRoute -ChangeCandidates @('FUTURE_CANDIDATE') } 'Unknown candidate must fail closed'
Assert-Throws { Get-Phase3ReviewRoute -ChangeCandidates @('baseline_established') } 'Case-changed candidate is not the approved History token'
Assert-Throws { Get-Phase3ReviewRoute -ChangeCandidates @('LOCATION_CHANGE_SUSPECTED','OPERATIONAL_FAILURE') } 'Human and operational candidates must conflict'
Assert-Throws { Get-Phase3ReviewRoute -ChangeCandidates @('EVIDENCE_CHANGE_ONLY','CANONICAL_INPUT_CHANGED') } 'Record-only and audit candidates must conflict'

$businessId = 'biz-0123456789abcdef0123456789abcdef'
$artifact = New-HistoryArtifactReference -Kind 'LOCATION_SEMANTIC_PROJECTION' -ContentHash ('a'*64) -RelativePath 'artifacts/sha256/aa/projection.json'
$observation = New-HistoryObservation -ObservationId 'obs-current' -RunId 'run-current' -BusinessId $businessId -Domain 'LOCATION' -ObservedAt '2026-09-27T10:00:00Z' -OperationalStatus 'COMPLETE' -Comparable $true -InputFingerprint ('1'*64) -EvidenceFingerprint ('2'*64) -SemanticFingerprint ('3'*64) -ExecutionFingerprint ('4'*64) -ArtifactReferences @($artifact) -SemanticResultReference 'artifacts/sha256/aa/projection.json'
$comparison = New-ObservationComparison -ComparisonId 'cmp-current' -RunId 'run-current' -BusinessId $businessId -Domain 'LOCATION' -PreviousObservationId 'obs-previous' -CurrentObservationId 'obs-current' -ComparisonStatus 'COMPLETE' -DeltaDimensions @('EVIDENCE','SEMANTIC') -ChangeCandidates @('LOCATION_CHANGE_SUSPECTED','LOCATION_ABSENCE_SUSPECTED') -ReasonCodes @('LOCATION_DELTA','SOURCE_CHANGED')

$item = New-Phase3ReviewItem -Observation $observation -Comparison $comparison
Assert-Equal $item.ContractType 'Phase3ReviewItem' 'Review item type'
Assert-Equal $item.ContractVersion 1 'Review item version'
Assert-Equal $item.ReviewKey 'cmp-current' 'Comparison-backed review key'
Assert-Equal $item.BusinessId $businessId 'Current business ID'
Assert-Equal $item.Domain 'LOCATION' 'Current domain'
Assert-Equal $item.RunId 'run-current' 'Current run ID'
Assert-Equal $item.ObservedAt '2026-09-27T10:00:00Z' 'Current observed timestamp'
Assert-Equal $item.CurrentObservationId 'obs-current' 'Current observation ID'
Assert-Equal $item.PreviousObservationId 'obs-previous' 'Previous observation ID'
Assert-Equal $item.ComparisonId 'cmp-current' 'Comparison ID'
Assert-Equal $item.ReviewRoute 'HUMAN_DOMAIN_REVIEW' 'Comparison route'
Assert-Equal $item.ComparisonStatus 'COMPLETE' 'Comparison status'
Assert-Equal (@($item.DeltaDimensions) -join ',') 'EVIDENCE,SEMANTIC' 'Delta order preserved'
Assert-Equal (@($item.ChangeCandidates) -join ',') 'LOCATION_CHANGE_SUSPECTED,LOCATION_ABSENCE_SUSPECTED' 'Candidate order preserved'
Assert-Equal (@($item.ReasonCodes) -join ',') 'LOCATION_DELTA,SOURCE_CHANGED' 'Reason order preserved'
Assert-Equal @($item.AuditFlags).Count 0 'Comparison-backed item has no audit flags'
Assert-Equal $item.CurrentOperationalStatus 'COMPLETE' 'Operational status preserved'
Assert-Equal $item.CurrentComparable $true 'Comparability preserved'
Assert-Equal @($item.CurrentNonComparableReasons).Count 0 'Non-comparable reasons preserved'
Assert-Equal $item.SemanticResultReference 'artifacts/sha256/aa/projection.json' 'Semantic reference preserved'
Assert-Equal @($item.ArtifactReferences).Count 1 'Artifact references preserved'
Assert-Equal $item.ArtifactReferences[0].ContentHash ('a'*64) 'Artifact reference content preserved'
Assert-Equal (@($comparison.ChangeCandidates) -join ',') 'LOCATION_CHANGE_SUSPECTED,LOCATION_ABSENCE_SUSPECTED' 'Original candidates unchanged'
Assert-Equal (@($comparison.ReasonCodes) -join ',') 'LOCATION_DELTA,SOURCE_CHANGED' 'Original reasons unchanged'

$missing = New-Phase3ReviewItem -Observation $observation
Assert-Equal $missing.ReviewKey 'obs-current' 'Missing-comparison review key'
Assert-Equal $missing.ReviewRoute 'AUDIT_VERIFICATION' 'Missing-comparison route'
Assert-Equal $missing.PreviousObservationId '' 'No synthetic previous observation'
Assert-Equal $missing.ComparisonId '' 'No synthetic comparison ID'
Assert-Equal $missing.ComparisonStatus '' 'No synthetic comparison status'
Assert-Equal @($missing.DeltaDimensions).Count 0 'No synthetic deltas'
Assert-Equal @($missing.ChangeCandidates).Count 0 'No synthetic candidates'
Assert-Equal @($missing.ReasonCodes).Count 0 'No synthetic reasons'
Assert-Equal (@($missing.AuditFlags) -join ',') 'COMPARISON_NOT_RECORDED' 'Missing-comparison audit flag only'

foreach ($mismatch in @(
    @{ BusinessId='biz-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; Domain='LOCATION'; RunId='run-current'; CurrentObservationId='obs-current' }
    @{ BusinessId=$businessId; Domain='BENEFIT'; RunId='run-current'; CurrentObservationId='obs-current' }
    @{ BusinessId=$businessId; Domain='LOCATION'; RunId='run-other'; CurrentObservationId='obs-current' }
    @{ BusinessId=$businessId; Domain='LOCATION'; RunId='run-current'; CurrentObservationId='obs-other' }
)) {
    $wrong = New-ObservationComparison -ComparisonId 'cmp-wrong' -RunId $mismatch.RunId -BusinessId $mismatch.BusinessId -Domain $mismatch.Domain -PreviousObservationId 'obs-previous' -CurrentObservationId $mismatch.CurrentObservationId -ComparisonStatus 'COMPLETE' -ChangeCandidates @('LOCATION_CHANGE_SUSPECTED')
    Assert-Throws { New-Phase3ReviewItem -Observation $observation -Comparison $wrong } 'Comparison/current identity mismatch must fail'
}

$benefitObservation = New-HistoryObservation -ObservationId 'obs-benefit' -RunId 'run-benefit' -BusinessId $businessId -Domain 'BENEFIT' -ObservedAt '2026-09-27T11:00:00Z' -OperationalStatus 'PARTIAL' -Comparable $false -InputFingerprint ('1'*64) -EvidenceFingerprint ('2'*64) -SemanticFingerprint ('3'*64) -ExecutionFingerprint ('4'*64) -NonComparableReasons @('SOURCE_PARTIAL')
$recordComparison = New-ObservationComparison -ComparisonId 'cmp-record' -RunId 'run-benefit' -BusinessId $businessId -Domain 'BENEFIT' -CurrentObservationId 'obs-benefit' -ComparisonStatus 'COMPLETE' -ChangeCandidates @('BASELINE_ESTABLISHED')
$auditComparison = New-ObservationComparison -ComparisonId 'cmp-audit' -RunId 'run-benefit' -BusinessId $businessId -Domain 'BENEFIT' -CurrentObservationId 'obs-benefit' -ComparisonStatus 'COMPLETE' -ChangeCandidates @('CANONICAL_INPUT_CHANGED')
$operationalComparison = New-ObservationComparison -ComparisonId 'cmp-operational' -RunId 'run-benefit' -BusinessId $businessId -Domain 'BENEFIT' -PreviousObservationId 'obs-previous' -CurrentObservationId 'obs-benefit' -ComparisonStatus 'UNAVAILABLE' -ChangeCandidates @('OPERATIONAL_FAILURE','COMPARISON_UNAVAILABLE') -ReasonCodes @('SOURCE_PARTIAL')

$items = @(
    $item
    (New-Phase3ReviewItem -Observation $benefitObservation -Comparison $recordComparison)
    (New-Phase3ReviewItem -Observation $benefitObservation -Comparison $auditComparison)
    (New-Phase3ReviewItem -Observation $benefitObservation -Comparison $operationalComparison)
    $missing
)
$summary = New-Phase3ReviewAuditSummary -Items $items -CommittedRunCount 3 -CommittedObservationCount 5 -CommittedComparisonCount 4 -IgnoredUncommittedRecordCount 2 -UniqueArtifactReferenceCount 7 -UniqueArtifactsValidated 6
Assert-Equal $summary.CommittedRunCount 3 'Committed run count'
Assert-Equal $summary.CommittedObservationCount 5 'Committed observation count'
Assert-Equal $summary.CommittedComparisonCount 4 'Committed comparison count'
Assert-Equal $summary.ReviewItemCount 5 'Review item count'
Assert-Equal $summary.RecordOnlyCount 1 'Record-only count'
Assert-Equal $summary.HumanDomainReviewCount 1 'Human-review count'
Assert-Equal $summary.AuditVerificationCount 2 'Audit-verification count includes missing comparison'
Assert-Equal $summary.OperationalDiagnosticCount 1 'Operational-diagnostic count'
Assert-Equal $summary.MissingComparisonCount 1 'Missing-comparison count'
Assert-Equal $summary.IgnoredUncommittedRecordCount 2 'Ignored-uncommitted count'
Assert-Equal $summary.UniqueArtifactReferenceCount 7 'Unique reference count'
Assert-Equal $summary.UniqueArtifactsValidated 6 'Unique artifact validation count'
Assert-Equal $summary.LocationItemCount 2 'Location item count'
Assert-Equal $summary.BenefitItemCount 3 'Benefit item count'
Assert-Equal $summary.CandidateCounts.LOCATION_CHANGE_SUSPECTED 1 'First human candidate count'
Assert-Equal $summary.CandidateCounts.LOCATION_ABSENCE_SUSPECTED 1 'Second human candidate count'
Assert-Equal $summary.CandidateCounts.BASELINE_ESTABLISHED 1 'Baseline candidate count'
Assert-Equal $summary.CandidateCounts.CANONICAL_INPUT_CHANGED 1 'Audit candidate count'
Assert-Equal $summary.CandidateCounts.OPERATIONAL_FAILURE 1 'First operational candidate count'
Assert-Equal $summary.CandidateCounts.COMPARISON_UNAVAILABLE 1 'Second operational candidate count'
Assert-Equal $summary.CandidateCounts.Count 6 'Missing-comparison flag is not a History candidate'

Write-Host 'Phase 3 review audit projection tests passed.'

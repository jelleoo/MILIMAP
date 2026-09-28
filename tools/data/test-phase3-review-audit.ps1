$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/history/history-contracts.ps1')
. (Join-Path $PSScriptRoot 'lib/history/history-store.ps1')
$projectionPath = Join-Path $PSScriptRoot 'lib/history/phase3-review-audit.ps1'
if (Test-Path -LiteralPath $projectionPath) { . $projectionPath }
$scannerPath = Join-Path $PSScriptRoot 'invoke-phase3-review-audit.ps1'
if (Test-Path -LiteralPath $scannerPath) { . $scannerPath }

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

function Assert-ThrowsMatching {
    param([scriptblock]$Action,[string]$Pattern,[string]$Message)
    try { & $Action } catch {
        if ($_.Exception.Message -match $Pattern) { return }
        throw "$Message (wrong failure: $($_.Exception.Message))"
    }
    throw "$Message (no failure)"
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

function New-AuditTestStore {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('milimap-phase3-audit-' + [Guid]::NewGuid().ToString('N'))
    return New-HistoryStoreLayout -Root $root
}

function Write-AuditTestJson {
    param([string]$Path,$Value)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $Value | ConvertTo-Json -Depth 20 -Compress | Set-Content -LiteralPath $Path -Encoding utf8 -NoNewline
}

function Write-AuditTestManifest {
    param($Store,[string]$RunId,[string]$Status='COMMITTED')
    $completedAt = if ($Status -ceq 'COMMITTED') { '2026-09-27T10:01:00Z' } else { '' }
    $manifest = New-HistoryRunManifest -RunId $RunId -StartedAt '2026-09-27T10:00:00Z' -CompletedAt $completedAt -RepositoryRevision ('a'*40) -ExecutionStatus 'COMPLETE' -RunCommitStatus $Status -RequestedBusinessIds @($businessId)
    Write-AuditTestJson -Path (Get-HistoryRunManifestPath -Store $Store -RunId $RunId) -Value $manifest
}

function Write-AuditTestObservation {
    param($Store,[string]$Id,[string]$RunId,[string]$Domain='LOCATION',[string]$BusinessId=$businessId,[object[]]$Artifacts=@())
    $value = New-HistoryObservation -ObservationId $Id -RunId $RunId -BusinessId $BusinessId -Domain $Domain -ObservedAt '2026-09-27T10:00:00Z' -OperationalStatus 'COMPLETE' -Comparable $true -InputFingerprint ('1'*64) -EvidenceFingerprint ('2'*64) -SemanticFingerprint ('3'*64) -ExecutionFingerprint ('4'*64) -ArtifactReferences $Artifacts
    Write-AuditTestJson -Path (Join-Path $Store.ObservationsRoot ($Id + '.json')) -Value $value
    return $value
}

function Write-AuditTestComparison {
    param($Store,[string]$Id,[string]$RunId,[string]$CurrentId,[string]$PreviousId='', [string]$Domain='LOCATION',[string]$BusinessId=$businessId)
    $value = New-ObservationComparison -ComparisonId $Id -RunId $RunId -BusinessId $BusinessId -Domain $Domain -CurrentObservationId $CurrentId -PreviousObservationId $PreviousId -ComparisonStatus 'COMPLETE' -ChangeCandidates @('BASELINE_ESTABLISHED')
    Write-AuditTestJson -Path (Join-Path $Store.ComparisonsRoot ($Id + '.json')) -Value $value
    return $value
}

$auditStore = New-AuditTestStore
try {
    Write-AuditTestManifest -Store $auditStore -RunId 'run-committed'
    Write-AuditTestManifest -Store $auditStore -RunId 'run-aborted' -Status 'ABORTED'
    [void](Write-AuditTestObservation -Store $auditStore -Id 'obs-committed' -RunId 'run-committed')
    [void](Write-AuditTestObservation -Store $auditStore -Id 'obs-aborted' -RunId 'run-aborted')
    [void](Write-AuditTestObservation -Store $auditStore -Id 'obs-orphan' -RunId 'run-no-terminal')

    $audit = Invoke-Phase3ReviewAudit -Store $auditStore
    Assert-Equal @($audit.Items).Count 1 'Only COMMITTED observation produces a review item'
    Assert-Equal $audit.Items[0].CurrentObservationId 'obs-committed' 'Committed observation is authoritative'
    Assert-Equal $audit.Summary.CommittedRunCount 1 'Only COMMITTED run counted'
    Assert-Equal $audit.Summary.CommittedObservationCount 1 'Only COMMITTED observation counted'
    Assert-Equal $audit.Summary.IgnoredUncommittedRecordCount 2 'ABORTED and orphan physical records are ignored/countable'

    New-Item -ItemType Directory -Path (Join-Path $auditStore.RunsRoot 'run-missing-manifest') | Out-Null
    Assert-Throws { Invoke-Phase3ReviewAudit -Store $auditStore } 'Run directory without manifest must fail closed'
} finally {
    Remove-Item -LiteralPath $auditStore.Root -Recurse -Force -ErrorAction SilentlyContinue
}

$linkedStore = New-AuditTestStore
try {
    Write-AuditTestManifest -Store $linkedStore -RunId 'run-current'
    Write-AuditTestManifest -Store $linkedStore -RunId 'run-previous'
    [void](Write-AuditTestObservation -Store $linkedStore -Id 'obs-current' -RunId 'run-current')
    [void](Write-AuditTestObservation -Store $linkedStore -Id 'obs-previous' -RunId 'run-previous')
    [void](Write-AuditTestComparison -Store $linkedStore -Id 'cmp-linked' -RunId 'run-current' -CurrentId 'obs-current' -PreviousId 'obs-previous')
    $linkedAudit = Invoke-Phase3ReviewAudit -Store $linkedStore
    $linkedCurrent = @($linkedAudit.Items | Where-Object { $_.CurrentObservationId -ceq 'obs-current' })[0]
    $linkedPrevious = @($linkedAudit.Items | Where-Object { $_.CurrentObservationId -ceq 'obs-previous' })[0]
    Assert-Equal $linkedAudit.Summary.CommittedComparisonCount 1 'Committed comparison counted'
    Assert-Equal $linkedCurrent.ReviewKey 'cmp-linked' 'Committed comparison joins current observation'
    Assert-Equal $linkedCurrent.PreviousObservationId 'obs-previous' 'Previous lineage retained'
    Assert-Equal $linkedPrevious.ReviewRoute 'AUDIT_VERIFICATION' 'Committed observation without comparison is retained'
    Assert-Equal (@($linkedPrevious.AuditFlags) -join ',') 'COMPARISON_NOT_RECORDED' 'No comparison has audit-only flag'
    Assert-Equal $linkedAudit.Summary.MissingComparisonCount 1 'Missing comparison is counted'

    [void](Write-AuditTestComparison -Store $linkedStore -Id 'cmp-duplicate' -RunId 'run-current' -CurrentId 'obs-current')
    Assert-ThrowsMatching { Invoke-Phase3ReviewAudit -Store $linkedStore } 'Duplicate.*comparison' 'Two committed comparisons for one current observation must fail'
} finally {
    Remove-Item -LiteralPath $linkedStore.Root -Recurse -Force -ErrorAction SilentlyContinue
}

$comparisonCases = @(
    @{ Name='current missing'; CurrentId='obs-missing'; PreviousId=''; RunId='run-current'; Domain='LOCATION'; BusinessId=$businessId; Expected='Current observation.*missing' }
    @{ Name='current business mismatch'; CurrentId='obs-current'; PreviousId=''; RunId='run-current'; Domain='LOCATION'; BusinessId='biz-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; Expected='BusinessId.*mismatch' }
    @{ Name='current domain mismatch'; CurrentId='obs-current'; PreviousId=''; RunId='run-current'; Domain='BENEFIT'; BusinessId=$businessId; Expected='Domain.*mismatch' }
    @{ Name='current run mismatch'; CurrentId='obs-current'; PreviousId=''; RunId='run-other'; Domain='LOCATION'; BusinessId=$businessId; Expected='RunId.*mismatch' }
    @{ Name='previous missing'; CurrentId='obs-current'; PreviousId='obs-missing'; RunId='run-current'; Domain='LOCATION'; BusinessId=$businessId; Expected='Previous observation.*missing' }
    @{ Name='previous noncommitted'; CurrentId='obs-current'; PreviousId='obs-aborted'; RunId='run-current'; Domain='LOCATION'; BusinessId=$businessId; Expected='Previous observation.*committed' }
)
foreach ($case in $comparisonCases) {
    $caseStore = New-AuditTestStore
    try {
        Write-AuditTestManifest -Store $caseStore -RunId 'run-current'
        Write-AuditTestManifest -Store $caseStore -RunId 'run-other'
        Write-AuditTestManifest -Store $caseStore -RunId 'run-aborted' -Status 'ABORTED'
        [void](Write-AuditTestObservation -Store $caseStore -Id 'obs-current' -RunId 'run-current')
        [void](Write-AuditTestObservation -Store $caseStore -Id 'obs-aborted' -RunId 'run-aborted')
        [void](Write-AuditTestComparison -Store $caseStore -Id 'cmp-case' -RunId $case.RunId -CurrentId $case.CurrentId -PreviousId $case.PreviousId -Domain $case.Domain -BusinessId $case.BusinessId)
        Assert-ThrowsMatching { Invoke-Phase3ReviewAudit -Store $caseStore } $case.Expected "Comparison $($case.Name) must fail"
    } finally {
        Remove-Item -LiteralPath $caseStore.Root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

foreach ($case in @(
    @{ Name='previous business mismatch'; Domain='LOCATION'; BusinessId='biz-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' }
    @{ Name='previous domain mismatch'; Domain='BENEFIT'; BusinessId=$businessId }
)) {
    $caseStore = New-AuditTestStore
    try {
        Write-AuditTestManifest -Store $caseStore -RunId 'run-current'
        Write-AuditTestManifest -Store $caseStore -RunId 'run-previous'
        [void](Write-AuditTestObservation -Store $caseStore -Id 'obs-current' -RunId 'run-current')
        [void](Write-AuditTestObservation -Store $caseStore -Id 'obs-previous' -RunId 'run-previous' -Domain $case.Domain -BusinessId $case.BusinessId)
        [void](Write-AuditTestComparison -Store $caseStore -Id 'cmp-case' -RunId 'run-current' -CurrentId 'obs-current' -PreviousId 'obs-previous')
        Assert-ThrowsMatching { Invoke-Phase3ReviewAudit -Store $caseStore } 'Previous observation.*mismatch' "Comparison $($case.Name) must fail"
    } finally {
        Remove-Item -LiteralPath $caseStore.Root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$badComparisonStore = New-AuditTestStore
try {
    Write-AuditTestManifest -Store $badComparisonStore -RunId 'run-current'
    [void](Write-AuditTestObservation -Store $badComparisonStore -Id 'obs-current' -RunId 'run-current')
    $badPath = Join-Path $badComparisonStore.ComparisonsRoot 'cmp-bad.json'
    Set-Content -LiteralPath $badPath -Value '{bad-json' -Encoding utf8 -NoNewline
    Assert-ThrowsMatching { Invoke-Phase3ReviewAudit -Store $badComparisonStore } 'Malformed comparison JSON' 'Malformed comparison JSON must fail'
    Remove-Item -LiteralPath $badPath
    $misnamed = Write-AuditTestComparison -Store $badComparisonStore -Id 'cmp-actual' -RunId 'run-current' -CurrentId 'obs-current'
    Move-Item -LiteralPath (Join-Path $badComparisonStore.ComparisonsRoot 'cmp-actual.json') -Destination (Join-Path $badComparisonStore.ComparisonsRoot 'cmp-wrong.json')
    Assert-ThrowsMatching { Invoke-Phase3ReviewAudit -Store $badComparisonStore } 'Comparison filename identity mismatch' 'Comparison filename identity mismatch must fail'
} finally {
    Remove-Item -LiteralPath $badComparisonStore.Root -Recurse -Force -ErrorAction SilentlyContinue
}

$uncommittedStore = New-AuditTestStore
try {
    Write-AuditTestManifest -Store $uncommittedStore -RunId 'run-committed'
    Write-AuditTestManifest -Store $uncommittedStore -RunId 'run-aborted' -Status 'ABORTED'
    [void](Write-AuditTestObservation -Store $uncommittedStore -Id 'obs-current' -RunId 'run-committed')
    [void](Write-AuditTestComparison -Store $uncommittedStore -Id 'cmp-aborted' -RunId 'run-aborted' -CurrentId 'obs-current')
    [void](Write-AuditTestComparison -Store $uncommittedStore -Id 'cmp-orphan' -RunId 'run-orphan' -CurrentId 'obs-current')
    $uncommittedAudit = Invoke-Phase3ReviewAudit -Store $uncommittedStore
    Assert-Equal $uncommittedAudit.Summary.CommittedComparisonCount 0 'Non-COMMITTED comparisons are not authoritative'
    Assert-Equal $uncommittedAudit.Summary.IgnoredUncommittedRecordCount 2 'ABORTED/orphan comparisons increment ignored count'
    Assert-Equal $uncommittedAudit.Items[0].ReviewRoute 'AUDIT_VERIFICATION' 'No comparison is invented from non-COMMITTED records'

    $bad = Join-Path $uncommittedStore.ComparisonsRoot 'cmp-bad.json'
    Set-Content -LiteralPath $bad -Value '{broken' -Encoding utf8 -NoNewline
    Assert-ThrowsMatching { Invoke-Phase3ReviewAudit -Store $uncommittedStore } 'Malformed comparison JSON' 'Malformed ABORTED comparison must fail before filtering'
} finally {
    Remove-Item -LiteralPath $uncommittedStore.Root -Recurse -Force -ErrorAction SilentlyContinue
}

$badObservationStore = New-AuditTestStore
try {
    Write-AuditTestManifest -Store $badObservationStore -RunId 'run-aborted' -Status 'ABORTED'
    $bad = Join-Path $badObservationStore.ObservationsRoot 'obs-bad.json'
    Set-Content -LiteralPath $bad -Value '{broken' -Encoding utf8 -NoNewline
    Assert-ThrowsMatching { Invoke-Phase3ReviewAudit -Store $badObservationStore } 'Malformed observation JSON' 'Malformed ABORTED observation must fail before filtering'
    Remove-Item -LiteralPath $bad
    [void](Write-AuditTestObservation -Store $badObservationStore -Id 'obs-actual' -RunId 'run-aborted')
    Move-Item -LiteralPath (Join-Path $badObservationStore.ObservationsRoot 'obs-actual.json') -Destination (Join-Path $badObservationStore.ObservationsRoot 'obs-wrong.json')
    Assert-ThrowsMatching { Invoke-Phase3ReviewAudit -Store $badObservationStore } 'Observation filename identity mismatch' 'ABORTED observation filename must be checked before filtering'
} finally {
    Remove-Item -LiteralPath $badObservationStore.Root -Recurse -Force -ErrorAction SilentlyContinue
}

$badRunStore = New-AuditTestStore
try {
    $runPath = Join-Path $badRunStore.RunsRoot 'run-current'
    New-Item -ItemType Directory -Path $runPath | Out-Null
    Set-Content -LiteralPath (Join-Path $runPath 'manifest.json') -Value '{broken' -Encoding utf8 -NoNewline
    Assert-ThrowsMatching { Invoke-Phase3ReviewAudit -Store $badRunStore } 'Malformed run manifest JSON' 'Malformed run manifest must fail'
    Write-AuditTestManifest -Store $badRunStore -RunId 'run-current' -Status 'PREPARED'
    Assert-ThrowsMatching { Invoke-Phase3ReviewAudit -Store $badRunStore } 'no terminal manifest' 'PREPARED run directory has no terminal authority'
    $wrongManifest = New-HistoryRunManifest -RunId 'run-other' -StartedAt '2026-09-27T10:00:00Z' -CompletedAt '2026-09-27T10:01:00Z' -RepositoryRevision ('a'*40) -ExecutionStatus 'COMPLETE' -RunCommitStatus 'COMMITTED'
    Write-AuditTestJson -Path (Join-Path $runPath 'manifest.json') -Value $wrongManifest
    Assert-ThrowsMatching { Invoke-Phase3ReviewAudit -Store $badRunStore } 'Run manifest identity mismatch' 'Run directory/manifest identity mismatch must fail'
} finally {
    Remove-Item -LiteralPath $badRunStore.Root -Recurse -Force -ErrorAction SilentlyContinue
}

$artifactStore = New-AuditTestStore
try {
    Write-AuditTestManifest -Store $artifactStore -RunId 'run-current'
    $hashA = Get-HistorySha256 -Text 'audit-artifact-A'
    $hashB = Get-HistorySha256 -Text 'audit-artifact-B'
    $referenceA = Write-HistoryArtifact -Store $artifactStore -ContentHash $hashA -Extension 'txt' -Text 'audit-artifact-A'
    $referenceB = Write-HistoryArtifact -Store $artifactStore -ContentHash $hashB -Extension 'txt' -Text 'audit-artifact-B'
    [void](Write-AuditTestObservation -Store $artifactStore -Id 'obs-a1' -RunId 'run-current' -Artifacts @($referenceA))
    [void](Write-AuditTestObservation -Store $artifactStore -Id 'obs-a2' -RunId 'run-current' -Artifacts @($referenceA))
    [void](Write-AuditTestObservation -Store $artifactStore -Id 'obs-b' -RunId 'run-current' -Artifacts @($referenceB))
    [void](Write-AuditTestObservation -Store $artifactStore -Id 'obs-orphan' -RunId 'run-orphan' -Artifacts @((New-HistoryArtifactReference -Kind 'RAW_SOURCE_PAYLOAD' -ContentHash ('f'*64) -RelativePath 'artifacts/sha256/missing.txt')))

    $script:originalAuditArtifactValidator = ${function:Assert-HistoryArtifactReferenceExists}
    $script:auditPhysicalValidationCount = 0
    function Assert-HistoryArtifactReferenceExists {
        param($Store,$Reference)
        $script:auditPhysicalValidationCount++
        & $script:originalAuditArtifactValidator -Store $Store -Reference $Reference
    }
    try {
        $artifactAudit = Invoke-Phase3ReviewAudit -Store $artifactStore
    } finally {
        Set-Item -Path function:Assert-HistoryArtifactReferenceExists -Value $script:originalAuditArtifactValidator
    }
    Assert-Equal $artifactAudit.Summary.UniqueArtifactReferenceCount 2 'Two distinct authoritative artifact references'
    Assert-Equal $artifactAudit.Summary.UniqueArtifactsValidated 2 'Each distinct artifact physically validated once'
    Assert-Equal $script:auditPhysicalValidationCount 2 'Shared artifact does not cause repeated physical validation'
    Assert-Equal $artifactAudit.Summary.CommittedObservationCount 3 'Orphan artifact is not validated as authoritative'
} finally {
    Remove-Item -LiteralPath $artifactStore.Root -Recurse -Force -ErrorAction SilentlyContinue
}

$artifactFailures = @(
    @{ Name='missing'; Hash=('f'*64); RelativePath='artifacts/sha256/missing.txt'; Expected='does not exist' }
    @{ Name='hash mismatch'; Hash=('f'*64); RelativePath='artifacts/sha256/real.txt'; Expected='hash mismatch' }
    @{ Name='path escape'; Hash=('f'*64); RelativePath='../outside.txt'; Expected='escapes store root' }
)
foreach ($case in $artifactFailures) {
    $caseStore = New-AuditTestStore
    try {
        Write-AuditTestManifest -Store $caseStore -RunId 'run-current'
        if ($case.Name -ceq 'hash mismatch') {
            $realPath = Join-Path $caseStore.Root $case.RelativePath
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $realPath) | Out-Null
            Set-Content -LiteralPath $realPath -Value 'not the claimed hash' -Encoding utf8 -NoNewline
        }
        $badReference = New-HistoryArtifactReference -Kind 'RAW_SOURCE_PAYLOAD' -ContentHash $case.Hash -RelativePath $case.RelativePath
        [void](Write-AuditTestObservation -Store $caseStore -Id 'obs-current' -RunId 'run-current' -Artifacts @($badReference))
        Assert-ThrowsMatching { Invoke-Phase3ReviewAudit -Store $caseStore } $case.Expected "Authoritative artifact $($case.Name) must fail"
    } finally {
        Remove-Item -LiteralPath $caseStore.Root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-AuditTestFileInventory {
    param($Store)
    return @(
        Get-ChildItem -LiteralPath $Store.Root -Recurse -File |
            Sort-Object FullName |
            ForEach-Object { $_.FullName + '|' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    )
}

$readOnlyStore = New-AuditTestStore
try {
    Write-AuditTestManifest -Store $readOnlyStore -RunId 'run-current'
    [void](Write-AuditTestObservation -Store $readOnlyStore -Id 'obs-current' -RunId 'run-current')
    Assert-Equal @(Get-ChildItem -LiteralPath $readOnlyStore.IndexesRoot -File).Count 0 'Audit fixture has empty derived indexes'
    $beforeFiles = @(Get-AuditTestFileInventory -Store $readOnlyStore)

    $script:originalAuditLayout = ${function:New-HistoryStoreLayout}
    $script:originalAuditRebuild = ${function:Rebuild-HistoryIndexes}
    $script:auditRootPasses = @{ Runs=0; Observations=0; Comparisons=0 }
    $script:auditPassStore = $readOnlyStore
    function New-HistoryStoreLayout { throw 'Audit must not create store layout' }
    function Rebuild-HistoryIndexes { throw 'Audit must not rebuild indexes' }
    function Get-ChildItem {
        param([string]$LiteralPath,[switch]$Directory,[switch]$File,[string]$Filter)
        if ($LiteralPath -ceq $script:auditPassStore.RunsRoot) { $script:auditRootPasses.Runs++ }
        if ($LiteralPath -ceq $script:auditPassStore.ObservationsRoot) { $script:auditRootPasses.Observations++ }
        if ($LiteralPath -ceq $script:auditPassStore.ComparisonsRoot) { $script:auditRootPasses.Comparisons++ }
        Microsoft.PowerShell.Management\Get-ChildItem @PSBoundParameters
    }
    try {
        $readOnlyAudit = Invoke-Phase3ReviewAudit -Store $readOnlyStore
    } finally {
        Set-Item -Path function:New-HistoryStoreLayout -Value $script:originalAuditLayout
        Set-Item -Path function:Rebuild-HistoryIndexes -Value $script:originalAuditRebuild
        Remove-Item -Path function:Get-ChildItem
    }
    Assert-Equal $readOnlyAudit.Summary.ReviewItemCount 1 'Empty indexes do not block audit'
    Assert-Equal $script:auditRootPasses.Runs 1 'Run inventory has one directory pass'
    Assert-Equal $script:auditRootPasses.Observations 1 'Observation inventory has one file pass'
    Assert-Equal $script:auditRootPasses.Comparisons 1 'Comparison inventory has one file pass'
    $afterFiles = @(Get-AuditTestFileInventory -Store $readOnlyStore)
    Assert-Equal ($afterFiles -join "`n") ($beforeFiles -join "`n") 'Audit leaves file inventory/content unchanged'
} finally {
    Remove-Item -LiteralPath $readOnlyStore.Root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'Phase 3 review audit tests passed.'

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/history/history-contracts.ps1')
. (Join-Path $PSScriptRoot 'lib/history/history-fingerprints.ps1')
. (Join-Path $PSScriptRoot 'lib/history/compare-history-observations.ps1')

function Assert-Equal { param($Actual,$Expected,[string]$Message); if($Actual -cne $Expected){throw "$Message (expected: $Expected, actual: $Actual)"} }
function Assert-True { param([bool]$Condition,[string]$Message); if(-not $Condition){throw $Message} }

function New-TestObservation {
    param(
        [string]$ObservationId,
        [string]$OperationalStatus='COMPLETE',
        [bool]$Comparable=$true,
        [string]$Input='1',
        [string]$Evidence='2',
        [string]$Semantic='3',
        [string]$Execution='4'
    )
    New-HistoryObservation -ObservationId $ObservationId -RunId 'run-test' -BusinessId 'biz-0123456789abcdef0123456789abcdef' -Domain 'BENEFIT' -ObservedAt '2026-09-26T00:00:00Z' -OperationalStatus $OperationalStatus -Comparable $Comparable -InputFingerprint ($Input*64) -EvidenceFingerprint ($Evidence*64) -SemanticFingerprint ($Semantic*64) -ExecutionFingerprint ($Execution*64)
}

$current = New-TestObservation -ObservationId 'obs-current'
$called = 0
$resolver = {
    param($Previous,$Current)
    $script:called++
    [pscustomobject]@{
        ChangeCandidates=@('BENEFIT_CHANGE_SUSPECTED')
        ReasonCodes=@('SEMANTIC_BENEFIT_DELTA')
    }
}

$baseline = Compare-HistoryObservations -Previous $null -Current $current -DomainChangeResolver $resolver
Assert-Equal $baseline.ChangeCandidates[0] 'BASELINE_ESTABLISHED' 'No previous observation must establish baseline'
Assert-Equal $called 0 'Baseline must not call domain resolver'

$failed = New-TestObservation -ObservationId 'obs-failed' -OperationalStatus 'FAILED' -Comparable $false
$failure = Compare-HistoryObservations -Previous $current -Current $failed -DomainChangeResolver $resolver
Assert-True (@($failure.ChangeCandidates) -contains 'OPERATIONAL_FAILURE') 'FAILED current observation must emit OPERATIONAL_FAILURE'
Assert-True (@($failure.ChangeCandidates) -contains 'COMPARISON_UNAVAILABLE') 'FAILED current observation must emit COMPARISON_UNAVAILABLE'
Assert-Equal $failure.ComparisonStatus 'UNAVAILABLE' 'Operational failure must make comparison unavailable'
Assert-Equal $called 0 'Operational failure must not call domain resolver'

$inputChanged = New-TestObservation -ObservationId 'obs-input' -Input 'a' -Semantic 'b'
$inputComparison = Compare-HistoryObservations -Previous $current -Current $inputChanged -DomainChangeResolver $resolver
Assert-Equal $inputComparison.ChangeCandidates[0] 'CANONICAL_INPUT_CHANGED' 'Input delta must take precedence over semantic/domain change'
Assert-Equal $called 0 'Input change must not call domain resolver'

$executionChanged = New-TestObservation -ObservationId 'obs-exec' -Execution 'a' -Semantic 'b'
$executionComparison = Compare-HistoryObservations -Previous $current -Current $executionChanged -DomainChangeResolver $resolver
Assert-Equal $executionComparison.ChangeCandidates[0] 'PROCESSOR_OUTPUT_CHANGED' 'Execution delta must take precedence over domain change'
Assert-Equal $called 0 'Execution change must not call domain resolver'

$evidenceOnly = New-TestObservation -ObservationId 'obs-evidence' -Evidence 'a'
$evidenceComparison = Compare-HistoryObservations -Previous $current -Current $evidenceOnly -DomainChangeResolver $resolver
Assert-Equal $evidenceComparison.ChangeCandidates[0] 'EVIDENCE_CHANGE_ONLY' 'Evidence-only delta must remain audit-only'
Assert-Equal $called 0 'Evidence-only delta with same semantics must not call domain resolver'

$semantic = New-TestObservation -ObservationId 'obs-semantic' -Evidence 'a' -Semantic 'a'
$domainComparison = Compare-HistoryObservations -Previous $current -Current $semantic -DomainChangeResolver $resolver
Assert-Equal $domainComparison.ChangeCandidates[0] 'BENEFIT_CHANGE_SUSPECTED' 'Comparable semantic delta may call domain resolver'
Assert-Equal $called 1 'Domain resolver must be called exactly once for eligible semantic delta'
Assert-True (@($domainComparison.DeltaDimensions) -contains 'EVIDENCE') 'Domain comparison preserves evidence delta'
Assert-True (@($domainComparison.DeltaDimensions) -contains 'SEMANTIC') 'Domain comparison preserves semantic delta'

$unchanged = New-TestObservation -ObservationId 'obs-unchanged'
$unchangedComparison = Compare-HistoryObservations -Previous $current -Current $unchanged -DomainChangeResolver $resolver
Assert-Equal @($unchangedComparison.ChangeCandidates).Count 0 'Unchanged observations must emit no change candidate'
Assert-Equal $called 1 'Unchanged observations must not call domain resolver'

Write-Host 'History comparison precedence tests passed.'

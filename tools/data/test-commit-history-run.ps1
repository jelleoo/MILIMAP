$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/history/history-contracts.ps1')
. (Join-Path $PSScriptRoot 'lib/history/history-fingerprints.ps1')
. (Join-Path $PSScriptRoot 'lib/history/history-store.ps1')
. (Join-Path $PSScriptRoot 'lib/history/commit-history-run.ps1')

function Assert-True { param([bool]$Condition,[string]$Message); if(-not $Condition){throw $Message} }
function Assert-Equal { param($Actual,$Expected,[string]$Message); if($Actual -ne $Expected){throw "$Message (expected: $Expected, actual: $Actual)"} }
function Assert-Throws { param([scriptblock]$Action,[string]$Message); $threw=$false; try{& $Action}catch{$threw=$true}; if(-not $threw){throw $Message} }

$businessId='biz-0123456789abcdef0123456789abcdef'

function New-TestObservation {
    param([string]$Id,[string]$RunId,[string]$ObservedAt,[bool]$Comparable=$true,[string]$Status='COMPLETE')
    New-HistoryObservation -ObservationId $Id -RunId $RunId -BusinessId $businessId -Domain 'BENEFIT' -ObservedAt $ObservedAt -OperationalStatus $Status -Comparable $Comparable -InputFingerprint ('1'*64) -EvidenceFingerprint ('2'*64) -SemanticFingerprint ('3'*64) -ExecutionFingerprint ('4'*64)
}

function New-TestManifest {
    param([string]$RunId)
    New-HistoryRunManifest -RunId $RunId -StartedAt '2026-09-26T00:00:00Z' -CompletedAt '' -RepositoryRevision ('a'*40) -HistoryContractVersion 1 -FingerprintSchemaVersion 1 -RequestedBusinessIds @($businessId) -CompletedBusinessIds @($businessId) -FailedBusinessIds @() -ExecutionStatus 'COMPLETE' -RunCommitStatus 'PREPARED'
}

function Prepare-One {
    param($Store,[string]$RunId,[string]$ObservationId,[string]$ObservedAt='2026-09-26T00:01:00Z')
    $obs=New-TestObservation -Id $ObservationId -RunId $RunId -ObservedAt $ObservedAt
    Prepare-HistoryRun -Store $Store -RunManifest (New-TestManifest -RunId $RunId) -Artifacts @() -Observations @($obs) -Comparisons @()
}

function Get-Key { return ($businessId + '|BENEFIT') }

$root = Join-Path ([IO.Path]::GetTempPath()) ('milimap-history-commit-' + [Guid]::NewGuid().ToString('N'))
try {
    $store=New-HistoryStoreLayout -Root $root

    $runA=New-HistoryRunId
    Assert-True ($runA -cmatch '^run-[0-9a-f]{32}$') 'Run IDs must be opaque lowercase GUID tokens'
    $preparedA=Prepare-One -Store $store -RunId $runA -ObservationId 'obs-0010'
    $resultA=Commit-HistoryRun -Store $store -PreparedRun $preparedA -ExpectedBaselines @{ (Get-Key)='' }
    Assert-Equal $resultA.Code 'COMMITTED' 'Initial run must commit'
    Assert-Equal $resultA.RetryRequired $false 'Successful commit must not request retry'
    $latestA=Get-HistoryLatestEntry -Store $store -BusinessId $businessId -Domain 'BENEFIT' -ComparableOnly
    Assert-Equal $latestA.LatestComparableObservationId 'obs-0010' 'Initial comparable baseline must be indexed'

    Assert-Throws {
        Prepare-One -Store $store -RunId $runA -ObservationId 'obs-reuse-runid' -ObservedAt '2026-09-26T00:01:30Z'
    } 'Committed RunId must be immutable and cannot be prepared again'

    Assert-Throws {
        Prepare-One -Store $store -RunId $runA -ObservationId 'obs-runid-reuse' -ObservedAt '2026-09-26T00:01:30Z'
    } 'A committed RunId must never be reused'

    $missingHash=Get-HistorySha256 -Text 'missing-artifact'
    $missingRef=New-HistoryArtifactReference -Kind 'RAW_SOURCE_PAYLOAD' -ContentHash $missingHash -RelativePath ('artifacts/sha256/' + $missingHash + '.html')
    $badArtifactRun=New-HistoryRunId
    $badArtifactObs=New-HistoryObservation -ObservationId 'obs-missing-artifact' -RunId $badArtifactRun -BusinessId $businessId -Domain 'BENEFIT' -ObservedAt '2026-09-26T00:01:40Z' -OperationalStatus 'COMPLETE' -Comparable $true -InputFingerprint ('1'*64) -EvidenceFingerprint ('2'*64) -SemanticFingerprint ('3'*64) -ExecutionFingerprint ('4'*64) -ArtifactReferences @($missingRef)
    Assert-Throws {
        Prepare-HistoryRun -Store $store -RunManifest (New-TestManifest -RunId $badArtifactRun) -Artifacts @() -Observations @($badArtifactObs) -Comparisons @()
    } 'Prepared observations may not reference missing/unprepared artifacts'

    $badComparisonRun=New-HistoryRunId
    $badCurrent=New-TestObservation -Id 'obs-comparison-current' -RunId $badComparisonRun -ObservedAt '2026-09-26T00:01:45Z'
    $badComparison=New-ObservationComparison -ComparisonId 'cmp-missing-current' -RunId $badComparisonRun -BusinessId $businessId -Domain 'BENEFIT' -PreviousObservationId 'obs-0010' -CurrentObservationId 'obs-not-prepared' -ComparisonStatus 'COMPLETE' -DeltaDimensions @('SEMANTIC') -ComparatorVersion 1 -ChangeCandidates @('BENEFIT_CHANGE_SUSPECTED') -ReasonCodes @()
    Assert-Throws {
        Prepare-HistoryRun -Store $store -RunManifest (New-TestManifest -RunId $badComparisonRun) -Artifacts @() -Observations @($badCurrent) -Comparisons @($badComparison)
    } 'Comparison current observation must be part of the same prepared run'

    $badPreviousRun=New-HistoryRunId
    $badPreviousCurrent=New-TestObservation -Id 'obs-comparison-current-2' -RunId $badPreviousRun -ObservedAt '2026-09-26T00:01:46Z'
    $badPreviousComparison=New-ObservationComparison -ComparisonId 'cmp-missing-previous' -RunId $badPreviousRun -BusinessId $businessId -Domain 'BENEFIT' -PreviousObservationId 'obs-never-committed' -CurrentObservationId 'obs-comparison-current-2' -ComparisonStatus 'COMPLETE' -DeltaDimensions @('SEMANTIC') -ComparatorVersion 1 -ChangeCandidates @('BENEFIT_CHANGE_SUSPECTED') -ReasonCodes @()
    Assert-Throws {
        Prepare-HistoryRun -Store $store -RunManifest (New-TestManifest -RunId $badPreviousRun) -Artifacts @() -Observations @($badPreviousCurrent) -Comparisons @($badPreviousComparison)
    } 'Comparison previous observation must exist in committed history'

    $runB=New-HistoryRunId
    $preparedB=Prepare-One -Store $store -RunId $runB -ObservationId 'obs-0011' -ObservedAt '2026-09-26T00:02:00Z'
    $resultB=Commit-HistoryRun -Store $store -PreparedRun $preparedB -ExpectedBaselines @{ (Get-Key)='obs-0010' }
    Assert-Equal $resultB.Code 'COMMITTED' 'Second run with current baseline must commit'

    $runStale=New-HistoryRunId
    $preparedStale=Prepare-One -Store $store -RunId $runStale -ObservationId 'obs-0012' -ObservedAt '2026-09-26T00:03:00Z'
    $stale=Commit-HistoryRun -Store $store -PreparedRun $preparedStale -ExpectedBaselines @{ (Get-Key)='obs-0010' }
    Assert-Equal $stale.Code 'BASELINE_MOVED' 'Stale expected baseline must fail closed'
    Assert-Equal $stale.RetryRequired $true 'Stale baseline must require explicit caller retry'
    Assert-Equal (Get-HistoryLatestEntry -Store $store -BusinessId $businessId -Domain 'BENEFIT' -ComparableOnly).LatestComparableObservationId 'obs-0011' 'Stale writer must not advance baseline'

    $duplicateRun=New-HistoryRunId
    $duplicateObs1=New-TestObservation -Id 'obs-dupe-a' -RunId $duplicateRun -ObservedAt '2026-09-26T00:04:00Z'
    $duplicateObs2=New-TestObservation -Id 'obs-dupe-b' -RunId $duplicateRun -ObservedAt '2026-09-26T00:04:01Z'
    Assert-Throws {
        Prepare-HistoryRun -Store $store -RunManifest (New-TestManifest -RunId $duplicateRun) -Artifacts @() -Observations @($duplicateObs1,$duplicateObs2) -Comparisons @()
    } 'One run must reject duplicate businessId+domain observations'

    $heldLock=[IO.File]::Open((Join-Path $store.Root '.writer-lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try {
        $lockRun=New-HistoryRunId
        $lockPrepared=Prepare-One -Store $store -RunId $lockRun -ObservationId 'obs-lock' -ObservedAt '2026-09-26T00:05:00Z'
        $locked=Commit-HistoryRun -Store $store -PreparedRun $lockPrepared -ExpectedBaselines @{ (Get-Key)='obs-0011' }
        Assert-Equal $locked.Code 'WRITER_LOCKED' 'Second writer must fail fast while exclusive lock is held'
    } finally {
        $heldLock.Dispose()
    }

    foreach($checkpoint in @('AFTER_ARTIFACTS','AFTER_OBSERVATIONS','BEFORE_MANIFEST_COMMIT')){
        $faultRun=New-HistoryRunId
        $faultObsId='obs-fault-' + $checkpoint.ToLowerInvariant().Replace('_','-')
        $faultPrepared=Prepare-One -Store $store -RunId $faultRun -ObservationId $faultObsId -ObservedAt '2026-09-26T00:06:00Z'
        $fault={
            param($Name)
            if($Name -ceq $checkpoint){ throw ('fault:' + $Name) }
        }.GetNewClosure()
        $failedCommit=Commit-HistoryRun -Store $store -PreparedRun $faultPrepared -ExpectedBaselines @{ (Get-Key)='obs-0011' } -FaultInjector $fault
        Assert-Equal $failedCommit.Code 'ABORTED' "$checkpoint fault before manifest commit must abort"
        $stillLatest=Get-HistoryLatestEntry -Store $store -BusinessId $businessId -Domain 'BENEFIT' -ComparableOnly
        Assert-Equal $stillLatest.LatestComparableObservationId 'obs-0011' "$checkpoint fault must not advance comparable baseline"
    }

    $postCommitRun=New-HistoryRunId
    $postCommitPrepared=Prepare-One -Store $store -RunId $postCommitRun -ObservationId 'obs-post-commit' -ObservedAt '2026-09-26T00:07:00Z'
    $postFault={
        param($Name)
        if($Name -ceq 'AFTER_MANIFEST_COMMIT'){ throw 'fault after manifest commit' }
    }
    $postResult=Commit-HistoryRun -Store $store -PreparedRun $postCommitPrepared -ExpectedBaselines @{ (Get-Key)='obs-0011' } -FaultInjector $postFault
    Assert-Equal $postResult.Code 'COMMITTED' 'Fault after manifest commit must not downgrade committed history'
    Assert-Equal $postResult.IndexRepairRequired $true 'Post-commit fault must require index repair'

    $staleIndex=Get-HistoryLatestEntry -Store $store -BusinessId $businessId -Domain 'BENEFIT' -ComparableOnly
    Assert-Equal $staleIndex.LatestComparableObservationId 'obs-0011' 'Index may remain stale immediately after post-commit crash'
    [void](Rebuild-HistoryIndexes -Store $store)
    $repaired=Get-HistoryLatestEntry -Store $store -BusinessId $businessId -Domain 'BENEFIT' -ComparableOnly
    Assert-Equal $repaired.LatestComparableObservationId 'obs-post-commit' 'Rebuild must recover committed observation after index-update crash'

    $repairRun=New-HistoryRunId
    $repairPrepared=Prepare-One -Store $store -RunId $repairRun -ObservationId 'obs-after-repair' -ObservedAt '2026-09-26T00:08:00Z'
    Remove-Item -LiteralPath (Get-HistoryIndexPath -Store $store -BusinessId $businessId -Domain 'BENEFIT') -Force
    $repairCommit=Commit-HistoryRun -Store $store -PreparedRun $repairPrepared -ExpectedBaselines @{ (Get-Key)='obs-post-commit' }
    Assert-Equal $repairCommit.Code 'COMMITTED' 'Missing index must rebuild on cold recovery path before CAS'
    Assert-Equal (Get-HistoryLatestEntry -Store $store -BusinessId $businessId -Domain 'BENEFIT' -ComparableOnly).LatestComparableObservationId 'obs-after-repair' 'Recovered commit must advance baseline'

    $badExpectedRun=New-HistoryRunId
    $badExpectedPrepared=Prepare-One -Store $store -RunId $badExpectedRun -ObservationId 'obs-missing-cas' -ObservedAt '2026-09-26T00:09:00Z'
    Assert-Throws {
        Commit-HistoryRun -Store $store -PreparedRun $badExpectedPrepared -ExpectedBaselines @{}
    } 'Every observation must have an explicit expected baseline key'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'History staged commit tests passed.'

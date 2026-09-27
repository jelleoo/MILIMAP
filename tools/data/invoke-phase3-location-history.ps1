Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$dataLibRoot=Join-Path $PSScriptRoot 'lib'
$historyRoot=Join-Path $dataLibRoot 'history'
. (Join-Path $dataLibRoot 'identity/canonical-business-id.ps1')
. (Join-Path $dataLibRoot 'identity/normalize-business.ps1')
. (Join-Path $dataLibRoot 'poi-discovery/discover-poi-candidates.ps1')
. (Join-Path $dataLibRoot 'poi-matching/evaluate-poi-match.ps1')
. (Join-Path $historyRoot 'location-incremental-reuse.ps1')
. (Join-Path $historyRoot 'compare-location-history.ps1')
. (Join-Path $historyRoot 'commit-history-run.ps1')

function Invoke-LocationIncrementalPostDiscovery {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$ObservedAt,
        [Parameter(Mandatory)][string]$RepositoryRevision,
        [Parameter(Mandatory)][string]$BusinessId,
        [Parameter(Mandatory)]$Business,
        [Parameter(Mandatory)]$DiscoveryBatch,
        [Parameter(Mandatory)]$BaselineResolution,
        [Parameter(Mandatory)][bool]$RepositoryClean,
        [Parameter(Mandatory)]$ExecutionConfiguration
    )

    $checkpoint=New-LocationIncrementalCheckpoint -BusinessId $BusinessId -Business $Business -DiscoveryBatch $DiscoveryBatch -RepositoryRevision $RepositoryRevision -ExecutionConfiguration $ExecutionConfiguration
    $decision=Get-LocationIncrementalReuseDecision -BaselineResolution $BaselineResolution -Checkpoint $checkpoint -RepositoryClean $RepositoryClean
    $result=$null
    $matcherCount=0
    if([bool]$decision.ReuseApplied) {
        $package=New-LocationIncrementalReusePackage -Store $Store -RunId $RunId -ObservedAt $ObservedAt -Checkpoint $checkpoint -BaselineResolution $BaselineResolution -Decision $decision
    } else {
        $result=Invoke-PoiMatchEvaluation -Business $Business -DiscoveryBatch $DiscoveryBatch
        $matcherCount=1
        $package=New-LocationHistoryObservationPackage -Store $Store -RunId $RunId -BusinessId $BusinessId -ObservedAt $ObservedAt -RepositoryRevision $RepositoryRevision -Business $Business -DiscoveryBatch $DiscoveryBatch -Result $result -ExecutionConfiguration $ExecutionConfiguration
        if([string]$package.Observation.InputFingerprint -cne [string]$checkpoint.InputFingerprint -or
           [string]$package.Observation.EvidenceFingerprint -cne [string]$checkpoint.EvidenceFingerprint -or
           [string]$package.Observation.ExecutionFingerprint -cne [string]$checkpoint.ExecutionFingerprint) {
            throw 'P3-5 recompute package fingerprints do not match pre-match checkpoint'
        }
    }

    $comparison=$null
    if([string]$BaselineResolution.Status -cne 'ARTIFACT_INVALID') {
        $previous=if([string]$BaselineResolution.Status -ceq 'VALID'){$BaselineResolution.Observation}else{$null}
        if([bool]$decision.ReuseApplied) {
            $comparison=Compare-LocationHistoryObservations -Store $Store -Previous $previous -Current $package.Observation
        } else {
            $comparison=Compare-LocationHistoryObservations -Store $Store -Previous $previous -Current $package.Observation -StagedCurrentSemanticProjection $package.SemanticProjection
        }
    }
    $operationalStatus=[string]$package.Observation.OperationalStatus
    $completedIds=@()
    $failedIds=@()
    if($operationalStatus -ceq 'FAILED'){$failedIds=@($BusinessId)}else{$completedIds=@($BusinessId)}
    $manifest=New-HistoryRunManifest -RunId $RunId -StartedAt $ObservedAt -RepositoryRevision $RepositoryRevision -RequestedBusinessIds @($BusinessId) -CompletedBusinessIds $completedIds -FailedBusinessIds $failedIds -ExecutionStatus $operationalStatus -RunCommitStatus 'PREPARED'
    $comparisons=@()
    if($null -ne $comparison){$comparisons=@($comparison)}
    $prepared=Prepare-HistoryRun -Store $Store -RunManifest $manifest -Artifacts @($package.PreparedArtifacts) -Observations @($package.Observation) -Comparisons $comparisons
    $expected=@{}
    $expected[$BusinessId+'|LOCATION']=[string]$BaselineResolution.ExpectedBaselineObservationId
    $commit=Commit-HistoryRun -Store $Store -PreparedRun $prepared -ExpectedBaselines $expected

    $baselineHit= -not [string]::IsNullOrEmpty([string]$BaselineResolution.ExpectedBaselineObservationId)
    $fetchCount=@($DiscoveryBatch.QueryAttempts | Where-Object { [string]$_.Status -cne 'SKIPPED' }).Count
    $candidates=if($null -eq $comparison){@()}else{@($comparison.ChangeCandidates)}
    $reviewCount=@($candidates | Where-Object { [string]$_ -cin @('LOCATION_CHANGE_SUSPECTED','LOCATION_ABSENCE_SUSPECTED') }).Count
    $metrics=[pscustomobject][ordered]@{
        RowsRequested=1
        RowsCompleted=[int]([string]$commit.Code -ceq 'COMMITTED')
        BaselineHits=[int]$baselineHit
        BaselineMisses=[int](-not $baselineHit)
        ReuseEligible=[int](@($decision.ReasonCodes) -contains 'REUSE_ELIGIBLE')
        ReuseApplied=[int]([bool]$decision.ReuseApplied -and $matcherCount -eq 0)
        ReuseRejected=[int](-not [bool]$decision.ReuseApplied)
        ExternalFetchCount=$fetchCount
        MatcherCount=$matcherCount
        AvoidedMatcherCount=[int]([bool]$decision.ReuseApplied -and $matcherCount -eq 0)
        ComparisonCandidates=@($candidates).Count
        HumanReviewCandidates=$reviewCount
    }
    return [pscustomobject][ordered]@{
        Business=$Business
        DiscoveryBatch=$DiscoveryBatch
        BaselineResolution=$BaselineResolution
        ReuseDecision=$decision
        Result=$result
        Observation=$package.Observation
        Comparison=$comparison
        Commit=$commit
        Metrics=$metrics
        Package=$package
    }
}

function Invoke-Phase3LocationHistory {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$ObservedAt,
        [Parameter(Mandatory)][string]$RepositoryRevision,
        [Parameter(Mandatory)]$Row,
        [Parameter(Mandatory)][int]$SourceRowNumber,
        [Parameter(Mandatory)][scriptblock]$RepositoryStateProvider,
        [string]$ClientId=$env:NAVER_API_HUB_CLIENT_ID,
        [string]$ClientSecret=$env:NAVER_API_HUB_CLIENT_SECRET,
        [scriptblock]$RequestInvoker
    )

    $businessId=if($Row.PSObject.Properties.Name -contains 'businessId'){[string]$Row.businessId}else{''}
    Assert-CanonicalBusinessId -Value $businessId
    $business=ConvertTo-NormalizedBusiness -Row $Row -SourceRowNumber $SourceRowNumber
    $repositoryClean=$false
    try {
        $repositoryState=& $RepositoryStateProvider
        $repositoryClean=($null -ne $repositoryState -and $repositoryState.PSObject.Properties.Name -contains 'IsClean' -and $repositoryState.IsClean -is [bool] -and [bool]$repositoryState.IsClean)
    } catch {
        $repositoryClean=$false
    }
    $configuration=New-LocationIncrementalExecutionConfiguration -RepositoryClean $repositoryClean
    $baseline=Get-LocationIncrementalBaselineResolution -Store $Store -BusinessId $businessId
    $discoveryArgs=@{Business=$business;ClientId=$ClientId;ClientSecret=$ClientSecret}
    if($PSBoundParameters.ContainsKey('RequestInvoker')){$discoveryArgs.RequestInvoker=$RequestInvoker}
    $discovery=Invoke-PoiDiscovery @discoveryArgs
    return Invoke-LocationIncrementalPostDiscovery -Store $Store -RunId $RunId -ObservedAt $ObservedAt -RepositoryRevision $RepositoryRevision -BusinessId $businessId -Business $business -DiscoveryBatch $discovery -BaselineResolution $baseline -RepositoryClean $repositoryClean -ExecutionConfiguration $configuration
}

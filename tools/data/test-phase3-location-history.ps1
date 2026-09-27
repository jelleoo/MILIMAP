$ErrorActionPreference='Stop'

. (Join-Path $PSScriptRoot 'lib/history/location-incremental-reuse.ps1')
. (Join-Path $PSScriptRoot 'lib/history/compare-location-history.ps1')
$runnerPath=Join-Path $PSScriptRoot 'invoke-phase3-location-history.ps1'
if(Test-Path -LiteralPath $runnerPath){ . $runnerPath }

function Assert-Equal { param($Actual,$Expected,[string]$Message);if($Actual -cne $Expected){throw "$Message (expected: $Expected, actual: $Actual)"} }
function Assert-True { param([bool]$Condition,[string]$Message);if(-not $Condition){throw $Message} }
function Assert-Sequence { param([object[]]$Actual,[object[]]$Expected,[string]$Message);if((@($Actual) -join '|') -cne (@($Expected) -join '|')){throw "$Message (expected: $(@($Expected) -join ','), actual: $(@($Actual) -join ','))"} }
function Assert-Throws { param([scriptblock]$Action,[string]$Message);try{[void](& $Action)}catch{return};throw $Message }

$businessId='biz-0123456789abcdef0123456789abcdef'
$revision='a'*40
$row=[pscustomobject]@{
    businessId=$businessId
    업소명='테스트 식당 본점'
    시도='서울특별시'
    시군구='마포구'
    소재지도로명주소='서울특별시 마포구 테스트로 12-3, 2층 201호'
    소재지지번주소='서울특별시 마포구 테스트동 123'
}
$item=[pscustomobject]@{
    title='<b>테스트</b> 식당 본점'
    roadAddress='서울특별시 마포구 테스트로 12-3, 2층 201호'
    address='서울특별시 마포구 테스트동 123'
    telephone='02-000-0000'
    category='음식점'
    link='https://example.invalid/fixture-strong'
    mapx='1269012345'
    mapy='375012345'
}

function New-TestRequestInvoker {
    param([object[]]$Items=@($script:item),[int]$FailureCall=0,[bool]$FailAll=$false)
    $state=[pscustomobject]@{Calls=0;Uris=[Collections.Generic.List[string]]::new()}
    $invoker={
        param($Uri,$Headers)
        $state.Calls++
        $state.Uris.Add([string]$Uri)
        if($FailAll -or ($FailureCall -gt 0 -and $state.Calls -eq $FailureCall)){throw 'fixture request failure'}
        return [pscustomobject]@{items=@($Items)}
    }.GetNewClosure()
    return [pscustomobject]@{State=$state;Invoker=$invoker}
}

$script:Trace=[Collections.Generic.List[string]]::new()
$script:DiscoveryTransform=$null
$script:PrepareCalls=0
$script:CommitCalls=0
$script:CommitBeforeHook=$null
if(Test-Path -LiteralPath $runnerPath){
    $script:OriginalDiscovery=(Get-Command Invoke-PoiDiscovery).ScriptBlock
    $script:OriginalMatcher=(Get-Command Invoke-PoiMatchEvaluation).ScriptBlock
    $script:OriginalBaseline=(Get-Command Get-LocationIncrementalBaselineResolution).ScriptBlock
    $script:OriginalPrepare=(Get-Command Prepare-HistoryRun).ScriptBlock
    $script:OriginalCommit=(Get-Command Commit-HistoryRun).ScriptBlock
    function Invoke-PoiDiscovery {
        param($Business,[string]$ClientId,[string]$ClientSecret,[scriptblock]$RequestInvoker)
        $script:Trace.Add('DISCOVERY')
        $batch=& $script:OriginalDiscovery -Business $Business -ClientId $ClientId -ClientSecret $ClientSecret -RequestInvoker $RequestInvoker
        if($null -ne $script:DiscoveryTransform){return & $script:DiscoveryTransform $batch}
        return $batch
    }
    function Invoke-PoiMatchEvaluation {
        param($Business,$DiscoveryBatch)
        $script:Trace.Add('MATCHER')
        return & $script:OriginalMatcher -Business $Business -DiscoveryBatch $DiscoveryBatch
    }
    function Get-LocationIncrementalBaselineResolution {
        param($Store,[string]$BusinessId)
        $script:Trace.Add('BASELINE')
        return & $script:OriginalBaseline -Store $Store -BusinessId $BusinessId
    }
    function Prepare-HistoryRun {
        param($Store,$RunManifest,[object[]]$Artifacts=@(),[object[]]$Observations=@(),[object[]]$Comparisons=@())
        $script:PrepareCalls++
        return & $script:OriginalPrepare @PSBoundParameters
    }
    function Commit-HistoryRun {
        param($Store,$PreparedRun,$ExpectedBaselines)
        $script:CommitCalls++
        if($null -ne $script:CommitBeforeHook){
            $hook=$script:CommitBeforeHook
            $script:CommitBeforeHook=$null
            $beforeTrace=@($script:Trace)
            try { & $hook $Store $PreparedRun $ExpectedBaselines }
            finally {
                $script:Trace.Clear()
                foreach($event in $beforeTrace){$script:Trace.Add($event)}
            }
        }
        return & $script:OriginalCommit @PSBoundParameters
    }
}

function Invoke-TestRun {
    param($Store,[string]$RunId,[string]$ObservedAt,$Row=$script:row,[string]$Revision=$script:revision,[bool]$Clean=$true,[object[]]$Items=@($script:item),[int]$FailureCall=0,[bool]$FailAll=$false,[string]$RepositoryMode='NORMAL',[scriptblock]$TransformDiscovery=$null)
    $script:Trace.Clear()
    $script:DiscoveryTransform=$TransformDiscovery
    $request=New-TestRequestInvoker -Items $Items -FailureCall $FailureCall -FailAll $FailAll
    $state=[pscustomobject]@{Calls=0}
    $repositoryProvider={
        $state.Calls++
        switch($RepositoryMode){
            'THROW' {throw 'fixture repository state failure'}
            'NULL' {return $null}
            'INVALID' {return [pscustomobject]@{IsClean='true'}}
            default {return [pscustomobject]@{IsClean=$Clean}}
        }
    }.GetNewClosure()
    try {
        $run=Invoke-Phase3LocationHistory -Store $Store -RunId $RunId -ObservedAt $ObservedAt -RepositoryRevision $Revision -Row $Row -SourceRowNumber 2 -RepositoryStateProvider $repositoryProvider -ClientId 'fixture-id' -ClientSecret 'fixture-secret' -RequestInvoker $request.Invoker
    } finally {
        $script:DiscoveryTransform=$null
    }
    return [pscustomobject]@{Run=$run;RepositoryCalls=$state.Calls;ProviderCalls=$request.State.Calls;Trace=@($script:Trace)}
}

function New-TestScenario {
    param([string]$Name,[object[]]$BaselineItems=@($script:item))
    $scenarioStore=New-HistoryStoreLayout -Root (Join-Path $script:root $Name)
    $initial=Invoke-TestRun -Store $scenarioStore -RunId 'run-scenario-baseline' -ObservedAt '2026-09-27T01:00:00Z' -Items $BaselineItems
    Assert-Equal $initial.Run.Commit.Code 'COMMITTED' "$Name baseline commits"
    return [pscustomobject]@{Store=$scenarioStore;Initial=$initial}
}

function Assert-StructuralStop {
    param($Store,[string]$Name)
    $runId='run-structural-' + $Name
    $prepareBefore=$script:PrepareCalls
    $commitBefore=$script:CommitCalls
    Assert-Throws { Invoke-TestRun -Store $Store -RunId $runId -ObservedAt '2026-09-27T01:10:00Z' } "$Name structural corruption fails closed"
    Assert-Sequence @($script:Trace) @('BASELINE') "$Name stops before discovery and matcher"
    Assert-Equal $script:PrepareCalls $prepareBefore "$Name cannot prepare"
    Assert-Equal $script:CommitCalls $commitBefore "$Name cannot commit"
    Assert-True (-not (Test-Path -LiteralPath (Get-HistoryRunManifestPath -Store $Store -RunId $runId))) "$Name has no authoritative run"
}

$root=Join-Path ([IO.Path]::GetTempPath()) ('milimap-p3-6-task2-' + [guid]::NewGuid().ToString('N'))
try {
    $store=New-HistoryStoreLayout -Root $root
    $first=Invoke-TestRun -Store $store -RunId 'run-location-first' -ObservedAt '2026-09-27T00:00:00Z'
    Assert-Equal $first.RepositoryCalls 1 'Repository state is evaluated once'
    Assert-Sequence $first.Trace @('BASELINE','DISCOVERY','MATCHER') 'Baseline precedes one discovery and one matcher'
    Assert-True ($first.ProviderCalls -gt 0) 'Current discovery makes provider requests'
    Assert-Equal $first.Run.ReuseDecision.ReasonCodes[0] 'NO_BASELINE' 'First run cannot reuse'
    Assert-Equal $first.Run.Comparison.ChangeCandidates[0] 'BASELINE_ESTABLISHED' 'First run establishes baseline'
    Assert-Equal $first.Run.Commit.Code 'COMMITTED' 'First run commits'
    Assert-Equal $first.Run.Metrics.RowsRequested 1 'One row is requested'
    Assert-Equal $first.Run.Metrics.RowsCompleted 1 'Committed row is completed'
    Assert-Equal $first.Run.Metrics.BaselineHits 0 'First run misses baseline'
    Assert-Equal $first.Run.Metrics.MatcherCount 1 'First run invokes matcher once'
    Assert-Equal $first.Run.Metrics.AvoidedMatcherCount 0 'First run avoids no matcher work'
    Assert-Equal $first.Run.Metrics.ExternalFetchCount $first.ProviderCalls 'Fetch metric counts actual non-skipped requests'
    Assert-Equal $first.Run.Metrics.BaselineMisses 1 'First run has one baseline miss'
    Assert-Equal $first.Run.Metrics.ReuseRejected 1 'First run rejects reuse once'
    Assert-Equal $first.Run.Metrics.ComparisonCandidates 1 'First baseline comparison has one establishment candidate'
    Assert-Sequence @($first.Run.Metrics.PSObject.Properties.Name) @('RowsRequested','RowsCompleted','BaselineHits','BaselineMisses','ReuseEligible','ReuseApplied','ReuseRejected','ExternalFetchCount','MatcherCount','AvoidedMatcherCount','ComparisonCandidates','HumanReviewCandidates') 'Metrics expose exactly the approved Task 2 summary'
    Assert-Equal $first.Run.Observation.OperationalStatus 'COMPLETE' 'First run observation is complete'
    $firstCheckpoint=New-LocationIncrementalCheckpoint -BusinessId $businessId -Business $first.Run.Business -DiscoveryBatch $first.Run.DiscoveryBatch -RepositoryRevision $revision -ExecutionConfiguration $first.Run.Package.ExecutionProjection.Configuration
    Assert-Equal $first.Run.Observation.InputFingerprint $firstCheckpoint.InputFingerprint 'Recompute input fingerprint equals pre-match checkpoint'
    Assert-Equal $first.Run.Observation.EvidenceFingerprint $firstCheckpoint.EvidenceFingerprint 'Recompute evidence fingerprint equals pre-match checkpoint'
    Assert-Equal $first.Run.Observation.ExecutionFingerprint $firstCheckpoint.ExecutionFingerprint 'Recompute execution fingerprint equals pre-match checkpoint'
    $manifestPath=Get-HistoryRunManifestPath -Store $store -RunId 'run-location-first'
    $manifest=Read-HistoryJsonFile -Store $store -Path $manifestPath -Kind 'run manifest'
    Assert-Equal (([DateTimeOffset]$manifest.StartedAt).ToUniversalTime().ToString('o')) '2026-09-27T00:00:00.0000000+00:00' 'Manifest StartedAt uses ObservedAt'
    Assert-Equal $manifest.ExecutionStatus 'COMPLETE' 'COMPLETE observation maps to COMPLETE manifest'
    Assert-Sequence $manifest.CompletedBusinessIds @($businessId) 'COMPLETE run records completed business'
    Assert-Equal @($manifest.FailedBusinessIds).Count 0 'COMPLETE run has no failed business'

    $second=Invoke-TestRun -Store $store -RunId 'run-location-second' -ObservedAt '2026-09-27T00:10:00Z'
    Assert-Equal $second.RepositoryCalls 1 'Second run evaluates repository state once'
    Assert-Sequence $second.Trace @('BASELINE','DISCOVERY') 'Second run resolves indexed baseline and discovers but skips matcher'
    Assert-True ($second.ProviderCalls -gt 0) 'Second run still performs current provider requests'
    Assert-Equal $second.Run.ReuseDecision.ReasonCodes[0] 'REUSE_ELIGIBLE' 'Identical current evidence passes exact reuse gate'
    Assert-Equal $second.Run.BaselineResolution.Observation.ObservationId $first.Run.Observation.ObservationId 'Latest comparable first observation is reused'
    Assert-Equal $second.Run.Result $null 'Reuse creates no synthetic PoiMatchResult'
    Assert-Equal $second.Run.Commit.Code 'COMMITTED' 'Second run commits reused observation'
    Assert-Equal $second.Run.Observation.RunId 'run-location-second' 'Reused observation has new run identity'
    Assert-True ($second.Run.Observation.ObservationId -cne $first.Run.Observation.ObservationId) 'Reused observation has new observation identity'
    Assert-Equal $second.Run.Observation.SemanticFingerprint $first.Run.Observation.SemanticFingerprint 'Reused semantic fingerprint is preserved'
    Assert-Equal $second.Run.Observation.SemanticResultReference $first.Run.Observation.SemanticResultReference 'Reused semantic reference is preserved'
    Assert-Equal @($second.Run.Observation.ArtifactReferences).Count 3 'Reused observation has exactly evidence, semantic, audit refs'
    Assert-Equal @($second.Run.Package.PreparedArtifacts).Count 1 'Only current reuse audit is staged'
    Assert-Equal @($second.Run.Comparison.DeltaDimensions).Count 0 'Identical reuse has no delta dimensions'
    Assert-Equal @($second.Run.Comparison.ChangeCandidates).Count 0 'Identical reuse has no change candidates'
    Assert-Equal $second.Run.Metrics.BaselineHits 1 'Second run has indexed comparable baseline hit'
    Assert-Equal $second.Run.Metrics.BaselineMisses 0 'Second run has no baseline miss'
    Assert-Equal $second.Run.Metrics.ReuseEligible 1 'Second run is eligible'
    Assert-Equal $second.Run.Metrics.ReuseApplied 1 'Second run applies reuse'
    Assert-Equal $second.Run.Metrics.ReuseRejected 0 'Second run is not rejected'
    Assert-Equal $second.Run.Metrics.MatcherCount 0 'Second run invokes no matcher'
    Assert-Equal $second.Run.Metrics.AvoidedMatcherCount 1 'Second run avoids exactly one matcher'
    Assert-Equal $second.Run.Metrics.ExternalFetchCount $second.ProviderCalls 'Second run fetch metric reflects actual provider calls'

    $third=Invoke-TestRun -Store $store -RunId 'run-location-third' -ObservedAt '2026-09-27T00:20:00Z'
    Assert-Sequence $third.Trace @('BASELINE','DISCOVERY') 'Third run discovers once and skips matcher'
    Assert-Equal $third.Run.Commit.Code 'COMMITTED' 'Third reuse observation commits'
    Assert-Equal $third.Run.BaselineResolution.Observation.ObservationId $second.Run.Observation.ObservationId 'Third run uses second comparable observation'
    $firstEvidence=@($first.Run.Observation.ArtifactReferences | Where-Object Kind -eq 'LOCATION_EVIDENCE_PROJECTION')[0]
    $firstSemantic=@($first.Run.Observation.ArtifactReferences | Where-Object Kind -eq 'LOCATION_SEMANTIC_PROJECTION')[0]
    $secondAudit=@($second.Run.Observation.ArtifactReferences | Where-Object Kind -eq 'LOCATION_REUSE_DECISION')[0]
    foreach($reusedRun in @($second,$third)) {
        Assert-Equal @($reusedRun.Run.Observation.ArtifactReferences).Count 3 'Each reuse has evidence, semantic and current audit only'
        Assert-Equal @($reusedRun.Run.Observation.ArtifactReferences | Where-Object Kind -eq 'LOCATION_EVIDENCE_PROJECTION').Count 1 'Each reuse references evidence exactly once'
        Assert-Equal @($reusedRun.Run.Observation.ArtifactReferences | Where-Object Kind -eq 'LOCATION_SEMANTIC_PROJECTION').Count 1 'Each reuse references semantic exactly once'
        Assert-Equal @($reusedRun.Run.Observation.ArtifactReferences | Where-Object Kind -eq 'LOCATION_REUSE_DECISION').Count 1 'Each reuse references current audit exactly once'
        Assert-Equal @($reusedRun.Run.Package.PreparedArtifacts).Count 1 'Each reuse stages only current audit'
        Assert-Equal @($reusedRun.Run.Observation.ArtifactReferences | Where-Object Kind -eq 'LOCATION_EVIDENCE_PROJECTION')[0].ContentHash $firstEvidence.ContentHash 'Evidence artifact lineage is reused'
        Assert-Equal @($reusedRun.Run.Observation.ArtifactReferences | Where-Object Kind -eq 'LOCATION_SEMANTIC_PROJECTION')[0].ContentHash $firstSemantic.ContentHash 'Semantic artifact lineage is reused'
    }
    Assert-Equal @($third.Run.Observation.ArtifactReferences | Where-Object { $_.ContentHash -ceq $secondAudit.ContentHash }).Count 0 'Third run does not inherit second audit reference'

    $otherItem=$item | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $otherItem.roadAddress='서울특별시 강남구 다른로 99'
    $otherItem.address='서울특별시 강남구 다른동 99'
    $otherItem.telephone='02-0000-0099'
    $otherItem.link='https://example.invalid/fixture-other'
    $reorderScenario=New-TestScenario -Name 'provider-reorder' -BaselineItems @($item,$otherItem)
    $reordered=Invoke-TestRun -Store $reorderScenario.Store -RunId 'run-provider-reordered' -ObservedAt '2026-09-27T01:10:00Z' -Items @($otherItem,$item)
    Assert-Sequence $reordered.Trace @('BASELINE','DISCOVERY') 'Physical provider reorder skips matcher'
    Assert-Equal $reordered.Run.ReuseDecision.ReasonCodes[0] 'REUSE_ELIGIBLE' 'Physical provider reorder preserves evidence fingerprint'

    $duplicateScenario=New-TestScenario -Name 'duplicate-membership'
    $duplicateMember={param($batch);$candidate=$batch.Candidates[0];$candidate.DiscoveredBy=@($candidate.DiscoveredBy)+@($candidate.DiscoveredBy[0]);return $batch}
    $duplicated=Invoke-TestRun -Store $duplicateScenario.Store -RunId 'run-duplicate-member' -ObservedAt '2026-09-27T01:10:00Z' -TransformDiscovery $duplicateMember
    Assert-Sequence $duplicated.Trace @('BASELINE','DISCOVERY') 'Duplicate same-query membership skips matcher'
    Assert-Equal $duplicated.Run.ReuseDecision.ReasonCodes[0] 'REUSE_ELIGIBLE' 'Duplicate membership preserves evidence fingerprint'

    $changedProviderItem=$item | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $changedProviderItem.telephone='02-0000-9999'
    $changedProviderItem.category='카페'
    $changedProviderItem.link='https://example.invalid/changed'
    $evidenceScenario=New-TestScenario -Name 'evidence-changed'
    $evidenceChanged=Invoke-TestRun -Store $evidenceScenario.Store -RunId 'run-evidence-changed' -ObservedAt '2026-09-27T01:10:00Z' -Items @($changedProviderItem)
    Assert-Sequence $evidenceChanged.Trace @('BASELINE','DISCOVERY','MATCHER') 'Provider-field change runs matcher once without rediscovery'
    Assert-Equal $evidenceChanged.Run.ReuseDecision.ReasonCodes[0] 'EVIDENCE_CHANGED' 'Provider field change rejects reuse'
    Assert-Sequence $evidenceChanged.Run.Comparison.ChangeCandidates @('EVIDENCE_CHANGE_ONLY') 'Semantic-stable provider change is evidence-only'
    Assert-Equal $evidenceChanged.Run.Metrics.AvoidedMatcherCount 0 'Rejected recompute avoids no matcher work'

    $changedRow=$row | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $changedRow.업소명='다른 식당 본점'
    $inputScenario=New-TestScenario -Name 'input-changed'
    $inputChanged=Invoke-TestRun -Store $inputScenario.Store -RunId 'run-input-changed' -ObservedAt '2026-09-27T01:10:00Z' -Row $changedRow
    Assert-Sequence $inputChanged.Trace @('BASELINE','DISCOVERY','MATCHER') 'Input change runs matcher once'
    Assert-Equal $inputChanged.Run.ReuseDecision.ReasonCodes[0] 'INPUT_CHANGED' 'Canonical input change rejects reuse'
    Assert-Sequence $inputChanged.Run.Comparison.ChangeCandidates @('CANONICAL_INPUT_CHANGED') 'Input change uses P3-5 comparison precedence'

    $executionScenario=New-TestScenario -Name 'execution-changed'
    $executionChanged=Invoke-TestRun -Store $executionScenario.Store -RunId 'run-execution-changed' -ObservedAt '2026-09-27T01:10:00Z' -Revision ('b'*40)
    Assert-Sequence $executionChanged.Trace @('BASELINE','DISCOVERY','MATCHER') 'Execution change runs matcher once'
    Assert-Equal $executionChanged.Run.ReuseDecision.ReasonCodes[0] 'EXECUTION_CHANGED' 'Repository revision change rejects reuse'
    Assert-Sequence $executionChanged.Run.Comparison.ChangeCandidates @('PROCESSOR_OUTPUT_CHANGED') 'Execution change uses P3-5 processor classification'

    foreach($mode in @('NORMAL','THROW','NULL','INVALID')) {
        $dirtyScenario=New-TestScenario -Name ('repository-' + $mode.ToLowerInvariant())
        $dirty=Invoke-TestRun -Store $dirtyScenario.Store -RunId ('run-repository-' + $mode.ToLowerInvariant()) -ObservedAt '2026-09-27T01:10:00Z' -Clean $false -RepositoryMode $mode
        Assert-Equal $dirty.RepositoryCalls 1 "$mode repository state evaluated once"
        Assert-Sequence $dirty.Trace @('BASELINE','DISCOVERY','MATCHER') "$mode repository state fails closed to matcher"
        Assert-Equal $dirty.Run.ReuseDecision.ReasonCodes[0] 'DIRTY_REPOSITORY' "$mode repository state rejects reuse"
        Assert-Equal $dirty.Run.Observation.ExecutionFingerprint $dirty.Run.Package.Observation.ExecutionFingerprint "$mode recompute package is the observation"
    }

    $dirtyChain=New-TestScenario -Name 'clean-dirty-clean'
    $dirtyMiddle=Invoke-TestRun -Store $dirtyChain.Store -RunId 'run-dirty-middle' -ObservedAt '2026-09-27T01:10:00Z' -Clean $false
    Assert-Equal $dirtyMiddle.RepositoryCalls 1 'Dirty middle run checks repository exactly once'
    Assert-Sequence $dirtyMiddle.Trace @('BASELINE','DISCOVERY','MATCHER') 'Dirty middle run does not reuse clean baseline'
    Assert-Equal $dirtyMiddle.Run.ReuseDecision.ReasonCodes[0] 'DIRTY_REPOSITORY' 'Dirty middle run rejects reuse'
    Assert-Equal $dirtyMiddle.Run.Commit.Code 'COMMITTED' 'Dirty middle observation commits'
    $cleanAfterDirty=Invoke-TestRun -Store $dirtyChain.Store -RunId 'run-clean-after-dirty' -ObservedAt '2026-09-27T01:20:00Z'
    Assert-Equal $cleanAfterDirty.RepositoryCalls 1 'Clean run checks repository exactly once'
    Assert-Equal $cleanAfterDirty.Run.BaselineResolution.Observation.ObservationId $dirtyMiddle.Run.Observation.ObservationId 'Clean run sees latest comparable dirty observation'
    Assert-Equal $cleanAfterDirty.Run.ReuseDecision.ReasonCodes[0] 'EXECUTION_CHANGED' 'Dirty execution fingerprint cannot poison clean reuse'
    Assert-Sequence $cleanAfterDirty.Trace @('BASELINE','DISCOVERY','MATCHER') 'Clean after dirty recomputes once'
    $dirtyAgain=Invoke-TestRun -Store $dirtyChain.Store -RunId 'run-dirty-again' -ObservedAt '2026-09-27T01:30:00Z' -Clean $false
    Assert-Equal $dirtyAgain.Run.ReuseDecision.ReasonCodes[0] 'DIRTY_REPOSITORY' 'Dirty-to-dirty remains ineligible'
    Assert-Sequence $dirtyAgain.Trace @('BASELINE','DISCOVERY','MATCHER') 'Dirty-to-dirty also invokes matcher once'

    foreach($status in @('PARTIAL','FAILED')) {
        $statusScenario=New-TestScenario -Name ('discovery-' + $status.ToLowerInvariant())
        $incomplete=Invoke-TestRun -Store $statusScenario.Store -RunId ('run-discovery-' + $status.ToLowerInvariant()) -ObservedAt '2026-09-27T01:10:00Z' -FailureCall 1 -FailAll ($status -ceq 'FAILED')
        Assert-Sequence $incomplete.Trace @('BASELINE','DISCOVERY','MATCHER') "$status discovery runs matcher once"
        Assert-Equal $incomplete.Run.DiscoveryBatch.Status $status "$status discovery retains operational status"
        Assert-Equal $incomplete.Run.ReuseDecision.ReasonCodes[0] 'CURRENT_DISCOVERY_NOT_COMPLETE' "$status discovery rejects reuse"
        Assert-Equal $incomplete.Run.Comparison.ComparisonStatus 'UNAVAILABLE' "$status discovery does not become semantic comparison"
        Assert-Equal $incomplete.Run.Observation.OperationalStatus $status "$status observation retains operational status"
        $incompleteManifest=Read-HistoryJsonFile -Store $statusScenario.Store -Path (Get-HistoryRunManifestPath -Store $statusScenario.Store -RunId ('run-discovery-' + $status.ToLowerInvariant())) -Kind 'run manifest'
        Assert-Equal $incompleteManifest.ExecutionStatus $status "$status manifest status maps from observation"
        Assert-Equal @($incompleteManifest.CompletedBusinessIds).Count $(if($status -ceq 'FAILED'){0}else{1}) "$status manifest completed ids are mapped"
        Assert-Equal @($incompleteManifest.FailedBusinessIds).Count $(if($status -ceq 'FAILED'){1}else{0}) "$status manifest failed ids are mapped"
    }

    $comparableChain=New-TestScenario -Name 'latest-comparable-chain'
    $partialMiddle=Invoke-TestRun -Store $comparableChain.Store -RunId 'run-partial-middle' -ObservedAt '2026-09-27T01:10:00Z' -FailureCall 1
    Assert-Equal $partialMiddle.Run.Observation.OperationalStatus 'PARTIAL' 'Middle run is operationally partial'
    Assert-Equal $partialMiddle.Run.Observation.Comparable $false 'Middle run is non-comparable'
    Assert-Equal $partialMiddle.Run.Commit.Code 'COMMITTED' 'Partial middle run can be latest observation'
    $middleIndex=Get-HistoryLatestEntry -Store $comparableChain.Store -BusinessId $businessId -Domain 'LOCATION'
    Assert-Equal $middleIndex.LatestObservationId $partialMiddle.Run.Observation.ObservationId 'Latest observation advances to partial run'
    Assert-Equal $middleIndex.LatestComparableObservationId $comparableChain.Initial.Run.Observation.ObservationId 'Latest comparable stays on first COMPLETE run'
    $completeAfterPartial=Invoke-TestRun -Store $comparableChain.Store -RunId 'run-complete-after-partial' -ObservedAt '2026-09-27T01:20:00Z'
    Assert-Equal $completeAfterPartial.Run.BaselineResolution.Observation.ObservationId $comparableChain.Initial.Run.Observation.ObservationId 'Third run uses first comparable observation, not partial latest'
    Assert-Equal $completeAfterPartial.Run.Observation.OperationalStatus 'COMPLETE' 'Third run is complete'
    Assert-Equal $completeAfterPartial.Run.Commit.Code 'COMMITTED' 'Third run commits against comparable baseline'

    $missingIndexScenario=New-TestScenario -Name 'missing-derived-index'
    $derivedIndexPath=Get-HistoryIndexPath -Store $missingIndexScenario.Store -BusinessId $businessId -Domain 'LOCATION'
    Assert-True ($derivedIndexPath.StartsWith([IO.Path]::GetFullPath($missingIndexScenario.Store.Root),[StringComparison]::OrdinalIgnoreCase)) 'Only scenario-local derived index may be removed'
    Remove-Item -LiteralPath $derivedIndexPath -Force
    $missingIndex=Invoke-TestRun -Store $missingIndexScenario.Store -RunId 'run-missing-index' -ObservedAt '2026-09-27T01:10:00Z'
    Assert-Equal $missingIndex.Run.BaselineResolution.Status 'NONE' 'Missing derived index appears as no baseline before discovery'
    Assert-Sequence $missingIndex.Trace @('BASELINE','DISCOVERY','MATCHER') 'Missing index performs one discovery and matcher'
    Assert-Equal $missingIndex.Run.Comparison.ChangeCandidates[0] 'BASELINE_ESTABLISHED' 'Staged comparison initially sees no indexed baseline'
    Assert-Equal $missingIndex.Run.Commit.Code 'BASELINE_MOVED' 'Commit-time rebuild detects old comparable baseline'
    Assert-Equal $missingIndex.Run.Commit.RetryRequired $true 'Missing-index CAS requests explicit retry'
    Assert-Equal $missingIndex.Run.Metrics.ExternalFetchCount $missingIndex.ProviderCalls 'Missing-index run fetches only current discovery attempts'
    Assert-Equal $missingIndex.Run.Metrics.RowsCompleted 0 'CAS failure is not a completed row'
    Assert-Equal (Get-HistoryLatestEntry -Store $missingIndexScenario.Store -BusinessId $businessId -Domain 'LOCATION' -ComparableOnly).LatestComparableObservationId $missingIndexScenario.Initial.Run.Observation.ObservationId 'Rebuilt index retains old comparable baseline'
    Assert-True (-not (Test-Path -LiteralPath (Get-HistoryObservationPath -Store $missingIndexScenario.Store -ObservationId $missingIndex.Run.Observation.ObservationId))) 'Stale observation is not published after index rebuild'
    Assert-True (-not (Test-Path -LiteralPath (Get-HistoryComparisonPath -Store $missingIndexScenario.Store -ComparisonId $missingIndex.Run.Comparison.ComparisonId))) 'Stale establishment comparison is not published'

    foreach($raceMode in @('reuse','recompute')) {
        $raceScenario=New-TestScenario -Name ('baseline-moved-' + $raceMode)
        $script:CompetingResult=$null
        $script:CompetingRunId='run-competing-' + $raceMode
        $script:CommitBeforeHook={
            param($Store,$PreparedRun,$ExpectedBaselines)
            $script:CompetingResult=Invoke-TestRun -Store $Store -RunId $script:CompetingRunId -ObservedAt '2026-09-27T01:11:00Z' -Items @($script:changedProviderItem)
        }
        $raceRunId='run-stale-' + $raceMode
        $raceArgs=@{Store=$raceScenario.Store;RunId=$raceRunId;ObservedAt='2026-09-27T01:10:00Z'}
        if($raceMode -ceq 'recompute'){$raceArgs.Revision='b'*40}
        $race=Invoke-TestRun @raceArgs
        Assert-Equal $script:CompetingResult.Run.Commit.Code 'COMMITTED' "$raceMode competing baseline commits between decision and CAS"
        Assert-Equal $race.Run.Commit.Code 'BASELINE_MOVED' "$raceMode stale commit is rejected by existing CAS"
        Assert-Equal $race.Run.Commit.RetryRequired $true "$raceMode CAS requires caller-controlled retry"
        Assert-Equal $race.Run.Metrics.RowsCompleted 0 "$raceMode stale run is not completed"
        Assert-Sequence $race.Trace $(if($raceMode -ceq 'reuse'){@('BASELINE','DISCOVERY')}else{@('BASELINE','DISCOVERY','MATCHER')}) "$raceMode current discovery and matcher counts do not repeat"
        Assert-Equal $race.Run.Metrics.ExternalFetchCount $race.ProviderCalls "$raceMode current provider work is counted once"
        Assert-Equal (Get-HistoryLatestEntry -Store $raceScenario.Store -BusinessId $businessId -Domain 'LOCATION' -ComparableOnly).LatestComparableObservationId $script:CompetingResult.Run.Observation.ObservationId "$raceMode competing baseline remains authoritative"
        Assert-True (-not (Test-Path -LiteralPath (Get-HistoryObservationPath -Store $raceScenario.Store -ObservationId $race.Run.Observation.ObservationId))) "$raceMode stale observation is not published"
        Assert-True (-not (Test-Path -LiteralPath (Get-HistoryComparisonPath -Store $raceScenario.Store -ComparisonId $race.Run.Comparison.ComparisonId))) "$raceMode stale comparison is not published"
        Assert-True (-not (Test-Path -LiteralPath (Get-HistoryRunManifestPath -Store $raceScenario.Store -RunId $raceRunId))) "$raceMode stale run is not authoritative"
        if($raceMode -ceq 'reuse'){
            $auditRef=@($race.Run.Observation.ArtifactReferences | Where-Object Kind -eq 'LOCATION_REUSE_DECISION')[0]
            Assert-True (-not (Test-Path -LiteralPath (Join-Path $raceScenario.Store.Root $auditRef.RelativePath))) 'Stale reuse audit artifact is not published'
            Assert-Equal @($race.Run.Package.PreparedArtifacts).Count 1 'Reuse race stages only current audit'
        }
    }

    foreach($lockMode in @('reuse','recompute')) {
        $lockScenario=New-TestScenario -Name ('writer-locked-' + $lockMode)
        $lockRunId='run-writer-locked-' + $lockMode
        $lockPath=Join-Path $lockScenario.Store.Root '.writer-lock'
        $heldLock=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        $prepareBefore=$script:PrepareCalls
        $commitBefore=$script:CommitCalls
        try {
            $lockArgs=@{Store=$lockScenario.Store;RunId=$lockRunId;ObservedAt='2026-09-27T01:10:00Z'}
            if($lockMode -ceq 'recompute'){$lockArgs.Revision='b'*40}
            $locked=Invoke-TestRun @lockArgs
        } finally { $heldLock.Dispose() }
        Assert-Sequence $locked.Trace $(if($lockMode -ceq 'reuse'){@('BASELINE','DISCOVERY')}else{@('BASELINE','DISCOVERY','MATCHER')}) "$lockMode expensive work occurs before locked commit"
        Assert-Equal $locked.Run.Metrics.ExternalFetchCount $locked.ProviderCalls "$lockMode current provider work is counted once"
        Assert-Equal $script:PrepareCalls ($prepareBefore+1) "$lockMode prepares exactly once"
        Assert-Equal $script:CommitCalls ($commitBefore+1) "$lockMode attempts commit exactly once"
        Assert-Equal $locked.Run.Commit.Code 'WRITER_LOCKED' "$lockMode sees existing writer lock"
        Assert-Equal $locked.Run.Commit.RetryRequired $false "$lockMode writer lock does not schedule retry"
        Assert-Equal $locked.Run.Metrics.RowsCompleted 0 "$lockMode locked run is not complete"
        Assert-Equal (Get-HistoryLatestEntry -Store $lockScenario.Store -BusinessId $businessId -Domain 'LOCATION' -ComparableOnly).LatestComparableObservationId $lockScenario.Initial.Run.Observation.ObservationId "$lockMode baseline stays authoritative"
        Assert-True (-not (Test-Path -LiteralPath (Get-HistoryObservationPath -Store $lockScenario.Store -ObservationId $locked.Run.Observation.ObservationId))) "$lockMode observation is not published"
        Assert-True (-not (Test-Path -LiteralPath (Get-HistoryComparisonPath -Store $lockScenario.Store -ComparisonId $locked.Run.Comparison.ComparisonId))) "$lockMode comparison is not published"
        if($lockMode -ceq 'reuse'){
            $auditRef=@($locked.Run.Observation.ArtifactReferences | Where-Object Kind -eq 'LOCATION_REUSE_DECISION')[0]
            Assert-True (-not (Test-Path -LiteralPath (Join-Path $lockScenario.Store.Root $auditRef.RelativePath))) 'Locked reuse audit artifact is not published'
        }
    }

    $absenceScenario=New-TestScenario -Name 'complete-absence'
    $absence=Invoke-TestRun -Store $absenceScenario.Store -RunId 'run-complete-absence' -ObservedAt '2026-09-27T01:10:00Z' -Items @()
    Assert-Sequence $absence.Trace @('BASELINE','DISCOVERY','MATCHER') 'COMPLETE zero-candidate discovery must use matcher'
    Assert-Equal $absence.Run.DiscoveryBatch.Status 'COMPLETE' 'Zero-candidate evidence is operationally complete'
    Assert-Equal $absence.Run.ReuseDecision.ReasonCodes[0] 'EVIDENCE_CHANGED' 'Selected-to-zero cannot reuse matcher'
    Assert-True (@($absence.Run.Comparison.ChangeCandidates) -contains 'LOCATION_ABSENCE_SUSPECTED') 'Only P3-5 matcher/comparator creates strict absence suspicion'
    Assert-Equal $absence.Run.Metrics.HumanReviewCandidates 1 'Strict absence counts one human review candidate'

    $artifactScenario=New-TestScenario -Name 'artifact-invalid'
    $oldEvidence=@($artifactScenario.Initial.Run.Observation.ArtifactReferences | Where-Object Kind -eq 'LOCATION_EVIDENCE_PROJECTION')[0]
    $oldEvidencePath=Join-Path $artifactScenario.Store.Root $oldEvidence.RelativePath
    Set-Content -LiteralPath $oldEvidencePath -Value 'tampered evidence' -Encoding utf8
    $artifactInvalid=Invoke-TestRun -Store $artifactScenario.Store -RunId 'run-after-artifact-invalid' -ObservedAt '2026-09-27T01:10:00Z' -Items @($changedProviderItem)
    Assert-Sequence $artifactInvalid.Trace @('BASELINE','DISCOVERY','MATCHER') 'Projection corruption still permits current recompute once'
    Assert-Equal $artifactInvalid.Run.BaselineResolution.Status 'ARTIFACT_INVALID' 'Projection corruption is isolated from structural lineage'
    Assert-Equal $artifactInvalid.Run.ReuseDecision.ReasonCodes[0] 'PRIOR_ARTIFACT_INVALID' 'Corrupt baseline rejects reuse'
    Assert-Equal $artifactInvalid.Run.BaselineResolution.ExpectedBaselineObservationId $artifactScenario.Initial.Run.Observation.ObservationId 'Corrupt artifact preserves CAS baseline id'
    Assert-Equal $artifactInvalid.Run.Comparison $null 'Corrupt prior semantic is not compared'
    Assert-True ($null -ne $artifactInvalid.Run.Observation) 'Current recompute observation exists'
    Assert-Equal $artifactInvalid.Run.Metrics.BaselineHits 1 'Artifact-invalid lineage still counts as baseline hit'
    Assert-Equal $artifactInvalid.Run.Metrics.ComparisonCandidates 0 'No comparison means no comparison candidates'
    Assert-Equal $artifactInvalid.Run.Commit.Code 'COMMITTED' "Current recompute can commit without comparison against corrupt baseline: $($artifactInvalid.Run.Commit.Reason)"
    Assert-Equal (Get-HistoryLatestEntry -Store $artifactScenario.Store -BusinessId $businessId -Domain 'LOCATION' -ComparableOnly).LatestComparableObservationId $artifactInvalid.Run.Observation.ObservationId 'Valid recompute supersedes evidence-corrupt comparable baseline'
    Assert-Equal (Get-Content -LiteralPath $oldEvidencePath -Raw -Encoding utf8).Trim() 'tampered evidence' 'Old evidence artifact is not repaired'

    $semanticScenario=New-TestScenario -Name 'semantic-artifact-invalid'
    $oldSemantic=@($semanticScenario.Initial.Run.Observation.ArtifactReferences | Where-Object Kind -eq 'LOCATION_SEMANTIC_PROJECTION')[0]
    $oldSemanticPath=Join-Path $semanticScenario.Store.Root $oldSemantic.RelativePath
    Set-Content -LiteralPath $oldSemanticPath -Value 'tampered semantic' -Encoding utf8
    $semanticChangedRow=$row | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $semanticChangedRow.업소명='다른 식당 본점'
    $semanticInvalid=Invoke-TestRun -Store $semanticScenario.Store -RunId 'run-after-semantic-invalid' -ObservedAt '2026-09-27T01:10:00Z' -Row $semanticChangedRow
    Assert-Equal $semanticInvalid.Run.BaselineResolution.Status 'ARTIFACT_INVALID' 'Semantic projection corruption does not invalidate committed lineage'
    Assert-Equal $semanticInvalid.Run.BaselineResolution.ExpectedBaselineObservationId $semanticScenario.Initial.Run.Observation.ObservationId 'Semantic corruption preserves expected CAS baseline'
    Assert-Sequence $semanticInvalid.Trace @('BASELINE','DISCOVERY','MATCHER') 'Semantic corruption recomputes after one discovery'
    Assert-Equal $semanticInvalid.Run.Comparison $null 'Untrusted previous semantic cannot be compared'
    Assert-Equal $semanticInvalid.Run.Commit.Code 'COMMITTED' 'Fresh semantic recompute commits'
    Assert-Equal (Get-HistoryLatestEntry -Store $semanticScenario.Store -BusinessId $businessId -Domain 'LOCATION' -ComparableOnly).LatestComparableObservationId $semanticInvalid.Run.Observation.ObservationId 'Fresh semantic becomes latest comparable'
    Assert-Equal (Get-Content -LiteralPath $oldSemanticPath -Raw -Encoding utf8).Trim() 'tampered semantic' 'Old semantic artifact is not repaired'

    $structuralScenario=New-TestScenario -Name 'structural-invalid'
    $indexPath=Get-HistoryIndexPath -Store $structuralScenario.Store -BusinessId $businessId -Domain 'LOCATION'
    $originalIndex=Get-Content -LiteralPath $indexPath -Raw -Encoding utf8
    Set-Content -LiteralPath $indexPath -Value '{invalid-json' -Encoding utf8
    Assert-StructuralStop -Store $structuralScenario.Store -Name 'malformed-index'
    foreach($field in @('BusinessId','Domain')) {
        $wrongIndex=$originalIndex | ConvertFrom-Json
        if($field -ceq 'BusinessId'){$wrongIndex.BusinessId='biz-' + ('f'*32)}else{$wrongIndex.Domain='BENEFIT'}
        $wrongIndex | ConvertTo-Json -Depth 30 -Compress | Set-Content -LiteralPath $indexPath -Encoding utf8 -NoNewline
        Assert-StructuralStop -Store $structuralScenario.Store -Name ('index-' + $field.ToLowerInvariant())
    }
    $missingObservationIndex=$originalIndex | ConvertFrom-Json
    $missingObservationIndex.LatestComparableObservationId='obs-missing'
    $missingObservationIndex | ConvertTo-Json -Depth 30 -Compress | Set-Content -LiteralPath $indexPath -Encoding utf8 -NoNewline
    Assert-StructuralStop -Store $structuralScenario.Store -Name 'indexed-observation-missing'
    Set-Content -LiteralPath $indexPath -Value $originalIndex -Encoding utf8 -NoNewline
    $observationPath=Get-HistoryObservationPath -Store $structuralScenario.Store -ObservationId $structuralScenario.Initial.Run.Observation.ObservationId
    $originalObservation=Get-Content -LiteralPath $observationPath -Raw -Encoding utf8
    $wrongObservation=$originalObservation | ConvertFrom-Json
    $wrongObservation.BusinessId='biz-' + ('f'*32)
    $wrongObservation | ConvertTo-Json -Depth 30 -Compress | Set-Content -LiteralPath $observationPath -Encoding utf8 -NoNewline
    Assert-StructuralStop -Store $structuralScenario.Store -Name 'observation-identity'
    Set-Content -LiteralPath $observationPath -Value $originalObservation -Encoding utf8 -NoNewline
    $previousManifestPath=Get-HistoryRunManifestPath -Store $structuralScenario.Store -RunId $structuralScenario.Initial.Run.Observation.RunId
    $previousManifest=Get-Content -LiteralPath $previousManifestPath -Raw -Encoding utf8
    $uncommitted=$previousManifest | ConvertFrom-Json
    $uncommitted.RunCommitStatus='ABORTED'
    $uncommitted | ConvertTo-Json -Depth 30 -Compress | Set-Content -LiteralPath $previousManifestPath -Encoding utf8 -NoNewline
    Assert-StructuralStop -Store $structuralScenario.Store -Name 'previous-not-committed'

    $badBusiness=$row | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $badBusiness.businessId='not-a-canonical-id'
    $identityStore=New-HistoryStoreLayout -Root (Join-Path $root 'invalid-business-id')
    Assert-Throws { Invoke-TestRun -Store $identityStore -RunId 'run-invalid-business-id' -ObservedAt '2026-09-27T01:10:00Z' -Row $badBusiness } 'Canonical businessId is validated, not generated from name/address'
    Assert-Equal @($script:Trace).Count 0 'Invalid businessId stops before baseline/discovery/matcher'

    $legacyStore=New-HistoryStoreLayout -Root (Join-Path $root 'legacy-p3-5-baseline')
    $legacyBusiness=ConvertTo-NormalizedBusiness -Row $row -SourceRowNumber 2
    $legacyRequest=New-TestRequestInvoker
    $legacyBatch=Invoke-PoiDiscovery -Business $legacyBusiness -ClientId 'fixture-id' -ClientSecret 'fixture-secret' -RequestInvoker $legacyRequest.Invoker
    $legacyResult=Invoke-PoiMatchEvaluation -Business $legacyBusiness -DiscoveryBatch $legacyBatch
    $legacyPackage=New-LocationHistoryObservationPackage -Store $legacyStore -RunId 'run-legacy-p3-5' -BusinessId $businessId -ObservedAt '2026-09-27T01:00:00Z' -RepositoryRevision $revision -Business $legacyBusiness -DiscoveryBatch $legacyBatch -Result $legacyResult
    $legacyManifest=New-HistoryRunManifest -RunId 'run-legacy-p3-5' -StartedAt '2026-09-27T01:00:00Z' -RepositoryRevision $revision -RequestedBusinessIds @($businessId) -CompletedBusinessIds @($businessId) -FailedBusinessIds @() -ExecutionStatus 'COMPLETE' -RunCommitStatus 'PREPARED'
    $legacyPrepared=Prepare-HistoryRun -Store $legacyStore -RunManifest $legacyManifest -Artifacts @($legacyPackage.PreparedArtifacts) -Observations @($legacyPackage.Observation)
    $legacyExpected=@{}
    $legacyExpected[$businessId+'|LOCATION']=''
    Assert-Equal (Commit-HistoryRun -Store $legacyStore -PreparedRun $legacyPrepared -ExpectedBaselines $legacyExpected).Code 'COMMITTED' 'Prior P3-5 baseline fixture commits'
    $warmed=Invoke-TestRun -Store $legacyStore -RunId 'run-legacy-warmup' -ObservedAt '2026-09-27T01:10:00Z'
    Assert-Sequence $warmed.Trace @('BASELINE','DISCOVERY','MATCHER') 'P3-5 baseline without P3-6 configuration forces one matcher recompute'
    Assert-Equal $warmed.Run.ReuseDecision.ReasonCodes[0] 'EXECUTION_CHANGED' 'P3-5 baseline is not retrofitted around execution gate'
    Assert-Sequence $warmed.Run.Comparison.ChangeCandidates @('PROCESSOR_OUTPUT_CHANGED') 'One-time P3-6 warmup is processor change'

    $tamperScenario=New-TestScenario -Name 'checkpoint-package-mismatch'
    $script:OriginalPackage=(Get-Command New-LocationHistoryObservationPackage).ScriptBlock
    $script:PackageTamperField=''
    function New-LocationHistoryObservationPackage {
        param($Store,[string]$RunId,[string]$BusinessId,[string]$ObservedAt,[string]$RepositoryRevision,$Business,$DiscoveryBatch,$Result,$ExecutionConfiguration)
        $package=& $script:OriginalPackage @PSBoundParameters
        if($script:PackageTamperField){$package.Observation.($script:PackageTamperField)='0'*64}
        return $package
    }
    foreach($field in @('InputFingerprint','EvidenceFingerprint','ExecutionFingerprint')) {
        $script:PackageTamperField=$field
        $tamperedRunId='run-mismatch-' + $field.ToLowerInvariant()
        Assert-Throws { Invoke-TestRun -Store $tamperScenario.Store -RunId $tamperedRunId -ObservedAt '2026-09-27T01:10:00Z' -Revision ('b'*40) } "$field mismatch between checkpoint and P3-5 package fails closed"
        Assert-Sequence @($script:Trace) @('BASELINE','DISCOVERY','MATCHER') "$field mismatch checks only after one matcher"
        Assert-True (-not (Test-Path -LiteralPath (Get-HistoryRunManifestPath -Store $tamperScenario.Store -RunId $tamperedRunId))) "$field mismatch prevents commit"
    }
    $script:PackageTamperField=''
} finally {
    $safeRoot=[IO.Path]::GetFullPath($root)
    if($safeRoot.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::Ordinal) -and (Test-Path -LiteralPath $safeRoot)){Remove-Item -LiteralPath $safeRoot -Recurse -Force}
}

Write-Host 'Phase 3 Location history Task 2/3 tests passed.'

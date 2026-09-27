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
if(Test-Path -LiteralPath $runnerPath){
    $script:OriginalDiscovery=(Get-Command Invoke-PoiDiscovery).ScriptBlock
    $script:OriginalMatcher=(Get-Command Invoke-PoiMatchEvaluation).ScriptBlock
    $script:OriginalBaseline=(Get-Command Get-LocationIncrementalBaselineResolution).ScriptBlock
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

    $structuralScenario=New-TestScenario -Name 'structural-invalid'
    $indexPath=Get-HistoryIndexPath -Store $structuralScenario.Store -BusinessId $businessId -Domain 'LOCATION'
    Set-Content -LiteralPath $indexPath -Value '{invalid-json' -Encoding utf8
    Assert-Throws { Invoke-TestRun -Store $structuralScenario.Store -RunId 'run-after-structural-invalid' -ObservedAt '2026-09-27T01:10:00Z' } 'Structural index corruption stops before provider work'
    Assert-Sequence @($script:Trace) @('BASELINE') 'Structural failure has no discovery or matcher invocation'
    Assert-True (-not (Test-Path -LiteralPath (Get-HistoryRunManifestPath -Store $structuralScenario.Store -RunId 'run-after-structural-invalid'))) 'Structural failure creates no committed run'

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

Write-Host 'Phase 3 Location history Task 2 tests passed.'

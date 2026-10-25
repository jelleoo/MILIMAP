Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'invoke-phase5-benefit-cycle.ps1')

function Resolve-InternalPhase5BenefitBatchPlan {
    param([string]$CanonicalCsvPath,[AllowEmptyCollection()][string[]]$BusinessIds,$Store,[string]$BatchWorkspaceRoot,[string]$ObservedAt,[string]$RepositoryRevision)
    $repositoryRoots=Get-Phase5BenefitRepositoryRoots
    $actualRevision=& git -C $repositoryRoots[0] rev-parse HEAD
    if($LASTEXITCODE -ne 0 -or $RepositoryRevision -cne [string]$actualRevision){throw 'P51_REPOSITORY_REVISION_MISMATCH'}
    if($BusinessIds.Count -lt 1 -or $BusinessIds.Count -gt 10){throw 'P51_SELECTION_COUNT_INVALID'}
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($id in $BusinessIds){Assert-CanonicalBusinessId $id;if(-not $seen.Add($id)){throw 'P51_DUPLICATE_BUSINESS_ID'}}
    $csv=[IO.Path]::GetFullPath($CanonicalCsvPath)
    if(-not (Test-Path -LiteralPath $csv -PathType Leaf)){throw 'P51_CANONICAL_INPUT_MISSING'}
    $rows=@(Import-Csv -LiteralPath $csv -Encoding utf8)
    Assert-CanonicalBusinessIds -Rows $rows
    $workspace=(Assert-Phase5BenefitExternalPath $BatchWorkspaceRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $history=[IO.Path]::GetFullPath([string]$Store.Root).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if($workspace.Equals($history,[StringComparison]::OrdinalIgnoreCase) -or $workspace.StartsWith($history+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or $history.StartsWith($workspace+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'P51_WORKSPACE_HISTORY_OVERLAP'}
    $inputs=[Collections.Generic.List[object]]::new();$entries=[Collections.Generic.List[object]]::new()
    foreach($id in $BusinessIds){
        $resolved=Resolve-InternalPhase5BenefitInput -Store $Store -Rows $rows -BusinessId $id -RunId 'run-p51-preflight' -ObservedAt $ObservedAt -RepositoryRevision $RepositoryRevision -OutputDirectory (Join-Path $workspace 'items') -SourceRowNumberOffset 2
        $projection=ConvertTo-BenefitHistoryInputProjection -BusinessId $id -Benefit $resolved.Benefit -BusinessIdentity $resolved.Business -CanonicalPhone $resolved.Phone
        $entries.Add([pscustomobject][ordered]@{BusinessId=$id;SourceRowNumber=$resolved.SourceRowNumber;BusinessIdentity=$projection.BusinessIdentity;SourceUrl=$resolved.Candidate.Url;SourceKind=$resolved.Candidate.SourceKind;SourceLabel=$resolved.Candidate.SourceLabel;InputFingerprint=(Get-HistoryFingerprint -Projection $projection -SchemaVersion $script:FingerprintSchemaVersion)})
        $inputs.Add($resolved)
    }
    $layout=[ordered]@{}
    foreach($property in @('Root','RunsRoot','ObservationsRoot','ComparisonsRoot','ArtifactsRoot','IndexesRoot','TempRoot')){$layout[$property]=[IO.Path]::GetFullPath([string]$Store.$property).TrimEnd([IO.Path]::DirectorySeparatorChar)}
    $core=[pscustomobject][ordered]@{PlanVersion=1;CanonicalCsvPath=$csv;CanonicalInputDigest=(Get-HistorySha256 -Text (ConvertTo-HistoryCanonicalJson -Value $rows));RepositoryRevision=$RepositoryRevision;ObservedAt=$ObservedAt;HistoryRoot=$history;HistoryLayout=[pscustomobject]$layout;BatchWorkspaceRoot=$workspace;SourceRowNumberOffset=2;MaxBusinesses=10;Items=@($entries.ToArray())}
    $batchId='batch-'+(Get-HistorySha256 -Text (ConvertTo-HistoryCanonicalJson -Value $core))
    $directory=Join-Path $workspace $batchId
    $output=Join-Path $directory 'items'
    foreach($path in @($directory,$output,(Join-Path $directory 'plan.json'),(Join-Path $directory '.execution.claim'),(Join-Path $directory 'summary.json'))){[void](Assert-Phase5BenefitExternalPath $path)}
    $items=@(for($i=0;$i -lt $inputs.Count;$i++){
        $runId='run-p51-'+(Get-HistorySha256 -Text (ConvertTo-HistoryCanonicalJson -Value ([pscustomobject]@{Purpose='P5_1_RUN_ID_V1';BatchId=$batchId;BusinessId=$BusinessIds[$i]})))
        $inputs[$i].RunId=$runId;$inputs[$i].OutputDirectory=$output
        [pscustomobject]@{BusinessId=$BusinessIds[$i];SourceRowNumber=$inputs[$i].SourceRowNumber;RunId=$runId}
    })
    $plan=[pscustomobject][ordered]@{PlanCore=$core;BatchId=$batchId;Items=$items;PlanPath=(Join-Path $directory 'plan.json');GuardPath=(Join-Path $directory '.execution.claim');OutputDirectory=$output;SummaryPath=(Join-Path $directory 'summary.json')}
    return [pscustomobject]@{Plan=$plan;Rows=$rows;Inputs=@($inputs.ToArray())}
}

function New-Phase5BenefitBatchPlan {
    param([Parameter(Mandatory)][string]$CanonicalCsvPath,[Parameter(Mandatory)][AllowEmptyCollection()][string[]]$BusinessIds,[Parameter(Mandatory)]$Store,[Parameter(Mandatory)][string]$BatchWorkspaceRoot,[Parameter(Mandatory)][string]$ObservedAt,[Parameter(Mandatory)][string]$RepositoryRevision)
    return (Resolve-InternalPhase5BenefitBatchPlan @PSBoundParameters).Plan
}

function New-InternalPhase5BenefitBatchItem {
    param($Resolved)
    return [pscustomobject][ordered]@{
        RunId=$Resolved.RunId;BusinessId=$Resolved.BusinessId;SourceRowNumber=$Resolved.SourceRowNumber;ObservedAt=$Resolved.ObservedAt;RepositoryRevision=$Resolved.RepositoryRevision
        Action='NOT_STARTED';AuthorityValidated=$false;Status='NOT_STARTED';Code=$null;CommitCode=$null;RetryRequired=$false;Recovered=$false
        OperationalStatus=$null;ObservationId=$null;BenefitState=$null;ReviewClass=$null;Comparison=$null;Review=$null;Metrics=$null;Reasons=@();OutputStatus='NOT_WRITTEN';ProductionAction='NONE'
    }
}

function Assert-InternalPhase5BenefitBatchIndex {
    param($Store,[string]$BusinessId,[object[]]$KnownReviews=@())
    $known=@($KnownReviews | Where-Object {$_.BusinessId -ceq $BusinessId -and $_.Domain -ceq 'BENEFIT'})
    $entry=Get-HistoryLatestEntry -Store $Store -BusinessId $BusinessId -Domain BENEFIT
    if($null -eq $entry){if($known.Count -gt 0){throw 'P51_HISTORY_INDEX_MISSING'};return $null}
    if([string]::IsNullOrWhiteSpace($entry.LatestObservationId)){throw 'P51_HISTORY_LATEST_MISSING'}
    $latest=Read-HistoryObservation -Store $Store -ObservationId $entry.LatestObservationId
    if($null -ne $latest -and $latest.Comparable -and $latest.OperationalStatus -ceq 'COMPLETE' -and $entry.LatestComparableObservationId -cne $entry.LatestObservationId){throw 'P51_HISTORY_COMPARABLE_POINTER_MISMATCH'}
    if([string]::IsNullOrEmpty($entry.LatestComparableObservationId) -and @($known | Where-Object {$_.CurrentComparable -and $_.CurrentOperationalStatus -ceq 'COMPLETE'}).Count -gt 0){throw 'P51_HISTORY_COMPARABLE_POINTER_MISSING'}
    foreach($property in @('LatestObservationId','LatestComparableObservationId')){
        $id=[string]$entry.$property
        if([string]::IsNullOrEmpty($id)){continue}
        $obs=Read-HistoryObservation -Store $Store -ObservationId $id
        if($null -eq $obs -or $obs.BusinessId -cne $BusinessId -or $obs.Domain -cne 'BENEFIT'){throw 'P51_HISTORY_INDEX_REFERENCE_INVALID'}
        Assert-HistoryObservationIsCommitted -Store $Store -Observation $obs
        if($property -ceq 'LatestComparableObservationId' -and (-not $obs.Comparable -or $obs.OperationalStatus -cne 'COMPLETE')){throw 'P51_HISTORY_COMPARABLE_INVALID'}
        foreach($reference in $obs.ArtifactReferences){Assert-HistoryArtifactReferenceExists -Store $Store -Reference $reference}
    }
    # Existing committed comparison edges prove baseline succession; do not infer commit order from timestamps.
    if($known.Count -gt 0){
        $latestSuccessors=@($known | Where-Object {$_.PreviousObservationId -ceq $entry.LatestObservationId -and $_.CurrentObservationId -cne $entry.LatestObservationId})
        if($latestSuccessors.Count -gt 0){throw 'P51_HISTORY_LATEST_POINTER_REGRESSED'}
        $successors=@($known | Where-Object {$_.CurrentComparable -and $_.CurrentOperationalStatus -ceq 'COMPLETE' -and $_.PreviousObservationId -ceq $entry.LatestComparableObservationId -and $_.CurrentObservationId -cne $entry.LatestComparableObservationId})
        if(-not [string]::IsNullOrEmpty($entry.LatestComparableObservationId) -and $successors.Count -gt 0){throw 'P51_HISTORY_COMPARABLE_POINTER_REGRESSED'}
        if(-not ($latest.Comparable -and $latest.OperationalStatus -ceq 'COMPLETE')){
            $latestReview=@($known | Where-Object CurrentObservationId -CEQ $entry.LatestObservationId)
            if($latestReview.Count -ne 1 -or [string]::IsNullOrEmpty($latestReview[0].ComparisonId) -or $latestReview[0].PreviousObservationId -cne $entry.LatestComparableObservationId){throw 'P51_HISTORY_COMPARABLE_LINK_UNVERIFIED'}
        }
    }
    if(-not [string]::IsNullOrEmpty($entry.LatestComparableObservationId)){[void](Get-BenefitIncrementalBaseline -Store $Store -BusinessId $BusinessId -Entry $entry)}
    return $entry
}

function Write-InternalPhase5BenefitBatchJson {
    param([string]$Path,$Value,[switch]$Immutable)
    [void](Assert-Phase5BenefitExternalPath $Path)
    $text=ConvertTo-HistoryCanonicalJson -Value $Value
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes($text)
    if($bytes.Length -gt 1048576){throw 'P51_METADATA_TOO_LARGE'}
    if($Immutable){
        if([IO.File]::Exists($Path)){
            if((Get-Item -LiteralPath $Path -Force).Length -gt 1048576 -or [IO.File]::ReadAllText($Path) -cne $text){throw 'P51_STORED_PLAN_MISMATCH'}
            return
        }
        $stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try{$stream.Write($bytes);$stream.Flush()}finally{$stream.Dispose()}
        return
    }
    $temporary=Join-Path (Split-Path -Parent $Path) ('.summary-'+[guid]::NewGuid().ToString('N')+'.tmp')
    try{
        $stream=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try{$stream.Write($bytes);$stream.Flush()}finally{$stream.Dispose()}
        [IO.File]::Move($temporary,$Path,$true)
    }finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
}

function Set-InternalPhase5BenefitBatchSummary {
    param($Result)
    $items=@($Result.Items)
    $Result.Summary=[pscustomobject][ordered]@{
        SelectedCount=$items.Count;ExecutedCount=@($items | Where-Object Action -CEQ 'EXECUTE').Count;RecoveredCount=@($items | Where-Object Action -CEQ 'RECOVER').Count
        CommittedCount=@($items | Where-Object CommitCode -CEQ 'COMMITTED').Count
        CommittedOperationalCompleteCount=@($items | Where-Object {$_.CommitCode -ceq 'COMMITTED' -and $_.OperationalStatus -ceq 'COMPLETE'}).Count
        CommittedOperationalFailureCount=@($items | Where-Object {$_.CommitCode -ceq 'COMMITTED' -and $_.OperationalStatus -cin @('FAILED','PARTIAL','UNSUPPORTED')}).Count
        NotStartedCount=@($items | Where-Object Action -CEQ 'NOT_STARTED').Count;BlockedCount=@($items | Where-Object Status -CEQ 'BLOCKED').Count
        ReviewRouteCounts=@{}
    }
    foreach($item in $items){if($item.AuthorityValidated -and $null -ne $item.Review){$route=$item.Review.ReviewRoute;if(-not $Result.Summary.ReviewRouteCounts.ContainsKey($route)){$Result.Summary.ReviewRouteCounts[$route]=0};$Result.Summary.ReviewRouteCounts[$route]++}}
    $metrics=[ordered]@{}
    foreach($name in @('ExternalFetchCount','FetchCacheHits','ParseCount','ExtractionCount','EvaluationCount','ReuseApplied','ReuseRejected','AvoidedParseCount','AvoidedExtractionCount','AvoidedEvaluationCount','ArtifactWrites','ArtifactDedupHits','AdapterReuseCount')){
        $sum=0L;$observed=0
        foreach($item in $items){if($null -ne $item.Metrics -and $null -ne $item.Metrics.PSObject.Properties[$name] -and $null -ne $item.Metrics.$name){$sum+=[long]$item.Metrics.$name;$observed++}}
        $metrics[$name]=[pscustomobject]@{KnownSum=$sum;ObservedCount=$observed;MissingCount=($items.Count-$observed);Total=$(if($observed -eq $items.Count -and $items.Count -gt 0){$sum}else{$null})}
    }
    $Result.Metrics=[pscustomobject]$metrics
}

function Invoke-Phase5BenefitBatch {
    param([Parameter(Mandatory)][string]$CanonicalCsvPath,[Parameter(Mandatory)][AllowEmptyCollection()][string[]]$BusinessIds,[Parameter(Mandatory)]$Store,[Parameter(Mandatory)][string]$BatchWorkspaceRoot,[Parameter(Mandatory)][string]$ObservedAt,[Parameter(Mandatory)][string]$RepositoryRevision,[Parameter(Mandatory)][string]$BatchId,[ValidateSet('Execute','RecoverOnly')][string]$Mode='Execute',[Parameter(Mandatory)][scriptblock]$RepositoryStateProvider,[AllowNull()][scriptblock]$RequestInvoker=$null)
    $result=[pscustomobject][ordered]@{BatchId=$BatchId;Mode=$Mode;Status='BLOCKED';Code=$null;Reasons=@();Items=@();Summary=$null;Metrics=$null;OutputStatus='NOT_WRITTEN';ProductionAction='NONE'}
    $guard=$null;$plan=$null;$release=$false;$started=$false
    try{
        $resolved=Resolve-InternalPhase5BenefitBatchPlan -CanonicalCsvPath $CanonicalCsvPath -BusinessIds $BusinessIds -Store $Store -BatchWorkspaceRoot $BatchWorkspaceRoot -ObservedAt $ObservedAt -RepositoryRevision $RepositoryRevision
        $plan=$resolved.Plan
        if($BatchId -cne $plan.BatchId){throw 'P51_PLAN_ID_MISMATCH'}
        $result.Items=@($resolved.Inputs | ForEach-Object {New-InternalPhase5BenefitBatchItem $_})
        # Verify a previously frozen plan before any execution or replacement.
        if(Test-Path -LiteralPath $plan.PlanPath){
            if(-not [IO.File]::Exists($plan.PlanPath) -or (Get-Item -LiteralPath $plan.PlanPath -Force).Length -gt 1048576 -or [IO.File]::ReadAllText($plan.PlanPath) -cne (ConvertTo-HistoryCanonicalJson -Value $plan)){throw 'P51_STORED_PLAN_MISMATCH'}
        }
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $plan.GuardPath))
        try{$guard=[IO.File]::Open($plan.GuardPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch [IO.IOException]{$result.Code='P51_BATCH_GUARD_PRESENT';throw}
        $audit=Invoke-Phase3ReviewAudit -Store $Store
        foreach($inputRow in $resolved.Inputs){[void](Assert-InternalPhase5BenefitBatchIndex -Store $Store -BusinessId $inputRow.BusinessId -KnownReviews $audit.Items)}
        # All selected launch states are checked before any new source request.
        for($i=0;$i -lt $resolved.Inputs.Count;$i++){
            $inputRow=$resolved.Inputs[$i];$item=$result.Items[$i]
            $manifestPath=Get-HistoryRunManifestPath -Store $Store -RunId $inputRow.RunId
            $manifest=Read-HistoryJsonFile -Store $Store -Path $manifestPath -Kind 'run manifest'
            $residue=(Test-Path -LiteralPath (Join-Path $Store.TempRoot ('.p5-'+$inputRow.RunId+'.claim'))) -or (Test-Path -LiteralPath (Join-Path $Store.TempRoot $inputRow.RunId))
            if($Mode -ceq 'Execute' -and $residue){throw 'P51_UNRESOLVED_RUN_RESIDUE'}
            if($null -ne $manifest){
                Assert-HistoryRunManifest $manifest
                if($manifest.RunCommitStatus -ceq 'COMMITTED'){
                    $item=Restore-InternalPhase5BenefitCommittedCycle -Store $Store -ResolvedInput $inputRow -Result $item
                    $item.AuthorityValidated=$true;$item.Action='RECOVER';$result.Items[$i]=$item
                }elseif($Mode -ceq 'Execute'){throw 'P51_RUN_NOT_COMMITTED'}
                else{$item.Status='BLOCKED';$item.Code='P51_RUN_NOT_COMMITTED';$item.CommitCode=$manifest.RunCommitStatus}
            }elseif((Test-Path -LiteralPath (Split-Path -Parent $manifestPath)) -or $residue){
                if($Mode -ceq 'Execute'){throw 'P51_RUN_STATE_AMBIGUOUS'}
                $item.Status='BLOCKED';$item.Code='P51_RUN_STATE_AMBIGUOUS'
            }
        }
        Write-InternalPhase5BenefitBatchJson -Path $plan.PlanPath -Value $plan -Immutable
        $result.Status='FINISHED';$result.Code='P51_FINISHED'
        for($i=0;$i -lt $resolved.Inputs.Count;$i++){
            $inputRow=$resolved.Inputs[$i];$item=$result.Items[$i]
            if($item.Action -ceq 'RECOVER'){
                try{$item.OutputStatus='WRITTEN';Write-Phase5BenefitCycleOutput -Result $item -Directory $plan.OutputDirectory}catch{$item.OutputStatus='FAILED';$item.Code='OUTPUT_FAILED';$item.Reasons+=@($_.Exception.Message)}
            }elseif($Mode -ceq 'RecoverOnly'){continue}
            else{
                $started=$true;$item.Action='EXECUTE'
                $prior=Get-HistoryLatestEntry -Store $Store -BusinessId $item.BusinessId -Domain BENEFIT
                $priorComparable=if($null -ne $prior){[string]$prior.LatestComparableObservationId}else{''}
                $cycle=Invoke-Phase5BenefitCycle -Store $Store -Rows $resolved.Rows -BusinessId $item.BusinessId -RunId $item.RunId -ObservedAt $ObservedAt -RepositoryRevision $RepositoryRevision -OutputDirectory $plan.OutputDirectory -SourceRowNumberOffset 2 -RepositoryStateProvider $RepositoryStateProvider -RequestInvoker $RequestInvoker
                foreach($property in $cycle.PSObject.Properties){if($null -ne $item.PSObject.Properties[$property.Name]){$item.($property.Name)=$property.Value}}
                if($item.Recovered){$item.Action='RECOVER'}
                if($item.CommitCode -ceq 'COMMITTED'){
                    $review=$item.Review;$comparison=$item.Comparison;$item.Review=$null;$item.Comparison=$null
                    $obs=Read-HistoryObservation -Store $Store -ObservationId $item.ObservationId
                    if($null -eq $obs -or $obs.BusinessId -cne $item.BusinessId -or $obs.RunId -cne $item.RunId -or $obs.Domain -cne 'BENEFIT'){throw 'P51_COMMITTED_OBSERVATION_INVALID'}
                    Assert-HistoryObservationIsCommitted -Store $Store -Observation $obs
                    foreach($reference in $obs.ArtifactReferences){Assert-HistoryArtifactReferenceExists -Store $Store -Reference $reference}
                    $entry=Assert-InternalPhase5BenefitBatchIndex -Store $Store -BusinessId $item.BusinessId
                    $expectedComparable=if($obs.Comparable -and $obs.OperationalStatus -ceq 'COMPLETE'){$obs.ObservationId}else{$priorComparable}
                    if($null -eq $entry -or $entry.LatestObservationId -cne $obs.ObservationId -or $entry.LatestComparableObservationId -cne $expectedComparable){throw 'P51_COMMIT_INDEX_UNVERIFIED'}
                    if($null -eq $review){throw 'P51_COMMITTED_REVIEW_UNVERIFIED'}
                    $item.Review=$review;$item.Comparison=$comparison;$item.AuthorityValidated=$true
                }
            }
            if($item.CommitCode -cne 'COMMITTED' -or -not $item.AuthorityValidated){$result.Status='STOPPED';$result.Code='P51_ITEM_UNCOMMITTED';break}
            if($item.OutputStatus -ceq 'FAILED'){$result.Status='STOPPED';$result.Code='P51_ITEM_OUTPUT_FAILED';break}
            if($item.OperationalStatus -cne 'COMPLETE' -and ($item.OperationalStatus -cnotin @('FAILED','PARTIAL','UNSUPPORTED') -or $item.Review.ReviewRoute -cne 'OPERATIONAL_DIAGNOSTIC')){$result.Status='STOPPED';$result.Code='P51_DIAGNOSTIC_ROUTE_UNVERIFIED';break}
        }
        $release=$true
    }catch{
        if($started -and $item.Action -ceq 'EXECUTE' -and -not $item.AuthorityValidated){
            $item.Status='FAILED';$item.Code='P51_ITEM_RESULT_UNVERIFIED';$item.Reasons=@($_.Exception.Message);$item.Review=$null;$item.Comparison=$null
        }
        $result.Status=if($started){'STOPPED'}else{'BLOCKED'}
        if(-not $result.Code -or $result.Code -ceq 'P51_FINISHED'){$result.Code='P51_VALIDATION_OR_EXECUTION_FAILED'}
        $result.Reasons=@($_.Exception.Message)
    }
    try{
        Set-InternalPhase5BenefitBatchSummary $result
        if($null -ne $guard){
            try{$result.OutputStatus='WRITTEN';Write-InternalPhase5BenefitBatchJson -Path $plan.SummaryPath -Value $result}catch{$result.OutputStatus='FAILED';$result.Status='STOPPED';$result.Code='P51_SUMMARY_OUTPUT_FAILED';$result.Reasons+=@($_.Exception.Message);$release=$false}
        }
    }finally{
        if($null -ne $guard){$guard.Dispose();if($release){[IO.File]::Delete($plan.GuardPath)}}
    }
    return $result
}

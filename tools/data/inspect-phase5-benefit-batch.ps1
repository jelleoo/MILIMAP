Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'invoke-phase5-benefit-batch.ps1')

function Assert-InternalPhase5InspectionPath {
    param([string]$Path,[switch]$External)
    if([string]::IsNullOrWhiteSpace($Path) -or $Path -match '(^|[/\\])\.\.([/\\]|$)'){throw 'P52_UNSAFE_PATH'}
    $full=[IO.Path]::GetFullPath($Path)
    $ancestor=$full
    while(-not [string]::IsNullOrEmpty($ancestor)){
        if(Test-Path -LiteralPath $ancestor){if((Get-Item -LiteralPath $ancestor -Force).Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)){throw 'P52_REPARSE_PATH'}}
        $ancestor=[IO.Path]::GetDirectoryName($ancestor)
    }
    if($External){[void](Assert-Phase5BenefitExternalPath $full)}
    return $full
}

function Get-InternalPhase5InspectionStamp {
    param([string]$Path)
    [void](Assert-InternalPhase5InspectionPath $Path)
    if(-not (Test-Path -LiteralPath $Path)){return 'ABSENT'}
    $item=Get-Item -LiteralPath $Path -Force
    if($item.PSIsContainer){return 'DIR|'+$item.LastWriteTimeUtc.Ticks+'|'+(@([IO.Directory]::EnumerateFileSystemEntries($Path) | Sort-Object -CaseSensitive) -join '|')}
    try{return 'FILE|'+$item.Length+'|'+$item.LastWriteTimeUtc.Ticks+'|'+(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
    catch [IO.IOException]{return 'UNREADABLE|'+$item.Length+'|'+$item.LastWriteTimeUtc.Ticks}
}

function Read-InternalPhase5InspectionJson {
    param([string]$Path,[string]$TooLargeCode='P52_METADATA_TOO_LARGE')
    [void](Assert-InternalPhase5InspectionPath $Path)
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try{
        if($stream.Length -gt 1048576){throw $TooLargeCode}
        $memory=[IO.MemoryStream]::new()
        try{
            $buffer=[byte[]]::new(4096)
            while(($read=$stream.Read($buffer,0,$buffer.Length)) -gt 0){if($memory.Length+$read -gt 1048576){throw $TooLargeCode};$memory.Write($buffer,0,$read)}
            $text=[Text.UTF8Encoding]::new($false,$true).GetString($memory.ToArray()).TrimStart([char]0xfeff)
        }finally{$memory.Dispose()}
    }finally{$stream.Dispose()}
    $jsonOptions=@{};if((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')){$jsonOptions.DateKind='String'}
    return [pscustomobject]@{Text=$text;Value=($text | ConvertFrom-Json @jsonOptions)}
}

function Assert-InternalPhase5InspectionFields {
    param($Value,[string[]]$Names)
    if($null -eq $Value -or $Value -isnot [pscustomobject] -or (@($Value.PSObject.Properties.Name | Sort-Object -CaseSensitive) -join '|') -cne (@($Names | Sort-Object -CaseSensitive) -join '|')){throw 'P52_PLAN_SHAPE_INVALID'}
}

function Get-InternalPhase5InspectionRunId {
    param([string]$BatchId,[string]$BusinessId)
    return 'run-p51-'+(Get-HistorySha256 -Text (ConvertTo-HistoryCanonicalJson ([pscustomobject]@{Purpose='P5_1_RUN_ID_V1';BatchId=$BatchId;BusinessId=$BusinessId})))
}
function Assert-InternalPhase5StoredPlan {
    param($Plan,[string]$Text)
    Assert-InternalPhase5InspectionFields $Plan @('PlanCore','BatchId','Items','PlanPath','GuardPath','OutputDirectory','SummaryPath')
    $core=$Plan.PlanCore
    Assert-InternalPhase5InspectionFields $core @('PlanVersion','CanonicalCsvPath','CanonicalInputDigest','RepositoryRevision','ObservedAt','HistoryRoot','HistoryLayout','BatchWorkspaceRoot','SourceRowNumberOffset','MaxBusinesses','Items')
    if(($core.PlanVersion -isnot [int] -and $core.PlanVersion -isnot [long]) -or $core.PlanVersion -ne 1){throw 'P52_PLAN_VERSION_UNSUPPORTED'}
    if(($core.SourceRowNumberOffset -isnot [int] -and $core.SourceRowNumberOffset -isnot [long]) -or $core.SourceRowNumberOffset -ne 2 -or ($core.MaxBusinesses -isnot [int] -and $core.MaxBusinesses -isnot [long]) -or $core.MaxBusinesses -ne 10){throw 'P52_PLAN_BOUNDS_INVALID'}
    Assert-HistoryHash $core.CanonicalInputDigest
    Assert-HistoryTimestamp $core.ObservedAt
    if($core.RepositoryRevision -cnotmatch '^[0-9a-f]{40}$'){throw 'P52_PLAN_REVISION_INVALID'}
    foreach($path in @($core.CanonicalCsvPath,$core.HistoryRoot,$core.BatchWorkspaceRoot)){
        if($path -isnot [string] -or -not [IO.Path]::IsPathFullyQualified($path) -or $path -match '(^|[/\\])\.\.([/\\]|$)'){throw 'P52_STORED_PATH_INVALID'}
    }
    Assert-InternalPhase5InspectionFields $core.HistoryLayout @('Root','RunsRoot','ObservationsRoot','ComparisonsRoot','ArtifactsRoot','IndexesRoot','TempRoot')
    if($core.HistoryLayout.Root -cne $core.HistoryRoot){throw 'P52_STORED_ROOT_MISMATCH'}
    foreach($property in @('RunsRoot','ObservationsRoot','ComparisonsRoot','ArtifactsRoot','IndexesRoot','TempRoot')){
        $path=[string]$core.HistoryLayout.$property
        if(-not [IO.Path]::IsPathFullyQualified($path) -or $path -match '(^|[/\\])\.\.([/\\]|$)'){throw 'P52_STORED_PATH_INVALID'}
        [void](Assert-HistoryStorePathWithinRoot -Store $core.HistoryLayout -Path $path)
    }
    $expected='batch-'+(Get-HistorySha256 -Text (ConvertTo-HistoryCanonicalJson $core))
    if($Plan.BatchId -cne $expected){throw 'P52_PLAN_BATCH_ID_INVALID'}
    $directory=Join-Path $core.BatchWorkspaceRoot $expected
    foreach($pair in @(@('PlanPath','plan.json'),@('GuardPath','.execution.claim'),@('OutputDirectory','items'),@('SummaryPath','summary.json'))){if($Plan.($pair[0]) -cne (Join-Path $directory $pair[1])){throw 'P52_DERIVED_PATH_INVALID'}}
    if($core.Items -isnot [array] -or $Plan.Items -isnot [array] -or $core.Items.Count -lt 1 -or $core.Items.Count -gt 10 -or $core.Items.Count -ne $Plan.Items.Count){throw 'P52_PLAN_SELECTION_INVALID'}
    $ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$ordinals=[Collections.Generic.HashSet[int]]::new()
    for($i=0;$i -lt $core.Items.Count;$i++){
        $item=$core.Items[$i];$run=$Plan.Items[$i]
        Assert-InternalPhase5InspectionFields $item @('BusinessId','SourceRowNumber','BusinessIdentity','SourceUrl','SourceKind','SourceLabel','InputFingerprint')
        Assert-InternalPhase5InspectionFields $run @('BusinessId','SourceRowNumber','RunId')
        if($item.BusinessId -isnot [string] -or $run.BusinessId -isnot [string] -or $run.RunId -isnot [string] -or ($run.SourceRowNumber -isnot [int] -and $run.SourceRowNumber -isnot [long])){throw 'P52_PLAN_RUN_ID_INVALID'}
        Assert-CanonicalBusinessId $item.BusinessId;Assert-HistoryHash $item.InputFingerprint
        Assert-InternalPhase5InspectionFields $item.BusinessIdentity @('OriginalName','NormalizedName','BaseName','BranchName','OriginalRoadAddress','OriginalLotAddress','PreferredAddress','Province','City','District','Dong','RoadName','BuildingMain','BuildingSub','Floor','Unit','AddressParseStatus','Phone')
        foreach($field in $item.BusinessIdentity.PSObject.Properties){if($field.Value -isnot [string]){throw 'P52_PLAN_IDENTITY_INVALID'}}
        if(-not $ids.Add($item.BusinessId) -or ($item.SourceRowNumber -isnot [int] -and $item.SourceRowNumber -isnot [long]) -or $item.SourceRowNumber -lt 2 -or -not $ordinals.Add($item.SourceRowNumber)){throw 'P52_PLAN_SELECTION_INVALID'}
        if($item.SourceKind -isnot [string] -or $item.SourceUrl -isnot [string] -or $item.SourceKind -cne 'PUBLIC_OFFICIAL' -or $item.SourceLabel -isnot [string] -or -not (Test-BenefitSafeHttpUri $item.SourceUrl)){throw 'P52_PLAN_SOURCE_INVALID'}
        $runId=Get-InternalPhase5InspectionRunId -BatchId $expected -BusinessId $item.BusinessId
        if($run.BusinessId -cne $item.BusinessId -or $run.SourceRowNumber -cne $item.SourceRowNumber -or $run.RunId -cne $runId){throw 'P52_PLAN_RUN_ID_INVALID'}
    }
    if($Text -cne (ConvertTo-HistoryCanonicalJson $Plan)){throw 'P52_PLAN_CANONICAL_BYTES_INVALID'}
}

function Assert-InternalPhase5InspectionTree {
    param([string]$Root)
    if(-not (Test-Path -LiteralPath $Root -PathType Container)){throw 'P52_HISTORY_ROOT_MISSING'}
    $pending=[Collections.Generic.Stack[string]]::new();$pending.Push($Root)
    while($pending.Count -gt 0){
        foreach($entry in [IO.DirectoryInfo]::new($pending.Pop()).GetFileSystemInfos()){
            if($entry.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)){throw 'P52_REPARSE_PATH'}
            if($entry.Attributes.HasFlag([IO.FileAttributes]::Directory)){$pending.Push($entry.FullName)}
        }
    }
}

function Inspect-Phase5BenefitBatch {
    param([Parameter(Mandatory)]$Store,[Parameter(Mandatory)][string]$CanonicalCsvPath,[Parameter(Mandatory)][AllowEmptyCollection()][string[]]$BusinessIds,[Parameter(Mandatory)][string]$BatchWorkspaceRoot,[Parameter(Mandatory)][string]$BatchId,[Parameter(Mandatory)][string]$ObservedAt,[Parameter(Mandatory)][string]$RepositoryRevision)
    $result=[pscustomobject][ordered]@{InspectionStatus='FINISHED';PlanState='NOT_INSPECTED';CurrentCompatibility='UNAVAILABLE';HistoryState='NOT_INSPECTED';GuardState='NOT_INSPECTED';Items=@();ReasonCodes=@();RecoveryConsideration='BLOCKED';ExecutionAuthorized=$false;ProductionAction='NONE';SnapshotGuarantee='BEST_EFFORT_ONLY'}
    $watch=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    try{
        if($BatchId -cnotmatch '^batch-[0-9a-f]{64}$' -or $RepositoryRevision -cnotmatch '^[0-9a-f]{40}$'){throw 'P52_INPUT_ID_INVALID'}
        Assert-HistoryTimestamp $ObservedAt
        if($BusinessIds.Count -lt 1 -or $BusinessIds.Count -gt 10){throw 'P52_SELECTION_INVALID'}
        $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($id in $BusinessIds){Assert-CanonicalBusinessId $id;if(-not $seen.Add($id)){throw 'P52_SELECTION_INVALID'}}
        foreach($property in @('Root','RunsRoot','ObservationsRoot','ComparisonsRoot','ArtifactsRoot','IndexesRoot','TempRoot')){[void](Assert-InternalPhase5InspectionPath $Store.$property -External);if($property -cne 'Root'){[void](Assert-HistoryStorePathWithinRoot -Store $Store -Path $Store.$property)}}
        $csv=Assert-InternalPhase5InspectionPath $CanonicalCsvPath
        $workspace=(Assert-InternalPhase5InspectionPath $BatchWorkspaceRoot -External).TrimEnd([IO.Path]::DirectorySeparatorChar)
        $history=[IO.Path]::GetFullPath($Store.Root).TrimEnd([IO.Path]::DirectorySeparatorChar)
        if($workspace.Equals($history,[StringComparison]::OrdinalIgnoreCase) -or $workspace.StartsWith($history+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or $history.StartsWith($workspace+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'P52_WORKSPACE_HISTORY_OVERLAP'}
        $directory=Assert-InternalPhase5InspectionPath (Join-Path $workspace $BatchId) -External
        $planPath=Assert-InternalPhase5InspectionPath (Join-Path $directory 'plan.json') -External
        $guardPath=Assert-InternalPhase5InspectionPath (Join-Path $directory '.execution.claim') -External
        # Metadata-only size check precedes even the plan's watched content hash.
        if((Test-Path -LiteralPath $planPath -PathType Leaf) -and (Get-Item -LiteralPath $planPath -Force).Length -gt 1048576){$result.PlanState='INVALID';throw 'P52_PLAN_TOO_LARGE'}
        foreach($path in @($planPath,$guardPath,$csv)){$watch[$path]=Get-InternalPhase5InspectionStamp $path}
        $result.GuardState=if(Test-Path -LiteralPath $guardPath){'PRESENT_BLOCKING'}else{'ABSENT'}
        $frozen=$null
        if(Test-Path -LiteralPath $planPath){
            $result.PlanState='INVALID'
            $read=Read-InternalPhase5InspectionJson -Path $planPath -TooLargeCode P52_PLAN_TOO_LARGE
            Assert-InternalPhase5StoredPlan -Plan $read.Value -Text $read.Text
            $frozen=$read.Value
            if($frozen.BatchId -cne $BatchId){throw 'P52_PLAN_BATCH_ID_INVALID'}
            $result.PlanState='VALID'
        }else{$result.PlanState='MISSING'}
        $actual=[string](& git -C (Get-Phase5BenefitRepositoryRoots)[0] rev-parse HEAD)
        if($LASTEXITCODE -ne 0){throw 'P52_CHECKOUT_UNAVAILABLE'}
        $resolved=$null
        if($RepositoryRevision -cne $actual){$result.CurrentCompatibility='MISMATCH';$result.ReasonCodes+=@('P52_CURRENT_REVISION_MISMATCH')}
        else{
            try{
                $resolved=Resolve-InternalPhase5BenefitBatchPlan -Store $Store -CanonicalCsvPath $csv -BusinessIds $BusinessIds -BatchWorkspaceRoot $workspace -ObservedAt $ObservedAt -RepositoryRevision $RepositoryRevision
                $result.CurrentCompatibility=if($resolved.Plan.BatchId -ceq $BatchId){'MATCH'}else{'MISMATCH'}
                if($result.CurrentCompatibility -ceq 'MISMATCH'){$result.ReasonCodes+=@('P52_CURRENT_INPUT_MISMATCH')}
            }catch{$result.CurrentCompatibility='UNAVAILABLE';$result.ReasonCodes+=@('P52_CURRENT_INPUT_UNAVAILABLE')}
        }
        if($null -ne $frozen){
            if(($frozen.Items.BusinessId -join '|') -cne ($BusinessIds -join '|') -or $frozen.PlanCore.ObservedAt -cne $ObservedAt -or $frozen.PlanCore.RepositoryRevision -cne $RepositoryRevision -or $frozen.PlanCore.CanonicalCsvPath -cne $csv -or $frozen.PlanCore.BatchWorkspaceRoot -cne $workspace -or (ConvertTo-HistoryCanonicalJson $frozen.PlanCore.HistoryLayout) -cne (ConvertTo-HistoryCanonicalJson ([pscustomobject][ordered]@{Root=$Store.Root;RunsRoot=$Store.RunsRoot;ObservationsRoot=$Store.ObservationsRoot;ComparisonsRoot=$Store.ComparisonsRoot;ArtifactsRoot=$Store.ArtifactsRoot;IndexesRoot=$Store.IndexesRoot;TempRoot=$Store.TempRoot}))){$result.CurrentCompatibility='MISMATCH';$result.ReasonCodes+=@('P52_OPERATOR_PLAN_MISMATCH')}
        }
        $resolvedMatches=($null -ne $resolved -and $resolved.Plan.BatchId -ceq $BatchId)
        $items=if($null -ne $frozen){@($frozen.Items)}elseif($resolvedMatches){@($resolved.Plan.Items)}else{@(foreach($id in $BusinessIds){[pscustomobject]@{BusinessId=$id;RunId=(Get-InternalPhase5InspectionRunId -BatchId $BatchId -BusinessId $id);SourceRowNumber=$null}})}
        $result.Items=@($items | ForEach-Object {[pscustomobject][ordered]@{BusinessId=$_.BusinessId;RunId=$_.RunId;SourceRowNumber=$_.SourceRowNumber;RunState='UNSTARTED';CommitStatus=$null;OperationalStatus=$null;ObservationId=$null;ComparisonId=$null;ReviewKey=$null;ClaimState='NOT_INSPECTED';StagingState='NOT_INSPECTED';DerivedReportState='NOT_INSPECTED';FingerprintState='NOT_VERIFIED';Metrics=$null;ResidueBlocksExecute=$false;ReasonCodes=@();RecoveryConsideration='NOT_APPLICABLE';ExecutionAuthorized=$false;ProductionAction='NONE'}})
        Assert-InternalPhase5InspectionTree $history
        $identityPlan=if($null -ne $frozen){$frozen}elseif($resolvedMatches){$resolved.Plan}else{$null}
        $identityRevision=if($null -ne $identityPlan){$identityPlan.PlanCore.RepositoryRevision}else{$RepositoryRevision}
        $identityTime=if($null -ne $identityPlan){$identityPlan.PlanCore.ObservedAt}else{$ObservedAt}
        if($null -ne $frozen -and (ConvertTo-HistoryCanonicalJson $frozen.PlanCore.HistoryLayout) -cne (ConvertTo-HistoryCanonicalJson ([pscustomobject][ordered]@{Root=$Store.Root;RunsRoot=$Store.RunsRoot;ObservationsRoot=$Store.ObservationsRoot;ComparisonsRoot=$Store.ComparisonsRoot;ArtifactsRoot=$Store.ArtifactsRoot;IndexesRoot=$Store.IndexesRoot;TempRoot=$Store.TempRoot}))){$result.HistoryState='NOT_ASSOCIATED';throw 'P52_HISTORY_ROOT_ASSOCIATION_MISMATCH'}
        $manifests=@{}
        # Establish selected mutable identities before the one global audit.
        foreach($item in $result.Items){
            $manifestPath=Get-HistoryRunManifestPath -Store $Store -RunId $item.RunId
            $claimPath=Join-Path $Store.TempRoot ('.p5-'+$item.RunId+'.claim');$stagePath=Join-Path $Store.TempRoot $item.RunId
            $reportPath=Join-Path (Join-Path $directory 'items') ($item.RunId+'.json')
            foreach($path in @($manifestPath,(Split-Path -Parent $manifestPath),$claimPath,$stagePath,$reportPath,(Get-HistoryIndexPath -Store $Store -BusinessId $item.BusinessId -Domain BENEFIT))){$watch[$path]=Get-InternalPhase5InspectionStamp $path}
            $item.ClaimState=if(Test-Path -LiteralPath $claimPath){'PRESENT'}else{'ABSENT'}
            $item.StagingState=if(Test-Path -LiteralPath $stagePath){'PRESENT'}else{'ABSENT'}
            $item.ResidueBlocksExecute=($item.ClaimState -ceq 'PRESENT' -or $item.StagingState -ceq 'PRESENT')
            $item.RunState='INVALID'
            $manifest=Read-HistoryJsonFile -Store $Store -Path $manifestPath -Kind 'run manifest'
            if($null -eq $manifest){
                $item.RunState=if($item.ResidueBlocksExecute -or (Test-Path -LiteralPath (Split-Path -Parent $manifestPath))){'UNRESOLVED'}else{'UNSTARTED'}
                continue
            }
            Assert-HistoryRunManifest $manifest
            if($manifest.RunId -cne $item.RunId -or $manifest.RepositoryRevision -cne $identityRevision -or [DateTimeOffset]$manifest.StartedAt -ne [DateTimeOffset]::Parse($identityTime,[Globalization.CultureInfo]::InvariantCulture) -or @($manifest.RequestedBusinessIds).Count -ne 1 -or $manifest.RequestedBusinessIds[0] -cne $item.BusinessId){throw 'P52_MANIFEST_IDENTITY_MISMATCH'}
            $manifests[$item.RunId]=$manifest;$item.CommitStatus=$manifest.RunCommitStatus
            $item.RunState=switch -CaseSensitive ($manifest.RunCommitStatus){COMMITTED {'COMMITTED_UNVERIFIED'};ABORTED {'ABORTED'};default {'UNRESOLVED'}}
        }
        $audit=Invoke-Phase3ReviewAudit -Store $Store
        foreach($id in $BusinessIds){[void](Assert-InternalPhase5BenefitBatchIndex -Store $Store -BusinessId $id -KnownReviews $audit.Items)}
        for($i=0;$i -lt $result.Items.Count;$i++){
            $item=$result.Items[$i]
            if($item.CommitStatus -cne 'COMMITTED'){continue}
            $matches=@($audit.Items | Where-Object RunId -CEQ $item.RunId)
            if($matches.Count -ne 1 -or $matches[0].BusinessId -cne $item.BusinessId -or $matches[0].Domain -cne 'BENEFIT'){throw 'P52_COMMITTED_LINKAGE_AMBIGUOUS'}
            $review=$matches[0]
            $observationPath=Get-HistoryObservationPath -Store $Store -ObservationId $review.CurrentObservationId
            $watch[$observationPath]=Get-InternalPhase5InspectionStamp $observationPath
            $obs=Read-HistoryObservation -Store $Store -ObservationId $review.CurrentObservationId
            if($null -eq $obs -or $obs.RunId -cne $item.RunId -or $obs.BusinessId -cne $item.BusinessId -or $obs.Domain -cne 'BENEFIT' -or [DateTimeOffset]$obs.ObservedAt -ne [DateTimeOffset]::Parse($identityTime,[Globalization.CultureInfo]::InvariantCulture) -or ($null -ne $identityPlan -and $obs.InputFingerprint -cne $identityPlan.PlanCore.Items[$i].InputFingerprint)){throw 'P52_OBSERVATION_IDENTITY_MISMATCH'}
            [void](Read-BenefitIncrementalEvidenceProjection -Store $Store -Observation $obs)
            if($result.CurrentCompatibility -ceq 'MATCH' -and $null -ne $resolved){
                $input=$resolved.Inputs[$i]
                $projection=ConvertTo-BenefitHistoryInputProjection -BusinessId $item.BusinessId -Benefit $input.Benefit -BusinessIdentity $input.Business -CanonicalPhone $input.Phone
                $execution=ConvertTo-BenefitHistoryExecutionProjection -RepositoryRevision $RepositoryRevision
                if($obs.InputFingerprint -cne (Get-HistoryFingerprint $projection -SchemaVersion $script:FingerprintSchemaVersion) -or $obs.ExecutionFingerprint -cne (Get-HistoryFingerprint $execution -SchemaVersion $script:FingerprintSchemaVersion)){throw 'P52_COMMITTED_FINGERPRINT_MISMATCH'}
                $item.FingerprintState='MATCH'
            }
            $comparison=$null
            if($review.ComparisonId){
                $comparisonPath=Get-HistoryComparisonPath -Store $Store -ComparisonId $review.ComparisonId
                $watch[$comparisonPath]=Get-InternalPhase5InspectionStamp $comparisonPath
                $comparison=Read-HistoryJsonFile -Store $Store -Path $comparisonPath -Kind 'comparison'
                if($null -eq $comparison){throw 'P52_COMPARISON_MISSING'}
            }
            $view=[pscustomobject]@{ObservedAt=$identityTime;ObservationId=$null;OperationalStatus=$null;BenefitState=$null;ReviewClass=$null;Comparison=$null;Review=$null;Reasons=@();Status=$null}
            Set-Phase5BenefitCommittedView -Result $view -Store $Store -Observation $obs -Comparison $comparison
            # Observation time was validated above against the manifest/frozen instant.
            # The audit's display string can differ after the Core JSON reader parses dates.
            $audited=$review | Select-Object *;$audited.ObservedAt=$view.Review.ObservedAt
            if((ConvertTo-HistoryCanonicalJson $view.Review) -cne (ConvertTo-HistoryCanonicalJson $audited)){
                $changeException=[InvalidOperationException]::new('P52_AUDITED_REVIEW_CHANGED')
                $changeException.Data['P52ConcurrentChange']=$true
                throw $changeException
            }
            $item.RunState='COMMITTED';$item.OperationalStatus=$obs.OperationalStatus;$item.ObservationId=$obs.ObservationId;$item.ComparisonId=$review.ComparisonId;$item.ReviewKey=$review.ReviewKey
            $item.RecoveryConsideration='CONDITIONAL'
            $reportPath=Join-Path (Join-Path $directory 'items') ($item.RunId+'.json')
            if(-not (Test-Path -LiteralPath $reportPath)){$item.DerivedReportState='MISSING'}else{
                $item.DerivedReportState='UNREADABLE'
                try{
                    $report=(Read-InternalPhase5InspectionJson $reportPath).Value
                    if($null -eq $report.Review -or $report.Review.ReviewKey -cne $item.ReviewKey -or $report.RunId -cne $item.RunId -or $report.BusinessId -cne $item.BusinessId -or $report.ObservationId -cne $obs.ObservationId -or $report.RepositoryRevision -cne $identityRevision -or [DateTimeOffset]$report.ObservedAt -ne [DateTimeOffset]::Parse($identityTime,[Globalization.CultureInfo]::InvariantCulture)){$item.DerivedReportState='IDENTITY_CONFLICT'}else{$item.DerivedReportState='PRESENT_IDENTITY_ONLY'}
                }catch{$item.ReasonCodes+=@('P52_DERIVED_REPORT_UNREADABLE')}
                if($item.DerivedReportState -cne 'PRESENT_IDENTITY_ONLY'){$item.RecoveryConsideration='BLOCKED'}
            }
        }
        $result.HistoryState='VERIFIED'
        if($result.GuardState -ceq 'PRESENT_BLOCKING' -or $result.CurrentCompatibility -cne 'MATCH' -or $result.PlanState -cne 'VALID'){
            $result.RecoveryConsideration='BLOCKED'
            foreach($item in $result.Items){if($item.CommitStatus -ceq 'COMMITTED'){$item.RecoveryConsideration='BLOCKED'}}
        }elseif(@($result.Items | Where-Object RecoveryConsideration -CEQ 'BLOCKED').Count -gt 0){$result.RecoveryConsideration='BLOCKED'}
        elseif(@($result.Items | Where-Object RecoveryConsideration -CEQ 'CONDITIONAL').Count -gt 0){$result.RecoveryConsideration='CONDITIONAL'}else{$result.RecoveryConsideration='NOT_APPLICABLE'}
    }catch{
        $concurrent=$_.Exception.Data.Contains('P52ConcurrentChange')
        $result.InspectionStatus=if($concurrent){'INCONCLUSIVE_CONCURRENT_CHANGE'}else{'BLOCKED'}
        if(-not $concurrent -and $result.HistoryState -ceq 'NOT_INSPECTED' -and $result.PlanState -cin @('VALID','MISSING')){$result.HistoryState='INVALID'}
        $result.ReasonCodes+=@($_.Exception.Message)
        $result.RecoveryConsideration=if($concurrent){'INCONCLUSIVE'}else{'BLOCKED'}
        $code=if($concurrent){'P52_CONCURRENT_CHANGE'}else{'P52_GLOBAL_INSPECTION_BLOCKED'}
        if($concurrent){$result.ReasonCodes+=@($code)}
        foreach($item in $result.Items){$item.RecoveryConsideration=$result.RecoveryConsideration;$item.ReasonCodes+=@($code)}
    }finally{
        foreach($path in $watch.Keys){
            try{if((Get-InternalPhase5InspectionStamp $path) -cne $watch[$path]){$result.InspectionStatus='INCONCLUSIVE_CONCURRENT_CHANGE';$result.RecoveryConsideration='INCONCLUSIVE';$result.ReasonCodes+=@('P52_CONCURRENT_CHANGE')}}catch{$result.InspectionStatus='INCONCLUSIVE_CONCURRENT_CHANGE';$result.RecoveryConsideration='INCONCLUSIVE';$result.ReasonCodes+=@('P52_CONCURRENT_CHANGE')}
        }
    }
    if($result.InspectionStatus -ceq 'INCONCLUSIVE_CONCURRENT_CHANGE'){$result.HistoryState='INCONCLUSIVE';foreach($item in $result.Items){$item.RecoveryConsideration='INCONCLUSIVE'}}
    return $result
}
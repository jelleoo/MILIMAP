param([ValidateSet('Plan','History','Safety','All')][string]$Group='All')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$inspector=Join-Path $PSScriptRoot 'inspect-phase5-benefit-batch.ps1'
if(-not (Test-Path -LiteralPath $inspector)){throw 'RED: missing read-only batch operational inspector'}
. $inspector
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-location/test-support.ps1')
function Check($Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Equal($Actual,$Expected,[string]$Message){if($Actual -cne $Expected){throw "$Message (expected=$Expected actual=$Actual)"}}
function Inventory([string]$Path){
    return (@(Get-ChildItem -LiteralPath $Path -Force -Recurse | Sort-Object FullName | ForEach-Object {
        $digest=if($_.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)){'REPARSE'}elseif($_.PSIsContainer){'DIR'}else{try{(Get-FileHash -LiteralPath $_.FullName).Hash}catch [IO.IOException]{'LOCKED:'+$_.Exception.GetType().Name}}
        $_.FullName+':'+$digest
    }) -join '|')
}
$root=Join-Path ([IO.Path]::GetTempPath()) ('milimap-p52a-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$ids=@(('biz-'+('1'*32)),('biz-'+('2'*32)))
$rows=@(for($i=0;$i -lt 2;$i++){$r=New-ScopeTestRow -Name ('검사테스트 '+[char](65+$i)) -Building ([string](12+$i)) -Phone ('02-0000-00'+(12+$i));$r | Add-Member NoteProperty businessId $ids[$i];$r})
$csv=Join-Path $root 'canonical.csv';$rows | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding utf8
$store=New-HistoryStoreLayout -Root (Join-Path $root 'history')
$options=@{Store=$store;CanonicalCsvPath=$csv;BusinessIds=$ids;BatchWorkspaceRoot=(Join-Path $root 'batches');ObservedAt='2026-10-25T00:00:00Z';RepositoryRevision=([string](& git -C (Join-Path $PSScriptRoot '../..') rev-parse HEAD))}
$plan=New-Phase5BenefitBatchPlan @options;$options.BatchId=$plan.BatchId
$jsonOptions=@{};if((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')){$jsonOptions.DateKind='String'}
$probe=[pscustomobject]@{Audits=0;Traps=0;AfterMutation=$null}
function Inspect-Checked {
    param($Options,[AllowNull()][scriptblock]$DuringAudit=$null)
    $before=Inventory $root;$probe.Audits=0;$probe.Traps=0;$probe.AfterMutation=$null
    $originalAudit=(Get-Command Invoke-Phase3ReviewAudit).ScriptBlock
    $saved=@{}
    $blocked=@('New-HistoryStoreLayout','Invoke-Phase5BenefitBatch','Invoke-Phase5BenefitCycle','Restore-InternalPhase5BenefitCommittedCycle','Prepare-HistoryRun','Commit-HistoryRun','Rebuild-HistoryIndexes','Write-HistoryIndexEntry','Write-HistoryArtifact','Write-Phase5BenefitCycleOutput','Write-InternalPhase5BenefitBatchJson','Get-BenefitSourceDocument','Get-BenefitRunSourceDocument','Invoke-WebRequest','Invoke-RestMethod')
    $trap={ $probe.Traps++;throw 'INSPECTION_MUTATION_OR_NETWORK_ATTEMPT' }.GetNewClosure()
    foreach($name in $blocked){$command=Get-Command $name -ErrorAction SilentlyContinue;if($null -ne $command -and $command.CommandType -eq 'Function'){$saved[$name]=$command.ScriptBlock};Set-Item -Path ('Function:script:'+$name) -Value $trap}
    function Invoke-Phase3ReviewAudit {
        param($Store)
        $probe.Audits++
        $value=& $originalAudit -Store $Store
        if($null -ne $DuringAudit){& $DuringAudit;$probe.AfterMutation=Inventory $root}
        return $value
    }
    try{$returned=@(Inspect-Phase5BenefitBatch @Options)}finally{
        foreach($name in $blocked){if($saved.ContainsKey($name)){Set-Item -Path ('Function:script:'+$name) -Value $saved[$name]}else{Remove-Item -Path ('Function:script:'+$name)}}
    }
    Equal $returned.Count 1 'Inspector returns exactly one pipeline object'
    $result=$returned[0]
    Equal $probe.Traps 0 'All mutation/network entrypoints remain uncalled'
    Check ($probe.Audits -le 1) 'At most one global audit per inspection'
    Equal (Inventory $root) $(if($null -ne $probe.AfterMutation){$probe.AfterMutation}else{$before}) 'HTTP0 / History0 / Workspace0 / file-list and SHA inventories unchanged'
    Equal $result.ExecutionAuthorized $false 'Inspection never authorizes execution'
    foreach($item in $result.Items){Equal $item.ExecutionAuthorized $false 'Per-business assessment never authorizes execution'}
    Equal $result.ProductionAction NONE 'Production action always NONE'
    return $result
}
function Freeze-Plan($Value){[void][IO.Directory]::CreateDirectory((Split-Path -Parent $Value.PlanPath));Write-InternalPhase5BenefitBatchJson -Path $Value.PlanPath -Value $Value -Immutable}
function Rebind-Plan($Value){
    $Value.BatchId='batch-'+(Get-HistorySha256 -Text (ConvertTo-HistoryCanonicalJson $Value.PlanCore))
    $directory=Join-Path $Value.PlanCore.BatchWorkspaceRoot $Value.BatchId
    $Value.PlanPath=Join-Path $directory 'plan.json';$Value.GuardPath=Join-Path $directory '.execution.claim';$Value.OutputDirectory=Join-Path $directory 'items';$Value.SummaryPath=Join-Path $directory 'summary.json'
    foreach($item in $Value.Items){$item.RunId='run-p51-'+(Get-HistorySha256 -Text (ConvertTo-HistoryCanonicalJson ([pscustomobject]@{Purpose='P5_1_RUN_ID_V1';BatchId=$Value.BatchId;BusinessId=$item.BusinessId})))}
}
try{
    if($Group -cin @('Plan','All')){
        $r=Inspect-Checked $options
        Equal $r.PlanState MISSING 'Unstarted plan absence is not corruption'
        Equal $r.HistoryState VERIFIED 'Empty existing History is valid'
        Equal $r.CurrentCompatibility MATCH 'Current canonical/revision match'
        Equal ($r.Items.RunState -join ',') 'UNSTARTED,UNSTARTED' 'Both items remain unstarted'
        Check (-not (Test-Path -LiteralPath $options.BatchWorkspaceRoot)) 'Inspection does not create workspace'
        Freeze-Plan $plan
        $r=Inspect-Checked $options
        Equal $r.PlanState VALID ('Frozen builder plan accepted: '+($r.ReasonCodes -join ';'))
        Equal $r.RecoveryConsideration NOT_APPLICABLE 'Nothing committed to recover'
        $old=$plan | ConvertTo-Json -Depth 40 | ConvertFrom-Json @jsonOptions;$old.PlanCore.RepositoryRevision='a'*40;Rebind-Plan $old;Freeze-Plan $old
        $historical=$options.Clone();$historical.BatchId=$old.BatchId;$historical.RepositoryRevision='a'*40
        $r=Inspect-Checked $historical
        Equal $r.PlanState VALID 'Historical revision is not plan corruption'
        Equal $r.CurrentCompatibility MISMATCH 'Historical checkout mismatch is explicit'
        Equal $r.RecoveryConsideration BLOCKED 'Revision mismatch cannot recommend recovery'
        $original=[IO.File]::ReadAllBytes($csv)
        try{
            $changed=$rows | ConvertTo-Json -Depth 8 | ConvertFrom-Json @jsonOptions;$changed[0].할인정보='다른 합성 값';$changed | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding utf8
            $r=Inspect-Checked $options
            Equal $r.PlanState VALID 'Changed current input does not corrupt stored plan'
            Equal $r.CurrentCompatibility MISMATCH 'Canonical mismatch is separate'
        }finally{[IO.File]::WriteAllBytes($csv,$original)}
        $bytes=[IO.File]::ReadAllBytes($plan.PlanPath)
        try{
            $bad=$plan | ConvertTo-Json -Depth 40 | ConvertFrom-Json @jsonOptions;$bad.OutputDirectory=Join-Path $root 'never-follow-this';[IO.File]::WriteAllText($plan.PlanPath,(ConvertTo-HistoryCanonicalJson $bad))
            $r=Inspect-Checked $options
            Equal $r.PlanState INVALID 'Forged derived output path rejected'
            $oversized=[string]::new([char]' ',1048577);[IO.File]::WriteAllText($plan.PlanPath,$oversized)
            $r=Inspect-Checked $options
            Equal $r.PlanState INVALID 'Oversized plan rejected'
            Check (@($r.ReasonCodes) -ccontains 'P52_PLAN_TOO_LARGE') 'Size checked before JSON loading'
        }finally{[IO.File]::WriteAllBytes($plan.PlanPath,$bytes)}
        foreach($fault in @('run-ordinal-type','source-kind-type','empty-identity')){
            $badPlan=$plan | ConvertTo-Json -Depth 40 | ConvertFrom-Json @jsonOptions
            switch($fault){
                run-ordinal-type {$badPlan.Items[0].SourceRowNumber='2'}
                source-kind-type {$badPlan.PlanCore.Items[0].SourceKind=@('PUBLIC_OFFICIAL');Rebind-Plan $badPlan}
                empty-identity {$badPlan.PlanCore.Items[0].BusinessIdentity=[pscustomobject]@{};Rebind-Plan $badPlan}
            }
            if($badPlan.BatchId -ceq $plan.BatchId){$backup=[IO.File]::ReadAllBytes($plan.PlanPath);[IO.File]::WriteAllText($plan.PlanPath,(ConvertTo-HistoryCanonicalJson $badPlan))}
            else{Freeze-Plan $badPlan}
            try{
                $badOptions=$options.Clone();$badOptions.BatchId=$badPlan.BatchId
                $r=Inspect-Checked $badOptions
                Equal $r.PlanState INVALID "Malformed $fault is not a valid frozen plan"
            }finally{if($badPlan.BatchId -ceq $plan.BatchId){[IO.File]::WriteAllBytes($plan.PlanPath,$backup)}}
        }
        $bad=$options.Clone();$bad.CanonicalCsvPath=Join-Path $root 'sub/../canonical.csv'
        $r=Inspect-Checked $bad
        Equal $r.InspectionStatus BLOCKED 'Operator path traversal rejected'
        Equal $probe.Audits 0 'Unsafe operator paths stop before audit'
        $common=@([Management.Automation.PSCmdlet]::CommonParameters)+@([Management.Automation.PSCmdlet]::OptionalCommonParameters)
        Equal (@((Get-Command Inspect-Phase5BenefitBatch).Parameters.Keys | Where-Object {$_ -notin $common} | Sort-Object) -join ',') (@('Store','CanonicalCsvPath','BusinessIds','BatchWorkspaceRoot','BatchId','ObservedAt','RepositoryRevision' | Sort-Object) -join ',') 'Read-only public interface only'
        Write-Host 'P5-2A Plan PASS: missing/frozen/historical/input mismatch; unsafe/oversized rejected; HTTP0 / writes0'
    }
    if($Group -cin @('History','Safety','All')){
        $html='<table><tr><th>업소명</th><th>주소</th><th>전화번호</th><th>할인</th></tr>'
        foreach($row in $rows){$html+='<tr><td>'+$row.업소명+'</td><td>'+$row.소재지도로명주소+'</td><td>'+$row.업소전화번호+'</td><td>10% 할인</td></tr>'};$html+='</table>'
        $http={param($Uri);[pscustomobject]@{StatusCode=200;ContentType='text/html';Text=$html;Bytes=$null}}.GetNewClosure()
        $invocation=@{RepositoryStateProvider={ [pscustomobject]@{IsClean=$true} };RequestInvoker=$http}
        $committed=Invoke-Phase5BenefitBatch @options @invocation
        Equal $committed.Summary.CommittedCount 2 'Offline fixture has two real committed runs'
    }
    if($Group -cin @('History','All')){
        $r=Inspect-Checked $options
        Equal ($r.Items.RunState -join ',') 'COMMITTED,COMMITTED' ('Both committed observations verified: '+($r.ReasonCodes -join ';'))
        Equal ($r.Items.ObservationId -join '|') ($committed.Items.ObservationId -join '|') 'Exact persisted observation identities'
        Equal ($r.Items.ReviewKey -join '|') ($committed.Items.Review.ReviewKey -join '|') 'Original ReviewKeys preserved'
        Equal ($r.Items.FingerprintState -join ',') 'MATCH,MATCH' 'Input and execution fingerprints verified'
        Equal $r.RecoveryConsideration CONDITIONAL 'Verified committed recovery may only be considered'
        Equal $probe.Audits 1 'One committed-History audit for the whole inspection'
        Check ($null -eq $r.Items[0].Metrics) 'Unavailable historical work metrics stay null'
        $report=Join-Path $plan.OutputDirectory ($plan.Items[0].RunId+'.json');$reportBytes=[IO.File]::ReadAllBytes($report)
        try{
            [IO.File]::Delete($report)
            $r=Inspect-Checked $options
            Equal $r.Items[0].RunState COMMITTED 'Missing report does not lose committed authority'
            Equal $r.Items[0].DerivedReportState MISSING 'Missing derived report reported, never regenerated'
            Equal $r.Items[0].RecoveryConsideration CONDITIONAL 'Committed missing output may be recovered separately'
        }finally{[IO.File]::WriteAllBytes($report,$reportBytes)}
        $claim=Join-Path $store.TempRoot ('.p5-'+$plan.Items[0].RunId+'.claim');$stage=Join-Path $store.TempRoot $plan.Items[0].RunId
        try{
            [IO.File]::WriteAllText($claim,'P5_INTERRUPTED');[void][IO.Directory]::CreateDirectory($stage)
            $r=Inspect-Checked $options
            Equal $r.Items[0].ClaimState PRESENT 'Claim observed separately'
            Equal $r.Items[0].StagingState PRESENT 'Stage observed separately'
            Check $r.Items[0].ResidueBlocksExecute 'Residue blocks Execute'
            Equal $r.Items[0].RecoveryConsideration CONDITIONAL 'Committed residue does not erase recovery authority'
        }finally{[IO.File]::Delete($claim);[IO.Directory]::Delete($stage)}
        $abortArgs=$options.Clone();$abortArgs.Remove('BatchId');$abortArgs.ObservedAt='2026-10-25T00:30:00Z';$abortPlan=New-Phase5BenefitBatchPlan @abortArgs;$abortArgs.BatchId=$abortPlan.BatchId;Freeze-Plan $abortPlan
        $manifest=New-HistoryRunManifest -RunId $abortPlan.Items[0].RunId -StartedAt $abortArgs.ObservedAt -RepositoryRevision $abortArgs.RepositoryRevision -RequestedBusinessIds @($ids[0]) -FailedBusinessIds @($ids[0]) -ExecutionStatus FAILED -RunCommitStatus ABORTED
        $manifestPath=Get-HistoryRunManifestPath -Store $store -RunId $manifest.RunId
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $manifestPath));[IO.File]::WriteAllText($manifestPath,(ConvertTo-HistoryCanonicalJson $manifest))
        $r=Inspect-Checked $abortArgs
        Equal $r.Items[0].RunState ABORTED 'Valid ABORTED is not corrupt History'
        Equal $r.HistoryState VERIFIED 'ABORTED remains a legitimate terminal'
        $manifest.RunCommitStatus='PREPARED';[IO.File]::WriteAllText($manifestPath,(ConvertTo-HistoryCanonicalJson $manifest))
        $r=Inspect-Checked $abortArgs
        Equal $r.Items[0].RunState UNRESOLVED 'Nonterminal PREPARED is unresolved'
        Equal $r.RecoveryConsideration BLOCKED 'Ambiguous shared History blocks recovery consideration'
        [IO.File]::Delete($manifestPath);[IO.Directory]::Delete((Split-Path -Parent $manifestPath))
        Write-Host 'P5-2A History PASS: committed identities/fingerprints/ReviewKeys; missing report; residue; ABORTED vs unresolved; audit1'
    }
    if($Group -cin @('Safety','All')){
        # Basic derived identity includes the stable committed ReviewKey.
        $reportPath=Join-Path $plan.OutputDirectory ($plan.Items[0].RunId+'.json');$reportBytes=[IO.File]::ReadAllBytes($reportPath)
        try{
            $report=[Text.Encoding]::UTF8.GetString($reportBytes) | ConvertFrom-Json @jsonOptions
            $report.Review.ReviewKey='obs-'+('f'*32);[IO.File]::WriteAllText($reportPath,($report | ConvertTo-Json -Depth 35))
            $r=Inspect-Checked $options
            Equal $r.Items[0].RunState COMMITTED 'Bad derived identity never changes the committed History state'
            Equal $r.Items[0].DerivedReportState IDENTITY_CONFLICT 'Wrong derived ReviewKey is not a basic identity match'
            Equal $r.RecoveryConsideration BLOCKED 'Conflicting output requires examination'
        }finally{[IO.File]::WriteAllBytes($reportPath,$reportBytes)}
        foreach($active in @($false,$true)){
            $held=$null
            try{
                if($active){$held=[IO.File]::Open($plan.GuardPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}
                else{[IO.File]::WriteAllText($plan.GuardPath,'old is not safe');[IO.File]::SetLastWriteTimeUtc($plan.GuardPath,[DateTime]::UtcNow.AddYears(-1))}
                $r=Inspect-Checked $options
                Equal $r.GuardState PRESENT_BLOCKING 'Active and old-looking guards both block'
                Equal $r.RecoveryConsideration BLOCKED 'Age never authorizes guard cleanup or recovery'
            }finally{if($null -ne $held){$held.Dispose()};[IO.File]::Delete($plan.GuardPath)}
        }
        $obs=Read-HistoryObservation -Store $store -ObservationId $committed.Items[0].ObservationId
        $paths=@{
            manifest=(Get-HistoryRunManifestPath -Store $store -RunId $plan.Items[0].RunId)
            comparison=(Get-HistoryComparisonPath -Store $store -ComparisonId $committed.Items[0].Comparison.ComparisonId)
            artifact=(Join-Path $store.Root $obs.ArtifactReferences[0].RelativePath)
            index=(Get-HistoryIndexPath -Store $store -BusinessId $ids[0] -Domain BENEFIT)
        }
        foreach($kind in @('manifest','comparison','artifact','index')){
            $path=$paths[$kind];$original=[IO.File]::ReadAllBytes($path)
            try{
                [IO.File]::WriteAllText($path,'{broken')
                $r=Inspect-Checked $options
                Equal $r.HistoryState INVALID "$kind damage is fail-closed"
                Equal $r.RecoveryConsideration BLOCKED "$kind damage cannot recommend recovery"
            }finally{[IO.File]::WriteAllBytes($path,$original)}
        }
        # A historical selected run is still inspectable when a legitimate failed B is latest.
        $failure=Invoke-Phase5BenefitCycle -Store $store -Rows $rows -BusinessId $ids[0] -RunId 'run-inspection-failure-b' -ObservedAt '2026-10-25T01:00:00Z' -RepositoryRevision $options.RepositoryRevision -SourceRowNumberOffset 2 -OutputDirectory (Join-Path $root 'failure-output') -RepositoryStateProvider $invocation.RepositoryStateProvider -RequestInvoker {param($Uri);throw 'offline timeout'}
        Equal $failure.CommitCode COMMITTED 'Operational failure really commits'
        $index=Get-HistoryLatestEntry -Store $store -BusinessId $ids[0] -Domain BENEFIT
        Equal $index.LatestObservationId $failure.ObservationId 'Latest is noncomparable B'
        Equal $index.LatestComparableObservationId $committed.Items[0].ObservationId 'Comparable remains A'
        $r=Inspect-Checked $options
        Equal $r.HistoryState VERIFIED 'Legitimate B/A accepted'
        $indexPath=$paths.index;$indexBytes=[IO.File]::ReadAllBytes($indexPath)
        try{
            $index.LatestObservationId=$index.LatestComparableObservationId;[IO.File]::WriteAllText($indexPath,(ConvertTo-HistoryCanonicalJson $index))
            $r=Inspect-Checked $options
            Equal $r.HistoryState INVALID 'Corrupted A/A remains rejected by existing P5-1 validator'
            Equal $r.RecoveryConsideration BLOCKED 'Index rollback never authorizes recovery'
        }finally{[IO.File]::WriteAllBytes($indexPath,$indexBytes)}
        foreach($path in @($plan.PlanPath,$indexPath)){
            $original=[IO.File]::ReadAllBytes($path)
            try{
                $mutate={ [IO.File]::AppendAllText($path,' ') }.GetNewClosure()
                $r=Inspect-Checked $options -DuringAudit $mutate
                Equal $r.InspectionStatus INCONCLUSIVE_CONCURRENT_CHANGE 'Detected concurrent critical-file change is inconclusive'
                Equal $r.RecoveryConsideration INCONCLUSIVE 'Concurrent change cannot authorize recovery'
            }finally{[IO.File]::WriteAllBytes($path,$original)}
        }
        # Only fixture-owned paths are linked; the inspector must reject before following them.
        $decoy=Join-Path $root 'decoy';[void][IO.Directory]::CreateDirectory($decoy);[IO.File]::WriteAllText((Join-Path $decoy 'sentinel.txt'),'do not follow')
        $link=Join-Path $root 'linked-workspace'
        try{
            $linkType=if($IsWindows){'Junction'}else{'SymbolicLink'}
            [void](New-Item -ItemType $linkType -Path $link -Target $decoy)
            $unsafe=$options.Clone();$unsafe.BatchWorkspaceRoot=$link
            $r=Inspect-Checked $unsafe
            Equal $r.InspectionStatus BLOCKED 'Reparse operator path rejected'
            Equal $probe.Audits 0 'Reparse path never reaches History audit'
            Check (@($r.ReasonCodes) -ccontains 'P52_REPARSE_PATH') 'Reparse rejection is for the actual unsafe boundary'
        }finally{if(Test-Path -LiteralPath $link){[IO.Directory]::Delete($link)}}
        $link=Join-Path $store.ArtifactsRoot 'unsafe'
        try{
            [void](New-Item -ItemType $linkType -Path $link -Target $decoy)
            $r=Inspect-Checked $options
            Equal $r.HistoryState INVALID 'Internal History reparse path rejected'
            Equal $probe.Audits 0 'Audit never follows internal reparse targets'
            Check (@($r.ReasonCodes) -ccontains 'P52_REPARSE_PATH') 'Internal reparse detection is the actual rejection reason'
        }finally{if(Test-Path -LiteralPath $link){[IO.Directory]::Delete($link)}}
        # An audit/reread difference is detected even if the first file stamp follows the change.
        $path=$paths.comparison;$original=[IO.File]::ReadAllBytes($path)
        try{
            $comparison=[IO.File]::ReadAllText($path) | ConvertFrom-Json @jsonOptions
            $comparison.ChangeCandidates=@()
            Assert-ObservationComparison $comparison
            $changedComparisonText=ConvertTo-HistoryCanonicalJson $comparison
            $mutate={ [IO.File]::WriteAllText($path,$changedComparisonText) }.GetNewClosure()
            $r=Inspect-Checked $options -DuringAudit $mutate
            Equal $r.InspectionStatus INCONCLUSIVE_CONCURRENT_CHANGE ('Detected audit/reread mismatch is concurrent change, not History damage: '+($r.ReasonCodes -join ';'))
            Equal $r.HistoryState INCONCLUSIVE 'Different valid read versions do not establish History corruption'
            Equal $r.RecoveryConsideration INCONCLUSIVE 'Audit/reread mismatch never recommends recovery'
            foreach($item in $r.Items){Equal $item.RecoveryConsideration INCONCLUSIVE 'Every item inherits the inconclusive inspection'}
        }finally{[IO.File]::WriteAllBytes($path,$original)}
        Write-Host 'P5-2A Safety PASS: guards/corruption/index rollback/concurrent mutation/reparse; HTTP0 / History0 / Workspace0'
    }
    if($Group -cin @('History','All')){
        $frozenBytes=[IO.File]::ReadAllBytes($plan.PlanPath);$csvBytes=[IO.File]::ReadAllBytes($csv)
        try{
            [IO.File]::Delete($plan.PlanPath)
            $changed=$rows | ConvertTo-Json -Depth 10 | ConvertFrom-Json @jsonOptions;$changed[0].할인정보='변경된 합성 입력';$changed | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding utf8
            $r=Inspect-Checked $options
            Equal $r.PlanState MISSING 'Missing old plan is not corruption'
            Equal $r.CurrentCompatibility MISMATCH 'Current input belongs to another BatchId'
            Equal ($r.Items.RunId -join '|') ($plan.Items.RunId -join '|') 'Missing plan must retain requested BatchId RunIds'
            Equal ($r.Items.RunState -join ',') 'COMMITTED,COMMITTED' 'Requested old committed runs must not become unstarted'
            Equal ($r.Items.ObservationId -join '|') ($committed.Items.ObservationId -join '|') 'Requested old observations retained'
            Check ($null -eq $r.Items[0].SourceRowNumber -and $r.Items[0].FingerprintState -ceq 'NOT_VERIFIED') 'Unknown frozen ordinals/fingerprints are not copied from another plan'
            Equal $r.RecoveryConsideration BLOCKED 'Missing plan and input mismatch never recommend recovery'
            $newOptions=$options.Clone();$newOptions.Remove('BatchId');$newPlan=New-Phase5BenefitBatchPlan @newOptions;$newOptions.BatchId=$newPlan.BatchId
            $other=Invoke-Phase5BenefitBatch @newOptions @invocation
            Equal $other.Summary.CommittedCount 2 'Different current batch really exists in shared History'
            $r=Inspect-Checked $options
            Equal ($r.Items.RunId -join '|') ($plan.Items.RunId -join '|') 'Other committed batch cannot replace requested RunIds'
            Equal ($r.Items.ObservationId -join '|') ($committed.Items.ObservationId -join '|') 'Other batch committed observations cannot leak into requested batch'
            Equal ($r.Items.ReviewKey -join '|') ($committed.Items.Review.ReviewKey -join '|') 'Requested old ReviewKeys retained'
        }finally{[IO.File]::WriteAllBytes($plan.PlanPath,$frozenBytes);[IO.File]::WriteAllBytes($csv,$csvBytes)}
        Write-Host 'P5-2A MissingPlanIdentity PASS: requested RunIds/observations retained; other batch excluded; unknown frozen fields remain unavailable'
    }
}finally{
    $full=[IO.Path]::GetFullPath($root)
    if(-not $full.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or -not ([IO.Path]::GetFileName($full)).StartsWith('milimap-p52a-')){throw 'UNSAFE_TEST_CLEANUP'}
    if(Test-Path -LiteralPath $full){Remove-Item -LiteralPath $full -Recurse -Force}
}
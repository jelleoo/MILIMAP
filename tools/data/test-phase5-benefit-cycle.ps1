param([ValidateSet('Base','Recovery','Safety','Parity','All')][string]$Group='All')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$runner=Join-Path $PSScriptRoot 'invoke-phase5-benefit-cycle.ps1'
if(-not (Test-Path -LiteralPath $runner)){throw 'RED: missing manual Benefit cycle runner'}
. $runner
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-location/test-support.ps1')
function Check($Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Equal($Actual,$Expected,[string]$Message){if($Actual -cne $Expected){throw "$Message (expected=$Expected actual=$Actual)"}}
function Copy-TestRow($Row){return $Row | ConvertTo-Json | ConvertFrom-Json}
$root=Join-Path ([IO.Path]::GetTempPath()) ('milimap-p50-'+[guid]::NewGuid().ToString('N'))
$id='biz-0123456789abcdef0123456789abcdef'
$row=New-ScopeTestRow
$row | Add-Member NoteProperty businessId $id
$html=Get-ScopeTestHtml
$requests=[pscustomobject]@{Count=0}
$http={param($Uri);$requests.Count++;[pscustomobject]@{StatusCode=200;ContentType='text/html';Text=$html;Bytes=$null}}.GetNewClosure()
$store=New-HistoryStoreLayout -Root (Join-Path $root 'history')
$args50=@{Store=$store;Rows=@($row);BusinessId=$id;SourceRowNumberOffset=2;ObservedAt='2026-10-24T00:00:00Z';RepositoryRevision=('a'*40);OutputDirectory=(Join-Path $root 'output');RequestInvoker=$http;RepositoryStateProvider={ [pscustomobject]@{IsClean=$true} }}
try{
    if($Group -cin @('Base','All')){
        foreach($fault in @('missing-id','duplicate-id','no-url','website','sns','local','csv','hwp','bad-run')){
            $a=$args50.Clone();$bad=Copy-TestRow $row
            switch($fault){
                missing-id {$a.BusinessId='biz-11111111111111111111111111111111'}
                duplicate-id {$a.Rows=@($bad,(Copy-TestRow $bad))}
                no-url {$bad.출처URL='';$a.Rows=@($bad)}
                website {$bad.출처유형='업체 공식 홈페이지';$a.Rows=@($bad)}
                sns {$bad.출처유형='업체 공식 SNS';$a.Rows=@($bad)}
                local {$bad.출처URL='http://intranet/';$a.Rows=@($bad)}
                csv {$bad.출처URL='https://city.example.go.kr/file.csv';$a.Rows=@($bad)}
                hwp {$bad.출처URL='https://city.example.go.kr/file.hwp';$a.Rows=@($bad)}
                bad-run {}
            }
            $runId=if($fault -ceq 'bad-run'){'../escape'}else{'run-invalid-'+$fault}
            $before=$requests.Count
            $r=Invoke-Phase5BenefitCycle @a -RunId $runId
            Equal $r.Status BLOCKED "Invalid $fault blocked"
            Equal $requests.Count $before "Invalid $fault performs no fetch"
            Check ($null -eq $r.Review -and $null -eq $r.Metrics) 'Invalid selection cannot fabricate review or metrics'
        }
        foreach($unsafeRunId in @('run-dot.','con','aux','nul','prn','com1','lpt9','con.txt','com2.log')){
            $before=$requests.Count
            $filesBefore=@(Get-ChildItem -LiteralPath $store.Root -Recurse -File -Force | Sort-Object FullName | ForEach-Object {"$($_.FullName):$((Get-FileHash -LiteralPath $_.FullName).Hash)"})
            $invalidRun=Invoke-Phase5BenefitCycle @args50 -RunId $unsafeRunId
            Equal $invalidRun.Status BLOCKED "Windows-unsafe RunId $unsafeRunId rejected before execution"
            Check (@($invalidRun.Reasons) -contains 'P5_RUN_ID_INVALID') 'Unsafe filename has an explicit identity rejection'
            Equal $requests.Count $before "Windows-unsafe RunId $unsafeRunId fetch0"
            $filesAfter=@(Get-ChildItem -LiteralPath $store.Root -Recurse -File -Force | Sort-Object FullName | ForEach-Object {"$($_.FullName):$((Get-FileHash -LiteralPath $_.FullName).Hash)"})
            Equal ($filesAfter -join ',') ($filesBefore -join ',') 'Unsafe RunId cannot create or change History files'
        }
        $first=Invoke-Phase5BenefitCycle @args50 -RunId 'run-first'
        Equal $first.CommitCode COMMITTED 'First cycle commits'
        Equal $first.OperationalStatus COMPLETE 'First cycle operational status from observation'
        Equal $first.SourceRowNumber 2 'Canonical row number retained'
        Equal $first.BenefitState NEEDS_VERIFICATION 'No lifecycle inference'
        Equal $first.Review.ReviewRoute RECORD_ONLY 'Baseline route uses actual comparator'
        Equal $first.Metrics.ExternalFetchCount 1 'One physical request'
        Equal $first.Metrics.ParseCount 1 'One real parse'
        Equal $first.Metrics.ExtractionCount 1 'One real extraction'
        Equal $first.Metrics.EvaluationCount 1 'One real evaluation'
        Equal $first.OutputStatus WRITTEN 'Derived result written once'
        Equal $first.ProductionAction NONE 'No production action'
        Equal $requests.Count 1 'Invalid controls did not spend requests'
        Write-Host 'P5-0 Base PASS: first fetch1 / parse1 / extraction1 / evaluation1 / COMMITTED; invalid fetch0'
    }
    if($Group -cin @('Recovery','All')){
        $one=Invoke-Phase5BenefitCycle @args50 -RunId 'run-recovery-first'
        Equal $one.CommitCode COMMITTED 'Recovery baseline committed'
        $before=$requests.Count
        $historyBefore=@(Get-ChildItem -LiteralPath $store.Root -Recurse -File | Sort-Object FullName | ForEach-Object {"$($_.FullName):$((Get-FileHash -LiteralPath $_.FullName).Hash)"})
        $again=Invoke-Phase5BenefitCycle @args50 -RunId 'run-recovery-first'
        Equal $requests.Count $before 'Committed same RunId cannot refetch'
        Check $again.Recovered "Committed run recovered read-only: $($again.Code) $($again.Reasons -join ',')"
        Equal $again.Review.ReviewKey $one.Review.ReviewKey 'Same committed event keeps same ReviewKey'
        Equal $again.OutputStatus PRESERVED 'No duplicate output on reentry'
        Check ($null -eq $again.Metrics) 'Unpersisted execution metrics must remain unknown on recovery'
        $historyAfter=@(Get-ChildItem -LiteralPath $store.Root -Recurse -File | Sort-Object FullName | ForEach-Object {"$($_.FullName):$((Get-FileHash -LiteralPath $_.FullName).Hash)"})
        Equal ($historyAfter -join ',') ($historyBefore -join ',') 'Committed recovery cannot write History'

        $unchanged=Invoke-Phase5BenefitCycle @args50 -RunId 'run-unchanged'
        Equal $unchanged.CommitCode COMMITTED 'Fresh unchanged run commits a fresh observation'
        Equal $unchanged.Metrics.ExternalFetchCount 1 'New RunId still fetches current source once'
        Equal $unchanged.Metrics.ParseCount 0 'Eligible new RunId avoids parsing'
        Equal $unchanged.Metrics.ExtractionCount 0 'Eligible new RunId avoids extraction'
        Equal $unchanged.Metrics.EvaluationCount 0 'Eligible new RunId avoids evaluation'
        Equal $unchanged.Metrics.ReuseApplied 1 'Eligible reuse actually applies'
        Equal $unchanged.Review.ReviewRoute RECORD_ONLY 'Unchanged result routed by comparator'
        Equal @($unchanged.Comparison.ChangeCandidates).Count 0 'No apparent-equality review override'
        $old=Invoke-Phase5BenefitCycle @args50 -RunId 'run-recovery-first'
        Equal $old.ObservationId $one.ObservationId 'Recovery selects supplied RunId, not newer latest index'

        $changedHtml=$html.Replace('10% 할인','20% 할인')
        $changedArgs=$args50.Clone()
        $changedArgs.RequestInvoker={param($Uri);$requests.Count++;[pscustomobject]@{StatusCode=200;ContentType='text/html';Text=$changedHtml;Bytes=$null}}.GetNewClosure()
        $changed=Invoke-Phase5BenefitCycle @changedArgs -RunId 'run-changed'
        Equal $changed.Review.ReviewRoute HUMAN_DOMAIN_REVIEW 'Actual material change preserves existing ReviewRoute'
        Check (@($changed.Comparison.ChangeCandidates) -contains 'BENEFIT_CHANGE_SUSPECTED') 'Domain comparison is retained'

        $before=$requests.Count;$different=Copy-TestRow $row;$different.할인정보='33% 할인'
        $badArgs=$args50.Clone();$badArgs.Rows=@($different)
        $bad=Invoke-Phase5BenefitCycle @badArgs -RunId 'run-recovery-first'
        Check ($null -eq $bad.Review -and $bad.Status -ceq 'BLOCKED') 'RunId cannot be rebound to changed input'
        Equal $requests.Count $before 'Input mismatch recovery fetch0'

        $outputTarget=Join-Path $args50.OutputDirectory 'run-output-failure.json'
        [void][IO.Directory]::CreateDirectory($outputTarget)
        $failedOutput=Invoke-Phase5BenefitCycle @args50 -RunId 'run-output-failure'
        Equal $failedOutput.CommitCode COMMITTED 'Output failure cannot erase successful commit'
        Equal $failedOutput.OutputStatus FAILED 'Real filesystem output failure is visible'
        [IO.Directory]::Delete($outputTarget)
        $before=$requests.Count
        $recovered=Invoke-Phase5BenefitCycle @args50 -RunId 'run-output-failure'
        Equal $recovered.CommitCode COMMITTED 'Missing view reconstructed from committed records'
        Equal $recovered.OutputStatus WRITTEN 'Recovered view materialized once'
        Equal $requests.Count $before 'Output recovery does not rerun work'
        Check ($null -eq $recovered.Metrics -and $null -ne $recovered.Review) 'Recovered Review known but transient metrics unknown'
        Equal @((Get-ChildItem -LiteralPath $args50.OutputDirectory -Filter 'run-output-failure.json' -File)).Count 1 'One stable recovered output'
        Write-Host 'P5-0 Recovery PASS: same RunId fetch0; fresh unchanged fetch1 / parse0 / reuse1; output recovery metrics=null; material route preserved'
    }
    if($Group -cin @('Safety','All')){
        # Unix dotfiles and Windows Hidden claims must preserve failed-attempt reasons.
        $hiddenClaim=Join-Path $store.TempRoot '.p5-run-hidden-claim.claim'
        [IO.File]::WriteAllText($hiddenClaim,'WRITER_LOCKED')
        [IO.File]::SetAttributes($hiddenClaim,([IO.File]::GetAttributes($hiddenClaim) -bor [IO.FileAttributes]::Hidden))
        $before=$requests.Count
        $hidden=Invoke-Phase5BenefitCycle @args50 -RunId 'run-hidden-claim'
        Equal $hidden.CommitCode WRITER_LOCKED 'Hidden prior claim preserves the actual failure reason'
        Equal $hidden.Status BLOCKED 'Hidden prior claim cannot restart work'
        Equal $requests.Count $before 'Hidden prior claim fetch0'
        # Check the path guard directly so a regression cannot write production data.
        $primaryRoot=Split-Path -Parent (& git -C (Join-Path $PSScriptRoot '../..') rev-parse --path-format=absolute --git-common-dir)
        $rejected=$false
        try{Assert-Phase5BenefitExternalPath (Join-Path $primaryRoot 'data/canonical') | Out-Null}catch{$rejected=$true}
        Check $rejected 'Primary checkout protected paths are not external merely because runner is in a worktree'
        $overlapArgs=$args50.Clone()
        $overlapStore=New-HistoryStoreLayout -Root (Join-Path $root 'overlap-history')
        $overlapArgs.Store=$overlapStore;$overlapArgs.OutputDirectory=$overlapStore.ObservationsRoot
        $before=$requests.Count
        $overlap=Invoke-Phase5BenefitCycle @overlapArgs -RunId 'run-output-overlap'
        Equal $overlap.Status BLOCKED 'Derived reports cannot enter authoritative History directories'
        Equal $requests.Count $before 'History/output overlap rejected before fetch'
        Equal @(Get-ChildItem -LiteralPath $overlapStore.Root -Recurse -File).Count 0 'Overlap creates no History or derived files'
        foreach($state in @('staging','ambiguous-terminal','aborted')){
            $rid='run-'+$state;$before=$requests.Count
            if($state -ceq 'staging'){[void][IO.Directory]::CreateDirectory((Join-Path $store.TempRoot $rid))}
            else{
                $path=Get-HistoryRunManifestPath -Store $store -RunId $rid
                [void][IO.Directory]::CreateDirectory((Split-Path -Parent $path))
                if($state -ceq 'aborted'){
                    $manifest=New-HistoryRunManifest -RunId $rid -StartedAt $args50.ObservedAt -CompletedAt $args50.ObservedAt -RepositoryRevision $args50.RepositoryRevision -RequestedBusinessIds @($id) -FailedBusinessIds @($id) -ExecutionStatus FAILED -RunCommitStatus ABORTED
                    [IO.File]::WriteAllText($path,($manifest | ConvertTo-Json -Depth 10))
                }
            }
            $r=Invoke-Phase5BenefitCycle @args50 -RunId $rid
            Equal $requests.Count $before "Existing $state fetch0"
            Equal $r.Status BLOCKED "Existing $state stays blocked"
            Check ($null -eq $r.Review -and $null -eq $r.Metrics) 'Noncommitted state has no authoritative Review/work metrics'
            if($state -ceq 'aborted'){Equal $r.CommitCode ABORTED 'ABORTED stays distinguishable'}
        }
        # Separate store: ambiguous states above deliberately remain untouched.
        $safeArgs=$args50.Clone();$safeStore=New-HistoryStoreLayout -Root (Join-Path $root 'safety-history');$safeArgs.Store=$safeStore
        $collision=[pscustomobject]@{Inner=$null;OuterCount=0;InnerRequests=0;Error=$null}
        $innerArgs=$safeArgs.Clone()
        $innerArgs.RequestInvoker={param($Uri);$collision.InnerRequests++;throw 'NESTED_FETCH_FORBIDDEN'}.GetNewClosure()
        $outerArgs=$safeArgs.Clone()
        # Keep this immediate nested call in the test's script session state:
        # GetNewClosure creates a dynamic module that cannot resolve local functions
        # when CI invokes this test via &, even though -File happens to expose them.
        $outerArgs.RequestInvoker={param($Uri);$collision.OuterCount++;try{$collision.Inner=Invoke-Phase5BenefitCycle @innerArgs -RunId 'run-concurrent'}catch{$collision.Error=$_.Exception.Message;throw};[pscustomobject]@{StatusCode=200;ContentType='text/html';Text=$html;Bytes=$null}}
        $outer=Invoke-Phase5BenefitCycle @outerArgs -RunId 'run-concurrent'
        Equal $outer.CommitCode COMMITTED 'Owner launch completes'
        Equal $collision.InnerRequests 0 'Overlapping same-RunId launch never fetches'
        Check ($null -ne $collision.Inner -and $null -ne $collision.Inner.PSObject.Properties['Code']) "Concurrent attempt must return one cycle result: $($collision.Inner | ConvertTo-Json -Depth 8 -Compress); error=$($collision.Error)"
        Equal $collision.Inner.Code P5_RUN_ACTIVE 'Concurrent collision is explicit'
        Check ($null -eq $collision.Inner.Review) 'Concurrent losing attempt has no Review'
        Equal $collision.OuterCount 1 'Owner never retries'

        $lock=[IO.File]::Open((Join-Path $safeStore.Root '.writer-lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        try{$locked=Invoke-Phase5BenefitCycle @safeArgs -RunId 'run-writer-locked'}finally{$lock.Dispose()}
        Equal $locked.CommitCode WRITER_LOCKED 'Existing writer lock code preserved'
        Equal $locked.Metrics.ExternalFetchCount 1 'Writer lock does not enclose fetch'
        Equal $locked.Metrics.ParseCount 0 'Identical baseline uses existing reuse even when commit is locked'
        Check ($null -eq $locked.Review -and $null -eq $locked.Comparison) 'Uncommitted reused observation/comparison not published as Review'
        $before=$requests.Count
        $lockedAgain=Invoke-Phase5BenefitCycle @safeArgs -RunId 'run-writer-locked'
        Equal $lockedAgain.CommitCode WRITER_LOCKED 'Blocked prior attempt keeps its reason'
        Equal $requests.Count $before 'No silent retry of writer-locked attempt'

        $failedArgs=$safeArgs.Clone()
        $failedArgs.RequestInvoker={param($Uri);$requests.Count++;throw 'synthetic timeout'}.GetNewClosure()
        $failed=Invoke-Phase5BenefitCycle @failedArgs -RunId 'run-fetch-failed'
        Equal $failed.CommitCode COMMITTED 'Operational failure can be recorded as committed history'
        Equal $failed.OperationalStatus FAILED 'Commit success is not operational success'
        Check ($failed.BenefitState -cne 'ENDED' -and $failed.BenefitState -cne 'ACTIVE') 'Fetch failure cannot produce lifecycle success'
        Equal $failed.Review.ReviewRoute OPERATIONAL_DIAGNOSTIC 'Failure routes to diagnostics'
        Check (@($failed.Comparison.ChangeCandidates | Where-Object {$_ -cin @('BENEFIT_ABSENCE_SUSPECTED','BENEFIT_CHANGE_SUSPECTED')}).Count -eq 0) 'No absence/change from fetch failure'
        Equal $failed.Metrics.ParseCount 0 'Fetch failure parser0'
        Equal $failed.Metrics.ExtractionCount 0 'Fetch failure extraction0'

        $unsupportedArgs=$safeArgs.Clone()
        $unsupportedArgs.RequestInvoker={param($Uri);$requests.Count++;[pscustomobject]@{StatusCode=200;ContentType='text/csv';Text='unusable';Bytes=$null}}.GetNewClosure()
        $unsupported=Invoke-Phase5BenefitCycle @unsupportedArgs -RunId 'run-response-unsupported'
        Check ($unsupported.OperationalStatus -cne 'COMPLETE' -and $unsupported.BenefitState -cne 'ENDED') 'Unknown response format stays fail-closed'
        Equal $unsupported.Metrics.ParseCount 0 'Unsupported response never parsed as HTML'
        Equal $unsupported.ProductionAction NONE 'Unsupported response has no production action'

        $originalCommit=(Get-Command Commit-HistoryRun).ScriptBlock
        $race=[pscustomobject]@{Injected=$false;CompetingId='obs-cccccccccccccccccccccccccccccccc'}
        function Commit-HistoryRun {
            param($Store,$PreparedRun,$ExpectedBaselines)
            if($PreparedRun.RunManifest.RunId -ceq 'run-cas-moved' -and -not $race.Injected){
                $race.Injected=$true
                $baseline=Get-BenefitIncrementalBaseline -Store $Store -BusinessId $id
                $competing=$baseline.Observation | Select-Object *
                $competing.ObservationId=$race.CompetingId;$competing.RunId='run-competing'
                $manifest=New-HistoryRunManifest -RunId 'run-competing' -StartedAt $args50.ObservedAt -RepositoryRevision $args50.RepositoryRevision -RequestedBusinessIds @($id) -CompletedBusinessIds @($id) -ExecutionStatus COMPLETE -RunCommitStatus PREPARED
                $prepared=Prepare-HistoryRun -Store $Store -RunManifest $manifest -Observations @($competing)
                $won=& $originalCommit -Store $Store -PreparedRun $prepared -ExpectedBaselines @{($id+'|BENEFIT')=$baseline.Observation.ObservationId}
                Equal $won.Code COMMITTED 'Competing baseline really commits'
            }
            return & $originalCommit -Store $Store -PreparedRun $PreparedRun -ExpectedBaselines $ExpectedBaselines
        }
        try{$moved=Invoke-Phase5BenefitCycle @safeArgs -RunId 'run-cas-moved'}finally{Set-Item Function:Commit-HistoryRun $originalCommit}
        Equal $moved.CommitCode BASELINE_MOVED 'Real CAS movement preserved'
        Check $moved.RetryRequired 'CAS movement requests explicit retry only'
        Equal $moved.Metrics.ExternalFetchCount 1 'CAS movement fetch1, no automatic retry'
        Equal $moved.Metrics.ArtifactWrites 0 'CAS failure has no authoritative artifact writes'
        Check ($null -eq $moved.Review -and $null -eq $moved.Comparison) 'CAS failure cannot expose stale Review'
        $latest=Get-HistoryLatestEntry -Store $safeStore -BusinessId $id -Domain BENEFIT -ComparableOnly
        Equal $latest.LatestComparableObservationId $race.CompetingId 'Competing baseline remains authoritative'
        $before=$requests.Count
        $movedAgain=Invoke-Phase5BenefitCycle @safeArgs -RunId 'run-cas-moved'
        Equal $movedAgain.CommitCode BASELINE_MOVED 'CAS failed attempt remains distinguishable on reentry'
        Equal $requests.Count $before 'No silent retry after CAS rejection'
        Write-Host 'P5-0 Safety PASS: overlapping RunId blocked before fetch; writer/CAS fetch1; no stale Review; failure parse0 / extraction0; ProductionAction NONE'
    }
    if($Group -cin @('Parity','All')){
        $store=New-HistoryStoreLayout -Root (Join-Path $root 'parity-history');$args50=$args50.Clone();$args50.Store=$store
        $badRow=Copy-TestRow $row;$badRow.출처URL=''
        $badArgs=$args50.Clone();$badArgs.Rows=@($badRow)
        $before=$requests.Count
        $bad=Invoke-Phase5BenefitCycle @badArgs -RunId 'run-parity-invalid'
        Equal $bad.Code P5_PREFLIGHT_REJECTED 'Original preflight error code preserved'
        Equal $bad.SourceRowNumber 2 'Selected row identity survives later preflight rejection'
        Equal $requests.Count $before 'Characterization invalid source fetch0'
        $common=@([Management.Automation.PSCmdlet]::CommonParameters)+@([Management.Automation.PSCmdlet]::OptionalCommonParameters);$names=@((Get-Command Invoke-Phase5BenefitCycle).Parameters.Keys | Where-Object {$_ -notin $common} | Sort-Object)
        $public=@('Store','Rows','BusinessId','RunId','ObservedAt','RepositoryRevision','OutputDirectory','RepositoryStateProvider','SourceRowNumberOffset','RequestInvoker' | Sort-Object)
        Equal ($names -join '|') ($public -join '|') 'Existing P5-0 public interface unchanged'
        $preArgs=$args50.Clone();$preArgs.Remove('RequestInvoker');$preArgs.Remove('RepositoryStateProvider')
        $historyBefore=@(Get-ChildItem -LiteralPath $store.Root -File -Recurse -Force | Sort-Object FullName | ForEach-Object {"$($_.FullName):$((Get-FileHash -LiteralPath $_.FullName).Hash)"})
        $input=Resolve-InternalPhase5BenefitInput @preArgs -RunId 'run-parity'
        Equal $input.SourceRowNumber 2 'Shared preflight retains canonical ordinal'
        Equal $input.Candidate.SourceKind PUBLIC_OFFICIAL 'Shared preflight reuses official-source policy'
        Equal $requests.Count $before 'Shared preflight fetch0'
        Equal (@(Get-ChildItem -LiteralPath $store.Root -File -Recurse -Force | Sort-Object FullName | ForEach-Object {"$($_.FullName):$((Get-FileHash -LiteralPath $_.FullName).Hash)"}) -join '|') ($historyBefore -join '|') 'Shared preflight has no History writes'
        $one=Invoke-Phase5BenefitCycle @args50 -RunId 'run-parity'
        Equal $one.CommitCode COMMITTED 'Parity baseline commits'
        $before=$requests.Count
        $historyBefore=@(Get-ChildItem -LiteralPath $store.Root -File -Recurse -Force | Sort-Object FullName | ForEach-Object {"$($_.FullName):$((Get-FileHash -LiteralPath $_.FullName).Hash)"})
        $view=$one | Select-Object *
        $recovered=Restore-InternalPhase5BenefitCommittedCycle -Store $store -ResolvedInput $input -Result $view
        Equal $recovered.Review.ReviewKey $one.Review.ReviewKey 'Internal recovery preserves original ReviewKey'
        Check ($recovered.Recovered -and $null -eq $recovered.Metrics) 'Internal recovery never claims historical work metrics'
        Equal $requests.Count $before 'Internal recovery never fetches'
        Equal (@(Get-ChildItem -LiteralPath $store.Root -File -Recurse -Force | Sort-Object FullName | ForEach-Object {"$($_.FullName):$((Get-FileHash -LiteralPath $_.FullName).Hash)"}) -join '|') ($historyBefore -join '|') 'Internal recovery never writes History'
        $pending=Resolve-InternalPhase5BenefitInput @preArgs -RunId 'run-parity-pending'
        $rejected=$false
        try{Restore-InternalPhase5BenefitCommittedCycle -Store $store -ResolvedInput $pending -Result ($one | Select-Object *) | Out-Null}catch{$rejected=$true}
        Check $rejected 'Recovery-only helper rejects a missing committed run without executing it'
        Equal $requests.Count $before 'Missing committed run recovery fetch0'
        Write-Host 'P5-0 Parity PASS: public interface/error/ordinal preserved; internal preflight read-only; recovery never executes'
    }
}finally{
    $fullRoot=[IO.Path]::GetFullPath($root)
    if(-not $fullRoot.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or -not ([IO.Path]::GetFileName($fullRoot)).StartsWith('milimap-p50-')){throw 'UNSAFE_TEST_CLEANUP'}
    if(Test-Path -LiteralPath $fullRoot){Remove-Item -LiteralPath $fullRoot -Recurse -Force}
}

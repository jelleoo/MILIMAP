param([ValidateSet('Plan','Execution','Recovery','Safety','Network','All')][string]$Group='All')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$runner=Join-Path $PSScriptRoot 'invoke-phase5-benefit-batch.ps1'
if(-not (Test-Path -LiteralPath $runner)){throw 'RED: missing bounded Benefit batch runner'}
. $runner
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-location/test-support.ps1')
function Check($Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Equal($Actual,$Expected,[string]$Message){if($Actual -cne $Expected){throw "$Message (expected=$Expected actual=$Actual)"}}
function Reject([scriptblock]$Action,[string]$Message){$caught=$false;try{& $Action | Out-Null}catch{$caught=$true};Check $caught $Message}
function Inventory([string]$Path){return (@(Get-ChildItem -LiteralPath $Path -Recurse -File -Force | Sort-Object FullName | ForEach-Object {"$($_.FullName):$(if($_.Name -ceq '.writer-lock'){'LOCK'}else{(Get-FileHash -LiteralPath $_.FullName).Hash})"}) -join '|')}
$root=Join-Path ([IO.Path]::GetTempPath()) ('milimap-p51-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$ids=@(1..5 | ForEach-Object { 'biz-'+(([string]$_)*32) })
$rows=@(for($i=0;$i -lt 5;$i++){$r=New-ScopeTestRow -Name ('배치테스트 '+[char](65+$i)) -Building ([string](12+$i)) -Phone ('02-0000-00'+(12+$i));$r | Add-Member NoteProperty businessId $ids[$i];$r})
$csv=Join-Path $root 'canonical.csv';$rows | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding utf8
$html='<table><tr><th>업소명</th><th>주소</th><th>전화번호</th><th>할인</th></tr>'
foreach($r in $rows){$html+='<tr><td>'+$r.업소명+'</td><td>'+$r.소재지도로명주소+'</td><td>'+$r.업소전화번호+'</td><td>10% 할인</td></tr>'};$html+='</table>'
$requests=[pscustomobject]@{Urls=[Collections.Generic.List[string]]::new()}
$http={param($Uri);$requests.Urls.Add([string]$Uri);[pscustomobject]@{StatusCode=200;ContentType='text/html';Text=$html;Bytes=$null}}.GetNewClosure()
$store=New-HistoryStoreLayout -Root (Join-Path $root 'history')
$args51=@{CanonicalCsvPath=$csv;BusinessIds=@($ids[0],$ids[2],$ids[4]);Store=$store;BatchWorkspaceRoot=(Join-Path $root 'batches');ObservedAt='2026-10-25T00:00:00Z';RepositoryRevision=([string](& git -C (Join-Path $PSScriptRoot '../..') rev-parse HEAD))}
$invokeArgs=@{RepositoryStateProvider={ [pscustomobject]@{IsClean=$true} };RequestInvoker=$http}
try{
    if($Group -cin @('Network','All')){
        Check ((Get-Command New-Phase5BenefitBatchPlan).Parameters.ContainsKey('NetworkPolicy')) 'RED: missing explicit optional NetworkPolicy on plan creation'
        $policy=New-Phase5BenefitNetworkPolicy -AllowedHttpsHosts @('city.example.go.kr','open.mma.go.kr') -MaxPhysicalAttempts 0
        $a=$args51.Clone();$a.Store=New-HistoryStoreLayout -Root (Join-Path $root 'strict-zero-history');$a.BatchWorkspaceRoot=Join-Path $root 'strict-zero-batches';$a.NetworkPolicy=$policy
        $originalIdentity=(Get-Command Get-Phase5NetworkTransportIdentity).ScriptBlock
        # All integration I/O below is synthetic. Qualification itself is independently tested by the transport tests.
        function Get-Phase5NetworkTransportIdentity {[pscustomobject]@{Profile='P52_HTTP11_SINGLE_CONNECTION_V1';Framework='.NET 10.0.12';OS='Microsoft Windows 10.0.26300';Architecture='X64'}}
        $dispatch=Get-Command Invoke-InternalPhase5NetworkDispatch
        $networkProbe=[pscustomobject]@{Calls=0;Urls=[Collections.Generic.List[string]]::new();Timeout=$false;HeaderLimit=$false;Family='HTML'}
        function Invoke-InternalPhase5NetworkDispatch {
            param($State,$Uri,$Token)
            $networkProbe.Calls++;$networkProbe.Urls.Add([string]$Uri);$State.Accounting.Dispatch($Token)
            if($networkProbe.Timeout){throw 'ordinary synthetic timeout'}
            if($networkProbe.HeaderLimit){$State.Accounting.Stop('RESPONSE_HEADERS_EXCEEDED');throw 'counted transport header limit'}
            $State.Accounting.Response($Token)
            if($networkProbe.Family -ceq 'MMA'){
                $text=if([string]$Uri -like '*mmanrsrListAjaxJsonCallNew*'){$mmaList}else{$mmaDetail}
                return [pscustomobject]@{StatusCode=200;ContentType='application/json';Text=$text;Bytes=$null}
            }
            if($networkProbe.Family -ceq 'XLSX'){return [pscustomobject]@{StatusCode=200;ContentType='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';Text='';Bytes=$xlsxBytes}}
            [pscustomobject]@{StatusCode=200;ContentType='text/html';Text=$html;Bytes=$null}
        }
        try{
            $plan=New-Phase5BenefitBatchPlan @a
            Equal $plan.PlanCore.PlanVersion 2 'Strict Plan v2'
            Equal $plan.PlanCore.NetworkPolicyFingerprint (Get-Phase5NetworkPolicyFingerprint $policy) 'Policy fingerprint bound'
            $pristine=Invoke-Phase5BenefitBatch @a -BatchId $plan.BatchId -Mode RecoverOnly -RepositoryStateProvider $invokeArgs.RepositoryStateProvider
            Equal $pristine.Code P52B_RECOVERY_PLAN_MISSING 'Pristine strict RecoverOnly must not manufacture a one-shot seal'
            Check (-not (Test-Path -LiteralPath $plan.PlanPath) -and -not (Test-Path -LiteralPath $plan.GuardPath)) 'Pristine recovery creates neither seal nor guard'
            $before=Inventory $a.Store.Root
            $zero=Invoke-Phase5BenefitBatch @a -BatchId $plan.BatchId -RepositoryStateProvider $invokeArgs.RepositoryStateProvider
            Equal $zero.Code P52B_NETWORK_POLICY_STOP "Budget0 is explicit policy stop: $($zero.Reasons -join '; ')"
            Equal $zero.Summary.ExecutedCount 0 'Budget0 cycle0'
            Equal $zero.Summary.CommittedCount 0 'Budget0 commit0'
            Equal $networkProbe.Calls 0 'Budget0 actual dispatch0'
            Equal $zero.NetworkExecution.AttemptedCount 0 'Budget0 measured attempts0'
            Equal (Inventory $a.Store.Root) $before 'Budget0 History unchanged'
            $again=Invoke-Phase5BenefitBatch @a -BatchId $plan.BatchId -RepositoryStateProvider $invokeArgs.RepositoryStateProvider
            Equal $again.Code P52B_STRICT_EXECUTE_REENTRY 'Plan seal blocks budget reset even with no prior dispatch'
            $custom=Invoke-Phase5BenefitBatch @a @invokeArgs -BatchId $plan.BatchId
            Equal $custom.Code P52B_CUSTOM_INVOKER_DENIED 'Raw custom invoker rejected'
            $a=$args51.Clone();$a.Store=New-HistoryStoreLayout -Root (Join-Path $root 'strict-history');$a.BatchWorkspaceRoot=Join-Path $root 'strict-batches';$a.NetworkPolicy=New-Phase5BenefitNetworkPolicy -AllowedHttpsHosts @('city.example.go.kr') -MaxPhysicalAttempts 1
            $plan=New-Phase5BenefitBatchPlan @a;$start=$networkProbe.Calls
            $one=Invoke-Phase5BenefitBatch @a -BatchId $plan.BatchId -RepositoryStateProvider $invokeArgs.RepositoryStateProvider
            Equal $one.Code P52B_NETWORK_POLICY_STOP 'No next business after pre-cycle budget stop'
            Equal $one.Summary.CommittedCount 1 'First independent commit preserved'
            Equal ($networkProbe.Calls-$start) 1 'Actual single-source request1'
            Equal $one.Summary.NotStartedCount 2 'Subsequent businesses pristine'
            $reenter=Invoke-Phase5BenefitBatch @a -BatchId $plan.BatchId -RepositoryStateProvider $invokeArgs.RepositoryStateProvider
            Equal $reenter.Code P52B_STRICT_EXECUTE_REENTRY 'Committed strict Execute cannot reset the budget'
            Check (-not (Test-Path -LiteralPath $plan.GuardPath)) 'Rejected strict reentry must not manufacture a new stale guard blocking RecoverOnly'
            $history=Inventory $a.Store.Root;$reviewKey=$one.Items[0].Review.ReviewKey
            $recovered=Invoke-Phase5BenefitBatch @a -BatchId $plan.BatchId -Mode RecoverOnly -RepositoryStateProvider $invokeArgs.RepositoryStateProvider
            Equal ($networkProbe.Calls-$start) 1 'Recovery adds no network'
            Equal (Inventory $a.Store.Root) $history 'Recovery adds no History mutation'
            Equal $recovered.Items[0].Review.ReviewKey $reviewKey 'Review key stable'
            Equal $recovered.NetworkExecution $null 'Historical network metrics unavailable, not zero'
            $a.NetworkPolicy.MaxPhysicalAttempts=2
            $mismatch=Invoke-Phase5BenefitBatch @a -BatchId $plan.BatchId -RepositoryStateProvider $invokeArgs.RepositoryStateProvider
            Equal $mismatch.Status BLOCKED 'Changed policy cannot reuse BatchId'
            Equal ($networkProbe.Calls-$start) 1 'Policy mismatch network0'
            foreach($barrier in @('guard','claim','partial-seal','runtime')){
                $a=$args51.Clone();$a.Store=New-HistoryStoreLayout -Root (Join-Path $root ($barrier+'-history'));$a.BatchWorkspaceRoot=Join-Path $root ($barrier+'-batches');$a.NetworkPolicy=New-Phase5BenefitNetworkPolicy -AllowedHttpsHosts @('city.example.go.kr') -MaxPhysicalAttempts 1
                $plan=New-Phase5BenefitBatchPlan @a;$start=$networkProbe.Calls;$before=Inventory $a.Store.Root
                $hold=$null
                if($barrier -ceq 'guard'){[void][IO.Directory]::CreateDirectory((Split-Path -Parent $plan.GuardPath));$hold=[IO.File]::Open($plan.GuardPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)}
                if($barrier -ceq 'claim'){[IO.File]::WriteAllText((Join-Path $a.Store.TempRoot ('.p5-'+$plan.Items[0].RunId+'.claim')),'retained fixture');$before=Inventory $a.Store.Root}
                if($barrier -ceq 'partial-seal'){[void][IO.Directory]::CreateDirectory((Split-Path -Parent $plan.PlanPath));[IO.File]::WriteAllText($plan.PlanPath,'partial interrupted seal')}
                $qualifier=(Get-Command Test-InternalPhase5NetworkQualification).ScriptBlock
                if($barrier -ceq 'runtime'){function Test-InternalPhase5NetworkQualification {param($Identity);return $false}}
                try{$blocked=Invoke-Phase5BenefitBatch @a -BatchId $plan.BatchId -RepositoryStateProvider $invokeArgs.RepositoryStateProvider}finally{if($null -ne $hold){$hold.Dispose()};Set-Item Function:Test-InternalPhase5NetworkQualification $qualifier}
                Equal $blocked.Status BLOCKED "$barrier blocks before execution"
                Equal ($networkProbe.Calls-$start) 0 "$barrier request0"
                Equal $blocked.Summary.ExecutedCount 0 "$barrier cycle0"
                Equal (Inventory $a.Store.Root) $before "$barrier preserves History and residue"
            }
            # Same exact existing MMA adapter and JSONP linkage; no new source implementation.
            $mmaList=([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'testdata/benefit-evidence-mma/mma-list.fixture.jsonp'))) -replace '^MmaTestList','MmaBenefitList'
            $mmaDetail=([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'testdata/benefit-evidence-mma/mma-detail-2789.fixture.jsonp'))) -replace '^MmaTestDetail','MmaBenefitDetail'
            $mmaRows=$rows | ConvertTo-Json -Depth 10 | ConvertFrom-Json
            $mmaRows[0].업소명='(유)투투여행사';$mmaRows[0].소재지도로명주소='서울특별시 테스트구 여행로 2789';$mmaRows[0].업소전화번호='02-2789-0000';$mmaRows[0].출처유형='병무청 공식 자료';$mmaRows[0].출처URL='https://www.mma.go.kr/about/udgg/list.do?mc=mma0003357'
            $mmaCsv=Join-Path $root 'mma.csv';$mmaRows | Export-Csv -LiteralPath $mmaCsv -NoTypeInformation -Encoding utf8
            $networkProbe.Family='MMA'
            foreach($scenario in @('detail-denied','detail-complete','list-only')){
                $a=$args51.Clone();$a.CanonicalCsvPath=$mmaCsv;$a.BusinessIds=@($ids[0],$ids[2]);$a.Store=New-HistoryStoreLayout -Root (Join-Path $root ($scenario+'-history'));$a.BatchWorkspaceRoot=Join-Path $root ($scenario+'-batches')
                $a.NetworkPolicy=New-Phase5BenefitNetworkPolicy -AllowedHttpsHosts @('city.example.go.kr','open.mma.go.kr') -MaxPhysicalAttempts $(if($scenario -ceq 'detail-complete'){2}else{1})
                if($scenario -ceq 'list-only'){$mmaRows[0].업소명='없는 합성 업체';$mmaRows | Export-Csv -LiteralPath $mmaCsv -NoTypeInformation -Encoding utf8}
                $plan=New-Phase5BenefitBatchPlan @a;$start=$networkProbe.Calls
                $value=Invoke-Phase5BenefitBatch @a -BatchId $plan.BatchId -RepositoryStateProvider $invokeArgs.RepositoryStateProvider
                Equal $value.Code P52B_NETWORK_POLICY_STOP "$scenario hard stop"
                Equal ($networkProbe.Calls-$start) $(if($scenario -ceq 'detail-complete'){2}else{1}) "$scenario underlying requests"
                Equal $value.Summary.ExecutedCount 1 'No later pristine business cycle'
                Equal $value.Summary.CommittedCount 1 'Existing current-cycle legitimate commit preserved'
                if($scenario -ceq 'detail-denied'){
                    Equal $value.NetworkExecution.DeniedCount 1 'DETAIL rejected before transport'
                    Equal $value.Items[0].OperationalStatus FAILED 'Denied DETAIL becomes operational failure, not semantic absence'
                    Equal $value.Items[0].Metrics.ExternalFetchCount 2 'Legacy logical counter includes swallowed denied request'
                    Equal $value.NetworkExecution.AttemptedCount 1 'Strict actual dispatch distinct from legacy logical count'
                    Check ($value.Items[0].BenefitState -cnotin @('ENDED','ACTIVE')) 'Policy failure never approves/ends benefit'
                    Check ($networkProbe.Urls[$start] -like '*mmanrsrListAjaxJsonCallNew*') 'Only LIST transmitted on DETAIL denial'
                }
                Write-Host "P5-2B MMA $scenario PASS: dispatch=$($value.NetworkExecution.AttemptedCount) denied=$($value.NetworkExecution.DeniedCount) committed=$($value.Summary.CommittedCount)"
            }
            . (Join-Path $PSScriptRoot 'testdata/benefit-evidence-xlsx/test-support.ps1')
            $xlsxRows=$rows | ConvertTo-Json -Depth 10 | ConvertFrom-Json;$xlsxRows[0].출처URL='https://city.example.go.kr/list.xlsx'
            $xlsxCsv=Join-Path $root 'xlsx.csv';$xlsxRows | Export-Csv -LiteralPath $xlsxCsv -NoTypeInformation -Encoding utf8
            $xlsxBytes=New-XlsxTestBytes -Name $rows[0].업소명 -Address $rows[0].소재지도로명주소 -Phone $rows[0].업소전화번호 -Benefit '합성 혜택'
            $networkProbe.Family='XLSX'
            $a=$args51.Clone();$a.CanonicalCsvPath=$xlsxCsv;$a.BusinessIds=@($ids[0]);$a.Store=New-HistoryStoreLayout -Root (Join-Path $root 'xlsx-history');$a.BatchWorkspaceRoot=Join-Path $root 'xlsx-batches';$a.NetworkPolicy=New-Phase5BenefitNetworkPolicy -AllowedHttpsHosts @('city.example.go.kr') -MaxPhysicalAttempts 1
            $plan=New-Phase5BenefitBatchPlan @a;$start=$networkProbe.Calls
            $xlsx=Invoke-Phase5BenefitBatch @a -BatchId $plan.BatchId -RepositoryStateProvider $invokeArgs.RepositoryStateProvider
            Equal $xlsx.Items[0].OperationalStatus COMPLETE 'XLSX normal pipeline remains COMPLETE'
            Equal ($networkProbe.Calls-$start) 1 'XLSX underlying request1'
            Equal $xlsx.Items[0].Metrics.ParseCount 1 'XLSX parsed once'
            $networkProbe.Family='HTML';$networkProbe.Timeout=$true
            $a=$args51.Clone();$a.BusinessIds=@($ids[0]);$a.Store=New-HistoryStoreLayout -Root (Join-Path $root 'timeout-history');$a.BatchWorkspaceRoot=Join-Path $root 'timeout-batches';$a.NetworkPolicy=New-Phase5BenefitNetworkPolicy -AllowedHttpsHosts @('city.example.go.kr') -MaxPhysicalAttempts 1
            $plan=New-Phase5BenefitBatchPlan @a;$start=$networkProbe.Calls
            $timeout=Invoke-Phase5BenefitBatch @a -BatchId $plan.BatchId -RepositoryStateProvider $invokeArgs.RepositoryStateProvider
            Equal ($networkProbe.Calls-$start) 1 'Ordinary timeout actual attempt1'
            Equal $timeout.NetworkExecution.FirstStopReason $null 'Ordinary timeout never becomes budget exhaustion'
            Equal $timeout.NetworkExecution.UnknownOutcomeCount 1 'Ordinary timeout preserves unknown response outcome'
            Equal $timeout.Items[0].OperationalStatus FAILED 'Ordinary source failure remains source failure'
            $networkProbe.Timeout=$false
            $networkProbe.HeaderLimit=$true
            $a=$args51.Clone();$a.Store=New-HistoryStoreLayout -Root (Join-Path $root 'header-limit-history');$a.BatchWorkspaceRoot=Join-Path $root 'header-limit-batches';$a.NetworkPolicy=New-Phase5BenefitNetworkPolicy -AllowedHttpsHosts @('city.example.go.kr') -MaxPhysicalAttempts 3
            $plan=New-Phase5BenefitBatchPlan @a;$start=$networkProbe.Calls
            $headers=Invoke-Phase5BenefitBatch @a -BatchId $plan.BatchId -RepositoryStateProvider $invokeArgs.RepositoryStateProvider
            Equal $headers.Code P52B_NETWORK_POLICY_STOP 'Caught header-limit exception remains sticky at coordinator'
            Equal ($networkProbe.Calls-$start) 1 'Header limit stops before next business despite remaining budget'
            Equal $headers.Summary.CommittedCount 1 'Existing first-cycle diagnostic commit retained'
            Equal $headers.Summary.NotStartedCount 2 'No fabricated later failures'
            Equal $headers.NetworkExecution.FirstStopReason RESPONSE_HEADERS_EXCEEDED 'Exact stop reason retained outside SOURCE_FETCH_FAILED'
            $networkProbe.HeaderLimit=$false
        }finally{Set-Item Function:Get-Phase5NetworkTransportIdentity $originalIdentity;Set-Item Function:Invoke-InternalPhase5NetworkDispatch $dispatch.ScriptBlock}
        Write-Host 'P5-2B Network batch PASS: policy-v2, budget0 cycle0/commit0, one-shot seal, stop-next-business, committed recovery0/0, custom-invoker rejection'
    }
    if($Group -cin @('Plan','All')){
        $before=Inventory $store.Root
        $wrongRevision=$args51.Clone();$wrongRevision.RepositoryRevision=('0'*40)
        Reject {New-Phase5BenefitBatchPlan @wrongRevision} 'Repository revision must match the actual checked-out implementation before network'
        $plan=New-Phase5BenefitBatchPlan @args51
        Equal @($plan.Items).Count 3 'Three explicitly selected businesses'
        Equal (($plan.Items | ForEach-Object SourceRowNumber) -join ',') '2,4,6' 'Noncontiguous CSV ordinals preserved'
        Equal $plan.BatchId (New-Phase5BenefitBatchPlan @args51).BatchId 'Stable content-bound BatchId'
        Equal (($plan.Items | ForEach-Object RunId) -join ',') (((New-Phase5BenefitBatchPlan @args51).Items | ForEach-Object RunId) -join ',') 'Stable per-business RunIds'
        Equal @($plan.Items.RunId | Select-Object -Unique).Count 3 'Independent run identities'
        Check ($plan.BatchId -cmatch '^batch-[0-9a-f]{64}$') 'Full content-bound batch digest'
        Equal (Inventory $store.Root) $before 'Planning never writes History'
        Equal $requests.Urls.Count 0 'Planning has no network'
        foreach($bad in @('empty','duplicate','missing','over-limit','last-source')){
            $a=$args51.Clone()
            switch($bad){
                empty {$a.BusinessIds=@()}
                duplicate {$a.BusinessIds=@($ids[0],$ids[0])}
                missing {$a.BusinessIds=@($ids[0],('biz-'+('9'*32)))}
                over-limit {$a.BusinessIds=@(1..11 | ForEach-Object {'biz-'+('{0:x32}' -f $_)})}
                last-source {$changed=$rows | ConvertTo-Json -Depth 6 | ConvertFrom-Json;$changed[4].출처URL='';$badCsv=Join-Path $root 'invalid.csv';$changed | Export-Csv -LiteralPath $badCsv -NoTypeInformation -Encoding utf8;$a.CanonicalCsvPath=$badCsv}
            }
            # An invalid selection must fail before a batch claim or any pipeline call.
            Reject {New-Phase5BenefitBatchPlan @a} "Invalid $bad plan rejected"
            $rejected=Invoke-Phase5BenefitBatch @a @invokeArgs -BatchId $plan.BatchId
            Equal $rejected.Status BLOCKED "Invalid $bad invocation blocked"
            Equal (Inventory $store.Root) $before 'Late invalid selection leaves History untouched'
            Equal $requests.Urls.Count 0 'Invalid selection fetch0'
        }
        foreach($change in @('input','order','time','revision','workspace')){
            $a=$args51.Clone()
            switch($change){
                input {$changed=$rows | ConvertTo-Json -Depth 6 | ConvertFrom-Json;$changed[1].할인정보='changed fictional fixture';$otherCsv=Join-Path $root 'changed.csv';$changed | Export-Csv -LiteralPath $otherCsv -NoTypeInformation -Encoding utf8;$a.CanonicalCsvPath=$otherCsv}
                order {$a.BusinessIds=@($ids[4],$ids[2],$ids[0])}
                time {$a.ObservedAt='2026-10-25T00:01:00Z'}
                revision {$a.RepositoryRevision=('b'*40)}
                workspace {$a.BatchWorkspaceRoot=Join-Path $root 'other-batches'}
            }
            $r=Invoke-Phase5BenefitBatch @a @invokeArgs -BatchId $plan.BatchId
            Equal $r.Status BLOCKED "Changed $change rejects frozen BatchId"
            Equal $requests.Urls.Count 0 'Plan mismatch fetch0'
        }
        $alternate=$store | Select-Object *
        foreach($property in @('RunsRoot','ObservationsRoot','ComparisonsRoot','ArtifactsRoot','IndexesRoot','TempRoot')){
            $alternate.$property=Join-Path $store.Root ('alternate/'+$property)
            [void][IO.Directory]::CreateDirectory($alternate.$property)
        }
        $alternateArgs=$args51.Clone();$alternateArgs.Store=$alternate
        $historyBefore=Inventory $store.Root;$requestBefore=$requests.Urls.Count
        $otherNamespace=Invoke-Phase5BenefitBatch @alternateArgs @invokeArgs -BatchId $plan.BatchId
        Equal $otherNamespace.Status BLOCKED 'Same History Root with changed effective subroots rejects the frozen BatchId'
        Equal $requests.Urls.Count $requestBefore 'Changed History namespace fetch0'
        Equal (Inventory $store.Root) $historyBefore 'Changed History namespace writes0'
        Write-Host 'P5-1 Plan PASS: all-selected preflight fetch0 / History0; ordinals2,4,6; content-bound IDs; mismatch rejected'
    }
    if($Group -cin @('Execution','All')){
        $a=$args51.Clone();$a.Store=New-HistoryStoreLayout -Root (Join-Path $root 'execution-history');$a.BatchWorkspaceRoot=Join-Path $root 'execution-batches'
        $plan=New-Phase5BenefitBatchPlan @a
        $before=$requests.Urls.Count
        $originalImport=Get-Command Import-Csv -CommandType Cmdlet
        $reads=[pscustomobject]@{Count=0}
        function Import-Csv {param($LiteralPath,$Encoding);$reads.Count++;& $originalImport -LiteralPath $LiteralPath -Encoding $Encoding}
        try{$r=Invoke-Phase5BenefitBatch @a @invokeArgs -BatchId $plan.BatchId}finally{Remove-Item Function:Import-Csv}
        Equal $reads.Count 1 'Whole canonical CSV read exactly once per batch invocation'
        Equal $r.Status FINISHED 'Three-business sequential execution completes'
        Equal $r.Summary.CommittedCount 3 'Three independent commits'
        Equal $r.Summary.ExecutedCount 3 'Three actual cycle invocations'
        Equal (($r.Items | ForEach-Object BusinessId) -join ',') ($a.BusinessIds -join ',') 'Frozen operator order preserved'
        Equal (($r.Items | ForEach-Object SourceRowNumber) -join ',') '2,4,6' 'Original full-input ordinals reach History'
        Equal ($requests.Urls.Count-$before) 3 'Shared URL still makes three requests, no claimed cross-business cache'
        Equal $r.Metrics.ExternalFetchCount.Total 3 'Aggregate actual physical requests'
        Equal $r.Metrics.ParseCount.Total 3 'No shared parse optimization claimed'
        Equal @($r.Items.ObservationId | Select-Object -Unique).Count 3 'Independent observation identities'
        Equal @($r.Items.Review.ReviewKey | Select-Object -Unique).Count 3 'Independent authoritative Review keys'
        Equal $r.OutputStatus WRITTEN 'One atomic batch summary written'
        Check ([IO.File]::Exists($plan.PlanPath)) 'Immutable plan persisted'
        Equal @(Get-ChildItem -LiteralPath $plan.OutputDirectory -File -Filter '*.json').Count 3 'One stable report per business'
        foreach($item in $r.Items){
            Equal $item.CommitCode COMMITTED 'Every item independently committed'
            Equal $item.OperationalStatus COMPLETE 'Actual operational status retained'
            Equal $item.ProductionAction NONE 'No production action'
            Check ($item.BenefitState -cne 'ENDED') 'No lifecycle ending inferred'
        }
        $a.Store=New-HistoryStoreLayout -Root (Join-Path $root 'failure-history');$a.BatchWorkspaceRoot=Join-Path $root 'failure-batches'
        $plan=New-Phase5BenefitBatchPlan @a
        $seedPlan=New-Phase5BenefitBatchPlan @a
        $seed=Invoke-Phase5BenefitBatch @a @invokeArgs -BatchId $seedPlan.BatchId
        Equal $seed.Summary.CommittedCount 3 'Failure isolation has a committed comparable baseline'
        $a.ObservedAt='2026-10-25T00:30:00Z';$plan=New-Phase5BenefitBatchPlan @a
        $updatedHtml=$html.Replace('10% 할인','20% 할인')
        $calls=[pscustomobject]@{Count=0}
        $faultHttp={param($Uri);$calls.Count++;if($calls.Count -eq 2){throw 'synthetic bounded timeout'};[pscustomobject]@{StatusCode=200;ContentType='text/html';Text=$updatedHtml;Bytes=$null}}.GetNewClosure()
        $failure=Invoke-Phase5BenefitBatch @a -BatchId $plan.BatchId -RepositoryStateProvider $invokeArgs.RepositoryStateProvider -RequestInvoker $faultHttp
        Equal $calls.Count 3 'Safely committed failure permits independent next business'
        Equal $failure.Status FINISHED 'Batch completion is not benefit/operational approval'
        Equal $failure.Summary.CommittedOperationalFailureCount 1 'Committed failed observation counted separately'
        Equal $failure.Items[1].OperationalStatus FAILED 'Failed business retains operational failure'
        Equal $failure.Items[2].OperationalStatus COMPLETE 'Next business not contaminated'
        Check ($failure.Items[1].BenefitState -cne 'ENDED' -and $failure.Items[1].BenefitState -cne 'ACTIVE') 'Failure never becomes benefit truth'
        Equal $failure.Metrics.ExtractionCount.Total 2 'Only successful located sources actually extract'
        Write-Host 'P5-1 Execution PASS: sequential3 / commits3 / shared-URL fetch3 parse3; middle committed failure isolated; no production writes'
    }
    if($Group -cin @('Recovery','All')){
        $a=$args51.Clone();$a.Store=New-HistoryStoreLayout -Root (Join-Path $root 'recovery-history');$a.BatchWorkspaceRoot=Join-Path $root 'recovery-batches'
        $plan=New-Phase5BenefitBatchPlan @a
        $before=Inventory $a.Store.Root;$count=$requests.Urls.Count
        $pending=Invoke-Phase5BenefitBatch @a @invokeArgs -BatchId $plan.BatchId -Mode RecoverOnly
        Equal $requests.Urls.Count $count 'RecoverOnly pending never fetches'
        Equal (Inventory $a.Store.Root) $before 'RecoverOnly pending History writes0'
        Equal $pending.Summary.NotStartedCount 3 'Pending businesses are not executed'
        $one=Invoke-Phase5BenefitBatch @a @invokeArgs -BatchId $plan.BatchId
        Equal $one.Summary.CommittedCount 3 'Recovery fixture really committed'
        $before=Inventory $a.Store.Root;$count=$requests.Urls.Count
        $planHash=(Get-FileHash -LiteralPath $plan.PlanPath).Hash
        [IO.File]::WriteAllText($plan.SummaryPath,'{"spoofedResume":"must not be trusted"}')
        $again=Invoke-Phase5BenefitBatch @a @invokeArgs -BatchId $plan.BatchId -Mode RecoverOnly
        Equal $again.Summary.RecoveredCount 3 'All three recovered'
        Equal (Get-FileHash -LiteralPath $plan.PlanPath).Hash $planHash 'Recovery validates the immutable plan without rewriting it'
        Equal $again.Summary.ExecutedCount 0 'No cycle invocation on recovery'
        Equal $requests.Urls.Count $count 'Same batch recovery fetch0'
        Equal (Inventory $a.Store.Root) $before 'Same batch recovery commits0 / evidence unchanged'
        Equal (($again.Items.Review | ForEach-Object ReviewKey) -join ',') (($one.Items.Review | ForEach-Object ReviewKey) -join ',') 'Original ReviewKeys preserved'
        Check ($null -eq $again.Metrics.ExternalFetchCount.Total) 'Unknown historical metrics not invented'
        Equal $again.Metrics.ExternalFetchCount.MissingCount 3 'Metric coverage explicitly reports recovered unknowns'
        Equal @(Get-ChildItem -LiteralPath $plan.OutputDirectory -File -Filter '*.json').Count 3 'No duplicate per-business Review output'
        # COMMITTED authority wins over per-business residue for read-only recovery.
        $claim=Join-Path $a.Store.TempRoot ('.p5-'+$plan.Items[0].RunId+'.claim')
        [IO.File]::WriteAllText($claim,'P5_INTERRUPTED')
        $stage=Join-Path $a.Store.TempRoot $plan.Items[0].RunId;[void][IO.Directory]::CreateDirectory($stage)
        $before=Inventory $a.Store.Root
        $residual=Invoke-Phase5BenefitBatch @a @invokeArgs -BatchId $plan.BatchId -Mode RecoverOnly
        Equal $residual.Summary.RecoveredCount 3 'COMMITTED residue still recoverable'
        Equal (Inventory $a.Store.Root) $before 'Recovery never deletes residue'
        $blocked=Invoke-Phase5BenefitBatch @a @invokeArgs -BatchId $plan.BatchId
        Equal $blocked.Status BLOCKED 'Residue blocks new Execute work'
        Equal $requests.Urls.Count $count 'Residue cannot cause automatic retry'
        # Mixed committed/pristine plan: one authoritative old run plus two new runs.
        $m=$args51.Clone();$m.Store=New-HistoryStoreLayout -Root (Join-Path $root 'mixed-history');$m.BatchWorkspaceRoot=Join-Path $root 'mixed-batches'
        $mp=New-Phase5BenefitBatchPlan @m
        $seed=Invoke-Phase5BenefitCycle -Store $m.Store -Rows $rows -BusinessId $m.BusinessIds[0] -RunId $mp.Items[0].RunId -ObservedAt $m.ObservedAt -RepositoryRevision $m.RepositoryRevision -SourceRowNumberOffset 2 -OutputDirectory $mp.OutputDirectory @invokeArgs
        Equal $seed.CommitCode COMMITTED 'Mixed fixture baseline committed through existing entrypoint'
        $mixed=Invoke-Phase5BenefitBatch @m @invokeArgs -BatchId $mp.BatchId
        Equal $mixed.Summary.RecoveredCount 1 'Mixed recovery counted separately'
        Equal $mixed.Summary.ExecutedCount 2 'Only two pristine businesses executed'
        Equal $mixed.Metrics.ExternalFetchCount.KnownSum 2 'Known actual request sum retained'
        Equal $mixed.Metrics.ExternalFetchCount.ObservedCount 2 'Observed metric coverage retained'
        Equal $mixed.Metrics.ExternalFetchCount.MissingCount 1 'Recovered metric remains missing'
        Check ($null -eq $mixed.Metrics.ExternalFetchCount.Total) 'Partial metrics cannot become complete total'
        Write-Host 'P5-1 Recovery PASS: recovered3 HTTP0 / History0 / stable ReviewKeys; residue preserved; mixed known2 missing1 total=null'
    }
    if($Group -cin @('Safety','All')){
        # A later committed operational failure remains LatestObservation even though A stays comparable.
        $a=$args51.Clone();$a.BusinessIds=@($ids[0]);$a.Store=New-HistoryStoreLayout -Root (Join-Path $root 'latest-regression-history');$a.BatchWorkspaceRoot=Join-Path $root 'latest-regression-batches'
        $baseline=Invoke-Phase5BenefitCycle -Store $a.Store -Rows $rows -BusinessId $ids[0] -RunId 'run-latest-regression-a' -ObservedAt $a.ObservedAt -RepositoryRevision $a.RepositoryRevision -SourceRowNumberOffset 2 -OutputDirectory (Join-Path $root 'latest-regression-seed-output') @invokeArgs
        Equal $baseline.CommitCode COMMITTED 'Comparable A actually commits'
        $failureHttp={param($Uri);$requests.Urls.Add([string]$Uri);throw 'synthetic operational failure'}.GetNewClosure()
        $failure=Invoke-Phase5BenefitCycle -Store $a.Store -Rows $rows -BusinessId $ids[0] -RunId 'run-latest-regression-b' -ObservedAt '2026-10-25T00:10:00Z' -RepositoryRevision $a.RepositoryRevision -SourceRowNumberOffset 2 -OutputDirectory (Join-Path $root 'latest-regression-seed-output') -RepositoryStateProvider $invokeArgs.RepositoryStateProvider -RequestInvoker $failureHttp
        Equal $failure.CommitCode COMMITTED 'Operational failure B actually commits'
        Equal $failure.OperationalStatus FAILED 'B is an operational failure'
        Check (-not (Read-HistoryObservation -Store $a.Store -ObservationId $failure.ObservationId).Comparable) 'B is noncomparable'
        Equal $failure.Comparison.PreviousObservationId $baseline.ObservationId 'Committed B comparison references A'
        $entry=Get-HistoryLatestEntry -Store $a.Store -BusinessId $ids[0] -Domain BENEFIT
        Equal $entry.LatestObservationId $failure.ObservationId 'Legitimate latest is failed B'
        Equal $entry.LatestComparableObservationId $baseline.ObservationId 'Legitimate comparable remains A'
        $count=$requests.Urls.Count;$before=Inventory $a.Store.Root
        $validated=Assert-InternalPhase5BenefitBatchIndex -Store $a.Store -BusinessId $ids[0] -KnownReviews (Invoke-Phase3ReviewAudit -Store $a.Store).Items
        Equal $validated.LatestObservationId $failure.ObservationId 'Legitimate B/A index remains accepted'
        Equal $requests.Urls.Count $count 'Legitimate index validation fetch0'
        Equal (Inventory $a.Store.Root) $before 'Legitimate validation does not write History'
        # Corrupt only LatestObservationId: the comparable pointer must remain untouched.
        $entry.LatestObservationId=$baseline.ObservationId
        [IO.File]::WriteAllText((Get-HistoryIndexPath -Store $a.Store -BusinessId $ids[0] -Domain BENEFIT),(ConvertTo-HistoryCanonicalJson -Value $entry))
        $a.ObservedAt='2026-10-25T00:20:00Z';$plan=New-Phase5BenefitBatchPlan @a
        $before=Inventory $a.Store.Root
        $regressed=Invoke-Phase5BenefitBatch @a @invokeArgs -BatchId $plan.BatchId
        Equal $requests.Urls.Count $count 'Regressed latest A with committed failed B must reject before HTTP'
        Equal $regressed.Status BLOCKED 'Regressed latest blocks Execute'
        Equal $regressed.Summary.CommittedCount 0 'Regressed latest produces no new commits'
        Equal (Inventory $a.Store.Root) $before 'Regressed latest leaves all History bytes unchanged'
        Check ($null -eq $regressed.Items[0].Review -and -not $regressed.Items[0].AuthorityValidated) 'Regressed latest publishes no authoritative Review'
        Check (-not (Test-Path -LiteralPath $plan.OutputDirectory)) 'Regressed latest creates no per-business Review output'
        foreach($fault in @('guard','active-guard','staging','bare-terminal','index','noncomp-unlinked','paired-rollback','cleared-comparable','rolled-comparable','noncomp-cleared','noncomp-rolled','artifact','plan','output','writer','unclassified')){
            $a=$args51.Clone();$a.Store=New-HistoryStoreLayout -Root (Join-Path $root ($fault+'-history'));$a.BatchWorkspaceRoot=Join-Path $root ($fault+'-batches')
            $plan=New-Phase5BenefitBatchPlan @a
            $count=$requests.Urls.Count;$held=$null;$savedCycle=$null
            switch($fault){
                guard {[void][IO.Directory]::CreateDirectory((Split-Path -Parent $plan.GuardPath));[IO.File]::WriteAllText($plan.GuardPath,'interrupted')}
                active-guard {[void][IO.Directory]::CreateDirectory((Split-Path -Parent $plan.GuardPath));$held=[IO.File]::Open($plan.GuardPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}
                staging {[void][IO.Directory]::CreateDirectory((Join-Path $a.Store.TempRoot $plan.Items[2].RunId))}
                bare-terminal {[void][IO.Directory]::CreateDirectory((Split-Path -Parent (Get-HistoryRunManifestPath -Store $a.Store -RunId $plan.Items[2].RunId)))}
                index {[IO.File]::WriteAllText((Get-HistoryIndexPath -Store $a.Store -BusinessId $a.BusinessIds[2] -Domain BENEFIT),'{broken')}
                {$_ -cin @('noncomp-unlinked','paired-rollback','cleared-comparable','rolled-comparable','noncomp-cleared','noncomp-rolled')} {
                    $seed=Invoke-Phase5BenefitCycle -Store $a.Store -Rows $rows -BusinessId $a.BusinessIds[0] -RunId 'run-comparable-seed' -ObservedAt $a.ObservedAt -RepositoryRevision $a.RepositoryRevision -SourceRowNumberOffset 2 -OutputDirectory (Join-Path $root 'comparable-seed-output') @invokeArgs
                    Equal $seed.CommitCode COMMITTED 'Comparable corruption fixture starts with a real committed baseline'
                    if($fault -ceq 'noncomp-rolled'){
                        $newer=Invoke-Phase5BenefitCycle -Store $a.Store -Rows $rows -BusinessId $a.BusinessIds[0] -RunId 'run-newer-comparable' -ObservedAt '2026-10-25T00:10:00Z' -RepositoryRevision $a.RepositoryRevision -SourceRowNumberOffset 2 -OutputDirectory (Join-Path $root 'newer-seed-output') @invokeArgs
                        Equal $newer.CommitCode COMMITTED 'Second comparable baseline really commits'
                    }
                    if($fault -cin @('noncomp-unlinked','paired-rollback','rolled-comparable','noncomp-cleared','noncomp-rolled')){
                        $argsSeed=@{Store=$a.Store;Rows=$rows;BusinessId=$a.BusinessIds[0];RunId='run-current-comparable';ObservedAt='2026-10-25T00:15:00Z';RepositoryRevision=$a.RepositoryRevision;SourceRowNumberOffset=2;OutputDirectory=(Join-Path $root 'current-seed-output');RepositoryStateProvider=$invokeArgs.RepositoryStateProvider;RequestInvoker=$http}
                        if($fault -cin @('noncomp-unlinked','noncomp-cleared','noncomp-rolled')){$argsSeed.RequestInvoker={param($Uri);throw 'synthetic timeout'}}
                        $current=Invoke-Phase5BenefitCycle @argsSeed
                        Equal $current.CommitCode COMMITTED 'A newer committed observation exists'
                    }
                    $entry=Get-HistoryLatestEntry -Store $a.Store -BusinessId $a.BusinessIds[0] -Domain BENEFIT
                    if($fault -ceq 'noncomp-rolled'){
                        Equal $entry.LatestComparableObservationId $newer.ObservationId 'Legitimate failed latest retains the second comparable baseline'
                        [void](Assert-InternalPhase5BenefitBatchIndex -Store $a.Store -BusinessId $a.BusinessIds[0] -KnownReviews (Invoke-Phase3ReviewAudit -Store $a.Store).Items)
                    }
                    if($fault -ceq 'noncomp-unlinked'){
                        Remove-Item -LiteralPath (Get-HistoryComparisonPath -Store $a.Store -ComparisonId $current.Comparison.ComparisonId)
                    }else{
                        if($fault -ceq 'paired-rollback'){$entry.LatestObservationId=$seed.ObservationId}
                        $entry.LatestComparableObservationId=if($fault -cin @('paired-rollback','rolled-comparable','noncomp-rolled')){$seed.ObservationId}else{''}
                    }
                    [IO.File]::WriteAllText((Get-HistoryIndexPath -Store $a.Store -BusinessId $a.BusinessIds[0] -Domain BENEFIT),(ConvertTo-HistoryCanonicalJson -Value $entry))
                    $count=$requests.Urls.Count
                }
                artifact {
                    $seed=Invoke-Phase5BenefitCycle -Store $a.Store -Rows $rows -BusinessId $a.BusinessIds[0] -RunId 'run-artifact-seed' -ObservedAt $a.ObservedAt -RepositoryRevision $a.RepositoryRevision -SourceRowNumberOffset 2 -OutputDirectory (Join-Path $root 'seed-output') @invokeArgs
                    $obs=Read-HistoryObservation -Store $a.Store -ObservationId $seed.ObservationId
                    $ref=$obs.ArtifactReferences[0];[IO.File]::AppendAllText((Join-Path $a.Store.Root $ref.RelativePath),'tampered')
                    $count=$requests.Urls.Count
                }
                plan {[void][IO.Directory]::CreateDirectory((Split-Path -Parent $plan.PlanPath));[IO.File]::WriteAllText($plan.PlanPath,'{"PlanCore":{}}')}
                output {[void][IO.Directory]::CreateDirectory((Join-Path $plan.OutputDirectory ($plan.Items[0].RunId+'.json')))}
                writer {$held=[IO.File]::Open((Join-Path $a.Store.Root '.writer-lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}
                unclassified {$savedCycle=(Get-Command Invoke-Phase5BenefitCycle).ScriptBlock;function Invoke-Phase5BenefitCycle {throw 'unclassified fixture fault'}}
            }
            $before=Inventory $a.Store.Root
            try{$r=Invoke-Phase5BenefitBatch @a @invokeArgs -BatchId $plan.BatchId}finally{if($null -ne $held){$held.Dispose()};if($null -ne $savedCycle){Set-Item Function:Invoke-Phase5BenefitCycle $savedCycle}}
            if($fault -cin @('writer','output')){
                Equal ($requests.Urls.Count-$count) 1 "$fault stops before second business"
                Equal $r.Status STOPPED "$fault stops batch"
                Equal $r.Summary.NotStartedCount 2 "$fault leaves two businesses unstarted"
                if($fault -ceq 'writer'){Equal $r.Items[0].CommitCode WRITER_LOCKED 'Writer-lock outcome preserved';Check ($null -eq $r.Items[0].Review) 'Uncommitted item has no authoritative Review'}
                else{
                    Equal $r.Items[0].CommitCode COMMITTED 'Output failure retains commit success'
                    Equal $r.Items[0].OutputStatus FAILED 'Output failure separately visible'
                    [IO.Directory]::Delete((Join-Path $plan.OutputDirectory ($plan.Items[0].RunId+'.json')))
                    $n=$requests.Urls.Count;$snapshot=Inventory $a.Store.Root
                    $fix=Invoke-Phase5BenefitBatch @a @invokeArgs -BatchId $plan.BatchId -Mode RecoverOnly
                    Equal $fix.Summary.RecoveredCount 1 'Committed failed-output item is recoverable'
                    Equal $requests.Urls.Count $n 'Output recovery fetch0'
                    Equal (Inventory $a.Store.Root) $snapshot 'Output recovery commits0'
                }
            }else{
                Equal $requests.Urls.Count $count "$fault fetch0"
                Check ($r.Status -cin @('BLOCKED','STOPPED')) "$fault fail-closed"
                Equal (Inventory $a.Store.Root) $before "$fault no new History writes"
            }
            if($fault -ceq 'unclassified'){
                Equal $r.Items[0].Status FAILED 'An attempted cycle without a result is not an unstarted business'
                Check ($null -eq $r.Items[0].Metrics -and $null -eq $r.Items[0].Review) 'Unknown attempted work cannot fabricate metrics or Review'
            }
            Equal $r.ProductionAction NONE 'All failures retain NONE'
        }
        # Actual History CAS movement, not a fabricated result code.
        $a=$args51.Clone();$a.Store=New-HistoryStoreLayout -Root (Join-Path $root 'cas-history');$a.BatchWorkspaceRoot=Join-Path $root 'cas-batches'
        $basePlan=New-Phase5BenefitBatchPlan @a;$seed=Invoke-Phase5BenefitBatch @a @invokeArgs -BatchId $basePlan.BatchId
        Equal $seed.Summary.CommittedCount 3 'CAS baseline exists'
        $a.ObservedAt='2026-10-25T02:00:00Z';$plan=New-Phase5BenefitBatchPlan @a
        $originalCommit=(Get-Command Commit-HistoryRun).ScriptBlock
        $race=[pscustomobject]@{Injected=$false;ObservationId=('obs-'+('c'*32))}
        function Commit-HistoryRun {
            param($Store,$PreparedRun,$ExpectedBaselines)
            if(-not $race.Injected){
                $race.Injected=$true
                $baseline=Get-BenefitIncrementalBaseline -Store $Store -BusinessId $a.BusinessIds[0]
                $competing=$baseline.Observation | Select-Object *
                $competing.ObservationId=$race.ObservationId;$competing.RunId='run-p51-competing'
                $manifest=New-HistoryRunManifest -RunId $competing.RunId -StartedAt $a.ObservedAt -RepositoryRevision $a.RepositoryRevision -RequestedBusinessIds @($competing.BusinessId) -CompletedBusinessIds @($competing.BusinessId) -ExecutionStatus COMPLETE -RunCommitStatus PREPARED
                $prepared=Prepare-HistoryRun -Store $Store -RunManifest $manifest -Observations @($competing)
                $win=& $originalCommit -Store $Store -PreparedRun $prepared -ExpectedBaselines @{($competing.BusinessId+'|BENEFIT')=$baseline.Observation.ObservationId}
                Equal $win.Code COMMITTED 'Competing run actually commits'
            }
            return & $originalCommit -Store $Store -PreparedRun $PreparedRun -ExpectedBaselines $ExpectedBaselines
        }
        $count=$requests.Urls.Count
        try{$moved=Invoke-Phase5BenefitBatch @a @invokeArgs -BatchId $plan.BatchId}finally{Set-Item Function:Commit-HistoryRun $originalCommit}
        Equal $moved.Status STOPPED 'CAS stops the remaining batch'
        Equal $moved.Items[0].CommitCode BASELINE_MOVED 'Actual CAS code retained'
        Check $moved.Items[0].RetryRequired 'RetryRequired is exposed, never auto-executed'
        Equal ($requests.Urls.Count-$count) 1 'CAS movement never fetches twice or runs later businesses'
        Equal $moved.Summary.NotStartedCount 2 'CAS leaves two businesses pristine'
        Equal $moved.Items[0].Metrics.ArtifactWrites 0 'Stale artifacts not published'
        Check ($null -eq $moved.Items[0].Review) 'CAS cannot publish stale Review'
        Equal (Get-HistoryLatestEntry -Store $a.Store -BusinessId $a.BusinessIds[0] -Domain BENEFIT).LatestObservationId $race.ObservationId 'Competing observation remains authoritative'
        # Newer operational failure changes LatestObservation, not the prior comparable baseline.
        $a=$args51.Clone();$a.Store=New-HistoryStoreLayout -Root (Join-Path $root 'index-semantics-history');$a.BatchWorkspaceRoot=Join-Path $root 'index-semantics-batches'
        $first=New-Phase5BenefitBatchPlan @a;$good=Invoke-Phase5BenefitBatch @a @invokeArgs -BatchId $first.BatchId
        $a.ObservedAt='2026-10-25T01:00:00Z';$next=New-Phase5BenefitBatchPlan @a
        $failHttp={param($Uri);$requests.Urls.Add([string]$Uri);throw 'synthetic source timeout'}.GetNewClosure()
        $failed=Invoke-Phase5BenefitBatch @a -BatchId $next.BatchId -RepositoryStateProvider $invokeArgs.RepositoryStateProvider -RequestInvoker $failHttp
        Equal $failed.Summary.CommittedCount 3 'Committed diagnostic routes allow independent progress'
        foreach($i in 0..2){
            $entry=Get-HistoryLatestEntry -Store $a.Store -BusinessId $a.BusinessIds[$i] -Domain BENEFIT
            Equal $entry.LatestObservationId $failed.Items[$i].ObservationId 'Latest observation advances to failed observation'
            Equal $entry.LatestComparableObservationId $good.Items[$i].ObservationId 'Latest comparable remains valid earlier baseline'
            Equal $failed.Items[$i].Review.ReviewRoute OPERATIONAL_DIAGNOSTIC 'Existing operational diagnostic route retained'
        }
        Write-Host 'P5-1 Safety PASS: guards/staging/corruption fetch0; writer/output stop after1; latest vs comparable retained'
    }
}finally{
    $full=[IO.Path]::GetFullPath($root)
    if(-not $full.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or -not ([IO.Path]::GetFileName($full)).StartsWith('milimap-p51-')){throw 'UNSAFE_TEST_CLEANUP'}
    if(Test-Path -LiteralPath $full){Remove-Item -LiteralPath $full -Recurse -Force}
}
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
        $mmaDetail2740=''
        $networkProbe=[pscustomobject]@{Calls=0;Urls=[Collections.Generic.List[string]]::new();Timeout=$false;HeaderLimit=$false;Family='HTML'}
        function Invoke-InternalPhase5NetworkDispatch {
            param($State,$Uri,$Token)
            $networkProbe.Calls++;$networkProbe.Urls.Add([string]$Uri);$State.Accounting.Dispatch($Token)
            if($networkProbe.Timeout){throw 'ordinary synthetic timeout'}
            if($networkProbe.HeaderLimit){$State.Accounting.Stop('RESPONSE_HEADERS_EXCEEDED');throw 'counted transport header limit'}
            $State.Accounting.Response($Token)
            if($networkProbe.Family -ceq 'MMA'){
                $text=if([string]$Uri -like '*mmanrsrListAjaxJsonCallNew*'){$mmaList}elseif([string]$Uri -like '*udgigwan_cd=2740*'){$mmaDetail2740}else{$mmaDetail}
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
            $mmaDetail2740=([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'testdata/benefit-evidence-mma/mma-detail-2740.fixture.jsonp'))) -replace '^MmaTestDetail','MmaBenefitDetail'
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

            # Opt-in -ReuseBatchRunContext Test A: HTML C_LITE_V1 3-business shared URL with MaxPhysicalAttempts = 1.
            $networkProbe.Family='HTML';$networkProbe.Timeout=$false;$networkProbe.HeaderLimit=$false
            $reuseA=$args51.Clone();$reuseA.Store=New-HistoryStoreLayout -Root (Join-Path $root 'reuse-html-history');$reuseA.BatchWorkspaceRoot=Join-Path $root 'reuse-html-batches';$reuseA.NetworkPolicy=New-Phase5BenefitNetworkPolicy -AllowedHttpsHosts @('city.example.go.kr') -MaxPhysicalAttempts 1
            $reusePlan1=New-Phase5BenefitBatchPlan @reuseA;$reuseStart1=$networkProbe.Calls
            $reuseRun1=Invoke-Phase5BenefitBatch @reuseA -BatchId $reusePlan1.BatchId -RepositoryStateProvider $invokeArgs.RepositoryStateProvider -ReuseBatchRunContext
            Equal $reuseRun1.Status FINISHED 'ReuseBatchRunContext HTML batch1 finishes'
            Equal $reuseRun1.Summary.CommittedCount 3 'ReuseBatchRunContext HTML batch1 commits 3 items'
            Equal $reuseRun1.NetworkExecution.AttemptedCount 1 'ReuseBatchRunContext HTML batch1 AttemptedCount 1'
            Equal ($networkProbe.Calls-$reuseStart1) 1 'ReuseBatchRunContext HTML batch1 underlying dispatch 1'
            Equal $reuseRun1.Metrics.ExternalFetchCount.Total 1 'ReuseBatchRunContext HTML batch1 ExternalFetchCount 1'
            Equal $reuseRun1.Metrics.ParseCount.Total 1 'ReuseBatchRunContext HTML batch1 ParseCount 1'
            Equal $reuseRun1.Metrics.AdapterReuseCount.Total 2 'ReuseBatchRunContext HTML batch1 AdapterReuseCount 2'
            Equal @(Get-ChildItem -LiteralPath $reuseA.Store.ArtifactsRoot -Filter '*.html' -File).Count 0 'ReuseBatchRunContext HTML batch1 stores 0 .html files'
            Equal @($reuseRun1.Items.ObservationId | Select-Object -Unique).Count 3 'ReuseBatchRunContext HTML batch1 has 3 distinct ObservationIds'
            Equal @($reuseRun1.Items.Review.ReviewKey | Select-Object -Unique).Count 3 'ReuseBatchRunContext HTML batch1 has 3 distinct ReviewKeys'
            foreach($item in $reuseRun1.Items){
                $obs=Read-HistoryObservation -Store $reuseA.Store -ObservationId $item.ObservationId
                Equal @($obs.ArtifactReferences).Count 3 'ReuseBatchRunContext HTML batch1 capture has 3 artifacts'
            }
            $reuseInvBeforeRec=Inventory $reuseA.Store.Root;$reuseRecStart=$networkProbe.Calls
            $reuseRec1=Invoke-Phase5BenefitBatch @reuseA -BatchId $reusePlan1.BatchId -Mode RecoverOnly -RepositoryStateProvider $invokeArgs.RepositoryStateProvider
            Equal $reuseRec1.Status FINISHED 'ReuseBatchRunContext HTML batch1 RecoverOnly finishes'
            Equal $reuseRec1.Summary.RecoveredCount 3 'ReuseBatchRunContext HTML batch1 RecoverOnly recovers 3 items'
            Equal ($networkProbe.Calls-$reuseRecStart) 0 'ReuseBatchRunContext HTML batch1 RecoverOnly makes 0 network calls'
            Equal (Inventory $reuseA.Store.Root) $reuseInvBeforeRec 'ReuseBatchRunContext HTML batch1 RecoverOnly History unchanged'

            $reuseA2=$reuseA.Clone();$reuseA2.ObservedAt='2026-10-25T00:10:00Z'
            $reusePlan2=New-Phase5BenefitBatchPlan @reuseA2;$reuseStart2=$networkProbe.Calls
            $reuseRun2=Invoke-Phase5BenefitBatch @reuseA2 -BatchId $reusePlan2.BatchId -RepositoryStateProvider $invokeArgs.RepositoryStateProvider -ReuseBatchRunContext
            Equal $reuseRun2.Status FINISHED 'ReuseBatchRunContext HTML batch2 finishes'
            Equal $reuseRun2.Summary.CommittedCount 3 'ReuseBatchRunContext HTML batch2 commits 3 items'
            Equal $reuseRun2.NetworkExecution.AttemptedCount 1 'ReuseBatchRunContext HTML batch2 AttemptedCount 1'
            Equal ($networkProbe.Calls-$reuseStart2) 1 'ReuseBatchRunContext HTML batch2 underlying dispatch 1'
            Equal $reuseRun2.Metrics.ExternalFetchCount.Total 1 'ReuseBatchRunContext HTML batch2 ExternalFetchCount 1'
            Equal $reuseRun2.Metrics.ReuseApplied.Total 3 'ReuseBatchRunContext HTML batch2 ReuseApplied 3'
            Equal $reuseRun2.Metrics.ParseCount.Total 0 'ReuseBatchRunContext HTML batch2 ParseCount 0'
            Equal @(Get-ChildItem -LiteralPath $reuseA2.Store.ArtifactsRoot -Filter '*.html' -File).Count 0 'ReuseBatchRunContext HTML batch2 stores 0 .html files'
            foreach($item in $reuseRun2.Items){
                $obs=Read-HistoryObservation -Store $reuseA2.Store -ObservationId $item.ObservationId
                Equal @($obs.ArtifactReferences).Count 4 'ReuseBatchRunContext HTML batch2 reuse has 4 artifacts'
            }

            # Opt-in -ReuseBatchRunContext Test B: cached FAILED payload must never bypass strict MaxPhysicalAttempts = 1.
            $reuseB=$args51.Clone();$reuseB.Store=New-HistoryStoreLayout -Root (Join-Path $root 'reuse-timeout-history');$reuseB.BatchWorkspaceRoot=Join-Path $root 'reuse-timeout-batches';$reuseB.NetworkPolicy=New-Phase5BenefitNetworkPolicy -AllowedHttpsHosts @('city.example.go.kr') -MaxPhysicalAttempts 1
            $reusePlanB=New-Phase5BenefitBatchPlan @reuseB;$reuseStartB=$networkProbe.Calls
            $networkProbe.Timeout=$true
            try{
                $reuseRunB=Invoke-Phase5BenefitBatch @reuseB -BatchId $reusePlanB.BatchId -RepositoryStateProvider $invokeArgs.RepositoryStateProvider -ReuseBatchRunContext
            }finally{$networkProbe.Timeout=$false}
            Equal $reuseRunB.Code P52B_NETWORK_POLICY_STOP 'Cached FAILED payload never bypasses strict budget'
            Equal $reuseRunB.Summary.CommittedCount 1 'Timeout item commits diagnostic failure before policy stop'
            Equal $reuseRunB.Items[0].OperationalStatus FAILED 'Timeout item retains OperationalStatus FAILED'
            Equal $reuseRunB.Summary.NotStartedCount 2 'Subsequent items stay NOT_STARTED after budget exhaustion'
            Equal $reuseRunB.NetworkExecution.AttemptedCount 1 'Strict timeout attempted count 1'
            Equal ($networkProbe.Calls-$reuseStartB) 1 'Strict timeout physical call count 1'

            # Opt-in -ReuseBatchRunContext Test C: MMA JSONP 2-business shared LIST with strict MaxPhysicalAttempts = 3 (1 LIST + 2 DETAILs).
            $mmaReuseRows=$rows | ConvertTo-Json -Depth 10 | ConvertFrom-Json
            $mmaReuseRows[0].업소명='(유)투투여행사';$mmaReuseRows[0].소재지도로명주소='서울특별시 테스트구 여행로 2789';$mmaReuseRows[0].업소전화번호='02-2789-0000';$mmaReuseRows[0].출처유형='병무청 공식 자료';$mmaReuseRows[0].출처URL='https://www.mma.go.kr/about/udgg/list.do?mc=mma0003357'
            $mmaReuseRows[2].업소명='(주) 예쁜떡 오늘';$mmaReuseRows[2].소재지도로명주소='서울특별시 테스트구 떡로 2740';$mmaReuseRows[2].업소전화번호='02-2740-0000';$mmaReuseRows[2].출처유형='병무청 공식 자료';$mmaReuseRows[2].출처URL='https://www.mma.go.kr/about/udgg/list.do?mc=mma0003357'
            $mmaReuseCsv=Join-Path $root 'mma-reuse.csv';$mmaReuseRows | Export-Csv -LiteralPath $mmaReuseCsv -NoTypeInformation -Encoding utf8
            $reuseC=$args51.Clone();$reuseC.CanonicalCsvPath=$mmaReuseCsv;$reuseC.BusinessIds=@($ids[0],$ids[2]);$reuseC.Store=New-HistoryStoreLayout -Root (Join-Path $root 'reuse-mma-history');$reuseC.BatchWorkspaceRoot=Join-Path $root 'reuse-mma-batches';$reuseC.NetworkPolicy=New-Phase5BenefitNetworkPolicy -AllowedHttpsHosts @('open.mma.go.kr') -MaxPhysicalAttempts 3
            $reusePlanC=New-Phase5BenefitBatchPlan @reuseC;$reuseStartC=$networkProbe.Calls
            $networkProbe.Family='MMA'
            try{
                $reuseRunC=Invoke-Phase5BenefitBatch @reuseC -BatchId $reusePlanC.BatchId -RepositoryStateProvider $invokeArgs.RepositoryStateProvider -ReuseBatchRunContext
            }finally{$networkProbe.Family='HTML'}
            Equal $reuseRunC.Status FINISHED 'ReuseBatchRunContext MMA shared-LIST batch finishes'
            Equal $reuseRunC.Summary.CommittedCount 2 'ReuseBatchRunContext MMA batch commits 2 items'
            Equal $reuseRunC.Summary.CommittedOperationalCompleteCount 2 'ReuseBatchRunContext MMA batch completes both items'
            Equal ($networkProbe.Calls-$reuseStartC) 3 'ReuseBatchRunContext MMA batch dispatches 1 LIST + 2 DETAILs'
            Equal $reuseRunC.NetworkExecution.AttemptedCount 3 'ReuseBatchRunContext MMA batch NetworkExecution AttemptedCount 3'
            Equal $reuseRunC.Metrics.ExternalFetchCount.Total 3 'ReuseBatchRunContext MMA batch ExternalFetchCount 3'
            Equal $reuseRunC.Metrics.FetchCacheHits.Total 1 'ReuseBatchRunContext MMA batch FetchCacheHits 1'
            Equal $reuseRunC.Metrics.ParseCount.Total 3 'ReuseBatchRunContext MMA batch ParseCount 3'
            Equal $reuseRunC.Metrics.AdapterReuseCount.Total 1 'ReuseBatchRunContext MMA batch AdapterReuseCount 1'
            Equal @($reuseRunC.Items | Where-Object BenefitState -CEQ 'NEEDS_VERIFICATION').Count 2 'ReuseBatchRunContext MMA items stay NEEDS_VERIFICATION'
            $reuseRecCStart=$networkProbe.Calls;$reuseRecCInv=Inventory $reuseC.Store.Root
            $reuseRecC=Invoke-Phase5BenefitBatch @reuseC -BatchId $reusePlanC.BatchId -Mode RecoverOnly -RepositoryStateProvider $invokeArgs.RepositoryStateProvider
            Equal $reuseRecC.Status FINISHED 'ReuseBatchRunContext MMA RecoverOnly finishes'
            Equal $reuseRecC.Summary.RecoveredCount 2 'ReuseBatchRunContext MMA RecoverOnly recovers 2 items'
            Equal ($networkProbe.Calls-$reuseRecCStart) 0 'ReuseBatchRunContext MMA RecoverOnly makes 0 network calls'
            Equal (Inventory $reuseC.Store.Root) $reuseRecCInv 'ReuseBatchRunContext MMA RecoverOnly History unchanged'
            Write-Host 'P5-2B ReuseBatchRunContext PASS: HTML C-Lite batch1/batch2 reuse, failed-payload budget guard, MMA shared LIST+2 DETAIL'
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

        # Unprimed (no previous baseline) first-run unsupported HTML response must route to OPERATIONAL_DIAGNOSTIC without stopping batch.
        $unprimedArgs=$args51.Clone();$unprimedArgs.BusinessIds=@($ids[0],$ids[2]);$unprimedArgs.Store=New-HistoryStoreLayout -Root (Join-Path $root 'unprimed-fail-history');$unprimedArgs.BatchWorkspaceRoot=Join-Path $root 'unprimed-fail-batches'
        $unprimedPlan=New-Phase5BenefitBatchPlan @unprimedArgs
        $unprimedCalls=[pscustomobject]@{Count=0}
        $unprimedHttp={param($Uri);$unprimedCalls.Count++;if($unprimedCalls.Count -eq 1){return [pscustomobject]@{StatusCode=200;ContentType='text/html';Text='<html><body><h2>blocked stub</h2></body></html>';Bytes=$null}};[pscustomobject]@{StatusCode=200;ContentType='text/html';Text=$html;Bytes=$null}}.GetNewClosure()
        $unprimed=Invoke-Phase5BenefitBatch @unprimedArgs -BatchId $unprimedPlan.BatchId -RepositoryStateProvider $invokeArgs.RepositoryStateProvider -RequestInvoker $unprimedHttp
        Equal $unprimedCalls.Count 2 'Unprimed batch isolates first operational failure and continues to second business'
        Equal $unprimed.Status FINISHED 'Unprimed operational failure routed cleanly as OPERATIONAL_DIAGNOSTIC'
        Equal $unprimed.Summary.CommittedCount 2 'Both unprimed items commit'
        Equal $unprimed.Summary.CommittedOperationalFailureCount 1 'Unprimed operational failure counted separately'
        Equal $unprimed.Summary.CommittedOperationalCompleteCount 1 'Second business operational complete counted'
        Equal $unprimed.Items[0].OperationalStatus FAILED 'First item stays operational FAILED'
        Equal $unprimed.Items[0].Review.ReviewRoute OPERATIONAL_DIAGNOSTIC 'First-run operational failure routes to OPERATIONAL_DIAGNOSTIC'
        Check (@($unprimed.Items[0].Comparison.ChangeCandidates) -contains 'OPERATIONAL_FAILURE') 'First-run failure comparison records OPERATIONAL_FAILURE'
        Check (@($unprimed.Items[0].Comparison.ChangeCandidates) -notcontains 'BASELINE_ESTABLISHED') 'First-run failure does not claim BASELINE_ESTABLISHED'
        Equal @(Get-ChildItem -LiteralPath $unprimedArgs.Store.ArtifactsRoot -Filter '*.html' -File).Count 0 'Unprimed C_LITE_V1 batch writes 0 .html files'
        Equal $unprimed.Items[1].OperationalStatus COMPLETE 'Second business remains unaffected COMPLETE'

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

        # PR 3A: Phase 5 RecoverOnly batch compatibility with C-Lite capture and v2 reuse records.
        . (Join-Path $PSScriptRoot 'lib/history/benefit-scoped-html-capture-builder.ps1')
        $cStore=New-HistoryStoreLayout -Root (Join-Path $root 'clite-batch-history')
        $cBatchRoot=Join-Path $root 'clite-batch-ws'
        $cObsAt='2026-11-19T12:34:56.000+09:00'
        $cBatchArgs=@{CanonicalCsvPath=$csv;BusinessIds=@($ids[0],$ids[2]);Store=$cStore;BatchWorkspaceRoot=$cBatchRoot;ObservedAt=$cObsAt;RepositoryRevision=$args51.RepositoryRevision}
        $cPlan=New-Phase5BenefitBatchPlan @cBatchArgs
        $cUrl=$rows[0].출처URL

        # Business 0: C-Lite capture committed under batch RunId 0.
        $b0Biz=ConvertTo-NormalizedBusiness -Row $rows[0] -SourceRowNumber 2
        $b0Ben=ConvertTo-Phase2CanonicalBenefitRecord -Row $rows[0] -SourceRowNumber 2
        $b0Cand=Get-ExistingBenefitSourceCandidate -Benefit $b0Ben; $b0Cand.ObservedAt=$cObsAt
        $b0Ctx=New-BenefitSourceRunContext
        $b0Rec=Invoke-ScopedPhase2BenefitSourceCandidate -Candidate $b0Cand -Business $b0Biz -CanonicalPhone $rows[0].업소전화번호 -RunContext $b0Ctx -RequestInvoker {param($Uri)[pscustomobject]@{StatusCode=200;ContentType='text/html';Text=$html;Bytes=$null}}.GetNewClosure()
        $b0Eval=Get-Phase2BenefitEvaluation -Benefit $b0Ben -SourceRecords @($b0Rec) -DiscoveryStatus COMPLETE
        $b0Reasons=[Collections.Generic.List[string]]::new();Add-Phase2UniqueReasonCodes -Target $b0Reasons -ReasonCodes $b0Eval.Evaluation.ReasonCodes;Add-Phase2UniqueReasonCodes -Target $b0Reasons -ReasonCodes $b0Rec.ReasonCodes
        $b0Res=New-BenefitVerificationResult -SourceRowNumber 2 -BusinessIdentity $b0Biz -BenefitState $b0Eval.Evaluation.BenefitState -ReviewClass $b0Eval.Evaluation.ReviewClass -ReasonCodes @($b0Reasons) -ClaimResults $b0Eval.ClaimResults -Evidence $b0Eval.Evaluation.Evidence -Warnings $b0Eval.Evaluation.Warnings -ProductionAction NONE
        $b0Pkg=New-BenefitScopedHtmlCaptureCandidate -RunContext $b0Ctx -SourceRecord $b0Rec -Benefit $b0Ben -BusinessId $ids[0] -BusinessIdentity $b0Biz -CanonicalPhone $rows[0].업소전화번호 -Result $b0Res -OperationalStatus $b0Eval.OperationalStatus -RunId $cPlan.Items[0].RunId -ObservedAt $cObsAt -RepositoryRevision $cBatchArgs.RepositoryRevision
        $b0Arts=@(foreach($a in $b0Pkg.Candidate.Artifacts){[pscustomobject]@{ContentHash=$a.Reference.ContentHash;Extension='json';Kind=$a.Reference.Kind;Text=$a.Text}})
        $b0Man=New-HistoryRunManifest -RunId $cPlan.Items[0].RunId -StartedAt $cObsAt -CompletedAt '' -RepositoryRevision $cBatchArgs.RepositoryRevision -RequestedBusinessIds @($ids[0]) -CompletedBusinessIds @($ids[0]) -FailedBusinessIds @() -ExecutionStatus COMPLETE -RunCommitStatus PREPARED
        $b0Prep=Prepare-HistoryRun -Store $cStore -RunManifest $b0Man -Artifacts $b0Arts -Observations @($b0Pkg.Candidate.Observation) -Comparisons @()
        Equal (Commit-HistoryRun -Store $cStore -PreparedRun $b0Prep -ExpectedBaselines @{($ids[0]+'|BENEFIT')=''}).Code COMMITTED 'P5-1 C-Lite capture item commits'

        # Business 1 (ids[2]): prior C-Lite capture then v2 reuse committed under batch RunId 1.
        $b1SeedObsAt='2026-11-19T11:34:56.000+09:00'
        $b1Biz=ConvertTo-NormalizedBusiness -Row $rows[2] -SourceRowNumber 4
        $b1Ben=ConvertTo-Phase2CanonicalBenefitRecord -Row $rows[2] -SourceRowNumber 4
        $b1SeedCand=Get-ExistingBenefitSourceCandidate -Benefit $b1Ben; $b1SeedCand.ObservedAt=$b1SeedObsAt
        $b1SeedCtx=New-BenefitSourceRunContext
        $b1SeedRec=Invoke-ScopedPhase2BenefitSourceCandidate -Candidate $b1SeedCand -Business $b1Biz -CanonicalPhone $rows[2].업소전화번호 -RunContext $b1SeedCtx -RequestInvoker {param($Uri)[pscustomobject]@{StatusCode=200;ContentType='text/html';Text=$html;Bytes=$null}}.GetNewClosure()
        $b1SeedEval=Get-Phase2BenefitEvaluation -Benefit $b1Ben -SourceRecords @($b1SeedRec) -DiscoveryStatus COMPLETE
        $b1SeedReasons=[Collections.Generic.List[string]]::new();Add-Phase2UniqueReasonCodes -Target $b1SeedReasons -ReasonCodes $b1SeedEval.Evaluation.ReasonCodes;Add-Phase2UniqueReasonCodes -Target $b1SeedReasons -ReasonCodes $b1SeedRec.ReasonCodes
        $b1SeedRes=New-BenefitVerificationResult -SourceRowNumber 4 -BusinessIdentity $b1Biz -BenefitState $b1SeedEval.Evaluation.BenefitState -ReviewClass $b1SeedEval.Evaluation.ReviewClass -ReasonCodes @($b1SeedReasons) -ClaimResults $b1SeedEval.ClaimResults -Evidence $b1SeedEval.Evaluation.Evidence -Warnings $b1SeedEval.Evaluation.Warnings -ProductionAction NONE
        $b1SeedPkg=New-BenefitScopedHtmlCaptureCandidate -RunContext $b1SeedCtx -SourceRecord $b1SeedRec -Benefit $b1Ben -BusinessId $ids[2] -BusinessIdentity $b1Biz -CanonicalPhone $rows[2].업소전화번호 -Result $b1SeedRes -OperationalStatus $b1SeedEval.OperationalStatus -RunId 'run-clite-b1-seed' -ObservedAt $b1SeedObsAt -RepositoryRevision $cBatchArgs.RepositoryRevision
        $b1SeedArts=@(foreach($a in $b1SeedPkg.Candidate.Artifacts){[pscustomobject]@{ContentHash=$a.Reference.ContentHash;Extension='json';Kind=$a.Reference.Kind;Text=$a.Text}})
        $b1SeedMan=New-HistoryRunManifest -RunId 'run-clite-b1-seed' -StartedAt $b1SeedObsAt -CompletedAt '' -RepositoryRevision $cBatchArgs.RepositoryRevision -RequestedBusinessIds @($ids[2]) -CompletedBusinessIds @($ids[2]) -FailedBusinessIds @() -ExecutionStatus COMPLETE -RunCommitStatus PREPARED
        $b1SeedPrep=Prepare-HistoryRun -Store $cStore -RunManifest $b1SeedMan -Artifacts $b1SeedArts -Observations @($b1SeedPkg.Candidate.Observation) -Comparisons @()
        Equal (Commit-HistoryRun -Store $cStore -PreparedRun $b1SeedPrep -ExpectedBaselines @{($ids[2]+'|BENEFIT')=''}).Code COMMITTED 'P5-1 C-Lite prior capture commits'

        $b1ReuseCtx=New-BenefitSourceRunContext
        $b1ReuseCand=Get-ExistingBenefitSourceCandidate -Benefit $b1Ben; $b1ReuseCand.ObservedAt=$cObsAt
        $b1ReuseDoc=Get-BenefitRunSourceDocument -Context $b1ReuseCtx -Candidate $b1ReuseCand -RequestInvoker {param($Uri)[pscustomobject]@{StatusCode=200;ContentType='text/html';Text=$html;Bytes=$null}}.GetNewClosure()
        [void](Get-BenefitRunSourceSnapshot -Context $b1ReuseCtx -Document $b1ReuseDoc)
        $b1ReusePkg=New-BenefitScopedHtmlReusePackage -Store $cStore -PreviousObservationId $b1SeedPkg.Candidate.Observation.ObservationId -RunContext $b1ReuseCtx -Candidate $b1ReuseCand -Document $b1ReuseDoc -Benefit $b1Ben -BusinessId $ids[2] -BusinessIdentity $b1Biz -CanonicalPhone $rows[2].업소전화번호 -RunId $cPlan.Items[1].RunId -ObservedAt $cObsAt -RepositoryRevision $cBatchArgs.RepositoryRevision -RepositoryClean $true
        $b1ReuseMan=New-HistoryRunManifest -RunId $cPlan.Items[1].RunId -StartedAt $cObsAt -CompletedAt '' -RepositoryRevision $cBatchArgs.RepositoryRevision -RequestedBusinessIds @($ids[2]) -CompletedBusinessIds @($ids[2]) -FailedBusinessIds @() -ExecutionStatus COMPLETE -RunCommitStatus PREPARED
        $b1ReusePrep=Prepare-HistoryRun -Store $cStore -RunManifest $b1ReuseMan -Artifacts $b1ReusePkg.Package.PreparedArtifacts -Observations @($b1ReusePkg.Package.Observation) -Comparisons @($b1ReusePkg.Package.Comparison)
        Equal (Commit-HistoryRun -Store $cStore -PreparedRun $b1ReusePrep -ExpectedBaselines @{($ids[2]+'|BENEFIT')=$b1SeedPkg.Candidate.Observation.ObservationId}).Code COMMITTED 'P5-1 C-Lite reuse item commits'

        $cBeforeInv=Inventory $cStore.Root; $cBeforeHttp=$requests.Urls.Count
        $cRec=Invoke-Phase5BenefitBatch @cBatchArgs @invokeArgs -BatchId $cPlan.BatchId -Mode RecoverOnly
        Equal $cRec.Status FINISHED 'P5-1 C-Lite RecoverOnly succeeds'
        Equal $cRec.Summary.RecoveredCount 2 'P5-1 C-Lite recovers both capture and reuse items'
        Equal $cRec.Items[0].ObservationId $b0Pkg.Candidate.Observation.ObservationId 'P5-1 C-Lite capture ObservationId preserved'
        Equal $cRec.Items[1].ObservationId $b1ReusePkg.Package.Observation.ObservationId 'P5-1 C-Lite reuse ObservationId preserved'
        Equal $cRec.Items[1].Comparison.ComparisonId $b1ReusePkg.Package.Comparison.ComparisonId 'P5-1 C-Lite reuse ComparisonId preserved'
        Equal $requests.Urls.Count $cBeforeHttp 'P5-1 C-Lite RecoverOnly fetch0'
        Equal (Inventory $cStore.Root) $cBeforeInv 'P5-1 C-Lite RecoverOnly History unchanged'

        # Negative control: corrupted scoped artifact blocks batch recovery.
        $b0ScopedRef=@($b0Pkg.Candidate.Observation.ArtifactReferences | Where-Object Kind -CEQ 'BENEFIT_SCOPED_EVIDENCE')[0]
        $b0ScopedPath=Join-Path $cStore.Root $b0ScopedRef.RelativePath
        $origB0Scoped=[IO.File]::ReadAllBytes($b0ScopedPath)
        try{
            [IO.File]::WriteAllText($b0ScopedPath,'{"tampered":true}')
            $cBad=Invoke-Phase5BenefitBatch @cBatchArgs @invokeArgs -BatchId $cPlan.BatchId -Mode RecoverOnly
            Equal $cBad.Status BLOCKED 'P5-1 corrupted C-Lite scoped artifact blocks recovery'
            Equal $requests.Urls.Count $cBeforeHttp 'P5-1 corrupted C-Lite recovery fetch0'
        }finally{[IO.File]::WriteAllBytes($b0ScopedPath,$origB0Scoped)}

        # Step A: Default P5-1 batch Execute wiring for C_LITE_V1 capture, reuse, and RecoverOnly.
        $batchProfileCmd=Get-Command Get-InternalPhase5HtmlEvidenceRetentionProfile -ErrorAction SilentlyContinue
        Check ($null -ne $batchProfileCmd) 'PR3B retention profile helper must exist for batch'
        Equal (& $batchProfileCmd.ScriptBlock) C_LITE_V1 'Default P5-1 batch retention profile is C_LITE_V1'
        $ceStore=New-HistoryStoreLayout -Root (Join-Path $root 'clite-exec-batch-history')
        $ceBatchRoot=Join-Path $root 'clite-exec-batch-ws'
        $ceArgs1=@{CanonicalCsvPath=$csv;BusinessIds=@($ids[0],$ids[2]);Store=$ceStore;BatchWorkspaceRoot=$ceBatchRoot;ObservedAt='2026-11-19T15:00:00.000+09:00';RepositoryRevision=$args51.RepositoryRevision}
        $cePlan1=New-Phase5BenefitBatchPlan @ceArgs1
        $ceRun1=Invoke-Phase5BenefitBatch @ceArgs1 @invokeArgs -BatchId $cePlan1.BatchId
        Equal $ceRun1.Status FINISHED 'P5-1 default C_LITE_V1 Execute batch1 finishes'
        Equal $ceRun1.Summary.CommittedCount 2 'P5-1 default C_LITE_V1 batch1 commits 2 items'
        Equal $ceRun1.Summary.ExecutedCount 2 'P5-1 default C_LITE_V1 batch1 executes 2 items'
        Equal $ceRun1.Metrics.ReuseApplied.Total 0 'P5-1 default C_LITE_V1 batch1 reuse0'
        Equal $ceRun1.Metrics.ParseCount.Total 2 'P5-1 default C_LITE_V1 batch1 parses both items'
        Equal @(Get-ChildItem -LiteralPath $ceStore.ArtifactsRoot -Filter '*.html' -File).Count 0 'P5-1 default C_LITE_V1 batch1 writes 0 .html files'
        foreach($item in $ceRun1.Items){
            $obs=Read-HistoryObservation -Store $ceStore -ObservationId $item.ObservationId
            Equal @($obs.ArtifactReferences).Count 3 'P5-1 default C_LITE_V1 batch1 capture has 3 artifacts'
            Equal @($obs.ArtifactReferences | Where-Object Kind -CEQ 'RAW_SOURCE_PAYLOAD').Count 0 'P5-1 default C_LITE_V1 batch1 capture has 0 RAW'
        }

        $ceArgs2=@{CanonicalCsvPath=$csv;BusinessIds=@($ids[0],$ids[2]);Store=$ceStore;BatchWorkspaceRoot=$ceBatchRoot;ObservedAt='2026-11-19T15:10:00.000+09:00';RepositoryRevision=$args51.RepositoryRevision}
        $cePlan2=New-Phase5BenefitBatchPlan @ceArgs2
        $ceRun2=Invoke-Phase5BenefitBatch @ceArgs2 @invokeArgs -BatchId $cePlan2.BatchId
        Equal $ceRun2.Status FINISHED 'P5-1 default C_LITE_V1 Execute batch2 finishes'
        Equal $ceRun2.Summary.CommittedCount 2 'P5-1 default C_LITE_V1 batch2 commits 2 reuse items'
        Equal $ceRun2.Metrics.ReuseApplied.Total 2 'P5-1 default C_LITE_V1 batch2 reuses both items'
        Equal $ceRun2.Metrics.ParseCount.Total 0 'P5-1 default C_LITE_V1 batch2 avoids parse completely'
        Equal @(Get-ChildItem -LiteralPath $ceStore.ArtifactsRoot -Filter '*.html' -File).Count 0 'P5-1 default C_LITE_V1 batch2 writes 0 .html files'
        foreach($item in $ceRun2.Items){
            $obs=Read-HistoryObservation -Store $ceStore -ObservationId $item.ObservationId
            Equal @($obs.ArtifactReferences).Count 4 'P5-1 default C_LITE_V1 batch2 reuse has 4 artifacts'
            Equal @($obs.ArtifactReferences | Where-Object Kind -CEQ 'RAW_SOURCE_PAYLOAD').Count 0 'P5-1 default C_LITE_V1 batch2 reuse has 0 RAW'
        }

        $ceBeforeHttp=$requests.Urls.Count
        $ceBeforeInv=Inventory $ceStore.Root
        $ceRec2=Invoke-Phase5BenefitBatch @ceArgs2 @invokeArgs -BatchId $cePlan2.BatchId -Mode RecoverOnly
        Equal $ceRec2.Status FINISHED 'P5-1 default C_LITE_V1 RecoverOnly succeeds on executed batch2'
        Equal $ceRec2.Summary.RecoveredCount 2 'P5-1 default C_LITE_V1 RecoverOnly recovers 2 items'
        Equal $requests.Urls.Count $ceBeforeHttp 'P5-1 default C_LITE_V1 RecoverOnly fetch0'
        Equal (Inventory $ceStore.Root) $ceBeforeInv 'P5-1 default C_LITE_V1 RecoverOnly History unchanged'

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
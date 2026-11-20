Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$opsRunnerPath = Join-Path $PSScriptRoot 'invoke-phase5-ops-cycle.ps1'
if (-not (Test-Path -LiteralPath $opsRunnerPath)) {
    throw 'Missing invoke-phase5-ops-cycle.ps1'
}
. $opsRunnerPath
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-location/test-support.ps1')

function Assert-OpsTrue($Condition, [string]$Message) {
    if (-not $Condition) { throw "ASSERT_TRUE_FAILED: $Message" }
}
function Assert-OpsEqual($Actual, $Expected, [string]$Message) {
    if ($Actual -cne $Expected) { throw "ASSERT_EQUAL_FAILED: $Message (expected='$Expected' actual='$Actual')" }
}
function Assert-OpsThrows([scriptblock]$Action, [string]$Message) {
    $threw = $false
    try { & $Action | Out-Null } catch { $threw = $true }
    if (-not $threw) { throw "ASSERT_THROWS_FAILED: $Message" }
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('milimap-p5ops-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($tempRoot)

try {
    $repoRoot = (Get-Phase5BenefitRepositoryRoots)[0]
    $headRev = ([string](& git -C $repoRoot rev-parse HEAD)).Trim()

    $ids = @(
        'biz-10000000000000000000000000000001',
        'biz-20000000000000000000000000000002',
        'biz-30000000000000000000000000000003'
    )
    $rowHtml = New-ScopeTestRow -Name '운영테스트식당' -Building '15' -Phone '02-555-0101'
    $rowHtml | Add-Member NoteProperty businessId $ids[0]

    $rowMma = New-ScopeTestRow -Name '운영테스트여행사' -Building '20' -Phone '02-555-0202'
    $rowMma | Add-Member NoteProperty businessId $ids[1]
    $rowMma.'출처유형' = '병무청 공식 자료'
    $rowMma.'출처URL' = 'https://www.mma.go.kr/about/udgg/list.do?mc=mma0003357'

    $rowXlsx = New-ScopeTestRow -Name '운영테스트카페' -Building '25' -Phone '02-555-0303'
    $rowXlsx | Add-Member NoteProperty businessId $ids[2]
    $rowXlsx.'출처URL' = 'https://city.example.go.kr/benefits/list.xlsx'

    $csvPath = Join-Path $tempRoot 'canonical-ops.csv'
    @($rowHtml, $rowMma, $rowXlsx) | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding utf8

    $html = '<table><tr><th>업소명</th><th>주소</th><th>전화번호</th><th>할인</th></tr>' +
        "<tr><td>$($rowHtml.업소명)</td><td>$($rowHtml.소재지도로명주소)</td><td>$($rowHtml.업소전화번호)</td><td>10% 할인</td></tr></table>"

    $httpState = [pscustomobject]@{ Calls = 0 }
    $httpInvoker = {
        param($Uri)
        $httpState.Calls++
        [pscustomobject]@{ StatusCode = 200; ContentType = 'text/html'; Text = $html; Bytes = $null }
    }.GetNewClosure()
    $cleanRepo = { [pscustomobject]@{ IsClean = $true } }

    # 1. PlanOnly: zero disk writes, zero HTTP, Plan v1 + Plan v2 + mixed retention profile classification.
    $planHistory = Join-Path $tempRoot 'planonly-history'
    $planWorkspace = Join-Path $tempRoot 'planonly-batches'
    $planReviewOut = Join-Path $tempRoot 'planonly-review'
    $planPilotLog = Join-Path $tempRoot 'planonly-pilot.ndjson'

    $planOnly = Invoke-Phase5OpsCycle `
        -CanonicalCsvPath $csvPath `
        -BusinessIds $ids `
        -HistoryRoot $planHistory `
        -BatchWorkspaceRoot $planWorkspace `
        -ReviewQueueOutputDirectory $planReviewOut `
        -Mode 'PlanOnly' `
        -ObservedAt '2026-11-20T01:00:00Z' `
        -RepositoryRevision $headRev `
        -PilotLogPath $planPilotLog `
        -MaxRolling24hPhysicalAttempts 3

    Assert-OpsEqual $planOnly.Mode 'PlanOnly' 'PlanOnly mode preserved'
    Assert-OpsEqual $planOnly.Status 'READY' 'PlanOnly status READY'
    Assert-OpsEqual $planOnly.Plan.PlanCore.PlanVersion 1 'PlanOnly without NetworkPolicy builds PlanVersion 1'
    Assert-OpsEqual $planOnly.RetentionProfiles[0].RetentionProfile 'C_LITE_V1' 'HTML source uses C_LITE_V1'
    Assert-OpsEqual $planOnly.RetentionProfiles[1].RetentionProfile 'LEGACY' 'MMA JSONP source retains LEGACY'
    Assert-OpsEqual $planOnly.RetentionProfiles[2].RetentionProfile 'LEGACY' 'XLSX source retains LEGACY'
    Assert-OpsEqual $planOnly.Inspection.HistoryState 'ABSENT' 'PlanOnly detects absent History cleanly'
    Assert-OpsEqual $planOnly.ProductionAction 'NONE' 'PlanOnly ProductionAction NONE'
    Assert-OpsTrue $planOnly.ApprovalRequired 'PlanOnly requires approval'
    Assert-OpsTrue (-not (Test-Path -LiteralPath $planHistory)) 'PlanOnly creates no HistoryRoot'
    Assert-OpsTrue (-not (Test-Path -LiteralPath $planWorkspace)) 'PlanOnly creates no BatchWorkspaceRoot'
    Assert-OpsTrue (-not (Test-Path -LiteralPath $planReviewOut)) 'PlanOnly creates no ReviewQueueOutputDirectory'
    Assert-OpsTrue (-not (Test-Path -LiteralPath $planPilotLog)) 'PlanOnly creates no PilotLogPath'
    Assert-OpsEqual $httpState.Calls 0 'PlanOnly performs zero HTTP calls'

    # PlanOnly with strict Plan v2 NetworkPolicy
    $strictPolicy = New-Phase5BenefitNetworkPolicy -AllowedHttpsHosts @('city.example.go.kr') -MaxPhysicalAttempts 1 -RequestTimeoutMilliseconds 15000 -MaxResponseBodyBytes 2097152 -MaxResponseHeaderBytes 16384
    $planStrict = Invoke-Phase5OpsCycle `
        -CanonicalCsvPath $csvPath `
        -BusinessIds @($ids[0]) `
        -HistoryRoot $planHistory `
        -BatchWorkspaceRoot $planWorkspace `
        -ReviewQueueOutputDirectory $planReviewOut `
        -Mode 'PlanOnly' `
        -ObservedAt '2026-11-20T01:00:00Z' `
        -RepositoryRevision $headRev `
        -NetworkPolicy $strictPolicy `
        -PilotLogPath $planPilotLog `
        -MaxRolling24hPhysicalAttempts 1
    Assert-OpsEqual $planStrict.Status 'READY' 'Strict PlanOnly READY'
    Assert-OpsEqual $planStrict.Plan.PlanCore.PlanVersion 2 'Strict PlanOnly produces PlanVersion 2'
    Assert-OpsEqual $planStrict.PilotBudget.Status 'ALLOWED' 'Strict PlanOnly budget ALLOWED'
    Assert-OpsTrue (-not (Test-Path -LiteralPath $planHistory)) 'Strict PlanOnly creates no HistoryRoot'

    # 2. Execute 1st run (HTML C_LITE_V1 capture -> 0 RAW) -> Inspect -> ExportReviewQueue -> summary receipt.
    $execHistory = Join-Path $tempRoot 'exec-history'
    $execWorkspace = Join-Path $tempRoot 'exec-batches'
    $execReviewOut = Join-Path $tempRoot 'exec-review'
    $execPilotLog = Join-Path $tempRoot 'exec-pilot.ndjson'

    $exec1 = Invoke-Phase5OpsCycle `
        -CanonicalCsvPath $csvPath `
        -BusinessIds @($ids[0]) `
        -HistoryRoot $execHistory `
        -BatchWorkspaceRoot $execWorkspace `
        -ReviewQueueOutputDirectory $execReviewOut `
        -Mode 'Execute' `
        -ObservedAt '2026-11-20T02:00:00Z' `
        -RepositoryRevision $headRev `
        -RequestInvoker $httpInvoker `
        -RepositoryStateProvider $cleanRepo `
        -PilotLogPath $execPilotLog `
        -MaxRolling24hPhysicalAttempts 1

    Assert-OpsEqual $exec1.Status 'FINISHED' 'Execute 1 finishes cleanly'
    Assert-OpsEqual $exec1.BatchResult.Summary.CommittedCount 1 'Execute 1 commits 1 item'
    Assert-OpsEqual $exec1.BatchResult.Metrics.ParseCount.Total 1 'Execute 1 parses once'
    Assert-OpsEqual $exec1.Inspection.HistoryState 'VERIFIED' 'Execute 1 inspector verifies History'
    Assert-OpsEqual $exec1.ReviewQueueExport.Summary.ExportedItemCount 1 'Execute 1 exports 1 review queue item'
    Assert-OpsEqual $exec1.ProductionAction 'NONE' 'Execute 1 ProductionAction NONE'
    Assert-OpsEqual @(Get-ChildItem -LiteralPath (Join-Path $execHistory 'artifacts/sha256') -Filter '*.html' -File).Count 0 'Execute 1 stores 0 .html RAW files'
    Assert-OpsTrue (Test-Path -LiteralPath $exec1.ReceiptPath -PathType Leaf) 'Execute 1 writes ops-cycle-summary.json'
    Assert-OpsTrue (Test-Path -LiteralPath $exec1.ReviewQueueExport.SummaryJsonPath -PathType Leaf) 'Execute 1 writes review-queue-summary.json'
    Assert-OpsTrue (Test-Path -LiteralPath $exec1.ReviewQueueExport.ItemsCsvPath -PathType Leaf) 'Execute 1 writes review-queue-items.csv'
    $rawLeakCheck = [IO.File]::ReadAllText($exec1.ReviewQueueExport.SummaryJsonPath)
    Assert-OpsTrue ($rawLeakCheck -notmatch '<td>') 'Review queue summary never leaks raw HTML'

    # 3. Rolling-24h pilot cap blocks second Execute within 24h BEFORE any HTTP or History writes.
    $beforeBlockedHttp = $httpState.Calls
    $blocked24h = Invoke-Phase5OpsCycle `
        -CanonicalCsvPath $csvPath `
        -BusinessIds @($ids[0]) `
        -HistoryRoot $execHistory `
        -BatchWorkspaceRoot $execWorkspace `
        -ReviewQueueOutputDirectory $execReviewOut `
        -Mode 'Execute' `
        -ObservedAt '2026-11-20T03:00:00Z' `
        -RepositoryRevision $headRev `
        -RequestInvoker $httpInvoker `
        -RepositoryStateProvider $cleanRepo `
        -PilotLogPath $execPilotLog `
        -MaxRolling24hPhysicalAttempts 1

    Assert-OpsEqual $blocked24h.Status 'BLOCKED' 'Rolling-24h cap blocks Execute within 24h'
    Assert-OpsEqual $blocked24h.Code 'OPS_ROLLING_24H_BUDGET_EXCEEDED' 'Rolling-24h cap returns exact reason code'
    Assert-OpsEqual $blocked24h.PilotBudget.Recent24hAttemptCount 1 'Recent 24h attempts = 1'
    Assert-OpsEqual $httpState.Calls $beforeBlockedHttp 'Blocked rolling-24h performs 0 HTTP calls'

    # 4. Execute after >24h succeeds with C_LITE_V1 reuse (ParseCount=0, 0 .html files).
    $exec2 = Invoke-Phase5OpsCycle `
        -CanonicalCsvPath $csvPath `
        -BusinessIds @($ids[0]) `
        -HistoryRoot $execHistory `
        -BatchWorkspaceRoot $execWorkspace `
        -ReviewQueueOutputDirectory $execReviewOut `
        -Mode 'Execute' `
        -ObservedAt '2026-11-21T02:00:01Z' `
        -RepositoryRevision $headRev `
        -RequestInvoker $httpInvoker `
        -RepositoryStateProvider $cleanRepo `
        -PilotLogPath $execPilotLog `
        -MaxRolling24hPhysicalAttempts 1

    Assert-OpsEqual $exec2.Status 'FINISHED' 'Execute after 24h finishes'
    Assert-OpsEqual $exec2.BatchResult.Summary.CommittedCount 1 'Execute after 24h commits reuse observation'
    Assert-OpsEqual $exec2.BatchResult.Metrics.ReuseApplied.Total 1 'Execute after 24h applies C_LITE_V1 reuse'
    Assert-OpsEqual $exec2.BatchResult.Metrics.ParseCount.Total 0 'Execute after 24h avoids HTML parse'
    Assert-OpsEqual @(Get-ChildItem -LiteralPath (Join-Path $execHistory 'artifacts/sha256') -Filter '*.html' -File).Count 0 'Execute after 24h writes 0 .html files'
    Assert-OpsEqual $exec2.ReviewQueueExport.Summary.ExportedItemCount 1 'Latest-only review queue still exports 1 latest item'

    # 5. RecoverOnly mode performs 0 HTTP and preserves History SHA inventory.
    $invBeforeRecover = (@(Get-ChildItem -LiteralPath $execHistory -Recurse -File | Sort-Object FullName | ForEach-Object { "$($_.FullName):$((Get-FileHash -LiteralPath $_.FullName).Hash)" }) -join '|')
    $httpBeforeRecover = $httpState.Calls
    $rec = Invoke-Phase5OpsCycle `
        -CanonicalCsvPath $csvPath `
        -BusinessIds @($ids[0]) `
        -HistoryRoot $execHistory `
        -BatchWorkspaceRoot $execWorkspace `
        -ReviewQueueOutputDirectory $execReviewOut `
        -Mode 'RecoverOnly' `
        -ObservedAt '2026-11-21T02:00:01Z' `
        -RepositoryRevision $headRev `
        -RepositoryStateProvider $cleanRepo

    Assert-OpsEqual $rec.Status 'FINISHED' 'RecoverOnly finishes'
    Assert-OpsEqual $rec.BatchResult.Summary.RecoveredCount 1 'RecoverOnly recovers 1 committed item'
    Assert-OpsEqual $httpState.Calls $httpBeforeRecover 'RecoverOnly performs 0 HTTP calls'
    $invAfterRecover = (@(Get-ChildItem -LiteralPath $execHistory -Recurse -File | Sort-Object FullName | ForEach-Object { "$($_.FullName):$((Get-FileHash -LiteralPath $_.FullName).Hash)" }) -join '|')
    Assert-OpsEqual $invAfterRecover $invBeforeRecover 'RecoverOnly never mutates History files'

    # RecoverOnly on absent History fails closed with 0 writes.
    $missingHist = Join-Path $tempRoot 'absent-recover-history'
    $missingRecover = Invoke-Phase5OpsCycle `
        -CanonicalCsvPath $csvPath `
        -BusinessIds @($ids[0]) `
        -HistoryRoot $missingHist `
        -BatchWorkspaceRoot (Join-Path $tempRoot 'absent-recover-batches') `
        -ReviewQueueOutputDirectory (Join-Path $tempRoot 'absent-recover-review') `
        -Mode 'RecoverOnly' `
        -ObservedAt '2026-11-20T01:00:00Z' `
        -RepositoryRevision $headRev
    Assert-OpsEqual $missingRecover.Status 'BLOCKED' 'RecoverOnly absent History returns BLOCKED'
    Assert-OpsEqual $missingRecover.Code 'OPS_HISTORY_ROOT_MISSING' 'RecoverOnly absent History exact code'
    Assert-OpsTrue (-not (Test-Path -LiteralPath $missingHist)) 'RecoverOnly absent History creates no directory'

    # 6. Fail-closed path, overlap, and custom-invoker + policy rejections.
    Assert-OpsThrows {
        Invoke-Phase5OpsCycle -CanonicalCsvPath $csvPath -BusinessIds @($ids[0]) -HistoryRoot (Join-Path $repoRoot 'forbidden-history') -BatchWorkspaceRoot $planWorkspace -ReviewQueueOutputDirectory $planReviewOut -ObservedAt '2026-11-20T01:00:00Z' -RepositoryRevision $headRev
    } 'Repository-internal HistoryRoot rejected'

    Assert-OpsThrows {
        Invoke-Phase5OpsCycle -CanonicalCsvPath $csvPath -BusinessIds @($ids[0]) -HistoryRoot $execHistory -BatchWorkspaceRoot $execHistory -ReviewQueueOutputDirectory $planReviewOut -ObservedAt '2026-11-20T01:00:00Z' -RepositoryRevision $headRev
    } 'History/Workspace overlap rejected'

    Assert-OpsThrows {
        Invoke-Phase5OpsCycle -CanonicalCsvPath $csvPath -BusinessIds @($ids[0]) -HistoryRoot $execHistory -BatchWorkspaceRoot (Join-Path $execHistory 'nested-ws') -ReviewQueueOutputDirectory $planReviewOut -ObservedAt '2026-11-20T01:00:00Z' -RepositoryRevision $headRev
    } 'Nested Workspace inside History rejected'

    Assert-OpsThrows {
        Invoke-Phase5OpsCycle -CanonicalCsvPath $csvPath -BusinessIds @($ids[0]) -HistoryRoot $execHistory -BatchWorkspaceRoot $planWorkspace -ReviewQueueOutputDirectory $planReviewOut -ObservedAt '2026-11-20T01:00:00Z' -RepositoryRevision $headRev -NetworkPolicy $strictPolicy -RequestInvoker $httpInvoker
    } 'Combining NetworkPolicy with custom RequestInvoker rejected'

    # 7. Direct CLI invocation test via & (and verify zero writes in PlanOnly).
    $cliHistory = Join-Path $tempRoot 'cli-history'
    $cliWorkspace = Join-Path $tempRoot 'cli-batches'
    $cliReviewOut = Join-Path $tempRoot 'cli-review'
    $cliResult = & $opsRunnerPath `
        -CanonicalCsvPath $csvPath `
        -BusinessIds @($ids[0]) `
        -HistoryRoot $cliHistory `
        -BatchWorkspaceRoot $cliWorkspace `
        -ReviewQueueOutputDirectory $cliReviewOut `
        -Mode 'PlanOnly' `
        -ObservedAt '2026-11-20T01:00:00Z' `
        -RepositoryRevision $headRev
    Assert-OpsEqual $cliResult.Status 'READY' 'Direct CLI PlanOnly returns READY'
    Assert-OpsTrue (-not (Test-Path -LiteralPath $cliHistory)) 'Direct CLI PlanOnly writes nothing'

    Write-Host 'PASS: Phase 5 operational cycle runner tests'
} finally {
    $full = [IO.Path]::GetFullPath($tempRoot)
    if ($full.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase) -and
        ([IO.Path]::GetFileName($full)).StartsWith('milimap-p5ops-') -and
        (Test-Path -LiteralPath $full)) {
        Remove-Item -LiteralPath $full -Recurse -Force
    }
}

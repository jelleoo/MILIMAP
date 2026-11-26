Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'build-ops-dashboard-snapshot.ps1')

function Assert-OpsSnapshotEqual {
    param([AllowNull()]$Actual, [AllowNull()]$Expected, [Parameter(Mandatory)][string]$Message)
    if ($Actual -cne $Expected) {
        throw "$Message (expected: $Expected, actual: $Actual)"
    }
}

function Assert-OpsSnapshotTrue {
    param([bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

function Assert-OpsSnapshotThrowsMatching {
    param([scriptblock]$Action, [string]$Pattern, [string]$Message)
    try {
        & $Action | Out-Null
    } catch {
        if ($_.Exception.Message -match $Pattern) { return }
        throw "$Message (wrong error: $($_.Exception.Message))"
    }
    throw "$Message (did not throw)"
}

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$realManifestPath = Join-Path $repoRoot 'apps/android/app/src/main/assets/benefits.seed.manifest.json'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("milimap-ops-snapshot-test-" + [guid]::NewGuid().ToString('N'))

try {
    [void][IO.Directory]::CreateDirectory($tempRoot)

    # 1. Baseline manifest-only snapshot
    $baselineOut = Join-Path $tempRoot 'baseline.json'
    $res1 = Build-OpsDashboardSnapshot -SeedManifestJson $realManifestPath -OutputJson $baselineOut
    Assert-OpsSnapshotEqual $res1.ProductionAction 'NONE' 'Snapshot builder must always keep ProductionAction=NONE'
    Assert-OpsSnapshotTrue (Test-Path -LiteralPath $baselineOut -PathType Leaf) 'Baseline snapshot JSON should exist'

    $parsed1 = (Get-Content -Raw -Encoding utf8 -LiteralPath $baselineOut) | ConvertFrom-Json
    Assert-OpsSnapshotEqual $parsed1.ContractType 'OpsDashboardSnapshot' 'ContractType mismatch'
    Assert-OpsSnapshotEqual ([int]$parsed1.ContractVersion) 1 'ContractVersion mismatch'
    Assert-OpsSnapshotTrue ([int]$parsed1.SeedBaseline.totalCount -ge 1) 'SeedBaseline.totalCount should be >= 1'
    Assert-OpsSnapshotTrue ($null -eq $parsed1.WeeklyDrift) 'WeeklyDrift should be null when omitted'
    Assert-OpsSnapshotTrue ($null -eq $parsed1.ReviewQueue) 'ReviewQueue should be null when omitted'

    # Overwriting an existing output JSON must succeed across Windows and Linux pwsh
    [void](Build-OpsDashboardSnapshot -SeedManifestJson $realManifestPath -OutputJson $baselineOut)
    $parsedOverwrite = (Get-Content -Raw -Encoding utf8 -LiteralPath $baselineOut) | ConvertFrom-Json
    Assert-OpsSnapshotEqual $parsedOverwrite.ContractType 'OpsDashboardSnapshot' 'Overwritten snapshot ContractType mismatch'

    # 2. Full snapshot with synthetic WeeklyDrift & ReviewQueue
    $driftPath = Join-Path $tempRoot 'weekly-drift-summary.json'
    $driftObj = [pscustomobject][ordered]@{
        contractType               = 'WeeklyBenefitDriftSummary'
        contractVersion            = 1
        generatedAtUtc             = '2026-11-26T00:00:00Z'
        canonicalRowCount          = 1137
        automaticCanonicalMutation = $false
        productionAction           = 'NONE'
        sources                    = @(
            [pscustomobject][ordered]@{
                id             = 'mma'
                name           = '병무청 나라사랑가게 수도권 (open.mma.go.kr)'
                status         = 'OK'
                officialCount  = 757
                canonicalCount = 757
                detail         = '일치=757, 내용변경=0, 신규후보=0, 정본미관측=0'
                error          = ''
            }
        )
    }
    [IO.File]::WriteAllText($driftPath, ($driftObj | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))

    $rqPath = Join-Path $tempRoot 'review-queue-summary.json'
    $rqObj = [pscustomobject][ordered]@{
        ContractType    = 'Phase5ReviewQueueExport'
        ContractVersion = 1
        ExportedAt      = '2026-11-26T00:00:00Z'
        Summary         = [pscustomobject][ordered]@{
            ExportedItemCount    = 2
            FastReviewCount      = 0
            DomainReviewCount    = 1
            DiagnosticHoldCount  = 1
            BenefitItemCount     = 2
            LocationItemCount    = 0
            ApprovalRequired     = $true
            ProductionAction     = 'NONE'
        }
        Items           = @(
            [pscustomobject][ordered]@{
                OperatorBucket     = 'DOMAIN_REVIEW'
                BusinessId         = 'biz-00000000000000000000000000000001'
                BusinessName       = '테스트식당'
                Domain             = 'BENEFIT'
                ReviewKey          = 'rk-1'
                RunId              = 'run-1'
                CurrentObservationId = 'obs-1'
                ReviewRoute        = 'HUMAN_DOMAIN_REVIEW'
                OperationalStatus  = 'COMPLETE'
                Comparable         = $true
                RAW_SOURCE_PAYLOAD = 'SHOULD_BE_STRIPPED'
                ProductionAction   = 'NONE'
            },
            [pscustomobject][ordered]@{
                OperatorBucket     = 'DIAGNOSTIC_HOLD'
                BusinessId         = 'biz-00000000000000000000000000000002'
                BusinessName       = '테스트카페'
                Domain             = 'BENEFIT'
                ReviewKey          = 'rk-2'
                RunId              = 'run-1'
                CurrentObservationId = 'obs-2'
                ReviewRoute        = 'OPERATIONAL_DIAGNOSTIC'
                OperationalStatus  = 'PARTIAL'
                Comparable         = $false
                ProductionAction   = 'NONE'
            }
        )
    }
    [IO.File]::WriteAllText($rqPath, ($rqObj | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))

    $fullOut = Join-Path $tempRoot 'full.json'
    [void](Build-OpsDashboardSnapshot -SeedManifestJson $realManifestPath -WeeklyDriftSummaryJson $driftPath -ReviewQueueSummaryJson $rqPath -OutputJson $fullOut)
    $parsed2 = (Get-Content -Raw -Encoding utf8 -LiteralPath $fullOut) | ConvertFrom-Json
    Assert-OpsSnapshotEqual ([int]$parsed2.WeeklyDrift.sources.Count) 1 'WeeklyDrift sources count mismatch'
    Assert-OpsSnapshotEqual ([int]$parsed2.ReviewQueue.Summary.DomainReviewCount) 1 'DomainReviewCount mismatch'
    Assert-OpsSnapshotEqual ([int]$parsed2.ReviewQueue.Items.Count) 2 'ReviewQueue items count mismatch'
    Assert-OpsSnapshotTrue (-not ($parsed2.ReviewQueue.Items[0].PSObject.Properties.Name -contains 'RAW_SOURCE_PAYLOAD')) 'Unexpected raw payload property must be stripped'

    # 3. Path traversal and contract failure guards
    Assert-OpsSnapshotThrowsMatching {
        Build-OpsDashboardSnapshot -SeedManifestJson $realManifestPath -OutputJson (Join-Path $tempRoot '../escape.json')
    } 'REL_UNSAFE_PATH' 'Should reject .. path traversal'

    $badRqPath = Join-Path $tempRoot 'bad-rq.json'
    [IO.File]::WriteAllText($badRqPath, '{"ContractType":"WrongType"}', [Text.UTF8Encoding]::new($false))
    Assert-OpsSnapshotThrowsMatching {
        Build-OpsDashboardSnapshot -SeedManifestJson $realManifestPath -ReviewQueueSummaryJson $badRqPath -OutputJson (Join-Path $tempRoot 'bad.json')
    } 'OPS_SNAPSHOT_INVALID_REVIEW_QUEUE' 'Should reject wrong ReviewQueue ContractType'

    Write-Output 'OPS_DASHBOARD_SNAPSHOT_TEST: PASS'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

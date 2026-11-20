[CmdletBinding()]
param(
    [string]$CanonicalCsvPath = '',
    [string[]]$BusinessIds = @(),
    [string]$HistoryRoot = '',
    [string]$BatchWorkspaceRoot = '',
    [string]$ReviewQueueOutputDirectory = '',
    [ValidateSet('PlanOnly', 'Execute', 'RecoverOnly')]
    [string]$Mode = 'PlanOnly',
    [string]$ObservedAt = '',
    [string]$RepositoryRevision = '',
    $NetworkPolicy = $null,
    [ValidateSet('ALL', 'BENEFIT', 'LOCATION')]
    [string]$ReviewDomain = 'BENEFIT',
    [switch]$IncludeSuperseded,
    [string]$PilotLogPath = '',
    [int]$MaxRolling24hPhysicalAttempts = 0,
    [switch]$SkipReviewQueueExport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Capture CLI parameters before dot-sourcing history adapters that overwrite script-scope $historyRoot.
$script:OpsCycleCliInvoked = ($PSBoundParameters.Count -gt 0)
$script:OpsCycleCliParams = @{
    CanonicalCsvPath = $CanonicalCsvPath
    BusinessIds = $BusinessIds
    HistoryRoot = $HistoryRoot
    BatchWorkspaceRoot = $BatchWorkspaceRoot
    ReviewQueueOutputDirectory = $ReviewQueueOutputDirectory
    Mode = $Mode
    ObservedAt = $ObservedAt
    RepositoryRevision = $RepositoryRevision
    NetworkPolicy = $NetworkPolicy
    ReviewDomain = $ReviewDomain
    IncludeSuperseded = [bool]$IncludeSuperseded
    PilotLogPath = $PilotLogPath
    MaxRolling24hPhysicalAttempts = $MaxRolling24hPhysicalAttempts
    SkipReviewQueueExport = [bool]$SkipReviewQueueExport
}

. (Join-Path $PSScriptRoot 'inspect-phase5-benefit-batch.ps1')
. (Join-Path $PSScriptRoot 'export-phase5-review-queue.ps1')

function Assert-InternalPhase5OpsPathNonOverlapping {
    param(
        [Parameter(Mandatory)][string]$LeftPath,
        [Parameter(Mandatory)][string]$RightPath,
        [Parameter(Mandatory)][string]$ErrorCode
    )

    $left = $LeftPath.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $right = $RightPath.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $cmp = [StringComparison]::OrdinalIgnoreCase
    if ($left.Equals($right, $cmp) -or
        $left.StartsWith($right + [IO.Path]::DirectorySeparatorChar, $cmp) -or
        $right.StartsWith($left + [IO.Path]::DirectorySeparatorChar, $cmp)) {
        throw $ErrorCode
    }
}

function New-InternalPhase5OpsReadOnlyStoreLayout {
    param([Parameter(Mandatory)][string]$Root)

    $fullRoot = [IO.Path]::GetFullPath($Root)
    return [pscustomobject][ordered]@{
        Root = $fullRoot
        RunsRoot = (Join-Path $fullRoot 'runs')
        ObservationsRoot = (Join-Path $fullRoot 'observations')
        ComparisonsRoot = (Join-Path $fullRoot 'comparisons')
        ArtifactsRoot = (Join-Path $fullRoot 'artifacts/sha256')
        IndexesRoot = (Join-Path $fullRoot 'indexes')
        TempRoot = (Join-Path $fullRoot 'tmp')
    }
}

function Get-InternalPhase5OpsPilotBudget {
    param(
        [string]$PilotLogPath = '',
        [Parameter(Mandatory)][string]$ObservedAt,
        [AllowNull()]$NetworkPolicy = $null,
        [Parameter(Mandatory)][int]$BusinessCount,
        [int]$MaxRolling24hPhysicalAttempts = 0
    )

    $plannedBudget = if ($null -ne $NetworkPolicy) { [long]$NetworkPolicy.MaxPhysicalAttempts } else { [long]$BusinessCount }
    $nowUtc = [DateTimeOffset]::Parse($ObservedAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).UtcDateTime
    $windowStartUtc = $nowUtc.AddHours(-24)

    $recentAttemptSum = 0L
    $recentEntryCount = 0
    $logExists = (-not [string]::IsNullOrWhiteSpace($PilotLogPath) -and (Test-Path -LiteralPath $PilotLogPath -PathType Leaf))

    if ($logExists) {
        $lines = [IO.File]::ReadAllLines($PilotLogPath, [Text.UTF8Encoding]::new($false, $true))
        $jsonOpts = @{}
        if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $jsonOpts.DateKind = 'String' }
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $entry = $line | ConvertFrom-Json @jsonOpts
            if ($null -eq $entry -or -not ($entry.PSObject.Properties.Name -contains 'ObservedAt')) {
                throw 'OPS_PILOT_LOG_INVALID'
            }
            $entryUtc = [DateTimeOffset]::Parse([string]$entry.ObservedAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).UtcDateTime
            if ($entryUtc -ge $windowStartUtc -and $entryUtc -le $nowUtc.AddMinutes(5)) {
                $recentEntryCount++
                $attempts = if ($entry.PSObject.Properties.Name -contains 'AttemptedCount' -and $null -ne $entry.AttemptedCount) { [long]$entry.AttemptedCount } else { 0L }
                $recentAttemptSum += $attempts
            }
        }
    }

    $exceeded = ($MaxRolling24hPhysicalAttempts -gt 0 -and ($recentAttemptSum + $plannedBudget) -gt [long]$MaxRolling24hPhysicalAttempts)
    return [pscustomobject][ordered]@{
        Enforced = ($MaxRolling24hPhysicalAttempts -gt 0)
        PilotLogPath = $PilotLogPath
        PilotLogExists = $logExists
        WindowHours = 24
        MaxRolling24hPhysicalAttempts = $MaxRolling24hPhysicalAttempts
        Recent24hEntryCount = $recentEntryCount
        Recent24hAttemptCount = $recentAttemptSum
        PlannedBudget = $plannedBudget
        Status = if ($exceeded) { 'EXCEEDED' } else { 'ALLOWED' }
    }
}

function Add-InternalPhase5OpsPilotLogEntry {
    param(
        [Parameter(Mandatory)][string]$PilotLogPath,
        [Parameter(Mandatory)]$Entry
    )

    $dir = Split-Path -Parent $PilotLogPath
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        [void][IO.Directory]::CreateDirectory($dir)
    }
    $existing = if (Test-Path -LiteralPath $PilotLogPath -PathType Leaf) {
        [IO.File]::ReadAllText($PilotLogPath, [Text.UTF8Encoding]::new($false, $true)).Replace("`r`n", "`n").Replace("`r", "`n")
    } else {
        ''
    }
    if (-not [string]::IsNullOrEmpty($existing) -and -not $existing.EndsWith("`n")) {
        $existing += "`n"
    }
    $line = ($Entry | ConvertTo-Json -Compress -Depth 10) + "`n"
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($existing + $line)
    $tempPath = Join-Path $dir ('.pilot-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllBytes($tempPath, $bytes)
        [IO.File]::Move($tempPath, $PilotLogPath, $true)
    } finally {
        if (Test-Path -LiteralPath $tempPath) {
            [IO.File]::Delete($tempPath)
        }
    }
}

function Invoke-Phase5OpsCycle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CanonicalCsvPath,
        [Parameter(Mandatory)][string[]]$BusinessIds,
        [Parameter(Mandatory)][string]$HistoryRoot,
        [Parameter(Mandatory)][string]$BatchWorkspaceRoot,
        [Parameter(Mandatory)][string]$ReviewQueueOutputDirectory,
        [ValidateSet('PlanOnly', 'Execute', 'RecoverOnly')]
        [string]$Mode = 'PlanOnly',
        [string]$ObservedAt = '',
        [string]$RepositoryRevision = '',
        [AllowNull()]$NetworkPolicy = $null,
        [AllowNull()][scriptblock]$RequestInvoker = $null,
        [AllowNull()][scriptblock]$RepositoryStateProvider = $null,
        [ValidateSet('ALL', 'BENEFIT', 'LOCATION')]
        [string]$ReviewDomain = 'BENEFIT',
        [switch]$IncludeSuperseded,
        [string]$PilotLogPath = '',
        [int]$MaxRolling24hPhysicalAttempts = 0,
        [switch]$SkipReviewQueueExport
    )

    if ($MaxRolling24hPhysicalAttempts -lt 0) {
        throw 'OPS_MAX_24H_ATTEMPTS_INVALID'
    }
    if ($MaxRolling24hPhysicalAttempts -gt 0 -and [string]::IsNullOrWhiteSpace($PilotLogPath)) {
        throw 'OPS_PILOT_LOG_REQUIRED_FOR_24H_CAP'
    }
    if ($null -ne $NetworkPolicy -and $null -ne $RequestInvoker) {
        throw 'P52B_CUSTOM_INVOKER_DENIED'
    }

    $repoRoot = (Get-Phase5BenefitRepositoryRoots)[0]
    if ([string]::IsNullOrWhiteSpace($ObservedAt)) {
        $ObservedAt = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
    }
    Assert-HistoryTimestamp -Value $ObservedAt

    if ([string]::IsNullOrWhiteSpace($RepositoryRevision)) {
        $RepositoryRevision = ([string](& git -C $repoRoot rev-parse HEAD)).Trim()
        if ($LASTEXITCODE -ne 0) { throw 'OPS_REPOSITORY_REVISION_UNAVAILABLE' }
    }

    if ($null -eq $RepositoryStateProvider) {
        $capturedRepoRoot = $repoRoot
        $RepositoryStateProvider = {
            $status = @(& git -C $capturedRepoRoot status --porcelain)
            [pscustomobject]@{ IsClean = ($LASTEXITCODE -eq 0 -and $status.Count -eq 0) }
        }.GetNewClosure()
    }

    $safeCsv = Assert-InternalPhase5ReviewQueueSafePath -Path $CanonicalCsvPath
    if (-not (Test-Path -LiteralPath $safeCsv -PathType Leaf)) {
        throw "OPS_CANONICAL_CSV_MISSING: $safeCsv"
    }
    $safeHistoryRoot = Assert-Phase5BenefitExternalPath -Path $HistoryRoot
    $safeWorkspaceRoot = Assert-Phase5BenefitExternalPath -Path $BatchWorkspaceRoot
    $safeReviewOut = Assert-Phase5BenefitExternalPath -Path $ReviewQueueOutputDirectory

    Assert-InternalPhase5OpsPathNonOverlapping -LeftPath $safeHistoryRoot -RightPath $safeWorkspaceRoot -ErrorCode 'OPS_PATH_OVERLAP_HISTORY_WORKSPACE'
    Assert-InternalPhase5OpsPathNonOverlapping -LeftPath $safeHistoryRoot -RightPath $safeReviewOut -ErrorCode 'OPS_PATH_OVERLAP_HISTORY_REVIEW_QUEUE'
    Assert-InternalPhase5OpsPathNonOverlapping -LeftPath $safeWorkspaceRoot -RightPath $safeReviewOut -ErrorCode 'OPS_PATH_OVERLAP_WORKSPACE_REVIEW_QUEUE'

    $safePilotLog = ''
    if (-not [string]::IsNullOrWhiteSpace($PilotLogPath)) {
        if ($PilotLogPath -match '(^|[/\\])\.\.([/\\]|$)') {
            throw 'OPS_UNSAFE_PILOT_LOG_PATH'
        }
        $safePilotLog = Assert-Phase5BenefitExternalPath -Path $PilotLogPath
        if (Test-Path -LiteralPath $safePilotLog -PathType Container) {
            throw 'OPS_PILOT_LOG_MUST_BE_FILE'
        }
        Assert-InternalPhase5OpsPathNonOverlapping -LeftPath $safePilotLog -RightPath $safeHistoryRoot -ErrorCode 'OPS_PATH_OVERLAP_PILOT_HISTORY'
        Assert-InternalPhase5OpsPathNonOverlapping -LeftPath $safePilotLog -RightPath $safeWorkspaceRoot -ErrorCode 'OPS_PATH_OVERLAP_PILOT_WORKSPACE'
    }

    $readOnlyStore = New-InternalPhase5OpsReadOnlyStoreLayout -Root $safeHistoryRoot
    $planArgs = @{
        CanonicalCsvPath = $safeCsv
        BusinessIds = $BusinessIds
        Store = $readOnlyStore
        BatchWorkspaceRoot = $safeWorkspaceRoot
        ObservedAt = $ObservedAt
        RepositoryRevision = $RepositoryRevision
    }
    if ($null -ne $NetworkPolicy) {
        $planArgs.NetworkPolicy = $NetworkPolicy
    }
    $plan = New-Phase5BenefitBatchPlan @planArgs

    $retentionProfiles = @(
        foreach ($planItem in $plan.PlanCore.Items) {
            $profile = Get-InternalPhase5HtmlEvidenceRetentionProfile -Candidate ([pscustomobject]@{ Url = $planItem.SourceUrl })
            [pscustomobject][ordered]@{
                BusinessId = $planItem.BusinessId
                SourceRowNumber = $planItem.SourceRowNumber
                SourceUrl = $planItem.SourceUrl
                RetentionProfile = $profile
            }
        }
    )

    $transportIdentity = Get-Phase5NetworkTransportIdentity
    $transportQualified = Test-InternalPhase5NetworkQualification -Identity $transportIdentity

    $pilotBudget = Get-InternalPhase5OpsPilotBudget `
        -PilotLogPath $safePilotLog `
        -ObservedAt $ObservedAt `
        -NetworkPolicy $NetworkPolicy `
        -BusinessCount $BusinessIds.Count `
        -MaxRolling24hPhysicalAttempts $MaxRolling24hPhysicalAttempts

    if ($Mode -ceq 'PlanOnly') {
        $inspection = if (Test-Path -LiteralPath $safeHistoryRoot -PathType Container) {
            Inspect-Phase5BenefitBatch `
                -Store $readOnlyStore `
                -CanonicalCsvPath $safeCsv `
                -BusinessIds $BusinessIds `
                -BatchWorkspaceRoot $safeWorkspaceRoot `
                -BatchId $plan.BatchId `
                -ObservedAt $ObservedAt `
                -RepositoryRevision $RepositoryRevision
        } else {
            [pscustomobject][ordered]@{
                Skipped = $true
                Reason = 'HISTORY_ROOT_ABSENT'
                HistoryState = 'ABSENT'
                ProductionAction = 'NONE'
            }
        }

        $planStatus = if ($pilotBudget.Status -ceq 'EXCEEDED') { 'BLOCKED' } else { 'READY' }
        $planCode = if ($pilotBudget.Status -ceq 'EXCEEDED') { 'OPS_ROLLING_24H_BUDGET_EXCEEDED' } else { 'OPS_PLAN_READY' }
        return [pscustomobject][ordered]@{
            ContractType = 'Phase5OpsCycleResult'
            ContractVersion = 1
            Mode = 'PlanOnly'
            Status = $planStatus
            Code = $planCode
            BatchId = $plan.BatchId
            ObservedAt = $ObservedAt
            RepositoryRevision = $RepositoryRevision
            Plan = $plan
            RetentionProfiles = $retentionProfiles
            TransportIdentity = $transportIdentity
            TransportQualified = $transportQualified
            PilotBudget = $pilotBudget
            Inspection = $inspection
            BatchResult = $null
            ReviewQueueExport = $null
            ReceiptPath = $null
            ApprovalRequired = $true
            ProductionAction = 'NONE'
        }
    }

    if ($Mode -ceq 'Execute' -and $pilotBudget.Status -ceq 'EXCEEDED') {
        return [pscustomobject][ordered]@{
            ContractType = 'Phase5OpsCycleResult'
            ContractVersion = 1
            Mode = 'Execute'
            Status = 'BLOCKED'
            Code = 'OPS_ROLLING_24H_BUDGET_EXCEEDED'
            BatchId = $plan.BatchId
            ObservedAt = $ObservedAt
            RepositoryRevision = $RepositoryRevision
            Plan = $plan
            RetentionProfiles = $retentionProfiles
            TransportIdentity = $transportIdentity
            TransportQualified = $transportQualified
            PilotBudget = $pilotBudget
            Inspection = $null
            BatchResult = $null
            ReviewQueueExport = $null
            ReceiptPath = $null
            ApprovalRequired = $true
            ProductionAction = 'NONE'
        }
    }

    if ($Mode -ceq 'RecoverOnly' -and -not (Test-Path -LiteralPath $safeHistoryRoot -PathType Container)) {
        return [pscustomobject][ordered]@{
            ContractType = 'Phase5OpsCycleResult'
            ContractVersion = 1
            Mode = 'RecoverOnly'
            Status = 'BLOCKED'
            Code = 'OPS_HISTORY_ROOT_MISSING'
            BatchId = $plan.BatchId
            ObservedAt = $ObservedAt
            RepositoryRevision = $RepositoryRevision
            Plan = $plan
            RetentionProfiles = $retentionProfiles
            TransportIdentity = $transportIdentity
            TransportQualified = $transportQualified
            PilotBudget = $pilotBudget
            Inspection = $null
            BatchResult = $null
            ReviewQueueExport = $null
            ReceiptPath = $null
            ApprovalRequired = $true
            ProductionAction = 'NONE'
        }
    }

    $activeStore = if ($Mode -ceq 'Execute') {
        New-HistoryStoreLayout -Root $safeHistoryRoot
    } else {
        $readOnlyStore
    }

    $batchInvokeArgs = @{
        CanonicalCsvPath = $safeCsv
        BusinessIds = $BusinessIds
        Store = $activeStore
        BatchWorkspaceRoot = $safeWorkspaceRoot
        ObservedAt = $ObservedAt
        RepositoryRevision = $RepositoryRevision
        BatchId = $plan.BatchId
        Mode = $Mode
        RepositoryStateProvider = $RepositoryStateProvider
    }
    if ($null -ne $NetworkPolicy) {
        $batchInvokeArgs.NetworkPolicy = $NetworkPolicy
    }
    if ($null -ne $RequestInvoker) {
        $batchInvokeArgs.RequestInvoker = $RequestInvoker
    }

    $batchResult = Invoke-Phase5BenefitBatch @batchInvokeArgs

    if ($Mode -ceq 'Execute' -and -not [string]::IsNullOrWhiteSpace($safePilotLog)) {
        $attemptedCount = 0L
        $hasNetExec = ($batchResult.PSObject.Properties.Name -contains 'NetworkExecution') -and ($null -ne $batchResult.NetworkExecution)
        if ($hasNetExec) {
            $attemptedCount = [long]$batchResult.NetworkExecution.AttemptedCount
        } elseif ($null -ne $batchResult.Metrics -and $null -ne $batchResult.Metrics.ExternalFetchCount -and $null -ne $batchResult.Metrics.ExternalFetchCount.KnownSum) {
            $attemptedCount = [long]$batchResult.Metrics.ExternalFetchCount.KnownSum
        }

        $pilotEntry = [pscustomobject][ordered]@{
            ObservedAt = $ObservedAt
            BatchId = $plan.BatchId
            Mode = $Mode
            BusinessIds = @($BusinessIds)
            RepositoryRevision = $RepositoryRevision
            AttemptedCount = $attemptedCount
            CommittedCount = if ($null -ne $batchResult.Summary) { [int]$batchResult.Summary.CommittedCount } else { 0 }
            Status = [string]$batchResult.Status
            Code = [string]$batchResult.Code
            ProductionAction = 'NONE'
        }
        Add-InternalPhase5OpsPilotLogEntry -PilotLogPath $safePilotLog -Entry $pilotEntry
    }

    $inspection = Inspect-Phase5BenefitBatch `
        -Store $activeStore `
        -CanonicalCsvPath $safeCsv `
        -BusinessIds $BusinessIds `
        -BatchWorkspaceRoot $safeWorkspaceRoot `
        -BatchId $plan.BatchId `
        -ObservedAt $ObservedAt `
        -RepositoryRevision $RepositoryRevision

    $reviewQueueExport = $null
    if (-not $SkipReviewQueueExport) {
        $reviewQueueExport = Export-Phase5ReviewQueue `
            -Store $activeStore `
            -CanonicalCsvPath $safeCsv `
            -OutputDirectory $safeReviewOut `
            -Domain $ReviewDomain `
            -IncludeSuperseded:$IncludeSuperseded
    }

    $opsSummary = [pscustomobject][ordered]@{
        ContractType = 'Phase5OpsCycleSummary'
        ContractVersion = 1
        Mode = $Mode
        Status = [string]$batchResult.Status
        Code = [string]$batchResult.Code
        BatchId = $plan.BatchId
        ObservedAt = $ObservedAt
        RepositoryRevision = $RepositoryRevision
        RetentionProfiles = $retentionProfiles
        TransportIdentity = $transportIdentity
        TransportQualified = $transportQualified
        PilotBudget = $pilotBudget
        BatchSummary = $batchResult.Summary
        InspectionSummary = [pscustomobject][ordered]@{
            InspectionStatus = $inspection.InspectionStatus
            PlanState = $inspection.PlanState
            CurrentCompatibility = $inspection.CurrentCompatibility
            HistoryState = $inspection.HistoryState
            GuardState = $inspection.GuardState
            RecoveryConsideration = $inspection.RecoveryConsideration
        }
        ReviewQueueSummary = if ($null -ne $reviewQueueExport) { $reviewQueueExport.Summary } else { $null }
        ApprovalRequired = $true
        ProductionAction = 'NONE'
    }

    $receiptPath = Join-Path $safeReviewOut 'ops-cycle-summary.json'
    Write-InternalPhase5ReviewQueueAtomicText -Path $receiptPath -Content ($opsSummary | ConvertTo-Json -Depth 15)

    return [pscustomobject][ordered]@{
        ContractType = 'Phase5OpsCycleResult'
        ContractVersion = 1
        Mode = $Mode
        Status = [string]$batchResult.Status
        Code = [string]$batchResult.Code
        BatchId = $plan.BatchId
        ObservedAt = $ObservedAt
        RepositoryRevision = $RepositoryRevision
        Plan = $plan
        RetentionProfiles = $retentionProfiles
        TransportIdentity = $transportIdentity
        TransportQualified = $transportQualified
        PilotBudget = $pilotBudget
        Inspection = $inspection
        BatchResult = $batchResult
        ReviewQueueExport = $reviewQueueExport
        ReceiptPath = $receiptPath
        ApprovalRequired = $true
        ProductionAction = 'NONE'
    }
}

if ($script:OpsCycleCliInvoked) {
    $cliArgs = $script:OpsCycleCliParams
    if ([string]::IsNullOrWhiteSpace($cliArgs.CanonicalCsvPath) -or
        @($cliArgs.BusinessIds).Count -eq 0 -or
        [string]::IsNullOrWhiteSpace($cliArgs.HistoryRoot) -or
        [string]::IsNullOrWhiteSpace($cliArgs.BatchWorkspaceRoot) -or
        [string]::IsNullOrWhiteSpace($cliArgs.ReviewQueueOutputDirectory)) {
        throw 'OPS_CLI_PARAMETERS_REQUIRED: -CanonicalCsvPath, -BusinessIds, -HistoryRoot, -BatchWorkspaceRoot, and -ReviewQueueOutputDirectory are required.'
    }

    Invoke-Phase5OpsCycle @cliArgs
}

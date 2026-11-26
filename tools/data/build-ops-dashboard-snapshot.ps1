[CmdletBinding()]
param(
    [string]$SeedManifestJson = 'apps/android/app/src/main/assets/benefits.seed.manifest.json',
    [string]$WeeklyDriftSummaryJson = '',
    [string]$ReviewQueueSummaryJson = '',
    [string]$OutputJson = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/release/approval-release-contracts.ps1')

function Read-OpsSnapshotJsonObject {
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$MaxBytes = 16777216
    )

    $safePath = Assert-ReleaseSafeFilePath -Path $Path
    if (-not (Test-Path -LiteralPath $safePath -PathType Leaf)) {
        throw "OPS_SNAPSHOT_FILE_MISSING: $safePath"
    }
    $bytes = [IO.File]::ReadAllBytes($safePath)
    if ($bytes.Length -gt $MaxBytes) {
        throw "OPS_SNAPSHOT_JSON_TOO_LARGE: $safePath"
    }
    $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes).TrimStart([char]0xFEFF)
    $jsonOptions = @{}
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) {
        $jsonOptions.DateKind = 'String'
    }
    return ($text | ConvertFrom-Json @jsonOptions)
}

function Write-OpsSnapshotAtomicJson {
    param(
        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter(Mandatory)]$Value
    )

    $safeOut = Assert-ReleaseSafeFilePath -Path $OutputPath
    $parent = Split-Path -Parent $safeOut
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        [void][IO.Directory]::CreateDirectory($parent)
    }
    $jsonText = $Value | ConvertTo-Json -Depth 15
    $tmpPath = "$safeOut.tmp.$([guid]::NewGuid().ToString('N'))"
    try {
        [IO.File]::WriteAllText($tmpPath, $jsonText, [Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $safeOut -PathType Leaf) {
            [IO.File]::Replace($tmpPath, $safeOut, $null)
        } else {
            [IO.File]::Move($tmpPath, $safeOut)
        }
    } finally {
        if (Test-Path -LiteralPath $tmpPath -PathType Leaf) {
            Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue
        }
    }
    return $safeOut
}

function Build-OpsDashboardSnapshot {
    param(
        [Parameter(Mandatory)][string]$SeedManifestJson,
        [string]$WeeklyDriftSummaryJson = '',
        [string]$ReviewQueueSummaryJson = '',
        [Parameter(Mandatory)][string]$OutputJson
    )

    $manifest = Read-OpsSnapshotJsonObject -Path $SeedManifestJson
    Assert-BenefitReleaseSeedManifest -Manifest $manifest

    $weeklyDrift = $null
    if (-not [string]::IsNullOrWhiteSpace($WeeklyDriftSummaryJson)) {
        $driftObj = Read-OpsSnapshotJsonObject -Path $WeeklyDriftSummaryJson
        if ([string]$driftObj.contractType -cne 'WeeklyBenefitDriftSummary') {
            throw "OPS_SNAPSHOT_INVALID_WEEKLY_DRIFT: Unexpected contractType '$($driftObj.contractType)'"
        }
        $weeklyDrift = [pscustomobject][ordered]@{
            contractType               = [string]$driftObj.contractType
            contractVersion            = [int]$driftObj.contractVersion
            generatedAtUtc             = [string]$driftObj.generatedAtUtc
            canonicalRowCount          = [int]$driftObj.canonicalRowCount
            automaticCanonicalMutation = [bool]$driftObj.automaticCanonicalMutation
            productionAction           = if ($driftObj.PSObject.Properties['productionAction']) { [string]$driftObj.productionAction } else { 'NONE' }
            sources                    = @($driftObj.sources)
        }
    }

    $reviewQueue = $null
    if (-not [string]::IsNullOrWhiteSpace($ReviewQueueSummaryJson)) {
        $rqObj = Read-OpsSnapshotJsonObject -Path $ReviewQueueSummaryJson
        if ([string]$rqObj.ContractType -cne 'Phase5ReviewQueueExport') {
            throw "OPS_SNAPSHOT_INVALID_REVIEW_QUEUE: Unexpected ContractType '$($rqObj.ContractType)'"
        }
        if ($null -eq $rqObj.Summary) {
            throw 'OPS_SNAPSHOT_INVALID_REVIEW_QUEUE: Missing Summary'
        }
        $allowedItemProps = @(
            'OperatorBucket', 'BusinessId', 'CanonicalRowNumber', 'BusinessName', 'District',
            'RoadAddress', 'CanonicalBenefitStatus', 'CanonicalCoordinateStatus', 'CanonicalSourceUrl',
            'CanonicalLastVerifiedAt', 'Domain', 'ReviewKey', 'RunId', 'ObservedAt',
            'CurrentObservationId', 'PreviousObservationId', 'ComparisonId', 'ReviewRoute',
            'OperationalStatus', 'Comparable', 'SemanticProjectionAvailable', 'DeltaDimensions',
            'ChangeCandidates', 'ReasonCodes', 'AuditFlags', 'DiagnosticReasons', 'BenefitState',
            'ReviewClass', 'BusinessPresence', 'AbsenceEligible', 'ValidatedClaims', 'SourceUrls',
            'SourceFormats', 'SourceContentHashes', 'SourceLocationStatuses', 'LocationEvaluationStatus',
            'LocationClassification', 'LocationSelectionStatus', 'LocationSelectedLatitude',
            'LocationSelectedLongitude', 'MaterialReasonCodes', 'ConflictCodes', 'ApprovalRequired',
            'ProductionAction'
        )
        $sanitizedItems = @(
            foreach ($item in @($rqObj.Items)) {
                $cleanItem = [ordered]@{}
                foreach ($propName in $allowedItemProps) {
                    if ($item.PSObject.Properties.Name -contains $propName) {
                        $cleanItem[$propName] = $item.$propName
                    }
                }
                [pscustomobject]$cleanItem
            }
        )
        $reviewQueue = [pscustomobject][ordered]@{
            ContractType     = [string]$rqObj.ContractType
            ContractVersion  = [int]$rqObj.ContractVersion
            ExportedAt       = [string]$rqObj.ExportedAt
            Summary          = $rqObj.Summary
            Items            = @($sanitizedItems)
        }
    }

    $snapshot = [pscustomobject][ordered]@{
        ContractType     = 'OpsDashboardSnapshot'
        ContractVersion  = 1
        GeneratedAtUtc   = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
        ProductionAction = 'NONE'
        SeedBaseline     = $manifest
        WeeklyDrift      = $weeklyDrift
        ReviewQueue      = $reviewQueue
    }

    $writtenPath = Write-OpsSnapshotAtomicJson -OutputPath $OutputJson -Value $snapshot
    return [pscustomobject][ordered]@{
        OutputJsonPath   = $writtenPath
        Snapshot         = $snapshot
        ProductionAction = 'NONE'
    }
}

if ($MyInvocation.InvocationName -ne '.' -and $PSBoundParameters.Count -gt 0) {
    if ([string]::IsNullOrWhiteSpace($OutputJson)) {
        throw 'OPS_SNAPSHOT_OUTPUT_REQUIRED: -OutputJson is required.'
    }
    Build-OpsDashboardSnapshot `
        -SeedManifestJson $SeedManifestJson `
        -WeeklyDriftSummaryJson $WeeklyDriftSummaryJson `
        -ReviewQueueSummaryJson $ReviewQueueSummaryJson `
        -OutputJson $OutputJson | Out-Null
}

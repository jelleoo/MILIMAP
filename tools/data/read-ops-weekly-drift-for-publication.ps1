[CmdletBinding()]
param([Parameter(Mandatory)][string]$SummaryPath)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/release/approval-release-contracts.ps1')

try {
    $jsonOptions = @{}
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $jsonOptions.DateKind = 'String' }
    $rawSummary = Read-ReleaseUtf8Text -Path $SummaryPath
    if ($rawSummary.Length -gt 0 -and $rawSummary[0] -eq [char]0xFEFF) { $rawSummary = $rawSummary.Substring(1) }
    $summary = $rawSummary | ConvertFrom-Json @jsonOptions
    if ($null -eq $summary -or $summary.contractType -cne 'WeeklyBenefitDriftSummary' -or
        ($summary.contractVersion -isnot [int] -and $summary.contractVersion -isnot [long]) -or
        $summary.contractVersion -ne 1 -or
        $summary.productionAction -cne 'NONE' -or $summary.automaticCanonicalMutation -isnot [bool] -or
        $summary.automaticCanonicalMutation -or
        ($summary.canonicalRowCount -isnot [int] -and $summary.canonicalRowCount -isnot [long]) -or
        $summary.canonicalRowCount -le 0 -or
        -not (Test-ReleaseIso8601WithOffset -Value ([string]$summary.generatedAtUtc))) {
        throw 'Contract or read-only policy mismatch'
    }

    $expected = @('ddc', 'mma', 'paju', 'yangju')
    $sources = @($summary.sources | Where-Object { $null -ne $_ })
    $ids = @($sources | ForEach-Object { $_.id })
    if ($ids.Count -ne $expected.Count -or (Compare-Object -CaseSensitive $expected $ids)) { throw 'Unexpected source set' }
    foreach ($source in $sources) {
        if ($source.status -cnotin @('OK', 'DRIFT_DETECTED', 'FETCH_FAILED') -or
            [string]::IsNullOrWhiteSpace($source.name) -or $source.detail -isnot [string] -or
            $source.error -isnot [string]) {
            throw 'Invalid source status or metadata'
        }
    }
} catch {
    throw "OPS_WEEKLY_INVALID_SUMMARY: $($_.Exception.Message)"
}

[pscustomobject]@{
    failedSources = @($summary.sources | Where-Object status -CEQ 'FETCH_FAILED' | ForEach-Object id)
    sourceCount = $summary.sources.Count
}

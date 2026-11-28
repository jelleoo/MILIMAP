[CmdletBinding()]
param([Parameter(Mandatory)][string]$SnapshotPath)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/release/approval-release-contracts.ps1')

$jsonOptions = @{}
if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $jsonOptions.DateKind = 'String' }
$rawSnapshot = Read-ReleaseUtf8Text -Path $SnapshotPath
if ($rawSnapshot.Length -gt 0 -and $rawSnapshot[0] -eq [char]0xFEFF) { $rawSnapshot = $rawSnapshot.Substring(1) }
$snapshot = $rawSnapshot | ConvertFrom-Json @jsonOptions
$driftProp = if ($null -ne $snapshot) { $snapshot.PSObject.Properties['WeeklyDrift'] } else { $null }
$drift = if ($null -ne $driftProp) { $driftProp.Value } else { $null }
if ($null -eq $drift -or $drift.productionAction -cne 'NONE' -or
    $drift.automaticCanonicalMutation -isnot [bool] -or $drift.automaticCanonicalMutation) {
    throw 'WEEKLY_DRIFT_REVIEW_NOT_READ_ONLY'
}

$categories = @('CONTENT_CHANGED', 'MISSING_IN_OFFICIAL', 'ADDRESS_RECHECK', 'ATTACHMENT_CHANGED')
$sources = @($drift.sources | Where-Object { $null -ne $_ })
$reviewItems = @($drift.reviewItems | Where-Object { $null -ne $_ })
$newCandidates = @($drift.newCandidates | Where-Object { $null -ne $_ })

foreach ($source in $sources) {
    if ($source.status -cnotin @('OK', 'DRIFT_DETECTED') -or $source.id -cnotin @('ddc', 'paju', 'mma', 'yangju')) {
        continue
    }
    $sourceId = $source.id
    $keys = [Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
    foreach ($item in $reviewItems) {
        if ($item.sourceId -cne $sourceId -or $item.category -cnotin $categories) { continue }
        $businessIdProp = $item.PSObject.Properties['businessId']
        $businessIdValue = if ($null -ne $businessIdProp) { $businessIdProp.Value } else { $null }
        $identity = if ($businessIdValue) { $businessIdValue } else { @($item.businessName, $item.roadAddress) }
        $key = ConvertTo-Json -InputObject @($item.category, $identity, $item.reasonSummary, $item.officialDetail) -Compress -Depth 5
        [void]$keys.Add($key)
    }
    foreach ($item in $newCandidates) {
        if ($item.sourceId -cne $sourceId) { continue }
        $key = ConvertTo-Json -InputObject @('NEW', $item.institutionCode, $item.businessName, $item.roadAddress, $item.category) -Compress -Depth 5
        [void]$keys.Add($key)
    }
    if ($keys.Count -gt 0) {
        [pscustomobject]@{
            source = $sourceId
            candidateCount = $keys.Count
            fingerprint = Get-ReleaseNormalizedLfSha256 -Text ($keys -join [char]10)
        }
    }
}

$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('ops-drift-publish-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$path = Join-Path $root 'weekly-drift-summary.json'
$reader = Join-Path $PSScriptRoot 'read-ops-weekly-drift-for-publication.ps1'
try {
    $report = [ordered]@{
        contractType = 'WeeklyBenefitDriftSummary'
        contractVersion = 1
        generatedAtUtc = '2026-11-23T00:00:00Z'
        canonicalRowCount = 1298
        automaticCanonicalMutation = $false
        productionAction = 'NONE'
        sources = @('ddc', 'paju', 'mma', 'yangju' | ForEach-Object {
            [ordered]@{ id = $_; name = $_; status = 'OK'; officialCount = 1; canonicalCount = 1; detail = ''; error = '' }
        })
    }
    foreach ($failedCount in 0, 1, 4) {
        for ($i = 0; $i -lt $failedCount; $i++) {
            $report.sources[$i].status = 'FETCH_FAILED'
            $report.sources[$i].officialCount = $null
        }
        $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding utf8
        $result = & $reader -SummaryPath $path
        if ($result.failedSources.Count -ne $failedCount) { throw 'Unexpected failed source count' }
    }
    $report.sources[0].id = 'DDC'
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding utf8
    try {
        & $reader -SummaryPath $path | Out-Null
        throw 'Wrong-case source id was accepted'
    } catch {
        if ($_.Exception.Message -notlike 'OPS_WEEKLY_INVALID_SUMMARY*') { throw }
    }
    $report.sources[0].id = 'ddc'
    $report.automaticCanonicalMutation = $true
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding utf8
    try {
        & $reader -SummaryPath $path | Out-Null
        throw 'Automatic mutation flag was accepted'
    } catch {
        if ($_.Exception.Message -notlike 'OPS_WEEKLY_INVALID_SUMMARY*') { throw }
    }
    $report.automaticCanonicalMutation = $false
    $report.productionAction = 'APPLY'
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding utf8
    try {
        & $reader -SummaryPath $path | Out-Null
        throw 'Unsafe summary was accepted'
    } catch {
        if ($_.Exception.Message -notlike 'OPS_WEEKLY_INVALID_SUMMARY*') { throw }
    }
    Set-Content -LiteralPath $path -Value '{"contractType":' -Encoding utf8
    try {
        & $reader -SummaryPath $path | Out-Null
        throw 'Broken JSON was accepted'
    } catch {
        if ($_.Exception.Message -notlike 'OPS_WEEKLY_INVALID_SUMMARY*') { throw }
    }
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
Write-Output 'PASS: weekly drift publication contract'

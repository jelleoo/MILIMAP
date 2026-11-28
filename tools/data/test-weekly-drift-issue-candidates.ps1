$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('ops-drift-issues-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$path = Join-Path $root 'snapshot.json'
$exporter = Join-Path $PSScriptRoot 'export-weekly-drift-issue-candidates.ps1'

try {
    $items = @(
        @{ sourceId = 'mma'; category = 'CONTENT_CHANGED'; businessId = 'b1'; businessName = 'fixture'; roadAddress = 'fixture address'; reasonSummary = 'discount'; officialDetail = '10%' }
        @{ sourceId = 'mma'; category = 'MISSING_IN_OFFICIAL'; businessId = 'b2'; businessName = 'second fixture'; roadAddress = ''; reasonSummary = ''; officialDetail = '' }
        @{ sourceId = 'ddc'; category = 'CONTENT_CHANGED'; businessId = 'b3'; businessName = 'failed source'; roadAddress = ''; reasonSummary = ''; officialDetail = '' }
        @{ sourceId = 'paju'; category = 'DETAIL_RECHECK'; businessId = 'b4'; businessName = 'review only'; roadAddress = ''; reasonSummary = ''; officialDetail = '' }
        @{ sourceId = 'yangju'; category = 'ATTACHMENT_CHANGED'; businessName = 'yangju fixture'; roadAddress = 'yangju road'; reasonSummary = 'sheet updated'; officialDetail = 'xlsx' }
    )
    $snapshot = @{
        WeeklyDrift = @{
            productionAction = 'NONE'
            automaticCanonicalMutation = $false
            sources = @(@{id='mma';status='OK'}, @{id='ddc';status='FETCH_FAILED'}, @{id='paju';status='OK'}, @{id='yangju';status='DRIFT_DETECTED'})
            reviewItems = $items
            newCandidates = @(
                @{ sourceId = 'paju'; institutionCode = 'PJ01'; businessName = 'new paju'; roadAddress = 'paju road'; category = 'FOOD' }
            )
        }
    }
    $snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding utf8
    $initial = @(& $exporter -SnapshotPath $path)
    if ($initial.Count -ne 3) {
        throw 'Expected findings for mma, paju(new), and yangju(attachment)'
    }
    $mma = $initial | Where-Object { $_.source -ceq 'mma' } | Select-Object -First 1
    $paju = $initial | Where-Object { $_.source -ceq 'paju' } | Select-Object -First 1
    $yangju = $initial | Where-Object { $_.source -ceq 'yangju' } | Select-Object -First 1
    if ($null -eq $mma -or $mma.candidateCount -ne 2 -or $null -eq $paju -or $paju.candidateCount -ne 1 -or $null -eq $yangju -or $yangju.candidateCount -ne 1) {
        throw 'Unexpected candidate counts across sources'
    }

    $snapshot.WeeklyDrift.reviewItems = @($items[1], $items[0], $items[2], $items[3], $items[4])
    $snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding utf8
    $reordered = @(& $exporter -SnapshotPath $path) | Where-Object { $_.source -ceq 'mma' } | Select-Object -First 1
    if ($reordered.fingerprint -cne $mma.fingerprint) { throw 'Row ordering changed the fingerprint' }

    $items[0].officialDetail = '20%'
    $snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding utf8
    $changed = @(& $exporter -SnapshotPath $path) | Where-Object { $_.source -ceq 'mma' } | Select-Object -First 1
    if ($changed.fingerprint -ceq $mma.fingerprint) { throw 'Changed evidence did not change the fingerprint' }

    $snapshot.WeeklyDrift.sources[0].status = 'FETCH_FAILED'
    $snapshot.WeeklyDrift.sources[2].status = 'FETCH_FAILED'
    $snapshot.WeeklyDrift.sources[3].status = 'FETCH_FAILED'
    $snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding utf8
    if (@(& $exporter -SnapshotPath $path).Count -ne 0) { throw 'Fetch errors generated an issue candidate' }

    $snapshot.WeeklyDrift.productionAction = 'APPLY'
    $snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding utf8
    try {
        & $exporter -SnapshotPath $path | Out-Null
        throw 'Non-NONE productionAction was accepted'
    } catch {
        if ($_.Exception.Message -notlike 'WEEKLY_DRIFT_REVIEW_NOT_READ_ONLY*') { throw }
    }
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
Write-Output 'PASS: weekly drift review issue candidates'

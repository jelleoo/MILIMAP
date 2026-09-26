$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/identity/canonical-business-id.ps1')

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$canonicalPath = Join-Path $repoRoot 'data/canonical/capital-area-military-benefits.csv'
$rows = @(Import-Csv -LiteralPath $canonicalPath -Encoding utf8)

if ($rows.Count -ne 496) {
    throw "Canonical row count changed (expected 496, actual $($rows.Count))"
}

$missing = @($rows | Where-Object {
    $_.PSObject.Properties.Name -notcontains 'businessId' -or
    [string]::IsNullOrWhiteSpace([string]$_.businessId)
})

if ($missing.Count -gt 0) {
    $migrationIds = @(1..$rows.Count | ForEach-Object { New-CanonicalBusinessId })
    Write-Host ('P3_CANONICAL_BUSINESS_IDS=' + ($migrationIds -join ','))
    throw "Canonical rows are missing businessId: $($missing.Count)"
}

Assert-CanonicalBusinessIds -Rows $rows
Write-Host 'Canonical repository business ID invariant passed.'

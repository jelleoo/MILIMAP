$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$assets = Join-Path $repo 'apps/android/app/src/main/assets'
$canonical = Join-Path $repo 'data/canonical/capital-area-military-benefits.csv'
$root = Join-Path ([IO.Path]::GetTempPath()) ('milimap-public-seed-' + [guid]::NewGuid().ToString('N'))
$output = Join-Path $root 'site'

try {
    $result = & (Join-Path $PSScriptRoot 'build-public-benefit-seed-package.ps1') `
        -AssetDirectory $assets -CanonicalCsv $canonical -OutputDirectory $output
    $prefix = "v/$($result.seedVersion)"
    $expected = @('_headers', 'benefits.seed.manifest.json', "$prefix/benefits.seed.json", "$prefix/manual_benefits_seed.json")
    $actual = @(Get-ChildItem -LiteralPath $output -File -Recurse | ForEach-Object {
        [IO.Path]::GetRelativePath($output, $_.FullName).Replace('\', '/')
    })
    if (Compare-Object $expected $actual) { throw 'Unexpected public files' }
    foreach ($name in 'benefits.seed.json', 'manual_benefits_seed.json') {
        if ((Get-FileHash (Join-Path $assets $name)).Hash -cne (Get-FileHash (Join-Path $output "$prefix/$name")).Hash) {
            throw "The public file was changed: $name"
        }
    }

    $published = Join-Path $root 'published'
    [void][IO.Directory]::CreateDirectory($published)
    Copy-Item -LiteralPath (Join-Path $output 'benefits.seed.manifest.json') -Destination $published
    Copy-Item -LiteralPath (Join-Path $output "$prefix/benefits.seed.json"), (Join-Path $output "$prefix/manual_benefits_seed.json") -Destination $published
    $argsForPublished = @{
        AssetDirectory = $assets
        CanonicalCsv = $canonical
        OutputDirectory = Join-Path $root 'next-site'
        PublishedDirectory = $published
    }
    $builder = Join-Path $PSScriptRoot 'build-public-benefit-seed-package.ps1'
    if ((& $builder @argsForPublished).publish) { throw 'Re-run attempted to publish an identical release' }

    $publishedManifestPath = Join-Path $published 'benefits.seed.manifest.json'
    $manifest = Get-Content -Raw -LiteralPath $publishedManifestPath | ConvertFrom-Json -DateKind String
    $oldHash = $manifest.manualSeedSha256
    $manifest.manualSeedSha256 = 'a' * 64
    $manifest | ConvertTo-Json | Set-Content -LiteralPath $publishedManifestPath -Encoding utf8
    try {
        & $builder @argsForPublished | Out-Null
        throw 'Same-version mutation was accepted'
    } catch {
        if ($_.Exception.Message -notlike 'PUBLIC_SEED_VERSION_REUSED*') { throw }
    }
    $manifest.manualSeedSha256 = $oldHash
    $manifest.seedVersion = $result.seedVersion + 1
    $manifest | ConvertTo-Json | Set-Content -LiteralPath $publishedManifestPath -Encoding utf8
    try {
        & $builder @argsForPublished | Out-Null
        throw 'Downgrade was accepted'
    } catch {
        if ($_.Exception.Message -notlike 'PUBLIC_SEED_VERSION_DOWNGRADE*') { throw }
    }
    $manifest.seedVersion = $result.seedVersion - 1
    $manifest | ConvertTo-Json | Set-Content -LiteralPath $publishedManifestPath -Encoding utf8
    if (!(& $builder @argsForPublished).publish) { throw 'New release was skipped' }
    if (!(Test-Path -LiteralPath (Join-Path $argsForPublished.OutputDirectory "v/$($manifest.seedVersion)/benefits.seed.json"))) {
        throw 'Previous release is unavailable after publishing'
    }

    $tampered = Join-Path $root 'tampered'
    [void][IO.Directory]::CreateDirectory($tampered)
    foreach ($name in 'benefits.seed.manifest.json', 'benefits.seed.json', 'manual_benefits_seed.json') {
        Copy-Item -LiteralPath (Join-Path $assets $name) -Destination $tampered
    }
    Add-Content -LiteralPath (Join-Path $tampered 'benefits.seed.json') -Value ' '
    $badOutput = Join-Path $root 'invalid-site'
    try {
        & (Join-Path $PSScriptRoot 'build-public-benefit-seed-package.ps1') `
            -AssetDirectory $tampered -CanonicalCsv $canonical -OutputDirectory $badOutput | Out-Null
        throw 'Tampered seed was accepted'
    } catch {
        if ($_.Exception.Message -notlike 'PUBLIC_SEED_PARITY*') { throw }
    }
    if (Test-Path -LiteralPath $badOutput) { throw 'Unverified files were staged' }
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}

Write-Output 'PASS: public benefit seed package'

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AssetDirectory,
    [Parameter(Mandatory)][string]$CanonicalCsv,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$PublishedDirectory
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'build-release-benefit-seed-manifest.ps1')

$manifestName = 'benefits.seed.manifest.json'
$seedName = 'benefits.seed.json'
$manualName = 'manual_benefits_seed.json'
$limits = @{ $manifestName = 16KB; $seedName = 4MB; $manualName = 256KB }

function Get-PublicSeedFile([string]$Directory, [string]$Name) {
    $path = Assert-ReleaseSafeFilePath -Path (Join-Path $Directory $Name)
    $file = Get-Item -LiteralPath $path
    if ($file.PSIsContainer -or $file.Length -lt 1 -or $file.Length -gt $limits[$Name]) {
        throw "PUBLIC_SEED_FILE_SIZE: $Name"
    }
    return $path
}

function Read-PublicSeedManifest([string]$Directory) {
    $file = Get-PublicSeedFile $Directory $manifestName
    $manifest = ConvertFrom-InternalManifestJson -Text (Read-ReleaseUtf8Text -Path $file)
    Assert-BenefitReleaseSeedManifest -Manifest $manifest
    return $manifest
}

$current = Read-PublicSeedManifest $AssetDirectory
$seedFile = Get-PublicSeedFile $AssetDirectory $seedName
$manualFile = Get-PublicSeedFile $AssetDirectory $manualName
$manifestParams = @{
    SeedJsonPath = $seedFile
    ManualSeedJsonPath = $manualFile
    CanonicalCsvPath = $CanonicalCsv
    SeedVersion = $current.seedVersion
    GeneratedAt = $current.generatedAt
}
$rebuilt = New-ReleaseBenefitSeedManifest @manifestParams
foreach ($field in $rebuilt.PSObject.Properties.Name) {
    if ($rebuilt.$field -cne $current.$field) { throw "PUBLIC_SEED_PARITY: $field" }
}

$previous = $null
if ($PublishedDirectory) {
    $previous = Read-PublicSeedManifest $PublishedDirectory
    if ($previous.seedVersion -gt $current.seedVersion) { throw 'PUBLIC_SEED_VERSION_DOWNGRADE' }

    if ($previous.seedVersion -eq $current.seedVersion) {
        foreach ($field in $rebuilt.PSObject.Properties.Name | Where-Object { $_ -ne 'generatedAt' }) {
            if ($previous.$field -cne $current.$field) { throw "PUBLIC_SEED_VERSION_REUSED: $field" }
        }
    }

    $publishedSeed = Get-PublicSeedFile $PublishedDirectory $seedName
    $publishedManual = Get-PublicSeedFile $PublishedDirectory $manualName
    if ((Get-ReleaseFileNormalizedLfSha256 -Path $publishedSeed) -cne $previous.seedSha256 -or
        (Get-ReleaseFileNormalizedLfSha256 -Path $publishedManual) -cne $previous.manualSeedSha256) {
        throw 'PUBLIC_SEED_PUBLISHED_HASH_MISMATCH'
    }
    if ($previous.seedVersion -eq $current.seedVersion) {
        return [pscustomobject]@{ seedVersion = $current.seedVersion; publish = $false }
    }
}

$output = Assert-ReleaseSafeFilePath -Path $OutputDirectory
if (Test-Path -LiteralPath $output) { throw 'PUBLIC_SEED_OUTPUT_MUST_BE_NEW' }
$currentPath = Join-Path $output "v/$($current.seedVersion)"
[void][IO.Directory]::CreateDirectory($currentPath)
Copy-Item -LiteralPath (Get-PublicSeedFile $AssetDirectory $manifestName) -Destination $output
Copy-Item -LiteralPath $seedFile, $manualFile -Destination $currentPath
if ($null -ne $previous) {
    $previousPath = Join-Path $output "v/$($previous.seedVersion)"
    [void][IO.Directory]::CreateDirectory($previousPath)
    Copy-Item -LiteralPath $publishedSeed, $publishedManual -Destination $previousPath
}
@'
/*
  X-Content-Type-Options: nosniff
/benefits.seed.manifest.json
  Cache-Control: no-cache
/v/*
  Cache-Control: public, max-age=31536000, immutable
'@ | Set-Content -LiteralPath (Join-Path $output '_headers') -Encoding utf8

[pscustomobject]@{ seedVersion = $current.seedVersion; publish = $true }

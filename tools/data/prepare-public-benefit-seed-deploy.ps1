[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AssetDirectory,
    [Parameter(Mandatory)][string]$CanonicalCsv,
    [Parameter(Mandatory)][string]$WorkDirectory,
    [switch]$Bootstrap,
    [switch]$VerifyPublished
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'build-release-benefit-seed-manifest.ps1')

$origin = 'https://milimap-data.pages.dev'
$safeWorkDirectory = Assert-ReleaseSafeFilePath -Path $WorkDirectory
$published = Join-Path $safeWorkDirectory 'published'
if (Test-Path -LiteralPath $published) { Remove-Item -LiteralPath $published -Recurse -Force }
[void][IO.Directory]::CreateDirectory($published)
$manifestName = 'benefits.seed.manifest.json'

function Save-PublicSeedResponse([string]$Path, [string]$Name, [int]$Limit, [string]$CacheDirective) {
    $target = Join-Path $published $Name
    $headers = Join-Path $safeWorkDirectory 'response-headers.txt'
    $curlArgs = @('--silent', '--show-error', '--proto', '=https', '--connect-timeout', '10', '--max-time', '25',
        '--max-filesize', $Limit, '--header', 'Cache-Control: no-cache', '--dump-header', $headers,
        '--output', $target, '--write-out', '%{http_code}', '--', "$origin/$Path")
    $maxAttempts = if ($VerifyPublished) { 6 } else { 1 }
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $status = & curl @curlArgs
        if ($LASTEXITCODE -eq 0 -and $status -eq '200') { break }
        if ($attempt -eq $maxAttempts) {
            if ($LASTEXITCODE -ne 0) { throw "PUBLIC_SEED_DOWNLOAD_FAILED: $Name" }
            throw "PUBLIC_SEED_UNEXPECTED_HTTP_STATUS: $Name ($status)"
        }
        Start-Sleep -Seconds 5
    }
    $downloaded = Get-Item -LiteralPath $target
    if ($downloaded.Length -lt 1 -or $downloaded.Length -gt $Limit) {
        throw "PUBLIC_SEED_UNEXPECTED_SIZE: $Name ($($downloaded.Length))"
    }
    if ($VerifyPublished) {
        $headerText = Get-Content -LiteralPath $headers -Raw
        $escapedDirective = [regex]::Escape($CacheDirective)
        if ($headerText -notmatch '(?im)^Content-Type:\s*application/json\b' -or
            $headerText -notmatch "(?im)^Cache-Control:[^\r\n]*\b$escapedDirective\b") {
            throw "PUBLIC_SEED_UNEXPECTED_HEADERS: $Name"
        }
    }
}

$packageParams = @{
    AssetDirectory = $AssetDirectory
    CanonicalCsv = $CanonicalCsv
    OutputDirectory = Join-Path $safeWorkDirectory 'site'
}
if (!$Bootstrap -or $VerifyPublished) {
    $expectedManifest = $null
    if ($VerifyPublished) {
        $expectedManifest = ConvertFrom-InternalManifestJson -Text (Read-ReleaseUtf8Text -Path (Join-Path $AssetDirectory $manifestName))
    }
    $manifestAttempts = if ($VerifyPublished) { 6 } else { 1 }
    for ($attempt = 1; $attempt -le $manifestAttempts; $attempt++) {
        Save-PublicSeedResponse $manifestName $manifestName 16KB 'no-cache'
        $raw = Read-ReleaseUtf8Text -Path (Join-Path $published $manifestName)
        $manifest = ConvertFrom-InternalManifestJson -Text $raw
        Assert-BenefitReleaseSeedManifest -Manifest $manifest
        if (!$VerifyPublished -or $manifest.seedVersion -eq $expectedManifest.seedVersion -or $attempt -eq $manifestAttempts) {
            break
        }
        Start-Sleep -Seconds 5
    }
    $prefix = "v/$($manifest.seedVersion)"
    Save-PublicSeedResponse "$prefix/benefits.seed.json" 'benefits.seed.json' 4MB 'immutable'
    Save-PublicSeedResponse "$prefix/manual_benefits_seed.json" 'manual_benefits_seed.json' 256KB 'immutable'
    $packageParams.PublishedDirectory = $published
}

$result = & (Join-Path $PSScriptRoot 'build-public-benefit-seed-package.ps1') @packageParams
if ($VerifyPublished -and $result.publish) { throw 'PUBLIC_SEED_POST_DEPLOY_VERSION_MISMATCH' }
return $result

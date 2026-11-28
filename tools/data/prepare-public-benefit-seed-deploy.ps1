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
$published = Join-Path $WorkDirectory 'published'
[void][IO.Directory]::CreateDirectory($published)
$manifestName = 'benefits.seed.manifest.json'

function Save-PublicSeedResponse([string]$Path, [string]$Name, [int]$Limit, [string]$CacheDirective) {
    $target = Join-Path $published $Name
    $headers = Join-Path $WorkDirectory 'response-headers.txt'
    $curlArgs = @('--silent', '--show-error', '--proto', '=https', '--connect-timeout', '10', '--max-time', '25',
        '--max-filesize', $Limit, '--header', 'Cache-Control: no-cache', '--dump-header', $headers,
        '--output', $target, '--write-out', '%{http_code}', '--', "$origin/$Path")
    $status = & curl @curlArgs
    if ($LASTEXITCODE -ne 0) { throw "PUBLIC_SEED_DOWNLOAD_FAILED: $Name" }
    if ($status -ne '200') { throw "PUBLIC_SEED_UNEXPECTED_HTTP_STATUS: $Name ($status)" }
    if ($VerifyPublished) {
        $headerText = Get-Content -LiteralPath $headers -Raw
        if ($headerText -notmatch '(?im)^Content-Type:\s*application/json\b' -or
            $headerText -notmatch "(?im)^Cache-Control:[^\r\n]*\b$CacheDirective\b") {
            throw "PUBLIC_SEED_UNEXPECTED_HEADERS: $Name"
        }
    }
}

$packageParams = @{
    AssetDirectory = $AssetDirectory
    CanonicalCsv = $CanonicalCsv
    OutputDirectory = Join-Path $WorkDirectory 'site'
}
if (!$Bootstrap -or $VerifyPublished) {
    Save-PublicSeedResponse $manifestName $manifestName 16KB 'no-cache'
    $raw = Read-ReleaseUtf8Text -Path (Join-Path $published $manifestName)
    $manifest = ConvertFrom-InternalManifestJson -Text $raw
    Assert-BenefitReleaseSeedManifest -Manifest $manifest
    $prefix = "v/$($manifest.seedVersion)"
    Save-PublicSeedResponse "$prefix/benefits.seed.json" 'benefits.seed.json' 4MB 'immutable'
    Save-PublicSeedResponse "$prefix/manual_benefits_seed.json" 'manual_benefits_seed.json' 256KB 'immutable'
    $packageParams.PublishedDirectory = $published
}

$result = & (Join-Path $PSScriptRoot 'build-public-benefit-seed-package.ps1') @packageParams
if ($VerifyPublished -and $result.publish) { throw 'PUBLIC_SEED_POST_DEPLOY_VERSION_MISMATCH' }
return $result

[CmdletBinding()]
param(
    [string]$SeedJsonPath = '',
    [string]$ManualSeedJsonPath = '',
    [string]$CanonicalCsvPath = '',
    [int]$SeedVersion = 0,
    [string]$GeneratedAt = '',
    [string]$DestinationManifestPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:BuildManifestCliInvoked = ($PSBoundParameters.Count -gt 0)
$script:BuildManifestCliParams = @{
    SeedJsonPath = $SeedJsonPath
    ManualSeedJsonPath = $ManualSeedJsonPath
    CanonicalCsvPath = $CanonicalCsvPath
    SeedVersion = $SeedVersion
    GeneratedAt = $GeneratedAt
    DestinationManifestPath = $DestinationManifestPath
}

. (Join-Path $PSScriptRoot 'lib/release/approval-release-contracts.ps1')

function ConvertFrom-InternalManifestJson {
    param(
        [Parameter(Mandatory)][string]$Text,
        [switch]$NoEnumerate
    )

    $cleaned = if ($Text.Length -gt 0 -and $Text[0] -eq [char]0xFEFF) { $Text.Substring(1) } else { $Text }
    $params = @{}
    $cmdParams = (Get-Command ConvertFrom-Json).Parameters
    if ($cmdParams.ContainsKey('DateKind')) { $params.DateKind = 'String' }
    if ($NoEnumerate -and $cmdParams.ContainsKey('NoEnumerate')) { $params.NoEnumerate = $true }
    return ($cleaned | ConvertFrom-Json @params)
}

function Write-InternalManifestAtomicText {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content
    )

    $safe = Assert-ReleaseSafeFilePath -Path $Path
    $directory = Split-Path -Parent $safe
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        [void][IO.Directory]::CreateDirectory($directory)
    }
    $normalized = $Content.Replace("`r`n", "`n").Replace("`r", "`n")
    if (-not $normalized.EndsWith("`n")) { $normalized += "`n" }
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($normalized)
    $tempPath = Join-Path $directory ('.manifest-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllBytes($tempPath, $bytes)
        [IO.File]::Move($tempPath, $safe, $true)
    } finally {
        if (Test-Path -LiteralPath $tempPath) {
            [IO.File]::Delete($tempPath)
        }
    }
}

function New-ReleaseBenefitSeedManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SeedJsonPath,
        [Parameter(Mandatory)][string]$ManualSeedJsonPath,
        [Parameter(Mandatory)][string]$CanonicalCsvPath,
        [Parameter(Mandatory)][int]$SeedVersion,
        [string]$GeneratedAt = '',
        [string]$DestinationManifestPath = ''
    )

    if ($SeedVersion -lt 1) {
        throw "MNF_SEED_VERSION_INVALID: $SeedVersion"
    }

    $effectiveGeneratedAt = if ([string]::IsNullOrWhiteSpace($GeneratedAt)) {
        [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
    } else {
        $GeneratedAt
    }
    if (-not (Test-ReleaseIso8601WithOffset -Value $effectiveGeneratedAt)) {
        throw "MNF_GENERATED_AT_INVALID: $effectiveGeneratedAt"
    }

    $canonicalSafePath = Assert-ReleaseSafeFilePath -Path $CanonicalCsvPath
    if (-not (Test-Path -LiteralPath $canonicalSafePath -PathType Leaf)) {
        throw "MNF_CANONICAL_CSV_MISSING: $canonicalSafePath"
    }
    $canonicalRows = @(Import-Csv -LiteralPath $canonicalSafePath -Encoding utf8)
    if ($canonicalRows.Count -eq 0) {
        throw 'MNF_CANONICAL_CSV_EMPTY'
    }
    Assert-CanonicalBusinessIds -Rows $canonicalRows
    $canonicalCsvSha256 = Get-ReleaseFileNormalizedLfSha256 -Path $canonicalSafePath

    $seedText = Read-ReleaseUtf8Text -Path $SeedJsonPath
    $seedTrimmed = $seedText.TrimStart([char]0xFEFF).Trim()
    if (-not $seedTrimmed.StartsWith('[') -or -not $seedTrimmed.EndsWith(']')) {
        throw 'MNF_SEED_JSON_MUST_BE_ARRAY'
    }
    $seedParsed = ConvertFrom-InternalManifestJson -Text $seedText -NoEnumerate
    $seedItems = @($seedParsed)
    if ($seedItems.Count -lt 1) {
        throw 'MNF_SEED_JSON_EMPTY'
    }

    $seenIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $exactPinCount = 0
    $unconfirmedCount = 0
    $invariant = [Globalization.CultureInfo]::InvariantCulture
    foreach ($item in $seedItems) {
        if ($null -eq $item -or $item -isnot [pscustomobject]) {
            throw 'MNF_SEED_ITEM_NOT_OBJECT'
        }
        $idProp = $item.PSObject.Properties['id']
        $idVal = if ($null -eq $idProp -or $null -eq $idProp.Value) { '' } else { ([string]$idProp.Value).Trim() }
        if ([string]::IsNullOrWhiteSpace($idVal)) {
            throw 'MNF_SEED_ITEM_ID_BLANK'
        }
        if (-not $seenIds.Add($idVal)) {
            throw "MNF_SEED_ITEM_DUPLICATE_ID: $idVal"
        }
        $statusProp = $item.PSObject.Properties['status']
        $statusVal = if ($null -eq $statusProp -or $null -eq $statusProp.Value) { '' } else { ([string]$statusProp.Value).Trim() }
        if ($statusVal -cne 'ACTIVE') {
            throw "MNF_SEED_ITEM_NOT_ACTIVE: $idVal ($statusVal)"
        }

        $latProp = $item.PSObject.Properties['latitude']
        $lonProp = $item.PSObject.Properties['longitude']
        $latVal = if ($null -eq $latProp) { $null } else { $latProp.Value }
        $lonVal = if ($null -eq $lonProp) { $null } else { $lonProp.Value }
        if (($null -eq $latVal) -ne ($null -eq $lonVal)) {
            throw "MNF_SEED_ITEM_PARTIAL_COORDINATES: $idVal"
        }
        if ($null -ne $latVal) {
            $lat = 0.0
            $lon = 0.0
            if (-not [double]::TryParse([string]$latVal, [Globalization.NumberStyles]::Float, $invariant, [ref]$lat) -or
                -not [double]::TryParse([string]$lonVal, [Globalization.NumberStyles]::Float, $invariant, [ref]$lon) -or
                [double]::IsNaN($lat) -or [double]::IsInfinity($lat) -or
                [double]::IsNaN($lon) -or [double]::IsInfinity($lon) -or
                $lat -lt -90.0 -or $lat -gt 90.0 -or
                $lon -lt -180.0 -or $lon -gt 180.0) {
                throw "MNF_SEED_ITEM_INVALID_COORDINATES: $idVal"
            }
            $exactPinCount++
        } else {
            $unconfirmedCount++
        }
    }
    $seedSha256 = Get-ReleaseNormalizedLfSha256 -Text $seedText

    $manualText = Read-ReleaseUtf8Text -Path $ManualSeedJsonPath
    $manualTrimmed = $manualText.TrimStart([char]0xFEFF).Trim()
    if (-not $manualTrimmed.StartsWith('{') -or -not $manualTrimmed.EndsWith('}')) {
        throw 'MNF_MANUAL_SEED_MUST_BE_OBJECT'
    }
    $manualDoc = ConvertFrom-InternalManifestJson -Text $manualText -NoEnumerate
    if ($null -eq $manualDoc -or $manualDoc -isnot [pscustomobject] -or $manualDoc.PSObject.Properties.Name -cnotcontains 'items' -or $null -eq $manualDoc.items) {
        throw 'MNF_MANUAL_SEED_MISSING_ITEMS'
    }
    $manualItems = @($manualDoc.items)
    $manualSeenIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($mItem in $manualItems) {
        if ($null -eq $mItem -or $mItem -isnot [pscustomobject]) {
            throw 'MNF_MANUAL_ITEM_NOT_OBJECT'
        }
        $mIdProp = $mItem.PSObject.Properties['id']
        $mIdVal = if ($null -eq $mIdProp -or $null -eq $mIdProp.Value) { '' } else { ([string]$mIdProp.Value).Trim() }
        if ([string]::IsNullOrWhiteSpace($mIdVal)) {
            throw 'MNF_MANUAL_ITEM_ID_BLANK'
        }
        if (-not $manualSeenIds.Add($mIdVal)) {
            throw "MNF_MANUAL_ITEM_DUPLICATE_ID: $mIdVal"
        }
    }
    $manualSeedSha256 = Get-ReleaseNormalizedLfSha256 -Text $manualText

    $manifest = [pscustomobject][ordered]@{
        manifestVersion = 1
        seedName = 'benefits'
        seedVersion = [int]$SeedVersion
        hashAlgorithm = 'SHA-256-LF-UTF8'
        generatedAt = $effectiveGeneratedAt
        canonicalCsvSha256 = $canonicalCsvSha256
        totalCount = $seedItems.Count
        exactPinCount = $exactPinCount
        unconfirmedCoordinateCount = $unconfirmedCount
        seedSha256 = $seedSha256
        manualSeedCount = $manualItems.Count
        manualSeedSha256 = $manualSeedSha256
    }

    Assert-BenefitReleaseSeedManifest -Manifest $manifest

    if (-not [string]::IsNullOrWhiteSpace($DestinationManifestPath)) {
        $jsonText = $manifest | ConvertTo-Json -Depth 10
        Write-InternalManifestAtomicText -Path $DestinationManifestPath -Content $jsonText
    }

    return $manifest
}

if ($script:BuildManifestCliInvoked) {
    $cliArgs = $script:BuildManifestCliParams
    if ([string]::IsNullOrWhiteSpace($cliArgs.SeedJsonPath) -or
        [string]::IsNullOrWhiteSpace($cliArgs.ManualSeedJsonPath) -or
        [string]::IsNullOrWhiteSpace($cliArgs.CanonicalCsvPath) -or
        [int]$cliArgs.SeedVersion -lt 1) {
        throw 'MNF_CLI_PARAMETERS_REQUIRED: -SeedJsonPath, -ManualSeedJsonPath, -CanonicalCsvPath, and -SeedVersion (>=1) are required.'
    }

    $invokeParams = @{
        SeedJsonPath = $cliArgs.SeedJsonPath
        ManualSeedJsonPath = $cliArgs.ManualSeedJsonPath
        CanonicalCsvPath = $cliArgs.CanonicalCsvPath
        SeedVersion = $cliArgs.SeedVersion
    }
    if (-not [string]::IsNullOrWhiteSpace($cliArgs.GeneratedAt)) {
        $invokeParams.GeneratedAt = $cliArgs.GeneratedAt
    }
    if (-not [string]::IsNullOrWhiteSpace($cliArgs.DestinationManifestPath)) {
        $invokeParams.DestinationManifestPath = $cliArgs.DestinationManifestPath
    }

    New-ReleaseBenefitSeedManifest @invokeParams
}

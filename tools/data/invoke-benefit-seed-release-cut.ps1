[CmdletBinding()]
param(
    [switch]$LibraryOnly,
    [string]$CanonicalCsv = 'data/canonical/capital-area-military-benefits.csv',
    [string]$DdcComparisonCsv = 'data/canonical/reports/ddc-benefit-comparison-20261120.csv',
    [string]$PajuComparisonCsv = 'data/canonical/reports/paju-benefit-comparison-20261122.csv',
    [string]$YangjuComparisonCsv = 'data/canonical/reports/yangju-benefit-comparison-20261122.csv',
    [string]$MmaComparisonCsv = 'data/canonical/reports/mma-benefit-comparison-20261123-v14.csv',
    [string]$CoordinateReviewCsv = 'data/canonical/reports/poi-coordinate-review-candidates-20261123-v14.csv',
    [string]$ManualSeedJson = 'apps/android/app/src/main/assets/manual_benefits_seed.json',
    [int]$SeedVersion = 0,
    [string]$CandidateOutputCsv = '',
    [string]$DestinationSeedJson = 'apps/android/app/src/main/assets/benefits.seed.json',
    [string]$DestinationManifestPath = 'apps/android/app/src/main/assets/benefits.seed.manifest.json',
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ReleaseCutCliInvoked = ($MyInvocation.InvocationName -ne '.' -or $PSBoundParameters.Count -gt 0)
$script:ReleaseCutCliParams = @{
    CanonicalCsv = $CanonicalCsv
    DdcComparisonCsv = $DdcComparisonCsv
    PajuComparisonCsv = $PajuComparisonCsv
    YangjuComparisonCsv = $YangjuComparisonCsv
    MmaComparisonCsv = $MmaComparisonCsv
    CoordinateReviewCsv = $CoordinateReviewCsv
    ManualSeedJson = $ManualSeedJson
    SeedVersion = $SeedVersion
    CandidateOutputCsv = $CandidateOutputCsv
    DestinationSeedJson = $DestinationSeedJson
    DestinationManifestPath = $DestinationManifestPath
    Apply = [bool]$Apply
}

. (Join-Path $PSScriptRoot 'lib/identity/canonical-business-id.ps1')
. (Join-Path $PSScriptRoot 'lib/release/approval-release-contracts.ps1')

function Resolve-ReleaseCutPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$RepoRoot
    )

    if ([IO.Path]::IsPathRooted($Path)) {
        return [IO.Path]::GetFullPath($Path)
    }
    return [IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
}

function Assert-ReleaseCutNoKakaoCoordinates {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$CanonicalRows)

    for ($i = 0; $i -lt $CanonicalRows.Count; $i++) {
        $row = $CanonicalRows[$i]
        $rowNumber = $i + 2
        $coordSrc = if ($row.PSObject.Properties.Name -contains '좌표출처' -and $null -ne $row.좌표출처) { [string]$row.좌표출처 } else { '' }
        $coordUrl = if ($row.PSObject.Properties.Name -contains '좌표출처URL' -and $null -ne $row.좌표출처URL) { [string]$row.좌표출처URL } else { '' }
        if ($coordSrc -match '(?i)kakao|카카오' -or $coordUrl -match '(?i)kakao') {
            throw "RELEASE_CUT_KAKAO_COORDINATE_FORBIDDEN: Row $rowNumber uses Kakao coordinate provenance ('$coordSrc')."
        }
    }
}

function Assert-ReleaseCutOutputPaths {
    param([string[]]$OutputPaths, [string[]]$InputPaths)

    $comparer = if ($IsWindows) { [StringComparer]::OrdinalIgnoreCase } else { [StringComparer]::Ordinal }
    $destinations = [Collections.Generic.HashSet[string]]::new($comparer)
    foreach ($destination in $OutputPaths) {
        [void](Assert-ReleaseSafeFilePath -Path $destination)
        if ([IO.Directory]::Exists($destination) -or [IO.Path]::EndsInDirectorySeparator($destination)) {
            throw "RELEASE_CUT_OUTPUT_NOT_FILE: $destination"
        }
        if (-not $destinations.Add($destination)) {
            throw "RELEASE_CUT_PATH_COLLISION: $destination"
        }
    }

    foreach ($path in $InputPaths) {
        if ($destinations.Contains($path)) {
            throw "RELEASE_CUT_PATH_COLLISION: $path"
        }
    }

    foreach ($destination in $OutputPaths) {
        for ($parent = [IO.Path]::GetDirectoryName($destination); $parent; $parent = [IO.Path]::GetDirectoryName($parent)) {
            if ($destinations.Contains($parent)) {
                throw "RELEASE_CUT_PATH_COLLISION: $destination is inside output $parent"
            }
            if ([IO.File]::Exists($parent)) {
                throw "RELEASE_CUT_OUTPUT_PARENT_NOT_DIRECTORY: $parent"
            }
        }
    }
}

function Test-ReleaseCutPublishSeed {
    param([string]$SeedPath, [string]$ManifestPath, $Manifest)

    if (-not [IO.File]::Exists($ManifestPath)) {
        if ([IO.File]::Exists($SeedPath)) {
            throw "RELEASE_CUT_INSTALLED_MANIFEST_MISSING: $ManifestPath"
        }
        return $true
    }

    $installed = Get-Content -Raw -Encoding utf8 -LiteralPath $ManifestPath | ConvertFrom-Json
    $version = if ($null -ne $installed) { $installed.PSObject.Properties['seedVersion'] }
    if ($null -eq $version -or ($version.Value -isnot [int] -and $version.Value -isnot [long]) -or $version.Value -lt 1) {
        throw "RELEASE_CUT_INSTALLED_VERSION_INVALID: $ManifestPath"
    }

    if ($Manifest.seedVersion -gt $version.Value) {
        return $true
    }
    if ($Manifest.seedVersion -eq $version.Value) {
        # GeneratedAt changes on every build. All release content and provenance must match.
        $unchanged = $true
        foreach ($property in $Manifest.PSObject.Properties) {
            if ($property.Name -ceq 'generatedAt') { continue }
            $previous = $installed.PSObject.Properties[$property.Name]
            if ($null -eq $previous -or $previous.Value -cne $property.Value) {
                $unchanged = $false
                break
            }
        }
        if ($unchanged -and [IO.File]::Exists($SeedPath) -and
            (Get-ReleaseFileNormalizedLfSha256 -Path $SeedPath) -ceq $Manifest.seedSha256) {
            return $false
        }
    }

    throw "RELEASE_CUT_VERSION_NOT_NEWER: installed=$($version.Value), requested=$($Manifest.seedVersion)"
}

function Install-ReleaseCutOutput {
    param([string]$Source, [string]$Destination)

    $parent = [IO.Path]::GetDirectoryName($Destination)
    [void][IO.Directory]::CreateDirectory($parent)
    $temporary = Join-Path $parent ('.milimap-release-cut-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        Copy-Item -LiteralPath $Source -Destination $temporary -ErrorAction Stop
        [IO.File]::Move($temporary, $Destination, $true)
    } finally {
        [IO.File]::Delete($temporary)
    }
}

function Install-ReleaseCutOutputs {
    param([object[]]$Outputs, [string]$StagingDir)

    # Snapshot original bytes before touching any destination.
    for ($i = 0; $i -lt $Outputs.Count; $i++) {
        $output = $Outputs[$i]
        if ([IO.File]::Exists($output.Destination)) {
            $output.Backup = Join-Path $StagingDir "original-$i"
            [IO.File]::Copy($output.Destination, $output.Backup)
        }
    }

    $installedCount = 0
    try {
        foreach ($output in $Outputs) {
            Install-ReleaseCutOutput -Source $output.Source -Destination $output.Destination
            $installedCount++
        }
    } catch {
        $applyFailure = $_
        $restoreFailures = [Collections.Generic.List[string]]::new()
        for ($i = $installedCount - 1; $i -ge 0; $i--) {
            $output = $Outputs[$i]
            try {
                if ($output.Backup) {
                    Install-ReleaseCutOutput -Source $output.Backup -Destination $output.Destination
                } else {
                    [IO.File]::Delete($output.Destination)
                }
            } catch {
                $restoreFailures.Add("$($output.Destination) ($($_.Exception.Message))")
            }
        }
        if ($restoreFailures.Count -gt 0) {
            $details = $restoreFailures -join ' | '
            $failure = [IO.IOException]::new(
                "RELEASE_CUT_ROLLBACK_FAILED: $details. Original backups remain in $StagingDir.",
                $applyFailure.Exception
            )
            $failure.Data['ReleaseCutPreserveStaging'] = $true
            throw $failure
        }
        throw
    }
}

function Invoke-BenefitSeedReleaseCut {
    [CmdletBinding()]
    param(
        [string]$CanonicalCsv = 'data/canonical/capital-area-military-benefits.csv',
        [string]$DdcComparisonCsv = 'data/canonical/reports/ddc-benefit-comparison-20261120.csv',
        [string]$PajuComparisonCsv = 'data/canonical/reports/paju-benefit-comparison-20261122.csv',
        [string]$YangjuComparisonCsv = 'data/canonical/reports/yangju-benefit-comparison-20261122.csv',
        [string]$MmaComparisonCsv = 'data/canonical/reports/mma-benefit-comparison-20261123-v14.csv',
        [string]$CoordinateReviewCsv = 'data/canonical/reports/poi-coordinate-review-candidates-20261123-v14.csv',
        [string]$ManualSeedJson = 'apps/android/app/src/main/assets/manual_benefits_seed.json',
        [int]$SeedVersion = 0,
        [string]$CandidateOutputCsv = '',
        [string]$DestinationSeedJson = 'apps/android/app/src/main/assets/benefits.seed.json',
        [string]$DestinationManifestPath = 'apps/android/app/src/main/assets/benefits.seed.manifest.json',
        [switch]$Apply
    )

    $repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $resolvedCanonicalCsv = Resolve-ReleaseCutPath -Path $CanonicalCsv -RepoRoot $repoRoot
    $resolvedDdcCsv = Resolve-ReleaseCutPath -Path $DdcComparisonCsv -RepoRoot $repoRoot
    $resolvedPajuCsv = Resolve-ReleaseCutPath -Path $PajuComparisonCsv -RepoRoot $repoRoot
    $resolvedYangjuCsv = Resolve-ReleaseCutPath -Path $YangjuComparisonCsv -RepoRoot $repoRoot
    $resolvedMmaCsv = Resolve-ReleaseCutPath -Path $MmaComparisonCsv -RepoRoot $repoRoot
    $resolvedCoordCsv = Resolve-ReleaseCutPath -Path $CoordinateReviewCsv -RepoRoot $repoRoot
    $resolvedManualJson = Resolve-ReleaseCutPath -Path $ManualSeedJson -RepoRoot $repoRoot
    $resolvedDestSeedJson = Resolve-ReleaseCutPath -Path $DestinationSeedJson -RepoRoot $repoRoot
    $resolvedDestManifest = Resolve-ReleaseCutPath -Path $DestinationManifestPath -RepoRoot $repoRoot
    $resolvedCandidateOut = if ([string]::IsNullOrWhiteSpace($CandidateOutputCsv)) { '' } else { Resolve-ReleaseCutPath -Path $CandidateOutputCsv -RepoRoot $repoRoot }

    $inputPaths = @($resolvedCanonicalCsv, $resolvedDdcCsv, $resolvedPajuCsv, $resolvedYangjuCsv, $resolvedMmaCsv, $resolvedCoordCsv, $resolvedManualJson)
    foreach ($requiredFile in $inputPaths) {
        if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
            throw "RELEASE_CUT_INPUT_MISSING: $requiredFile"
        }
    }

    $effectiveSeedVersion = $SeedVersion
    if ($effectiveSeedVersion -le 0) {
        if (Test-Path -LiteralPath $resolvedDestManifest -PathType Leaf) {
            $existingManifest = Get-Content -Raw -Encoding utf8 -LiteralPath $resolvedDestManifest | ConvertFrom-Json
            if ($null -ne $existingManifest.PSObject.Properties['seedVersion'] -and [int]$existingManifest.seedVersion -gt 0) {
                $effectiveSeedVersion = [int]$existingManifest.seedVersion
            }
        }
        if ($effectiveSeedVersion -le 0) {
            $effectiveSeedVersion = 14
        }
    }

    $canonicalRows = @(Import-Csv -LiteralPath $resolvedCanonicalCsv -Encoding utf8)
    Assert-CanonicalBusinessIds -Rows $canonicalRows
    Assert-ReleaseCutNoKakaoCoordinates -CanonicalRows $canonicalRows

    $stagingDir = Join-Path ([IO.Path]::GetTempPath()) ('milimap-release-cut-' + [Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($stagingDir)
    $retainStaging = $false
    try {
        $stagedCandidatesCsv = Join-Path $stagingDir 'candidates.csv'
        $stagedIntermediateJson = Join-Path $stagingDir 'intermediate.json'
        $stagedSeedJson = Join-Path $stagingDir 'benefits.seed.json'
        $stagedManifestJson = Join-Path $stagingDir 'benefits.seed.manifest.json'

        & (Join-Path $PSScriptRoot 'build-official-benefit-release-candidates.ps1') `
            -CanonicalCsv $resolvedCanonicalCsv `
            -DdcComparisonCsv $resolvedDdcCsv `
            -PajuComparisonCsv $resolvedPajuCsv `
            -YangjuComparisonCsv $resolvedYangjuCsv `
            -MmaComparisonCsv $resolvedMmaCsv `
            -OutputCsv $stagedCandidatesCsv | Out-Null

        $convertParams = @{
            SourceCsv = $resolvedCanonicalCsv
            DestinationJson = $stagedIntermediateJson
        }
        if (Test-Path -LiteralPath $resolvedDestSeedJson -PathType Leaf) {
            $convertParams.DistrictReferenceJson = $resolvedDestSeedJson
        }
        & (Join-Path $PSScriptRoot 'convert-benefits.ps1') @convertParams | Out-Null

        & (Join-Path $PSScriptRoot 'build-release-benefit-seed.ps1') `
            -CanonicalCsv $resolvedCanonicalCsv `
            -CandidateCsv $stagedCandidatesCsv `
            -CoordinateReviewCsv $resolvedCoordCsv `
            -SourceJson $stagedIntermediateJson `
            -DestinationJson $stagedSeedJson | Out-Null

        & (Join-Path $PSScriptRoot 'build-release-benefit-seed-manifest.ps1') `
            -SeedJsonPath $stagedSeedJson `
            -ManualSeedJsonPath $resolvedManualJson `
            -CanonicalCsvPath $resolvedCanonicalCsv `
            -SeedVersion $effectiveSeedVersion `
            -DestinationManifestPath $stagedManifestJson | Out-Null

        $candidateRows = @(Import-Csv -LiteralPath $stagedCandidatesCsv -Encoding utf8)
        $seedItems = @(Get-Content -Raw -Encoding utf8 -LiteralPath $stagedSeedJson | ConvertFrom-Json)
        $manifest = Get-Content -Raw -Encoding utf8 -LiteralPath $stagedManifestJson | ConvertFrom-Json

        if ([int]$manifest.totalCount -ne ([int]$manifest.exactPinCount + [int]$manifest.unconfirmedCoordinateCount)) {
            throw "RELEASE_CUT_COUNT_MISMATCH: totalCount=$($manifest.totalCount) != pins=$($manifest.exactPinCount) + unconfirmed=$($manifest.unconfirmedCoordinateCount)"
        }
        $seenSeedIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($item in $seedItems) {
            if (-not $seenSeedIds.Add([string]$item.id)) {
                throw "RELEASE_CUT_DUPLICATE_SEED_ID: $($item.id)"
            }
            if ([string]$item.status -cne 'ACTIVE') {
                throw "RELEASE_CUT_NON_ACTIVE_SEED_ITEM: $($item.id) ($($item.status))"
            }
            $sLabel = if ($null -ne $item.PSObject.Properties['sourceLabel'] -and $null -ne $item.sourceLabel) { [string]$item.sourceLabel } else { '' }
            $sUrl = if ($null -ne $item.PSObject.Properties['sourceUrl'] -and $null -ne $item.sourceUrl) { [string]$item.sourceUrl } else { '' }
            if ($sLabel -match '(?i)kakao|카카오' -or $sUrl -match '(?i)kakao|dapi\.kakao') {
                throw "RELEASE_CUT_SEED_KAKAO_FORBIDDEN: $($item.id)"
            }
        }

        if ($Apply) {
            $outputPaths = @($resolvedDestSeedJson, $resolvedDestManifest)
            if ($resolvedCandidateOut) { $outputPaths += $resolvedCandidateOut }

            # Serialize Apply invocations so version checks and backups see the same installed state.
            $mutex = [Threading.Mutex]::new($false, 'MILIMAP_BENEFIT_SEED_RELEASE_CUT')
            try {
                try {
                    [void]$mutex.WaitOne()
                } catch [Threading.AbandonedMutexException] {
                    # WaitOne grants ownership even when the previous process exits unexpectedly.
                }
                try {
                    Assert-ReleaseCutOutputPaths -OutputPaths $outputPaths -InputPaths $inputPaths
                    $outputs = @()
                    if (Test-ReleaseCutPublishSeed -SeedPath $resolvedDestSeedJson -ManifestPath $resolvedDestManifest -Manifest $manifest) {
                        $outputs += [pscustomobject]@{ Source = $stagedSeedJson; Destination = $resolvedDestSeedJson; Backup = $null }
                        $outputs += [pscustomobject]@{ Source = $stagedManifestJson; Destination = $resolvedDestManifest; Backup = $null }
                    }
                    if ($resolvedCandidateOut -and (
                        -not [IO.File]::Exists($resolvedCandidateOut) -or
                        (Get-FileHash -LiteralPath $resolvedCandidateOut).Hash -cne (Get-FileHash -LiteralPath $stagedCandidatesCsv).Hash
                    )) {
                        $outputs += [pscustomobject]@{ Source = $stagedCandidatesCsv; Destination = $resolvedCandidateOut; Backup = $null }
                    }
                    Install-ReleaseCutOutputs -Outputs $outputs -StagingDir $stagingDir
                } finally {
                    $mutex.ReleaseMutex()
                }
            } finally {
                $mutex.Dispose()
            }
        }

        $publicEvidenceCount = @($seedItems | Where-Object { $_.sourceType -ceq 'PUBLIC_EVIDENCE' }).Count
        $localGovCount = @($seedItems | Where-Object { $_.sourceType -ceq 'LOCAL_GOV' }).Count

        return [pscustomobject][ordered]@{
            ContractType = 'BenefitSeedReleaseCutSummary'
            ContractVersion = 1
            Mode = if ($Apply) { 'APPLY' } else { 'DRY_RUN' }
            SeedVersion = [int]$manifest.seedVersion
            CanonicalCount = $canonicalRows.Count
            CandidateCount = $candidateRows.Count
            TotalCount = [int]$manifest.totalCount
            ExactPinCount = [int]$manifest.exactPinCount
            UnconfirmedCoordinateCount = [int]$manifest.unconfirmedCoordinateCount
            PublicEvidenceCount = $publicEvidenceCount
            LocalGovCount = $localGovCount
            CanonicalCsvSha256 = [string]$manifest.canonicalCsvSha256
            SeedSha256 = [string]$manifest.seedSha256
        }
    } catch {
        $retainStaging = $_.Exception.Data.Contains('ReleaseCutPreserveStaging')
        throw
    } finally {
        if (-not $retainStaging -and (Test-Path -LiteralPath $stagingDir)) {
            Remove-Item -LiteralPath $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

if ($LibraryOnly) { return }

if ($script:ReleaseCutCliInvoked) {
    $cli = $script:ReleaseCutCliParams
    Invoke-BenefitSeedReleaseCut @cli
}

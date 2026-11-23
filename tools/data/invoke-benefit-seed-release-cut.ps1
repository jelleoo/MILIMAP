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

$script:ReleaseCutCliInvoked = ($PSBoundParameters.Count -gt 0 -and -not $LibraryOnly)
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

    foreach ($requiredFile in @($resolvedCanonicalCsv, $resolvedDdcCsv, $resolvedPajuCsv, $resolvedYangjuCsv, $resolvedMmaCsv, $resolvedCoordCsv, $resolvedManualJson)) {
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

        & (Join-Path $PSScriptRoot 'convert-benefits.ps1') `
            -SourceCsv $resolvedCanonicalCsv `
            -DestinationJson $stagedIntermediateJson | Out-Null

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
            foreach ($targetPath in @($resolvedDestSeedJson, $resolvedDestManifest)) {
                $parent = Split-Path -Parent $targetPath
                if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
                    [void][IO.Directory]::CreateDirectory($parent)
                }
            }
            [IO.File]::Copy($stagedSeedJson, $resolvedDestSeedJson, $true)
            [IO.File]::Copy($stagedManifestJson, $resolvedDestManifest, $true)
            if (-not [string]::IsNullOrWhiteSpace($resolvedCandidateOut)) {
                $candParent = Split-Path -Parent $resolvedCandidateOut
                if (-not (Test-Path -LiteralPath $candParent -PathType Container)) {
                    [void][IO.Directory]::CreateDirectory($candParent)
                }
                [IO.File]::Copy($stagedCandidatesCsv, $resolvedCandidateOut, $true)
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
    } finally {
        if (Test-Path -LiteralPath $stagingDir) {
            Remove-Item -LiteralPath $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

if ($LibraryOnly) { return }

if ($script:ReleaseCutCliInvoked) {
    $cli = $script:ReleaseCutCliParams
    Invoke-BenefitSeedReleaseCut @cli
}

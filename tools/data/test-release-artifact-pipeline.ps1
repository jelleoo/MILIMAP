$ErrorActionPreference = 'Stop'

function Assert-Equal {
    param(
        [AllowNull()]$Actual,
        [AllowNull()]$Expected,
        [Parameter(Mandatory)][string]$Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message (expected: $Expected, actual: $Actual)"
    }
}

function Get-NormalizedJson {
    param([string]$Path)

    return (Get-Content -Raw -Encoding utf8 -LiteralPath $Path | ConvertFrom-Json | ConvertTo-Json -Depth 10 -Compress)
}

$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$canonicalCsv = Join-Path $repositoryRoot 'data\canonical\capital-area-military-benefits.csv'
$reportsRoot = Join-Path $repositoryRoot 'data\canonical\reports'
$appSeed = Join-Path $repositoryRoot 'apps\android\app\src\main\assets\benefits.seed.json'
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('milimap-release-artifact-' + [guid]::NewGuid().ToString('N'))
$sourceJson = Join-Path $temporaryRoot 'canonical-source.json'
$candidateCsv = Join-Path $temporaryRoot 'official-release-candidates.csv'
$releaseJson = Join-Path $temporaryRoot 'benefits.seed.json'

try {
    New-Item -ItemType Directory -Path $temporaryRoot | Out-Null

    & (Join-Path $PSScriptRoot 'convert-benefits.ps1') `
        -SourceCsv $canonicalCsv `
        -DestinationJson $sourceJson `
        -DistrictReferenceJson $appSeed
    $sourceItems = @(Get-Content -Raw -Encoding utf8 -LiteralPath $sourceJson | ConvertFrom-Json)
    Assert-Equal -Actual $sourceItems.Count -Expected 496 -Message '정본 496건을 중간 시드로 변환해야 합니다'
    Assert-Equal -Actual (@($sourceItems.id | Select-Object -Unique).Count) -Expected 496 -Message '정본 중간 시드 ID는 유일해야 합니다'

    & (Join-Path $PSScriptRoot 'build-official-benefit-release-candidates.ps1') `
        -CanonicalCsv $canonicalCsv `
        -DdcComparisonCsv (Join-Path $reportsRoot 'ddc-benefit-comparison-20260908.csv') `
        -PajuComparisonCsv (Join-Path $reportsRoot 'paju-benefit-comparison-20260906.csv') `
        -YangjuComparisonCsv (Join-Path $reportsRoot 'yangju-benefit-comparison-20260906.csv') `
        -OutputCsv $candidateCsv
    Assert-Equal -Actual (@(Import-Csv -LiteralPath $candidateCsv -Encoding utf8).Count) -Expected 249 -Message '공식 최신 근거 출시 후보는 249건이어야 합니다'

    & (Join-Path $PSScriptRoot 'build-release-benefit-seed.ps1') `
        -CanonicalCsv $canonicalCsv `
        -CandidateCsv $candidateCsv `
        -CoordinateReviewCsv (Join-Path $reportsRoot 'poi-coordinate-review-candidates-20260908.csv') `
        -SourceJson $sourceJson `
        -DestinationJson $releaseJson

    $releaseItems = @(Get-Content -Raw -Encoding utf8 -LiteralPath $releaseJson | ConvertFrom-Json)
    Assert-Equal -Actual $releaseItems.Count -Expected 249 -Message '출시 시드는 공식 최신 근거 249건만 포함해야 합니다'
    Assert-Equal -Actual (@($releaseItems | Where-Object { $_.status -eq 'ACTIVE' }).Count) -Expected 249 -Message '출시 시드 항목은 모두 이용 가능 상태여야 합니다'
    Assert-Equal -Actual (@($releaseItems | Where-Object { $null -ne $_.latitude -and $null -ne $_.longitude }).Count) -Expected 9 -Message '엄격 POI 대조를 통과한 9건만 지도 핀을 가져야 합니다'
    Assert-Equal -Actual (Get-NormalizedJson -Path $releaseJson) -Expected (Get-NormalizedJson -Path $appSeed) -Message '정본 파이프라인 결과가 Android 내장 출시 시드와 일치해야 합니다'
} finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}

Write-Output 'PASS: canonical release artifact pipeline'

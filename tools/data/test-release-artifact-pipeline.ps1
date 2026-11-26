$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/release/approval-release-contracts.ps1')

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
$appManualSeed = Join-Path $repositoryRoot 'apps\android\app\src\main\assets\manual_benefits_seed.json'
$appManifest = Join-Path $repositoryRoot 'apps\android\app\src\main\assets\benefits.seed.manifest.json'
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
    Assert-Equal -Actual $sourceItems.Count -Expected 1298 -Message '정본 1298건을 중간 시드로 변환해야 합니다'
    Assert-Equal -Actual (@($sourceItems.id | Select-Object -Unique).Count) -Expected 1298 -Message '정본 중간 시드 ID는 유일해야 합니다'

    & (Join-Path $PSScriptRoot 'build-official-benefit-release-candidates.ps1') `
        -CanonicalCsv $canonicalCsv `
        -DdcComparisonCsv (Join-Path $reportsRoot 'ddc-benefit-comparison-20261120.csv') `
        -PajuComparisonCsv (Join-Path $reportsRoot 'paju-benefit-comparison-20261122.csv') `
        -YangjuComparisonCsv (Join-Path $reportsRoot 'yangju-benefit-comparison-20261122.csv') `
        -MmaComparisonCsv (Join-Path $reportsRoot 'mma-benefit-comparison-20261126-v15.csv') `
        -OutputCsv $candidateCsv
    Assert-Equal -Actual (@(Import-Csv -LiteralPath $candidateCsv -Encoding utf8).Count) -Expected 1187 -Message '공식 최신 근거 출시 후보는 1187건이어야 합니다'

    & (Join-Path $PSScriptRoot 'build-release-benefit-seed.ps1') `
        -CanonicalCsv $canonicalCsv `
        -CandidateCsv $candidateCsv `
        -CoordinateReviewCsv (Join-Path $reportsRoot 'poi-coordinate-review-candidates-20261126-v15.csv') `
        -SourceJson $sourceJson `
        -DestinationJson $releaseJson

    $releaseItems = @(Get-Content -Raw -Encoding utf8 -LiteralPath $releaseJson | ConvertFrom-Json)
    Assert-Equal -Actual $releaseItems.Count -Expected 1187 -Message '출시 시드는 공식 최신 근거 1187건만 포함해야 합니다'
    Assert-Equal -Actual (@($releaseItems | Where-Object { $_.status -eq 'ACTIVE' }).Count) -Expected 1187 -Message '출시 시드 항목은 모두 이용 가능 상태여야 합니다'
    Assert-Equal -Actual (@($releaseItems | Where-Object { $null -ne $_.latitude -and $null -ne $_.longitude }).Count) -Expected 1170 -Message '엄격 POI 대조를 통과한 1170건만 지도 핀을 가져야 합니다'
    Assert-Equal -Actual (@($releaseItems | Where-Object { $_.lastVerifiedAt -eq '2026-11-26' }).Count) -Expected 177 -Message '2026-11-26 승인 반영·동기화 수도권 병무청 177건만 2026-11-26 확인일을 가져야 합니다'
    Assert-Equal -Actual (@($releaseItems | Where-Object { $_.lastVerifiedAt -eq '2026-11-23' }).Count) -Expected 646 -Message '2026-11-23 승인 반영 수도권 병무청 646건만 2026-11-23 확인일을 가져야 합니다'
    Assert-Equal -Actual (@($releaseItems | Where-Object { $_.lastVerifiedAt -eq '2026-11-22' }).Count) -Expected 302 -Message '2026-11-22 승인 반영 파주시 175건, 양주시 24건 및 병무청 103건(합계 302건)만 2026-11-22 확인일을 가져야 합니다'
    Assert-Equal -Actual (@($releaseItems | Where-Object { $_.lastVerifiedAt -eq '2026-11-20' }).Count) -Expected 46 -Message '2026-11-20 승인 반영 동두천시 46건만 2026-11-20 확인일을 가져야 합니다'
    Assert-Equal -Actual (@($releaseItems | Where-Object { $_.lastVerifiedAt -eq '2026-09-06' }).Count) -Expected 16 -Message '기존 확인일 유지 항목 16건은 2026-09-06 확인일을 유지해야 합니다'
    Assert-Equal -Actual (@($releaseItems | Where-Object { $_.sourceType -eq 'LOCAL_GOV' }).Count) -Expected 261 -Message '지자체 공식 자료 시드는 261건이어야 합니다'
    Assert-Equal -Actual (@($releaseItems | Where-Object { $_.sourceType -eq 'PUBLIC_EVIDENCE' }).Count) -Expected 926 -Message '번들 편입 병무청 시드는 926건(PUBLIC_EVIDENCE)이어야 합니다'
    Assert-Equal -Actual (@($releaseItems | Where-Object { $_.sourceType -eq 'MMA_API' }).Count) -Expected 0 -Message '번들 시드에는 라이브 전용 MMA_API sourceType이 남으면 안 됩니다'
    Assert-Equal -Actual (@($releaseItems | Where-Object { $_.sourceUrl -like '*nttNo=208699*' }).Count) -Expected 27 -Message '양주시 시드 27건은 현행 공식 안내 URL(nttNo=208699)을 가리켜야 합니다'
    Assert-Equal -Actual (@($releaseItems | Where-Object { $_.sourceUrl -like '*nttNo=206761*' }).Count) -Expected 0 -Message '삭제된 양주시 구 안내 URL(nttNo=206761)을 참조하면 안 됩니다'
    Assert-Equal -Actual (Get-NormalizedJson -Path $releaseJson) -Expected (Get-NormalizedJson -Path $appSeed) -Message '정본 파이프라인 결과가 Android 내장 출시 시드와 일치해야 합니다'

    if (-not (Test-Path -LiteralPath $appManifest -PathType Leaf)) {
        throw "커밋된 출시 시드 매니페스트가 없습니다: $appManifest"
    }
    $manifestJsonOptions = @{}
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) {
        $manifestJsonOptions.DateKind = 'String'
    }
    $committedManifest = Read-ReleaseUtf8Text -Path $appManifest | ConvertFrom-Json @manifestJsonOptions
    Assert-BenefitReleaseSeedManifest -Manifest $committedManifest
    Assert-Equal -Actual ([int]$committedManifest.seedVersion) -Expected 15 -Message '현재 1187건 시드 매니페스트의 seedVersion은 15여야 합니다'
    Assert-Equal -Actual ([int]$committedManifest.totalCount) -Expected 1187 -Message '매니페스트 totalCount는 1187이어야 합니다'
    Assert-Equal -Actual ([int]$committedManifest.exactPinCount) -Expected 1170 -Message '매니페스트 exactPinCount는 1170이어야 합니다'
    Assert-Equal -Actual ([int]$committedManifest.unconfirmedCoordinateCount) -Expected 17 -Message '매니페스트 unconfirmedCoordinateCount는 17이어야 합니다'
    Assert-Equal -Actual ([int]$committedManifest.manualSeedCount) -Expected 0 -Message '매니페스트 manualSeedCount는 0이어야 합니다'
    Assert-Equal -Actual $committedManifest.canonicalCsvSha256 -Expected (Get-ReleaseFileNormalizedLfSha256 -Path $canonicalCsv) -Message '매니페스트 canonicalCsvSha256가 정본 CSV와 일치해야 합니다'
    Assert-Equal -Actual $committedManifest.seedSha256 -Expected (Get-ReleaseFileNormalizedLfSha256 -Path $appSeed) -Message '매니페스트 seedSha256가 커밋된 benefits.seed.json과 일치해야 합니다'
    Assert-Equal -Actual $committedManifest.manualSeedSha256 -Expected (Get-ReleaseFileNormalizedLfSha256 -Path $appManualSeed) -Message '매니페스트 manualSeedSha256가 커밋된 manual_benefits_seed.json과 일치해야 합니다'
} finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}

Write-Output 'PASS: canonical release artifact pipeline'

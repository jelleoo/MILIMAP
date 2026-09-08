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

$fixtureRoot = Join-Path $PSScriptRoot 'testdata\release-benefit-seed'
$outputPath = Join-Path ([IO.Path]::GetTempPath()) ('release-benefit-seed-' + [guid]::NewGuid().ToString('N') + '.json')
$scriptPath = Join-Path $PSScriptRoot 'build-release-benefit-seed.ps1'

& $scriptPath `
    -CanonicalCsv (Join-Path $fixtureRoot 'canonical.csv') `
    -CandidateCsv (Join-Path $fixtureRoot 'candidates.csv') `
    -CoordinateReviewCsv (Join-Path $fixtureRoot 'coordinate-review.csv') `
    -SourceJson (Join-Path $fixtureRoot 'benefits.seed.json') `
    -DestinationJson $outputPath

$items = @(Get-Content -Raw -Encoding utf8 $outputPath | ConvertFrom-Json)
Assert-Equal -Actual $items.Count -Expected 3 -Message '공식 출시 후보만 시드에 포함해야 합니다'

$ddc = @($items | Where-Object { $_.id -eq 'ddc' })[0]
Assert-Equal -Actual $ddc.benefitDescription -Expected '전 메뉴 15% 할인' -Message '세부 공식 할인 문구를 시드에 반영해야 합니다'
Assert-Equal -Actual $ddc.latitude -Expected 37.5 -Message '확인 완료 좌표는 유지해야 합니다'

$paju = @($items | Where-Object { $_.id -eq 'paju' })[0]
Assert-Equal -Actual $paju.benefitDescription -Expected '군 장병·사회복무요원 대상 10% 이상 할인 또는 상응 서비스' -Message '파주 공통 혜택 문구를 시드에 반영해야 합니다'
Assert-Equal -Actual $paju.eligibleTarget -Expected '관내 주둔 군 장병·사회복무요원' -Message '파주 공통 적용 대상을 시드에 반영해야 합니다'
Assert-Equal -Actual $paju.latitude -Expected $null -Message '재확인 필요 위도는 출시 시드에서 비워야 합니다'
Assert-Equal -Actual $paju.longitude -Expected $null -Message '재확인 필요 경도는 출시 시드에서 비워야 합니다'

$yangju = @($items | Where-Object { $_.id -eq 'yangju' })[0]
Assert-Equal -Actual $yangju.benefitDescription -Expected '돈가스: 10% 할인' -Message '양주 공식 메뉴와 할인 문구를 시드에 반영해야 합니다'
Assert-Equal -Actual $yangju.lastVerifiedAt -Expected '2026-09-06' -Message '공식 근거 확인일을 시드에 반영해야 합니다'
Assert-Equal -Actual $yangju.latitude -Expected $null -Message '엄격 POI 좌표 감사가 없는 확인 완료 업소는 지도 핀을 표시하면 안 됩니다'
Assert-Equal -Actual $yangju.longitude -Expected $null -Message '엄격 POI 좌표 감사가 없는 확인 완료 업소는 지도 핀을 표시하면 안 됩니다'

Remove-Item -LiteralPath $outputPath -Force

$invalidCanonicalPath = Join-Path ([IO.Path]::GetTempPath()) ('release-benefit-seed-invalid-coordinate-status-' + [guid]::NewGuid().ToString('N') + '.csv')
$invalidOutputPath = Join-Path ([IO.Path]::GetTempPath()) ('release-benefit-seed-invalid-coordinate-status-' + [guid]::NewGuid().ToString('N') + '.json')
$invalidCanonical = Get-Content -Raw -Encoding utf8 (Join-Path $fixtureRoot 'canonical.csv')
$invalidCanonical = $invalidCanonical.Replace('파주 업소,경기도 파주시 테스트로 2,,재확인 필요', '파주 업소,경기도 파주시 테스트로 2,,알 수 없음')
Set-Content -LiteralPath $invalidCanonicalPath -Value $invalidCanonical -Encoding utf8

$unknownStatusRejected = $false
try {
    & $scriptPath `
        -CanonicalCsv $invalidCanonicalPath `
        -CandidateCsv (Join-Path $fixtureRoot 'candidates.csv') `
        -CoordinateReviewCsv (Join-Path $fixtureRoot 'coordinate-review.csv') `
        -SourceJson (Join-Path $fixtureRoot 'benefits.seed.json') `
        -DestinationJson $invalidOutputPath
} catch {
    $unknownStatusRejected = $_.Exception.Message -match '좌표검증상태가 올바르지 않습니다'
}

Remove-Item -LiteralPath $invalidCanonicalPath -Force
if (Test-Path -LiteralPath $invalidOutputPath) { Remove-Item -LiteralPath $invalidOutputPath -Force }
Assert-Equal -Actual $unknownStatusRejected -Expected $true -Message '알 수 없는 좌표검증상태는 출시 시드 생성을 중단해야 합니다'

Write-Output 'PASS: release benefit seed'

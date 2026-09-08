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

$fixtureRoot = Join-Path $PSScriptRoot 'testdata\official-benefit-release-candidates'
$outputPath = Join-Path ([IO.Path]::GetTempPath()) ('official-benefit-release-candidates-' + [guid]::NewGuid().ToString('N') + '.csv')
$scriptPath = Join-Path $PSScriptRoot 'build-official-benefit-release-candidates.ps1'

& $scriptPath `
    -CanonicalCsv (Join-Path $fixtureRoot 'canonical.csv') `
    -DdcComparisonCsv (Join-Path $fixtureRoot 'ddc.csv') `
    -PajuComparisonCsv (Join-Path $fixtureRoot 'paju.csv') `
    -YangjuComparisonCsv (Join-Path $fixtureRoot 'yangju.csv') `
    -OutputCsv $outputPath

$rows = @(Import-Csv -LiteralPath $outputPath -Encoding utf8)
Assert-Equal -Actual $rows.Count -Expected 3 -Message '최신 공식 근거가 있는 업소만 출시 후보에 포함해야 합니다'

$ddc = @($rows | Where-Object { $_.업소명 -eq '동두천 업소' })[0]
Assert-Equal -Actual $ddc.혜택문구유형 -Expected '세부' -Message '동두천 공식 개별 할인은 세부 문구로 유지해야 합니다'
Assert-Equal -Actual $ddc.출시할인정보 -Expected '전 메뉴 15% 할인' -Message '동두천 공식 개별 할인 문구를 사용해야 합니다'

$paju = @($rows | Where-Object { $_.업소명 -eq '파주 업소' })[0]
Assert-Equal -Actual $paju.혜택문구유형 -Expected '공통' -Message '파주 참여 목록은 공통 혜택 문구로 표시해야 합니다'
Assert-Equal -Actual $paju.출시할인정보 -Expected '군 장병·사회복무요원 대상 10% 이상 할인 또는 상응 서비스' -Message '파주 공식 공통 혜택 문구를 사용해야 합니다'
Assert-Equal -Actual $paju.출처URL -Expected 'https://www.paju.go.kr/www/www_02/health/health_03/health_03_09/health_03_09_01.jsp | https://example.com/paju-list' -Message '파주 공통 정책과 참여 목록 출처를 모두 남겨야 합니다'

$yangju = @($rows | Where-Object { $_.업소명 -eq '양주 업소' })[0]
Assert-Equal -Actual $yangju.혜택문구유형 -Expected '세부' -Message '양주 공식 개별 할인은 세부 문구로 유지해야 합니다'
Assert-Equal -Actual $yangju.출시할인정보 -Expected '돈가스: 10% 할인' -Message '양주 공식 메뉴와 할인 정보를 함께 표시해야 합니다'

Remove-Item -LiteralPath $outputPath -Force
Write-Output 'PASS: official benefit release candidates'

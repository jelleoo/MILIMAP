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

. (Join-Path $PSScriptRoot 'compare-yangju-benefits.ps1') -LibraryOnly

$fixtureRoot = Join-Path $PSScriptRoot 'testdata\yangju-official-list'
$canonicalRows = @(Import-Csv -LiteralPath (Join-Path $fixtureRoot 'canonical.csv') -Encoding utf8)
$officialRows = @(Import-Csv -LiteralPath (Join-Path $fixtureRoot 'official.csv') -Encoding utf8)
$comparisonRows = @(Compare-YangjuBenefits -CanonicalRows $canonicalRows -OfficialRows $officialRows)

Assert-Equal -Actual $comparisonRows.Count -Expected 3 -Message '정본 양주 행마다 비교 결과 하나를 만들어야 합니다'
Assert-Equal -Actual $comparisonRows[0].판정 -Expected '현재 공식 목록 일치 후보' -Message '상호·주소·전화가 같으면 기존 포괄 할인 문구가 달라도 최신 공식 후보여야 합니다'
Assert-Equal -Actual $comparisonRows[0].공식할인정보 -Expected '10% 할인' -Message '공식 파일의 구체적인 할인 정보를 보존해야 합니다'
Assert-Equal -Actual $comparisonRows[1].판정 -Expected '상호 변경 가능성' -Message '주소와 전화가 같고 상호만 달라지면 변경 가능성으로 보류해야 합니다'
Assert-Equal -Actual $comparisonRows[2].판정 -Expected '공식목록 미발견' -Message '현재 공식 목록에 없는 업소는 미발견으로 기록해야 합니다'
Assert-Equal -Actual $comparisonRows[0].정본반영여부 -Expected '아니오' -Message '양주 비교는 정본 자동 반영을 제안하면 안 됩니다'

Write-Output 'PASS: Yangju benefit comparison rules'

$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot 'compare-paju-benefits.ps1'
. $scriptPath -LibraryOnly

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

$fixturePath = Join-Path $PSScriptRoot 'testdata\paju-official-list.fixture.html'
$officialRows = @(ConvertFrom-PajuOfficialListHtml -Html (Get-Content -LiteralPath $fixturePath -Raw -Encoding utf8) -SourceUrl 'https://example.test/food')
Assert-Equal -Actual $officialRows.Count -Expected 2 -Message '파주 공식 표의 합계 행을 제외한 업소 행만 읽어야 합니다'
Assert-Equal -Actual $officialRows[0].Name -Expected '테스트 식당' -Message '파주 공식 표에서 업소명을 읽어야 합니다'
Assert-Equal -Actual $officialRows[0].Address -Expected '파주시 중앙로 10 (금촌동)' -Message '파주 공식 표에서 소재지를 읽어야 합니다'

$comparisonRows = @(Compare-PajuBenefits -CanonicalRows @(
    [pscustomobject]@{ 업소명 = '테스트식당'; 소재지도로명주소 = '경기도 파주시 중앙로10(금촌동)'; 업소전화번호 = '031-111-2222'; 할인정보 = '전체 메뉴 10% 할인' },
    [pscustomobject]@{ 업소명 = '변경 업소'; 소재지도로명주소 = '경기도 파주시 문화로20(금촌동)'; 업소전화번호 = '031-999-0000'; 할인정보 = '전체 메뉴 10% 할인' },
    [pscustomobject]@{ 업소명 = '목록 없는 업소'; 소재지도로명주소 = '경기도 파주시 새길 1'; 업소전화번호 = '031-555-6666'; 할인정보 = '전체 메뉴 10% 할인' }
) -OfficialRows $officialRows)
Assert-Equal -Actual $comparisonRows.Count -Expected 3 -Message '정본 행마다 비교 결과 하나를 만들어야 합니다'
Assert-Equal -Actual $comparisonRows[0].판정 -Expected '공식 참여업소 일치 후보' -Message '상호·주소·전화가 일치하면 참여업소 일치 후보여야 합니다'
Assert-Equal -Actual $comparisonRows[0].혜택상세검증 -Expected '참여 목록은 일치하나 개별 할인 조건 미기재' -Message '파주 목록에 없는 개별 할인 조건을 자동 확정하면 안 됩니다'
Assert-Equal -Actual $comparisonRows[1].판정 -Expected '상세정보 재확인 필요' -Message '전화가 다르면 현재 참여를 자동 확정하면 안 됩니다'
Assert-Equal -Actual $comparisonRows[2].판정 -Expected '공식목록 미발견' -Message '공식 표에 없는 상호는 미발견으로 보고해야 합니다'
Assert-Equal -Actual $comparisonRows[0].정본반영여부 -Expected '아니오' -Message '비교 도구는 정본 자동 반영을 제안하면 안 됩니다'

Write-Output 'PASS: Paju benefit comparison rules'

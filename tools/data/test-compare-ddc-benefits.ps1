$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot 'compare-ddc-benefits.ps1'
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

$fixturePath = Join-Path $PSScriptRoot 'testdata\ddc-official-list.fixture.html'
$officialRows = @(ConvertFrom-DdcOfficialListHtml -Html (Get-Content -LiteralPath $fixturePath -Raw -Encoding utf8))
Assert-Equal -Actual $officialRows.Count -Expected 2 -Message '동두천 공식 표의 데이터 행만 읽어야 합니다'
Assert-Equal -Actual $officialRows[0].Name -Expected '테스트 카페' -Message '공식 표에서 업소명을 읽어야 합니다'
Assert-Equal -Actual $officialRows[0].Address -Expected '중앙로 10, 2층 (생연동)' -Message '공식 표에서 주소를 보존해야 합니다'
Assert-Equal -Actual $officialRows[0].Discount -Expected '음료 10%' -Message '공식 표에서 할인 내용을 읽어야 합니다'

$comparisonRows = @(Compare-DdcBenefits -CanonicalRows @(
    [pscustomobject]@{ 업소명 = '테스트카페'; 소재지도로명주소 = '경기도 동두천시 중앙로10, 2층(생연동)'; 업소전화번호 = '031-111-2222'; 할인정보 = '음료 10% 할인' },
    [pscustomobject]@{ 업소명 = '변경 업소'; 소재지도로명주소 = '경기도 동두천시 평화로20(생연동)'; 업소전화번호 = '031-333-4444'; 할인정보 = '10% 할인' },
    [pscustomobject]@{ 업소명 = '목록 없는 업소'; 소재지도로명주소 = '경기도 동두천시 생연로 1'; 업소전화번호 = '031-555-6666'; 할인정보 = '10% 할인' }
) -OfficialRows $officialRows)
Assert-Equal -Actual $comparisonRows.Count -Expected 3 -Message '정본 행마다 비교 결과 하나를 만들어야 합니다'
Assert-Equal -Actual $comparisonRows[0].판정 -Expected '현재 공식 목록 일치 후보' -Message '상호·주소·전화·할인이 일치하면 일치 후보여야 합니다'
Assert-Equal -Actual $comparisonRows[1].판정 -Expected '상세정보 재확인 필요' -Message '할인이 달라지면 이용 가능으로 자동 확정하면 안 됩니다'
Assert-Equal -Actual $comparisonRows[2].판정 -Expected '공식목록 미발견' -Message '공식 표에 없는 상호는 미발견으로 보고해야 합니다'
Assert-Equal -Actual $comparisonRows[2].정본반영여부 -Expected '아니오' -Message '비교 도구는 정본 자동 반영을 제안하면 안 됩니다'

Write-Output 'PASS: DDC benefit comparison rules'

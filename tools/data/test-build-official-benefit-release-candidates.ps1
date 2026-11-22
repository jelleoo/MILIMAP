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
Assert-Equal -Actual $ddc.최근확인일 -Expected '2026-09-06' -Message '비교 CSV에 확인일이 없으면 기본 VerifiedOn(2026-09-06)을 사용해야 합니다'

$datedDdcPath = Join-Path ([IO.Path]::GetTempPath()) ('official-benefit-release-candidates-dated-' + [guid]::NewGuid().ToString('N') + '.csv')
$datedOutputPath = Join-Path ([IO.Path]::GetTempPath()) ('official-benefit-release-candidates-dated-out-' + [guid]::NewGuid().ToString('N') + '.csv')
@'
정본CSV행번호,업소명,소재지도로명주소,공식할인정보,판정,확인일
2,동두천 업소,테스트로 1,전 메뉴 15% 할인,현재 공식 목록 일치 후보,2026-11-20
'@ | Set-Content -LiteralPath $datedDdcPath -Encoding utf8

try {
    & $scriptPath `
        -CanonicalCsv (Join-Path $fixtureRoot 'canonical.csv') `
        -DdcComparisonCsv $datedDdcPath `
        -PajuComparisonCsv (Join-Path $fixtureRoot 'paju.csv') `
        -YangjuComparisonCsv (Join-Path $fixtureRoot 'yangju.csv') `
        -OutputCsv $datedOutputPath

    $datedRows = @(Import-Csv -LiteralPath $datedOutputPath -Encoding utf8)
    $datedDdc = @($datedRows | Where-Object { $_.업소명 -eq '동두천 업소' })[0]
    $datedPaju = @($datedRows | Where-Object { $_.업소명 -eq '파주 업소' })[0]
    Assert-Equal -Actual $datedDdc.최근확인일 -Expected '2026-11-20' -Message '비교 CSV에 행별 확인일이 있으면 해당 날짜를 우선 사용해야 합니다'
    Assert-Equal -Actual $datedPaju.최근확인일 -Expected '2026-09-06' -Message '확인일 컬럼이 없는 행은 기본 VerifiedOn으로 폴백해야 합니다'
} finally {
    if (Test-Path -LiteralPath $datedDdcPath) { Remove-Item -LiteralPath $datedDdcPath -Force }
    if (Test-Path -LiteralPath $datedOutputPath) { Remove-Item -LiteralPath $datedOutputPath -Force }
}

$mismatchDdcPath = Join-Path ([IO.Path]::GetTempPath()) ('official-benefit-release-candidates-mismatch-' + [guid]::NewGuid().ToString('N') + '.csv')
$mismatchOutputPath = Join-Path ([IO.Path]::GetTempPath()) ('official-benefit-release-candidates-mismatch-output-' + [guid]::NewGuid().ToString('N') + '.csv')
@'
정본CSV행번호,업소명,소재지도로명주소,공식할인정보,판정
2,동두천 업소,테스트로 999,전 메뉴 15% 할인,현재 공식 목록 일치 후보
'@ | Set-Content -LiteralPath $mismatchDdcPath -Encoding utf8

$mismatchMessage = ''
try {
    & $scriptPath `
        -CanonicalCsv (Join-Path $fixtureRoot 'canonical.csv') `
        -DdcComparisonCsv $mismatchDdcPath `
        -PajuComparisonCsv (Join-Path $fixtureRoot 'paju.csv') `
        -YangjuComparisonCsv (Join-Path $fixtureRoot 'yangju.csv') `
        -OutputCsv $mismatchOutputPath
    throw '주소 불일치 후보 생성은 실패해야 합니다.'
} catch {
    $mismatchMessage = $_.Exception.Message
}
if ($mismatchMessage -notmatch [regex]::Escape('정본CSV행번호 2의 업소명 또는 도로명주소가 비교 결과와 일치하지 않습니다.')) {
    throw "주소 불일치 오류는 정본 행 번호를 포함해야 합니다. actual: $mismatchMessage"
}

Remove-Item -LiteralPath $outputPath -Force
Remove-Item -LiteralPath $mismatchDdcPath -Force
if (Test-Path -LiteralPath $mismatchOutputPath) { Remove-Item -LiteralPath $mismatchOutputPath -Force }

$mmaFixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('official-benefit-release-candidates-mma-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $mmaFixtureRoot | Out-Null
try {
    $mmaCanonicalPath = Join-Path $mmaFixtureRoot 'canonical.csv'
    $mmaCsvPath = Join-Path $mmaFixtureRoot 'mma.csv'
    $mmaOutPath = Join-Path $mmaFixtureRoot 'candidates.csv'
    @'
businessId,업종명,업소명,시도,시군구,소재지도로명주소,소재지지번주소,위도,경도,좌표출처,좌표출처URL,좌표검증상태,할인정보,적용대상,이용조건,인증방법,업소전화번호,출처유형,출처URL,최근확인일,혜택상태,수집자,비고
biz-ddc,미용·뷰티,동두천 업소,경기도,동두천시,테스트로 1,,37.5,127.0,확인출처,https://example.com,확인 완료,커트 할인,현역 장병,평일 방문,휴가증,031-000-0001,지자체 공식 자료,https://ddc.example.com,2026-09-06,이용 가능,tester,
biz-paju,음식,파주 업소,경기도,파주시,테스트로 2,,37.7,126.8,,,재확인 필요,10% 할인,군 장병,주말 제외,군인증,031-000-0002,지자체 공식 자료,https://paju.example.com,2026-09-06,이용 가능,tester,
biz-yangju,음식,양주 업소,경기도,양주시,테스트로 3,,37.8,127.1,Geocoding API,https://yangju.example.com,확인 완료,공통 할인,장병,예약 필수,신분증,031-000-0003,지자체 공식 자료,https://yangju.example.com,2026-09-06,이용 가능,tester,
biz-mma,음식,병무청 업소,경기도,수원시,수원로 4,,37.2,127.0,소상공인 상가정보(공공누리1유형),https://apis.data.go.kr/B553077/api/open/sdsc2,확인 완료,기존 문구,복무중인 사람,방문 확인,복무확인서,031-000-0004,공공데이터,https://www.mma.go.kr/about/udgg/list.do?mc=mma0003357,2026-08-15,이용 가능,tester,
'@ | Set-Content -LiteralPath $mmaCanonicalPath -Encoding utf8
    @'
정본CSV행번호,업소명,소재지도로명주소,기존할인정보,공식할인정보,관측상태,판정,검토결정,정본반영여부,확인일
5,병무청 업소,수원로 4,기존 문구,전 메뉴 10% 할인,LOCATED,현재 공식 목록 일치 후보,승인(ilwoo-maker),예,2026-11-22
'@ | Set-Content -LiteralPath $mmaCsvPath -Encoding utf8

    & $scriptPath `
        -CanonicalCsv $mmaCanonicalPath `
        -DdcComparisonCsv (Join-Path $fixtureRoot 'ddc.csv') `
        -PajuComparisonCsv (Join-Path $fixtureRoot 'paju.csv') `
        -YangjuComparisonCsv (Join-Path $fixtureRoot 'yangju.csv') `
        -MmaComparisonCsv $mmaCsvPath `
        -OutputCsv $mmaOutPath

    $withMmaRows = @(Import-Csv -LiteralPath $mmaOutPath -Encoding utf8)
    Assert-Equal -Actual $withMmaRows.Count -Expected 4 -Message 'MmaComparisonCsv 지정 시 병무청 후보도 함께 생성해야 합니다'
    $mmaRow = @($withMmaRows | Where-Object { $_.업소명 -eq '병무청 업소' })[0]
    Assert-Equal -Actual $mmaRow.혜택문구유형 -Expected '세부' -Message '병무청 후보는 세부 문구 유형이어야 합니다'
    Assert-Equal -Actual $mmaRow.출처유형 -Expected '병무청 나라사랑가게' -Message '병무청 후보는 병무청 나라사랑가게 출처유형이어야 합니다'
    Assert-Equal -Actual $mmaRow.출시할인정보 -Expected '전 메뉴 10% 할인' -Message '병무청 후보는 관측된 공식할인정보를 사용해야 합니다'
    Assert-Equal -Actual $mmaRow.최근확인일 -Expected '2026-11-22' -Message '병무청 후보는 비교 CSV 확인일을 사용해야 합니다'
} finally {
    if (Test-Path -LiteralPath $mmaFixtureRoot) { Remove-Item -LiteralPath $mmaFixtureRoot -Recurse -Force }
}

Write-Output 'PASS: official benefit release candidates'

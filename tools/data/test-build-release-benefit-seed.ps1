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

$mmaTempRoot = Join-Path ([IO.Path]::GetTempPath()) ('release-benefit-seed-mma-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $mmaTempRoot | Out-Null
try {
    $mmaCanon = Join-Path $mmaTempRoot 'canonical.csv'
    $mmaCand = Join-Path $mmaTempRoot 'candidates.csv'
    $mmaRev = Join-Path $mmaTempRoot 'coordinate-review.csv'
    $mmaSrcJson = Join-Path $mmaTempRoot 'source.json'
    $mmaOutJson = Join-Path $mmaTempRoot 'out.json'
    @'
businessId,업종명,업소명,시도,시군구,소재지도로명주소,소재지지번주소,위도,경도,좌표출처,좌표출처URL,좌표검증상태,할인정보,적용대상,이용조건,인증방법,업소전화번호,출처유형,출처URL,최근확인일,혜택상태,수집자,비고
biz-mma,음식,병무청 업소,경기도,수원시,수원로 4,,37.26,127.01,소상공인 상가정보(공공누리1유형),https://apis.data.go.kr/B553077/api/open/sdsc2,확인 완료,전 메뉴 10% 할인,복무중인 사람,방문 확인,복무확인서,031-000-0004,공공데이터,https://www.mma.go.kr/about/udgg/list.do?mc=mma0003357,2026-11-22,이용 가능,tester,
'@ | Set-Content -LiteralPath $mmaCanon -Encoding utf8
    @'
정본CSV행번호,업소명,소재지도로명주소,혜택근거상태,혜택문구유형,출시할인정보,출시적용대상,출시이용조건,출시인증방법,출처유형,출처URL,최근확인일,결정근거
2,병무청 업소,수원로 4,공식 최신 근거 확인,세부,전 메뉴 10% 할인,복무중인 사람,방문 확인,복무확인서,병무청 나라사랑가게,https://www.mma.go.kr/about/udgg/list.do?mc=mma0003357,2026-11-22,테스트
'@ | Set-Content -LiteralPath $mmaCand -Encoding utf8
    @'
정본CSV행번호,업소명,소재지도로명주소,감사판정
2,병무청 업소,수원로 4,확인 후보
'@ | Set-Content -LiteralPath $mmaRev -Encoding utf8
    @'
[
  {
    "id": "seed-mma-1",
    "name": "병무청 업소",
    "address": "수원로 4",
    "latitude": 37.26,
    "longitude": 127.01,
    "category": "음식",
    "benefitType": "할인·우대",
    "benefitDescription": "기존",
    "phone": "031-000-0004",
    "eligibleTarget": "복무중인 사람",
    "usageCondition": "방문 확인",
    "verificationMethod": "복무확인서",
    "sourceType": "MMA_API",
    "sourceLabel": "공공데이터",
    "sourceUrl": "https://www.mma.go.kr/about/udgg/list.do?mc=mma0003357",
    "lastVerifiedAt": "2026-08-15",
    "status": "ACTIVE",
    "district": "수원시"
  }
]
'@ | Set-Content -LiteralPath $mmaSrcJson -Encoding utf8

    & $scriptPath `
        -CanonicalCsv $mmaCanon `
        -CandidateCsv $mmaCand `
        -CoordinateReviewCsv $mmaRev `
        -SourceJson $mmaSrcJson `
        -DestinationJson $mmaOutJson

    $mmaItems = @(Get-Content -Raw -Encoding utf8 $mmaOutJson | ConvertFrom-Json)
    Assert-Equal -Actual $mmaItems.Count -Expected 1 -Message '병무청 후보가 1건 생성되어야 합니다'
    Assert-Equal -Actual $mmaItems[0].sourceType -Expected 'PUBLIC_EVIDENCE' -Message '번들 시드 내 병무청 항목은 PUBLIC_EVIDENCE sourceType으로 정규화해야 합니다'
    Assert-Equal -Actual $mmaItems[0].sourceLabel -Expected '병무청 나라사랑가게 · 최신 확인' -Message '병무청 항목 sourceLabel 형식을 유지해야 합니다'
    Assert-Equal -Actual $mmaItems[0].latitude -Expected 37.26 -Message '엄격 좌표 감사를 통과한 병무청 항목은 좌표를 유지해야 합니다'
} finally {
    if (Test-Path -LiteralPath $mmaTempRoot) { Remove-Item -LiteralPath $mmaTempRoot -Recurse -Force }
}

Write-Output 'PASS: release benefit seed'

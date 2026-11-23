Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'run-weekly-benefit-drift-check.ps1') -LibraryOnly

function Assert-WeeklyEqual {
    param(
        $Actual,
        $Expected,
        [string]$Message
    )

    if ($Actual -cne $Expected) {
        throw "Assertion failed: $Message (expected='$Expected', actual='$Actual')"
    }
}

# 1. JSONP parser: valid list and rejection of malformed inputs
$validJsonp = 'MmaBenefitList({"success":true,"list":[{"udgigwan_cd":"101","udae_ggm":"가게A","addr":"서울특별시 강남구 테헤란로 1","udgigwan_telno":"02-111-2222","udggeopjong_gbnm":"음식점","hyhaeje_yn":""}]});'
$parsed = @(ConvertFrom-WeeklyMmaJsonpListText -RawText $validJsonp)
Assert-WeeklyEqual -Actual $parsed.Count -Expected 1 -Message 'Valid JSONP must parse 1 list item'
Assert-WeeklyEqual -Actual $parsed[0].udae_ggm -Expected '가게A' -Message 'Parsed item must keep udae_ggm'

$rejectedMalformed = $false
try {
    [void](ConvertFrom-WeeklyMmaJsonpListText -RawText '{"list":[]}')
} catch {
    $rejectedMalformed = $true
}
if (-not $rejectedMalformed) {
    throw 'Expected ConvertFrom-WeeklyMmaJsonpListText to reject payload without callback wrapper'
}

$rejectedMissingList = $false
try {
    [void](ConvertFrom-WeeklyMmaJsonpListText -RawText 'MmaBenefitList({"success":true});')
} catch {
    $rejectedMissingList = $true
}
if (-not $rejectedMissingList) {
    throw 'Expected ConvertFrom-WeeklyMmaJsonpListText to reject payload missing list array'
}

# 2. Metro comparison: cd= match, normalized (name, addr) fallback, content drift (DISCOUNT|PHONE), new candidate, missing canonical, non-metro ignore, ended ignore
$liveItems = @(
    [pscustomobject]@{ udgigwan_cd = '1001'; udae_ggm = '코드매칭점'; addr = '서울특별시 종로구 종로 1'; udgigwan_telno = '02-000-9999'; udsangse_cn = '전 메뉴 20% 할인'; uddaesang_cn = '현역병'; udggeopjong_gbnm = '카페'; jbc_nm = '서울'; hyhaeje_yn = '' },
    [pscustomobject]@{ udgigwan_cd = '1002'; udae_ggm = '이름주소 매칭'; addr = '경기도 수원시 팔달구 효원로 10 (1층)'; udgigwan_telno = '031-000-0002'; udsangse_cn = '10% 할인'; uddaesang_cn = '현역병'; udggeopjong_gbnm = '병원'; jbc_nm = '경인'; hyhaeje_yn = '' },
    [pscustomobject]@{ udgigwan_cd = '1003'; udae_ggm = '신규수도권점'; addr = '인천광역시 부평구 부평대로 20'; udgigwan_telno = '032-000-0003'; udggeopjong_gbnm = '안경점'; jbc_nm = '인천'; hyhaeje_yn = '' },
    [pscustomobject]@{ udgigwan_cd = '1004'; udae_ggm = '부산비수도권점'; addr = '부산광역시 해운대구 해운대로 30'; udgigwan_telno = '051-000-0004'; udggeopjong_gbnm = '음식점'; jbc_nm = '부산.울산'; hyhaeje_yn = '' },
    [pscustomobject]@{ udgigwan_cd = '1005'; udae_ggm = '남해경인관할점'; addr = '경상남도 남해군 서부로 1337'; udgigwan_telno = '055-000-0005'; udggeopjong_gbnm = '음식점'; jbc_nm = '경인'; hyhaeje_yn = '' },
    [pscustomobject]@{ udgigwan_cd = '1006'; udae_ggm = '해지된가게'; addr = '서울특별시 마포구 양화로 5'; udgigwan_telno = '02-000-0006'; udggeopjong_gbnm = '음식점'; jbc_nm = '서울'; hyhaeje_yn = 'Y' }
)

$canonicalRows = @(
    [pscustomobject]@{ businessId = 'biz-1'; 업소명 = '코드매칭점'; 시도 = '서울특별시'; 시군구 = '종로구'; 소재지도로명주소 = '서울특별시 종로구 종로 1'; 업소전화번호 = '02-000-0001'; 할인정보 = '전 메뉴 10% 할인'; 적용대상 = '현역병'; 출처유형 = '공공데이터'; 출처URL = 'https://www.mma.go.kr/about/udgg/list.do?mc=mma0003357'; 최근확인일 = '2026-11-23'; 좌표검증상태 = '확인 완료'; 혜택상태 = '이용 가능'; 비고 = '병무청 나라사랑가게 공식목록(cd=1001, 업종=카페)' },
    [pscustomobject]@{ businessId = 'biz-2'; 업소명 = '이름주소매칭'; 시도 = '경기도'; 시군구 = '수원시'; 소재지도로명주소 = '경기도수원시팔달구효원로10(1층)'; 업소전화번호 = '0310000002'; 할인정보 = '10%   할인'; 적용대상 = '현역병'; 출처유형 = '공공데이터'; 출처URL = 'https://www.mma.go.kr/about/udgg/list.do?mc=mma0003357'; 최근확인일 = '2026-11-23'; 좌표검증상태 = '확인 완료'; 혜택상태 = '이용 가능'; 비고 = '사전 수집' },
    [pscustomobject]@{ businessId = 'biz-3'; 업소명 = '정본미관측점'; 시도 = '경기도'; 시군구 = '성남시'; 소재지도로명주소 = '경기도 성남시 분당구 판교로 99'; 업소전화번호 = '031-000-0003'; 할인정보 = '5% 할인'; 적용대상 = '현역병'; 출처유형 = '공공데이터'; 출처URL = 'https://www.mma.go.kr/about/udgg/list.do?mc=mma0003357'; 최근확인일 = '2026-11-22'; 좌표검증상태 = '확인 완료'; 혜택상태 = '이용 가능'; 비고 = '병무청 나라사랑가게 공식목록(cd=1099, 업종=병원)' },
    [pscustomobject]@{ businessId = 'biz-4'; 업소명 = '이미종료된점'; 시도 = '경기도'; 시군구 = '안양시'; 소재지도로명주소 = '경기도 안양시 동안구 시민대로 1'; 업소전화번호 = ''; 할인정보 = ''; 적용대상 = ''; 출처유형 = '공공데이터'; 출처URL = 'https://www.mma.go.kr/about/udgg/list.do?mc=mma0003357'; 최근확인일 = '2026-11-22'; 좌표검증상태 = '미확인'; 혜택상태 = '종료'; 비고 = 'cd=1098' },
    [pscustomobject]@{ businessId = 'biz-5'; 업소명 = '파주지자체가게'; 시도 = '경기도'; 시군구 = '파주시'; 소재지도로명주소 = '경기도 파주시 중앙로 1'; 업소전화번호 = ''; 할인정보 = ''; 적용대상 = ''; 출처유형 = '지자체 공식 자료'; 출처URL = 'https://www.paju.go.kr/user/soldier/BD_discountStoreList.do?q_ctgCd=1001'; 최근확인일 = '2026-11-22'; 좌표검증상태 = '확인 완료'; 혜택상태 = '이용 가능'; 비고 = '' }
)

$drift = Compare-WeeklyMmaMetroToCanonical -LiveItems $liveItems -CanonicalRows $canonicalRows
Assert-WeeklyEqual -Actual $drift.totalLiveCount -Expected 6 -Message 'Total live count should include all raw entries'
Assert-WeeklyEqual -Actual $drift.liveMetroCount -Expected 3 -Message 'Only active 서울/경기/인천 addresses should count as live metro'
Assert-WeeklyEqual -Actual $drift.canonicalMmaCount -Expected 4 -Message 'Only MMA canonical rows should be counted'
Assert-WeeklyEqual -Actual $drift.canonicalActiveMmaCount -Expected 3 -Message 'Ended canonical MMA rows should be excluded from active comparison'
Assert-WeeklyEqual -Actual $drift.matchedCount -Expected 2 -Message 'Both cd= match and normalized (name, addr) match should succeed'
Assert-WeeklyEqual -Actual $drift.changedCount -Expected 1 -Message 'Exactly 1 matched MMA row has content changes (DISCOUNT|PHONE)'
Assert-WeeklyEqual -Actual $drift.changedCandidates[0].BusinessId -Expected 'biz-1' -Message 'Changed candidate must be biz-1'
Assert-WeeklyEqual -Actual $drift.changedCandidates[0].ChangedFields -Expected 'DISCOUNT|PHONE' -Message 'Changed fields must record DISCOUNT|PHONE'
Assert-WeeklyEqual -Actual $drift.newCandidateCount -Expected 1 -Message 'Exactly 1 new metro candidate expected'
Assert-WeeklyEqual -Actual $drift.newCandidates[0].InstitutionCode -Expected '1003' -Message 'New candidate cd must be 1003'
Assert-WeeklyEqual -Actual $drift.missingCanonicalCount -Expected 1 -Message 'Exactly 1 missing active canonical MMA row expected'
Assert-WeeklyEqual -Actual $drift.missingCanonical[0].BusinessId -Expected 'biz-3' -Message 'Missing canonical row must be biz-3'

# 2b. Yangju XLSX attachment hash check
$yjSampleBytes = [Text.Encoding]::UTF8.GetBytes('yangju-xlsx-sample-v1')
$yjSampleHash = [BitConverter]::ToString([Security.Cryptography.SHA256]::HashData($yjSampleBytes)).Replace('-', '').ToLowerInvariant()
$yjOk = Test-WeeklyYangjuAttachmentDrift -AttachmentBytes $yjSampleBytes -BaselineHash $yjSampleHash -BaselineByteSize $yjSampleBytes.Length
Assert-WeeklyEqual -Actual $yjOk.status -Expected 'OK' -Message 'Matching SHA-256 hash should yield OK'
Assert-WeeklyEqual -Actual $yjOk.hashMatched -Expected $true -Message 'hashMatched should be true when bytes match'

$yjChangedBytes = [Text.Encoding]::UTF8.GetBytes('yangju-xlsx-sample-v2')
$yjDrift = Test-WeeklyYangjuAttachmentDrift -AttachmentBytes $yjChangedBytes -BaselineHash $yjSampleHash -BaselineByteSize $yjSampleBytes.Length
Assert-WeeklyEqual -Actual $yjDrift.status -Expected 'DRIFT_DETECTED' -Message 'Modified bytes should yield DRIFT_DETECTED'
Assert-WeeklyEqual -Actual $yjDrift.hashMatched -Expected $false -Message 'hashMatched should be false when bytes differ'

# 3. Markdown report generation
$summaryFixture = [pscustomobject][ordered]@{
    contractType = 'WeeklyBenefitDriftSummary'
    contractVersion = 1
    generatedAtUtc = '2026-11-23T19:00:00Z'
    canonicalRowCount = 1137
    automaticCanonicalMutation = $false
    productionAction = 'NONE'
    sources = @(
        [pscustomobject][ordered]@{ id = 'ddc'; name = '동두천시 (ddc.go.kr)'; status = 'OK'; officialCount = 50; canonicalCount = 46; detail = '일치=46'; error = '' },
        [pscustomobject][ordered]@{ id = 'paju'; name = '파주시 (paju.go.kr)'; status = 'FETCH_FAILED'; officialCount = $null; canonicalCount = $null; detail = '조회 실패'; error = 'timeout' },
        [pscustomobject][ordered]@{ id = 'yangju'; name = '양주시 (yangju.go.kr)'; status = 'MANUAL_CSV_REQUIRED'; officialCount = $null; canonicalCount = 24; detail = '공고 첨부 CSV 수동 비교 대상'; error = '' }
    )
}
$md = New-WeeklyDriftMarkdownReport -Summary $summaryFixture
if ($md -notmatch 'ProductionAction.*NONE' -or $md -notmatch 'FETCH_FAILED' -or $md -notmatch 'MANUAL_CSV_REQUIRED' -or $md -notmatch 'timeout') {
    throw 'Generated weekly drift markdown report is missing expected fields.'
}

# 4. Path safety guard rejects writing inside data/ or apps/
$unsafeRejected = $false
try {
    [void](Assert-WeeklyOutputSafePath -OutputDir (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'data/canonical/unsafe') -RepoRoot (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent))
} catch {
    $unsafeRejected = $true
}
if (-not $unsafeRejected) {
    throw 'Expected Assert-WeeklyOutputSafePath to reject output path inside data/'
}

Write-Output 'PASS: weekly benefit drift check tests'

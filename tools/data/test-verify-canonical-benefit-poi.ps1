$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot 'verify-canonical-benefit-poi.ps1'
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

$propertiesPath = Join-Path $PSScriptRoot 'testdata\poi-audit.local.properties'
$properties = Read-LocalProperties -Path $propertiesPath
$auditConfiguration = Get-AuditConfiguration -Properties $properties
Assert-Equal -Actual $auditConfiguration.NAVER_API_HUB_CLIENT_ID -Expected 'test-api-hub-id' -Message '감사기는 local.properties의 API HUB Client ID를 읽어야 합니다'
Assert-Equal -Actual $auditConfiguration.NAVER_API_HUB_CLIENT_SECRET -Expected 'test-api-hub-secret' -Message '감사기는 local.properties의 API HUB Client Secret을 읽어야 합니다'
$auditEndpoints = Get-AuditEndpoints
Assert-Equal -Actual $auditEndpoints.localSearch -Expected 'https://naverapihub.apigw.ntruss.com/search/v1/local' -Message '감사 요약은 실제 API HUB 지역 검색 endpoint를 기록해야 합니다'

$searchQueries = @(Get-PoiSearchQueries -Name '테스트 카페' -Address '서울특별시 마포구 월드컵북로 1, 2층 201호')
Assert-Equal -Actual $searchQueries.Count -Expected 2 -Message '층·호수가 쉼표 뒤에 있으면 전체 주소와 도로명·건물번호 보조 검색을 모두 준비해야 합니다'
Assert-Equal -Actual $searchQueries[0].Strategy -Expected '전체 주소 검색' -Message '첫 검색은 원본 전체 주소여야 합니다'
Assert-Equal -Actual $searchQueries[0].Query -Expected '테스트 카페 서울특별시 마포구 월드컵북로 1, 2층 201호' -Message '첫 검색어는 업소명과 원본 전체 주소를 보존해야 합니다'
Assert-Equal -Actual $searchQueries[1].Strategy -Expected '도로명·건물번호 보조 검색' -Message '두 번째 검색은 보조 검색으로 표시해야 합니다'
Assert-Equal -Actual $searchQueries[1].Query -Expected '테스트 카페 서울특별시 마포구 월드컵북로 1' -Message '보조 검색어는 쉼표 앞 도로명·건물번호만 사용해야 합니다'

$localItems = Invoke-NaverLocalSearch -Query '테스트 카페 서울특별시 마포구 월드컵북로 1' -ClientId 'test-search-id' -ClientSecret 'test-search-secret' -RequestInvoker {
    param($Uri, $Headers)
    if ($Uri -notmatch '^https://naverapihub\.apigw\.ntruss\.com/search/v1/local\?') { throw 'NAVER API HUB 지역 검색 endpoint를 사용해야 합니다' }
    if ($Headers['X-NCP-APIGW-API-KEY-ID'] -ne 'test-search-id') { throw 'NAVER API HUB Client ID 헤더가 누락되었습니다' }
    if ($Headers['X-NCP-APIGW-API-KEY'] -ne 'test-search-secret') { throw 'NAVER API HUB Client Secret 헤더가 누락되었습니다' }
    [pscustomobject]@{ items = @([pscustomobject]@{ title = '테스트 카페'; roadAddress = '서울특별시 마포구 월드컵북로 1'; address = ''; mapx = '1269012345'; mapy = '375012345' }) }
}
Assert-Equal -Actual $localItems.Count -Expected 1 -Message '지역 검색 응답의 items만 후보 목록으로 반환해야 합니다'

$auditRows = Invoke-PoiCoordinateAudit -Rows @(
    [pscustomobject]@{ 업소명 = '테스트 카페'; 소재지도로명주소 = '서울특별시 마포구 월드컵북로 1'; 소재지지번주소 = ''; 위도 = '37.0000'; 경도 = '126.0000' }
) -SearchClientId 'test-search-id' -SearchClientSecret 'test-search-secret' -VerifiedAt '2026-09-06' -LocalSearchInvoker {
    param($Uri, $Headers)
    [pscustomobject]@{ items = @([pscustomobject]@{ title = '테스트 카페'; roadAddress = '서울특별시 마포구 월드컵북로 1'; address = ''; mapx = '1269012345'; mapy = '375012345' }) }
}
Assert-Equal -Actual $auditRows.Count -Expected 1 -Message '감사기는 입력 행마다 보고서 행 하나를 반환해야 합니다'
Assert-Equal -Actual $auditRows[0].정본행번호 -Expected 2 -Message '행 오프셋이 없으면 첫 데이터 행은 원본 CSV의 2행으로 기록해야 합니다'
Assert-Equal -Actual $auditRows[0].판정 -Expected '확인 후보' -Message '완전 일치 API HUB POI는 지오코딩 호출 없이 확인 후보여야 합니다'

$offsetAuditRows = Invoke-PoiCoordinateAudit -Rows @(
    [pscustomobject]@{ 업소명 = '오프셋 카페'; 소재지도로명주소 = '서울특별시 마포구 월드컵북로 3'; 소재지지번주소 = ''; 위도 = ''; 경도 = '' }
) -SearchClientId 'test-search-id' -SearchClientSecret 'test-search-secret' -VerifiedAt '2026-09-06' -RowNumberOffset 10 -LocalSearchInvoker {
    param($Uri, $Headers)
    [pscustomobject]@{ items = @([pscustomobject]@{ title = '오프셋 카페'; roadAddress = '서울특별시 마포구 월드컵북로 3'; address = ''; mapx = '1269012345'; mapy = '375012345' }) }
}
Assert-Equal -Actual $offsetAuditRows[0].정본행번호 -Expected 12 -Message '분할 실행의 보고서 행 번호는 원본 CSV 행 번호를 유지해야 합니다'

$fallbackAuditRows = Invoke-PoiCoordinateAudit -Rows @(
    [pscustomobject]@{ 업소명 = '보조 검색 카페'; 소재지도로명주소 = '서울특별시 마포구 월드컵북로 2, 2층 201호'; 소재지지번주소 = ''; 위도 = ''; 경도 = '' }
) -SearchClientId 'test-search-id' -SearchClientSecret 'test-search-secret' -VerifiedAt '2026-09-06' -LocalSearchInvoker {
    param($Uri, $Headers)
    $decodedUri = [Uri]::UnescapeDataString($Uri)
    if ($decodedUri -like '*월드컵북로 2, 2층 201호*') {
        return [pscustomobject]@{ items = @() }
    }
    if ($decodedUri -like '*월드컵북로 2*') {
        return [pscustomobject]@{ items = @([pscustomobject]@{ title = '보조 검색 카페'; roadAddress = '서울특별시 마포구 월드컵북로 2, 2층 201호'; address = ''; mapx = '1269012345'; mapy = '375012345' }) }
    }
    throw '예상하지 않은 보조 검색어입니다'
}
Assert-Equal -Actual $fallbackAuditRows[0].판정 -Expected '확인 후보' -Message '전체 주소가 0건이면 도로명·건물번호 보조 검색 후보도 전체 주소 대조 후 확인할 수 있어야 합니다'
Assert-Equal -Actual $fallbackAuditRows[0].POI조회방식 -Expected '도로명·건물번호 보조 검색' -Message '보조 검색으로 확인된 행은 보고서에 검색 방식을 남겨야 합니다'
Assert-Equal -Actual $fallbackAuditRows[0].최초POI조회어 -Expected '보조 검색 카페 서울특별시 마포구 월드컵북로 2, 2층 201호' -Message '보고서는 원본 전체 주소 검색어를 보존해야 합니다'

$oneMatch = Get-PoiDecision -CanonicalName '테스트 카페' -CanonicalAddress '서울특별시 마포구 월드컵북로 1' -Candidates @(
    [pscustomobject]@{ title = '<b>테스트</b> 카페'; roadAddress = '서울특별시 마포구 월드컵북로 1'; address = ''; mapx = '1269012345'; mapy = '375012345' }
)
Assert-Equal -Actual $oneMatch.Decision -Expected '확인 후보' -Message '단일 상호·주소 일치 후보는 확인 후보여야 합니다'
Assert-Equal -Actual $oneMatch.NameMatched -Expected $true -Message '확인 후보는 상호가 일치해야 합니다'
Assert-Equal -Actual $oneMatch.AddressMatched -Expected $true -Message '확인 후보는 주소가 일치해야 합니다'

$firstButWrong = Get-PoiDecision -CanonicalName '테스트 카페' -CanonicalAddress '서울특별시 마포구 월드컵북로 1' -Candidates @(
    [pscustomobject]@{ title = '다른 카페'; roadAddress = '서울특별시 마포구 월드컵북로 1'; address = '' },
    [pscustomobject]@{ title = '테스트 카페'; roadAddress = '서울특별시 마포구 월드컵북로 1'; address = '' }
)
Assert-Equal -Actual $firstButWrong.Decision -Expected '확인 후보' -Message '첫 번째가 아니어도 유일한 완전 일치 후보는 허용해야 합니다'
Assert-Equal -Actual $firstButWrong.SelectedCandidate.title -Expected '테스트 카페' -Message '첫 번째 불일치 결과를 선택하면 안 됩니다'

$twoMatches = Get-PoiDecision -CanonicalName '동명이인 식당' -CanonicalAddress '서울특별시 마포구 월드컵북로 2' -Candidates @(
    [pscustomobject]@{ title = '동명이인 식당'; roadAddress = '서울특별시 마포구 월드컵북로 2'; address = '' },
    [pscustomobject]@{ title = '동명이인 식당'; roadAddress = '서울특별시 마포구 월드컵북로 2'; address = '' }
)
Assert-Equal -Actual $twoMatches.Decision -Expected '재확인 필요' -Message '완전 일치 후보가 둘이면 자동 선택하면 안 됩니다'
Assert-Equal -Actual $twoMatches.SelectedCandidate -Expected $null -Message '복수 후보에서는 선택 후보가 없어야 합니다'

$suiteMismatch = Get-PoiDecision -CanonicalName '테스트 카페' -CanonicalAddress '서울특별시 마포구 월드컵북로 1 2층' -Candidates @(
    [pscustomobject]@{ title = '테스트 카페'; roadAddress = '서울특별시 마포구 월드컵북로 1'; address = ''; mapx = '1269012345'; mapy = '375012345' }
)
Assert-Equal -Actual $suiteMismatch.Decision -Expected '재확인 필요' -Message '층·호수 누락 주소를 자동 일치로 처리하면 안 됩니다'
Assert-Equal -Actual $suiteMismatch.SelectedCandidate -Expected $null -Message '주소 불일치 단일 후보를 선택 후보로 쓰면 안 됩니다'
Assert-Equal -Actual $suiteMismatch.ReferenceCandidate.title -Expected '테스트 카페' -Message '단일 상호 일치 후보는 사람이 재확인할 참고 정보로만 보존해야 합니다'

$suiteMismatchReport = New-AuditReportRow -RowNumber 6 -CanonicalName '테스트 카페' -InputAddress '서울특별시 마포구 월드컵북로 1 2층' -ExistingLatitude '37.0000' -ExistingLongitude '126.0000' -Query '테스트 카페 서울특별시 마포구 월드컵북로 1 2층' -PoiDecision $suiteMismatch -VerifiedAt '2026-09-06'
Assert-Equal -Actual $suiteMismatchReport.POI도로명주소 -Expected '서울특별시 마포구 월드컵북로 1' -Message '주소 불일치 단일 후보의 주소는 재확인용 참고 정보로 보고해야 합니다'
Assert-Equal -Actual $suiteMismatchReport.제안위도 -Expected '' -Message '재확인용 참고 후보로 좌표를 제안하면 안 됩니다'
Assert-Equal -Actual $suiteMismatchReport.좌표출처URL -Expected '' -Message '재확인용 참고 후보로 좌표 출처 링크를 기록하면 안 됩니다'

$noAddress = Get-PoiDecision -CanonicalName '주소 없는 업소' -CanonicalAddress '' -Candidates @()
Assert-Equal -Actual $noAddress.Decision -Expected '미확인' -Message '주소가 없으면 좌표 확인 후보가 될 수 없습니다'

$confirmedReport = New-AuditReportRow -RowNumber 7 -CanonicalName '테스트 카페' -InputAddress '서울특별시 마포구 월드컵북로 1' -ExistingLatitude '37.0000' -ExistingLongitude '126.0000' -Query '테스트 카페 서울특별시 마포구 월드컵북로 1' -PoiDecision $oneMatch -VerifiedAt '2026-09-06'
Assert-Equal -Actual $confirmedReport.판정 -Expected '확인 후보' -Message '단일 상호·주소 일치 POI의 유효한 API HUB 좌표는 확인 후보여야 합니다'
Assert-Equal -Actual $confirmedReport.제안위도 -Expected '37.5012345' -Message 'API HUB mapy는 1천만으로 나눈 제안 위도여야 합니다'
Assert-Equal -Actual $confirmedReport.제안경도 -Expected '126.9012345' -Message 'API HUB mapx는 1천만으로 나눈 제안 경도여야 합니다'
Assert-Equal -Actual $confirmedReport.좌표출처 -Expected '네이버 지도' -Message 'API HUB POI 좌표의 정본 출처는 네이버 지도로 기록해야 합니다'
Assert-Equal -Actual $confirmedReport.APIHUB좌표후보수 -Expected 1 -Message '보고서는 API HUB에서 읽은 유효 좌표 후보 수를 기록해야 합니다'
Assert-Equal -Actual $confirmedReport.권장좌표검증상태 -Expected '확인 완료' -Message '확인 후보만 확인 완료를 제안해야 합니다'

$invalidCoordinateMatch = Get-PoiDecision -CanonicalName '좌표 오류 카페' -CanonicalAddress '서울특별시 마포구 월드컵북로 4' -Candidates @(
    [pscustomobject]@{ title = '좌표 오류 카페'; roadAddress = '서울특별시 마포구 월드컵북로 4'; address = ''; mapx = 'not-a-number'; mapy = '375012345' }
)
$invalidCoordinateReport = New-AuditReportRow -RowNumber 8 -CanonicalName '좌표 오류 카페' -InputAddress '서울특별시 마포구 월드컵북로 4' -ExistingLatitude '' -ExistingLongitude '' -Query '좌표 오류 카페 서울특별시 마포구 월드컵북로 4' -PoiDecision $invalidCoordinateMatch -VerifiedAt '2026-09-06'
Assert-Equal -Actual $invalidCoordinateReport.판정 -Expected '재확인 필요' -Message 'API HUB mapx가 숫자가 아니면 자동 확인하면 안 됩니다'
Assert-Equal -Actual $invalidCoordinateReport.제안위도 -Expected '' -Message 'API HUB 좌표 변환이 실패하면 위도를 제안하면 안 됩니다'
Assert-Equal -Actual $invalidCoordinateReport.제안경도 -Expected '' -Message 'API HUB 좌표 변환이 실패하면 경도를 제안하면 안 됩니다'

$unconfirmedReport = New-AuditReportRow -RowNumber 8 -CanonicalName '주소 없는 업소' -InputAddress '' -ExistingLatitude '37.0002' -ExistingLongitude '126.0002' -Query '' -PoiDecision $noAddress -VerifiedAt '2026-09-06'
Assert-Equal -Actual $unconfirmedReport.판정 -Expected '미확인' -Message 'POI가 없으면 미확인 보고서여야 합니다'
Assert-Equal -Actual $unconfirmedReport.제안위도 -Expected '' -Message '미확인에는 제안 위도가 있으면 안 됩니다'
Assert-Equal -Actual $unconfirmedReport.제안경도 -Expected '' -Message '미확인에는 제안 경도가 있으면 안 됩니다'
Assert-Equal -Actual $unconfirmedReport.좌표출처 -Expected '' -Message '미확인에는 좌표출처가 있으면 안 됩니다'
Assert-Equal -Actual $unconfirmedReport.권장좌표검증상태 -Expected '미확인' -Message '미확인은 미확인 상태를 제안해야 합니다'

$apiErrorDecision = New-PoiDecision -Decision 'API 오류' -NameMatched $false -AddressMatched $false -SelectedCandidate $null -Reason '지역 검색 요청 실패'
$apiErrorReport = New-AuditReportRow -RowNumber 9 -CanonicalName '오류 업소' -InputAddress '서울특별시 마포구 월드컵북로 3' -ExistingLatitude '37.0003' -ExistingLongitude '126.0003' -Query '오류 업소 서울특별시 마포구 월드컵북로 3' -PoiDecision $apiErrorDecision -VerifiedAt '2026-09-06'
Assert-Equal -Actual $apiErrorReport.판정 -Expected 'API 오류' -Message 'API 요청 실패는 감사 판정에 남겨야 합니다'
Assert-Equal -Actual $apiErrorReport.권장좌표검증상태 -Expected '미확인' -Message 'API 오류는 유효한 좌표검증상태가 아니므로 미확인을 제안해야 합니다'
Assert-Equal -Actual $apiErrorReport.제안위도 -Expected '' -Message 'API 오류에는 제안 위도가 있으면 안 됩니다'

Write-Output 'PASS: POI matching rules'

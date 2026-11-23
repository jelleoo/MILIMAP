Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/poi-discovery/multi-api-poi-verification.ps1')

function Assert-EntrcEqual {
    param($Actual, $Expected, [string]$Message)

    if ($Actual -cne $Expected) {
        throw "Assertion failed: $Message (expected='$Expected', actual='$Actual')"
    }
}

function Assert-EntrcTrue {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) {
        throw "Assertion failed: $Message"
    }
}

# 1. GRS80 UTM-K (EPSG:5179) -> WGS84 projection verification (origin identity + Cheongun-dong sample)
$origin = ConvertFrom-Utmk5179ToWgs84 -X 1000000.0 -Y 2000000.0
Assert-EntrcEqual $origin.Latitude 38.0 'EPSG:5179 false easting/northing origin must invert to 38.0N'
Assert-EntrcEqual $origin.Longitude 127.5 'EPSG:5179 false easting/northing origin must invert to 127.5E'

$proj = ConvertFrom-Utmk5179ToWgs84 -X 953241.683263 -Y 1954023.466812
Assert-EntrcTrue ([Math]::Abs($proj.Latitude - 37.5844154) -lt 0.00001) "Expected Seoul Cheongun-dong lat ~37.5844154, got $($proj.Latitude)"
Assert-EntrcTrue ([Math]::Abs($proj.Longitude - 126.9704055) -lt 0.00001) "Expected Seoul Cheongun-dong lon ~126.9704055, got $($proj.Longitude)"

# 2. Import-AddressEntranceDbIndex & Resolve-AddressEntranceCoordinate on CP949 18-column fixture
$tempDir = Join-Path ([IO.Path]::GetTempPath()) ('milimap-entrc-test-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($tempDir)
try {
    $fixturePath = Join-Path $tempDir 'entrc_sample.txt'
    $rows = @(
        '11110|760|1111010100|서울특별시|종로구|청운동|111103100012|자하문로|0|94|0||03047|근린생활시설|0|청운효자동|953241.683263|1954023.466812',
        '41111|101|4111113000|경기도|수원시 장안구|송죽동|411113177015|송정로|0|83|0||16299|상가|0|송죽동|956000.0|1922000.0',
        '41111|102|4111113000|경기도|수원시 장안구|송죽동|411113177015|송정로|0|83|0||16299|상가|0|송죽동|956010.0|1922020.0'
    )
    $cp949 = [Text.Encoding]::GetEncoding(949)
    [IO.File]::WriteAllLines($fixturePath, $rows, $cp949)

    $jKey1 = Get-AddressEntranceJusoKey -RnMgtSn '111103100012' -UndergroundYn '0' -BuildingMain '94' -BuildingSub '0'
    $rKey2 = Get-AddressEntranceRoadKey -Sigungu '수원시' -RoadName '송정로' -UndergroundYn '0' -BuildingMain '83' -BuildingSub ''

    $index = Import-AddressEntranceDbIndex -Paths @($fixturePath) -NeededJusoKeys @($jKey1) -NeededRoadKeys @($rKey2) -EncodingName 'CP949'

    $exact = Resolve-AddressEntranceCoordinate -Index $index -RnMgtSn '111103100012' -UndergroundYn '0' -BuildingMain '94' -BuildingSub '0'
    Assert-EntrcTrue $exact.Found 'Exact JUSO key must resolve entrance coordinate'
    Assert-EntrcEqual $exact.MatchType 'ENTRC_JUSO_EXACT' 'MatchType must be ENTRC_JUSO_EXACT'
    Assert-EntrcEqual $exact.EntranceCount 1 'Single entrance expected'
    Assert-EntrcEqual $exact.EntrcDistrict '종로구' 'District preserved from entrance DB'
    Assert-EntrcEqual $exact.CoordinateSource '행정안전부 위치정보요약DB(2026-10)' 'CoordinateSource preserved'
    Assert-EntrcEqual $exact.CoordinateSourceUrl 'https://business.juso.go.kr' 'CoordinateSourceUrl preserved'

    $centroid = Resolve-AddressEntranceCoordinate -Index $index -SigunguCandidates @('수원시') -RoadName '송정로' -BuildingMain '83'
    $expectedAvg = ConvertFrom-Utmk5179ToWgs84 -X 956005.0 -Y 1922010.0
    Assert-EntrcTrue $centroid.Found 'Compound sigungu fallback must resolve multi-entrance building'
    Assert-EntrcEqual $centroid.MatchType 'ENTRC_ROAD_EXACT' 'MatchType must fall back to ENTRC_ROAD_EXACT'
    Assert-EntrcEqual $centroid.EntranceCount 2 'Multi-entrance building must average 2 entrances'
    Assert-EntrcEqual $centroid.Latitude $expectedAvg.Latitude 'Multi-entrance averaged latitude must match centroid projection'
    Assert-EntrcEqual $centroid.Longitude $expectedAvg.Longitude 'Multi-entrance averaged longitude must match centroid projection'

    $miss = Resolve-AddressEntranceCoordinate -Index $index -RnMgtSn '999999999999' -BuildingMain '1'
    Assert-EntrcTrue (-not $miss.Found) 'Unknown key must not resolve'
    Assert-EntrcEqual $miss.MatchType 'UNMATCHED' 'Unknown key must report UNMATCHED'

    # 3. Provider request caching & telemetry verification
    Reset-MultiApiProviderTelemetry
    Set-MultiApiRequestCache -Enabled $true

    $bPaju = ConvertTo-NormalizedBusiness -Row ([pscustomobject]@{
        업소명 = '임진강나루'
        시도 = '경기도'
        시군구 = '파주시'
        소재지도로명주소 = '파주시 문산읍 반구정로 53-51'
        소재지지번주소 = ''
    }) -SourceRowNumber 221

    $invocations = 0
    $mockJuso = {
        param($uri)
        $script:TestJusoMockCalls++
        [pscustomobject]@{
            results = [pscustomobject]@{
                common = [pscustomobject]@{ errorCode = '0' }
                juso = @([pscustomobject]@{
                    roadAddr = '경기도 파주시 문산읍 반구정로 53-51'
                    admCd = '41480'
                    rnMgtSn = '414803'
                    buldMnnm = '53'
                    buldSlno = '51'
                })
            }
        }
    }
    $script:TestJusoMockCalls = 0
    $first = Invoke-JusoRoadAddressLookup -Business $bPaju -ApiKey 'dummy-juso' -RequestInvoker $mockJuso
    $second = Invoke-JusoRoadAddressLookup -Business $bPaju -ApiKey 'dummy-juso' -RequestInvoker $mockJuso

    Assert-EntrcEqual $first.Status 'JUSO_EXACT' 'First JUSO call succeeds'
    Assert-EntrcEqual $second.Status 'JUSO_EXACT' 'Cached second JUSO call succeeds'
    Assert-EntrcEqual $script:TestJusoMockCalls 1 'Duplicate JUSO query must invoke mock requester only once when cache enabled'

    $stats = Get-MultiApiProviderTelemetrySummary
    Assert-EntrcEqual $stats.JUSO.Calls 1 'JUSO Calls telemetry must be 1'
    Assert-EntrcEqual $stats.JUSO.CacheHits 1 'JUSO CacheHits telemetry must be 1'
    Assert-EntrcEqual $stats.JUSO.Failures 0 'JUSO Failures telemetry must be 0'

    # Ensure error responses increment Failures and are not cached
    $errBiz = ConvertTo-NormalizedBusiness -Row ([pscustomobject]@{
        업소명 = '오류테스트점'
        시도 = '경기도'
        시군구 = '파주시'
        소재지도로명주소 = '파주시 중앙로 1'
        소재지지번주소 = ''
    }) -SourceRowNumber 222
    $script:ErrCalls = 0
    $errInvoker = {
        param($uri)
        $script:ErrCalls++
        [pscustomobject]@{ results = [pscustomobject]@{ common = [pscustomobject]@{ errorCode = '-999' }; juso = @() } }
    }
    $errRes1 = Invoke-JusoRoadAddressLookup -Business $errBiz -ApiKey 'dummy-juso' -RequestInvoker $errInvoker
    $errRes2 = Invoke-JusoRoadAddressLookup -Business $errBiz -ApiKey 'dummy-juso' -RequestInvoker $errInvoker
    Assert-EntrcEqual $errRes1.Status 'JUSO_ERR' 'Error response status preserved'
    Assert-EntrcEqual $errRes2.Status 'JUSO_ERR' 'Error response is not poisoned in cache'
    Assert-EntrcEqual $script:ErrCalls 2 'Error response retries without cache hit'
    $statsAfterErr = Get-MultiApiProviderTelemetrySummary
    Assert-EntrcEqual $statsAfterErr.JUSO.Calls 3 'Total JUSO Calls includes uncached retries'
    Assert-EntrcEqual $statsAfterErr.JUSO.Failures 2 'JUSO Failures increments on API errors'
} finally {
    Set-MultiApiRequestCache -Enabled $false
    Reset-MultiApiProviderTelemetry
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'PASS: address entrance DB and multi-API cache/telemetry tests'

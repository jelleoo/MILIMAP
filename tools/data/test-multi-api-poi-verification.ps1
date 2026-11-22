Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/poi-discovery/multi-api-poi-verification.ps1')

function Assert-Equal { param($Actual, $Expected, [string]$Message) if ($Actual -cne $Expected) { throw "$Message (expected: $Expected, actual: $Actual)" } }
function Assert-True { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }
function Assert-Throws { param([scriptblock]$Action, [string]$Message) $threw = $false; try { & $Action } catch { $threw = $true }; Assert-True $threw $Message }

# 1. Name matching tests (negative false-positive guards, positive aliases, branch conflicts)
$negatives = @(
    @{ Orig='숙성사돈 파주광탄점'; Cand='기로네숯불구이'; Prov='경기도'; City='파주시' },
    @{ Orig='장단콩두부전문점'; Cand='강종근트레이닝센터'; Prov='경기도'; City='파주시' },
    @{ Orig='다원'; Cand='순이네밥상'; Prov='경기도'; City='동두천시' },
    @{ Orig='강남카페'; Cand='역삼카페'; Prov='서울특별시'; City='강남구' },
    @{ Orig='테스트미용실'; Cand='아무개미용실'; Prov='경기도'; City='파주시' }
)
foreach ($tc in $negatives) {
    $b = ConvertTo-NormalizedBusiness -Row ([pscustomobject]@{업소명=$tc.Orig;시도=$tc.Prov;시군구=$tc.City;소재지도로명주소="$($tc.City) 테스트로 1";소재지지번주소=''}) -SourceRowNumber 2
    Assert-Equal (Test-MultiApiCandidateNameMatch $b $tc.Cand) 'NONE' "Unrelated name rejected: $($tc.Orig) vs $($tc.Cand)"
}

$positives = @(
    @{ Orig='두둑한한판'; Cand='두둑한한판 마장호수본점'; Exp='COMPATIBLE' },
    @{ Orig='(주)함지박'; Cand='함지박'; Exp='COMPATIBLE' },
    @{ Orig='소담촌'; Cand='소담촌 파주금촌점'; Exp='COMPATIBLE' },
    @{ Orig='씨케이미용실(CK 헤어)'; Cand='CK헤어'; Exp='COMPATIBLE' },
    @{ Orig='로얄치킨/곱창매니아'; Cand='곱창매니아'; Exp='COMPATIBLE' },
    @{ Orig='두둑한한판'; Cand='두둑한한판'; Exp='EXACT' }
)
foreach ($tc in $positives) {
    $b = ConvertTo-NormalizedBusiness -Row ([pscustomobject]@{업소명=$tc.Orig;시도='경기도';시군구='파주시';소재지도로명주소='파주시 보광로 646';소재지지번주소=''}) -SourceRowNumber 2
    Assert-Equal (Test-MultiApiCandidateNameMatch $b $tc.Cand) $tc.Exp "Compatible/Exact name matched: $($tc.Orig) vs $($tc.Cand)"
}

$bBranch = ConvertTo-NormalizedBusiness -Row ([pscustomobject]@{업소명='또봉이통닭(문산점)';시도='경기도';시군구='파주시';소재지도로명주소='파주시 문산읍 문향로 1';소재지지번주소=''}) -SourceRowNumber 2
Assert-Equal (Test-MultiApiCandidateNameMatch $bBranch '또봉이통닭 금촌점') 'BRANCH_CONFLICT' 'Different branch conflicts fail-closed'

# 2. Glued-prefix deterministic road+building match tests
$gluedRow = [pscustomobject]@{업소명='만나떡볶이';시도='경기도';시군구='과천시';소재지도로명주소='경기도 과천시별양상가2로35118호1층 (별양동)';소재지지번주소=''}
$bGlued = ConvertTo-NormalizedBusiness -Row $gluedRow -SourceRowNumber 67
Assert-Equal $bGlued.BuildingMain '' 'Raw glued token remains unsplit in Base A contract'
Assert-True (Test-MultiApiRoadBuildingMatch $bGlued '경기도 과천시 별양상가2로 35') 'Glued 35118호 deterministically matches building 35'
Assert-True (-not (Test-MultiApiRoadBuildingMatch $bGlued '경기도 과천시 별양상가2로 36')) 'Glued 35118호 rejects building 36'
Assert-True (-not (Test-MultiApiRoadBuildingMatch $bGlued '경기도 과천시 별양상가2로 35118')) 'Glued 35118호 rejects invalid bare-unit 35118'
Assert-True (-not (Test-MultiApiRoadBuildingMatch $bGlued '서울특별시 강남구 별양상가2로 35')) 'Glued check still enforces province match'

# 3. Mocked JUSO adapter tests
$bPaju = ConvertTo-NormalizedBusiness -Row ([pscustomobject]@{업소명='임진강나루';시도='경기도';시군구='파주시';소재지도로명주소='파주시 문산읍 반구정로 53-51';소재지지번주소=''}) -SourceRowNumber 221
Assert-Equal (Format-MultiApiJusoQuery $bPaju) '경기도 파주시 문산읍 반구정로 53-51' 'Juso query formats clean structured address without splitting 반구정로'
$jusoExact = Invoke-JusoRoadAddressLookup -Business $bPaju -ApiKey 'dummy-juso' -RequestInvoker {
    param($uri)
    [pscustomobject]@{ results = [pscustomobject]@{ common = [pscustomobject]@{ errorCode='0' }; juso = @([pscustomobject]@{ roadAddr='경기도 파주시 문산읍 반구정로 53-51'; admCd='41480'; rnMgtSn='414803'; buldMnnm='53'; buldSlno='51' }) } }
}
Assert-Equal $jusoExact.Status 'JUSO_EXACT' 'Juso EXACT match status'
Assert-Equal $jusoExact.BuldMnnm '53' 'Juso preserves building main'

$jusoOther = Invoke-JusoRoadAddressLookup -Business $bPaju -ApiKey 'dummy-juso' -RequestInvoker {
    param($uri)
    [pscustomobject]@{ results = [pscustomobject]@{ common = [pscustomobject]@{ errorCode='0' }; juso = @([pscustomobject]@{ roadAddr='경기도 파주시 문산읍 반구정로 99'; admCd='41480'; rnMgtSn='414803'; buldMnnm='99'; buldSlno='0' }) } }
}
Assert-Equal $jusoOther.Status 'JUSO_FOUND_OTHER' 'Juso building mismatch yields JUSO_FOUND_OTHER'

$jusoErr = Invoke-JusoRoadAddressLookup -Business $bPaju -ApiKey 'dummy-juso' -RequestInvoker {
    param($uri)
    [pscustomobject]@{ results = [pscustomobject]@{ common = [pscustomobject]@{ errorCode='-999' }; juso = @() } }
}
Assert-Equal $jusoErr.Status 'JUSO_ERR' 'Juso API error status handled cleanly'

# 4. Mocked SDSC2 adapter tests (NODATA + STRONG with public lat/lon)
$sdscNoData = Invoke-Sdsc2RadiusPoiDiscovery -Business $bPaju -Latitude 37.86 -Longitude 126.78 -ServiceKey 'dummy-key' -RequestInvoker {
    param($uri)
    [pscustomobject]@{ header=[pscustomobject]@{ resultCode='03' }; body=[pscustomobject]@{ items=@(); totalCount=0 } }
}
Assert-Equal $sdscNoData.Status 'SDSC2_NONE' 'SDSC2 code 03 maps cleanly to SDSC2_NONE'

$sdscStrong = Invoke-Sdsc2RadiusPoiDiscovery -Business $bPaju -Latitude 37.86 -Longitude 126.78 -ServiceKey 'dummy-key' -RequestInvoker {
    param($uri)
    [pscustomobject]@{
        header=[pscustomobject]@{ resultCode='00' }
        body=[pscustomobject]@{
            totalCount=1
            items=@([pscustomobject]@{ bizesId='BZ1'; bizesNm='임진강나루'; brchNm=''; rdnmAdr='경기도 파주시 문산읍 반구정로 53-51'; lat='37.8601'; lon='126.7801' })
        }
    }
}
Assert-Equal $sdscStrong.Status 'SDSC2_STRONG' 'SDSC2 strong match'
Assert-True ($sdscStrong.Latitude -gt 37.0 -and $sdscStrong.Longitude -gt 126.0) 'SDSC2 public WGS84 coords preserved'

# 5. Mocked Kakao verification-only adapter tests (NO coordinate properties permitted)
$kakaoPhone = Invoke-KakaoLocalPoiVerification -Business $bPaju -RawPhone '031-952-0001' -Latitude 37.86 -Longitude 126.78 -RestApiKey 'dummy-kakao' -RequestInvoker {
    param($uri, $headers)
    [pscustomobject]@{
        documents=@([pscustomobject]@{
            id='K1'; place_name='임진강나루'; road_address_name='경기 파주시 문산읍 반구정로 53-51'
            phone='031-952-0001'; distance='2'; place_url='https://place.map.kakao.com/1'; x='126.78'; y='37.86'
        })
    }
}
Assert-Equal $kakaoPhone.Status 'KAKAO_STRONG_PHONE' 'Kakao exact phone + building match'
$propNames = @($kakaoPhone.PSObject.Properties.Name)
Assert-True (@($propNames | Where-Object { $_ -match '(?:Lat|Lon|Coord|^X$|^Y$)' }).Count -eq 0) 'Kakao verification output NEVER stores x/y/lat/lon'

$kakaoMoved = Invoke-KakaoLocalPoiVerification -Business $bPaju -RawPhone '031-952-0001' -Latitude 37.86 -Longitude 126.78 -RestApiKey 'dummy-kakao' -RequestInvoker {
    param($uri, $headers)
    [pscustomobject]@{
        documents=@([pscustomobject]@{
            id='K2'; place_name='임진강나루'; road_address_name='경기 파주시 문산읍 다른길 9'
            phone='031-952-0001'; distance='245'; place_url='https://place.map.kakao.com/2'; x='126.78'; y='37.86'
        })
    }
}
Assert-Equal $kakaoMoved.Status 'KAKAO_PHONE_MOVED' 'Kakao detects moved phone > 120m away'

# 6. Mocked Naver enhanced recovery test (P1 YELLOW multi-candidate or compatible name recovered cleanly)
$bAlias = ConvertTo-NormalizedBusiness -Row ([pscustomobject]@{업소명='(주)함지박';시도='경기도';시군구='파주시';소재지도로명주소='파주시 법원읍 사임당로 800-8';소재지지번주소=''}) -SourceRowNumber 256
$naverMock = Invoke-NaverEnhancedPoiEvaluation -Business $bAlias -ClientId 'id' -ClientSecret 'sec' -RequestInvoker {
    param($uri, $headers)
    [pscustomobject]@{
        items=@([pscustomobject]@{
            title='함지박'; roadAddress='경기도 파주시 법원읍 사임당로 800-8 함지박화로구이'; address='경기도 파주시 법원읍 대능리 1'
            telephone=''; category='한식'; link='https://example.invalid/h'; mapx='1269000000'; mapy='378500000'
        })
    }
}
Assert-Equal $naverMock.P1Class 'YELLOW' 'Frozen Phase 1 remains untouched YELLOW for (주)함지박 vs 함지박'
Assert-Equal $naverMock.EnhStatus 'NAVER_ENH_STRONG' 'Enhanced layer recovers single road+building+alias match'

# 7. Merge & External directory safety checks
$merged = Merge-MultiApiPoiVerificationRow -RowNumber 221 -Business $bPaju -JusoResult $jusoExact -Sdsc2Result $sdscStrong -KakaoResult $kakaoPhone -NaverResult $naverMock
Assert-Equal $merged.ProductionAction 'NONE' 'Merge keeps ProductionAction=NONE'
Assert-True $merged.PublicLegalPin 'PublicLegalPin is true when SDSC2 or JUSO+POI matches'
Assert-Equal $merged.StrongApiCount 3 'All 3 POI APIs agreed'
Assert-Equal $merged.RecommendedCoordinateSource 'SDSC2_PUBLIC_OPEN_DATA' 'SDSC2 public coordinate prioritized'

Assert-Throws { Assert-MultiApiExternalOutputDirectory -Path $PSScriptRoot -RepositoryRoots @($PSScriptRoot) } 'In-repo output path rejected'
$extOk = Assert-MultiApiExternalOutputDirectory -Path 'C:\milimap-test-external' -RepositoryRoots @($PSScriptRoot)
Assert-True (-not [string]::IsNullOrWhiteSpace($extOk)) 'External output directory allowed'

Write-Host 'Multi-API POI verification tests passed.'

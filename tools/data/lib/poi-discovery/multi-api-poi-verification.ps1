Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$poiDataLibRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $poiDataLibRoot 'poi-verification-contracts.ps1')
. (Join-Path $poiDataLibRoot 'identity/normalize-business.ps1')
. (Join-Path $poiDataLibRoot 'poi-discovery/discover-poi-candidates.ps1')
. (Join-Path $poiDataLibRoot 'poi-discovery/address-entrance-db.ps1')
. (Join-Path $poiDataLibRoot 'poi-matching/evaluate-poi-match.ps1')

$script:MultiApiCacheEnabled = $false
$script:MultiApiResponseCache = @{}

function New-MultiApiEmptyTelemetryState {
    return @{
        JUSO  = @{ Calls = 0; CacheHits = 0; Failures = 0; TotalElapsedMs = 0L }
        SDSC2 = @{ Calls = 0; CacheHits = 0; Failures = 0; TotalElapsedMs = 0L }
        KAKAO = @{ Calls = 0; CacheHits = 0; Failures = 0; TotalElapsedMs = 0L }
        NAVER = @{ Calls = 0; CacheHits = 0; Failures = 0; TotalElapsedMs = 0L }
    }
}

$script:MultiApiProviderTelemetry = New-MultiApiEmptyTelemetryState

function Set-MultiApiRequestCache {
    param([Parameter(Mandatory)][bool]$Enabled)

    $script:MultiApiCacheEnabled = $Enabled
    if (-not $Enabled) {
        $script:MultiApiResponseCache.Clear()
    }
}

function Reset-MultiApiProviderTelemetry {
    $script:MultiApiProviderTelemetry = New-MultiApiEmptyTelemetryState
    $script:MultiApiResponseCache.Clear()
}

function Get-MultiApiProviderTelemetrySummary {
    $summary = [ordered]@{}
    foreach ($provider in @('JUSO', 'SDSC2', 'KAKAO', 'NAVER')) {
        $entry = $script:MultiApiProviderTelemetry[$provider]
        $summary[$provider] = [pscustomobject][ordered]@{
            Calls = [int]$entry.Calls
            CacheHits = [int]$entry.CacheHits
            Failures = [int]$entry.Failures
            TotalElapsedMs = [long]$entry.TotalElapsedMs
        }
    }
    return [pscustomobject]$summary
}

function Get-MultiApiCacheHashKey {
    param(
        [Parameter(Mandatory)][string]$Provider,
        [Parameter(Mandatory)][string]$RawIdentifier
    )

    $bytes = [Text.Encoding]::UTF8.GetBytes("$Provider|$RawIdentifier")
    $hex = [BitConverter]::ToString([Security.Cryptography.SHA256]::HashData($bytes)).Replace('-', '').ToLowerInvariant()
    return "$Provider`:$hex"
}

function Invoke-MultiApiCachedProviderRequest {
    param(
        [Parameter(Mandatory)][ValidateSet('JUSO', 'SDSC2', 'KAKAO', 'NAVER')][string]$Provider,
        [Parameter(Mandatory)][string]$CacheKey,
        [Parameter(Mandatory)][scriptblock]$Fetcher,
        [scriptblock]$ShouldCache = { param($Response) $true },
        [scriptblock]$IsErrorResponse = { param($Response) $false }
    )

    $stats = $script:MultiApiProviderTelemetry[$Provider]
    if ($script:MultiApiCacheEnabled -and $script:MultiApiResponseCache.ContainsKey($CacheKey)) {
        $stats.CacheHits++
        return $script:MultiApiResponseCache[$CacheKey]
    }

    $stats.Calls++
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $response = & $Fetcher
        $sw.Stop()
        $stats.TotalElapsedMs += [long]$sw.ElapsedMilliseconds
        if (& $IsErrorResponse $response) {
            $stats.Failures++
        } elseif ($script:MultiApiCacheEnabled -and (& $ShouldCache $response)) {
            $script:MultiApiResponseCache[$CacheKey] = $response
        }
        return $response
    } catch {
        $sw.Stop()
        $stats.TotalElapsedMs += [long]$sw.ElapsedMilliseconds
        $stats.Failures++
        throw
    }
}

$script:MultiApiGenericTerms = [Collections.Generic.HashSet[string]]::new(
    [string[]]@(
        '미용실','음식점','식당','카페','커피','커피숍','헤어','호텔','모텔','펜션',
        '편의점','정육점','전문점','부동산','공인중개사','노래방','노래연습장','분식',
        '치킨','족발','보쌈','갈비','국밥','해장국','칼국수','돈까스','베이커리',
        '마트','약국','의원','치과','한의원','세탁소','사진관','안경원'
    ),
    [StringComparer]::Ordinal
)

function Normalize-MultiApiCompareName {
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) { return '' }
    $clean = ([string]$Value) -replace '<[^>]+>', ''
    return ($clean.Normalize([Text.NormalizationForm]::FormKC).Trim().ToLowerInvariant() -replace '[\s,().·&\-]', '')
}

function Get-MultiApiCoreName {
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) { return '' }
    $raw = (([string]$Value) -replace '<[^>]+>', '').Normalize([Text.NormalizationForm]::FormKC).Trim()
    $raw = ($raw -replace '(?:\(\s*주\s*\)|㈜|주식회사)', ' ').Trim()
    $norm = ($raw.ToLowerInvariant() -replace '[\s,().·&\-]', '')
    if ($norm.Length -le 2) { return $norm }
    $stripped = $norm -replace '(음식점|미용실|식당|카페|커피|헤어|호텔|모텔|펜션|본점|직영점)$', ''
    if ($stripped.Length -ge 2) { return $stripped }
    return $norm
}

function Get-MultiApiCanonicalNameAliases {
    param([Parameter(Mandatory)]$Business)
    $list = [Collections.Generic.List[string]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)

    $addAlias = {
        param([string]$Text)
        $core = Get-MultiApiCoreName $Text
        if ($core.Length -ge 2 -and -not $script:MultiApiGenericTerms.Contains($core) -and $seen.Add($core)) {
            $list.Add($core)
        }
    }

    & $addAlias ([string]$Business.OriginalName)
    & $addAlias ([string]$Business.BaseName)

    $orig = ([string]$Business.OriginalName).Trim()
    $parenMatch = [regex]::Match($orig, '^(?<outer>.+?)\((?<inner>[^()]+)\)(?<tail>.*)$')
    if ($parenMatch.Success) {
        $outer = ($parenMatch.Groups['outer'].Value + ' ' + $parenMatch.Groups['tail'].Value).Trim()
        $inner = $parenMatch.Groups['inner'].Value.Trim()
        if ($inner -notmatch '점$' -and $inner -notmatch '^(?:주|유)$') {
            & $addAlias $outer
            & $addAlias $inner
        }
    }
    if ($orig.Contains('/')) {
        foreach ($part in ($orig -split '/')) {
            $p = $part.Trim()
            if ($p.Length -ge 2) { & $addAlias $p }
        }
    }
    return $list.ToArray()
}

function Normalize-MultiApiPhone {
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) { return '' }
    $digits = ([string]$Value) -replace '[^0-9]', ''
    if ($digits.Length -lt 8) { return '' }
    return $digits
}

function Test-MultiApiPhoneExact {
    param([string]$Left, [string]$Right)
    if (-not $Left -or -not $Right) { return $false }
    return $Left -ceq $Right
}

function Get-MultiApiHaversineMeters {
    param([double]$Lat1, [double]$Lon1, [double]$Lat2, [double]$Lon2)
    $r = 6371000.0
    $toRad = [Math]::PI / 180.0
    $dLat = ($Lat2 - $Lat1) * $toRad
    $dLon = ($Lon2 - $Lon1) * $toRad
    $a = [Math]::Sin($dLat / 2.0) * [Math]::Sin($dLat / 2.0) +
         [Math]::Cos($Lat1 * $toRad) * [Math]::Cos($Lat2 * $toRad) *
         [Math]::Sin($dLon / 2.0) * [Math]::Sin($dLon / 2.0)
    $c = 2.0 * [Math]::Atan2([Math]::Sqrt($a), [Math]::Sqrt(1.0 - $a))
    return [Math]::Round($r * $c, 1)
}

function Test-MultiApiCandidateNameMatch {
    param([Parameter(Mandatory)]$Business, [AllowNull()][string]$CandidateName)
    $candNorm = Normalize-MultiApiCompareName $CandidateName
    $canonNorm = Normalize-MultiApiCompareName $Business.OriginalName
    $candCore = Get-MultiApiCoreName $CandidateName
    if (-not $candNorm -or -not $canonNorm) { return 'NONE' }

    $canonBranch = ConvertTo-PoiMatchCompactText $Business.BranchName
    if ($canonBranch) {
        $candBranch = Get-PoiMatchBranchSuffix $CandidateName $Business.BaseName
        if ($null -ne $candBranch -and $candBranch -and $candBranch -cne $canonBranch) {
            return 'BRANCH_CONFLICT'
        }
    }

    if ($canonNorm -ceq $candNorm) { return 'EXACT' }
    if (-not $candCore -or $candCore.Length -lt 2) { return 'NONE' }

    $canonAliases = @(Get-MultiApiCanonicalNameAliases $Business)
    if ($canonAliases.Count -eq 0) {
        $fallbackCore = Get-MultiApiCoreName $Business.OriginalName
        if ($fallbackCore.Length -ge 2 -and $fallbackCore -ceq $candCore) { return 'COMPATIBLE' }
        return 'NONE'
    }

    foreach ($c in $canonAliases) {
        if ($candCore -ceq $c) { return 'COMPATIBLE' }
    }

    $candPrefixEligible = ($candCore.Length -ge 3) -and (-not $script:MultiApiGenericTerms.Contains($candCore))
    foreach ($c in $canonAliases) {
        if ($c.Length -ge 3 -and $candCore.StartsWith($c, [StringComparison]::Ordinal)) {
            return 'COMPATIBLE'
        }
        if ($candPrefixEligible -and $c.Length -ge 3 -and $c.StartsWith($candCore, [StringComparison]::Ordinal)) {
            return 'COMPATIBLE'
        }
    }
    return 'NONE'
}

function Test-MultiApiRoadBuildingMatch {
    param([Parameter(Mandatory)]$Business, [AllowNull()][string]$CandidateRoadAddress)
    $addr = ConvertTo-PoiText $CandidateRoadAddress
    if (-not $addr) { return $false }

    $canonProv = Get-PoiMatchProvince $Business.Province
    $candProv = Get-PoiMatchProvince $addr
    if ($canonProv -and $candProv -and $canonProv -cne $candProv) { return $false }

    $roadName = [string]$Business.RoadName
    if ([string]::IsNullOrWhiteSpace($roadName)) { return $false }
    if (-not [bool](Test-PoiMatchRoadToken $addr $roadName)) { return $false }

    $candBldg = Get-PoiMatchRoadBuilding $addr $roadName
    if ([string]::IsNullOrWhiteSpace($candBldg)) { return $false }

    $canonMain = ConvertTo-PoiMatchText $Business.BuildingMain
    if ($canonMain) {
        $canonBldg = $canonMain
        if (ConvertTo-PoiMatchText $Business.BuildingSub) { $canonBldg += '-' + (ConvertTo-PoiMatchText $Business.BuildingSub) }
        return $canonBldg -ceq $candBldg
    }

    # Fail-closed glued-prefix verification when raw address has digit-glued floor/unit/dong
    $rawRoad = ConvertTo-PoiText $Business.OriginalRoadAddress
    if (-not $rawRoad) { $rawRoad = ConvertTo-PoiText $Business.PreferredAddress }
    if (-not $rawRoad) { return $false }
    $normalizedRaw = ($rawRoad -replace '(\d+)\s*-\s*(\d+)', '$1-$2')
    $tailMatch = [regex]::Match($normalizedRaw, '(?:(?<![가-힣a-z0-9])|(?:특별시|광역시|특별자치시|시|구|군|읍|면))' + [regex]::Escape($roadName) + '\s*(?<tail>.+)$')
    if (-not $tailMatch.Success) { return $false }
    $tail = $tailMatch.Groups['tail'].Value.Trim()
    return [bool]($tail -match ('^' + [regex]::Escape($candBldg) + '(?:\d+(?:호|층)|(?:[A-Za-z]+|상가\d*)?\d*동\d*호|지하\d+층|B\d*층)'))
}

function Format-MultiApiJusoQuery {
    param([Parameter(Mandatory)]$Business)
    $bldg = [string]$Business.BuildingMain
    if ($bldg -and $Business.BuildingSub) { $bldg += '-' + [string]$Business.BuildingSub }
    $eupMyeon = if ([string]$Business.Dong -match '(?:읍|면)$') { [string]$Business.Dong } else { '' }
    if ($Business.RoadName -and $bldg) {
        $parts = @($Business.Province, $Business.City, $Business.District, $eupMyeon, $Business.RoadName, $bldg) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        return (($parts -join ' ') -replace '\s+', ' ').Trim()
    }

    $raw = [string]$Business.OriginalRoadAddress
    if (-not $raw) { $raw = [string]$Business.PreferredAddress }
    $cleaned = ($raw -replace '\s*,.*$', '').Trim()
    $cleaned = ($cleaned -replace '\(.*$', '').Trim()
    $cleaned = ($cleaned -replace '(\d+)\s*-\s*0\b', '$1').Trim()
    $cleaned = ($cleaned -replace '(\d+)\s*-\s*(\d+)', '$1-$2').Trim()
    if ($Business.RoadName) {
        $escRoad = [regex]::Escape([string]$Business.RoadName)
        $cleaned = ($cleaned -replace ("(?<!\s)($escRoad)"), ' $1')
        $cleaned = ($cleaned -replace ("($escRoad)(?=\S)"), '$1 ')
    }
    foreach ($admin in @($Business.Province, $Business.City, $Business.District, $eupMyeon)) {
        if (-not [string]::IsNullOrWhiteSpace($admin)) {
            $escAdmin = [regex]::Escape($admin)
            $cleaned = ($cleaned -replace ("(?<!\s)($escAdmin)"), ' $1')
            $cleaned = ($cleaned -replace ("($escAdmin)(?=\S)"), '$1 ')
        }
    }
    return ($cleaned -replace '\s+', ' ').Trim()
}

function Invoke-JusoRoadAddressLookup {
    param(
        [Parameter(Mandatory)]$Business,
        [Parameter(Mandatory)][string]$ApiKey,
        [AllowNull()][string]$CandidateRoadAddress = '',
        [scriptblock]$RequestInvoker
    )
    if ([string]::IsNullOrWhiteSpace($ApiKey)) { throw 'JUSO_API_KEY_REQUIRED' }

    $queries = [Collections.Generic.List[string]]::new()
    $seenQ = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $addQ = {
        param([string]$q)
        $t = ($q -replace '\s+', ' ').Trim()
        if ($t -and $seenQ.Add($t)) { $queries.Add($t) }
    }

    if ($CandidateRoadAddress) {
        & $addQ (($CandidateRoadAddress -replace '\s*,.*$', '') -replace '\(.*$', '')
    }
    & $addQ (Format-MultiApiJusoQuery $Business)
    $bldgStr = [string]$Business.BuildingMain
    if ($Business.BuildingSub) { $bldgStr += '-' + $Business.BuildingSub }
    $fallbackKw = (@($Business.Province, $Business.City, $Business.District, $Business.RoadName, $bldgStr) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' '
    & $addQ $fallbackKw

    $best = $null
    $anyFound = $false
    foreach ($kw in $queries) {
        $uri = "https://business.juso.go.kr/addrlink/addrLinkApi.do?confmKey=$([Uri]::EscapeDataString($ApiKey))&currentPage=1&countPerPage=5&keyword=$([Uri]::EscapeDataString($kw))&resultType=json"
        $cacheKey = Get-MultiApiCacheHashKey -Provider 'JUSO' -RawIdentifier $kw
        $res = Invoke-MultiApiCachedProviderRequest -Provider 'JUSO' -CacheKey $cacheKey -Fetcher {
            if ($null -ne $RequestInvoker) { & $RequestInvoker $uri } else { Invoke-RestMethod -Uri $uri -TimeoutSec 15 -MaximumRedirection 0 -ErrorAction Stop }
        } -IsErrorResponse {
            param($r)
            $null -eq $r -or $null -eq $r.results -or [string]$r.results.common.errorCode -ne '0'
        } -ShouldCache {
            param($r)
            $null -ne $r -and $null -ne $r.results -and [string]$r.results.common.errorCode -eq '0'
        }
        $common = $res.results.common
        if ([string]$common.errorCode -ne '0') {
            return [pscustomobject][ordered]@{ Status='JUSO_ERR'; ErrorCode="code=$($common.errorCode)"; RoadAddress=''; AdmCd=''; RnMgtSn=''; BuldMnnm=''; BuldSlno='' }
        }
        $items = @($res.results.juso)
        if ($items.Count -gt 0) { $anyFound = $true }
        foreach ($it in $items) {
            if (Test-MultiApiRoadBuildingMatch $Business ([string]$it.roadAddr)) {
                $best = $it; break
            }
        }
        if ($null -ne $best) { break }
    }

    if ($null -ne $best) {
        return [pscustomobject][ordered]@{
            Status='JUSO_EXACT'; ErrorCode=''; RoadAddress=[string]$best.roadAddr
            AdmCd=[string]$best.admCd; RnMgtSn=[string]$best.rnMgtSn
            BuldMnnm=[string]$best.buldMnnm; BuldSlno=[string]$best.buldSlno
        }
    }
    if ($anyFound) {
        return [pscustomobject][ordered]@{ Status='JUSO_FOUND_OTHER'; ErrorCode=''; RoadAddress=''; AdmCd=''; RnMgtSn=''; BuldMnnm=''; BuldSlno='' }
    }
    return [pscustomobject][ordered]@{ Status='JUSO_NONE'; ErrorCode=''; RoadAddress=''; AdmCd=''; RnMgtSn=''; BuldMnnm=''; BuldSlno='' }
}

function Invoke-Sdsc2RadiusPoiDiscovery {
    param(
        [Parameter(Mandatory)]$Business,
        [Parameter(Mandatory)][double]$Latitude,
        [Parameter(Mandatory)][double]$Longitude,
        [Parameter(Mandatory)][string]$ServiceKey,
        [scriptblock]$RequestInvoker
    )
    if ([string]::IsNullOrWhiteSpace($ServiceKey)) { throw 'SDSC2_SERVICE_KEY_REQUIRED' }
    $culture = [Globalization.CultureInfo]::InvariantCulture
    $encKey = if ($ServiceKey -match '%[0-9A-Fa-f]{2}') { $ServiceKey } else { [Uri]::EscapeDataString($ServiceKey) }
    $latStr = $Latitude.ToString($culture)
    $lngStr = $Longitude.ToString($culture)

    $evaluateItems = {
        param([object[]]$Items)
        $strong = @()
        $near = @()
        foreach ($it in $Items) {
            $fullNm = [string]$it.bizesNm
            if (-not [string]::IsNullOrWhiteSpace([string]$it.brchNm)) { $fullNm = "$fullNm $([string]$it.brchNm)".Trim() }
            $nm1 = Test-MultiApiCandidateNameMatch $Business ([string]$it.bizesNm)
            $nm2 = Test-MultiApiCandidateNameMatch $Business $fullNm
            if ($nm1 -eq 'BRANCH_CONFLICT' -or $nm2 -eq 'BRANCH_CONFLICT') { continue }
            $nm = if ($nm1 -eq 'EXACT' -or $nm2 -eq 'EXACT') { 'EXACT' } elseif ($nm1 -eq 'COMPATIBLE' -or $nm2 -eq 'COMPATIBLE') { 'COMPATIBLE' } else { 'NONE' }
            if ($nm -notin @('EXACT', 'COMPATIBLE')) { continue }

            $itLat = 0.0; $itLon = 0.0
            $hasCoord = [double]::TryParse([string]$it.lat, [Globalization.NumberStyles]::Float, $culture, [ref]$itLat) -and
                        [double]::TryParse([string]$it.lon, [Globalization.NumberStyles]::Float, $culture, [ref]$itLon)
            if (-not $hasCoord) { continue }
            Assert-PoiCoordinatePair $itLat $itLon
            $dist = Get-MultiApiHaversineMeters $Latitude $Longitude $itLat $itLon
            $roadMatch = Test-MultiApiRoadBuildingMatch $Business ([string]$it.rdnmAdr)
            $score = $(if ($nm -eq 'EXACT') { 10 } else { 5 })
            if ($roadMatch) {
                $strong += [pscustomobject]@{ Tier='SDSC2_STRONG'; Score=$score; Dist=$dist; Item=$it; FullName=$fullNm; Lat=$itLat; Lon=$itLon }
            } elseif ($dist -le 80.0 -and (-not (Get-PoiMatchProvince $Business.Province) -or (Get-PoiMatchProvince ([string]$it.rdnmAdr)) -ceq (Get-PoiMatchProvince $Business.Province))) {
                $near += [pscustomobject]@{ Tier='SDSC2_NEAR_NAME'; Score=$score; Dist=$dist; Item=$it; FullName=$fullNm; Lat=$itLat; Lon=$itLon }
            }
        }
        if ($strong.Count -gt 0) { return ($strong | Sort-Object @{Expression='Score';Descending=$true}, Dist | Select-Object -First 1) }
        if ($near.Count -gt 0) { return ($near | Sort-Object @{Expression='Score';Descending=$true}, Dist | Select-Object -First 1) }
        return $null
    }

    $queryRadius = {
        param([int]$Radius)
        $all = [Collections.Generic.List[object]]::new()
        for ($page = 1; $page -le 2; $page++) {
            $uri = "https://apis.data.go.kr/B553077/api/open/sdsc2/storeListInRadius?serviceKey=$encKey&pageNo=$page&numOfRows=500&radius=$Radius&cx=$lngStr&cy=$latStr&type=json"
            $cacheKey = Get-MultiApiCacheHashKey -Provider 'SDSC2' -RawIdentifier "radius=$Radius&page=$page&lat=$latStr&lng=$lngStr"
            $res = Invoke-MultiApiCachedProviderRequest -Provider 'SDSC2' -CacheKey $cacheKey -Fetcher {
                if ($null -ne $RequestInvoker) { & $RequestInvoker $uri } else { Invoke-RestMethod -Uri $uri -TimeoutSec 20 -MaximumRedirection 0 -ErrorAction Stop }
            } -IsErrorResponse {
                param($r)
                $null -eq $r -or $null -eq $r.header -or ([string]$r.header.resultCode -notin @('00', '03'))
            } -ShouldCache {
                param($r)
                $null -ne $r -and $null -ne $r.header -and ([string]$r.header.resultCode -in @('00', '03'))
            }
            $code = [string]$res.header.resultCode
            if ($code -eq '03') { break }
            if ($code -ne '00') { throw "SDSC2_CODE_$code" }
            if ($null -eq $res.body -or $null -eq $res.body.items) { break }
            $pageItems = @($res.body.items)
            foreach ($x in $pageItems) { $all.Add($x) }
            $totalCount = [int]$res.body.totalCount
            if ($all.Count -ge $totalCount -or $pageItems.Count -lt 500) { break }
        }
        return $all.ToArray()
    }

    $items60 = @(& $queryRadius 60)
    $hit = & $evaluateItems $items60
    if ($null -eq $hit -or $hit.Tier -ne 'SDSC2_STRONG') {
        $items150 = @(& $queryRadius 150)
        $hit150 = & $evaluateItems $items150
        if ($null -ne $hit150 -and ($null -eq $hit -or $hit150.Tier -eq 'SDSC2_STRONG')) { $hit = $hit150 }
    }

    if ($null -ne $hit) {
        return [pscustomobject][ordered]@{
            Status=$hit.Tier; ErrorCode=''; BizesId=[string]$hit.Item.bizesId; Name=$hit.FullName
            RoadAddress=[string]$hit.Item.rdnmAdr; DistanceMeters=$hit.Dist
            Latitude=$hit.Lat; Longitude=$hit.Lon
        }
    }
    return [pscustomobject][ordered]@{
        Status='SDSC2_NONE'; ErrorCode=''; BizesId=''; Name=''; RoadAddress=''
        DistanceMeters=''; Latitude=$null; Longitude=$null
    }
}

function Invoke-KakaoLocalPoiVerification {
    param(
        [Parameter(Mandatory)]$Business,
        [AllowNull()][string]$RawPhone = '',
        [Parameter(Mandatory)][double]$Latitude,
        [Parameter(Mandatory)][double]$Longitude,
        [Parameter(Mandatory)][string]$RestApiKey,
        [scriptblock]$RequestInvoker
    )
    if ([string]::IsNullOrWhiteSpace($RestApiKey)) { throw 'KAKAO_REST_API_KEY_REQUIRED' }
    $culture = [Globalization.CultureInfo]::InvariantCulture
    $latStr = $Latitude.ToString($culture)
    $lngStr = $Longitude.ToString($culture)
    $canonPhone = Normalize-MultiApiPhone $RawPhone
    $headers = @{ Authorization = "KakaoAK $RestApiKey" }

    $collected = [Collections.Generic.List[object]]::new()
    $seenIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)

    $invokeQuery = {
        param([string]$Uri)
        $cacheKey = Get-MultiApiCacheHashKey -Provider 'KAKAO' -RawIdentifier $Uri
        Invoke-MultiApiCachedProviderRequest -Provider 'KAKAO' -CacheKey $cacheKey -Fetcher {
            if ($null -ne $RequestInvoker) { & $RequestInvoker $Uri $headers }
            else { Invoke-RestMethod -Uri $Uri -Headers $headers -TimeoutSec 15 -MaximumRedirection 0 -ErrorAction Stop }
        }
    }

    $q1 = "https://dapi.kakao.com/v2/local/search/keyword.json?query=$([Uri]::EscapeDataString($Business.OriginalName))&x=$lngStr&y=$latStr&radius=150&size=15"
    $r1 = & $invokeQuery $q1
    foreach ($d in @($r1.documents)) {
        if ($seenIds.Add([string]$d.id)) { $collected.Add($d) }
    }

    $hasStrongPhone = $false
    $hasStrong = $false
    foreach ($d in $collected) {
        $nm0 = Test-MultiApiCandidateNameMatch $Business ([string]$d.place_name)
        $road0 = Test-MultiApiRoadBuildingMatch $Business ([string]$d.road_address_name)
        $ph0 = Test-MultiApiPhoneExact $canonPhone (Normalize-MultiApiPhone ([string]$d.phone))
        $dist0 = 99999.0; [void][double]::TryParse([string]$d.distance, [Globalization.NumberStyles]::Float, $culture, [ref]$dist0)
        if ($ph0 -and ($road0 -or $dist0 -le 120.0)) { $hasStrongPhone = $true; $hasStrong = $true; break }
        if ($nm0 -in @('EXACT','COMPATIBLE') -and ($road0 -or $dist0 -le 50.0)) { $hasStrong = $true }
    }

    if (-not $hasStrong -and $Business.BaseName -and $Business.BaseName -cne $Business.OriginalName) {
        $q2 = "https://dapi.kakao.com/v2/local/search/keyword.json?query=$([Uri]::EscapeDataString($Business.BaseName))&x=$lngStr&y=$latStr&radius=150&size=15"
        $r2 = & $invokeQuery $q2
        foreach ($d in @($r2.documents)) {
            if ($seenIds.Add([string]$d.id)) { $collected.Add($d) }
        }
        foreach ($d in $collected) {
            $ph0 = Test-MultiApiPhoneExact $canonPhone (Normalize-MultiApiPhone ([string]$d.phone))
            $road0 = Test-MultiApiRoadBuildingMatch $Business ([string]$d.road_address_name)
            $dist0 = 99999.0; [void][double]::TryParse([string]$d.distance, [Globalization.NumberStyles]::Float, $culture, [ref]$dist0)
            if ($ph0 -and ($road0 -or $dist0 -le 120.0)) { $hasStrongPhone = $true; break }
        }
    }

    if (-not $hasStrongPhone -and $canonPhone) {
        $q3 = "https://dapi.kakao.com/v2/local/search/keyword.json?query=$([Uri]::EscapeDataString($RawPhone.Trim()))&x=$lngStr&y=$latStr&radius=500&size=10"
        $r3 = & $invokeQuery $q3
        foreach ($d in @($r3.documents)) {
            if ($seenIds.Add([string]$d.id)) { $collected.Add($d) }
        }
    }

    # Evaluate collected documents in function scope and omit all Kakao coordinates (x/y).
    $best = $null
    $phoneMovedDist = ''
    foreach ($d in $collected) {
        $nm = Test-MultiApiCandidateNameMatch $Business ([string]$d.place_name)
        $roadOk = Test-MultiApiRoadBuildingMatch $Business ([string]$d.road_address_name)
        $candPhone = Normalize-MultiApiPhone ([string]$d.phone)
        $phoneOk = Test-MultiApiPhoneExact $canonPhone $candPhone
        $dist = 99999.0
        [void][double]::TryParse([string]$d.distance, [Globalization.NumberStyles]::Float, $culture, [ref]$dist)

        if ($phoneOk -and -not $roadOk -and $dist -gt 120.0) { $phoneMovedDist = "$dist" }
        if ($nm -eq 'BRANCH_CONFLICT') { continue }

        $ev = [Collections.Generic.List[string]]::new()
        if ($phoneOk) { $ev.Add('PHONE_EXACT') }
        if ($roadOk) { $ev.Add('ROAD_BLDG_EXACT') }
        if ($nm -eq 'EXACT') { $ev.Add('NAME_EXACT') } elseif ($nm -eq 'COMPATIBLE') { $ev.Add('NAME_COMPATIBLE') }

        $tier = $null; $rank = 0
        if ($phoneOk -and ($roadOk -or $dist -le 120.0)) {
            $tier = 'KAKAO_STRONG_PHONE'; $rank = 30
        } elseif (($nm -in @('EXACT','COMPATIBLE')) -and ($roadOk -or $dist -le 50.0)) {
            $tier = 'KAKAO_STRONG_POI'; $rank = $(if ($nm -eq 'EXACT' -and $roadOk) { 25 } elseif ($roadOk) { 22 } else { 18 })
        } elseif (($nm -in @('EXACT','COMPATIBLE')) -and $dist -le 150.0) {
            $tier = 'KAKAO_NEAR_NAME'; $rank = 10
        } elseif ($phoneOk -and $dist -gt 120.0) {
            $tier = 'KAKAO_PHONE_MOVED'; $rank = 5
        } else {
            continue
        }

        if ($null -eq $best -or $rank -gt $best.Rank -or ($rank -eq $best.Rank -and $dist -lt $best.Dist)) {
            $best = [pscustomobject]@{
                Status=$tier; Rank=$rank; Evidence=($ev -join '|')
                PlaceName=[string]$d.place_name; RoadAddress=[string]$d.road_address_name
                PhoneMatch=$phoneOk; Dist=$dist; PlaceId=[string]$d.id; PlaceUrl=[string]$d.place_url
            }
        }
    }

    if ($null -ne $best) {
        return [pscustomobject][ordered]@{
            Status=$best.Status; ErrorCode=''; Evidence=$best.Evidence; PlaceName=$best.PlaceName
            RoadAddress=$best.RoadAddress; PhoneMatch=$best.PhoneMatch; DistanceMeters=$best.Dist
            PhoneMovedMeters=$phoneMovedDist; PlaceId=$best.PlaceId; PlaceUrl=$best.PlaceUrl
        }
    }
    return [pscustomobject][ordered]@{
        Status='KAKAO_NONE'; ErrorCode=''; Evidence=''; PlaceName=''; RoadAddress=''
        PhoneMatch=$false; DistanceMeters=''; PhoneMovedMeters=$phoneMovedDist; PlaceId=''; PlaceUrl=''
    }
}

function Invoke-NaverEnhancedPoiEvaluation {
    param(
        [Parameter(Mandatory)]$Business,
        [string]$ClientId = $env:NAVER_API_HUB_CLIENT_ID,
        [string]$ClientSecret = $env:NAVER_API_HUB_CLIENT_SECRET,
        [scriptblock]$RequestInvoker
    )
    $discParams = @{ Business=$Business; ClientId=$ClientId; ClientSecret=$ClientSecret }
    if ($null -ne $RequestInvoker) { $discParams.RequestInvoker = $RequestInvoker }
    $naverCacheId = "$($Business.OriginalName)|$($Business.PreferredAddress)|$($Business.RoadName)|$($Business.BuildingMain)|$($Business.BuildingSub)"
    $naverCacheKey = Get-MultiApiCacheHashKey -Provider 'NAVER' -RawIdentifier $naverCacheId
    $batch = Invoke-MultiApiCachedProviderRequest -Provider 'NAVER' -CacheKey $naverCacheKey -Fetcher {
        Invoke-PoiDiscovery @discParams
    } -IsErrorResponse {
        param($b)
        $null -eq $b -or ([string]$b.Status -eq 'FAILED')
    } -ShouldCache {
        param($b)
        $null -ne $b -and ([string]$b.Status -ne 'FAILED')
    }
    $eval = Invoke-PoiMatchEvaluation -Business $Business -DiscoveryBatch $batch

    $sel = $eval.SelectedCandidate
    $enhStatus = [string]$eval.Classification
    $enhReason = (@($eval.ReasonCodes) -join '|')
    $enhSelectedName = if ($sel) { [string]$sel.OriginalName } else { '' }
    $enhRoadAddr = if ($sel) { [string]$sel.RoadAddress } else { '' }

    if ($eval.Classification -eq 'GREEN') {
        $enhStatus = 'NAVER_ENH_STRONG'
    } else {
        $enhMatches = [Collections.Generic.List[object]]::new()
        foreach ($c in @($batch.Candidates)) {
            $nm = Test-MultiApiCandidateNameMatch $Business ([string]$c.OriginalName)
            if ($nm -notin @('EXACT','COMPATIBLE')) { continue }
            if (Test-MultiApiRoadBuildingMatch $Business ([string]$c.RoadAddress)) {
                $enhMatches.Add([pscustomobject]@{ Candidate=$c; NameTier=$nm })
            }
        }
        if ($enhMatches.Count -eq 1) {
            $enhStatus = 'NAVER_ENH_STRONG'
            $enhReason = "RECOVERED_SINGLE_ROAD_BLDG_$($enhMatches[0].NameTier)"
            $enhSelectedName = [string]$enhMatches[0].Candidate.OriginalName
            $enhRoadAddr = [string]$enhMatches[0].Candidate.RoadAddress
        }
    }

    return [pscustomobject][ordered]@{
        DiscoveryStatus=[string]$batch.Status
        CandidateCount=@($batch.Candidates).Count
        P1Class=[string]$eval.Classification
        P1Reason=(@($eval.ReasonCodes) -join '|')
        EnhStatus=$enhStatus
        EnhReason=$enhReason
        SelectedName=if ($sel) { [string]$sel.OriginalName } else { '' }
        EnhSelectedName=$enhSelectedName
        EnhRoadAddress=$enhRoadAddr
    }
}

function Merge-MultiApiPoiVerificationRow {
    param(
        [Parameter(Mandatory)][int]$RowNumber,
        [Parameter(Mandatory)]$Business,
        [Parameter(Mandatory)]$JusoResult,
        [Parameter(Mandatory)]$Sdsc2Result,
        [Parameter(Mandatory)]$KakaoResult,
        [Parameter(Mandatory)]$NaverResult,
        [string]$District = '',
        [bool]$HasPhone = $false,
        [string]$CanonicalCoordStatus = ''
    )
    $sdscStrong = ($Sdsc2Result.Status -ceq 'SDSC2_STRONG')
    $kakaoStrong = ($KakaoResult.Status -in @('KAKAO_STRONG_PHONE','KAKAO_STRONG_POI'))
    $naverEnhStrong = ($NaverResult.EnhStatus -ceq 'NAVER_ENH_STRONG')
    $strongCount = ([int]$sdscStrong) + ([int]$kakaoStrong) + ([int]$naverEnhStrong)
    $anyStrongPoi = ($sdscStrong -or $kakaoStrong -or $naverEnhStrong)
    $jusoExact = ($JusoResult.Status -ceq 'JUSO_EXACT')
    $publicLegalPin = ($sdscStrong -or ($jusoExact -and ($kakaoStrong -or $naverEnhStrong)))

    $coordSource = if ($sdscStrong) { 'SDSC2_PUBLIC_OPEN_DATA' }
        elseif ($publicLegalPin) { 'JUSO_VERIFIED_BUILDING' }
        elseif ($naverEnhStrong) { 'NAVER_API_HUB_POI' }
        else { '' }

    $allUnmatched = (-not $anyStrongPoi -and $Sdsc2Result.Status -eq 'SDSC2_NONE' -and
        $KakaoResult.Status -in @('KAKAO_NONE','KAKAO_PHONE_MOVED') -and $NaverResult.P1Class -eq 'RED')

    return [pscustomobject][ordered]@{
        RowNumber=$RowNumber
        BusinessName=[string]$Business.OriginalName
        District=$District
        RoadAddress=[string]$Business.OriginalRoadAddress
        HasPhone=$HasPhone
        CanonicalCoordStatus=$CanonicalCoordStatus
        JusoStatus=$JusoResult.Status
        JusoRoadAddress=$JusoResult.RoadAddress
        JusoAdmCd=$JusoResult.AdmCd
        JusoRnMgtSn=$JusoResult.RnMgtSn
        JusoBuldMnnm=$JusoResult.BuldMnnm
        JusoBuldSlno=$JusoResult.BuldSlno
        Sdsc2Status=$Sdsc2Result.Status
        Sdsc2Name=$Sdsc2Result.Name
        Sdsc2RoadAddress=$Sdsc2Result.RoadAddress
        Sdsc2DistanceMeters=$Sdsc2Result.DistanceMeters
        Sdsc2Latitude=$Sdsc2Result.Latitude
        Sdsc2Longitude=$Sdsc2Result.Longitude
        Sdsc2BizesId=$Sdsc2Result.BizesId
        KakaoStatus=$KakaoResult.Status
        KakaoEvidence=$KakaoResult.Evidence
        KakaoPlaceName=$KakaoResult.PlaceName
        KakaoRoadAddress=$KakaoResult.RoadAddress
        KakaoPhoneMatch=$KakaoResult.PhoneMatch
        KakaoDistanceMeters=$KakaoResult.DistanceMeters
        KakaoPhoneMovedMeters=$KakaoResult.PhoneMovedMeters
        KakaoPlaceId=$KakaoResult.PlaceId
        KakaoPlaceUrl=$KakaoResult.PlaceUrl
        NaverP1Class=$NaverResult.P1Class
        NaverP1Reason=$NaverResult.P1Reason
        NaverEnhStatus=$NaverResult.EnhStatus
        NaverEnhReason=$NaverResult.EnhReason
        NaverSelectedName=$NaverResult.SelectedName
        NaverEnhSelectedName=$NaverResult.EnhSelectedName
        NaverEnhRoadAddress=$NaverResult.EnhRoadAddress
        StrongApiCount=$strongCount
        AnyStrongPoi=$anyStrongPoi
        PublicLegalPin=$publicLegalPin
        RecommendedCoordinateSource=$coordSource
        AllPoiUnmatched=$allUnmatched
        ProductionAction='NONE'
    }
}

function Assert-MultiApiExternalOutputDirectory {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string[]]$RepositoryRoots = @()
    )
    $full = [IO.Path]::GetFullPath($Path)
    if ($RepositoryRoots.Count -eq 0) {
        $worktree = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
        $common = & git -C $worktree rev-parse --path-format=absolute --git-common-dir
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($common)) { throw 'MULTI_API_REPO_ROOT_UNAVAILABLE' }
        $RepositoryRoots = @($worktree, (Split-Path -Parent $common))
    }
    foreach ($root in $RepositoryRoots) {
        $repo = [IO.Path]::GetFullPath($root).TrimEnd([IO.Path]::DirectorySeparatorChar)
        if ($full.Equals($repo, [StringComparison]::OrdinalIgnoreCase) -or
            $full.StartsWith($repo + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'MULTI_API_OUTPUT_MUST_BE_OUTSIDE_REPOSITORY'
        }
    }
    $ancestor = $full
    while (-not [string]::IsNullOrEmpty($ancestor)) {
        if (Test-Path -LiteralPath $ancestor) {
            if ((Get-Item -LiteralPath $ancestor -Force).Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) {
                throw 'MULTI_API_OUTPUT_REPARSE_POINT'
            }
        }
        $ancestor = [IO.Path]::GetDirectoryName($ancestor)
    }
    return $full
}

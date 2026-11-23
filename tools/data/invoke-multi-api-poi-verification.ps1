[CmdletBinding()]
param(
    [string]$CanonicalCsv = '.\data\canonical\capital-area-military-benefits.csv',
    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,
    [int[]]$RowNumbers = @(),
    [string]$LocalPropertiesPath = '.\apps\android\local.properties',
    [ValidateSet('JUSO','SDSC2','KAKAO','NAVER')]
    [string[]]$Providers = @('JUSO','SDSC2','KAKAO','NAVER'),
    [int]$DelayMilliseconds = 40
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/poi-discovery/multi-api-poi-verification.ps1')

function Read-MultiApiLocalProperties {
    param([string]$Path)
    $values = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $values }
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        if ($line -match '^\s*([^#!][^=]*)=(.*)$') {
            $values[$matches[1].Trim()] = $matches[2].Trim()
        }
    }
    return $values
}

function Get-MultiApiConfiguredSecret {
    param([hashtable]$Properties, [string]$Name)
    $envVal = [Environment]::GetEnvironmentVariable($Name)
    if (-not [string]::IsNullOrWhiteSpace($envVal)) { return $envVal.Trim() }
    if ($Properties.ContainsKey($Name)) { return ([string]$Properties[$Name]).Trim() }
    return ''
}

$resolvedOut = Assert-MultiApiExternalOutputDirectory -Path $OutputDirectory
[void][IO.Directory]::CreateDirectory($resolvedOut)

$props = Read-MultiApiLocalProperties -Path $LocalPropertiesPath
$jusoKey = Get-MultiApiConfiguredSecret $props 'JUSO_SEARCH_KEY'
$sdsc2Key = Get-MultiApiConfiguredSecret $props 'DATA_GO_KR_SERVICE_KEY'
$kakaoKey = Get-MultiApiConfiguredSecret $props 'KAKAO_REST_API_KEY'
$naverId = Get-MultiApiConfiguredSecret $props 'NAVER_API_HUB_CLIENT_ID'
$naverSecret = Get-MultiApiConfiguredSecret $props 'NAVER_API_HUB_CLIENT_SECRET'

if (($Providers -contains 'JUSO') -and -not $jusoKey) { throw 'JUSO_SEARCH_KEY is required when JUSO provider is enabled' }
if (($Providers -contains 'SDSC2') -and -not $sdsc2Key) { throw 'DATA_GO_KR_SERVICE_KEY is required when SDSC2 provider is enabled' }
if (($Providers -contains 'KAKAO') -and -not $kakaoKey) { throw 'KAKAO_REST_API_KEY is required when KAKAO provider is enabled' }
if (($Providers -contains 'NAVER') -and (-not $naverId -or -not $naverSecret)) { throw 'NAVER_API_HUB credentials are required when NAVER provider is enabled' }

$csvRows = @(Import-Csv -LiteralPath $CanonicalCsv -Encoding UTF8)
$culture = [Globalization.CultureInfo]::InvariantCulture
$targetSet = if ($RowNumbers.Count -gt 0) { [Collections.Generic.HashSet[int]]::new($RowNumbers) } else { $null }

$started = [DateTimeOffset]::Now
Reset-MultiApiProviderTelemetry
Set-MultiApiRequestCache -Enabled $true
$results = [Collections.Generic.List[object]]::new()

for ($i = 0; $i -lt $csvRows.Count; $i++) {
    $rn = $i + 2
    if ($null -ne $targetSet -and -not $targetSet.Contains($rn)) { continue }

    $row = $csvRows[$i]
    $lat = 0.0; $lng = 0.0
    $hasCoords = [double]::TryParse([string]$row.'위도', [Globalization.NumberStyles]::Float, $culture, [ref]$lat) -and
                 [double]::TryParse([string]$row.'경도', [Globalization.NumberStyles]::Float, $culture, [ref]$lng)
    if (-not $hasCoords) {
        if ($null -ne $targetSet) { throw "Row $rn does not have numeric coordinates" }
        continue
    }

    $business = ConvertTo-NormalizedBusiness -Row $row -SourceRowNumber $rn

    $juso = [pscustomobject][ordered]@{ Status='SKIPPED'; ErrorCode=''; RoadAddress=''; AdmCd=''; RnMgtSn=''; BuldMnnm=''; BuldSlno='' }
    if ($Providers -contains 'JUSO') {
        $prevHits = (Get-MultiApiProviderTelemetrySummary).JUSO.CacheHits
        try { $juso = Invoke-JusoRoadAddressLookup -Business $business -ApiKey $jusoKey } catch {
            $juso = [pscustomobject][ordered]@{ Status='JUSO_ERR'; ErrorCode='REQUEST_FAILED'; RoadAddress=''; AdmCd=''; RnMgtSn=''; BuldMnnm=''; BuldSlno='' }
        }
        $afterHits = (Get-MultiApiProviderTelemetrySummary).JUSO.CacheHits
        if ($DelayMilliseconds -gt 0 -and $afterHits -eq $prevHits) { Start-Sleep -Milliseconds $DelayMilliseconds }
    }

    $sdsc = [pscustomobject][ordered]@{ Status='SKIPPED'; ErrorCode=''; BizesId=''; Name=''; RoadAddress=''; DistanceMeters=''; Latitude=$null; Longitude=$null }
    if ($Providers -contains 'SDSC2') {
        $prevHits = (Get-MultiApiProviderTelemetrySummary).SDSC2.CacheHits
        try { $sdsc = Invoke-Sdsc2RadiusPoiDiscovery -Business $business -Latitude $lat -Longitude $lng -ServiceKey $sdsc2Key } catch {
            $sdsc = [pscustomobject][ordered]@{ Status='SDSC2_ERR'; ErrorCode='REQUEST_FAILED'; BizesId=''; Name=''; RoadAddress=''; DistanceMeters=''; Latitude=$null; Longitude=$null }
        }
        $afterHits = (Get-MultiApiProviderTelemetrySummary).SDSC2.CacheHits
        if ($DelayMilliseconds -gt 0 -and $afterHits -eq $prevHits) { Start-Sleep -Milliseconds $DelayMilliseconds }
    }

    $kakao = [pscustomobject][ordered]@{ Status='SKIPPED'; ErrorCode=''; Evidence=''; PlaceName=''; RoadAddress=''; PhoneMatch=$false; DistanceMeters=''; PhoneMovedMeters=''; PlaceId=''; PlaceUrl='' }
    if ($Providers -contains 'KAKAO') {
        $prevHits = (Get-MultiApiProviderTelemetrySummary).KAKAO.CacheHits
        try { $kakao = Invoke-KakaoLocalPoiVerification -Business $business -RawPhone ([string]$row.'업소전화번호') -Latitude $lat -Longitude $lng -RestApiKey $kakaoKey } catch {
            $kakao = [pscustomobject][ordered]@{ Status='KAKAO_ERR'; ErrorCode='REQUEST_FAILED'; Evidence=''; PlaceName=''; RoadAddress=''; PhoneMatch=$false; DistanceMeters=''; PhoneMovedMeters=''; PlaceId=''; PlaceUrl='' }
        }
        $afterHits = (Get-MultiApiProviderTelemetrySummary).KAKAO.CacheHits
        if ($DelayMilliseconds -gt 0 -and $afterHits -eq $prevHits) { Start-Sleep -Milliseconds $DelayMilliseconds }
    }

    $naver = [pscustomobject][ordered]@{ DiscoveryStatus='SKIPPED'; CandidateCount=0; P1Class='SKIPPED'; P1Reason=''; EnhStatus='SKIPPED'; EnhReason=''; SelectedName=''; EnhSelectedName=''; EnhRoadAddress='' }
    if ($Providers -contains 'NAVER') {
        $prevHits = (Get-MultiApiProviderTelemetrySummary).NAVER.CacheHits
        try { $naver = Invoke-NaverEnhancedPoiEvaluation -Business $business -ClientId $naverId -ClientSecret $naverSecret } catch {
            $naver = [pscustomobject][ordered]@{ DiscoveryStatus='FAILED'; CandidateCount=0; P1Class='ERR'; P1Reason='REQUEST_FAILED'; EnhStatus='NAVER_ERR'; EnhReason='REQUEST_FAILED'; SelectedName=''; EnhSelectedName=''; EnhRoadAddress='' }
        }
        $afterHits = (Get-MultiApiProviderTelemetrySummary).NAVER.CacheHits
        if ($DelayMilliseconds -gt 0 -and $afterHits -eq $prevHits) { Start-Sleep -Milliseconds $DelayMilliseconds }
    }

    # On glued rows (BuildingMain empty), retry JUSO once with a deterministic standard road address from SDSC2 or KAKAO
    if (($Providers -contains 'JUSO') -and $juso.Status -ne 'JUSO_EXACT' -and [string]::IsNullOrWhiteSpace([string]$business.BuildingMain)) {
        $stdRoad = if ($sdsc.Status -eq 'SDSC2_STRONG' -and $sdsc.RoadAddress) { [string]$sdsc.RoadAddress }
            elseif ($kakao.Status -in @('KAKAO_STRONG_PHONE','KAKAO_STRONG_POI') -and $kakao.RoadAddress -and (Test-MultiApiRoadBuildingMatch $business ([string]$kakao.RoadAddress))) { [string]$kakao.RoadAddress }
            else { '' }
        if ($stdRoad) {
            try {
                $retryJuso = Invoke-JusoRoadAddressLookup -Business $business -ApiKey $jusoKey -CandidateRoadAddress $stdRoad
                if ($retryJuso.Status -eq 'JUSO_EXACT') { $juso = $retryJuso }
            } catch { }
            if ($DelayMilliseconds -gt 0) { Start-Sleep -Milliseconds $DelayMilliseconds }
        }
    }

    $merged = Merge-MultiApiPoiVerificationRow -RowNumber $rn -Business $business `
        -JusoResult $juso -Sdsc2Result $sdsc -KakaoResult $kakao -NaverResult $naver `
        -District ([string]$row.'시군구') `
        -HasPhone (-not [string]::IsNullOrWhiteSpace([string]$row.'업소전화번호')) `
        -CanonicalCoordStatus ([string]$row.'좌표검증상태')
    $results.Add($merged)

    if ($results.Count % 25 -eq 0) {
        Write-Output ("[{0}] JUSO={1} | SDSC2={2} | KAKAO={3} | NAVER_ENH={4} | UNION={5}" -f `
            $results.Count, `
            @($results | Where-Object JusoStatus -eq 'JUSO_EXACT').Count, `
            @($results | Where-Object Sdsc2Status -eq 'SDSC2_STRONG').Count, `
            @($results | Where-Object { $_.KakaoStatus -in @('KAKAO_STRONG_PHONE','KAKAO_STRONG_POI') }).Count, `
            @($results | Where-Object NaverEnhStatus -eq 'NAVER_ENH_STRONG').Count, `
            @($results | Where-Object AnyStrongPoi).Count)
    }
}

$csvOut = Join-Path $resolvedOut 'multi-api-poi-results.csv'
$results | Export-Csv -LiteralPath $csvOut -NoTypeInformation -Encoding UTF8

$summary = [ordered]@{
    GeneratedAt = [DateTimeOffset]::Now.ToString('o')
    DurationSeconds = [Math]::Round(([DateTimeOffset]::Now - $started).TotalSeconds, 1)
    ProductionAction = 'NONE'
    Providers = @($Providers)
    Total = $results.Count
    JusoExact = @($results | Where-Object JusoStatus -eq 'JUSO_EXACT').Count
    Sdsc2Strong = @($results | Where-Object Sdsc2Status -eq 'SDSC2_STRONG').Count
    KakaoStrongTotal = @($results | Where-Object { $_.KakaoStatus -in @('KAKAO_STRONG_PHONE','KAKAO_STRONG_POI') }).Count
    KakaoPhoneMoved = @($results | Where-Object KakaoStatus -eq 'KAKAO_PHONE_MOVED').Count
    NaverP1Green = @($results | Where-Object NaverP1Class -eq 'GREEN').Count
    NaverEnhStrong = @($results | Where-Object NaverEnhStatus -eq 'NAVER_ENH_STRONG').Count
    UnionAnyStrongPoi = @($results | Where-Object AnyStrongPoi).Count
    PublicLegalPin = @($results | Where-Object PublicLegalPin).Count
    MultiApiAgreed2Plus = @($results | Where-Object { $_.StrongApiCount -ge 2 }).Count
    AllPoiUnmatched = @($results | Where-Object AllPoiUnmatched).Count
    ProviderTelemetry = (Get-MultiApiProviderTelemetrySummary)
}
Set-MultiApiRequestCache -Enabled $false
$jsonOut = Join-Path $resolvedOut 'multi-api-poi-summary.json'
$jsonBytes = [Text.UTF8Encoding]::new($false).GetBytes(($summary | ConvertTo-Json -Depth 10))
[IO.File]::WriteAllBytes($jsonOut, $jsonBytes)
Write-Output ("Multi-API POI verification completed: {0} rows (PublicLegalPin={1}, Union={2}) -> {3}" -f $results.Count, $summary.PublicLegalPin, $summary.UnionAnyStrongPoi, $resolvedOut)

[CmdletBinding()]
param(
    [string]$LocalPropertiesPath = ".\apps\android\local.properties",
    [string]$SeedCsv = ".\data\seed\capital-area-military-benefits-20260815.csv",
    [string]$ExistingCacheJson = ".\apps\android\app\src\main\assets\mma.coordinates.seed.json",
    [string]$DestinationJson = ".\apps\android\app\src\main\assets\mma.coordinates.seed.json",
    [string]$ReportCsv = ".\data\reports\mma-coordinate-geocoding-report-20260904.csv",
    [string]$SummaryJson = ".\data\reports\mma-coordinate-geocoding-summary-20260904.json",
    [int]$DelayMilliseconds = 120,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$mmaEndpoint = "https://apis.data.go.kr/1300000/JwctMmaUdhygigwan/getjwctMmaUdhygigwan"
$geocodingEndpoint = "https://maps.apigw.ntruss.com/map-geocode/v2/geocode"
$verifiedDate = [DateTimeOffset]::Now.ToString("yyyy-MM-dd")

function Read-LocalProperties {
    param([string]$Path)

    $values = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $values }
    foreach ($line in Get-Content -LiteralPath $Path -Encoding utf8) {
        if ($line -match '^\s*([^#!][^=]*)=(.*)$') {
            $values[$matches[1].Trim()] = $matches[2].Trim()
        }
    }
    return $values
}

function Get-ConfiguredValue {
    param(
        [hashtable]$Properties,
        [string]$Name
    )

    $environmentValue = [Environment]::GetEnvironmentVariable($Name)
    if (-not [string]::IsNullOrWhiteSpace($environmentValue)) { return $environmentValue.Trim() }
    if ($Properties.ContainsKey($Name)) { return ([string]$Properties[$Name]).Trim() }
    return ""
}

function ConvertTo-NormalizedKey {
    param(
        [string]$Name,
        [string]$Address
    )

    return (("$Name|$Address").ToLowerInvariant() -replace '[\s,()]', '')
}

function ConvertTo-NormalizedAddressText {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    return (($Value.ToLowerInvariant()) -replace '[^\p{L}\p{Nd}]', '')
}

function Get-AddressElement {
    param(
        [psobject]$Address,
        [string]$Type
    )

    foreach ($element in @($Address.addressElements)) {
        if (@($element.types) -contains $Type) { return [string]$element.longName }
    }
    return ""
}

function Get-ExpectedSido {
    param([string]$Address)

    switch -Regex ($Address.Trim()) {
        '^서울' { return "서울특별시" }
        '^경기' { return "경기도" }
        '^인천' { return "인천광역시" }
        default { return "" }
    }
}

function Test-CapitalAreaAddress {
    param([string]$Address)

    return $Address -match '^\s*(서울(?:특별시)?|경기(?:도)?|인천(?:광역시)?)'
}

function Test-AddressMatch {
    param(
        [string]$InputAddress,
        [psobject]$Candidate
    )

    $normalizedInput = ConvertTo-NormalizedAddressText $InputAddress
    $roadName = ConvertTo-NormalizedAddressText (Get-AddressElement $Candidate "ROAD_NAME")
    $buildingNumber = ConvertTo-NormalizedAddressText (Get-AddressElement $Candidate "BUILDING_NUMBER")
    if ($roadName -and $buildingNumber) {
        return $normalizedInput.Contains($roadName) -and $normalizedInput.Contains($buildingNumber)
    }
    foreach ($returnedAddress in @([string]$Candidate.roadAddress, [string]$Candidate.jibunAddress)) {
        $normalizedReturned = ConvertTo-NormalizedAddressText $returnedAddress
        if ($normalizedReturned -and
            ($normalizedInput.Contains($normalizedReturned) -or $normalizedReturned.Contains($normalizedInput))) {
            return $true
        }
    }
    return $false
}

function Test-KoreaCoordinate {
    param(
        [double]$Latitude,
        [double]$Longitude
    )

    return $Latitude -ge 33.0 -and $Latitude -le 39.5 -and
        $Longitude -ge 124.0 -and $Longitude -le 132.0
}

function ConvertTo-Double {
    param([string]$Value)

    $number = 0.0
    if ([double]::TryParse(
        $Value,
        [Globalization.NumberStyles]::Float,
        [Globalization.CultureInfo]::InvariantCulture,
        [ref]$number
    )) { return $number }
    return $null
}

function Invoke-MmaPage {
    param(
        [string]$ServiceKey,
        [int]$Page,
        [int]$Rows
    )

    $key = if ($ServiceKey.Contains('%')) { $ServiceKey } else { [Uri]::EscapeDataString($ServiceKey) }
    $uri = "${mmaEndpoint}?numOfRows=$Rows&pageNo=$Page&serviceKey=$key"
    $request = [System.Net.HttpWebRequest]::Create($uri)
    $request.Method = "GET"
    $request.Accept = "application/xml"
    $request.Timeout = 45000
    $response = $null
    try {
        $response = [System.Net.HttpWebResponse]$request.GetResponse()
        $reader = [System.IO.StreamReader]::new(
            $response.GetResponseStream(),
            [System.Text.UTF8Encoding]::new($false),
            $true
        )
        try { $xmlText = $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally {
        if ($null -ne $response) { $response.Dispose() }
    }
    $document = [System.Xml.XmlDocument]::new()
    $document.LoadXml($xmlText)
    $header = $document.response.header
    $resultCode = [string]$header.resultCode
    if ($resultCode -and $resultCode -notin @("00", "0", "NORMAL_SERVICE")) {
        throw "나라사랑가게 API 오류: $($header.resultMsg) ($resultCode)"
    }
    return $document.response.body
}

function Invoke-NaverGeocoding {
    param(
        [string]$Query,
        [string]$KeyId,
        [string]$Secret
    )

    $uri = "${geocodingEndpoint}?query=$([Uri]::EscapeDataString($Query))&count=10"
    $headers = @{
        "x-ncp-apigw-api-key-id" = $KeyId
        "x-ncp-apigw-api-key" = $Secret
        "Accept" = "application/json"
    }
    $lastError = $null
    for ($attempt = 1; $attempt -le 3; $attempt += 1) {
        try {
            return Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -TimeoutSec 30
        } catch {
            $lastError = $_
            if ($attempt -lt 3) { Start-Sleep -Seconds ([math]::Pow(2, $attempt - 1)) }
        }
    }
    throw $lastError
}

function Get-XmlValue {
    param(
        [psobject]$Item,
        [string]$Name
    )

    if ($Item -is [System.Xml.XmlNode]) {
        $node = $Item.SelectSingleNode($Name)
        if ($null -ne $node) { return ([string]$node.InnerText).Trim() }
    }
    $property = $Item.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return "" }
    return ([string]$property.Value).Trim()
}

function Save-Json {
    param(
        [string]$Path,
        [object]$Value,
        [int]$Depth = 8
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $parent = Split-Path -Parent $fullPath
    if ($parent) { [System.IO.Directory]::CreateDirectory($parent) | Out-Null }
    $json = $Value | ConvertTo-Json -Depth $Depth
    [System.IO.File]::WriteAllText($fullPath, $json, [System.Text.UTF8Encoding]::new($false))
}

function New-CoordinateEntry {
    param(
        [string]$Name,
        [string]$Address,
        [double]$Latitude,
        [double]$Longitude,
        [string]$CoordinateSource,
        [string]$SourceUrl,
        [string]$VerifiedAt
    )

    return [pscustomobject][ordered]@{
        name = $Name
        address = $Address
        latitude = $Latitude
        longitude = $Longitude
        coordinateSource = $CoordinateSource
        sourceUrl = $SourceUrl
        verifiedAt = $VerifiedAt
    }
}

$properties = Read-LocalProperties $LocalPropertiesPath
$mmaServiceKey = Get-ConfiguredValue $properties "MMA_SERVICE_KEY"
$naverKeyId = Get-ConfiguredValue $properties "NAVER_MAP_NCP_KEY_ID"
$naverSecret = Get-ConfiguredValue $properties "NAVER_MAP_NCP_SECRET"
if ([string]::IsNullOrWhiteSpace($mmaServiceKey)) {
    throw "MMA_SERVICE_KEY를 local.properties 또는 환경 변수에 설정해 주세요."
}
if (-not $DryRun -and
    ([string]::IsNullOrWhiteSpace($naverKeyId) -or [string]::IsNullOrWhiteSpace($naverSecret))) {
    throw "NAVER_MAP_NCP_KEY_ID와 NAVER_MAP_NCP_SECRET을 local.properties 또는 환경 변수에 설정해 주세요."
}

$pageSize = 500
$firstBody = Invoke-MmaPage $mmaServiceKey 1 $pageSize
$totalCount = [int]$firstBody.totalCount
$pageCount = [math]::Max(1, [math]::Ceiling($totalCount / [double]$pageSize))
$rawItems = [System.Collections.Generic.List[object]]::new()
foreach ($item in @($firstBody.items.item)) { if ($null -ne $item) { $rawItems.Add($item) } }
for ($page = 2; $page -le $pageCount; $page += 1) {
    $body = Invoke-MmaPage $mmaServiceKey $page $pageSize
    foreach ($item in @($body.items.item)) { if ($null -ne $item) { $rawItems.Add($item) } }
}

$storesByIdentity = [ordered]@{}
foreach ($item in $rawItems) {
    $name = Get-XmlValue $item "udaeGgm"
    $address = Get-XmlValue $item "juso"
    $rowNumber = Get-XmlValue $item "rnum"
    if ([string]::IsNullOrWhiteSpace($name)) { continue }
    $identity = if ($rowNumber) { "rnum:$rowNumber" } else { ConvertTo-NormalizedKey $name $address }
    if (-not $storesByIdentity.Contains($identity)) {
        $storesByIdentity[$identity] = [pscustomobject][ordered]@{
            rowNumber = $rowNumber
            name = $name
            address = $address
            phone = Get-XmlValue $item "udgigwanTelno"
            benefitGroup = Get-XmlValue $item "gtcdNm"
        }
    }
}
$allStores = @($storesByIdentity.Values)
if ($allStores.Count -gt 0) {
    Write-Verbose "첫 API 주소 표본: $([string]$allStores[0].address)"
    $capitalSample = $allStores | Where-Object { ([string]$_.address) -match '서울|경기|인천' } | Select-Object -First 1
    if ($null -ne $capitalSample) {
        Write-Verbose "수도권 주소 표본: $([string]$capitalSample.address), 필터=$([bool](Test-CapitalAreaAddress ([string]$capitalSample.address)))"
    }
}
$capitalStores = @($allStores | Where-Object { Test-CapitalAreaAddress $_.address })

$reusableByKey = @{}
if (Test-Path -LiteralPath $SeedCsv) {
    foreach ($row in @(Import-Csv -LiteralPath $SeedCsv -Encoding utf8)) {
        $name = ([string]$row.업소명).Trim()
        $address = ([string]$row.소재지도로명주소).Trim()
        $latitude = ConvertTo-Double ([string]$row.위도)
        $longitude = ConvertTo-Double ([string]$row.경도)
        if ($name -and $address -and $null -ne $latitude -and $null -ne $longitude -and
            (Test-KoreaCoordinate $latitude $longitude) -and
            ([string]$row.좌표검증상태).Trim() -eq "확인 완료") {
            $reusableByKey[(ConvertTo-NormalizedKey $name $address)] = New-CoordinateEntry `
                $name $address $latitude $longitude ([string]$row.좌표출처) ([string]$row.좌표출처URL) $verifiedDate
        }
    }
}
if (Test-Path -LiteralPath $ExistingCacheJson) {
    $existingJson = Get-Content -LiteralPath $ExistingCacheJson -Raw -Encoding utf8 | ConvertFrom-Json
    foreach ($entry in @($existingJson)) {
        $latitude = ConvertTo-Double ([string]$entry.latitude)
        $longitude = ConvertTo-Double ([string]$entry.longitude)
        if ($entry.name -and $entry.address -and $null -ne $latitude -and $null -ne $longitude -and
            (Test-KoreaCoordinate $latitude $longitude) -and
            ([string]$entry.coordinateSource).Trim() -eq "네이버 Geocoding API") {
            $reusableByKey[(ConvertTo-NormalizedKey ([string]$entry.name) ([string]$entry.address))] = $entry
        }
    }
}

$coordinatesByKey = [ordered]@{}
$reports = [System.Collections.Generic.List[object]]::new()
$counts = [ordered]@{
    apiTotalCount = $totalCount
    fetchedRows = $rawItems.Count
    uniqueRows = $allStores.Count
    capitalAreaRows = $capitalStores.Count
    uniqueCapitalAreaPlaces = 0
    reused = 0
    requested = 0
    matched = 0
    noResult = 0
    ambiguous = 0
    regionMismatch = 0
    addressMismatch = 0
    invalidCoordinate = 0
    missingAddress = 0
    apiError = 0
    pendingDryRun = 0
}

$uniqueCapitalStores = [ordered]@{}
foreach ($store in $capitalStores) {
    $key = ConvertTo-NormalizedKey $store.name $store.address
    if (-not $uniqueCapitalStores.Contains($key)) { $uniqueCapitalStores[$key] = $store }
}
$counts.uniqueCapitalAreaPlaces = $uniqueCapitalStores.Count

foreach ($key in $uniqueCapitalStores.Keys) {
    $store = $uniqueCapitalStores[$key]
    $report = [ordered]@{
        rnum = $store.rowNumber
        업소명 = $store.name
        주소 = $store.address
        전화번호 = $store.phone
        혜택유형 = $store.benefitGroup
        처리상태 = ""
        좌표출처 = ""
        좌표검증상태 = ""
        위도 = ""
        경도 = ""
        반환주소 = ""
        검토메모 = ""
    }

    if ([string]::IsNullOrWhiteSpace($store.address)) {
        $counts.missingAddress += 1
        $report.처리상태 = "MISSING_ADDRESS"
        $report.좌표검증상태 = "미확인"
        $report.검토메모 = "주소 누락"
        $reports.Add([pscustomobject]$report)
        continue
    }
    if ($reusableByKey.ContainsKey($key)) {
        $entry = $reusableByKey[$key]
        $coordinatesByKey[$key] = New-CoordinateEntry `
            $store.name $store.address ([double]$entry.latitude) ([double]$entry.longitude) `
            ([string]$entry.coordinateSource) ([string]$entry.sourceUrl) ([string]$entry.verifiedAt)
        $counts.reused += 1
        $report.처리상태 = "REUSED"
        $report.좌표출처 = [string]$entry.coordinateSource
        $report.좌표검증상태 = "확인 완료"
        $report.위도 = ([double]$entry.latitude).ToString("0.########", [Globalization.CultureInfo]::InvariantCulture)
        $report.경도 = ([double]$entry.longitude).ToString("0.########", [Globalization.CultureInfo]::InvariantCulture)
        $report.검토메모 = "업소명·주소 정규화 키가 기존 검증 좌표와 일치"
        $reports.Add([pscustomobject]$report)
        continue
    }
    if ($DryRun) {
        $counts.pendingDryRun += 1
        $report.처리상태 = "PENDING_DRY_RUN"
        $report.좌표검증상태 = "미확인"
        $report.검토메모 = "Geocoding API 미호출"
        $reports.Add([pscustomobject]$report)
        continue
    }

    $counts.requested += 1
    try {
        $response = Invoke-NaverGeocoding $store.address $naverKeyId $naverSecret
        $addresses = @($response.addresses)
        if ($addresses.Count -eq 0) {
            $counts.noResult += 1
            $report.처리상태 = "NO_RESULT"
            $report.좌표검증상태 = "미확인"
            $report.검토메모 = "주소 검색 결과 없음"
            $reports.Add([pscustomobject]$report)
            continue
        }

        $expectedSido = Get-ExpectedSido $store.address
        $regionMatches = @($addresses | Where-Object {
            (Get-AddressElement $_ "SIDO") -eq $expectedSido
        })
        if ($regionMatches.Count -eq 0) {
            $counts.regionMismatch += 1
            $report.처리상태 = "REGION_MISMATCH"
            $report.좌표검증상태 = "재확인 필요"
            $report.검토메모 = "반환 주소의 시·도가 원본과 다름"
            $reports.Add([pscustomobject]$report)
            continue
        }

        $addressMatches = @($regionMatches | Where-Object { Test-AddressMatch $store.address $_ })
        if ($addressMatches.Count -eq 0) {
            $counts.addressMismatch += 1
            $report.처리상태 = "ADDRESS_MISMATCH"
            $report.좌표검증상태 = "재확인 필요"
            $report.검토메모 = "도로명·건물번호가 원본과 일치하지 않음"
            $reports.Add([pscustomobject]$report)
            continue
        }
        if ($addressMatches.Count -ne 1) {
            $counts.ambiguous += 1
            $report.처리상태 = "AMBIGUOUS"
            $report.좌표검증상태 = "재확인 필요"
            $report.검토메모 = "주소가 일치하는 결과가 여러 개"
            $reports.Add([pscustomobject]$report)
            continue
        }

        $match = $addressMatches[0]
        $latitude = ConvertTo-Double ([string]$match.y)
        $longitude = ConvertTo-Double ([string]$match.x)
        if ($null -eq $latitude -or $null -eq $longitude -or
            -not (Test-KoreaCoordinate $latitude $longitude)) {
            $counts.invalidCoordinate += 1
            $report.처리상태 = "INVALID_COORDINATE"
            $report.좌표검증상태 = "재확인 필요"
            $report.검토메모 = "대한민국 WGS84 범위를 벗어나거나 좌표 파싱 실패"
            $reports.Add([pscustomobject]$report)
            continue
        }

        $returnedAddress = if (-not [string]::IsNullOrWhiteSpace([string]$match.roadAddress)) {
            [string]$match.roadAddress
        } else { [string]$match.jibunAddress }
        $sourceUrl = "https://map.naver.com/p/search/$([Uri]::EscapeDataString(("$($store.name) $returnedAddress").Trim()))"
        $entry = New-CoordinateEntry $store.name $store.address $latitude $longitude `
            "네이버 Geocoding API" $sourceUrl $verifiedDate
        $coordinatesByKey[$key] = $entry
        $counts.matched += 1
        $report.처리상태 = "MATCHED"
        $report.좌표출처 = "네이버 Geocoding API"
        $report.좌표검증상태 = "확인 완료"
        $report.위도 = $latitude.ToString("0.########", [Globalization.CultureInfo]::InvariantCulture)
        $report.경도 = $longitude.ToString("0.########", [Globalization.CultureInfo]::InvariantCulture)
        $report.반환주소 = $returnedAddress
        $report.검토메모 = "시·도, 도로명과 건물번호가 일치하는 단일 결과"
        $reports.Add([pscustomobject]$report)
    } catch {
        $counts.apiError += 1
        $report.처리상태 = "API_ERROR"
        $report.좌표검증상태 = "미확인"
        $report.검토메모 = "API 호출 실패(비밀정보 보호를 위해 상세 메시지 미기록)"
        $reports.Add([pscustomobject]$report)
    }
    if ($DelayMilliseconds -gt 0) { Start-Sleep -Milliseconds $DelayMilliseconds }
}

$cacheEntries = @($coordinatesByKey.Values | Sort-Object name, address)
Save-Json $DestinationJson $cacheEntries
$reportFullPath = [System.IO.Path]::GetFullPath($ReportCsv)
$reportParent = Split-Path -Parent $reportFullPath
if ($reportParent) { [System.IO.Directory]::CreateDirectory($reportParent) | Out-Null }
$reports | Export-Csv -LiteralPath $reportFullPath -NoTypeInformation -Encoding utf8

$summary = [ordered]@{
    generatedAt = [DateTimeOffset]::Now.ToString("o")
    source = [ordered]@{
        provider = "병무청 나라사랑가게조회서비스 OpenAPI"
        endpoint = $mmaEndpoint
        fetchedAt = [DateTimeOffset]::Now.ToString("o")
        filter = "주소가 서울특별시·경기도·인천광역시로 시작하는 항목"
    }
    coordinatePolicy = [ordered]@{
        provider = "네이버 Geocoding API"
        automaticAcceptance = "원본 시·도, 도로명, 건물번호가 일치하는 단일 결과 및 대한민국 좌표 범위"
        unresolved = "좌표 캐시 제외 후 수동 검토"
        secretBundledInApp = $false
    }
    dryRun = [bool]$DryRun
    counts = $counts
    cacheEntries = $cacheEntries.Count
    destinationJson = $DestinationJson
    reportCsv = $ReportCsv
}
Save-Json $SummaryJson $summary

Write-Output (
    "MMA coordinate cache complete: total={0}, capital={1}, places={2}, cached={3}, review={4}" -f
        $counts.apiTotalCount,
        $counts.capitalAreaRows,
        $counts.uniqueCapitalAreaPlaces,
        $cacheEntries.Count,
        ($counts.noResult + $counts.ambiguous + $counts.regionMismatch +
            $counts.addressMismatch + $counts.invalidCoordinate + $counts.missingAddress +
            $counts.apiError + $counts.pendingDryRun)
)

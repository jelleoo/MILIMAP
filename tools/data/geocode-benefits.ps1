[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceCsv,
    [Parameter(Mandatory = $true)]
    [string]$DestinationCsv,
    [Parameter(Mandatory = $true)]
    [string]$ReportCsv,
    [Parameter(Mandatory = $true)]
    [string]$SummaryJson,
    [string]$LocalPropertiesPath = ".\apps\android\local.properties",
    [int]$DelayMilliseconds = 120,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$geocodingEndpoint = "https://maps.apigw.ntruss.com/map-geocode/v2"

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

function Add-ColumnIfMissing {
    param(
        [psobject]$Row,
        [string]$Name,
        [object]$Value = ""
    )

    if ($null -eq $Row.PSObject.Properties[$Name]) {
        $Row | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Get-TextValue {
    param(
        [psobject]$Row,
        [string[]]$Names
    )

    foreach ($name in $Names) {
        $property = $Row.PSObject.Properties[$name]
        if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            return ([string]$property.Value).Trim()
        }
    }
    return ""
}

function Get-QueryAddress {
    param([psobject]$Row)

    $address = Get-TextValue $Row @("소재지도로명주소", "소재지지번주소", "address")
    if ([string]::IsNullOrWhiteSpace($address)) { return "" }
    return ($address -replace '\s*,\s*.*$', '').Trim()
}

function Get-ExpectedSido {
    param(
        [psobject]$Row,
        [string]$Address
    )

    $sido = Get-TextValue $Row @("시도")
    if ([string]::IsNullOrWhiteSpace($sido)) {
        $sido = ($Address -split '\s+')[0]
    }
    switch -Regex ($sido) {
        '^서울' { return "서울특별시" }
        '^경기' { return "경기도" }
        '^인천' { return "인천광역시" }
        '^파주시$' { return "경기도" }
        default { return $sido }
    }
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

function ConvertTo-NormalizedAddressText {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    return (($Value.ToLowerInvariant()) -replace '[^\p{L}\p{Nd}]', '')
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

function Invoke-NaverGeocoding {
    param(
        [string]$Query,
        [string]$KeyId,
        [string]$Secret
    )

    $uri = "$geocodingEndpoint/geocode?query=$([Uri]::EscapeDataString($Query))&count=10"
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

function Test-KoreaCoordinate {
    param(
        [double]$Latitude,
        [double]$Longitude
    )

    return $Latitude -ge 33.0 -and $Latitude -le 39.5 -and
        $Longitude -ge 124.0 -and $Longitude -le 132.0
}

function Save-Json {
    param(
        [string]$Path,
        [object]$Value
    )

    $parent = Split-Path -Parent $Path
    if ($parent) { [System.IO.Directory]::CreateDirectory($parent) | Out-Null }
    $json = $Value | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

$sourcePath = (Resolve-Path -LiteralPath $SourceCsv).Path
$destinationPath = [System.IO.Path]::GetFullPath($DestinationCsv)
if ($sourcePath -eq $destinationPath) {
    throw "원본 CSV를 직접 덮어쓸 수 없습니다. DestinationCsv에 별도 경로를 지정해 주세요."
}
$rows = @(Import-Csv -LiteralPath $sourcePath -Encoding utf8)
if ($rows.Count -eq 0) { throw "입력 CSV에 데이터가 없습니다: $sourcePath" }

$properties = Read-LocalProperties $LocalPropertiesPath
$keyId = if ($env:NAVER_MAP_NCP_KEY_ID) { $env:NAVER_MAP_NCP_KEY_ID } else { $properties["NAVER_MAP_NCP_KEY_ID"] }
$secret = if ($env:NAVER_MAP_NCP_SECRET) { $env:NAVER_MAP_NCP_SECRET } else { $properties["NAVER_MAP_NCP_SECRET"] }
if (-not $DryRun -and ([string]::IsNullOrWhiteSpace($keyId) -or [string]::IsNullOrWhiteSpace($secret))) {
    throw "NAVER_MAP_NCP_KEY_ID와 NAVER_MAP_NCP_SECRET을 local.properties 또는 환경 변수에 설정해 주세요."
}

$report = [System.Collections.Generic.List[object]]::new()
$counts = [ordered]@{
    total = $rows.Count
    existingCoordinates = 0
    invalidExistingCoordinates = 0
    requested = 0
    matched = 0
    noResult = 0
    ambiguous = 0
    invalidRegion = 0
    addressMismatch = 0
    invalidCoordinate = 0
    missingAddress = 0
    failed = 0
    pendingDryRun = 0
}

for ($index = 0; $index -lt $rows.Count; $index += 1) {
    $row = $rows[$index]
    $hadInvalidExistingCoordinate = $false
    Add-ColumnIfMissing $row "좌표출처"
    Add-ColumnIfMissing $row "좌표출처URL"
    Add-ColumnIfMissing $row "좌표검증상태"

    $latitudeText = Get-TextValue $row @("위도", "latitude")
    $longitudeText = Get-TextValue $row @("경도", "longitude")
    if ($latitudeText -and $longitudeText) {
        $existingLatitude = 0.0
        $existingLongitude = 0.0
        $validExistingLatitude = [double]::TryParse(
            $latitudeText,
            [Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture,
            [ref]$existingLatitude
        )
        $validExistingLongitude = [double]::TryParse(
            $longitudeText,
            [Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture,
            [ref]$existingLongitude
        )
        if ($validExistingLatitude -and $validExistingLongitude -and
            (Test-KoreaCoordinate $existingLatitude $existingLongitude)) {
            $counts.existingCoordinates += 1
            if ([string]::IsNullOrWhiteSpace([string]$row.좌표출처)) {
                $row.좌표출처 = "기존 데이터(출처 미기록)"
            }
            if ([string]::IsNullOrWhiteSpace([string]$row.좌표검증상태)) {
                $row.좌표검증상태 = "재확인 필요"
            }
            continue
        }

        $counts.invalidExistingCoordinates += 1
        $hadInvalidExistingCoordinate = $true
        $row.위도 = ""
        $row.경도 = ""
        $row.좌표출처 = ""
        $row.좌표출처URL = ""
        $row.좌표검증상태 = "재확인 필요"
    }

    $name = Get-TextValue $row @("업소명", "name")
    $queryAddress = Get-QueryAddress $row
    $expectedSido = Get-ExpectedSido $row $queryAddress
    $baseReport = [ordered]@{
        rowNumber = $index + 2
        storeName = $name
        inputAddress = $queryAddress
        expectedSido = $expectedSido
        replacedInvalidCoordinate = $hadInvalidExistingCoordinate
        status = ""
        resultCount = 0
        matchedAddress = ""
        latitude = ""
        longitude = ""
        message = ""
    }

    if ([string]::IsNullOrWhiteSpace($queryAddress)) {
        $counts.missingAddress += 1
        $row.좌표검증상태 = "미확인"
        $baseReport.status = "MISSING_ADDRESS"
        $baseReport.message = "도로명주소와 지번주소가 모두 비어 있음"
        $report.Add([pscustomobject]$baseReport)
        continue
    }

    if ($DryRun) {
        $counts.pendingDryRun += 1
        $row.좌표검증상태 = "미확인"
        $baseReport.status = "PENDING_DRY_RUN"
        $baseReport.message = "인증 키를 사용하지 않는 사전 점검"
        $report.Add([pscustomobject]$baseReport)
        continue
    }

    $counts.requested += 1
    try {
        $response = Invoke-NaverGeocoding $queryAddress $keyId $secret
        $addresses = @($response.addresses)
        $baseReport.resultCount = $addresses.Count
        if ($addresses.Count -eq 0) {
            $counts.noResult += 1
            $row.좌표검증상태 = "미확인"
            $baseReport.status = "NO_RESULT"
            $baseReport.message = "주소 검색 결과 없음"
            $report.Add([pscustomobject]$baseReport)
            continue
        }

        $regionMatches = @($addresses | Where-Object {
            $returnedSido = Get-AddressElement $_ "SIDO"
            [string]::IsNullOrWhiteSpace($expectedSido) -or $returnedSido -eq $expectedSido
        })
        if ($regionMatches.Count -eq 0) {
            $counts.invalidRegion += 1
            $row.좌표검증상태 = "재확인 필요"
            $baseReport.status = "REGION_MISMATCH"
            $baseReport.message = "검색 결과의 시도가 입력 주소와 다름"
            $report.Add([pscustomobject]$baseReport)
            continue
        }

        $addressMatches = @($regionMatches | Where-Object {
            Test-AddressMatch $queryAddress $_
        })
        if ($addressMatches.Count -eq 0) {
            $counts.addressMismatch += 1
            $row.좌표검증상태 = "재확인 필요"
            $baseReport.status = "ADDRESS_MISMATCH"
            $baseReport.message = "반환 주소의 도로명·건물번호가 입력 주소와 일치하지 않음"
            $report.Add([pscustomobject]$baseReport)
            continue
        }
        if ($addressMatches.Count -ne 1) {
            $counts.ambiguous += 1
            $row.좌표검증상태 = "재확인 필요"
            $baseReport.status = "AMBIGUOUS"
            $baseReport.message = "시도와 주소가 일치하는 검색 결과가 여러 개"
            $report.Add([pscustomobject]$baseReport)
            continue
        }

        $match = $addressMatches[0]
        $latitude = 0.0
        $longitude = 0.0
        $validLatitude = [double]::TryParse(
            [string]$match.y,
            [Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture,
            [ref]$latitude
        )
        $validLongitude = [double]::TryParse(
            [string]$match.x,
            [Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture,
            [ref]$longitude
        )
        if (-not $validLatitude -or -not $validLongitude -or
            -not (Test-KoreaCoordinate $latitude $longitude)) {
            $counts.invalidCoordinate += 1
            $row.좌표검증상태 = "재확인 필요"
            $baseReport.status = "INVALID_COORDINATE"
            $baseReport.message = "대한민국 WGS84 범위를 벗어나거나 좌표 파싱 실패"
            $report.Add([pscustomobject]$baseReport)
            continue
        }

        $matchedAddress = if (-not [string]::IsNullOrWhiteSpace([string]$match.roadAddress)) {
            [string]$match.roadAddress
        } else {
            [string]$match.jibunAddress
        }
        $row.위도 = $latitude.ToString("0.########", [Globalization.CultureInfo]::InvariantCulture)
        $row.경도 = $longitude.ToString("0.########", [Globalization.CultureInfo]::InvariantCulture)
        $row.좌표출처 = "네이버 Geocoding API"
        $mapQuery = [Uri]::EscapeDataString(("$name $matchedAddress").Trim())
        $row.좌표출처URL = "https://map.naver.com/p/search/$mapQuery"
        $row.좌표검증상태 = "확인 완료"
        $counts.matched += 1
        $baseReport.status = "MATCHED"
        $baseReport.matchedAddress = $matchedAddress
        $baseReport.latitude = $row.위도
        $baseReport.longitude = $row.경도
        $baseReport.message = if ($hadInvalidExistingCoordinate) {
            "기존 비정상 좌표를 시도·주소 일치 단일 검색 결과로 교체"
        } else {
            "시도·주소 일치 단일 검색 결과"
        }
        $report.Add([pscustomobject]$baseReport)
    } catch {
        $counts.failed += 1
        $row.좌표검증상태 = "미확인"
        $baseReport.status = "API_ERROR"
        $baseReport.message = $_.Exception.Message
        $report.Add([pscustomobject]$baseReport)
    }
    if ($DelayMilliseconds -gt 0) { Start-Sleep -Milliseconds $DelayMilliseconds }
}

$destinationParent = Split-Path -Parent $DestinationCsv
if ($destinationParent) { [System.IO.Directory]::CreateDirectory($destinationParent) | Out-Null }
$reportParent = Split-Path -Parent $ReportCsv
if ($reportParent) { [System.IO.Directory]::CreateDirectory($reportParent) | Out-Null }
$rows | Export-Csv -LiteralPath $DestinationCsv -NoTypeInformation -Encoding utf8
$report | Export-Csv -LiteralPath $ReportCsv -NoTypeInformation -Encoding utf8

$summary = [ordered]@{
    generatedAt = [DateTimeOffset]::Now.ToString("o")
    dryRun = [bool]$DryRun
    sourceCsv = $sourcePath
    destinationCsv = [System.IO.Path]::GetFullPath($DestinationCsv)
    reportCsv = [System.IO.Path]::GetFullPath($ReportCsv)
    counts = $counts
}
Save-Json $SummaryJson $summary

Write-Output (
    "Geocoding complete: total={0}, existing={1}, requested={2}, matched={3}, pending={4}, review={5}" -f
        $counts.total,
        $counts.existingCoordinates,
        $counts.requested,
        $counts.matched,
        $counts.pendingDryRun,
        ($counts.noResult + $counts.ambiguous + $counts.invalidRegion +
            $counts.addressMismatch + $counts.invalidCoordinate +
            $counts.missingAddress + $counts.failed)
)

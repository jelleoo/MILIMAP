[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CanonicalCsv,
    [Parameter(Mandatory = $true)]
    [string]$SourceJson,
    [Parameter(Mandatory = $true)]
    [string]$DestinationJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RequiredValue {
    param($Row, [string]$Name)

    $property = $Row.PSObject.Properties[$Name]
    if ($null -eq $property -or [string]::IsNullOrWhiteSpace([string]$property.Value)) {
        throw "$Name 값이 비어 있습니다."
    }
    return ([string]$property.Value).Trim()
}

function Normalize-IdentityPart {
    param([string]$Value)

    $normalized = $Value.Trim()
    $normalized = $normalized.Replace('서울특별시', '서울').Replace('서울시', '서울')
    $normalized = $normalized.Replace('경기도', '경기').Replace('인천광역시', '인천')
    return ($normalized -replace '[^0-9A-Za-z가-힣]', '').ToLowerInvariant()
}

function Get-IdentityKey {
    param([string]$Name, [string]$Address)

    return "$(Normalize-IdentityPart $Name)|$(Normalize-IdentityPart $Address)"
}

function Get-CanonicalAddress {
    param($Row)

    $roadAddress = [string]($Row.PSObject.Properties['소재지도로명주소']?.Value)
    if (-not [string]::IsNullOrWhiteSpace($roadAddress)) { return $roadAddress.Trim() }
    return Get-RequiredValue $Row '소재지지번주소'
}

function Test-ValidCoordinatePair {
    param($Item)

    $latitude = $Item.latitude
    $longitude = $Item.longitude
    if ($null -eq $latitude -and $null -eq $longitude) { return }
    if ($null -eq $latitude -or $null -eq $longitude) {
        throw "시드 '$($Item.id)'의 위도와 경도는 함께 입력하거나 함께 비워야 합니다."
    }

    $parsedLatitude = 0.0
    $parsedLongitude = 0.0
    if (-not [double]::TryParse([string]$latitude, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$parsedLatitude) -or
        -not [double]::TryParse([string]$longitude, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$parsedLongitude) -or
        $parsedLatitude -lt -90.0 -or
        $parsedLatitude -gt 90.0 -or
        $parsedLongitude -lt -180.0 -or
        $parsedLongitude -gt 180.0) {
        throw "시드 '$($Item.id)'의 좌표 범위가 올바르지 않습니다."
    }
}

$canonicalRows = @(Import-Csv -LiteralPath $CanonicalCsv -Encoding utf8)
$canonicalByIdentity = @{}
foreach ($row in $canonicalRows) {
    $key = Get-IdentityKey (Get-RequiredValue $row '업소명') (Get-CanonicalAddress $row)
    if ($canonicalByIdentity.ContainsKey($key)) {
        throw "정본에 같은 업소명과 주소가 중복되어 있습니다: $key"
    }
    $canonicalByIdentity[$key] = $row
}

$sourceItems = @(Get-Content -Raw -Encoding utf8 -LiteralPath $SourceJson | ConvertFrom-Json)
$outputItems = @()
$clearedRecheckCount = 0
$clearedUnverifiedCount = 0

foreach ($sourceItem in $sourceItems) {
    $record = [ordered]@{}
    foreach ($property in $sourceItem.PSObject.Properties) {
        $record[$property.Name] = $property.Value
    }
    $item = [pscustomobject]$record
    $key = Get-IdentityKey (Get-RequiredValue $item 'name') (Get-RequiredValue $item 'address')
    if (-not $canonicalByIdentity.ContainsKey($key)) {
        throw "시드 '$($item.id)'에 대응하는 정본 업소를 찾지 못했습니다."
    }

    $coordinateStatus = Get-RequiredValue $canonicalByIdentity[$key] '좌표검증상태'
    switch ($coordinateStatus) {
        '확인 완료' { }
        '재확인 필요' {
            $item.latitude = $null
            $item.longitude = $null
            $clearedRecheckCount += 1
        }
        '미확인' {
            $item.latitude = $null
            $item.longitude = $null
            $clearedUnverifiedCount += 1
        }
        default {
            throw "시드 '$($item.id)'에 대응하는 정본의 좌표검증상태가 올바르지 않습니다: $coordinateStatus"
        }
    }
    Test-ValidCoordinatePair $item
    $outputItems += $item
}

$resolvedDestination = [IO.Path]::GetFullPath($DestinationJson)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolvedDestination) | Out-Null
$outputItems | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resolvedDestination -Encoding utf8
Write-Output ("정본 좌표 정책 적용: 전체 {0}건, 재확인 필요 좌표 제거 {1}건, 미확인 좌표 제거 {2}건" -f $outputItems.Count, $clearedRecheckCount, $clearedUnverifiedCount)

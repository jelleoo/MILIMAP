[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CanonicalCsv,
    [Parameter(Mandatory = $true)]
    [string]$CandidateCsv,
    [Parameter(Mandatory = $true)]
    [string]$CoordinateReviewCsv,
    [Parameter(Mandatory = $true)]
    [string]$SourceJson,
    [Parameter(Mandatory = $true)]
    [string]$DestinationJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RowValue {
    param($Row, [string]$Name)

    $property = $Row.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return '' }
    return ([string]$property.Value).Trim()
}

function Get-RequiredRowValue {
    param($Row, [string]$Name)

    $value = Get-RowValue $Row $Name
    if ([string]::IsNullOrWhiteSpace($value)) { throw "$Name 값이 비어 있습니다." }
    return $value
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

$canonicalEntries = @(
    Import-Csv -LiteralPath $CanonicalCsv -Encoding utf8 |
        ForEach-Object -Begin { $index = 0 } -Process {
            $index += 1
            [pscustomobject]@{ RowNumber = $index + 1; Row = $_ }
        }
)
$canonicalByRowNumber = @{}
foreach ($entry in $canonicalEntries) {
    $canonicalByRowNumber[$entry.RowNumber] = $entry.Row
}

$strictPoiCoordinateRows = [System.Collections.Generic.HashSet[int]]::new()
foreach ($review in @(Import-Csv -LiteralPath $CoordinateReviewCsv -Encoding utf8 | Where-Object {
    (Get-RowValue $_ '감사판정') -eq '확인 후보'
})) {
    $rowNumber = 0
    $rowNumberText = Get-RequiredRowValue $review '정본CSV행번호'
    if (-not [int]::TryParse($rowNumberText, [ref]$rowNumber) -or -not $canonicalByRowNumber.ContainsKey($rowNumber)) {
        throw "좌표 검토의 정본CSV행번호 '$rowNumberText'에 대응하는 정본 행을 찾지 못했습니다."
    }
    $canonical = $canonicalByRowNumber[$rowNumber]
    if ((Normalize-IdentityPart (Get-RequiredRowValue $canonical '업소명')) -ne (Normalize-IdentityPart (Get-RequiredRowValue $review '업소명')) -or
        (Normalize-IdentityPart (Get-RequiredRowValue $canonical '소재지도로명주소')) -ne (Normalize-IdentityPart (Get-RequiredRowValue $review '소재지도로명주소'))) {
        throw "좌표 검토 정본CSV행번호 $rowNumber의 업소명 또는 도로명주소가 정본과 일치하지 않습니다."
    }
    if (-not $strictPoiCoordinateRows.Add($rowNumber)) {
        throw "정본CSV행번호 $rowNumber에 확인 후보 좌표 검토가 여러 개 있습니다."
    }
}

$sourceItems = @(Get-Content -Raw -Encoding utf8 -LiteralPath $SourceJson | ConvertFrom-Json)
$sourceByIdentity = @{}
foreach ($sourceItem in $sourceItems) {
    $key = Get-IdentityKey (Get-RequiredRowValue $sourceItem 'name') (Get-RequiredRowValue $sourceItem 'address')
    if ($sourceByIdentity.ContainsKey($key)) { throw "출시 전 시드에 같은 업소명과 주소가 중복되어 있습니다: $key" }
    $sourceByIdentity[$key] = $sourceItem
}

$candidates = @(Import-Csv -LiteralPath $CandidateCsv -Encoding utf8)
$candidateRowNumbers = [System.Collections.Generic.HashSet[int]]::new()
$outputItems = [System.Collections.Generic.List[object]]::new()
foreach ($candidate in $candidates) {
    if ((Get-RequiredRowValue $candidate '혜택근거상태') -ne '공식 최신 근거 확인') {
        throw "출시 후보 '$((Get-RowValue $candidate '업소명'))'의 혜택근거상태가 공식 최신 근거 확인이 아닙니다."
    }

    $rowNumber = 0
    $rowNumberText = Get-RequiredRowValue $candidate '정본CSV행번호'
    if (-not [int]::TryParse($rowNumberText, [ref]$rowNumber) -or -not $canonicalByRowNumber.ContainsKey($rowNumber)) {
        throw "정본CSV행번호 '$rowNumberText'에 대응하는 정본 행을 찾지 못했습니다."
    }
    if (-not $candidateRowNumbers.Add($rowNumber)) {
        throw "정본CSV행번호 $rowNumber가 출시 후보에 중복되었습니다."
    }

    $canonical = $canonicalByRowNumber[$rowNumber]
    $canonicalAddress = Get-RequiredRowValue $canonical '소재지도로명주소'
    if ((Normalize-IdentityPart (Get-RequiredRowValue $canonical '업소명')) -ne (Normalize-IdentityPart (Get-RequiredRowValue $candidate '업소명')) -or
        (Normalize-IdentityPart $canonicalAddress) -ne (Normalize-IdentityPart (Get-RequiredRowValue $candidate '소재지도로명주소'))) {
        throw "정본CSV행번호 $rowNumber의 업소명 또는 도로명주소가 출시 후보와 일치하지 않습니다."
    }

    $key = Get-IdentityKey (Get-RequiredRowValue $candidate '업소명') (Get-RequiredRowValue $candidate '소재지도로명주소')
    if (-not $sourceByIdentity.ContainsKey($key)) {
        throw "출시 후보 '$((Get-RowValue $candidate '업소명'))'에 대응하는 기존 시드 업소를 찾지 못했습니다."
    }
    $sourceItem = $sourceByIdentity[$key]
    $record = [ordered]@{}
    foreach ($property in $sourceItem.PSObject.Properties) {
        $record[$property.Name] = $property.Value
    }
    $item = [pscustomobject]$record

    $item.benefitDescription = Get-RequiredRowValue $candidate '출시할인정보'
    $item.eligibleTarget = Get-RowValue $candidate '출시적용대상'
    $item.usageCondition = Get-RowValue $candidate '출시이용조건'
    $item.verificationMethod = Get-RequiredRowValue $candidate '출시인증방법'
    $item.sourceLabel = "$(Get-RequiredRowValue $candidate '출처유형') · 최신 확인"
    $item.sourceUrl = Get-RequiredRowValue $candidate '출처URL'
    $item.lastVerifiedAt = Get-RequiredRowValue $candidate '최근확인일'
    $item.status = 'ACTIVE'

    $coordinateStatus = Get-RequiredRowValue $canonical '좌표검증상태'
    if ($coordinateStatus -notin @('확인 완료', '재확인 필요', '미확인')) {
        throw "출시 후보 '$($item.id)'의 좌표검증상태가 올바르지 않습니다: $coordinateStatus"
    }
    $hasStrictPoiCoordinate = $coordinateStatus -eq '확인 완료' -and $strictPoiCoordinateRows.Contains($rowNumber)
    if (-not $hasStrictPoiCoordinate) {
        $item.latitude = $null
        $item.longitude = $null
    }
    Test-ValidCoordinatePair $item
    $outputItems.Add($item)
}

$resolvedDestination = [IO.Path]::GetFullPath($DestinationJson)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolvedDestination) | Out-Null
$outputItems | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resolvedDestination -Encoding utf8
Write-Output ("출시 혜택 시드 생성: {0}건" -f $outputItems.Count)

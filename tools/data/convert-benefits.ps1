[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceCsv,
    [Parameter(Mandatory = $true)]
    [string]$DestinationJson,
    [string]$DistrictReferenceJson
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

function Get-CanonicalAddress {
    param($Row)

    $roadAddress = Get-RowValue $Row '소재지도로명주소'
    if (-not [string]::IsNullOrWhiteSpace($roadAddress)) { return $roadAddress }
    return Get-RequiredRowValue $Row '소재지지번주소'
}

function Get-StableSeedId {
    param([string]$Name, [string]$Address)

    $identity = "$($Name.Trim())|$($Address.Trim())"
    $bytes = [Text.Encoding]::UTF8.GetBytes($identity)
    $hash = [Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    $hashText = -join ($hash | ForEach-Object { $_.ToString('x2') })
    return "seed-$($hashText.Substring(0, 12))"
}

function Convert-Category {
    param([string]$Value)

    switch -Regex ($Value) {
        '음식' { return '음식' }
        '카페' { return '카페' }
        '미용|뷰티' { return '미용·뷰티' }
        '병원|의료|안경' { return '병원' }
        '문화|여가' { return '문화·여가' }
        '숙박' { return '숙박' }
        default { return '기타' }
    }
}

function Convert-SourceType {
    param($Row)

    $sourceType = Get-RowValue $Row '출처유형'
    $sourceUrl = Get-RowValue $Row '출처URL'
    if ($sourceType -match '병무청|공공데이터' -or $sourceUrl -match 'mma\.go\.kr') { return 'MMA_API' }
    if ($sourceType -match '지자체|시청|군청|구청') { return 'LOCAL_GOV' }
    return 'PUBLIC_EVIDENCE'
}

function Convert-Status {
    param([string]$Value)

    switch ($Value) {
        '이용 가능' { return 'ACTIVE' }
        '확인 필요' { return 'NEEDS_VERIFICATION' }
        '종료' { return 'ENDED' }
        default { throw "혜택상태가 올바르지 않습니다: $Value" }
    }
}

function Convert-Coordinates {
    param($Row, [string]$Id)

    $latitudeText = Get-RowValue $Row '위도'
    $longitudeText = Get-RowValue $Row '경도'
    if ([string]::IsNullOrWhiteSpace($latitudeText) -and [string]::IsNullOrWhiteSpace($longitudeText)) {
        return [pscustomobject]@{ Latitude = $null; Longitude = $null }
    }
    if ([string]::IsNullOrWhiteSpace($latitudeText) -or [string]::IsNullOrWhiteSpace($longitudeText)) {
        throw "정본 '$Id'의 위도와 경도는 함께 입력하거나 함께 비워야 합니다."
    }

    $latitude = 0.0
    $longitude = 0.0
    $invariant = [Globalization.CultureInfo]::InvariantCulture
    if (-not [double]::TryParse($latitudeText, [Globalization.NumberStyles]::Float, $invariant, [ref]$latitude) -or
        -not [double]::TryParse($longitudeText, [Globalization.NumberStyles]::Float, $invariant, [ref]$longitude) -or
        $latitude -lt 33.0 -or $latitude -gt 39.0 -or $longitude -lt 124.0 -or $longitude -gt 132.0) {
        throw "정본 '$Id'의 좌표가 대한민국 WGS84 범위가 아닙니다."
    }
    return [pscustomobject]@{ Latitude = $latitude; Longitude = $longitude }
}

$districtById = @{}
if (-not [string]::IsNullOrWhiteSpace($DistrictReferenceJson)) {
    $referenceItems = @(Get-Content -Raw -Encoding utf8 -LiteralPath $DistrictReferenceJson | ConvertFrom-Json)
    foreach ($reference in $referenceItems) {
        $id = Get-RequiredRowValue $reference 'id'
        if ($districtById.ContainsKey($id)) { throw "세부 지역 참조 시드에 중복 ID가 있습니다: $id" }
        $districtById[$id] = Get-RowValue $reference 'district'
    }
}

$items = [System.Collections.Generic.List[object]]::new()
$seenIds = [System.Collections.Generic.HashSet[string]]::new()
foreach ($row in @(Import-Csv -LiteralPath $SourceCsv -Encoding utf8)) {
    $name = Get-RequiredRowValue $row '업소명'
    $address = Get-CanonicalAddress $row
    $id = Get-StableSeedId -Name $name -Address $address
    if (-not $seenIds.Add($id)) { throw "정본에 업소명과 주소가 같은 행이 중복되어 있습니다: $id" }

    $coordinates = Convert-Coordinates -Row $row -Id $id
    $district = Get-RequiredRowValue $row '시군구'
    if ($districtById.ContainsKey($id) -and -not [string]::IsNullOrWhiteSpace($districtById[$id])) {
        $district = $districtById[$id]
    }

    $items.Add([ordered]@{
        id = $id
        name = $name
        address = $address
        latitude = $coordinates.Latitude
        longitude = $coordinates.Longitude
        category = Convert-Category (Get-RequiredRowValue $row '업종명')
        benefitType = '할인·우대'
        benefitDescription = Get-RequiredRowValue $row '할인정보'
        phone = Get-RowValue $row '업소전화번호'
        eligibleTarget = Get-RequiredRowValue $row '적용대상'
        usageCondition = Get-RowValue $row '이용조건'
        verificationMethod = Get-RowValue $row '인증방법'
        sourceType = Convert-SourceType $row
        sourceLabel = Get-RequiredRowValue $row '출처유형'
        sourceUrl = Get-RequiredRowValue $row '출처URL'
        lastVerifiedAt = Get-RequiredRowValue $row '최근확인일'
        status = Convert-Status (Get-RequiredRowValue $row '혜택상태')
        district = $district
    })
}

$resolvedDestination = [IO.Path]::GetFullPath($DestinationJson)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolvedDestination) | Out-Null
[IO.File]::WriteAllText($resolvedDestination, ($items | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
Write-Output "정본 중간 시드 생성: $($items.Count)건"

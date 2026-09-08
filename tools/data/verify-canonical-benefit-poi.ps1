[CmdletBinding()]
param(
    [switch]$LibraryOnly,
    [string]$InputCsv,
    [string]$OutputCsv,
    [string]$SummaryJson,
    [string]$LocalPropertiesPath = '.\apps\android\local.properties',
    [int]$DelayMilliseconds = 120,
    [int]$StartRow = 0,
    [int]$MaxRows = 0,
    [switch]$OnlyExistingCoordinates
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
    param([hashtable]$Properties, [string]$Name)

    $environmentValue = [Environment]::GetEnvironmentVariable($Name)
    if (-not [string]::IsNullOrWhiteSpace($environmentValue)) { return $environmentValue.Trim() }
    if ($Properties.ContainsKey($Name)) { return ([string]$Properties[$Name]).Trim() }
    return ''
}

function Get-AuditConfiguration {
    param([hashtable]$Properties)

    return @{
        NAVER_API_HUB_CLIENT_ID = Get-ConfiguredValue -Properties $Properties -Name 'NAVER_API_HUB_CLIENT_ID'
        NAVER_API_HUB_CLIENT_SECRET = Get-ConfiguredValue -Properties $Properties -Name 'NAVER_API_HUB_CLIENT_SECRET'
    }
}

function Get-AuditEndpoints {
    return [pscustomobject][ordered]@{
        localSearch = 'https://naverapihub.apigw.ntruss.com/search/v1/local'
    }
}

function Invoke-NaverLocalSearch {
    param(
        [string]$Query,
        [string]$ClientId,
        [string]$ClientSecret,
        [scriptblock]$RequestInvoker
    )

    $uri = (Get-AuditEndpoints).localSearch + '?display=5&start=1&sort=random&format=json&query=' + [Uri]::EscapeDataString($Query)
    $headers = @{
        'X-NCP-APIGW-API-KEY-ID' = $ClientId
        'X-NCP-APIGW-API-KEY' = $ClientSecret
    }
    $response = if ($null -ne $RequestInvoker) {
        & $RequestInvoker $uri $headers
    } else {
        Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -ErrorAction Stop
    }
    return @($response.items)
}

function Normalize-PoiName {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    return ((($Value -replace '<[^>]+>', '') -replace '[\s,().·&-]', '')).ToLowerInvariant()
}

function Normalize-PoiAddress {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }

    $normalized = $Value.Trim()
    if ($normalized.StartsWith('서울특별시')) { $normalized = '서울' + $normalized.Substring('서울특별시'.Length) }
    elseif ($normalized.StartsWith('서울시')) { $normalized = '서울' + $normalized.Substring('서울시'.Length) }
    elseif ($normalized.StartsWith('경기도')) { $normalized = '경기' + $normalized.Substring('경기도'.Length) }
    elseif ($normalized.StartsWith('인천광역시')) { $normalized = '인천' + $normalized.Substring('인천광역시'.Length) }

    return (($normalized -replace '[\s,().-]', '')).ToLowerInvariant()
}

function Get-PreferredAddress {
    param($Row)

    if (-not [string]::IsNullOrWhiteSpace([string]$Row.소재지도로명주소)) {
        return ([string]$Row.소재지도로명주소).Trim()
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Row.소재지지번주소)) {
        return ([string]$Row.소재지지번주소).Trim()
    }
    return ''
}

function Get-PoiSearchQueries {
    param([string]$Name, [string]$Address)

    $storeName = $Name.Trim()
    $fullAddress = $Address.Trim()
    if (-not $storeName -or -not $fullAddress) { return @() }

    $queries = [System.Collections.Generic.List[object]]::new()
    $queries.Add([pscustomobject][ordered]@{
        Strategy = '전체 주소 검색'
        Query = "$storeName $fullAddress"
    })

    $commaIndex = $fullAddress.IndexOf(',')
    if ($commaIndex -gt 0) {
        $roadAddress = $fullAddress.Substring(0, $commaIndex).Trim()
        if ($roadAddress -and $roadAddress -ne $fullAddress) {
            $queries.Add([pscustomobject][ordered]@{
                Strategy = '도로명·건물번호 보조 검색'
                Query = "$storeName $roadAddress"
            })
        }
    }

    return @($queries)
}

function New-PoiDecision {
    param(
        [string]$Decision,
        [bool]$NameMatched,
        [bool]$AddressMatched,
        $SelectedCandidate,
        [string]$Reason,
        $ReferenceCandidate = $null
    )

    return [pscustomobject]@{
        Decision = $Decision
        NameMatched = $NameMatched
        AddressMatched = $AddressMatched
        SelectedCandidate = $SelectedCandidate
        ReferenceCandidate = $ReferenceCandidate
        Reason = $Reason
    }
}

function Get-PoiDecision {
    param(
        [Parameter(Mandatory)][string]$CanonicalName,
        [Parameter(Mandatory)][AllowEmptyString()][string]$CanonicalAddress,
        [object[]]$Candidates
    )

    $normalizedName = Normalize-PoiName $CanonicalName
    $normalizedAddress = Normalize-PoiAddress $CanonicalAddress
    if (-not $normalizedName -or -not $normalizedAddress) {
        return New-PoiDecision -Decision '미확인' -NameMatched $false -AddressMatched $false -SelectedCandidate $null -Reason '업소명 또는 주소가 비어 있습니다'
    }

    $candidates = @($Candidates)
    if ($candidates.Count -eq 0) {
        return New-PoiDecision -Decision '미확인' -NameMatched $false -AddressMatched $false -SelectedCandidate $null -Reason '지역 검색 결과가 없습니다'
    }

    $nameMatches = @($candidates | Where-Object { (Normalize-PoiName ([string]$_.title)) -eq $normalizedName })
    $exactMatches = @($nameMatches | Where-Object {
        (Normalize-PoiAddress ([string]$_.roadAddress)) -eq $normalizedAddress -or
        (Normalize-PoiAddress ([string]$_.address)) -eq $normalizedAddress
    })

    if ($exactMatches.Count -eq 1) {
        return New-PoiDecision -Decision '확인 후보' -NameMatched $true -AddressMatched $true -SelectedCandidate $exactMatches[0] -Reason '단일 상호·주소 일치 후보'
    }
    if ($exactMatches.Count -gt 1) {
        return New-PoiDecision -Decision '재확인 필요' -NameMatched $true -AddressMatched $true -SelectedCandidate $null -Reason '상호와 주소가 일치하는 후보가 복수입니다'
    }
    if ($nameMatches.Count -gt 0) {
        $referenceCandidate = if ($nameMatches.Count -eq 1) { $nameMatches[0] } else { $null }
        return New-PoiDecision -Decision '재확인 필요' -NameMatched $true -AddressMatched $false -SelectedCandidate $null -Reason '상호는 일치하지만 주소가 일치하지 않습니다' -ReferenceCandidate $referenceCandidate
    }
    return New-PoiDecision -Decision '미확인' -NameMatched $false -AddressMatched $false -SelectedCandidate $null -Reason '상호와 주소가 일치하는 후보가 없습니다'
}

function Test-KoreaCoordinate {
    param([string]$Latitude, [string]$Longitude)

    $latitudeValue = 0.0
    $longitudeValue = 0.0
    $culture = [Globalization.CultureInfo]::InvariantCulture
    if (-not [double]::TryParse($Latitude, [Globalization.NumberStyles]::Float, $culture, [ref]$latitudeValue)) { return $false }
    if (-not [double]::TryParse($Longitude, [Globalization.NumberStyles]::Float, $culture, [ref]$longitudeValue)) { return $false }
    return $latitudeValue -ge 33.0 -and $latitudeValue -le 39.5 -and $longitudeValue -ge 124.0 -and $longitudeValue -le 132.0
}

function New-NaverMapSearchUrl {
    param([string]$CanonicalName, [string]$InputAddress)

    return 'https://map.naver.com/p/search/' + [Uri]::EscapeDataString("$CanonicalName $InputAddress".Trim())
}

function New-AuditReportRow {
    param(
        [int]$RowNumber,
        [string]$CanonicalName,
        [string]$InputAddress,
        [string]$ExistingLatitude,
        [string]$ExistingLongitude,
        [string]$Query,
        [string]$InitialQuery,
        [string]$QueryStrategy,
        $PoiDecision,
        [string]$VerifiedAt,
        [int]$PoiCandidateCount = 0
    )

    $selectedPoi = $PoiDecision.SelectedCandidate
    $displayPoi = if ($null -ne $selectedPoi) { $selectedPoi } else { $PoiDecision.ReferenceCandidate }
    $decision = [string]$PoiDecision.Decision
    $reason = [string]$PoiDecision.Reason
    $recommendedStatus = if ($decision -in @('재확인 필요', '미확인')) { $decision } else { '미확인' }
    $proposedLatitude = ''
    $proposedLongitude = ''
    $coordinateSource = ''
    $coordinateSourceUrl = ''
    $apiHubCoordinateCandidateCount = 0

    if ($decision -eq '확인 후보') {
        $culture = [Globalization.CultureInfo]::InvariantCulture
        $mapX = 0.0
        $mapY = 0.0
        $coordinateParsed = [double]::TryParse([string]$selectedPoi.mapx, [Globalization.NumberStyles]::Float, $culture, [ref]$mapX) -and
            [double]::TryParse([string]$selectedPoi.mapy, [Globalization.NumberStyles]::Float, $culture, [ref]$mapY)
        if (-not $coordinateParsed) {
            $decision = '재확인 필요'
            $recommendedStatus = '재확인 필요'
            $reason = 'POI는 일치하지만 API HUB 좌표 형식을 읽을 수 없습니다'
        } else {
            $apiHubCoordinateCandidateCount = 1
            $candidateLatitude = ($mapY / 10000000.0).ToString('0.#######', $culture)
            $candidateLongitude = ($mapX / 10000000.0).ToString('0.#######', $culture)
            if (-not (Test-KoreaCoordinate -Latitude $candidateLatitude -Longitude $candidateLongitude)) {
                $decision = '재확인 필요'
                $recommendedStatus = '재확인 필요'
                $reason = 'POI는 일치하지만 API HUB 좌표가 대한민국 범위를 벗어납니다'
            } else {
                $proposedLatitude = $candidateLatitude
                $proposedLongitude = $candidateLongitude
                $coordinateSource = '네이버 지도'
                $coordinateSourceUrl = New-NaverMapSearchUrl -CanonicalName $CanonicalName -InputAddress $InputAddress
                $recommendedStatus = '확인 완료'
            }
        }
    }

    [pscustomobject][ordered]@{
        정본행번호 = $RowNumber
        업소명 = $CanonicalName
        입력주소 = $InputAddress
        기존위도 = $ExistingLatitude
        기존경도 = $ExistingLongitude
        최초POI조회어 = $InitialQuery
        POI조회어 = $Query
        POI조회방식 = $QueryStrategy
        POI후보수 = $PoiCandidateCount
        POI상호 = if ($null -eq $displayPoi) { '' } else { [string]$displayPoi.title }
        POI도로명주소 = if ($null -eq $displayPoi) { '' } else { [string]$displayPoi.roadAddress }
        POI지번주소 = if ($null -eq $displayPoi) { '' } else { [string]$displayPoi.address }
        POI상호일치 = [bool]$PoiDecision.NameMatched
        POI주소일치 = [bool]$PoiDecision.AddressMatched
        APIHUB좌표후보수 = $apiHubCoordinateCandidateCount
        제안위도 = $proposedLatitude
        제안경도 = $proposedLongitude
        좌표출처 = $coordinateSource
        좌표출처URL = $coordinateSourceUrl
        권장좌표검증상태 = $recommendedStatus
        판정 = $decision
        검토사유 = $reason
        확인일 = $VerifiedAt
    }
}

function Invoke-PoiCoordinateAudit {
    param(
        [object[]]$Rows,
        [string]$SearchClientId,
        [string]$SearchClientSecret,
        [string]$VerifiedAt,
        [scriptblock]$LocalSearchInvoker,
        [int]$RowNumberOffset = 0,
        [int]$DelayMilliseconds = 0
    )

    $reportRows = [System.Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $Rows.Count; $index += 1) {
        $row = $Rows[$index]
        $name = ([string]$row.업소명).Trim()
        $address = Get-PreferredAddress $row
        $searchQueries = @(Get-PoiSearchQueries -Name $name -Address $address)
        $initialQuery = if ($searchQueries.Count -gt 0) { [string]$searchQueries[0].Query } else { '' }
        $query = $initialQuery
        $queryStrategy = if ($searchQueries.Count -gt 0) { [string]$searchQueries[0].Strategy } else { '' }
        $candidates = @()
        $decision = $null

        if ($searchQueries.Count -eq 0) {
            $decision = New-PoiDecision -Decision '미확인' -NameMatched $false -AddressMatched $false -SelectedCandidate $null -Reason '업소명 또는 주소가 비어 있습니다'
        } else {
            try {
                foreach ($searchQuery in $searchQueries) {
                    $query = [string]$searchQuery.Query
                    $queryStrategy = [string]$searchQuery.Strategy
                    $candidates = @(Invoke-NaverLocalSearch -Query $query -ClientId $SearchClientId -ClientSecret $SearchClientSecret -RequestInvoker $LocalSearchInvoker)
                    if ($candidates.Count -gt 0) { break }
                }
                $decision = Get-PoiDecision -CanonicalName $name -CanonicalAddress $address -Candidates $candidates
            } catch {
                $decision = New-PoiDecision -Decision 'API 오류' -NameMatched $false -AddressMatched $false -SelectedCandidate $null -Reason 'API HUB 지역 검색 요청 실패'
            }
        }

        $reportRows.Add((New-AuditReportRow -RowNumber ($RowNumberOffset + $index + 2) -CanonicalName $name -InputAddress $address -ExistingLatitude ([string]$row.위도) -ExistingLongitude ([string]$row.경도) -Query $query -InitialQuery $initialQuery -QueryStrategy $queryStrategy -PoiDecision $decision -VerifiedAt $VerifiedAt -PoiCandidateCount $candidates.Count))
        if ($DelayMilliseconds -gt 0 -and $index -lt ($Rows.Count - 1)) {
            Start-Sleep -Milliseconds $DelayMilliseconds
        }
    }
    return @($reportRows)
}

if ($LibraryOnly) { return }

if ([string]::IsNullOrWhiteSpace($InputCsv) -or [string]::IsNullOrWhiteSpace($OutputCsv) -or [string]::IsNullOrWhiteSpace($SummaryJson)) {
    throw 'InputCsv, OutputCsv, SummaryJson을 모두 지정해 주세요.'
}
if ($DelayMilliseconds -lt 0 -or $StartRow -lt 0 -or $MaxRows -lt 0) {
    throw 'DelayMilliseconds, StartRow, MaxRows는 0 이상이어야 합니다.'
}

$properties = Read-LocalProperties -Path $LocalPropertiesPath
$configuration = Get-AuditConfiguration -Properties $properties
$missing = @($configuration.Keys | Where-Object { [string]::IsNullOrWhiteSpace([string]$configuration[$_]) } | Sort-Object)
if ($missing.Count -gt 0) {
    throw ('다음 환경 변수 또는 local.properties 값이 필요합니다: ' + ($missing -join ', '))
}

$inputRows = @(Import-Csv -LiteralPath $InputCsv -Encoding utf8)
$auditRows = if ($OnlyExistingCoordinates) {
    @($inputRows | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.위도) -and -not [string]::IsNullOrWhiteSpace([string]$_.경도) })
} else {
    $inputRows
}
if ($StartRow -gt 0) { $auditRows = @($auditRows | Select-Object -Skip $StartRow) }
if ($MaxRows -gt 0) { $auditRows = @($auditRows | Select-Object -First $MaxRows) }

$verifiedAt = [DateTimeOffset]::Now.ToString('yyyy-MM-dd')
$reportRows = Invoke-PoiCoordinateAudit -Rows $auditRows -SearchClientId $configuration.NAVER_API_HUB_CLIENT_ID -SearchClientSecret $configuration.NAVER_API_HUB_CLIENT_SECRET -VerifiedAt $verifiedAt -RowNumberOffset $StartRow -DelayMilliseconds $DelayMilliseconds

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputCsv) | Out-Null
$reportRows | Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -Encoding utf8
$summary = [ordered]@{
    generatedAt = [DateTimeOffset]::Now.ToString('o')
    inputRows = $inputRows.Count
    auditedRows = $reportRows.Count
    onlyExistingCoordinates = [bool]$OnlyExistingCoordinates
    startRow = $StartRow
    maxRows = $MaxRows
    endpoints = Get-AuditEndpoints
    decisions = @($reportRows | Group-Object 판정 | Sort-Object Name | ForEach-Object { [ordered]@{ decision = $_.Name; count = $_.Count } })
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $SummaryJson) | Out-Null
$summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $SummaryJson -Encoding utf8
Write-Output ("감사 완료: 입력 {0}건, 감사 {1}건" -f $inputRows.Count, $reportRows.Count)

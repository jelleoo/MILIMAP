[CmdletBinding()]
param(
    [switch]$LibraryOnly,
    [string]$CanonicalCsv,
    [string]$OutputCsv,
    [string]$SummaryJson,
    [string[]]$SourceUrls = @(
        'https://www.paju.go.kr/user/soldier/BD_discountStoreList.do?q_ctgCd=1001',
        'https://www.paju.go.kr/user/soldier/BD_discountStoreList.do?q_ctgCd=1002',
        'https://www.paju.go.kr/user/soldier/BD_discountStoreList.do?q_ctgCd=1004'
    ),
    [int]$TimeoutSeconds = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertFrom-PajuHtmlText {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $withoutBreaks = $Value -replace '(?is)<br\s*/?>', ' '
    $withoutTags = $withoutBreaks -replace '(?is)<[^>]+>', ' '
    $decoded = [Net.WebUtility]::HtmlDecode($withoutTags)
    return (($decoded -replace '\s+', ' ').Trim())
}

function Get-PajuRowValue {
    param($Row, [string]$Name)

    $property = $Row.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return '' }
    return ([string]$property.Value).Trim()
}

function Normalize-PajuName {
    param([string]$Value)

    return ((ConvertFrom-PajuHtmlText $Value) -replace '[\s,().·&-]', '').ToLowerInvariant()
}

function Normalize-PajuAddress {
    param([string]$Value)

    $normalized = ConvertFrom-PajuHtmlText $Value
    $normalized = $normalized -replace '경기도', ''
    $normalized = $normalized -replace '파주시', ''
    $normalized = $normalized -replace '\([^)]*\)', ''
    return (($normalized -replace '[\s,.-]', '')).ToLowerInvariant()
}

function Normalize-PajuPhone {
    param([string]$Value)

    return ((ConvertFrom-PajuHtmlText $Value) -replace '\D', '')
}

function ConvertFrom-PajuOfficialListHtml {
    param(
        [Parameter(Mandatory = $true)][string]$Html,
        [Parameter(Mandatory = $true)][string]$SourceUrl
    )

    $rows = [System.Collections.Generic.List[object]]::new()
    $tableMatches = [regex]::Matches($Html, '(?is)<table\b[^>]*>(?<table>.*?)</table>')
    foreach ($tableMatch in $tableMatches) {
        $tableHtml = $tableMatch.Groups['table'].Value
        $captionMatch = [regex]::Match($tableHtml, '(?is)<caption\b[^>]*>(?<caption>.*?)</caption>')
        $caption = ConvertFrom-PajuHtmlText $captionMatch.Groups['caption'].Value
        if ($caption -notmatch '군장병\s*할인업소') { continue }

        $headerMatch = [regex]::Match($tableHtml, '(?is)<thead\b[^>]*>.*?<tr\b[^>]*>(?<header>.*?)</tr>.*?</thead>')
        if (-not $headerMatch.Success) { continue }
        $headers = @([regex]::Matches($headerMatch.Groups['header'].Value, '(?is)<th\b[^>]*>(?<cell>.*?)</th>') | ForEach-Object {
            ConvertFrom-PajuHtmlText $_.Groups['cell'].Value
        })
        $nameIndex = -1
        for ($index = 0; $index -lt $headers.Count; $index += 1) {
            if ($headers[$index] -match '^업소명') { $nameIndex = $index; break }
        }
        $addressIndex = [Array]::IndexOf([string[]]$headers, '소재지')
        $phoneIndex = [Array]::IndexOf([string[]]$headers, '전화번호')
        if ($nameIndex -lt 0 -or $addressIndex -lt 0 -or $phoneIndex -lt 0) { continue }

        $bodyMatch = [regex]::Match($tableHtml, '(?is)<tbody\b[^>]*>(?<body>.*?)</tbody>')
        if (-not $bodyMatch.Success) { continue }
        $rowMatches = [regex]::Matches($bodyMatch.Groups['body'].Value, '(?is)<tr\b[^>]*>(?<row>.*?)</tr>')
        foreach ($rowMatch in $rowMatches) {
            $cells = @([regex]::Matches($rowMatch.Groups['row'].Value, '(?is)<td\b[^>]*>(?<cell>.*?)</td>') | ForEach-Object {
                ConvertFrom-PajuHtmlText $_.Groups['cell'].Value
            })
            if ($cells.Count -le [Math]::Max($nameIndex, [Math]::Max($addressIndex, $phoneIndex))) { continue }
            if ([string]::IsNullOrWhiteSpace($cells[$nameIndex])) { continue }
            $rows.Add([pscustomobject][ordered]@{
                Name = $cells[$nameIndex]
                Address = $cells[$addressIndex]
                Phone = $cells[$phoneIndex]
                SourceTable = $caption
                SourceUrl = $SourceUrl
            })
        }
    }
    return @($rows)
}

function Compare-PajuBenefits {
    param(
        [Parameter(Mandatory = $true)][object[]]$CanonicalRows,
        [Parameter(Mandatory = $true)][object[]]$OfficialRows
    )

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($canonical in $CanonicalRows) {
        $canonicalName = Get-PajuRowValue $canonical '업소명'
        $canonicalAddress = Get-PajuRowValue $canonical '소재지도로명주소'
        $canonicalPhone = Get-PajuRowValue $canonical '업소전화번호'
        $canonicalDiscount = Get-PajuRowValue $canonical '할인정보'
        $nameMatches = @($OfficialRows | Where-Object { (Normalize-PajuName $_.Name) -eq (Normalize-PajuName $canonicalName) })
        $addressMatches = @($nameMatches | Where-Object { (Normalize-PajuAddress $_.Address) -eq (Normalize-PajuAddress $canonicalAddress) })

        $official = $null
        $nameAddressMatched = $false
        $phoneMatched = $false
        $decision = ''
        if ($addressMatches.Count -eq 1) {
            $official = $addressMatches[0]
            $nameAddressMatched = $true
            $phoneMatched = (Normalize-PajuPhone $official.Phone) -eq (Normalize-PajuPhone $canonicalPhone) -and -not [string]::IsNullOrWhiteSpace((Normalize-PajuPhone $canonicalPhone))
            $decision = if ($phoneMatched) { '공식 참여업소 일치 후보' } else { '상세정보 재확인 필요' }
        } elseif ($addressMatches.Count -gt 1) {
            $decision = '복수 공식 후보'
        } elseif ($nameMatches.Count -gt 0) {
            $decision = '주소 재확인 필요'
        } else {
            $decision = '공식목록 미발견'
        }

        $results.Add([pscustomobject][ordered]@{
            정본CSV행번호 = Get-PajuRowValue $canonical '정본CSV행번호'
            업소명 = $canonicalName
            소재지도로명주소 = $canonicalAddress
            기존전화번호 = $canonicalPhone
            기존할인정보 = $canonicalDiscount
            공식업소명 = if ($null -ne $official) { $official.Name } else { '' }
            공식주소 = if ($null -ne $official) { $official.Address } else { '' }
            공식전화번호 = if ($null -ne $official) { $official.Phone } else { '' }
            공식출처URL = if ($null -ne $official) { $official.SourceUrl } else { '' }
            상호주소일치 = $nameAddressMatched
            전화일치 = $phoneMatched
            혜택상세검증 = if ($nameAddressMatched) { '참여 목록은 일치하나 개별 할인 조건 미기재' } else { '미확인' }
            판정 = $decision
            검토결정 = '미검토'
            정본반영여부 = '아니오'
        })
    }
    return @($results)
}

if ($LibraryOnly) { return }

if ([string]::IsNullOrWhiteSpace($CanonicalCsv) -or [string]::IsNullOrWhiteSpace($OutputCsv) -or [string]::IsNullOrWhiteSpace($SummaryJson)) {
    throw 'CanonicalCsv, OutputCsv, SummaryJson을 모두 지정해 주세요.'
}
if ($TimeoutSeconds -le 0) { throw 'TimeoutSeconds는 1 이상이어야 합니다.' }

$allCanonicalRows = @(Import-Csv -LiteralPath $CanonicalCsv -Encoding utf8)
$canonicalRows = @(
    $allCanonicalRows | ForEach-Object -Begin { $index = 0 } -Process {
        $index += 1
        if ($SourceUrls -contains $_.출처URL) {
            $_ | Add-Member -NotePropertyName 정본CSV행번호 -NotePropertyValue ($index + 1) -Force
            $_
        }
    }
)
if ($canonicalRows.Count -eq 0) { throw '지정한 파주 공식 출처 URL을 사용하는 정본 행이 없습니다.' }

$officialRows = [System.Collections.Generic.List[object]]::new()
foreach ($sourceUrl in $SourceUrls) {
    $response = Invoke-WebRequest -Uri $sourceUrl -MaximumRedirection 3 -TimeoutSec $TimeoutSeconds
    if ([int]$response.StatusCode -ne 200) { throw "파주 공식 페이지 응답 코드가 200이 아닙니다: $($response.StatusCode)" }
    foreach ($officialRow in @(ConvertFrom-PajuOfficialListHtml -Html $response.Content -SourceUrl $sourceUrl)) {
        $officialRows.Add($officialRow)
    }
}
if ($officialRows.Count -eq 0) { throw '파주 공식 페이지에서 할인업소 표를 읽지 못했습니다.' }
$comparisonRows = @(Compare-PajuBenefits -CanonicalRows $canonicalRows -OfficialRows @($officialRows))

$resolvedOutputCsv = [IO.Path]::GetFullPath($OutputCsv)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolvedOutputCsv) | Out-Null
$comparisonRows | Export-Csv -LiteralPath $resolvedOutputCsv -NoTypeInformation -Encoding utf8

$summary = [ordered]@{
    generatedAt = [DateTimeOffset]::Now.ToString('o')
    sourceUrls = $SourceUrls
    officialRows = $officialRows.Count
    canonicalRows = $canonicalRows.Count
    decisions = @($comparisonRows | Group-Object 판정 | Sort-Object Name | ForEach-Object { [ordered]@{ decision = $_.Name; count = $_.Count } })
    individualDiscountConditionsInOfficialList = $false
    automaticCanonicalMutation = $false
}
$resolvedSummaryJson = [IO.Path]::GetFullPath($SummaryJson)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolvedSummaryJson) | Out-Null
$summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $resolvedSummaryJson -Encoding utf8
Write-Output ("파주 공식 목록 비교 완료: 정본 {0}건, 공식 목록 {1}건" -f $canonicalRows.Count, $officialRows.Count)

[CmdletBinding()]
param(
    [switch]$LibraryOnly,
    [string]$CanonicalCsv,
    [string]$OutputCsv,
    [string]$SummaryJson,
    [string]$SourceUrl = 'https://www.ddc.go.kr/ddc/contents.do?key=1570',
    [int]$TimeoutSeconds = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertFrom-DdcHtmlText {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $withoutBreaks = $Value -replace '(?is)<br\s*/?>', ' '
    $withoutTags = $withoutBreaks -replace '(?is)<[^>]+>', ' '
    $decoded = [Net.WebUtility]::HtmlDecode($withoutTags)
    return (($decoded -replace '\s+', ' ').Trim())
}

function Get-DdcRowValue {
    param($Row, [string]$Name)

    $property = $Row.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return '' }
    return ([string]$property.Value).Trim()
}

function Normalize-DdcName {
    param([string]$Value)

    return ((ConvertFrom-DdcHtmlText $Value) -replace '[\s,().·&-]', '').ToLowerInvariant()
}

function Normalize-DdcAddress {
    param([string]$Value)

    $normalized = ConvertFrom-DdcHtmlText $Value
    $normalized = $normalized -replace '경기도', ''
    $normalized = $normalized -replace '동두천시', ''
    $normalized = $normalized -replace '\([^)]*\)', ''
    return (($normalized -replace '[\s,.-]', '')).ToLowerInvariant()
}

function Normalize-DdcPhone {
    param([string]$Value)

    return ((ConvertFrom-DdcHtmlText $Value) -replace '\D', '')
}

function Normalize-DdcDiscount {
    param([string]$Value)

    $normalized = ConvertFrom-DdcHtmlText $Value
    $normalized = $normalized -replace '할인', ''
    return (($normalized -replace '[\s,.-]', '')).ToLowerInvariant()
}

function ConvertFrom-DdcOfficialListHtml {
    param([Parameter(Mandatory = $true)][string]$Html)

    $rows = [System.Collections.Generic.List[object]]::new()
    $tableMatches = [regex]::Matches($Html, '(?is)<table\b[^>]*>(?<table>.*?)</table>')
    foreach ($tableMatch in $tableMatches) {
        $tableHtml = $tableMatch.Groups['table'].Value
        $captionMatch = [regex]::Match($tableHtml, '(?is)<caption\b[^>]*>(?<caption>.*?)</caption>')
        $caption = ConvertFrom-DdcHtmlText $captionMatch.Groups['caption'].Value
        if ($caption -notmatch '군\s*장병\s*할인업소') { continue }

        $headerMatch = [regex]::Match($tableHtml, '(?is)<thead\b[^>]*>.*?<tr\b[^>]*>(?<header>.*?)</tr>.*?</thead>')
        if (-not $headerMatch.Success) { continue }
        $headers = @([regex]::Matches($headerMatch.Groups['header'].Value, '(?is)<th\b[^>]*>(?<cell>.*?)</th>') | ForEach-Object {
            ConvertFrom-DdcHtmlText $_.Groups['cell'].Value
        })
        $nameIndex = [Array]::IndexOf([string[]]$headers, '업소명')
        $addressIndex = [Array]::IndexOf([string[]]$headers, '주소')
        $phoneIndex = [Array]::IndexOf([string[]]$headers, '전화번호')
        $discountIndex = [Array]::IndexOf([string[]]$headers, '할인')
        if ($nameIndex -lt 0 -or $addressIndex -lt 0 -or $phoneIndex -lt 0 -or $discountIndex -lt 0) { continue }

        $bodyMatch = [regex]::Match($tableHtml, '(?is)<tbody\b[^>]*>(?<body>.*?)</tbody>')
        if (-not $bodyMatch.Success) { continue }
        $rowMatches = [regex]::Matches($bodyMatch.Groups['body'].Value, '(?is)<tr\b[^>]*>(?<row>.*?)</tr>')
        foreach ($rowMatch in $rowMatches) {
            $cells = @([regex]::Matches($rowMatch.Groups['row'].Value, '(?is)<td\b[^>]*>(?<cell>.*?)</td>') | ForEach-Object {
                ConvertFrom-DdcHtmlText $_.Groups['cell'].Value
            })
            if ($cells.Count -le [Math]::Max([Math]::Max($nameIndex, $addressIndex), [Math]::Max($phoneIndex, $discountIndex))) { continue }
            if ([string]::IsNullOrWhiteSpace($cells[$nameIndex])) { continue }
            $rows.Add([pscustomobject][ordered]@{
                Name = $cells[$nameIndex]
                Address = $cells[$addressIndex]
                Phone = $cells[$phoneIndex]
                Discount = $cells[$discountIndex]
                SourceTable = $caption
            })
        }
    }
    return @($rows)
}

function Compare-DdcBenefits {
    param(
        [Parameter(Mandatory = $true)][object[]]$CanonicalRows,
        [Parameter(Mandatory = $true)][object[]]$OfficialRows
    )

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($canonical in $CanonicalRows) {
        $canonicalName = Get-DdcRowValue $canonical '업소명'
        $canonicalAddress = Get-DdcRowValue $canonical '소재지도로명주소'
        $canonicalPhone = Get-DdcRowValue $canonical '업소전화번호'
        $canonicalDiscount = Get-DdcRowValue $canonical '할인정보'
        $nameMatches = @($OfficialRows | Where-Object { (Normalize-DdcName $_.Name) -eq (Normalize-DdcName $canonicalName) })
        $addressMatches = @($nameMatches | Where-Object { (Normalize-DdcAddress $_.Address) -eq (Normalize-DdcAddress $canonicalAddress) })

        $official = $null
        $decision = ''
        $nameAddressMatched = $false
        $phoneMatched = $false
        $discountMatched = $false
        if ($addressMatches.Count -eq 1) {
            $official = $addressMatches[0]
            $nameAddressMatched = $true
            $phoneMatched = (Normalize-DdcPhone $official.Phone) -eq (Normalize-DdcPhone $canonicalPhone) -and -not [string]::IsNullOrWhiteSpace((Normalize-DdcPhone $canonicalPhone))
            $discountMatched = (Normalize-DdcDiscount $official.Discount) -eq (Normalize-DdcDiscount $canonicalDiscount) -and -not [string]::IsNullOrWhiteSpace((Normalize-DdcDiscount $canonicalDiscount))
            $decision = if ($phoneMatched -and $discountMatched) { '현재 공식 목록 일치 후보' } else { '상세정보 재확인 필요' }
        } elseif ($addressMatches.Count -gt 1) {
            $decision = '복수 공식 후보'
        } elseif ($nameMatches.Count -gt 0) {
            $decision = '주소 재확인 필요'
        } else {
            $decision = '공식목록 미발견'
        }

        $results.Add([pscustomobject][ordered]@{
            정본CSV행번호 = Get-DdcRowValue $canonical '정본CSV행번호'
            업소명 = $canonicalName
            소재지도로명주소 = $canonicalAddress
            기존전화번호 = $canonicalPhone
            기존할인정보 = $canonicalDiscount
            공식업소명 = if ($null -ne $official) { $official.Name } else { '' }
            공식주소 = if ($null -ne $official) { $official.Address } else { '' }
            공식전화번호 = if ($null -ne $official) { $official.Phone } else { '' }
            공식할인정보 = if ($null -ne $official) { $official.Discount } else { '' }
            상호주소일치 = $nameAddressMatched
            전화일치 = $phoneMatched
            할인일치 = $discountMatched
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
        if ($_.출처URL -eq $SourceUrl) {
            $_ | Add-Member -NotePropertyName 정본CSV행번호 -NotePropertyValue ($index + 1) -Force
            $_
        }
    }
)
if ($canonicalRows.Count -eq 0) { throw '지정한 동두천 공식 출처 URL을 사용하는 정본 행이 없습니다.' }

$response = Invoke-WebRequest -Uri $SourceUrl -MaximumRedirection 3 -TimeoutSec $TimeoutSeconds
if ([int]$response.StatusCode -ne 200) { throw "동두천 공식 페이지 응답 코드가 200이 아닙니다: $($response.StatusCode)" }
$officialRows = @(ConvertFrom-DdcOfficialListHtml -Html $response.Content)
if ($officialRows.Count -eq 0) { throw '동두천 공식 페이지에서 할인업소 표를 읽지 못했습니다.' }
$comparisonRows = @(Compare-DdcBenefits -CanonicalRows $canonicalRows -OfficialRows $officialRows)

$resolvedOutputCsv = [IO.Path]::GetFullPath($OutputCsv)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolvedOutputCsv) | Out-Null
$comparisonRows | Export-Csv -LiteralPath $resolvedOutputCsv -NoTypeInformation -Encoding utf8

$summary = [ordered]@{
    generatedAt = [DateTimeOffset]::Now.ToString('o')
    sourceUrl = $SourceUrl
    officialRows = $officialRows.Count
    canonicalRows = $canonicalRows.Count
    decisions = @($comparisonRows | Group-Object 판정 | Sort-Object Name | ForEach-Object { [ordered]@{ decision = $_.Name; count = $_.Count } })
    automaticCanonicalMutation = $false
}
$resolvedSummaryJson = [IO.Path]::GetFullPath($SummaryJson)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolvedSummaryJson) | Out-Null
$summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $resolvedSummaryJson -Encoding utf8
Write-Output ("동두천 공식 목록 비교 완료: 정본 {0}건, 공식 목록 {1}건" -f $canonicalRows.Count, $officialRows.Count)

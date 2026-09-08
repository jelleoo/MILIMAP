[CmdletBinding()]
param(
    [switch]$LibraryOnly,
    [string]$CanonicalCsv,
    [string]$OfficialCsv,
    [string]$OutputCsv,
    [string]$SummaryJson,
    [string]$LegacySourceUrl = 'https://www.yangju.go.kr/www/selectBbsNttView.do?bbsNo=13&key=202&nttNo=198019',
    [string]$CurrentSourceUrl = 'https://www.yangju.go.kr/health/selectBbsNttView.do?key=2716&bbsNo=81&nttNo=206761'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-YangjuRowValue {
    param($Row, [string]$Name)

    $property = $Row.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return '' }
    return ([string]$property.Value).Trim()
}

function Normalize-YangjuName {
    param([string]$Value)

    $normalized = Get-YangjuRowValue ([pscustomobject]@{ value = $Value }) 'value'
    $normalized = $normalized -replace '\([^)]*\)', ''
    return (($normalized -replace '[\s,().·&-]', '')).ToLowerInvariant()
}

function Normalize-YangjuAddress {
    param([string]$Value)

    $normalized = Get-YangjuRowValue ([pscustomobject]@{ value = $Value }) 'value'
    $normalized = $normalized -replace '경기도', ''
    $normalized = $normalized -replace '양주시', ''
    return (($normalized -replace '[\s,().-]', '')).ToLowerInvariant()
}

function Normalize-YangjuPhone {
    param([string]$Value)

    return ((Get-YangjuRowValue ([pscustomobject]@{ value = $Value }) 'value') -replace '\D', '')
}

function Compare-YangjuBenefits {
    param(
        [Parameter(Mandatory = $true)][object[]]$CanonicalRows,
        [Parameter(Mandatory = $true)][object[]]$OfficialRows
    )

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($canonical in $CanonicalRows) {
        $canonicalName = Get-YangjuRowValue $canonical '업소명'
        $canonicalAddress = Get-YangjuRowValue $canonical '소재지도로명주소'
        $canonicalPhone = Get-YangjuRowValue $canonical '업소전화번호'
        $canonicalDiscount = Get-YangjuRowValue $canonical '할인정보'

        $nameMatches = @($OfficialRows | Where-Object { (Normalize-YangjuName (Get-YangjuRowValue $_ '업소명')) -eq (Normalize-YangjuName $canonicalName) })
        $nameAddressMatches = @($nameMatches | Where-Object { (Normalize-YangjuAddress (Get-YangjuRowValue $_ '소재지도로명주소')) -eq (Normalize-YangjuAddress $canonicalAddress) })
        $addressMatches = @($OfficialRows | Where-Object { (Normalize-YangjuAddress (Get-YangjuRowValue $_ '소재지도로명주소')) -eq (Normalize-YangjuAddress $canonicalAddress) })

        $official = $null
        $decision = ''
        $nameAddressMatched = $false
        $phoneMatched = $false
        if ($nameAddressMatches.Count -eq 1) {
            $official = $nameAddressMatches[0]
            $nameAddressMatched = $true
            $phoneMatched = (Normalize-YangjuPhone (Get-YangjuRowValue $official '업소전화번호')) -eq (Normalize-YangjuPhone $canonicalPhone) -and -not [string]::IsNullOrWhiteSpace((Normalize-YangjuPhone $canonicalPhone))
            $decision = if ($phoneMatched) { '현재 공식 목록 일치 후보' } else { '상세정보 재확인 필요' }
        } elseif ($addressMatches.Count -eq 1) {
            $official = $addressMatches[0]
            $phoneMatched = (Normalize-YangjuPhone (Get-YangjuRowValue $official '업소전화번호')) -eq (Normalize-YangjuPhone $canonicalPhone) -and -not [string]::IsNullOrWhiteSpace((Normalize-YangjuPhone $canonicalPhone))
            $decision = if ($phoneMatched) { '상호 변경 가능성' } else { '주소 재확인 필요' }
        } elseif ($nameMatches.Count -gt 0) {
            $decision = '주소 재확인 필요'
        } else {
            $decision = '공식목록 미발견'
        }

        $results.Add([pscustomobject][ordered]@{
            정본CSV행번호 = Get-YangjuRowValue $canonical '정본CSV행번호'
            업소명 = $canonicalName
            소재지도로명주소 = $canonicalAddress
            기존전화번호 = $canonicalPhone
            기존할인정보 = $canonicalDiscount
            공식업소명 = if ($null -ne $official) { Get-YangjuRowValue $official '업소명' } else { '' }
            공식주소 = if ($null -ne $official) { Get-YangjuRowValue $official '소재지도로명주소' } else { '' }
            공식전화번호 = if ($null -ne $official) { Get-YangjuRowValue $official '업소전화번호' } else { '' }
            공식메뉴 = if ($null -ne $official) { Get-YangjuRowValue $official '메뉴' } else { '' }
            공식할인정보 = if ($null -ne $official) { Get-YangjuRowValue $official '할인정보' } else { '' }
            상호주소일치 = $nameAddressMatched
            전화일치 = $phoneMatched
            판정 = $decision
            검토결정 = '미검토'
            정본반영여부 = '아니오'
        })
    }
    return @($results)
}

if ($LibraryOnly) { return }

if ([string]::IsNullOrWhiteSpace($CanonicalCsv) -or [string]::IsNullOrWhiteSpace($OfficialCsv) -or [string]::IsNullOrWhiteSpace($OutputCsv) -or [string]::IsNullOrWhiteSpace($SummaryJson)) {
    throw 'CanonicalCsv, OfficialCsv, OutputCsv, SummaryJson을 모두 지정해 주세요.'
}

$officialRows = @(Import-Csv -LiteralPath $OfficialCsv -Encoding utf8)
if ($officialRows.Count -eq 0) { throw '양주시 공식 업소 목록이 비어 있습니다.' }

$canonicalRows = @(
    Import-Csv -LiteralPath $CanonicalCsv -Encoding utf8 |
        ForEach-Object -Begin { $index = 0 } -Process {
            $index += 1
            if ((Get-YangjuRowValue $_ '출처URL') -eq $LegacySourceUrl) {
                $_ | Add-Member -NotePropertyName 정본CSV행번호 -NotePropertyValue ($index + 1) -Force
                $_
            }
        }
)
if ($canonicalRows.Count -eq 0) { throw '지정한 양주시 기존 출처 URL을 사용하는 정본 행이 없습니다.' }

$comparisonRows = @(Compare-YangjuBenefits -CanonicalRows $canonicalRows -OfficialRows $officialRows)
$resolvedOutputCsv = [IO.Path]::GetFullPath($OutputCsv)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolvedOutputCsv) | Out-Null
$comparisonRows | Export-Csv -LiteralPath $resolvedOutputCsv -NoTypeInformation -Encoding utf8

$summary = [ordered]@{
    generatedAt = [DateTimeOffset]::Now.ToString('o')
    legacySourceUrl = $LegacySourceUrl
    currentSourceUrl = $CurrentSourceUrl
    officialRows = $officialRows.Count
    canonicalRows = $canonicalRows.Count
    decisions = @($comparisonRows | Group-Object 판정 | Sort-Object Name | ForEach-Object { [ordered]@{ decision = $_.Name; count = $_.Count } })
    automaticCanonicalMutation = $false
}
$resolvedSummaryJson = [IO.Path]::GetFullPath($SummaryJson)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolvedSummaryJson) | Out-Null
$summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $resolvedSummaryJson -Encoding utf8
Write-Output ("양주시 공식 목록 비교 완료: 정본 {0}건, 공식 목록 {1}건" -f $canonicalRows.Count, $officialRows.Count)

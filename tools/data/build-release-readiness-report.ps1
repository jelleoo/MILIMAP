[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CanonicalCsv,
    [Parameter(Mandatory = $true)]
    [string]$CoordinateReviewCsv,
    [Parameter(Mandatory = $true)]
    [string[]]$BenefitReviewCsv,
    [Parameter(Mandatory = $true)]
    [string]$OutputCsv,
    [string]$SummaryJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RowValue {
    param($Row, [string]$Name)

    $property = $Row.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return '' }
    return ([string]$property.Value).Trim()
}

function Normalize-ReadinessName {
    param([string]$Value)

    return ((Get-RowValue ([pscustomobject]@{ value = $Value }) 'value') -replace '<[^>]+>', '' -replace '[\s,().·&-]', '').ToLowerInvariant()
}

function Normalize-ReadinessAddress {
    param([string]$Value)

    $normalized = (Get-RowValue ([pscustomobject]@{ value = $Value }) 'value')
    if ($normalized.StartsWith('서울특별시')) { $normalized = '서울' + $normalized.Substring('서울특별시'.Length) }
    elseif ($normalized.StartsWith('서울시')) { $normalized = '서울' + $normalized.Substring('서울시'.Length) }
    elseif ($normalized.StartsWith('경기도')) { $normalized = '경기' + $normalized.Substring('경기도'.Length) }
    elseif ($normalized.StartsWith('인천광역시')) { $normalized = '인천' + $normalized.Substring('인천광역시'.Length) }
    return (($normalized -replace '[\s,().-]', '')).ToLowerInvariant()
}

function Test-SameStore {
    param($Canonical, $Review)

    if ((Normalize-ReadinessName (Get-RowValue $Canonical '업소명')) -ne (Normalize-ReadinessName (Get-RowValue $Review '업소명'))) {
        return $false
    }

    $reviewRoad = Normalize-ReadinessAddress (Get-RowValue $Review '소재지도로명주소')
    $reviewLot = Normalize-ReadinessAddress (Get-RowValue $Review '소재지지번주소')
    $canonicalRoad = Normalize-ReadinessAddress (Get-RowValue $Canonical '소재지도로명주소')
    $canonicalLot = Normalize-ReadinessAddress (Get-RowValue $Canonical '소재지지번주소')

    return ($reviewRoad -and ($reviewRoad -eq $canonicalRoad -or $reviewRoad -eq $canonicalLot)) -or
        ($reviewLot -and ($reviewLot -eq $canonicalRoad -or $reviewLot -eq $canonicalLot))
}

function Get-CoordinateState {
    param([object[]]$Matches)

    $strictPoiMatches = @($Matches | Where-Object {
        (Get-RowValue $_ '감사판정') -eq '확인 후보'
    })
    if ($strictPoiMatches.Count -eq 1) { return '확인 완료' }
    return '위치 확인 필요'
}

function Get-BenefitState {
    param([object[]]$Matches)

    $officialMatches = @($Matches | Where-Object {
        if ((Get-RowValue $_ '혜택근거상태') -eq '공식 최신 근거 확인') {
            return $true
        }

        $decision = Get-RowValue $_ '판정'
        if ($decision -eq '현재 공식 목록 일치 후보') {
            return -not [string]::IsNullOrWhiteSpace((Get-RowValue $_ '공식할인정보'))
        }
        if ($decision -eq '공식 참여업소 일치 후보') {
            return -not [string]::IsNullOrWhiteSpace((Get-RowValue $_ '공식출처URL'))
        }
        return $false
    })
    if ($officialMatches.Count -eq 1) { return '공식 최신 근거 확인' }
    if ($officialMatches.Count -gt 1) { return '복수 공식 근거 재확인' }
    return '최신 공식 혜택 근거 없음'
}

$blankBenefitInputs = @($BenefitReviewCsv | Where-Object { [string]::IsNullOrWhiteSpace($_) })
if ($blankBenefitInputs.Count -gt 0) { throw 'BenefitReviewCsv에는 비어 있지 않은 보고서 경로만 지정해 주세요.' }

$canonicalRows = @(
    Import-Csv -LiteralPath $CanonicalCsv -Encoding utf8 |
        ForEach-Object -Begin { $index = 0 } -Process {
            $index += 1
            [pscustomobject]@{ RowNumber = $index + 1; Row = $_ }
        }
)
$coordinateRows = @(Import-Csv -LiteralPath $CoordinateReviewCsv -Encoding utf8)
$benefitRows = @(
    foreach ($benefitReviewPath in $BenefitReviewCsv) {
        Import-Csv -LiteralPath $benefitReviewPath -Encoding utf8
    }
)

$results = foreach ($canonicalEntry in $canonicalRows) {
    $canonical = $canonicalEntry.Row
    $coordinateMatches = @($coordinateRows | Where-Object { Test-SameStore $canonical $_ })
    $benefitMatches = @($benefitRows | Where-Object { Test-SameStore $canonical $_ })

    $canonicalCoordinateStatus = Get-RowValue $canonical '좌표검증상태'
    $coordinateState = if ($canonicalCoordinateStatus -eq '확인 완료') {
        Get-CoordinateState -Matches $coordinateMatches
    } else { '위치 확인 필요' }
    $mapDisplayPolicy = switch ($coordinateState) {
        '확인 완료' { '좌표 마커 표시' }
        '위치 확인 필요' { '지도 핀 미표시 · 주소 직접 확인' }
        default { '좌표 검토 후 결정' }
    }
    $benefitState = Get-BenefitState -Matches $benefitMatches
    $releaseDecision = if ($benefitState -ne '공식 최신 근거 확인') { '보류: 최신 공식 혜택 근거 없음' }
        else { '출시 검토 가능' }

    [pscustomobject][ordered]@{
        정본CSV행번호 = $canonicalEntry.RowNumber
        업소명 = Get-RowValue $canonical '업소명'
        시도 = Get-RowValue $canonical '시도'
        시군구 = Get-RowValue $canonical '시군구'
        소재지도로명주소 = Get-RowValue $canonical '소재지도로명주소'
        소재지지번주소 = Get-RowValue $canonical '소재지지번주소'
        혜택상태 = Get-RowValue $canonical '혜택상태'
        좌표검토상태 = $coordinateState
        지도표시정책 = $mapDisplayPolicy
        혜택검토상태 = $benefitState
        출시판정 = $releaseDecision
        좌표검토행수 = $coordinateMatches.Count
        혜택검토행수 = $benefitMatches.Count
        정본반영여부 = '아니오'
    }
}

$resolvedOutputCsv = [IO.Path]::GetFullPath($OutputCsv)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolvedOutputCsv) | Out-Null
$results | Export-Csv -LiteralPath $resolvedOutputCsv -NoTypeInformation -Encoding utf8

if (-not [string]::IsNullOrWhiteSpace($SummaryJson)) {
    $summary = [ordered]@{
        generatedAt = [DateTimeOffset]::Now.ToString('o')
        canonicalRows = $results.Count
        releaseDecisions = @($results | Group-Object 출시판정 | Sort-Object Name | ForEach-Object { [ordered]@{ decision = $_.Name; count = $_.Count } })
        automaticCanonicalMutation = $false
    }
    $resolvedSummaryJson = [IO.Path]::GetFullPath($SummaryJson)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolvedSummaryJson) | Out-Null
    $summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $resolvedSummaryJson -Encoding utf8
}

Write-Output ("출시 준비도 보고서 생성: {0}건" -f $results.Count)

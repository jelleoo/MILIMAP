[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CanonicalCsv,
    [Parameter(Mandatory = $true)]
    [string]$CoordinateAuditCsv,
    [Parameter(Mandatory = $true)]
    [string[]]$BenefitReviewCsv,
    [Parameter(Mandatory = $true)]
    [string]$OutputCsv,
    [string]$SummaryJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PriorityRowValue {
    param($Row, [string]$Name)

    $property = $Row.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return '' }
    return ([string]$property.Value).Trim()
}

function Normalize-PriorityName {
    param([string]$Value)

    $normalized = Get-PriorityRowValue ([pscustomobject]@{ value = $Value }) 'value'
    $normalized = $normalized -replace '<[^>]+>', ''
    $normalized = $normalized -replace '\([^)]*\)', ''
    return (($normalized -replace '[\s,().·&-]', '')).ToLowerInvariant()
}

function Normalize-PriorityAddress {
    param([string]$Value)

    $normalized = Get-PriorityRowValue ([pscustomobject]@{ value = $Value }) 'value'
    if ($normalized.StartsWith('서울특별시')) { $normalized = '서울' + $normalized.Substring('서울특별시'.Length) }
    elseif ($normalized.StartsWith('서울시')) { $normalized = '서울' + $normalized.Substring('서울시'.Length) }
    elseif ($normalized.StartsWith('경기도')) { $normalized = '경기' + $normalized.Substring('경기도'.Length) }
    elseif ($normalized.StartsWith('인천광역시')) { $normalized = '인천' + $normalized.Substring('인천광역시'.Length) }
    return (($normalized -replace '[\s,().-]', '')).ToLowerInvariant()
}

function Test-PrioritySameStore {
    param($Canonical, $Comparison)

    if ((Normalize-PriorityName (Get-PriorityRowValue $Canonical '업소명')) -ne (Normalize-PriorityName (Get-PriorityRowValue $Comparison '업소명'))) {
        return $false
    }

    $canonicalRoad = Normalize-PriorityAddress (Get-PriorityRowValue $Canonical '소재지도로명주소')
    $canonicalLot = Normalize-PriorityAddress (Get-PriorityRowValue $Canonical '소재지지번주소')
    $comparisonRoad = Normalize-PriorityAddress (Get-PriorityRowValue $Comparison '소재지도로명주소')
    $comparisonLot = Normalize-PriorityAddress (Get-PriorityRowValue $Comparison '소재지지번주소')
    $comparisonInput = Normalize-PriorityAddress (Get-PriorityRowValue $Comparison '입력주소')

    return ($comparisonRoad -and ($comparisonRoad -eq $canonicalRoad -or $comparisonRoad -eq $canonicalLot)) -or
        ($comparisonLot -and ($comparisonLot -eq $canonicalRoad -or $comparisonLot -eq $canonicalLot)) -or
        ($comparisonInput -and ($comparisonInput -eq $canonicalRoad -or $comparisonInput -eq $canonicalLot))
}

function Get-CoordinatePriority {
    param([string]$AuditDecision)

    switch ($AuditDecision) {
        '확인 후보' { return [pscustomobject]@{ Code = 'P1'; Task = '지도 POI 상호·주소를 사람이 대조한 뒤 승인 또는 반려' } }
        '재확인 필요' { return [pscustomobject]@{ Code = 'P2'; Task = '동일 상호·주소 후보를 지도에서 분기·지점까지 재확인' } }
        default { return [pscustomobject]@{ Code = 'P3'; Task = '업소명과 전체 주소로 지도 POI를 새로 확인하고, 불확실하면 좌표를 비움' } }
    }
}

if ($BenefitReviewCsv.Count -eq 0 -or @($BenefitReviewCsv | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
    throw 'BenefitReviewCsv에는 비어 있지 않은 보고서 경로를 하나 이상 지정해 주세요.'
}

$canonicalEntries = @(
    Import-Csv -LiteralPath $CanonicalCsv -Encoding utf8 |
        ForEach-Object -Begin { $index = 0 } -Process {
            $index += 1
            [pscustomobject]@{ RowNumber = $index + 1; Row = $_ }
        }
)
$auditRows = @(Import-Csv -LiteralPath $CoordinateAuditCsv -Encoding utf8)
$benefitEntries = @(
    foreach ($benefitPath in $BenefitReviewCsv) {
        $sourceFile = Split-Path -Leaf $benefitPath
        Import-Csv -LiteralPath $benefitPath -Encoding utf8 |
            Where-Object { (Get-PriorityRowValue $_ '판정') -eq '현재 공식 목록 일치 후보' } |
            ForEach-Object { [pscustomobject]@{ SourceFile = $sourceFile; Row = $_ } }
    }
)

$candidateEntries = [System.Collections.Generic.List[object]]::new()
foreach ($benefitEntry in $benefitEntries) {
    $canonicalMatches = @($canonicalEntries | Where-Object { Test-PrioritySameStore $_.Row $benefitEntry.Row })
    if ($canonicalMatches.Count -ne 1) {
        throw ('혜택 후보와 정본 CSV의 1:1 대응을 확인할 수 없습니다: {0} / {1} (일치 {2}건)' -f (Get-PriorityRowValue $benefitEntry.Row '업소명'), (Get-PriorityRowValue $benefitEntry.Row '소재지도로명주소'), $canonicalMatches.Count)
    }
    $candidateEntries.Add([pscustomobject]@{ Canonical = $canonicalMatches[0]; Benefit = $benefitEntry })
}

$duplicateCandidates = @($candidateEntries | Group-Object { $_.Canonical.RowNumber } | Where-Object { $_.Count -gt 1 })
if ($duplicateCandidates.Count -gt 0) {
    throw ('같은 정본 행이 여러 혜택 보고서의 일치 후보입니다: ' + (($duplicateCandidates | ForEach-Object Name) -join ', '))
}

$queueRows = foreach ($candidate in $candidateEntries) {
    $canonical = $candidate.Canonical.Row
    $auditMatches = @($auditRows | Where-Object { Test-PrioritySameStore $canonical $_ })
    if ($auditMatches.Count -gt 1) {
        throw ('좌표 감사와 정본 CSV의 1:1 대응을 확인할 수 없습니다: {0} / {1} (일치 {2}건)' -f (Get-PriorityRowValue $canonical '업소명'), (Get-PriorityRowValue $canonical '소재지도로명주소'), $auditMatches.Count)
    }

    $audit = if ($auditMatches.Count -eq 1) { $auditMatches[0] } else { $null }
    $auditDecision = if ($null -ne $audit) { Get-PriorityRowValue $audit '판정' } else { '감사 미수행' }
    $priority = Get-CoordinatePriority $auditDecision
    [pscustomobject][ordered]@{
        정본CSV행번호 = $candidate.Canonical.RowNumber
        업소명 = Get-PriorityRowValue $canonical '업소명'
        시도 = Get-PriorityRowValue $canonical '시도'
        시군구 = Get-PriorityRowValue $canonical '시군구'
        소재지도로명주소 = Get-PriorityRowValue $canonical '소재지도로명주소'
        소재지지번주소 = Get-PriorityRowValue $canonical '소재지지번주소'
        혜택검토보고서 = $candidate.Benefit.SourceFile
        혜택검토판정 = Get-PriorityRowValue $candidate.Benefit.Row '판정'
        좌표감사판정 = $auditDecision
        좌표감사사유 = if ($null -ne $audit) { Get-PriorityRowValue $audit '검토사유' } else { '현재 좌표 감사 입력에 없음' }
        권장좌표검증상태 = if ($null -ne $audit) { Get-PriorityRowValue $audit '권장좌표검증상태' } else { '미확인' }
        최초POI조회어 = if ($null -ne $audit) { Get-PriorityRowValue $audit '최초POI조회어' } else { '' }
        POI조회어 = if ($null -ne $audit) { Get-PriorityRowValue $audit 'POI조회어' } else { '' }
        POI조회방식 = if ($null -ne $audit) { Get-PriorityRowValue $audit 'POI조회방식' } else { '' }
        POI상호 = if ($null -ne $audit) { Get-PriorityRowValue $audit 'POI상호' } else { '' }
        POI도로명주소 = if ($null -ne $audit) { Get-PriorityRowValue $audit 'POI도로명주소' } else { '' }
        POI지번주소 = if ($null -ne $audit) { Get-PriorityRowValue $audit 'POI지번주소' } else { '' }
        감사제안위도 = if ($null -ne $audit) { Get-PriorityRowValue $audit '제안위도' } else { '' }
        감사제안경도 = if ($null -ne $audit) { Get-PriorityRowValue $audit '제안경도' } else { '' }
        좌표출처URL = if ($null -ne $audit) { Get-PriorityRowValue $audit '좌표출처URL' } else { '' }
        우선순위 = $priority.Code
        검토작업 = $priority.Task
        검토결정 = '미검토'
        정본반영여부 = '아니오'
        검토메모 = '좌표·혜택 어느 쪽도 정본에 자동 반영하지 않음'
    }
}

$rank = @{ P1 = 1; P2 = 2; P3 = 3 }
$sortedQueueRows = @($queueRows | Sort-Object @{ Expression = { $rank[$_.우선순위] } }, 시도, 시군구, 업소명)
$resolvedOutputCsv = [IO.Path]::GetFullPath($OutputCsv)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolvedOutputCsv) | Out-Null
$sortedQueueRows | Export-Csv -LiteralPath $resolvedOutputCsv -NoTypeInformation -Encoding utf8

if (-not [string]::IsNullOrWhiteSpace($SummaryJson)) {
    $summary = [ordered]@{
        generatedAt = [DateTimeOffset]::Now.ToString('o')
        candidates = $sortedQueueRows.Count
        priorities = @($sortedQueueRows | Group-Object 우선순위 | Sort-Object Name | ForEach-Object { [ordered]@{ priority = $_.Name; count = $_.Count } })
        automaticCanonicalMutation = $false
    }
    $resolvedSummaryJson = [IO.Path]::GetFullPath($SummaryJson)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolvedSummaryJson) | Out-Null
    $summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $resolvedSummaryJson -Encoding utf8
}

Write-Output ('좌표 검증 우선순위 큐 생성: {0}건' -f $sortedQueueRows.Count)

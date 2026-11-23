[CmdletBinding()]
param(
    [switch]$LibraryOnly,
    [string]$CanonicalCsv = 'data/canonical/capital-area-military-benefits.csv',
    [string]$OutputDirectory = '',
    [string]$MmaListUrl = 'https://open.mma.go.kr/caisGGGS/mmanrsrListAjaxJsonCallNew.json?jbc_cd=&udggeopjong_gbcd=&callback=MmaBenefitList',
    [int]$TimeoutSeconds = 30,
    [string]$StepSummaryPath = '',
    [switch]$FailOnFetchError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Normalize-WeeklyDriftIdentityPart {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    return ([regex]::Replace($Value.Trim().ToLowerInvariant(), '[^a-z0-9가-힣]', ''))
}

function Get-WeeklyDriftField {
    param(
        [AllowNull()]$Item,
        [Parameter(Mandatory)][string[]]$CandidateNames
    )

    if ($null -eq $Item) { return '' }
    foreach ($name in $CandidateNames) {
        $prop = $Item.PSObject.Properties[$name]
        if ($null -ne $prop -and $null -ne $prop.Value) {
            $text = ([string]$prop.Value).Trim()
            if (-not [string]::IsNullOrWhiteSpace($text)) {
                return $text
            }
        }
    }
    return ''
}

function ConvertFrom-WeeklyMmaJsonpListText {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$RawText)

    $cleaned = $RawText
    if ($cleaned.Length -gt 0 -and $cleaned[0] -eq [char]0xFEFF) {
        $cleaned = $cleaned.Substring(1)
    }
    $match = [regex]::Match($cleaned, '^\s*[A-Za-z_][A-Za-z0-9_]*\(([\s\S]*)\)\s*;?\s*$')
    if (-not $match.Success) {
        throw 'WEEKLY_MMA_JSONP_INVALID: Expected callback wrapper around JSON payload.'
    }
    $jsonBody = $match.Groups[1].Value
    $parsed = $jsonBody | ConvertFrom-Json -ErrorAction Stop
    if ($null -eq $parsed -or $parsed -isnot [pscustomobject] -or $null -eq $parsed.PSObject.Properties['list'] -or $null -eq $parsed.list) {
        throw 'WEEKLY_MMA_JSONP_MISSING_LIST: Parsed JSONP payload does not contain a list array.'
    }
    return @($parsed.list)
}

function Read-WeeklyUtf8WebResponseText {
    param([Parameter(Mandatory)]$Response)

    if ($Response.PSObject.Properties.Name -contains 'RawContentStream' -and $null -ne $Response.RawContentStream -and $Response.RawContentStream.Length -gt 0) {
        $Response.RawContentStream.Position = 0
        return [IO.StreamReader]::new($Response.RawContentStream, [Text.UTF8Encoding]::new($false), $true).ReadToEnd()
    }
    if ($Response.Content -is [byte[]]) {
        return [Text.Encoding]::UTF8.GetString($Response.Content)
    }
    return [string]$Response.Content
}

function Compare-WeeklyMmaMetroToCanonical {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$LiveItems,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$CanonicalRows
    )

    $metroRegex = '^\s*(서울(?:특별시)?|경기(?:도)?|인천(?:광역시)?)'

    $canonicalMmaRows = @(
        $CanonicalRows | Where-Object {
            $srcType = Get-WeeklyDriftField -Item $_ -CandidateNames @('출처유형')
            $srcUrl = Get-WeeklyDriftField -Item $_ -CandidateNames @('출처URL')
            ($srcType -match '병무청|공공데이터') -or ($srcUrl -match 'mma\.go\.kr')
        }
    )

    $canonicalCds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $canonicalKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($cRow in $canonicalMmaRows) {
        $note = Get-WeeklyDriftField -Item $cRow -CandidateNames @('비고')
        if ($note -match 'cd=([0-9]+)') {
            [void]$canonicalCds.Add($Matches[1])
        }
        $namePart = Normalize-WeeklyDriftIdentityPart (Get-WeeklyDriftField -Item $cRow -CandidateNames @('업소명'))
        $addrPart = Normalize-WeeklyDriftIdentityPart (Get-WeeklyDriftField -Item $cRow -CandidateNames @('소재지도로명주소'))
        if (-not [string]::IsNullOrWhiteSpace($namePart) -and -not [string]::IsNullOrWhiteSpace($addrPart)) {
            [void]$canonicalKeys.Add("$namePart|$addrPart")
        }
    }

    $liveMetroItems = [Collections.Generic.List[object]]::new()
    $liveCds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $liveKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $newCandidates = [Collections.Generic.List[object]]::new()
    $matchedCount = 0

    foreach ($item in @($LiveItems)) {
        $endedYn = Get-WeeklyDriftField -Item $item -CandidateNames @('hyhaeje_yn', 'endedYn')
        if ($endedYn -ceq 'Y') { continue }

        $addr = Get-WeeklyDriftField -Item $item -CandidateNames @('addr', 'juso', 'roadAddress')
        if ($addr -notmatch $metroRegex) { continue }

        $cd = Get-WeeklyDriftField -Item $item -CandidateNames @('udgigwan_cd', 'udgigwancd', 'institutionCode')
        $name = Get-WeeklyDriftField -Item $item -CandidateNames @('udae_ggm', 'sangho', 'businessName', 'udgigwan_yhnm')
        $phone = Get-WeeklyDriftField -Item $item -CandidateNames @('udgigwan_telno', 'telno', 'phone')
        $category = Get-WeeklyDriftField -Item $item -CandidateNames @('udggeopjong_gbnm', 'upjong_nm', 'category')
        $office = Get-WeeklyDriftField -Item $item -CandidateNames @('jbc_nm', 'regionalOffice')

        $liveMetroItems.Add($item)
        if (-not [string]::IsNullOrWhiteSpace($cd)) { [void]$liveCds.Add($cd) }
        $key = "$(Normalize-WeeklyDriftIdentityPart $name)|$(Normalize-WeeklyDriftIdentityPart $addr)"
        if ($key -ne '|') { [void]$liveKeys.Add($key) }

        $inCanonical = ($cd -and $canonicalCds.Contains($cd)) -or ($key -ne '|' -and $canonicalKeys.Contains($key))
        if ($inCanonical) {
            $matchedCount++
        } else {
            $newCandidates.Add([pscustomobject][ordered]@{
                InstitutionCode = $cd
                BusinessName = $name
                RoadAddress = $addr
                Phone = $phone
                Category = $category
                RegionalOffice = $office
            })
        }
    }

    $canonicalActiveMmaRows = @(
        $canonicalMmaRows | Where-Object {
            (Get-WeeklyDriftField -Item $_ -CandidateNames @('혜택상태')) -ceq '이용 가능'
        }
    )
    $missingCanonical = [Collections.Generic.List[object]]::new()
    foreach ($cRow in $canonicalActiveMmaRows) {
        $note = Get-WeeklyDriftField -Item $cRow -CandidateNames @('비고')
        $cd = if ($note -match 'cd=([0-9]+)') { $Matches[1] } else { '' }
        $name = Get-WeeklyDriftField -Item $cRow -CandidateNames @('업소명')
        $addr = Get-WeeklyDriftField -Item $cRow -CandidateNames @('소재지도로명주소')
        $key = "$(Normalize-WeeklyDriftIdentityPart $name)|$(Normalize-WeeklyDriftIdentityPart $addr)"

        $inLive = ($cd -and $liveCds.Contains($cd)) -or ($key -ne '|' -and $liveKeys.Contains($key))
        if (-not $inLive) {
            $missingCanonical.Add([pscustomobject][ordered]@{
                BusinessId = (Get-WeeklyDriftField -Item $cRow -CandidateNames @('businessId'))
                BusinessName = $name
                Sido = (Get-WeeklyDriftField -Item $cRow -CandidateNames @('시도'))
                District = (Get-WeeklyDriftField -Item $cRow -CandidateNames @('시군구'))
                RoadAddress = $addr
                InstitutionCode = $cd
                LastVerifiedAt = (Get-WeeklyDriftField -Item $cRow -CandidateNames @('최근확인일'))
                CoordStatus = (Get-WeeklyDriftField -Item $cRow -CandidateNames @('좌표검증상태'))
            })
        }
    }

    return [pscustomobject][ordered]@{
        totalLiveCount = @($LiveItems).Count
        liveMetroCount = $liveMetroItems.Count
        canonicalMmaCount = $canonicalMmaRows.Count
        canonicalActiveMmaCount = $canonicalActiveMmaRows.Count
        matchedCount = $matchedCount
        newCandidateCount = $newCandidates.Count
        missingCanonicalCount = $missingCanonical.Count
        newCandidates = @($newCandidates)
        missingCanonical = @($missingCanonical)
    }
}

function Format-WeeklyMarkdownCell {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return '-' }
    return (($Value -replace '[\r\n]+', ' ') -replace '\|', '\|').Trim()
}

function New-WeeklyDriftMarkdownReport {
    param([Parameter(Mandatory)]$Summary)

    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('# MILIMAP 주간 공식 출처 변경 점검 리포트')
    $lines.Add('')
    $lines.Add("- 생성 시각(UTC): ``$($Summary.generatedAtUtc)``")
    $lines.Add("- 정본 행 수: **$($Summary.canonicalRowCount)건**")
    $lines.Add('- `ProductionAction`: **NONE** (정본 자동 수정 없음 · 검토/승인 후 시드 반영)')
    $lines.Add('')
    $lines.Add('| 출처 | 상태 | 공식 목록 건수 | 정본 건수 | 요약 / 드리프트 |')
    $lines.Add('| --- | --- | ---: | ---: | --- |')

    foreach ($src in @($Summary.sources)) {
        $official = if ($null -ne $src.officialCount) { [string]$src.officialCount } else { '-' }
        $canonical = if ($null -ne $src.canonicalCount) { [string]$src.canonicalCount } else { '-' }
        $note = if ($src.status -ceq 'FETCH_FAILED' -and -not [string]::IsNullOrWhiteSpace($src.error)) {
            "$($src.detail) ($($src.error))"
        } else {
            [string]$src.detail
        }
        $lines.Add("| $(Format-WeeklyMarkdownCell $src.name) | $(Format-WeeklyMarkdownCell $src.status) | $official | $canonical | $(Format-WeeklyMarkdownCell $note) |")
    }

    $lines.Add('')
    $lines.Add('## 후속 확인 기준')
    $lines.Add('- `동두천시` / `파주시`: 아티팩트 내 CSV(`ddc-comparison.csv`, `paju-comparison.csv`)의 변경·종료 후보를 확인합니다.')
    $lines.Add('- `병무청 나라사랑가게(수도권)`: `mma-new-candidates.csv`와 `mma-missing-canonical.csv`를 검토한 뒤 수동 승인 절차로 다음 `seedVersion`에 반영합니다.')
    $lines.Add('- `양주시`: 첨부 CSV 공고 확인 후 `tools/data/compare-yangju-benefits.ps1`로 수동 비교합니다.')

    return ($lines -join "`n") + "`n"
}

function Assert-WeeklyOutputSafePath {
    param(
        [Parameter(Mandatory)][string]$OutputDir,
        [Parameter(Mandatory)][string]$RepoRoot
    )

    $fullOut = [IO.Path]::GetFullPath($OutputDir).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    foreach ($protected in @('data', 'apps')) {
        $fullProtected = [IO.Path]::GetFullPath((Join-Path $RepoRoot $protected)).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
        $cmp = [StringComparison]::OrdinalIgnoreCase
        if ($fullOut.Equals($fullProtected, $cmp) -or
            $fullOut.StartsWith($fullProtected + [IO.Path]::DirectorySeparatorChar, $cmp)) {
            throw "WEEKLY_UNSAFE_OUTPUT_PATH: OutputDirectory cannot reside inside '$protected': $fullOut"
        }
    }
    return $fullOut
}

if ($LibraryOnly) { return }

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    throw 'WEEKLY_OUTPUT_DIRECTORY_REQUIRED: -OutputDirectory is required.'
}
if ($TimeoutSeconds -lt 1) {
    throw 'WEEKLY_TIMEOUT_INVALID: -TimeoutSeconds must be >= 1.'
}

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$resolvedCanonicalCsv = if ([IO.Path]::IsPathRooted($CanonicalCsv)) { $CanonicalCsv } else { Join-Path $repoRoot $CanonicalCsv }
if (-not (Test-Path -LiteralPath $resolvedCanonicalCsv -PathType Leaf)) {
    throw "WEEKLY_CANONICAL_CSV_MISSING: $resolvedCanonicalCsv"
}
$resolvedOutDir = Assert-WeeklyOutputSafePath -OutputDir $OutputDirectory -RepoRoot $repoRoot
[void][IO.Directory]::CreateDirectory($resolvedOutDir)

$canonicalRows = @(Import-Csv -LiteralPath $resolvedCanonicalCsv -Encoding utf8)
$sources = [Collections.Generic.List[object]]::new()

# 1. 동두천시 (compare-ddc-benefits.ps1)
$ddcOutCsv = Join-Path $resolvedOutDir 'ddc-comparison.csv'
$ddcSummaryJson = Join-Path $resolvedOutDir 'ddc-summary.json'
try {
    & (Join-Path $PSScriptRoot 'compare-ddc-benefits.ps1') `
        -CanonicalCsv $resolvedCanonicalCsv `
        -OutputCsv $ddcOutCsv `
        -SummaryJson $ddcSummaryJson `
        -TimeoutSeconds $TimeoutSeconds | Out-Null
    $ddcSummary = Get-Content -Raw -Encoding utf8 -LiteralPath $ddcSummaryJson | ConvertFrom-Json
    $ddcDecisions = @($ddcSummary.decisions | ForEach-Object { "$($_.decision)=$($_.count)" }) -join ', '
    $sources.Add([pscustomobject][ordered]@{
        id = 'ddc'
        name = '동두천시 (ddc.go.kr)'
        status = 'OK'
        officialCount = [int]$ddcSummary.officialRows
        canonicalCount = [int]$ddcSummary.canonicalRows
        detail = $ddcDecisions
        error = ''
    })
} catch {
    $sources.Add([pscustomobject][ordered]@{
        id = 'ddc'
        name = '동두천시 (ddc.go.kr)'
        status = 'FETCH_FAILED'
        officialCount = $null
        canonicalCount = $null
        detail = '동두천시 공식 목록 조회 또는 파싱 실패'
        error = $_.Exception.Message
    })
}

# 2. 파주시 (compare-paju-benefits.ps1)
$pajuOutCsv = Join-Path $resolvedOutDir 'paju-comparison.csv'
$pajuSummaryJson = Join-Path $resolvedOutDir 'paju-summary.json'
try {
    & (Join-Path $PSScriptRoot 'compare-paju-benefits.ps1') `
        -CanonicalCsv $resolvedCanonicalCsv `
        -OutputCsv $pajuOutCsv `
        -SummaryJson $pajuSummaryJson `
        -TimeoutSeconds $TimeoutSeconds | Out-Null
    $pajuSummary = Get-Content -Raw -Encoding utf8 -LiteralPath $pajuSummaryJson | ConvertFrom-Json
    $pajuDecisions = @($pajuSummary.decisions | ForEach-Object { "$($_.decision)=$($_.count)" }) -join ', '
    $sources.Add([pscustomobject][ordered]@{
        id = 'paju'
        name = '파주시 (paju.go.kr)'
        status = 'OK'
        officialCount = [int]$pajuSummary.officialRows
        canonicalCount = [int]$pajuSummary.canonicalRows
        detail = $pajuDecisions
        error = ''
    })
} catch {
    $sources.Add([pscustomobject][ordered]@{
        id = 'paju'
        name = '파주시 (paju.go.kr)'
        status = 'FETCH_FAILED'
        officialCount = $null
        canonicalCount = $null
        detail = '파주시 공식 목록 조회 또는 파싱 실패'
        error = $_.Exception.Message
    })
}

# 3. 병무청 나라사랑가게 수도권 공개 JSONP 목록 (open.mma.go.kr)
$mmaNewCsv = Join-Path $resolvedOutDir 'mma-new-candidates.csv'
$mmaMissingCsv = Join-Path $resolvedOutDir 'mma-missing-canonical.csv'
$mmaSummaryJson = Join-Path $resolvedOutDir 'mma-summary.json'
try {
    $mmaResp = Invoke-WebRequest -Uri $MmaListUrl -MaximumRedirection 3 -TimeoutSec $TimeoutSeconds
    if ([int]$mmaResp.StatusCode -ne 200) {
        throw "HTTP status $($mmaResp.StatusCode)"
    }
    $mmaText = Read-WeeklyUtf8WebResponseText -Response $mmaResp
    $mmaLiveItems = @(ConvertFrom-WeeklyMmaJsonpListText -RawText $mmaText)
    $mmaDrift = Compare-WeeklyMmaMetroToCanonical -LiveItems $mmaLiveItems -CanonicalRows $canonicalRows

    @($mmaDrift.newCandidates) | Export-Csv -LiteralPath $mmaNewCsv -NoTypeInformation -Encoding utf8
    @($mmaDrift.missingCanonical) | Export-Csv -LiteralPath $mmaMissingCsv -NoTypeInformation -Encoding utf8

    $mmaMetaSummary = [pscustomobject][ordered]@{
        generatedAtUtc = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
        sourceUrl = $MmaListUrl
        totalLiveCount = $mmaDrift.totalLiveCount
        liveMetroCount = $mmaDrift.liveMetroCount
        canonicalMmaCount = $mmaDrift.canonicalMmaCount
        canonicalActiveMmaCount = $mmaDrift.canonicalActiveMmaCount
        matchedCount = $mmaDrift.matchedCount
        newCandidateCount = $mmaDrift.newCandidateCount
        missingCanonicalCount = $mmaDrift.missingCanonicalCount
        automaticCanonicalMutation = $false
    }
    $mmaMetaSummary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $mmaSummaryJson -Encoding utf8

    $sources.Add([pscustomobject][ordered]@{
        id = 'mma'
        name = '병무청 나라사랑가게 수도권 (open.mma.go.kr)'
        status = 'OK'
        officialCount = [int]$mmaDrift.liveMetroCount
        canonicalCount = [int]$mmaDrift.canonicalActiveMmaCount
        detail = "일치=$($mmaDrift.matchedCount), 신규후보=$($mmaDrift.newCandidateCount), 정본미관측=$($mmaDrift.missingCanonicalCount)"
        error = ''
    })
} catch {
    $sources.Add([pscustomobject][ordered]@{
        id = 'mma'
        name = '병무청 나라사랑가게 수도권 (open.mma.go.kr)'
        status = 'FETCH_FAILED'
        officialCount = $null
        canonicalCount = $null
        detail = '병무청 공개 목록 조회 또는 파싱 실패'
        error = $_.Exception.Message
    })
}

# 4. 양주시 (수동 첨부 CSV 비교 안내)
$yangjuCount = @($canonicalRows | Where-Object { (Get-WeeklyDriftField -Item $_ -CandidateNames @('시군구')) -ceq '양주시' -and (Get-WeeklyDriftField -Item $_ -CandidateNames @('출처유형')) -match '지자체' }).Count
$sources.Add([pscustomobject][ordered]@{
    id = 'yangju'
    name = '양주시 (yangju.go.kr)'
    status = 'MANUAL_CSV_REQUIRED'
    officialCount = $null
    canonicalCount = $yangjuCount
    detail = '공고 첨부 CSV 수동 비교 대상 (compare-yangju-benefits.ps1)'
    error = ''
})

$summary = [pscustomobject][ordered]@{
    contractType = 'WeeklyBenefitDriftSummary'
    contractVersion = 1
    generatedAtUtc = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
    canonicalRowCount = $canonicalRows.Count
    automaticCanonicalMutation = $false
    productionAction = 'NONE'
    sources = @($sources)
}

$summaryPath = Join-Path $resolvedOutDir 'weekly-drift-summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding utf8

$markdown = New-WeeklyDriftMarkdownReport -Summary $summary
$markdownPath = Join-Path $resolvedOutDir 'weekly-drift-report.md'
[IO.File]::WriteAllText($markdownPath, $markdown, [Text.UTF8Encoding]::new($false))

if (-not [string]::IsNullOrWhiteSpace($StepSummaryPath)) {
    [IO.File]::AppendAllText($StepSummaryPath, $markdown + "`n", [Text.UTF8Encoding]::new($false))
}

Write-Output $markdown

$failedSources = @($sources | Where-Object { $_.status -ceq 'FETCH_FAILED' })
if ($FailOnFetchError -and $failedSources.Count -gt 0) {
    $names = ($failedSources | ForEach-Object { $_.id }) -join ', '
    throw "WEEKLY_DRIFT_FETCH_FAILED: $names"
}

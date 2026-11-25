[CmdletBinding()]
param(
    [switch]$LibraryOnly,
    [string]$CanonicalCsv = 'data/canonical/capital-area-military-benefits.csv',
    [string]$OutputDirectory = '',
    [string]$MmaListUrl = 'https://open.mma.go.kr/caisGGGS/mmanrsrListAjaxJsonCallNew.json?jbc_cd=&udggeopjong_gbcd=&callback=MmaBenefitList',
    [int]$TimeoutSeconds = 30,
    [string]$StepSummaryPath = '',
    [string]$YangjuAttachmentUrl = '',
    [string]$YangjuControlJsonPath = 'tools/data/testdata/benefit-evidence-xlsx/yangju-live-control.json',
    [switch]$FailOnFetchError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/benefit-source/discover-official-benefit-sources.ps1')
. (Join-Path $PSScriptRoot 'lib/benefit-source/safe-output-and-http.ps1')

function Normalize-WeeklyDriftIdentityPart {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    return ([regex]::Replace($Value.Trim().ToLowerInvariant(), '[^a-z0-9가-힣]', ''))
}

function Normalize-WeeklyDriftClaimText {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    return ([regex]::Replace($Value.Trim(), '\s+', ' ')).Trim()
}

function Normalize-WeeklyDriftPhone {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    return ($Value -replace '[^0-9]', '')
}

function Get-WeeklyDriftField {
    param(
        [AllowNull()]$Item,
        [Parameter(Mandatory)][string[]]$CandidateNames,
        [switch]$PreserveAbsence
    )

    $present = $false
    if ($null -ne $Item) {
        foreach ($name in $CandidateNames) {
            $prop = $Item.PSObject.Properties[$name]
            if ($null -eq $prop) { continue }
            $present = $true
            $text = ([string]$prop.Value).Trim()
            if (-not [string]::IsNullOrWhiteSpace($text)) { return $text }
        }
    }
    if ($PreserveAbsence -and -not $present) { return $null }
    return ''
}

function ConvertFrom-WeeklyMmaJsonpListText {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$RawText,
        [string]$ExpectedCallback = 'MmaBenefitList'
    )

    if ($ExpectedCallback -cnotmatch '^[A-Za-z_$][A-Za-z0-9_$]*$') {
        throw 'WEEKLY_MMA_JSONP_INVALID: Invalid expected callback name.'
    }
    $pattern = '\A\s*' + [regex]::Escape($ExpectedCallback) + '\s*\((?<json>.*)\)\s*;?\s*\z'
    $match = [regex]::Match($RawText.TrimStart([char]0xFEFF), $pattern, [Text.RegularExpressions.RegexOptions]::Singleline, [TimeSpan]::FromSeconds(1))
    if (-not $match.Success) {
        throw 'WEEKLY_MMA_JSONP_INVALID: Expected the configured callback wrapper around the JSON payload.'
    }
    try {
        $json = $match.Groups['json'].Value
        # ConvertFrom-Json alone accepts JavaScript extensions such as trailing commas.
        [Text.Json.JsonDocument]::Parse($json).Dispose()
        $parsed = ConvertFrom-Json -InputObject $json -NoEnumerate
    } catch {
        throw 'WEEKLY_MMA_JSONP_INVALID: Callback contains malformed JSON.'
    }
    if ($parsed -isnot [pscustomobject] -or $null -eq $parsed.PSObject.Properties['success'] -or $parsed.success -isnot [bool] -or -not $parsed.success) {
        throw 'WEEKLY_MMA_JSONP_UNSUCCESSFUL: The source did not return a successful list response.'
    }
    $list = $parsed.PSObject.Properties['list']
    if ($null -eq $list -or $list.Value -isnot [array] -or $list.Value.Count -eq 0) {
        throw 'WEEKLY_MMA_JSONP_UNUSABLE_LIST: The response must contain a nonempty list array.'
    }
    foreach ($item in $list.Value) {
        if ($item -isnot [pscustomobject]) {
            throw 'WEEKLY_MMA_JSONP_UNUSABLE_LIST: Every list entry must be a JSON object.'
        }
    }
    return $list.Value
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
    $canonicalByCd = @{}
    $canonicalByKey = @{}
    foreach ($cRow in $canonicalMmaRows) {
        $note = Get-WeeklyDriftField -Item $cRow -CandidateNames @('비고')
        if ($note -match 'cd=([0-9]+)') {
            $rowCd = $Matches[1]
            [void]$canonicalCds.Add($rowCd)
            if (-not $canonicalByCd.ContainsKey($rowCd)) {
                $canonicalByCd[$rowCd] = $cRow
            }
        }
        $namePart = Normalize-WeeklyDriftIdentityPart (Get-WeeklyDriftField -Item $cRow -CandidateNames @('업소명'))
        $addrPart = Normalize-WeeklyDriftIdentityPart (Get-WeeklyDriftField -Item $cRow -CandidateNames @('소재지도로명주소'))
        if (-not [string]::IsNullOrWhiteSpace($namePart) -and -not [string]::IsNullOrWhiteSpace($addrPart)) {
            $rowKey = "$namePart|$addrPart"
            [void]$canonicalKeys.Add($rowKey)
            if (-not $canonicalByKey.ContainsKey($rowKey)) {
                $canonicalByKey[$rowKey] = $cRow
            }
        }
    }

    $liveMetroItems = [Collections.Generic.List[object]]::new()
    $liveCds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $liveKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $newCandidates = [Collections.Generic.List[object]]::new()
    $changedCandidates = [Collections.Generic.List[object]]::new()
    $matchedCount = 0

    foreach ($item in @($LiveItems)) {
        $endedYn = Get-WeeklyDriftField -Item $item -CandidateNames @('hyhaeje_yn', 'endedYn')
        if ($endedYn -ceq 'Y') { continue }

        $addr = Get-WeeklyDriftField -Item $item -CandidateNames @('addr', 'juso', 'roadAddress')
        if ($addr -notmatch $metroRegex) { continue }

        $cd = Get-WeeklyDriftField -Item $item -CandidateNames @('udgigwan_cd', 'udgigwancd', 'institutionCode')
        $name = Get-WeeklyDriftField -Item $item -CandidateNames @('udae_ggm', 'sangho', 'businessName', 'udgigwan_yhnm')
        $phone = Get-WeeklyDriftField -Item $item -CandidateNames @('udgigwan_telno', 'telno', 'phone') -PreserveAbsence
        $category = Get-WeeklyDriftField -Item $item -CandidateNames @('udggeopjong_gbnm', 'upjong_nm', 'category')
        $office = Get-WeeklyDriftField -Item $item -CandidateNames @('jbc_nm', 'regionalOffice')

        if (-not $cd -and -not (Normalize-WeeklyDriftIdentityPart $name)) {
            throw 'WEEKLY_MMA_METRO_IDENTITY_MISSING: An active metro row has no usable institution code or name.'
        }
        $liveMetroItems.Add($item)
        if (-not [string]::IsNullOrWhiteSpace($cd)) { [void]$liveCds.Add($cd) }
        $key = "$(Normalize-WeeklyDriftIdentityPart $name)|$(Normalize-WeeklyDriftIdentityPart $addr)"
        if ($key -ne '|') { [void]$liveKeys.Add($key) }

        $matchedCanonical = if ($cd -and $canonicalByCd.ContainsKey($cd)) {
            $canonicalByCd[$cd]
        } elseif ($key -ne '|' -and $canonicalByKey.ContainsKey($key)) {
            $canonicalByKey[$key]
        } else {
            $null
        }

        if ($null -ne $matchedCanonical) {
            $matchedCount++
            if ((Get-WeeklyDriftField -Item $matchedCanonical -CandidateNames @('혜택상태')) -ceq '이용 가능') {
                $liveDiscountRaw = Get-WeeklyDriftField -Item $item -CandidateNames @('udsangse_cn', 'benefitDetail') -PreserveAbsence
                $liveDiscount = Normalize-WeeklyDriftClaimText $liveDiscountRaw
                $canDiscount = Normalize-WeeklyDriftClaimText (Get-WeeklyDriftField -Item $matchedCanonical -CandidateNames @('할인정보'))
                $liveTargetRaw = Get-WeeklyDriftField -Item $item -CandidateNames @('uddaesang_cn', 'eligibleTarget') -PreserveAbsence
                $liveTarget = Normalize-WeeklyDriftClaimText $liveTargetRaw
                $canTarget = Normalize-WeeklyDriftClaimText (Get-WeeklyDriftField -Item $matchedCanonical -CandidateNames @('적용대상'))
                $livePhoneNorm = Normalize-WeeklyDriftPhone $phone
                $canPhoneRaw = Get-WeeklyDriftField -Item $matchedCanonical -CandidateNames @('업소전화번호')
                $canPhoneNorm = Normalize-WeeklyDriftPhone $canPhoneRaw

                $diffTags = [Collections.Generic.List[string]]::new()
                if ($null -ne $liveDiscountRaw -and $liveDiscount -cne $canDiscount) {
                    $diffTags.Add('DISCOUNT')
                }
                if ($null -ne $liveTargetRaw -and $liveTarget -cne $canTarget) {
                    $diffTags.Add('TARGET')
                }
                if ($null -ne $phone -and $livePhoneNorm -cne $canPhoneNorm) {
                    $diffTags.Add('PHONE')
                }

                if ($diffTags.Count -gt 0) {
                    $changedCandidates.Add([pscustomobject][ordered]@{
                        BusinessId = (Get-WeeklyDriftField -Item $matchedCanonical -CandidateNames @('businessId'))
                        InstitutionCode = $cd
                        BusinessName = $name
                        RoadAddress = $addr
                        ChangedFields = ($diffTags -join '|')
                        CanonicalDiscount = $canDiscount
                        LiveDiscount = $liveDiscount
                        CanonicalTarget = $canTarget
                        LiveTarget = $liveTarget
                        CanonicalPhone = $canPhoneRaw
                        LivePhone = [string]$phone
                    })
                }
            }
        } else {
            $newCandidates.Add([pscustomobject][ordered]@{
                InstitutionCode = $cd
                BusinessName = $name
                RoadAddress = $addr
                Phone = [string]$phone
                Category = $category
                RegionalOffice = $office
            })
        }
    }

    if ($liveMetroItems.Count -eq 0) {
        throw 'WEEKLY_MMA_METRO_EMPTY: The official list contains no active metro records.'
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
        changedCount = $changedCandidates.Count
        newCandidateCount = $newCandidates.Count
        missingCanonicalCount = $missingCanonical.Count
        changedCandidates = @($changedCandidates)
        newCandidates = @($newCandidates)
        missingCanonical = @($missingCanonical)
    }
}

function Get-WeeklyYangjuBoardId {
    param([uri]$PageUrl, [string]$Href, [string]$Path, [string]$IdParameter)

    $target = $null
    if (-not [uri]::TryCreate($PageUrl, [Net.WebUtility]::HtmlDecode($Href), [ref]$target) -or
        $target.Scheme -cne 'https' -or $target.Host -cne 'www.yangju.go.kr' -or -not $target.IsDefaultPort -or
        $target.UserInfo -or $target.Fragment -or $target.AbsolutePath -cne $Path) {
        return
    }

    $query = [System.Web.HttpUtility]::ParseQueryString($target.Query)
    if ($query['key'] -cne '2716' -or $query['bbsNo'] -cne '81') { return }
    $id = 0L
    $rawId = $query[$IdParameter]
    if ($rawId -cmatch '^[1-9][0-9]*$' -and [long]::TryParse($rawId, [ref]$id)) { return $id }
}

function Get-WeeklyYangjuPageAnchors {
    param([string]$Html)

    $regexTimeout = [TimeSpan]::FromSeconds(5)
    $regexOptions = [Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [Text.RegularExpressions.RegexOptions]::Singleline
    $pattern = '<a\b[^>]*\shref\s*=\s*(?<quote>["''])(?<href>.*?)\k<quote>[^>]*>(?<label>.*?)</a\s*>'
    foreach ($anchor in [regex]::Matches($Html, $pattern, $regexOptions, $regexTimeout)) {
        [pscustomobject]@{
            Href = $anchor.Groups['href'].Value
            Label = [Net.WebUtility]::HtmlDecode(([regex]::Replace($anchor.Groups['label'].Value, '<[^>]+>', '', $regexOptions, $regexTimeout))).Trim()
        }
    }
}

function Find-WeeklyYangjuNoticeUrl {
    param([uri]$BoardUrl, [string]$Html)

    $regexTimeout = [TimeSpan]::FromSeconds(5)
    $path = '/health/selectBbsNttView.do'
    $newestId = 0L
    foreach ($anchor in @(Get-WeeklyYangjuPageAnchors -Html $Html)) {
        if (-not [regex]::IsMatch($anchor.Label, '군\s*장병\s*할인\s*[·ㆍ・‧∙/]?\s*우대\s*업소.*현황', [Text.RegularExpressions.RegexOptions]::None, $regexTimeout)) { continue }
        $id = Get-WeeklyYangjuBoardId -PageUrl $BoardUrl -Href $anchor.Href -Path $path -IdParameter 'nttNo'
        if ($id -gt $newestId) { $newestId = $id }
    }
    if ($newestId -eq 0) {
        throw 'WEEKLY_YANGJU_NOTICE_NOT_FOUND: No verified military discount inventory notice was found.'
    }
    return [uri]::new($BoardUrl, $path + '?key=2716&bbsNo=81&nttNo=' + $newestId)
}

function Find-WeeklyYangjuAttachmentUrl {
    param([uri]$NoticeUrl, [string]$Html)

    $regexTimeout = [TimeSpan]::FromSeconds(5)
    $regexOptions = [Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [Text.RegularExpressions.RegexOptions]::Singleline
    $path = '/health/downloadBbsFile.do'
    $ids = [Collections.Generic.HashSet[long]]::new()
    $pattern = '<div\b[^>]*\sclass\s*=\s*["''][^"'']*\bdown_view\b[^"'']*["''][^>]*>(?<body>.*?)</div\s*>'
    foreach ($block in [regex]::Matches($Html, $pattern, $regexOptions, $regexTimeout)) {
        $body = $block.Groups['body'].Value
        $filename = [regex]::Match($body, '<span\b[^>]*>(.*?)</span\s*>', $regexOptions, $regexTimeout).Groups[1].Value
        $filename = [Net.WebUtility]::HtmlDecode(([regex]::Replace($filename, '<[^>]+>', '', $regexOptions, $regexTimeout))).Trim()
        if (-not [regex]::IsMatch($filename, '군\s*장병\s*할인\s*[·ㆍ・‧∙/]?\s*우대\s*업소\s*현황.*\.xlsx$', [Text.RegularExpressions.RegexOptions]::None, $regexTimeout)) { continue }

        $downloadIds = @(
            foreach ($anchor in @(Get-WeeklyYangjuPageAnchors -Html $body)) {
                Get-WeeklyYangjuBoardId -PageUrl $NoticeUrl -Href $anchor.Href -Path $path -IdParameter 'atchmnflNo'
            }
        )
        if ($downloadIds.Count -eq 0) {
            throw 'WEEKLY_YANGJU_ATTACHMENT_UNVERIFIED: The inventory workbook download is outside the verified Yangju board.'
        }
        foreach ($id in $downloadIds) { [void]$ids.Add($id) }
    }
    if ($ids.Count -ne 1) {
        throw 'WEEKLY_YANGJU_ATTACHMENT_UNVERIFIED: The newest notice must identify exactly one verified inventory workbook.'
    }
    return [uri]::new($NoticeUrl, $path + '?key=2716&bbsNo=81&atchmnflNo=' + ($ids | Select-Object -First 1))
}

function Invoke-WeeklyYangjuRequest {
    param(
        [uri]$Uri,
        [int]$TimeoutSeconds,
        [int]$MaximumRedirection = 0,
        [int]$MaxResponseBytes = 20MB
    )

    return Invoke-BenefitBoundedHttpsGet `
        -Uri $Uri `
        -Headers @{ 'User-Agent' = 'MILIMAP-Phase5-EvidenceVerifier/1.0' } `
        -TimeoutSeconds $TimeoutSeconds `
        -MaxResponseBytes $MaxResponseBytes `
        -MaximumRedirection $MaximumRedirection `
        -ErrorPrefix 'WEEKLY_YANGJU'
}

function ConvertTo-WeeklySafeCsvCell {
    param([AllowNull()][string]$Value)

    return ConvertTo-BenefitSafeCsvCell -Value $Value
}

function ConvertTo-WeeklySafeCsvRows {
    param([AllowEmptyCollection()][object[]]$Rows)

    return ConvertTo-BenefitSafeCsvRows -Rows $Rows
}

function Test-WeeklyYangjuAttachmentDrift {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$AttachmentBytes,
        [Parameter(Mandatory)][string]$BaselineHash,
        [long]$BaselineByteSize = 0
    )

    if (-not (Test-BenefitXlsxBinaryPackage -Bytes $AttachmentBytes)) {
        throw 'WEEKLY_YANGJU_XLSX_INVALID: Download is not an XLSX workbook package.'
    }

    $actualHash = [BitConverter]::ToString([Security.Cryptography.SHA256]::HashData($AttachmentBytes)).Replace('-', '').ToLowerInvariant()
    $expectedHash = $BaselineHash.Trim().ToLowerInvariant()
    $hashMatched = ($actualHash -ceq $expectedHash)
    return [pscustomobject][ordered]@{
        status = if ($hashMatched) { 'OK' } else { 'DRIFT_DETECTED' }
        hashMatched = $hashMatched
        actualHash = $actualHash
        baselineHash = $expectedHash
        actualByteSize = [long]$AttachmentBytes.Length
        baselineByteSize = $BaselineByteSize
    }
}

function Format-WeeklyMarkdownCell {
    param([AllowNull()][string]$Value)

    return Format-BenefitSafeMarkdownCell -Value $Value
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
    $lines.Add('- `병무청 나라사랑가게(수도권)`: `mma-changed-candidates.csv`, `mma-new-candidates.csv`, `mma-missing-canonical.csv`를 검토한 뒤 수동 승인 절차로 다음 `seedVersion`에 반영합니다.')
    $lines.Add('- `양주시`: 첨부 XLSX 해시 변경(`DRIFT_DETECTED`) 감지 시 공고 파일을 내려받아 `tools/data/compare-yangju-benefits.ps1`로 비교합니다.')

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
$mmaChangedCsv = Join-Path $resolvedOutDir 'mma-changed-candidates.csv'
$mmaNewCsv = Join-Path $resolvedOutDir 'mma-new-candidates.csv'
$mmaMissingCsv = Join-Path $resolvedOutDir 'mma-missing-canonical.csv'
$mmaSummaryJson = Join-Path $resolvedOutDir 'mma-summary.json'
try {
    $mmaResp = Invoke-BenefitBoundedHttpsGet `
        -Uri ([uri]$MmaListUrl) `
        -TimeoutSeconds $TimeoutSeconds `
        -MaxResponseBytes 20MB `
        -MaximumRedirection 0 `
        -ErrorPrefix 'WEEKLY_MMA'
    $mmaText = $mmaResp.Text
    $mmaCallback = [System.Web.HttpUtility]::ParseQueryString(([uri]$MmaListUrl).Query)['callback']
    if (-not $mmaCallback) { $mmaCallback = 'MmaBenefitList' }
    $mmaLiveItems = @(ConvertFrom-WeeklyMmaJsonpListText -RawText $mmaText -ExpectedCallback $mmaCallback)
    $mmaDrift = Compare-WeeklyMmaMetroToCanonical -LiveItems $mmaLiveItems -CanonicalRows $canonicalRows

    @(ConvertTo-WeeklySafeCsvRows -Rows @($mmaDrift.changedCandidates)) | Export-Csv -LiteralPath $mmaChangedCsv -NoTypeInformation -Encoding utf8
    @(ConvertTo-WeeklySafeCsvRows -Rows @($mmaDrift.newCandidates)) | Export-Csv -LiteralPath $mmaNewCsv -NoTypeInformation -Encoding utf8
    @(ConvertTo-WeeklySafeCsvRows -Rows @($mmaDrift.missingCanonical)) | Export-Csv -LiteralPath $mmaMissingCsv -NoTypeInformation -Encoding utf8

    $mmaMetaSummary = [pscustomobject][ordered]@{
        generatedAtUtc = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
        sourceUrl = $MmaListUrl
        totalLiveCount = $mmaDrift.totalLiveCount
        liveMetroCount = $mmaDrift.liveMetroCount
        canonicalMmaCount = $mmaDrift.canonicalMmaCount
        canonicalActiveMmaCount = $mmaDrift.canonicalActiveMmaCount
        matchedCount = $mmaDrift.matchedCount
        changedCount = $mmaDrift.changedCount
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
        detail = "일치=$($mmaDrift.matchedCount), 내용변경=$($mmaDrift.changedCount), 신규후보=$($mmaDrift.newCandidateCount), 정본미관측=$($mmaDrift.missingCanonicalCount)"
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

# 4. 양주시 (공식 첨부 XLSX 해시 자동 점검)
$yangjuCount = @($canonicalRows | Where-Object { (Get-WeeklyDriftField -Item $_ -CandidateNames @('시군구')) -ceq '양주시' -and (Get-WeeklyDriftField -Item $_ -CandidateNames @('출처유형')) -match '지자체' }).Count
$yangjuSummaryJson = Join-Path $resolvedOutDir 'yangju-summary.json'
try {
    $resolvedYangjuControlPath = if ([IO.Path]::IsPathRooted($YangjuControlJsonPath)) { $YangjuControlJsonPath } else { Join-Path $repoRoot $YangjuControlJsonPath }
    if (-not (Test-Path -LiteralPath $resolvedYangjuControlPath -PathType Leaf)) {
        throw "Yangju baseline control JSON missing: $resolvedYangjuControlPath"
    }
    $yjBaseline = Get-Content -Raw -Encoding utf8 -LiteralPath $resolvedYangjuControlPath | ConvertFrom-Json
    $yjNoticeUrl = $null
    $yjRedirectLimit = 0
    $yjAttachmentUrl = $YangjuAttachmentUrl
    if ([string]::IsNullOrWhiteSpace($yjAttachmentUrl)) {
        $yjBoardUrl = [uri]'https://www.yangju.go.kr/health/selectBbsNttList.do?key=2716&bbsNo=81&searchCnd=SJ&searchKrwd=%EA%B5%B0%EC%9E%A5%EB%B3%91'
        $yjBoard = Invoke-WeeklyYangjuRequest -Uri $yjBoardUrl -TimeoutSeconds $TimeoutSeconds
        $yjNoticeUrl = Find-WeeklyYangjuNoticeUrl -BoardUrl $yjBoardUrl -Html $yjBoard.Text
        $yjNotice = Invoke-WeeklyYangjuRequest -Uri $yjNoticeUrl -TimeoutSeconds $TimeoutSeconds
        $yjAttachmentUrl = Find-WeeklyYangjuAttachmentUrl -NoticeUrl $yjNoticeUrl -Html $yjNotice.Text
    }
    $yjResp = Invoke-WeeklyYangjuRequest -Uri $yjAttachmentUrl -TimeoutSeconds $TimeoutSeconds -MaximumRedirection $yjRedirectLimit

    $yjBytes = [byte[]]$yjResp.Bytes
    $yjCheck = Test-WeeklyYangjuAttachmentDrift -AttachmentBytes $yjBytes -BaselineHash ([string]$yjBaseline.ContentHash) -BaselineByteSize ([long]$yjBaseline.WorkbookByteSize)
    $yjSummary = [pscustomobject][ordered]@{
        generatedAtUtc = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
        noticeUrl = [string]$yjNoticeUrl
        attachmentUrl = [string]$yjAttachmentUrl
        status = $yjCheck.status
        hashMatched = $yjCheck.hashMatched
        actualHash = $yjCheck.actualHash
        baselineHash = $yjCheck.baselineHash
        actualByteSize = $yjCheck.actualByteSize
        baselineByteSize = $yjCheck.baselineByteSize
        canonicalCount = $yangjuCount
        automaticCanonicalMutation = $false
    }
    $yjSummary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $yangjuSummaryJson -Encoding utf8
    $sources.Add([pscustomobject][ordered]@{
        id = 'yangju'
        name = '양주시 (yangju.go.kr)'
        status = $yjCheck.status
        officialCount = $null
        canonicalCount = $yangjuCount
        detail = if ($yjCheck.hashMatched) {
            "공식 첨부 XLSX 해시 일치(변경 없음, bytes=$($yjCheck.actualByteSize))"
        } else {
            "공식 첨부 XLSX 해시 변경 감지(bytes=$($yjCheck.actualByteSize), compare-yangju-benefits.ps1 실행 필요)"
        }
        error = ''
    })
} catch {
    $sources.Add([pscustomobject][ordered]@{
        id = 'yangju'
        name = '양주시 (yangju.go.kr)'
        status = 'FETCH_FAILED'
        officialCount = $null
        canonicalCount = $yangjuCount
        detail = '양주시 공식 첨부 XLSX 해시 조회 실패'
        error = $_.Exception.Message
    })
}

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

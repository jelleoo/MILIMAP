[CmdletBinding()]
param(
    [string]$SeedManifestJson = 'apps/android/app/src/main/assets/benefits.seed.manifest.json',
    [string]$WeeklyDriftSummaryJson = '',
    [string]$ReviewQueueSummaryJson = '',
    [string]$OutputJson = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/release/approval-release-contracts.ps1')

function Read-OpsSnapshotJsonObject {
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$MaxBytes = 16777216
    )

    $safePath = Assert-ReleaseSafeFilePath -Path $Path
    if (-not (Test-Path -LiteralPath $safePath -PathType Leaf)) {
        throw "OPS_SNAPSHOT_FILE_MISSING: $safePath"
    }
    $bytes = [IO.File]::ReadAllBytes($safePath)
    if ($bytes.Length -gt $MaxBytes) {
        throw "OPS_SNAPSHOT_JSON_TOO_LARGE: $safePath"
    }
    $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes).TrimStart([char]0xFEFF)
    $jsonOptions = @{}
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) {
        $jsonOptions.DateKind = 'String'
    }
    return ($text | ConvertFrom-Json @jsonOptions)
}

function Write-OpsSnapshotAtomicJson {
    param(
        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter(Mandatory)]$Value
    )

    $safeOut = Assert-ReleaseSafeFilePath -Path $OutputPath
    $parent = Split-Path -Parent $safeOut
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        [void][IO.Directory]::CreateDirectory($parent)
    }
    $jsonText = $Value | ConvertTo-Json -Depth 15
    $tmpPath = "$safeOut.tmp.$([guid]::NewGuid().ToString('N'))"
    try {
        [IO.File]::WriteAllText($tmpPath, $jsonText, [Text.UTF8Encoding]::new($false))
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            [IO.File]::Move($tmpPath, $safeOut, $true)
        } else {
            Move-Item -LiteralPath $tmpPath -Destination $safeOut -Force
        }
    } finally {
        if (Test-Path -LiteralPath $tmpPath -PathType Leaf) {
            Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue
        }
    }
    return $safeOut
}

function ConvertFrom-OpsSafeCsvCellValue {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $trimmed = $Value.Trim()
    if ($trimmed.Length -ge 2 -and $trimmed[0] -eq "'" -and $trimmed[1] -cmatch '[=+\-@\t\r\n]') {
        return $trimmed.Substring(1).Trim()
    }
    return $trimmed
}

function Get-OpsDriftCsvCell {
    param(
        [AllowNull()]$Row,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $Row) { return '' }
    $prop = $Row.PSObject.Properties[$Name]
    if ($null -eq $prop -or $null -eq $prop.Value) { return '' }
    return (ConvertFrom-OpsSafeCsvCellValue ([string]$prop.Value))
}

function Test-OpsSafeHttpUrl {
    param([AllowNull()][string]$Url)

    if ([string]::IsNullOrWhiteSpace($Url)) { return $false }
    $uri = $null
    if (-not [uri]::TryCreate($Url.Trim(), [UriKind]::Absolute, [ref]$uri)) { return $false }
    return ($uri.Scheme -cin @('http', 'https')) -and -not [string]::IsNullOrWhiteSpace($uri.Host) -and [string]::IsNullOrEmpty($uri.UserInfo)
}

function Read-OpsSiblingDriftReviewItems {
    param([Parameter(Mandatory)][string]$DriftSummaryJsonPath)

    $driftDir = Split-Path -Parent (Assert-ReleaseSafeFilePath -Path $DriftSummaryJsonPath)
    if ([string]::IsNullOrWhiteSpace($driftDir) -or -not (Test-Path -LiteralPath $driftDir -PathType Container)) {
        return @()
    }

    $items = [Collections.Generic.List[object]]::new()
    $mmaListWebUrl = 'https://www.mma.go.kr/about/udgg/list.do?mc=mma0003357'
    $ddcOfficialUrl = 'https://www.ddc.go.kr/ddc/contents.do?key=1570'
    $pajuFallbackUrl = 'https://www.paju.go.kr/user/soldier/BD_discountStoreList.do?q_ctgCd=1001'

    # 1. MMA changed candidates
    $mmaChangedPath = Join-Path $driftDir 'mma-changed-candidates.csv'
    if (Test-Path -LiteralPath $mmaChangedPath -PathType Leaf) {
        $idx = 0
        foreach ($row in @(Import-Csv -LiteralPath $mmaChangedPath -Encoding utf8)) {
            $idx++
            $bizId = Get-OpsDriftCsvCell $row 'BusinessId'
            $name = Get-OpsDriftCsvCell $row 'BusinessName'
            if (-not $name -and -not $bizId) { continue }
            $changedFields = Get-OpsDriftCsvCell $row 'ChangedFields'
            $canDisc = Get-OpsDriftCsvCell $row 'CanonicalDiscount'
            $liveDisc = Get-OpsDriftCsvCell $row 'LiveDiscount'
            $canTarget = Get-OpsDriftCsvCell $row 'CanonicalTarget'
            $liveTarget = Get-OpsDriftCsvCell $row 'LiveTarget'
            $canPhone = Get-OpsDriftCsvCell $row 'CanonicalPhone'
            $livePhone = Get-OpsDriftCsvCell $row 'LivePhone'
            $items.Add([pscustomobject][ordered]@{
                id                 = "drift-mma-changed-$idx-$bizId"
                sourceId           = 'mma'
                sourceName         = '병무청 나라사랑가게'
                category           = 'CONTENT_CHANGED'
                categoryLabel      = '내용 변경'
                severity           = 'amber'
                businessId         = if ($bizId) { $bizId } else { $null }
                canonicalRowNumber = $null
                businessName       = $name
                district           = ''
                roadAddress        = (Get-OpsDriftCsvCell $row 'RoadAddress')
                reasonSummary      = if ($changedFields) { "변경 감지 필드: $changedFields" } else { '공식 목록과 정본 내용 상이' }
                canonicalDetail    = "할인: $canDisc / 대상: $canTarget / 전화: $canPhone"
                officialDetail     = "할인: $liveDisc / 대상: $liveTarget / 전화: $livePhone"
                sourceUrls         = @($mmaListWebUrl)
            })
        }
    }

    # 2. MMA missing canonical
    $mmaMissingPath = Join-Path $driftDir 'mma-missing-canonical.csv'
    if (Test-Path -LiteralPath $mmaMissingPath -PathType Leaf) {
        $idx = 0
        foreach ($row in @(Import-Csv -LiteralPath $mmaMissingPath -Encoding utf8)) {
            $idx++
            $bizId = Get-OpsDriftCsvCell $row 'BusinessId'
            $name = Get-OpsDriftCsvCell $row 'BusinessName'
            if (-not $name -and -not $bizId) { continue }
            $lastVerified = Get-OpsDriftCsvCell $row 'LastVerifiedAt'
            $coordStatus = Get-OpsDriftCsvCell $row 'CoordStatus'
            $items.Add([pscustomobject][ordered]@{
                id                 = "drift-mma-missing-$idx-$bizId"
                sourceId           = 'mma'
                sourceName         = '병무청 나라사랑가게'
                category           = 'MISSING_IN_OFFICIAL'
                categoryLabel      = '공식목록 미관측'
                severity           = 'red'
                businessId         = if ($bizId) { $bizId } else { $null }
                canonicalRowNumber = $null
                businessName       = $name
                district           = (Get-OpsDriftCsvCell $row 'District')
                roadAddress        = (Get-OpsDriftCsvCell $row 'RoadAddress')
                reasonSummary      = '최신 병무청 나라사랑가게 목록에서 미관측'
                canonicalDetail    = "최근확인일: $lastVerified / 좌표: $coordStatus"
                officialDetail     = '최신 공식 목록 미관측 (자동 종료 금지 · 폐업/제외 여부 직접 확인 필요)'
                sourceUrls         = @($mmaListWebUrl)
            })
        }
    }

    # 3. Dongducheon comparison
    $ddcPath = Join-Path $driftDir 'ddc-comparison.csv'
    if (Test-Path -LiteralPath $ddcPath -PathType Leaf) {
        foreach ($row in @(Import-Csv -LiteralPath $ddcPath -Encoding utf8)) {
            $decision = Get-OpsDriftCsvCell $row '판정'
            if (-not $decision -or $decision -ceq '현재 공식 목록 일치 후보') { continue }
            $rowNumText = Get-OpsDriftCsvCell $row '정본CSV행번호'
            $parsedRowNum = 0
            $rowNumVal = if ([int]::TryParse($rowNumText, [ref]$parsedRowNum)) { $parsedRowNum } else { $null }
            $name = Get-OpsDriftCsvCell $row '업소명'
            $cat = switch -CaseSensitive ($decision) {
                '공식목록 미발견' { 'MISSING_IN_OFFICIAL' }
                '주소 재확인 필요' { 'ADDRESS_RECHECK' }
                default { 'DETAIL_RECHECK' }
            }
            $sev = if ($cat -ceq 'MISSING_IN_OFFICIAL') { 'red' } else { 'amber' }
            $items.Add([pscustomobject][ordered]@{
                id                 = "drift-ddc-$rowNumText-$name"
                sourceId           = 'ddc'
                sourceName         = '동두천시'
                category           = $cat
                categoryLabel      = $decision
                severity           = $sev
                businessId         = $null
                canonicalRowNumber = $rowNumVal
                businessName       = $name
                district           = '동두천시'
                roadAddress        = (Get-OpsDriftCsvCell $row '소재지도로명주소')
                reasonSummary      = "동두천 공식 비교 판정: $decision"
                canonicalDetail    = "할인: $(Get-OpsDriftCsvCell $row '기존할인정보') / 전화: $(Get-OpsDriftCsvCell $row '기존전화번호')"
                officialDetail     = if ($cat -ceq 'MISSING_IN_OFFICIAL') {
                    '공식 표에서 업소 미발견 (직접 확인 필요)'
                } else {
                    "공식명: $(Get-OpsDriftCsvCell $row '공식업소명') / 할인: $(Get-OpsDriftCsvCell $row '공식할인정보') / 전화: $(Get-OpsDriftCsvCell $row '공식전화번호') / 주소: $(Get-OpsDriftCsvCell $row '공식주소')"
                }
                sourceUrls         = @($ddcOfficialUrl)
            })
        }
    }

    # 4. Paju comparison
    $pajuPath = Join-Path $driftDir 'paju-comparison.csv'
    if (Test-Path -LiteralPath $pajuPath -PathType Leaf) {
        foreach ($row in @(Import-Csv -LiteralPath $pajuPath -Encoding utf8)) {
            $decision = Get-OpsDriftCsvCell $row '판정'
            if (-not $decision -or $decision -ceq '공식 참여업소 일치 후보') { continue }
            $rowNumText = Get-OpsDriftCsvCell $row '정본CSV행번호'
            $parsedRowNum = 0
            $rowNumVal = if ([int]::TryParse($rowNumText, [ref]$parsedRowNum)) { $parsedRowNum } else { $null }
            $name = Get-OpsDriftCsvCell $row '업소명'
            $cat = switch -CaseSensitive ($decision) {
                '공식목록 미발견' { 'MISSING_IN_OFFICIAL' }
                '주소 재확인 필요' { 'ADDRESS_RECHECK' }
                default { 'DETAIL_RECHECK' }
            }
            $sev = if ($cat -ceq 'MISSING_IN_OFFICIAL') { 'red' } else { 'amber' }
            $officialUrl = Get-OpsDriftCsvCell $row '공식출처URL'
            $srcUrl = if (Test-OpsSafeHttpUrl $officialUrl) { $officialUrl } else { $pajuFallbackUrl }
            $items.Add([pscustomobject][ordered]@{
                id                 = "drift-paju-$rowNumText-$name"
                sourceId           = 'paju'
                sourceName         = '파주시'
                category           = $cat
                categoryLabel      = $decision
                severity           = $sev
                businessId         = $null
                canonicalRowNumber = $rowNumVal
                businessName       = $name
                district           = '파주시'
                roadAddress        = (Get-OpsDriftCsvCell $row '소재지도로명주소')
                reasonSummary      = "파주 공식 비교 판정: $decision"
                canonicalDetail    = "할인: $(Get-OpsDriftCsvCell $row '기존할인정보') / 전화: $(Get-OpsDriftCsvCell $row '기존전화번호')"
                officialDetail     = if ($cat -ceq 'MISSING_IN_OFFICIAL') {
                    '파주 공식 참여업소 목록에서 미발견 (직접 확인 필요)'
                } else {
                    "공식명: $(Get-OpsDriftCsvCell $row '공식업소명') / 전화: $(Get-OpsDriftCsvCell $row '공식전화번호') / 주소: $(Get-OpsDriftCsvCell $row '공식주소')"
                }
                sourceUrls         = @($srcUrl)
            })
        }
    }

    # 5. Yangju summary attachment drift
    $yangjuPath = Join-Path $driftDir 'yangju-summary.json'
    if (Test-Path -LiteralPath $yangjuPath -PathType Leaf) {
        $yj = Read-OpsSnapshotJsonObject -Path $yangjuPath
        if ([string]$yj.status -cne 'OK') {
            $yjUrls = [Collections.Generic.List[string]]::new()
            if ($yj.PSObject.Properties['noticeUrl'] -and (Test-OpsSafeHttpUrl ([string]$yj.noticeUrl))) {
                $yjUrls.Add([string]$yj.noticeUrl)
            }
            if ($yj.PSObject.Properties['attachmentUrl'] -and (Test-OpsSafeHttpUrl ([string]$yj.attachmentUrl))) {
                $yjUrls.Add([string]$yj.attachmentUrl)
            }
            if ($yjUrls.Count -eq 0) {
                $yjUrls.Add('https://www.yangju.go.kr/health/selectBbsNttList.do?key=2716&bbsNo=81')
            }
            $items.Add([pscustomobject][ordered]@{
                id                 = 'drift-yangju-attachment'
                sourceId           = 'yangju'
                sourceName         = '양주시'
                category           = 'ATTACHMENT_CHANGED'
                categoryLabel      = '첨부파일 변경 감지'
                severity           = 'amber'
                businessId         = $null
                canonicalRowNumber = $null
                businessName       = '양주시 군장병 할인업소 공식 공고/첨부 XLSX'
                district           = '양주시'
                roadAddress        = ''
                reasonSummary      = "공식 첨부 XLSX 해시 변경 감지 (bytes=$($yj.actualByteSize) vs baseline=$($yj.baselineByteSize))"
                canonicalDetail    = "기준 해시: $($yj.baselineHash) (bytes=$($yj.baselineByteSize))"
                officialDetail     = "최신 해시: $($yj.actualHash) (bytes=$($yj.actualByteSize))"
                sourceUrls         = @($yjUrls.ToArray())
            })
        }
    }

    return @($items.ToArray())
}

function Build-OpsDashboardSnapshot {
    param(
        [Parameter(Mandatory)][string]$SeedManifestJson,
        [string]$WeeklyDriftSummaryJson = '',
        [string]$ReviewQueueSummaryJson = '',
        [Parameter(Mandatory)][string]$OutputJson
    )

    $manifest = Read-OpsSnapshotJsonObject -Path $SeedManifestJson
    Assert-BenefitReleaseSeedManifest -Manifest $manifest

    $weeklyDrift = $null
    if (-not [string]::IsNullOrWhiteSpace($WeeklyDriftSummaryJson)) {
        $driftObj = Read-OpsSnapshotJsonObject -Path $WeeklyDriftSummaryJson
        if ([string]$driftObj.contractType -cne 'WeeklyBenefitDriftSummary') {
            throw "OPS_SNAPSHOT_INVALID_WEEKLY_DRIFT: Unexpected contractType '$($driftObj.contractType)'"
        }
        $driftReviewItems = @(Read-OpsSiblingDriftReviewItems -DriftSummaryJsonPath $WeeklyDriftSummaryJson)
        $weeklyDrift = [pscustomobject][ordered]@{
            contractType               = [string]$driftObj.contractType
            contractVersion            = [int]$driftObj.contractVersion
            generatedAtUtc             = [string]$driftObj.generatedAtUtc
            canonicalRowCount          = [int]$driftObj.canonicalRowCount
            automaticCanonicalMutation = [bool]$driftObj.automaticCanonicalMutation
            productionAction           = if ($driftObj.PSObject.Properties['productionAction']) { [string]$driftObj.productionAction } else { 'NONE' }
            sources                    = @($driftObj.sources)
            reviewItems                = @($driftReviewItems)
        }
    }

    $reviewQueue = $null
    if (-not [string]::IsNullOrWhiteSpace($ReviewQueueSummaryJson)) {
        $rqObj = Read-OpsSnapshotJsonObject -Path $ReviewQueueSummaryJson
        if ([string]$rqObj.ContractType -cne 'Phase5ReviewQueueExport') {
            throw "OPS_SNAPSHOT_INVALID_REVIEW_QUEUE: Unexpected ContractType '$($rqObj.ContractType)'"
        }
        if ($null -eq $rqObj.Summary) {
            throw 'OPS_SNAPSHOT_INVALID_REVIEW_QUEUE: Missing Summary'
        }
        $allowedItemProps = @(
            'OperatorBucket', 'BusinessId', 'CanonicalRowNumber', 'BusinessName', 'District',
            'RoadAddress', 'CanonicalBenefitStatus', 'CanonicalCoordinateStatus', 'CanonicalSourceUrl',
            'CanonicalLastVerifiedAt', 'Domain', 'ReviewKey', 'RunId', 'ObservedAt',
            'CurrentObservationId', 'PreviousObservationId', 'ComparisonId', 'ReviewRoute',
            'OperationalStatus', 'Comparable', 'SemanticProjectionAvailable', 'DeltaDimensions',
            'ChangeCandidates', 'ReasonCodes', 'AuditFlags', 'DiagnosticReasons', 'BenefitState',
            'ReviewClass', 'BusinessPresence', 'AbsenceEligible', 'ValidatedClaims', 'SourceUrls',
            'SourceFormats', 'SourceContentHashes', 'SourceLocationStatuses', 'LocationEvaluationStatus',
            'LocationClassification', 'LocationSelectionStatus', 'LocationSelectedLatitude',
            'LocationSelectedLongitude', 'MaterialReasonCodes', 'ConflictCodes', 'ApprovalRequired',
            'ProductionAction'
        )
        $sanitizedItems = @(
            foreach ($item in @($rqObj.Items)) {
                $cleanItem = [ordered]@{}
                foreach ($propName in $allowedItemProps) {
                    if ($item.PSObject.Properties.Name -contains $propName) {
                        $cleanItem[$propName] = $item.$propName
                    }
                }
                [pscustomobject]$cleanItem
            }
        )
        $reviewQueue = [pscustomobject][ordered]@{
            ContractType     = [string]$rqObj.ContractType
            ContractVersion  = [int]$rqObj.ContractVersion
            ExportedAt       = [string]$rqObj.ExportedAt
            Summary          = $rqObj.Summary
            Items            = @($sanitizedItems)
        }
    }

    $snapshot = [pscustomobject][ordered]@{
        ContractType     = 'OpsDashboardSnapshot'
        ContractVersion  = 1
        GeneratedAtUtc   = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
        ProductionAction = 'NONE'
        SeedBaseline     = $manifest
        WeeklyDrift      = $weeklyDrift
        ReviewQueue      = $reviewQueue
    }

    $writtenPath = Write-OpsSnapshotAtomicJson -OutputPath $OutputJson -Value $snapshot
    return [pscustomobject][ordered]@{
        OutputJsonPath   = $writtenPath
        Snapshot         = $snapshot
        ProductionAction = 'NONE'
    }
}

if ($MyInvocation.InvocationName -ne '.' -and $PSBoundParameters.Count -gt 0) {
    if ([string]::IsNullOrWhiteSpace($OutputJson)) {
        throw 'OPS_SNAPSHOT_OUTPUT_REQUIRED: -OutputJson is required.'
    }
    Build-OpsDashboardSnapshot `
        -SeedManifestJson $SeedManifestJson `
        -WeeklyDriftSummaryJson $WeeklyDriftSummaryJson `
        -ReviewQueueSummaryJson $ReviewQueueSummaryJson `
        -OutputJson $OutputJson | Out-Null
}

[CmdletBinding()]
param(
    [string]$HistoryRoot = '',
    [string]$CanonicalCsvPath = '',
    [string]$CoordinateReviewCsvPath = '',
    [string]$ApprovalLedgerJsonPath = '',
    [int]$SourceRowNumberOffset = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Capture CLI arguments before dot-sourcing history adapters that overwrite script-scope $historyRoot.
$script:ValidateApprovalsCliInvoked = ($PSBoundParameters.Count -gt 0)
$script:ValidateApprovalsCliParams = @{
    HistoryRoot = $HistoryRoot
    CanonicalCsvPath = $CanonicalCsvPath
    CoordinateReviewCsvPath = $CoordinateReviewCsvPath
    ApprovalLedgerJsonPath = $ApprovalLedgerJsonPath
    SourceRowNumberOffset = $SourceRowNumberOffset
}

. (Join-Path $PSScriptRoot 'lib/release/approval-release-contracts.ps1')
. (Join-Path $PSScriptRoot 'invoke-phase3-review-audit.ps1')
. (Join-Path $PSScriptRoot 'lib/history/benefit-history-adapter.ps1')
. (Join-Path $PSScriptRoot 'lib/history/location-history-adapter.ps1')

function ConvertTo-InternalApprovalIdentityPart {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $normalized = $Value.Trim()
    $normalized = $normalized.Replace('서울특별시', '서울').Replace('서울시', '서울')
    $normalized = $normalized.Replace('경기도', '경기').Replace('인천광역시', '인천')
    return ($normalized -replace '[^0-9A-Za-z가-힣]', '').ToLowerInvariant()
}

function Get-InternalApprovalRowValue {
    param([AllowNull()]$Row, [Parameter(Mandatory)][string]$Name)

    if ($null -eq $Row) { return '' }
    $prop = $Row.PSObject.Properties[$Name]
    if ($null -eq $prop -or $null -eq $prop.Value) { return '' }
    return ([string]$prop.Value).Trim()
}

function Get-InternalApprovalReadOnlyStoreLayout {
    param([Parameter(Mandatory)][string]$HistoryRoot)

    $fullRoot = Assert-ReleaseSafeFilePath -Path $HistoryRoot
    if (-not (Test-Path -LiteralPath $fullRoot -PathType Container)) {
        throw "History store directory missing: $fullRoot"
    }
    return [pscustomobject][ordered]@{
        Root = $fullRoot
        RunsRoot = (Join-Path $fullRoot 'runs')
        ObservationsRoot = (Join-Path $fullRoot 'observations')
        ComparisonsRoot = (Join-Path $fullRoot 'comparisons')
        ArtifactsRoot = (Join-Path $fullRoot 'artifacts/sha256')
        IndexesRoot = (Join-Path $fullRoot 'indexes')
        TempRoot = (Join-Path $fullRoot 'tmp')
    }
}

function Read-InternalApprovalJsonFile {
    param([Parameter(Mandatory)][string]$Path, [int]$MaxBytes = 4194304)

    $safe = Assert-ReleaseSafeFilePath -Path $Path
    if (-not (Test-Path -LiteralPath $safe -PathType Leaf)) {
        throw "APV_JSON_MISSING: $safe"
    }
    $bytes = [IO.File]::ReadAllBytes($safe)
    if ($bytes.Length -gt $MaxBytes) {
        throw "APV_JSON_TOO_LARGE: $safe"
    }
    $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes).TrimStart([char]0xFEFF)
    $jsonOptions = @{}
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) {
        $jsonOptions.DateKind = 'String'
    }
    return ($text | ConvertFrom-Json @jsonOptions)
}

function Test-BenefitReleaseApprovalLedger {
    [CmdletBinding(DefaultParameterSetName = 'ByRoot')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByRoot')]
        [string]$HistoryRoot,
        [Parameter(Mandatory, ParameterSetName = 'ByStore')]
        $Store,
        [Parameter(Mandatory)]
        [string]$CanonicalCsvPath,
        [Parameter(Mandatory)]
        [string]$CoordinateReviewCsvPath,
        [Parameter(Mandatory)]
        [string]$ApprovalLedgerJsonPath,
        [int]$SourceRowNumberOffset = 2
    )

    if ($SourceRowNumberOffset -lt 1) {
        throw 'APV_ROW_OFFSET_INVALID'
    }

    $resolvedStore = if ($PSCmdlet.ParameterSetName -eq 'ByRoot') {
        Get-InternalApprovalReadOnlyStoreLayout -HistoryRoot $HistoryRoot
    } else {
        if ($null -eq $Store) { throw 'APV_STORE_REQUIRED' }
        foreach ($prop in @('Root', 'RunsRoot', 'ObservationsRoot', 'ComparisonsRoot', 'ArtifactsRoot', 'IndexesRoot', 'TempRoot')) {
            if ($Store.PSObject.Properties.Name -notcontains $prop -or [string]::IsNullOrWhiteSpace([string]$Store.$prop)) {
                throw "APV_STORE_PROPERTY_MISSING: $prop"
            }
            [void](Assert-ReleaseSafeFilePath -Path ([string]$Store.$prop))
            if ($prop -cne 'Root') {
                [void](Assert-HistoryStorePathWithinRoot -Store $Store -Path ([string]$Store.$prop))
            }
        }
        $Store
    }

    $safeCanonicalPath = Assert-ReleaseSafeFilePath -Path $CanonicalCsvPath
    if (-not (Test-Path -LiteralPath $safeCanonicalPath -PathType Leaf)) {
        throw "APV_CANONICAL_MISSING: $safeCanonicalPath"
    }
    $safeCoordReviewPath = Assert-ReleaseSafeFilePath -Path $CoordinateReviewCsvPath
    if (-not (Test-Path -LiteralPath $safeCoordReviewPath -PathType Leaf)) {
        throw "APV_COORD_REVIEW_MISSING: $safeCoordReviewPath"
    }

    $canonicalRows = @(Import-Csv -LiteralPath $safeCanonicalPath -Encoding utf8)
    if ($canonicalRows.Count -eq 0) {
        throw 'APV_CANONICAL_EMPTY'
    }
    Assert-CanonicalBusinessIds -Rows $canonicalRows
    $canonicalByBizId = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    $canonicalByRowNumber = [Collections.Generic.Dictionary[int, object]]::new()
    for ($i = 0; $i -lt $canonicalRows.Count; $i++) {
        $rowNumber = $i + $SourceRowNumberOffset
        $row = $canonicalRows[$i]
        $entry = [pscustomobject]@{ RowNumber = $rowNumber; Row = $row }
        $canonicalByBizId[[string]$row.businessId] = $entry
        $canonicalByRowNumber[$rowNumber] = $entry
    }

    $strictCoordinateRows = [Collections.Generic.HashSet[int]]::new()
    foreach ($reviewRow in @(Import-Csv -LiteralPath $safeCoordReviewPath -Encoding utf8)) {
        if ((Get-InternalApprovalRowValue $reviewRow '감사판정') -cne '확인 후보') {
            continue
        }
        $rowNumText = Get-InternalApprovalRowValue $reviewRow '정본CSV행번호'
        $parsedRowNum = 0
        if (-not [int]::TryParse($rowNumText, [ref]$parsedRowNum) -or -not $canonicalByRowNumber.ContainsKey($parsedRowNum)) {
            throw "APV_COORD_ROW_NOT_FOUND: $rowNumText"
        }
        $canonicalRow = $canonicalByRowNumber[$parsedRowNum].Row
        if ((ConvertTo-InternalApprovalIdentityPart (Get-InternalApprovalRowValue $canonicalRow '업소명')) -cne (ConvertTo-InternalApprovalIdentityPart (Get-InternalApprovalRowValue $reviewRow '업소명')) -or
            (ConvertTo-InternalApprovalIdentityPart (Get-InternalApprovalRowValue $canonicalRow '소재지도로명주소')) -cne (ConvertTo-InternalApprovalIdentityPart (Get-InternalApprovalRowValue $reviewRow '소재지도로명주소'))) {
            throw "APV_COORD_IDENTITY_MISMATCH: row $parsedRowNum"
        }
        if (-not $strictCoordinateRows.Add($parsedRowNum)) {
            throw "APV_COORD_DUPLICATE_CONFIRMED: row $parsedRowNum"
        }
    }

    $audit = Invoke-Phase3ReviewAudit -Store $resolvedStore
    $benefitReviewsByObsId = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    $locationReviewsByObsId = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($item in @($audit.Items)) {
        $obsId = [string]$item.CurrentObservationId
        if ([string]$item.Domain -ceq 'BENEFIT') {
            $benefitReviewsByObsId[$obsId] = $item
        } elseif ([string]$item.Domain -ceq 'LOCATION') {
            $locationReviewsByObsId[$obsId] = $item
        }
    }

    $ledger = Read-InternalApprovalJsonFile -Path $ApprovalLedgerJsonPath
    Assert-BenefitReleaseApprovalLedger -Ledger $ledger

    $approveActiveCount = 0
    $holdCount = 0
    $approveEndedCount = 0
    $keepPinCount = 0
    $suppressPinCount = 0

    foreach ($rec in @($ledger.Records)) {
        $bizId = [string]$rec.businessId
        if (-not $canonicalByBizId.ContainsKey($bizId)) {
            throw "APV_CANONICAL_BUSINESS_NOT_FOUND: $bizId"
        }
        $canonicalEntry = $canonicalByBizId[$bizId]
        $canonicalRow = $canonicalEntry.Row
        $rowNumber = [int]$canonicalEntry.RowNumber

        if ($rec.PSObject.Properties.Name -contains 'canonicalRowNumber' -and $null -ne $rec.canonicalRowNumber) {
            if ([int]$rec.canonicalRowNumber -ne $rowNumber) {
                throw "APV_CANONICAL_ROW_NUMBER_MISMATCH: $bizId (expected=$rowNumber actual=$($rec.canonicalRowNumber))"
            }
        }

        $obsId = [string]$rec.observationId
        if (-not $benefitReviewsByObsId.ContainsKey($obsId)) {
            throw "APV_OBSERVATION_NOT_COMMITTED_BENEFIT: $obsId"
        }
        $revItem = $benefitReviewsByObsId[$obsId]
        if ([string]$revItem.BusinessId -cne $bizId) {
            throw "APV_OBSERVATION_BUSINESS_MISMATCH: $obsId"
        }
        if ([string]$revItem.RunId -cne [string]$rec.targetRunId) {
            throw "APV_OBSERVATION_RUN_MISMATCH: $obsId"
        }
        if ([string]$revItem.ReviewKey -cne [string]$rec.reviewKey) {
            throw "APV_OBSERVATION_REVIEW_KEY_MISMATCH: $obsId"
        }

        $obs = Read-HistoryObservation -Store $resolvedStore -ObservationId $obsId
        if ($null -eq $obs) {
            throw "APV_OBSERVATION_FILE_MISSING: $obsId"
        }
        $semantic = Read-BenefitHistorySemanticProjection -Store $resolvedStore -Observation $obs

        $decision = [string]$rec.benefitDecision
        switch -CaseSensitive ($decision) {
            'APPROVE_ACTIVE' {
                if ([string]$obs.OperationalStatus -cne 'COMPLETE' -or -not [bool]$obs.Comparable) {
                    throw "APV_APPROVE_ACTIVE_REQUIRES_COMPLETE_COMPARABLE: $bizId ($obsId)"
                }
                if ([string]$semantic.ReviewClass -cne 'GREEN' -and [string]::IsNullOrWhiteSpace([string]$rec.rationale)) {
                    throw "APV_APPROVE_ACTIVE_NON_GREEN_REQUIRES_RATIONALE: $bizId ($($semantic.ReviewClass))"
                }
                $approveActiveCount++
            }
            'HOLD_NEEDS_VERIFICATION' {
                $holdCount++
            }
            'APPROVE_ENDED' {
                if ([string]::IsNullOrWhiteSpace([string]$rec.rationale)) {
                    throw "APV_APPROVE_ENDED_REQUIRES_RATIONALE: $bizId"
                }
                if ([string]$rec.coordinateDecision -cne 'SUPPRESS_PIN') {
                    throw "APV_APPROVE_ENDED_REQUIRES_SUPPRESS_PIN: $bizId"
                }
                $approveEndedCount++
            }
            default {
                throw "APV_UNSUPPORTED_BENEFIT_DECISION: $decision"
            }
        }

        $coordDecision = [string]$rec.coordinateDecision
        if ($coordDecision -ceq 'KEEP_PIN') {
            $coordStatus = Get-InternalApprovalRowValue $canonicalRow '좌표검증상태'
            if ($coordStatus -cne '확인 완료') {
                throw "APV_KEEP_PIN_REQUIRES_CONFIRMED_CANONICAL_COORDINATE: $bizId (actual='$coordStatus')"
            }
            $latText = Get-InternalApprovalRowValue $canonicalRow '위도'
            $lonText = Get-InternalApprovalRowValue $canonicalRow '경도'
            $lat = 0.0
            $lon = 0.0
            $inv = [Globalization.CultureInfo]::InvariantCulture
            if ([string]::IsNullOrWhiteSpace($latText) -or
                [string]::IsNullOrWhiteSpace($lonText) -or
                -not [double]::TryParse($latText, [Globalization.NumberStyles]::Float, $inv, [ref]$lat) -or
                -not [double]::TryParse($lonText, [Globalization.NumberStyles]::Float, $inv, [ref]$lon) -or
                $lat -lt 33.0 -or $lat -gt 39.0 -or $lon -lt 124.0 -or $lon -gt 132.0) {
                throw "APV_KEEP_PIN_REQUIRES_VALID_KOREA_WGS84: $bizId"
            }
            if (-not $strictCoordinateRows.Contains($rowNumber)) {
                throw "APV_KEEP_PIN_REQUIRES_STRICT_COORDINATE_REVIEW: $bizId (row $rowNumber)"
            }
            $keepPinCount++
        } else {
            $suppressPinCount++
        }

        if ($rec.PSObject.Properties.Name -contains 'locationObservationId' -and
            $null -ne $rec.locationObservationId -and
            -not [string]::IsNullOrWhiteSpace([string]$rec.locationObservationId)) {
            $locObsId = [string]$rec.locationObservationId
            if (-not $locationReviewsByObsId.ContainsKey($locObsId)) {
                throw "APV_LOCATION_OBSERVATION_NOT_COMMITTED: $locObsId"
            }
            $locRev = $locationReviewsByObsId[$locObsId]
            if ([string]$locRev.BusinessId -cne $bizId) {
                throw "APV_LOCATION_OBSERVATION_BUSINESS_MISMATCH: $locObsId"
            }
            $locObs = Read-HistoryObservation -Store $resolvedStore -ObservationId $locObsId
            if ($null -eq $locObs -or [string]$locObs.OperationalStatus -cne 'COMPLETE' -or -not [bool]$locObs.Comparable) {
                throw "APV_LOCATION_OBSERVATION_NOT_COMPLETE_COMPARABLE: $locObsId"
            }
            [void](Read-LocationHistorySemanticProjection -Store $resolvedStore -Observation $locObs)
        }
    }

    return [pscustomobject][ordered]@{
        ValidationStatus = 'VALID'
        RecordCount = @($ledger.Records).Count
        ApproveActiveCount = $approveActiveCount
        HoldCount = $holdCount
        ApproveEndedCount = $approveEndedCount
        KeepPinCount = $keepPinCount
        SuppressPinCount = $suppressPinCount
        ProductionAction = 'NONE'
    }
}

if ($script:ValidateApprovalsCliInvoked) {
    $cliArgs = $script:ValidateApprovalsCliParams
    if ([string]::IsNullOrWhiteSpace($cliArgs.HistoryRoot) -or
        [string]::IsNullOrWhiteSpace($cliArgs.CanonicalCsvPath) -or
        [string]::IsNullOrWhiteSpace($cliArgs.CoordinateReviewCsvPath) -or
        [string]::IsNullOrWhiteSpace($cliArgs.ApprovalLedgerJsonPath)) {
        throw 'APV_CLI_PARAMETERS_REQUIRED: -HistoryRoot, -CanonicalCsvPath, -CoordinateReviewCsvPath, and -ApprovalLedgerJsonPath are required.'
    }

    Test-BenefitReleaseApprovalLedger @cliArgs
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '../history/history-contracts.ps1')
. (Join-Path $PSScriptRoot '../identity/canonical-business-id.ps1')

function Get-ReleaseNormalizedLfSha256 {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $stripped = if ($Text.Length -gt 0 -and $Text[0] -eq [char]0xFEFF) {
        $Text.Substring(1)
    } else {
        $Text
    }
    $normalized = $stripped.Replace("`r`n", "`n").Replace("`r", "`n")
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($normalized)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
        return ([BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Assert-ReleaseSafeFilePath {
    param([Parameter(Mandatory)][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -match '(^|[/\\])\.\.([/\\]|$)') {
        throw "REL_UNSAFE_PATH: $Path"
    }
    $full = [IO.Path]::GetFullPath($Path)
    $ancestor = $full
    while (-not [string]::IsNullOrEmpty($ancestor)) {
        if (Test-Path -LiteralPath $ancestor) {
            if ((Get-Item -LiteralPath $ancestor -Force).Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) {
                throw "REL_REPARSE_PATH: $ancestor"
            }
        }
        $ancestor = [IO.Path]::GetDirectoryName($ancestor)
    }
    return $full
}

function Read-ReleaseUtf8Text {
    param([Parameter(Mandatory)][string]$Path)

    $safe = Assert-ReleaseSafeFilePath -Path $Path
    if (-not (Test-Path -LiteralPath $safe -PathType Leaf)) {
        throw "REL_FILE_MISSING: $safe"
    }
    $bytes = [IO.File]::ReadAllBytes($safe)
    return [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
}

function Get-ReleaseFileNormalizedLfSha256 {
    param([Parameter(Mandatory)][string]$Path)

    $text = Read-ReleaseUtf8Text -Path $Path
    return Get-ReleaseNormalizedLfSha256 -Text $text
}

function Test-ReleaseCalendarDate {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -cnotmatch '^\d{4}-\d{2}-\d{2}$') {
        return $false
    }
    $parsed = [datetime]::MinValue
    return [datetime]::TryParseExact(
        $Value,
        'yyyy-MM-dd',
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::None,
        [ref]$parsed
    )
}

function Test-ReleaseIso8601WithOffset {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -cne $Value.Trim()) {
        return $false
    }
    if ($Value -cnotmatch '^(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,9}))?(Z|([+-])(\d{2}):(\d{2}))$') {
        return $false
    }
    $datePart = $Matches[1]
    if (-not (Test-ReleaseCalendarDate -Value $datePart)) {
        return $false
    }
    $hour = [int]$Matches[2]
    $minute = [int]$Matches[3]
    $second = [int]$Matches[4]
    if ($hour -lt 0 -or $hour -gt 23 -or $minute -lt 0 -or $minute -gt 59 -or $second -lt 0 -or $second -gt 59) {
        return $false
    }
    if ($Matches[6] -cne 'Z') {
        $offHour = [int]$Matches[8]
        $offMin = [int]$Matches[9]
        if ($offMin -lt 0 -or $offMin -gt 59 -or $offHour -lt 0 -or $offHour -gt 14 -or ($offHour -eq 14 -and $offMin -ne 0)) {
            return $false
        }
    }
    $parsed = [DateTimeOffset]::MinValue
    return [DateTimeOffset]::TryParse(
        $Value,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::RoundtripKind,
        [ref]$parsed
    )
}

function Test-ReleaseHttpUrlList {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -cne $Value.Trim()) {
        return $false
    }
    $parts = $Value.Split(@(' | '), [StringSplitOptions]::None)
    if ($parts.Count -lt 1) { return $false }
    foreach ($part in $parts) {
        if ([string]::IsNullOrWhiteSpace($part) -or $part -cne $part.Trim()) {
            return $false
        }
        $uri = $null
        if (-not [uri]::TryCreate($part, [UriKind]::Absolute, [ref]$uri)) {
            return $false
        }
        if ($uri.Scheme -notin @('http', 'https') -or
            [string]::IsNullOrWhiteSpace($uri.Host) -or
            -not [string]::IsNullOrEmpty($uri.UserInfo)) {
            return $false
        }
    }
    return $true
}

function Test-ReleaseHumanApprover {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -cne $Value.Trim()) {
        return $false
    }
    $upper = $Value.ToUpperInvariant()
    if ($upper -in @('AUTO', 'AUTOMATIC', 'SYSTEM', 'BOT', 'UNKNOWN', 'NONE', 'N/A', 'NULL', 'ADMIN_BOT')) {
        return $false
    }
    if ($upper -match '^(AUTO|SYSTEM|BOT)[-_:\s]') {
        return $false
    }
    return $true
}

function Assert-ReleaseExactObjectProperties {
    param(
        [AllowNull()]$Value,
        [Parameter(Mandatory)][string[]]$RequiredProperties,
        [string[]]$OptionalProperties = @(),
        [Parameter(Mandatory)][string]$Kind
    )

    if ($null -eq $Value -or $Value -isnot [pscustomobject]) {
        throw "${Kind}: must be a JSON object"
    }
    $names = @($Value.PSObject.Properties | ForEach-Object { [string]$_.Name })
    $allowed = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($p in $RequiredProperties) { [void]$allowed.Add($p) }
    foreach ($p in $OptionalProperties) { [void]$allowed.Add($p) }
    foreach ($req in $RequiredProperties) {
        if ($names -cnotcontains $req) {
            throw "${Kind}: missing required property '$req'"
        }
    }
    foreach ($actual in $names) {
        if (-not $allowed.Contains($actual)) {
            throw "${Kind}: unexpected property '$actual'"
        }
    }
}

function Assert-BenefitReleaseApprovalRecord {
    param([Parameter(Mandatory)]$Record)

    Assert-ReleaseExactObjectProperties `
        -Value $Record `
        -RequiredProperties @(
            'businessId', 'reviewKey', 'targetRunId', 'observationId',
            'benefitDecision', 'coordinateDecision', 'verifiedSourceUrl',
            'verifiedOn', 'approvedBy', 'approvedAt', 'rationale'
        ) `
        -OptionalProperties @('canonicalRowNumber', 'locationObservationId') `
        -Kind 'BenefitReleaseApprovalRecord'

    Assert-HistoryBusinessId -Value ([string]$Record.businessId)
    if ($Record.PSObject.Properties.Name -contains 'canonicalRowNumber' -and $null -ne $Record.canonicalRowNumber) {
        $rn = $Record.canonicalRowNumber
        if (($rn -isnot [int] -and $rn -isnot [long]) -or [int]$rn -lt 2) {
            throw 'BenefitReleaseApprovalRecord: canonicalRowNumber must be an integer >= 2'
        }
    }
    Assert-HistoryToken -Value ([string]$Record.reviewKey) -Name 'reviewKey'
    Assert-HistoryToken -Value ([string]$Record.targetRunId) -Name 'targetRunId'
    Assert-HistoryToken -Value ([string]$Record.observationId) -Name 'observationId'
    if ($Record.PSObject.Properties.Name -contains 'locationObservationId' -and
        $null -ne $Record.locationObservationId -and
        -not [string]::IsNullOrWhiteSpace([string]$Record.locationObservationId)) {
        Assert-HistoryToken -Value ([string]$Record.locationObservationId) -Name 'locationObservationId'
    }

    if ([string]$Record.benefitDecision -cnotin @('APPROVE_ACTIVE', 'HOLD_NEEDS_VERIFICATION', 'APPROVE_ENDED')) {
        throw "BenefitReleaseApprovalRecord: invalid benefitDecision '$($Record.benefitDecision)'"
    }
    if ([string]$Record.coordinateDecision -cnotin @('KEEP_PIN', 'SUPPRESS_PIN')) {
        throw "BenefitReleaseApprovalRecord: invalid coordinateDecision '$($Record.coordinateDecision)'"
    }
    if (-not (Test-ReleaseHttpUrlList -Value ([string]$Record.verifiedSourceUrl))) {
        throw "BenefitReleaseApprovalRecord: invalid verifiedSourceUrl '$($Record.verifiedSourceUrl)'"
    }
    if (-not (Test-ReleaseCalendarDate -Value ([string]$Record.verifiedOn))) {
        throw "BenefitReleaseApprovalRecord: invalid verifiedOn '$($Record.verifiedOn)'"
    }
    if (-not (Test-ReleaseHumanApprover -Value ([string]$Record.approvedBy))) {
        throw "BenefitReleaseApprovalRecord: invalid approvedBy '$($Record.approvedBy)'"
    }
    if (-not (Test-ReleaseIso8601WithOffset -Value ([string]$Record.approvedAt))) {
        throw "BenefitReleaseApprovalRecord: invalid approvedAt '$($Record.approvedAt)'"
    }
    if ($null -eq $Record.rationale -or $Record.rationale -isnot [string]) {
        throw 'BenefitReleaseApprovalRecord: rationale must be a string'
    }
    if ([string]$Record.benefitDecision -ceq 'APPROVE_ENDED') {
        if ([string]::IsNullOrWhiteSpace([string]$Record.rationale)) {
            throw 'BenefitReleaseApprovalRecord: APPROVE_ENDED requires non-blank rationale'
        }
        if ([string]$Record.coordinateDecision -cne 'SUPPRESS_PIN') {
            throw 'BenefitReleaseApprovalRecord: APPROVE_ENDED requires coordinateDecision SUPPRESS_PIN'
        }
    }
}

function Assert-BenefitReleaseApprovalLedger {
    param([Parameter(Mandatory)]$Ledger)

    Assert-ReleaseExactObjectProperties `
        -Value $Ledger `
        -RequiredProperties @('ContractType', 'ContractVersion', 'Records') `
        -Kind 'BenefitReleaseApprovalLedger'

    if ([string]$Ledger.ContractType -cne 'BenefitReleaseApprovalLedger') {
        throw 'BenefitReleaseApprovalLedger: invalid ContractType'
    }
    if (($Ledger.ContractVersion -isnot [int] -and $Ledger.ContractVersion -isnot [long]) -or [int]$Ledger.ContractVersion -ne 1) {
        throw 'BenefitReleaseApprovalLedger: unsupported ContractVersion'
    }
    if ($null -eq $Ledger.Records -or $Ledger.Records -isnot [array]) {
        throw 'BenefitReleaseApprovalLedger: Records must be an array'
    }
    $seenBizIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($rec in $Ledger.Records) {
        Assert-BenefitReleaseApprovalRecord -Record $rec
        $bizId = [string]$rec.businessId
        if (-not $seenBizIds.Add($bizId)) {
            throw "BenefitReleaseApprovalLedger: duplicate businessId '$bizId'"
        }
    }
}

function Assert-BenefitReleaseSeedManifest {
    param([Parameter(Mandatory)]$Manifest)

    $required = @(
        'manifestVersion', 'seedName', 'seedVersion', 'hashAlgorithm',
        'generatedAt', 'canonicalCsvSha256', 'totalCount', 'exactPinCount',
        'unconfirmedCoordinateCount', 'seedSha256', 'manualSeedCount', 'manualSeedSha256'
    )
    Assert-ReleaseExactObjectProperties `
        -Value $Manifest `
        -RequiredProperties $required `
        -Kind 'BenefitReleaseSeedManifest'

    foreach ($intField in @('manifestVersion', 'seedVersion', 'totalCount', 'exactPinCount', 'unconfirmedCoordinateCount', 'manualSeedCount')) {
        $v = $Manifest.$intField
        if ($v -isnot [int] -and $v -isnot [long]) {
            throw "BenefitReleaseSeedManifest: '$intField' must be an integer"
        }
    }
    if ([int]$Manifest.manifestVersion -ne 1) {
        throw 'BenefitReleaseSeedManifest: manifestVersion must be 1'
    }
    if ([string]$Manifest.seedName -cne 'benefits') {
        throw 'BenefitReleaseSeedManifest: seedName must be benefits'
    }
    if ([int]$Manifest.seedVersion -lt 1) {
        throw 'BenefitReleaseSeedManifest: seedVersion must be >= 1'
    }
    if ([string]$Manifest.hashAlgorithm -cne 'SHA-256-LF-UTF8') {
        throw 'BenefitReleaseSeedManifest: hashAlgorithm must be SHA-256-LF-UTF8'
    }
    if (-not (Test-ReleaseIso8601WithOffset -Value ([string]$Manifest.generatedAt))) {
        throw "BenefitReleaseSeedManifest: invalid generatedAt '$($Manifest.generatedAt)'"
    }
    Assert-HistoryHash -Value ([string]$Manifest.canonicalCsvSha256) -Name 'canonicalCsvSha256'
    Assert-HistoryHash -Value ([string]$Manifest.seedSha256) -Name 'seedSha256'
    Assert-HistoryHash -Value ([string]$Manifest.manualSeedSha256) -Name 'manualSeedSha256'

    if ([int]$Manifest.totalCount -lt 1) {
        throw 'BenefitReleaseSeedManifest: totalCount must be >= 1'
    }
    if ([int]$Manifest.exactPinCount -lt 0 -or [int]$Manifest.unconfirmedCoordinateCount -lt 0) {
        throw 'BenefitReleaseSeedManifest: pin counts cannot be negative'
    }
    if (([int]$Manifest.exactPinCount + [int]$Manifest.unconfirmedCoordinateCount) -ne [int]$Manifest.totalCount) {
        throw 'BenefitReleaseSeedManifest: exactPinCount + unconfirmedCoordinateCount must equal totalCount'
    }
    if ([int]$Manifest.manualSeedCount -lt 0) {
        throw 'BenefitReleaseSeedManifest: manualSeedCount cannot be negative'
    }
}

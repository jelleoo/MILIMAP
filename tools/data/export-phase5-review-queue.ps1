[CmdletBinding()]
param(
    [string]$HistoryRoot = '',
    [string]$CanonicalCsvPath = '',
    [string]$OutputDirectory = '',
    [ValidateSet('ALL', 'BENEFIT', 'LOCATION')]
    [string]$Domain = 'ALL',
    [switch]$IncludeSuperseded,
    [int]$SourceRowNumberOffset = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Capture CLI parameters before dot-sourcing history adapters that overwrite script-scope $historyRoot.
$script:ExportReviewQueueCliInvoked = ($PSBoundParameters.Count -gt 0)
$script:ExportReviewQueueCliParams = @{
    HistoryRoot = $HistoryRoot
    CanonicalCsvPath = $CanonicalCsvPath
    OutputDirectory = $OutputDirectory
    Domain = $Domain
    IncludeSuperseded = [bool]$IncludeSuperseded
    SourceRowNumberOffset = $SourceRowNumberOffset
}

. (Join-Path $PSScriptRoot 'invoke-phase3-review-audit.ps1')
. (Join-Path $PSScriptRoot 'invoke-phase5-benefit-cycle.ps1')
. (Join-Path $PSScriptRoot 'lib/identity/canonical-business-id.ps1')
. (Join-Path $PSScriptRoot 'lib/history/location-history-adapter.ps1')

function Assert-InternalPhase5ReviewQueueExternalOutputDirectory {
    param(
        [Parameter(Mandatory)][string]$OutputDirectory,
        [Parameter(Mandatory)]$Store
    )

    if ([string]::IsNullOrWhiteSpace($OutputDirectory) -or $OutputDirectory -match '(^|[/\\])\.\.([/\\]|$)') {
        throw 'RQ_UNSAFE_OUTPUT_PATH'
    }

    $safeOutput = Assert-Phase5BenefitExternalPath -Path $OutputDirectory
    $outNorm = $safeOutput.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $histNorm = [IO.Path]::GetFullPath([string]$Store.Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $cmp = [StringComparison]::OrdinalIgnoreCase
    if ($outNorm.Equals($histNorm, $cmp) -or
        $outNorm.StartsWith($histNorm + [IO.Path]::DirectorySeparatorChar, $cmp) -or
        $histNorm.StartsWith($outNorm + [IO.Path]::DirectorySeparatorChar, $cmp)) {
        throw 'RQ_OUTPUT_OVERLAPS_HISTORY_STORE'
    }
    return $safeOutput
}

function Assert-InternalPhase5ReviewQueueSafePath {
    param([Parameter(Mandatory)][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -match '(^|[/\\])\.\.([/\\]|$)') {
        throw 'RQ_UNSAFE_INPUT_PATH'
    }
    $full = [IO.Path]::GetFullPath($Path)
    $ancestor = $full
    while (-not [string]::IsNullOrEmpty($ancestor)) {
        if (Test-Path -LiteralPath $ancestor) {
            if ((Get-Item -LiteralPath $ancestor -Force).Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) {
                throw 'RQ_REPARSE_PATH'
            }
        }
        $ancestor = [IO.Path]::GetDirectoryName($ancestor)
    }
    return $full
}

function Get-InternalPhase5ReviewQueueReadOnlyStoreLayout {
    param([Parameter(Mandatory)][string]$HistoryRoot)

    $fullRoot = Assert-InternalPhase5ReviewQueueSafePath -Path $HistoryRoot
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

function Read-InternalPhase5ReviewQueueJsonFile {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)][string]$Path,
        [int]$MaxBytes = 2097152
    )

    $safePath = Assert-HistoryStorePathWithinRoot -Store $Store -Path $Path
    $storeRoot = [IO.Path]::GetFullPath([string]$Store.Root)
    $ancestor = $safePath
    while (-not [string]::IsNullOrEmpty($ancestor)) {
        if (Test-Path -LiteralPath $ancestor) {
            if ((Get-Item -LiteralPath $ancestor -Force).Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) {
                throw 'RQ_REPARSE_PATH'
            }
        }
        if ($ancestor.Equals($storeRoot, [StringComparison]::OrdinalIgnoreCase)) { break }
        $ancestor = [IO.Path]::GetDirectoryName($ancestor)
    }
    if (-not (Test-Path -LiteralPath $safePath -PathType Leaf)) {
        return $null
    }
    $bytes = [IO.File]::ReadAllBytes($safePath)
    if ($bytes.Length -gt $MaxBytes) {
        throw "RQ_JSON_TOO_LARGE: $safePath"
    }
    $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes).TrimStart([char]0xFEFF)
    $jsonOptions = @{}
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) {
        $jsonOptions.DateKind = 'String'
    }
    return ($text | ConvertFrom-Json @jsonOptions)
}

function Read-InternalPhase5ReviewQueueBenefitEvidenceProjection {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)]$Observation
    )

    $references = @($Observation.ArtifactReferences | Where-Object { [string]$_.Kind -ceq 'BENEFIT_EVIDENCE_PROJECTION' })
    if ($references.Count -eq 0) {
        return $null
    }
    if ($references.Count -ne 1) {
        throw 'Observation cannot contain multiple BENEFIT_EVIDENCE_PROJECTION artifacts'
    }

    $reference = $references[0]
    Assert-HistoryArtifactReferenceExists -Store $Store -Reference $reference
    $path = Join-Path $Store.Root ([string]$reference.RelativePath)
    $projection = Read-InternalPhase5ReviewQueueJsonFile -Store $Store -Path $path -MaxBytes 1048576
    if ($null -eq $projection) {
        throw 'Benefit evidence projection artifact is missing'
    }
    if ([string]$projection.ProjectionType -cne 'BenefitHistoryEvidence' -or [int]$projection.ProjectionVersion -ne 1) {
        throw 'Unsupported benefit evidence projection'
    }
    $fingerprint = Get-HistoryFingerprint -Projection $projection -SchemaVersion 1 -OrderInsensitivePaths @('Sources', 'Sources[].CandidateReferences')
    if ($fingerprint -cne [string]$Observation.EvidenceFingerprint) {
        throw 'Benefit evidence projection fingerprint mismatch'
    }
    return $projection
}

function Write-InternalPhase5ReviewQueueAtomicText {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        [void][IO.Directory]::CreateDirectory($directory)
    }
    $normalized = $Content.Replace("`r`n", "`n").Replace("`r", "`n")
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($normalized)
    $tempPath = Join-Path $directory ('.rq-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllBytes($tempPath, $bytes)
        [IO.File]::Move($tempPath, $Path, $true)
    } finally {
        if (Test-Path -LiteralPath $tempPath) {
            [IO.File]::Delete($tempPath)
        }
    }
}

function Get-InternalPhase5ReviewQueueRowValue {
    param(
        [AllowNull()]$Row,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $Row) { return '' }
    $prop = $Row.PSObject.Properties[$Name]
    if ($null -eq $prop -or $null -eq $prop.Value) { return '' }
    return ([string]$prop.Value).Trim()
}

function Export-Phase5ReviewQueue {
    [CmdletBinding(DefaultParameterSetName = 'ByRoot')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByRoot')]
        [string]$HistoryRoot,
        [Parameter(Mandatory, ParameterSetName = 'ByStore')]
        $Store,
        [Parameter(Mandatory)]
        [string]$CanonicalCsvPath,
        [Parameter(Mandatory)]
        [string]$OutputDirectory,
        [ValidateSet('ALL', 'BENEFIT', 'LOCATION')]
        [string]$Domain = 'ALL',
        [switch]$IncludeSuperseded,
        [int]$SourceRowNumberOffset = 2
    )

    if ($SourceRowNumberOffset -lt 1) {
        throw 'RQ_ROW_OFFSET_INVALID'
    }

    $resolvedStore = if ($PSCmdlet.ParameterSetName -eq 'ByRoot') {
        Get-InternalPhase5ReviewQueueReadOnlyStoreLayout -HistoryRoot $HistoryRoot
    } else {
        if ($null -eq $Store) { throw 'RQ_STORE_REQUIRED' }
        foreach ($prop in @('Root', 'RunsRoot', 'ObservationsRoot', 'ComparisonsRoot', 'ArtifactsRoot', 'IndexesRoot', 'TempRoot')) {
            if ($Store.PSObject.Properties.Name -notcontains $prop -or [string]::IsNullOrWhiteSpace([string]$Store.$prop)) {
                throw "RQ_STORE_PROPERTY_MISSING: $prop"
            }
            [void](Assert-InternalPhase5ReviewQueueSafePath -Path ([string]$Store.$prop))
            if ($prop -cne 'Root') {
                [void](Assert-HistoryStorePathWithinRoot -Store $Store -Path ([string]$Store.$prop))
            }
        }
        $Store
    }

    $safeOutputDir = Assert-InternalPhase5ReviewQueueExternalOutputDirectory -OutputDirectory $OutputDirectory -Store $resolvedStore
    $safeCanonicalPath = Assert-InternalPhase5ReviewQueueSafePath -Path $CanonicalCsvPath
    if (-not (Test-Path -LiteralPath $safeCanonicalPath -PathType Leaf)) {
        throw "RQ_CANONICAL_CSV_MISSING: $safeCanonicalPath"
    }

    $canonicalRows = @(Import-Csv -LiteralPath $safeCanonicalPath -Encoding utf8)
    Assert-CanonicalBusinessIds -Rows $canonicalRows
    $canonicalByBusinessId = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    for ($i = 0; $i -lt $canonicalRows.Count; $i++) {
        $row = $canonicalRows[$i]
        $bizId = [string]$row.businessId
        $canonicalByBusinessId[$bizId] = [pscustomobject]@{
            RowNumber = $i + $SourceRowNumberOffset
            Row = $row
        }
    }

    $audit = Invoke-Phase3ReviewAudit -Store $resolvedStore
    $domainFiltered = @(
        $audit.Items | Where-Object {
            $Domain -ceq 'ALL' -or [string]$_.Domain -ceq $Domain
        }
    )

    $hydratedEntries = [Collections.Generic.List[object]]::new()
    foreach ($auditItem in $domainFiltered) {
        $obsId = [string]$auditItem.CurrentObservationId
        $obsPath = Get-HistoryObservationPath -Store $resolvedStore -ObservationId $obsId
        $rawObs = Read-InternalPhase5ReviewQueueJsonFile -Store $resolvedStore -Path $obsPath -MaxBytes 1048576
        if ($null -eq $rawObs) {
            throw "RQ_COMMITTED_OBSERVATION_MISSING: $obsId"
        }
        Assert-HistoryObservation $rawObs
        $observedAtStr = [string]$rawObs.ObservedAt
        $observedAtUtc = [DateTimeOffset]::Parse($observedAtStr, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
        $hydratedEntries.Add([pscustomobject]@{
            AuditItem = $auditItem
            Observation = $rawObs
            ObservedAt = $observedAtStr
            ObservedAtUtcTicks = $observedAtUtc.UtcTicks
        })
    }

    $selectedEntries = [Collections.Generic.List[object]]::new()
    $supersededExcludedCount = 0
    if ($IncludeSuperseded) {
        foreach ($entry in $hydratedEntries) {
            $selectedEntries.Add($entry)
        }
    } else {
        $grouped = @($hydratedEntries | Group-Object -Property { "$($_.AuditItem.BusinessId)|$($_.AuditItem.Domain)" })
        foreach ($group in $grouped) {
            $ordered = @($group.Group | Sort-Object `
                @{ Expression = { $_.ObservedAtUtcTicks } }, `
                @{ Expression = { [string]$_.AuditItem.CurrentObservationId } })
            $selectedEntries.Add($ordered[-1])
            $supersededExcludedCount += ($ordered.Count - 1)
        }
    }

    $exportedItems = [Collections.Generic.List[object]]::new()
    foreach ($entry in $selectedEntries) {
        $auditItem = $entry.AuditItem
        $rawObs = $entry.Observation
        $bizId = [string]$rawObs.BusinessId
        $itemDomain = [string]$rawObs.Domain
        $opStatus = [string]$rawObs.OperationalStatus
        $comparable = [bool]$rawObs.Comparable
        $route = [string]$auditItem.ReviewRoute

        $canonicalMissing = -not $canonicalByBusinessId.ContainsKey($bizId)
        $canonicalRowNumber = $null
        $businessName = ''
        $district = ''
        $roadAddress = ''
        $canonicalBenefitStatus = ''
        $canonicalCoordinateStatus = ''
        $canonicalSourceUrl = ''
        $canonicalLastVerifiedAt = ''
        if (-not $canonicalMissing) {
            $canonicalEntry = $canonicalByBusinessId[$bizId]
            $canonicalRowNumber = [int]$canonicalEntry.RowNumber
            $cRow = $canonicalEntry.Row
            $businessName = Get-InternalPhase5ReviewQueueRowValue $cRow '업소명'
            $district = Get-InternalPhase5ReviewQueueRowValue $cRow '시군구'
            $roadAddress = Get-InternalPhase5ReviewQueueRowValue $cRow '소재지도로명주소'
            $canonicalBenefitStatus = Get-InternalPhase5ReviewQueueRowValue $cRow '혜택상태'
            $canonicalCoordinateStatus = Get-InternalPhase5ReviewQueueRowValue $cRow '좌표검증상태'
            $canonicalSourceUrl = Get-InternalPhase5ReviewQueueRowValue $cRow '출처URL'
            $canonicalLastVerifiedAt = Get-InternalPhase5ReviewQueueRowValue $cRow '최근확인일'
        }

        $semanticAvailable = $false
        $benefitState = $null
        $reviewClass = $null
        $businessPresence = $null
        $absenceEligible = $null
        $validatedClaimSummary = @()
        $sourceUrls = @()
        $sourceFormats = @()
        $sourceContentHashes = @()
        $sourceLocationStatuses = @()
        $locationEvaluationStatus = $null
        $locationClassification = $null
        $locationSelectionStatus = $null
        $locationSelectedLatitude = $null
        $locationSelectedLongitude = $null
        $materialReasonCodes = @()
        $conflictCodes = @()

        if ($itemDomain -ceq 'BENEFIT') {
            $semanticRefs = @($rawObs.ArtifactReferences | Where-Object { [string]$_.Kind -ceq 'BENEFIT_SEMANTIC_PROJECTION' })
            $hasSemanticRef = ($semanticRefs.Count -gt 0 -or -not [string]::IsNullOrWhiteSpace([string]$rawObs.SemanticResultReference))
            if ($hasSemanticRef) {
                $semantic = Read-BenefitHistorySemanticProjection -Store $resolvedStore -Observation $rawObs
                $semanticAvailable = $true
                $benefitState = [string]$semantic.BenefitState
                $reviewClass = [string]$semantic.ReviewClass
                $businessPresence = [string]$semantic.BusinessPresence
                $absenceEligible = [bool]$semantic.AbsenceEligible
                $materialReasonCodes = @($semantic.MaterialReasonCodes | ForEach-Object { [string]$_ })
                $validatedClaimSummary = @(
                    $semantic.Claims | Where-Object {
                        [string]$_.ValidationStatus -ceq 'VALIDATED'
                    } | ForEach-Object {
                        [pscustomobject][ordered]@{
                            ClaimType = [string]$_.ClaimType
                            SemanticValue = [string]$_.SemanticValue
                            ClaimResult = [string]$_.ClaimResult
                            BusinessBound = [bool]$_.BusinessBound
                        }
                    }
                )
            }

            $evidenceProj = Read-InternalPhase5ReviewQueueBenefitEvidenceProjection -Store $resolvedStore -Observation $rawObs
            if ($null -ne $evidenceProj) {
                $sourceUrls = @($evidenceProj.Sources | ForEach-Object { [string]$_.SourceUrl } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
                $sourceFormats = @($evidenceProj.Sources | ForEach-Object { [string]$_.SourceFormat } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
                $sourceContentHashes = @($evidenceProj.Sources | ForEach-Object { [string]$_.ContentHash } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
                $sourceLocationStatuses = @($evidenceProj.Sources | ForEach-Object { [string]$_.LocationStatus } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
            }
        } elseif ($itemDomain -ceq 'LOCATION') {
            $semanticRefs = @($rawObs.ArtifactReferences | Where-Object { [string]$_.Kind -ceq 'LOCATION_SEMANTIC_PROJECTION' })
            $hasSemanticRef = ($semanticRefs.Count -gt 0 -or -not [string]::IsNullOrWhiteSpace([string]$rawObs.SemanticResultReference))
            if ($hasSemanticRef) {
                $semantic = Read-LocationHistorySemanticProjection -Store $resolvedStore -Observation $rawObs
                $semanticAvailable = $true
                $locationEvaluationStatus = [string]$semantic.EvaluationStatus
                $locationClassification = [string]$semantic.Classification
                $locationSelectionStatus = [string]$semantic.SelectionStatus
                if ($null -ne $semantic.SelectedLocation) {
                    $locationSelectedLatitude = $semantic.SelectedLocation.Latitude
                    $locationSelectedLongitude = $semantic.SelectedLocation.Longitude
                }
                $materialReasonCodes = @($semantic.MaterialReasonCodes | ForEach-Object { [string]$_ })
                $conflictCodes = @($semantic.ConflictCodes | ForEach-Object { [string]$_ })
            }
        } else {
            throw "RQ_UNSUPPORTED_DOMAIN: $itemDomain"
        }

        $diagnosticReasons = [Collections.Generic.List[string]]::new()
        if ($canonicalMissing) { [void]$diagnosticReasons.Add('CANONICAL_ROW_MISSING') }
        if (-not $semanticAvailable) { [void]$diagnosticReasons.Add('SEMANTIC_PROJECTION_UNAVAILABLE') }
        if ($opStatus -cne 'COMPLETE') { [void]$diagnosticReasons.Add("OPERATIONAL_STATUS_$opStatus") }
        if (-not $comparable) { [void]$diagnosticReasons.Add('NON_COMPARABLE_OBSERVATION') }
        foreach ($nc in @($rawObs.NonComparableReasons)) {
            $code = [string]$nc
            if (-not [string]::IsNullOrWhiteSpace($code) -and -not $diagnosticReasons.Contains($code)) {
                [void]$diagnosticReasons.Add($code)
            }
        }

        if ($route -cin @('AUDIT_VERIFICATION', 'OPERATIONAL_DIAGNOSTIC') -or
            $opStatus -cne 'COMPLETE' -or
            -not $comparable -or
            $canonicalMissing -or
            -not $semanticAvailable) {
            $bucket = 'DIAGNOSTIC_HOLD'
        } elseif ($route -ceq 'RECORD_ONLY' -and (
            ($itemDomain -ceq 'BENEFIT' -and $reviewClass -ceq 'GREEN' -and $benefitState -ceq 'ACTIVE') -or
            ($itemDomain -ceq 'LOCATION' -and $locationClassification -ceq 'GREEN')
        )) {
            $bucket = 'FAST_REVIEW'
        } else {
            $bucket = 'DOMAIN_REVIEW'
        }

        $bucketPriority = switch -CaseSensitive ($bucket) {
            'DOMAIN_REVIEW' { 0 }
            'FAST_REVIEW' { 1 }
            'DIAGNOSTIC_HOLD' { 2 }
            default { 3 }
        }

        $exportedItems.Add([pscustomobject][ordered]@{
            BucketPriority = $bucketPriority
            OperatorBucket = $bucket
            BusinessId = $bizId
            CanonicalRowNumber = $canonicalRowNumber
            BusinessName = $businessName
            District = $district
            RoadAddress = $roadAddress
            CanonicalBenefitStatus = $canonicalBenefitStatus
            CanonicalCoordinateStatus = $canonicalCoordinateStatus
            CanonicalSourceUrl = $canonicalSourceUrl
            CanonicalLastVerifiedAt = $canonicalLastVerifiedAt
            Domain = $itemDomain
            ReviewKey = [string]$auditItem.ReviewKey
            RunId = [string]$auditItem.RunId
            ObservedAt = $entry.ObservedAt
            CurrentObservationId = [string]$auditItem.CurrentObservationId
            PreviousObservationId = [string]$auditItem.PreviousObservationId
            ComparisonId = [string]$auditItem.ComparisonId
            ReviewRoute = $route
            OperationalStatus = $opStatus
            Comparable = $comparable
            SemanticProjectionAvailable = $semanticAvailable
            DeltaDimensions = @($auditItem.DeltaDimensions | ForEach-Object { [string]$_ })
            ChangeCandidates = @($auditItem.ChangeCandidates | ForEach-Object { [string]$_ })
            ReasonCodes = @($auditItem.ReasonCodes | ForEach-Object { [string]$_ })
            AuditFlags = @($auditItem.AuditFlags | ForEach-Object { [string]$_ })
            DiagnosticReasons = @($diagnosticReasons.ToArray())
            BenefitState = $benefitState
            ReviewClass = $reviewClass
            BusinessPresence = $businessPresence
            AbsenceEligible = $absenceEligible
            ValidatedClaims = @($validatedClaimSummary)
            SourceUrls = @($sourceUrls)
            SourceFormats = @($sourceFormats)
            SourceContentHashes = @($sourceContentHashes)
            SourceLocationStatuses = @($sourceLocationStatuses)
            LocationEvaluationStatus = $locationEvaluationStatus
            LocationClassification = $locationClassification
            LocationSelectionStatus = $locationSelectionStatus
            LocationSelectedLatitude = $locationSelectedLatitude
            LocationSelectedLongitude = $locationSelectedLongitude
            MaterialReasonCodes = @($materialReasonCodes)
            ConflictCodes = @($conflictCodes)
            ApprovalRequired = $true
            ProductionAction = 'NONE'
        })
    }

    $sortedItems = @(
        $exportedItems |
            Sort-Object `
                @{ Expression = { $_.BucketPriority } }, `
                @{ Expression = { if ($null -eq $_.CanonicalRowNumber) { [int]::MaxValue } else { [int]$_.CanonicalRowNumber } } }, `
                @{ Expression = { [string]$_.BusinessId } }, `
                @{ Expression = { [string]$_.Domain } }, `
                @{ Expression = { [string]$_.CurrentObservationId } } |
            ForEach-Object {
                $_.PSObject.Properties.Remove('BucketPriority')
                $_
            }
    )

    $fastCount = @($sortedItems | Where-Object { $_.OperatorBucket -ceq 'FAST_REVIEW' }).Count
    $domainCount = @($sortedItems | Where-Object { $_.OperatorBucket -ceq 'DOMAIN_REVIEW' }).Count
    $diagnosticCount = @($sortedItems | Where-Object { $_.OperatorBucket -ceq 'DIAGNOSTIC_HOLD' }).Count
    $benefitCount = @($sortedItems | Where-Object { $_.Domain -ceq 'BENEFIT' }).Count
    $locationCount = @($sortedItems | Where-Object { $_.Domain -ceq 'LOCATION' }).Count

    $summary = [pscustomobject][ordered]@{
        CommittedRunCount = [int]$audit.Summary.CommittedRunCount
        CommittedObservationCount = [int]$audit.Summary.CommittedObservationCount
        CommittedComparisonCount = [int]$audit.Summary.CommittedComparisonCount
        IgnoredUncommittedRecordCount = [int]$audit.Summary.IgnoredUncommittedRecordCount
        DomainFilter = $Domain
        IncludeSuperseded = [bool]$IncludeSuperseded
        SupersededExcludedCount = $supersededExcludedCount
        ExportedItemCount = $sortedItems.Count
        FastReviewCount = $fastCount
        DomainReviewCount = $domainCount
        DiagnosticHoldCount = $diagnosticCount
        BenefitItemCount = $benefitCount
        LocationItemCount = $locationCount
        ApprovalRequired = $true
        ProductionAction = 'NONE'
    }

    $document = [pscustomobject][ordered]@{
        ContractType = 'Phase5ReviewQueueExport'
        ContractVersion = 1
        ExportedAt = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
        Summary = $summary
        Items = @($sortedItems)
    }

    $jsonPath = Join-Path $safeOutputDir 'review-queue-summary.json'
    $csvPath = Join-Path $safeOutputDir 'review-queue-items.csv'

    $jsonText = $document | ConvertTo-Json -Depth 15
    Write-InternalPhase5ReviewQueueAtomicText -Path $jsonPath -Content $jsonText

    $csvRows = @(
        foreach ($item in $sortedItems) {
            [pscustomobject][ordered]@{
                OperatorBucket = $item.OperatorBucket
                BusinessId = $item.BusinessId
                CanonicalRowNumber = if ($null -eq $item.CanonicalRowNumber) { '' } else { [string]$item.CanonicalRowNumber }
                BusinessName = $item.BusinessName
                District = $item.District
                RoadAddress = $item.RoadAddress
                CanonicalBenefitStatus = $item.CanonicalBenefitStatus
                CanonicalCoordinateStatus = $item.CanonicalCoordinateStatus
                Domain = $item.Domain
                ReviewRoute = $item.ReviewRoute
                BenefitState = if ($null -eq $item.BenefitState) { '' } else { $item.BenefitState }
                ReviewClass = if ($null -eq $item.ReviewClass) { '' } else { $item.ReviewClass }
                LocationClassification = if ($null -eq $item.LocationClassification) { '' } else { $item.LocationClassification }
                OperationalStatus = $item.OperationalStatus
                Comparable = [string]$item.Comparable
                ChangeCandidates = (@($item.ChangeCandidates) -join ';')
                ReasonCodes = (@($item.ReasonCodes) -join ';')
                DiagnosticReasons = (@($item.DiagnosticReasons) -join ';')
                ObservedAt = $item.ObservedAt
                RunId = $item.RunId
                ReviewKey = $item.ReviewKey
                CurrentObservationId = $item.CurrentObservationId
                SourceUrls = (@($item.SourceUrls) -join ' | ')
                ApprovalRequired = [string]$item.ApprovalRequired
                ProductionAction = $item.ProductionAction
            }
        }
    )

    $csvText = if ($csvRows.Count -gt 0) {
        ($csvRows | ConvertTo-Csv -NoTypeInformation) -join "`n"
    } else {
        'OperatorBucket,BusinessId,CanonicalRowNumber,BusinessName,District,RoadAddress,CanonicalBenefitStatus,CanonicalCoordinateStatus,Domain,ReviewRoute,BenefitState,ReviewClass,LocationClassification,OperationalStatus,Comparable,ChangeCandidates,ReasonCodes,DiagnosticReasons,ObservedAt,RunId,ReviewKey,CurrentObservationId,SourceUrls,ApprovalRequired,ProductionAction'
    }
    Write-InternalPhase5ReviewQueueAtomicText -Path $csvPath -Content $csvText

    return [pscustomobject][ordered]@{
        SummaryJsonPath = $jsonPath
        ItemsCsvPath = $csvPath
        Document = $document
        Summary = $summary
        Items = @($sortedItems)
        ProductionAction = 'NONE'
    }
}

if ($script:ExportReviewQueueCliInvoked) {
    $cliArgs = $script:ExportReviewQueueCliParams
    if ([string]::IsNullOrWhiteSpace($cliArgs.HistoryRoot) -or
        [string]::IsNullOrWhiteSpace($cliArgs.CanonicalCsvPath) -or
        [string]::IsNullOrWhiteSpace($cliArgs.OutputDirectory)) {
        throw 'RQ_CLI_PARAMETERS_REQUIRED: -HistoryRoot, -CanonicalCsvPath, and -OutputDirectory are required.'
    }

    Export-Phase5ReviewQueue @cliArgs
}

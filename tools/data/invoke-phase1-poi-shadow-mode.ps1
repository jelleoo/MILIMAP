Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$libraryRoot = Join-Path $PSScriptRoot 'lib'
. (Join-Path $libraryRoot 'poi-verification-contracts.ps1')
. (Join-Path $libraryRoot 'identity/normalize-business.ps1')
. (Join-Path $libraryRoot 'poi-discovery/discover-poi-candidates.ps1')
. (Join-Path $libraryRoot 'poi-matching/evaluate-poi-match.ps1')

function ConvertTo-Phase1PoiShadowRow {
    param([Parameter(Mandatory)]$Business, [Parameter(Mandatory)]$Batch, [Parameter(Mandatory)]$Result)

    $selected = $Result.SelectedCandidate
    return [pscustomobject][ordered]@{
        SourceRowNumber = $Business.SourceRowNumber
        OriginalName = $Business.OriginalName
        AddressParseStatus = $Business.AddressParseStatus
        NormalizationWarnings = @($Business.NormalizationWarnings)
        DiscoveryStatus = $Batch.Status
        CandidateCount = @($Batch.Candidates).Count
        QueryAttemptCount = @($Batch.QueryAttempts | Where-Object { $_.Status -ne 'SKIPPED' }).Count
        EvaluationStatus = $Result.EvaluationStatus
        Classification = $Result.Classification
        SelectedCandidateKey = if ($null -eq $selected) { '' } else { $selected.CandidateKey }
        SelectedCandidateName = if ($null -eq $selected) { '' } else { $selected.OriginalName }
        SelectedCandidateRoadAddress = if ($null -eq $selected) { '' } else { $selected.RoadAddress }
        ReasonCodes = @($Result.ReasonCodes)
        ConflictCodes = @($Result.ConflictCodes)
        ProductionAction = $Result.ProductionAction
    }
}

function Invoke-Phase1PoiShadowMode {
    param(
        [Parameter(Mandatory)][object[]]$Rows,
        [int]$SourceRowNumberOffset = 1,
        [scriptblock]$RequestInvoker,
        [string]$ClientId = '',
        [string]$ClientSecret = '',
        [hashtable]$GoldenExpectations = @{},
        [switch]$OperationalLiveRun
    )

    if ($OperationalLiveRun -and $null -ne $RequestInvoker) { throw 'Operational live mode cannot use RequestInvoker' }
    if (-not $OperationalLiveRun -and $null -eq $RequestInvoker) { throw 'Deterministic mode requires RequestInvoker' }
    $reportRows = [Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $Rows.Count; $index++) {
        $sourceRowNumber = $SourceRowNumberOffset + $index + 1
        $business = ConvertTo-NormalizedBusiness -Row $Rows[$index] -SourceRowNumber $sourceRowNumber
        Assert-NormalizedBusiness $business
        $discoveryParameters = @{ Business=$business; RequestInvoker=$RequestInvoker }
        if (-not [string]::IsNullOrWhiteSpace($ClientId)) { $discoveryParameters.ClientId = $ClientId }
        if (-not [string]::IsNullOrWhiteSpace($ClientSecret)) { $discoveryParameters.ClientSecret = $ClientSecret }
        $batch = Invoke-PoiDiscovery @discoveryParameters
        Assert-PoiDiscoveryBatch $batch
        $result = Invoke-PoiMatchEvaluation -Business $business -DiscoveryBatch $batch
        Assert-PoiMatchResult $result
        if ($business.SourceRowNumber -ne $batch.SourceRowNumber -or $batch.SourceRowNumber -ne $result.SourceRowNumber) {
            throw 'SourceRowNumber chain mismatch'
        }
        $reportRows.Add((ConvertTo-Phase1PoiShadowRow -Business $business -Batch $batch -Result $result))
    }

    return [pscustomobject][ordered]@{
        Rows = $reportRows.ToArray()
        Summary = Get-Phase1PoiShadowSummary -Rows $reportRows.ToArray() -GoldenExpectations $GoldenExpectations -OperationalLiveRun:$OperationalLiveRun
    }
}

function Get-Phase1PoiShadowSummary {
    param(
        [Parameter(Mandatory)][object[]]$Rows,
        [hashtable]$GoldenExpectations = @{},
        [switch]$OperationalLiveRun
    )

    $allRows = @($Rows)
    $goldenRows = @($allRows | Where-Object { $GoldenExpectations.ContainsKey([string]$_.SourceRowNumber) })
    $fullyEvaluableGoldenRows = @($goldenRows | Where-Object {
        [string]$GoldenExpectations[[string]$_.SourceRowNumber].SourceCoverage -eq 'FULL_CANDIDATE'
    })
    $sourceLimitedGoldenRows = @($goldenRows | Where-Object {
        [string]$GoldenExpectations[[string]$_.SourceRowNumber].SourceCoverage -eq 'SOURCE_LIMITED'
    })
    $fullyEvaluableAmbiguousNegativeFalseGreen = @($fullyEvaluableGoldenRows | Where-Object {
        $expectedLabel = [string]$GoldenExpectations[[string]$_.SourceRowNumber].ExpectedLabel
        $_.Classification -eq 'GREEN' -and $expectedLabel -in @('ambiguous', 'negative')
    })
    $totalQueryAttempts = [int](@($allRows | Measure-Object -Property QueryAttemptCount -Sum).Sum)

    return [pscustomobject][ordered]@{
        EvaluatedRows = $allRows.Count
        DiscoveryComplete = @($allRows | Where-Object DiscoveryStatus -eq 'COMPLETE').Count
        DiscoveryPartial = @($allRows | Where-Object DiscoveryStatus -eq 'PARTIAL').Count
        DiscoveryFailed = @($allRows | Where-Object DiscoveryStatus -eq 'FAILED').Count
        MatcherComplete = @($allRows | Where-Object EvaluationStatus -eq 'COMPLETE').Count
        MatcherIncomplete = @($allRows | Where-Object EvaluationStatus -eq 'INCOMPLETE').Count
        Green = @($allRows | Where-Object Classification -eq 'GREEN').Count
        Yellow = @($allRows | Where-Object Classification -eq 'YELLOW').Count
        Red = @($allRows | Where-Object Classification -eq 'RED').Count
        FastReviewCandidates = @($allRows | Where-Object Classification -eq 'GREEN').Count
        DeepManualReviewRequired = @($allRows | Where-Object { $_.Classification -in @('YELLOW', 'RED') }).Count
        AllRowsRequireFinalHumanApproval = $true
        NoCandidateCount = @($allRows | Where-Object {
            $_.DiscoveryStatus -eq 'COMPLETE' -and $_.CandidateCount -eq 0 -and $_.ReasonCodes -contains 'NO_CANDIDATE'
        }).Count
        DiscoveryFailureCount = @($allRows | Where-Object DiscoveryStatus -eq 'FAILED').Count
        TotalQueryAttempts = $totalQueryAttempts
        AverageQueryAttempts = if ($allRows.Count -eq 0) { [double]0 } else { [double]$totalQueryAttempts / [double]$allRows.Count }
        TotalGoldenCases = $goldenRows.Count
        FullyEvaluableGoldenCases = $fullyEvaluableGoldenRows.Count
        SourceLimitedGoldenCases = $sourceLimitedGoldenRows.Count
        FullyEvaluableAmbiguousNegativeFalseGreenCount = $fullyEvaluableAmbiguousNegativeFalseGreen.Count
        OperationalLiveShadowRun = if ($OperationalLiveRun) { 'RUN' } else { 'NOT_RUN' }
    }
}

function ConvertTo-Phase1PoiShadowCsvRow {
    param([Parameter(Mandatory)]$Row)

    $projected = [ordered]@{}
    foreach ($property in $Row.PSObject.Properties) {
        $value = $property.Value
        $projected[$property.Name] = if ($value -is [Collections.IEnumerable] -and $value -isnot [string]) {
            (@($value | ForEach-Object { [string]$_ }) -join '|')
        } else {
            $value
        }
    }
    return [pscustomobject]$projected
}

function Test-Phase1PoiShadowPathWithinDirectory {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Directory)

    $fullPath = [IO.Path]::GetFullPath($Path)
    $separators = [char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $fullDirectory = ([IO.Path]::GetFullPath($Directory)).TrimEnd($separators)
    $comparison = [StringComparison]::OrdinalIgnoreCase
    return $fullPath.Equals($fullDirectory, $comparison) -or
        $fullPath.StartsWith($fullDirectory + [IO.Path]::DirectorySeparatorChar, $comparison)
}

function Resolve-Phase1PoiShadowExportPath {
    param([Parameter(Mandatory)][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Explicit output paths are required' }
    $fullPath = [IO.Path]::GetFullPath($Path)
    $repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
    foreach ($protectedPath in @('data/canonical', 'data/seed', 'apps')) {
        if (Test-Phase1PoiShadowPathWithinDirectory -Path $fullPath -Directory (Join-Path $repositoryRoot $protectedPath)) {
            throw 'Protected output path is not allowed'
        }
    }
    return $fullPath
}

function Export-Phase1PoiShadowMode {
    param(
        [Parameter(Mandatory)]$Run,
        [Parameter(Mandatory)][string]$RowReportCsv,
        [Parameter(Mandatory)][string]$SummaryJson
    )

    $resolvedRowReportCsv = Resolve-Phase1PoiShadowExportPath $RowReportCsv
    $resolvedSummaryJson = Resolve-Phase1PoiShadowExportPath $SummaryJson
    foreach ($path in @($resolvedRowReportCsv, $resolvedSummaryJson)) {
        $parent = Split-Path -Parent $path
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
        }
    }
    @($Run.Rows | ForEach-Object { ConvertTo-Phase1PoiShadowCsvRow $_ }) |
        Export-Csv -LiteralPath $resolvedRowReportCsv -NoTypeInformation -Encoding utf8
    $summaryText = $Run.Summary | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText($resolvedSummaryJson, $summaryText + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}

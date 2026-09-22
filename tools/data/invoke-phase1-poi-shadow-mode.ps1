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
        [string]$ClientSecret = ''
    )

    $reportRows = [Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $Rows.Count; $index++) {
        $sourceRowNumber = $SourceRowNumberOffset + $index + 1
        $business = ConvertTo-NormalizedBusiness -Row $Rows[$index] -SourceRowNumber $sourceRowNumber
        Assert-NormalizedBusiness $business
        $batch = Invoke-PoiDiscovery -Business $business -ClientId $ClientId -ClientSecret $ClientSecret -RequestInvoker $RequestInvoker
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
        Summary = [pscustomobject][ordered]@{ EvaluatedRows = $reportRows.Count }
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

function Export-Phase1PoiShadowMode {
    param(
        [Parameter(Mandatory)]$Run,
        [Parameter(Mandatory)][string]$RowReportCsv,
        [Parameter(Mandatory)][string]$SummaryJson
    )

    foreach ($path in @($RowReportCsv, $SummaryJson)) {
        if ([string]::IsNullOrWhiteSpace($path)) { throw 'Explicit output paths are required' }
        $parent = Split-Path -Parent $path
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
        }
    }
    @($Run.Rows | ForEach-Object { ConvertTo-Phase1PoiShadowCsvRow $_ }) |
        Export-Csv -LiteralPath $RowReportCsv -NoTypeInformation -Encoding utf8
    $summaryText = $Run.Summary | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText($SummaryJson, $summaryText + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}

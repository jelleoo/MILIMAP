Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'history-contracts.ps1')
. (Join-Path $PSScriptRoot 'history-fingerprints.ps1')

function New-HistoryComparisonId {
    param(
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$BusinessId,
        [Parameter(Mandatory)][string]$Domain,
        [AllowEmptyString()][string]$PreviousObservationId='',
        [Parameter(Mandatory)][string]$CurrentObservationId
    )
    $material = $RunId + '|' + $BusinessId + '|' + $Domain + '|' + $PreviousObservationId + '|' + $CurrentObservationId
    return 'cmp-' + (Get-HistorySha256 -Text $material).Substring(0,32)
}

function Compare-HistoryObservations {
    param(
        [AllowNull()]$Previous,
        [Parameter(Mandatory)]$Current,
        [Parameter(Mandatory)][scriptblock]$DomainChangeResolver
    )

    Assert-HistoryObservation $Current
    if ($null -ne $Previous) {
        Assert-HistoryObservation $Previous
        if ([string]$Previous.BusinessId -cne [string]$Current.BusinessId -or [string]$Previous.Domain -cne [string]$Current.Domain) {
            throw 'Previous and current observations must share businessId and domain'
        }
    }

    $previousId = if ($null -eq $Previous) { '' } else { [string]$Previous.ObservationId }
    $comparisonId = New-HistoryComparisonId -RunId ([string]$Current.RunId) -BusinessId ([string]$Current.BusinessId) -Domain ([string]$Current.Domain) -PreviousObservationId $previousId -CurrentObservationId ([string]$Current.ObservationId)

    if ($null -eq $Previous) {
        return New-ObservationComparison -ComparisonId $comparisonId -RunId $Current.RunId -BusinessId $Current.BusinessId -Domain $Current.Domain -PreviousObservationId '' -CurrentObservationId $Current.ObservationId -ComparisonStatus 'COMPLETE' -DeltaDimensions @() -ComparatorVersion 1 -ChangeCandidates @('BASELINE_ESTABLISHED') -ReasonCodes @()
    }

    $deltas = @(Get-HistoryDeltaDimensions -Previous $Previous -Current $Current)

    if (-not [bool]$Current.Comparable -or [string]$Current.OperationalStatus -ne 'COMPLETE') {
        $reasons = @($Current.NonComparableReasons)
        return New-ObservationComparison -ComparisonId $comparisonId -RunId $Current.RunId -BusinessId $Current.BusinessId -Domain $Current.Domain -PreviousObservationId $Previous.ObservationId -CurrentObservationId $Current.ObservationId -ComparisonStatus 'UNAVAILABLE' -DeltaDimensions $deltas -ComparatorVersion 1 -ChangeCandidates @('OPERATIONAL_FAILURE','COMPARISON_UNAVAILABLE') -ReasonCodes $reasons
    }

    if (-not [bool]$Previous.Comparable -or [string]$Previous.OperationalStatus -ne 'COMPLETE') {
        return New-ObservationComparison -ComparisonId $comparisonId -RunId $Current.RunId -BusinessId $Current.BusinessId -Domain $Current.Domain -PreviousObservationId $Previous.ObservationId -CurrentObservationId $Current.ObservationId -ComparisonStatus 'UNAVAILABLE' -DeltaDimensions $deltas -ComparatorVersion 1 -ChangeCandidates @('COMPARISON_UNAVAILABLE') -ReasonCodes @('PREVIOUS_OBSERVATION_NOT_COMPARABLE')
    }

    if ($deltas -contains 'INPUT') {
        return New-ObservationComparison -ComparisonId $comparisonId -RunId $Current.RunId -BusinessId $Current.BusinessId -Domain $Current.Domain -PreviousObservationId $Previous.ObservationId -CurrentObservationId $Current.ObservationId -ComparisonStatus 'COMPLETE' -DeltaDimensions $deltas -ComparatorVersion 1 -ChangeCandidates @('CANONICAL_INPUT_CHANGED') -ReasonCodes @()
    }

    if ($deltas -contains 'EXECUTION') {
        return New-ObservationComparison -ComparisonId $comparisonId -RunId $Current.RunId -BusinessId $Current.BusinessId -Domain $Current.Domain -PreviousObservationId $Previous.ObservationId -CurrentObservationId $Current.ObservationId -ComparisonStatus 'COMPLETE' -DeltaDimensions $deltas -ComparatorVersion 1 -ChangeCandidates @('PROCESSOR_OUTPUT_CHANGED') -ReasonCodes @()
    }

    if (($deltas -contains 'EVIDENCE') -and -not ($deltas -contains 'SEMANTIC')) {
        return New-ObservationComparison -ComparisonId $comparisonId -RunId $Current.RunId -BusinessId $Current.BusinessId -Domain $Current.Domain -PreviousObservationId $Previous.ObservationId -CurrentObservationId $Current.ObservationId -ComparisonStatus 'COMPLETE' -DeltaDimensions $deltas -ComparatorVersion 1 -ChangeCandidates @('EVIDENCE_CHANGE_ONLY') -ReasonCodes @()
    }

    if ($deltas.Count -eq 0) {
        return New-ObservationComparison -ComparisonId $comparisonId -RunId $Current.RunId -BusinessId $Current.BusinessId -Domain $Current.Domain -PreviousObservationId $Previous.ObservationId -CurrentObservationId $Current.ObservationId -ComparisonStatus 'COMPLETE' -DeltaDimensions @() -ComparatorVersion 1 -ChangeCandidates @() -ReasonCodes @()
    }

    $resolved = & $DomainChangeResolver $Previous $Current
    if ($null -eq $resolved) { throw 'DomainChangeResolver must return a result object' }

    $candidates = if ($resolved.PSObject.Properties.Name -contains 'ChangeCandidates') { @($resolved.ChangeCandidates) } else { @() }
    $reasons = if ($resolved.PSObject.Properties.Name -contains 'ReasonCodes') { @($resolved.ReasonCodes) } else { @() }

    return New-ObservationComparison -ComparisonId $comparisonId -RunId $Current.RunId -BusinessId $Current.BusinessId -Domain $Current.Domain -PreviousObservationId $Previous.ObservationId -CurrentObservationId $Current.ObservationId -ComparisonStatus 'COMPLETE' -DeltaDimensions $deltas -ComparatorVersion 1 -ChangeCandidates $candidates -ReasonCodes $reasons
}

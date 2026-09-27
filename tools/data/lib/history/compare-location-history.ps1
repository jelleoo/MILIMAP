Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'history-contracts.ps1')
. (Join-Path $PSScriptRoot 'history-fingerprints.ps1')
. (Join-Path $PSScriptRoot 'history-store.ps1')
. (Join-Path $PSScriptRoot 'compare-history-observations.ps1')
. (Join-Path $PSScriptRoot 'location-history-adapter.ps1')

function Test-LocationHistoryCodeSetEqual {
    param([AllowNull()][object[]]$Left=@(),[AllowNull()][object[]]$Right=@())

    $leftCodes=@($Left | ForEach-Object { [string]$_ } | Sort-Object -CaseSensitive -Unique)
    $rightCodes=@($Right | ForEach-Object { [string]$_ } | Sort-Object -CaseSensitive -Unique)
    if($leftCodes.Count -ne $rightCodes.Count){ return $false }
    for($index=0;$index -lt $leftCodes.Count;$index++){
        if($leftCodes[$index] -cne $rightCodes[$index]){ return $false }
    }
    return $true
}

function Resolve-LocationHistoryChange {
    param(
        [Parameter(Mandatory)]$PreviousProjection,
        [Parameter(Mandatory)]$CurrentProjection
    )

    foreach($projection in @($PreviousProjection,$CurrentProjection)){
        if([string]$projection.ProjectionType -cne 'LocationHistorySemantic' -or [int]$projection.ProjectionVersion -ne 1){
            throw 'Unsupported Location semantic projection'
        }
    }

    if([string]$PreviousProjection.SelectionStatus -ceq 'SELECTED' -and [bool]$CurrentProjection.AbsenceEligible){
        return [pscustomobject][ordered]@{
            ChangeCandidates=@('LOCATION_ABSENCE_SUSPECTED')
            ReasonCodes=@('LOCATION_SELECTION_CHANGED','COMPLETE_NO_CANDIDATE')
        }
    }

    $reasons=[Collections.Generic.List[string]]::new()
    $materialLocationChanged=$false
    $previousSelected=([string]$PreviousProjection.SelectionStatus -ceq 'SELECTED')
    $currentSelected=([string]$CurrentProjection.SelectionStatus -ceq 'SELECTED')
    if($previousSelected -and $currentSelected){
        if([string]$PreviousProjection.SelectedLocation.Name -cne [string]$CurrentProjection.SelectedLocation.Name){
            $reasons.Add('LOCATION_NAME_CHANGED')
            $materialLocationChanged=$true
        }
        if([string]$PreviousProjection.SelectedLocation.RoadAddress -cne [string]$CurrentProjection.SelectedLocation.RoadAddress -or [string]$PreviousProjection.SelectedLocation.LotAddress -cne [string]$CurrentProjection.SelectedLocation.LotAddress){
            $reasons.Add('LOCATION_ADDRESS_CHANGED')
            $materialLocationChanged=$true
        }
        if($PreviousProjection.SelectedLocation.Latitude -ne $CurrentProjection.SelectedLocation.Latitude -or $PreviousProjection.SelectedLocation.Longitude -ne $CurrentProjection.SelectedLocation.Longitude){
            $reasons.Add('LOCATION_COORDINATE_CHANGED')
            $materialLocationChanged=$true
        }
    } elseif($previousSelected -ne $currentSelected){
        $reasons.Add('LOCATION_SELECTION_CHANGED')
    }

    $evaluationChanged=(
        [string]$PreviousProjection.Classification -cne [string]$CurrentProjection.Classification -or
        -not (Test-LocationHistoryCodeSetEqual -Left @($PreviousProjection.MaterialReasonCodes) -Right @($CurrentProjection.MaterialReasonCodes)) -or
        -not (Test-LocationHistoryCodeSetEqual -Left @($PreviousProjection.ConflictCodes) -Right @($CurrentProjection.ConflictCodes)) -or
        [bool]$PreviousProjection.AbsenceEligible -ne [bool]$CurrentProjection.AbsenceEligible
    )
    if($evaluationChanged){ $reasons.Add('LOCATION_EVALUATION_CHANGED') }

    $orderedReasons=@(
        'LOCATION_NAME_CHANGED',
        'LOCATION_ADDRESS_CHANGED',
        'LOCATION_COORDINATE_CHANGED',
        'LOCATION_SELECTION_CHANGED',
        'LOCATION_EVALUATION_CHANGED',
        'COMPLETE_NO_CANDIDATE' | Where-Object { $reasons -contains $_ }
    )
    return [pscustomobject][ordered]@{
        ChangeCandidates=@(if($materialLocationChanged){'LOCATION_CHANGE_SUSPECTED'})
        ReasonCodes=$orderedReasons
    }
}

function Compare-LocationHistoryObservations {
    param(
        [Parameter(Mandatory)]$Store,
        [AllowNull()]$Previous,
        [Parameter(Mandatory)]$Current,
        [AllowNull()]$StagedCurrentSemanticProjection=$null
    )

    Assert-HistoryObservation $Current
    if([string]$Current.Domain -cne 'LOCATION'){ throw 'Location history comparison requires LOCATION current observation' }
    if($null -ne $Previous){
        Assert-HistoryObservation $Previous
        if([string]$Previous.Domain -cne 'LOCATION'){ throw 'Location history comparison requires LOCATION previous observation' }
    }
    if($null -ne $StagedCurrentSemanticProjection){
        [void](Get-InternalStagedLocationHistorySemanticProjection -Current $Current -StagedCurrentSemanticProjection $StagedCurrentSemanticProjection)
    }

    $gateResolver={
        param($PreviousObservation,$CurrentObservation)
        return [pscustomobject][ordered]@{
            ChangeCandidates=@('LOCATION_DOMAIN_RESOLUTION_REQUIRED')
            ReasonCodes=@('LOCATION_DOMAIN_RESOLUTION_REQUIRED')
        }
    }
    $gate=Compare-HistoryObservations -Previous $Previous -Current $Current -DomainChangeResolver $gateResolver
    if(@($gate.ChangeCandidates) -notcontains 'LOCATION_DOMAIN_RESOLUTION_REQUIRED'){
        return $gate
    }

    $previousProjection=Read-LocationHistorySemanticProjection -Store $Store -Observation $Previous
    $currentProjection=if($null -eq $StagedCurrentSemanticProjection){
        Read-LocationHistorySemanticProjection -Store $Store -Observation $Current
    } else {
        Get-InternalStagedLocationHistorySemanticProjection -Current $Current -StagedCurrentSemanticProjection $StagedCurrentSemanticProjection
    }
    $resolved=Resolve-LocationHistoryChange -PreviousProjection $previousProjection -CurrentProjection $currentProjection
    $gate.ChangeCandidates=@($resolved.ChangeCandidates)
    $gate.ReasonCodes=@($resolved.ReasonCodes)
    Assert-ObservationComparison $gate
    return $gate
}

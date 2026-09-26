# Test-only serializer for a one-shot Yangju live-control record.  It is
# deliberately defensive: recording must not change the live result or fail
# simply because a control has no claim, slice, or optional property.
function Get-YangjuLiveValue {
    param([AllowNull()]$Object, [Parameter(Mandatory)][string]$Name, [AllowNull()]$Default='')
    if ($null -eq $Object -or $Object.PSObject.Properties.Name -notcontains $Name) { return $Default }
    $value = $Object.$Name
    if ($null -eq $value) { return $Default }
    return $value
}

function Get-YangjuLiveClaim {
    param([AllowNull()]$Result, [Parameter(Mandatory)][string]$ClaimType, [string]$ValidationStatus='')
    $container = Get-YangjuLiveValue -Object $Result -Name $(if ($ValidationStatus) { 'Validation' } else { 'Extraction' }) -Default $null
    $claims = @(Get-YangjuLiveValue -Object $container -Name 'Claims' -Default @())
    $matches = @($claims | Where-Object {
        (Get-YangjuLiveValue -Object $_ -Name 'ClaimType') -ceq $ClaimType -and
        (-not $ValidationStatus -or (Get-YangjuLiveValue -Object $_ -Name 'ValidationStatus') -ceq $ValidationStatus)
    })
    if ($matches.Count -eq 1) { return $matches[0] }
    return $null
}

function Get-YangjuLiveForbiddenInferences {
    param([AllowNull()]$Result)
    $inferences = [Collections.Generic.List[string]]::new()
    $claims = @()
    foreach ($containerName in @('Extraction','Validation')) {
        $claims += @(Get-YangjuLiveValue -Object (Get-YangjuLiveValue -Object $Result -Name $containerName -Default $null) -Name 'Claims' -Default @())
    }
    foreach ($claim in $claims) {
        $claimType = [string](Get-YangjuLiveValue -Object $claim -Name 'ClaimType')
        $value = [string](Get-YangjuLiveValue -Object $claim -Name 'Value')
        if ($claimType -ceq 'VALID_UNTIL' -and $inferences -notcontains 'VALID_UNTIL') { $inferences.Add('VALID_UNTIL') }
        if ($claimType -ceq 'ENDED' -and $inferences -notcontains 'ENDED') { $inferences.Add('ENDED') }
        if ($claimType -ceq 'CURRENT_APPLICABILITY' -and $value -ceq 'false' -and $inferences -notcontains 'CURRENT_APPLICABILITY_FALSE') { $inferences.Add('CURRENT_APPLICABILITY_FALSE') }
    }
    if (@(Get-YangjuLiveValue -Object $Result -Name 'ReasonCodes' -Default @()) -contains 'EXPLICIT_DISCONTINUATION') { $inferences.Add('EXPLICIT_DISCONTINUATION') }
    return @($inferences)
}

function ConvertTo-YangjuLiveControlArtifact {
    param(
        [Parameter(Mandatory)][string]$CheckedAt, [Parameter(Mandatory)][string]$SourceUrl,
        [Parameter(Mandatory)]$Transport, [Parameter(Mandatory)]$PositiveResult, [Parameter(Mandatory)]$AbsenceResult,
        [Parameter(Mandatory)]$Metrics, [Parameter(Mandatory)]$Timings, [AllowNull()][object[]]$ProtectedPathChanges=@()
    )
    $positiveClaim = Get-YangjuLiveClaim -Result $PositiveResult -ClaimType 'BENEFIT_DESCRIPTION'
    $validatedClaim = Get-YangjuLiveClaim -Result $PositiveResult -ClaimType 'BENEFIT_DESCRIPTION' -ValidationStatus 'VALIDATED'
    $positiveSlices = @(Get-YangjuLiveValue -Object $PositiveResult -Name 'Slices' -Default @())
    $positiveSlice = $null
    if ($positiveSlices.Count -eq 1) { $positiveSlice = $positiveSlices[0] }
    $positiveObservation = Get-YangjuLiveValue -Object $PositiveResult -Name 'Observation' -Default $null
    $absenceObservation = Get-YangjuLiveValue -Object $AbsenceResult -Name 'Observation' -Default $null
    $positiveLocation = Get-YangjuLiveValue -Object $PositiveResult -Name 'LocationResult' -Default $null
    $absenceLocation = Get-YangjuLiveValue -Object $AbsenceResult -Name 'LocationResult' -Default $null
    $positiveSnapshot = Get-YangjuLiveValue -Object $positiveObservation -Name 'Snapshot' -Default $null

    return [pscustomobject][ordered]@{
        CheckedAt=$CheckedAt; SourceUrl=$SourceUrl
        HttpStatus=(Get-YangjuLiveValue -Object $Transport -Name 'StatusCode')
        ContentType=(Get-YangjuLiveValue -Object $Transport -Name 'ContentType')
        FinalUrl=(Get-YangjuLiveValue -Object $Transport -Name 'FinalUrl')
        WorkbookByteSize=(Get-YangjuLiveValue -Object $Transport -Name 'ByteSize')
        SnapshotId=(Get-YangjuLiveValue -Object $positiveObservation -Name 'SnapshotId')
        ContentHash=(Get-YangjuLiveValue -Object $positiveSnapshot -Name 'ContentHash')
        Timings=$Timings; Metrics=$Metrics; ProductionAction='NONE'; ProtectedPathChanges=@($ProtectedPathChanges)
        PositiveControl=[pscustomobject][ordered]@{
            FetchStatus=(Get-YangjuLiveValue -Object (Get-YangjuLiveValue -Object $PositiveResult -Name 'Document' -Default $null) -Name 'FetchStatus')
            SourceFormat=(Get-YangjuLiveValue -Object (Get-YangjuLiveValue -Object $PositiveResult -Name 'Document' -Default $null) -Name 'SourceFormat')
            OfficialityStatus=(Get-YangjuLiveValue -Object (Get-YangjuLiveValue -Object $PositiveResult -Name 'Qualified' -Default $null) -Name 'OfficialityStatus')
            ObservationStatus=(Get-YangjuLiveValue -Object $positiveObservation -Name 'AdapterStatus')
            LocationOperationalStatus=(Get-YangjuLiveValue -Object $positiveLocation -Name 'OperationalStatus')
            LocationStatus=(Get-YangjuLiveValue -Object $positiveLocation -Name 'Status')
            BindingStatus=(Get-YangjuLiveValue -Object (Get-YangjuLiveValue -Object $PositiveResult -Name 'Bound' -Default $null) -Name 'BusinessBindingStatus')
            ExtractionStatus=(Get-YangjuLiveValue -Object (Get-YangjuLiveValue -Object $PositiveResult -Name 'Extraction' -Default $null) -Name 'Status')
            ExtractionMethod=(Get-YangjuLiveValue -Object $positiveClaim -Name 'ExtractionMethod')
            ValidationStatus=(Get-YangjuLiveValue -Object $validatedClaim -Name 'ValidationStatus')
            SheetName=(Get-YangjuLiveValue -Object $positiveSlice -Name 'SheetName')
            SheetIndex=(Get-YangjuLiveValue -Object $positiveSlice -Name 'SheetIndex' -Default 0)
            RowNumber=(Get-YangjuLiveValue -Object $positiveSlice -Name 'RowNumber' -Default 0)
            BenefitCellReference=(Get-YangjuLiveValue -Object $positiveClaim -Name 'EvidenceReference')
            BenefitValue=(Get-YangjuLiveValue -Object $positiveClaim -Name 'Value')
            ReasonCodes=@(Get-YangjuLiveValue -Object $PositiveResult -Name 'ReasonCodes' -Default @())
        }
        AbsenceControl=[pscustomobject][ordered]@{
            ObservationStatus=(Get-YangjuLiveValue -Object $absenceObservation -Name 'AdapterStatus')
            LocationOperationalStatus=(Get-YangjuLiveValue -Object $absenceLocation -Name 'OperationalStatus')
            LocationStatus=(Get-YangjuLiveValue -Object $absenceLocation -Name 'Status')
            ExtractionStatus=(Get-YangjuLiveValue -Object (Get-YangjuLiveValue -Object $AbsenceResult -Name 'Extraction' -Default $null) -Name 'Status')
            ClaimTypes=@(Get-YangjuLiveValue -Object (Get-YangjuLiveValue -Object $AbsenceResult -Name 'Extraction' -Default $null) -Name 'Claims' -Default @() | ForEach-Object { Get-YangjuLiveValue -Object $_ -Name 'ClaimType' })
            ReasonCodes=@(Get-YangjuLiveValue -Object $AbsenceResult -Name 'ReasonCodes' -Default @())
            ForbiddenInferences=@(Get-YangjuLiveForbiddenInferences -Result $AbsenceResult)
        }
    }
}

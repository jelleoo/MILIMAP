Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'benefit-source-run-context.ps1')
. (Join-Path $PSScriptRoot 'find-business-evidence-slice.ps1')
. (Join-Path $PSScriptRoot '../benefit-source/qualify-official-benefit-source.ps1')
. (Join-Path $PSScriptRoot '../benefit-source/bind-benefit-source.ps1')
. (Join-Path $PSScriptRoot 'extract-benefit-evidence.ps1')
. (Join-Path $PSScriptRoot 'validate-benefit-evidence.ps1')

function Add-ScopedBenefitReasonCode {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Target,
        [AllowNull()][object[]]$ReasonCodes=@()
    )
    foreach ($reason in @($ReasonCodes | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
        Assert-BenefitAllowedCode 'ReasonCode' ([string]$reason)
        if ($Target -notcontains [string]$reason) { $Target.Add([string]$reason) }
    }
}

function New-ScopedBenefitPlaceholderBoundSource {
    param(
        [Parameter(Mandatory)]$QualifiedSource,
        [bool]$Conflict=$false,
        [AllowNull()][object[]]$BindingEvidence=@()
    )
    $status = if ($Conflict) { 'CONFLICT' } else { 'AMBIGUOUS' }
    $reasons = if ($Conflict) { @('BUSINESS_BINDING_CONFLICT') } else { @('BUSINESS_BINDING_AMBIGUOUS') }
    $bound = New-BoundBenefitSource -QualifiedSource $QualifiedSource -BusinessBindingStatus $status -BindingEvidence $BindingEvidence -ReasonCodes $reasons
    Assert-BoundBenefitSource $bound
    return $bound
}

function New-ScopedBenefitEmptyExtraction {
    param(
        [Parameter(Mandatory)]$BoundSource,
        [AllowNull()][object[]]$ReasonCodes=@('EXTRACTION_FAILED')
    )
    return New-BenefitEvidenceExtractionResult -Source $BoundSource -Status 'FAILED' -Claims @() -ReasonCodes $ReasonCodes
}

function New-ScopedBenefitEmptyValidation {
    param([Parameter(Mandatory)]$Extraction)
    return [pscustomobject][ordered]@{
        SourceRowNumber=[int]$Extraction.SourceRowNumber
        Status='FAILED'
        Claims=@()
        ReasonCodes=@($Extraction.ReasonCodes)
    }
}

function Test-ScopedBenefitLocationHardConflict {
    param([AllowNull()]$LocationResult)
    if ($null -eq $LocationResult) { return $false }
    # The locator emits EXPLICIT_NAME_MISMATCH when other observed identity
    # evidence agrees. Do not downgrade that contradiction to plain absence.
    return @($LocationResult.Diagnostics | Where-Object {
        $_.Code -ceq 'LOCATOR_IDENTITY_CONFLICT' -and
        ($_.Detail -ceq 'EXPLICIT_NAME_MISMATCH' -or [string]$_.Detail -match '_CONFLICT(?:,|$)')
    }).Count -gt 0
}

function Invoke-ScopedPhase2BenefitSourceCandidate {
    param(
        [Parameter(Mandatory)]$Candidate,
        [Parameter(Mandatory)]$Business,
        [string]$CanonicalPhone='',
        [Parameter(Mandatory)]$RunContext,
        [AllowNull()][scriptblock]$RequestInvoker=$null
    )

    Assert-BenefitSourceCandidate $Candidate
    Assert-NormalizedBusiness $Business
    if ([int]$Candidate.SourceRowNumber -ne [int]$Business.SourceRowNumber) {
        throw 'Scoped source and business must preserve one SourceRowNumber'
    }

    $document = Get-BenefitRunSourceDocument -Context $RunContext -Candidate $Candidate -RequestInvoker $RequestInvoker
    $qualified = Get-QualifiedBenefitSource -Candidate $Candidate -Document $document -Business $Business
    $observation = $null
    $location = $null
    $slices = @()
    $preparationDiagnostics = @()
    $bound = $null
    $extraction = $null
    $validation = $null

    if ([string]$Candidate.SourceKind -ne 'PUBLIC_OFFICIAL') {
        $preparationDiagnostics += [pscustomobject][ordered]@{
            Code='SOURCE_KIND_UNSUPPORTED'; Stage='SCOPED_PREPARATION'; EvidenceReference=''; Detail='A1 scoped HTML supports PUBLIC_OFFICIAL sources only'
        }
        $bound = New-ScopedBenefitPlaceholderBoundSource -QualifiedSource $qualified
        $extraction = New-ScopedBenefitEmptyExtraction -BoundSource $bound -ReasonCodes @('SOURCE_UNSUPPORTED')
        $validation = New-ScopedBenefitEmptyValidation -Extraction $extraction
    } elseif ([string]$qualified.OfficialityStatus -ne 'VERIFIED_OFFICIAL') {
        $preparationDiagnostics += [pscustomobject][ordered]@{
            Code='SOURCE_NOT_QUALIFIED'; Stage='SCOPED_PREPARATION'; EvidenceReference=''; Detail='Source qualification did not establish a verified official source'
        }
        $bound = New-ScopedBenefitPlaceholderBoundSource -QualifiedSource $qualified
        $failureReasons = @($document.ReasonCodes)
        if ($failureReasons.Count -eq 0) { $failureReasons = @('SOURCE_OFFICIALITY_UNRESOLVED') }
        $extraction = New-ScopedBenefitEmptyExtraction -BoundSource $bound -ReasonCodes $failureReasons
        $validation = New-ScopedBenefitEmptyValidation -Extraction $extraction
    } elseif ($document.SourceFormat -cne 'HTML') {
        # A successfully fetched PDF/XLSX is still unsupported by this path.
        # Never manufacture a text snapshot or invoke an extraction provider.
        $preparationDiagnostics += [pscustomobject][ordered]@{
            Code='HTML_FORMAT_UNSUPPORTED'; Stage='SCOPED_PREPARATION'; EvidenceReference=''; Detail='A1 scoped preparation accepts HTML documents only'
        }
        $bound = New-ScopedBenefitPlaceholderBoundSource -QualifiedSource $qualified
        $extraction = New-ScopedBenefitEmptyExtraction -BoundSource $bound -ReasonCodes @('SOURCE_UNSUPPORTED')
        $validation = New-ScopedBenefitEmptyValidation -Extraction $extraction
    } else {
        # Isolate source parsing/span-construction failures, not invalid caller
        # contracts, request-profile changes, or unsafe URL rejection above.
        try {
            $observation = Get-BenefitRunHtmlObservation -Context $RunContext -Document $document
        } catch {
            $preparationDiagnostics += [pscustomobject][ordered]@{
                Code='HTML_PREPARATION_FAILED'; Stage='SCOPED_PREPARATION'; EvidenceReference=''
                Detail=('Unable to construct a safe HTML observation: ' + $_.Exception.GetType().FullName)
            }
            $bound = New-ScopedBenefitPlaceholderBoundSource -QualifiedSource $qualified
            $extraction = New-ScopedBenefitEmptyExtraction -BoundSource $bound -ReasonCodes @('EXTRACTION_FAILED')
            $validation = New-ScopedBenefitEmptyValidation -Extraction $extraction
        }

        if ($null -ne $observation) {
            $location = Find-BenefitBusinessEvidence -Observation $observation -Business $Business -CanonicalPhone $CanonicalPhone
            $preparationDiagnostics += @($observation.Diagnostics)
            $preparationDiagnostics += @($location.Diagnostics)

            if ($location.OperationalStatus -ceq 'COMPLETE' -and $location.Status -ceq 'LOCATED') {
                $slices = @($location.Slices)
                $slice = $slices[0]
                $bound = Get-BenefitBusinessBinding -Source $qualified -Business $Business -CanonicalPhone $CanonicalPhone -EvidenceSlice $slice
                if ($bound.BusinessBindingStatus -ceq 'STRONG') {
                    $extraction = Invoke-BenefitEvidenceExtraction -Source $bound -Document $document -EvidenceSlice $slice
                    $validation = ConvertTo-ValidatedBenefitEvidence -Extraction $extraction -Document $document -EvidenceSlice $slice
                } else {
                    $extraction = New-ScopedBenefitEmptyExtraction -BoundSource $bound
                    $validation = New-ScopedBenefitEmptyValidation -Extraction $extraction
                }
            } else {
                $hardConflict = Test-ScopedBenefitLocationHardConflict -LocationResult $location
                $bindingEvidence = @($location.Diagnostics | ForEach-Object { [string]$_.Detail } | Where-Object { $_ })
                $bound = New-ScopedBenefitPlaceholderBoundSource -QualifiedSource $qualified -Conflict:$hardConflict -BindingEvidence $bindingEvidence
                $reason = if ($hardConflict) { 'BUSINESS_BINDING_CONFLICT' }
                    elseif ($location.OperationalStatus -ceq 'UNSUPPORTED') { 'SOURCE_UNSUPPORTED' }
                    elseif ($location.OperationalStatus -cne 'COMPLETE') { 'EXTRACTION_FAILED' }
                    elseif ($location.Status -ceq 'NOT_FOUND') { 'SOURCE_NOT_FOUND' }
                    else { 'BUSINESS_BINDING_AMBIGUOUS' }
                $extraction = New-ScopedBenefitEmptyExtraction -BoundSource $bound -ReasonCodes @($reason)
                $validation = New-ScopedBenefitEmptyValidation -Extraction $extraction
            }
        }
    }

    $reasons = [System.Collections.Generic.List[string]]::new()
    Add-ScopedBenefitReasonCode -Target $reasons -ReasonCodes $Candidate.ReasonCodes
    Add-ScopedBenefitReasonCode -Target $reasons -ReasonCodes $document.ReasonCodes
    Add-ScopedBenefitReasonCode -Target $reasons -ReasonCodes $qualified.ReasonCodes
    Add-ScopedBenefitReasonCode -Target $reasons -ReasonCodes $bound.ReasonCodes
    Add-ScopedBenefitReasonCode -Target $reasons -ReasonCodes $extraction.ReasonCodes
    Add-ScopedBenefitReasonCode -Target $reasons -ReasonCodes $validation.ReasonCodes

    return [pscustomobject][ordered]@{
        SourceRowNumber=$Candidate.SourceRowNumber
        Candidate=$Candidate
        Document=$document
        Qualified=$qualified
        Bound=$bound
        Extraction=$extraction
        Validation=$validation
        Observation=$observation
        LocationResult=$location
        Slices=@($slices)
        PreparationDiagnostics=@($preparationDiagnostics)
        DiscoveryExecution='NOT_REQUESTED'
        ReasonCodes=@($reasons)
    }
}

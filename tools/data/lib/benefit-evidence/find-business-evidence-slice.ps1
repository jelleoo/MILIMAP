Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '../benefit-evidence-location-contracts.ps1')
. (Join-Path $PSScriptRoot '../identity/normalize-business.ps1')
. (Join-Path $PSScriptRoot '../benefit-source/bind-benefit-source.ps1')

function ConvertTo-BenefitEvidencePhone {
    param([AllowNull()]$Value)
    return (([string]$Value) -replace '[^0-9]', '')
}

function Get-BenefitEvidenceField {
    param([Parameter(Mandatory)]$Unit, [Parameter(Mandatory)][string]$Name)
    if ($Unit.StructuredFields.Contains($Name)) { return [string]$Unit.StructuredFields[$Name] }
    return ''
}

function New-BenefitEvidenceLocatorDiagnostic {
    param([string]$Detail, [string]$EvidenceReference='')
    return [pscustomobject][ordered]@{ Code='LOCATOR_IDENTITY_CONFLICT'; Stage='BUSINESS_LOCATOR'; EvidenceReference=$EvidenceReference; Detail=$Detail }
}

function Get-BenefitEvidenceCandidate {
    param([Parameter(Mandatory)]$Unit, [Parameter(Mandatory)]$Business, [AllowNull()][string]$CanonicalPhone='')
    $name = Get-BenefitEvidenceField -Unit $Unit -Name 'BusinessName'
    $address = Get-BenefitEvidenceField -Unit $Unit -Name 'Address'
    $branch = Get-BenefitEvidenceField -Unit $Unit -Name 'Branch'
    $phone = Get-BenefitEvidenceField -Unit $Unit -Name 'Phone'
    $sourceAddress = Get-NormalizedAddressParts -RoadAddress $address -LotAddress '' -MetadataProvince '' -MetadataArea ''
    $fullAddressMatch = $Business.PreferredAddress -and $address -and ((ConvertTo-IdentityComparisonText $Business.PreferredAddress) -ceq (ConvertTo-IdentityComparisonText $address))
    $canonicalPhoneDigits = ConvertTo-BenefitEvidencePhone $CanonicalPhone
    $sourcePhoneDigits = ConvertTo-BenefitEvidencePhone $phone
    $phoneMatch = $canonicalPhoneDigits -and $sourcePhoneDigits -and ($canonicalPhoneDigits -ceq $sourcePhoneDigits)
    $nameMatch = (ConvertTo-IdentityComparisonText $name) -and ((ConvertTo-IdentityComparisonText $name) -ceq (ConvertTo-IdentityComparisonText $Business.NormalizedName))
    if (-not $nameMatch) {
        return [pscustomobject]@{ Unit=$Unit; NameMatch=$false; Strong=$false; Conflict=$false; IdentityReview=([bool]($name -and ($fullAddressMatch -or $phoneMatch))); Evidence=@(); Detail='EXPLICIT_NAME_MISMATCH' }
    }

    $evidence = @('FULL_NAME_MATCH')
    $conflicts = @()
    $addressConflicts = @(Get-BenefitBindingAddressConflicts -Business $Business -AddressParts $sourceAddress)
    if ($addressConflicts.Count -gt 0) { $conflicts += $addressConflicts }
    if ($Business.Floor -and $sourceAddress.Floor -and ((ConvertTo-IdentityComparisonText $Business.Floor) -cne (ConvertTo-IdentityComparisonText $sourceAddress.Floor))) { $conflicts += 'FLOOR_CONFLICT' }
    if ($Business.Unit -and $sourceAddress.Unit -and ((ConvertTo-IdentityComparisonText $Business.Unit) -cne (ConvertTo-IdentityComparisonText $sourceAddress.Unit))) { $conflicts += 'UNIT_CONFLICT' }

    $branchMatch = $Business.BranchName -and $branch -and ((ConvertTo-IdentityComparisonText $Business.BranchName) -ceq (ConvertTo-IdentityComparisonText $branch))

    if ($Business.BranchName -and $branch -and -not $branchMatch) { $conflicts += 'BRANCH_CONFLICT' }
    if ($CanonicalPhone -and $phone -and -not $phoneMatch) { $conflicts += 'PHONE_CONFLICT' }
    if ($fullAddressMatch) { $evidence += 'FULL_ADDRESS_MATCH' }
    if ($branchMatch) { $evidence += 'BRANCH_MATCH' }
    if ($phoneMatch) { $evidence += 'PHONE_MATCH' }
    $conflicts = @($conflicts | Select-Object -Unique)
    return [pscustomobject]@{
        Unit=$Unit; NameMatch=$true; Strong=([bool](($fullAddressMatch -or $branchMatch -or $phoneMatch) -and $conflicts.Count -eq 0)
        ); Conflict=($conflicts.Count -gt 0); IdentityReview=$false; Evidence=@($evidence); Detail=($conflicts -join ',')
    }
}

function Find-BenefitBusinessEvidence {
    param([Parameter(Mandatory)]$Observation, [Parameter(Mandatory)]$Business, [AllowNull()][string]$CanonicalPhone='')
    Assert-ScopeObservation $Observation
    Assert-NormalizedBusiness $Business
    if ([int]$Observation.SourceRowNumber -ne [int]$Business.SourceRowNumber) { throw 'Locator inputs must preserve one SourceRowNumber' }
    if ($Observation.AdapterStatus -cne 'COMPLETE') {
        return New-BenefitEvidenceLocationResult -SourceRowNumber $Observation.SourceRowNumber -OperationalStatus $Observation.AdapterStatus -Status $null -Slices @() -CandidateReferences @() -Diagnostics $Observation.Diagnostics
    }

    $candidates = @(foreach ($unit in $Observation.ContentUnits) { Get-BenefitEvidenceCandidate -Unit $unit -Business $Business -CanonicalPhone $CanonicalPhone })
    $named = @($candidates | Where-Object { $_.NameMatch })
    $references = @($named | ForEach-Object { [string]$_.Unit.UnitReference })
    $diagnostics = @()
    foreach ($candidate in @($named | Where-Object { $_.Conflict })) {
        $diagnostics += New-BenefitEvidenceLocatorDiagnostic -Detail $candidate.Detail -EvidenceReference $candidate.Unit.UnitReference
    }
    foreach ($candidate in @($candidates | Where-Object { $_.IdentityReview })) {
        $diagnostics += New-BenefitEvidenceLocatorDiagnostic -Detail $candidate.Detail -EvidenceReference $candidate.Unit.UnitReference
    }
    $strong = @($named | Where-Object { $_.Strong })
    $unexcluded = @($named | Where-Object { -not $_.Conflict })

    if ($strong.Count -eq 1 -and $unexcluded.Count -eq 1) {
        $selected = $strong[0]
        $slice = New-RelevantBenefitEvidenceSlice -Observation $Observation -Unit $selected.Unit -IdentityEvidence $selected.Evidence
        return New-BenefitEvidenceLocationResult -SourceRowNumber $Observation.SourceRowNumber -OperationalStatus COMPLETE -Status LOCATED -Slices @($slice) -CandidateReferences $references -Diagnostics $diagnostics
    }
    if ($named.Count -gt 0) {
        return New-BenefitEvidenceLocationResult -SourceRowNumber $Observation.SourceRowNumber -OperationalStatus COMPLETE -Status AMBIGUOUS -Slices @() -CandidateReferences $references -Diagnostics $diagnostics
    }
    return New-BenefitEvidenceLocationResult -SourceRowNumber $Observation.SourceRowNumber -OperationalStatus COMPLETE -Status NOT_FOUND -Slices @() -CandidateReferences @() -Diagnostics $diagnostics
}

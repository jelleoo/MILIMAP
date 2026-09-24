Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'benefit-verification-contracts.ps1')
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'identity/normalize-business.ps1')

function ConvertTo-BenefitBindingPhone {
    param([AllowNull()]$Value)
    return (([string]$Value) -replace '[^0-9]', '')
}

function Get-BenefitBindingLabeledValue {
    param([AllowNull()]$Text, [Parameter(Mandatory)][string[]]$Labels)
    $labelExpression = @($Labels | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $match = [regex]::Match([string]$Text, '(?:' + $labelExpression + ')\s*[:：]\s*(?<value>[^;\r\n]+)', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) { return '' }
    return $match.Groups['value'].Value.Trim()
}

function Test-BenefitBindingNameCompatibility {
    param([Parameter(Mandatory)]$Business, [AllowNull()]$Text)
    $documentText = ConvertTo-IdentityComparisonText $Text
    $fullName = ConvertTo-IdentityComparisonText $Business.NormalizedName
    $baseName = ConvertTo-IdentityComparisonText $Business.BaseName
    return [bool](($fullName -and $documentText.Contains($fullName)) -or ($baseName -and $documentText.Contains($baseName)))
}

function Get-BenefitBindingAddressConflicts {
    param([Parameter(Mandatory)]$Business, [Parameter(Mandatory)]$AddressParts)
    $conflicts = @()
    foreach ($component in @(
        @{ Business='Province'; Source='Province'; Code='PROVINCE_CONFLICT' },
        @{ Business='City'; Source='City'; Code='CITY_CONFLICT' },
        @{ Business='District'; Source='District'; Code='DISTRICT_CONFLICT' },
        @{ Business='Dong'; Source='Dong'; Code='DONG_CONFLICT' },
        @{ Business='RoadName'; Source='RoadName'; Code='ROAD_NAME_CONFLICT' },
        @{ Business='BuildingMain'; Source='BuildingMain'; Code='BUILDING_NUMBER_CONFLICT' },
        @{ Business='BuildingSub'; Source='BuildingSub'; Code='BUILDING_SUB_CONFLICT' }
    )) {
        $businessValue = ConvertTo-IdentityComparisonText $Business.($component.Business)
        $sourceValue = ConvertTo-IdentityComparisonText $AddressParts.($component.Source)
        if ($businessValue -and $sourceValue -and $businessValue -ne $sourceValue) { $conflicts += $component.Code }
    }
    return @($conflicts)
}

function Get-BenefitBusinessBinding {
    param([Parameter(Mandatory)]$Source, [Parameter(Mandatory)]$Business, [AllowNull()][string]$CanonicalPhone='')

    Assert-QualifiedBenefitSource $Source
    Assert-NormalizedBusiness $Business
    if ([int]$Source.SourceRowNumber -ne [int]$Business.SourceRowNumber) { throw 'Binding inputs must preserve one SourceRowNumber' }

    $text = [string]$Source.Document.Text
    $nameCompatible = Test-BenefitBindingNameCompatibility -Business $Business -Text $text
    $explicitName = [bool]([regex]::IsMatch($text, '(사업장명|업체명|상호)\s*[:：]'))
    $address = Get-BenefitBindingLabeledValue -Text $text -Labels @('주소','소재지')
    $branch = Get-BenefitBindingLabeledValue -Text $text -Labels @('지점','지점명','branch')
    $phone = Get-BenefitBindingLabeledValue -Text $text -Labels @('전화','전화번호','연락처','phone')
    $addressParts = Get-NormalizedAddressParts -RoadAddress $address -LotAddress '' -MetadataProvince '' -MetadataArea ''
    $branchCompatible = $Business.BranchName -and $branch -and ((ConvertTo-IdentityComparisonText $branch).Contains((ConvertTo-IdentityComparisonText $Business.BranchName)))
    $phoneCompatible = $CanonicalPhone -and $phone -and ((ConvertTo-BenefitBindingPhone $CanonicalPhone) -eq (ConvertTo-BenefitBindingPhone $phone))
    $fullAddressCompatible = $Business.PreferredAddress -and $address -and ((ConvertTo-IdentityComparisonText $address) -eq (ConvertTo-IdentityComparisonText $Business.PreferredAddress))
    $localityCompatible = $Business.City -and $addressParts.City -and ((ConvertTo-IdentityComparisonText $Business.City) -eq (ConvertTo-IdentityComparisonText $addressParts.City))
    $conflict = $false
    $evidence = @()
    $addressConflicts = @(Get-BenefitBindingAddressConflicts -Business $Business -AddressParts $addressParts)

    if ($explicitName -and -not $nameCompatible) { $conflict = $true; $evidence += 'BUSINESS_NAME_CONFLICT' }
    if ($branch -and $Business.BranchName -and -not $branchCompatible) { $conflict = $true; $evidence += 'BRANCH_CONFLICT' }
    if ($addressConflicts.Count -gt 0) { $conflict = $true; $evidence += $addressConflicts }
    if ($phone -and $CanonicalPhone -and $explicitName -and $nameCompatible -and -not $phoneCompatible) { $conflict = $true; $evidence += 'PHONE_CONFLICT' }

    if ($conflict) {
        $status = 'CONFLICT'
        $reasons = @('BUSINESS_BINDING_CONFLICT')
    } elseif ($nameCompatible -and ($fullAddressCompatible -or $branchCompatible -or $phoneCompatible)) {
        $status = 'STRONG'
        $reasons = @()
        if ($fullAddressCompatible) { $evidence += 'FULL_ADDRESS_MATCH' }
        if ($branchCompatible) { $evidence += 'BRANCH_MATCH' }
        if ($phoneCompatible) { $evidence += 'PHONE_MATCH' }
    } elseif ($nameCompatible -and $localityCompatible) {
        $status = 'PLAUSIBLE'
        $reasons = @()
        $evidence += 'LOCALITY_MATCH'
    } else {
        $status = 'AMBIGUOUS'
        $reasons = @('BUSINESS_BINDING_AMBIGUOUS')
    }

    $result = New-BoundBenefitSource -QualifiedSource $Source -BusinessBindingStatus $status -BindingEvidence $evidence -ReasonCodes $reasons
    Assert-BoundBenefitSource $result
    return $result
}

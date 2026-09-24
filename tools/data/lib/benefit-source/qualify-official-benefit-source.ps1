Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'benefit-verification-contracts.ps1')
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'identity/normalize-business.ps1')

function Get-BenefitSourceHostname {
    param([Parameter(Mandatory)][string]$Url)
    try { return ([Uri]$Url).Host.ToLowerInvariant() } catch { return '' }
}

function Test-BenefitBusinessNameCompatibility {
    param([Parameter(Mandatory)]$Business, [AllowNull()]$Text)
    $documentText = ConvertTo-IdentityComparisonText $Text
    $fullName = ConvertTo-IdentityComparisonText $Business.NormalizedName
    $baseName = ConvertTo-IdentityComparisonText $Business.BaseName
    return [bool](($fullName -and $documentText.Contains($fullName)) -or ($baseName -and $documentText.Contains($baseName)))
}

function Test-BenefitFullAddressCompatibility {
    param([Parameter(Mandatory)]$Business, [AllowNull()]$Text)
    $address = ConvertTo-IdentityComparisonText $Business.PreferredAddress
    return [bool]($address -and (ConvertTo-IdentityComparisonText $Text).Contains($address))
}

function Get-BenefitLabeledValue {
    param([AllowNull()]$Text, [Parameter(Mandatory)][string[]]$Labels)
    $labelExpression = @($Labels | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $match = [regex]::Match([string]$Text, '(?:' + $labelExpression + ')\s*[:：]\s*(?<value>[^;\r\n]+)', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) { return '' }
    return $match.Groups['value'].Value.Trim()
}

function Get-BenefitQualificationAddressConflicts {
    param([Parameter(Mandatory)]$Business, [AllowNull()]$Address)
    $source = Get-NormalizedAddressParts -RoadAddress ([string]$Address) -LotAddress '' -MetadataProvince '' -MetadataArea ''
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
        $sourceValue = ConvertTo-IdentityComparisonText $source.($component.Source)
        if ($businessValue -and $sourceValue -and $businessValue -ne $sourceValue) { $conflicts += $component.Code }
    }
    return @($conflicts)
}

function Get-QualifiedBenefitSource {
    param([Parameter(Mandatory)]$Candidate, [Parameter(Mandatory)]$Document, [Parameter(Mandatory)]$Business)

    Assert-BenefitSourceCandidate $Candidate
    Assert-BenefitSourceDocument $Document
    Assert-NormalizedBusiness $Business
    if ([int]$Candidate.SourceRowNumber -ne [int]$Document.SourceRowNumber -or [int]$Candidate.SourceRowNumber -ne [int]$Business.SourceRowNumber) {
        throw 'Qualification inputs must preserve one SourceRowNumber'
    }
    if ([string]$Candidate.Url -cne [string]$Document.Url) { throw 'Qualification candidate and document URLs must match' }

    $officiality = 'UNVERIFIED'
    $evidence = @()
    $reasons = @()
    $documentFetched = [string]$Document.FetchStatus -eq 'COMPLETE'
    $hostname = Get-BenefitSourceHostname $Candidate.Url

    if ([string]$Candidate.SourceKind -eq 'PUBLIC_OFFICIAL') {
        if ($documentFetched -and ($hostname -eq 'go.kr' -or $hostname.EndsWith('.go.kr', [StringComparison]::Ordinal))) {
            $officiality = 'VERIFIED_OFFICIAL'
            $evidence += 'GOVERNMENT_HOST_MATCH'
        } else {
            $reasons += 'SOURCE_OFFICIALITY_UNRESOLVED'
        }
    } else {
        $explicitName = Get-BenefitLabeledValue -Text $Document.Text -Labels @('사업장명','업체명','상호')
        $nameCompatible = Test-BenefitBusinessNameCompatibility -Business $Business -Text $(if ($explicitName) { $explicitName } else { $Document.Text })
        $addressCompatible = Test-BenefitFullAddressCompatibility -Business $Business -Text $Document.Text
        $address = Get-BenefitLabeledValue -Text $Document.Text -Labels @('주소','소재지')
        $branch = Get-BenefitLabeledValue -Text $Document.Text -Labels @('지점','지점명','branch')
        $branchCompatible = $Business.BranchName -and $branch -and ((ConvertTo-IdentityComparisonText $branch) -ceq (ConvertTo-IdentityComparisonText $Business.BranchName))
        $identityConflicts = @(Get-BenefitQualificationAddressConflicts -Business $Business -Address $address)
        if ($explicitName -and -not $nameCompatible) { $identityConflicts += 'BUSINESS_NAME_CONFLICT' }
        if ($branch -and $Business.BranchName -and -not $branchCompatible) { $identityConflicts += 'BRANCH_CONFLICT' }

        if ($documentFetched -and $identityConflicts.Count -gt 0) {
            $officiality = 'REJECTED'
            $evidence += $identityConflicts
            $reasons += 'SOURCE_CONFLICT'
        } elseif ($documentFetched -and $nameCompatible -and ($addressCompatible -or $branchCompatible)) {
            $officiality = 'VERIFIED_OFFICIAL'
            $evidence += 'BUSINESS_NAME_MATCH'
            if ($addressCompatible) { $evidence += 'FULL_ADDRESS_MATCH' }
            if ($branchCompatible) { $evidence += 'BRANCH_MATCH' }
        } else {
            $reasons += 'SOURCE_OFFICIALITY_UNRESOLVED'
        }
    }

    $result = New-QualifiedBenefitSource -Candidate $Candidate -Document $Document -OfficialityStatus $officiality -CurrentnessStatus 'UNKNOWN' -QualificationEvidence $evidence -ReasonCodes $reasons
    Assert-QualifiedBenefitSource $result
    return $result
}

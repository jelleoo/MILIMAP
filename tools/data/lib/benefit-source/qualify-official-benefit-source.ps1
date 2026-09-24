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

function Get-QualifiedBenefitSource {
    param([Parameter(Mandatory)]$Candidate, [Parameter(Mandatory)]$Document, [Parameter(Mandatory)]$Business)

    Assert-BenefitSourceCandidate $Candidate
    Assert-BenefitSourceDocument $Document
    Assert-NormalizedBusiness $Business
    if ([int]$Candidate.SourceRowNumber -ne [int]$Document.SourceRowNumber -or [int]$Candidate.SourceRowNumber -ne [int]$Business.SourceRowNumber) {
        throw 'Qualification inputs must preserve one SourceRowNumber'
    }

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
        $nameCompatible = Test-BenefitBusinessNameCompatibility -Business $Business -Text $Document.Text
        $addressCompatible = Test-BenefitFullAddressCompatibility -Business $Business -Text $Document.Text
        $branch = Get-BenefitLabeledValue -Text $Document.Text -Labels @('지점','지점명','branch')
        $phone = Get-BenefitLabeledValue -Text $Document.Text -Labels @('전화','전화번호','연락처','phone')
        $branchCompatible = $Business.BranchName -and $branch -and ((ConvertTo-IdentityComparisonText $branch).Contains((ConvertTo-IdentityComparisonText $Business.BranchName)))
        $hasExplicitName = [bool]([regex]::IsMatch([string]$Document.Text, '(사업장명|업체명|상호)\s*[:：]'))

        if ($documentFetched -and $nameCompatible -and ($addressCompatible -or $branchCompatible -or $phone)) {
            $officiality = 'VERIFIED_OFFICIAL'
            $evidence += 'BUSINESS_NAME_MATCH'
            if ($addressCompatible) { $evidence += 'FULL_ADDRESS_MATCH' }
            if ($branchCompatible) { $evidence += 'BRANCH_MATCH' }
            if ($phone) { $evidence += 'EXPLICIT_BUSINESS_PHONE' }
        } elseif ($hasExplicitName -and -not $nameCompatible) {
            $officiality = 'REJECTED'
            $reasons += 'SOURCE_CONFLICT'
        } else {
            $reasons += 'SOURCE_OFFICIALITY_UNRESOLVED'
        }
    }

    $result = New-QualifiedBenefitSource -Candidate $Candidate -Document $Document -OfficialityStatus $officiality -CurrentnessStatus 'UNKNOWN' -QualificationEvidence $evidence -ReasonCodes $reasons
    Assert-QualifiedBenefitSource $result
    return $result
}

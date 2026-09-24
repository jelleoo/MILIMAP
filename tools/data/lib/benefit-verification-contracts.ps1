$script:BenefitVerificationContractDefinition = [pscustomobject][ordered]@{
    ContractVersion = 1
    ContractTypes = @(
        'CanonicalBenefitRecord', 'BenefitSourceCandidate', 'BenefitSourceDocument', 'QualifiedBenefitSource',
        'BoundBenefitSource', 'ExtractedBenefitClaim', 'ValidatedBenefitClaim', 'BenefitClaimVerification',
        'BenefitVerificationResult'
    )
    SourceDiscoveryStatus = @('COMPLETE', 'PARTIAL', 'FAILED')
    SourceFormat = @('HTML', 'CSV', 'XLSX', 'PDF', 'UNSUPPORTED')
    SourceKind = @('PUBLIC_OFFICIAL', 'BUSINESS_WEBSITE')
    OfficialityStatus = @('VERIFIED_OFFICIAL', 'UNVERIFIED', 'REJECTED')
    BusinessBindingStatus = @('STRONG', 'PLAUSIBLE', 'AMBIGUOUS', 'CONFLICT')
    ExtractionStatus = @('COMPLETE', 'PARTIAL', 'FAILED')
    EvidenceValidationStatus = @('VALIDATED', 'UNKNOWN', 'CONFLICT', 'INVALID')
    ClaimType = @('BENEFIT_EXISTENCE', 'CURRENT_APPLICABILITY', 'BENEFIT_DESCRIPTION', 'ELIGIBLE_TARGET', 'USAGE_CONDITION', 'VERIFICATION_METHOD', 'VALID_FROM', 'VALID_UNTIL')
    ClaimResult = @('CONFIRMED', 'CHANGED', 'ENDED', 'UNKNOWN', 'CONFLICT', 'NOT_APPLICABLE')
    BenefitState = @('ACTIVE', 'CHANGED', 'ENDED', 'NEEDS_VERIFICATION')
    ReviewClass = @('GREEN', 'YELLOW', 'RED')
    ProductionAction = @('NONE')
    FetchStatus = @('COMPLETE', 'FAILED')
    CurrentnessStatus = @('CURRENT', 'UNKNOWN', 'NOT_CURRENT')
    ReasonCode = @(
        'SOURCE_NOT_FOUND', 'SOURCE_FETCH_FAILED', 'SOURCE_UNSUPPORTED', 'SOURCE_OFFICIALITY_UNRESOLVED',
        'BUSINESS_BINDING_AMBIGUOUS', 'BUSINESS_BINDING_CONFLICT', 'CURRENTNESS_INSUFFICIENT',
        'DISCOVERY_PROVIDER_NOT_CONFIGURED', 'DISCOVERY_PARTIAL_FAILURE', 'DISCOVERY_FAILED',
        'EXTRACTION_PROVIDER_NOT_CONFIGURED', 'EXTRACTION_FAILED', 'EXTRACTION_SOURCE_MISMATCH',
        'CLAIM_UNKNOWN', 'DETAIL_INCOMPLETE', 'MATERIAL_CHANGE', 'EXPLICIT_VALIDITY_END',
        'EXPLICIT_DISCONTINUATION', 'SOURCE_CONFLICT', 'COMPOSITE_EVIDENCE_USED'
    )
}

function Get-BenefitVerificationContractDefinition {
    return $script:BenefitVerificationContractDefinition
}

function ConvertTo-BenefitText {
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return '' }
    return ([string]$Value).Trim()
}

function ConvertTo-BenefitArray {
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return @() }
    return @($Value)
}

function Assert-BenefitRequiredProperties {
    param([Parameter(Mandatory)]$Object, [Parameter(Mandatory)][string[]]$RequiredProperties)
    foreach ($property in $RequiredProperties) {
        if ($Object.PSObject.Properties.Name -notcontains $property) { throw "Missing required property: $property" }
    }
}

function Assert-BenefitContractTypeAndVersion {
    param([Parameter(Mandatory)]$Object, [Parameter(Mandatory)][string]$ExpectedContractType)
    Assert-BenefitRequiredProperties $Object @('ContractType', 'ContractVersion')
    if ([string]$Object.ContractType -ne $ExpectedContractType) { throw "Expected contract type: $ExpectedContractType" }
    if ([int]$Object.ContractVersion -ne $script:BenefitVerificationContractDefinition.ContractVersion) { throw "Unsupported contract version: $($Object.ContractVersion)" }
}

function Assert-BenefitAllowedCode {
    param([Parameter(Mandatory)][string]$Category, [Parameter(Mandatory)][string]$Value)
    $resolvedCategory = if ($Category -eq 'Reason') { 'ReasonCode' } else { $Category }
    if ($script:BenefitVerificationContractDefinition.PSObject.Properties.Name -notcontains $resolvedCategory) { throw "Unknown code category: $Category" }
    if ([string]::IsNullOrWhiteSpace($Value)) { throw "$Category must not be empty" }
    if (@($script:BenefitVerificationContractDefinition.$resolvedCategory) -notcontains $Value) { throw "Invalid $Category code: $Value" }
}

function Assert-BenefitSourceRowNumber {
    param([int]$SourceRowNumber)
    if ($SourceRowNumber -le 1) { throw 'SourceRowNumber must be greater than 1' }
}

function Assert-BenefitNonEmptyText {
    param([AllowNull()]$Value, [Parameter(Mandatory)][string]$Name)
    if ([string]::IsNullOrWhiteSpace([string]$Value)) { throw "$Name must not be empty" }
}

function Assert-BenefitReasonCodes {
    param([AllowNull()][object[]]$ReasonCodes)
    foreach ($reasonCode in @(ConvertTo-BenefitArray $ReasonCodes)) {
        Assert-BenefitAllowedCode 'ReasonCode' ([string]$reasonCode)
    }
}

function New-CanonicalBenefitRecord {
    param(
        [int]$SourceRowNumber, [string]$BusinessName, [string]$BenefitDescription='', [string]$EligibleTarget='',
        [string]$UsageCondition='', [string]$VerificationMethod='', [string]$ExistingSourceType='',
        [string]$ExistingSourceUrl='', [string]$ExistingVerifiedOn=''
    )
    return [pscustomobject][ordered]@{
        ContractType='CanonicalBenefitRecord'; ContractVersion=1; SourceRowNumber=$SourceRowNumber
        BusinessName=ConvertTo-BenefitText $BusinessName; BenefitDescription=ConvertTo-BenefitText $BenefitDescription
        EligibleTarget=ConvertTo-BenefitText $EligibleTarget; UsageCondition=ConvertTo-BenefitText $UsageCondition
        VerificationMethod=ConvertTo-BenefitText $VerificationMethod; ExistingSourceType=ConvertTo-BenefitText $ExistingSourceType
        ExistingSourceUrl=ConvertTo-BenefitText $ExistingSourceUrl; ExistingVerifiedOn=ConvertTo-BenefitText $ExistingVerifiedOn
    }
}

function Assert-CanonicalBenefitRecord {
    param([Parameter(Mandatory)]$Object)
    Assert-BenefitRequiredProperties $Object @('ContractType', 'ContractVersion', 'SourceRowNumber', 'BusinessName', 'BenefitDescription', 'EligibleTarget', 'UsageCondition', 'VerificationMethod', 'ExistingSourceType', 'ExistingSourceUrl', 'ExistingVerifiedOn')
    Assert-BenefitContractTypeAndVersion $Object 'CanonicalBenefitRecord'
    Assert-BenefitSourceRowNumber ([int]$Object.SourceRowNumber)
    Assert-BenefitNonEmptyText $Object.BusinessName 'BusinessName'
}

function New-BenefitSourceCandidate {
    param(
        [int]$SourceRowNumber, [string]$Url, [string]$SourceKind='PUBLIC_OFFICIAL', [string]$SourceLabel='',
        [string]$DiscoveryMethod='', [string]$ObservedAt='', [AllowNull()][object[]]$ReasonCodes=@()
    )
    return [pscustomobject][ordered]@{
        ContractType='BenefitSourceCandidate'; ContractVersion=1; SourceRowNumber=$SourceRowNumber; Url=ConvertTo-BenefitText $Url
        SourceKind=ConvertTo-BenefitText $SourceKind; SourceLabel=ConvertTo-BenefitText $SourceLabel
        DiscoveryMethod=ConvertTo-BenefitText $DiscoveryMethod; ObservedAt=ConvertTo-BenefitText $ObservedAt
        ReasonCodes=@(ConvertTo-BenefitArray $ReasonCodes)
    }
}

function Assert-BenefitSourceCandidate {
    param([Parameter(Mandatory)]$Object)
    Assert-BenefitRequiredProperties $Object @('ContractType', 'ContractVersion', 'SourceRowNumber', 'Url', 'SourceKind', 'SourceLabel', 'DiscoveryMethod', 'ObservedAt', 'ReasonCodes')
    Assert-BenefitContractTypeAndVersion $Object 'BenefitSourceCandidate'
    Assert-BenefitSourceRowNumber ([int]$Object.SourceRowNumber)
    Assert-BenefitNonEmptyText $Object.Url 'Url'
    Assert-BenefitAllowedCode 'SourceKind' ([string]$Object.SourceKind)
    Assert-BenefitReasonCodes $Object.ReasonCodes
}

function New-BenefitSourceDocument {
    param(
        [int]$SourceRowNumber, [string]$Url, [string]$SourceFormat='UNSUPPORTED', [string]$FetchStatus='FAILED',
        [string]$ContentType='', [string]$Text='', [AllowNull()][byte[]]$Bytes=$null, [string]$ObservedAt='',
        [AllowNull()][object[]]$ReasonCodes=@()
    )
    return [pscustomobject][ordered]@{
        ContractType='BenefitSourceDocument'; ContractVersion=1; SourceRowNumber=$SourceRowNumber; Url=ConvertTo-BenefitText $Url
        SourceFormat=ConvertTo-BenefitText $SourceFormat; FetchStatus=ConvertTo-BenefitText $FetchStatus
        ContentType=ConvertTo-BenefitText $ContentType; Text=ConvertTo-BenefitText $Text; Bytes=$Bytes
        ObservedAt=ConvertTo-BenefitText $ObservedAt; ReasonCodes=@(ConvertTo-BenefitArray $ReasonCodes)
    }
}

function Assert-BenefitSourceDocument {
    param([Parameter(Mandatory)]$Object)
    Assert-BenefitRequiredProperties $Object @('ContractType', 'ContractVersion', 'SourceRowNumber', 'Url', 'SourceFormat', 'FetchStatus', 'ContentType', 'Text', 'Bytes', 'ObservedAt', 'ReasonCodes')
    Assert-BenefitContractTypeAndVersion $Object 'BenefitSourceDocument'
    Assert-BenefitSourceRowNumber ([int]$Object.SourceRowNumber)
    Assert-BenefitNonEmptyText $Object.Url 'Url'
    Assert-BenefitAllowedCode 'SourceFormat' ([string]$Object.SourceFormat)
    Assert-BenefitAllowedCode 'FetchStatus' ([string]$Object.FetchStatus)
    Assert-BenefitReasonCodes $Object.ReasonCodes
}

function New-QualifiedBenefitSource {
    param(
        [Parameter(Mandatory)]$Candidate, [Parameter(Mandatory)]$Document, [string]$OfficialityStatus='UNVERIFIED',
        [string]$CurrentnessStatus='UNKNOWN', [AllowNull()][object[]]$QualificationEvidence=@(), [AllowNull()][object[]]$ReasonCodes=@()
    )
    return [pscustomobject][ordered]@{
        ContractType='QualifiedBenefitSource'; ContractVersion=1; SourceRowNumber=$Candidate.SourceRowNumber
        Candidate=$Candidate; Document=$Document; OfficialityStatus=ConvertTo-BenefitText $OfficialityStatus
        CurrentnessStatus=ConvertTo-BenefitText $CurrentnessStatus; QualificationEvidence=@(ConvertTo-BenefitArray $QualificationEvidence)
        ReasonCodes=@(ConvertTo-BenefitArray $ReasonCodes)
    }
}

function Assert-QualifiedBenefitSource {
    param([Parameter(Mandatory)]$Object)
    Assert-BenefitRequiredProperties $Object @('ContractType', 'ContractVersion', 'SourceRowNumber', 'Candidate', 'Document', 'OfficialityStatus', 'CurrentnessStatus', 'QualificationEvidence', 'ReasonCodes')
    Assert-BenefitContractTypeAndVersion $Object 'QualifiedBenefitSource'
    Assert-BenefitSourceRowNumber ([int]$Object.SourceRowNumber)
    Assert-BenefitSourceCandidate $Object.Candidate
    Assert-BenefitSourceDocument $Object.Document
    if ([int]$Object.Candidate.SourceRowNumber -ne [int]$Object.SourceRowNumber -or [int]$Object.Document.SourceRowNumber -ne [int]$Object.SourceRowNumber) { throw 'Qualified source records must preserve SourceRowNumber' }
    Assert-BenefitAllowedCode 'OfficialityStatus' ([string]$Object.OfficialityStatus)
    Assert-BenefitAllowedCode 'CurrentnessStatus' ([string]$Object.CurrentnessStatus)
    Assert-BenefitReasonCodes $Object.ReasonCodes
}

function New-BoundBenefitSource {
    param(
        [Parameter(Mandatory)]$QualifiedSource, [string]$BusinessBindingStatus='AMBIGUOUS',
        [AllowNull()][object[]]$BindingEvidence=@(), [AllowNull()][object[]]$ReasonCodes=@()
    )
    return [pscustomobject][ordered]@{
        ContractType='BoundBenefitSource'; ContractVersion=1; SourceRowNumber=$QualifiedSource.SourceRowNumber
        QualifiedSource=$QualifiedSource; BusinessBindingStatus=ConvertTo-BenefitText $BusinessBindingStatus
        BindingEvidence=@(ConvertTo-BenefitArray $BindingEvidence); ReasonCodes=@(ConvertTo-BenefitArray $ReasonCodes)
    }
}

function Assert-BoundBenefitSource {
    param([Parameter(Mandatory)]$Object)
    Assert-BenefitRequiredProperties $Object @('ContractType', 'ContractVersion', 'SourceRowNumber', 'QualifiedSource', 'BusinessBindingStatus', 'BindingEvidence', 'ReasonCodes')
    Assert-BenefitContractTypeAndVersion $Object 'BoundBenefitSource'
    Assert-BenefitSourceRowNumber ([int]$Object.SourceRowNumber)
    Assert-QualifiedBenefitSource $Object.QualifiedSource
    if ([int]$Object.QualifiedSource.SourceRowNumber -ne [int]$Object.SourceRowNumber) { throw 'Bound source must preserve SourceRowNumber' }
    Assert-BenefitAllowedCode 'BusinessBindingStatus' ([string]$Object.BusinessBindingStatus)
    Assert-BenefitReasonCodes $Object.ReasonCodes
}

function New-ExtractedBenefitClaim {
    param(
        [string]$ClaimType, [string]$Value='', [string]$EvidenceText='', [string]$EvidenceReference='',
        [string]$SourceUrl='', [string]$ExtractionMethod=''
    )
    return [pscustomobject][ordered]@{
        ContractType='ExtractedBenefitClaim'; ContractVersion=1; ClaimType=ConvertTo-BenefitText $ClaimType
        Value=ConvertTo-BenefitText $Value; EvidenceText=ConvertTo-BenefitText $EvidenceText
        EvidenceReference=ConvertTo-BenefitText $EvidenceReference; SourceUrl=ConvertTo-BenefitText $SourceUrl
        ExtractionMethod=ConvertTo-BenefitText $ExtractionMethod
    }
}

function Assert-ExtractedBenefitClaim {
    param([Parameter(Mandatory)]$Object)
    Assert-BenefitRequiredProperties $Object @('ContractType', 'ContractVersion', 'ClaimType', 'Value', 'EvidenceText', 'EvidenceReference', 'SourceUrl', 'ExtractionMethod')
    Assert-BenefitContractTypeAndVersion $Object 'ExtractedBenefitClaim'
    Assert-BenefitAllowedCode 'ClaimType' ([string]$Object.ClaimType)
    Assert-BenefitNonEmptyText $Object.Value 'Value'
    Assert-BenefitNonEmptyText $Object.EvidenceText 'EvidenceText'
}

function New-ValidatedBenefitClaim {
    param(
        [string]$ClaimType, [string]$Value='', [string]$ValidationStatus='UNKNOWN', [string]$EvidenceText='',
        [string]$EvidenceReference='', [string]$SourceUrl='', [AllowNull()][object[]]$ReasonCodes=@()
    )
    return [pscustomobject][ordered]@{
        ContractType='ValidatedBenefitClaim'; ContractVersion=1; ClaimType=ConvertTo-BenefitText $ClaimType
        Value=ConvertTo-BenefitText $Value; ValidationStatus=ConvertTo-BenefitText $ValidationStatus
        EvidenceText=ConvertTo-BenefitText $EvidenceText; EvidenceReference=ConvertTo-BenefitText $EvidenceReference
        SourceUrl=ConvertTo-BenefitText $SourceUrl; ReasonCodes=@(ConvertTo-BenefitArray $ReasonCodes)
    }
}

function Assert-ValidatedBenefitClaim {
    param([Parameter(Mandatory)]$Object)
    Assert-BenefitRequiredProperties $Object @('ContractType', 'ContractVersion', 'ClaimType', 'Value', 'ValidationStatus', 'EvidenceText', 'EvidenceReference', 'SourceUrl', 'ReasonCodes')
    Assert-BenefitContractTypeAndVersion $Object 'ValidatedBenefitClaim'
    Assert-BenefitAllowedCode 'ClaimType' ([string]$Object.ClaimType)
    Assert-BenefitAllowedCode 'EvidenceValidationStatus' ([string]$Object.ValidationStatus)
    if ([string]$Object.ValidationStatus -eq 'VALIDATED') {
        Assert-BenefitNonEmptyText $Object.Value 'Value'
        Assert-BenefitNonEmptyText $Object.EvidenceText 'EvidenceText'
        Assert-BenefitNonEmptyText $Object.SourceUrl 'SourceUrl'
    }
    Assert-BenefitReasonCodes $Object.ReasonCodes
}

function New-BenefitClaimVerification {
    param(
        [string]$ClaimType, [string]$CanonicalValue='', [string]$EvidenceValue='', [string]$Result='UNKNOWN',
        [AllowNull()]$ValidatedClaim=$null, [AllowNull()][object[]]$ReasonCodes=@()
    )
    return [pscustomobject][ordered]@{
        ContractType='BenefitClaimVerification'; ContractVersion=1; ClaimType=ConvertTo-BenefitText $ClaimType
        CanonicalValue=ConvertTo-BenefitText $CanonicalValue; EvidenceValue=ConvertTo-BenefitText $EvidenceValue
        Result=ConvertTo-BenefitText $Result; ValidatedClaim=$ValidatedClaim; ReasonCodes=@(ConvertTo-BenefitArray $ReasonCodes)
    }
}

function Assert-BenefitClaimVerification {
    param([Parameter(Mandatory)]$Object)
    Assert-BenefitRequiredProperties $Object @('ContractType', 'ContractVersion', 'ClaimType', 'CanonicalValue', 'EvidenceValue', 'Result', 'ValidatedClaim', 'ReasonCodes')
    Assert-BenefitContractTypeAndVersion $Object 'BenefitClaimVerification'
    Assert-BenefitAllowedCode 'ClaimType' ([string]$Object.ClaimType)
    Assert-BenefitAllowedCode 'ClaimResult' ([string]$Object.Result)
    if ($null -ne $Object.ValidatedClaim) { Assert-ValidatedBenefitClaim $Object.ValidatedClaim }
    Assert-BenefitReasonCodes $Object.ReasonCodes
}

function New-BenefitVerificationResult {
    param(
        [int]$SourceRowNumber, [string]$BenefitState='NEEDS_VERIFICATION', [string]$ReviewClass='YELLOW',
        [AllowNull()][object[]]$ReasonCodes=@(), [AllowNull()][object[]]$ClaimResults=@(), [AllowNull()][object[]]$Evidence=@(),
        [AllowNull()][object[]]$Warnings=@(), [string]$ProductionAction='NONE'
    )
    return [pscustomobject][ordered]@{
        ContractType='BenefitVerificationResult'; ContractVersion=1; SourceRowNumber=$SourceRowNumber
        BenefitState=ConvertTo-BenefitText $BenefitState; ReviewClass=ConvertTo-BenefitText $ReviewClass
        ReasonCodes=@(ConvertTo-BenefitArray $ReasonCodes); ClaimResults=@(ConvertTo-BenefitArray $ClaimResults)
        Evidence=@(ConvertTo-BenefitArray $Evidence); Warnings=@(ConvertTo-BenefitArray $Warnings)
        ProductionAction=ConvertTo-BenefitText $ProductionAction
    }
}

function Assert-BenefitVerificationResult {
    param([Parameter(Mandatory)]$Object)
    Assert-BenefitRequiredProperties $Object @('ContractType', 'ContractVersion', 'SourceRowNumber', 'BenefitState', 'ReviewClass', 'ReasonCodes', 'ClaimResults', 'Evidence', 'Warnings', 'ProductionAction')
    Assert-BenefitContractTypeAndVersion $Object 'BenefitVerificationResult'
    Assert-BenefitSourceRowNumber ([int]$Object.SourceRowNumber)
    Assert-BenefitAllowedCode 'BenefitState' ([string]$Object.BenefitState)
    Assert-BenefitAllowedCode 'ReviewClass' ([string]$Object.ReviewClass)
    Assert-BenefitReasonCodes $Object.ReasonCodes
    foreach ($claimResult in @(ConvertTo-BenefitArray $Object.ClaimResults)) { Assert-BenefitClaimVerification $claimResult }
    Assert-BenefitAllowedCode 'ProductionAction' ([string]$Object.ProductionAction)
    if ([string]$Object.ProductionAction -ne 'NONE') { throw 'BenefitVerificationResult ProductionAction must be NONE' }
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'benefit-verification-contracts.ps1')
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'benefit-evidence-location-contracts.ps1')

function ConvertTo-BenefitValidationText {
    param([AllowNull()]$Value)
    $text=[Net.WebUtility]::HtmlDecode([string]$Value)
    $text=$text -replace '<[^>]+>',' '
    return (($text -replace '\s+',' ').Trim().ToLowerInvariant())
}

function Get-BenefitValidationNumericTokens {
    param([AllowNull()][string]$Value)
    return @([regex]::Matches([string]$Value,'\d{4}[-./]\d{1,2}[-./]\d{1,2}|\d+(?:\.\d+)?\s*%|\d{1,3}(?:,\d{3})+\s*원|\d+\s*원')|ForEach-Object{$_.Value})
}

function New-BenefitValidationResult {
    param([Parameter(Mandatory)]$Claim,[Parameter(Mandatory)][string]$Status,[AllowNull()][object[]]$ReasonCodes=@())
    $result=New-ValidatedBenefitClaim -ClaimType $Claim.ClaimType -Value $Claim.Value -ValidationStatus $Status -EvidenceText $Claim.EvidenceText -EvidenceReference $Claim.EvidenceReference -SourceUrl $Claim.SourceUrl -ReasonCodes $ReasonCodes
    Assert-ValidatedBenefitClaim $result;return $result
}

function Test-BenefitExtractedClaim {
    param([Parameter(Mandatory)]$Claim,[Parameter(Mandatory)]$Document)
    Assert-ExtractedBenefitClaim $Claim;Assert-BenefitSourceDocument $Document
    $sourceText=ConvertTo-BenefitValidationText $Document.Text;$evidenceText=ConvertTo-BenefitValidationText $Claim.EvidenceText;$valueText=ConvertTo-BenefitValidationText $Claim.Value
    $mismatch=([string]$Claim.SourceUrl -cne [string]$Document.Url) -or -not $evidenceText -or -not $sourceText.Contains($evidenceText) -or -not $valueText -or -not $evidenceText.Contains($valueText)
    foreach($token in @(Get-BenefitValidationNumericTokens $Claim.Value)){$normalizedToken=ConvertTo-BenefitValidationText $token;if(-not $evidenceText.Contains($normalizedToken) -or -not $sourceText.Contains($normalizedToken)){$mismatch=$true}}
    if([string]$Claim.ClaimType -in @('VALID_FROM','VALID_UNTIL')){
        $publication=$evidenceText -match '(게시일|작성일|등록일|공고일|posted|published)'
        $semantics=if([string]$Claim.ClaimType -eq 'VALID_FROM'){$evidenceText -match '(시작|개시|적용\s*시작|effective|from)'}else{$evidenceText -match '(종료|마감|까지|유효\s*(종료|기한)|until|expire)'}
        if($publication -or -not $semantics){$mismatch=$true}
    }
    if($mismatch){return New-BenefitValidationResult -Claim $Claim -Status 'INVALID' -ReasonCodes @('EXTRACTION_SOURCE_MISMATCH')}
    return New-BenefitValidationResult -Claim $Claim -Status 'VALIDATED'
}

function ConvertTo-BenefitScopedValidationText {
    param([AllowNull()]$Value)
    return (([string]$Value -replace '\s+',' ').Trim())
}

function Test-ScopedBenefitExtractedClaim {
    param([Parameter(Mandatory)]$Claim,[Parameter(Mandatory)]$Document,[Parameter(Mandatory)]$EvidenceSlice)
    Assert-ExtractedBenefitClaim $Claim
    Assert-BenefitSourceDocument $Document
    Assert-RelevantBenefitEvidenceSlice -Slice $EvidenceSlice -Document $Document -SourceRowNumber $Document.SourceRowNumber
    $fieldMap = @{ BENEFIT_DESCRIPTION='BenefitDescription'; ELIGIBLE_TARGET='EligibleTarget'; USAGE_CONDITION='UsageCondition'; VERIFICATION_METHOD='VerificationMethod' }
    $mismatch = $false
    $claimType = [string]$Claim.ClaimType
    if (-not $fieldMap.ContainsKey($claimType)) { $mismatch=$true }
    else {
        $field = $fieldMap[$claimType]
        if (-not $EvidenceSlice.StructuredFields.Contains($field) -or -not $EvidenceSlice.FieldReferences.Contains($field)) { $mismatch=$true }
        else {
            $reference = $EvidenceSlice.FieldReferences[$field]
            $sourceValue = [string]$EvidenceSlice.StructuredFields[$field]
            if ([string]$Claim.SourceUrl -cne [string]$Document.Url -or [string]$Claim.EvidenceReference -cne [string]$reference.FieldReference -or
                (ConvertTo-BenefitScopedValidationText $Claim.Value) -cne (ConvertTo-BenefitScopedValidationText $sourceValue) -or
                (ConvertTo-BenefitScopedValidationText $Claim.EvidenceText) -cne (ConvertTo-BenefitScopedValidationText $sourceValue)) { $mismatch=$true }
        }
    }
    if ($mismatch) { return New-BenefitValidationResult -Claim $Claim -Status 'INVALID' -ReasonCodes @('EXTRACTION_SOURCE_MISMATCH') }
    return New-BenefitValidationResult -Claim $Claim -Status 'VALIDATED'
}

function ConvertTo-ValidatedBenefitEvidence {
    param([Parameter(Mandatory)]$Extraction,[Parameter(Mandatory)]$Document,[AllowNull()]$EvidenceSlice=$null)
    foreach($property in @('SourceRowNumber','Status','Claims','ReasonCodes')){if($Extraction.PSObject.Properties.Name -notcontains $property){throw "Missing extraction property: $property"}}
    Assert-BenefitSourceDocument $Document;Assert-BenefitSourceRowNumber ([int]$Extraction.SourceRowNumber);Assert-BenefitAllowedCode 'ExtractionStatus' ([string]$Extraction.Status);Assert-BenefitReasonCodes $Extraction.ReasonCodes
    if([int]$Extraction.SourceRowNumber -ne [int]$Document.SourceRowNumber){throw 'Validation inputs must preserve one SourceRowNumber'}
    if ($PSBoundParameters.ContainsKey('EvidenceSlice')) {
        if ($null -eq $EvidenceSlice) { throw 'Explicit scoped evidence cannot be null' }
        Assert-RelevantBenefitEvidenceSlice -Slice $EvidenceSlice -Document $Document -SourceRowNumber $Document.SourceRowNumber
        $claims=@($Extraction.Claims|ForEach-Object{Test-ScopedBenefitExtractedClaim -Claim $_ -Document $Document -EvidenceSlice $EvidenceSlice})
        $status=if([string]$Extraction.Status -eq 'FAILED'){'FAILED'}elseif(@($claims|Where-Object{$_.ValidationStatus -eq 'INVALID'}).Count -gt 0){'PARTIAL'}else{'COMPLETE'}
        return [pscustomobject][ordered]@{SourceRowNumber=[int]$Extraction.SourceRowNumber;Status=$status;Claims=$claims;ReasonCodes=@($Extraction.ReasonCodes)}
    }
    $validationDocument=$Document
    if($Extraction.PSObject.Properties.Name -contains 'SourceRepresentation' -and -not [string]::IsNullOrWhiteSpace([string]$Extraction.SourceRepresentation)){
        $validationDocument=New-BenefitSourceDocument -SourceRowNumber $Document.SourceRowNumber -Url $Document.Url -SourceFormat $Document.SourceFormat -FetchStatus $Document.FetchStatus -ContentType $Document.ContentType -Text ([string]$Extraction.SourceRepresentation) -Bytes $Document.Bytes -ObservedAt $Document.ObservedAt -ReasonCodes $Document.ReasonCodes
    }
    $claims=@($Extraction.Claims|ForEach-Object{Test-BenefitExtractedClaim -Claim $_ -Document $validationDocument})
    $status=if([string]$Extraction.Status -eq 'FAILED'){'FAILED'}elseif(@($claims|Where-Object{$_.ValidationStatus -eq 'INVALID'}).Count -gt 0){'PARTIAL'}else{'COMPLETE'}
    [pscustomobject][ordered]@{SourceRowNumber=[int]$Extraction.SourceRowNumber;Status=$status;Claims=$claims;ReasonCodes=@($Extraction.ReasonCodes)}
}

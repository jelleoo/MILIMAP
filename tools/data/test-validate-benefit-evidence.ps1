$ErrorActionPreference = 'Stop'

$contractPath = Join-Path $PSScriptRoot 'lib/benefit-verification-contracts.ps1'
$validationPath = Join-Path $PSScriptRoot 'lib/benefit-evidence/validate-benefit-evidence.ps1'
. $contractPath
if (Test-Path -LiteralPath $validationPath) { . $validationPath }

function Assert-Equal {
    param([AllowNull()]$Actual, [AllowNull()]$Expected, [Parameter(Mandatory)][string]$Message)
    if ($Actual -cne $Expected) { throw "$Message (expected: $Expected, actual: $Actual)" }
}

function Assert-True {
    param([bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw $Message }
}
function Assert-Throws {
    param([Parameter(Mandatory)][scriptblock]$Action, [Parameter(Mandatory)][string]$Message)
    $threw=$false
    try { & $Action } catch { $threw=$true }
    if (-not $threw) { throw $Message }
}

function New-TestDocument {
    param([string]$Url='https://city.example.go.kr/benefit', [string]$Text='현역 장병 20% 할인', [int]$SourceRowNumber=2)
    return New-BenefitSourceDocument -SourceRowNumber $SourceRowNumber -Url $Url -SourceFormat 'HTML' -FetchStatus 'COMPLETE' -ContentType 'text/html' -Text $Text -ObservedAt '2026-09-24T00:00:00Z'
}

$document = New-TestDocument
$supported = New-ExtractedBenefitClaim -ClaimType 'BENEFIT_DESCRIPTION' -Value '20% 할인' -EvidenceText '현역 장병 20% 할인' -EvidenceReference 'fixture:1' -SourceUrl $document.Url -ExtractionMethod 'TEST'
$supportedResult = Test-BenefitExtractedClaim -Claim $supported -Document $document
Assert-ValidatedBenefitClaim $supportedResult
Assert-Equal $supportedResult.ValidationStatus 'VALIDATED' 'Exact source-supported benefit must validate'

$inventedPercentage = New-ExtractedBenefitClaim -ClaimType 'BENEFIT_DESCRIPTION' -Value '20% 할인' -EvidenceText '현역 장병 10% 할인' -EvidenceReference 'fixture:2' -SourceUrl $document.Url -ExtractionMethod 'TEST'
$percentageResult = Test-BenefitExtractedClaim -Claim $inventedPercentage -Document (New-TestDocument -Text '현역 장병 10% 할인')
Assert-Equal $percentageResult.ValidationStatus 'INVALID' 'Invented percentage must be invalid'
Assert-True ($percentageResult.ReasonCodes -contains 'EXTRACTION_SOURCE_MISMATCH') 'Invented percentage preserves mismatch reason'

$inventedMoney = New-ExtractedBenefitClaim -ClaimType 'BENEFIT_DESCRIPTION' -Value '5,000원 할인' -EvidenceText '현역 장병 3,000원 할인' -EvidenceReference 'fixture:3' -SourceUrl $document.Url -ExtractionMethod 'TEST'
$moneyResult = Test-BenefitExtractedClaim -Claim $inventedMoney -Document (New-TestDocument -Text '현역 장병 3,000원 할인')
Assert-Equal $moneyResult.ValidationStatus 'INVALID' 'Invented monetary amount must be invalid'

$inventedDate = New-ExtractedBenefitClaim -ClaimType 'VALID_UNTIL' -Value '2026-12-31' -EvidenceText '혜택 종료일 2025-12-31' -EvidenceReference 'fixture:4' -SourceUrl $document.Url -ExtractionMethod 'TEST'
$dateResult = Test-BenefitExtractedClaim -Claim $inventedDate -Document (New-TestDocument -Text '혜택 종료일 2025-12-31')
Assert-Equal $dateResult.ValidationStatus 'INVALID' 'Invented date must be invalid'

$missingEvidence = New-ExtractedBenefitClaim -ClaimType 'BENEFIT_DESCRIPTION' -Value '20% 할인' -EvidenceText '현역 장병 20% 할인' -EvidenceReference 'fixture:5' -SourceUrl $document.Url -ExtractionMethod 'TEST'
$missingEvidenceResult = Test-BenefitExtractedClaim -Claim $missingEvidence -Document (New-TestDocument -Text '현역 장병 10% 할인')
Assert-Equal $missingEvidenceResult.ValidationStatus 'INVALID' 'Evidence text absent from source must be invalid'

$wrongUrl = New-ExtractedBenefitClaim -ClaimType 'BENEFIT_DESCRIPTION' -Value '20% 할인' -EvidenceText '현역 장병 20% 할인' -EvidenceReference 'fixture:6' -SourceUrl 'https://other.example.com/benefit' -ExtractionMethod 'TEST'
$wrongUrlResult = Test-BenefitExtractedClaim -Claim $wrongUrl -Document $document
Assert-True ($wrongUrlResult.ValidationStatus -ne 'VALIDATED') 'Mismatched source URL must not validate'

$publicationDocument = New-TestDocument -Text '게시일 2026-04-03'
foreach ($claimType in @('VALID_FROM', 'VALID_UNTIL')) {
    $publicationClaim = New-ExtractedBenefitClaim -ClaimType $claimType -Value '2026-04-03' -EvidenceText '게시일 2026-04-03' -EvidenceReference 'fixture:publication' -SourceUrl $publicationDocument.Url -ExtractionMethod 'TEST'
    $publicationResult = Test-BenefitExtractedClaim -Claim $publicationClaim -Document $publicationDocument
    Assert-True ($publicationResult.ValidationStatus -ne 'VALIDATED') "Publication date must not validate $claimType"
}

$effectiveDocument = New-TestDocument -Text '혜택 적용 시작일: 2026-04-03'
$effectiveClaim = New-ExtractedBenefitClaim -ClaimType 'VALID_FROM' -Value '2026-04-03' -EvidenceText '혜택 적용 시작일: 2026-04-03' -EvidenceReference 'fixture:effective' -SourceUrl $effectiveDocument.Url -ExtractionMethod 'TEST'
Assert-Equal (Test-BenefitExtractedClaim -Claim $effectiveClaim -Document $effectiveDocument).ValidationStatus 'VALIDATED' 'Explicit effective/start wording validates valid-from date'

$untilDocument = New-TestDocument -Text '혜택 종료일: 2026-12-31까지'
$untilClaim = New-ExtractedBenefitClaim -ClaimType 'VALID_UNTIL' -Value '2026-12-31' -EvidenceText '혜택 종료일: 2026-12-31까지' -EvidenceReference 'fixture:until' -SourceUrl $untilDocument.Url -ExtractionMethod 'TEST'
Assert-Equal (Test-BenefitExtractedClaim -Claim $untilClaim -Document $untilDocument).ValidationStatus 'VALIDATED' 'Explicit until/end wording validates valid-until date'

$mixedExtraction = [pscustomobject]@{
    SourceRowNumber = 2
    Status = 'COMPLETE'
    Claims = @(
        $supported,
        $inventedPercentage
    )
    ReasonCodes = @()
}
$mixed = ConvertTo-ValidatedBenefitEvidence -Extraction $mixedExtraction -Document $document
Assert-Equal $mixed.Status 'PARTIAL' 'Mixed valid and invalid claims must remain operationally partial'
Assert-Equal @($mixed.Claims | Where-Object { $_.ValidationStatus -eq 'VALIDATED' }).Count 1 'One valid claim must survive independently'
Assert-Equal @($mixed.Claims | Where-Object { $_.ValidationStatus -eq 'INVALID' }).Count 1 'One invalid claim must remain preserved independently'

# A1.3 scoped validation independently checks selected original cell provenance.
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-location/test-support.ps1')
. (Join-Path $PSScriptRoot 'lib/benefit-evidence/convert-html-source-observation.ps1')
. (Join-Path $PSScriptRoot 'lib/benefit-evidence/find-business-evidence-slice.ps1')
. (Join-Path $PSScriptRoot 'lib/benefit-evidence/extract-benefit-evidence.ps1')
$scopedDocument = New-ScopeTestDocument
$scopedObservation = ConvertTo-BenefitHtmlObservation -Document $scopedDocument
$scopedBusiness = New-ScopeTestBusiness
$scopedSlice = (Find-BenefitBusinessEvidence -Observation $scopedObservation -Business $scopedBusiness -CanonicalPhone '02-0000-0012').Slices[0]
$scopedClaim = New-ExtractedBenefitClaim -ClaimType BENEFIT_DESCRIPTION -Value '10% 할인' -EvidenceText '10% 할인' -EvidenceReference $scopedSlice.FieldReferences.BenefitDescription.FieldReference -SourceUrl $scopedDocument.Url -ExtractionMethod SCOPED_HTML_CELL
$scopedValidated = Test-ScopedBenefitExtractedClaim -Claim $scopedClaim -Document $scopedDocument -EvidenceSlice $scopedSlice
Assert-Equal $scopedValidated.ValidationStatus 'VALIDATED' 'Selected original detail cell validates independently'
$foreignClaim = New-ExtractedBenefitClaim -ClaimType BENEFIT_DESCRIPTION -Value '30% 할인' -EvidenceText '30% 할인' -EvidenceReference $scopedObservation.ContentUnits[1].FieldReferences.BenefitDescription.FieldReference -SourceUrl $scopedDocument.Url -ExtractionMethod SCOPED_HTML_CELL
$foreignExtraction = [pscustomobject]@{SourceRowNumber=2;Status='COMPLETE';Claims=@($foreignClaim);ReasonCodes=@();SourceRepresentation='30% 할인'}
$foreignValidated = ConvertTo-ValidatedBenefitEvidence -Extraction $foreignExtraction -Document $scopedDocument -EvidenceSlice $scopedSlice
Assert-Equal $foreignValidated.Claims[0].ValidationStatus 'INVALID' 'Extractor-authored representation cannot certify a foreign-row claim'
Assert-True ($foreignValidated.Claims[0].ReasonCodes -contains 'EXTRACTION_SOURCE_MISMATCH') 'Foreign-row claim preserves mismatch reason'
$wrongType = New-ExtractedBenefitClaim -ClaimType ELIGIBLE_TARGET -Value '10% 할인' -EvidenceText '10% 할인' -EvidenceReference $scopedSlice.FieldReferences.BenefitDescription.FieldReference -SourceUrl $scopedDocument.Url -ExtractionMethod SCOPED_HTML_CELL
Assert-Equal (Test-ScopedBenefitExtractedClaim -Claim $wrongType -Document $scopedDocument -EvidenceSlice $scopedSlice).ValidationStatus 'INVALID' 'Correct value under another claim type fails'
$wrongReference = New-ExtractedBenefitClaim -ClaimType BENEFIT_DESCRIPTION -Value '10% 할인' -EvidenceText '10% 할인' -EvidenceReference 'HTML_TABLE_9_ROW_9/BenefitDescription' -SourceUrl $scopedDocument.Url -ExtractionMethod SCOPED_HTML_CELL
Assert-Equal (Test-ScopedBenefitExtractedClaim -Claim $wrongReference -Document $scopedDocument -EvidenceSlice $scopedSlice).ValidationStatus 'INVALID' 'Matching text without selected field reference fails'
$wrongUrlScoped = New-ExtractedBenefitClaim -ClaimType BENEFIT_DESCRIPTION -Value '10% 할인' -EvidenceText '10% 할인' -EvidenceReference $scopedSlice.FieldReferences.BenefitDescription.FieldReference -SourceUrl 'https://other.example.com/list' -ExtractionMethod SCOPED_HTML_CELL
Assert-Equal (Test-ScopedBenefitExtractedClaim -Claim $wrongUrlScoped -Document $scopedDocument -EvidenceSlice $scopedSlice).ValidationStatus 'INVALID' 'Different source URL fails scoped validation'
Assert-Throws { ConvertTo-ValidatedBenefitEvidence -Extraction $foreignExtraction -Document $scopedDocument -EvidenceSlice $null } 'An explicitly supplied null slice must not enable legacy validation'
$mutatedSlice = $scopedSlice
$mutatedSlice.StructuredFields['BenefitDescription'] = '99% 할인'
Assert-Throws { Assert-RelevantBenefitEvidenceSlice -Slice $mutatedSlice -Document $scopedDocument -SourceRowNumber 2 } 'A mutated slice field must fail original-source provenance validation'
$qualifiedHtml = (Get-ScopeTestHtml).Replace('10% 할인','&lt;회원만&gt; 10% 할인')
$qualifiedDocument = New-ScopeTestDocument -Html $qualifiedHtml
$qualifiedObservation = ConvertTo-BenefitHtmlObservation -Document $qualifiedDocument
$qualifiedSlice = (Find-BenefitBusinessEvidence -Observation $qualifiedObservation -Business $scopedBusiness -CanonicalPhone '02-0000-0012').Slices[0]
$truncatedQualifiedClaim = New-ExtractedBenefitClaim -ClaimType BENEFIT_DESCRIPTION -Value '10% 할인' -EvidenceText '10% 할인' -EvidenceReference $qualifiedSlice.FieldReferences.BenefitDescription.FieldReference -SourceUrl $qualifiedDocument.Url -ExtractionMethod SCOPED_HTML_CELL
Assert-Equal (Test-ScopedBenefitExtractedClaim -Claim $truncatedQualifiedClaim -Document $qualifiedDocument -EvidenceSlice $qualifiedSlice).ValidationStatus 'INVALID' 'Decoded literal qualifiers cannot be stripped to certify a truncated scoped claim'

Write-Host 'Benefit evidence validation tests passed.'

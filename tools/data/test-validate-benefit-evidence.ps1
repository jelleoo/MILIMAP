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

Write-Host 'Benefit evidence validation tests passed.'

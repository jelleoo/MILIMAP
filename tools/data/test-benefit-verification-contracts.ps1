$ErrorActionPreference = 'Stop'

$contractPath = Join-Path $PSScriptRoot 'lib/benefit-verification-contracts.ps1'
if (Test-Path -LiteralPath $contractPath) { . $contractPath }

function Assert-Equal {
    param([AllowNull()]$Actual, [AllowNull()]$Expected, [Parameter(Mandatory)][string]$Message)
    if ($Actual -cne $Expected) { throw "$Message (expected: $Expected, actual: $Actual)" }
}

function Assert-NoThrow {
    param([Parameter(Mandatory)][scriptblock]$Action, [Parameter(Mandatory)][string]$Message)
    try { & $Action } catch { throw "$Message ($($_.Exception.Message))" }
}

function Assert-Throws {
    param([Parameter(Mandatory)][scriptblock]$Action, [Parameter(Mandatory)][string]$Message)
    $threw = $false
    try { & $Action } catch { $threw = $true }
    if (-not $threw) { throw $Message }
}

$definition = Get-BenefitVerificationContractDefinition
Assert-Equal $definition.ContractVersion 1 'Contract version must be 1'

$requiredCodes = @{
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
    ReasonCode = @('SOURCE_NOT_FOUND', 'SOURCE_FETCH_FAILED', 'SOURCE_UNSUPPORTED', 'SOURCE_OFFICIALITY_UNRESOLVED', 'BUSINESS_BINDING_AMBIGUOUS', 'BUSINESS_BINDING_CONFLICT', 'CURRENTNESS_INSUFFICIENT', 'DISCOVERY_PROVIDER_NOT_CONFIGURED', 'DISCOVERY_PARTIAL_FAILURE', 'DISCOVERY_FAILED', 'EXTRACTION_PROVIDER_NOT_CONFIGURED', 'EXTRACTION_FAILED', 'EXTRACTION_SOURCE_MISMATCH', 'CLAIM_UNKNOWN', 'DETAIL_INCOMPLETE', 'MATERIAL_CHANGE', 'EXPLICIT_VALIDITY_END', 'EXPLICIT_DISCONTINUATION', 'SOURCE_CONFLICT', 'COMPOSITE_EVIDENCE_USED')
}
foreach ($category in $requiredCodes.Keys) {
    foreach ($code in $requiredCodes[$category]) {
        Assert-NoThrow { Assert-BenefitAllowedCode $category $code } "Required code must be allowed: $category/$code"
    }
}
Assert-Throws { Assert-BenefitAllowedCode 'ProductionAction' 'APPLY' } 'ProductionAction APPLY must be rejected'

$benefit = New-CanonicalBenefitRecord -SourceRowNumber 2 -BusinessName '테스트 식당' -BenefitDescription '10% 할인' -EligibleTarget '현역 장병' -UsageCondition '평일' -VerificationMethod '군인증' -ExistingSourceType '지자체 공식 자료' -ExistingSourceUrl 'https://example.go.kr/benefit' -ExistingVerifiedOn '2026-09-01'
Assert-NoThrow { Assert-CanonicalBenefitRecord $benefit } 'Canonical benefit record must be valid'
Assert-Equal $benefit.ContractVersion 1 'Canonical benefit contract version'

$candidate = New-BenefitSourceCandidate -SourceRowNumber 2 -Url 'https://example.go.kr/benefit' -SourceKind 'PUBLIC_OFFICIAL' -DiscoveryMethod 'EXISTING_CANONICAL_URL'
Assert-NoThrow { Assert-BenefitSourceCandidate $candidate } 'Benefit source candidate must be valid'

$document = New-BenefitSourceDocument -SourceRowNumber 2 -Url 'https://example.go.kr/benefit' -SourceFormat 'HTML' -FetchStatus 'COMPLETE' -Text '현역 장병 10% 할인'
Assert-NoThrow { Assert-BenefitSourceDocument $document } 'Benefit source document must be valid'

$qualified = New-QualifiedBenefitSource -Candidate $candidate -Document $document -OfficialityStatus 'VERIFIED_OFFICIAL' -CurrentnessStatus 'UNKNOWN'
Assert-NoThrow { Assert-QualifiedBenefitSource $qualified } 'Qualified benefit source must be valid'

$bound = New-BoundBenefitSource -QualifiedSource $qualified -BusinessBindingStatus 'STRONG' -BindingEvidence @('business-name-and-address')
Assert-NoThrow { Assert-BoundBenefitSource $bound } 'Bound benefit source must be valid'

$extracted = New-ExtractedBenefitClaim -ClaimType 'BENEFIT_DESCRIPTION' -Value '10% 할인' -EvidenceText '현역 장병 10% 할인' -SourceUrl 'https://example.go.kr/benefit'
Assert-NoThrow { Assert-ExtractedBenefitClaim $extracted } 'Extracted benefit claim must be valid'

$validated = New-ValidatedBenefitClaim -ClaimType 'BENEFIT_DESCRIPTION' -Value '10% 할인' -ValidationStatus 'VALIDATED' -EvidenceText '현역 장병 10% 할인' -SourceUrl 'https://example.go.kr/benefit'
Assert-NoThrow { Assert-ValidatedBenefitClaim $validated } 'Validated claim with source evidence must be valid'
Assert-Throws { $x = New-ValidatedBenefitClaim -ClaimType 'VALID_UNTIL' -Value '2026-12-31' -ValidationStatus 'VALIDATED' -EvidenceText ''; Assert-ValidatedBenefitClaim $x } 'Validated claim requires source evidence'

$claimVerification = New-BenefitClaimVerification -ClaimType 'BENEFIT_DESCRIPTION' -CanonicalValue '10% 할인' -EvidenceValue '10% 할인' -Result 'CONFIRMED' -ValidatedClaim $validated
Assert-NoThrow { Assert-BenefitClaimVerification $claimVerification } 'Benefit claim verification must be valid'

$result = New-BenefitVerificationResult -SourceRowNumber 2 -BenefitState 'ACTIVE' -ReviewClass 'YELLOW' -ReasonCodes @('DETAIL_INCOMPLETE') -ClaimResults @($claimVerification) -Evidence @($bound)
Assert-NoThrow { Assert-BenefitVerificationResult $result } 'Benefit verification result must be valid'
Assert-Equal $result.ProductionAction 'NONE' 'Shadow action must be NONE'
Assert-Throws { $x = New-BenefitVerificationResult -SourceRowNumber 2 -ProductionAction 'APPLY'; Assert-BenefitVerificationResult $x } 'Non-NONE production action must fail'

Write-Host 'Benefit verification contract tests passed.'

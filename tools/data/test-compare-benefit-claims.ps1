$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/benefit-verification-contracts.ps1')
$comparisonPath = Join-Path $PSScriptRoot 'lib/benefit-verification/compare-benefit-claims.ps1'
if (Test-Path -LiteralPath $comparisonPath) { . $comparisonPath }

function Assert-Equal { param([AllowNull()]$Actual, [AllowNull()]$Expected, [Parameter(Mandatory)][string]$Message); if ($Actual -cne $Expected) { throw "$Message (expected: $Expected, actual: $Actual)" } }
function Assert-True { param([bool]$Condition, [Parameter(Mandatory)][string]$Message); if (-not $Condition) { throw $Message } }
function New-TestBenefit { New-CanonicalBenefitRecord -SourceRowNumber 2 -BusinessName '테스트 식당' -BenefitDescription '10% 할인' -EligibleTarget '현역 장병만' -UsageCondition '상시' -VerificationMethod '군인 신분증 확인' }
function New-TestValidated {
    param([string]$ClaimType, [string]$Value, [string]$ValidationStatus='VALIDATED')
    New-ValidatedBenefitClaim -ClaimType $ClaimType -Value $Value -ValidationStatus $ValidationStatus -EvidenceText "근거: $Value" -EvidenceReference 'fixture:1' -SourceUrl 'https://city.example.go.kr/benefit'
}

Assert-Equal (Compare-BenefitClaim -ClaimType 'BENEFIT_DESCRIPTION' -CanonicalValue '10% 할인' -EvidenceValue '이용금액 10% 할인').Result 'CONFIRMED' 'Same explicit percentage with approved boilerplate must confirm'
Assert-Equal (Compare-BenefitClaim -ClaimType 'BENEFIT_DESCRIPTION' -CanonicalValue '10% 할인' -EvidenceValue '결제금액의 10% 할인').Result 'CONFIRMED' 'Payment wording with the same percentage must confirm'
Assert-Equal (Compare-BenefitClaim -ClaimType 'BENEFIT_DESCRIPTION' -CanonicalValue '10% 할인' -EvidenceValue '20% 할인').Result 'CHANGED' 'Different explicit percentage must change'
Assert-Equal (Compare-BenefitClaim -ClaimType 'BENEFIT_DESCRIPTION' -CanonicalValue '10% 할인' -EvidenceValue '군 장병 할인 혜택').Result 'UNKNOWN' 'Ambiguous benefit wording must remain unknown'
Assert-Equal (Compare-BenefitClaim -ClaimType 'ELIGIBLE_TARGET' -CanonicalValue '현역 장병' -EvidenceValue '군 관계자').Result 'UNKNOWN' 'Ambiguous target relationship must remain unknown'
Assert-Equal (Compare-BenefitClaim -ClaimType 'ELIGIBLE_TARGET' -CanonicalValue '현역 장병만' -EvidenceValue '현역 장병 및 군무원').Result 'CHANGED' 'Explicit target expansion must change'
Assert-Equal (Compare-BenefitClaim -ClaimType 'USAGE_CONDITION' -CanonicalValue '상시' -EvidenceValue '평일만').Result 'CHANGED' 'Explicit weekday-only restriction must change'
Assert-Equal (Compare-BenefitClaim -ClaimType 'VERIFICATION_METHOD' -CanonicalValue '군인 신분증 확인' -EvidenceValue '나라사랑카드 결제 필수').Result 'CHANGED' 'Explicit verification method replacement must change'
Assert-Equal (Compare-BenefitClaim -ClaimType 'ELIGIBLE_TARGET' -CanonicalValue ' 현역  장병 ' -EvidenceValue '현역 장병').Result 'CONFIRMED' 'Whitespace-normalized exact text must confirm'

$benefit = New-TestBenefit
$invalid = New-TestValidated -ClaimType 'BENEFIT_DESCRIPTION' -Value '20% 할인' -ValidationStatus 'INVALID'
$invalidResult = @(Compare-BenefitClaims -Benefit $benefit -ValidatedEvidence @($invalid))[0]
Assert-Equal $invalidResult.Result 'UNKNOWN' 'INVALID evidence must not become decisive'

$unknown = New-TestValidated -ClaimType 'BENEFIT_DESCRIPTION' -Value '20% 할인' -ValidationStatus 'UNKNOWN'
$unknownResult = @(Compare-BenefitClaims -Benefit $benefit -ValidatedEvidence @($unknown))[0]
Assert-Equal $unknownResult.Result 'UNKNOWN' 'UNKNOWN evidence must not become decisive'

$confirmedEvidence = New-TestValidated -ClaimType 'BENEFIT_DESCRIPTION' -Value '10% 할인'
$confirmedResult = @(Compare-BenefitClaims -Benefit $benefit -ValidatedEvidence @($confirmedEvidence))[0]
Assert-Equal $confirmedResult.Result 'CONFIRMED' 'Validated matching evidence must produce a decisive confirmation'
Assert-True ($confirmedResult.ValidatedClaim -eq $confirmedEvidence) 'Decisive verification must retain its validated claim'
Assert-BenefitClaimVerification $confirmedResult

$changedEvidence = New-TestValidated -ClaimType 'BENEFIT_DESCRIPTION' -Value '20% 할인'
$conflicts = @(Compare-BenefitClaims -Benefit $benefit -ValidatedEvidence @($confirmedEvidence, $changedEvidence))
Assert-Equal @($conflicts | Where-Object { $_.Result -eq 'CONFLICT' }).Count 2 'Contradictory validated material values must remain unresolved conflicts'
Assert-True (@($conflicts | Where-Object { $_.ReasonCodes -contains 'SOURCE_CONFLICT' }).Count -eq 2) 'Conflicting evidence must preserve source-conflict reasons'

Write-Host 'Benefit claim comparison tests passed.'

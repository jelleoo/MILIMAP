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

$validationConflict = New-TestValidated -ClaimType 'BENEFIT_DESCRIPTION' -Value '10% 할인' -ValidationStatus 'CONFLICT'
$validationConflict.ReasonCodes = @('SOURCE_CONFLICT')
$validationConflictResult = @(Compare-BenefitClaims -Benefit $benefit -ValidatedEvidence @($validationConflict))[0]
Assert-Equal $validationConflictResult.Result 'CONFLICT' 'A conflict-status validated claim must remain a claim-level conflict'
Assert-True ($validationConflictResult.ReasonCodes -contains 'SOURCE_CONFLICT') 'A conflict-status validated claim must preserve its conflict reason'

$negatedEnd = New-TestValidated -ClaimType 'CURRENT_APPLICABILITY' -Value '혜택 종료 예정 없음'
$negatedEndResult = @(Compare-BenefitClaims -Benefit $benefit -ValidatedEvidence @($negatedEnd))[0]
Assert-Equal $negatedEndResult.Result 'UNKNOWN' 'Negated ending language must not become explicit ending evidence'
$negatedCurrent = New-TestValidated -ClaimType 'CURRENT_APPLICABILITY' -Value '현재 적용되지 않습니다'
$negatedCurrentResult = @(Compare-BenefitClaims -Benefit $benefit -ValidatedEvidence @($negatedCurrent))[0]
Assert-Equal $negatedCurrentResult.Result 'UNKNOWN' 'Negated currentness language must not become confirmed applicability'

# Review regression: semantically equivalent multi-source evidence is not a conflict.
$equivalentConfirmedA = New-TestValidated -ClaimType 'BENEFIT_DESCRIPTION' -Value '10% 할인'
$equivalentConfirmedB = New-TestValidated -ClaimType 'BENEFIT_DESCRIPTION' -Value '이용금액 10% 할인'
$equivalentConfirmedResults = @(Compare-BenefitClaims -Benefit $benefit -ValidatedEvidence @($equivalentConfirmedA, $equivalentConfirmedB))
Assert-Equal @($equivalentConfirmedResults | Where-Object { $_.Result -eq 'CONFLICT' }).Count 0 'Equivalent confirmed benefit wording must not become a source conflict'
Assert-Equal @($equivalentConfirmedResults | Where-Object { $_.Result -eq 'CONFIRMED' }).Count 2 'Equivalent confirmed benefit wording must remain confirmed'

$equivalentChangedA = New-TestValidated -ClaimType 'BENEFIT_DESCRIPTION' -Value '20% 할인'
$equivalentChangedB = New-TestValidated -ClaimType 'BENEFIT_DESCRIPTION' -Value '이용금액 20% 할인'
$equivalentChangedResults = @(Compare-BenefitClaims -Benefit $benefit -ValidatedEvidence @($equivalentChangedA, $equivalentChangedB))
Assert-Equal @($equivalentChangedResults | Where-Object { $_.Result -eq 'CONFLICT' }).Count 0 'Equivalent changed benefit wording must not become a source conflict'
Assert-Equal @($equivalentChangedResults | Where-Object { $_.Result -eq 'CHANGED' }).Count 2 'Equivalent changed benefit wording must remain changed'

$trueChangedA = New-TestValidated -ClaimType 'BENEFIT_DESCRIPTION' -Value '20% 할인'
$trueChangedB = New-TestValidated -ClaimType 'BENEFIT_DESCRIPTION' -Value '30% 할인'
$trueChangedResults = @(Compare-BenefitClaims -Benefit $benefit -ValidatedEvidence @($trueChangedA, $trueChangedB))
Assert-Equal @($trueChangedResults | Where-Object { $_.Result -eq 'CONFLICT' }).Count 2 'Materially different validated benefit values must remain conflicts'

$currentEquivalentA = New-TestValidated -ClaimType 'CURRENT_APPLICABILITY' -Value '현재 적용'
$currentEquivalentB = New-TestValidated -ClaimType 'CURRENT_APPLICABILITY' -Value '적용 중'
$currentEquivalentResults = @(Compare-BenefitClaims -Benefit $benefit -ValidatedEvidence @($currentEquivalentA, $currentEquivalentB))
Assert-Equal @($currentEquivalentResults | Where-Object { $_.Result -eq 'CONFLICT' }).Count 0 'Equivalent current-applicability wording must not become a source conflict'
Assert-Equal @($currentEquivalentResults | Where-Object { $_.Result -eq 'CONFIRMED' }).Count 2 'Equivalent current-applicability wording must remain confirmed'

Assert-Equal (Compare-BenefitClaim -ClaimType 'VALID_UNTIL' -CanonicalValue '2026-12-31' -EvidenceValue '2026.12.31').Result 'CONFIRMED' 'Equivalent validity dates with separator-only formatting differences must confirm'

$sameDateA = New-TestValidated -ClaimType 'VALID_UNTIL' -Value '2026-12-31'
$sameDateB = New-TestValidated -ClaimType 'VALID_UNTIL' -Value '2026.12.31'
$sameDateResults = @(Compare-BenefitClaims -Benefit $benefit -ValidatedEvidence @($sameDateA, $sameDateB))
Assert-Equal @($sameDateResults | Where-Object { $_.Result -eq 'CONFLICT' }).Count 0 'Equivalent validity-date formatting must not become source conflict'

$differentDate = New-TestValidated -ClaimType 'VALID_UNTIL' -Value '2027-01-01'
$differentDateResults = @(Compare-BenefitClaims -Benefit $benefit -ValidatedEvidence @($sameDateA, $differentDate))
Assert-Equal @($differentDateResults | Where-Object { $_.Result -eq 'CONFLICT' }).Count 2 'Different validated validity dates must remain unresolved source conflicts'

Write-Host 'Benefit claim comparison tests passed.'



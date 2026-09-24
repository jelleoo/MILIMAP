Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'benefit-verification-contracts.ps1')

function Add-BenefitEvaluationReason { param([Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Reasons, [Parameter(Mandatory)][string]$Reason); if ($Reasons -notcontains $Reason) { $Reasons.Add($Reason) } }
function Test-BenefitClaimResult { param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$ClaimResults, [Parameter(Mandatory)][string]$ClaimType, [Parameter(Mandatory)][string[]]$Results); return @($ClaimResults | Where-Object { $_.ClaimType -eq $ClaimType -and $Results -contains $_.Result }).Count -gt 0 }
function New-BenefitStateEvaluationResult {
    param([Parameter(Mandatory)][string]$BenefitState, [Parameter(Mandatory)][string]$ReviewClass, [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$ClaimResults, [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$ReasonCodes)
    $evidence = @($ClaimResults | ForEach-Object { $_.ValidatedClaim } | Where-Object { $null -ne $_ })
    [pscustomobject][ordered]@{ BenefitState=$BenefitState; ReviewClass=$ReviewClass; ReasonCodes=@($ReasonCodes); ClaimResults=@($ClaimResults); Evidence=$evidence; Warnings=@(); ProductionAction='NONE' }
}
function Invoke-BenefitStateEvaluation {
    param([Parameter(Mandatory)]$Benefit, [AllowNull()][object[]]$Sources=@(), [AllowNull()][object[]]$ClaimResults=@(), [AllowNull()]$OperationalStatus=$null)
    Assert-CanonicalBenefitRecord $Benefit
    $sources = @($Sources | Where-Object { $null -ne $_ }); $claims = @($ClaimResults | Where-Object { $null -ne $_ }); foreach ($source in $sources) { Assert-BoundBenefitSource $source }; foreach ($claim in $claims) { Assert-BenefitClaimVerification $claim }
    $reasons = [System.Collections.Generic.List[string]]::new(); $sourceConflict = @($sources | Where-Object { $_.BusinessBindingStatus -eq 'CONFLICT' -or $_.ReasonCodes -contains 'SOURCE_CONFLICT' }).Count -gt 0; $bindingConflict = @($sources | Where-Object { $_.BusinessBindingStatus -eq 'CONFLICT' -or $_.ReasonCodes -contains 'BUSINESS_BINDING_CONFLICT' }).Count -gt 0; $claimConflict = @($claims | Where-Object { $_.Result -eq 'CONFLICT' -or $_.ReasonCodes -contains 'SOURCE_CONFLICT' }).Count -gt 0
    if ($bindingConflict) { Add-BenefitEvaluationReason $reasons 'BUSINESS_BINDING_CONFLICT' }; if ($sourceConflict -or $claimConflict) { Add-BenefitEvaluationReason $reasons 'SOURCE_CONFLICT' }; if ($bindingConflict -or $sourceConflict -or $claimConflict) { return New-BenefitStateEvaluationResult 'NEEDS_VERIFICATION' 'RED' $claims $reasons }
    $ambiguous = @($sources | Where-Object { $_.BusinessBindingStatus -eq 'AMBIGUOUS' -or $_.ReasonCodes -contains 'BUSINESS_BINDING_AMBIGUOUS' }).Count -gt 0; if ($ambiguous) { Add-BenefitEvaluationReason $reasons 'BUSINESS_BINDING_AMBIGUOUS'; return New-BenefitStateEvaluationResult 'NEEDS_VERIFICATION' 'YELLOW' $claims $reasons }
    $operationalFailed = $false
    if ($null -ne $OperationalStatus) { if ($OperationalStatus.PSObject.Properties.Name -contains 'DiscoveryStatus' -and $OperationalStatus.DiscoveryStatus -ne 'COMPLETE') { $operationalFailed = $true; if ($OperationalStatus.DiscoveryStatus -eq 'FAILED') { Add-BenefitEvaluationReason $reasons 'DISCOVERY_FAILED' } elseif ($OperationalStatus.DiscoveryStatus -eq 'PARTIAL') { Add-BenefitEvaluationReason $reasons 'DISCOVERY_PARTIAL_FAILURE' } }; if ($OperationalStatus.PSObject.Properties.Name -contains 'ExtractionStatus' -and $OperationalStatus.ExtractionStatus -ne 'COMPLETE') { $operationalFailed = $true; if ($OperationalStatus.ExtractionStatus -eq 'FAILED') { Add-BenefitEvaluationReason $reasons 'EXTRACTION_FAILED' } } }
    if ($operationalFailed) { return New-BenefitStateEvaluationResult 'NEEDS_VERIFICATION' 'YELLOW' $claims $reasons }
    $strongBinding = @($sources | Where-Object { $_.BusinessBindingStatus -eq 'STRONG' }).Count -gt 0; $explicitEnd = @($claims | Where-Object { $_.Result -eq 'ENDED' -and $_.ValidatedClaim.ValidationStatus -eq 'VALIDATED' -and (@($_.ReasonCodes | Where-Object { $_ -in @('EXPLICIT_VALIDITY_END', 'EXPLICIT_DISCONTINUATION') }).Count -gt 0) }).Count -gt 0
    if ($strongBinding -and $explicitEnd) { Add-BenefitEvaluationReason $reasons 'EXPLICIT_DISCONTINUATION'; return New-BenefitStateEvaluationResult 'ENDED' 'GREEN' $claims $reasons }
    $existenceConfirmed = Test-BenefitClaimResult -ClaimResults $claims -ClaimType 'BENEFIT_EXISTENCE' -Results @('CONFIRMED'); $currentConfirmed = Test-BenefitClaimResult -ClaimResults $claims -ClaimType 'CURRENT_APPLICABILITY' -Results @('CONFIRMED')
    if (-not $existenceConfirmed -or -not $currentConfirmed) { Add-BenefitEvaluationReason $reasons 'CURRENTNESS_INSUFFICIENT'; return New-BenefitStateEvaluationResult 'NEEDS_VERIFICATION' 'YELLOW' $claims $reasons }; if (-not $strongBinding) { return New-BenefitStateEvaluationResult 'NEEDS_VERIFICATION' 'YELLOW' $claims $reasons }
    $detailTypes = @('BENEFIT_DESCRIPTION', 'ELIGIBLE_TARGET', 'USAGE_CONDITION', 'VERIFICATION_METHOD'); $detailComplete = @($detailTypes | Where-Object { -not (Test-BenefitClaimResult -ClaimResults $claims -ClaimType $_ -Results @('CONFIRMED', 'CHANGED', 'NOT_APPLICABLE')) }).Count -eq 0; if (-not $detailComplete) { Add-BenefitEvaluationReason $reasons 'DETAIL_INCOMPLETE' }
    $materialChange = @($claims | Where-Object { $_.Result -eq 'CHANGED' }).Count -gt 0; if ($materialChange) { Add-BenefitEvaluationReason $reasons 'MATERIAL_CHANGE'; return New-BenefitStateEvaluationResult 'CHANGED' $(if ($detailComplete) { 'GREEN' } else { 'YELLOW' }) $claims $reasons }
    return New-BenefitStateEvaluationResult 'ACTIVE' $(if ($detailComplete) { 'GREEN' } else { 'YELLOW' }) $claims $reasons
}

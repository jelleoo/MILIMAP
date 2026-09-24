Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'benefit-verification-contracts.ps1')

function ConvertTo-BenefitComparisonText {
    param([AllowNull()]$Value)
    $text = [string]$Value
    try { $text = $text.Normalize([Text.NormalizationForm]::FormKC) } catch { }
    return (($text.ToLowerInvariant() -replace '[\s\p{Z}]+', ' ').Trim())
}

function Get-BenefitComparisonAmountTokens {
    param([AllowNull()]$Value)
    return @([regex]::Matches((ConvertTo-BenefitComparisonText $Value), '\d+(?:\.\d+)?\s*%|\d{1,3}(?:,\d{3})+\s*원|\d+\s*원') | ForEach-Object { ($_.Value -replace '\s+', '').ToLowerInvariant() })
}

function Get-BenefitComparisonDateToken {
    param([AllowNull()]$Value)
    $match = [regex]::Match((ConvertTo-BenefitComparisonText $Value), '\b(?<year>\d{4})[-./](?<month>\d{1,2})[-./](?<day>\d{1,2})\b')
    if (-not $match.Success) { return '' }
    $year = [int]$match.Groups['year'].Value
    $month = [int]$match.Groups['month'].Value
    $day = [int]$match.Groups['day'].Value
    if ($month -lt 1 -or $month -gt 12 -or $day -lt 1 -or $day -gt 31) { return '' }
    return ('{0:D4}-{1:D2}-{2:D2}' -f $year, $month, $day)
}

function New-BenefitComparisonResult {
    param([string]$ClaimType, [string]$CanonicalValue, [string]$EvidenceValue, [string]$Result, [AllowNull()][object[]]$ReasonCodes=@())
    [pscustomobject][ordered]@{ ClaimType=$ClaimType; CanonicalValue=$CanonicalValue; EvidenceValue=$EvidenceValue; Result=$Result; ReasonCodes=@($ReasonCodes) }
}

function Compare-BenefitClaim {
    param([Parameter(Mandatory)][string]$ClaimType, [AllowNull()][string]$CanonicalValue='', [AllowNull()][string]$EvidenceValue='')
    Assert-BenefitAllowedCode 'ClaimType' $ClaimType
    $canonical = ConvertTo-BenefitComparisonText $CanonicalValue; $evidence = ConvertTo-BenefitComparisonText $EvidenceValue
    if (-not $canonical -or -not $evidence) { return New-BenefitComparisonResult $ClaimType $CanonicalValue $EvidenceValue 'UNKNOWN' @('CLAIM_UNKNOWN') }
    if ($canonical -ceq $evidence) { return New-BenefitComparisonResult $ClaimType $CanonicalValue $EvidenceValue 'CONFIRMED' }
    if ($ClaimType -eq 'BENEFIT_DESCRIPTION') {
        $canonicalAmounts = @(Get-BenefitComparisonAmountTokens $canonical); $evidenceAmounts = @(Get-BenefitComparisonAmountTokens $evidence)
        if ($canonicalAmounts.Count -eq 1 -and $evidenceAmounts.Count -eq 1) {
            if ($canonicalAmounts[0] -cne $evidenceAmounts[0]) { return New-BenefitComparisonResult $ClaimType $CanonicalValue $EvidenceValue 'CHANGED' @('MATERIAL_CHANGE') }
            $canonicalWithoutBoilerplate = ($canonical -replace '^(이용\s*금액|결제\s*금액의?)\s*', '').Trim(); $evidenceWithoutBoilerplate = ($evidence -replace '^(이용\s*금액|결제\s*금액의?)\s*', '').Trim()
            if ($canonicalWithoutBoilerplate -ceq $evidenceWithoutBoilerplate) { return New-BenefitComparisonResult $ClaimType $CanonicalValue $EvidenceValue 'CONFIRMED' }
        }
    }
    if ($ClaimType -eq 'ELIGIBLE_TARGET') {
        $canonicalTarget = ($canonical -replace '만$', '').Trim()
        if ($canonicalTarget -and $evidence -match ('^' + [regex]::Escape($canonicalTarget) + '\s*(및|,|·)\s*\S+')) { return New-BenefitComparisonResult $ClaimType $CanonicalValue $EvidenceValue 'CHANGED' @('MATERIAL_CHANGE') }
    }
    if ($ClaimType -eq 'USAGE_CONDITION') { $explicitConditions = @('상시', '평일만', '주말만', '공휴일 제외'); if ($explicitConditions -contains $canonical -and $explicitConditions -contains $evidence) { return New-BenefitComparisonResult $ClaimType $CanonicalValue $EvidenceValue 'CHANGED' @('MATERIAL_CHANGE') } }
    if ($ClaimType -eq 'VERIFICATION_METHOD') {
        $canonicalMethod = if ($canonical -match '군인\s*신분증') { 'MILITARY_ID' } elseif ($canonical -match '나라사랑카드') { 'NARASARANG_CARD' } else { '' }
        $evidenceMethod = if ($evidence -match '군인\s*신분증') { 'MILITARY_ID' } elseif ($evidence -match '나라사랑카드') { 'NARASARANG_CARD' } else { '' }
        if ($canonicalMethod -and $evidenceMethod -and $canonicalMethod -cne $evidenceMethod) { return New-BenefitComparisonResult $ClaimType $CanonicalValue $EvidenceValue 'CHANGED' @('MATERIAL_CHANGE') }
    }
    if ($ClaimType -in @('VALID_FROM', 'VALID_UNTIL')) {
        $canonicalDate = Get-BenefitComparisonDateToken $canonical
        $evidenceDate = Get-BenefitComparisonDateToken $evidence
        if ($canonicalDate -and $evidenceDate) {
            if ($canonicalDate -ceq $evidenceDate) { return New-BenefitComparisonResult $ClaimType $CanonicalValue $EvidenceValue 'CONFIRMED' }
            return New-BenefitComparisonResult $ClaimType $CanonicalValue $EvidenceValue 'CHANGED' @('MATERIAL_CHANGE')
        }
    }
    return New-BenefitComparisonResult $ClaimType $CanonicalValue $EvidenceValue 'UNKNOWN' @('CLAIM_UNKNOWN')
}

function Get-BenefitCanonicalClaimValue {
    param([Parameter(Mandatory)]$Benefit, [Parameter(Mandatory)][string]$ClaimType)
    switch ($ClaimType) { 'BENEFIT_DESCRIPTION' { return [string]$Benefit.BenefitDescription }; 'ELIGIBLE_TARGET' { return [string]$Benefit.EligibleTarget }; 'USAGE_CONDITION' { return [string]$Benefit.UsageCondition }; 'VERIFICATION_METHOD' { return [string]$Benefit.VerificationMethod }; default { return '' } }
}

function Get-BenefitLifecycleComparisonResult {
    param([Parameter(Mandatory)]$Claim)
    $value = ConvertTo-BenefitComparisonText $Claim.Value
    if ($Claim.ClaimType -eq 'CURRENT_APPLICABILITY' -and $value -match '^(혜택\s*)?(종료|중단|폐지)(됨|되었습니다|입니다)?$') { return [pscustomobject]@{ Result='ENDED'; ReasonCodes=@('EXPLICIT_DISCONTINUATION') } }
    if ($Claim.ClaimType -eq 'CURRENT_APPLICABILITY' -and $value -match '^(현재\s*)?(적용|적용\s*중|이용\s*가능|상시)$') { return [pscustomobject]@{ Result='CONFIRMED'; ReasonCodes=@() } }
    if ($Claim.ClaimType -eq 'BENEFIT_EXISTENCE' -and $value -match '^(혜택|할인)\s*(제공|적용)$') { return [pscustomobject]@{ Result='CONFIRMED'; ReasonCodes=@() } }
    return [pscustomobject]@{ Result='UNKNOWN'; ReasonCodes=@('CLAIM_UNKNOWN') }
}

function Test-BenefitValidatedClaimSetConflict {
    param([Parameter(Mandatory)]$Benefit, [Parameter(Mandatory)][string]$ClaimType, [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Claims)
    $validated = @($Claims | Where-Object { $_.ClaimType -eq $ClaimType -and $_.ValidationStatus -eq 'VALIDATED' })
    if ($validated.Count -le 1) { return $false }

    $canonicalValue = Get-BenefitCanonicalClaimValue -Benefit $Benefit -ClaimType $ClaimType
    if ($canonicalValue -or $ClaimType -in @('VALID_FROM','VALID_UNTIL')) {
        $baseline = $validated[0]
        foreach ($candidate in @($validated | Select-Object -Skip 1)) {
            $pair = Compare-BenefitClaim -ClaimType $ClaimType -CanonicalValue $baseline.Value -EvidenceValue $candidate.Value
            if ($pair.Result -eq 'CHANGED') { return $true }
        }
        return $false
    }

    $decisive = @($validated | ForEach-Object { (Get-BenefitLifecycleComparisonResult -Claim $_).Result } | Where-Object { $_ -in @('CONFIRMED','ENDED') } | Select-Object -Unique)
    return $decisive.Count -gt 1
}

function Compare-BenefitClaims {
    param([Parameter(Mandatory)]$Benefit, [AllowNull()][object[]]$ValidatedEvidence=@())
    Assert-CanonicalBenefitRecord $Benefit
    $claims = @($ValidatedEvidence | Where-Object { $null -ne $_ }); foreach ($claim in $claims) { Assert-ValidatedBenefitClaim $claim }
    $conflictTypes = @()
    foreach ($claimType in @($claims | ForEach-Object { $_.ClaimType } | Select-Object -Unique)) {
        if (Test-BenefitValidatedClaimSetConflict -Benefit $Benefit -ClaimType $claimType -Claims $claims) { $conflictTypes += $claimType }
    }
    $results = @()
    foreach ($claim in $claims) {
        $canonicalValue = Get-BenefitCanonicalClaimValue -Benefit $Benefit -ClaimType $claim.ClaimType; $result = 'UNKNOWN'; $reasons = @('CLAIM_UNKNOWN')
        if ($claim.ValidationStatus -eq 'CONFLICT') { $result = 'CONFLICT'; $reasons = @('SOURCE_CONFLICT') }
        elseif ($claim.ValidationStatus -eq 'VALIDATED') {
            if ($conflictTypes -contains $claim.ClaimType) { $result = 'CONFLICT'; $reasons = @('SOURCE_CONFLICT') }
            elseif ($canonicalValue) { $comparison = Compare-BenefitClaim -ClaimType $claim.ClaimType -CanonicalValue $canonicalValue -EvidenceValue $claim.Value; $result = $comparison.Result; $reasons = @($comparison.ReasonCodes) }
            else { $comparison = Get-BenefitLifecycleComparisonResult -Claim $claim; $result = $comparison.Result; $reasons = @($comparison.ReasonCodes) }
        }
        $verification = New-BenefitClaimVerification -ClaimType $claim.ClaimType -CanonicalValue $canonicalValue -EvidenceValue $claim.Value -Result $result -ValidatedClaim $claim -ReasonCodes $reasons; Assert-BenefitClaimVerification $verification; $results += $verification
    }
    return @($results)
}

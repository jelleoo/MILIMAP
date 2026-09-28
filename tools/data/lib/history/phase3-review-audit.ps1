Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'history-contracts.ps1')

function Get-Phase3ReviewRoute {
    param([string[]]$ChangeCandidates=@())

    $candidateRoutes = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    $candidateRoutes.Add('BASELINE_ESTABLISHED','RECORD_ONLY')
    $candidateRoutes.Add('EVIDENCE_CHANGE_ONLY','RECORD_ONLY')
    $candidateRoutes.Add('LOCATION_CHANGE_SUSPECTED','HUMAN_DOMAIN_REVIEW')
    $candidateRoutes.Add('LOCATION_ABSENCE_SUSPECTED','HUMAN_DOMAIN_REVIEW')
    $candidateRoutes.Add('BENEFIT_CHANGE_SUSPECTED','HUMAN_DOMAIN_REVIEW')
    $candidateRoutes.Add('BENEFIT_ABSENCE_SUSPECTED','HUMAN_DOMAIN_REVIEW')
    $candidateRoutes.Add('CANONICAL_INPUT_CHANGED','AUDIT_VERIFICATION')
    $candidateRoutes.Add('PROCESSOR_OUTPUT_CHANGED','OPERATIONAL_DIAGNOSTIC')
    $candidateRoutes.Add('OPERATIONAL_FAILURE','OPERATIONAL_DIAGNOSTIC')
    $candidateRoutes.Add('COMPARISON_UNAVAILABLE','OPERATIONAL_DIAGNOSTIC')

    $route = ''
    foreach ($candidate in $ChangeCandidates) {
        if (-not $candidateRoutes.ContainsKey($candidate)) { throw "Unknown review candidate: $candidate" }
        $candidateRoute = $candidateRoutes[$candidate]
        if ($route -and $route -cne $candidateRoute) { throw 'Mixed review route categories' }
        $route = $candidateRoute
    }
    if (-not $route) { return 'RECORD_ONLY' }
    return $route
}

function New-Phase3ReviewItem {
    param(
        [Parameter(Mandatory)]$Observation,
        [AllowNull()]$Comparison=$null
    )

    Assert-HistoryObservation -Value $Observation
    if ($null -ne $Comparison) {
        Assert-ObservationComparison -Value $Comparison
        foreach ($property in @('BusinessId','Domain','RunId')) {
            if ([string]$Comparison.$property -cne [string]$Observation.$property) {
                throw "Comparison/current $property mismatch"
            }
        }
        if ([string]$Comparison.CurrentObservationId -cne [string]$Observation.ObservationId) {
            throw 'Comparison/current observation ID mismatch'
        }
    }

    $reviewKey = if ($null -eq $Comparison) { [string]$Observation.ObservationId } else { [string]$Comparison.ComparisonId }
    $previousId = if ($null -eq $Comparison) { '' } else { [string]$Comparison.PreviousObservationId }
    $comparisonId = if ($null -eq $Comparison) { '' } else { [string]$Comparison.ComparisonId }
    $comparisonStatus = if ($null -eq $Comparison) { '' } else { [string]$Comparison.ComparisonStatus }
    $deltas = if ($null -eq $Comparison) { @() } else { @($Comparison.DeltaDimensions) }
    $candidates = if ($null -eq $Comparison) { @() } else { @($Comparison.ChangeCandidates) }
    $reasons = if ($null -eq $Comparison) { @() } else { @($Comparison.ReasonCodes) }
    $auditFlags = if ($null -eq $Comparison) { @('COMPARISON_NOT_RECORDED') } else { @() }
    $route = if ($null -eq $Comparison) { 'AUDIT_VERIFICATION' } else { Get-Phase3ReviewRoute -ChangeCandidates $candidates }

    return [pscustomobject][ordered]@{
        ContractType='Phase3ReviewItem'
        ContractVersion=1
        ReviewKey=$reviewKey
        BusinessId=[string]$Observation.BusinessId
        Domain=[string]$Observation.Domain
        RunId=[string]$Observation.RunId
        ObservedAt=[string]$Observation.ObservedAt
        CurrentObservationId=[string]$Observation.ObservationId
        PreviousObservationId=$previousId
        ComparisonId=$comparisonId
        ReviewRoute=$route
        ComparisonStatus=$comparisonStatus
        DeltaDimensions=@($deltas)
        ChangeCandidates=@($candidates)
        ReasonCodes=@($reasons)
        AuditFlags=@($auditFlags)
        CurrentOperationalStatus=[string]$Observation.OperationalStatus
        CurrentComparable=[bool]$Observation.Comparable
        CurrentNonComparableReasons=@($Observation.NonComparableReasons)
        SemanticResultReference=[string]$Observation.SemanticResultReference
        ArtifactReferences=@($Observation.ArtifactReferences)
    }
}

function New-Phase3ReviewAuditSummary {
    param(
        [object[]]$Items=@(),
        [Parameter(Mandatory)][int]$CommittedRunCount,
        [Parameter(Mandatory)][int]$CommittedObservationCount,
        [Parameter(Mandatory)][int]$CommittedComparisonCount,
        [Parameter(Mandatory)][int]$IgnoredUncommittedRecordCount,
        [Parameter(Mandatory)][int]$UniqueArtifactReferenceCount,
        [Parameter(Mandatory)][int]$UniqueArtifactsValidated
    )

    $recordOnly = 0
    $humanReview = 0
    $auditVerification = 0
    $operationalDiagnostic = 0
    $missingComparison = 0
    $location = 0
    $benefit = 0
    $candidateCounts = @{}

    foreach ($item in $Items) {
        if ($null -eq $item -or [string]$item.ContractType -cne 'Phase3ReviewItem' -or [int]$item.ContractVersion -ne 1) {
            throw 'Invalid Phase 3 review item'
        }
        switch -CaseSensitive ([string]$item.ReviewRoute) {
            'RECORD_ONLY' { $recordOnly++ }
            'HUMAN_DOMAIN_REVIEW' { $humanReview++ }
            'AUDIT_VERIFICATION' { $auditVerification++ }
            'OPERATIONAL_DIAGNOSTIC' { $operationalDiagnostic++ }
            default { throw 'Invalid Phase 3 review route' }
        }
        switch -CaseSensitive ([string]$item.Domain) {
            'LOCATION' { $location++ }
            'BENEFIT' { $benefit++ }
            default { throw 'Invalid Phase 3 review domain' }
        }
        if (@($item.AuditFlags) -ccontains 'COMPARISON_NOT_RECORDED') { $missingComparison++ }
        foreach ($candidate in @($item.ChangeCandidates)) {
            if (-not $candidateCounts.ContainsKey([string]$candidate)) { $candidateCounts[[string]$candidate] = 0 }
            $candidateCounts[[string]$candidate]++
        }
    }

    return [pscustomobject][ordered]@{
        CommittedRunCount=$CommittedRunCount
        CommittedObservationCount=$CommittedObservationCount
        CommittedComparisonCount=$CommittedComparisonCount
        ReviewItemCount=$Items.Count
        RecordOnlyCount=$recordOnly
        HumanDomainReviewCount=$humanReview
        AuditVerificationCount=$auditVerification
        OperationalDiagnosticCount=$operationalDiagnostic
        MissingComparisonCount=$missingComparison
        IgnoredUncommittedRecordCount=$IgnoredUncommittedRecordCount
        UniqueArtifactReferenceCount=$UniqueArtifactReferenceCount
        UniqueArtifactsValidated=$UniqueArtifactsValidated
        LocationItemCount=$location
        BenefitItemCount=$benefit
        CandidateCounts=$candidateCounts
    }
}

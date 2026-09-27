Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$historyRoot = $PSScriptRoot
$dataLibRoot = Split-Path -Parent $historyRoot

. (Join-Path $dataLibRoot 'poi-verification-contracts.ps1')
. (Join-Path $dataLibRoot 'poi-matching/evaluate-poi-match.ps1')
. (Join-Path $historyRoot 'history-contracts.ps1')
. (Join-Path $historyRoot 'history-fingerprints.ps1')

$script:LocationHistoryAdapterVersion = 1
$script:LocationHistoryMaterialReasonCodes = @(
    'SINGLE_STRONG_CANDIDATE',
    'MULTIPLE_PLAUSIBLE_CANDIDATES',
    'INSUFFICIENT_IDENTITY_EVIDENCE',
    'NO_CANDIDATE',
    'DISCOVERY_PARTIAL_FAILURE',
    'DISCOVERY_FAILED'
)

function ConvertTo-LocationHistoryInputProjection {
    param(
        [Parameter(Mandatory)][string]$BusinessId,
        [Parameter(Mandatory)]$Business
    )

    Assert-HistoryBusinessId -Value $BusinessId
    Assert-NormalizedBusiness $Business

    return [pscustomobject][ordered]@{
        ProjectionType='LocationHistoryInput'
        ProjectionVersion=1
        BusinessId=$BusinessId
        OriginalName=[string]$Business.OriginalName
        NormalizedName=[string]$Business.NormalizedName
        BaseName=[string]$Business.BaseName
        BranchName=[string]$Business.BranchName
        OriginalRoadAddress=[string]$Business.OriginalRoadAddress
        OriginalLotAddress=[string]$Business.OriginalLotAddress
        PreferredAddress=[string]$Business.PreferredAddress
        Province=[string]$Business.Province
        City=[string]$Business.City
        District=[string]$Business.District
        Dong=[string]$Business.Dong
        RoadName=[string]$Business.RoadName
        BuildingMain=[string]$Business.BuildingMain
        BuildingSub=[string]$Business.BuildingSub
        Floor=[string]$Business.Floor
        Unit=[string]$Business.Unit
    }
}

function ConvertTo-LocationHistoryEvidenceProjection {
    param([Parameter(Mandatory)]$DiscoveryBatch)

    Assert-PoiDiscoveryBatch $DiscoveryBatch

    $candidates = [Collections.Generic.List[object]]::new()
    foreach($candidate in @($DiscoveryBatch.Candidates)) {
        Assert-PoiCandidate $candidate
        $memberships = [Collections.Generic.List[object]]::new()
        $seenMemberships = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($discovery in @($candidate.DiscoveredBy)) {
            Assert-PoiDiscoveryEvidence $discovery
            $membership = [pscustomobject][ordered]@{
                StrategyCode=[string]$discovery.StrategyCode
                Query=[string]$discovery.Query
                QueryOrder=[int]$discovery.QueryOrder
            }
            $membershipKey = ConvertTo-HistoryCanonicalJson -Value $membership
            if($seenMemberships.Add($membershipKey)) { $memberships.Add($membership) }
        }

        $candidates.Add([pscustomobject][ordered]@{
            Provider=[string]$candidate.Provider
            OriginalName=[string]$candidate.OriginalName
            NormalizedName=[string]$candidate.NormalizedName
            RoadAddress=[string]$candidate.RoadAddress
            LotAddress=[string]$candidate.LotAddress
            Latitude=$candidate.Latitude
            Longitude=$candidate.Longitude
            Phone=[string]$candidate.Phone
            Category=[string]$candidate.Category
            ProviderLink=[string]$candidate.ProviderLink
            DiscoveredBy=@($memberships)
        })
    }

    $attempts = [Collections.Generic.List[object]]::new()
    foreach($attempt in @($DiscoveryBatch.QueryAttempts)) {
        Assert-PoiQueryAttempt $attempt
        $attempts.Add([pscustomobject][ordered]@{
            StrategyCode=[string]$attempt.StrategyCode
            Query=[string]$attempt.Query
            QueryOrder=[int]$attempt.QueryOrder
            Status=[string]$attempt.Status
            ErrorCode=[string]$attempt.ErrorCode
        })
    }

    return [pscustomobject][ordered]@{
        ProjectionType='LocationHistoryEvidence'
        ProjectionVersion=1
        DiscoveryStatus=[string]$DiscoveryBatch.Status
        QueryAttempts=@($attempts)
        Candidates=@($candidates)
    }
}

function ConvertTo-LocationHistorySemanticProjection {
    param(
        [Parameter(Mandatory)]$DiscoveryBatch,
        [Parameter(Mandatory)]$Result
    )

    Assert-PoiDiscoveryBatch $DiscoveryBatch
    Assert-PoiMatchResult $Result
    if([int]$DiscoveryBatch.SourceRowNumber -ne [int]$Result.SourceRowNumber) {
        throw 'DiscoveryBatch and Result SourceRowNumber must match'
    }

    $selectedLocation = $null
    $selectionStatus = 'NONE'
    if($null -ne $Result.SelectedCandidate) {
        Assert-PoiCandidate $Result.SelectedCandidate
        $selectionStatus = 'SELECTED'
        $selectedLocation = [pscustomobject][ordered]@{
            Name=ConvertTo-PoiMatchCompactText ([string]$Result.SelectedCandidate.NormalizedName)
            RoadAddress=ConvertTo-PoiMatchCompactText ([string]$Result.SelectedCandidate.RoadAddress)
            LotAddress=ConvertTo-PoiMatchCompactText ([string]$Result.SelectedCandidate.LotAddress)
            Latitude=$Result.SelectedCandidate.Latitude
            Longitude=$Result.SelectedCandidate.Longitude
        }
    }

    $materialReasons = @($Result.ReasonCodes |
        Where-Object { $script:LocationHistoryMaterialReasonCodes -contains [string]$_ } |
        Sort-Object -CaseSensitive -Unique)
    $conflictCodes = @($Result.ConflictCodes | ForEach-Object { [string]$_ } | Sort-Object -CaseSensitive -Unique)
    $absenceEligible = (
        [string]$DiscoveryBatch.Status -ceq 'COMPLETE' -and
        @($DiscoveryBatch.Candidates).Count -eq 0 -and
        [string]$Result.EvaluationStatus -ceq 'COMPLETE' -and
        [string]$Result.Classification -ceq 'RED' -and
        $null -eq $Result.SelectedCandidate -and
        @($Result.ReasonCodes | Where-Object { [string]$_ -ceq 'NO_CANDIDATE' }).Count -gt 0
    )

    return [pscustomobject][ordered]@{
        ProjectionType='LocationHistorySemantic'
        ProjectionVersion=1
        EvaluationStatus=[string]$Result.EvaluationStatus
        Classification=[string]$Result.Classification
        SelectionStatus=$selectionStatus
        SelectedLocation=$selectedLocation
        MaterialReasonCodes=$materialReasons
        ConflictCodes=$conflictCodes
        AbsenceEligible=[bool]$absenceEligible
    }
}

function ConvertTo-LocationHistoryExecutionProjection {
    param(
        [Parameter(Mandatory)][string]$RepositoryRevision,
        [AllowNull()]$ExecutionConfiguration=$null
    )

    if($RepositoryRevision -cnotmatch '^[0-9a-f]{40}$') { throw 'RepositoryRevision must be a lowercase 40-character SHA' }

    return [pscustomobject][ordered]@{
        ProjectionType='LocationHistoryExecution'
        ProjectionVersion=1
        RepositoryRevision=$RepositoryRevision
        LocationHistoryAdapterVersion=$script:LocationHistoryAdapterVersion
        PoiContractVersion=(Get-PoiVerificationContractDefinition).ContractVersion
        HistoryContractVersion=$script:HistoryContractVersion
        FingerprintSchemaVersion=$script:FingerprintSchemaVersion
        ComparatorVersion=$script:ComparatorVersion
        Configuration=$ExecutionConfiguration
    }
}

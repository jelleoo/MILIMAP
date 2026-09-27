Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$historyRoot = $PSScriptRoot
$dataLibRoot = Split-Path -Parent $historyRoot

. (Join-Path $dataLibRoot 'poi-verification-contracts.ps1')
. (Join-Path $dataLibRoot 'poi-matching/evaluate-poi-match.ps1')
. (Join-Path $historyRoot 'history-contracts.ps1')
. (Join-Path $historyRoot 'history-fingerprints.ps1')
. (Join-Path $historyRoot 'history-store.ps1')

$script:LocationHistoryAdapterVersion = 1
$script:LocationHistoryMaterialReasonCodes = @(
    'SINGLE_STRONG_CANDIDATE',
    'MULTIPLE_PLAUSIBLE_CANDIDATES',
    'INSUFFICIENT_IDENTITY_EVIDENCE',
    'NO_CANDIDATE',
    'DISCOVERY_PARTIAL_FAILURE',
    'DISCOVERY_FAILED'
)
$script:LocationHistoryEvidenceOrderInsensitivePaths = @(
    'Candidates',
    'Candidates[].DiscoveredBy',
    'QueryAttempts'
)
$script:LocationHistorySemanticOrderInsensitivePaths = @(
    'MaterialReasonCodes',
    'ConflictCodes'
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

function Get-LocationHistoryOperationalAssessment {
    param(
        [Parameter(Mandatory)]$DiscoveryBatch,
        [Parameter(Mandatory)]$Result
    )

    Assert-PoiDiscoveryBatch $DiscoveryBatch
    Assert-PoiMatchResult $Result
    if([int]$DiscoveryBatch.SourceRowNumber -ne [int]$Result.SourceRowNumber) {
        throw 'DiscoveryBatch and Result SourceRowNumber must match'
    }

    $reasons = [Collections.Generic.List[string]]::new()
    if([string]$DiscoveryBatch.Status -ceq 'FAILED') {
        $reasons.Add('DISCOVERY_FAILED')
    } elseif([string]$DiscoveryBatch.Status -cne 'COMPLETE') {
        $reasons.Add('DISCOVERY_PARTIAL_FAILURE')
    }
    if([string]$Result.EvaluationStatus -cne 'COMPLETE') {
        $reasons.Add('EVALUATION_INCOMPLETE')
    }

    $operationalStatus = if([string]$DiscoveryBatch.Status -ceq 'FAILED') {
        'FAILED'
    } elseif([string]$DiscoveryBatch.Status -cne 'COMPLETE' -or [string]$Result.EvaluationStatus -cne 'COMPLETE') {
        'PARTIAL'
    } else {
        'COMPLETE'
    }
    return [pscustomobject][ordered]@{
        OperationalStatus=$operationalStatus
        Comparable=([string]$DiscoveryBatch.Status -ceq 'COMPLETE' -and [string]$Result.EvaluationStatus -ceq 'COMPLETE')
        NonComparableReasons=@($reasons | Sort-Object -CaseSensitive -Unique)
    }
}

function New-LocationHistoryProjectionArtifact {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)]$Projection,
        [string[]]$OrderInsensitivePaths=@()
    )

    $json=ConvertTo-HistoryCanonicalJson -Value $Projection -OrderInsensitivePaths $OrderInsensitivePaths
    $hash=Get-HistorySha256 -Text $json
    $path=Get-HistoryArtifactPath -Store $Store -ContentHash $hash -Extension 'json'
    $reference=New-HistoryArtifactReference -Kind $Kind -ContentHash $hash -RelativePath (Get-HistoryRelativePath -Store $Store -FullPath $path)
    return [pscustomobject][ordered]@{
        Reference=$reference
        PreparedArtifact=[pscustomobject][ordered]@{
            ContentHash=$hash
            Extension='json'
            Kind=$Kind
            Text=$json
        }
    }
}

function New-LocationHistoryObservationPackage {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$BusinessId,
        [Parameter(Mandatory)][string]$ObservedAt,
        [Parameter(Mandatory)][string]$RepositoryRevision,
        [Parameter(Mandatory)]$Business,
        [Parameter(Mandatory)]$DiscoveryBatch,
        [Parameter(Mandatory)]$Result,
        [AllowNull()]$ExecutionConfiguration=$null
    )

    Assert-HistoryToken -Value $RunId -Name 'run id'
    Assert-HistoryBusinessId -Value $BusinessId
    Assert-HistoryTimestamp -Value $ObservedAt -Name 'ObservedAt'
    Assert-NormalizedBusiness $Business
    Assert-PoiDiscoveryBatch $DiscoveryBatch
    Assert-PoiMatchResult $Result
    if([int]$Business.SourceRowNumber -ne [int]$DiscoveryBatch.SourceRowNumber -or [int]$Business.SourceRowNumber -ne [int]$Result.SourceRowNumber) {
        throw 'Location history adapter inputs must preserve one SourceRowNumber'
    }

    $input=ConvertTo-LocationHistoryInputProjection -BusinessId $BusinessId -Business $Business
    $evidence=ConvertTo-LocationHistoryEvidenceProjection -DiscoveryBatch $DiscoveryBatch
    $semantic=ConvertTo-LocationHistorySemanticProjection -DiscoveryBatch $DiscoveryBatch -Result $Result
    $execution=ConvertTo-LocationHistoryExecutionProjection -RepositoryRevision $RepositoryRevision -ExecutionConfiguration $ExecutionConfiguration
    $fingerprints=New-HistoryFingerprintSet -InputProjection $input -EvidenceProjection $evidence -SemanticProjection $semantic -ExecutionProjection $execution -SchemaVersion $script:FingerprintSchemaVersion -EvidenceOrderInsensitivePaths $script:LocationHistoryEvidenceOrderInsensitivePaths -SemanticOrderInsensitivePaths $script:LocationHistorySemanticOrderInsensitivePaths
    $assessment=Get-LocationHistoryOperationalAssessment -DiscoveryBatch $DiscoveryBatch -Result $Result

    $evidenceArtifact=New-LocationHistoryProjectionArtifact -Store $Store -Kind 'LOCATION_EVIDENCE_PROJECTION' -Projection $evidence -OrderInsensitivePaths $script:LocationHistoryEvidenceOrderInsensitivePaths
    $semanticArtifact=New-LocationHistoryProjectionArtifact -Store $Store -Kind 'LOCATION_SEMANTIC_PROJECTION' -Projection $semantic -OrderInsensitivePaths $script:LocationHistorySemanticOrderInsensitivePaths
    $identityMaterial=$RunId + '|' + $BusinessId + '|LOCATION|' + $fingerprints.InputFingerprint + '|' + $fingerprints.EvidenceFingerprint + '|' + $fingerprints.SemanticFingerprint + '|' + $fingerprints.ExecutionFingerprint
    $observationId='obs-' + (Get-HistorySha256 -Text $identityMaterial).Substring(0,32)
    $observation=New-HistoryObservation -ObservationId $observationId -RunId $RunId -BusinessId $BusinessId -Domain 'LOCATION' -ObservedAt $ObservedAt -OperationalStatus $assessment.OperationalStatus -Comparable ([bool]$assessment.Comparable) -InputFingerprint $fingerprints.InputFingerprint -EvidenceFingerprint $fingerprints.EvidenceFingerprint -SemanticFingerprint $fingerprints.SemanticFingerprint -ExecutionFingerprint $fingerprints.ExecutionFingerprint -ArtifactReferences @($evidenceArtifact.Reference,$semanticArtifact.Reference) -SemanticResultReference ([string]$semanticArtifact.Reference.RelativePath) -NonComparableReasons @($assessment.NonComparableReasons)

    return [pscustomobject][ordered]@{
        Observation=$observation
        PreparedArtifacts=@($evidenceArtifact.PreparedArtifact,$semanticArtifact.PreparedArtifact)
        InputProjection=$input
        EvidenceProjection=$evidence
        SemanticProjection=$semantic
        ExecutionProjection=$execution
    }
}

function Read-LocationHistorySemanticProjection {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)]$Observation
    )

    Assert-HistoryObservation $Observation
    if([string]$Observation.Domain -cne 'LOCATION') { throw 'Location semantic projection requires LOCATION observation' }
    $references=@($Observation.ArtifactReferences | Where-Object { [string]$_.Kind -ceq 'LOCATION_SEMANTIC_PROJECTION' })
    if($references.Count -ne 1) { throw 'Location observation requires exactly one semantic projection artifact' }
    $reference=$references[0]
    if([string]$Observation.SemanticResultReference -cne [string]$reference.RelativePath) {
        throw 'Location semantic result reference does not match semantic artifact'
    }

    Assert-HistoryArtifactReferenceExists -Store $Store -Reference $reference
    $path=Assert-HistoryStorePathWithinRoot -Store $Store -Path (Join-Path $Store.Root ([string]$reference.RelativePath))
    $projection=Read-HistoryJsonFile -Store $Store -Path $path -Kind 'location semantic projection'
    if($null -eq $projection) { throw 'Location semantic projection artifact is missing' }
    if([string]$projection.ProjectionType -cne 'LocationHistorySemantic' -or [int]$projection.ProjectionVersion -ne 1) {
        throw 'Unsupported location semantic projection'
    }
    $fingerprint=Get-HistoryFingerprint -Projection $projection -SchemaVersion $script:FingerprintSchemaVersion -OrderInsensitivePaths $script:LocationHistorySemanticOrderInsensitivePaths
    if($fingerprint -cne [string]$Observation.SemanticFingerprint) {
        throw 'Location semantic projection fingerprint mismatch'
    }
    return $projection
}

function Get-InternalStagedLocationHistorySemanticProjection {
    param(
        [Parameter(Mandatory)]$Current,
        [Parameter(Mandatory)]$StagedCurrentSemanticProjection
    )

    Assert-HistoryObservation $Current
    if([string]$Current.Domain -cne 'LOCATION') { throw 'Staged Location semantic projection requires LOCATION current observation' }
    if([string]$StagedCurrentSemanticProjection.ProjectionType -cne 'LocationHistorySemantic' -or [int]$StagedCurrentSemanticProjection.ProjectionVersion -ne 1) {
        throw 'Unsupported staged Location semantic projection'
    }
    $references=@($Current.ArtifactReferences | Where-Object { [string]$_.Kind -ceq 'LOCATION_SEMANTIC_PROJECTION' })
    if($references.Count -ne 1) { throw 'Current Location observation requires exactly one semantic projection artifact' }
    $reference=$references[0]
    if([string]$Current.SemanticResultReference -cne [string]$reference.RelativePath) {
        throw 'Current semantic result reference does not match semantic artifact'
    }
    $fingerprint=Get-HistoryFingerprint -Projection $StagedCurrentSemanticProjection -SchemaVersion $script:FingerprintSchemaVersion -OrderInsensitivePaths $script:LocationHistorySemanticOrderInsensitivePaths
    if($fingerprint -cne [string]$Current.SemanticFingerprint) {
        throw 'Staged Location semantic projection fingerprint mismatch'
    }
    $artifactHash=Get-HistorySha256 -Text (ConvertTo-HistoryCanonicalJson -Value $StagedCurrentSemanticProjection -OrderInsensitivePaths $script:LocationHistorySemanticOrderInsensitivePaths)
    if($artifactHash -cne [string]$reference.ContentHash) {
        throw 'Staged Location semantic projection artifact hash mismatch'
    }
    return $StagedCurrentSemanticProjection
}

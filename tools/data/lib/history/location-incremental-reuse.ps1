Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'location-history-adapter.ps1')
. (Join-Path $PSScriptRoot 'commit-history-run.ps1')

function New-LocationIncrementalExecutionConfiguration {
    param([Parameter(Mandatory)][bool]$RepositoryClean)

    return [pscustomobject][ordered]@{
        ProcessingMode='PHASE3_LOCATION_INCREMENTAL'
        IncrementalReuseVersion=1
        RepositoryClean=$RepositoryClean
    }
}

function New-LocationIncrementalCheckpoint {
    param(
        [Parameter(Mandatory)][string]$BusinessId,
        [Parameter(Mandatory)]$Business,
        [Parameter(Mandatory)]$DiscoveryBatch,
        [Parameter(Mandatory)][string]$RepositoryRevision,
        [Parameter(Mandatory)]$ExecutionConfiguration
    )

    $configurationFields=@($ExecutionConfiguration.PSObject.Properties.Name)
    if($configurationFields.Count -ne 3 -or
       -not ($configurationFields -ccontains 'ProcessingMode') -or
       -not ($configurationFields -ccontains 'IncrementalReuseVersion') -or
       -not ($configurationFields -ccontains 'RepositoryClean') -or
       [string]$ExecutionConfiguration.ProcessingMode -cne 'PHASE3_LOCATION_INCREMENTAL' -or
       [int]$ExecutionConfiguration.IncrementalReuseVersion -ne 1 -or
       $ExecutionConfiguration.RepositoryClean -isnot [bool]) {
        throw 'Checkpoint requires P3-6 Location incremental execution configuration'
    }
    if ([int]$Business.SourceRowNumber -ne [int]$DiscoveryBatch.SourceRowNumber) {
        throw 'Checkpoint business/discovery SourceRowNumber mismatch'
    }
    $input=ConvertTo-LocationHistoryInputProjection -BusinessId $BusinessId -Business $Business
    $evidence=ConvertTo-LocationHistoryEvidenceProjection -DiscoveryBatch $DiscoveryBatch
    $execution=ConvertTo-LocationHistoryExecutionProjection -RepositoryRevision $RepositoryRevision -ExecutionConfiguration $ExecutionConfiguration
    return [pscustomobject][ordered]@{
        ContractType='LocationIncrementalCheckpoint'
        ContractVersion=1
        BusinessId=$BusinessId
        DiscoveryStatus=[string]$DiscoveryBatch.Status
        InputProjection=$input
        EvidenceProjection=$evidence
        ExecutionProjection=$execution
        InputFingerprint=Get-HistoryFingerprint -Projection $input -SchemaVersion $script:FingerprintSchemaVersion
        EvidenceFingerprint=Get-HistoryFingerprint -Projection $evidence -SchemaVersion $script:FingerprintSchemaVersion -OrderInsensitivePaths $script:LocationHistoryEvidenceOrderInsensitivePaths
        ExecutionFingerprint=Get-HistoryFingerprint -Projection $execution -SchemaVersion $script:FingerprintSchemaVersion
    }
}

function Get-LocationIncrementalBaselineResolution {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)][string]$BusinessId
    )

    Assert-HistoryBusinessId -Value $BusinessId
    $entry=Get-HistoryLatestEntry -Store $Store -BusinessId $BusinessId -Domain 'LOCATION' -ComparableOnly
    if($null -eq $entry) {
        return [pscustomobject][ordered]@{
            ContractType='LocationBaselineResolution'; ContractVersion=1; Status='NONE'
            ExpectedBaselineObservationId=''; Observation=$null
            EvidenceProjection=$null; EvidenceReference=$null
            SemanticProjection=$null; SemanticReference=$null
        }
    }

    $expectedId=[string]$entry.LatestComparableObservationId
    $observation=Read-HistoryObservation -Store $Store -ObservationId $expectedId
    if($null -eq $observation) { throw 'Indexed comparable Location observation is missing' }
    if([string]$observation.ObservationId -cne $expectedId -or
       [string]$observation.BusinessId -cne $BusinessId -or
       [string]$observation.Domain -cne 'LOCATION') {
        throw 'Indexed comparable Location observation identity mismatch'
    }
    Assert-HistoryObservationIsCommitted -Store $Store -Observation $observation
    if([string]$observation.OperationalStatus -cne 'COMPLETE' -or -not [bool]$observation.Comparable) {
        throw 'Indexed Location baseline is not COMPLETE and comparable'
    }

    $result=[ordered]@{
        ContractType='LocationBaselineResolution'; ContractVersion=1; Status='ARTIFACT_INVALID'
        ExpectedBaselineObservationId=$expectedId; Observation=$observation
        EvidenceProjection=$null; EvidenceReference=$null
        SemanticProjection=$null; SemanticReference=$null
    }
    try {
        $evidenceRefs=@($observation.ArtifactReferences | Where-Object { [string]$_.Kind -ceq 'LOCATION_EVIDENCE_PROJECTION' })
        $semanticRefs=@($observation.ArtifactReferences | Where-Object { [string]$_.Kind -ceq 'LOCATION_SEMANTIC_PROJECTION' })
        if($evidenceRefs.Count -ne 1 -or $semanticRefs.Count -ne 1) {
            throw 'Location baseline requires one evidence and one semantic projection'
        }
        $evidenceRef=$evidenceRefs[0]
        $semanticRef=$semanticRefs[0]
        Assert-HistoryArtifactReferenceExists -Store $Store -Reference $evidenceRef
        $evidencePath=Assert-HistoryStorePathWithinRoot -Store $Store -Path (Join-Path $Store.Root ([string]$evidenceRef.RelativePath))
        $evidence=Read-HistoryJsonFile -Store $Store -Path $evidencePath -Kind 'location evidence projection'
        if($null -eq $evidence -or [string]$evidence.ProjectionType -cne 'LocationHistoryEvidence' -or [int]$evidence.ProjectionVersion -ne 1) {
            throw 'Unsupported Location evidence projection'
        }
        $evidenceFingerprint=Get-HistoryFingerprint -Projection $evidence -SchemaVersion $script:FingerprintSchemaVersion -OrderInsensitivePaths $script:LocationHistoryEvidenceOrderInsensitivePaths
        if($evidenceFingerprint -cne [string]$observation.EvidenceFingerprint) {
            throw 'Location evidence projection fingerprint mismatch'
        }
        $semantic=Read-LocationHistorySemanticProjection -Store $Store -Observation $observation
        $result.Status='VALID'
        $result.EvidenceProjection=$evidence
        $result.EvidenceReference=$evidenceRef
        $result.SemanticProjection=$semantic
        $result.SemanticReference=$semanticRef
    } catch {
        return [pscustomobject]$result
    }
    return [pscustomobject]$result
}

function Get-LocationIncrementalReuseDecision {
    param(
        [Parameter(Mandatory)]$BaselineResolution,
        [Parameter(Mandatory)]$Checkpoint,
        [Parameter(Mandatory)][bool]$RepositoryClean
    )

    if([string]$Checkpoint.ContractType -cne 'LocationIncrementalCheckpoint' -or [int]$Checkpoint.ContractVersion -ne 1) {
        throw 'Invalid Location incremental checkpoint'
    }
    if([string]$BaselineResolution.ContractType -cne 'LocationBaselineResolution' -or [int]$BaselineResolution.ContractVersion -ne 1 -or
       [string]$BaselineResolution.Status -cnotin @('NONE','VALID','ARTIFACT_INVALID')) {
        throw 'Invalid Location baseline resolution'
    }
    $observation=$BaselineResolution.Observation
    $inputMatch=($null -ne $observation -and [string]$Checkpoint.InputFingerprint -ceq [string]$observation.InputFingerprint)
    $evidenceMatch=($null -ne $observation -and [string]$Checkpoint.EvidenceFingerprint -ceq [string]$observation.EvidenceFingerprint)
    $executionMatch=($null -ne $observation -and [string]$Checkpoint.ExecutionFingerprint -ceq [string]$observation.ExecutionFingerprint)
    $clean=($RepositoryClean -and [bool]$Checkpoint.ExecutionProjection.Configuration.RepositoryClean)
    $reason=if([string]$BaselineResolution.Status -ceq 'ARTIFACT_INVALID') {
        'PRIOR_ARTIFACT_INVALID'
    } elseif([string]$BaselineResolution.Status -ceq 'NONE') {
        'NO_BASELINE'
    } elseif(-not $clean) {
        'DIRTY_REPOSITORY'
    } elseif([string]$Checkpoint.DiscoveryStatus -cne 'COMPLETE') {
        'CURRENT_DISCOVERY_NOT_COMPLETE'
    } elseif(-not $inputMatch) {
        'INPUT_CHANGED'
    } elseif(-not $executionMatch) {
        'EXECUTION_CHANGED'
    } elseif(-not $evidenceMatch) {
        'EVIDENCE_CHANGED'
    } else {
        'REUSE_ELIGIBLE'
    }
    return [pscustomobject][ordered]@{
        ContractType='LocationIncrementalReuseDecision'
        ContractVersion=1
        Capability='POST_DISCOVERY'
        ReuseApplied=($reason -ceq 'REUSE_ELIGIBLE')
        BaselineResolution=$BaselineResolution
        ExpectedBaselineObservationId=[string]$BaselineResolution.ExpectedBaselineObservationId
        RepositoryClean=[bool]$clean
        CurrentDiscoveryStatus=[string]$Checkpoint.DiscoveryStatus
        InputMatch=[bool]$inputMatch
        EvidenceMatch=[bool]$evidenceMatch
        ExecutionMatch=[bool]$executionMatch
        ReasonCodes=@($reason)
    }
}

function New-LocationIncrementalReusePackage {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$ObservedAt,
        [Parameter(Mandatory)]$Checkpoint,
        [Parameter(Mandatory)]$BaselineResolution,
        [Parameter(Mandatory)]$Decision
    )

    Assert-HistoryToken -Value $RunId -Name 'run id'
    Assert-HistoryTimestamp -Value $ObservedAt -Name 'ObservedAt'
    if([string]$BaselineResolution.Status -cne 'VALID' -or $null -eq $BaselineResolution.Observation -or
       [string]$Decision.Capability -cne 'POST_DISCOVERY' -or -not [bool]$Decision.ReuseApplied -or
       @($Decision.ReasonCodes).Count -ne 1 -or [string]$Decision.ReasonCodes[0] -cne 'REUSE_ELIGIBLE' -or
       -not [bool]$Decision.RepositoryClean -or [string]$Decision.CurrentDiscoveryStatus -cne 'COMPLETE' -or
       -not [bool]$Decision.InputMatch -or -not [bool]$Decision.EvidenceMatch -or -not [bool]$Decision.ExecutionMatch) {
        throw 'Location reuse package requires an eligible validated decision'
    }
    $previous=$BaselineResolution.Observation
    Assert-HistoryObservation $previous
    if([string]$previous.Domain -cne 'LOCATION' -or [string]$previous.OperationalStatus -cne 'COMPLETE' -or
       -not [bool]$previous.Comparable -or [string]$previous.BusinessId -cne [string]$Checkpoint.BusinessId -or
       [string]$previous.ObservationId -cne [string]$BaselineResolution.ExpectedBaselineObservationId -or
       [string]$Decision.ExpectedBaselineObservationId -cne [string]$previous.ObservationId -or
       [string]$Checkpoint.InputFingerprint -cne [string]$previous.InputFingerprint -or
       [string]$Checkpoint.EvidenceFingerprint -cne [string]$previous.EvidenceFingerprint -or
       [string]$Checkpoint.ExecutionFingerprint -cne [string]$previous.ExecutionFingerprint) {
        throw 'Location reuse package baseline/checkpoint mismatch'
    }
    $evidenceRef=$BaselineResolution.EvidenceReference
    $semanticRef=$BaselineResolution.SemanticReference
    Assert-HistoryArtifactReference $evidenceRef
    Assert-HistoryArtifactReference $semanticRef
    $observedEvidence=@($previous.ArtifactReferences | Where-Object { [string]$_.Kind -ceq 'LOCATION_EVIDENCE_PROJECTION' })
    $observedSemantic=@($previous.ArtifactReferences | Where-Object { [string]$_.Kind -ceq 'LOCATION_SEMANTIC_PROJECTION' })
    if($observedEvidence.Count -ne 1 -or $observedSemantic.Count -ne 1 -or
       [string]$evidenceRef.Kind -cne 'LOCATION_EVIDENCE_PROJECTION' -or
       [string]$semanticRef.Kind -cne 'LOCATION_SEMANTIC_PROJECTION' -or
       [string]$evidenceRef.ContentHash -cne [string]$observedEvidence[0].ContentHash -or
       [string]$evidenceRef.RelativePath -cne [string]$observedEvidence[0].RelativePath -or
       [string]$semanticRef.ContentHash -cne [string]$observedSemantic[0].ContentHash -or
       [string]$semanticRef.RelativePath -cne [string]$observedSemantic[0].RelativePath -or
       [string]$previous.SemanticResultReference -cne [string]$semanticRef.RelativePath) {
        throw 'Location reuse package projection reference mismatch'
    }

    $audit=[pscustomobject][ordered]@{
        ContractType='LocationReuseDecision'
        ContractVersion=1
        ProcessingMode='REUSED_IDENTICAL_DISCOVERY_EVIDENCE'
        Capability='POST_DISCOVERY'
        ReusedFromObservationId=[string]$previous.ObservationId
        InputMatch=$true
        EvidenceMatch=$true
        ExecutionMatch=$true
        RepositoryClean=$true
        PreviousComparable=$true
        ReuseApplied=$true
        ReasonCodes=@('REUSE_ELIGIBLE')
    }
    $auditArtifact=New-LocationHistoryProjectionArtifact -Store $Store -Kind 'LOCATION_REUSE_DECISION' -Projection $audit
    $identityMaterial=$RunId + '|' + [string]$Checkpoint.BusinessId + '|LOCATION|' + [string]$Checkpoint.InputFingerprint + '|' + [string]$Checkpoint.EvidenceFingerprint + '|' + [string]$previous.SemanticFingerprint + '|' + [string]$Checkpoint.ExecutionFingerprint
    $observationId='obs-' + (Get-HistorySha256 -Text $identityMaterial).Substring(0,32)
    $observation=New-HistoryObservation -ObservationId $observationId -RunId $RunId -BusinessId ([string]$Checkpoint.BusinessId) -Domain 'LOCATION' -ObservedAt $ObservedAt -OperationalStatus 'COMPLETE' -Comparable $true -InputFingerprint ([string]$Checkpoint.InputFingerprint) -EvidenceFingerprint ([string]$Checkpoint.EvidenceFingerprint) -SemanticFingerprint ([string]$previous.SemanticFingerprint) -ExecutionFingerprint ([string]$Checkpoint.ExecutionFingerprint) -ArtifactReferences @($evidenceRef,$semanticRef,$auditArtifact.Reference) -SemanticResultReference ([string]$semanticRef.RelativePath) -NonComparableReasons @()
    return [pscustomobject][ordered]@{
        Observation=$observation
        PreparedArtifacts=@($auditArtifact.PreparedArtifact)
        InputProjection=$Checkpoint.InputProjection
        EvidenceProjection=$Checkpoint.EvidenceProjection
        SemanticProjection=$BaselineResolution.SemanticProjection
        ExecutionProjection=$Checkpoint.ExecutionProjection
        ReuseDecisionArtifact=$audit
    }
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$historyRoot = $PSScriptRoot
$dataLibRoot = Split-Path -Parent $historyRoot

. (Join-Path $dataLibRoot 'benefit-verification-contracts.ps1')
. (Join-Path $dataLibRoot 'benefit-evidence-location-contracts.ps1')
. (Join-Path $historyRoot 'history-contracts.ps1')
. (Join-Path $historyRoot 'history-fingerprints.ps1')
. (Join-Path $historyRoot 'history-store.ps1')
. (Join-Path $historyRoot 'commit-history-run.ps1')
. (Join-Path $historyRoot 'benefit-history-adapter.ps1')

function Get-BenefitIncrementalCapability {
    param(
        [Parameter(Mandatory)]$Candidate,
        [Parameter(Mandatory)]$Document
    )

    Assert-BenefitSourceCandidate $Candidate
    Assert-BenefitSourceDocument $Document
    if ([int]$Candidate.SourceRowNumber -ne [int]$Document.SourceRowNumber -or
        [string]$Candidate.Url -cne [string]$Document.Url) {
        throw 'Incremental capability inputs must preserve one source candidate/document identity'
    }

    if ($Candidate.SourceKind -cne 'PUBLIC_OFFICIAL' -or $Document.FetchStatus -cne 'COMPLETE') {
        return 'NONE'
    }

    if ($Document.SourceFormat -in @('HTML', 'XLSX')) {
        return 'POST_FETCH'
    }

    return 'NONE'
}

function New-BenefitIncrementalPayloadCheckpoint {
    param([Parameter(Mandatory)]$Document)

    Assert-BenefitSourceDocument $Document
    if ($Document.FetchStatus -cne 'COMPLETE') { throw 'Payload checkpoint requires a successfully fetched source document' }

    $contentHash = if ($Document.SourceFormat -ceq 'XLSX') {
        if ($Document.Bytes -isnot [byte[]] -or $Document.Bytes.Length -eq 0) { throw 'XLSX payload checkpoint requires original Bytes' }
        Get-BenefitEvidenceByteHash -Bytes $Document.Bytes
    } else {
        Get-BenefitEvidenceTextHash -Text $Document.Text
    }

    return [pscustomobject][ordered]@{
        ContractType = 'BenefitIncrementalPayloadCheckpoint'
        ContractVersion = 1
        SourceUrl = [string]$Document.Url
        SourceFormat = [string]$Document.SourceFormat
        ContentHash = $contentHash
    }
}

function Test-BenefitIncrementalRepositoryClean {
    param([Parameter(Mandatory)][scriptblock]$RepositoryStateProvider)

    try {
        $state = & $RepositoryStateProvider
        return ($null -ne $state -and $state.PSObject.Properties.Name -contains 'IsClean' -and [bool]$state.IsClean)
    } catch {
        return $false
    }
}

function Read-BenefitIncrementalEvidenceProjection {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)]$Observation
    )

    Assert-HistoryObservation $Observation
    $references = @($Observation.ArtifactReferences | Where-Object { [string]$_.Kind -ceq 'BENEFIT_EVIDENCE_PROJECTION' })
    if ($references.Count -ne 1) { throw 'Benefit observation requires exactly one evidence projection artifact' }
    $reference = $references[0]
    Assert-HistoryArtifactReferenceExists -Store $Store -Reference $reference
    $path = Assert-HistoryStorePathWithinRoot -Store $Store -Path (Join-Path $Store.Root ([string]$reference.RelativePath))
    $projection = Read-HistoryJsonFile -Store $Store -Path $path -Kind 'benefit evidence projection'
    if ($null -eq $projection -or [string]$projection.ProjectionType -cne 'BenefitHistoryEvidence' -or [int]$projection.ProjectionVersion -ne 1) {
        throw 'Unsupported benefit evidence projection'
    }
    $fingerprint = Get-HistoryFingerprint -Projection $projection -SchemaVersion $script:FingerprintSchemaVersion -OrderInsensitivePaths @('Sources','Sources[].CandidateReferences')
    if ($fingerprint -cne [string]$Observation.EvidenceFingerprint) { throw 'Benefit evidence projection fingerprint mismatch' }
    return $projection
}

function Get-BenefitIncrementalBaseline {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)][string]$BusinessId
    )

    Assert-HistoryBusinessId -Value $BusinessId
    $entry = Get-HistoryLatestEntry -Store $Store -BusinessId $BusinessId -Domain BENEFIT -ComparableOnly
    if ($null -eq $entry) { return $null }

    $observation = Read-HistoryObservation -Store $Store -ObservationId ([string]$entry.LatestComparableObservationId)
    if ($null -eq $observation) { throw 'Indexed comparable benefit observation is missing' }
    Assert-HistoryObservationIsCommitted -Store $Store -Observation $observation
    if ([string]$observation.OperationalStatus -cne 'COMPLETE' -or -not [bool]$observation.Comparable) {
        throw 'Indexed baseline is not a complete comparable observation'
    }

    return [pscustomobject][ordered]@{
        Observation = $observation
        EvidenceProjection = Read-BenefitIncrementalEvidenceProjection -Store $Store -Observation $observation
        SemanticProjection = Read-BenefitHistorySemanticProjection -Store $Store -Observation $observation
    }
}

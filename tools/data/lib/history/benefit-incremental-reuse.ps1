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

function Get-BenefitIncrementalProjectionCheckpoint {
    param([Parameter(Mandatory)]$EvidenceProjection)

    if ([string]$EvidenceProjection.ProjectionType -cne 'BenefitHistoryEvidence' -or [int]$EvidenceProjection.ProjectionVersion -ne 1) {
        throw 'Unsupported benefit evidence projection'
    }
    $sources = @($EvidenceProjection.Sources)
    if ($sources.Count -ne 1) { throw 'Incremental reuse requires exactly one previous evidence source' }
    $source = $sources[0]
    if ([string]::IsNullOrWhiteSpace([string]$source.SourceUrl) -or
        [string]$source.SourceFormat -notin @('HTML','XLSX') -or
        [string]$source.ContentHash -cnotmatch '^[0-9a-f]{64}$') {
        throw 'Previous evidence projection has no supported payload checkpoint'
    }
    return [pscustomobject][ordered]@{
        ContractType = 'BenefitIncrementalPayloadCheckpoint'
        ContractVersion = 1
        SourceUrl = [string]$source.SourceUrl
        SourceFormat = [string]$source.SourceFormat
        ContentHash = [string]$source.ContentHash
    }
}

function Test-BenefitIncrementalPayloadCheckpointMatch {
    param(
        [Parameter(Mandatory)]$Previous,
        [Parameter(Mandatory)]$Current
    )
    return ([string]$Previous.SourceUrl -ceq [string]$Current.SourceUrl -and
        [string]$Previous.SourceFormat -ceq [string]$Current.SourceFormat -and
        [string]$Previous.ContentHash -ceq [string]$Current.ContentHash)
}

function New-BenefitIncrementalReuseDecision {
    param(
        [bool]$ReuseApplied,
        [string]$Capability,
        [AllowNull()]$Baseline = $null,
        [AllowNull()]$PreviousPayloadCheckpoint = $null,
        [AllowNull()]$CurrentPayloadCheckpoint = $null,
        [bool]$InputMatch = $false,
        [bool]$ExecutionMatch = $false,
        [bool]$PayloadMatch = $false,
        [bool]$RepositoryClean = $false,
        [string[]]$ReasonCodes = @()
    )
    return [pscustomobject][ordered]@{
        ReuseApplied = $ReuseApplied
        Capability = $Capability
        Baseline = $Baseline
        PreviousPayloadCheckpoint = $PreviousPayloadCheckpoint
        CurrentPayloadCheckpoint = $CurrentPayloadCheckpoint
        InputMatch = $InputMatch
        ExecutionMatch = $ExecutionMatch
        PayloadMatch = $PayloadMatch
        RepositoryClean = $RepositoryClean
        PreviousComparable = ($null -ne $Baseline -and [bool]$Baseline.Observation.Comparable)
        ReasonCodes = @($ReasonCodes)
    }
}

function Get-BenefitIncrementalReuseDecision {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)][string]$BusinessId,
        [Parameter(Mandatory)]$Candidate,
        [Parameter(Mandatory)]$Document,
        [Parameter(Mandatory)][string]$CurrentInputFingerprint,
        [Parameter(Mandatory)][string]$CurrentExecutionFingerprint,
        [Parameter(Mandatory)][scriptblock]$RepositoryStateProvider
    )

    Assert-HistoryBusinessId -Value $BusinessId
    Assert-HistoryHash -Value $CurrentInputFingerprint -Name 'current input fingerprint'
    Assert-HistoryHash -Value $CurrentExecutionFingerprint -Name 'current execution fingerprint'
    $capability = Get-BenefitIncrementalCapability -Candidate $Candidate -Document $Document
    if ($capability -cne 'POST_FETCH') {
        return New-BenefitIncrementalReuseDecision -ReuseApplied $false -Capability $capability -ReasonCodes @('CAPABILITY_NONE')
    }
    if (-not (Test-BenefitIncrementalRepositoryClean -RepositoryStateProvider $RepositoryStateProvider)) {
        return New-BenefitIncrementalReuseDecision -ReuseApplied $false -Capability $capability -ReasonCodes @('DIRTY_REPOSITORY')
    }

    try { $baseline = Get-BenefitIncrementalBaseline -Store $Store -BusinessId $BusinessId }
    catch { return New-BenefitIncrementalReuseDecision -ReuseApplied $false -Capability $capability -ReasonCodes @('PRIOR_ARTIFACT_INVALID') }
    if ($null -eq $baseline) {
        return New-BenefitIncrementalReuseDecision -ReuseApplied $false -Capability $capability -ReasonCodes @('NO_BASELINE')
    }
    if ([string]$baseline.Observation.OperationalStatus -cne 'COMPLETE') {
        return New-BenefitIncrementalReuseDecision -ReuseApplied $false -Capability $capability -Baseline $baseline -ReasonCodes @('PREVIOUS_NOT_COMPLETE')
    }
    if (-not [bool]$baseline.Observation.Comparable) {
        return New-BenefitIncrementalReuseDecision -ReuseApplied $false -Capability $capability -Baseline $baseline -ReasonCodes @('PREVIOUS_NOT_COMPARABLE')
    }
    $inputMatch = [string]$baseline.Observation.InputFingerprint -ceq $CurrentInputFingerprint
    if (-not $inputMatch) {
        return New-BenefitIncrementalReuseDecision -ReuseApplied $false -Capability $capability -Baseline $baseline -InputMatch $false -ReasonCodes @('INPUT_CHANGED')
    }
    $executionMatch = [string]$baseline.Observation.ExecutionFingerprint -ceq $CurrentExecutionFingerprint
    if (-not $executionMatch) {
        return New-BenefitIncrementalReuseDecision -ReuseApplied $false -Capability $capability -Baseline $baseline -InputMatch $true -ExecutionMatch $false -ReasonCodes @('EXECUTION_CHANGED')
    }
    try {
        $previousCheckpoint = Get-BenefitIncrementalProjectionCheckpoint -EvidenceProjection $baseline.EvidenceProjection
        $currentCheckpoint = New-BenefitIncrementalPayloadCheckpoint -Document $Document
    } catch {
        return New-BenefitIncrementalReuseDecision -ReuseApplied $false -Capability $capability -Baseline $baseline -InputMatch $true -ExecutionMatch $true -ReasonCodes @('PRIOR_ARTIFACT_INVALID')
    }
    $payloadMatch = Test-BenefitIncrementalPayloadCheckpointMatch -Previous $previousCheckpoint -Current $currentCheckpoint
    if (-not $payloadMatch) {
        return New-BenefitIncrementalReuseDecision -ReuseApplied $false -Capability $capability -Baseline $baseline -PreviousPayloadCheckpoint $previousCheckpoint -CurrentPayloadCheckpoint $currentCheckpoint -InputMatch $true -ExecutionMatch $true -PayloadMatch $false -RepositoryClean $true -ReasonCodes @('PAYLOAD_CHANGED')
    }
    return New-BenefitIncrementalReuseDecision -ReuseApplied $true -Capability $capability -Baseline $baseline -PreviousPayloadCheckpoint $previousCheckpoint -CurrentPayloadCheckpoint $currentCheckpoint -InputMatch $true -ExecutionMatch $true -PayloadMatch $true -RepositoryClean $true -ReasonCodes @('REUSE_ELIGIBLE')
}

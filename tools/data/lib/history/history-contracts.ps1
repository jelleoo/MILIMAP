Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:HistoryContractVersion = 1
$script:FingerprintSchemaVersion = 1
$script:ComparatorVersion = 1

function Assert-HistoryBusinessId {
    param([Parameter(Mandatory)][string]$Value)
    if ($Value -cnotmatch '^biz-[0-9a-f]{32}$') { throw "Invalid history businessId: $Value" }
}

function Assert-HistoryHash {
    param([Parameter(Mandatory)][string]$Value,[string]$Name='hash')
    if ($Value -cnotmatch '^[0-9a-f]{64}$') { throw "Invalid $Name" }
}

function Assert-HistoryToken {
    param([Parameter(Mandatory)][string]$Value,[string]$Name='token')
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -cnotmatch '^[A-Za-z0-9._:/-]+$') { throw "Invalid $Name" }
}

function Assert-HistoryTimestamp {
    param([Parameter(Mandatory)][string]$Value,[string]$Name='timestamp')
    $parsed = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse($Value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$parsed)) { throw "Invalid $Name" }
}

function Assert-HistoryArtifactReference {
    param([Parameter(Mandatory)]$Value)
    if ($null -eq $Value) { throw 'Artifact reference is required' }
    if ([string]$Value.ContractType -cne 'HistoryArtifactReference') { throw 'Invalid artifact reference ContractType' }
    if ([int]$Value.ContractVersion -ne 1) { throw 'Unsupported artifact reference version' }
    Assert-HistoryToken -Value ([string]$Value.Kind) -Name 'artifact kind'
    Assert-HistoryHash -Value ([string]$Value.ContentHash) -Name 'content hash'
    Assert-HistoryToken -Value ([string]$Value.RelativePath) -Name 'artifact relative path'
}

function New-HistoryArtifactReference {
    param(
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][string]$ContentHash,
        [Parameter(Mandatory)][string]$RelativePath
    )
    $result = [pscustomobject][ordered]@{
        ContractType='HistoryArtifactReference'
        ContractVersion=1
        Kind=$Kind
        ContentHash=$ContentHash
        RelativePath=$RelativePath
    }
    Assert-HistoryArtifactReference $result
    return $result
}

function Assert-HistoryObservation {
    param([Parameter(Mandatory)]$Value)
    if ([string]$Value.ContractType -cne 'HistoryObservation') { throw 'Invalid history observation ContractType' }
    if ([int]$Value.HistoryContractVersion -ne 1) { throw 'Unsupported history observation version' }
    Assert-HistoryToken -Value ([string]$Value.ObservationId) -Name 'observation id'
    Assert-HistoryToken -Value ([string]$Value.RunId) -Name 'run id'
    Assert-HistoryBusinessId -Value ([string]$Value.BusinessId)
    if ([string]$Value.Domain -cnotin @('LOCATION','BENEFIT')) { throw 'Invalid history domain' }
    Assert-HistoryTimestamp -Value ([string]$Value.ObservedAt) -Name 'ObservedAt'
    if ([string]$Value.OperationalStatus -cnotin @('COMPLETE','PARTIAL','FAILED')) { throw 'Invalid operational status' }
    foreach ($property in @('InputFingerprint','EvidenceFingerprint','SemanticFingerprint','ExecutionFingerprint')) {
        Assert-HistoryHash -Value ([string]$Value.$property) -Name $property
    }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($artifact in @($Value.ArtifactReferences)) {
        Assert-HistoryArtifactReference $artifact
        $key = ([string]$artifact.Kind) + '|' + ([string]$artifact.ContentHash) + '|' + ([string]$artifact.RelativePath)
        if (-not $seen.Add($key)) { throw 'Duplicate artifact reference' }
    }
    foreach ($reason in @($Value.NonComparableReasons)) {
        Assert-HistoryToken -Value ([string]$reason) -Name 'non-comparable reason'
    }
}

function New-HistoryObservation {
    param(
        [Parameter(Mandatory)][string]$ObservationId,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$BusinessId,
        [Parameter(Mandatory)][ValidateSet('LOCATION','BENEFIT')][string]$Domain,
        [Parameter(Mandatory)][string]$ObservedAt,
        [Parameter(Mandatory)][ValidateSet('COMPLETE','PARTIAL','FAILED')][string]$OperationalStatus,
        [Parameter(Mandatory)][bool]$Comparable,
        [Parameter(Mandatory)][string]$InputFingerprint,
        [Parameter(Mandatory)][string]$EvidenceFingerprint,
        [Parameter(Mandatory)][string]$SemanticFingerprint,
        [Parameter(Mandatory)][string]$ExecutionFingerprint,
        [object[]]$ArtifactReferences=@(),
        [string]$SemanticResultReference='',
        [string[]]$NonComparableReasons=@()
    )
    $result = [pscustomobject][ordered]@{
        ContractType='HistoryObservation'
        HistoryContractVersion=1
        ObservationId=$ObservationId
        RunId=$RunId
        BusinessId=$BusinessId
        Domain=$Domain
        ObservedAt=$ObservedAt
        OperationalStatus=$OperationalStatus
        Comparable=$Comparable
        NonComparableReasons=@($NonComparableReasons)
        InputFingerprint=$InputFingerprint
        EvidenceFingerprint=$EvidenceFingerprint
        SemanticFingerprint=$SemanticFingerprint
        ExecutionFingerprint=$ExecutionFingerprint
        ArtifactReferences=@($ArtifactReferences)
        SemanticResultReference=$SemanticResultReference
    }
    Assert-HistoryObservation $result
    return $result
}

function Assert-ObservationComparison {
    param([Parameter(Mandatory)]$Value)
    if ([string]$Value.ContractType -cne 'ObservationComparison') { throw 'Invalid observation comparison ContractType' }
    if ([int]$Value.HistoryContractVersion -ne 1 -or [int]$Value.ComparatorVersion -ne 1) { throw 'Unsupported comparison version' }
    Assert-HistoryToken -Value ([string]$Value.ComparisonId) -Name 'comparison id'
    Assert-HistoryToken -Value ([string]$Value.RunId) -Name 'run id'
    Assert-HistoryBusinessId -Value ([string]$Value.BusinessId)
    if ([string]$Value.Domain -cnotin @('LOCATION','BENEFIT')) { throw 'Invalid history domain' }
    Assert-HistoryToken -Value ([string]$Value.CurrentObservationId) -Name 'current observation id'
    if (-not [string]::IsNullOrWhiteSpace([string]$Value.PreviousObservationId)) {
        Assert-HistoryToken -Value ([string]$Value.PreviousObservationId) -Name 'previous observation id'
        if ([string]$Value.PreviousObservationId -ceq [string]$Value.CurrentObservationId) { throw 'Comparison cannot self-link' }
    }
    if ([string]$Value.ComparisonStatus -cnotin @('COMPLETE','UNAVAILABLE')) { throw 'Invalid comparison status' }
    foreach ($dimension in @($Value.DeltaDimensions)) {
        if ([string]$dimension -cnotin @('INPUT','EVIDENCE','SEMANTIC','EXECUTION')) { throw 'Invalid delta dimension' }
    }
    foreach ($candidate in @($Value.ChangeCandidates)) { Assert-HistoryToken -Value ([string]$candidate) -Name 'change candidate' }
    foreach ($reason in @($Value.ReasonCodes)) { Assert-HistoryToken -Value ([string]$reason) -Name 'reason code' }
}

function New-ObservationComparison {
    param(
        [Parameter(Mandatory)][string]$ComparisonId,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$BusinessId,
        [Parameter(Mandatory)][ValidateSet('LOCATION','BENEFIT')][string]$Domain,
        [string]$PreviousObservationId='',
        [Parameter(Mandatory)][string]$CurrentObservationId,
        [Parameter(Mandatory)][ValidateSet('COMPLETE','UNAVAILABLE')][string]$ComparisonStatus,
        [string[]]$DeltaDimensions=@(),
        [int]$ComparatorVersion=1,
        [string[]]$ChangeCandidates=@(),
        [string[]]$ReasonCodes=@()
    )
    $result = [pscustomobject][ordered]@{
        ContractType='ObservationComparison'
        HistoryContractVersion=1
        ComparisonId=$ComparisonId
        RunId=$RunId
        BusinessId=$BusinessId
        Domain=$Domain
        PreviousObservationId=$PreviousObservationId
        CurrentObservationId=$CurrentObservationId
        ComparisonStatus=$ComparisonStatus
        DeltaDimensions=@($DeltaDimensions)
        ComparatorVersion=$ComparatorVersion
        ChangeCandidates=@($ChangeCandidates)
        ReasonCodes=@($ReasonCodes)
    }
    Assert-ObservationComparison $result
    return $result
}

function Assert-HistoryRunManifest {
    param([Parameter(Mandatory)]$Value)
    if ([string]$Value.ContractType -cne 'HistoryRunManifest') { throw 'Invalid history run manifest ContractType' }
    Assert-HistoryToken -Value ([string]$Value.RunId) -Name 'run id'
    Assert-HistoryTimestamp -Value ([string]$Value.StartedAt) -Name 'StartedAt'
    if ([string]$Value.RunCommitStatus -cnotin @('PREPARED','COMMITTED','ABORTED')) { throw 'Invalid run commit status' }
    if ([string]$Value.ExecutionStatus -cnotin @('COMPLETE','PARTIAL','FAILED')) { throw 'Invalid execution status' }
    if ([string]$Value.RepositoryRevision -cnotmatch '^[0-9a-f]{40}$') { throw 'Invalid repository revision' }
    if ([int]$Value.HistoryContractVersion -ne 1 -or [int]$Value.FingerprintSchemaVersion -ne 1) { throw 'Unsupported run version' }
    if ([string]$Value.RunCommitStatus -ceq 'COMMITTED') {
        if ([string]::IsNullOrWhiteSpace([string]$Value.CompletedAt)) { throw 'Committed run requires CompletedAt' }
        Assert-HistoryTimestamp -Value ([string]$Value.CompletedAt) -Name 'CompletedAt'
    } elseif (-not [string]::IsNullOrWhiteSpace([string]$Value.CompletedAt)) {
        Assert-HistoryTimestamp -Value ([string]$Value.CompletedAt) -Name 'CompletedAt'
    }
    foreach ($property in @('RequestedBusinessIds','CompletedBusinessIds','FailedBusinessIds')) {
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($id in @($Value.$property)) {
            Assert-HistoryBusinessId -Value ([string]$id)
            if (-not $seen.Add([string]$id)) { throw "Duplicate businessId in $property" }
        }
    }
}

function New-HistoryRunManifest {
    param(
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$StartedAt,
        [string]$CompletedAt='',
        [Parameter(Mandatory)][string]$RepositoryRevision,
        [int]$HistoryContractVersion=1,
        [int]$FingerprintSchemaVersion=1,
        [string[]]$RequestedBusinessIds=@(),
        [string[]]$CompletedBusinessIds=@(),
        [string[]]$FailedBusinessIds=@(),
        [Parameter(Mandatory)][ValidateSet('COMPLETE','PARTIAL','FAILED')][string]$ExecutionStatus,
        [Parameter(Mandatory)][ValidateSet('PREPARED','COMMITTED','ABORTED')][string]$RunCommitStatus
    )
    $result = [pscustomobject][ordered]@{
        ContractType='HistoryRunManifest'
        RunId=$RunId
        StartedAt=$StartedAt
        CompletedAt=$CompletedAt
        RepositoryRevision=$RepositoryRevision
        HistoryContractVersion=$HistoryContractVersion
        FingerprintSchemaVersion=$FingerprintSchemaVersion
        RequestedBusinessIds=@($RequestedBusinessIds)
        CompletedBusinessIds=@($CompletedBusinessIds)
        FailedBusinessIds=@($FailedBusinessIds)
        ExecutionStatus=$ExecutionStatus
        RunCommitStatus=$RunCommitStatus
    }
    Assert-HistoryRunManifest $result
    return $result
}

function Assert-HistoryIndexEntry {
    param([Parameter(Mandatory)]$Value)
    if ([string]$Value.ContractType -cne 'HistoryIndexEntry') { throw 'Invalid history index ContractType' }
    if ([int]$Value.ContractVersion -ne 1) { throw 'Unsupported history index version' }
    Assert-HistoryBusinessId -Value ([string]$Value.BusinessId)
    if ([string]$Value.Domain -cnotin @('LOCATION','BENEFIT')) { throw 'Invalid history domain' }
    if (-not [string]::IsNullOrWhiteSpace([string]$Value.LatestObservationId)) { Assert-HistoryToken -Value ([string]$Value.LatestObservationId) -Name 'latest observation id' }
    if (-not [string]::IsNullOrWhiteSpace([string]$Value.LatestComparableObservationId)) { Assert-HistoryToken -Value ([string]$Value.LatestComparableObservationId) -Name 'latest comparable observation id' }
}

function New-HistoryIndexEntry {
    param(
        [Parameter(Mandatory)][string]$BusinessId,
        [Parameter(Mandatory)][ValidateSet('LOCATION','BENEFIT')][string]$Domain,
        [string]$LatestObservationId='',
        [string]$LatestComparableObservationId=''
    )
    $result = [pscustomobject][ordered]@{
        ContractType='HistoryIndexEntry'
        ContractVersion=1
        BusinessId=$BusinessId
        Domain=$Domain
        LatestObservationId=$LatestObservationId
        LatestComparableObservationId=$LatestComparableObservationId
    }
    Assert-HistoryIndexEntry $result
    return $result
}

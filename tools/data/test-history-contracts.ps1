$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/history/history-contracts.ps1')

function Assert-True { param([bool]$Condition,[string]$Message); if(-not $Condition){throw $Message} }
function Assert-Equal { param($Actual,$Expected,[string]$Message); if($Actual -ne $Expected){throw "$Message (expected: $Expected, actual: $Actual)"} }
function Assert-Throws { param([scriptblock]$Action,[string]$Message); $threw=$false; try{& $Action}catch{$threw=$true}; if(-not $threw){throw $Message} }

$artifact = New-HistoryArtifactReference -Kind 'RAW_SOURCE_PAYLOAD' -ContentHash ('a'*64) -RelativePath 'artifacts/sha256/aa/test.html'
Assert-HistoryArtifactReference $artifact
Assert-Equal $artifact.ContractVersion 1 'Artifact reference version is fixed at 1'
Assert-Throws { New-HistoryArtifactReference -Kind 'RAW_SOURCE_PAYLOAD' -ContentHash 'abc' -RelativePath 'x' } 'Short content hash must fail'

$observation = New-HistoryObservation -ObservationId 'obs-0000000000000001' -RunId 'run-0000000000000001' -BusinessId 'biz-0123456789abcdef0123456789abcdef' -Domain 'BENEFIT' -ObservedAt '2026-09-26T00:00:00Z' -OperationalStatus 'COMPLETE' -Comparable $true -InputFingerprint ('1'*64) -EvidenceFingerprint ('2'*64) -SemanticFingerprint ('3'*64) -ExecutionFingerprint ('4'*64) -ArtifactReferences @($artifact) -SemanticResultReference 'semantic/benefit/result-1.json'
Assert-HistoryObservation $observation
Assert-Equal $observation.HistoryContractVersion 1 'Observation contract version is fixed at 1'
Assert-Throws { New-HistoryObservation -ObservationId 'obs-x' -RunId 'run-x' -BusinessId 'biz-0123456789abcdef0123456789ABCDEF' -Domain 'BENEFIT' -ObservedAt '2026-09-26T00:00:00Z' -OperationalStatus 'COMPLETE' -Comparable $true -InputFingerprint ('1'*64) -EvidenceFingerprint ('2'*64) -SemanticFingerprint ('3'*64) -ExecutionFingerprint ('4'*64) } 'Uppercase business ID must fail'
Assert-Throws { New-HistoryObservation -ObservationId 'obs-x' -RunId 'run-x' -BusinessId 'biz-0123456789abcdef0123456789abcdef' -Domain 'UNKNOWN' -ObservedAt '2026-09-26T00:00:00Z' -OperationalStatus 'COMPLETE' -Comparable $true -InputFingerprint ('1'*64) -EvidenceFingerprint ('2'*64) -SemanticFingerprint ('3'*64) -ExecutionFingerprint ('4'*64) } 'Unknown domain must fail'
Assert-Throws { New-HistoryObservation -ObservationId 'obs-x' -RunId 'run-x' -BusinessId 'biz-0123456789abcdef0123456789abcdef' -Domain 'LOCATION' -ObservedAt '2026-09-26T00:00:00Z' -OperationalStatus 'BROKEN' -Comparable $false -InputFingerprint ('1'*64) -EvidenceFingerprint ('2'*64) -SemanticFingerprint ('3'*64) -ExecutionFingerprint ('4'*64) } 'Unknown operational status must fail'
Assert-Throws { New-HistoryObservation -ObservationId 'obs-x' -RunId 'run-x' -BusinessId 'biz-0123456789abcdef0123456789abcdef' -Domain 'LOCATION' -ObservedAt '2026-09-26T00:00:00Z' -OperationalStatus 'COMPLETE' -Comparable $true -InputFingerprint '' -EvidenceFingerprint ('2'*64) -SemanticFingerprint ('3'*64) -ExecutionFingerprint ('4'*64) } 'Blank fingerprint must fail'
Assert-Throws { New-HistoryObservation -ObservationId 'obs-x' -RunId 'run-x' -BusinessId 'biz-0123456789abcdef0123456789abcdef' -Domain 'LOCATION' -ObservedAt '2026-09-26T00:00:00Z' -OperationalStatus 'COMPLETE' -Comparable $true -InputFingerprint ('1'*64) -EvidenceFingerprint ('2'*64) -SemanticFingerprint ('3'*64) -ExecutionFingerprint ('4'*64) -ArtifactReferences @($artifact,$artifact) } 'Duplicate artifact references must fail'

$comparison = New-ObservationComparison -ComparisonId 'cmp-0000000000000001' -RunId 'run-0000000000000001' -BusinessId 'biz-0123456789abcdef0123456789abcdef' -Domain 'BENEFIT' -PreviousObservationId 'obs-previous' -CurrentObservationId 'obs-current' -ComparisonStatus 'COMPLETE' -DeltaDimensions @('EVIDENCE') -ComparatorVersion 1 -ChangeCandidates @('EVIDENCE_CHANGE_ONLY') -ReasonCodes @()
Assert-ObservationComparison $comparison
Assert-Throws { New-ObservationComparison -ComparisonId 'cmp-x' -RunId 'run-x' -BusinessId 'biz-0123456789abcdef0123456789abcdef' -Domain 'BENEFIT' -PreviousObservationId 'obs-same' -CurrentObservationId 'obs-same' -ComparisonStatus 'COMPLETE' -DeltaDimensions @() -ComparatorVersion 1 } 'Self-linked comparison must fail'
Assert-Throws { New-ObservationComparison -ComparisonId 'cmp-x' -RunId 'run-x' -BusinessId 'biz-0123456789abcdef0123456789abcdef' -Domain 'BENEFIT' -PreviousObservationId 'obs-a' -CurrentObservationId 'obs-b' -ComparisonStatus 'COMPLETE' -DeltaDimensions @('UNKNOWN') -ComparatorVersion 1 } 'Unknown delta dimension must fail'

$manifest = New-HistoryRunManifest -RunId 'run-0000000000000001' -StartedAt '2026-09-26T00:00:00Z' -CompletedAt '2026-09-26T00:01:00Z' -RepositoryRevision ('a'*40) -HistoryContractVersion 1 -FingerprintSchemaVersion 1 -RequestedBusinessIds @('biz-0123456789abcdef0123456789abcdef') -CompletedBusinessIds @('biz-0123456789abcdef0123456789abcdef') -FailedBusinessIds @() -ExecutionStatus 'COMPLETE' -RunCommitStatus 'COMMITTED'
Assert-HistoryRunManifest $manifest
Assert-Throws { New-HistoryRunManifest -RunId 'run-x' -StartedAt '2026-09-26T00:00:00Z' -CompletedAt '' -RepositoryRevision ('a'*40) -HistoryContractVersion 1 -FingerprintSchemaVersion 1 -RequestedBusinessIds @() -CompletedBusinessIds @() -FailedBusinessIds @() -ExecutionStatus 'COMPLETE' -RunCommitStatus 'COMMITTED' } 'Committed manifest requires CompletedAt'
Assert-Throws { New-HistoryRunManifest -RunId 'run-x' -StartedAt '2026-09-26T00:00:00Z' -CompletedAt '2026-09-26T00:01:00Z' -RepositoryRevision ('a'*40) -HistoryContractVersion 1 -FingerprintSchemaVersion 1 -RequestedBusinessIds @() -CompletedBusinessIds @() -FailedBusinessIds @() -ExecutionStatus 'COMPLETE' -RunCommitStatus 'UNKNOWN' } 'Unknown commit status must fail'

$index = New-HistoryIndexEntry -BusinessId 'biz-0123456789abcdef0123456789abcdef' -Domain 'BENEFIT' -LatestObservationId 'obs-current' -LatestComparableObservationId 'obs-current'
Assert-HistoryIndexEntry $index
Assert-Throws { New-HistoryIndexEntry -BusinessId 'bad' -Domain 'BENEFIT' -LatestObservationId 'obs-current' } 'Malformed business ID must fail in index'

Write-Host 'History contract tests passed.'

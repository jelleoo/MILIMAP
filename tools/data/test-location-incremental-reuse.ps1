$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/history/location-history-adapter.ps1')

function Assert-Equal { param($Actual,$Expected,[string]$Message); if($Actual -cne $Expected){throw "$Message (expected: $Expected, actual: $Actual)"} }
function Assert-True { param([bool]$Condition,[string]$Message); if(-not $Condition){throw $Message} }
function Assert-Throws { param([scriptblock]$Action,[string]$Message); try { [void](& $Action) } catch { return }; throw $Message }

function New-TestBusiness {
    return New-NormalizedBusiness -SourceRowNumber 2 -OriginalName '테스트 식당' -NormalizedName '테스트식당' -BaseName '테스트 식당' -BranchName '양주점' -OriginalRoadAddress '경기도 양주시 테스트로 10' -OriginalLotAddress '경기도 양주시 테스트동 10' -PreferredAddress '경기도 양주시 테스트로 10' -Province '경기도' -City '양주시' -District '' -Dong '테스트동' -RoadName '테스트로' -BuildingMain '10' -BuildingSub '2' -Floor '3' -Unit '301' -AddressParseStatus 'COMPLETE' -NormalizationWarnings @()
}
function New-TestBatch {
    param([object[]]$Candidates=@(),[object[]]$Attempts=@(),[string]$Status='COMPLETE')
    return New-PoiDiscoveryBatch -SourceRowNumber 2 -Status $Status -Candidates $Candidates -QueryAttempts $Attempts
}
function New-TestCandidate {
    param([string]$Key='naver-1',[string]$Phone='031-0000-0010',[object[]]$DiscoveredBy=@())
    return New-PoiCandidate -CandidateKey $Key -Provider 'NAVER_API_HUB_LOCAL' -OriginalName '테스트 식당 양주점' -NormalizedName '테스트식당양주점' -RoadAddress '경기도 양주시 테스트로 10' -LotAddress '경기도 양주시 테스트동 10' -Latitude 37.123456 -Longitude 127.123456 -Phone $Phone -Category '음식점' -ProviderLink 'https://map.example/1' -DiscoveredBy $DiscoveredBy
}
function New-TestDiscovery {
    param([int]$Order=1,[int]$Position=1)
    return New-PoiDiscoveryEvidence -StrategyCode 'NAME_FULL_ADDRESS' -Query '테스트 식당 경기도 양주시 테스트로 10' -QueryOrder $Order -ResultPosition $Position -ResultCount 2
}
function New-TestAttempt {
    param([int]$Order=1)
    return New-PoiQueryAttempt -StrategyCode 'NAME_FULL_ADDRESS' -Query '테스트 식당 경기도 양주시 테스트로 10' -QueryOrder $Order -Status 'SUCCESS' -ResultCount 1 -ErrorCode ''
}

$modulePath=Join-Path $PSScriptRoot 'lib/history/location-incremental-reuse.ps1'
if(Test-Path -LiteralPath $modulePath){ . $modulePath }

$businessId='biz-0123456789abcdef0123456789abcdef'
$business=New-TestBusiness
$discovery=New-TestDiscovery
$batch=New-TestBatch -Candidates @((New-TestCandidate -DiscoveredBy @($discovery))) -Attempts @((New-TestAttempt))
$config=New-LocationIncrementalExecutionConfiguration -RepositoryClean $true
Assert-Equal $config.ProcessingMode 'PHASE3_LOCATION_INCREMENTAL' 'Processing mode is fixed'
Assert-Equal $config.IncrementalReuseVersion 1 'Reuse version is fixed'
Assert-True $config.RepositoryClean 'Clean state is recorded'
Assert-Equal @($config.PSObject.Properties).Count 3 'Execution configuration has exactly three fields'
Assert-True (-not ($config.PSObject.Properties.Name -contains 'ReuseApplied')) 'Reuse decision is not execution configuration'
$dirtyConfig=New-LocationIncrementalExecutionConfiguration -RepositoryClean $false
Assert-True (-not $dirtyConfig.RepositoryClean) 'Dirty state is recorded'

$checkpoint=New-LocationIncrementalCheckpoint -BusinessId $businessId -Business $business -DiscoveryBatch $batch -RepositoryRevision ('a'*40) -ExecutionConfiguration $config
$expectedInput=ConvertTo-LocationHistoryInputProjection -BusinessId $businessId -Business $business
$expectedEvidence=ConvertTo-LocationHistoryEvidenceProjection -DiscoveryBatch $batch
$expectedExecution=ConvertTo-LocationHistoryExecutionProjection -RepositoryRevision ('a'*40) -ExecutionConfiguration $config
Assert-Equal $checkpoint.InputFingerprint (Get-HistoryFingerprint -Projection $expectedInput) 'Checkpoint reuses P3-5 input fingerprint'
Assert-Equal $checkpoint.EvidenceFingerprint (Get-HistoryFingerprint -Projection $expectedEvidence -OrderInsensitivePaths $script:LocationHistoryEvidenceOrderInsensitivePaths) 'Checkpoint reuses P3-5 evidence canonicalization'
Assert-Equal $checkpoint.ExecutionFingerprint (Get-HistoryFingerprint -Projection $expectedExecution) 'Checkpoint reuses P3-5 execution fingerprint'
Assert-Equal $checkpoint.InputProjection.ProjectionType 'LocationHistoryInput' 'Checkpoint retains input projection'
Assert-Equal $checkpoint.EvidenceProjection.ProjectionType 'LocationHistoryEvidence' 'Checkpoint retains evidence projection'
Assert-Equal $checkpoint.ExecutionProjection.ProjectionType 'LocationHistoryExecution' 'Checkpoint retains execution projection'
Assert-Equal $checkpoint.DiscoveryStatus 'COMPLETE' 'Checkpoint records operational discovery status'
$wrongConfiguration=[pscustomobject]@{ProcessingMode='OTHER';IncrementalReuseVersion=1;RepositoryClean=$true}
Assert-Throws { New-LocationIncrementalCheckpoint -BusinessId $businessId -Business $business -DiscoveryBatch $batch -RepositoryRevision ('a'*40) -ExecutionConfiguration $wrongConfiguration } 'Checkpoint rejects a non-P3-6 processing mode'

$reordered=New-TestBatch -Candidates @((New-TestCandidate -DiscoveredBy @((New-TestDiscovery -Position 2),(New-TestDiscovery -Position 1)))) -Attempts @((New-TestAttempt))
$reorderedCheckpoint=New-LocationIncrementalCheckpoint -BusinessId $businessId -Business $business -DiscoveryBatch $reordered -RepositoryRevision ('a'*40) -ExecutionConfiguration $config
Assert-Equal $reorderedCheckpoint.EvidenceFingerprint $checkpoint.EvidenceFingerprint 'Duplicate same-query membership and physical position do not change evidence'
$firstCandidate=New-TestCandidate -Key 'naver-a' -Phone '031-0000-0010' -DiscoveredBy @((New-TestDiscovery))
$secondCandidate=New-TestCandidate -Key 'naver-b' -Phone '031-0000-0020' -DiscoveredBy @((New-TestDiscovery))
$twoCandidates=New-TestBatch -Candidates @($firstCandidate,$secondCandidate) -Attempts @((New-TestAttempt))
$reverseCandidates=New-TestBatch -Candidates @($secondCandidate,$firstCandidate) -Attempts @((New-TestAttempt))
$twoCheckpoint=New-LocationIncrementalCheckpoint -BusinessId $businessId -Business $business -DiscoveryBatch $twoCandidates -RepositoryRevision ('a'*40) -ExecutionConfiguration $config
$reverseCheckpoint=New-LocationIncrementalCheckpoint -BusinessId $businessId -Business $business -DiscoveryBatch $reverseCandidates -RepositoryRevision ('a'*40) -ExecutionConfiguration $config
Assert-Equal $reverseCheckpoint.EvidenceFingerprint $twoCheckpoint.EvidenceFingerprint 'Candidate physical ordering does not change evidence'

function New-TestMatchResult {
    param([Parameter(Mandatory)]$Candidate)
    return New-PoiMatchResult -SourceRowNumber 2 -EvaluationStatus 'COMPLETE' -Classification 'GREEN' -SelectedCandidate $Candidate -RankedCandidateKeys @($Candidate.CandidateKey) -ReasonCodes @('SINGLE_STRONG_CANDIDATE','NAME_EXACT') -ConflictCodes @() -Evidence @((New-PoiMatchEvidence -EvidenceCode 'NAME_EXACT' -CandidateKey $Candidate.CandidateKey -CanonicalValue '테스트 식당' -CandidateValue '테스트 식당 양주점' -Matched $true)) -EvaluatedCandidateCount 1 -SurvivingCandidateCount 1 -ProductionAction 'NONE'
}
function Copy-TestObject { param($Value); return ($Value | ConvertTo-Json -Depth 40 | ConvertFrom-Json) }
function Write-TestObject { param([string]$Path,$Value); New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null; $Value | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $Path -Encoding utf8 }
function Publish-TestBaseline {
    param($Store,[string]$RunId='run-location-baseline',[string]$ObservationId='')
    $candidate=New-TestCandidate -DiscoveredBy @((New-TestDiscovery))
    $package=New-LocationHistoryObservationPackage -Store $Store -RunId $RunId -BusinessId $businessId -ObservedAt '2026-09-27T00:00:00Z' -RepositoryRevision ('a'*40) -Business $business -DiscoveryBatch $batch -Result (New-TestMatchResult -Candidate $candidate) -ExecutionConfiguration $config
    foreach($artifact in @($package.PreparedArtifacts)) {
        [void](Write-HistoryArtifact -Store $Store -ContentHash $artifact.ContentHash -Extension $artifact.Extension -Text $artifact.Text)
    }
    $observation=$package.Observation
    if($ObservationId){$observation.ObservationId=$ObservationId}
    Write-TestObject -Path (Get-HistoryObservationPath -Store $Store -ObservationId $observation.ObservationId) -Value $observation
    $manifest=New-HistoryRunManifest -RunId $RunId -StartedAt '2026-09-27T00:00:00Z' -CompletedAt '2026-09-27T00:01:00Z' -RepositoryRevision ('a'*40) -RequestedBusinessIds @($businessId) -CompletedBusinessIds @($businessId) -FailedBusinessIds @() -ExecutionStatus 'COMPLETE' -RunCommitStatus 'COMMITTED'
    Write-TestObject -Path (Get-HistoryRunManifestPath -Store $Store -RunId $RunId) -Value $manifest
    Write-HistoryIndexEntry -Store $Store -Entry (New-HistoryIndexEntry -BusinessId $businessId -Domain 'LOCATION' -LatestObservationId $observation.ObservationId -LatestComparableObservationId $observation.ObservationId)
    return $package
}

$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('milimap-location-incremental-' + [guid]::NewGuid().ToString('N'))
try {
    $store=New-HistoryStoreLayout -Root $testRoot
    $none=Get-LocationIncrementalBaselineResolution -Store $store -BusinessId $businessId
    Assert-Equal $none.Status 'NONE' 'Missing index has no comparable baseline'
    Assert-Equal $none.ExpectedBaselineObservationId '' 'Missing index has empty CAS expectation'

    $package=Publish-TestBaseline -Store $store
    $valid=Get-LocationIncrementalBaselineResolution -Store $store -BusinessId $businessId
    Assert-Equal $valid.Status 'VALID' 'Committed comparable baseline resolves'
    Assert-Equal $valid.ExpectedBaselineObservationId $package.Observation.ObservationId 'Baseline keeps comparable observation ID'
    Assert-Equal $valid.EvidenceProjection.ProjectionType 'LocationHistoryEvidence' 'Evidence is validated and read'
    Assert-Equal $valid.SemanticProjection.ProjectionType 'LocationHistorySemantic' 'Semantic is validated and read'
    Assert-Equal $valid.EvidenceReference.Kind 'LOCATION_EVIDENCE_PROJECTION' 'Evidence reference is retained'
    Assert-Equal $valid.SemanticReference.Kind 'LOCATION_SEMANTIC_PROJECTION' 'Semantic reference is retained'

    $indexPath=Get-HistoryIndexPath -Store $store -BusinessId $businessId -Domain 'LOCATION'
    $originalIndex=Get-Content -LiteralPath $indexPath -Raw -Encoding utf8
    $latest=New-HistoryIndexEntry -BusinessId $businessId -Domain 'LOCATION' -LatestObservationId 'obs-noncomparable' -LatestComparableObservationId $package.Observation.ObservationId
    Write-HistoryIndexEntry -Store $store -Entry $latest
    Assert-Equal (Get-LocationIncrementalBaselineResolution -Store $store -BusinessId $businessId).Observation.ObservationId $package.Observation.ObservationId 'Latest non-comparable never replaces latest comparable'
    Set-Content -LiteralPath $indexPath -Value $originalIndex -Encoding utf8

    $evidenceRef=@($package.Observation.ArtifactReferences | Where-Object Kind -eq 'LOCATION_EVIDENCE_PROJECTION')[0]
    $evidencePath=Join-Path $store.Root $evidenceRef.RelativePath
    $originalEvidence=Get-Content -LiteralPath $evidencePath -Raw -Encoding utf8
    Set-Content -LiteralPath $evidencePath -Value 'tampered' -Encoding utf8
    $invalid=Get-LocationIncrementalBaselineResolution -Store $store -BusinessId $businessId
    Assert-Equal $invalid.Status 'ARTIFACT_INVALID' 'Evidence hash corruption is recoverable artifact invalidity'
    Assert-Equal $invalid.ExpectedBaselineObservationId $package.Observation.ObservationId 'Artifact invalidity retains expected baseline'
    Set-Content -LiteralPath $evidencePath -Value $originalEvidence -Encoding utf8 -NoNewline

    $semanticRef=@($package.Observation.ArtifactReferences | Where-Object Kind -eq 'LOCATION_SEMANTIC_PROJECTION')[0]
    $semanticPath=Join-Path $store.Root $semanticRef.RelativePath
    $originalSemantic=Get-Content -LiteralPath $semanticPath -Raw -Encoding utf8
    Set-Content -LiteralPath $semanticPath -Value 'tampered' -Encoding utf8
    Assert-Equal (Get-LocationIncrementalBaselineResolution -Store $store -BusinessId $businessId).Status 'ARTIFACT_INVALID' 'Semantic hash corruption is recoverable artifact invalidity'
    Set-Content -LiteralPath $semanticPath -Value $originalSemantic -Encoding utf8 -NoNewline

    $observationPath=Get-HistoryObservationPath -Store $store -ObservationId $package.Observation.ObservationId
    $originalObservation=Get-Content -LiteralPath $observationPath -Raw -Encoding utf8
    $wrongFingerprint=Copy-TestObject $package.Observation
    $wrongFingerprint.EvidenceFingerprint='0'*64
    Write-TestObject -Path $observationPath -Value $wrongFingerprint
    Assert-Equal (Get-LocationIncrementalBaselineResolution -Store $store -BusinessId $businessId).Status 'ARTIFACT_INVALID' 'Evidence fingerprint mismatch is artifact invalidity'
    Set-Content -LiteralPath $observationPath -Value $originalObservation -Encoding utf8
    $wrongSemantic=Copy-TestObject $package.Observation
    $wrongSemantic.SemanticResultReference='artifacts/sha256/wrong.json'
    Write-TestObject -Path $observationPath -Value $wrongSemantic
    Assert-Equal (Get-LocationIncrementalBaselineResolution -Store $store -BusinessId $businessId).Status 'ARTIFACT_INVALID' 'Semantic reference mismatch is artifact invalidity'
    Set-Content -LiteralPath $observationPath -Value $originalObservation -Encoding utf8
    $wrongSemanticFingerprint=Copy-TestObject $package.Observation
    $wrongSemanticFingerprint.SemanticFingerprint='0'*64
    Write-TestObject -Path $observationPath -Value $wrongSemanticFingerprint
    Assert-Equal (Get-LocationIncrementalBaselineResolution -Store $store -BusinessId $businessId).Status 'ARTIFACT_INVALID' 'Semantic fingerprint mismatch is artifact invalidity'
    Set-Content -LiteralPath $observationPath -Value $originalObservation -Encoding utf8
    foreach($kind in @('LOCATION_EVIDENCE_PROJECTION','LOCATION_SEMANTIC_PROJECTION')) {
        $missing=Copy-TestObject $package.Observation
        $missingRef=@($missing.ArtifactReferences | Where-Object Kind -eq $kind)[0]
        $missingRef.ContentHash='f'*64
        $missingRef.RelativePath='artifacts/sha256/' + ('f'*64) + '.json'
        if($kind -ceq 'LOCATION_SEMANTIC_PROJECTION') {$missing.SemanticResultReference=$missingRef.RelativePath}
        Write-TestObject -Path $observationPath -Value $missing
        Assert-Equal (Get-LocationIncrementalBaselineResolution -Store $store -BusinessId $businessId).Status 'ARTIFACT_INVALID' "Missing $kind artifact is recoverable artifact invalidity"
        Set-Content -LiteralPath $observationPath -Value $originalObservation -Encoding utf8
    }
    foreach($kind in @('LOCATION_EVIDENCE_PROJECTION','LOCATION_SEMANTIC_PROJECTION')) {
        $projection=if($kind -ceq 'LOCATION_EVIDENCE_PROJECTION') { Copy-TestObject $package.EvidenceProjection } else { Copy-TestObject $package.SemanticProjection }
        foreach($mutation in @(@{ProjectionType='WrongLocationProjection'},@{ProjectionVersion=2})) {
            foreach($key in $mutation.Keys) {$projection.$key=$mutation[$key]}
            $altered=New-LocationHistoryProjectionArtifact -Store $store -Kind $kind -Projection $projection
            [void](Write-HistoryArtifact -Store $store -ContentHash $altered.PreparedArtifact.ContentHash -Extension 'json' -Text $altered.PreparedArtifact.Text)
            $observationCopy=Copy-TestObject $package.Observation
            $reference=@($observationCopy.ArtifactReferences | Where-Object Kind -eq $kind)[0]
            $reference.ContentHash=$altered.Reference.ContentHash
            $reference.RelativePath=$altered.Reference.RelativePath
            if($kind -ceq 'LOCATION_SEMANTIC_PROJECTION') {$observationCopy.SemanticResultReference=$reference.RelativePath}
            Write-TestObject -Path $observationPath -Value $observationCopy
            Assert-Equal (Get-LocationIncrementalBaselineResolution -Store $store -BusinessId $businessId).Status 'ARTIFACT_INVALID' "Wrong $kind projection type/version is artifact invalidity"
            Set-Content -LiteralPath $observationPath -Value $originalObservation -Encoding utf8
            $projection=if($kind -ceq 'LOCATION_EVIDENCE_PROJECTION') { Copy-TestObject $package.EvidenceProjection } else { Copy-TestObject $package.SemanticProjection }
        }
    }

    Set-Content -LiteralPath $indexPath -Value '{not-json' -Encoding utf8
    Assert-Throws { Get-LocationIncrementalBaselineResolution -Store $store -BusinessId $businessId } 'Malformed index throws'
    Set-Content -LiteralPath $indexPath -Value $originalIndex -Encoding utf8
    $wrongIndex=New-HistoryIndexEntry -BusinessId ('biz-' + ('f'*32)) -Domain 'LOCATION' -LatestComparableObservationId $package.Observation.ObservationId
    Write-TestObject -Path $indexPath -Value $wrongIndex
    Assert-Throws { Get-LocationIncrementalBaselineResolution -Store $store -BusinessId $businessId } 'Index identity mismatch throws'
    Set-Content -LiteralPath $indexPath -Value $originalIndex -Encoding utf8
    $missingIndex=New-HistoryIndexEntry -BusinessId $businessId -Domain 'LOCATION' -LatestComparableObservationId 'obs-missing'
    Write-TestObject -Path $indexPath -Value $missingIndex
    Assert-Throws { Get-LocationIncrementalBaselineResolution -Store $store -BusinessId $businessId } 'Indexed observation missing throws'
    Set-Content -LiteralPath $indexPath -Value $originalIndex -Encoding utf8
    $wrongIdentity=Copy-TestObject $package.Observation
    $wrongIdentity.BusinessId='biz-' + ('f'*32)
    Write-TestObject -Path $observationPath -Value $wrongIdentity
    Assert-Throws { Get-LocationIncrementalBaselineResolution -Store $store -BusinessId $businessId } 'Observation business identity mismatch throws'
    Set-Content -LiteralPath $observationPath -Value $originalObservation -Encoding utf8
    $manifestPath=Get-HistoryRunManifestPath -Store $store -RunId $package.Observation.RunId
    $manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8
    $uncommitted=$manifest | ConvertFrom-Json
    $uncommitted.RunCommitStatus='PREPARED'
    Write-TestObject -Path $manifestPath -Value $uncommitted
    Assert-Throws { Get-LocationIncrementalBaselineResolution -Store $store -BusinessId $businessId } 'Non-COMMITTED run throws'
    Set-Content -LiteralPath $manifestPath -Value $manifest -Encoding utf8
} finally {
    $safeRoot=[IO.Path]::GetFullPath($testRoot)
    if($safeRoot.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::Ordinal) -and (Test-Path -LiteralPath $safeRoot)) { Remove-Item -LiteralPath $safeRoot -Recurse -Force }
}

function Assert-Decision {
    param($Resolution,$Current,[bool]$Clean,[string]$Expected)
    $decision=Get-LocationIncrementalReuseDecision -BaselineResolution $Resolution -Checkpoint $Current -RepositoryClean $Clean
    Assert-Equal $decision.Capability 'POST_DISCOVERY' 'Only POST_DISCOVERY capability is used'
    Assert-Equal @($decision.ReasonCodes).Count 1 'Decision has one precedence reason'
    Assert-Equal $decision.ReasonCodes[0] $Expected 'First matching decision reason wins'
    Assert-Equal $decision.ReuseApplied ($Expected -ceq 'REUSE_ELIGIBLE') 'Only eligible decision applies reuse'
    return $decision
}
$invalidResolution=Copy-TestObject $valid
$invalidResolution.Status='ARTIFACT_INVALID'
[void](Assert-Decision -Resolution $invalidResolution -Current $checkpoint -Clean $false -Expected 'PRIOR_ARTIFACT_INVALID')
[void](Assert-Decision -Resolution $none -Current $checkpoint -Clean $false -Expected 'NO_BASELINE')
[void](Assert-Decision -Resolution $valid -Current $checkpoint -Clean $false -Expected 'DIRTY_REPOSITORY')
$partialCheckpoint=Copy-TestObject $checkpoint
$partialCheckpoint.DiscoveryStatus='PARTIAL'
[void](Assert-Decision -Resolution $valid -Current $partialCheckpoint -Clean $true -Expected 'CURRENT_DISCOVERY_NOT_COMPLETE')
$changedInput=Copy-TestObject $checkpoint
$changedInput.InputFingerprint='1'*64
$changedInput.ExecutionFingerprint='2'*64
$changedInput.EvidenceFingerprint='3'*64
[void](Assert-Decision -Resolution $valid -Current $changedInput -Clean $true -Expected 'INPUT_CHANGED')
$changedExecution=Copy-TestObject $checkpoint
$changedExecution.ExecutionFingerprint='2'*64
$changedExecution.EvidenceFingerprint='3'*64
[void](Assert-Decision -Resolution $valid -Current $changedExecution -Clean $true -Expected 'EXECUTION_CHANGED')
$changedEvidence=Copy-TestObject $checkpoint
$changedEvidence.EvidenceFingerprint='3'*64
[void](Assert-Decision -Resolution $valid -Current $changedEvidence -Clean $true -Expected 'EVIDENCE_CHANGED')
$oldP35Baseline=Copy-TestObject $valid
$oldP35Baseline.Observation.ExecutionFingerprint='4'*64
[void](Assert-Decision -Resolution $oldP35Baseline -Current $checkpoint -Clean $true -Expected 'EXECUTION_CHANGED')
$dirtyCheckpoint=New-LocationIncrementalCheckpoint -BusinessId $businessId -Business $business -DiscoveryBatch $batch -RepositoryRevision ('a'*40) -ExecutionConfiguration $dirtyConfig
$dirtyBaseline=Copy-TestObject $valid
$dirtyBaseline.Observation.ExecutionFingerprint=$dirtyCheckpoint.ExecutionFingerprint
[void](Assert-Decision -Resolution $dirtyBaseline -Current $dirtyCheckpoint -Clean $false -Expected 'DIRTY_REPOSITORY')
$eligible=Assert-Decision -Resolution $valid -Current $checkpoint -Clean $true -Expected 'REUSE_ELIGIBLE'
Assert-Equal $eligible.ExpectedBaselineObservationId $valid.ExpectedBaselineObservationId 'Decision retains CAS expectation'
Assert-True ($eligible.InputMatch -and $eligible.EvidenceMatch -and $eligible.ExecutionMatch) 'Eligible decision records all exact matches'

$packageRoot=Join-Path ([IO.Path]::GetTempPath()) ('milimap-location-reuse-' + [guid]::NewGuid().ToString('N'))
try {
    $reuseStore=New-HistoryStoreLayout -Root $packageRoot
    $first=Publish-TestBaseline -Store $reuseStore
    $firstBaseline=Get-LocationIncrementalBaselineResolution -Store $reuseStore -BusinessId $businessId
    $firstDecision=Get-LocationIncrementalReuseDecision -BaselineResolution $firstBaseline -Checkpoint $checkpoint -RepositoryClean $true
    $reuse=New-LocationIncrementalReusePackage -Store $reuseStore -RunId 'run-location-reuse-two' -ObservedAt '2026-09-27T00:10:00Z' -Checkpoint $checkpoint -BaselineResolution $firstBaseline -Decision $firstDecision
    Assert-Equal $reuse.Observation.RunId 'run-location-reuse-two' 'Reuse has current RunId'
    Assert-Equal $reuse.Observation.ObservedAt '2026-09-27T00:10:00Z' 'Reuse has current ObservedAt'
    Assert-True ($reuse.Observation.ObservationId -cne $first.Observation.ObservationId) 'Reuse gets a fresh ObservationId'
    Assert-Equal $reuse.Observation.InputFingerprint $checkpoint.InputFingerprint 'Reuse uses current input fingerprint'
    Assert-Equal $reuse.Observation.EvidenceFingerprint $checkpoint.EvidenceFingerprint 'Reuse uses current evidence fingerprint'
    Assert-Equal $reuse.Observation.ExecutionFingerprint $checkpoint.ExecutionFingerprint 'Reuse uses current execution fingerprint'
    Assert-Equal $reuse.Observation.SemanticFingerprint $first.Observation.SemanticFingerprint 'Reuse carries validated semantic fingerprint'
    Assert-Equal $reuse.Observation.SemanticResultReference $first.Observation.SemanticResultReference 'Reuse references prior semantic artifact'
    Assert-Equal @($reuse.Observation.ArtifactReferences).Count 3 'Reuse has exactly evidence, semantic, current audit references'
    foreach($kind in @('LOCATION_EVIDENCE_PROJECTION','LOCATION_SEMANTIC_PROJECTION','LOCATION_REUSE_DECISION')) {
        Assert-Equal @($reuse.Observation.ArtifactReferences | Where-Object Kind -eq $kind).Count 1 "Reuse has exactly one $kind reference"
    }
    Assert-Equal @($reuse.PreparedArtifacts).Count 1 'Reuse prepares only one audit artifact'
    Assert-Equal $reuse.PreparedArtifacts[0].Kind 'LOCATION_REUSE_DECISION' 'Only prepared artifact is current audit'
    Assert-Equal $reuse.ReuseDecisionArtifact.ContractType 'LocationReuseDecision' 'Audit contract type is fixed'
    Assert-Equal $reuse.ReuseDecisionArtifact.ContractVersion 1 'Audit version is fixed'
    Assert-Equal $reuse.ReuseDecisionArtifact.ProcessingMode 'REUSED_IDENTICAL_DISCOVERY_EVIDENCE' 'Audit processing mode is fixed'
    Assert-Equal $reuse.ReuseDecisionArtifact.Capability 'POST_DISCOVERY' 'Audit capability is fixed'
    Assert-Equal $reuse.ReuseDecisionArtifact.ReusedFromObservationId $first.Observation.ObservationId 'Audit links to trusted baseline'
    Assert-True ($reuse.ReuseDecisionArtifact.InputMatch -and $reuse.ReuseDecisionArtifact.EvidenceMatch -and $reuse.ReuseDecisionArtifact.ExecutionMatch -and $reuse.ReuseDecisionArtifact.RepositoryClean -and $reuse.ReuseDecisionArtifact.PreviousComparable -and $reuse.ReuseDecisionArtifact.ReuseApplied) 'Audit records all passing gates'
    Assert-Equal $reuse.ReuseDecisionArtifact.ReasonCodes[0] 'REUSE_ELIGIBLE' 'Audit records eligible reason'
    Assert-True (-not ($reuse.PSObject.Properties.Name -contains 'PoiMatchResult')) 'Reuse creates no synthetic PoiMatchResult'
    Assert-Throws { New-LocationIncrementalReusePackage -Store $reuseStore -RunId 'run-rejected' -ObservedAt '2026-09-27T00:11:00Z' -Checkpoint $checkpoint -BaselineResolution $firstBaseline -Decision (Get-LocationIncrementalReuseDecision -BaselineResolution $firstBaseline -Checkpoint $checkpoint -RepositoryClean $false) } 'Rejected decision cannot create reuse package'

    [void](Write-HistoryArtifact -Store $reuseStore -ContentHash $reuse.PreparedArtifacts[0].ContentHash -Extension 'json' -Text $reuse.PreparedArtifacts[0].Text)
    Write-TestObject -Path (Get-HistoryObservationPath -Store $reuseStore -ObservationId $reuse.Observation.ObservationId) -Value $reuse.Observation
    $reuseManifest=New-HistoryRunManifest -RunId $reuse.Observation.RunId -StartedAt $reuse.Observation.ObservedAt -CompletedAt '2026-09-27T00:11:00Z' -RepositoryRevision ('a'*40) -RequestedBusinessIds @($businessId) -CompletedBusinessIds @($businessId) -FailedBusinessIds @() -ExecutionStatus 'COMPLETE' -RunCommitStatus 'COMMITTED'
    Write-TestObject -Path (Get-HistoryRunManifestPath -Store $reuseStore -RunId $reuse.Observation.RunId) -Value $reuseManifest
    Write-HistoryIndexEntry -Store $reuseStore -Entry (New-HistoryIndexEntry -BusinessId $businessId -Domain 'LOCATION' -LatestObservationId $reuse.Observation.ObservationId -LatestComparableObservationId $reuse.Observation.ObservationId)
    $secondBaseline=Get-LocationIncrementalBaselineResolution -Store $reuseStore -BusinessId $businessId
    $secondDecision=Get-LocationIncrementalReuseDecision -BaselineResolution $secondBaseline -Checkpoint $checkpoint -RepositoryClean $true
    $reuseAgain=New-LocationIncrementalReusePackage -Store $reuseStore -RunId 'run-location-reuse-three' -ObservedAt '2026-09-27T00:20:00Z' -Checkpoint $checkpoint -BaselineResolution $secondBaseline -Decision $secondDecision
    Assert-Equal @($reuseAgain.Observation.ArtifactReferences).Count 3 'Third run does not accumulate old audit refs'
    Assert-True (@($reuseAgain.Observation.ArtifactReferences | Where-Object { $_.ContentHash -ceq $reuse.PreparedArtifacts[0].ContentHash }).Count -eq 0) 'Previous reuse audit is absent from next run'
    Assert-Equal @($reuseAgain.PreparedArtifacts).Count 1 'Third run still prepares only its own audit'
} finally {
    $safeRoot=[IO.Path]::GetFullPath($packageRoot)
    if($safeRoot.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::Ordinal) -and (Test-Path -LiteralPath $safeRoot)) { Remove-Item -LiteralPath $safeRoot -Recurse -Force }
}

Write-Host 'Location incremental Task 1 tests passed.'

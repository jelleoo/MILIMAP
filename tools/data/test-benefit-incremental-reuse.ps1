$ErrorActionPreference='Stop'

. (Join-Path $PSScriptRoot 'invoke-phase2-benefit-shadow-mode.ps1')
. (Join-Path $PSScriptRoot 'lib/history/benefit-history-adapter.ps1')
. (Join-Path $PSScriptRoot 'lib/history/benefit-incremental-reuse.ps1')
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-xlsx/test-support.ps1')

function Assert-Equal { param($Actual,$Expected,[string]$Message); if($Actual -cne $Expected){ throw "$Message (expected: $Expected, actual: $Actual)" } }
function Assert-True { param([bool]$Condition,[string]$Message); if(-not $Condition){ throw $Message } }
function Assert-NotEqual { param($Actual,$Expected,[string]$Message); if($Actual -ceq $Expected){ throw $Message } }

$htmlCandidate=New-BenefitSourceCandidate -SourceRowNumber 2 -Url 'https://city.example.go.kr/benefit' -SourceKind PUBLIC_OFFICIAL -SourceLabel 'fixture' -DiscoveryMethod TEST -ObservedAt '2026-09-26T00:00:00Z'
$htmlDocument=New-BenefitSourceDocument -SourceRowNumber 2 -Url $htmlCandidate.Url -SourceFormat HTML -FetchStatus COMPLETE -ContentType 'text/html' -Text '<html><body>10% 할인</body></html>' -ObservedAt '2026-09-26T00:00:00Z'
Assert-Equal (Get-BenefitIncrementalCapability -Candidate $htmlCandidate -Document $htmlDocument) 'POST_FETCH' 'Official HTML supports POST_FETCH reuse'

$xlsxDocument=New-BenefitSourceDocument -SourceRowNumber 2 -Url 'https://city.example.go.kr/benefit.xlsx' -SourceFormat XLSX -FetchStatus COMPLETE -ContentType 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' -Text '' -Bytes ([byte[]](1,2,3,4)) -ObservedAt '2026-09-26T00:00:00Z'
$xlsxCandidate=New-BenefitSourceCandidate -SourceRowNumber 2 -Url $xlsxDocument.Url -SourceKind PUBLIC_OFFICIAL -SourceLabel 'fixture' -DiscoveryMethod TEST -ObservedAt '2026-09-26T00:00:00Z'
Assert-Equal (Get-BenefitIncrementalCapability -Candidate $xlsxCandidate -Document $xlsxDocument) 'POST_FETCH' 'Official XLSX supports POST_FETCH reuse'

$mmaCandidate=New-BenefitSourceCandidate -SourceRowNumber 2 -Url 'https://www.mma.go.kr/about/udgg/list.do?mc=mma0003357' -SourceKind PUBLIC_OFFICIAL -SourceLabel 'MMA' -DiscoveryMethod EXISTING_CANONICAL_URL -ObservedAt '2026-09-26T00:00:00Z'
$mmaDocument=New-BenefitSourceDocument -SourceRowNumber 2 -Url $mmaCandidate.Url -SourceFormat JSONP -FetchStatus COMPLETE -ContentType 'application/javascript' -Text 'callback({});' -ObservedAt '2026-09-26T00:00:00Z'
Assert-Equal (Get-BenefitIncrementalCapability -Candidate $mmaCandidate -Document $mmaDocument) 'NONE' 'MMA JSONP remains outside P3-4 reuse'

$failedDocument=New-BenefitSourceDocument -SourceRowNumber 2 -Url $htmlCandidate.Url -SourceFormat HTML -FetchStatus FAILED -ContentType 'text/html' -Text '' -ObservedAt '2026-09-26T00:00:00Z' -ReasonCodes @('SOURCE_FETCH_FAILED')
Assert-Equal (Get-BenefitIncrementalCapability -Candidate $htmlCandidate -Document $failedDocument) 'NONE' 'Failed fetch cannot enter reuse capability'

$checkpoint1=New-BenefitIncrementalPayloadCheckpoint -Document $htmlDocument
$trustedHtmlSnapshot=New-BenefitSourceSnapshot -SourceUrl $htmlDocument.Url -SourceFormat HTML -Text $htmlDocument.Text -ObservedAt $htmlDocument.ObservedAt
$checkpointFromSnapshot=New-BenefitIncrementalPayloadCheckpoint -Document $htmlDocument -Snapshot $trustedHtmlSnapshot
Assert-Equal $checkpointFromSnapshot.ContentHash $trustedHtmlSnapshot.ContentHash 'Trusted snapshot checkpoint reuses the established content hash'
$htmlDocumentLater=New-BenefitSourceDocument -SourceRowNumber 2 -Url $htmlCandidate.Url -SourceFormat HTML -FetchStatus COMPLETE -ContentType 'text/html' -Text $htmlDocument.Text -ObservedAt '2026-09-27T00:00:00Z'
$checkpoint2=New-BenefitIncrementalPayloadCheckpoint -Document $htmlDocumentLater
Assert-Equal $checkpoint1.ContentHash $checkpoint2.ContentHash 'ObservedAt must not affect payload checkpoint'
Assert-Equal $checkpoint1.SourceUrl $checkpoint2.SourceUrl 'Checkpoint preserves stable source identity'
Assert-Equal $checkpoint1.SourceFormat $checkpoint2.SourceFormat 'Checkpoint preserves source format'

$htmlDocumentChanged=New-BenefitSourceDocument -SourceRowNumber 2 -Url $htmlCandidate.Url -SourceFormat HTML -FetchStatus COMPLETE -ContentType 'text/html' -Text '<html><body>20% 할인</body></html>' -ObservedAt '2026-09-27T00:00:00Z'
$checkpointChanged=New-BenefitIncrementalPayloadCheckpoint -Document $htmlDocumentChanged
Assert-NotEqual $checkpoint1.ContentHash $checkpointChanged.ContentHash 'Payload content change must change checkpoint'

$xlsxCheckpoint=New-BenefitIncrementalPayloadCheckpoint -Document $xlsxDocument
Assert-True ($xlsxCheckpoint.ContentHash -match '^[0-9a-f]{64}$') 'XLSX checkpoint uses stable payload hash'

Assert-True (Test-BenefitIncrementalRepositoryClean -RepositoryStateProvider { [pscustomobject]@{IsClean=$true} }) 'Injected clean repository state permits reuse'
Assert-True (-not (Test-BenefitIncrementalRepositoryClean -RepositoryStateProvider { [pscustomobject]@{IsClean=$false} })) 'Injected dirty repository state rejects reuse'
Assert-True (-not (Test-BenefitIncrementalRepositoryClean -RepositoryStateProvider { throw 'git unavailable' })) 'Repository-state failure is fail closed'

function New-IncrementalBaselineFixture {
    param([Parameter(Mandatory)]$Store)

    $business = New-NormalizedBusiness -SourceRowNumber 2 -OriginalName '테스트 식당' -NormalizedName '테스트식당' -BaseName '테스트 식당' -OriginalRoadAddress '경기도 양주시 테스트로 10' -PreferredAddress '경기도 양주시 테스트로 10' -Province '경기도' -City '양주시' -RoadName '테스트로' -BuildingMain '10' -AddressParseStatus COMPLETE
    $benefit = New-CanonicalBenefitRecord -SourceRowNumber 2 -BusinessName '테스트 식당' -BenefitDescription '10% 할인' -EligibleTarget '현역 장병' -UsageCondition '평일' -VerificationMethod '군인증' -ExistingSourceType '지자체 공식 자료' -ExistingSourceUrl $htmlDocument.Url -ExistingVerifiedOn '2026-09-26'
    $validated = New-ValidatedBenefitClaim -ClaimType BENEFIT_DESCRIPTION -Value '10% 할인' -ValidationStatus VALIDATED -EvidenceText '10% 할인' -EvidenceReference 'TABLE_ROW:1:CELL:2' -SourceUrl $htmlDocument.Url
    $claim = New-BenefitClaimVerification -ClaimType BENEFIT_DESCRIPTION -CanonicalValue '10% 할인' -EvidenceValue '10% 할인' -Result CONFIRMED -ValidatedClaim $validated -ReasonCodes @()
    $result = New-BenefitVerificationResult -SourceRowNumber 2 -BusinessIdentity $business -BenefitState ACTIVE -ReviewClass GREEN -ReasonCodes @() -ClaimResults @($claim) -Evidence @() -Warnings @() -ProductionAction NONE
    $diagnostic = [pscustomobject]@{ Url=$htmlDocument.Url; SourceFormat='HTML'; FetchStatus='COMPLETE'; ContentHash=(Get-BenefitEvidenceTextHash -Text $htmlDocument.Text); AdapterId='HTML_GENERIC'; AdapterVersion='1'; AdapterStatus='COMPLETE'; LocationOperationalStatus='COMPLETE'; LocationStatus='LOCATED'; CandidateReferences=@('TABLE_ROW:1'); OfficialityStatus='VERIFIED_OFFICIAL'; BusinessBindingStatus='STRONG'; ExtractionStatus='COMPLETE' }
    $runId='run-11111111111111111111111111111111'
    $package=New-BenefitHistoryObservationPackage -Store $Store -RunId $runId -BusinessId 'biz-0123456789abcdef0123456789abcdef' -ObservedAt '2026-09-26T00:00:00Z' -RepositoryRevision ('a'*40) -Benefit $benefit -BusinessIdentity $business -Result $result -EvidenceDiagnostics @($diagnostic) -OperationalStatus ([pscustomobject]@{DiscoveryStatus='COMPLETE';ExtractionStatus='COMPLETE'})
    foreach($artifact in @($package.PreparedArtifacts)){ [void](Write-HistoryArtifact -Store $Store -ContentHash $artifact.ContentHash -Extension $artifact.Extension -Text $artifact.Text) }
    $observationPath=Get-HistoryObservationPath -Store $Store -ObservationId $package.Observation.ObservationId
    $package.Observation | ConvertTo-Json -Depth 30 -Compress | Set-Content -LiteralPath $observationPath -Encoding utf8 -NoNewline
    $manifest=New-HistoryRunManifest -RunId $runId -StartedAt '2026-09-26T00:00:00Z' -CompletedAt '2026-09-26T00:01:00Z' -RepositoryRevision ('a'*40) -RequestedBusinessIds @($package.Observation.BusinessId) -CompletedBusinessIds @($package.Observation.BusinessId) -FailedBusinessIds @() -ExecutionStatus COMPLETE -RunCommitStatus COMMITTED
    $runRoot=Join-Path $Store.RunsRoot $runId; New-Item -ItemType Directory -Force -Path $runRoot | Out-Null
    $manifest | ConvertTo-Json -Depth 30 -Compress | Set-Content -LiteralPath (Join-Path $runRoot 'manifest.json') -Encoding utf8 -NoNewline
    Write-HistoryIndexEntry -Store $Store -Entry (New-HistoryIndexEntry -BusinessId $package.Observation.BusinessId -Domain BENEFIT -LatestObservationId $package.Observation.ObservationId -LatestComparableObservationId $package.Observation.ObservationId)
    return $package
}

$incrementalRoot=Join-Path ([IO.Path]::GetTempPath()) ('milimap-incremental-' + [Guid]::NewGuid().ToString('N'))
try {
    $incrementalStore=New-HistoryStoreLayout -Root $incrementalRoot
    $baselinePackage=New-IncrementalBaselineFixture -Store $incrementalStore
    $baseline=Get-BenefitIncrementalBaseline -Store $incrementalStore -BusinessId $baselinePackage.Observation.BusinessId
    Assert-Equal $baseline.Observation.ObservationId $baselinePackage.Observation.ObservationId 'Indexed comparable baseline must load the committed observation'
    Assert-Equal $baseline.EvidenceProjection.ProjectionType 'BenefitHistoryEvidence' 'Baseline must validate the persisted evidence projection'
    Assert-Equal $baseline.SemanticProjection.ProjectionType 'BenefitHistorySemantic' 'Baseline must validate the persisted semantic projection'

    $eligible=Get-BenefitIncrementalReuseDecision -Store $incrementalStore -BusinessId $baselinePackage.Observation.BusinessId -Candidate $htmlCandidate -Document $htmlDocument -CurrentInputFingerprint $baselinePackage.Observation.InputFingerprint -CurrentExecutionFingerprint $baselinePackage.Observation.ExecutionFingerprint -RepositoryStateProvider { [pscustomobject]@{IsClean=$true} }
    Assert-True $eligible.ReuseApplied 'Same complete official HTML payload and fingerprints must be eligible for reuse'
    Assert-True ($eligible.ReasonCodes -contains 'REUSE_ELIGIBLE') 'Eligible reuse records the deterministic reason code'
    Assert-True (-not (Get-BenefitIncrementalReuseDecision -Store $incrementalStore -BusinessId $baselinePackage.Observation.BusinessId -Candidate $htmlCandidate -Document $htmlDocument -CurrentInputFingerprint ('b'*64) -CurrentExecutionFingerprint $baselinePackage.Observation.ExecutionFingerprint -RepositoryStateProvider { [pscustomobject]@{IsClean=$true} }).ReuseApplied) 'Input change rejects reuse'
    Assert-True (-not (Get-BenefitIncrementalReuseDecision -Store $incrementalStore -BusinessId $baselinePackage.Observation.BusinessId -Candidate $htmlCandidate -Document $htmlDocumentChanged -CurrentInputFingerprint $baselinePackage.Observation.InputFingerprint -CurrentExecutionFingerprint $baselinePackage.Observation.ExecutionFingerprint -RepositoryStateProvider { [pscustomobject]@{IsClean=$true} }).ReuseApplied) 'Payload change rejects reuse'
    Assert-True (-not (Get-BenefitIncrementalReuseDecision -Store $incrementalStore -BusinessId $baselinePackage.Observation.BusinessId -Candidate $htmlCandidate -Document $htmlDocument -CurrentInputFingerprint $baselinePackage.Observation.InputFingerprint -CurrentExecutionFingerprint $baselinePackage.Observation.ExecutionFingerprint -RepositoryStateProvider { [pscustomobject]@{IsClean=$false} }).ReuseApplied) 'Dirty repository rejects reuse'
    Assert-True (-not (Get-BenefitIncrementalReuseDecision -Store $incrementalStore -BusinessId $baselinePackage.Observation.BusinessId -Candidate $mmaCandidate -Document $mmaDocument -CurrentInputFingerprint $baselinePackage.Observation.InputFingerprint -CurrentExecutionFingerprint $baselinePackage.Observation.ExecutionFingerprint -RepositoryStateProvider { [pscustomobject]@{IsClean=$true} }).ReuseApplied) 'MMA remains capability NONE'
    $reusePackage=New-BenefitIncrementalReusePackage -Store $incrementalStore -RunId 'run-22222222222222222222222222222222' -ObservedAt '2026-09-27T00:00:00Z' -Decision $eligible
    Assert-True ($reusePackage.Observation.ObservationId -ne $baselinePackage.Observation.ObservationId) 'Reuse creates a new observation identity'
    Assert-Equal $reusePackage.Observation.EvidenceFingerprint $baselinePackage.Observation.EvidenceFingerprint 'Reuse preserves the validated prior evidence fingerprint'
    Assert-Equal $reusePackage.Observation.SemanticFingerprint $baselinePackage.Observation.SemanticFingerprint 'Reuse preserves the validated prior semantic fingerprint'
    Assert-Equal @($reusePackage.Observation.ArtifactReferences | Where-Object Kind -eq 'BENEFIT_REUSE_DECISION').Count 1 'Reuse attaches one adapter-owned audit artifact'
    Assert-Equal $reusePackage.ReuseDecisionArtifact.Projection.ProcessingMode 'REUSED_IDENTICAL_EVIDENCE' 'Reuse audit records deterministic processing mode outside HistoryObservation'

    $orchestrationContext=New-BenefitSourceRunContext
    $orchestrationFetch=[pscustomobject]@{ Count=0 }
    $orchestrationHttp={ param($Uri) $orchestrationFetch.Count++; [pscustomobject]@{StatusCode=200;ContentType='text/html';Text=$htmlDocument.Text;Bytes=$null} }.GetNewClosure()
    $orchestrationBusiness=New-NormalizedBusiness -SourceRowNumber 2 -OriginalName '테스트 식당' -NormalizedName '테스트식당' -BaseName '테스트 식당' -OriginalRoadAddress '경기도 양주시 테스트로 10' -PreferredAddress '경기도 양주시 테스트로 10' -Province '경기도' -City '양주시' -RoadName '테스트로' -BuildingMain '10' -AddressParseStatus COMPLETE
    $orchestrationBenefit=New-CanonicalBenefitRecord -SourceRowNumber 2 -BusinessName '테스트 식당' -BenefitDescription '10% 할인' -EligibleTarget '현역 장병' -UsageCondition '평일' -VerificationMethod '군인증' -ExistingSourceType '지자체 공식 자료' -ExistingSourceUrl 'https://city.example.go.kr/benefit' -ExistingVerifiedOn '2026-09-26'
    $orchestrationResult=Invoke-BenefitIncrementalPostFetch -Store $incrementalStore -RunId 'run-33333333333333333333333333333333' -ObservedAt '2026-09-27T00:00:00Z' -RepositoryRevision ('a'*40) -BusinessId $baselinePackage.Observation.BusinessId -Benefit $orchestrationBenefit -BusinessIdentity $orchestrationBusiness -Candidate $htmlCandidate -RunContext $orchestrationContext -RequestInvoker $orchestrationHttp -RepositoryStateProvider { [pscustomobject]@{IsClean=$true} }
    Assert-Equal $orchestrationFetch.Count 1 'Identical HTML reuse still performs the current external fetch exactly once'
    Assert-True $orchestrationResult.ReuseDecision.ReuseApplied 'Identical indexed HTML baseline applies reuse'
    Assert-Equal $orchestrationResult.Metrics.AvoidedParseCount 1 'Reuse avoids downstream parse'
    Assert-Equal $orchestrationResult.Metrics.AvoidedExtractionCount 1 'Reuse avoids downstream extraction'
    Assert-Equal $orchestrationResult.Metrics.AvoidedEvaluationCount 1 'Reuse avoids downstream evaluation'
    Assert-Equal $orchestrationResult.Observation.EvidenceFingerprint $baselinePackage.Observation.EvidenceFingerprint 'Reuse retains the prior evidence fingerprint'
    Assert-Equal @($orchestrationResult.Observation.ArtifactReferences | Where-Object Kind -eq 'BENEFIT_REUSE_DECISION').Count 1 'Reuse persists its audit artifact'

    # Task 6 RED: establish a real scoped XLSX/P3-3 committed baseline, then
    # prove the generic second-run orchestrator reuses it without XLSX work.
    $xlsxRow = [pscustomobject]@{ 업소명='가마골 백숙'; 시도='경기도'; 시군구='양주시'; 소재지도로명주소='양주시 장흥면 북한산로 1028'; 소재지지번주소=''; 업소전화번호='031-861-4800'; 할인정보=''; 적용대상=''; 이용조건=''; 인증방법=''; 출처유형='지자체 공식 자료'; 출처URL='https://city.example.go.kr/incremental.xlsx'; 최근확인일='2026-09-26' }
    $xlsxBusiness = ConvertTo-NormalizedBusiness -Row $xlsxRow -SourceRowNumber 2
    $xlsxBenefit = ConvertTo-Phase2CanonicalBenefitRecord -Row $xlsxRow -SourceRowNumber 2
    $xlsxCandidate = New-BenefitSourceCandidate -SourceRowNumber 2 -Url $xlsxRow.출처URL -SourceKind PUBLIC_OFFICIAL -SourceLabel '지자체 공식 자료' -DiscoveryMethod TEST -ObservedAt '2026-09-26T00:00:00Z'
    [byte[]]$xlsxBytes = New-XlsxTestBytes
    $xlsxFirstFetch = [pscustomobject]@{ Count=0 }
    $xlsxFirstHttp = { param($Uri) $xlsxFirstFetch.Count++; [pscustomobject]@{ StatusCode=200; ContentType='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'; Text=''; Bytes=$xlsxBytes } }.GetNewClosure()
    $xlsxFirstContext = New-BenefitSourceRunContext
    $xlsxSourceRecord = Invoke-ScopedPhase2BenefitSourceCandidate -Candidate $xlsxCandidate -Business $xlsxBusiness -CanonicalPhone '031-861-4800' -RunContext $xlsxFirstContext -RequestInvoker $xlsxFirstHttp
    Assert-Equal $xlsxSourceRecord.LocationResult.Status LOCATED 'First XLSX run creates a located scoped evidence record'
    Assert-Equal $xlsxSourceRecord.Bound.BusinessBindingStatus STRONG 'First XLSX run binds the located record strongly'
    Assert-Equal $xlsxSourceRecord.Validation.Status COMPLETE 'First XLSX run validates its scoped evidence'
    $xlsxFinal = Get-Phase2BenefitEvaluation -Benefit $xlsxBenefit -SourceRecords @($xlsxSourceRecord) -DiscoveryStatus COMPLETE
    $xlsxReasons = [Collections.Generic.List[string]]::new()
    Add-Phase2UniqueReasonCodes -Target $xlsxReasons -ReasonCodes $xlsxFinal.Evaluation.ReasonCodes
    Add-Phase2UniqueReasonCodes -Target $xlsxReasons -ReasonCodes $xlsxSourceRecord.ReasonCodes
    $xlsxResult = New-BenefitVerificationResult -SourceRowNumber 2 -BusinessIdentity $xlsxBusiness -BenefitState $xlsxFinal.Evaluation.BenefitState -ReviewClass $xlsxFinal.Evaluation.ReviewClass -ReasonCodes @($xlsxReasons) -ClaimResults $xlsxFinal.ClaimResults -Evidence $xlsxFinal.Evaluation.Evidence -Warnings $xlsxFinal.Evaluation.Warnings -ProductionAction NONE
    $xlsxBusinessId = 'biz-11111111111111111111111111111111'
    $xlsxFirstPackage = New-BenefitHistoryObservationPackage -Store $incrementalStore -RunId 'run-44444444444444444444444444444444' -BusinessId $xlsxBusinessId -ObservedAt '2026-09-26T00:00:00Z' -RepositoryRevision ('a'*40) -Benefit $xlsxBenefit -BusinessIdentity $xlsxBusiness -CanonicalPhone '031-861-4800' -Result $xlsxResult -EvidenceDiagnostics @((ConvertTo-Phase2ScopedBenefitEvidenceDiagnostic -SourceRecord $xlsxSourceRecord)) -OperationalStatus $xlsxFinal.OperationalStatus
    $xlsxFirstManifest = New-HistoryRunManifest -RunId 'run-44444444444444444444444444444444' -StartedAt '2026-09-26T00:00:00Z' -RepositoryRevision ('a'*40) -RequestedBusinessIds @($xlsxBusinessId) -CompletedBusinessIds @($xlsxBusinessId) -FailedBusinessIds @() -ExecutionStatus COMPLETE -RunCommitStatus PREPARED
    $xlsxFirstPrepared = Prepare-HistoryRun -Store $incrementalStore -RunManifest $xlsxFirstManifest -Artifacts $xlsxFirstPackage.PreparedArtifacts -Observations @($xlsxFirstPackage.Observation) -Comparisons @()
    $xlsxFirstCommit = Commit-HistoryRun -Store $incrementalStore -PreparedRun $xlsxFirstPrepared -ExpectedBaselines @{ (($xlsxBusinessId + '|BENEFIT'))='' }
    Assert-Equal $xlsxFirstCommit.Code COMMITTED 'First XLSX observation commits as the comparable baseline'
    $xlsxCommittedBaseline = Get-BenefitIncrementalBaseline -Store $incrementalStore -BusinessId $xlsxBusinessId
    Assert-Equal $xlsxCommittedBaseline.Observation.ObservationId $xlsxFirstPackage.Observation.ObservationId 'First XLSX commit remains a readable comparable baseline'
    $xlsxPreviousCheckpoint = Get-BenefitIncrementalProjectionCheckpoint -EvidenceProjection $xlsxCommittedBaseline.EvidenceProjection
    Assert-Equal $xlsxPreviousCheckpoint.SourceFormat XLSX 'Committed XLSX evidence projection retains its source format checkpoint'

    $xlsxSecondFetch = [pscustomobject]@{ Count=0 }
    $xlsxSecondHttp = { param($Uri) $xlsxSecondFetch.Count++; [pscustomobject]@{ StatusCode=200; ContentType='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'; Text=''; Bytes=$xlsxBytes } }.GetNewClosure()
    $xlsxSecondContext = New-BenefitSourceRunContext
    $script:incrementalXlsxHashCount = 0
    $script:incrementalXlsxIndexCount = 0
    $script:incrementalExtractionCount = 0
    $script:incrementalEvaluationCount = 0
    $script:originalIncrementalXlsxHash = (Get-Item Function:Get-BenefitEvidenceByteHash).ScriptBlock
    $script:originalIncrementalXlsxIndex = (Get-Item Function:New-InternalBenefitXlsxValidationIndex).ScriptBlock
    $script:originalIncrementalExtraction = (Get-Item Function:Invoke-BenefitEvidenceExtraction).ScriptBlock
    $script:originalIncrementalEvaluation = (Get-Item Function:Get-Phase2BenefitEvaluation).ScriptBlock
    function Get-BenefitEvidenceByteHash { param([Parameter(Mandatory)][byte[]]$Bytes); $script:incrementalXlsxHashCount++; & $script:originalIncrementalXlsxHash -Bytes $Bytes }
    function New-InternalBenefitXlsxValidationIndex { param([Parameter(Mandatory)]$Snapshot); $script:incrementalXlsxIndexCount++; & $script:originalIncrementalXlsxIndex -Snapshot $Snapshot }
    function Invoke-BenefitEvidenceExtraction { param($Source,$Document,$EvidenceSlice,$XlsxValidationIndex); $script:incrementalExtractionCount++; & $script:originalIncrementalExtraction @PSBoundParameters }
    function Get-Phase2BenefitEvaluation { param($Benefit,$SourceRecords,$DiscoveryStatus); $script:incrementalEvaluationCount++; & $script:originalIncrementalEvaluation @PSBoundParameters }
    try {
        # The prefetch/checkpoint boundary owns the one required workbook hash.
        # The orchestration call below must use that cached document/snapshot.
        $xlsxSecondDocument = Get-BenefitRunSourceDocument -Context $xlsxSecondContext -Candidate $xlsxCandidate -RequestInvoker $xlsxSecondHttp
        $xlsxSecondSnapshot = Get-BenefitRunSourceSnapshot -Context $xlsxSecondContext -Document $xlsxSecondDocument
        $xlsxHashCountAtCheckpoint = $script:incrementalXlsxHashCount
        $xlsxSecondRun = Invoke-BenefitIncrementalPostFetch -Store $incrementalStore -RunId 'run-55555555555555555555555555555555' -ObservedAt '2026-09-27T00:00:00Z' -RepositoryRevision ('a'*40) -BusinessId $xlsxBusinessId -Benefit $xlsxBenefit -BusinessIdentity $xlsxBusiness -CanonicalPhone '031-861-4800' -Candidate $xlsxCandidate -RunContext $xlsxSecondContext -RequestInvoker $xlsxSecondHttp -RepositoryStateProvider { [pscustomobject]@{ IsClean=$true } }
    } finally {
        Set-Item Function:Get-BenefitEvidenceByteHash -Value $script:originalIncrementalXlsxHash
        Set-Item Function:New-InternalBenefitXlsxValidationIndex -Value $script:originalIncrementalXlsxIndex
        Set-Item Function:Invoke-BenefitEvidenceExtraction -Value $script:originalIncrementalExtraction
        Set-Item Function:Get-Phase2BenefitEvaluation -Value $script:originalIncrementalEvaluation
        Remove-Variable -Scope Script -Name originalIncrementalXlsxHash,originalIncrementalXlsxIndex,originalIncrementalExtraction,originalIncrementalEvaluation -ErrorAction SilentlyContinue
    }
    Assert-Equal $xlsxSecondFetch.Count 1 'Second XLSX run performs the current external fetch exactly once'
    Assert-Equal $xlsxSecondContext.Metrics.ExternalFetchCount 1 'Second XLSX run records one external fetch'
    Assert-Equal $xlsxSecondContext.Metrics.FetchCacheHits 1 'Second XLSX orchestration reuses its prefetched run-context payload'
    Assert-Equal $xlsxSecondRun.ReuseDecision.Baseline.Observation.ObservationId $xlsxFirstPackage.Observation.ObservationId 'Second XLSX run hits the indexed comparable baseline'
    Assert-Equal $xlsxSecondRun.Metrics.ReuseEligible 1 'Second XLSX run records one eligible reuse decision'
    Assert-Equal $xlsxSecondRun.Metrics.ReuseApplied 1 'Second XLSX run records one applied reuse decision'
    Assert-Equal $xlsxSecondRun.Metrics.ReuseRejected 0 'Second XLSX run records no rejected reuse decision'
    Assert-Equal $script:incrementalXlsxHashCount $xlsxHashCountAtCheckpoint 'Second XLSX reuse adds no workbook SHA-256 after checkpoint'
    Assert-Equal $script:incrementalXlsxIndexCount 0 'Second XLSX reuse builds no ZIP/XML validation index'
    Assert-Equal $script:incrementalExtractionCount 0 'Second XLSX reuse invokes no extraction'
    Assert-Equal $script:incrementalEvaluationCount 0 'Second XLSX reuse invokes no evaluation'
    Assert-Equal $xlsxSecondRun.Metrics.AvoidedParseCount 1 'Second XLSX reuse reports avoided parse work'
    Assert-Equal $xlsxSecondRun.Metrics.AvoidedExtractionCount 1 'Second XLSX reuse reports avoided extraction work'
    Assert-Equal $xlsxSecondRun.Metrics.AvoidedEvaluationCount 1 'Second XLSX reuse reports avoided evaluation work'
    Assert-NotEqual $xlsxSecondRun.Observation.ObservationId $xlsxFirstPackage.Observation.ObservationId 'Second XLSX reuse creates a new observation identity'
    Assert-Equal $xlsxSecondRun.Observation.RunId 'run-55555555555555555555555555555555' 'Second XLSX reuse records its new run id'
    Assert-Equal $xlsxSecondRun.Observation.ObservedAt '2026-09-27T00:00:00Z' 'Second XLSX reuse records its new observed time'
    Assert-Equal $xlsxSecondRun.Observation.EvidenceFingerprint $xlsxFirstPackage.Observation.EvidenceFingerprint 'Second XLSX reuse retains previous evidence fingerprint'
    Assert-Equal $xlsxSecondRun.Observation.SemanticFingerprint $xlsxFirstPackage.Observation.SemanticFingerprint 'Second XLSX reuse retains previous semantic fingerprint'
    Assert-Equal $xlsxSecondRun.Observation.SemanticResultReference $xlsxFirstPackage.Observation.SemanticResultReference 'Second XLSX reuse retains previous semantic result artifact'
    Assert-Equal @($xlsxSecondRun.Observation.ArtifactReferences | Where-Object Kind -eq 'BENEFIT_REUSE_DECISION').Count 1 'Second XLSX reuse records its audit artifact'
    Assert-Equal $xlsxSecondRun.Commit.Code COMMITTED 'Second XLSX reuse commits successfully'

    # Task 7 RED: every rejected gate must recompute using the already fetched
    # run-context payload.  The counters prove real Phase 2 work occurs.
    function Invoke-Task7RejectedRecompute {
        param(
            [Parameter(Mandatory)][string]$RunId,
            [Parameter(Mandatory)][string]$BusinessId,
            [Parameter(Mandatory)]$Benefit,
            [Parameter(Mandatory)][byte[]]$Bytes,
            [Parameter(Mandatory)][string]$RepositoryRevision,
            [Parameter(Mandatory)][scriptblock]$RepositoryStateProvider
        )

        $fetch = [pscustomobject]@{ Count=0 }
        $http = { param($Uri) $fetch.Count++; [pscustomobject]@{ StatusCode=200; ContentType='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'; Text=''; Bytes=$Bytes } }.GetNewClosure()
        $context = New-BenefitSourceRunContext
        $script:task7ParserCount = 0
        $script:task7ExtractionCount = 0
        $script:task7EvaluationCount = 0
        $script:task7OriginalIndex = (Get-Item Function:New-InternalBenefitXlsxValidationIndex).ScriptBlock
        $script:task7OriginalExtraction = (Get-Item Function:Invoke-BenefitEvidenceExtraction).ScriptBlock
        $script:task7OriginalEvaluation = (Get-Item Function:Get-Phase2BenefitEvaluation).ScriptBlock
        function New-InternalBenefitXlsxValidationIndex { param([Parameter(Mandatory)]$Snapshot); $script:task7ParserCount++; & $script:task7OriginalIndex -Snapshot $Snapshot }
        function Invoke-BenefitEvidenceExtraction { param($Source,$Document,$EvidenceSlice,$XlsxValidationIndex); $script:task7ExtractionCount++; & $script:task7OriginalExtraction @PSBoundParameters }
        function Get-Phase2BenefitEvaluation { param($Benefit,$SourceRecords,$DiscoveryStatus); $script:task7EvaluationCount++; & $script:task7OriginalEvaluation @PSBoundParameters }
        try {
            $run = Invoke-BenefitIncrementalPostFetch -Store $incrementalStore -RunId $RunId -ObservedAt '2026-09-28T00:00:00Z' -RepositoryRevision $RepositoryRevision -BusinessId $BusinessId -Benefit $Benefit -BusinessIdentity $xlsxBusiness -CanonicalPhone '031-861-4800' -Candidate $xlsxCandidate -RunContext $context -RequestInvoker $http -RepositoryStateProvider $RepositoryStateProvider
            return [pscustomobject]@{ Run=$run; Fetch=$fetch; Context=$context; ParserCount=$script:task7ParserCount; ExtractionCount=$script:task7ExtractionCount; EvaluationCount=$script:task7EvaluationCount }
        } finally {
            Set-Item Function:New-InternalBenefitXlsxValidationIndex -Value $script:task7OriginalIndex
            Set-Item Function:Invoke-BenefitEvidenceExtraction -Value $script:task7OriginalExtraction
            Set-Item Function:Get-Phase2BenefitEvaluation -Value $script:task7OriginalEvaluation
            Remove-Variable -Scope Script -Name task7OriginalIndex,task7OriginalExtraction,task7OriginalEvaluation -ErrorAction SilentlyContinue
        }
    }

    function Assert-Task7RejectedRecompute {
        param([Parameter(Mandatory)]$Tracked,[Parameter(Mandatory)][string]$ReasonCode,[Parameter(Mandatory)][string]$Message)
        Assert-Equal $Tracked.Fetch.Count 1 ($Message + ': one current external fetch')
        Assert-Equal $Tracked.Context.Metrics.ExternalFetchCount 1 ($Message + ': run context records one external fetch')
        Assert-Equal $Tracked.Context.Metrics.FetchCacheHits 1 ($Message + ': scoped recompute reuses the current document')
        Assert-Equal $Tracked.Run.Metrics.ReuseApplied 0 ($Message + ': reuse is not applied')
        Assert-Equal $Tracked.Run.Metrics.ReuseRejected 1 ($Message + ': rejection is recorded')
        Assert-Equal $Tracked.Run.Metrics.AvoidedParseCount 0 ($Message + ': parse is not reported as avoided')
        Assert-Equal $Tracked.Run.Metrics.AvoidedExtractionCount 0 ($Message + ': extraction is not reported as avoided')
        Assert-Equal $Tracked.Run.Metrics.AvoidedEvaluationCount 0 ($Message + ': evaluation is not reported as avoided')
        Assert-True ($Tracked.Run.ReuseDecision.ReasonCodes -contains $ReasonCode) ($Message + ': deterministic rejection reason is preserved')
        Assert-True ($Tracked.ParserCount -gt 0) ($Message + ': XLSX parser/index actually runs')
        Assert-True ($Tracked.ExtractionCount -gt 0) ($Message + ': extraction actually runs')
        Assert-True ($Tracked.EvaluationCount -gt 0) ($Message + ': evaluation actually runs')
        Assert-Equal $Tracked.Run.Commit.Code COMMITTED ($Message + ': fresh recompute observation commits')
        Assert-Equal @($Tracked.Run.Observation.ArtifactReferences | Where-Object Kind -eq 'BENEFIT_REUSE_DECISION').Count 0 ($Message + ': rejected recompute has no reuse audit artifact')
    }

    [byte[]]$task7ChangedBytes = New-XlsxTestBytes -Benefit '다른 서비스'
    $task7PayloadChanged = Invoke-Task7RejectedRecompute -RunId 'run-66666666666666666666666666666666' -BusinessId $xlsxBusinessId -Benefit $xlsxBenefit -Bytes $task7ChangedBytes -RepositoryRevision ('a'*40) -RepositoryStateProvider { [pscustomobject]@{ IsClean=$true } }
    Assert-Task7RejectedRecompute -Tracked $task7PayloadChanged -ReasonCode PAYLOAD_CHANGED -Message 'Payload changed'
    Assert-NotEqual $task7PayloadChanged.Run.Observation.EvidenceFingerprint $xlsxSecondRun.Observation.EvidenceFingerprint 'Payload changed recompute does not reuse the prior evidence fingerprint'

    $task7InputChangedBenefit = New-CanonicalBenefitRecord -SourceRowNumber 2 -BusinessName '가마골 백숙' -BenefitDescription '입력 변경' -EligibleTarget '' -UsageCondition '' -VerificationMethod '' -ExistingSourceType '지자체 공식 자료' -ExistingSourceUrl $xlsxCandidate.Url -ExistingVerifiedOn '2026-09-26'
    $task7InputChanged = Invoke-Task7RejectedRecompute -RunId 'run-77777777777777777777777777777777' -BusinessId $xlsxBusinessId -Benefit $task7InputChangedBenefit -Bytes $task7ChangedBytes -RepositoryRevision ('a'*40) -RepositoryStateProvider { [pscustomobject]@{ IsClean=$true } }
    Assert-Task7RejectedRecompute -Tracked $task7InputChanged -ReasonCode INPUT_CHANGED -Message 'Input fingerprint changed'
    Assert-True (@($task7InputChanged.Run.Comparison.ChangeCandidates) -contains 'CANONICAL_INPUT_CHANGED') 'Input change is not misclassified as an external benefit change'
    Assert-True (@($task7InputChanged.Run.Comparison.ChangeCandidates) -notcontains 'BENEFIT_CHANGE_SUSPECTED') 'Input change never becomes a benefit change candidate'

    $task7ExecutionChanged = Invoke-Task7RejectedRecompute -RunId 'run-88888888888888888888888888888888' -BusinessId $xlsxBusinessId -Benefit $task7InputChangedBenefit -Bytes $task7ChangedBytes -RepositoryRevision ('b'*40) -RepositoryStateProvider { [pscustomobject]@{ IsClean=$true } }
    Assert-Task7RejectedRecompute -Tracked $task7ExecutionChanged -ReasonCode EXECUTION_CHANGED -Message 'Execution fingerprint changed'
    Assert-True (@($task7ExecutionChanged.Run.Comparison.ChangeCandidates) -contains 'PROCESSOR_OUTPUT_CHANGED') 'Execution change is not misclassified as an external benefit change'
    Assert-True (@($task7ExecutionChanged.Run.Comparison.ChangeCandidates) -notcontains 'BENEFIT_CHANGE_SUSPECTED') 'Execution change never becomes a benefit change candidate'

    $task7Dirty = Invoke-Task7RejectedRecompute -RunId 'run-99999999999999999999999999999999' -BusinessId $xlsxBusinessId -Benefit $task7InputChangedBenefit -Bytes $task7ChangedBytes -RepositoryRevision ('b'*40) -RepositoryStateProvider { [pscustomobject]@{ IsClean=$false } }
    Assert-Task7RejectedRecompute -Tracked $task7Dirty -ReasonCode DIRTY_REPOSITORY -Message 'Dirty repository'

    $task7NoBaselineId = 'biz-22222222222222222222222222222222'
    $task7NoBaseline = Invoke-Task7RejectedRecompute -RunId 'run-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' -BusinessId $task7NoBaselineId -Benefit $xlsxBenefit -Bytes $task7ChangedBytes -RepositoryRevision ('a'*40) -RepositoryStateProvider { [pscustomobject]@{ IsClean=$true } }
    Assert-Task7RejectedRecompute -Tracked $task7NoBaseline -ReasonCode NO_BASELINE -Message 'No usable comparable baseline'
    Assert-Equal $task7NoBaseline.Run.Comparison.ChangeCandidates[0] BASELINE_ESTABLISHED 'No baseline recompute does not reuse a prior semantic result'

    $invalidPriorEntry=Get-HistoryLatestEntry -Store $incrementalStore -BusinessId $xlsxBusinessId -Domain BENEFIT -ComparableOnly
    $invalidPriorObservation=Read-HistoryObservation -Store $incrementalStore -ObservationId $invalidPriorEntry.LatestComparableObservationId
    $invalidPriorEvidenceReference=@($invalidPriorObservation.ArtifactReferences | Where-Object Kind -eq 'BENEFIT_EVIDENCE_PROJECTION')[0]
    Set-Content -LiteralPath (Join-Path $incrementalStore.Root $invalidPriorEvidenceReference.RelativePath) -Value '{"ProjectionType":"BenefitHistoryEvidence","ProjectionVersion":1,"tampered":true}' -Encoding utf8 -NoNewline
    [byte[]]$task7FreshBytesAfterInvalidPrior = New-XlsxTestBytes -Benefit '새로운 서비스'
    $task7InvalidPrior = Invoke-Task7RejectedRecompute -RunId 'run-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' -BusinessId $xlsxBusinessId -Benefit $task7InputChangedBenefit -Bytes $task7FreshBytesAfterInvalidPrior -RepositoryRevision ('b'*40) -RepositoryStateProvider { [pscustomobject]@{ IsClean=$true } }
    Assert-Task7RejectedRecompute -Tracked $task7InvalidPrior -ReasonCode PRIOR_ARTIFACT_INVALID -Message 'Invalid prior artifact'
    Assert-True ($null -eq $task7InvalidPrior.Run.Comparison) 'Invalid prior artifact is never used as a semantic comparison baseline'

    $fetchFailureContext=New-BenefitSourceRunContext
    $fetchFailureCount=[pscustomobject]@{ Count=0 }
    $fetchFailureHttp={ param($Uri) $fetchFailureCount.Count++; [pscustomobject]@{ StatusCode=500; ContentType='text/plain'; Text='upstream failed'; Bytes=$null } }.GetNewClosure()
    $fetchFailureRun=Invoke-BenefitIncrementalPostFetch -Store $incrementalStore -RunId 'run-cccccccccccccccccccccccccccccccc' -ObservedAt '2026-09-28T00:00:00Z' -RepositoryRevision ('b'*40) -BusinessId $xlsxBusinessId -Benefit $task7InputChangedBenefit -BusinessIdentity $xlsxBusiness -CanonicalPhone '031-861-4800' -Candidate $xlsxCandidate -RunContext $fetchFailureContext -RequestInvoker $fetchFailureHttp -RepositoryStateProvider { [pscustomobject]@{ IsClean=$true } }
    Assert-Equal $fetchFailureCount.Count 1 'Fetch failure performs one current external request'
    Assert-Equal $fetchFailureRun.Metrics.ReuseApplied 0 'Fetch failure never applies reuse'
    Assert-Equal $fetchFailureRun.Metrics.AvoidedParseCount 0 'Fetch failure is not counted as avoided parse work'
    Assert-Equal $fetchFailureRun.Result.BenefitState NEEDS_VERIFICATION 'Fetch failure remains operationally unresolved'
    Assert-True (@($fetchFailureRun.Result.ClaimResults | Where-Object Result -in @('ENDED','UNCHANGED')).Count -eq 0) 'Fetch failure never becomes UNCHANGED or ENDED'
    Assert-True (@($fetchFailureRun.Comparison.ChangeCandidates) -notcontains 'BENEFIT_ABSENCE_SUSPECTED') 'Fetch failure never becomes benefit absence'
    Assert-True (@($fetchFailureRun.Comparison.ChangeCandidates) -notcontains 'ENDED') 'Fetch failure never becomes ended'

    # Task 8 RED: MMA remains its existing LIST/DETAIL JSONP family.  P3-4
    # may record a fresh history result but must never route it through the
    # HTML/XLSX shortcut.
    $mmaRow=[pscustomobject]@{업소명='(유)투투여행사';시도='서울특별시';시군구='테스트구';소재지도로명주소='서울특별시 테스트구 여행로 2789';소재지지번주소='';업소전화번호='02-2789-0000';할인정보='서비스 이용료 3% 할인';적용대상='군장병';이용조건='제휴 조건 적용';인증방법='군 신분증 제시';출처유형='병무청 공식 자료';출처URL='https://www.mma.go.kr/about/udgg/list.do?mc=mma0003357';최근확인일='2026-09-25'}
    $mmaBusiness=ConvertTo-NormalizedBusiness -Row $mmaRow -SourceRowNumber 2
    $mmaBenefit=ConvertTo-Phase2CanonicalBenefitRecord -Row $mmaRow -SourceRowNumber 2
    $mmaCandidate=New-BenefitSourceCandidate -SourceRowNumber 2 -Url $mmaRow.출처URL -SourceKind PUBLIC_OFFICIAL -SourceLabel '병무청 나라사랑 가게조회' -DiscoveryMethod EXISTING_CANONICAL_URL -ObservedAt '2026-09-25T00:00:00Z'
    $mmaCapabilityDocument=New-BenefitSourceDocument -SourceRowNumber 2 -Url $mmaCandidate.Url -SourceFormat JSONP -FetchStatus COMPLETE -ContentType 'application/json' -Text 'MmaBenefitList({});' -ObservedAt '2026-09-25T00:00:00Z'
    Assert-Equal (Get-BenefitIncrementalCapability -Candidate $mmaCandidate -Document $mmaCapabilityDocument) NONE 'MMA JSONP remains outside POST_FETCH reuse capability'
    $mmaFixtureRoot=Join-Path $PSScriptRoot 'testdata/benefit-evidence-mma'
    $mmaList=(Get-Content -Raw -LiteralPath (Join-Path $mmaFixtureRoot 'mma-list.fixture.jsonp')) -replace '^MmaTestList','MmaBenefitList'
    $mmaDetail=(Get-Content -Raw -LiteralPath (Join-Path $mmaFixtureRoot 'mma-detail-2789.fixture.jsonp')) -replace '^MmaTestDetail','MmaBenefitDetail'
    $mmaRequests=[Collections.Generic.List[string]]::new()
    $mmaHttp={param($Uri);[void]$mmaRequests.Add([string]$Uri);if($Uri -like '*mmanrsrListAjaxJsonCallNew.json*'){return [pscustomobject]@{StatusCode=200;ContentType='application/json';Text=$mmaList;Bytes=$null}}if($Uri -like '*udgigwan_cd=2789*'){return [pscustomobject]@{StatusCode=200;ContentType='application/json';Text=$mmaDetail;Bytes=$null}}throw "Unexpected MMA request: $Uri"}.GetNewClosure()
    $mmaRun=Invoke-BenefitIncrementalPostFetch -Store $incrementalStore -RunId 'run-dddddddddddddddddddddddddddddddd' -ObservedAt '2026-09-28T00:00:00Z' -RepositoryRevision ('b'*40) -BusinessId 'biz-33333333333333333333333333333333' -Benefit $mmaBenefit -BusinessIdentity $mmaBusiness -CanonicalPhone '02-2789-0000' -Candidate $mmaCandidate -RunContext (New-BenefitSourceRunContext) -RequestInvoker $mmaHttp -RepositoryStateProvider { [pscustomobject]@{IsClean=$true} }
    Assert-Equal $mmaRun.ReuseDecision.Capability NONE 'MMA orchestration preserves capability NONE'
    Assert-Equal $mmaRun.Metrics.ReuseApplied 0 'MMA never applies reuse'
    Assert-Equal $mmaRun.Metrics.AvoidedParseCount 0 'MMA never reports avoided HTML/XLSX parsing'
    Assert-Equal $mmaRun.Metrics.AvoidedExtractionCount 0 'MMA never reports avoided extraction'
    Assert-Equal $mmaRun.Metrics.AvoidedEvaluationCount 0 'MMA never reports avoided evaluation'
    Assert-Equal $mmaRequests.Count 2 'MMA uses existing list then selected detail requests without a shortcut'
    Assert-Equal $mmaRun.SourceRecord.Document.SourceFormat JSONP 'MMA returns the existing JSONP detail source record'
    Assert-Equal @($mmaRun.SourceRecord.Validation.Claims | Where-Object ClaimType -eq BENEFIT_DESCRIPTION).Count 1 'MMA preserves existing detail claim validation'
    Assert-Equal @($mmaRun.Observation.ArtifactReferences | Where-Object Kind -eq 'BENEFIT_REUSE_DECISION').Count 0 'MMA creates no reuse audit artifact'

    $unsupportedCandidate=New-BenefitSourceCandidate -SourceRowNumber 2 -Url 'https://city.example.go.kr/source.unknown' -SourceKind PUBLIC_OFFICIAL -SourceLabel 'unknown fixture' -DiscoveryMethod TEST -ObservedAt '2026-09-28T00:00:00Z'
    $unsupportedContext=New-BenefitSourceRunContext
    $unsupportedRun=Invoke-BenefitIncrementalPostFetch -Store $incrementalStore -RunId 'run-eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee' -ObservedAt '2026-09-28T00:00:00Z' -RepositoryRevision ('b'*40) -BusinessId 'biz-44444444444444444444444444444444' -Benefit $xlsxBenefit -BusinessIdentity $xlsxBusiness -CanonicalPhone '031-861-4800' -Candidate $unsupportedCandidate -RunContext $unsupportedContext -RequestInvoker { param($Uri) [pscustomobject]@{StatusCode=200;ContentType='application/unknown';Text='opaque';Bytes=$null} } -RepositoryStateProvider { [pscustomobject]@{IsClean=$true} }
    Assert-Equal $unsupportedRun.ReuseDecision.Capability NONE 'Unknown source format remains capability NONE'
    Assert-Equal $unsupportedRun.Metrics.ReuseApplied 0 'Unknown source format never applies reuse'
    Assert-Equal $unsupportedRun.Metrics.AvoidedParseCount 0 'Unknown source format never reports avoided parse work'
    Assert-Equal $unsupportedRun.Result.BenefitState NEEDS_VERIFICATION 'Unknown source format preserves existing safe unresolved result'
    Assert-Equal @($unsupportedRun.Observation.ArtifactReferences | Where-Object Kind -eq 'BENEFIT_REUSE_DECISION').Count 0 'Unknown source format creates no reuse audit artifact'
} finally { if(Test-Path -LiteralPath $incrementalRoot){ Remove-Item -LiteralPath $incrementalRoot -Recurse -Force } }

Write-Host 'Benefit incremental checkpoint tests passed.'

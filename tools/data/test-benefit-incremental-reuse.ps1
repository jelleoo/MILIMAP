$ErrorActionPreference='Stop'

. (Join-Path $PSScriptRoot 'invoke-phase2-benefit-shadow-mode.ps1')
. (Join-Path $PSScriptRoot 'lib/history/benefit-history-adapter.ps1')
. (Join-Path $PSScriptRoot 'lib/history/benefit-incremental-reuse.ps1')

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
} finally { if(Test-Path -LiteralPath $incrementalRoot){ Remove-Item -LiteralPath $incrementalRoot -Recurse -Force } }

Write-Host 'Benefit incremental checkpoint tests passed.'

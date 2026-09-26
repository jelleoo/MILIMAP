$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/benefit-verification-contracts.ps1')
. (Join-Path $PSScriptRoot 'lib/identity/normalize-business.ps1')
. (Join-Path $PSScriptRoot 'lib/history/history-contracts.ps1')
. (Join-Path $PSScriptRoot 'lib/history/history-fingerprints.ps1')
. (Join-Path $PSScriptRoot 'lib/history/history-store.ps1')
. (Join-Path $PSScriptRoot 'lib/history/compare-history-observations.ps1')
. (Join-Path $PSScriptRoot 'lib/history/benefit-history-adapter.ps1')

function Assert-True { param([bool]$Condition,[string]$Message); if(-not $Condition){ throw $Message } }
function Assert-Equal { param($Actual,$Expected,[string]$Message); if($Actual -cne $Expected){ throw "$Message (expected: $Expected, actual: $Actual)" } }
function Assert-NotEqual { param($Actual,$Expected,[string]$Message); if($Actual -ceq $Expected){ throw $Message } }

$businessId='biz-0123456789abcdef0123456789abcdef'
$runId='run-0123456789abcdef0123456789abcdef'
$revision='5b52df5a57ba7cbbaa829a6a2b153a22f3fb6804'

function New-TestBusiness {
    param([string]$Name='테스트 식당',[string]$Address='경기도 양주시 테스트로 10')
    New-NormalizedBusiness -SourceRowNumber 2 -OriginalName $Name -NormalizedName ($Name -replace '\s','') -BaseName $Name -OriginalRoadAddress $Address -PreferredAddress $Address -Province '경기도' -City '양주시' -RoadName '테스트로' -BuildingMain '10' -AddressParseStatus 'COMPLETE'
}
function New-TestBenefit {
    param([string]$Description='10% 할인',[string]$Target='현역 장병',[string]$SourceUrl='https://city.example.go.kr/benefit')
    New-CanonicalBenefitRecord -SourceRowNumber 2 -BusinessName '테스트 식당' -BenefitDescription $Description -EligibleTarget $Target -UsageCondition '평일' -VerificationMethod '군인증' -ExistingSourceType '지자체 공식 자료' -ExistingSourceUrl $SourceUrl -ExistingVerifiedOn '2026-09-01'
}
function New-TestClaim {
    param([string]$Type='BENEFIT_DESCRIPTION',[string]$Value='10% 할인',[string]$Result='CONFIRMED',[string[]]$Reasons=@())
    $validated=New-ValidatedBenefitClaim -ClaimType $Type -Value $Value -ValidationStatus 'VALIDATED' -EvidenceText $Value -EvidenceReference 'TABLE_ROW:1:CELL:2' -SourceUrl 'https://city.example.go.kr/benefit'
    New-BenefitClaimVerification -ClaimType $Type -CanonicalValue $Value -EvidenceValue $Value -Result $Result -ValidatedClaim $validated -ReasonCodes $Reasons
}
function New-TestResult {
    param([string]$State='ACTIVE',[string]$Review='GREEN',[object[]]$Claims=@((New-TestClaim)))
    New-BenefitVerificationResult -SourceRowNumber 2 -BusinessIdentity (New-TestBusiness) -BenefitState $State -ReviewClass $Review -ReasonCodes @() -ClaimResults $Claims -Evidence @() -Warnings @() -ProductionAction 'NONE'
}
function New-TestDiagnostic {
    param([string]$Hash=('a'*64),[string]$ObservedAt='2026-09-26T00:00:00Z',[string]$LocationStatus='LOCATED',[string]$LocationOperationalStatus='COMPLETE',[string]$ExtractionStatus='COMPLETE',[string]$FetchStatus='COMPLETE')
    [pscustomobject][ordered]@{
        Url='https://city.example.go.kr/benefit'
        SourceFormat='HTML'
        FetchStatus=$FetchStatus
        ContentHash=$Hash
        ObservedAt=$ObservedAt
        AdapterId='HTML_GENERIC'
        AdapterVersion=1
        LocationOperationalStatus=$LocationOperationalStatus
        LocationStatus=$LocationStatus
        CandidateReferences=@('TABLE_ROW:1')
        OfficialityStatus='VERIFIED_OFFICIAL'
        BusinessBindingStatus='STRONG'
        ExtractionStatus=$ExtractionStatus
        ValidatedClaims=@()
        ReasonCodes=@()
    }
}
function New-TestPackage {
    param(
        $Store,
        [string]$BusinessName='테스트 식당',
        [string]$BenefitDescription='10% 할인',
        [string]$EvidenceHash=('a'*64),
        [string]$ObservedAt='2026-09-26T00:00:00Z',
        [string]$DiagnosticObservedAt='2026-09-26T00:00:00Z',
        [string]$Revision=$revision,
        [string]$RunIdValue=$runId,
        [string]$DiscoveryStatus='COMPLETE',
        [string]$ExtractionStatus='COMPLETE',
        [string]$FetchStatus='COMPLETE',
        [string]$LocationOperationalStatus='COMPLETE',
        [string]$LocationStatus='LOCATED',
        [string]$State='ACTIVE',
        [string]$Review='GREEN',
        [AllowEmptyCollection()][object[]]$Claims=@((New-TestClaim))
    )
    $business=New-TestBusiness -Name $BusinessName
    $benefit=New-TestBenefit -Description $BenefitDescription
    $result=New-BenefitVerificationResult -SourceRowNumber 2 -BusinessIdentity $business -BenefitState $State -ReviewClass $Review -ReasonCodes @() -ClaimResults $Claims -Evidence @() -Warnings @() -ProductionAction 'NONE'
    $diagnostic=New-TestDiagnostic -Hash $EvidenceHash -ObservedAt $DiagnosticObservedAt -ExtractionStatus $ExtractionStatus -FetchStatus $FetchStatus -LocationOperationalStatus $LocationOperationalStatus -LocationStatus $LocationStatus
    $operational=[pscustomobject]@{DiscoveryStatus=$DiscoveryStatus;ExtractionStatus=$ExtractionStatus}
    New-BenefitHistoryObservationPackage -Store $Store -RunId $RunIdValue -BusinessId $businessId -ObservedAt $ObservedAt -RepositoryRevision $Revision -Benefit $benefit -BusinessIdentity $business -CanonicalPhone '031-000-0000' -Result $result -EvidenceDiagnostics @($diagnostic) -OperationalStatus $operational
}
function Publish-TestPackageArtifacts {
    param($Store,$Package)
    foreach($artifact in @($Package.PreparedArtifacts)){
        [void](Write-HistoryArtifact -Store $Store -ContentHash $artifact.ContentHash -Extension $artifact.Extension -Text $artifact.Text)
    }
}

$root=Join-Path ([IO.Path]::GetTempPath()) ('milimap-benefit-history-' + [Guid]::NewGuid().ToString('N'))
try {
    $store=New-HistoryStoreLayout -Root $root
    $base=New-TestPackage -Store $store
    Assert-HistoryObservation $base.Observation
    Assert-Equal $base.Observation.BusinessId $businessId 'Stable businessId must be the history identity'
    Assert-True $base.Observation.Comparable 'Complete scoped benefit observation must be comparable'
    Assert-Equal @($base.PreparedArtifacts).Count 2 'Benefit adapter stores evidence and semantic projections only'
    Assert-Equal @($base.Observation.ArtifactReferences).Count 2 'Observation references both structured projection artifacts'

    $nextDay=New-TestPackage -Store $store -ObservedAt '2026-09-27T00:00:00Z' -DiagnosticObservedAt '2026-09-27T00:00:00Z'
    Assert-Equal $nextDay.Observation.EvidenceFingerprint $base.Observation.EvidenceFingerprint 'ObservedAt must not affect evidence fingerprint'
    Assert-Equal $nextDay.Observation.SemanticFingerprint $base.Observation.SemanticFingerprint 'ObservedAt must not affect semantic fingerprint'

    $inputChanged=New-TestPackage -Store $store -BenefitDescription '20% 할인'
    Assert-NotEqual $inputChanged.Observation.InputFingerprint $base.Observation.InputFingerprint 'Canonical benefit edit must change input fingerprint'
    Assert-Equal $inputChanged.Observation.EvidenceFingerprint $base.Observation.EvidenceFingerprint 'Canonical edit must not masquerade as evidence change'

    $evidenceChanged=New-TestPackage -Store $store -EvidenceHash ('b'*64)
    Assert-NotEqual $evidenceChanged.Observation.EvidenceFingerprint $base.Observation.EvidenceFingerprint 'Source content change must change evidence fingerprint'
    Assert-Equal $evidenceChanged.Observation.SemanticFingerprint $base.Observation.SemanticFingerprint 'Physical evidence change alone must not change semantic fingerprint'

    $wordingClaim=New-TestClaim -Value '이용 금액 10% 할인'
    $wordingChanged=New-TestPackage -Store $store -EvidenceHash ('c'*64) -Claims @($wordingClaim)
    Assert-Equal $wordingChanged.Observation.SemanticFingerprint $base.Observation.SemanticFingerprint 'Phase 2 comparison-equivalent wording must not create semantic drift'

    $executionChanged=New-TestPackage -Store $store -Revision ('f'*40)
    Assert-NotEqual $executionChanged.Observation.ExecutionFingerprint $base.Observation.ExecutionFingerprint 'Repository revision must change execution fingerprint'

    $failed=New-TestPackage -Store $store -DiscoveryStatus 'FAILED' -ExtractionStatus 'FAILED'
    Assert-True (-not $failed.Observation.Comparable) 'Operational failure must not be comparable'
    Assert-True (@($failed.Observation.NonComparableReasons).Count -gt 0) 'Non-comparable observation must explain why'

    $missingHashDiagnostic=New-TestDiagnostic -Hash ''
    $business=New-TestBusiness
    $benefit=New-TestBenefit
    $result=New-TestResult
    $noEvidenceIdentity=New-BenefitHistoryObservationPackage -Store $store -RunId $runId -BusinessId $businessId -ObservedAt '2026-09-26T00:00:00Z' -RepositoryRevision $revision -Benefit $benefit -BusinessIdentity $business -Result $result -EvidenceDiagnostics @($missingHashDiagnostic) -OperationalStatus ([pscustomobject]@{DiscoveryStatus='COMPLETE';ExtractionStatus='COMPLETE'})
    Assert-True (-not $noEvidenceIdentity.Observation.Comparable) 'Missing source ContentHash must fail closed for run-to-run comparison'


    $previous=New-TestPackage -Store $store -RunIdValue 'run-11111111111111111111111111111111'
    $evidenceOnly=New-TestPackage -Store $store -RunIdValue 'run-22222222222222222222222222222222' -EvidenceHash ('b'*64)
    Publish-TestPackageArtifacts -Store $store -Package $previous
    Publish-TestPackageArtifacts -Store $store -Package $evidenceOnly
    $evidenceOnlyComparison=Compare-BenefitHistoryObservations -Store $store -Previous $previous.Observation -Current $evidenceOnly.Observation
    Assert-Equal $evidenceOnlyComparison.ChangeCandidates[0] 'EVIDENCE_CHANGE_ONLY' 'Physical evidence-only change stays audit-only'

    $inputOnly=New-TestPackage -Store $store -RunIdValue 'run-33333333333333333333333333333333' -BenefitDescription '20% 할인'
    Publish-TestPackageArtifacts -Store $store -Package $inputOnly
    $inputComparison=Compare-BenefitHistoryObservations -Store $store -Previous $previous.Observation -Current $inputOnly.Observation
    Assert-Equal $inputComparison.ChangeCandidates[0] 'CANONICAL_INPUT_CHANGED' 'Canonical edit must not become external benefit change'

    $executionOnly=New-TestPackage -Store $store -RunIdValue 'run-44444444444444444444444444444444' -Revision ('f'*40)
    Publish-TestPackageArtifacts -Store $store -Package $executionOnly
    $executionComparison=Compare-BenefitHistoryObservations -Store $store -Previous $previous.Observation -Current $executionOnly.Observation
    Assert-Equal $executionComparison.ChangeCandidates[0] 'PROCESSOR_OUTPUT_CHANGED' 'Processor change must not become external benefit change'

    $changedClaim=New-TestClaim -Value '20% 할인' -Result 'CHANGED' -Reasons @('MATERIAL_CHANGE')
    $materialChange=New-TestPackage -Store $store -RunIdValue 'run-55555555555555555555555555555555' -EvidenceHash ('c'*64) -Claims @($changedClaim) -State 'CHANGED'
    Publish-TestPackageArtifacts -Store $store -Package $materialChange
    $materialComparison=Compare-BenefitHistoryObservations -Store $store -Previous $previous.Observation -Current $materialChange.Observation
    Assert-Equal $materialComparison.ChangeCandidates[0] 'BENEFIT_CHANGE_SUSPECTED' 'Validated material semantic delta may create benefit change candidate'

    $absence=New-TestPackage -Store $store -RunIdValue 'run-66666666666666666666666666666666' -EvidenceHash ('d'*64) -LocationStatus 'NOT_FOUND' -LocationOperationalStatus 'COMPLETE' -ExtractionStatus 'FAILED' -State 'NEEDS_VERIFICATION' -Review 'YELLOW' -Claims @()
    Assert-True $absence.Observation.Comparable 'Complete business lookup NOT_FOUND is comparable as an absence observation'
    Publish-TestPackageArtifacts -Store $store -Package $absence
    $absenceComparison=Compare-BenefitHistoryObservations -Store $store -Previous $previous.Observation -Current $absence.Observation
    Assert-Equal $absenceComparison.ChangeCandidates[0] 'BENEFIT_ABSENCE_SUSPECTED' 'Complete explicit NOT_FOUND may create absence candidate'
    Assert-True (@($absenceComparison.ChangeCandidates) -notcontains 'ENDED') 'Absence candidate must never imply ENDED'

    $failedNotFound=New-TestPackage -Store $store -RunIdValue 'run-77777777777777777777777777777777' -EvidenceHash ('e'*64) -FetchStatus 'FAILED' -LocationStatus 'NOT_FOUND' -LocationOperationalStatus 'PARTIAL' -DiscoveryStatus 'PARTIAL' -ExtractionStatus 'FAILED' -State 'NEEDS_VERIFICATION' -Review 'YELLOW' -Claims @()
    Assert-True (-not $failedNotFound.Observation.Comparable) 'Partial/failed NOT_FOUND must not be comparable'
    Publish-TestPackageArtifacts -Store $store -Package $failedNotFound
    $failedComparison=Compare-BenefitHistoryObservations -Store $store -Previous $previous.Observation -Current $failedNotFound.Observation
    Assert-True (@($failedComparison.ChangeCandidates) -contains 'OPERATIONAL_FAILURE') 'Operational failure stays operational'
    Assert-True (@($failedComparison.ChangeCandidates) -notcontains 'BENEFIT_ABSENCE_SUSPECTED') 'Operational failure must never become absence'

    $semanticProjection=Read-BenefitHistorySemanticProjection -Store $store -Observation $materialChange.Observation
    Assert-Equal $semanticProjection.ProjectionType 'BenefitHistorySemantic' 'Persisted semantic projection must be readable and typed'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'Benefit history adapter projection tests passed.'

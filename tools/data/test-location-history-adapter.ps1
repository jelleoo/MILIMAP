$ErrorActionPreference='Stop'

$adapterPath=Join-Path $PSScriptRoot 'lib/history/location-history-adapter.ps1'
if(-not (Test-Path -LiteralPath $adapterPath)){throw 'Location history adapter is missing'}
. $adapterPath

function Assert-Equal { param($Actual,$Expected,[string]$Message);if($Actual -cne $Expected){throw "$Message (expected: $Expected, actual: $Actual)"} }
function Assert-True { param([bool]$Condition,[string]$Message);if(-not $Condition){throw $Message} }
function Assert-NotEqual { param($Actual,$Expected,[string]$Message);if($Actual -ceq $Expected){throw $Message} }
function Assert-Throws { param([scriptblock]$Action,[string]$Message);try { & $Action } catch { return };throw $Message }

function New-TestBusiness {
    param([hashtable]$Overrides=@{})
    $values=[ordered]@{SourceRowNumber=2;OriginalName='테스트 식당';NormalizedName='테스트식당';BaseName='테스트 식당';BranchName='양주점';OriginalRoadAddress='경기도 양주시 테스트로 10';OriginalLotAddress='경기도 양주시 테스트동 10';PreferredAddress='경기도 양주시 테스트로 10';Province='경기도';City='양주시';District='';Dong='테스트동';RoadName='테스트로';BuildingMain='10';BuildingSub='2';Floor='3';Unit='301';AddressParseStatus='COMPLETE';NormalizationWarnings=@()}
    foreach($key in $Overrides.Keys){$values[$key]=$Overrides[$key]}
    return New-NormalizedBusiness @values
}

function New-TestAttempt {
    param([hashtable]$Overrides=@{})
    $values=[ordered]@{StrategyCode='NAME_FULL_ADDRESS';Query='테스트 식당 경기도 양주시 테스트로 10';QueryOrder=1;Status='SUCCESS';ResultCount=1;ErrorCode=''}
    foreach($key in $Overrides.Keys){$values[$key]=$Overrides[$key]}
    return New-PoiQueryAttempt @values
}

function New-TestDiscovery {
    param([hashtable]$Overrides=@{})
    $values=[ordered]@{StrategyCode='NAME_FULL_ADDRESS';Query='테스트 식당 경기도 양주시 테스트로 10';QueryOrder=1;ResultPosition=1;ResultCount=1}
    foreach($key in $Overrides.Keys){$values[$key]=$Overrides[$key]}
    return New-PoiDiscoveryEvidence @values
}

function New-TestCandidate {
    param([hashtable]$Overrides=@{})
    $values=[ordered]@{CandidateKey='naver-1';Provider='NAVER_API_HUB_LOCAL';OriginalName='테스트 식당 양주점';NormalizedName='테스트식당양주점';RoadAddress='경기도 양주시 테스트로 10';LotAddress='경기도 양주시 테스트동 10';Latitude=[double]37.123456;Longitude=[double]127.123456;Phone='031-0000-0010';Category='음식점';ProviderLink='https://map.example/1';DiscoveredBy=@((New-TestDiscovery))}
    foreach($key in $Overrides.Keys){$values[$key]=$Overrides[$key]}
    return New-PoiCandidate @values
}

function New-TestDiscoveryBatch {
    param([hashtable]$Overrides=@{})
    $values=[ordered]@{SourceRowNumber=2;Status='COMPLETE';Candidates=@((New-TestCandidate));QueryAttempts=@((New-TestAttempt))}
    foreach($key in $Overrides.Keys){$values[$key]=$Overrides[$key]}
    return New-PoiDiscoveryBatch @values
}

function New-TestMatchResult {
    param([hashtable]$Overrides=@{})
    $candidate=New-TestCandidate
    $values=[ordered]@{SourceRowNumber=2;EvaluationStatus='COMPLETE';Classification='GREEN';SelectedCandidate=$candidate;RankedCandidateKeys=@($candidate.CandidateKey);ReasonCodes=@('SINGLE_STRONG_CANDIDATE','NAME_EXACT');ConflictCodes=@();Evidence=@((New-PoiMatchEvidence -EvidenceCode 'NAME_EXACT' -CandidateKey $candidate.CandidateKey -CanonicalValue '테스트 식당' -CandidateValue '테스트 식당 양주점' -Matched $true));EvaluatedCandidateCount=1;SurvivingCandidateCount=1;ProductionAction='NONE'}
    foreach($key in $Overrides.Keys){$values[$key]=$Overrides[$key]}
    return New-PoiMatchResult @values
}

function Get-TestFingerprintSet {
    param([Parameter(Mandatory)]$InputProjection,[Parameter(Mandatory)]$Evidence,[Parameter(Mandatory)]$Semantic,[Parameter(Mandatory)]$Execution)
    return New-HistoryFingerprintSet -InputProjection $InputProjection -EvidenceProjection $Evidence -SemanticProjection $Semantic -ExecutionProjection $Execution -InputOrderInsensitivePaths @() -EvidenceOrderInsensitivePaths @('Candidates','Candidates[].DiscoveredBy','QueryAttempts') -SemanticOrderInsensitivePaths @('MaterialReasonCodes','ConflictCodes') -ExecutionOrderInsensitivePaths @()
}

$business=New-TestBusiness
$batch=New-TestDiscoveryBatch
$result=New-TestMatchResult
$input=ConvertTo-LocationHistoryInputProjection -BusinessId 'biz-0123456789abcdef0123456789abcdef' -Business $business
$evidence=ConvertTo-LocationHistoryEvidenceProjection -DiscoveryBatch $batch
$semantic=ConvertTo-LocationHistorySemanticProjection -DiscoveryBatch $batch -Result $result
$execution=ConvertTo-LocationHistoryExecutionProjection -RepositoryRevision ('a'*40) -ExecutionConfiguration ([pscustomobject]@{Mode='TEST'})
$fingerprints=Get-TestFingerprintSet -InputProjection $input -Evidence $evidence -Semantic $semantic -Execution $execution

Assert-Equal $input.ProjectionType LocationHistoryInput 'Input projection type is fixed'
Assert-Equal $evidence.ProjectionType LocationHistoryEvidence 'Evidence projection type is fixed'
Assert-Equal $semantic.ProjectionType LocationHistorySemantic 'Semantic projection type is fixed'
Assert-Equal $execution.ProjectionType LocationHistoryExecution 'Execution projection type is fixed'
Assert-Equal $input.ProjectionVersion 1 'Input projection version is fixed'
Assert-Equal $execution.LocationHistoryAdapterVersion 1 'Execution projection records the Location adapter version'
Assert-True (-not ($input.PSObject.Properties.Name -contains 'SourceRowNumber')) 'Input projection excludes source row metadata'
Assert-True (-not ($input.PSObject.Properties.Name -contains 'AddressParseStatus')) 'Input projection excludes parse-status metadata'
Assert-True (-not ($input.PSObject.Properties.Name -contains 'NormalizationWarnings')) 'Input projection excludes normalization warnings'
Assert-True (-not ($evidence.Candidates[0].PSObject.Properties.Name -contains 'CandidateKey')) 'Evidence projection excludes provider-local CandidateKey'
Assert-True (-not ($evidence.Candidates[0].DiscoveredBy[0].PSObject.Properties.Name -contains 'ResultPosition')) 'Evidence projection excludes provider result position'
Assert-True (-not ($evidence.Candidates[0].DiscoveredBy[0].PSObject.Properties.Name -contains 'ResultCount')) 'Evidence projection excludes provider result count'
Assert-True (-not ($semantic.PSObject.Properties.Name -contains 'ProductionAction')) 'Semantic projection does not fingerprint ProductionAction'

# Input mutation matrix: source metadata does not change matcher input, while
# each explicit normalized identity field remains meaningful fingerprint input.
foreach($ignored in @(
    @{SourceRowNumber=3},
    @{AddressParseStatus='PARTIAL'},
    @{NormalizationWarnings=@('ADDRESS_PARSE_PARTIAL')}
)){
    $changed=ConvertTo-LocationHistoryInputProjection -BusinessId 'biz-0123456789abcdef0123456789abcdef' -Business (New-TestBusiness -Overrides $ignored)
    Assert-Equal (Get-TestFingerprintSet -InputProjection $changed -Evidence $evidence -Semantic $semantic -Execution $execution).InputFingerprint $fingerprints.InputFingerprint 'Input metadata-only mutation does not change InputFingerprint'
}
foreach($mutation in @(
    @{OriginalName='다른 식당'},@{NormalizedName='다른식당'},@{BaseName='다른 식당'},@{BranchName='파주점'},
    @{OriginalRoadAddress='경기도 양주시 다른로 10';PreferredAddress='경기도 양주시 다른로 10'},@{OriginalLotAddress='경기도 양주시 다른동 10'},@{PreferredAddress='경기도 양주시 테스트동 10'},
    @{Province='서울특별시'},@{City='파주시'},@{District='테스트구'},@{Dong='다른동'},@{RoadName='다른로'},
    @{BuildingMain='11'},@{BuildingSub='3'},@{Floor='4'},@{Unit='401'}
)){
    $changed=ConvertTo-LocationHistoryInputProjection -BusinessId 'biz-0123456789abcdef0123456789abcdef' -Business (New-TestBusiness -Overrides $mutation)
    Assert-NotEqual (Get-TestFingerprintSet -InputProjection $changed -Evidence $evidence -Semantic $semantic -Execution $execution).InputFingerprint $fingerprints.InputFingerprint 'Meaningful normalized identity mutation changes InputFingerprint'
}

# Evidence mutation matrix: only the discovery batch participates.  Physical
# provider ordering, discovery result placement, and provider-local keys do not.
$candidate2=New-TestCandidate -Overrides @{CandidateKey='naver-2';OriginalName='두 번째 식당';NormalizedName='두번째식당';RoadAddress='경기도 양주시 테스트로 20';LotAddress='경기도 양주시 테스트동 20';Latitude=[double]37.223456;Longitude=[double]127.223456;Phone='031-0000-0020';ProviderLink='https://map.example/2'}
$attempt2=New-TestAttempt -Overrides @{StrategyCode='NAME_ROAD_BUILDING';Query='테스트 식당 테스트로 10';QueryOrder=2;ResultCount=0}
$orderedBatch=New-TestDiscoveryBatch -Overrides @{Candidates=@((New-TestCandidate),$candidate2);QueryAttempts=@((New-TestAttempt),$attempt2)}
$orderedEvidence=ConvertTo-LocationHistoryEvidenceProjection -DiscoveryBatch $orderedBatch
$reorderedBatch=New-TestDiscoveryBatch -Overrides @{Candidates=@($candidate2,(New-TestCandidate));QueryAttempts=@($attempt2,(New-TestAttempt))}
$reorderedEvidence=ConvertTo-LocationHistoryEvidenceProjection -DiscoveryBatch $reorderedBatch
Assert-Equal (Get-TestFingerprintSet -InputProjection $input -Evidence $orderedEvidence -Semantic $semantic -Execution $execution).EvidenceFingerprint (Get-TestFingerprintSet -InputProjection $input -Evidence $reorderedEvidence -Semantic $semantic -Execution $execution).EvidenceFingerprint 'Candidate and query-attempt physical order do not change EvidenceFingerprint'

$firstMembership=New-TestDiscovery
$secondMembership=New-TestDiscovery -Overrides @{StrategyCode='NAME_ROAD_BUILDING';Query='테스트 식당 테스트로 10';QueryOrder=2;ResultPosition=1;ResultCount=1}
$membershipOrdered=ConvertTo-LocationHistoryEvidenceProjection -DiscoveryBatch (New-TestDiscoveryBatch -Overrides @{Candidates=@((New-TestCandidate -Overrides @{DiscoveredBy=@($firstMembership,$secondMembership)}))})
$membershipReordered=ConvertTo-LocationHistoryEvidenceProjection -DiscoveryBatch (New-TestDiscoveryBatch -Overrides @{Candidates=@((New-TestCandidate -Overrides @{DiscoveredBy=@($secondMembership,$firstMembership)}))})
Assert-Equal (Get-TestFingerprintSet -InputProjection $input -Evidence $membershipOrdered -Semantic $semantic -Execution $execution).EvidenceFingerprint (Get-TestFingerprintSet -InputProjection $input -Evidence $membershipReordered -Semantic $semantic -Execution $execution).EvidenceFingerprint 'Discovery-membership physical order does not change EvidenceFingerprint'

$membership=New-TestDiscovery
$duplicateMembership=New-TestDiscovery -Overrides @{ResultPosition=1;ResultCount=2}
$candidateWithDuplicateMembership=New-TestCandidate -Overrides @{DiscoveredBy=@($membership,$duplicateMembership)}
$duplicateMembershipEvidence=ConvertTo-LocationHistoryEvidenceProjection -DiscoveryBatch (New-TestDiscoveryBatch -Overrides @{Candidates=@($candidateWithDuplicateMembership)})
Assert-Equal (Get-TestFingerprintSet -InputProjection $input -Evidence $evidence -Semantic $semantic -Execution $execution).EvidenceFingerprint (Get-TestFingerprintSet -InputProjection $input -Evidence $duplicateMembershipEvidence -Semantic $semantic -Execution $execution).EvidenceFingerprint 'Repeated discovery within one query membership is deduplicated before EvidenceFingerprint'
Assert-Equal @($duplicateMembershipEvidence.Candidates[0].DiscoveredBy).Count 1 'Evidence projection stores one distinct discovery-query membership tuple'

foreach($unchanged in @(
    (New-TestDiscoveryBatch -Overrides @{SourceRowNumber=3}),
    (New-TestDiscoveryBatch -Overrides @{Candidates=@((New-TestCandidate -Overrides @{CandidateKey='different-provider-key'}))}),
    (New-TestDiscoveryBatch -Overrides @{Candidates=@((New-TestCandidate -Overrides @{DiscoveredBy=@((New-TestDiscovery -Overrides @{ResultPosition=1;ResultCount=9}))}))})
)){
    $changed=ConvertTo-LocationHistoryEvidenceProjection -DiscoveryBatch $unchanged
    Assert-Equal (Get-TestFingerprintSet -InputProjection $input -Evidence $changed -Semantic $semantic -Execution $execution).EvidenceFingerprint $fingerprints.EvidenceFingerprint 'Provider-local source row/key/result-position/count mutation does not change EvidenceFingerprint'
}
foreach($mutation in @(
    @{OriginalName='다른 후보'},@{NormalizedName='다른후보'},@{RoadAddress='경기도 양주시 다른로 10'},@{LotAddress='경기도 양주시 다른동 10'},@{Latitude=[double]37.223456},@{Longitude=[double]127.223456},@{Phone='031-0000-0099'},@{Category='카페'},@{ProviderLink='https://map.example/changed'}
)){
    $changed=ConvertTo-LocationHistoryEvidenceProjection -DiscoveryBatch (New-TestDiscoveryBatch -Overrides @{Candidates=@((New-TestCandidate -Overrides $mutation))})
    Assert-NotEqual (Get-TestFingerprintSet -InputProjection $input -Evidence $changed -Semantic $semantic -Execution $execution).EvidenceFingerprint $fingerprints.EvidenceFingerprint 'Provider candidate evidence mutation changes EvidenceFingerprint'
}
$reorderedOutcome=New-TestMatchResult -Overrides @{ReasonCodes=@('NAME_EXACT','SINGLE_STRONG_CANDIDATE');ConflictCodes=@('BRANCH_CONFLICT','CITY_DISTRICT_CONFLICT')}
$orderedOutcome=New-TestMatchResult -Overrides @{ReasonCodes=@('SINGLE_STRONG_CANDIDATE','NAME_EXACT');ConflictCodes=@('CITY_DISTRICT_CONFLICT','BRANCH_CONFLICT')}
Assert-Equal (Get-TestFingerprintSet -InputProjection $input -Evidence $evidence -Semantic (ConvertTo-LocationHistorySemanticProjection -DiscoveryBatch $batch -Result $orderedOutcome) -Execution $execution).SemanticFingerprint (Get-TestFingerprintSet -InputProjection $input -Evidence $evidence -Semantic (ConvertTo-LocationHistorySemanticProjection -DiscoveryBatch $batch -Result $reorderedOutcome) -Execution $execution).SemanticFingerprint 'Material reason and conflict physical order do not change SemanticFingerprint'
$candidateCountOrOrderChangedBatch=New-TestDiscoveryBatch -Overrides @{Candidates=@($candidate2,(New-TestCandidate))}
Assert-Equal (Get-TestFingerprintSet -InputProjection $input -Evidence $evidence -Semantic (ConvertTo-LocationHistorySemanticProjection -DiscoveryBatch $candidateCountOrOrderChangedBatch -Result $result) -Execution $execution).SemanticFingerprint $fingerprints.SemanticFingerprint 'Unselected candidate count/order does not change final selected semantic meaning'
foreach($mutation in @(
    @{StrategyCode='NAME_ROAD_BUILDING'},@{Query='다른 검색어'},@{QueryOrder=2},@{Status='SKIPPED';ResultCount=0},@{ErrorCode='UPSTREAM'}
)){
    $changed=ConvertTo-LocationHistoryEvidenceProjection -DiscoveryBatch (New-TestDiscoveryBatch -Overrides @{QueryAttempts=@((New-TestAttempt -Overrides $mutation))})
    Assert-NotEqual (Get-TestFingerprintSet -InputProjection $input -Evidence $changed -Semantic $semantic -Execution $execution).EvidenceFingerprint $fingerprints.EvidenceFingerprint 'Discovery query meaning mutation changes EvidenceFingerprint'
}
$membershipChanged=ConvertTo-LocationHistoryEvidenceProjection -DiscoveryBatch (New-TestDiscoveryBatch -Overrides @{Candidates=@((New-TestCandidate -Overrides @{DiscoveredBy=@((New-TestDiscovery),(New-TestDiscovery -Overrides @{StrategyCode='NAME_ROAD_BUILDING';Query='테스트 식당 테스트로 10';QueryOrder=2;ResultPosition=1;ResultCount=1}))}))})
Assert-NotEqual (Get-TestFingerprintSet -InputProjection $input -Evidence $membershipChanged -Semantic $semantic -Execution $execution).EvidenceFingerprint $fingerprints.EvidenceFingerprint 'Discovery-query membership mutation changes EvidenceFingerprint'
$partialEvidence=ConvertTo-LocationHistoryEvidenceProjection -DiscoveryBatch (New-TestDiscoveryBatch -Overrides @{Status='PARTIAL'})
Assert-NotEqual (Get-TestFingerprintSet -InputProjection $input -Evidence $partialEvidence -Semantic $semantic -Execution $execution).EvidenceFingerprint $fingerprints.EvidenceFingerprint 'DiscoveryStatus changes EvidenceFingerprint'

# Semantic mutation matrix: only final selected-location/evaluation outcome and
# material reason/conflict sets are included.  Provider metadata and matcher
# internals must not become temporal location meaning.
Assert-Equal $semantic.SelectionStatus SELECTED 'Selected result projects a SELECTED semantic status'
Assert-Equal $semantic.SelectedLocation.Name (ConvertTo-PoiMatchCompactText $result.SelectedCandidate.NormalizedName) 'Selected semantic name uses existing matcher compact text semantics'
Assert-Equal $semantic.SelectedLocation.RoadAddress (ConvertTo-PoiMatchCompactText $result.SelectedCandidate.RoadAddress) 'Selected semantic road address uses existing matcher compact text semantics'
Assert-Equal $semantic.SelectedLocation.LotAddress (ConvertTo-PoiMatchCompactText $result.SelectedCandidate.LotAddress) 'Selected semantic lot address uses existing matcher compact text semantics'
Assert-Equal @($semantic.MaterialReasonCodes).Count 1 'Only approved material outcome reason codes are projected'
Assert-Equal $semantic.MaterialReasonCodes[0] SINGLE_STRONG_CANDIDATE 'Matcher-internal reason codes are excluded from semantic projection'
foreach($sameMeaning in @(
    (New-TestMatchResult -Overrides @{SelectedCandidate=(New-TestCandidate -Overrides @{CandidateKey='other-key'});RankedCandidateKeys=@('other-key')}),
    (New-TestMatchResult -Overrides @{RankedCandidateKeys=@('unrelated-rank')}),
    (New-TestMatchResult -Overrides @{SelectedCandidate=(New-TestCandidate -Overrides @{Phone='031-9999-9999';Category='카페';ProviderLink='https://map.example/other'})}),
    (New-TestMatchResult -Overrides @{Evidence=@((New-PoiMatchEvidence -EvidenceCode 'ADDRESS_EXACT' -CandidateKey 'unrelated' -CanonicalValue 'x' -CandidateValue 'y' -Matched $false))}),
    (New-TestMatchResult -Overrides @{EvaluatedCandidateCount=9;SurvivingCandidateCount=8})
)){
    $changed=ConvertTo-LocationHistorySemanticProjection -DiscoveryBatch $batch -Result $sameMeaning
    Assert-Equal (Get-TestFingerprintSet -InputProjection $input -Evidence $evidence -Semantic $changed -Execution $execution).SemanticFingerprint $fingerprints.SemanticFingerprint 'Provider-only matcher result mutation does not change SemanticFingerprint'
}
foreach($mutation in @(
    @{SelectedCandidate=(New-TestCandidate -Overrides @{NormalizedName='다른식당양주점'})},
    @{SelectedCandidate=(New-TestCandidate -Overrides @{RoadAddress='경기도 양주시 다른로 10'})},
    @{SelectedCandidate=(New-TestCandidate -Overrides @{LotAddress='경기도 양주시 다른동 10'})},
    @{SelectedCandidate=(New-TestCandidate -Overrides @{Latitude=[double]37.223456})},
    @{SelectedCandidate=(New-TestCandidate -Overrides @{Longitude=[double]127.223456})},
    @{Classification='YELLOW'},@{ReasonCodes=@('MULTIPLE_PLAUSIBLE_CANDIDATES')},@{ConflictCodes=@('BRANCH_CONFLICT')}
)){
    $changed=ConvertTo-LocationHistorySemanticProjection -DiscoveryBatch $batch -Result (New-TestMatchResult -Overrides $mutation)
    Assert-NotEqual (Get-TestFingerprintSet -InputProjection $input -Evidence $evidence -Semantic $changed -Execution $execution).SemanticFingerprint $fingerprints.SemanticFingerprint 'Final selected location or material semantic outcome mutation changes SemanticFingerprint'
}
$noneResult=New-PoiMatchResult -SourceRowNumber 2 -EvaluationStatus COMPLETE -Classification RED -SelectedCandidate $null -RankedCandidateKeys @() -ReasonCodes @('NO_CANDIDATE') -ConflictCodes @() -Evidence @() -EvaluatedCandidateCount 0 -SurvivingCandidateCount 0 -ProductionAction NONE
$absenceBatch=New-TestDiscoveryBatch -Overrides @{Candidates=@()}
$absenceSemantic=ConvertTo-LocationHistorySemanticProjection -DiscoveryBatch $absenceBatch -Result $noneResult
Assert-Equal $absenceSemantic.SelectionStatus NONE 'Unselected result projects a NONE semantic status'
Assert-True $absenceSemantic.AbsenceEligible 'Only complete zero-candidate RED/NO_CANDIDATE is absence eligible'
Assert-NotEqual (Get-TestFingerprintSet -InputProjection $input -Evidence $evidence -Semantic $absenceSemantic -Execution $execution).SemanticFingerprint $fingerprints.SemanticFingerprint 'SELECTED to NONE changes SemanticFingerprint'
foreach($notAbsence in @(
    (New-TestDiscoveryBatch -Overrides @{Status='PARTIAL';Candidates=@()}),
    (New-TestDiscoveryBatch -Overrides @{Status='FAILED';Candidates=@()}),
    (New-TestDiscoveryBatch -Overrides @{Candidates=@((New-TestCandidate))})
)){
    $notAbsenceResult=if($notAbsence.Status -ceq 'COMPLETE' -and @($notAbsence.Candidates).Count -gt 0){New-PoiMatchResult -SourceRowNumber 2 -EvaluationStatus COMPLETE -Classification RED -SelectedCandidate $null -RankedCandidateKeys @() -ReasonCodes @('NO_CANDIDATE') -ConflictCodes @('BRANCH_CONFLICT') -Evidence @() -EvaluatedCandidateCount 1 -SurvivingCandidateCount 0 -ProductionAction NONE}else{$noneResult}
    Assert-True (-not (ConvertTo-LocationHistorySemanticProjection -DiscoveryBatch $notAbsence -Result $notAbsenceResult).AbsenceEligible) 'Partial, failed, or candidate-bearing results are never absence eligible'
}
$originalCulture=[Globalization.CultureInfo]::CurrentCulture
try {
    [Globalization.CultureInfo]::CurrentCulture=[Globalization.CultureInfo]::GetCultureInfo('ko-KR')
    $koFingerprint=(Get-TestFingerprintSet -InputProjection $input -Evidence $evidence -Semantic $semantic -Execution $execution).SemanticFingerprint
    [Globalization.CultureInfo]::CurrentCulture=[Globalization.CultureInfo]::GetCultureInfo('fr-FR')
    $frFingerprint=(Get-TestFingerprintSet -InputProjection $input -Evidence $evidence -Semantic $semantic -Execution $execution).SemanticFingerprint
    Assert-Equal $koFingerprint $frFingerprint 'Invariant history serialization keeps coordinate SemanticFingerprint culture-independent'
} finally { [Globalization.CultureInfo]::CurrentCulture=$originalCulture }

Assert-Equal $execution.PoiContractVersion (Get-PoiVerificationContractDefinition).ContractVersion 'Execution projection preserves the frozen Phase 1 contract version'
Assert-Equal $execution.HistoryContractVersion 1 'Execution projection preserves History Core contract version'
Assert-Equal $execution.FingerprintSchemaVersion 1 'Execution projection preserves fingerprint schema version'
Assert-Equal $execution.ComparatorVersion 1 'Execution projection preserves comparator version'
Assert-Throws { ConvertTo-LocationHistoryExecutionProjection -RepositoryRevision ('A'*40) } 'Execution projection rejects non-lowercase repository revisions'

# Task 2: operational/comparable assessment, prepared projection artifacts,
# store-backed reads, and the internal staged-current validation boundary.
function Copy-TestLocationObject {
    param([Parameter(Mandatory)]$Value)
    return ($Value | ConvertTo-Json -Depth 30 | ConvertFrom-Json)
}

function New-TestLocationPackage {
    param(
        [Parameter(Mandatory)]$Store,
        [string]$RunId='run-0123456789abcdef0123456789abcdef',
        [string]$ObservedAt='2026-09-27T00:00:00Z',
        [string]$RepositoryRevision=('b'*40),
        [AllowNull()]$BusinessOverride=$null,
        [AllowNull()]$BatchOverride=$null,
        [AllowNull()]$ResultOverride=$null
    )
    $packageBusiness=if($null -eq $BusinessOverride){New-TestBusiness}else{$BusinessOverride}
    $packageBatch=if($null -eq $BatchOverride){New-TestDiscoveryBatch}else{$BatchOverride}
    $packageResult=if($null -eq $ResultOverride){New-TestMatchResult}else{$ResultOverride}
    return New-LocationHistoryObservationPackage -Store $Store -RunId $RunId -BusinessId 'biz-0123456789abcdef0123456789abcdef' -ObservedAt $ObservedAt -RepositoryRevision $RepositoryRevision -Business $packageBusiness -DiscoveryBatch $packageBatch -Result $packageResult -ExecutionConfiguration ([pscustomobject]@{Mode='TEST'})
}

function Publish-TestLocationPackageArtifacts {
    param([Parameter(Mandatory)]$Store,[Parameter(Mandatory)]$Package)
    foreach($artifact in @($Package.PreparedArtifacts)){
        [void](Write-HistoryArtifact -Store $Store -ContentHash $artifact.ContentHash -Extension $artifact.Extension -Text $artifact.Text)
    }
}

function New-TestLocationProjectionArtifact {
    param([Parameter(Mandatory)]$Store,[Parameter(Mandatory)][string]$Kind,[Parameter(Mandatory)]$Projection)
    $json=ConvertTo-HistoryCanonicalJson -Value $Projection -OrderInsensitivePaths @('MaterialReasonCodes','ConflictCodes')
    $hash=Get-HistorySha256 -Text $json
    [void](Write-HistoryArtifact -Store $Store -ContentHash $hash -Extension 'json' -Text $json)
    return New-HistoryArtifactReference -Kind $Kind -ContentHash $hash -RelativePath (Get-HistoryRelativePath -Store $Store -FullPath (Get-HistoryArtifactPath -Store $Store -ContentHash $hash -Extension 'json'))
}

$completeAssessment=Get-LocationHistoryOperationalAssessment -DiscoveryBatch $batch -Result $result
Assert-Equal $completeAssessment.OperationalStatus COMPLETE 'COMPLETE discovery and evaluation are operationally complete'
Assert-True $completeAssessment.Comparable 'COMPLETE discovery and evaluation are comparable'
$incompleteResult=New-TestMatchResult -Overrides @{EvaluationStatus='INCOMPLETE';Classification='YELLOW'}
$incompleteAssessment=Get-LocationHistoryOperationalAssessment -DiscoveryBatch $batch -Result $incompleteResult
Assert-Equal $incompleteAssessment.OperationalStatus PARTIAL 'Incomplete evaluation is operationally partial'
Assert-True (-not $incompleteAssessment.Comparable) 'Incomplete evaluation is not comparable'
Assert-Equal (@($incompleteAssessment.NonComparableReasons) -join ',') EVALUATION_INCOMPLETE 'Incomplete evaluation has the deterministic reason code'
$partialBatch=New-TestDiscoveryBatch -Overrides @{Status='PARTIAL'}
$partialAssessment=Get-LocationHistoryOperationalAssessment -DiscoveryBatch $partialBatch -Result $incompleteResult
Assert-Equal $partialAssessment.OperationalStatus PARTIAL 'Partial discovery remains partial'
Assert-Equal (@($partialAssessment.NonComparableReasons) -join ',') 'DISCOVERY_PARTIAL_FAILURE,EVALUATION_INCOMPLETE' 'Partial/incomplete reasons are deterministic and unique'
$failedBatch=New-TestDiscoveryBatch -Overrides @{Status='FAILED'}
$failedAssessment=Get-LocationHistoryOperationalAssessment -DiscoveryBatch $failedBatch -Result $incompleteResult
Assert-Equal $failedAssessment.OperationalStatus FAILED 'Failed discovery dominates operational status'
Assert-Equal (@($failedAssessment.NonComparableReasons) -join ',') 'DISCOVERY_FAILED,EVALUATION_INCOMPLETE' 'Failed/incomplete reasons are deterministic and unique'
Assert-True (Get-LocationHistoryOperationalAssessment -DiscoveryBatch $batch -Result (New-TestMatchResult -Overrides @{Classification='YELLOW'})).Comparable 'Complete YELLOW remains comparable'
Assert-True (Get-LocationHistoryOperationalAssessment -DiscoveryBatch $absenceBatch -Result $noneResult).Comparable 'Complete strict absence remains comparable'
Assert-Throws { Get-LocationHistoryOperationalAssessment -DiscoveryBatch (New-TestDiscoveryBatch -Overrides @{SourceRowNumber=3}) -Result $result } 'Discovery/result SourceRowNumber mismatch must fail closed'

$historyRoot=Join-Path ([IO.Path]::GetTempPath()) ('milimap-location-history-' + [Guid]::NewGuid().ToString('N'))
try {
    $store=New-HistoryStoreLayout -Root $historyRoot
    $package=New-TestLocationPackage -Store $store
    Assert-HistoryObservation $package.Observation
    Assert-Equal $package.Observation.Domain LOCATION 'Location package creates a LOCATION observation'
    Assert-Equal @($package.PreparedArtifacts).Count 2 'Location package prepares only evidence and semantic projection artifacts'
    Assert-Equal @($package.Observation.ArtifactReferences).Count 2 'Location observation references exactly two artifacts'
    $evidenceReference=@($package.Observation.ArtifactReferences | Where-Object { $_.Kind -ceq 'LOCATION_EVIDENCE_PROJECTION' })
    $semanticReference=@($package.Observation.ArtifactReferences | Where-Object { $_.Kind -ceq 'LOCATION_SEMANTIC_PROJECTION' })
    Assert-Equal $evidenceReference.Count 1 'Location observation has one evidence projection reference'
    Assert-Equal $semanticReference.Count 1 'Location observation has one semantic projection reference'
    Assert-Equal $package.Observation.SemanticResultReference $semanticReference[0].RelativePath 'Semantic result reference matches the semantic projection artifact'
    Assert-True (@($package.Observation.ArtifactReferences | Where-Object { $_.Kind -match 'RAW|INPUT|EXECUTION' }).Count -eq 0) 'Location package does not prepare raw, input, or execution artifacts'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $store.Root $semanticReference[0].RelativePath))) 'Prepared semantic artifact is not published before commit'

    $expectedFingerprints=Get-TestFingerprintSet -InputProjection $package.InputProjection -Evidence $package.EvidenceProjection -Semantic $package.SemanticProjection -Execution $package.ExecutionProjection
    Assert-Equal $package.Observation.InputFingerprint $expectedFingerprints.InputFingerprint 'Observation InputFingerprint uses Task 1 projection'
    Assert-Equal $package.Observation.EvidenceFingerprint $expectedFingerprints.EvidenceFingerprint 'Observation EvidenceFingerprint uses Task 1 projection ordering'
    Assert-Equal $package.Observation.SemanticFingerprint $expectedFingerprints.SemanticFingerprint 'Observation SemanticFingerprint uses Task 1 projection ordering'
    Assert-Equal $package.Observation.ExecutionFingerprint $expectedFingerprints.ExecutionFingerprint 'Observation ExecutionFingerprint uses Task 1 projection'
    $nextRun=New-TestLocationPackage -Store $store -RunId 'run-11111111111111111111111111111111'
    Assert-NotEqual $nextRun.Observation.ObservationId $package.Observation.ObservationId 'Different RunId produces a different deterministic ObservationId'

    $businessRowMismatch=New-TestBusiness -Overrides @{SourceRowNumber=3}
    Assert-Throws { New-TestLocationPackage -Store $store -BusinessOverride $businessRowMismatch } 'Business/discovery/result SourceRowNumber chain mismatch must fail closed'

    Publish-TestLocationPackageArtifacts -Store $store -Package $package
    $readSemantic=Read-LocationHistorySemanticProjection -Store $store -Observation $package.Observation
    Assert-Equal $readSemantic.ProjectionType LocationHistorySemantic 'Stored Location semantic projection is readable and typed'

    $unpublishedReadResult=New-TestMatchResult -Overrides @{SelectedCandidate=(New-TestCandidate -Overrides @{NormalizedName='미발행식당양주점'})}
    $unpublishedReadPackage=New-TestLocationPackage -Store $store -RunId 'run-22222222222222222222222222222222' -ResultOverride $unpublishedReadResult
    Assert-Throws { Read-LocationHistorySemanticProjection -Store $store -Observation $unpublishedReadPackage.Observation } 'Location semantic reader rejects a missing semantic artifact'

    $wrongDomain=Copy-TestLocationObject $package.Observation
    $wrongDomain.Domain='BENEFIT'
    Assert-Throws { Read-LocationHistorySemanticProjection -Store $store -Observation $wrongDomain } 'Location semantic reader rejects a non-LOCATION observation'
    $wrongKind=Copy-TestLocationObject $package.Observation
    (@($wrongKind.ArtifactReferences | Where-Object { $_.Kind -ceq 'LOCATION_SEMANTIC_PROJECTION' })[0]).Kind='OTHER_PROJECTION'
    Assert-Throws { Read-LocationHistorySemanticProjection -Store $store -Observation $wrongKind } 'Location semantic reader requires exactly one semantic projection artifact'
    $multipleSemanticReferences=Copy-TestLocationObject $package.Observation
    $multipleSemanticReferences.ArtifactReferences=@($multipleSemanticReferences.ArtifactReferences)+@(New-HistoryArtifactReference -Kind 'LOCATION_SEMANTIC_PROJECTION' -ContentHash ('e'*64) -RelativePath 'artifacts/sha256/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee.json')
    Assert-Throws { Read-LocationHistorySemanticProjection -Store $store -Observation $multipleSemanticReferences } 'Location semantic reader rejects multiple semantic projection artifacts'
    $wrongResultReference=Copy-TestLocationObject $package.Observation
    $wrongResultReference.SemanticResultReference='artifacts/sha256/not-the-semantic-projection.json'
    Assert-Throws { Read-LocationHistorySemanticProjection -Store $store -Observation $wrongResultReference } 'Location semantic reader rejects mismatched semantic result reference'

    $wrongType=Copy-TestLocationObject $package.SemanticProjection
    $wrongType.ProjectionType='WrongLocationHistorySemantic'
    $wrongTypeReference=New-TestLocationProjectionArtifact -Store $store -Kind 'LOCATION_SEMANTIC_PROJECTION' -Projection $wrongType
    $wrongTypeObservation=Copy-TestLocationObject $package.Observation
    (@($wrongTypeObservation.ArtifactReferences | Where-Object { $_.Kind -ceq 'LOCATION_SEMANTIC_PROJECTION' })[0]).ContentHash=$wrongTypeReference.ContentHash
    (@($wrongTypeObservation.ArtifactReferences | Where-Object { $_.Kind -ceq 'LOCATION_SEMANTIC_PROJECTION' })[0]).RelativePath=$wrongTypeReference.RelativePath
    $wrongTypeObservation.SemanticResultReference=$wrongTypeReference.RelativePath
    Assert-Throws { Read-LocationHistorySemanticProjection -Store $store -Observation $wrongTypeObservation } 'Location semantic reader rejects a tampered projection type'
    $wrongVersion=Copy-TestLocationObject $package.SemanticProjection
    $wrongVersion.ProjectionVersion=2
    $wrongVersionReference=New-TestLocationProjectionArtifact -Store $store -Kind 'LOCATION_SEMANTIC_PROJECTION' -Projection $wrongVersion
    $wrongVersionObservation=Copy-TestLocationObject $package.Observation
    (@($wrongVersionObservation.ArtifactReferences | Where-Object { $_.Kind -ceq 'LOCATION_SEMANTIC_PROJECTION' })[0]).ContentHash=$wrongVersionReference.ContentHash
    (@($wrongVersionObservation.ArtifactReferences | Where-Object { $_.Kind -ceq 'LOCATION_SEMANTIC_PROJECTION' })[0]).RelativePath=$wrongVersionReference.RelativePath
    $wrongVersionObservation.SemanticResultReference=$wrongVersionReference.RelativePath
    Assert-Throws { Read-LocationHistorySemanticProjection -Store $store -Observation $wrongVersionObservation } 'Location semantic reader rejects a tampered projection version'
    $wrongFingerprint=Copy-TestLocationObject $package.Observation
    $wrongFingerprint.SemanticFingerprint=('0'*64)
    Assert-Throws { Read-LocationHistorySemanticProjection -Store $store -Observation $wrongFingerprint } 'Location semantic reader rejects a semantic fingerprint mismatch'

    Assert-Equal (Get-InternalStagedLocationHistorySemanticProjection -Current $package.Observation -StagedCurrentSemanticProjection $package.SemanticProjection).ProjectionType LocationHistorySemantic 'Validated staged current semantic projection is accepted without pre-CAS publication'
    $stagedWrongType=Copy-TestLocationObject $package.SemanticProjection
    $stagedWrongType.ProjectionType='WrongLocationHistorySemantic'
    Assert-Throws { Get-InternalStagedLocationHistorySemanticProjection -Current $package.Observation -StagedCurrentSemanticProjection $stagedWrongType } 'Staged projection type tampering fails closed'
    $stagedWrongVersion=Copy-TestLocationObject $package.SemanticProjection
    $stagedWrongVersion.ProjectionVersion=2
    Assert-Throws { Get-InternalStagedLocationHistorySemanticProjection -Current $package.Observation -StagedCurrentSemanticProjection $stagedWrongVersion } 'Staged projection version tampering fails closed'
    $stagedWrongFingerprint=Copy-TestLocationObject $package.Observation
    $stagedWrongFingerprint.SemanticFingerprint=('0'*64)
    Assert-Throws { Get-InternalStagedLocationHistorySemanticProjection -Current $stagedWrongFingerprint -StagedCurrentSemanticProjection $package.SemanticProjection } 'Staged projection fingerprint mismatch fails closed'
    $stagedWrongReference=Copy-TestLocationObject $package.Observation
    $stagedWrongReference.SemanticResultReference='artifacts/sha256/not-the-semantic-projection.json'
    Assert-Throws { Get-InternalStagedLocationHistorySemanticProjection -Current $stagedWrongReference -StagedCurrentSemanticProjection $package.SemanticProjection } 'Staged semantic result reference mismatch fails closed'
    $stagedWrongHash=Copy-TestLocationObject $package.Observation
    (@($stagedWrongHash.ArtifactReferences | Where-Object { $_.Kind -ceq 'LOCATION_SEMANTIC_PROJECTION' })[0]).ContentHash=('0'*64)
    Assert-Throws { Get-InternalStagedLocationHistorySemanticProjection -Current $stagedWrongHash -StagedCurrentSemanticProjection $package.SemanticProjection } 'Staged semantic artifact hash mismatch fails closed'
    $stagedWrongKind=Copy-TestLocationObject $package.Observation
    (@($stagedWrongKind.ArtifactReferences | Where-Object { $_.Kind -ceq 'LOCATION_SEMANTIC_PROJECTION' })[0]).Kind='OTHER_PROJECTION'
    Assert-Throws { Get-InternalStagedLocationHistorySemanticProjection -Current $stagedWrongKind -StagedCurrentSemanticProjection $package.SemanticProjection } 'Staged validation rejects missing semantic reference'
    $stagedMultipleReferences=Copy-TestLocationObject $package.Observation
    $extraReference=New-HistoryArtifactReference -Kind 'LOCATION_SEMANTIC_PROJECTION' -ContentHash ('f'*64) -RelativePath 'artifacts/sha256/ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff.json'
    $stagedMultipleReferences.ArtifactReferences=@($stagedMultipleReferences.ArtifactReferences)+@($extraReference)
    Assert-Throws { Get-InternalStagedLocationHistorySemanticProjection -Current $stagedMultipleReferences -StagedCurrentSemanticProjection $package.SemanticProjection } 'Staged validation rejects multiple semantic references'

    foreach($functionName in @('Get-LocationHistoryOperationalAssessment','New-LocationHistoryObservationPackage','Read-LocationHistorySemanticProjection')){
        foreach($forbidden in @('Trusted','Validated','SkipValidation')){
            Assert-True (-not (Get-Command $functionName).Parameters.ContainsKey($forbidden)) "$functionName exposes no public $forbidden bypass"
        }
    }
} finally {
    if(Test-Path -LiteralPath $historyRoot){ Remove-Item -LiteralPath $historyRoot -Recurse -Force }
}

Write-Host 'Location history adapter tests passed.'

$ErrorActionPreference='Stop'

$adapterPath=Join-Path $PSScriptRoot 'lib/history/location-history-adapter.ps1'
$genericComparatorPath=Join-Path $PSScriptRoot 'lib/history/compare-history-observations.ps1'
$comparatorPath=Join-Path $PSScriptRoot 'lib/history/compare-location-history.ps1'
if(-not (Test-Path -LiteralPath $adapterPath)){throw 'Location history adapter is missing'}
if(-not (Test-Path -LiteralPath $comparatorPath)){throw 'Location history comparator is missing'}
. $adapterPath
. $genericComparatorPath
. $comparatorPath

function Assert-True { param([bool]$Condition,[string]$Message);if(-not $Condition){throw $Message} }
function Assert-Equal { param($Actual,$Expected,[string]$Message);if($Actual -cne $Expected){throw "$Message (expected: $Expected, actual: $Actual)"} }
function Assert-NotEqual { param($Actual,$Expected,[string]$Message);if($Actual -ceq $Expected){throw $Message} }
function Assert-Throws { param([scriptblock]$Action,[string]$Message);try { & $Action } catch { return };throw $Message }
function Assert-Sequence { param([object[]]$Actual,[object[]]$Expected,[string]$Message);if((@($Actual) -join '|') -cne (@($Expected) -join '|')){throw "$Message (expected: $(@($Expected) -join ','), actual: $(@($Actual) -join ','))"} }

$businessId='biz-0123456789abcdef0123456789abcdef'
$revision=('a'*40)

function New-TestLocationBusiness {
    param([hashtable]$Overrides=@{})
    $values=[ordered]@{SourceRowNumber=2;OriginalName='테스트 식당';NormalizedName='테스트식당';BaseName='테스트 식당';BranchName='양주점';OriginalRoadAddress='경기도 양주시 테스트로 10';OriginalLotAddress='경기도 양주시 테스트동 10';PreferredAddress='경기도 양주시 테스트로 10';Province='경기도';City='양주시';District='';Dong='테스트동';RoadName='테스트로';BuildingMain='10';BuildingSub='';Floor='';Unit='';AddressParseStatus='COMPLETE';NormalizationWarnings=@()}
    foreach($key in $Overrides.Keys){$values[$key]=$Overrides[$key]}
    return New-NormalizedBusiness @values
}
function New-TestLocationDiscovery {
    param([hashtable]$Overrides=@{})
    $values=[ordered]@{StrategyCode='NAME_FULL_ADDRESS';Query='테스트 식당 경기도 양주시 테스트로 10';QueryOrder=1;ResultPosition=1;ResultCount=1}
    foreach($key in $Overrides.Keys){$values[$key]=$Overrides[$key]}
    return New-PoiDiscoveryEvidence @values
}
function New-TestLocationCandidate {
    param([hashtable]$Overrides=@{})
    $values=[ordered]@{CandidateKey='naver-1';Provider='NAVER_API_HUB_LOCAL';OriginalName='테스트 식당 양주점';NormalizedName='테스트식당양주점';RoadAddress='경기도 양주시 테스트로 10';LotAddress='경기도 양주시 테스트동 10';Latitude=[double]37.123456;Longitude=[double]127.123456;Phone='031-0000-0010';Category='음식점';ProviderLink='https://map.example/1';DiscoveredBy=@((New-TestLocationDiscovery))}
    foreach($key in $Overrides.Keys){$values[$key]=$Overrides[$key]}
    return New-PoiCandidate @values
}
function New-TestLocationBatch {
    param([hashtable]$Overrides=@{})
    $attempt=New-PoiQueryAttempt -StrategyCode 'NAME_FULL_ADDRESS' -Query '테스트 식당 경기도 양주시 테스트로 10' -QueryOrder 1 -Status SUCCESS -ResultCount 1
    $values=[ordered]@{SourceRowNumber=2;Status='COMPLETE';Candidates=@((New-TestLocationCandidate));QueryAttempts=@($attempt)}
    foreach($key in $Overrides.Keys){$values[$key]=$Overrides[$key]}
    return New-PoiDiscoveryBatch @values
}
function New-TestLocationResult {
    param([hashtable]$Overrides=@{})
    $candidate=New-TestLocationCandidate
    $values=[ordered]@{SourceRowNumber=2;EvaluationStatus='COMPLETE';Classification='GREEN';SelectedCandidate=$candidate;RankedCandidateKeys=@($candidate.CandidateKey);ReasonCodes=@('SINGLE_STRONG_CANDIDATE');ConflictCodes=@();Evidence=@();EvaluatedCandidateCount=1;SurvivingCandidateCount=1;ProductionAction='NONE'}
    foreach($key in $Overrides.Keys){$values[$key]=$Overrides[$key]}
    return New-PoiMatchResult @values
}
function New-TestLocationPackage {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)][string]$RunId,
        [AllowNull()]$BusinessOverride=$null,
        [AllowNull()]$BatchOverride=$null,
        [AllowNull()]$ResultOverride=$null,
        [string]$RepositoryRevision=$revision
    )
    $business=if($null -eq $BusinessOverride){New-TestLocationBusiness}else{$BusinessOverride}
    $batch=if($null -eq $BatchOverride){New-TestLocationBatch}else{$BatchOverride}
    $result=if($null -eq $ResultOverride){New-TestLocationResult}else{$ResultOverride}
    return New-LocationHistoryObservationPackage -Store $Store -RunId $RunId -BusinessId $businessId -ObservedAt '2026-09-27T00:00:00Z' -RepositoryRevision $RepositoryRevision -Business $business -DiscoveryBatch $batch -Result $result -ExecutionConfiguration ([pscustomobject]@{Mode='TEST'})
}
function Publish-TestLocationArtifacts {
    param([Parameter(Mandatory)]$Store,[Parameter(Mandatory)]$Package)
    foreach($artifact in @($Package.PreparedArtifacts)){
        [void](Write-HistoryArtifact -Store $Store -ContentHash $artifact.ContentHash -Extension $artifact.Extension -Text $artifact.Text)
    }
}
function New-TestNoneRedResult {
    return New-PoiMatchResult -SourceRowNumber 2 -EvaluationStatus COMPLETE -Classification RED -SelectedCandidate $null -RankedCandidateKeys @() -ReasonCodes @('NO_CANDIDATE') -ConflictCodes @() -Evidence @() -EvaluatedCandidateCount 0 -SurvivingCandidateCount 0 -ProductionAction NONE
}
function New-TestAmbiguousNoneResult {
    return New-PoiMatchResult -SourceRowNumber 2 -EvaluationStatus COMPLETE -Classification YELLOW -SelectedCandidate $null -RankedCandidateKeys @() -ReasonCodes @('MULTIPLE_PLAUSIBLE_CANDIDATES') -ConflictCodes @() -Evidence @() -EvaluatedCandidateCount 1 -SurvivingCandidateCount 1 -ProductionAction NONE
}

$root=Join-Path ([IO.Path]::GetTempPath()) ('milimap-location-comparator-' + [Guid]::NewGuid().ToString('N'))
try {
    $store=New-HistoryStoreLayout -Root $root
    $previous=New-TestLocationPackage -Store $store -RunId 'run-11111111111111111111111111111111'
    Publish-TestLocationArtifacts -Store $store -Package $previous

    $baseline=Compare-LocationHistoryObservations -Store $store -Previous $null -Current $previous.Observation
    Assert-Sequence $baseline.ChangeCandidates @('BASELINE_ESTABLISHED') 'No previous Location observation establishes a baseline'

    $failedCurrent=New-TestLocationPackage -Store $store -RunId 'run-22222222222222222222222222222222' -BatchOverride (New-TestLocationBatch -Overrides @{Status='FAILED'}) -ResultOverride (New-TestLocationResult -Overrides @{EvaluationStatus='INCOMPLETE';Classification='YELLOW'})
    $failedComparison=Compare-LocationHistoryObservations -Store $store -Previous $previous.Observation -Current $failedCurrent.Observation
    Assert-Equal $failedComparison.ComparisonStatus UNAVAILABLE 'Current failed Location observation is unavailable'
    Assert-Sequence $failedComparison.ChangeCandidates @('OPERATIONAL_FAILURE','COMPARISON_UNAVAILABLE') 'Common operational precedence is not overridden by Location resolution'

    $inputChangedBusiness=New-TestLocationBusiness -Overrides @{OriginalName='다른 식당';NormalizedName='다른식당';BaseName='다른 식당'}
    $inputChanged=New-TestLocationPackage -Store $store -RunId 'run-33333333333333333333333333333333' -BusinessOverride $inputChangedBusiness
    $inputComparison=Compare-LocationHistoryObservations -Store $store -Previous $previous.Observation -Current $inputChanged.Observation
    Assert-Sequence $inputComparison.ChangeCandidates @('CANONICAL_INPUT_CHANGED') 'Input precedence is not overridden by Location resolver'

    $executionChanged=New-TestLocationPackage -Store $store -RunId 'run-44444444444444444444444444444444' -RepositoryRevision ('b'*40)
    $executionComparison=Compare-LocationHistoryObservations -Store $store -Previous $previous.Observation -Current $executionChanged.Observation
    Assert-Sequence $executionComparison.ChangeCandidates @('PROCESSOR_OUTPUT_CHANGED') 'Execution precedence is not overridden by Location resolver'

    $providerOnlyBatch=New-TestLocationBatch -Overrides @{Candidates=@((New-TestLocationCandidate -Overrides @{Phone='031-0000-9999';Category='카페';ProviderLink='https://map.example/changed'}))}
    $providerOnly=New-TestLocationPackage -Store $store -RunId 'run-55555555555555555555555555555555' -BatchOverride $providerOnlyBatch
    $providerComparison=Compare-LocationHistoryObservations -Store $store -Previous $previous.Observation -Current $providerOnly.Observation
    Assert-Sequence $providerComparison.ChangeCandidates @('EVIDENCE_CHANGE_ONLY') 'Provider-only evidence change remains generic evidence-only audit'
    Assert-True (@($providerComparison.ChangeCandidates) -notcontains 'LOCATION_CHANGE_SUSPECTED') 'Provider-only evidence change creates no Location candidate'

    $candidateKeyOnlyResult=New-TestLocationResult -Overrides @{SelectedCandidate=(New-TestLocationCandidate -Overrides @{CandidateKey='naver-other'});RankedCandidateKeys=@('naver-other')}
    $candidateKeyOnlyBatch=New-TestLocationBatch -Overrides @{Candidates=@((New-TestLocationCandidate -Overrides @{CandidateKey='naver-other'}))}
    $candidateKeyOnly=New-TestLocationPackage -Store $store -RunId 'run-66666666666666666666666666666666' -BatchOverride $candidateKeyOnlyBatch -ResultOverride $candidateKeyOnlyResult
    $candidateKeyComparison=Compare-LocationHistoryObservations -Store $store -Previous $previous.Observation -Current $candidateKeyOnly.Observation
    Assert-Equal @($candidateKeyComparison.ChangeCandidates).Count 0 'CandidateKey-only movement creates no Location candidate'

    $same=New-TestLocationPackage -Store $store -RunId 'run-77777777777777777777777777777777'
    $sameComparison=Compare-LocationHistoryObservations -Store $store -Previous $previous.Observation -Current $same.Observation
    Assert-Equal @($sameComparison.ChangeCandidates).Count 0 'Equivalent Location observations produce no change candidate'

    $nameResult=New-TestLocationResult -Overrides @{SelectedCandidate=(New-TestLocationCandidate -Overrides @{NormalizedName='다른식당양주점'})}
    $nameCurrent=New-TestLocationPackage -Store $store -RunId 'run-88888888888888888888888888888888' -ResultOverride $nameResult
    $nameComparison=Compare-LocationHistoryObservations -Store $store -Previous $previous.Observation -Current $nameCurrent.Observation -StagedCurrentSemanticProjection $nameCurrent.SemanticProjection
    Assert-Sequence $nameComparison.ChangeCandidates @('LOCATION_CHANGE_SUSPECTED') 'Selected normalized-name delta produces one Location candidate'
    Assert-Sequence $nameComparison.ReasonCodes @('LOCATION_NAME_CHANGED') 'Selected normalized-name delta has the name reason'

    $stagedValidatorScript=(Get-Command Get-InternalStagedLocationHistorySemanticProjection -CommandType Function).ScriptBlock
    $script:stagedValidatorCalls=0
    function Get-InternalStagedLocationHistorySemanticProjection {
        param([Parameter(Mandatory)]$Current,[Parameter(Mandatory)]$StagedCurrentSemanticProjection)
        $script:stagedValidatorCalls++
        return & $stagedValidatorScript @PSBoundParameters
    }
    try {
        $singleValidationCurrent=New-TestLocationPackage -Store $store -RunId 'run-81818181818181818181818181818181' -ResultOverride $nameResult
        $singleValidationComparison=Compare-LocationHistoryObservations -Store $store -Previous $previous.Observation -Current $singleValidationCurrent.Observation -StagedCurrentSemanticProjection $singleValidationCurrent.SemanticProjection
        Assert-Sequence $singleValidationComparison.ChangeCandidates @('LOCATION_CHANGE_SUSPECTED') 'Single-validation staged comparison retains material Location result'
        Assert-Equal $script:stagedValidatorCalls 1 'A staged semantic delta comparison validates/canonicalizes the current projection once'
    } finally {
        Set-Item -LiteralPath 'Function:\Get-InternalStagedLocationHistorySemanticProjection' -Value $stagedValidatorScript
    }

    $addressResult=New-TestLocationResult -Overrides @{SelectedCandidate=(New-TestLocationCandidate -Overrides @{RoadAddress='경기도 양주시 다른로 10';LotAddress='경기도 양주시 다른동 10'})}
    $addressCurrent=New-TestLocationPackage -Store $store -RunId 'run-99999999999999999999999999999999' -ResultOverride $addressResult
    $addressComparison=Compare-LocationHistoryObservations -Store $store -Previous $previous.Observation -Current $addressCurrent.Observation -StagedCurrentSemanticProjection $addressCurrent.SemanticProjection
    Assert-Sequence $addressComparison.ChangeCandidates @('LOCATION_CHANGE_SUSPECTED') 'Selected address delta produces one Location candidate'
    Assert-Sequence $addressComparison.ReasonCodes @('LOCATION_ADDRESS_CHANGED') 'Selected address delta has the address reason'

    $coordinateResult=New-TestLocationResult -Overrides @{SelectedCandidate=(New-TestLocationCandidate -Overrides @{Latitude=[double]37.999999;Longitude=[double]127.999999})}
    $coordinateCurrent=New-TestLocationPackage -Store $store -RunId 'run-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' -ResultOverride $coordinateResult
    $coordinateComparison=Compare-LocationHistoryObservations -Store $store -Previous $previous.Observation -Current $coordinateCurrent.Observation -StagedCurrentSemanticProjection $coordinateCurrent.SemanticProjection
    Assert-Sequence $coordinateComparison.ChangeCandidates @('LOCATION_CHANGE_SUSPECTED') 'Selected coordinate delta produces one Location candidate'
    Assert-Sequence $coordinateComparison.ReasonCodes @('LOCATION_COORDINATE_CHANGED') 'Selected coordinate delta has the coordinate reason'

    $allMaterialResult=New-TestLocationResult -Overrides @{SelectedCandidate=(New-TestLocationCandidate -Overrides @{NormalizedName='다른식당양주점';RoadAddress='경기도 양주시 다른로 10';LotAddress='경기도 양주시 다른동 10';Latitude=[double]37.999999;Longitude=[double]127.999999})}
    $allMaterialCurrent=New-TestLocationPackage -Store $store -RunId 'run-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' -ResultOverride $allMaterialResult
    $allMaterialComparison=Compare-LocationHistoryObservations -Store $store -Previous $previous.Observation -Current $allMaterialCurrent.Observation -StagedCurrentSemanticProjection $allMaterialCurrent.SemanticProjection
    Assert-Sequence $allMaterialComparison.ChangeCandidates @('LOCATION_CHANGE_SUSPECTED') 'Multiple material selected-location deltas produce one Location candidate'
    Assert-Sequence $allMaterialComparison.ReasonCodes @('LOCATION_NAME_CHANGED','LOCATION_ADDRESS_CHANGED','LOCATION_COORDINATE_CHANGED') 'Multiple material selected-location deltas retain fixed reason ordering'

    $absenceCurrent=New-TestLocationPackage -Store $store -RunId 'run-cccccccccccccccccccccccccccccccc' -BatchOverride (New-TestLocationBatch -Overrides @{Candidates=@()}) -ResultOverride (New-TestNoneRedResult)
    $absenceComparison=Compare-LocationHistoryObservations -Store $store -Previous $previous.Observation -Current $absenceCurrent.Observation -StagedCurrentSemanticProjection $absenceCurrent.SemanticProjection
    Assert-Sequence $absenceComparison.ChangeCandidates @('LOCATION_ABSENCE_SUSPECTED') 'Strict complete absence has its dedicated candidate only'
    Assert-Sequence $absenceComparison.ReasonCodes @('LOCATION_SELECTION_CHANGED','COMPLETE_NO_CANDIDATE') 'Strict complete absence has selection and complete-no-candidate reasons'
    Assert-True (@($absenceComparison.ChangeCandidates) -notcontains 'LOCATION_CHANGE_SUSPECTED') 'Strict absence must not duplicate the material Location change queue'

    $ambiguousCurrent=New-TestLocationPackage -Store $store -RunId 'run-dddddddddddddddddddddddddddddddd' -ResultOverride (New-TestAmbiguousNoneResult)
    $ambiguousComparison=Compare-LocationHistoryObservations -Store $store -Previous $previous.Observation -Current $ambiguousCurrent.Observation -StagedCurrentSemanticProjection $ambiguousCurrent.SemanticProjection
    Assert-Equal @($ambiguousComparison.ChangeCandidates).Count 0 'Selected-to-ambiguous NONE is selection-only, not a temporal Location candidate'
    Assert-Sequence $ambiguousComparison.ReasonCodes @('LOCATION_SELECTION_CHANGED','LOCATION_EVALUATION_CHANGED') 'Selected-to-ambiguous NONE preserves selection/evaluation audit reasons'

    $nonePrevious=New-TestLocationPackage -Store $store -RunId 'run-eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee' -BatchOverride (New-TestLocationBatch -Overrides @{Candidates=@()}) -ResultOverride (New-TestNoneRedResult)
    Publish-TestLocationArtifacts -Store $store -Package $nonePrevious
    $noneToSelected=New-TestLocationPackage -Store $store -RunId 'run-ffffffffffffffffffffffffffffffff'
    $noneToSelectedComparison=Compare-LocationHistoryObservations -Store $store -Previous $nonePrevious.Observation -Current $noneToSelected.Observation -StagedCurrentSemanticProjection $noneToSelected.SemanticProjection
    Assert-Equal @($noneToSelectedComparison.ChangeCandidates).Count 0 'NONE-to-selected is selection-only, not a temporal Location candidate'
    Assert-Sequence $noneToSelectedComparison.ReasonCodes @('LOCATION_SELECTION_CHANGED','LOCATION_EVALUATION_CHANGED') 'NONE-to-selected preserves selection/evaluation audit reasons'

    $noneYellow=New-TestLocationPackage -Store $store -RunId 'run-12121212121212121212121212121212' -BatchOverride (New-TestLocationBatch -Overrides @{Candidates=@()}) -ResultOverride (New-TestAmbiguousNoneResult)
    $noneYellowComparison=Compare-LocationHistoryObservations -Store $store -Previous $nonePrevious.Observation -Current $noneYellow.Observation -StagedCurrentSemanticProjection $noneYellow.SemanticProjection
    Assert-Equal @($noneYellowComparison.ChangeCandidates).Count 0 'NONE/RED-to-NONE/YELLOW is evaluation-only'
    Assert-Sequence $noneYellowComparison.ReasonCodes @('LOCATION_EVALUATION_CHANGED') 'NONE/RED-to-NONE/YELLOW has only evaluation audit reason'

    $reasonOnlyResult=New-TestLocationResult -Overrides @{ReasonCodes=@('MULTIPLE_PLAUSIBLE_CANDIDATES');ConflictCodes=@('BRANCH_CONFLICT')}
    $reasonOnlyCurrent=New-TestLocationPackage -Store $store -RunId 'run-13131313131313131313131313131313' -ResultOverride $reasonOnlyResult
    $reasonOnlyComparison=Compare-LocationHistoryObservations -Store $store -Previous $previous.Observation -Current $reasonOnlyCurrent.Observation -StagedCurrentSemanticProjection $reasonOnlyCurrent.SemanticProjection
    Assert-Equal @($reasonOnlyComparison.ChangeCandidates).Count 0 'Material reason/conflict-only delta creates no Location candidate'
    Assert-Sequence $reasonOnlyComparison.ReasonCodes @('LOCATION_EVALUATION_CHANGED') 'Material reason/conflict-only delta has evaluation audit reason'

    $storeBackedCurrent=New-TestLocationPackage -Store $store -RunId 'run-14141414141414141414141414141414' -ResultOverride $nameResult
    Publish-TestLocationArtifacts -Store $store -Package $storeBackedCurrent
    $storeBackedComparison=Compare-LocationHistoryObservations -Store $store -Previous $previous.Observation -Current $storeBackedCurrent.Observation
    Assert-Sequence $storeBackedComparison.ChangeCandidates @('LOCATION_CHANGE_SUSPECTED') 'Published current semantic artifact uses the strict store-backed reader'

    $tamperedStaged=$nameCurrent.SemanticProjection | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $tamperedStaged.SelectionStatus='NONE'
    Assert-Throws { Compare-LocationHistoryObservations -Store $store -Previous $previous.Observation -Current $nameCurrent.Observation -StagedCurrentSemanticProjection $tamperedStaged } 'Tampered staged current semantic projection fails closed'
    $unpublishedPreviousResult=New-TestLocationResult -Overrides @{SelectedCandidate=(New-TestLocationCandidate -Overrides @{NormalizedName='미발행이전식당양주점'})}
    $unpublishedPrevious=New-TestLocationPackage -Store $store -RunId 'run-15151515151515151515151515151515' -ResultOverride $unpublishedPreviousResult
    Assert-Throws { Compare-LocationHistoryObservations -Store $store -Previous $unpublishedPrevious.Observation -Current $nameCurrent.Observation -StagedCurrentSemanticProjection $nameCurrent.SemanticProjection } 'Previous unpublished semantic projection is never accepted'
} finally {
    if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force}
}

Write-Host 'Location history comparator tests passed.'

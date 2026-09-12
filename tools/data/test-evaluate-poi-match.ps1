$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/poi-verification-contracts.ps1')
$matcherLibraryPath = Join-Path $PSScriptRoot 'lib/poi-matching/evaluate-poi-match.ps1'
if (-not (Test-Path -LiteralPath $matcherLibraryPath)) { throw "POI matcher library does not exist: $matcherLibraryPath" }
. $matcherLibraryPath
if ($null -eq (Get-Command Invoke-PoiMatchEvaluation -ErrorAction SilentlyContinue)) { throw 'POI matcher must export Invoke-PoiMatchEvaluation' }

$script:assertionCount = 0
function Assert-Equal { param($Actual,$Expected,[string]$Message) $script:assertionCount++; if ($Actual -cne $Expected) { throw "$Message (expected: $Expected, actual: $Actual)" } }
function Assert-True { param([bool]$Condition,[string]$Message) $script:assertionCount++; if (-not $Condition) { throw $Message } }
function Assert-Throws { param([scriptblock]$Action,[string]$Message) $threw=$false; try { & $Action } catch { $threw=$true }; Assert-True $threw $Message }
function New-Business {
    param([int]$Row=101,[string]$Name='테스트 식당 본점',[string]$Base='테스트식당',[string]$Branch='본점',[string]$Province='경기도',[string]$City='양주시',[string]$District='',[string]$Dong='고암동',[string]$Road='테스트로',[string]$Main='22',[string]$Sub='25',[string]$Floor='2',[string]$Unit='201')
    $address="$Province $City $Dong $Road $Main"; if ($Sub) { $address += "-$Sub" }
    New-NormalizedBusiness -SourceRowNumber $Row -OriginalName $Name -NormalizedName ($Name -replace '\s','') -BaseName $Base -BranchName $Branch -OriginalRoadAddress $address -PreferredAddress $address -Province $Province -City $City -District $District -Dong $Dong -RoadName $Road -BuildingMain $Main -BuildingSub $Sub -Floor $Floor -Unit $Unit -AddressParseStatus 'COMPLETE'
}
function New-Evidence { param([int]$Order=1,[string]$Strategy='NAME_FULL_ADDRESS') New-PoiDiscoveryEvidence -StrategyCode $Strategy -Query "synthetic query $Order" -QueryOrder $Order -ResultPosition 1 -ResultCount 1 }
function New-Candidate {
    param([string]$Key='candidate-a',[string]$Name='테스트 식당 본점',[string]$Address='경기도 양주시 고암동 테스트로 22-25',[string]$LotAddress='경기도 양주시 고암동 1-1',[string]$Phone='031-000-0000',[object[]]$Evidence=@((New-Evidence)))
    # Fixed coordinates, phone, category, and link are synthetic contract-carrier fields, not source facts.
    New-PoiCandidate -CandidateKey $Key -OriginalName $Name -NormalizedName ($Name -replace '\s','') -RoadAddress $Address -LotAddress $LotAddress -Latitude ([double]37.8302) -Longitude ([double]127.0675) -Phone $Phone -Category '음식점' -ProviderLink 'https://example.invalid/place' -DiscoveredBy $Evidence
}
function New-Batch {
    param([int]$Row=101,[string]$Status='COMPLETE',[object[]]$Candidates=@())
    $attempt=New-PoiQueryAttempt -StrategyCode 'NAME_FULL_ADDRESS' -Query 'synthetic query 1' -QueryOrder 1 -Status 'SUCCESS' -ResultCount $Candidates.Count
    New-PoiDiscoveryBatch -SourceRowNumber $Row -Status $Status -Candidates $Candidates -QueryAttempts @($attempt)
}
function Assert-Result {
    param($Result,$Business,$Batch)
    Assert-PoiMatchResult $Result
    Assert-Equal $Result.SourceRowNumber $Business.SourceRowNumber 'Result preserves source row'
    Assert-Equal $Result.EvaluatedCandidateCount $Batch.Candidates.Count 'Every discovery candidate is evaluated'
    foreach ($code in @($Result.ReasonCodes)) { Assert-PoiAllowedCode 'Reason' $code }
    foreach ($code in @($Result.ConflictCodes)) { Assert-PoiAllowedCode 'Conflict' $code }
    foreach ($evidence in @($Result.Evidence)) { Assert-PoiMatchEvidence $evidence }
}
function Evaluate { param($Business,$Batch) Invoke-PoiMatchEvaluation -Business $Business -DiscoveryBatch $Batch }
function Assert-EvidenceCode {
    param($Result,[string]$Code,[string]$Message)
    $hasEvidence = @($Result.Evidence | Where-Object { $_.EvidenceCode -eq $Code }).Count -gt 0
    Assert-True $hasEvidence $Message
}
function Assert-HardConflict {
    param($Result,[string]$ConflictCode,[string]$Message)
    Assert-Equal $Result.EvaluationStatus 'COMPLETE' "$Message is conclusive"
    Assert-Equal $Result.Classification 'RED' "$Message is RED"
    Assert-Equal $Result.SelectedCandidate $null "$Message selects no candidate"
    Assert-True ($Result.Classification -ne 'GREEN') "$Message cannot be GREEN"
    $hasConflict = @($Result.ConflictCodes) -contains $ConflictCode
    Assert-True $hasConflict "$Message exposes exact conflict code"
    Assert-EvidenceCode $Result $ConflictCode "$Message keeps reviewable conflict evidence"
}

# The matcher output must use only contract codes and contract-valid evidence records.
Assert-PoiAllowedCode 'ProductionAction' 'NONE'
Assert-PoiMatchEvidence (New-PoiMatchEvidence -EvidenceCode 'BUILDING_NUMBER_MATCH' -CandidateKey 'candidate-a' -CanonicalValue '22' -CandidateValue '22' -Matched $true)
Assert-Throws { Assert-PoiMatchEvidence (New-PoiMatchEvidence -EvidenceCode 'UNDECLARED_EVIDENCE' -CandidateKey 'candidate-a') } 'Invalid match evidence code is rejected'

# A single independently evidenced candidate is GREEN; evaluation must never write production data.
$business=New-Business; $strong=New-Candidate -Key 'candidate-strong'; $strongBatch=New-Batch -Candidates @($strong); $green=Evaluate $business $strongBatch
Assert-Result $green $business $strongBatch
Assert-Equal $green.EvaluationStatus 'COMPLETE' 'Strong discovery completes evaluation'
Assert-Equal $green.Classification 'GREEN' 'Single strong candidate is GREEN'
Assert-Equal $green.ProductionAction 'NONE' 'Evaluation has no production action'
Assert-Equal $green.SelectedCandidate.CandidateKey 'candidate-strong' 'GREEN selects strong candidate'
Assert-Equal $green.RankedCandidateKeys[0] 'candidate-strong' 'Selected candidate is top ranked'
Assert-True (@($green.ReasonCodes) -contains 'SINGLE_STRONG_CANDIDATE') 'GREEN includes allowed reason'

$provinceAlias=New-Candidate -Key 'candidate-province-alias' -Address '경기 양주시 고암동 테스트로 22-25' -LotAddress ''
$provinceAliasBatch=New-Batch -Candidates @($provinceAlias); $provinceAliasResult=Evaluate $business $provinceAliasBatch
Assert-Result $provinceAliasResult $business $provinceAliasBatch
Assert-Equal $provinceAliasResult.Classification 'GREEN' 'Province alias 경기 is compatible with 경기도'

# Input contracts and source-row traceability are fail-closed; contract codes and evidence validators are public obligations.
Assert-Throws { Evaluate $business (New-Batch -Row 102 -Candidates @($strong)) } 'Mismatched source row is rejected'
$badBusiness=New-Business; $badBusiness.ContractVersion=2; Assert-Throws { Evaluate $badBusiness $strongBatch } 'Invalid business is rejected'
$badCandidate=New-Candidate -Key 'candidate-invalid-evidence'
$badCandidate.DiscoveredBy=@()
$badBatch=New-Batch -Candidates @($badCandidate); Assert-Throws { Evaluate $business $badBatch } 'Invalid candidate evidence is rejected'

# Complete zero results proves RED; PARTIAL or FAILED never proves absence and is INCOMPLETE YELLOW.
$empty=New-Batch; $red=Evaluate $business $empty; Assert-Result $red $business $empty
Assert-Equal $red.Classification 'RED' 'Complete zero-candidate batch is RED'
Assert-Equal $red.EvaluationStatus 'COMPLETE' 'No-candidate evidence is complete'
Assert-Equal $red.SelectedCandidate $null 'RED has no selected candidate'
Assert-True (@($red.ReasonCodes) -contains 'NO_CANDIDATE') 'RED records no-candidate reason'
foreach ($status in @('PARTIAL','FAILED')) {
    $batch=New-Batch -Status $status -Candidates @($strong); $yellow=Evaluate $business $batch; Assert-Result $yellow $business $batch
    Assert-Equal $yellow.EvaluationStatus 'INCOMPLETE' "$status cannot complete evaluation"
    Assert-Equal $yellow.Classification 'YELLOW' "$status must be YELLOW"
}

# Hard address conflict has precedence: compatible names cannot reverse a building mismatch.
$mismatch=New-Candidate -Key 'candidate-name-match-building-23' -Address '경기도 양주시 고암동 테스트로 23'
$mismatchBatch=New-Batch -Candidates @($mismatch); $mismatchResult=Evaluate $business $mismatchBatch; Assert-Result $mismatchResult $business $mismatchBatch
Assert-True ($mismatchResult.Classification -ne 'GREEN') 'Name compatibility cannot reverse building mismatch'
Assert-True (@($mismatchResult.ConflictCodes) -contains 'BUILDING_NUMBER_CONFLICT') 'Building conflict takes precedence'
$adjacentBuilding=New-Candidate -Key 'adjacent-building-conflict' -Address '경기도 양주시 고암동 테스트로22-26' -LotAddress '경기도 양주시 고암동 테스트로 22-25'
$adjacentBuildingBatch=New-Batch -Candidates @($adjacentBuilding); $adjacentBuildingResult=Evaluate $business $adjacentBuildingBatch
Assert-Result $adjacentBuildingResult $business $adjacentBuildingBatch
Assert-HardConflict $adjacentBuildingResult 'BUILDING_NUMBER_CONFLICT' 'Adjacent road-context building mismatch'
Assert-Equal $adjacentBuildingResult.SurvivingCandidateCount 0 'Adjacent building conflict removes candidate before ranking'
$numberedRoadBusiness=New-Business -Main '23' -Sub ''
$numberedRoadCandidate=New-Candidate -Key 'longer-numbered-road' -Address '경기도 양주시 고암동 테스트로23번길 10' -LotAddress ''
$numberedRoadBatch=New-Batch -Candidates @($numberedRoadCandidate); $numberedRoadResult=Evaluate $numberedRoadBusiness $numberedRoadBatch
Assert-Result $numberedRoadResult $numberedRoadBusiness $numberedRoadBatch
Assert-True (-not (@($numberedRoadResult.Evidence | Where-Object { $_.EvidenceCode -eq 'BUILDING_NUMBER_MATCH' }).Count -gt 0)) 'Digits inside a longer numbered road name are not a building match'
Assert-Equal $numberedRoadResult.Classification 'YELLOW' 'Longer numbered road name has insufficient identity evidence'
Assert-True (@($numberedRoadResult.ReasonCodes) -contains 'INSUFFICIENT_IDENTITY_EVIDENCE') 'Longer numbered road name records insufficient evidence'

# Every material, explicit identity conflict is conclusive even when the name and all remaining address detail are strong.
$provinceConflict=Evaluate $business (New-Batch -Candidates @((New-Candidate -Key 'province-conflict' -Address '서울특별시 양주시 고암동 테스트로 22-25')))
Assert-Result $provinceConflict $business (New-Batch -Candidates @((New-Candidate -Key 'province-conflict' -Address '서울특별시 양주시 고암동 테스트로 22-25')))
Assert-HardConflict $provinceConflict 'PROVINCE_CONFLICT' 'Name-compatible province conflict'
$splitProvinceCandidate=New-Candidate -Key 'split-province-conflict' -LotAddress '서울특별시 양주시 고암동 1-1'
$splitProvinceBatch=New-Batch -Candidates @($splitProvinceCandidate); $splitProvince=Evaluate $business $splitProvinceBatch
Assert-Result $splitProvince $business $splitProvinceBatch
Assert-HardConflict $splitProvince 'PROVINCE_CONFLICT' 'Conflicting preserved lot-address province'
$cityConflict=Evaluate $business (New-Batch -Candidates @((New-Candidate -Key 'city-conflict' -Address '경기도 파주시 고암동 테스트로 22-25')))
Assert-Result $cityConflict $business (New-Batch -Candidates @((New-Candidate -Key 'city-conflict' -Address '경기도 파주시 고암동 테스트로 22-25')))
Assert-HardConflict $cityConflict 'CITY_DISTRICT_CONFLICT' 'Name-compatible city conflict'
$gwangjuConflictCandidate=New-Candidate -Key 'gwangju-city-conflict' -Address '경기도 광주시 고암동 테스트로 22-25' -LotAddress '경기도 양주시 고암동 테스트로 22-25'
$gwangjuConflictBatch=New-Batch -Candidates @($gwangjuConflictCandidate); $gwangjuConflict=Evaluate $business $gwangjuConflictBatch
Assert-Result $gwangjuConflict $business $gwangjuConflictBatch
Assert-HardConflict $gwangjuConflict 'CITY_DISTRICT_CONFLICT' 'Gyeonggi Gwangju city conflict despite exact canonical lot address'
$gwangjuBusiness=New-Business -City '광주시'
$gwangjuCandidate=New-Candidate -Key 'gwangju-city-match' -Address '경기도 광주시 고암동 테스트로 22-25' -LotAddress ''
$gwangjuBatch=New-Batch -Candidates @($gwangjuCandidate); $gwangjuResult=Evaluate $gwangjuBusiness $gwangjuBatch
Assert-Result $gwangjuResult $gwangjuBusiness $gwangjuBatch
Assert-Equal $gwangjuResult.Classification 'GREEN' '경기도 광주시 remains a legitimate city match'
Assert-EvidenceCode $gwangjuResult 'LOCALITY_MATCH' '경기도 광주시 preserves positive locality evidence'
$branchConflict=Evaluate $business (New-Batch -Candidates @((New-Candidate -Key 'branch-conflict' -Name '테스트 식당 지점' -Address '경기도 양주시 고암동 테스트로 22-25')))
Assert-Result $branchConflict $business (New-Batch -Candidates @((New-Candidate -Key 'branch-conflict' -Name '테스트 식당 지점' -Address '경기도 양주시 고암동 테스트로 22-25')))
Assert-HardConflict $branchConflict 'BRANCH_CONFLICT' 'Name-compatible explicit branch conflict'
$floorConflict=Evaluate $business (New-Batch -Candidates @((New-Candidate -Key 'floor-unit-conflict' -Address '경기도 양주시 고암동 테스트로 22-25, 3층 301호')))
Assert-Result $floorConflict $business (New-Batch -Candidates @((New-Candidate -Key 'floor-unit-conflict' -Address '경기도 양주시 고암동 테스트로 22-25, 3층 301호')))
Assert-HardConflict $floorConflict 'FLOOR_UNIT_CONFLICT' 'Name-compatible explicit floor/unit conflict'

# data/canonical/capital-area-military-benefits.csv and
# data/canonical/reports/poi-coordinate-review-candidates-20260910-final.csv:
# 스컬스바버샵 preserves 1층 B-112호 on both canonical and POI road addresses.
$skullsBusiness=New-Business -Row 308 -Name '스컬스바버샵' -Base '스컬스바버샵' -Branch '' -City '시흥시' -Dong '' -Road '서울대학로264번길' -Main '12' -Sub '' -Floor '1' -Unit 'B-112'
$skullsAddress='경기도 시흥시 서울대학로264번길 12 208동 1층 B-112호'
$skullsLotAddress='경기도 시흥시 배곧동 221 208동 1층 B-112호'
$skullsMatchCandidate=New-Candidate -Key 'skulls-b-112' -Name '스컬스바버샵' -Address $skullsAddress -LotAddress $skullsLotAddress
$skullsMatchBatch=New-Batch -Row 308 -Candidates @($skullsMatchCandidate); $skullsMatch=Evaluate $skullsBusiness $skullsMatchBatch
Assert-Result $skullsMatch $skullsBusiness $skullsMatchBatch
Assert-Equal $skullsMatch.Classification 'GREEN' 'Alphanumeric B-112 unit preserves a single strong candidate'
Assert-True (-not (@($skullsMatch.ConflictCodes) -contains 'FLOOR_UNIT_CONFLICT')) 'Matching B-112 unit is not a floor/unit conflict'
Assert-EvidenceCode $skullsMatch 'FLOOR_UNIT_MATCH' 'Matching B-112 unit preserves floor/unit evidence'
$skullsMismatchCandidate=New-Candidate -Key 'skulls-b-113' -Name '스컬스바버샵' -Address ($skullsAddress -replace 'B-112호','B-113호') -LotAddress ($skullsLotAddress -replace 'B-112호','B-113호')
$skullsMismatchBatch=New-Batch -Row 308 -Candidates @($skullsMismatchCandidate); $skullsMismatch=Evaluate $skullsBusiness $skullsMismatchBatch
Assert-Result $skullsMismatch $skullsBusiness $skullsMismatchBatch
Assert-HardConflict $skullsMismatch 'FLOOR_UNIT_CONFLICT' 'Alphanumeric B-113 unit conflicts with canonical B-112'
$missingBranchCandidate=New-Candidate -Key 'missing-explicit-branch' -Name '테스트 식당' -LotAddress ''
$missingBranchBatch=New-Batch -Candidates @($missingBranchCandidate); $missingBranchResult=Evaluate $business $missingBranchBatch
Assert-Result $missingBranchResult $business $missingBranchBatch
$missingBranchEvidence=@($missingBranchResult.Evidence | Where-Object { $_.CandidateKey -eq 'missing-explicit-branch' -and $_.EvidenceCode -eq 'BRANCH_MATCH' })
Assert-Equal $missingBranchEvidence.Count 1 'Missing explicit candidate branch emits one review fact'
Assert-Equal $missingBranchEvidence[0].CanonicalValue '본점' 'Missing branch evidence preserves canonical branch'
Assert-Equal $missingBranchEvidence[0].CandidateValue '' 'Missing branch evidence preserves empty candidate value'
Assert-Equal $missingBranchEvidence[0].Matched $null 'Missing branch evidence is unavailable, not matched or conflicted'
Assert-True (-not (@($missingBranchResult.ReasonCodes) -contains 'BRANCH_MATCH')) 'Unavailable branch evidence adds no positive reason'
Assert-True (-not (@($missingBranchResult.ConflictCodes) -contains 'BRANCH_CONFLICT')) 'Missing candidate branch is not a conflict'

# CandidateKey ordering is deterministic reporting, not a tie breaker that can invent GREEN.
$tieA=New-Candidate -Key 'candidate-a' -Name '테스트 식당' -Address '경기도 양주시 고암동 테스트로 22-25'
$tieB=New-Candidate -Key 'candidate-b' -Name '테스트 식당' -Address '경기도 양주시 고암동 테스트로 22-25'
$tieBatch=New-Batch -Candidates @($tieB,$tieA); $tie=Evaluate $business $tieBatch; Assert-Result $tie $business $tieBatch
Assert-True ($tie.Classification -ne 'GREEN') 'Stable CandidateKey ordering cannot make evidence tie GREEN'
Assert-Equal (@($tie.RankedCandidateKeys) -join ',') 'candidate-a,candidate-b' 'Equal evidence keys sort deterministically'
Assert-Equal $tie.SelectedCandidate $null 'Tie has no selected candidate'
Assert-Equal $tie.EvaluationStatus 'COMPLETE' 'Equal plausible candidates complete evaluation'
Assert-Equal $tie.Classification 'YELLOW' 'Equal plausible candidates require review'
Assert-True (@($tie.ReasonCodes) -contains 'MULTIPLE_PLAUSIBLE_CANDIDATES') 'Equal plausible candidates use multiple-candidate reason'

$insufficient=New-Candidate -Key 'candidate-insufficient' -Address '' -LotAddress ''
$insufficientBatch=New-Batch -Candidates @($insufficient); $insufficientResult=Evaluate $business $insufficientBatch; Assert-Result $insufficientResult $business $insufficientBatch
Assert-Equal $insufficientResult.EvaluationStatus 'COMPLETE' 'Insufficient identity evidence still completes discovery evaluation'
Assert-Equal $insufficientResult.Classification 'YELLOW' 'Insufficient identity evidence requires review'
Assert-Equal $insufficientResult.SelectedCandidate $null 'Insufficient identity evidence selects no candidate'
Assert-True (@($insufficientResult.ReasonCodes) -contains 'INSUFFICIENT_IDENTITY_EVIDENCE') 'Insufficient identity has exact reason'

# Repeated independent discovery strengthens evidence and keeps candidate selection internally consistent.
$repeat=New-Candidate -Key 'candidate-repeated' -Evidence @((New-Evidence 1 'NAME_FULL_ADDRESS'),(New-Evidence 5 'BASE_NAME_LOCALITY'))
$repeatBatch=New-Batch -Candidates @($repeat)
$repeatBatch.QueryAttempts += New-PoiQueryAttempt -StrategyCode 'BASE_NAME_LOCALITY' -Query 'synthetic query 5' -QueryOrder 5 -Status 'SUCCESS' -ResultCount 1
$repeatResult=Evaluate $business $repeatBatch; Assert-Result $repeatResult $business $repeatBatch
Assert-Equal $repeatResult.SelectedCandidate.CandidateKey 'candidate-repeated' 'Repeated discovery preserves selected candidate'
Assert-True (@($repeatResult.ReasonCodes) -contains 'REPEATED_DISCOVERY') 'Repeated discovery is explicit evidence'
$failedRepeatBatch=New-Batch -Status 'PARTIAL' -Candidates @($repeat)
$failedRepeatBatch.QueryAttempts += New-PoiQueryAttempt -StrategyCode 'BASE_NAME_LOCALITY' -Query 'synthetic query 5' -QueryOrder 5 -Status 'FAILED'
$failedRepeatResult=Evaluate $business $failedRepeatBatch
Assert-True (-not (@($failedRepeatResult.ReasonCodes) -contains 'REPEATED_DISCOVERY')) 'Failed query attempts do not count as repeated discovery'

# Golden cases — repository-confirmed source facts only.
# New-Candidate's fixed coordinates/phone/category/link remain synthetic carriers unless a field is explicitly cited below.
# data/canonical/capital-area-military-benefits.csv: 버섯집 초리골 canonical 초리골길 12.
# data/canonical/reports/poi-coordinate-review-candidates-20260910-final.csv: POI 초리골길 23.
$mushroomBusiness=New-Business -Row 248 -Name '버섯집 초리골' -Base '버섯집초리골' -Branch '' -City '파주시' -Dong '법원읍' -Road '초리골길' -Main '12' -Sub '' -Floor '' -Unit ''
$mushroomBatch=New-Batch -Row 248 -Candidates @((New-Candidate -Key 'golden-mushroom-23' -Name '버섯집 초리골' -Address '경기 파주시 법원읍 초리골길 23' -LotAddress ''))
$mushroom=Evaluate $mushroomBusiness $mushroomBatch; Assert-Result $mushroom $mushroomBusiness $mushroomBatch
Assert-HardConflict $mushroom 'BUILDING_NUMBER_CONFLICT' 'Golden 버섯집 초리골 12 versus POI 23'
Assert-Equal (@($mushroom.ConflictCodes) -join ',') 'BUILDING_NUMBER_CONFLICT' 'Golden 버섯집 uses only report-supported conflict facts'

# data/canonical/reports/poi-coordinate-review-candidates-20260910-final.csv: 짜장마을 unresolved; fixture makes no full-POI-address claim.
$jajangBusiness=New-Business -Row 451 -Name '짜장마을' -Base '짜장마을' -Branch '' -City '파주시' -Dong '파주읍' -Road '술이홀로' -Main '463' -Sub '' -Floor '' -Unit ''
$jajangBatch=New-Batch -Row 451 -Candidates @((New-Candidate -Key 'golden-jajang-unresolved' -Name '짜장마을' -Address '' -LotAddress ''))
$jajang=Evaluate $jajangBusiness $jajangBatch; Assert-Result $jajang $jajangBusiness $jajangBatch
Assert-Equal $jajang.EvaluationStatus 'COMPLETE' 'Golden unresolved 짜장마을 completes evaluation'
Assert-Equal $jajang.Classification 'YELLOW' 'Golden unresolved 짜장마을 requires review'
Assert-Equal $jajang.SelectedCandidate $null 'Golden unresolved 짜장마을 selects no candidate'
Assert-True (@($jajang.ReasonCodes) -contains 'INSUFFICIENT_IDENTITY_EVIDENCE') 'Golden unresolved 짜장마을 has exact reason'
Assert-EvidenceCode $jajang 'NAME_EXACT' 'Golden unresolved 짜장마을 preserves name evidence'

# data/canonical/reports/poi-coordinate-review-candidates-20260910-p3.csv has no full POI address: minimal synthetic carrier of report-confirmed POI building number only (이지현미용실 26 vs 23).
$leeBusiness=New-Business -Row 135 -Name '이지현미용실' -Base '이지현미용실' -Branch '' -City '동두천시' -Dong '생연동' -Road '중앙로295번길' -Main '26' -Sub '' -Floor '' -Unit ''
$leeBatch=New-Batch -Row 135 -Candidates @((New-Candidate -Key 'golden-lee-23' -Name '이지현미용실' -Address '23' -LotAddress ''))
$lee=Evaluate $leeBusiness $leeBatch; Assert-Result $lee $leeBusiness $leeBatch
Assert-Equal $lee.EvaluationStatus 'COMPLETE' 'Golden 이지현미용실 completes evaluation'
Assert-Equal $lee.Classification 'YELLOW' 'Golden 이지현미용실 missing full POI address requires review'
Assert-Equal $lee.SelectedCandidate $null 'Golden 이지현미용실 selects no candidate'
Assert-True (@($lee.ReasonCodes) -contains 'INSUFFICIENT_IDENTITY_EVIDENCE') 'Golden 이지현미용실 has exact reason'
Assert-EvidenceCode $lee 'NAME_EXACT' 'Golden 이지현미용실 preserves reviewable name evidence'
# data/canonical/reports/poi-coordinate-review-candidates-20260910-p3.csv has no full POI address: minimal synthetic carrier of POI 904 only (인헤어 902·2동 104호 vs 904).
$inHairBusiness=New-Business -Row 136 -Name '인헤어' -Base '인헤어' -Branch '' -City '동두천시' -Dong '생연동' -Road '삼육사로' -Main '902' -Sub '' -Floor '' -Unit '104'
$inHairBatch=New-Batch -Row 136 -Candidates @((New-Candidate -Key 'golden-inhair-904' -Name '인헤어' -Address '904' -LotAddress ''))
$inHair=Evaluate $inHairBusiness $inHairBatch; Assert-Result $inHair $inHairBusiness $inHairBatch
Assert-Equal $inHair.EvaluationStatus 'COMPLETE' 'Golden 인헤어 completes evaluation'
Assert-Equal $inHair.Classification 'YELLOW' 'Golden 인헤어 missing full POI address requires review'
Assert-Equal $inHair.SelectedCandidate $null 'Golden 인헤어 selects no candidate'
Assert-True (@($inHair.ReasonCodes) -contains 'INSUFFICIENT_IDENTITY_EVIDENCE') 'Golden 인헤어 has exact reason'
Assert-EvidenceCode $inHair 'NAME_EXACT' 'Golden 인헤어 preserves reviewable name evidence'
$goldenRejectedOrAmbiguous=@($mushroom,$jajang,$lee,$inHair)
$goldenFalseGreenCount=@($goldenRejectedOrAmbiguous | Where-Object { $_.Classification -eq 'GREEN' }).Count
Assert-Equal $goldenFalseGreenCount 0 'Golden false-GREEN count is zero across four rejected/ambiguous cases'

# The reports preserve 거시기닭갈비 덕정본점 at 엄상동길 22-25 and lot address 고암동 157-6.
# They mention a phone suffix difference without preserving the candidate phone, so the helper phone remains synthetic and non-decisive.
$geosigiBusiness=New-Business -Row 339 -Name '거시기닭갈비' -Base '거시기닭갈비' -Branch '' -City '양주시' -Dong '' -Road '엄상동길' -Main '22' -Sub '25' -Floor '' -Unit ''
$geosigiBatch=New-Batch -Row 339 -Candidates @((New-Candidate -Key 'golden-geosigi' -Name '거시기닭갈비 덕정본점' -Address '경기도 양주시 엄상동길 22-25' -LotAddress '경기도 양주시 고암동 157-6'))
$geosigi=Evaluate $geosigiBusiness $geosigiBatch; Assert-Result $geosigi $geosigiBusiness $geosigiBatch
Assert-True (@($geosigi.ConflictCodes).Count -eq 0) 'Synthetic carrier phone is not a hard identity conflict'
Assert-True ($geosigi.Classification -ne 'RED') 'Location evidence is not reversed by a synthetic carrier phone'

$goldenFixtures=@(
    [pscustomobject]@{ Expected='negative'; Result=$mushroom },
    [pscustomobject]@{ Expected='ambiguous'; Result=$jajang },
    [pscustomobject]@{ Expected='negative'; Result=$lee },
    [pscustomobject]@{ Expected='negative'; Result=$inHair },
    [pscustomobject]@{ Expected='positive'; Result=$geosigi }
)
$goldenGreen=@($goldenFixtures | Where-Object { $_.Result.Classification -eq 'GREEN' })
$goldenCorrectGreen=@($goldenGreen | Where-Object { $_.Expected -eq 'positive' })
$goldenFalseGreen=@($goldenFixtures | Where-Object { $_.Expected -ne 'positive' -and $_.Result.Classification -eq 'GREEN' })
$goldenYellow=@($goldenFixtures | Where-Object { $_.Result.Classification -eq 'YELLOW' })
$goldenRed=@($goldenFixtures | Where-Object { $_.Result.Classification -eq 'RED' })
$goldenNoCandidate=@($goldenFixtures | Where-Object { $_.Result.EvaluatedCandidateCount -eq 0 })
$greenPrecision = if ($goldenGreen.Count -eq 0) { 'N/A' } else { '{0:P1}' -f ($goldenCorrectGreen.Count / $goldenGreen.Count) }
$manualReviewRate = '{0:P1}' -f ($goldenYellow.Count / $goldenFixtures.Count)
$noCandidateRate = '{0:P1}' -f ($goldenNoCandidate.Count / $goldenFixtures.Count)
Assert-Equal $goldenFalseGreen.Count 0 'Golden fixture metric false-GREEN count is zero'
Write-Host ("Golden matcher metrics: fixtures={0} (positive={1}, ambiguous={2}, negative={3}); GREEN={4}, YELLOW={5}, RED={6}; GREEN Precision={7}; false GREEN={8}; Manual Review Rate={9}; No-candidate count/rate={10}/{11}; C API calls/row=0." -f $goldenFixtures.Count, @($goldenFixtures | Where-Object Expected -eq 'positive').Count, @($goldenFixtures | Where-Object Expected -eq 'ambiguous').Count, @($goldenFixtures | Where-Object Expected -eq 'negative').Count, $goldenGreen.Count, $goldenYellow.Count, $goldenRed.Count, $greenPrecision, $goldenFalseGreen.Count, $manualReviewRate, $goldenNoCandidate.Count, $noCandidateRate)
Write-Host 'Candidate Recall: Not measured in Workstream C. Deferred to A/B/C Integration Shadow Mode.'
Write-Host "POI match evaluation tests passed ($script:assertionCount assertions)."

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
    param([int]$Row=101,[string]$Name='테스트 식당 본점',[string]$Base='테스트식당',[string]$Branch='본점',[string]$City='양주시',[string]$Dong='고암동',[string]$Road='테스트로',[string]$Main='22',[string]$Sub='25',[string]$Floor='2',[string]$Unit='201')
    $address="경기도 $City $Dong $Road $Main"; if ($Sub) { $address += "-$Sub" }
    New-NormalizedBusiness -SourceRowNumber $Row -OriginalName $Name -NormalizedName ($Name -replace '\s','') -BaseName $Base -BranchName $Branch -OriginalRoadAddress $address -PreferredAddress $address -Province '경기도' -City $City -Dong $Dong -RoadName $Road -BuildingMain $Main -BuildingSub $Sub -Floor $Floor -Unit $Unit -AddressParseStatus 'COMPLETE'
}
function New-Evidence { param([int]$Order=1,[string]$Strategy='NAME_FULL_ADDRESS') New-PoiDiscoveryEvidence -StrategyCode $Strategy -Query "synthetic query $Order" -QueryOrder $Order -ResultPosition 1 -ResultCount 1 }
function New-Candidate {
    param([string]$Key='candidate-a',[string]$Name='테스트 식당 본점',[string]$Address='경기도 양주시 고암동 테스트로 22-25',[string]$Phone='031-000-0000',[object[]]$Evidence=@((New-Evidence)))
    New-PoiCandidate -CandidateKey $Key -OriginalName $Name -NormalizedName ($Name -replace '\s','') -RoadAddress $Address -LotAddress '경기도 양주시 고암동 1-1' -Latitude ([double]37.8302) -Longitude ([double]127.0675) -Phone $Phone -Category '음식점' -ProviderLink 'https://example.invalid/place' -DiscoveredBy $Evidence
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

# Input contracts and source-row traceability are fail-closed; contract codes and evidence validators are public obligations.
Assert-Throws { Evaluate $business (New-Batch -Row 102 -Candidates @($strong)) } 'Mismatched source row is rejected'
$badBusiness=New-Business; $badBusiness.ContractVersion=2; Assert-Throws { Evaluate $badBusiness $strongBatch } 'Invalid business is rejected'
$badBatch=New-Batch -Candidates @($strong); $badBatch.Candidates[0].DiscoveredBy=@(); Assert-Throws { Evaluate $business $badBatch } 'Invalid candidate evidence is rejected'

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

# CandidateKey ordering is deterministic reporting, not a tie breaker that can invent GREEN.
$tieA=New-Candidate -Key 'candidate-a' -Name '테스트 식당' -Address '경기도 양주시 고암동 테스트로 22-25'
$tieB=New-Candidate -Key 'candidate-b' -Name '테스트 식당' -Address '경기도 양주시 고암동 테스트로 22-25'
$tieBatch=New-Batch -Candidates @($tieB,$tieA); $tie=Evaluate $business $tieBatch; Assert-Result $tie $business $tieBatch
Assert-True ($tie.Classification -ne 'GREEN') 'Stable CandidateKey ordering cannot make evidence tie GREEN'
Assert-Equal (@($tie.RankedCandidateKeys) -join ',') 'candidate-a,candidate-b' 'Equal evidence keys sort deterministically'
Assert-Equal $tie.SelectedCandidate $null 'Tie has no selected candidate'

# Repeated independent discovery strengthens evidence and keeps candidate selection internally consistent.
$repeat=New-Candidate -Key 'candidate-repeated' -Evidence @((New-Evidence 1 'NAME_FULL_ADDRESS'),(New-Evidence 5 'BASE_NAME_LOCALITY'))
$repeatBatch=New-Batch -Candidates @($repeat); $repeatResult=Evaluate $business $repeatBatch; Assert-Result $repeatResult $business $repeatBatch
Assert-Equal $repeatResult.SelectedCandidate.CandidateKey 'candidate-repeated' 'Repeated discovery preserves selected candidate'
Assert-True (@($repeatResult.ReasonCodes) -contains 'REPEATED_DISCOVERY') 'Repeated discovery is explicit evidence'

# Golden cases — repository-confirmed source facts only.
# canonical/capital-area-military-benefits.csv: 버섯집 초리골 canonical 초리골길 12.
# reports/poi-coordinate-review-candidates-20260910-final.csv: POI 초리골길 23.
$mushroom=Evaluate (New-Business -Row 248 -Name '버섯집 초리골' -Base '버섯집초리골' -Branch '' -City '파주시' -Dong '법원읍' -Road '초리골길' -Main '12' -Sub '' -Floor '' -Unit '') (New-Batch -Row 248 -Candidates @((New-Candidate -Key 'golden-mushroom-23' -Name '버섯집 초리골' -Address '경기도 파주시 법원읍 초리골길 23')))
Assert-True ($mushroom.Classification -ne 'GREEN') 'Golden 버섯집 초리골 12 versus POI 23 is not GREEN'

# final report: 짜장마을 unresolved; fixture makes no full-POI-address claim.
$jajang=Evaluate (New-Business -Row 451 -Name '짜장마을' -Base '짜장마을' -Branch '' -City '파주시' -Dong '파주읍' -Road '술이홀로' -Main '463' -Sub '' -Floor '' -Unit '') (New-Batch -Row 451 -Candidates @((New-Candidate -Key 'golden-jajang-unresolved' -Name '짜장마을' -Address '')))
Assert-True ($jajang.Classification -ne 'GREEN') 'Golden unresolved 짜장마을 is not GREEN'

# P3 has no full POI address: minimal synthetic carrier of report-confirmed POI building number only (이지현미용실 26 vs 23).
$lee=Evaluate (New-Business -Row 135 -Name '이지현미용실' -Base '이지현미용실' -Branch '' -City '동두천시' -Dong '생연동' -Road '중앙로295번길' -Main '26' -Sub '' -Floor '' -Unit '') (New-Batch -Row 135 -Candidates @((New-Candidate -Key 'golden-lee-23' -Name '이지현미용실' -Address '23')))
Assert-True ($lee.Classification -ne 'GREEN') 'Golden 이지현미용실 26 versus POI 23 is not GREEN'
# P3 has no full POI address: minimal synthetic carrier of POI 904 only (인헤어 902·2동 104호 vs 904).
$inHair=Evaluate (New-Business -Row 136 -Name '인헤어' -Base '인헤어' -Branch '' -City '동두천시' -Dong '생연동' -Road '삼육사로' -Main '902' -Sub '' -Floor '' -Unit '104') (New-Batch -Row 136 -Candidates @((New-Candidate -Key 'golden-inhair-904' -Name '인헤어' -Address '904')))
Assert-True ($inHair.Classification -ne 'GREEN') 'Golden 인헤어 902, 2동 104호 versus POI 904 is not GREEN'

# final/P3: 거시기닭갈비 덕정본점 at 엄상동길 22-25; a phone difference alone is not hard conflict.
$geosigiBusiness=New-Business -Row 339 -Name '거시기닭갈비' -Base '거시기닭갈비' -Branch '' -City '양주시' -Dong '' -Road '엄상동길' -Main '22' -Sub '25' -Floor '' -Unit ''
$geosigiBatch=New-Batch -Row 339 -Candidates @((New-Candidate -Key 'golden-geosigi' -Name '거시기닭갈비 덕정본점' -Address '경기도 양주시 엄상동길 22-25' -Phone '031-859-0000'))
$geosigi=Evaluate $geosigiBusiness $geosigiBatch; Assert-Result $geosigi $geosigiBusiness $geosigiBatch
Assert-True (@($geosigi.ConflictCodes).Count -eq 0) 'Phone discrepancy alone is not a hard conflict'
Assert-True ($geosigi.Classification -ne 'RED') 'Location evidence is not reversed by phone discrepancy'

Write-Host "POI match evaluation tests passed ($script:assertionCount assertions)."

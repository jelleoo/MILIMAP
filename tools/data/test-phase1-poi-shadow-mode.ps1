$ErrorActionPreference = 'Stop'

$runnerPath = Join-Path $PSScriptRoot 'invoke-phase1-poi-shadow-mode.ps1'
if (Test-Path -LiteralPath $runnerPath) { . $runnerPath }

$script:assertionCount = 0
function Assert-Equal {
    param([AllowNull()]$Actual, [AllowNull()]$Expected, [string]$Message)
    $script:assertionCount++
    if ($Actual -cne $Expected) { throw "$Message (expected: $Expected, actual: $Actual)" }
}
function Assert-True {
    param([bool]$Condition, [string]$Message)
    $script:assertionCount++
    if (-not $Condition) { throw $Message }
}

$singleStrongRow = [pscustomobject]@{
    업소명 = '테스트 식당 본점'
    시도 = '서울특별시'
    시군구 = '마포구'
    소재지도로명주소 = '서울특별시 마포구 테스트로 12-3, 2층 201호'
    소재지지번주소 = '서울특별시 마포구 테스트동 123'
}
$singleStrongItem = [pscustomobject]@{
    title = '<b>테스트</b> 식당 본점'
    roadAddress = '서울특별시 마포구 테스트로 12-3, 2층 201호'
    address = '서울특별시 마포구 테스트동 123'
    telephone = '02-000-0000'
    category = '음식점'
    link = 'https://example.invalid/fixture-strong'
    mapx = '1269012345'
    mapy = '375012345'
}
$singleStrongInvoker = { param($Uri, $Headers) [pscustomobject]@{ items=@($singleStrongItem) } }.GetNewClosure()

# Task 1: this call is intentionally RED until the Shadow runner exists.
$run = Invoke-Phase1PoiShadowMode -Rows @($singleStrongRow) -RequestInvoker $singleStrongInvoker
Assert-Equal $run.Rows.Count 1 'One input makes one report row'
Assert-Equal $run.Rows[0].SourceRowNumber 2 'Source row survives A B C'
Assert-Equal $run.Rows[0].DiscoveryStatus 'COMPLETE' 'Single mocked provider succeeds'
Assert-Equal $run.Rows[0].Classification 'GREEN' 'Single strong candidate can be GREEN'
Assert-Equal $run.Rows[0].ProductionAction 'NONE' 'No production action'
Assert-Equal $run.Rows[0].SelectedCandidateName '테스트 식당 본점' 'Selected provider candidate is reviewable'

# Task 2: the runner must retain B/C's distinction between complete negative
# evidence and incomplete provider evidence without translating Contract codes.
$zero = Invoke-Phase1PoiShadowMode -Rows @($singleStrongRow) -RequestInvoker { param($Uri, $Headers) @{ items=@() } }
Assert-Equal $zero.Rows[0].CandidateCount 0 'Successful zero has no candidates'
Assert-Equal $zero.Rows[0].QueryAttemptCount 5 'Successful zero records provider work'
Assert-Equal $zero.Rows[0].EvaluationStatus 'COMPLETE' 'Successful zero completes evaluation'
Assert-Equal $zero.Rows[0].Classification 'RED' 'Successful zero is conclusive RED'
Assert-True ($zero.Rows[0].ReasonCodes -contains 'NO_CANDIDATE') 'Successful zero retains no-candidate reason'

$partialCalls = [Collections.Generic.List[object]]::new()
$partialInvoker = {
    param($Uri, $Headers)
    $partialCalls.Add($Uri)
    if ($partialCalls.Count -eq 2) { throw 'fixture timeout' }
    [pscustomobject]@{ items=@($singleStrongItem) }
}.GetNewClosure()
$partial = Invoke-Phase1PoiShadowMode -Rows @($singleStrongRow) -RequestInvoker $partialInvoker
Assert-Equal $partial.Rows[0].DiscoveryStatus 'PARTIAL' 'Mixed provider result is partial'
Assert-Equal $partial.Rows[0].EvaluationStatus 'INCOMPLETE' 'Partial discovery is incomplete'
Assert-Equal $partial.Rows[0].Classification 'YELLOW' 'Partial discovery is YELLOW'
Assert-True ($partial.Rows[0].ReasonCodes -contains 'DISCOVERY_PARTIAL_FAILURE') 'Partial reason remains reviewable'
Assert-True (-not ($partial.Rows[0].ReasonCodes -contains 'NO_CANDIDATE')) 'Partial is never collapsed to no-candidate'

$failed = Invoke-Phase1PoiShadowMode -Rows @($singleStrongRow) -RequestInvoker { param($Uri, $Headers) throw 'fixture timeout' }
Assert-Equal $failed.Rows[0].DiscoveryStatus 'FAILED' 'Provider exception remains failure'
Assert-Equal $failed.Rows[0].CandidateCount 0 'Failed discovery has no usable candidates'
Assert-Equal $failed.Rows[0].EvaluationStatus 'INCOMPLETE' 'Failure is incomplete'
Assert-Equal $failed.Rows[0].Classification 'YELLOW' 'Failure cannot become RED'
Assert-True ($failed.Rows[0].ReasonCodes -contains 'DISCOVERY_FAILED') 'Failure reason remains reviewable'
Assert-True (-not ($failed.Rows[0].ReasonCodes -contains 'NO_CANDIDATE')) 'Failure is not no-candidate'

$secondStrongItem = [pscustomobject]@{
    title = '테스트 식당 본점'; roadAddress = '서울특별시 마포구 테스트로 12-3, 2층 201호'; address = '서울특별시 마포구 테스트동 123'
    telephone = '02-000-0001'; category = '음식점'; link = 'https://example.invalid/fixture-second'; mapx = '1269012345'; mapy = '375012345'
}
$multiple = Invoke-Phase1PoiShadowMode -Rows @($singleStrongRow) -RequestInvoker { param($Uri, $Headers) [pscustomobject]@{ items=@($singleStrongItem, $secondStrongItem) } }
Assert-Equal $multiple.Rows[0].DiscoveryStatus 'COMPLETE' 'Multiple successful candidates complete discovery'
Assert-Equal $multiple.Rows[0].CandidateCount 2 'Distinct provider observations remain distinct candidates'
Assert-Equal $multiple.Rows[0].EvaluationStatus 'COMPLETE' 'Multiple candidates are fully evaluated'
Assert-Equal $multiple.Rows[0].Classification 'YELLOW' 'Multiple plausible candidates are not GREEN'
Assert-True ($multiple.Rows[0].ReasonCodes -contains 'MULTIPLE_PLAUSIBLE_CANDIDATES') 'Multiplicity reason remains reviewable'
Assert-Equal $multiple.Rows[0].SelectedCandidateKey '' 'Multiple candidates select no production candidate'

Write-Host "Phase 1 Shadow Mode tests passed ($script:assertionCount assertions)."

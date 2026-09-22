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

Write-Host "Phase 1 Shadow Mode tests passed ($script:assertionCount assertions)."

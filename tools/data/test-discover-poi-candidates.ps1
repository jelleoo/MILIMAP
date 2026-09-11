$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/poi-discovery/discover-poi-candidates.ps1')

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
function Assert-Throws {
    param([scriptblock]$Action, [string]$Message)
    $threw = $false
    try { & $Action } catch { $threw = $true }
    Assert-True $threw $Message
}
function New-DiscoveryBusinessFixture {
    # Entirely synthetic contract fixture. Never invokes Workstream A.
    New-NormalizedBusiness -SourceRowNumber 7 -OriginalName '테스트 카페 홍대점' -NormalizedName '테스트카페홍대점' `
        -BaseName '테스트카페' -BranchName '홍대점' -OriginalRoadAddress '서울특별시 마포구 테스트로 12-3, 2층 201호' `
        -PreferredAddress '서울특별시 마포구 테스트로 12-3, 2층 201호' -Province '서울특별시' -District '마포구' `
        -Dong '테스트동' -RoadName '테스트로' -BuildingMain '12' -BuildingSub '3' -Floor '2' -Unit '201' -AddressParseStatus 'COMPLETE'
}
function New-DiscoveryPoiFixture {
    param([string]$Name='테스트 카페 홍대점', [string]$Road='서울특별시 마포구 테스트로 12-3, 2층 201호')
    [pscustomobject]@{ title=$Name; roadAddress=$Road; address='서울특별시 마포구 테스트동 123';
        telephone='02-000-0000'; category='카페,디저트>카페'; link='https://example.invalid/shared-home';
        mapx='1269012345'; mapy='375012345' }
}
function Assert-ValidDiscoveryBatch {
    param($Batch)
    Assert-PoiDiscoveryBatch $Batch
    Assert-True ($Batch.Candidates -is [array]) 'Candidates must always be an array'
    Assert-True ($Batch.QueryAttempts -is [array]) 'QueryAttempts must always be an array'
    foreach ($candidate in $Batch.Candidates) {
        Assert-PoiCandidate $candidate
        foreach ($evidence in $candidate.DiscoveredBy) {
            $attempt = @($Batch.QueryAttempts | Where-Object { $_.QueryOrder -eq $evidence.QueryOrder })
            Assert-Equal $attempt.Count 1 'Evidence must resolve to exactly one attempt'
            Assert-Equal $attempt[0].Status 'SUCCESS' 'Only successful results generate evidence'
            Assert-Equal $attempt[0].Query $evidence.Query 'Evidence query must be traceable'
            Assert-Equal $attempt[0].StrategyCode $evidence.StrategyCode 'Evidence strategy must be traceable'
            Assert-Equal $attempt[0].ResultCount $evidence.ResultCount 'Evidence retains raw result count before dedup'
        }
    }
}

$business = New-DiscoveryBusinessFixture
$before = $business | ConvertTo-Json -Depth 8 -Compress
$plan = @(Get-PoiDiscoveryQueryPlan $business)
Assert-Equal $plan.Count 5 'Complete fixture enables five strategies'
$expectedQueries = @(
    '테스트 카페 홍대점 서울특별시 마포구 테스트로 12-3, 2층 201호',
    '테스트 카페 홍대점 서울특별시 마포구 테스트로 12-3',
    '테스트 카페 홍대점 서울특별시 마포구 테스트동 테스트로',
    '테스트카페 서울특별시 마포구 테스트로 12-3',
    '테스트카페 서울특별시 마포구 테스트동'
)
$strategies = (Get-PoiVerificationContractDefinition).QueryStrategy
for ($index = 0; $index -lt 5; $index++) {
    Assert-Equal $plan[$index].StrategyCode $strategies[$index] 'Strict-to-broad contract order'
    Assert-Equal $plan[$index].Query $expectedQueries[$index] 'Queries only compose supplied fields'
    Assert-Equal $plan[$index].QueryOrder ($index + 1) 'Orders are one-based'
}
Assert-Equal (($plan | ConvertTo-Json -Compress)) ((@(Get-PoiDiscoveryQueryPlan $business) | ConvertTo-Json -Compress)) 'Query plan is deterministic'

# Two POIs, exact duplicates across/within queries, first result deliberately weak.
$weak = New-DiscoveryPoiFixture -Name '다른 카페' -Road '경기도 파주시 다른로 999'
$strong = New-DiscoveryPoiFixture -Name '<b>테스트</b> 카페 홍대점'
$calls = [Collections.Generic.List[object]]::new()
$invoker = {
    param($Uri, $Headers)
    $calls.Add([pscustomobject]@{ Uri=$Uri; Headers=$Headers })
    if ($calls.Count -eq 1) { return [pscustomobject]@{ items=@($weak) } }
    if ($calls.Count -eq 2) { return [pscustomobject]@{ items=@($weak, $strong, $strong) } }
    [pscustomobject]@{ items=@($strong) }
}.GetNewClosure()
$batch = Invoke-PoiDiscovery -Business $business -ClientId 'fixture-id' -ClientSecret 'fixture-secret' -RequestInvoker $invoker
Assert-ValidDiscoveryBatch $batch
Assert-Equal $batch.Status 'COMPLETE' 'All successful queries complete discovery'
Assert-Equal $batch.SourceRowNumber 7 'Source row survives'
Assert-Equal $calls.Count 5 'Nonempty weak first result must not stop exploration'
Assert-Equal $batch.Candidates.Count 2 'Exact observations deduplicate in first-seen order'
Assert-Equal $batch.Candidates[0].OriginalName '다른 카페' 'B does not rank or drop conflicting candidates'
Assert-Equal $batch.Candidates[1].OriginalName '테스트 카페 홍대점' 'Highlight tags removed without losing branch name'
Assert-Equal $batch.Candidates[1].NormalizedName '테스트카페홍대점' 'Provider comparison form deterministic'
Assert-Equal $batch.Candidates[0].DiscoveredBy.Count 2 'All weak candidate evidence remains'
Assert-Equal $batch.Candidates[1].DiscoveredBy.Count 5 'Repeated same-query positions and later queries remain'
Assert-Equal $batch.Candidates[1].DiscoveredBy[0].ResultPosition 2 'Original result position remains'
Assert-Equal $batch.Candidates[1].DiscoveredBy[1].ResultPosition 3 'Duplicate item evidence not discarded'
Assert-Equal $batch.Candidates[1].Latitude ([double]37.5012345) 'mapy decodes to latitude'
Assert-Equal $batch.Candidates[1].Longitude ([double]126.9012345) 'mapx decodes to longitude'
Assert-True ($batch.Candidates[1].Latitude -is [double]) 'Coordinates use double, not strings'
Assert-Equal $batch.Candidates[1].RoadAddress $strong.roadAddress 'Road address and floor are preserved'
Assert-Equal $batch.Candidates[1].LotAddress $strong.address 'Lot address is preserved'
Assert-Equal $batch.Candidates[1].Phone $strong.telephone 'Phone evidence is preserved when returned'
Assert-Equal $batch.Candidates[1].Category $strong.category 'Category is preserved'
Assert-Equal $batch.Candidates[1].ProviderLink $strong.link 'Provider link is not a synthesized search URL'
Assert-Equal $calls[0].Headers['X-NCP-APIGW-API-KEY-ID'] 'fixture-id' 'API HUB ID header'
Assert-Equal $calls[0].Headers['X-NCP-APIGW-API-KEY'] 'fixture-secret' 'API HUB secret header'
Assert-True ($calls[0].Uri.StartsWith('https://naverapihub.apigw.ntruss.com/search/v1/local?display=5&start=1&sort=random&format=json&query=')) 'Official API HUB endpoint and bounded request'
Assert-True ($calls[0].Uri.EndsWith([Uri]::EscapeDataString($expectedQueries[0]))) 'Query is UTF-8 URI encoded'
Assert-True (-not (($batch | ConvertTo-Json -Depth 10) -match 'fixture-secret|fixture-id')) 'Credentials never enter outputs'
Assert-Equal ($business | ConvertTo-Json -Depth 8 -Compress) $before 'Discovery does not mutate input'

# Successful zero is distinct from failure; dictionaries and PSCustomObjects work.
$empty = Invoke-PoiDiscovery $business -RequestInvoker { @{ items=@() } }
Assert-ValidDiscoveryBatch $empty
Assert-Equal $empty.Status 'COMPLETE' 'Genuine empty arrays are successful'
Assert-Equal $empty.Candidates.Count 0 'Complete empty batch has zero candidates'
Assert-Equal @($empty.QueryAttempts | Where-Object Status -eq 'SUCCESS').Count 5 'All empty searches recorded'
$emptyObject = Invoke-PoiDiscovery $business -RequestInvoker { [pscustomobject]@{ items=@() } }
Assert-Equal $emptyObject.Status 'COMPLETE' 'Empty PSCustomObject arrays must not collapse to null'

$counter = [Collections.Generic.List[int]]::new()
$partialInvoker = {
    param($Uri, $Headers)
    $counter.Add(1)
    if ($counter.Count -eq 2) { throw 'private-token-do-not-output' }
    [pscustomobject]@{ items=@($strong) }
}.GetNewClosure()
$partial = Invoke-PoiDiscovery $business -RequestInvoker $partialInvoker
Assert-ValidDiscoveryBatch $partial
Assert-Equal $partial.Status 'PARTIAL' 'Successful results and request failure mean partial'
Assert-Equal $counter.Count 5 'Failure does not stop later eligible queries'
Assert-Equal $partial.Candidates.Count 1 'Successful candidates retained across a failure'
Assert-Equal $partial.Candidates[0].DiscoveredBy.Count 4 'Only successful query evidence retained'
Assert-Equal $partial.QueryAttempts[1].ErrorCode 'REQUEST_FAILED' 'Transport error has safe code'
Assert-Equal $partial.QueryAttempts[1].ResultCount 0 'Failed attempt contract count is zero'
Assert-True (-not (($partial | ConvertTo-Json -Depth 10) -match 'private-token')) 'Exception text must not leak'
$failed = Invoke-PoiDiscovery $business -RequestInvoker { throw 'timeout-or-429' }
Assert-ValidDiscoveryBatch $failed
Assert-Equal $failed.Status 'FAILED' 'All request failures cannot become no-candidate evidence'
Assert-Equal @($failed.QueryAttempts | Where-Object Status -eq 'FAILED').Count 5 'Every failed attempt remains'
$zeroCounter = [Collections.Generic.List[int]]::new()
$zeroPartial = Invoke-PoiDiscovery $business -RequestInvoker {
    $zeroCounter.Add(1)
    if ($zeroCounter.Count -eq 1) { return @{ items=@() } }
    throw 'timeout'
}.GetNewClosure()
Assert-Equal $zeroPartial.Status 'PARTIAL' 'One successful zero query still means partial, not complete'

# Duplicate queries use no extra calls and never fabricate repeated-discovery evidence.
$duplicateBusiness = New-DiscoveryBusinessFixture
$duplicateBusiness.BaseName = $duplicateBusiness.OriginalName
$duplicateBusiness.OriginalRoadAddress = '서울특별시 마포구 테스트로 12-3'
$duplicateBusiness.PreferredAddress = $duplicateBusiness.OriginalRoadAddress
$duplicateCalls = [Collections.Generic.List[int]]::new()
$deduplicated = Invoke-PoiDiscovery $duplicateBusiness -RequestInvoker {
    $duplicateCalls.Add(1)
    @{ items=@($strong) }
}.GetNewClosure()
Assert-ValidDiscoveryBatch $deduplicated
Assert-Equal $duplicateCalls.Count 3 'Three unique queries, not five network calls'
Assert-Equal $deduplicated.QueryAttempts.Count 5 'Skipped queries remain in trace'
Assert-Equal @($deduplicated.QueryAttempts | Where-Object Status -eq 'SKIPPED').Count 2 'Two duplicate strategies skipped'
Assert-Equal $deduplicated.QueryAttempts[1].ErrorCode 'DUPLICATE_QUERY' 'Skip reason is explicit'
Assert-Equal $deduplicated.Candidates[0].DiscoveredBy.Count 3 'No invented evidence from skipped strategies'
$duplicateFailure = Invoke-PoiDiscovery $duplicateBusiness -RequestInvoker { throw 'failed' }
Assert-Equal $duplicateFailure.Status 'FAILED' 'Skipped duplicates cannot disguise failures'

# Partial input is not reparsed by B. No sensible query is FAILED, not successful empty.
$lotOnly = New-NormalizedBusiness -SourceRowNumber 2 -OriginalName '테스트 상점' -OriginalLotAddress '경기도 파주시 테스트리 11' -PreferredAddress '경기도 파주시 테스트리 11'
Assert-Equal @(Get-PoiDiscoveryQueryPlan $lotOnly).Count 1 'Unparsed lot-only input uses full original address only'
$missing = New-NormalizedBusiness -SourceRowNumber 2
$noPlan = Invoke-PoiDiscovery $missing -RequestInvoker { throw 'Must not be invoked' }
Assert-ValidDiscoveryBatch $noPlan
Assert-Equal $noPlan.Status 'FAILED' 'No executable plan is not proof of no results'
Assert-Equal $noPlan.QueryAttempts.Count 0 'No fictitious query placeholders'
$partialAddress = New-NormalizedBusiness -SourceRowNumber 3 -BaseName '테스트상점' -Province '경기도' -City '파주시' -Dong '테스트동' -AddressParseStatus 'PARTIAL'
$partialPlan = @(Get-PoiDiscoveryQueryPlan $partialAddress)
Assert-Equal $partialPlan.Count 1 'Base/locality works without inventing street components'
Assert-Equal $partialPlan[0].Query '테스트상점 경기도 파주시 테스트동' 'Supplied city and dong are included'
Assert-Equal $partialPlan[0].StrategyCode 'BASE_NAME_LOCALITY' 'Allowed fallback code'
Assert-Throws { Invoke-PoiDiscovery ([pscustomobject]@{ SourceRowNumber=2 }) -RequestInvoker { @{items=@()} } } 'Incomplete contracts rejected before network'
$badBusiness = New-DiscoveryBusinessFixture
$badBusiness.ContractVersion = 2
Assert-Throws { Invoke-PoiDiscovery $badBusiness -RequestInvoker { @{items=@()} } } 'Wrong contract version rejected'
Assert-Throws { Invoke-PoiDiscovery $business -ClientId '' -ClientSecret '' } 'Live path needs API HUB credentials before sending'

# Strict malformed-response validation: no silent HTTP-200 error or [] coercion.
foreach ($response in @(
    [pscustomobject]@{}, [pscustomobject]@{items=$null}, [pscustomobject]@{items='bad'},
    [pscustomobject]@{items=$strong}, [pscustomobject]@{items=@($null)},
    [pscustomobject]@{items=@('bad')}, [pscustomobject]@{items=@([pscustomobject]@{})},
    [pscustomobject]@{items=@($strong,$strong,$strong,$strong,$strong,$strong)}
)) {
    $malformed = Invoke-PoiDiscovery $lotOnly -RequestInvoker { $response }.GetNewClosure()
    Assert-ValidDiscoveryBatch $malformed
    Assert-Equal $malformed.Status 'FAILED' 'Malformed response fails closed'
    Assert-Equal $malformed.QueryAttempts[0].ErrorCode 'INVALID_PROVIDER_RESPONSE' 'Malformed is not successful zero'
}
foreach ($response in @([pscustomobject]@{errorCode='SE99';items=@()}, @{error=@{message='secret'};items=@()})) {
    $providerError = Invoke-PoiDiscovery $lotOnly -RequestInvoker { $response }.GetNewClosure()
    Assert-Equal $providerError.Status 'FAILED' 'Provider error envelope cannot become empty result'
    Assert-Equal $providerError.QueryAttempts[0].ErrorCode 'PROVIDER_ERROR' 'Provider error recorded safely'
}
foreach ($pair in @(
    @('1269012345',''), @('','375012345'), @('NaN','375012345'), @('Infinity','375012345'),
    @('not-a-number','375012345'), @('0','0'), @('126.9012345','37.5012345'),
    @('375012345','1269012345'), @('1269012345','320000000'), @('1330000000','375012345')
)) {
    $badPoi = New-DiscoveryPoiFixture
    $badPoi.mapx = $pair[0]
    $badPoi.mapy = $pair[1]
    $badCoordinates = Invoke-PoiDiscovery $lotOnly -RequestInvoker { @{ items=@($strong,$badPoi) } }.GetNewClosure()
    Assert-ValidDiscoveryBatch $badCoordinates
    Assert-Equal $badCoordinates.Status 'FAILED' 'Malformed coordinate makes query incomplete'
    Assert-Equal $badCoordinates.QueryAttempts[0].ErrorCode 'INVALID_PROVIDER_COORDINATES' 'Invalid pair is explicit'
    Assert-Equal $badCoordinates.Candidates.Count 0 'Malformed query is atomic, not a successful truncated list'
}
$noCoordinatesPoi = New-DiscoveryPoiFixture
$noCoordinatesPoi.mapx = ''
$noCoordinatesPoi.mapy = ''
$absent = Invoke-PoiDiscovery $lotOnly -RequestInvoker { @{ items=@($noCoordinatesPoi) } }.GetNewClosure()
Assert-ValidDiscoveryBatch $absent
Assert-Equal $absent.Status 'COMPLETE' 'Absent pair is permitted, not guessed'
Assert-Equal $absent.Candidates[0].Latitude $null 'Absent latitude remains null'
Assert-Equal $absent.Candidates[0].Longitude $null 'Absent longitude remains null'

# Conservative keys: no branch merge via shared homepages, coordinates, or names.
$variants = @($strong)
foreach ($field in @('title','roadAddress','address','telephone','category','link','mapx')) {
    $variant = New-DiscoveryPoiFixture -Name $strong.title
    $variant.$field = if ($field -eq 'mapx') { '1269012346' } else { $variant.$field + ' changed' }
    $variantBatch = Invoke-PoiDiscovery $lotOnly -RequestInvoker { @{ items=@($strong,$variant) } }.GetNewClosure()
    Assert-Equal $variantBatch.Candidates.Count 2 "Changed $field evidence must not be overwritten by dedup"
}
$encodedPoi = New-DiscoveryPoiFixture -Name '<b>A</b> &amp; B &lt;테스트&gt;'
$encoded = Invoke-PoiDiscovery $lotOnly -RequestInvoker { @{ items=@($encodedPoi) } }.GetNewClosure()
Assert-Equal $encoded.Candidates[0].OriginalName 'A & B <테스트>' 'Decode entities after stripping highlight markup'
$samePlain = New-DiscoveryPoiFixture
$sameMarkup = Invoke-PoiDiscovery $lotOnly -RequestInvoker { @{ items=@($strong,$samePlain) } }.GetNewClosure()
Assert-Equal $sameMarkup.Candidates.Count 1 'Highlight markup does not split identical observations'

$originalCulture = [Threading.Thread]::CurrentThread.CurrentCulture
try {
    $keys = @()
    foreach ($cultureName in @('en-US','ko-KR','de-DE')) {
        [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo($cultureName)
        $repeat = Invoke-PoiDiscovery $lotOnly -RequestInvoker { @{ items=@($strong) } }.GetNewClosure()
        Assert-ValidDiscoveryBatch $repeat
        $keys += $repeat.Candidates[0].CandidateKey
    }
    Assert-Equal $keys[0] $keys[1] 'Key stable across Korean locale'
    Assert-Equal $keys[0] $keys[2] 'Key stable across decimal-comma locale'
} finally { [Threading.Thread]::CurrentThread.CurrentCulture = $originalCulture }

Write-Host "POI discovery tests passed ($script:assertionCount assertions)."
Write-Host 'Mock API Calls/Row: full=5, duplicate-query=3, no-plan=0. Live API calls=0; no recall/precision claim.'

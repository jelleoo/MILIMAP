$ErrorActionPreference = 'Stop'

# Current-work acceptance: origin/dev 93c2e445, A PR #37, B PR #34, C PR #36,
# and open Integration Issue #38 must remain documented as Shadow Mode work.

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
function Assert-Throws {
    param([scriptblock]$Action, [string]$Message)
    $script:assertionCount++
    $threw = $false
    try { & $Action } catch { $threw = $true }
    if (-not $threw) { throw $Message }
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

# Review regression: live execution is an explicit operational opt-in; mock mode
# is deterministic and cannot silently fall through to B's network path.
$runnerCommand = Get-Command Invoke-Phase1PoiShadowMode
Assert-True $runnerCommand.Parameters.ContainsKey('OperationalLiveRun') 'Runner exposes explicit operational live opt-in'
$noProviderRow = [pscustomobject]@{ 업소명=''; 시도=''; 시군구=''; 소재지도로명주소=''; 소재지지번주소='' }
Assert-Throws { Invoke-Phase1PoiShadowMode -Rows @($noProviderRow) } 'Deterministic mode requires RequestInvoker before discovery'
Assert-Throws { Invoke-Phase1PoiShadowMode -Rows @($singleStrongRow) -OperationalLiveRun -RequestInvoker $singleStrongInvoker } 'Operational live mode rejects deterministic RequestInvoker'
Assert-Equal (Get-Phase1PoiShadowSummary -Rows $run.Rows).OperationalLiveShadowRun 'NOT_RUN' 'Deterministic summary remains NOT_RUN'
Assert-Equal (Get-Phase1PoiShadowSummary -Rows $run.Rows -OperationalLiveRun).OperationalLiveShadowRun 'RUN' 'Operational mode summary projects RUN without a network call'

$previousClientId = [Environment]::GetEnvironmentVariable('NAVER_API_HUB_CLIENT_ID', 'Process')
$previousClientSecret = [Environment]::GetEnvironmentVariable('NAVER_API_HUB_CLIENT_SECRET', 'Process')
$environmentHeaders = [Collections.Generic.List[hashtable]]::new()
try {
    [Environment]::SetEnvironmentVariable('NAVER_API_HUB_CLIENT_ID', 'fixture-env-id', 'Process')
    [Environment]::SetEnvironmentVariable('NAVER_API_HUB_CLIENT_SECRET', 'fixture-env-secret', 'Process')
    Invoke-Phase1PoiShadowMode -Rows @($singleStrongRow) -RequestInvoker {
        param($Uri, $Headers)
        $environmentHeaders.Add($Headers)
        [pscustomobject]@{ items=@() }
    }.GetNewClosure() | Out-Null
    Assert-Equal $environmentHeaders[0]['X-NCP-APIGW-API-KEY-ID'] 'fixture-env-id' 'Runner preserves B environment credential fallback'
    Assert-Equal $environmentHeaders[0]['X-NCP-APIGW-API-KEY'] 'fixture-env-secret' 'Runner preserves B environment secret fallback'
} finally {
    [Environment]::SetEnvironmentVariable('NAVER_API_HUB_CLIENT_ID', $previousClientId, 'Process')
    [Environment]::SetEnvironmentVariable('NAVER_API_HUB_CLIENT_SECRET', $previousClientSecret, 'Process')
}

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

# Candidate diagnostics are a projection of preserved B candidates and C evidence.
# The second candidate has a city conflict; row-level outcome reasons are not candidate conflicts.
$cityConflictItem = [pscustomobject]@{
    title = '테스트 식당 본점'; roadAddress = '서울특별시 강남구 테스트로 12-3'; address = ''
    telephone = '02-000-0002'; category = '음식점'; link = 'https://example.invalid/fixture-city-conflict'; mapx = '1270012345'; mapy = '375012345'
}
$diagnosticRun = Invoke-Phase1PoiShadowMode -Rows @($singleStrongRow) -RequestInvoker { param($Uri, $Headers) [pscustomobject]@{ items=@($singleStrongItem, $cityConflictItem) } }
Assert-True ($diagnosticRun.PSObject.Properties.Name -contains 'CandidateDiagnostics') 'Run exposes additive candidate diagnostics'
$rowDiagnostics = @($diagnosticRun.CandidateDiagnostics)[0]
Assert-Equal $rowDiagnostics.SourceRowNumber 2 'Diagnostics preserve source row number'
Assert-Equal @($rowDiagnostics.Candidates).Count 2 'Every discovered candidate has diagnostics'
Assert-Equal (@($rowDiagnostics.Candidates | Select-Object -ExpandProperty CandidateKey | Select-Object -Unique).Count) 2 'Candidate keys are preserved and distinct'
Assert-Equal $rowDiagnostics.Candidates[0].RoadAddress '서울특별시 마포구 테스트로 12-3, 2층 201호' 'Diagnostics use deterministic first discovery order'
Assert-Equal $rowDiagnostics.Candidates[1].RoadAddress '서울특별시 강남구 테스트로 12-3' 'Diagnostics retain the second candidate address'
foreach ($candidateDiagnostic in @($rowDiagnostics.Candidates)) {
    Assert-True (-not [string]::IsNullOrWhiteSpace($candidateDiagnostic.CandidateKey)) 'Diagnostic candidate key is non-empty'
    Assert-True (-not [string]::IsNullOrWhiteSpace($candidateDiagnostic.OriginalName)) 'Diagnostic candidate name is preserved'
    Assert-True (@($candidateDiagnostic.Discovery | Where-Object { $_.StrategyCode -eq 'NAME_FULL_ADDRESS' -and $_.QueryOrder -eq 1 }).Count -eq 1) 'Discovery strategy and query order are preserved'
    Assert-True (@($candidateDiagnostic.MatcherEvidence | Where-Object { $_.CandidateKey -ne $candidateDiagnostic.CandidateKey }).Count -eq 0) 'Matcher evidence is filtered by candidate key'
}
$conflictingDiagnostic = @($rowDiagnostics.Candidates | Where-Object { $_.RoadAddress -eq '서울특별시 강남구 테스트로 12-3' })[0]
$strongDiagnostic = @($rowDiagnostics.Candidates | Where-Object { $_.RoadAddress -eq '서울특별시 마포구 테스트로 12-3, 2층 201호' })[0]
Assert-True ($conflictingDiagnostic.ConflictCodes -contains 'CITY_DISTRICT_CONFLICT') 'Conflict is derived only from the conflicting candidate evidence'
Assert-Equal @($strongDiagnostic.ConflictCodes).Count 0 'Global conflict codes are not copied to the strong candidate'
Assert-True (@($conflictingDiagnostic.MatcherEvidence | Where-Object { $_.EvidenceCode -eq 'CITY_DISTRICT_CONFLICT' -and $_.Matched -eq $false }).Count -eq 1) 'Candidate conflict retains its source matcher evidence'
Assert-Equal $diagnosticRun.Rows[0].Classification 'GREEN' 'Diagnostics do not alter row classification'
Assert-Equal $diagnosticRun.Rows[0].EvaluationStatus 'COMPLETE' 'Diagnostics do not alter row evaluation status'
Assert-True ($diagnosticRun.Rows[0].ReasonCodes -contains 'SINGLE_STRONG_CANDIDATE') 'Row outcome reason remains row-level only'
Assert-True (-not ($conflictingDiagnostic.ConflictCodes -contains 'SINGLE_STRONG_CANDIDATE')) 'Row outcome reason is not a candidate conflict'
Assert-Equal $diagnosticRun.Rows[0].ProductionAction 'NONE' 'Diagnostics do not alter production action'

# Task 4: metrics are Contract partitions, not scores or automatic approval.
$metricRows = @($run.Rows[0], $zero.Rows[0], $partial.Rows[0], $failed.Rows[0] | ForEach-Object { $_ | Select-Object * })
for ($index = 0; $index -lt $metricRows.Count; $index++) { $metricRows[$index].SourceRowNumber = $index + 2 }
$metricGolden = @{
    '2' = @{ SourceCoverage='FULL_CANDIDATE'; ExpectedLabel='positive' }
    '3' = @{ SourceCoverage='FULL_CANDIDATE'; ExpectedLabel='ambiguous' }
    '4' = @{ SourceCoverage='FULL_CANDIDATE'; ExpectedLabel='negative' }
    '5' = @{ SourceCoverage='SOURCE_LIMITED'; ExpectedLabel='negative' }
}
$summary = Get-Phase1PoiShadowSummary -Rows $metricRows -GoldenExpectations $metricGolden
Assert-Equal $summary.EvaluatedRows 4 'Input count is evaluated count'
Assert-Equal ($summary.DiscoveryComplete + $summary.DiscoveryPartial + $summary.DiscoveryFailed) 4 'Discovery partitions reconcile'
Assert-Equal ($summary.MatcherComplete + $summary.MatcherIncomplete) 4 'Matcher partitions reconcile'
Assert-Equal ($summary.Green + $summary.Yellow + $summary.Red) 4 'Classification partitions reconcile'
Assert-Equal $summary.FastReviewCandidates $summary.Green 'GREEN is fast-review evidence only'
Assert-Equal $summary.DeepManualReviewRequired ($summary.Yellow + $summary.Red) 'YELLOW plus RED require deep manual review'
Assert-True $summary.AllRowsRequireFinalHumanApproval 'Every Phase 1 row still needs final human approval'
Assert-Equal $summary.NoCandidateCount 1 'Complete zero-candidate evidence is counted separately'
Assert-Equal $summary.DiscoveryFailureCount 1 'Provider failure is counted separately'
Assert-Equal $summary.TotalQueryAttempts 20 'Only non-skipped provider work is counted'
Assert-Equal $summary.AverageQueryAttempts ([double]5) 'Average provider work is deterministic'
Assert-Equal $summary.TotalGoldenCases 4 'Golden total is explicit'
Assert-Equal $summary.FullyEvaluableGoldenCases 3 'Full candidate coverage is explicit'
Assert-Equal $summary.SourceLimitedGoldenCases 1 'Source-limited coverage is explicit'
Assert-Equal $summary.FullyEvaluableAmbiguousNegativeFalseGreenCount 0 'Fully-evaluable ambiguous and negative cases have no false GREEN'
Assert-Equal $summary.OperationalLiveShadowRun 'NOT_RUN' 'Mock execution is not a live Shadow run'

$unsafeMetricRows = @($metricRows | ForEach-Object { $_ | Select-Object * })
$unsafeMetricRows[1].Classification = 'GREEN'
$unsafeSummary = Get-Phase1PoiShadowSummary -Rows $unsafeMetricRows -GoldenExpectations $metricGolden
Assert-Equal $unsafeSummary.FullyEvaluableAmbiguousNegativeFalseGreenCount 1 'False GREEN detects fully-evaluable ambiguous coverage'

# Task 5: repository-cited Golden cases never fabricate a provider address.
$golden = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'testdata/phase1-poi-shadow-golden.psd1')
Assert-Equal $golden['248'].SourcePath 'data/canonical/reports/poi-coordinate-review-candidates-20260910-final.csv' 'Golden source path is explicit'
Assert-Equal $golden.Count 5 'Golden fixture has the source-cited cases only'
Assert-Equal $golden['451'].SourceCoverage 'SOURCE_LIMITED' 'Historical row 451 coverage remains source-limited'
Assert-Equal $golden['451'].ExpectedLabel 'ambiguous' 'Historical row 451 label remains ambiguous'
Assert-Equal $golden['451'].SourceNote 'Final review holds 짜장마을 because the cited source URL resolves to a search for 짜장단가든, so it does not establish a trustworthy provider candidate.' 'Historical row 451 source note is preserved'
Assert-True $golden['451'].ContainsKey('OperationalObservation') 'Row 451 has separate additive operational provenance'
Assert-Equal $golden['451'].OperationalObservation.ObservedAt '2026-09-24' 'Operational observation retains its date'
Assert-Equal $golden['451'].OperationalObservation.Source 'NAVER_API_HUB_LOCAL operational Shadow' 'Operational observation retains its source'
Assert-Equal $golden['451'].OperationalObservation.Status 'current POI identity observation' 'Operational observation retains its status'
Assert-Equal $golden['451'].OperationalObservation.ObservedClassification 'GREEN' 'Operational observation retains its classification'
Assert-True ($golden['451'].OperationalObservation.IdentityEvidence -contains 'NAME_EXACT') 'Operational observation retains identity evidence'
foreach ($sourceLimitedRow in @('451', '135', '136')) {
    Assert-Equal $golden[$sourceLimitedRow].SourceCoverage 'SOURCE_LIMITED' "Source-limited coverage is explicit for $sourceLimitedRow"
    Assert-True (-not $golden[$sourceLimitedRow].ContainsKey('ProviderItem')) "Source-limited $sourceLimitedRow has no fabricated provider candidate"
}
$goldenRows = [Collections.Generic.List[object]]::new()
foreach ($sourceRowNumber in @('135', '136', '248', '339', '451')) {
    $case = $golden[$sourceRowNumber]
    $invoker = if ($case.SourceCoverage -eq 'FULL_CANDIDATE') {
        $providerItem = $case.ProviderItem
        { param($Uri, $Headers) [pscustomobject]@{ items=@($providerItem) } }.GetNewClosure()
    } else {
        { param($Uri, $Headers) [pscustomobject]@{ items=@() } }.GetNewClosure()
    }
    $caseRun = Invoke-Phase1PoiShadowMode -Rows @([pscustomobject]$case.CanonicalRow) -SourceRowNumberOffset ([int]$sourceRowNumber - 1) -RequestInvoker $invoker
    $goldenRows.Add($caseRun.Rows[0])
}
$goldenSummary = Get-Phase1PoiShadowSummary -Rows $goldenRows.ToArray() -GoldenExpectations $golden
Assert-Equal $goldenSummary.TotalGoldenCases 5 'All source-cited Golden rows are counted'
Assert-Equal $goldenSummary.FullyEvaluableGoldenCases 2 'Full candidate evidence is counted separately'
Assert-Equal $goldenSummary.SourceLimitedGoldenCases 3 'Source-limited cases are counted separately'
Assert-Equal $goldenSummary.FullyEvaluableAmbiguousNegativeFalseGreenCount 0 'Fully-evaluable ambiguous or negative false GREEN is zero'
Assert-Equal @($goldenRows | Where-Object { $_.SourceRowNumber -eq 248 -and $_.Classification -eq 'GREEN' }).Count 0 '버섯집 초리골 building conflict is never GREEN'
Assert-True (@($goldenRows | Where-Object { $_.SourceRowNumber -eq 248 })[0].ConflictCodes -contains 'BUILDING_NUMBER_CONFLICT') '버섯집 초리골 exposes building conflict evidence'
Assert-Equal @($goldenRows | Where-Object { $golden[[string]$_.SourceRowNumber].SourceCoverage -eq 'SOURCE_LIMITED' -and $_.Classification -eq 'GREEN' }).Count 0 'Source-limited safety cases are never GREEN'
Assert-True (@($goldenRows | Where-Object { $_.SourceRowNumber -eq 339 })[0].Classification -ne 'RED') '거시기닭갈비 is not reversed by absent provider phone evidence'

# Task 3: reports are an explicit caller-owned output, never a canonical default.
$reportDirectory = Join-Path ([IO.Path]::GetTempPath()) ('milimap-phase1-shadow-mode-' + [Guid]::NewGuid().ToString('N'))
$reportPath = Join-Path $reportDirectory 'row-report.csv'
$summaryPath = Join-Path $reportDirectory 'summary.json'
$diagnosticPath = Join-Path $reportDirectory 'candidate-diagnostics.json'
try {
    Export-Phase1PoiShadowMode -Run $zero -RowReportCsv $reportPath -SummaryJson $summaryPath
    Assert-True (Test-Path -LiteralPath $reportPath) 'Explicit row report is written'
    Assert-True (Test-Path -LiteralPath $summaryPath) 'Explicit summary is written'
    Assert-True (-not (Test-Path -LiteralPath $diagnosticPath)) 'Optional diagnostics do not change existing export artifacts'
    $exportedRow = @(Import-Csv -LiteralPath $reportPath)[0]
    Assert-Equal $exportedRow.SourceRowNumber '2' 'Export preserves source row number'
    Assert-Equal $exportedRow.ReasonCodes 'NO_CANDIDATE' 'Export serializes code arrays deterministically'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\data\canonical\capital-area-military-benefits.shadow.csv'))) 'Export has no canonical default path'

    Export-Phase1PoiShadowMode -Run $diagnosticRun -RowReportCsv $reportPath -SummaryJson $summaryPath -CandidateDiagnosticJson $diagnosticPath
    Assert-True (Test-Path -LiteralPath $diagnosticPath) 'Explicit candidate diagnostics are written'
    $exportedDiagnostics = @(Get-Content -Raw -Encoding UTF8 -LiteralPath $diagnosticPath | ConvertFrom-Json)
    Assert-Equal $exportedDiagnostics.Count 1 'Candidate diagnostics export one row artifact'
    Assert-Equal @($exportedDiagnostics[0].Candidates).Count 2 'Candidate diagnostics export every candidate'
    Assert-Equal $exportedDiagnostics[0].Candidates[0].RoadAddress '서울특별시 마포구 테스트로 12-3, 2층 201호' 'Candidate diagnostics export deterministic ordering'
} finally {
    if (Test-Path -LiteralPath $reportDirectory) { Remove-Item -LiteralPath $reportDirectory -Recurse -Force }
}

# Review regression: only explicit report paths outside repository production roots
# may be written. The disposable sentinels are new test files; existing data is
# never selected and every artifact is removed in finally.
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$outputGateId = [Guid]::NewGuid().ToString('N')
$sentinelText = 'phase1-shadow-output-gate-sentinel'
$outputGateTemp = Join-Path ([IO.Path]::GetTempPath()) ('milimap-phase1-output-gate-' + $outputGateId)
$protectedRoots = @('data/canonical', 'data/seed', 'apps')
foreach ($protectedRoot in $protectedRoots) {
    $relativeSentinel = Join-Path $protectedRoot ('.phase1-shadow-output-gate-' + $outputGateId + '.csv')
    $absoluteSentinel = Join-Path $repositoryRoot $relativeSentinel
    $temporarySummary = Join-Path $outputGateTemp ($protectedRoot.Replace('/', '-') + '-summary.json')
    $temporaryReport = Join-Path $outputGateTemp ($protectedRoot.Replace('/', '-') + '-report.csv')
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $absoluteSentinel) | Out-Null
    [IO.File]::WriteAllText($absoluteSentinel, $sentinelText, [Text.UTF8Encoding]::new($false))
    try {
        $relativeThrew = $false
        try { Export-Phase1PoiShadowMode -Run $zero -RowReportCsv $relativeSentinel -SummaryJson $temporarySummary } catch { $relativeThrew = $true }
        Assert-Equal ([IO.File]::ReadAllText($absoluteSentinel)) $sentinelText "$protectedRoot relative sentinel is unchanged"
        Assert-True $relativeThrew "$protectedRoot relative output is rejected"
        Assert-True (-not (Test-Path -LiteralPath $temporarySummary)) "$protectedRoot rejection creates no summary output"

        $absoluteThrew = $false
        try { Export-Phase1PoiShadowMode -Run $zero -RowReportCsv $temporaryReport -SummaryJson $absoluteSentinel } catch { $absoluteThrew = $true }
        Assert-Equal ([IO.File]::ReadAllText($absoluteSentinel)) $sentinelText "$protectedRoot absolute sentinel is unchanged"
        Assert-True $absoluteThrew "$protectedRoot absolute output is rejected"
    Assert-True (-not (Test-Path -LiteralPath $temporaryReport)) "$protectedRoot rejection creates no row report"

        $diagnosticThrew = $false
        try { Export-Phase1PoiShadowMode -Run $diagnosticRun -RowReportCsv $temporaryReport -SummaryJson $temporarySummary -CandidateDiagnosticJson $absoluteSentinel } catch { $diagnosticThrew = $true }
        Assert-Equal ([IO.File]::ReadAllText($absoluteSentinel)) $sentinelText "$protectedRoot diagnostic sentinel is unchanged"
        Assert-True $diagnosticThrew "$protectedRoot diagnostic output is rejected"
        Assert-True (-not (Test-Path -LiteralPath $temporarySummary)) "$protectedRoot diagnostic rejection creates no summary output"
    } finally {
        Remove-Item -LiteralPath $absoluteSentinel -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $temporarySummary, $temporaryReport -Force -ErrorAction SilentlyContinue
    }
}
$unrelatedAppsDirectory = Join-Path $repositoryRoot ('apps-old-phase1-shadow-' + $outputGateId)
$unrelatedReport = Join-Path $unrelatedAppsDirectory 'row-report.csv'
$unrelatedSummary = Join-Path $unrelatedAppsDirectory 'summary.json'
try {
    Export-Phase1PoiShadowMode -Run $zero -RowReportCsv $unrelatedReport -SummaryJson $unrelatedSummary
    Assert-True (Test-Path -LiteralPath $unrelatedReport) 'Unrelated apps-old path is not blocked'
    Assert-True (Test-Path -LiteralPath $unrelatedSummary) 'Unrelated apps-old summary is not blocked'
} finally {
    Remove-Item -LiteralPath $unrelatedAppsDirectory -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $outputGateTemp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Phase 1 Shadow Mode tests passed ($script:assertionCount assertions)."

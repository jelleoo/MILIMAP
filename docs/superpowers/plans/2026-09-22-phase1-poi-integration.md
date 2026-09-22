# Phase 1 POI Verification Shadow Mode Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Connect canonical rows through A NormalizedBusiness, B PoiDiscoveryBatch, and C PoiMatchResult in deterministic non-writing Shadow Mode, with reviewable reports and metrics.

**Architecture:** Create a new Phase 1 runner that dot-sources the frozen Contract and A/B/C public modules, calls their public functions unchanged, and emits only derived report data. Preserve the legacy coordinate audit unchanged because it has independent API, coordinate, Korean decision, and output-write semantics.

**Tech Stack:** PowerShell 7, Contract v1, Import-Csv/Export-Csv/ConvertTo-Json, B RequestInvoker mock seam; no dependencies.

**Spec:** docs/superpowers/specs/2026-09-10-benefit-business-verification-pipeline-design.md; docs/superpowers/specs/2026-09-10-poi-verification-contracts-design.md; GitHub Issue #38.

## Work summary

- **Problem:** merged A (#28), B (#29), and C (#30) have no canonical-row orchestration.
- **In scope:** A→B→C runner, deterministic provider mocks, derived row report/summary, source-cited Golden validation, limited current-work refresh.
- **Out of scope:** Contract/A/B/C logic, thresholds, provider contract, schema/API/auth, canonical/seed/Android writes, production approval, Phase 2.
- **Expected files:** create tools/data/invoke-phase1-poi-shadow-mode.ps1, tools/data/test-phase1-poi-shadow-mode.ps1, tools/data/testdata/phase1-poi-shadow-golden.psd1; modify docs/current-work.md. This plan is the only other document.
- **Test method:** every behavior is test-first; fixture/CI calls use B RequestInvoker only. Optional live execution requires supplied credentials and explicit report paths.
- **Risks:** failure becoming RED/no-candidate, GREEN being treated as approval, incomplete Golden observations, and accidental legacy-semantic reuse.

## Global constraints

- Execution baseline must be freshly fetched origin/dev, initially 93c2e4455cb6628dfc1c2ffe0050b48524dedd89; stop if it changed.
- Frozen Contract v1 and tools/data/lib/identity/**, poi-discovery/**, poi-matching/** are read-only. Record A/B/C defects as follow-up candidates, never fix them here.
- B PARTIAL/FAILED passes unchanged to C and must be INCOMPLETE/YELLOW. COMPLETE zero candidates remains COMPLETE/RED with NO_CANDIDATE.
- ProductionAction is always NONE. No code path writes data/canonical, data/seed, apps, or Android.
- Golden fixtures cite source files and only encode their confirmed source facts. Each case declares `SourceCoverage` as `FULL_CANDIDATE` or `SOURCE_LIMITED`; P3 rows without a full provider address are source-limited building observations, never synthetic provider candidates.
- Deterministic RequestInvoker tests are the implementation merge gate. An operational live Shadow run is a separate, optional read-only activity requiring supplied credentials and explicit output paths; if it is not run, report `Operational live Shadow run: NOT RUN` and use `Refs #38`, never `Closes #38`.

## Legacy orchestration decision

| Option | Compatibility and risk | Decision |
| --- | --- | --- |
| A: extend verify-canonical-benefit-poi.ps1 | Mixes legacy coordinate/API-error Korean decisions and write behavior with Contract v1 status semantics. | Reject |
| B: new Phase 1 runner | Leaves legacy callers/output untouched; small independent test and rollback surface. | **Adopt** |
| C: extract common runner/library | Refactors legacy before new behavior is proven and expands scope. | Reject |

## Review Focus

- FAILED discovery with no candidates is INCOMPLETE/YELLOW, never RED/NO_CANDIDATE (Task 2).
- Successful empty provider result is COMPLETE/RED/NO_CANDIDATE (Task 2).
- Building conflict 902 versus 904 can never become GREEN (Task 5).
- Multiple plausible candidates remain YELLOW (Task 2).
- GREEN is only fast-review evidence and keeps ProductionAction NONE (Tasks 1 and 3). Every row still requires final human approval; YELLOW and RED are the deep-manual-review partition.

## File structure and interfaces

- tools/data/invoke-phase1-poi-shadow-mode.ps1: Contract-only runner/library; dot-sources A/B/C but reimplements none.
- tools/data/test-phase1-poi-shadow-mode.ps1: deterministic integration and Golden assertions.
- tools/data/testdata/phase1-poi-shadow-golden.psd1: source-cited data-only Golden fixture.
- docs/current-work.md: only baseline, A/B/C completion, #38 in-progress, and Shadow Mode status.

~~~powershell
function Invoke-Phase1PoiShadowMode {
    param(
        [Parameter(Mandatory)][object[]]$Rows,
        [int]$SourceRowNumberOffset = 1,
        [scriptblock]$RequestInvoker,
        [string]$ClientId = '', [string]$ClientSecret = ''
    )
    # returns [pscustomobject]@{ Rows=[object[]]; Summary=[pscustomobject] }
}
function Export-Phase1PoiShadowMode {
    param($Run, [string]$RowReportCsv, [string]$SummaryJson)
}
~~~

Each derived row contains SourceRowNumber, OriginalName, AddressParseStatus, NormalizationWarnings, DiscoveryStatus, CandidateCount, QueryAttemptCount, EvaluationStatus, Classification, SelectedCandidateKey/Name/RoadAddress, ReasonCodes, ConflictCodes, ProductionAction. Summary contains evaluated counts, discovery/evaluation/classification partitions, FastReviewCandidates, DeepManualReviewRequired, NoCandidateCount, DiscoveryFailureCount, TotalQueryAttempts, average attempts, TotalGoldenCases, FullyEvaluableGoldenCases, SourceLimitedGoldenCases, FullyEvaluableAmbiguousNegativeFalseGreenCount, and the operational-run marker.

FastReviewCandidates means GREEN. DeepManualReviewRequired means YELLOW + RED. All rows remain subject to final human approval; no metric means automatic production approval. TotalQueryAttempts excludes B SKIPPED entries because it measures actual provider work. Source-limited Golden cases may assert safety (never GREEN) but are excluded from fully-evaluable candidate false-GREEN counting.

### Task 1: Contract chaining boundary

**Files:**
- Create: tools/data/invoke-phase1-poi-shadow-mode.ps1
- Create: tools/data/test-phase1-poi-shadow-mode.ps1

**Consumes:** row fields 업소명, 시도, 시군구, 소재지도로명주소, 소재지지번주소.
**Produces:** Run.Rows and Run.Summary specified above.

- [ ] **Step 1: Write failing chain tests**

~~~powershell
$run = Invoke-Phase1PoiShadowMode -Rows @($row) -RequestInvoker $singleStrongInvoker
Assert-Equal $run.Rows.Count 1 'One input makes one report row'
Assert-Equal $run.Rows[0].SourceRowNumber 2 'Source row survives A B C'
Assert-Equal $run.Rows[0].DiscoveryStatus 'COMPLETE' 'Single mocked provider succeeds'
Assert-Equal $run.Rows[0].Classification 'GREEN' 'Single strong candidate can be GREEN'
Assert-Equal $run.Rows[0].ProductionAction 'NONE' 'No production action'
~~~

- [ ] **Step 2: Confirm RED**

Run: pwsh -NoLogo -NoProfile -File tools/data/test-phase1-poi-shadow-mode.ps1

Expected: FAIL because Invoke-Phase1PoiShadowMode is undefined.

- [ ] **Step 3: Implement minimal chain**

~~~powershell
$business = ConvertTo-NormalizedBusiness -Row $row -SourceRowNumber ($SourceRowNumberOffset + $index + 1)
Assert-NormalizedBusiness $business
$batch = Invoke-PoiDiscovery -Business $business -ClientId $ClientId -ClientSecret $ClientSecret -RequestInvoker $RequestInvoker
Assert-PoiDiscoveryBatch $batch
$result = Invoke-PoiMatchEvaluation -Business $business -DiscoveryBatch $batch
Assert-PoiMatchResult $result
if ($business.SourceRowNumber -ne $batch.SourceRowNumber -or $batch.SourceRowNumber -ne $result.SourceRowNumber) { throw 'SourceRowNumber chain mismatch' }
~~~

Read only the five source columns and do not mutate a row.

- [ ] **Step 4: Confirm GREEN**

Run: pwsh -NoLogo -NoProfile -File tools/data/test-phase1-poi-shadow-mode.ps1

Expected: chain and all three Contract assertions pass.

- [ ] **Step 5: Commit checkpoint**

~~~powershell
git add tools/data/invoke-phase1-poi-shadow-mode.ps1 tools/data/test-phase1-poi-shadow-mode.ps1
git commit -m "feat(data): add phase1 shadow orchestration"
~~~

### Task 2: Provider and failure semantics

**Files:**
- Modify: tools/data/invoke-phase1-poi-shadow-mode.ps1
- Modify: tools/data/test-phase1-poi-shadow-mode.ps1

**Interface:** reuse B RequestInvoker, returning decoded @{ items=@(...) } or throwing. Pass its PoiDiscoveryBatch unchanged to C.

- [ ] **Step 1: Write failing semantic tests**

~~~powershell
$zero = Invoke-Phase1PoiShadowMode -Rows @($row) -RequestInvoker { @{ items=@() } }
Assert-Equal $zero.Rows[0].DiscoveryStatus 'COMPLETE' 'Successful zero is complete'
Assert-Equal $zero.Rows[0].Classification 'RED' 'Complete zero is conclusive RED'
Assert-True ($zero.Rows[0].ReasonCodes -contains 'NO_CANDIDATE') 'No-candidate reason remains'

$partial = Invoke-Phase1PoiShadowMode -Rows @($row) -RequestInvoker $oneSuccessThenThrow
Assert-Equal $partial.Rows[0].DiscoveryStatus 'PARTIAL' 'Mixed provider result is partial'
Assert-Equal $partial.Rows[0].EvaluationStatus 'INCOMPLETE' 'Partial is incomplete'
Assert-Equal $partial.Rows[0].Classification 'YELLOW' 'Partial is Yellow'

$failed = Invoke-Phase1PoiShadowMode -Rows @($row) -RequestInvoker { throw 'fixture timeout' }
Assert-Equal $failed.Rows[0].DiscoveryStatus 'FAILED' 'Failure remains failure'
Assert-Equal $failed.Rows[0].Classification 'YELLOW' 'Failure cannot become RED'
Assert-True (-not ($failed.Rows[0].ReasonCodes -contains 'NO_CANDIDATE')) 'Failure is not no-candidate'
~~~

Add a mock with two strong observations and require COMPLETE/YELLOW, MULTIPLE_PLAUSIBLE_CANDIDATES, and no selection.

- [ ] **Step 2: Confirm RED**

Run: pwsh -NoLogo -NoProfile -File tools/data/test-phase1-poi-shadow-mode.ps1

Expected: FAIL until report projection preserves B/C semantics.

- [ ] **Step 3: Implement direct projection**

Project Status, candidate/query counts, evaluation/classification, reasons/conflicts, and selected fields directly from B/C; never translate codes.

- [ ] **Step 4: Confirm GREEN**

Run: pwsh -NoLogo -NoProfile -File tools/data/test-phase1-poi-shadow-mode.ps1

Expected: zero, partial, failed, and multiple-candidate assertions pass.

- [ ] **Step 5: Commit checkpoint**

~~~powershell
git add tools/data/invoke-phase1-poi-shadow-mode.ps1 tools/data/test-phase1-poi-shadow-mode.ps1
git commit -m "test(data): cover shadow provider failure semantics"
~~~

### Task 3: Row report and safe export

**Files:**
- Modify: tools/data/invoke-phase1-poi-shadow-mode.ps1
- Modify: tools/data/test-phase1-poi-shadow-mode.ps1

- [ ] **Step 1: Write failing report/export tests**

~~~powershell
Assert-Equal $run.Rows.Count $inputRows.Count 'Report count equals input count'
Assert-Equal $run.Rows[0].SelectedCandidateKey 'fixture-strong' 'Selection is reviewable'
Assert-Equal $run.Rows[0].ProductionAction 'NONE' 'Report retains safety action'
Export-Phase1PoiShadowMode -Run $run -RowReportCsv $reportPath -SummaryJson $summaryPath
Assert-True (Test-Path -LiteralPath $reportPath) 'Explicit report written'
Assert-True (-not (Test-Path -LiteralPath 'data/canonical/capital-area-military-benefits.shadow.csv')) 'No canonical write'
~~~

- [ ] **Step 2: Confirm RED**

Run: pwsh -NoLogo -NoProfile -File tools/data/test-phase1-poi-shadow-mode.ps1

Expected: FAIL because export and report fields do not exist.

- [ ] **Step 3: Implement output-only export**

Require nonempty caller paths, create only their parents, write CSV/JSON with stable code-array ordering, and never default into data/canonical, data/seed, or apps.

- [ ] **Step 4: Confirm GREEN**

Run: pwsh -NoLogo -NoProfile -File tools/data/test-phase1-poi-shadow-mode.ps1

Expected: deterministic output and explicit-only write assertions pass.

- [ ] **Step 5: Commit checkpoint**

~~~powershell
git add tools/data/invoke-phase1-poi-shadow-mode.ps1 tools/data/test-phase1-poi-shadow-mode.ps1
git commit -m "feat(data): export phase1 shadow reports"
~~~

### Task 4: Metrics aggregation

**Files:**
- Modify: tools/data/invoke-phase1-poi-shadow-mode.ps1
- Modify: tools/data/test-phase1-poi-shadow-mode.ps1

**Produces:** Get-Phase1PoiShadowSummary -Rows [object[]] -GoldenExpectations [hashtable].

- [ ] **Step 1: Write failing reconciliation tests**

~~~powershell
$summary = Get-Phase1PoiShadowSummary -Rows $run.Rows -GoldenExpectations $golden
Assert-Equal $summary.EvaluatedRows 4 'Input count'
Assert-Equal ($summary.DiscoveryComplete + $summary.DiscoveryPartial + $summary.DiscoveryFailed) 4 'Discovery reconciles'
Assert-Equal ($summary.MatcherComplete + $summary.MatcherIncomplete) 4 'Matcher reconciles'
Assert-Equal ($summary.Green + $summary.Yellow + $summary.Red) 4 'Classification reconciles'
Assert-Equal $summary.FastReviewCandidates $summary.Green 'GREEN is fast-review evidence'
Assert-Equal $summary.DeepManualReviewRequired ($summary.Yellow + $summary.Red) 'YELLOW plus RED requires deep review'
Assert-Equal $summary.FullyEvaluableAmbiguousNegativeFalseGreenCount 0 'No fully-evaluable ambiguous or negative Golden GREEN'
~~~

- [ ] **Step 2: Confirm RED**

Run: pwsh -NoLogo -NoProfile -File tools/data/test-phase1-poi-shadow-mode.ps1

Expected: FAIL because summary function is missing.

- [ ] **Step 3: Implement count-only aggregation**

NoCandidateCount requires COMPLETE, zero candidates, and NO_CANDIDATE. DiscoveryFailureCount is FAILED. TotalQueryAttempts counts non-SKIPPED attempts. Average is 0 for no rows; otherwise culture-invariant division. Count total Golden cases separately from FULL_CANDIDATE and SOURCE_LIMITED cases; calculate false-GREEN only over fully-evaluable ambiguous/negative cases. Do not create scores or thresholds.

- [ ] **Step 4: Confirm GREEN**

Run: pwsh -NoLogo -NoProfile -File tools/data/test-phase1-poi-shadow-mode.ps1

Expected: partitions reconcile and false-GREEN is deterministic.

- [ ] **Step 5: Commit checkpoint**

~~~powershell
git add tools/data/invoke-phase1-poi-shadow-mode.ps1 tools/data/test-phase1-poi-shadow-mode.ps1
git commit -m "feat(data): summarize phase1 shadow metrics"
~~~

### Task 5: Source-cited Golden regression

**Files:**
- Create: tools/data/testdata/phase1-poi-shadow-golden.psd1
- Modify: tools/data/test-phase1-poi-shadow-mode.ps1

| Label | Row | Source fact | Required result |
| --- | --- | --- | --- |
| negative | 248 버섯집 초리골 | final review report: canonical 초리골길 12, observed POI 초리골길 23, rejected | never GREEN; building conflict |
| ambiguous | 451 짜장마을 | final review report: cited search URL establishes no trustworthy provider candidate and case is held | SOURCE_LIMITED; never GREEN; do not fabricate provider evidence |
| negative | 135 이지현미용실 | P3 report: canonical 26, observed POI building 23, rejected; no full POI address | SOURCE_LIMITED; never GREEN; record building-only limitation |
| negative | 136 인헤어 | P3 report: canonical 902/2동 104호, observed POI 904, rejected; no full POI address | SOURCE_LIMITED; never GREEN; record building-only limitation |
| positive caution | 339 거시기닭갈비 | final report: 덕정본점, 엄상동길 22-25, 고암동 157-6 approved; phone suffix differed | not RED solely for phone |

Sources are data/canonical/reports/poi-coordinate-review-candidates-20260910-final.csv and data/canonical/reports/poi-coordinate-review-candidates-20260910-p3.csv, plus data/canonical/capital-area-military-benefits.csv.

- [ ] **Step 1: Write failing source and false-GREEN tests**

~~~powershell
$golden = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'testdata/phase1-poi-shadow-golden.psd1')
Assert-Equal $golden['248'].SourcePath 'data/canonical/reports/poi-coordinate-review-candidates-20260910-final.csv' 'Golden source explicit'
$run = Invoke-Phase1PoiShadowMode -Rows $goldenRows -RequestInvoker $goldenInvoker
Assert-Equal @($run.Rows | Where-Object { $golden[[string]$_.SourceRowNumber].SourceCoverage -eq 'FULL_CANDIDATE' -and $golden[[string]$_.SourceRowNumber].ExpectedLabel -in @('negative', 'ambiguous') -and $_.Classification -eq 'GREEN' }).Count 0 'Fully-evaluable false GREEN is zero'
Assert-Equal @($run.Rows | Where-Object { $golden[[string]$_.SourceRowNumber].SourceCoverage -eq 'SOURCE_LIMITED' -and $_.Classification -eq 'GREEN' }).Count 0 'Source-limited safety cases are never GREEN'
~~~

- [ ] **Step 2: Confirm RED**

Run: pwsh -NoLogo -NoProfile -File tools/data/test-phase1-poi-shadow-mode.ps1

Expected: FAIL because fixture/mapping is absent.

- [ ] **Step 3: Add data-only source fixture**

Store exact source row fields, SourcePath, SourceNote, ExpectedLabel, and SourceCoverage. For P3 SOURCE_LIMITED cases, preserve only the source-confirmed building observation in fixture metadata; do not construct a synthetic provider candidate, address, phone, or coordinates. The test may assert safety without treating source-limited cases as full matcher-coverage evidence.

- [ ] **Step 4: Confirm GREEN**

Run: pwsh -NoLogo -NoProfile -File tools/data/test-phase1-poi-shadow-mode.ps1

Expected: source paths, coverage partitions, fully-evaluable false-GREEN=0, source-limited never-GREEN safety, and cautionary-positive assertions pass.

- [ ] **Step 5: Commit checkpoint**

~~~powershell
git add tools/data/testdata/phase1-poi-shadow-golden.psd1 tools/data/test-phase1-poi-shadow-mode.ps1
git commit -m "test(data): add phase1 shadow golden regressions"
~~~

### Task 6: Scoped current-work refresh

**Files:**
- Modify: docs/current-work.md

- [ ] **Step 1: Record the documentation acceptance checklist in test comments**

Require latest baseline at implementation time, A #28/PR #37 complete, B #29/PR #34 complete, C #30/PR #36 complete, #38 in progress, and Phase 1 Shadow Mode.

- [ ] **Step 2: Confirm RED**

Run: rg -n 'PR #37|PR #36|Issue #38|Shadow Mode' docs/current-work.md

Expected: stale A/C status appears before update.

- [ ] **Step 3: Update only current-status sections**

Replace baseline/workstream/Integration status statements; preserve historical P2/P3 context and roadmap. Do not claim implementation or merge before it happens.

- [ ] **Step 4: Confirm GREEN**

Run: rg -n 'A.*complete|B.*complete|C.*complete|#38|Shadow Mode|origin/dev' docs/current-work.md

Expected: all current-state facts appear with no broad rewrite.

- [ ] **Step 5: Commit checkpoint**

~~~powershell
git add docs/current-work.md
git commit -m "docs(data): update phase1 integration status"
~~~

### Task 7: Full regression and scope gate

**Files:** Verify only.

- [ ] **Step 1: Run focused evidence**

~~~powershell
pwsh -NoLogo -NoProfile -File tools/data/test-phase1-poi-shadow-mode.ps1
pwsh -NoLogo -NoProfile -File tools/data/test-normalize-business.ps1
pwsh -NoLogo -NoProfile -File tools/data/test-discover-poi-candidates.ps1
pwsh -NoLogo -NoProfile -File tools/data/test-evaluate-poi-match.ps1
pwsh -NoLogo -NoProfile -File tools/data/test-poi-verification-contracts.ps1
pwsh -NoLogo -NoProfile -File tools/data/test-verify-canonical-benefit-poi.ps1
~~~

- [ ] **Step 2: Run full data suite**

~~~powershell
Get-ChildItem tools/data -Filter 'test-*.ps1' | Sort-Object Name | ForEach-Object { & pwsh -NoLogo -NoProfile -File $_.FullName; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE } }
~~~

- [ ] **Step 3: Confirm scope**

~~~powershell
git diff --check
git diff --name-only origin/dev...HEAD
git diff --quiet origin/dev...HEAD -- tools/data/lib/poi-verification-contracts.ps1 tools/data/lib/identity tools/data/lib/poi-discovery tools/data/lib/poi-matching; if ($LASTEXITCODE -ne 0) { exit 1 }
git diff --quiet origin/dev...HEAD -- data/canonical data/seed apps; if ($LASTEXITCODE -ne 0) { exit 1 }
git status --short
~~~

Expected: only runner/test/testdata/current-work/plan files change; forbidden paths and automated live API calls are zero. Record `Operational live Shadow run: NOT RUN` unless a separately authorized credentials-backed read-only run is performed.

## Self-review

- Legacy audit is untouched; Contract/A/B/C internals are read-only.
- Provider failure remains B/C status evidence, never closure/no-candidate evidence.
- Golden sources, coverage partitions, and P3 evidence limits are explicit; no source fact is invented.
- All requested metrics are direct Contract partitions, reconcile to evaluated rows, and add no threshold.
- Export paths are explicit and non-canonical; tests use mocks.
- No TODO/TBD or unresolved interface remains.

## Execution handoff

Review rulings are incorporated above. Execute in the new isolated worktree from freshly fetched origin/dev, using test-first tasks and checkpoint commits. Do not start Phase 2. After deterministic verification and whole-branch review, open a non-merged PR; use `Refs #38` unless an operational live Shadow run satisfies the issue completion condition.

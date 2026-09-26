# Phase 3 P3-7 Integration, Review Routing, and Closeout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate Location and Benefit history into one auditable Phase 3 shadow runner, separate audit/operational/human-review outputs, validate representative scenarios, and close Phase 3 only when all 20 design gates pass.

**Architecture:** A thin integration runner invokes the two already-tested domain history flows and writes only through the shared History Store. Review projection is a pure classification layer over immutable comparisons. Closeout uses deterministic fixtures and committed captures by default and reports efficiency/safety metrics without claiming population accuracy.

**Tech Stack:** PowerShell 7, Phase 1/2 cores, Phase 3 History Core/Store/adapters, existing GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-26-phase3-snapshot-incremental-change-detection-design.md`

## Global Constraints

- Phase 3 remains shadow-only; `ProductionAction=NONE`.
- No automatic canonical/seed/apps writes.
- Audit history and human review queue are separate.
- No full 496-row live validation claim.
- No scheduler/retry service.
- No new source families or dependencies.
- New live traffic is not required for closeout.
- Existing historical ambiguous cases are regression controls, not fabricated temporal-change evidence.

## Review Focus

- One business/domain failure must not corrupt unrelated committed observations in the same run.
- Review projection must not send evidence-only/processor/input/operational events into domain human review.
- Metrics must count reused vs recomputed work consistently across both domains.
- Representative fixtures must distinguish synthetic temporal deltas from historical real-source evidence.
- Closeout documentation must state NOT_RUN/limitations explicitly instead of implying unexecuted live coverage.

---

### Task 1: Add review/audit projection

**Files:**
- Create: `tools/data/lib/history/project-history-review.ps1`
- Create: `tools/data/test-project-history-review.ps1`

**Interfaces:**
- Produces: `Get-HistoryReviewRoute -Comparison -> AUDIT_ONLY|HUMAN_DOMAIN_REVIEW|OPERATIONAL_DIAGNOSTIC|INPUT_VERIFICATION`
- Produces: `ConvertTo-HistoryReviewRow -Comparison -Observation metadata -> object`

- [ ] **Step 1: Write routing tests**

Pin:
- baseline/no delta/evidence-only -> `AUDIT_ONLY`;
- four domain suspected-change/absence candidates -> `HUMAN_DOMAIN_REVIEW`;
- operational failure/comparison unavailable/processor change -> `OPERATIONAL_DIAGNOSTIC`;
- canonical input change -> `INPUT_VERIFICATION`;
- no route creates or changes production state.

- [ ] **Step 2: Run RED**
- [ ] **Step 3: Implement pure projection**
- [ ] **Step 4: Run GREEN**
- [ ] **Step 5: Commit**

### Task 2: Add the Phase 3 integration shadow runner and metrics

**Files:**
- Create: `tools/data/invoke-phase3-history-shadow-mode.ps1`
- Create: `tools/data/test-phase3-history-shadow-mode.ps1`

**Interfaces:**
- Consumes: canonical rows with businessId, domain-specific Phase 3 runners, shared History Store.
- Produces: `Invoke-Phase3HistoryShadowMode -Rows -HistoryRoot -RepositoryRevision -... -> { Runs; Observations; Comparisons; ReviewRows; Summary }`
- Summary includes the efficiency metrics approved in spec section 21.

- [ ] **Step 1: Write integration tests**

Use deterministic rows and request invokers to assert:
- both domains can create baseline observations for one business;
- a later run can produce an evidence-only Benefit delta and unchanged Location;
- a domain operational failure remains committed audit history but does not replace latest comparable;
- one domain failure does not suppress the other domain's valid observation;
- review routing counts are correct;
- `RowsRequested/Completed`, baseline hits/misses, reuse applied/rejected, avoided work, artifact dedup, comparison/review counts are internally consistent.

- [ ] **Step 2: Run RED**
- [ ] **Step 3: Implement thin integration only**

Do not duplicate adapter/comparator/store behavior.

- [ ] **Step 4: Run GREEN**
- [ ] **Step 5: Commit**

### Task 3: Add representative Phase 3 deterministic controls

**Files:**
- Create directory: `tools/data/testdata/phase3-closeout/`
- Create: `tools/data/test-phase3-closeout-validation.ps1`

**Interfaces:**
- Produces fixed deterministic evidence matrix for three groups:
  - unchanged controls;
  - existing historical ambiguity/regression controls;
  - synthetic temporal deltas.

- [ ] **Step 1: Freeze the sample before reading result outputs**

Record selected business IDs/row references and evidence class in a PSD1/JSON manifest. Reuse known historical regression cases such as 버섯집 초리골 / 이지현미용실 / 인헤어 / 짜장마을 only for their documented regression role.

- [ ] **Step 2: Add synthetic fixture pairs**

Must include:
- address A -> B;
- coordinate change;
- 10% -> 20%;
- eligible target change;
- COMPLETE present -> COMPLETE absent;
- canonical input change;
- processor revision change;
- operational failure.

- [ ] **Step 3: Write safety assertions**

Require:
- false `LOCATION_CHANGE_SUSPECTED` = 0;
- false `LOCATION_ABSENCE_SUSPECTED` = 0;
- false `BENEFIT_CHANGE_SUSPECTED` = 0;
- false `BENEFIT_ABSENCE_SUSPECTED` = 0;
- operational failure -> semantic absence = 0;
- processor/input change -> external domain change = 0;
- `ProductionAction != NONE` = 0;
- protected-path writes = 0.

- [ ] **Step 4: Run closeout validation to GREEN**
- [ ] **Step 5: Commit fixtures/test**

### Task 4: Measure efficiency without overstating it

**Files:**
- Modify if needed: `tools/data/invoke-phase3-history-shadow-mode.ps1`
- Modify: `tools/data/test-phase3-history-shadow-mode.ps1`

**Interfaces:**
- Summary must expose:
  `RowsRequested, RowsCompleted, PreviousBaselineHits, PreviousBaselineMisses, EvidenceUnchanged, SemanticUnchanged, SemanticChanged, ReuseEligible, ReuseApplied, ReuseRejected, ExternalFetchCount, ParseCount, MatcherCount, ExtractionCount, EvaluationCount, ArtifactWrites, ArtifactDedupHits, ComparisonCandidates, HumanReviewCandidates, IndexLookupCount, IndexRebuildCount, AvoidedParseCount, AvoidedMatcherCount, AvoidedExtractionCount, AvoidedEvaluationCount`.

- [ ] **Step 1: Add metric consistency tests**
- [ ] **Step 2: Implement only missing aggregation**
- [ ] **Step 3: Run GREEN**
- [ ] **Step 4: Commit**

### Task 5: Run the Phase 3 closeout gate

**Files:**
- Create: `docs/handover/2026-09-26-phase3-snapshot-incremental-closeout.md`
- Modify: `docs/current-work.md`
- Modify: `docs/roadmap.md`
- Modify if needed: `tools/data/README.md`

**Interfaces:**
- Produces: evidence-backed Phase 3 status; no implementation behavior.

- [ ] **Step 1: Run targeted Phase 3 suite**

Run all P3-0 through P3-7 tests.

- [ ] **Step 2: Run required Phase 1/2 regressions**

At minimum runners, discovery/matcher, scoped HTML/MMA/XLSX, run-context, claim comparison, benefit state.

- [ ] **Step 3: Run full data suite once on final HEAD**

```bash
pwsh -NoProfile -Command "Get-ChildItem tools/data -Filter 'test-*.ps1' | Sort-Object Name | ForEach-Object { & $_.FullName }"
```

- [ ] **Step 4: Run Android CI-triggering verification**

Because `data/**` / `tools/data/**` changed, require GitHub Actions `verify-data` and Android `verify` jobs to pass on the final PR HEAD.

- [ ] **Step 5: Run repository hygiene checks**

`git diff --check`; confirm no unauthorized `data/seed/**` or `apps/**` changes and no automatic canonical writes after P3-0.

- [ ] **Step 6: Evaluate all 20 closeout gates one by one**

Each gate in spec section 28 receives `PASS`, `FAIL`, or explicit `NOT_APPLICABLE`; no silent omissions.

- [ ] **Step 7: Write closeout limitations**

Must explicitly state:
- full 496 current-state verification: NOT_RUN unless separately executed;
- periodic scheduler: NOT_IMPLEMENTED;
- provider fetch reduction: not generally guaranteed;
- automatic CLOSED/ENDED decisions: NOT_IMPLEMENTED;
- production auto-write: NOT_APPROVED;
- DB persistence: NOT_APPROVED.

- [ ] **Step 8: Update current-work/roadmap only after gates pass**

If any mandatory gate fails, keep Phase 3 IN PROGRESS and document the blocker instead of marking COMPLETE.

- [ ] **Step 9: Commit documentation**

```bash
git add docs/handover/2026-09-26-phase3-snapshot-incremental-closeout.md docs/current-work.md docs/roadmap.md tools/data/README.md
git commit -m "docs: close out phase 3 snapshot history"
```

### Task 6: Final implementation report

Report:
- changed files;
- implemented behavior;
- tests run;
- tests not run;
- remaining risks;
- next work;
- what became safer;
- what became more efficient;
- duplicate/overstated work avoided;
- remaining bottlenecks;
- concise overall development progress.

Do not mark Phase 4 work as started in the same PR.

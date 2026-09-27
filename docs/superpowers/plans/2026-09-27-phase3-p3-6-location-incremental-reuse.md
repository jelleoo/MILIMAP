# Phase 3 P3-6 Location Incremental Reuse Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add conservative POST_DISCOVERY matcher reuse for one-business Location history runs without changing Phase 1, P3-5 semantics, or History Core.

**Architecture:** The public entrypoint normalizes one canonical row, resolves repository state and the latest comparable Location baseline, then always executes POI discovery exactly once. A Location-only incremental layer computes the current checkpoint, skips matcher only when the full reuse gate passes, otherwise invokes matcher exactly once, then reuses the existing P3-5 observation/comparison path and existing History prepare/commit CAS.

**Tech Stack:** PowerShell 7, existing Phase 1 POI discovery/matching contracts, P3-5 Location History Adapter/Comparator, Phase 3 file History Core/Store/Commit, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-27-phase3-p3-6-location-incremental-reuse-design.md`

## Global Constraints

- Capability is exactly `POST_DISCOVERY`.
- One invocation processes exactly one canonical business.
- POI discovery always executes exactly once on normal runs.
- Matcher executes zero or one time; zero only when the complete reuse gate passes.
- Reuse must not fabricate a `PoiMatchResult`.
- Dirty repository state always rejects reuse and participates in current ExecutionFingerprint through ExecutionConfiguration.
- Existing P3-5 projection/fingerprint/comparison meaning is authoritative and must not be reimplemented.
- Existing History Core/store/commit/CAS is authoritative and must not be modified.
- No provider cache, raw Naver persistence, FULL_EVIDENCE reuse, auto retry, batch transaction, new dependency, schema change, DB/API/auth change, canonical/seed/apps mutation, or MOVED/CLOSED truth.
- If a required change appears outside the expected file boundary, stop and request review before editing.

## File Structure

Production:
- Create: `tools/data/lib/history/location-incremental-reuse.ps1`
  - Location-only checkpoint, baseline resolution, reuse decision, reuse package, metrics helpers.
- Create: `tools/data/invoke-phase3-location-history.ps1`
  - One-business orchestration: canonical row -> normalization -> baseline/repository state -> discovery -> reuse/recompute -> comparison -> prepare/commit.

Tests:
- Create: `tools/data/test-location-incremental-reuse.ps1`
  - Primitive contracts, baseline trust, decision precedence, reuse artifact lineage.
- Create: `tools/data/test-phase3-location-history.ps1`
  - End-to-end one-business orchestration, metrics, failure/concurrency hardening.

Default no-change boundary:
- `tools/data/lib/history/location-history-adapter.ps1`
- `tools/data/lib/history/compare-location-history.ps1`
- Phase 1 production files
- History Core/store/commit
- `data/canonical/**`
- `data/seed/**`
- `apps/**`

## Review Focus

1. Existing P3-5 baseline without P3-6 ExecutionConfiguration must cause one conservative warm-up matcher recompute, not accidental reuse.
2. A missing derived index with existing committed history must not be mistaken for a true first run at commit; existing rebuild/CAS must return `BASELINE_MOVED` without retry.
3. Repeated reuse must not accumulate old `LOCATION_REUSE_DECISION` references transitively.
4. A dirty run must not become reusable by a later clean run with the same repository revision.
5. Projection-artifact corruption may recompute current state, but structural history corruption must stop before provider/matcher work.

---

### Task 1: Location Incremental Primitives

**Files:**
- Create: `tools/data/lib/history/location-incremental-reuse.ps1`
- Create: `tools/data/test-location-incremental-reuse.ps1`

**Interfaces:**
- Consumes:
  - `ConvertTo-LocationHistoryInputProjection -BusinessId -Business`
  - `ConvertTo-LocationHistoryEvidenceProjection -DiscoveryBatch`
  - `ConvertTo-LocationHistoryExecutionProjection -RepositoryRevision -ExecutionConfiguration`
  - `Read-LocationHistorySemanticProjection -Store -Observation`
  - existing History canonical serializer/hash/store helpers.
- Produces:
  - `New-LocationIncrementalExecutionConfiguration -RepositoryClean -> object`
  - `New-LocationIncrementalCheckpoint -BusinessId -Business -DiscoveryBatch -RepositoryRevision -ExecutionConfiguration -> object`
  - `Get-LocationIncrementalBaselineResolution -Store -BusinessId -> object`
  - `Get-LocationIncrementalReuseDecision -BaselineResolution -Checkpoint -RepositoryClean -> object`
  - `New-LocationIncrementalReusePackage -Store -RunId -ObservedAt -Checkpoint -BaselineResolution -Decision -> object`

- [ ] **Step 1: Write RED tests for execution configuration and checkpoint**

Pin:
- execution configuration contains exactly `ProcessingMode=PHASE3_LOCATION_INCREMENTAL`, `IncrementalReuseVersion=1`, and `RepositoryClean`;
- `ReuseApplied` is not part of execution configuration;
- checkpoint Input/Evidence/Execution fingerprints equal the corresponding P3-5 projection fingerprints;
- checkpoint evidence remains invariant for provider physical reorder and duplicate same-query discovery membership.

- [ ] **Step 2: Run Task 1 tests and verify RED**

Run:
```bash
pwsh -NoProfile -File tools/data/test-location-incremental-reuse.ps1
```

Expected: FAIL because P3-6 incremental functions do not exist.

- [ ] **Step 3: Implement `New-LocationIncrementalExecutionConfiguration` and `New-LocationIncrementalCheckpoint`**

Use existing P3-5 projection functions and History fingerprint helpers. Do not copy projection field definitions.

- [ ] **Step 4: Write RED baseline-resolution tests**

Pin:
- no index -> `Status=NONE`, expected baseline ID empty;
- valid latest comparable committed Location baseline -> `Status=VALID`;
- latest non-comparable observation never replaces latest comparable baseline;
- valid lineage + missing/hash-invalid/type-invalid/fingerprint-invalid evidence or semantic artifact -> `Status=ARTIFACT_INVALID` and preserves expected baseline observation ID;
- malformed index, index identity mismatch, indexed observation missing, observation identity mismatch, or non-COMMITTED prior run throws.

- [ ] **Step 5: Implement `Get-LocationIncrementalBaselineResolution`**

Rules:
- perform one `Get-HistoryLatestEntry -Domain LOCATION -ComparableOnly` lookup;
- validate committed observation lineage;
- validate exactly one evidence and one semantic projection;
- read/validate evidence in this Location-only file using the adapter's existing P3-5 evidence order-insensitive-path constant after dot-sourcing `location-history-adapter.ps1`; do not duplicate the path list. If that constant cannot be safely reused in the actual invocation scope, stop and request a tiny helper exposure rather than copying the rules;
- reuse `Read-LocationHistorySemanticProjection` for semantic validation;
- distinguish projection-artifact failure from structural lineage failure exactly as the spec states.

- [ ] **Step 6: Write RED reuse-decision precedence tests**

Assert the first matching reason in this exact order:
1. `PRIOR_ARTIFACT_INVALID`
2. `NO_BASELINE`
3. `DIRTY_REPOSITORY`
4. `CURRENT_DISCOVERY_NOT_COMPLETE`
5. `INPUT_CHANGED`
6. `EXECUTION_CHANGED`
7. `EVIDENCE_CHANGED`
8. `REUSE_ELIGIBLE`

Also pin:
- old P3-5 baseline with different execution fingerprint -> `EXECUTION_CHANGED`;
- dirty-to-dirty still rejects with `DIRTY_REPOSITORY`.

- [ ] **Step 7: Implement `Get-LocationIncrementalReuseDecision`**

Return the Location-domain in-memory decision shape only. Do not change History contracts.

- [ ] **Step 8: Write RED reuse-package tests**

Pin:
- eligible reuse creates fresh RunId/ObservedAt/ObservationId;
- observation uses current Input/Evidence/Execution fingerprints and previous SemanticFingerprint;
- exactly one evidence ref, one semantic ref, one current `LOCATION_REUSE_DECISION` ref;
- no prior reuse audit ref is copied;
- `PreparedArtifacts.Count == 1`;
- the only prepared artifact is `LOCATION_REUSE_DECISION`;
- no synthetic `PoiMatchResult` exists in the path.

- [ ] **Step 9: Implement `New-LocationIncrementalReusePackage`**

Create the audit artifact with:
- `ContractType=LocationReuseDecision`
- `ContractVersion=1`
- `ProcessingMode=REUSED_IDENTICAL_DISCOVERY_EVIDENCE`
- `Capability=POST_DISCOVERY`
- `ReusedFromObservationId`
- Input/Evidence/Execution match flags true
- `RepositoryClean=true`
- `PreviousComparable=true`
- `ReuseApplied=true`
- `ReasonCodes=[REUSE_ELIGIBLE]`

Reuse only the validated baseline evidence and semantic references.

- [ ] **Step 10: Run Task 1 GREEN**

Run:
```bash
pwsh -NoProfile -File tools/data/test-location-incremental-reuse.ps1
pwsh -NoProfile -File tools/data/test-location-history-adapter.ps1
pwsh -NoProfile -File tools/data/test-compare-location-history.ps1
```

Expected: PASS.

- [ ] **Step 11: Commit Task 1**

```bash
git add tools/data/lib/history/location-incremental-reuse.ps1 tools/data/test-location-incremental-reuse.ps1
git commit -m "feat: add location incremental reuse primitives"
```

Stop for review before Task 2.

---

### Task 2: One-Business Location History Orchestration

**Files:**
- Create: `tools/data/invoke-phase3-location-history.ps1`
- Create: `tools/data/test-phase3-location-history.ps1`
- Modify only if proven necessary: Task 1 files.

**Interfaces:**
- Consumes Task 1 functions plus:
  - `Assert-CanonicalBusinessId`
  - `ConvertTo-NormalizedBusiness -Row -SourceRowNumber`
  - `Invoke-PoiDiscovery -Business [-ClientId] [-ClientSecret] [-RequestInvoker]`
  - `Invoke-PoiMatchEvaluation -Business -DiscoveryBatch`
  - `New-LocationHistoryObservationPackage`
  - `Compare-LocationHistoryObservations`
  - `New-HistoryRunManifest`
  - `Prepare-HistoryRun`
  - `Commit-HistoryRun`
- Produces:
  - `Invoke-LocationIncrementalPostDiscovery -Store -RunId -ObservedAt -RepositoryRevision -BusinessId -Business -DiscoveryBatch -BaselineResolution -RepositoryClean -ExecutionConfiguration -> object`
  - `Invoke-Phase3LocationHistory -Store -RunId -ObservedAt -RepositoryRevision -Row -SourceRowNumber -RepositoryStateProvider [-ClientId] [-ClientSecret] [-RequestInvoker] -> object`

- [ ] **Step 1: Write RED first-run orchestration test**

Pin:
- canonical `businessId` validated from the supplied row;
- repository-state provider invoked exactly once;
- baseline resolved before discovery;
- discovery invoked exactly once;
- first run decision is `NO_BASELINE`;
- matcher invoked exactly once;
- comparison is `BASELINE_ESTABLISHED`;
- commit is `COMMITTED`;
- metrics: `RowsRequested=1`, `RowsCompleted=1`, `BaselineHits=0`, `MatcherCount=1`, `AvoidedMatcherCount=0`.

- [ ] **Step 2: Run orchestration test and verify RED**

Run:
```bash
pwsh -NoProfile -File tools/data/test-phase3-location-history.ps1
```

Expected: FAIL because the P3-6 entrypoint does not exist.

- [ ] **Step 3: Implement repository-state boundary and entrypoint skeleton**

Repository-state behavior:
- `RepositoryStateProvider` is mandatory, matching the existing Benefit incremental boundary;
- it returns an object with `IsClean`;
- provider failure is treated conservatively as dirty;
- evaluate exactly once and pass the resulting Boolean through the run;
- the orchestrator does not introduce a second Git-status implementation.

- [ ] **Step 4: Implement first-run recompute path**

Sequence:
1. validate row `businessId`;
2. normalize;
3. build execution configuration;
4. baseline resolution;
5. discovery exactly once;
6. checkpoint/decision;
7. matcher exactly once on rejection;
8. P3-5 package;
9. P3-5 comparison;
10. one-business PREPARED manifest with `StartedAt=ObservedAt`;
11. prepare;
12. commit with expected `<businessId>|LOCATION` baseline.

- [ ] **Step 5: Write RED identical-second-run test**

Pin two committed runs where repository/input/discovery evidence are identical:
- provider calls remain > 0 on run 2;
- discovery invocation count = 1 on run 2;
- decision = `REUSE_ELIGIBLE`;
- matcher invocation count = 0 on run 2;
- `MatcherCount=0`;
- `AvoidedMatcherCount=1`;
- comparison has no delta/change candidate;
- run 2 refs are evidence + semantic + current reuse decision only.

- [ ] **Step 6: Implement reuse path**

Use `New-LocationIncrementalReusePackage`; do not call matcher and do not restage reused evidence/semantic artifacts.

- [ ] **Step 7: Write RED rejection-path tests**

Pin:
- provider physical reorder and duplicate same-query membership still reuse;
- phone/category/provider-link evidence change -> matcher 1 and generic `EVIDENCE_CHANGE_ONLY` when semantic stays equal;
- canonical input change -> matcher 1 and `CANONICAL_INPUT_CHANGED`;
- repository revision/config change -> matcher 1 and `PROCESSOR_OUTPUT_CHANGED`;
- current PARTIAL/FAILED -> matcher 1 and operational unavailable comparison;
- selected -> COMPLETE zero candidate -> matcher 1 and strict absence path.

- [ ] **Step 8: Implement rejected-recompute path without rediscovery**

The already-created `PoiDiscoveryBatch` is the only discovery input to matcher.

The existing P3-5 `New-LocationHistoryObservationPackage` may recompute the current Input/Evidence/Execution projections and fingerprints. This bounded pure-CPU recomputation is accepted on the reuse-rejected path to preserve the stable P3-5 construction/trust boundary. Do not modify P3-5 solely to deduplicate it. After package creation, fail closed unless its Input/Evidence/Execution fingerprints exactly equal the Task 1 checkpoint fingerprints.

- [ ] **Step 9: Implement run-manifest mapping and metrics**

Manifest mapping:
- COMPLETE observation -> ExecutionStatus COMPLETE / CompletedBusinessIds=[id]
- PARTIAL -> PARTIAL / CompletedBusinessIds=[id]
- FAILED -> FAILED / FailedBusinessIds=[id]

Metrics exactly as defined in the spec. `ExternalFetchCount` is count of current discovery attempts where `Status != SKIPPED`.

- [ ] **Step 10: Run Task 2 GREEN and regressions**

Run:
```bash
pwsh -NoProfile -File tools/data/test-phase3-location-history.ps1
pwsh -NoProfile -File tools/data/test-location-incremental-reuse.ps1
pwsh -NoProfile -File tools/data/test-discover-poi-candidates.ps1
pwsh -NoProfile -File tools/data/test-evaluate-poi-match.ps1
pwsh -NoProfile -File tools/data/test-location-history-adapter.ps1
pwsh -NoProfile -File tools/data/test-compare-location-history.ps1
```

Expected: PASS.

- [ ] **Step 11: Commit Task 2**

```bash
git add tools/data/invoke-phase3-location-history.ps1 tools/data/test-phase3-location-history.ps1 tools/data/lib/history/location-incremental-reuse.ps1 tools/data/test-location-incremental-reuse.ps1
git commit -m "feat: orchestrate incremental location history"
```

Stop for review before Task 3.

---

### Task 3: Failure and Concurrency Hardening

**Files:**
- Modify: `tools/data/test-location-incremental-reuse.ps1`
- Modify: `tools/data/test-phase3-location-history.ps1`
- Modify only as failures prove necessary:
  - `tools/data/lib/history/location-incremental-reuse.ps1`
  - `tools/data/invoke-phase3-location-history.ps1`

**Interfaces:**
- Consumes Task 1/2 public interfaces.
- Produces no new production abstraction unless an approved test demonstrates that one is required.

- [ ] **Step 1: Write RED artifact-corruption recovery tests**

Pin:
- structurally valid baseline with corrupt evidence artifact -> `ARTIFACT_INVALID`, matcher 1, comparison null, expected baseline preserved;
- same for semantic artifact;
- successful commit advances latest comparable to the new valid observation;
- no repair of old corrupted artifact is attempted.

- [ ] **Step 2: Write RED structural-corruption tests**

For malformed index, identity mismatch, indexed observation missing, observation identity mismatch, or non-COMMITTED prior run:
- fail before discovery;
- provider call count = 0;
- matcher count = 0;
- no prepare/commit.

- [ ] **Step 3: Write RED latest-comparable preservation test**

Sequence:
- run 1 COMPLETE comparable;
- run 2 PARTIAL non-comparable;
- run 3 COMPLETE.

Assert run 3 baseline is run 1, never run 2.

- [ ] **Step 4: Write RED dirty-run poisoning test**

Sequence:
- clean run A at revision X;
- dirty run B at revision X -> no reuse, matcher 1;
- clean run C at revision X -> no reuse from dirty B, matcher 1;
- dirty-to-dirty remains rejected even when execution fingerprint values otherwise match.

- [ ] **Step 5: Write RED missing-index recovery test**

Sequence:
- commit a valid baseline;
- remove only derived Location index;
- invoke P3-6;
- baseline resolution initially NONE;
- discovery = 1, matcher = 1;
- existing commit-time rebuild finds old baseline;
- commit returns `BASELINE_MOVED`, `RetryRequired=true`;
- current observation/comparison are not authoritative;
- no second discovery/matcher occurs.

- [ ] **Step 6: Write RED baseline-movement tests for both branches**

Eligible-reuse race:
- competing commit occurs after reuse decision, before current commit;
- current result = `BASELINE_MOVED`;
- matcher remains 0;
- current observation/comparison/reuse audit not authoritative.

Rejected-recompute race:
- matcher runs exactly 1 before commit;
- competing baseline causes `BASELINE_MOVED`;
- no automatic retry.

- [ ] **Step 7: Write RED writer-lock test**

With existing `.writer-lock` held:
- discovery/recompute work still occurs outside the lock;
- commit returns `WRITER_LOCKED`;
- `RetryRequired=false`;
- no current authoritative publish;
- no hidden retry.

- [ ] **Step 8: Write RED three-run artifact-lineage test**

Assert:
- run 1 refs = E1,S1;
- run 2 refs = E1,S1,R2;
- run 3 refs = E1,S1,R3;
- R2 absent from run 3;
- each reuse has `PreparedArtifacts.Count=1`.

- [ ] **Step 9: Implement only minimal fixes required by Steps 1-8**

Do not add a repair subsystem, retry scheduler, full-history scan, or shared Benefit/Location framework.

- [ ] **Step 10: Run Task 3 GREEN and related History regressions**

Run:
```bash
pwsh -NoProfile -File tools/data/test-location-incremental-reuse.ps1
pwsh -NoProfile -File tools/data/test-phase3-location-history.ps1
pwsh -NoProfile -File tools/data/test-history-store.ps1
pwsh -NoProfile -File tools/data/test-commit-history-run.ps1
pwsh -NoProfile -File tools/data/test-compare-history-observations.ps1
pwsh -NoProfile -File tools/data/test-benefit-incremental-reuse.ps1
```

Expected: PASS.

- [ ] **Step 11: Commit Task 3**

```bash
git add tools/data/lib/history/location-incremental-reuse.ps1 tools/data/invoke-phase3-location-history.ps1 tools/data/test-location-incremental-reuse.ps1 tools/data/test-phase3-location-history.ps1
git commit -m "test: harden location incremental reuse"
```

Stop for review before Task 4.

---

### Task 4: Final Verification and PR Preparation

**Files:**
- No production expansion expected.
- Include the approved P3-6 spec and this plan in the implementation PR if they are not already present on the implementation branch.

**Interfaces:**
- Consumes completed Tasks 1-3.
- Produces one P3-6 PR against `dev`; does not merge.

- [ ] **Step 1: Fetch and verify baseline**

Run:
```bash
git fetch origin
git status --short
git merge-base HEAD origin/dev
```

If `origin/dev` changed in P3-6-relevant Phase 1/P3-5/History files, stop and report before rebasing or editing.

- [ ] **Step 2: Run all P3-6 targeted tests**

```bash
pwsh -NoProfile -File tools/data/test-location-incremental-reuse.ps1
pwsh -NoProfile -File tools/data/test-phase3-location-history.ps1
```

Expected: PASS.

- [ ] **Step 3: Run Phase 1 and P3-5 regressions**

```bash
pwsh -NoProfile -File tools/data/test-poi-verification-contracts.ps1
pwsh -NoProfile -File tools/data/test-discover-poi-candidates.ps1
pwsh -NoProfile -File tools/data/test-evaluate-poi-match.ps1
pwsh -NoProfile -File tools/data/test-phase1-poi-shadow-mode.ps1
pwsh -NoProfile -File tools/data/test-location-history-adapter.ps1
pwsh -NoProfile -File tools/data/test-compare-location-history.ps1
```

Expected: PASS.

- [ ] **Step 4: Run History/Benefit regressions**

```bash
pwsh -NoProfile -File tools/data/test-history-contracts.ps1
pwsh -NoProfile -File tools/data/test-history-fingerprints.ps1
pwsh -NoProfile -File tools/data/test-history-store.ps1
pwsh -NoProfile -File tools/data/test-commit-history-run.ps1
pwsh -NoProfile -File tools/data/test-compare-history-observations.ps1
pwsh -NoProfile -File tools/data/test-benefit-history-adapter.ps1
pwsh -NoProfile -File tools/data/test-benefit-incremental-reuse.ps1
```

Expected: PASS.

- [ ] **Step 5: Run the full data suite once on final production HEAD**

Execute every `tools/data/test-*.ps1` using the repository's established full-suite pattern.

Report total scripts, passed, failed, and exact failures. Any production change after this point requires rerunning the full suite.

- [ ] **Step 6: Run Android final gate**

Run the repository's established Gradle invocation for:
- `testDebugUnitTest`
- `lintDebug`
- `assembleDebug`

Report counts/results; environment failures are not PASS.

- [ ] **Step 7: Repository hygiene**

Run:
```bash
git diff --check origin/dev...HEAD
git status --short
```

Confirm no diff under:
- `data/canonical/**`
- `data/seed/**`
- `apps/**`

- [ ] **Step 8: Whole-branch architecture review**

Explicitly verify:
- discovery exactly once on normal runs;
- matcher only after decision, zero/one only;
- no rediscovery on rejection;
- repository state evaluated once;
- no P3-5 fingerprint-rule duplication;
- no synthetic matcher result;
- latest comparable baseline only;
- reuse refs exactly E+S+current R;
- reused E/S are not restaged;
- dirty runs never reuse and cannot poison later clean runs;
- structural corruption stops pre-network;
- projection corruption recomputes without comparison;
- expensive work remains outside writer lock;
- no auto retry after `BASELINE_MOVED`/`WRITER_LOCKED`;
- no new History/Phase 1 contract/schema;
- no provider-cache/full-scan/generic-framework expansion.

If a Critical/Important issue is found, add a RED regression before fixing it.

- [ ] **Step 9: Include approved docs**

Bring into the implementation branch unchanged except for necessary status metadata:
- `docs/superpowers/specs/2026-09-27-phase3-p3-6-location-incremental-reuse-design.md`
- `docs/superpowers/plans/2026-09-27-phase3-p3-6-location-incremental-reuse.md`

- [ ] **Step 10: Push and open one PR**

Recommended branch:
`codex/phase3-p3-6-location-incremental-reuse`

Recommended title:
`[Phase 3 P3-6] Add Location incremental matcher reuse`

PR body must include:
- Closes the P3-6 Issue;
- problem/scope/non-scope;
- changed files;
- Task 1-3 RED->GREEN ledger;
- two-run matcher-skip evidence;
- dirty/corruption/CAS behavior;
- metrics;
- full-suite/Android results;
- protected paths;
- remaining risks;
- P3-7 NOT STARTED.

- [ ] **Step 11: Wait for CI and stop before merge**

Require current repository checks, including `verify-data` and `verify`, to pass. Do not merge.

## Final Report

Report:

- final HEAD SHA;
- `origin/dev` SHA and merge-base;
- branch;
- PR number/link/state/mergeability;
- changed files;
- RED -> GREEN ledger;
- first-run and identical-second-run provider/matcher counts;
- rejection matrix;
- dirty-run poisoning result;
- artifact-lineage result;
- artifact/structural corruption result;
- missing-index result;
- BASELINE_MOVED / WRITER_LOCKED result;
- targeted regressions;
- full data suite;
- Android verification;
- CI;
- `git diff --check`;
- protected paths;
- tests not run;
- remaining risks;
- next work = P3-7, NOT STARTED.

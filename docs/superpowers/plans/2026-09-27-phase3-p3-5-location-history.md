# Phase 3 P3-5 Location History Adapter / Comparator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Location-domain Phase 3 history adapter and comparator on top of the existing History Core without changing Phase 1 behavior or implementing matcher reuse.

**Architecture:** Phase 1 remains the source of current-state normalization, discovery, and matching. P3-5 projects `NormalizedBusiness`, `PoiDiscoveryBatch`, and `PoiMatchResult` into the four existing History fingerprints, persists immutable Location observations, and delegates generic precedence to `Compare-HistoryObservations` before applying a narrow field-level Location resolver.

**Tech Stack:** PowerShell 7, existing Phase 1 POI verification contracts/runners, shared Phase 3 History Core/Store, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-27-phase3-p3-5-location-history-design.md`

## Global Constraints

- P3-5 only; P3-6 matcher reuse is out of scope.
- No Phase 1 public-contract or production behavior change.
- No History Core/schema change.
- No raw Naver response persistence.
- No DB/API/auth/dependency change.
- No canonical/seed/apps modification.
- No MOVED/CLOSED truth labels.
- CandidateKey is not temporal identity.
- EvidenceFingerprint must be computable before matcher execution.
- Generic comparison precedence stays in `Compare-HistoryObservations`.
- If implementation appears to require Phase 1 production or History Core changes, STOP and report before editing.

## Review Focus

- Random provider result ordering must not perturb EvidenceFingerprint.
- Duplicate discovery appearances from the same query membership must not perturb EvidenceFingerprint.
- CandidateKey/phone/category/provider-link changes must not create false Location semantic change.
- Selection-only confidence changes must not create `LOCATION_CHANGE_SUSPECTED`.
- PARTIAL/FAILED discovery or matcher INCOMPLETE must never create location absence.

---

### Task 1: Add Location projections and fingerprint mutation matrix

**Files:**
- Create: `tools/data/lib/history/location-history-adapter.ps1`
- Create: `tools/data/test-location-history-adapter.ps1`

**Interfaces:**
- Consumes: `NormalizedBusiness`, `PoiDiscoveryBatch`, `PoiMatchResult`, existing History fingerprint helpers.
- Produces:
  - `ConvertTo-LocationHistoryInputProjection -BusinessId -Business -> object`
  - `ConvertTo-LocationHistoryEvidenceProjection -DiscoveryBatch -> object`
  - `ConvertTo-LocationHistorySemanticProjection -DiscoveryBatch -Result -> object`
  - `ConvertTo-LocationHistoryExecutionProjection -RepositoryRevision [-ExecutionConfiguration] -> object`

- [ ] **Step 1: Write RED tests for InputFingerprint**

Pin:
- `SourceRowNumber`, `AddressParseStatus`, `NormalizationWarnings` do not change the input projection fingerprint.
- name/branch/address/locality/road/building/floor/unit mutations do change it.

- [ ] **Step 2: Write RED tests for EvidenceFingerprint**

Pin equality under:
- candidate array reorder;
- `DiscoveredBy[]` reorder;
- duplicate `DiscoveredBy` membership for the same `(StrategyCode, Query, QueryOrder)`;
- `QueryAttempts[]` physical reorder;
- ResultPosition / ResultCount changes;
- CandidateKey-only change.

Pin inequality under:
- candidate name/address/coordinate/phone/category/provider-link changes;
- query strategy/query/order/status/error changes;
- candidate discovery-query membership changes;
- discovery status changes.

- [ ] **Step 3: Write RED tests for SemanticFingerprint**

Pin equality under:
- CandidateKey-only change;
- RankedCandidateKeys change;
- phone/category/provider-link change;
- matcher-internal evidence changes;
- candidate count/order changes when selected/evaluation meaning is unchanged.

Pin inequality under:
- selected normalized name/address/coordinates;
- SELECTED/NONE;
- classification;
- material outcome reason set;
- material conflict set;
- AbsenceEligible.

Also pin:
- selected name/road/lot address normalization uses `ConvertTo-PoiMatchCompactText`;
- invariant coordinate serialization survives culture changes.

- [ ] **Step 4: Run RED**

Run:
```bash
pwsh -NoProfile -File tools/data/test-location-history-adapter.ps1
```

Expected: FAIL because Location adapter functions do not yet exist.

- [ ] **Step 5: Implement the four projection functions**

Implementation constraints:
- reuse `ConvertTo-PoiMatchCompactText`; do not create a new text/address normalizer;
- Evidence projection reads only `PoiDiscoveryBatch`;
- distinct `DiscoveredBy` by `StrategyCode + Query + QueryOrder` before canonical serialization;
- use existing History canonical serializer/fingerprint helpers;
- do not hash CandidateKey itself;
- material semantic reasons are exactly the six approved outcome reasons in the spec.

- [ ] **Step 6: Run GREEN**

Run:
```bash
pwsh -NoProfile -File tools/data/test-location-history-adapter.ps1
```

Expected: PASS.

- [ ] **Step 7: Run focused Phase 1 contract regressions**

Run:
```bash
pwsh -NoProfile -File tools/data/test-poi-verification-contracts.ps1
pwsh -NoProfile -File tools/data/test-evaluate-poi-match.ps1
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add tools/data/lib/history/location-history-adapter.ps1 tools/data/test-location-history-adapter.ps1
git commit -m "feat: add location history projections"
```

---

### Task 2: Add Location observation package and staged semantic validation

**Files:**
- Modify: `tools/data/lib/history/location-history-adapter.ps1`
- Modify: `tools/data/test-location-history-adapter.ps1`

**Interfaces:**
- Consumes: Task 1 projection functions, existing History store/artifact/observation helpers.
- Produces:
  - `Get-LocationHistoryOperationalAssessment -DiscoveryBatch -Result -> object`
  - `New-LocationHistoryObservationPackage -Store -RunId -BusinessId -ObservedAt -RepositoryRevision -Business -DiscoveryBatch -Result [-ExecutionConfiguration] -> object`
  - `Read-LocationHistorySemanticProjection -Store -Observation -> object`
  - internal staged-current semantic validator used only by Location comparison.

- [ ] **Step 1: Write RED tests for operational/comparable matrix**

Pin:
- COMPLETE discovery + COMPLETE evaluation => COMPLETE/comparable true;
- COMPLETE + INCOMPLETE => PARTIAL/non-comparable;
- PARTIAL + INCOMPLETE => PARTIAL/non-comparable;
- FAILED + INCOMPLETE => FAILED/non-comparable;
- COMPLETE YELLOW/RED may still be comparable;
- strict absence eligibility only matches the approved zero-candidate contract.

- [ ] **Step 2: Write RED tests for prepared artifacts and observation package**

Pin:
- exactly one `LOCATION_EVIDENCE_PROJECTION` and one `LOCATION_SEMANTIC_PROJECTION`;
- `SemanticResultReference` matches the semantic artifact reference;
- fingerprints match the Task 1 projections;
- fresh RunId produces a distinct observation identity for identical evidence;
- no raw Naver payload artifact is created.

- [ ] **Step 3: Write RED tests for store-backed and staged semantic trust**

Pin:
- committed previous semantic projection reads successfully;
- staged current succeeds only when type/version/fingerprint/reference/content hash all match;
- tampered fingerprint/hash/reference/type/version fails closed;
- unpublished previous semantic artifact is rejected;
- no generic public trust/bypass parameter is added.

- [ ] **Step 4: Run RED**

Run:
```bash
pwsh -NoProfile -File tools/data/test-location-history-adapter.ps1
```

Expected: FAIL on the new observation-package contracts.

- [ ] **Step 5: Implement observation packaging**

Use the existing Benefit adapter pattern only as a structural reference:
- do not extract a shared adapter framework;
- use existing `New-HistoryFingerprintSet`, artifact path/reference helpers, `New-HistoryObservation`;
- keep all Location-specific semantics in the Location adapter.

- [ ] **Step 6: Implement staged-current semantic validation**

Previous remains committed/store-backed. Current may be in-memory only through the internal validated seam.

- [ ] **Step 7: Run GREEN and History regressions**

Run:
```bash
pwsh -NoProfile -File tools/data/test-location-history-adapter.ps1
pwsh -NoProfile -File tools/data/test-history-contracts.ps1
pwsh -NoProfile -File tools/data/test-history-fingerprints.ps1
pwsh -NoProfile -File tools/data/test-history-store.ps1
pwsh -NoProfile -File tools/data/test-benefit-history-adapter.ps1
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add tools/data/lib/history/location-history-adapter.ps1 tools/data/test-location-history-adapter.ps1
git commit -m "feat: package location history observations"
```

---

### Task 3: Add the Location domain comparator

**Files:**
- Create: `tools/data/lib/history/compare-location-history.ps1`
- Create: `tools/data/test-compare-location-history.ps1`

**Interfaces:**
- Consumes: Location semantic projections/observations from Tasks 1-2 and `Compare-HistoryObservations`.
- Produces:
  - `Resolve-LocationHistoryChange -PreviousProjection -CurrentProjection -> { ChangeCandidates; ReasonCodes }`
  - `Compare-LocationHistoryObservations -Store -Previous -Current [-StagedCurrentSemanticProjection] -> ObservationComparison`

- [ ] **Step 1: Write RED tests for common precedence delegation**

Pin through `Compare-LocationHistoryObservations`:
- no previous => `BASELINE_ESTABLISHED`;
- current FAILED/PARTIAL => common operational failure/unavailable;
- InputFingerprint change => `CANONICAL_INPUT_CHANGED`;
- ExecutionFingerprint change => `PROCESSOR_OUTPUT_CHANGED`;
- evidence-only change => `EVIDENCE_CHANGE_ONLY`;
- no delta => no change candidate.

The Location resolver must not duplicate these branches.

- [ ] **Step 2: Write RED tests for material selected-location changes**

Pin:
- selected name delta => one `LOCATION_CHANGE_SUSPECTED` + `LOCATION_NAME_CHANGED`;
- road/lot address delta => one candidate + `LOCATION_ADDRESS_CHANGED`;
- coordinate delta => one candidate + `LOCATION_COORDINATE_CHANGED`;
- name+address+coordinate => still one candidate, all applicable reasons.

- [ ] **Step 3: Write RED tests for strict absence and selection-only changes**

Pin:
- previous SELECTED + current strict complete zero-candidate => `LOCATION_ABSENCE_SUSPECTED` only, with `LOCATION_SELECTION_CHANGED` and `COMPLETE_NO_CANDIDATE`;
- selected -> ambiguous NONE => no Location change candidate, reason `LOCATION_SELECTION_CHANGED`;
- NONE -> selected => no Location change candidate, reason `LOCATION_SELECTION_CHANGED`;
- NONE/RED -> NONE/YELLOW => no Location candidate, reason `LOCATION_EVALUATION_CHANGED`.

- [ ] **Step 4: Write RED tests for CandidateKey/provider-only mutations**

Pin:
- CandidateKey-only semantic-equivalent change => no `LOCATION_CHANGE_SUSPECTED`;
- phone/category/provider-link-only evidence mutation => `EVIDENCE_CHANGE_ONLY`, not Location change.

- [ ] **Step 5: Run RED**

Run:
```bash
pwsh -NoProfile -File tools/data/test-compare-location-history.ps1
```

Expected: FAIL because comparator functions do not yet exist.

- [ ] **Step 6: Implement `Resolve-LocationHistoryChange`**

Rules:
- compare normalized selected Name/RoadAddress/LotAddress and exact numeric coordinates;
- strict absence has precedence over all other Location domain candidates;
- selection-only and evaluation-only changes produce audit reasons but no Location change candidate;
- do not emit MOVED/CLOSED;
- deterministic reason ordering.

- [ ] **Step 7: Implement `Compare-LocationHistoryObservations`**

Call `Compare-HistoryObservations` first. Invoke the Location resolver only when generic precedence leaves a semantic domain resolution to perform. Use the validated staged-current seam from Task 2.

- [ ] **Step 8: Run GREEN plus Phase 1/History regressions**

Run:
```bash
pwsh -NoProfile -File tools/data/test-compare-location-history.ps1
pwsh -NoProfile -File tools/data/test-location-history-adapter.ps1
pwsh -NoProfile -File tools/data/test-discover-poi-candidates.ps1
pwsh -NoProfile -File tools/data/test-evaluate-poi-match.ps1
pwsh -NoProfile -File tools/data/test-benefit-history-adapter.ps1
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add tools/data/lib/history/compare-location-history.ps1 tools/data/test-compare-location-history.ps1
git commit -m "feat: add location history comparator"
```

---

### Task 4: Final P3-5 verification and PR preparation

**Files:**
- No production-file expansion is expected.
- Update documentation/status only if existing repository workflow requires it.

**Interfaces:**
- Consumes: completed Tasks 1-3.
- Produces: one P3-5 implementation PR against `dev`.

- [ ] **Step 1: Run all P3-5 targeted tests**

```bash
pwsh -NoProfile -File tools/data/test-location-history-adapter.ps1
pwsh -NoProfile -File tools/data/test-compare-location-history.ps1
```

Expected: PASS.

- [ ] **Step 2: Run Phase 1 regressions**

```bash
pwsh -NoProfile -File tools/data/test-poi-verification-contracts.ps1
pwsh -NoProfile -File tools/data/test-discover-poi-candidates.ps1
pwsh -NoProfile -File tools/data/test-evaluate-poi-match.ps1
pwsh -NoProfile -File tools/data/test-phase1-poi-shadow-mode.ps1
```

Expected: PASS.

- [ ] **Step 3: Run History regressions**

```bash
pwsh -NoProfile -File tools/data/test-history-contracts.ps1
pwsh -NoProfile -File tools/data/test-history-fingerprints.ps1
pwsh -NoProfile -File tools/data/test-history-store.ps1
pwsh -NoProfile -File tools/data/test-commit-history-run.ps1
pwsh -NoProfile -File tools/data/test-benefit-history-adapter.ps1
```

Expected: PASS.

- [ ] **Step 4: Run full data suite once on final HEAD**

Run all `tools/data/test-*.ps1` using the repository's established full-suite command/pattern.

Expected: PASS.

- [ ] **Step 5: Run repository final gates**

Run:
- `git diff --check origin/dev...HEAD`;
- protected-path diff for `data/canonical/**`, `data/seed/**`, `apps/**`;
- Android `testDebugUnitTest lintDebug assembleDebug` if required by current CI/local verification flow.

Expected:
- no diff-check errors;
- no protected path changes;
- Android gate PASS.

- [ ] **Step 6: Whole-branch self-review**

Check specifically for:
- CandidateKey temporal-identity leakage;
- matcher result leaking into EvidenceFingerprint;
- duplicate common comparison precedence;
- new Phase 1 behavior;
- full-history scan;
- pre-comparison artifact publication;
- generic trust bypass;
- false absence/change candidate;
- unnecessary shared refactor.

If any Critical/Important issue is found, add a RED regression before fixing.

- [ ] **Step 7: Prepare one Issue/PR**

Do not start P3-6. Push the P3-5 branch, open/update one P3-5 PR against `dev`, run CI, and stop before merge for architecture review.

---

## Expected file boundary

Production:
- `tools/data/lib/history/location-history-adapter.ps1`
- `tools/data/lib/history/compare-location-history.ps1`

Tests:
- `tools/data/test-location-history-adapter.ps1`
- `tools/data/test-compare-location-history.ps1`

Any additional production-file change requires explanation before editing.

## Final report

Report:
- final HEAD SHA;
- dev merge-base;
- changed files;
- RED -> GREEN ledger per task;
- targeted/full-suite results;
- Android and CI results;
- protected-path result;
- implementation summary;
- tests not run;
- remaining risks;
- next task = P3-6, not started.

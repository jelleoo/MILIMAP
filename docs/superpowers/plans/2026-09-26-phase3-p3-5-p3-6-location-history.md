# Phase 3 P3-5/P3-6 Location History and Incremental Reuse Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Project Phase 1 POI discovery/matching into Phase 3 history, detect safe Location change candidates, and skip only matcher work when current complete discovery evidence is identical.

**Architecture:** A Location adapter fingerprints canonical identity inputs, the complete structured `PoiDiscoveryBatch`, and a semantic projection of `PoiMatchResult`. The comparator uses field-level name/address/coordinate/selection/evaluation dimensions rather than raw `CandidateKey`. Current POI discovery still executes; only matcher computation is reusable in v1.

**Tech Stack:** PowerShell 7, existing Phase 1 POI verification contracts/runners, shared Phase 3 History Core/Store.

**Spec:** `docs/superpowers/specs/2026-09-26-phase3-snapshot-incremental-change-detection-design.md`

## Global Constraints

- No new Naver raw-response persistence subsystem.
- POI discovery still runs in Phase 3 v1.
- Reuse applies only after COMPLETE discovery with unchanged input/evidence/execution/version.
- CandidateKey alone is never treated as stable business identity or movement proof.
- Phone/category/provider-link-only changes must not create `LOCATION_CHANGE_SUSPECTED`.
- PARTIAL/FAILED discovery can never create location absence.
- ProductionAction remains `NONE`.
- No canonical/seed/apps write.

## Review Focus

- Naver search result order may vary; equivalent candidate/discovery evidence must canonicalize deterministically where order has no semantic meaning.
- Repeated-discovery evidence used by matcher must remain in EvidenceFingerprint.
- Candidate phone/link/category changes must not become movement.
- Coordinate precision/serialization must not change with locale.
- COMPLETE zero-candidate and request failure must remain distinguishable.

---

### Task 1: Create Location history projections

**Files:**
- Create: `tools/data/lib/history/location-history-adapter.ps1`
- Create: `tools/data/test-location-history-adapter.ps1`

**Interfaces:**
- Consumes: `NormalizedBusiness`, `PoiDiscoveryBatch`, `PoiMatchResult`, candidate diagnostics.
- Produces: `New-LocationHistoryInputProjection -BusinessId -Business -> object`
- Produces: `New-LocationHistoryEvidenceProjection -DiscoveryBatch -CandidateDiagnostics -> object`
- Produces: `New-LocationHistorySemanticProjection -Result -> object`
- Produces: `ConvertTo-LocationHistoryObservation -... -> HistoryObservation`

- [ ] **Step 1: Write the mutation matrix**

Assert:
- SourceRowNumber does not affect input fingerprint;
- name/address/locality fields used by Phase 1 do;
- candidate/result ordering that is semantically order-insensitive canonicalizes;
- `DiscoveredBy` evidence participates because matcher uses repeated discovery;
- phone/category/provider-link-only candidate mutation changes evidence but not location semantic projection;
- selected address/coordinate/classification/reason/conflict mutation changes semantic projection;
- invariant coordinate formatting under culture changes.

- [ ] **Step 2: Run RED**

Run: `pwsh -NoProfile -File tools/data/test-location-history-adapter.ps1`  
Expected: FAIL.

- [ ] **Step 3: Implement adapter using shared serializer**

Do not duplicate `Get-PoiDiscoveryCandidateKey` as a business identity rule. Preserve the fields needed to reproduce matcher evidence.

- [ ] **Step 4: Run GREEN**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tools/data/lib/history/location-history-adapter.ps1 tools/data/test-location-history-adapter.ps1
git commit -m "feat: add location history adapter"
```

### Task 2: Add Location domain comparator

**Files:**
- Create: `tools/data/lib/history/compare-location-history.ps1`
- Create: `tools/data/test-compare-location-history.ps1`

**Interfaces:**
- Produces: `Resolve-LocationHistoryChange -PreviousProjection -CurrentProjection -> { ChangeCandidates; ReasonCodes; DomainDeltaDimensions }`
- Allowed dimensions: `NAME|ADDRESS|COORDINATE|SELECTION|EVALUATION`.

- [ ] **Step 1: Write comparator tests**

Pin:
- address change -> `LOCATION_CHANGE_SUSPECTED + ADDRESS`;
- coordinate-only change -> candidate + `COORDINATE`;
- name+address -> both dimensions;
- CandidateKey-only change caused by phone/link/category -> no Location semantic candidate;
- prior selected candidate + current COMPLETE/COMPLETE genuine `NO_CANDIDATE` -> `LOCATION_ABSENCE_SUSPECTED`;
- PARTIAL/FAILED/provider error -> no absence;
- input/execution changes are intercepted by common precedence before this resolver.

- [ ] **Step 2: Run RED**

Run: `pwsh -NoProfile -File tools/data/test-compare-location-history.ps1`.

- [ ] **Step 3: Implement field-level resolver**

Do not emit MOVED/CLOSED/RENAMED truth labels.

- [ ] **Step 4: Run GREEN plus Phase 1 matcher regressions**

Run:
```bash
pwsh -NoProfile -File tools/data/test-compare-location-history.ps1
pwsh -NoProfile -File tools/data/test-evaluate-poi-match.ps1
pwsh -NoProfile -File tools/data/test-discover-poi-candidates.ps1
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tools/data/lib/history/compare-location-history.ps1 tools/data/test-compare-location-history.ps1
git commit -m "feat: add location change candidate comparator"
```

### Task 3: Add Phase 1 runner seam only if matcher reuse requires it

**Files:**
- Modify only if required after latest-`dev` inspection:
  - `tools/data/invoke-phase1-poi-shadow-mode.ps1`
- Create: `tools/data/test-phase3-location-reuse-boundary.ps1`

**Interfaces:**
- Required capability: after `Invoke-PoiDiscovery` returns a COMPLETE batch, Phase 3 can compare its EvidenceFingerprint before invoking `Invoke-PoiMatchEvaluation`.
- Existing Phase 1 standalone runner behavior must remain unchanged.

- [ ] **Step 1: Inspect call path**

Current known flow is normalize -> `Invoke-PoiDiscovery` -> `Invoke-PoiMatchEvaluation`. If Phase 3 can orchestrate those existing public functions itself without duplicating logic, make no Phase 1 production change.

- [ ] **Step 2: Add a boundary test**

Prove discovery and matcher are independently invocable with the same contracts and that no hidden runner state is required.

- [ ] **Step 3: Run test**

Expected: PASS without production change if current boundary is already sufficient. If not, stop and propose the smallest extraction before editing Phase 1.

- [ ] **Step 4: Commit boundary test if useful**

Do not refactor just for stylistic symmetry.

### Task 4: Add Location incremental history orchestration

**Files:**
- Create: `tools/data/invoke-phase3-location-history.ps1`
- Create: `tools/data/test-phase3-location-history.ps1`

**Interfaces:**
- Produces: `Invoke-Phase3LocationHistory -Rows -HistoryRoot -RepositoryRevision -RequestInvoker/credentials -> run result`
- Result metrics include `MatcherCount`, `AvoidedMatcherCount`, baseline/reuse/change/review counts.

- [ ] **Step 1: Write two-run reuse tests**

Assert:
- first run performs discovery + matcher and commits;
- second run with same input and complete identical discovery still performs discovery but skips matcher;
- new observation has fresh time/run identity and references prior semantic result;
- evidence mutation forces matcher;
- input or repository revision change forces matcher;
- current PARTIAL/FAILED discovery forces matcher/no reuse and cannot generate absence;
- COMPLETE genuine zero-candidate may create absence candidate only against a prior comparable selected candidate.

- [ ] **Step 2: Run RED**

Run: `pwsh -NoProfile -File tools/data/test-phase3-location-history.ps1`.

- [ ] **Step 3: Implement POST_DISCOVERY capability**

Use existing `ConvertTo-NormalizedBusiness`, `Invoke-PoiDiscovery`, `Invoke-PoiMatchEvaluation`. Do not copy query planning or matcher rules into Phase 3.

- [ ] **Step 4: Run GREEN and Phase 1 regressions**

Run:
```bash
pwsh -NoProfile -File tools/data/test-phase3-location-history.ps1
pwsh -NoProfile -File tools/data/test-phase1-poi-shadow-mode.ps1
pwsh -NoProfile -File tools/data/test-discover-poi-candidates.ps1
pwsh -NoProfile -File tools/data/test-evaluate-poi-match.ps1
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tools/data/invoke-phase3-location-history.ps1 tools/data/test-phase3-location-history.ps1
git commit -m "feat: add location history incremental reuse"
```

### Task 5: P3-5/P3-6 final gate

- [ ] **Step 1: Run all Location Phase 3 targeted tests**
- [ ] **Step 2: Run Phase 1 deterministic regressions**
- [ ] **Step 3: Confirm discovery count is unchanged while matcher avoidance is measurable**
- [ ] **Step 4: Confirm false absence/change count is zero in fixtures**
- [ ] **Step 5: Run full data suite once on final PR HEAD**
- [ ] **Step 6: Report that provider query reduction is deferred; only matcher work is avoided in v1**

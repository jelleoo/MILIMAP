# Phase 3 P3-7 Review/Audit Projection + Closeout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a read-only Phase 3 review/audit projection, repo-reproducible representative validation, and evidence-based Phase 3 closeout without changing History Core or production data.

**Architecture:** P3-7 consumes the existing file History Store as an offline read-only client. It establishes COMMITTED run authority, linearly joins observations and comparisons, validates unique referenced artifacts once, projects known change candidates into four review routes, then validates representative A/B/C controls and records Phase 3 closeout evidence.

**Tech Stack:** PowerShell 7+, existing Phase 3 History Core/store/contracts, existing Location/Benefit adapters/comparators, PSD1 deterministic fixtures, repository script-test pattern.

**Spec:** `docs/superpowers/specs/2026-09-27-phase3-p3-7-review-audit-closeout-design.md`

## Global Constraints

- Baseline is latest `origin/dev`; this plan was authored from `dev@e9585884773fa28cec991439987a3ba83dae4bb5`.
- P3-7 is a read-only consumer of the existing Phase 3 file History Store.
- Do not change History Core contracts/store/commit/fingerprint semantics.
- Do not change P3-3/P3-4 Benefit history semantics or P3-5/P3-6 Location history semantics.
- Do not change Phase 1/2 production logic.
- Do not add DB/API/auth/dependency changes.
- Do not create a persisted review queue, review-status store, scheduler, repair subsystem, or new history index.
- Do not infer MOVED/CLOSED/CHANGED/ENDED production truth.
- Do not mutate `data/canonical/**`, `data/seed/**`, or `apps/**`.
- Historical source-cited controls must not be relabeled as temporal ground truth.
- Synthetic temporal fixtures must be explicitly labeled synthetic.
- New live provider requests are not a P3-7 closeout requirement.
- Audit scans must not call `New-HistoryStoreLayout`, `Rebuild-HistoryIndexes`, Phase 1 discovery/matcher, or Phase 2 fetch/parse/evaluation.
- Audit scan complexity must remain linear in runs + observations + comparisons + unique artifact references.
- Same physical artifact reference is hash-validated at most once per audit invocation.
- Intermediate tasks run focused regressions only; full data suite/Android/CI belong to Task 4.
- Each task ends with local review and STOP before the next task.
- If implementation requires any protected architecture/data change above, STOP and request approval.

## Review Focus

1. **A physically present record from a non-COMMITTED run** — must never become an authoritative review item; Task 2 pins ignore/count behavior.
2. **A future comparison candidate unknown to P3-7** — must fail closed rather than silently route; Task 1 pins unknown-candidate failure.
3. **Mixed route categories in one comparison, including RECORD_ONLY + non-record** — must fail closed as a routing conflict; Task 1 pins mixed-category failure.
4. **Many observations sharing one content-addressed artifact** — must validate the physical artifact once per invocation, not once per observation; Task 2 pins call-count deduplication.
5. **Historical ambiguity accidentally treated as real temporal change** — must remain `TemporalTruthStatus=NOT_ESTABLISHED`; Task 3 pins provenance-only Group B semantics.

---

## File Map

### New production/read-model files

- `tools/data/lib/history/phase3-review-audit.ps1`
  - pure review-route taxonomy;
  - review-item construction;
  - summary construction;
  - no filesystem enumeration.

- `tools/data/invoke-phase3-review-audit.ps1`
  - read-only committed-history scanner;
  - committed lineage validation;
  - observation/comparison join;
  - unique artifact validation memoization;
  - returns `Items` + `Summary`.

### New tests / fixtures

- `tools/data/test-phase3-review-audit.ps1`
  - Task 1 pure projection tests;
  - Task 2 store scan/corruption/memoization tests.

- `tools/data/testdata/phase3-closeout/representative-results.psd1`
  - A/B/C closeout provenance and exact expected route/candidate/reason/audit-flag sets.

- `tools/data/test-phase3-closeout-validation.ps1`
  - representative matrix integrity;
  - deterministic A/C replay;
  - Group B provenance-only safety;
  - aggregate zero-safety gates.

### Task 4 closeout documentation

- `docs/handover/2026-09-27-phase3-snapshot-incremental-closeout.md`
- modify only after final gates pass:
  - `docs/current-work.md`
  - `docs/current-status.md`
  - `docs/roadmap.md`
  - `tools/data/README.md`

No existing production History/Phase1/Phase2/P3-3..P3-6 file is expected to change.

---

### Task 1: Pure Review/Audit Projection

**Files:**
- Create: `tools/data/lib/history/phase3-review-audit.ps1`
- Create: `tools/data/test-phase3-review-audit.ps1`

**Interfaces:**
- Consumes existing contracts:
  - `Assert-HistoryObservation -Value <object>`
  - `Assert-ObservationComparison -Value <object>`
- Produces:
  - `Get-Phase3ReviewRoute -ChangeCandidates <string[]> -> string`
  - `New-Phase3ReviewItem -Observation <object> [-Comparison <object>] -> [pscustomobject]`
  - `New-Phase3ReviewAuditSummary -Items <object[]> -CommittedRunCount <int> -CommittedObservationCount <int> -CommittedComparisonCount <int> -IgnoredUncommittedRecordCount <int> -UniqueArtifactReferenceCount <int> -UniqueArtifactsValidated <int> -> [pscustomobject]`

- [ ] **Step 1: Write RED routing tests**

Add tests that assert exact route mapping:

- no candidates -> `RECORD_ONLY`
- `BASELINE_ESTABLISHED` -> `RECORD_ONLY`
- `EVIDENCE_CHANGE_ONLY` -> `RECORD_ONLY`
- each Location/Benefit change/absence candidate -> `HUMAN_DOMAIN_REVIEW`
- `CANONICAL_INPUT_CHANGED` -> `AUDIT_VERIFICATION`
- each processor/operational candidate -> `OPERATIONAL_DIAGNOSTIC`
- unknown candidate throws;
- any candidate set spanning more than one route category throws, including:
  - `LOCATION_CHANGE_SUSPECTED + OPERATIONAL_FAILURE`;
  - `EVIDENCE_CHANGE_ONLY + CANONICAL_INPUT_CHANGED`.

- [ ] **Step 2: Run Task 1 test and verify RED**

Run:

`pwsh -NoProfile -File tools/data/test-phase3-review-audit.ps1`

Expected: FAIL because P3-7 review functions do not exist.

- [ ] **Step 3: Implement `Get-Phase3ReviewRoute`**

Implement only the approved exact candidate taxonomy from the spec.

Rules:

- zero candidates = `RECORD_ONLY`;
- every candidate must be known;
- all candidates must resolve to exactly one route category;
- otherwise throw;
- do not mutate/reorder input candidate values.

- [ ] **Step 4: Add RED review-item tests**

Build valid existing `HistoryObservation` and `ObservationComparison` objects and assert:

comparison-backed item:

- `ReviewKey == ComparisonId`;
- IDs/domain/run/time come from current observation/comparison;
- `ChangeCandidates`, `ReasonCodes`, `DeltaDimensions` are preserved exactly;
- `AuditFlags` is empty;
- route comes from `Get-Phase3ReviewRoute`.

comparison-missing item:

- `ReviewKey == CurrentObservationId`;
- `ReviewRoute == AUDIT_VERIFICATION`;
- `PreviousObservationId == ''`;
- `ComparisonId == ''`;
- `ComparisonStatus == ''`;
- `DeltaDimensions/ChangeCandidates/ReasonCodes` empty;
- `AuditFlags == @('COMPARISON_NOT_RECORDED')`.

Add a mismatch test proving a supplied comparison with a different current observation/business/domain/run is rejected rather than projected.

- [ ] **Step 5: Implement `New-Phase3ReviewItem`**

Return an ordered `[pscustomobject]` with the exact spec fields:

- `ContractType='Phase3ReviewItem'`
- `ContractVersion=1`
- `ReviewKey`
- `BusinessId`
- `Domain`
- `RunId`
- `ObservedAt`
- `CurrentObservationId`
- `PreviousObservationId`
- `ComparisonId`
- `ReviewRoute`
- `ComparisonStatus`
- `DeltaDimensions[]`
- `ChangeCandidates[]`
- `ReasonCodes[]`
- `AuditFlags[]`
- `CurrentOperationalStatus`
- `CurrentComparable`
- `CurrentNonComparableReasons[]`
- `SemanticResultReference`
- `ArtifactReferences[]`

Do not create a History contract or persisted record.

- [ ] **Step 6: Add summary tests**

Assert `New-Phase3ReviewAuditSummary` returns exact counts for:

- total items;
- each review route;
- missing comparisons;
- Location/Benefit item counts;
- supplied committed run/observation/comparison counts;
- ignored-uncommitted count;
- unique artifact reference/validation counts;
- `CandidateCounts` keyed by candidate token.

Use multiple candidates from the same route to prove candidate counts are not confused with review-item counts.

- [ ] **Step 7: Implement `New-Phase3ReviewAuditSummary`**

Summary is an in-memory object only; no file write/index creation.

- [ ] **Step 8: Run Task 1 GREEN**

Run:

`pwsh -NoProfile -File tools/data/test-phase3-review-audit.ps1`

Expected: PASS.

Also run:

`pwsh -NoProfile -File tools/data/test-history-contracts.ps1`
`pwsh -NoProfile -File tools/data/test-compare-history-observations.ps1`

Expected: PASS.

- [ ] **Step 9: Self-review Task 1**

Confirm:

- no filesystem scan in `phase3-review-audit.ps1`;
- no History Core modification;
- no persisted review state;
- unknown/mixed route candidates fail closed;
- original History candidates/reasons remain unchanged.

- [ ] **Step 10: Commit and STOP**

Commit only Task 1 files.

Suggested message:

`feat: add Phase 3 review audit projection`

STOP for review before Task 2.

---

### Task 2: Read-only Committed-History Scanner

**Files:**
- Create: `tools/data/invoke-phase3-review-audit.ps1`
- Modify: `tools/data/test-phase3-review-audit.ps1`

**Interfaces:**
- Consumes Task 1:
  - `New-Phase3ReviewItem`
  - `New-Phase3ReviewAuditSummary`
- Reuses existing History helpers:
  - `Assert-HistoryStorePathWithinRoot`
  - `Get-HistoryRunManifestPath`
  - `Read-HistoryJsonFile`
  - `Assert-HistoryRunManifest`
  - `Assert-HistoryObservation`
  - `Assert-ObservationComparison`
  - `Assert-HistoryArtifactReferenceExists`
- Produces:
  - `Invoke-Phase3ReviewAudit -Store <existing layout> -> [pscustomobject]@{ Items; Summary }`
- Internal helpers may be added in the runner only when each represents one scan responsibility:
  - `Get-Phase3CommittedRunInventory -Store -> object`
  - `Get-Phase3CommittedObservationInventory -Store -RunInventory -> object`
  - `Get-Phase3CommittedComparisonInventory -Store -RunInventory -ObservationInventory -> object`
  - `Assert-Phase3UniqueArtifactReferences -Store -Observations -> object`

- [ ] **Step 1: Write RED COMMITTED-authority scan tests**

Create a temp History Store fixture in the test only.

Pin:

1. COMMITTED run observation becomes one review item.
2. ABORTED run's physically present valid observation does not become an item and increments `IgnoredUncommittedRecordCount`.
3. structurally valid observation whose RunId has no terminal run directory is ignored/countable rather than authoritative.
4. a run directory that exists but has no `manifest.json` throws.

The scanner itself must receive an existing Store; test setup may use `New-HistoryStoreLayout`.

- [ ] **Step 2: Run Task 2 test and verify RED**

Run:

`pwsh -NoProfile -File tools/data/test-phase3-review-audit.ps1`

Expected: FAIL because `Invoke-Phase3ReviewAudit` is not implemented.

- [ ] **Step 3: Implement run and observation linear passes**

`Get-Phase3CommittedRunInventory`:

- enumerate `Store.RunsRoot` once;
- require each run directory to contain a valid terminal manifest;
- validate directory name == manifest RunId;
- build a case-sensitive committed RunId set;
- retain committed-run count.

`Get-Phase3CommittedObservationInventory`:

- enumerate `Store.ObservationsRoot/*.json` once;
- parse with `Read-HistoryJsonFile`;
- `Assert-HistoryObservation`;
- require filename basename == ObservationId;
- committed RunId -> add once to `ObservationById`;
- non-committed/no-terminal-lineage RunId -> ignored count;
- duplicate ObservationId -> throw.

Do not read or rebuild `indexes/`.

- [ ] **Step 4: Add RED comparison-linkage tests**

Pin fail-closed cases:

- malformed comparison JSON;
- comparison filename identity mismatch;
- committed comparison current observation missing;
- current BusinessId mismatch;
- current Domain mismatch;
- current RunId mismatch;
- previous observation missing;
- previous observation belongs to non-COMMITTED lineage;
- two committed comparisons target the same `CurrentObservationId`.

Also pin valid committed observation with zero comparison -> one `AUDIT_VERIFICATION` item with `COMPARISON_NOT_RECORDED`.

- [ ] **Step 5: Implement comparison pass and map-based join**

`Get-Phase3CommittedComparisonInventory`:

- enumerate `Store.ComparisonsRoot/*.json` once;
- parse/validate every file structurally;
- require filename basename == ComparisonId;
- ignore/count structurally valid non-committed lineage records;
- for committed comparisons validate current/previous linkage exactly;
- build one comparison per CurrentObservationId;
- duplicate current mapping throws.

Join authoritative observations to zero/one committed comparison using maps. No nested directory scans.

- [ ] **Step 6: Add RED artifact trust/memoization tests**

Pin:

- missing authoritative artifact -> throw;
- hash-mismatched artifact -> throw;
- path escaping Store root -> throw;
- two or more observations referencing the same `ContentHash + RelativePath` cause one physical `Assert-HistoryArtifactReferenceExists` validation call;
- distinct reference keys validate independently.

Use a temporary function wrapper/counter in the test to measure actual helper calls, then restore it.

- [ ] **Step 7: Implement unique artifact validation**

`Assert-Phase3UniqueArtifactReferences`:

- collect authoritative observation artifact references only;
- key by exact `ContentHash + '|' + RelativePath`;
- call existing `Assert-HistoryArtifactReferenceExists` once per unique key;
- return:
  - `UniqueArtifactReferenceCount`
  - `UniqueArtifactsValidated`.

Do not parse domain artifact payload semantics.

- [ ] **Step 8: Add RED no-side-effect tests**

Pin that `Invoke-Phase3ReviewAudit`:

- does not call `New-HistoryStoreLayout`;
- does not call `Rebuild-HistoryIndexes`;
- succeeds with the `indexes/` directory empty;
- leaves a before/after file inventory and content hashes unchanged;
- never invokes Phase 1 discovery/matcher or Phase 2 evaluation functions.

Monkeypatch forbidden functions to throw if invoked where practical.

- [ ] **Step 9: Implement public runner**

`Invoke-Phase3ReviewAudit -Store`:

1. validate required existing store roots without creating them;
2. run the three linear inventories;
3. validate unique artifacts once;
4. join observations/comparisons into Task 1 review items;
5. build Task 1 summary;
6. return ordered object:
   - `Items`
   - `Summary`.

No writes.

- [ ] **Step 10: Run Task 2 GREEN + regressions**

Run:

`pwsh -NoProfile -File tools/data/test-phase3-review-audit.ps1`
`pwsh -NoProfile -File tools/data/test-history-store.ps1`
`pwsh -NoProfile -File tools/data/test-commit-history-run.ps1`
`pwsh -NoProfile -File tools/data/test-compare-history-observations.ps1`
`pwsh -NoProfile -File tools/data/test-benefit-incremental-reuse.ps1`
`pwsh -NoProfile -File tools/data/test-phase3-location-history.ps1`

Expected: PASS.

- [ ] **Step 11: Self-review Task 2**

Confirm actual code has:

- one run pass;
- one observation pass;
- one comparison pass;
- map join;
- one physical validation per unique artifact key;
- no index read/rebuild dependency;
- no store mutation;
- no domain re-evaluation;
- no network;
- no repair path.

- [ ] **Step 12: Commit and STOP**

Suggested message:

`feat: scan committed Phase 3 history for audit`

STOP for review before Task 3.

---

### Task 3: Representative A/B/C Validation and Closeout Matrix

**Files:**
- Create: `tools/data/testdata/phase3-closeout/representative-results.psd1`
- Create: `tools/data/test-phase3-closeout-validation.ps1`
- Modify Task 1/2 files only if a real defect is proven by RED regression; otherwise leave production unchanged.

**Interfaces:**
- Consumes:
  - `Get-Phase3ReviewRoute`
  - `New-Phase3ReviewItem`
  - existing `Compare-LocationHistoryObservations`
  - existing `Compare-BenefitHistoryObservations`
  - existing Location/Benefit observation-package helpers as needed for deterministic replay.
- Produces:
  - a machine-readable representative matrix with exact provenance;
  - deterministic closeout test evidence;
  - aggregate safety counts.

### Matrix vocabulary fixed by this plan

Allowed `Group`:

- `A`
- `B`
- `C`

Allowed `TemporalTruthStatus`:

- `NOT_ESTABLISHED`
- `SYNTHETIC_GROUND_TRUTH`

Allowed `ReplayStatus` for P3-7 matrix:

- `DETERMINISTIC_REPLAY`
- `PROVENANCE_ONLY_NO_TEMPORAL_GROUND_TRUTH`
- `REFERENCED_EXISTING_VALIDATION`

Use `PROVENANCE_ONLY_NO_TEMPORAL_GROUND_TRUTH` for historical ambiguity rows that must not be fabricated into previous/current temporal pairs.

- [ ] **Step 1: Write RED matrix-schema tests before creating the matrix**

Require every case to contain exactly the required provenance/expectation fields:

- `Group`
- `CaseId`
- `Domain`
- `EvidenceClass`
- `EvidenceReference`
- `VerifiedAt`
- `Status`
- `TemporalTruthStatus`
- `ReplayStatus`
- `ExpectedRoute`
- `ExpectedCandidates`
- `ExpectedReasons`
- `ExpectedAuditFlags`

Require non-empty evidence references and valid review-route values.

Historical/source-cited values must be copied from repository evidence. If `VerifiedAt` or `Status` is not supportable from the cited source, STOP rather than inventing it.

- [ ] **Step 2: Create the minimal A/B/C matrix**

Include enough cases to cover all parent-architecture semantics without duplicating every existing regression.

Minimum Group A deterministic controls:

- no delta -> `RECORD_ONLY`, no candidate;
- evidence-only change -> `RECORD_ONLY + EVIDENCE_CHANGE_ONLY`;
- baseline establishment -> `RECORD_ONLY + BASELINE_ESTABLISHED`.

At least one A case may cite historical row 339 `거시기닭갈비` only as `HISTORICAL_SOURCE_CITED_CONTROL` with `TemporalTruthStatus=NOT_ESTABLISHED`; do not claim current real-world unchanged state.

Minimum Group B provenance-only controls:

- row 135 `이지현미용실`;
- row 136 `인헤어`;
- row 248 `버섯집 초리골`;
- row 451 `짜장마을`.

All Group B cases:

- `TemporalTruthStatus=NOT_ESTABLISHED`;
- `ReplayStatus=PROVENANCE_ONLY_NO_TEMPORAL_GROUND_TRUTH`;
- must not expect Location/Benefit temporal change-or-absence candidates.

Reuse existing Phase 1 Golden fixture source paths/notes rather than copying unsupported provider facts.

Minimum Group C synthetic deterministic replay:

- Location address change -> `LOCATION_CHANGE_SUSPECTED`;
- Location coordinate change -> `LOCATION_CHANGE_SUSPECTED`;
- Location complete present -> safe absence -> `LOCATION_ABSENCE_SUSPECTED`;
- Benefit 10% -> 20% -> `BENEFIT_CHANGE_SUSPECTED`;
- Benefit eligible-target change -> `BENEFIT_CHANGE_SUSPECTED`;
- Benefit complete present -> safe absence -> `BENEFIT_ABSENCE_SUSPECTED`;
- canonical input change -> `AUDIT_VERIFICATION + CANONICAL_INPUT_CHANGED`;
- execution/repository revision change -> `OPERATIONAL_DIAGNOSTIC + PROCESSOR_OUTPUT_CHANGED`;
- operational failure -> `OPERATIONAL_DIAGNOSTIC + OPERATIONAL_FAILURE + COMPARISON_UNAVAILABLE`.

All Group C cases:

- `EvidenceClass=SYNTHETIC_TEMPORAL_FIXTURE`;
- `TemporalTruthStatus=SYNTHETIC_GROUND_TRUTH`;
- synthetic identities/data only.

- [ ] **Step 3: Run matrix test and verify RED**

Run:

`pwsh -NoProfile -File tools/data/test-phase3-closeout-validation.ps1`

Expected: FAIL until deterministic replay/assertion logic is implemented.

- [ ] **Step 4: Implement exact-set assertion helpers in the test**

Test-local helpers only:

- ordinal exact-set equality for candidates;
- ordinal exact-set equality for reasons;
- ordinal exact-set equality for audit flags;
- exact route equality.

Do not add production helpers solely for test convenience.

- [ ] **Step 5: Implement deterministic Group A/C replay**

For executable A/C cases, use existing History constructors/adapters/comparators to produce real `ObservationComparison` objects, then pass those objects through P3-7 routing/review-item projection.

Do not directly fabricate the final expected candidate arrays as "actual" output.

For domain cases:

- Location deltas must be generated through current Location history/comparator semantics.
- Benefit deltas must be generated through current Benefit history/comparator semantics.
- generic input/execution/operational precedence must exercise the shared comparison layer.

- [ ] **Step 6: Validate Group B provenance without temporal replay**

Load existing repository-cited Golden/provenance data and assert:

- row identity matches the matrix case;
- evidence reference/source path matches repository evidence;
- `TemporalTruthStatus=NOT_ESTABLISHED`;
- replay status is provenance-only;
- no temporal change truth is asserted.

Do not create previous/current observations for Group B merely to satisfy a replay count.

- [ ] **Step 7: Pin existing Phase 2 closeout distinctions**

Reference existing Phase 2 closeout matrix and assert P3-7 documentation data does not contradict:

- `CurrentFixed12ReplayStatus=NOT_RUN_NO_REPLAYABLE_RAW_CAPTURE`;
- historical evidence remains historical;
- zero real-source GREEN rows does not become a positive human audit;
- unsupported/capability-limited families remain fail-closed limitations.

Do not copy the whole fixed-12 matrix into P3-7.

- [ ] **Step 8: Add aggregate zero-safety assertions**

Compute from replayed P3-7 cases and assert:

- `UnexpectedDomainChangeCandidates == 0`;
- `OperationalFailureToSemanticAbsence == 0`;
- `CanonicalInputToExternalDomainChange == 0`;
- `ProcessorChangeToExternalDomainChange == 0`.

Also assert from existing Phase 1/2 safety evidence:

- `NonNoneProductionAction == 0`;
- `ProtectedPathWrites == 0`.

Do not add `ProductionAction` to History objects.

- [ ] **Step 9: Pin existing efficiency evidence without new benchmark claims**

Assert/reference existing deterministic P3-4/P3-6 regression evidence:

Benefit:

- reuse can avoid parse/extraction/evaluation;
- existing artifact dedup semantics remain intact.

Location:

- eligible identical-evidence reuse has `MatcherCount=0`;
- `AvoidedMatcherCount=1`;
- external discovery/provider work is not claimed avoided.

Do not calculate latency percentage improvements.

- [ ] **Step 10: Run Task 3 GREEN + targeted regressions**

Run:

`pwsh -NoProfile -File tools/data/test-phase3-closeout-validation.ps1`
`pwsh -NoProfile -File tools/data/test-phase3-review-audit.ps1`
`pwsh -NoProfile -File tools/data/test-phase1-poi-shadow-mode.ps1`
`pwsh -NoProfile -File tools/data/test-phase2-closeout-validation.ps1`
`pwsh -NoProfile -File tools/data/test-benefit-history-adapter.ps1`
`pwsh -NoProfile -File tools/data/test-benefit-incremental-reuse.ps1`
`pwsh -NoProfile -File tools/data/test-location-history-adapter.ps1`
`pwsh -NoProfile -File tools/data/test-compare-location-history.ps1`
`pwsh -NoProfile -File tools/data/test-phase3-location-history.ps1`

Expected: PASS.

- [ ] **Step 11: Self-review Task 3**

Confirm:

- historical evidence is not labeled current temporal truth;
- no benefit/location fact was invented;
- Group B has no fabricated temporal replay;
- Group C identities/data are obviously synthetic;
- exact expected sets are tested;
- aggregate safety does not replace per-case assertions;
- no live provider call is required.

- [ ] **Step 12: Commit and STOP**

Suggested message:

`test: add Phase 3 representative closeout validation`

STOP for review before Task 4.

---

### Task 4: Final Verification, Closeout Evidence, Status Docs, PR

**Files:**
- Create: `docs/handover/2026-09-27-phase3-snapshot-incremental-closeout.md`
- Modify after all gates pass:
  - `docs/current-work.md`
  - `docs/current-status.md`
  - `docs/roadmap.md`
  - `tools/data/README.md`
- Include approved P3-7 spec/plan on the implementation branch.

**Interfaces:**
- Consumes Task 1-3 implementation and test evidence.
- Produces no new runtime behavior unless final review exposes a tested defect.

- [ ] **Step 1: Fetch latest dev and check branch base**

Run:

`git fetch origin`

Report:

- `origin/dev` SHA;
- merge-base;
- branch HEAD;
- working-tree status.

If `origin/dev` gained relevant History/P3 changes after implementation started, STOP for rebase/reconciliation review before continuing.

- [ ] **Step 2: Run P3-7 targeted tests fresh**

Run:

`pwsh -NoProfile -File tools/data/test-phase3-review-audit.ps1`
`pwsh -NoProfile -File tools/data/test-phase3-closeout-validation.ps1`

Expected: PASS.

- [ ] **Step 3: Run History + domain regressions**

Run at minimum:

`pwsh -NoProfile -File tools/data/test-history-contracts.ps1`
`pwsh -NoProfile -File tools/data/test-history-fingerprints.ps1`
`pwsh -NoProfile -File tools/data/test-history-store.ps1`
`pwsh -NoProfile -File tools/data/test-commit-history-run.ps1`
`pwsh -NoProfile -File tools/data/test-compare-history-observations.ps1`
`pwsh -NoProfile -File tools/data/test-benefit-history-adapter.ps1`
`pwsh -NoProfile -File tools/data/test-benefit-incremental-reuse.ps1`
`pwsh -NoProfile -File tools/data/test-location-history-adapter.ps1`
`pwsh -NoProfile -File tools/data/test-compare-location-history.ps1`
`pwsh -NoProfile -File tools/data/test-phase3-location-history.ps1`

Expected: PASS.

- [ ] **Step 4: Run full data suite on final production HEAD**

Run repository-standard all-`test-*.ps1` command.

Record:

- total script count;
- PASS count;
- FAIL count;
- failed script names if any.

If production code changes after this step, rerun the full suite.

- [ ] **Step 5: Run Android final gate**

Use repository-standard Gradle commands for:

- `testDebugUnitTest`
- `lintDebug`
- `assembleDebug`

Record tests/failures/errors/skips, lint errors/warnings, build result.

Environment failures are not PASS.

- [ ] **Step 6: Verify repository hygiene**

Run:

`git diff --check origin/dev...HEAD`
`git status --short`

Assert no P3-7 diff under:

- `data/canonical/**`
- `data/seed/**`
- `apps/**`

Also verify no existing Phase 1/2/P3-3..P3-6 production file changed unless an explicitly reviewed RED regression required it.

- [ ] **Step 7: Perform whole-branch architecture review**

Review `origin/dev...HEAD` for:

- read-only scanner only;
- no `New-HistoryStoreLayout` in audit runner;
- no index rebuild/read dependency for audit authority;
- COMMITTED manifest authority;
- map-based linear scan;
- no N-by-N traversal;
- unique-artifact validation memoization;
- no artifact/domain re-evaluation;
- no network;
- no persisted review state;
- unknown/mixed candidate fail-closed;
- missing comparison exposed through `AuditFlags`;
- historical vs synthetic temporal truth separation;
- no unsupported performance claim.

If a defect is found:

1. add RED regression;
2. make minimum fix;
3. rerun targeted/affected tests;
4. rerun full data suite if production changed.

Protected architecture change -> STOP.

- [ ] **Step 8: Write closeout document from verified evidence**

Create `docs/handover/2026-09-27-phase3-snapshot-incremental-closeout.md`.

Record the parent 20 gates one-by-one with evidence references and PASS/NOT-APPLICABLE only where justified.

Must explicitly document:

- P3-0 through P3-6 merged evidence;
- P3-7 review/audit architecture;
- A/B/C representative validation;
- exact safety counts;
- P3-4/P3-6 avoided-work evidence;
- full data suite;
- Android/CI;
- protected-path result;
- tests not run;
- known content-addressed artifact repair limitation;
- no full 496-row current validation;
- no periodic scheduler;
- no Location provider-fetch reduction;
- no automatic MOVED/CLOSED/ENDED;
- no auto production write;
- no DB persistence;
- no human adjudication workflow;
- Phase 2 fixed-set replay limitation;
- live-provider validation not required/performed unless independently evidenced.

Do not mark a gate PASS from memory alone; cite the repository Issue/PR/test evidence used.

- [ ] **Step 9: Update current status docs only after closeout gates pass locally**

Update:

- `docs/current-work.md`
- `docs/current-status.md`
- `docs/roadmap.md`
- `tools/data/README.md`

Replace stale Phase 3 entry points/baselines with current verified state.

Do not change release-data counts unless a separately sourced current data change supports them.

Mark Phase 3 COMPLETE only if all closeout gates are actually satisfied.

- [ ] **Step 10: Rerun documentation-sensitive closeout validation**

Run:

`pwsh -NoProfile -File tools/data/test-phase3-closeout-validation.ps1`
`git diff --check origin/dev...HEAD`

Expected: PASS.

- [ ] **Step 11: Include approved spec and plan on implementation branch**

Bring in exact approved files:

- `docs/superpowers/specs/2026-09-27-phase3-p3-7-review-audit-closeout-design.md`
- `docs/superpowers/plans/2026-09-27-phase3-p3-7-review-audit-closeout.md`

Do not rewrite approved semantics during Task 4.

- [ ] **Step 12: Final commit**

Suggested final docs commit:

`docs: close Phase 3 snapshot history milestone`

- [ ] **Step 13: Push and create one P3-7 PR**

Push implementation branch without force.

PR:

- base: `dev`
- title: `[Phase 3 P3-7] Add review audit projection and closeout`
- body:
  - problem/scope/non-scope;
  - changed files;
  - Task 1-3 ledger;
  - read-only/COMMITTED authority;
  - routing taxonomy/fail-closed behavior;
  - representative A/B/C evidence;
  - exact safety gates;
  - efficiency evidence;
  - full suite/Android;
  - protected paths;
  - limitations;
  - parent Phase 3 design closeout relationship.

Link/close the dedicated P3-7 implementation Issue. Do not merge.

- [ ] **Step 14: Verify CI**

Confirm required PR checks including repository `verify-data` and `verify`.

Do not report merge-ready before required checks succeed.

- [ ] **Step 15: Final report and STOP before merge**

Report:

- origin/dev + merge-base;
- final HEAD;
- PR/Issue links;
- exact changed files;
- Task 1-3 implementation ledger;
- Task 4 changes;
- P3-7 targeted tests;
- History/domain regressions;
- full data-suite count;
- Android result;
- CI results;
- 20 closeout-gate status;
- protected paths;
- git diff check/worktree;
- tests not run;
- remaining risks;
- duplicate-work/bottleneck review;
- parent Phase 3 Issue closeout recommendation.

STOP. Merge requires explicit review after the PR exists.

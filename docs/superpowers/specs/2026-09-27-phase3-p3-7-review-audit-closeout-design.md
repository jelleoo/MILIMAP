# Phase 3 P3-7 Review/Audit Projection + Representative Validation + Closeout Design

- Status: Approved conversational design; written spec review pending
- Date: 2026-09-27
- Parent architecture: Phase 3 Snapshot / Incremental Change Detection
- Baseline: `dev@e9585884773fa28cec991439987a3ba83dae4bb5`
- Scope: P3-7 only
- Persistence mode: read-only consumer of the existing Phase 3 file history store

**Authority:** This spec refines the P3-7 portion of `docs/superpowers/specs/2026-09-26-phase3-snapshot-incremental-change-detection-design.md`. Existing P3-1 through P3-6 merged contracts, store behavior, domain projections, comparison semantics, reuse semantics, and commit semantics remain authoritative and are not redesigned here.

## 1. Problem

P3-1 through P3-6 established stable business identity, immutable audit history, deterministic fingerprints, Location and Benefit comparison, safe incremental reuse, artifact deduplication, optimistic baseline CAS, and writer-lock behavior.

Phase 3 still needs one final layer that:

1. reads committed history without mutating it;
2. projects comparison outcomes into a human-readable review/audit view;
3. preserves the difference between domain-change review, audit verification, operational diagnostics, and record-only history;
4. demonstrates representative comparison safety without inventing temporal truth;
5. records efficiency evidence already produced by P3-4/P3-6;
6. closes Phase 3 only after all parent closeout gates are evidenced.

P3-7 is not a new verification engine. It is a read-only interpretation and closeout layer over already-committed Phase 3 history.

## 2. Goals

P3-7 will:

- project committed Phase 3 history into deterministic review/audit items;
- keep History Core schemas unchanged;
- route known comparison candidates into explicit review categories;
- fail closed on unknown or semantically conflicting candidate combinations;
- expose committed observations that intentionally have no comparison;
- validate committed history lineage before producing audit output;
- validate referenced artifacts generically without re-running domain semantics;
- scan history in linear passes rather than N-by-N traversal;
- memoize repeated physical artifact validation within one audit invocation;
- use repo-reproducible representative validation;
- separate historical source-cited controls from synthetic temporal ground truth;
- pin representative expectations as exact sets, not only aggregate counts;
- record existing avoided-work metrics without inventing latency claims;
- produce Phase 3 closeout evidence and update status documents only after all final gates pass.

## 3. Non-goals

P3-7 does not:

- change History Core/store/contracts;
- add a persisted review queue;
- add reviewer assignment or review-status persistence;
- add HUMAN_AUDITED or equivalent production state;
- add a new database or index;
- rebuild history indexes during audit;
- repair corrupted history;
- re-run Phase 1 POI discovery or matching as part of audit projection;
- re-run Phase 2 benefit fetch/parse/extraction/evaluation as part of audit projection;
- add new provider calls;
- add periodic scheduling;
- infer MOVED, CLOSED, CHANGED, or ENDED as production truth;
- mutate canonical, seed, or app data;
- require a full 496-row current-state run;
- require new live-provider requests for Phase 3 closeout;
- add new external dependencies;
- change DB/API/auth contracts;
- claim population-level accuracy or production-readiness beyond the documented Phase 3 scope.

Any need for those changes requires separate approval.

## 4. Responsibility split

### Architecture owner

Owns:

- review-route semantics;
- audit-only flags;
- committed-history authority rules;
- corruption policy;
- representative evidence classes;
- temporal-truth labeling;
- closeout acceptance criteria;
- efficiency-claim boundaries;
- protected-path and final closeout semantics.

### Implementation owner

Owns:

- latest-`dev` call-path inventory;
- exact helper reuse;
- RED tests;
- minimal read-only implementation;
- deterministic fixtures;
- regression execution;
- full-suite/CI verification;
- PR preparation.

Implementation must stop rather than independently changing History Core, P3-3/P3-4, P3-5/P3-6, Phase 1/2 contracts, schemas, persistence models, dependencies, APIs, auth, or protected release data.

## 5. High-level architecture

```text
Committed Phase 3 History Store
        |
        |-- committed run manifests
        |-- committed observations
        |-- committed comparisons
        |-- referenced artifacts
        v
Phase 3 Review/Audit Projector
        |
        |-- RECORD_ONLY
        |-- HUMAN_DOMAIN_REVIEW
        |-- AUDIT_VERIFICATION
        |-- OPERATIONAL_DIAGNOSTIC
        v
Read-only Audit Result + Summary
        |
        v
Representative A/B/C Validation
        |
        v
Phase 3 Closeout Evidence
```

The projector is a consumer of existing history. It never writes back into the History Store.

## 6. Read-only boundary

The P3-7 runner consumes an already-created Store layout object.

Conceptual public entry:

```text
Invoke-Phase3ReviewAudit -Store <existing store>
```

The runner must not call `New-HistoryStoreLayout`, because that function creates directories. P3-7 must not create, repair, or mutate store structure while auditing.

Required store roots must already exist. Missing required roots fail closed.

The audit path performs no:

- index rebuild;
- temp cleanup;
- artifact repair;
- manifest rewrite;
- observation/comparison creation;
- provider request;
- matcher/evaluator execution.

## 7. Audit authority

Derived indexes are not audit authority.

P3-7 authority is:

```text
COMMITTED HistoryRunManifest
        ->
committed HistoryObservation
        ->
committed ObservationComparison
        ->
referenced artifacts
```

The `indexes/` directory is ignored for whole-history review projection. A stale or missing derived index must not change audit meaning.

## 8. COMMITTED manifest authority

Current History commit order publishes artifacts and records before writing the terminal COMMITTED manifest. Therefore, physical presence of an observation/comparison file is not sufficient to make it authoritative.

P3-7 first establishes committed RunIds from terminal run manifests.

Only records whose `RunId` belongs to a valid COMMITTED manifest may contribute authoritative review items.

### COMMITTED run

Records are eligible for audit projection.

### ABORTED run

Physically present records are excluded from review items and counted as ignored uncommitted records.

### Record with no terminal committed lineage

If the record is structurally valid enough to identify its RunId but that RunId has no committed terminal manifest, it is excluded from review items and counted as ignored uncommitted history.

This filtering is not a repair action and does not delete anything.

## 9. Structural corruption policy

P3-7 fails the entire audit invocation on structural corruption that prevents trusted interpretation.

Fail-closed cases include:

- malformed run-manifest JSON;
- run-directory / manifest RunId mismatch;
- run directory with no terminal manifest;
- invalid run-manifest contract;
- malformed observation JSON;
- invalid observation contract;
- observation file identity mismatch;
- malformed comparison JSON;
- invalid comparison contract;
- comparison file identity mismatch;
- committed comparison whose current observation does not exist;
- comparison/current BusinessId mismatch;
- comparison/current Domain mismatch;
- comparison/current RunId mismatch;
- previous observation ID exists but observation is missing;
- previous observation lineage is not committed;
- more than one committed comparison for one CurrentObservationId;
- invalid artifact reference;
- artifact path escaping store root;
- referenced artifact missing;
- referenced artifact content-hash mismatch.

P3-7 must not partially emit a successful audit report after such failures.

## 10. Scan algorithm

The audit scanner uses bounded linear passes.

### Pass 1: terminal runs

Scan `runs/` once:

- read each terminal manifest;
- validate contract and directory identity;
- build `CommittedRunIdSet`;
- count committed/aborted runs as needed for diagnostics.

### Pass 2: observations

Scan `observations/` once:

- parse and validate each observation;
- verify file identity;
- include in authoritative `ObservationById` only if its RunId is committed;
- count structurally valid records outside committed lineage as ignored uncommitted records.

### Pass 3: comparisons

Scan `comparisons/` once:

- parse and validate each comparison;
- verify file identity;
- include only committed-lineage comparisons;
- validate current and previous linkage;
- build `ComparisonByCurrentObservationId`;
- reject duplicate committed comparisons for one current observation.

### Join

For each authoritative committed observation:

- attach zero or one committed comparison;
- build one `Phase3ReviewItem`.

### Artifact validation

Validate unique authoritative artifact references once per physical reference key.

Complexity target:

```text
O(runs + observations + comparisons + unique artifacts)
```

No observation-by-observation full-directory rescans are permitted.

## 11. Artifact-validation boundary

P3-7 validates generic history trust only.

For each authoritative observation artifact reference, verify:

- artifact-reference contract;
- path containment;
- physical existence;
- SHA-256 content hash.

P3-7 does not:

- parse Location semantic projection meaning again;
- evaluate Benefit claims again;
- reparse HTML/JSONP/XLSX;
- invoke POI matching;
- invoke benefit evaluation.

Those semantics are already owned by P3-3/P3-5 and Phase 1/2 regressions.

## 12. Artifact-validation memoization

Incremental reuse can make many observations reference the same content-addressed artifact.

Within one audit invocation, physical hash validation is memoized by:

```text
ContentHash + RelativePath
```

The first reference performs physical validation. Later identical reference keys reuse that validation result.

This cache is invocation-local only. No persisted artifact-validation cache is added.

## 13. Review-route vocabulary

P3-7 defines exactly four read-model routes:

- `RECORD_ONLY`
- `HUMAN_DOMAIN_REVIEW`
- `AUDIT_VERIFICATION`
- `OPERATIONAL_DIAGNOSTIC`

These are P3-7 read-model categories, not new History comparison candidates.

## 14. Candidate taxonomy

Known History comparison candidates map as follows.

### RECORD_ONLY

- no change candidate;
- `BASELINE_ESTABLISHED`;
- `EVIDENCE_CHANGE_ONLY`.

These remain in audit history but do not represent external domain-change review.

### HUMAN_DOMAIN_REVIEW

- `LOCATION_CHANGE_SUSPECTED`;
- `LOCATION_ABSENCE_SUSPECTED`;
- `BENEFIT_CHANGE_SUSPECTED`;
- `BENEFIT_ABSENCE_SUSPECTED`.

These are review candidates only. They do not assert MOVED, CLOSED, CHANGED, or ENDED.

### AUDIT_VERIFICATION

- `CANONICAL_INPUT_CHANGED`.

This indicates input/audit verification, not external-world change.

### OPERATIONAL_DIAGNOSTIC

- `PROCESSOR_OUTPUT_CHANGED`;
- `OPERATIONAL_FAILURE`;
- `COMPARISON_UNAVAILABLE`.

These are engineering/operational diagnostics, not human domain-change candidates.

## 15. Routing conflict and unknown candidates

Routing is taxonomy validation, not priority selection.

A comparison may contain multiple candidates only when every candidate maps to the same route category. Any mixed route categories, including RECORD_ONLY mixed with a non-record route, fail closed with a routing conflict.

Example prohibited combination:

```text
LOCATION_CHANGE_SUSPECTED
+
OPERATIONAL_FAILURE
```

P3-7 must not silently choose HUMAN_DOMAIN_REVIEW and hide the operational diagnostic.

Any unknown candidate also fails closed. This ensures future History vocabulary additions cannot be silently misrouted.

## 16. Committed observation without comparison

A committed observation may intentionally have no comparison, for example when an invalid prior projection artifact caused recomputation but previous semantic comparison was intentionally withheld.

This is valid history.

P3-7 projects it as:

```text
ReviewRoute = AUDIT_VERIFICATION
PreviousObservationId = ''
ComparisonId = ''
ComparisonStatus = ''
DeltaDimensions = []
ChangeCandidates = []
ReasonCodes = []
AuditFlags = [COMPARISON_NOT_RECORDED]
```

The empty comparison fields mean no comparison was recorded; they must not be synthesized from the latest comparable index or another run.

`COMPARISON_NOT_RECORDED` is a P3-7 audit flag only. It must not be injected into History `ReasonCodes` or `ChangeCandidates`.

## 17. Review-item contract

P3-7 uses an in-memory read model, not a History schema contract.

Conceptual shape:

```text
Phase3ReviewItem
ContractVersion = 1

ReviewKey

BusinessId
Domain

RunId
ObservedAt

CurrentObservationId
PreviousObservationId
ComparisonId

ReviewRoute

ComparisonStatus
DeltaDimensions[]
ChangeCandidates[]
ReasonCodes[]

AuditFlags[]

CurrentOperationalStatus
CurrentComparable
CurrentNonComparableReasons[]

SemanticResultReference
ArtifactReferences[]
```

Rules:

- comparison-backed `ReviewKey = ComparisonId`;
- comparison-missing `ReviewKey = CurrentObservationId`;
- original `ChangeCandidates[]` are preserved unchanged;
- original `ReasonCodes[]` are preserved unchanged;
- P3-7-only diagnostics live in `AuditFlags[]`;
- artifact payloads are not copied into the item.

## 18. Review summary

The runner returns read-only summary metrics with the item collection.

Minimum summary:

```text
CommittedRunCount
CommittedObservationCount
CommittedComparisonCount

ReviewItemCount

RecordOnlyCount
HumanDomainReviewCount
AuditVerificationCount
OperationalDiagnosticCount

MissingComparisonCount
IgnoredUncommittedRecordCount

UniqueArtifactReferenceCount
UniqueArtifactsValidated

LocationItemCount
BenefitItemCount

CandidateCounts
```

The summary is calculated per invocation and is not persisted as a new index.

## 19. Representative-validation principle

Representative validation is repo-reproducible and must not depend on developer-local `output/phase3-history/` state.

It uses only:

- committed deterministic fixtures;
- committed captures;
- repository-cited historical evidence;
- explicit synthetic temporal fixtures.

New live requests are not a default P3-7 closeout requirement.

## 20. Representative groups

The parent Phase 3 architecture requires three groups.

### Group A — unchanged controls

Purpose: prove that unchanged or comparison-equivalent observations do not produce false domain-change candidates.

Examples include:

- identical semantic/evidence observations;
- provider physical-order changes that canonicalize identically;
- evidence-only change with unchanged semantics;
- baseline establishment;
- identical reuse observations.

A repository-cited positive Location control such as historical row 339 `거시기닭갈비` may be used as deterministic source-cited input, but not as proof that the real business is still unchanged today.

Expected temporal truth status: `NOT_ESTABLISHED`.

### Group B — historical ambiguous/regression controls

Purpose: ensure known historical ambiguity/conflict is not relabeled as temporal change truth.

Existing source-cited Location safety controls include:

- row 135 `이지현미용실`;
- row 136 `인헤어`;
- row 248 `버섯집 초리골`;
- row 451 `짜장마을`.

These cases prove historical ambiguity/conflict safety only. They do not establish MOVED, CLOSED, or any actual previous-to-current temporal transition.

Expected temporal truth status: `NOT_ESTABLISHED`.

Phase 2 fixed representative evidence remains governed by its existing replay limitations. P3-7 must not claim a current all-row replay when replayable raw captures do not exist.

### Group C — synthetic temporal fixtures

Purpose: provide explicit ground truth for change-detection mechanics without making claims about current real businesses.

Required synthetic coverage from the parent architecture:

- Location address A -> B;
- Location coordinate change;
- Benefit 10% -> 20%;
- Benefit eligible-target change;
- COMPLETE present -> safely established absence;
- canonical input change;
- processor/repository revision change;
- operational failure.

Synthetic cases must use clearly synthetic identity/material and must never be presented as real-source observations.

Expected temporal truth status: `SYNTHETIC_GROUND_TRUTH`.

## 21. Representative evidence classes

The closeout matrix distinguishes source provenance from temporal truth.

Minimum evidence classes:

- `HISTORICAL_SOURCE_CITED_CONTROL`;
- `COMMITTED_DETERMINISTIC_FIXTURE`;
- `COMMITTED_CAPTURE`;
- `SYNTHETIC_TEMPORAL_FIXTURE`.

Minimum temporal-truth values:

- `NOT_ESTABLISHED`;
- `SYNTHETIC_GROUND_TRUTH`.

Historical source evidence must never be silently promoted to current temporal truth.

## 22. Representative evidence matrix

Create a machine-readable matrix under:

```text
tools/data/testdata/phase3-closeout/representative-results.psd1
```

Each case contains at least:

```text
Group
CaseId
Domain

EvidenceClass
EvidenceReference
VerifiedAt
Status

TemporalTruthStatus
ReplayStatus

ExpectedRoute
ExpectedCandidates[]
ExpectedReasons[]
ExpectedAuditFlags[]
```

For real/historical source-cited data, `EvidenceReference` must identify the repository source, Issue/PR, or committed capture. `VerifiedAt` and `Status` must not be invented; they must match repository evidence.

## 23. Exact-set validation

Representative validation verifies exact expected semantics per case.

For every case:

```text
ActualRoute == ExpectedRoute

ActualCandidates exact-set == ExpectedCandidates

ActualReasons exact-set == ExpectedReasons

ActualAuditFlags exact-set == ExpectedAuditFlags
```

Aggregate counts alone are insufficient because a missing expected candidate could otherwise cancel out an unexpected candidate numerically.

## 24. Aggregate safety gates

In addition to exact case validation, P3-7 records aggregate safety invariants.

Required zero counts:

```text
UnexpectedDomainChangeCandidates = 0
OperationalFailureToSemanticAbsence = 0
CanonicalInputToExternalDomainChange = 0
ProcessorChangeToExternalDomainChange = 0
NonNoneProductionAction = 0
ProtectedPathWrites = 0
```

For unchanged/historical ambiguity controls, false Location/Benefit change-or-absence candidates must be zero.

## 25. Human-review meaning

P3-7 validates routing, not human adjudication.

A synthetic or real change candidate routed to `HUMAN_DOMAIN_REVIEW` means only that it reached the correct review category.

P3-7 does not create:

- reviewer assignment;
- reviewed/approved/rejected status persistence;
- human-decision database;
- HUMAN_AUDITED state;
- automatic canonical mutation.

Real-world final adjudication is outside Phase 3 closeout.

## 26. Existing Phase 2 representative evidence

The existing Phase 2 fixed closeout matrix remains authoritative for its scope.

P3-7 must preserve distinctions such as:

- current replay not run when raw capture is unavailable;
- historical observation-time evidence remains historical;
- policy/capability limitations remain limitations;
- zero real-source GREEN rows means human GREEN audit is not applicable, not positively passed.

P3-7 may reference this evidence but must not relabel it as newly executed P3-7 live validation.

## 27. Efficiency closeout

P3-7 records only efficiency already measured by merged incremental paths.

### Benefit P3-4

Existing metrics may evidence:

- avoided parse;
- avoided extraction;
- avoided evaluation;
- artifact dedup behavior;
- external fetch behavior actually observed by the implementation.

### Location P3-6

Existing metrics may evidence:

- discovery/provider work still occurs;
- matcher can be avoided;
- `MatcherCount=0` and `AvoidedMatcherCount=1` on eligible identical-evidence reuse.

P3-7 must not claim provider-request reduction for Location.

No unmeasured latency or percentage speedup is reported.

## 28. Phase 3 closeout gates

P3-7 uses the parent architecture's 20-gate closeout without weakening it.

Phase 3 may be marked complete only when evidence demonstrates:

1. stable businessId migration complete;
2. History contracts fixed and tested;
3. crash-safe file history store;
4. index rebuild works;
5. artifact dedup works;
6. baseline CAS race protection works;
7. Benefit adapter connected;
8. Location adapter connected;
9. deterministic comparison regressions pass;
10. safe reuse gates pass;
11. false domain-change candidates = 0 in deterministic controls;
12. operational failure -> semantic absence = 0;
13. processor/input change -> external domain change = 0;
14. `ProductionAction != NONE` = 0;
15. automatic canonical/seed/apps writes = 0 after P3-0;
16. representative validation complete;
17. efficiency metrics recorded;
18. full `tools/data/test-*.ps1` suite passes on final HEAD;
19. CI passes;
20. limitations are documented.

P3-7 references already-merged P3-0 through P3-6 evidence for gates 1-10 rather than reimplementing those capabilities.

## 29. ProductionAction gate

P3-7 does not add `ProductionAction` to History contracts.

The no-production-action gate is evidenced by existing Phase 1/2 contracts/regressions and protected-path verification.

No redundant History field is introduced.

## 30. Closeout document

Final closeout evidence is recorded in:

```text
docs/handover/2026-09-27-phase3-snapshot-incremental-closeout.md
```

It must include:

- scope and baseline;
- P3-0 through P3-7 evidence references;
- review/audit routing semantics;
- representative A/B/C validation;
- exact safety-gate outcomes;
- efficiency evidence;
- full data-suite result;
- Android/CI verification as required by repository workflow;
- protected-path result;
- tests not run;
- limitations;
- explicit statements about what Phase 3 completion does not mean.

## 31. Status-document updates

Only after the closeout gates pass on final P3-7 HEAD may P3-7 update:

- `docs/current-work.md`;
- `docs/current-status.md`;
- `docs/roadmap.md`;
- `tools/data/README.md`.

These documents must be updated from actual merged/current evidence because some existing baseline text predates P3-6.

Intermediate P3-7 tasks must not mark Phase 3 complete.

## 32. Required limitations to document

At minimum, final closeout records:

- no full 496-row current-state validation;
- no periodic scheduler;
- no Location provider-fetch reduction;
- no automatic MOVED/CLOSED/ENDED truth;
- no automatic canonical/seed/apps write;
- no product DB persistence;
- repository revision remains a conservative execution boundary;
- no repair subsystem for corrupted content-addressed artifacts;
- Phase 2 fixed representative set is not fully replayed when raw capture is unavailable;
- live-provider validation is not a Phase 3 closeout requirement;
- review routing is not human adjudication.

## 33. Expected production file boundaries

Expected new P3-7 code:

```text
tools/data/lib/history/phase3-review-audit.ps1
tools/data/invoke-phase3-review-audit.ps1
tools/data/test-phase3-review-audit.ps1
```

Expected representative closeout data/test:

```text
tools/data/testdata/phase3-closeout/representative-results.psd1
tools/data/test-phase3-closeout-validation.ps1
```

Expected closeout docs:

```text
docs/handover/2026-09-27-phase3-snapshot-incremental-closeout.md
```

Final-only status updates:

```text
docs/current-work.md
docs/current-status.md
docs/roadmap.md
tools/data/README.md
```

## 34. Protected and normally unchanged areas

P3-7 must not modify without separate approval:

- History Core contracts/store/commit/fingerprint semantics;
- Benefit history adapter/comparator/incremental reuse;
- Location history adapter/comparator/incremental reuse;
- Phase 1 production logic;
- Phase 2 production logic;
- `data/canonical/**`;
- `data/seed/**`;
- `apps/**`;
- DB/API/auth contracts;
- external dependencies.

If implementation proves such a change necessary, stop and report rather than broadening scope.

## 35. Testing strategy

### Task-level targeted tests

Use RED -> GREEN only for the focused behavior under implementation.

Avoid repeatedly running the full suite after small edits.

### Review projection tests

Pin:

- candidate-to-route mapping;
- no-delta/baseline/evidence-only record-only routing;
- human-domain routing;
- canonical-input audit routing;
- operational routing;
- unknown-candidate fail closed;
- any mixed route-category candidate set fail closed, including RECORD_ONLY plus a non-record route;
- original candidates/reasons preserved;
- missing comparison -> `AuditFlags=[COMPARISON_NOT_RECORDED]`.

### Store scan tests

Pin:

- COMMITTED manifest authority;
- ABORTED/uncommitted valid records ignored and counted;
- missing terminal manifest directory failure;
- malformed manifest/observation/comparison failure;
- current/previous linkage validation;
- duplicate current comparison failure;
- missing/hash-invalid/path-escaping artifact failure;
- repeated shared artifact physically hashed once per invocation;
- indexes not required and not rebuilt;
- scanner performs no store writes.

### Representative closeout tests

Pin A/B/C evidence metadata and exact expected route/candidate/reason/audit-flag sets.

Pin aggregate zero-safety gates.

### Final gate

On final production HEAD:

- P3-7 targeted tests;
- related History/Benefit/Location regressions;
- full `tools/data/test-*.ps1` suite;
- repository Android verification/CI;
- `git diff --check`;
- protected-path diff checks;
- final architecture review.

## 36. Bottleneck controls

P3-7 must avoid creating a closeout-time bottleneck.

Required:

- one run-manifest pass;
- one observation pass;
- one comparison pass;
- map-based join;
- physical artifact validation once per unique reference key;
- no network;
- no domain re-evaluation;
- no index rebuild;
- no N-by-N history scan;
- no repeated full suite during intermediate tasks.

## 37. Failure semantics

P3-7 distinguishes:

### Non-authoritative but structurally valid records

Excluded from review output and counted as ignored when they are outside committed lineage.

### Valid committed observation with intentionally missing comparison

Projected to `AUDIT_VERIFICATION` with `COMPARISON_NOT_RECORDED` audit flag.

### Structural or artifact corruption

Fail the audit invocation.

P3-7 never repairs or silently normalizes corrupt history.

## 38. Proposed implementation decomposition

The implementation plan should keep four small tasks:

### Task 1 — pure review/audit projection

Implement read-model construction, route taxonomy, conflict/unknown-candidate failure, and summary helpers that do not require filesystem scanning.

### Task 2 — read-only committed-history scanner

Implement linear committed-lineage scan, linkage validation, artifact validation memoization, and audit runner.

### Task 3 — representative A/B/C validation + closeout matrix

Add deterministic closeout evidence matrix and exact-set validation. Reuse repository-cited historical evidence without inventing new benefit/location facts.

### Task 4 — final verification + closeout docs + PR

Run final suites/CI, write closeout document, update current status/roadmap/README only after gates pass, then prepare one P3-7 PR.

Each task stops for review before the next task.

## 39. Completion criteria

P3-7 implementation is complete when:

- committed history can be projected read-only into deterministic review items;
- unknown/conflicting candidate semantics fail closed;
- committed authority and record linkage are verified;
- shared artifact validation is deduplicated in-memory;
- comparison-missing committed observations remain visible via audit flags;
- representative A/B/C exact-set validation passes;
- historical ambiguity is never relabeled as temporal truth;
- synthetic temporal change is clearly labeled synthetic;
- all aggregate safety gates pass;
- existing efficiency evidence is documented without overclaiming;
- protected paths remain unchanged;
- full data suite and CI pass;
- limitations are explicit;
- Phase 3 status is updated only from final verified evidence.

## 40. Explicit closeout meaning

Phase 3 completion means the repository has a deterministic, auditable snapshot/history/change-detection foundation with conservative incremental reuse and review routing.

It does not mean:

- all real businesses were freshly revalidated;
- all benefits are current;
- all POIs are current;
- all review candidates were human adjudicated;
- closures/moves/endings are automatically known;
- scheduling or production mutation exists;
- server/DB persistence is approved;
- Location provider traffic is optimized away.

Those remain separate future work.

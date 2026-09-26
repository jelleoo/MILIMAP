# Phase 3 Snapshot / Incremental Change Detection Design

- Status: Approved design
- Date: 2026-09-26
- Design Issue: #94
- Baseline: `dev@85335705f15484ba59b86ad850d98da127b849ba`
- Scope type: Architecture / design only
- Implementation: NOT STARTED

## 1. Problem

Phase 1 POI Verification and Phase 2 Benefit Verification can safely evaluate current observations, but each run largely treats work as new. The repository has no durable run-to-run audit history, no stable canonical business identity, and no safe mechanism to distinguish unchanged evidence from actual semantic change.

Phase 3 adds snapshot/history and incremental change detection without weakening Phase 1/2 safety semantics.

## 2. Goals

Phase 3 v1 will:

- preserve auditable observation history across runs;
- compare previous and current Location/Benefit observations;
- detect change candidates without asserting production truth;
- safely reuse deterministic work when input, evidence, execution, and comparison versions are unchanged;
- deduplicate identical physical artifacts;
- keep operational failure separate from semantic absence;
- measure avoided work and remaining bottlenecks;
- remain outside the product DB and outside automatic production mutation.

## 3. Non-goals

Phase 3 v1 does not:

- introduce Room/server DB persistence;
- implement periodic scheduling;
- auto-approve or auto-write canonical/seed/apps;
- infer CLOSED/MOVED/ENDED from absence alone;
- add PDF/HWP/OCR or new source families;
- add a new external dependency;
- redesign Phase 1/2 decision semantics;
- change API/auth contracts;
- claim full-population accuracy;
- require a full 496-row live run for completion.

## 4. Pre-implementation boundary

Before any implementation Issue starts, each Issue must state:

- problem being solved;
- scope;
- explicit non-scope;
- expected files;
- test method;
- risks.

Changes to core architecture, DB approach, external dependencies, auth, API contracts, or data schema require approval. The only schema change approved by this design is the canonical `businessId` addition described below.

## 5. Responsibility split

### Architecture owner

The architecture owner is responsible for:

- contract meaning and invariants;
- fingerprint field inclusion/exclusion;
- comparable rules;
- change-candidate semantics;
- persistence and concurrency invariants;
- skip/reuse safety gates;
- Issue acceptance criteria;
- architecture review and Phase 3 closeout decision.

### Codex implementation role

Codex is responsible for each approved Issue's:

- latest-`dev` repo/call-path inventory;
- reuse assessment of existing helpers/contracts;
- exact changed-file proposal;
- RED test;
- minimal implementation;
- targeted regressions;
- final full suite / protected-path verification;
- PR preparation.

Codex must escalate rather than independently deciding a new storage model, DB, dependency, contract meaning, fingerprint meaning, change-candidate meaning, source adapter, or additional canonical schema change.

## 6. Stable canonical business identity

Phase 3 requires a stable lineage identifier independent of mutable business attributes.

Canonical gains:

```text
businessId = biz-<32 lowercase hex>
```

Rules:

- generated once with `.NET Guid.NewGuid().ToString("N")`;
- opaque: no name/address/region meaning;
- required;
- unique;
- immutable after assignment;
- format `^biz-[0-9a-f]{32}$`.

The one-time migration must use temp write -> re-read validation -> atomic replacement. Existing row count and all pre-existing column values must remain unchanged. The Android `seed-*` ID remains unchanged and has a separate purpose.

`SourceRowNumber` becomes observation-time locator metadata only; `businessId` is the history identity.

Existing release/coordinate-review row-number tooling is not migrated in Phase 3.

## 7. Persistence model

Phase 3 v1 uses a file-based audit history store outside the product DB.

Conceptual root:

```text
output/phase3-history/
  runs/
  observations/
  comparisons/
  artifacts/sha256/
  indexes/
  tmp/
```

### 7.1 Immutable append-only observations

Once published, observations are never edited in place. Corrections create later observations.

### 7.2 Content-addressed artifacts

Every observation is recorded, but physical artifacts are stored once by content hash.

Example:

```text
obs-1 --obs-2 ----> sha256:<same hash> -> one physical artifact
obs-3 --/
```

Benefit HTML/JSONP/XLSX may reference existing raw payload provenance. POI does not gain a new raw-response capture subsystem; existing `PoiDiscoveryBatch` / candidate diagnostics are the audit artifact.

### 7.3 Derived indexes

Latest indexes are caches, not truth.

They must be rebuildable from committed immutable history.

Maintain separately:

- LatestObservation
- LatestComparableObservation

A FAILED/PARTIAL latest observation must not replace the latest comparable baseline.

## 8. Shared architecture

```text
Canonical businessId
        |
        v
Existing Phase 1 / Phase 2 verification
        |
        v
Phase 3 domain adapters
   |             |
Location       Benefit
   \             /
    v           v
      History Core
          |
          v
     File History Store
```

Dependencies are one-way:

- Phase 3 adapters may consume Phase 1/2 contracts/results.
- Phase 3 orchestrators may invoke Phase 1/2 runners.
- Phase 1/2 must not depend on Phase 3 history code.

History Core must not know Naver/MMA/HTML/XLSX/domain enums.

## 9. History contracts

### 9.1 HistoryObservation

Common envelope:

```text
ObservationId
RunId
BusinessId
Domain = LOCATION | BENEFIT
ObservedAt

OperationalStatus = COMPLETE | PARTIAL | FAILED
Comparable
NonComparableReasons[]

InputFingerprint
EvidenceFingerprint
SemanticFingerprint
ExecutionFingerprint

ArtifactReferences[]
SemanticResultReference
```

Domain-specific Phase 1/2 states are not duplicated into the common contract.

### 9.2 ObservationComparison

Comparison is immutable and separate from observations:

```text
ComparisonId
RunId
BusinessId
Domain

PreviousObservationId
CurrentObservationId

ComparisonStatus
DeltaDimensions[]
ComparatorVersion
ChangeCandidates[]
ReasonCodes[]
```

This allows later comparator versions without mutating observations.

## 10. Four-layer fingerprints

### 10.1 InputFingerprint

Represents canonical inputs that materially affect verification.

Location includes stable identity and fields used by normalization/discovery/matching. Benefit includes stable identity, benefit claim inputs, source metadata, and binding inputs.

Exclude audit-only metadata such as row position, collector, or note fields unless they become verification inputs.

### 10.2 EvidenceFingerprint

Represents observed external evidence.

For Benefit, reuse trusted existing `ContentHash` values whenever possible instead of rehashing raw source content.

For POI, create a canonical serialized fingerprint from discovery status, candidates, coordinates, provider evidence, and discovery evidence required by ranking.

### 10.3 SemanticFingerprint

Represents the interpreted domain result, not physical provenance.

Location projection includes evaluation status/classification, selected name/address/coordinates, and material reason/conflict sets.

Benefit projection includes benefit state/review class plus validated claim type/value/result/status and material reasons. Physical row/cell/URL positions remain evidence provenance.

### 10.4 ExecutionFingerprint

At minimum:

- RepositoryRevision;
- FingerprintSchemaVersion;
- HistoryContractVersion;
- relevant run configuration.

A dirty working tree is not eligible for incremental reuse.

v1 intentionally uses repository revision conservatively. Processor-level versioning may be refined later after evidence shows the need.

## 11. Canonical serialization

History fingerprint serialization is implemented once in History Core.

Requirements:

- fixed field order;
- explicit null representation;
- ordinal ordering;
- field-specific array sorting rules;
- invariant numeric representation;
- UTF-8;
- schema version in hash material.

Adapters produce projection objects but do not implement their own fingerprint serialization.

Existing Phase 1/2 hashing helpers are not moved merely for code deduplication. Existing trusted hashes are reused; Phase 3 hashes only Phase 3 projections/history objects.

## 12. Incremental reuse gate

Reuse requires all of:

```text
previous operational result is comparable/complete
InputFingerprint unchanged
EvidenceFingerprint unchanged
ExecutionFingerprint unchanged
fingerprint/contract versions compatible
adapter declares a safe incremental checkpoint
```

If any requirement fails, recompute.

### Benefit

Where a source adapter safely supports post-fetch reuse:

```text
fetch -> evidence hash
same evidence + same input/execution
-> skip parse/locator/binding/extraction/validation/comparison/evaluation
```

The new observation still records a fresh observation time and references the prior semantic result. It must not masquerade as newly recomputed semantics.

### Location

Current v1 POI discovery still runs. If the complete discovery evidence fingerprint is unchanged and input/execution are unchanged, matcher recomputation may be skipped.

### Capability gating

Incremental optimization is adapter-capability-based, not assumed globally.

Conceptual capabilities:

- NONE
- POST_DISCOVERY
- POST_FETCH
- FULL_EVIDENCE

If safety cannot be demonstrated for an adapter, the existing Phase 1/2 pipeline runs normally.

MMA JSONP multi-stage LIST -> linkage -> DETAIL must not be shortcut using only an insufficient checkpoint.

## 13. Change detection semantics

Phase 3 creates review candidates, not production truth.

It must never automatically assert:

- MOVED;
- CLOSED;
- CHANGED as a Phase 2 final benefit state;
- ENDED.

Candidate vocabulary:

- BASELINE_ESTABLISHED
- LOCATION_CHANGE_SUSPECTED
- LOCATION_ABSENCE_SUSPECTED
- BENEFIT_CHANGE_SUSPECTED
- BENEFIT_ABSENCE_SUSPECTED
- EVIDENCE_CHANGE_ONLY
- CANONICAL_INPUT_CHANGED
- PROCESSOR_OUTPUT_CHANGED
- COMPARISON_UNAVAILABLE
- OPERATIONAL_FAILURE

First observation means `BASELINE_ESTABLISHED`, not new-business discovery.

## 14. Comparison precedence

Comparison reason classification must happen in this order:

1. current operational failure -> OPERATIONAL_FAILURE / COMPARISON_UNAVAILABLE;
2. input changed -> CANONICAL_INPUT_CHANGED;
3. execution changed -> PROCESSOR_OUTPUT_CHANGED;
4. only then, if both observations are comparable, evaluate external/domain deltas.

This prevents canonical edits or processor changes from being mislabeled as real-world business changes.

## 15. Location comparator

Location semantic projection uses field-level meaning rather than raw CandidateKey identity.

Material dimensions:

- NAME
- ADDRESS
- COORDINATE
- SELECTION
- EVALUATION

CandidateKey changes caused only by phone/category/provider-link changes must not imply location movement.

`LOCATION_ABSENCE_SUSPECTED` requires:

- previous comparable selected candidate;
- current comparable COMPLETE discovery/evaluation;
- no selected candidate;
- genuine no-candidate evidence;
- unchanged input/execution fingerprints.

PARTIAL/FAILED/provider errors/input changes/execution changes cannot create an absence candidate.

## 16. Benefit comparator

Benefit comparison reuses existing Phase 2 semantic comparison rules rather than implementing a second discount/target/condition comparison engine.

`BENEFIT_CHANGE_SUSPECTED` requires comparable observations, unchanged input/execution, and a material business-bound validated semantic claim change.

Evidence/provenance movement without semantic change produces `EVIDENCE_CHANGE_ONLY`.

`BENEFIT_ABSENCE_SUSPECTED` requires a COMPLETE/comparable observation that safely establishes business identity absence in the observed source context. It never means ENDED.

Explicit ending evidence remains Phase 2's responsibility.

## 17. Review routing

Audit history and human-review queue are separate.

Normally record-only:

- UNCHANGED/no delta;
- BASELINE_ESTABLISHED;
- EVIDENCE_CHANGE_ONLY.

Human domain-review candidates:

- LOCATION_CHANGE_SUSPECTED;
- LOCATION_ABSENCE_SUSPECTED;
- BENEFIT_CHANGE_SUSPECTED;
- BENEFIT_ABSENCE_SUSPECTED.

Operational/development diagnostics:

- OPERATIONAL_FAILURE;
- COMPARISON_UNAVAILABLE;
- PROCESSOR_OUTPUT_CHANGED.

`CANONICAL_INPUT_CHANGED` routes to audit/verification, not external-change review.

## 18. Run commit model

Run metadata separates pipeline execution from history commit.

```text
ExecutionStatus = COMPLETE | PARTIAL | FAILED
RunCommitStatus = PREPARED | COMMITTED | ABORTED
```

A PARTIAL execution may still be validly COMMITTED as audit history.

Write flow:

1. prepare staging;
2. validate contracts/hash/references;
3. acquire writer lock;
4. re-check expected baseline;
5. publish deduplicated artifacts;
6. publish observations/comparisons;
7. publish COMMITTED run manifest;
8. update derived indexes;
9. release lock.

Readers use observations only from COMMITTED runs.

If crash occurs after manifest commit but before index update, the index is repaired/rebuilt from committed history.

## 19. Concurrency

Phase 3 v1 uses single-writer / many-reader history access.

Writer lock uses built-in .NET exclusive file access (`FileShare.None`) and is held only during the short persistence commit window, not during network/verification work.

Commit performs optimistic baseline CAS:

```text
ExpectedPreviousObservationId
==
CurrentLatestComparableObservationId
```

If the baseline moved:

- do not three-way merge;
- do not auto-retry;
- do not reissue hidden live requests;
- fail closed with `BASELINE_MOVED / RETRY_REQUIRED`.

Retry is caller-controlled. Scheduler/retry policy belongs to later operational phases.

## 20. Observation identity and duplicate prevention

Within the same run, duplicate persistence for one `businessId + domain` is rejected.

Observation identity should be deterministic from at least:

- businessId;
- domain;
- RunId;
- InputFingerprint;
- EvidenceFingerprint.

Different runs observing identical evidence still create distinct observations because RunId differs.

## 21. Efficiency metrics

Phase 3 reports, where applicable:

- RowsRequested / RowsCompleted;
- PreviousBaselineHits / Misses;
- EvidenceUnchanged;
- SemanticUnchanged / Changed;
- ReuseEligible / Applied / Rejected;
- ExternalFetchCount;
- ParseCount;
- MatcherCount;
- ExtractionCount;
- EvaluationCount;
- ArtifactWrites / ArtifactDedupHits;
- ComparisonCandidates;
- HumanReviewCandidates;
- IndexLookupCount / IndexRebuildCount;
- AvoidedParseCount;
- AvoidedMatcherCount;
- AvoidedExtractionCount;
- AvoidedEvaluationCount.

These are operational observations, not population quality claims.

## 22. Test strategy

Testing is layered:

```text
contract
-> history store
-> fingerprint
-> domain adapters
-> reuse
-> crash/concurrency
-> representative end-to-end
-> full tools/data suite
-> CI
```

### Contract tests

Reject invalid IDs, domains, fingerprints, references, comparison linkage, and uncommitted baseline use.

Initial versions:

- HistoryContractVersion = 1
- FingerprintSchemaVersion = 1
- ComparatorVersion = 1

Version mismatch prevents silent reuse.

### Fingerprint mutation matrix

Must verify expected equality/difference for:

- phone/provider-link only changes;
- address/coordinate changes;
- HTML whitespace/provenance-only changes;
- XLSX physical movement with same semantic claim;
- benefit amount/target changes;
- order-insensitive collection reorder;
- order-sensitive data changes.

### History store

Verify:

- append-only preservation;
- identical artifact written once;
- identical evidence across runs creates multiple observations;
- latest observation advances;
- latest comparable ignores failed observations;
- index rebuild reproduces the same derived state;
- staging never becomes a baseline.

### Crash safety

Fault-injection checkpoints cover:

- after artifact publish;
- after observation publish;
- before manifest commit;
- after manifest commit / before index update.

No PREPARED/ABORTED run becomes a comparison baseline.

### Concurrency

Two runs reading the same baseline must not both commit stale comparison chains. The second stale writer receives `RETRY_REQUIRED`.

### Reuse safety

Reuse is rejected when input/evidence/execution/version/comparable/capability gates do not hold.

## 23. Representative validation

Use three groups:

A. unchanged controls;
B. existing historical ambiguous/regression controls;
C. synthetic delta fixtures.

Reuse existing known regression examples where applicable, but never relabel historical ambiguity as a real temporal change.

Synthetic fixtures cover:

- address A -> B;
- coordinate change;
- 10% -> 20%;
- eligible target change;
- present -> absent under COMPLETE observation;
- canonical input change;
- processor revision change;
- operational failure.

Prefer deterministic fixtures and committed captures. New live requests are not a default Phase 3 closeout requirement.

## 24. Protected paths

Except for the approved one-time P3-0 `businessId` migration, Phase 3 code treats these as protected:

- `data/canonical/**`;
- `data/seed/**`;
- `apps/**`.

P3-0 must prove:

- only `businessId` is added to canonical;
- existing canonical values and row count are unchanged;
- seed semantic diff is zero;
- apps diff is zero.

After P3-0, Phase 3 history code is canonical read-only.

## 25. Implementation decomposition

Expected small Issue/PR sequence:

- P3-0 — Stable canonical `businessId` migration
- P3-1 — History contracts + canonical serialization + fingerprints
- P3-2 — File history store + artifact dedup + lock/index/run commit
- P3-3 — Benefit history adapter + comparator
- P3-4 — Benefit incremental reuse integration
- P3-5 — Location history adapter + comparator
- P3-6 — Location incremental reuse integration
- P3-7 — Review/audit projection + representative validation + closeout

A small composability prerequisite may be inserted only if current Phase 1/2 runner boundaries demonstrably force duplicate orchestration/fetch/parse. Do not pre-emptively refactor.

## 26. Expected file boundaries

Exact filenames are chosen from latest `dev` at each Issue, but expected ownership is:

- `tools/data/lib/history/**` — shared deterministic History Core;
- Phase 3 domain adapter files under `tools/data/lib/**`;
- Phase 3 runner/test files under `tools/data/**`;
- deterministic fixtures under `tools/data/testdata/**`;
- design/handover/status docs under `docs/**`;
- canonical CSV touched only by P3-0.

No Android product code is expected unless a later separately approved Issue requires it.

## 27. Risks

Primary risks:

- unstable business identity corrupts lineage;
- stale baseline race creates incorrect delta chain;
- source failure is misread as absence;
- processor/input change is misread as external change;
- fingerprint serialization drift creates false changes;
- unsafe reuse hides a real change;
- history/index writes become a new bottleneck;
- source-specific optimization duplicates Phase 1/2 logic;
- repo revision granularity causes conservative recomputation;
- file-based persistence may eventually become operationally insufficient.

Mitigations are stable businessId, comparable gates, precedence rules, single canonical serializer, capability-based reuse, immutable append-only history, CAS, rebuildable indexes, and small Issue/PR implementation.

## 28. Phase 3 closeout gate

Phase 3 is complete only when all are demonstrated:

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

Closeout does not imply full 496-row current-state validation, periodic scheduling, provider-fetch reduction, automatic closure/ending decisions, production auto-write, or DB persistence approval.

## 29. Test execution efficiency

During each implementation Issue:

```text
RED targeted test
-> GREEN targeted test
-> necessary related regressions
```

Do not repeatedly run every expensive suite after each small edit.

On final PR HEAD:

- full `tools/data/test-*.ps1`;
- Android CI as triggered by repository workflow;
- `git diff --check`;
- protected-path diff checks.

## 30. Approved design decisions

This design approves:

1. file-based audit persistence outside product DB;
2. shared Location + Benefit History Core;
3. content-addressed physical artifact dedup;
4. opaque immutable canonical businessId;
5. four-layer fingerprints;
6. conservative capability-based incremental reuse;
7. immutable observations and separate comparisons;
8. change-candidate-only semantics;
9. strict absence gates;
10. audit/review separation;
11. single-writer, optimistic baseline CAS;
12. one canonical history serializer;
13. small Issue/PR decomposition;
14. safety-first closeout metrics and tests.

## 31. Deferred decisions

Not approved here:

- database migration for history;
- periodic scheduler/retry policy;
- automatic production mutation;
- new source families;
- exact future retention/compaction policy;
- exact processor-level version granularity beyond v1 conservative repository revision;
- Android seed identity migration;
- replacement of row-number-based release tooling;
- full-population execution policy.

Any implementation need in these areas requires a separate design/approval step.

## 32. Acceptance

User approved this committed design on 2026-09-26. The next allowed architectural step is a detailed implementation plan using the writing-plans workflow.

No Phase 3 product implementation begins before that plan is reviewed and an execution method is selected.

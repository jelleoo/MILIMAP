# Phase 3 P3-6 Location Incremental Reuse Design

- Status: Approved design draft for written review
- Date: 2026-09-27
- Parent architecture: Phase 3 Snapshot / Incremental Change Detection
- Baseline: `dev@d1df26ce9a68383b9f3de04ba49ef67bef4d8052`
- Scope: P3-6 only
- Capability: `POST_DISCOVERY`

**Authority:** For P3-6, this spec supersedes the P3-6 portions of the older combined plan `docs/superpowers/plans/2026-09-26-phase3-p3-5-p3-6-location-history.md`. The merged P3-5 design remains authoritative for Location projections, observations, and comparison semantics.

## 1. Problem

P3-5 established durable Location history, deterministic projections/fingerprints, immutable observations, and domain comparison. Current Phase 1 still runs POI matching on every Location run even when current discovery evidence is identical to the latest comparable committed Location observation.

P3-6 adds a conservative post-discovery reuse path:

```text
normalize
-> discovery always runs
-> current Input / Evidence / Execution checkpoint
-> compare with latest comparable committed Location baseline
-> if reuse gate passes: skip matcher
-> otherwise: run matcher exactly once
-> P3-5 observation/comparison
-> existing History prepare + commit
```

The optimization removes only matcher work. It does not reduce Naver provider requests.

## 2. Goals

P3-6 will:

- keep current POI discovery on every run;
- compute current evidence deterministically before matcher execution;
- reuse a prior semantic result only when input/evidence/execution and trust conditions all match;
- avoid creating a synthetic `PoiMatchResult` on reuse;
- create a fresh immutable observation for every run;
- keep reuse provenance auditable;
- preserve existing optimistic baseline CAS and single-writer commit semantics;
- measure actual matcher work avoided;
- fail closed on untrusted baselines;
- avoid duplicate discovery, duplicate matcher execution, and unnecessary artifact rewriting.

## 3. Non-goals

P3-6 does not:

- skip Naver discovery;
- reduce query-plan/provider request count;
- add a provider cache;
- store raw Naver responses;
- add FULL_EVIDENCE reuse;
- add periodic scheduling;
- add automatic retry;
- add a multi-business batch commit policy;
- redesign Phase 1 discovery or matching;
- change P3-5 fingerprint/comparison meaning;
- change History Core/store/schema;
- introduce processor-level versioning beyond current conservative repository revision;
- introduce DB/API/auth/dependency changes;
- mutate canonical/seed/apps;
- emit MOVED/CLOSED production truth.

Any implementation need in those areas requires explicit approval.

## 4. Responsibility split

### Architecture owner

Owns:

- reuse safety gate;
- baseline trust semantics;
- execution-configuration meaning;
- artifact reuse boundary;
- invalid-baseline recovery;
- CAS/retry semantics;
- metrics meaning;
- failure/concurrency acceptance matrix;
- final architecture review and merge decision.

### Codex

Owns:

- latest-`dev` call-path inventory;
- exact helper/file proposal;
- RED fixtures;
- minimal PowerShell implementation;
- matcher invocation instrumentation;
- baseline/artifact validation wiring;
- targeted regressions;
- final full suite / Android / CI / PR mechanics.

Codex must stop rather than independently introduce a new storage model, schema, Phase 1 contract, normalization policy, cache, retry loop, generic incremental framework, or dependency.

## 5. Architectural boundary

P3-6 uses the existing one-way dependency direction:

```text
canonical row + businessId
        |
        v
ConvertTo-NormalizedBusiness
        |
        +--> current InputProjection
        +--> current ExecutionProjection
        |
        v
baseline resolution
        |
        v
Invoke-PoiDiscovery             ALWAYS
        |
        v
PoiDiscoveryBatch
        |
        v
current EvidenceProjection
        |
        v
Location reuse decision
   |                    |
 eligible             rejected
   |                    |
matcher skipped      Invoke-PoiMatchEvaluation once
   |                    |
prior semantic          |
   \                    /
    v                  v
    P3-5 Location observation/comparison
                    |
                    v
      existing Prepare-HistoryRun
                    |
                    v
       existing Commit-HistoryRun
```

Phase 1 remains unaware of Phase 3.

## 6. One-business atomic run

P3-6 v1 processes exactly one canonical business per invocation.

```text
one canonical row
-> one businessId
-> one discovery
-> matcher 0 or 1
-> one LOCATION observation
-> zero or one comparison
-> one optimistic-CAS commit
```

P3-6 does not introduce a multi-business history transaction.

Rationale:

- a baseline race for one business must not invalidate unrelated network/verification work;
- the current History commit model already provides correct per-business optimistic CAS;
- full-population/batch execution policy is deferred by the parent Phase 3 design.

## 7. Entrypoint and post-discovery boundary

Two layers are introduced.

### 7.1 `Invoke-Phase3LocationHistory`

Responsibilities:

- validate canonical `businessId`;
- normalize the row;
- resolve repository clean state exactly once;
- construct stable execution configuration;
- resolve baseline once before discovery;
- invoke `Invoke-PoiDiscovery` exactly once;
- pass the resulting `PoiDiscoveryBatch` into the post-discovery layer.

### 7.2 `Invoke-LocationIncrementalPostDiscovery`

Consumes an already-created `PoiDiscoveryBatch`.

Responsibilities:

- build current checkpoint;
- make reuse decision;
- invoke matcher zero or one time;
- build Location observation package;
- compare against prior valid baseline where allowed;
- create the run manifest;
- prepare;
- commit using the existing optimistic baseline CAS;
- return metrics and audit result.

The post-discovery layer must not call `Invoke-PoiDiscovery`.

## 8. Current pre-match checkpoint

Before matcher execution, compute:

```text
LocationIncrementalCheckpoint

InputProjection
EvidenceProjection
ExecutionProjection

InputFingerprint
EvidenceFingerprint
ExecutionFingerprint
```

Reuse only existing P3-5 projection meaning:

- `ConvertTo-LocationHistoryInputProjection`
- `ConvertTo-LocationHistoryEvidenceProjection`
- `ConvertTo-LocationHistoryExecutionProjection`
- existing History fingerprint serializer/hash functions.

P3-6 must not reimplement projection fields or canonicalization rules.

EvidenceFingerprint remains matcher-independent.

## 9. Execution configuration and dirty repository state

The parent Phase 3 design already requires a dirty working tree to be ineligible for incremental reuse.

P3-6 records repository clean state inside the existing Location execution projection configuration:

```text
Configuration = {
    ProcessingMode = PHASE3_LOCATION_INCREMENTAL
    IncrementalReuseVersion = 1
    RepositoryClean = true | false
}
```

Do not include `ReuseApplied` in ExecutionFingerprint.

Rationale:

- a dirty recompute observation must not later be treated as processor-equivalent to a clean run;
- reuse/non-reuse mode itself must not make fingerprints self-invalidating;
- no new fingerprint schema or processor-version subsystem is needed.

The repository state provider is evaluated once per run and its value is reused for checkpoint, decision, observation, and metrics.

## 9.1 Rollout compatibility with pre-P3-6 baselines

Existing P3-5 Location observations may have been created without the P3-6 execution configuration above.

The first P3-6 run against such a baseline is therefore expected to reject reuse conservatively because the ExecutionFingerprint differs. It runs the matcher once and commits a P3-6-compatible baseline.

Only a later run with the same repository revision, clean-state configuration, input, and complete discovery evidence can reuse matcher output.

This one-time warm-up recomputation is intentional. P3-6 must not special-case or retrofit old observations to bypass the execution gate.

## 10. Baseline lookup

Baseline lookup uses the derived Location history index:

```text
Get-HistoryLatestEntry
- BusinessId <current>
- Domain LOCATION
- ComparableOnly
```

No normal-path full-history scan is introduced.

The expected baseline for commit remains the current `LatestComparableObservationId`.

## 11. Baseline resolution contract

Conceptually, as a **Location-domain internal in-memory shape** (not a new History Core/schema contract):

```text
LocationBaselineResolution
ContractVersion = 1

Status =
  NONE
  VALID
  ARTIFACT_INVALID

ExpectedBaselineObservationId

Observation
EvidenceProjection
EvidenceReference
SemanticProjection
SemanticReference
```

### 11.1 NONE

No comparable index entry exists.

```text
ExpectedBaselineObservationId = ''
```

A missing index file is treated as NONE before discovery because it may be a true first run.

### 11.2 VALID

A latest comparable observation exists and all required trust checks pass.

Required:

- LOCATION domain;
- observation identity matches index;
- previous run is COMMITTED;
- `OperationalStatus == COMPLETE`;
- `Comparable == true`;
- exactly one `LOCATION_EVIDENCE_PROJECTION`;
- evidence artifact hash exists and validates;
- evidence projection type/version validates;
- evidence projection fingerprint equals observation EvidenceFingerprint;
- exactly one `LOCATION_SEMANTIC_PROJECTION`;
- semantic artifact hash exists and validates;
- semantic projection type/version validates;
- semantic projection fingerprint equals observation SemanticFingerprint;
- `SemanticResultReference` matches semantic artifact reference.

### 11.3 ARTIFACT_INVALID

The index/observation lineage itself is structurally valid, but required Location projection artifact content cannot be trusted.

Examples:

- projection artifact missing;
- artifact hash mismatch;
- projection type/version mismatch;
- projection fingerprint mismatch;
- semantic result reference mismatch.

The expected baseline observation ID is preserved for CAS.

This status permits current discovery/matcher recomputation, but the damaged previous semantic projection is not used for comparison or reuse.

## 12. Structural history corruption

The following are not downgraded to `ARTIFACT_INVALID`:

- malformed index JSON;
- index business/domain mismatch;
- indexed observation missing;
- observation identity mismatch;
- indexed observation belongs to a non-COMMITTED run.

These mean history lineage itself cannot be trusted.

Result:

```text
fail closed
provider calls = 0
matcher calls = 0
no prepare/commit
```

P3-6 does not repair structural history corruption.

## 13. Missing derived index

A missing Location index file is initially treated as `NONE`.

If committed history actually exists but the index is missing, the existing commit path handles it:

1. current run performs discovery and normal matcher work;
2. expected baseline remains empty;
3. `Commit-HistoryRun` invokes existing index recovery/rebuild;
4. actual latest comparable ID becomes non-empty;
5. optimistic CAS returns `BASELINE_MOVED` with `RetryRequired=true`.

No automatic retry follows.

The next explicit invocation can use the rebuilt index.

## 14. Reuse decision contract

Conceptually, as a **Location-domain internal in-memory shape** (not a new History Core/schema contract):

```text
LocationIncrementalReuseDecision
ContractVersion = 1

Capability = POST_DISCOVERY
ReuseApplied

BaselineResolution
ExpectedBaselineObservationId

RepositoryClean
CurrentDiscoveryStatus

InputMatch
EvidenceMatch
ExecutionMatch

ReasonCodes[]
```

Reason vocabulary:

- `PRIOR_ARTIFACT_INVALID`
- `NO_BASELINE`
- `DIRTY_REPOSITORY`
- `CURRENT_DISCOVERY_NOT_COMPLETE`
- `INPUT_CHANGED`
- `EXECUTION_CHANGED`
- `EVIDENCE_CHANGED`
- `REUSE_ELIGIBLE`

No fuzzy/partial matching is used.

## 15. Reuse decision precedence

Evaluate in this order:

```text
1. baseline artifact invalid
   -> PRIOR_ARTIFACT_INVALID

2. no baseline
   -> NO_BASELINE

3. repository dirty
   -> DIRTY_REPOSITORY

4. current DiscoveryStatus != COMPLETE
   -> CURRENT_DISCOVERY_NOT_COMPLETE

5. InputFingerprint mismatch
   -> INPUT_CHANGED

6. ExecutionFingerprint mismatch
   -> EXECUTION_CHANGED

7. EvidenceFingerprint mismatch
   -> EVIDENCE_CHANGED

8. all checks pass
   -> REUSE_ELIGIBLE
```

Only `REUSE_ELIGIBLE` sets `ReuseApplied=true`.

Any other result recomputes via matcher.

## 16. Reuse gate

Reuse requires all of:

- capability `POST_DISCOVERY`;
- current repository clean;
- current discovery COMPLETE;
- valid previous comparable COMPLETE baseline;
- InputFingerprint equal;
- EvidenceFingerprint equal;
- ExecutionFingerprint equal;
- validated previous evidence projection;
- validated previous semantic projection.

No individual candidate/key similarity can override the gate.

## 17. Recompute path

If reuse is rejected:

```text
already normalized Business
+
already created PoiDiscoveryBatch
        |
        v
Invoke-PoiMatchEvaluation exactly once
```

Do not rediscover.

Then reuse the existing P3-5 path:

- `New-LocationHistoryObservationPackage`
- `Compare-LocationHistoryObservations`

The same ExecutionConfiguration used for the pre-match checkpoint must be passed into the P3-5 observation package.

## 18. Reuse path

On eligible reuse:

- do not call `Invoke-PoiMatchEvaluation`;
- do not fabricate a `PoiMatchResult`;
- validate and reuse the prior semantic projection;
- create a fresh Location observation for the current run.

The new observation has:

- fresh RunId;
- fresh ObservedAt;
- fresh ObservationId;
- current InputFingerprint;
- current EvidenceFingerprint;
- prior SemanticFingerprint;
- current ExecutionFingerprint.

Because the reuse gate requires equality, these current input/evidence/execution fingerprints equal the trusted baseline values, but they are still computed from the current run checkpoint.

## 19. Reuse artifact references

A reuse observation must not copy the baseline observation's entire artifact-reference array.

It references exactly:

1. one validated prior `LOCATION_EVIDENCE_PROJECTION`;
2. one validated prior `LOCATION_SEMANTIC_PROJECTION`;
3. one new `LOCATION_REUSE_DECISION`.

This prevents transitive accumulation of old reuse audit artifacts.

Example:

```text
run 1 recompute:
E1, S1

run 2 reuse:
E1, S1, R2

run 3 reuse:
E1, S1, R3
```

`R2` must not appear in run 3.

## 20. Physical artifact preparation on reuse

Reuse does not restage the prior evidence or semantic projection.

The only newly prepared physical artifact is:

```text
LOCATION_REUSE_DECISION
```

Therefore a normal eligible reuse package has:

```text
PreparedArtifacts.Count == 1
```

The existing committed evidence/semantic references are validated by `Prepare-HistoryRun` as existing references.

## 21. Reuse-decision audit artifact

```text
ContractType = LocationReuseDecision
ContractVersion = 1

ProcessingMode =
  REUSED_IDENTICAL_DISCOVERY_EVIDENCE

Capability = POST_DISCOVERY

ReusedFromObservationId

InputMatch = true
EvidenceMatch = true
ExecutionMatch = true

RepositoryClean = true
PreviousComparable = true
ReuseApplied = true

ReasonCodes = [REUSE_ELIGIBLE]
```

This artifact is processing provenance only.

It does not participate in:

- InputFingerprint;
- EvidenceFingerprint;
- SemanticFingerprint;
- ExecutionFingerprint.

Rejected decisions remain in-memory return/metrics state; P3-6 does not create a physical audit artifact for every rejection.

## 22. Comparison semantics

### VALID baseline + reuse

Run `Compare-LocationHistoryObservations` normally.

Expected:

- no delta dimensions;
- no change candidates.

Comparison is persisted rather than inferred implicitly from reuse.

### VALID baseline + recompute

Use P3-5 normally:

```text
Previous = committed baseline
Current = staged current observation
StagedCurrentSemanticProjection = current semantic
```

### NONE baseline

Compare with `Previous = null`, producing `BASELINE_ESTABLISHED`.

### ARTIFACT_INVALID baseline

- matcher recomputes current result;
- current observation is built;
- comparison is omitted because prior semantic projection is untrusted;
- expected baseline ID is still supplied to CAS.

Do not emit `BASELINE_ESTABLISHED` for a known-but-untrusted prior baseline.

## 23. Strict absence interaction

Strict Location absence cannot be created through matcher reuse.

If a previously selected location becomes a genuine COMPLETE zero-candidate discovery:

- candidate set changes;
- EvidenceFingerprint changes;
- reuse is rejected as `EVIDENCE_CHANGED`;
- matcher runs;
- P3-5 computes `AbsenceEligible`;
- P3-5 comparator may emit `LOCATION_ABSENCE_SUSPECTED`.

No reuse shortcut manufactures absence.

## 24. Run manifest mapping

One-business run mapping:

| Observation operational status | Manifest ExecutionStatus | CompletedBusinessIds | FailedBusinessIds |
| --- | --- | --- | --- |
| COMPLETE | COMPLETE | current businessId | empty |
| PARTIAL | PARTIAL | current businessId | empty |
| FAILED | FAILED | empty | current businessId |

A PARTIAL observation is still valid audit history and is not placed in `FailedBusinessIds`.

The prepared manifest uses `RunCommitStatus=PREPARED`. Existing History Core owns terminal commit status.

## 25. Prepare / commit / CAS

P3-6 adds no new persistence engine.

Use:

```text
New-HistoryRunManifest
-> Prepare-HistoryRun
-> Commit-HistoryRun
```

Expected baseline:

```text
<businessId>|LOCATION
=
BaselineResolution.ExpectedBaselineObservationId
```

If the baseline moved:

```text
Code = BASELINE_MOVED
RetryRequired = true
```

No automatic retry, rediscovery, or second matcher invocation is allowed.

If the writer lock is held:

```text
Code = WRITER_LOCKED
RetryRequired = false
```

No hidden retry follows.

## 26. Expensive work stays outside writer lock

Discovery and matcher work complete before `Commit-HistoryRun`.

The existing writer lock covers only the persistence commit window.

P3-6 does not acquire or extend the writer lock around network/matcher work.

## 27. Metrics

P3-6 v1 reports:

- `RowsRequested`
- `RowsCompleted`
- `BaselineHits`
- `BaselineMisses`
- `ReuseEligible`
- `ReuseApplied`
- `ReuseRejected`
- `ExternalFetchCount`
- `MatcherCount`
- `AvoidedMatcherCount`
- `ComparisonCandidates`
- `HumanReviewCandidates`

Definitions:

### RowsRequested

Always 1 for the one-business entrypoint.

### RowsCompleted

1 only when `Commit.Code == COMMITTED`; otherwise 0.

It represents durable history completion, not semantic success.

### BaselineHits / Misses

A hit means a non-empty expected latest-comparable observation ID was resolved.

`ARTIFACT_INVALID` remains a baseline hit because the lineage ID exists.

### ReuseEligible

1 only when decision reason is `REUSE_ELIGIBLE`.

### ReuseApplied

1 only when matcher was actually skipped.

### ReuseRejected

1 when matcher reuse was not applied.

### ExternalFetchCount

Derived from current `PoiDiscoveryBatch.QueryAttempts`:

```text
count(Status != SKIPPED)
```

This matches Phase 1's existing API-call definition.

### MatcherCount

Actual matcher invocation count: 0 or 1.

### AvoidedMatcherCount

1 only for applied reuse.

### ComparisonCandidates

`Comparison.ChangeCandidates.Count`, or 0 when no comparison exists.

### HumanReviewCandidates

Count only:

- `LOCATION_CHANGE_SUSPECTED`;
- `LOCATION_ABSENCE_SUSPECTED`.

## 28. Core acceptance matrix

| Scenario | Discovery | Matcher | Reuse result | Comparison/result |
| --- | ---: | ---: | --- | --- |
| first run | yes | 1 | NO_BASELINE | BASELINE_ESTABLISHED |
| identical second run | yes | 0 | REUSE_ELIGIBLE | no delta |
| provider physical reorder only | yes | 0 | REUSE_ELIGIBLE | no delta |
| duplicate same-query discovery membership only | yes | 0 | REUSE_ELIGIBLE | no delta |
| phone/category/provider-link only | yes | 1 | EVIDENCE_CHANGED | EVIDENCE_CHANGE_ONLY if semantic equal |
| canonical input change | yes | 1 | INPUT_CHANGED | CANONICAL_INPUT_CHANGED |
| repository revision/config change | yes | 1 | EXECUTION_CHANGED | PROCESSOR_OUTPUT_CHANGED |
| dirty repository | yes | 1 | DIRTY_REPOSITORY | no reuse |
| current PARTIAL | yes | 1 | CURRENT_DISCOVERY_NOT_COMPLETE | operational unavailable |
| current FAILED | yes | 1 | CURRENT_DISCOVERY_NOT_COMPLETE | operational unavailable |
| selected -> COMPLETE zero candidate | yes | 1 | EVIDENCE_CHANGED | strict absence path |
| prior projection artifact corrupt | yes | 1 | PRIOR_ARTIFACT_INVALID | no comparison |
| structural history corruption | no | 0 | fail closed | no commit |

## 29. Dirty-run poisoning matrix

Required three-run regression:

```text
run A:
revision abc
RepositoryClean = true
-> normal comparable baseline

run B:
revision abc
RepositoryClean = false
-> reuse rejected
-> matcher runs
-> ExecutionFingerprint contains RepositoryClean=false

run C:
revision abc
RepositoryClean = true
-> execution differs from latest comparable dirty run
-> matcher runs
```

Dirty-to-dirty reuse is also forbidden by the reuse gate even if fingerprints match.

## 30. Latest-comparable preservation matrix

Required sequence:

```text
run 1 COMPLETE comparable
run 2 PARTIAL non-comparable
run 3 COMPLETE
```

The baseline for run 3 must remain run 1, not run 2.

P3-6 must always use `LatestComparableObservationId`, never `LatestObservationId`, for reuse baseline/CAS expectation.

## 31. Artifact-lineage matrix

Three-run reuse regression:

```text
run 1 recompute refs: E1, S1
run 2 reuse refs:     E1, S1, R2
run 3 reuse refs:     E1, S1, R3
```

Each reuse observation must contain exactly:

- one Location evidence projection reference;
- one Location semantic projection reference;
- one Location reuse-decision reference.

Old reuse-decision references must not accumulate transitively.

## 32. Artifact-corruption behavior

### Projection artifact corruption

If baseline lineage is structurally valid but evidence/semantic artifact trust fails:

- status `ARTIFACT_INVALID`;
- preserve expected baseline observation ID;
- perform current discovery and matcher;
- create current observation;
- do not compare against damaged prior semantic;
- attempt CAS commit.

A successful commit advances latest comparable to the new valid observation.

P3-6 does not repair the historical corrupted artifact.

### Structural corruption

Fail before provider/matcher work.

## 33. Missing-index behavior

Required regression:

1. commit a valid prior Location baseline;
2. remove only its derived index;
3. invoke P3-6;
4. pre-discovery baseline resolution reports NONE;
5. discovery/matcher occur once;
6. commit-time existing index recovery rebuilds baseline;
7. commit returns `BASELINE_MOVED`;
8. stale current observation/comparison is not published authoritatively;
9. no automatic retry occurs.

## 34. Concurrency matrix

| Scenario | Work before commit | Commit result | Authoritative current publish |
| --- | --- | --- | --- |
| normal reuse | discovery only | COMMITTED | yes |
| normal recompute | discovery + matcher | COMMITTED | yes |
| reuse then baseline moves | discovery, matcher 0 | BASELINE_MOVED | no |
| recompute then baseline moves | discovery + matcher 1 | BASELINE_MOVED | no |
| writer lock held | normal work outside lock | WRITER_LOCKED | no |
| missing index with prior history | discovery + matcher | BASELINE_MOVED after rebuild | no |

No scenario automatically retries.

## 35. Test layering

### Incremental primitive tests

`tools/data/test-location-incremental-reuse.ps1`

Covers:

- checkpoint fingerprints;
- baseline resolution;
- artifact validation;
- decision precedence;
- reuse package;
- artifact lineage;
- prepared-artifact count.

### End-to-end orchestration tests

`tools/data/test-phase3-location-history.ps1`

Covers:

- canonical row -> normalization -> discovery;
- repository-state evaluation exactly once;
- first run;
- identical second run matcher skip;
- rejection paths;
- observation/comparison;
- manifest;
- prepare/commit;
- metrics;
- CAS failure;
- writer lock;
- missing index;
- no retry.

Tests use deterministic request/matcher instrumentation. No live Naver requests are required.

## 36. Implementation decomposition

### Task 1 — incremental primitives

Create:

- `tools/data/lib/history/location-incremental-reuse.ps1`
- `tools/data/test-location-incremental-reuse.ps1`

RED -> GREEN:

- checkpoint;
- baseline resolution;
- reuse decision;
- reuse observation package;
- reuse-decision artifact.

No discovery orchestration or commit flow yet.

### Task 2 — one-business orchestration

Create:

- `tools/data/invoke-phase3-location-history.ps1`
- `tools/data/test-phase3-location-history.ps1`

RED -> GREEN:

- canonical businessId/normalization;
- repository state once;
- discovery exactly once;
- matcher zero/one;
- P3-5 package/comparison;
- manifest;
- prepare/commit;
- metrics.

### Task 3 — failure/concurrency hardening

Add RED regressions for:

- artifact corruption;
- structural corruption;
- latest-comparable preservation;
- missing index;
- BASELINE_MOVED on reuse;
- BASELINE_MOVED on recompute;
- WRITER_LOCKED;
- no retry;
- no stale authoritative publication;
- dirty-run poisoning.

Fix only minimal implementation defects discovered by these tests.

### Task 4 — final gate

On final PR HEAD:

- P3-6 targeted tests;
- Phase 1 regressions;
- P3-5 Location history regressions;
- History Core/store/commit regressions;
- full `tools/data/test-*.ps1`;
- Android unit/lint/debug build;
- `git diff --check`;
- protected-path diff;
- CI;
- whole-branch architecture review.

Stop before merge for architecture review.

## 37. Expected file boundary

Production:

- CREATE `tools/data/lib/history/location-incremental-reuse.ps1`
- CREATE `tools/data/invoke-phase3-location-history.ps1`

Tests:

- CREATE `tools/data/test-location-incremental-reuse.ps1`
- CREATE `tools/data/test-phase3-location-history.ps1`

By default, do not modify:

- Phase 1 production;
- `location-history-adapter.ps1`;
- `compare-location-history.ps1`;
- History Core/store/commit;
- canonical/seed/apps.

If current code proves that a tiny P3-5 helper exposure is necessary to avoid fingerprint-rule duplication, stop and request review before changing an existing production file.

## 38. Efficiency constraints

P3-6 explicitly prevents:

- second discovery after a reuse rejection;
- matcher invocation before reuse decision;
- second matcher invocation;
- repeated repository-state checks;
- full-history scans in the normal path;
- reserialization/restaging of reused evidence/semantic artifacts;
- transitive reuse-audit reference growth;
- long-held writer locks around network/matcher work;
- batch-wide CAS blast radius;
- generic Benefit/Location incremental framework extraction.

The largest remaining cost is deliberate: Naver discovery still runs on every P3-6 invocation.

## 39. Risks

Known accepted risks:

- repository revision remains a conservative execution boundary, so unrelated commits may reject matcher reuse;
- Naver discovery remains the dominant network cost;
- corrupted historical artifacts remain fail-closed during a later full index rebuild even if a newer valid observation was committed;
- a missing derived index may cause one wasted discovery/matcher run before commit-time rebuild returns BASELINE_MOVED;
- v1 does not define automatic retry or scheduler behavior.

## 40. Acceptance

P3-6 is complete only when:

1. discovery always runs exactly once per normal invocation;
2. matcher runs zero times only when the complete reuse gate passes;
3. identical second run skips matcher and records `AvoidedMatcherCount=1`;
4. reuse rejection never rediscoveries;
5. dirty repository never reuses;
6. dirty observation cannot poison later clean reuse;
7. latest comparable, not latest observation, is used as baseline;
8. strict absence cannot arise through reuse;
9. reuse observations reference exactly evidence + semantic + current reuse decision;
10. reused evidence/semantic artifacts are not physically rewritten;
11. artifact-invalid baseline recomputes without comparison;
12. structural history corruption fails before provider/matcher work;
13. baseline movement and writer-lock failures never auto-retry;
14. stale prepared data is not authoritative after failed commit;
15. no Phase 1 or History Core contract/schema change is introduced;
16. full data suite, Android verification, and CI pass;
17. P3-7 is not started in the same PR.

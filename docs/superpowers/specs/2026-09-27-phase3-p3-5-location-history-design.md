# Phase 3 P3-5 Location History Adapter / Comparator Design

- Status: Approved design draft for written review
- Date: 2026-09-27
- Parent architecture: Issue #94
- Baseline: `dev@5fc4f2354b3c2c8c0d33e1835a4fe8188d6169f2`
- Scope: P3-5 only
- Out of scope: P3-6 matcher reuse integration

**Authority:** For P3-5, this spec supersedes the P3-5 portions of `docs/superpowers/plans/2026-09-26-phase3-p3-5-p3-6-location-history.md`. That older plan remains background only for P3-5. Its P3-6 guidance is not superseded by this document.

## 1. Problem

Phase 1 can evaluate the current POI/location state, but Phase 3 still lacks a Location-domain history adapter and comparator that can compare runs by stable `businessId` without confusing provider evidence movement with real location change.

P3-5 adds deterministic Location projections, history observations, and field-level change-candidate semantics on top of the already merged Phase 3 History Core. It must not redesign Phase 1 discovery/matching or add reuse orchestration yet.

## 2. Goals

P3-5 will:

- project current Phase 1 inputs, discovery evidence, matcher semantics, and execution metadata into the existing four History fingerprints;
- persist immutable Location observations using existing History Core/store contracts;
- compare current vs previous comparable Location observations;
- emit review candidates only for material Location meaning changes;
- keep provider/evidence-only change separate from semantic location change;
- enforce strict absence eligibility;
- prepare a matcher-independent EvidenceFingerprint suitable for later P3-6 POST_DISCOVERY reuse.

## 3. Non-goals

P3-5 does not:

- skip or reuse matcher work;
- reduce Naver provider requests;
- modify `Invoke-PoiDiscovery` or `Invoke-PoiMatchEvaluation`;
- change Phase 1 public contracts;
- add raw Naver response persistence;
- change History Core/schema;
- add DB/API/auth/dependency changes;
- write canonical/seed/apps;
- emit MOVED/CLOSED or other production truth;
- create new normalization or POI ranking logic.

If implementation appears to require a Phase 1 production change or History Core change, stop and request approval.

## 4. Responsibility split

### Architecture owner

Owns:

- projection field inclusion/exclusion;
- Evidence vs Semantic boundary;
- comparability and absence rules;
- field-level delta semantics;
- review candidate vocabulary;
- mutation matrix and acceptance criteria;
- staged-current trust boundary;
- final architecture/code review and merge decision.

### Codex

Owns:

- latest-`dev` call-path inventory;
- exact file proposal;
- RED tests;
- minimal implementation;
- regression execution;
- commit/push/PR/CI mechanics;
- duplicate-work/full-scan/bottleneck checks.

Codex must not independently introduce new storage models, schemas, normalization policies, source adapters, comparison semantics, or public contracts.

## 5. Architecture boundary

```text
NormalizedBusiness
      |
      v
Invoke-PoiDiscovery
      |
      v
PoiDiscoveryBatch
      |
      +--> LocationHistoryEvidenceProjection
      |         |
      |         v
      |   EvidenceFingerprint
      |
      v
Invoke-PoiMatchEvaluation
      |
      v
PoiMatchResult
      |
      +--> LocationHistorySemanticProjection
                |
                v
          SemanticFingerprint

InputProjection + EvidenceProjection + SemanticProjection + ExecutionProjection
                              |
                              v
                    HistoryObservation
                              |
                              v
                 Compare-HistoryObservations
                              |
                              v
                  Location domain resolver
```

Important boundary:

- EvidenceFingerprint must be computable before matcher execution.
- `PoiMatchResult.Evidence` and matcher diagnostics are therefore not part of Location evidence.
- P3-5 does not alter the Phase 1 runner.

## 6. Location Input Projection

`LocationHistoryInput` v1 contains only fields that materially affect current Phase 1 discovery/matching.

Included:

- `ProjectionType`
- `ProjectionVersion`
- `BusinessId`
- `OriginalName`
- `NormalizedName`
- `BaseName`
- `BranchName`
- `OriginalRoadAddress`
- `OriginalLotAddress`
- `PreferredAddress`
- `Province`
- `City`
- `District`
- `Dong`
- `RoadName`
- `BuildingMain`
- `BuildingSub`
- `Floor`
- `Unit`

Excluded:

- `SourceRowNumber`
- `AddressParseStatus`
- `NormalizationWarnings`

Rationale:

- `SourceRowNumber` is locator metadata, not lineage identity.
- parse status/warnings currently do not participate directly in Phase 1 discovery/matcher decisions and must not cause false invalidation.
- if Phase 1 later consumes them materially, projection versioning must be revisited.

## 7. Location Evidence Projection

`LocationHistoryEvidence` v1 is built from `PoiDiscoveryBatch` only.

Included:

- `ProjectionType`
- `ProjectionVersion`
- `DiscoveryStatus`
- `QueryAttempts[]`
  - `StrategyCode`
  - `Query`
  - `QueryOrder`
  - `Status`
  - `ErrorCode`
- `Candidates[]`
  - `Provider`
  - `OriginalName`
  - `NormalizedName`
  - `RoadAddress`
  - `LotAddress`
  - `Latitude`
  - `Longitude`
  - `Phone`
  - `Category`
  - `ProviderLink`
  - `DiscoveredBy[]`
    - `StrategyCode`
    - `Query`
    - `QueryOrder`

Excluded:

- `SourceRowNumber`
- `CandidateKey`
- `ResultPosition`
- `ResultCount`
- `PoiMatchResult.Evidence`
- matcher diagnostics

### Ordering

Order-insensitive:

- `Candidates[]`
- `Candidates[].DiscoveredBy[]`
- `QueryAttempts[]`

Before canonical serialization, each candidate's `DiscoveredBy[]` is reduced to distinct query-membership tuples `(StrategyCode, Query, QueryOrder)`. Duplicate appearances from the same query do not create extra evidence because the current matcher also evaluates repeated discovery by distinct successful query membership. Each array item carries its own semantic values such as `QueryOrder`; physical array position must not affect the fingerprint.

### Rationale

- Naver local search uses randomized result ordering.
- `CandidateKey` is a derived run-level evidence key and not a temporal business identity.
- result position/count do not directly affect matcher semantics.
- phone/category/provider-link still belong to evidence; they may change EvidenceFingerprint without implying a semantic Location change.

## 8. Location Semantic Projection

`LocationHistorySemantic` v1 contains only interpreted Location meaning.

Fields:

- `ProjectionType`
- `ProjectionVersion`
- `EvaluationStatus`
- `Classification`
- `SelectionStatus = SELECTED | NONE`
- `SelectedLocation`
  - `Name`
  - `RoadAddress`
  - `LotAddress`
  - `Latitude`
  - `Longitude`
- `MaterialReasonCodes[]`
- `ConflictCodes[]`
- `AbsenceEligible`

Excluded:

- `CandidateKey`
- `RankedCandidateKeys`
- phone/category/provider-link
- evaluated/surviving counts
- raw matcher evidence
- `ProductionAction`

`ProductionAction` remains contract-validated as `NONE`, but is not part of semantic fingerprint meaning.

### Selected string normalization

No new normalization algorithm is introduced.

- selected name uses `ConvertTo-PoiMatchCompactText`;
- selected road address uses `ConvertTo-PoiMatchCompactText`;
- selected lot address uses `ConvertTo-PoiMatchCompactText`;
- coordinates remain numeric and are serialized by the existing canonical History serializer using invariant numeric formatting.

### Material outcome reasons

Only the following outcome-level reasons participate in the semantic projection:

- `SINGLE_STRONG_CANDIDATE`
- `MULTIPLE_PLAUSIBLE_CANDIDATES`
- `INSUFFICIENT_IDENTITY_EVIDENCE`
- `NO_CANDIDATE`
- `DISCOVERY_PARTIAL_FAILURE`
- `DISCOVERY_FAILED`

Matcher-internal evidence such as `NAME_EXACT`, `ADDRESS_EXACT`, or `REPEATED_DISCOVERY` is not semantic Location meaning.

Material reason/conflict arrays are order-insensitive.

## 9. Absence eligibility

`AbsenceEligible=true` only when all are true:

```text
DiscoveryBatch.Status == COMPLETE
Candidates.Count == 0
PoiMatchResult.EvaluationStatus == COMPLETE
PoiMatchResult.Classification == RED
PoiMatchResult.SelectedCandidate == null
PoiMatchResult.ReasonCodes contains NO_CANDIDATE
```

The following never establish absence:

- PARTIAL discovery;
- FAILED discovery;
- provider/request failure;
- matcher INCOMPLETE;
- candidate conflicts;
- ambiguous candidate sets;
- no selection by itself.

P3-5 never emits CLOSED/MOVED from absence.

## 10. Execution Projection

`LocationHistoryExecution` v1 contains:

- `ProjectionType`
- `ProjectionVersion`
- `RepositoryRevision`
- `LocationHistoryAdapterVersion = 1`
- `PoiContractVersion`
- `HistoryContractVersion`
- `FingerprintSchemaVersion`
- `ComparatorVersion`
- `Configuration`

No separate discovery/matcher processor version system is added in v1. Repository revision remains the conservative execution boundary.

## 11. Operational / comparable rules

| Discovery | Evaluation | OperationalStatus | Comparable |
| --- | --- | --- | --- |
| COMPLETE | COMPLETE | COMPLETE | true |
| COMPLETE | INCOMPLETE | PARTIAL | false |
| PARTIAL | INCOMPLETE | PARTIAL | false |
| FAILED | INCOMPLETE | FAILED | false |

A COMPLETE YELLOW or COMPLETE RED result may be comparable. Comparable means the observation completed sufficiently for temporal comparison; it does not mean a location was positively selected.

## 12. Location artifacts and staging

Each recomputed Location observation prepares exactly:

- `LOCATION_EVIDENCE_PROJECTION`
- `LOCATION_SEMANTIC_PROJECTION`

No raw Naver-response artifact is introduced.

Flow:

```text
projection
-> prepared artifacts
-> current HistoryObservation
-> comparison
-> Prepare-HistoryRun
-> Commit-HistoryRun
```

The current semantic artifact is not published before comparison.

### Staged-current semantic seam

Previous projection:

- must always be read from a committed store-backed semantic artifact.

Current projection:

- may use an explicitly supplied staged in-memory semantic projection before commit.

The staged projection must match:

- `ProjectionType`
- `ProjectionVersion`
- current `SemanticFingerprint`
- current `SemanticResultReference`
- referenced artifact `ContentHash`

Any mismatch fails closed.

Forbidden:

- previous staged semantic projection;
- pre-comparison artifact publication;
- generic arbitrary projection injection;
- public trusted/bypass switches.

## 13. Comparator integration

The existing `Compare-HistoryObservations` common precedence remains authoritative.

Location code does not reimplement:

1. operational failure;
2. canonical input change;
3. execution change;
4. evidence-only change;
5. no-delta handling.

Only unresolved semantic Location deltas reach the Location resolver.

## 14. Internal Location delta reasons

History Core `DeltaDimensions` remains unchanged:

- `INPUT`
- `EVIDENCE`
- `SEMANTIC`
- `EXECUTION`

Location-specific field meaning is recorded as reason codes:

- `LOCATION_NAME_CHANGED`
- `LOCATION_ADDRESS_CHANGED`
- `LOCATION_COORDINATE_CHANGED`
- `LOCATION_SELECTION_CHANGED`
- `LOCATION_EVALUATION_CHANGED`
- `COMPLETE_NO_CANDIDATE`

No History schema change is required.

## 15. Field-level comparison rules

### NAME

When both observations are selected, a normalized selected-name difference adds:

- `LOCATION_NAME_CHANGED`

### ADDRESS

When both observations are selected, a selected road or lot address difference adds:

- `LOCATION_ADDRESS_CHANGED`

No new address similarity algorithm is introduced.

### COORDINATE

When both observations are selected, any latitude or longitude difference adds:

- `LOCATION_COORDINATE_CHANGED`

v1 introduces no distance threshold.

### SELECTION

`SELECTED <-> NONE` adds:

- `LOCATION_SELECTION_CHANGED`

A CandidateKey-only change is not a selection change.

### EVALUATION

A change in classification, material outcome reason set, or material conflict set adds:

- `LOCATION_EVALUATION_CHANGED`

Evaluation-only change does not by itself create a Location change candidate.

## 16. Change-candidate rules

### Strict absence

If:

```text
Previous.SelectionStatus == SELECTED
Current.AbsenceEligible == true
```

emit only:

- `LOCATION_ABSENCE_SUSPECTED`

Reasons include:

- `LOCATION_SELECTION_CHANGED`
- `COMPLETE_NO_CANDIDATE`

Do not also emit `LOCATION_CHANGE_SUSPECTED` for the same event.

### Material selected-location change

If both observations are selected and NAME, ADDRESS, or COORDINATE changed:

- emit one `LOCATION_CHANGE_SUSPECTED`;
- include every material field reason that changed.

### Selection change without strict absence

If selection changes between SELECTED and NONE, but strict absence is not proven:

- emit no Location change candidate;
- include `LOCATION_SELECTION_CHANGED` as an audit reason.

This avoids duplicating Phase 1's current-state review queue when selection confidence changes without evidence of a material selected-location field change or strict absence.

### Evaluation-only change

If only evaluation meaning changes while selection remains NONE:

- emit no Location change candidate;
- include `LOCATION_EVALUATION_CHANGED`.

## 17. Mutation matrix

### InputFingerprint equality

Must remain equal when only:

- SourceRowNumber changes;
- AddressParseStatus changes;
- NormalizationWarnings change.

Must change when any Phase 1-used identity/address field changes.

### EvidenceFingerprint equality

Must remain equal when only:

- candidate array order changes;
- `DiscoveredBy[]` physical order changes;
- duplicate `DiscoveredBy[]` entries for the same `(StrategyCode, Query, QueryOrder)` membership are added/removed;
- `QueryAttempts[]` physical order changes;
- ResultPosition changes;
- ResultCount changes;
- CandidateKey changes.

Must change when:

- candidate name/address/coordinate/phone/category/provider link changes;
- query strategy/query/order/status/error changes;
- candidate discovery-query membership changes;
- discovery status changes.

### SemanticFingerprint equality

Must remain equal when only:

- CandidateKey changes;
- RankedCandidateKeys change;
- phone/category/provider link change;
- matcher-internal evidence changes;
- candidate count changes;
- physical ordering changes;

provided final selected-location/evaluation meaning is unchanged.

Must change when:

- selected normalized name changes;
- selected normalized address changes;
- selected coordinates change;
- SELECTED/NONE changes;
- classification changes;
- material outcome reason changes;
- material conflict changes;
- AbsenceEligible changes.

## 18. Comparator acceptance matrix

| Previous | Current | Expected |
| --- | --- | --- |
| no baseline | first comparable | BASELINE_ESTABLISHED |
| identical | identical | no candidate |
| phone/link/category only | same semantic | EVIDENCE_CHANGE_ONLY |
| CandidateKey only | same semantic | no LOCATION_CHANGE_SUSPECTED |
| selected name A -> B | selected | LOCATION_CHANGE_SUSPECTED + LOCATION_NAME_CHANGED |
| address A -> B | selected | LOCATION_CHANGE_SUSPECTED + LOCATION_ADDRESS_CHANGED |
| coordinate A -> B | selected | LOCATION_CHANGE_SUSPECTED + LOCATION_COORDINATE_CHANGED |
| selected -> COMPLETE zero candidate | strict absence | LOCATION_ABSENCE_SUSPECTED only |
| selected -> ambiguous NONE | non-absence | no Location candidate + LOCATION_SELECTION_CHANGED |
| NONE -> selected | non-absence | no Location candidate + LOCATION_SELECTION_CHANGED |
| NONE/RED -> NONE/YELLOW | evaluation only | no Location candidate + LOCATION_EVALUATION_CHANGED |
| current PARTIAL/FAILED | non-comparable | common operational failure/unavailable |
| input changed | any semantic | CANONICAL_INPUT_CHANGED |
| execution changed | any semantic | PROCESSOR_OUTPUT_CHANGED |

## 19. Implementation decomposition

### Task 1 — projections and fingerprints

Create:

- `tools/data/lib/history/location-history-adapter.ps1`
- `tools/data/test-location-history-adapter.ps1`

Implement and test:

- Input projection;
- Evidence projection;
- Semantic projection;
- Execution projection;
- mutation matrix;
- canonical fingerprint integration.

Do not add observation commit/comparator behavior yet.

### Task 2 — observation package

Extend the Location adapter with:

- operational assessment;
- Location observation package;
- projection artifacts;
- store-backed semantic reader;
- staged-current semantic validator.

Test:

- artifact/reference integrity;
- comparability rules;
- staged-current validation;
- forged staged projection rejection;
- unpublished previous semantic artifact rejection.

### Task 3 — Location comparator

Create:

- `tools/data/lib/history/compare-location-history.ps1`
- `tools/data/test-compare-location-history.ps1`

Implement:

- `Resolve-LocationHistoryChange`
- `Compare-LocationHistoryObservations`

Reuse common History comparison precedence.

### Task 4 — final P3-5 gate

Run targeted Location tests, Phase 1 regressions, History regressions, then one full data suite on final PR HEAD.

P3-6 reuse is not part of this PR.

## 20. Test strategy

Targeted RED/GREEN:

- `test-location-history-adapter.ps1`
- `test-compare-location-history.ps1`

Phase 1 regressions:

- `test-poi-verification-contracts.ps1`
- `test-discover-poi-candidates.ps1`
- `test-evaluate-poi-match.ps1`
- `test-phase1-poi-shadow-mode.ps1`

History regressions:

- `test-history-contracts.ps1`
- `test-history-fingerprints.ps1`
- `test-history-store.ps1`
- `test-commit-history-run.ps1`
- `test-benefit-history-adapter.ps1`

Final PR HEAD only:

- all `tools/data/test-*.ps1`;
- Android repository CI/local gate as required by current workflow;
- `git diff --check`;
- protected-path diff.

Do not run the expensive full suite after every small RED/GREEN edit.

## 21. Protected paths

P3-5 must not modify:

- `data/canonical/**`
- `data/seed/**`
- `apps/**`

## 22. Efficiency and bottleneck controls

The design explicitly avoids:

- matcher result inside EvidenceFingerprint;
- provider physical result ordering as evidence meaning;
- CandidateKey as temporal identity;
- duplicate Location implementations of common comparison precedence;
- a new raw Naver response capture system;
- a new Location persistence engine;
- a Benefit/Location shared adapter refactor before evidence justifies it;
- full-suite/Android build on every small implementation step.

The remaining adapter-validation boilerplate duplication with Benefit is accepted intentionally. Refactoring it now would widen P3-4 regression scope without improving P3-5 correctness.

## 23. Risks

Known risks:

- matcher material reason/conflict meaning may evolve and require projection-version review;
- exact coordinate comparison may raise review candidates for small provider coordinate changes;
- file-history staged semantic validation remains domain-owned in both Benefit and Location;
- P3-6 will still perform provider discovery on every run; only matcher work is eligible for later reuse.

These are accepted for P3-5 v1.

## 24. Acceptance

P3-5 is complete only when:

1. projections/fingerprints obey the mutation matrix;
2. comparable/operational boundaries are deterministic;
3. staged-current comparison is fail-closed;
4. common precedence is reused rather than duplicated;
5. CandidateKey/provider-only movement and selection-only confidence changes do not create false Location change candidates;
6. strict absence is the only path to `LOCATION_ABSENCE_SUSPECTED`;
7. selected material NAME/ADDRESS/COORDINATE changes create only review candidates, never MOVED/CLOSED truth;
8. Phase 1 behavior remains unchanged;
9. protected paths remain unchanged;
10. final full data suite and CI pass.

P3-6 POST_DISCOVERY matcher reuse starts only after P3-5 merges.

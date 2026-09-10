# Phase 1 POI Verification Contracts Design

- Status: Proposed for owner review
- Date: 2026-09-10
- Issue: #24
- Baseline branch: `dev`
- Baseline commit: `dc2bfc42feba20f92341b620876d88c5614d563e`
- Parent design: `docs/superpowers/specs/2026-09-10-benefit-business-verification-pipeline-design.md`
- Scope: Contract and module-boundary design only

## 1. Purpose

Phase 1 POI Verification Core is intentionally split into three independently developed workstreams:

1. Business Identity / Normalization
2. POI Discovery / Candidate Collection
3. POI Matching / Evaluation

This document freezes the shared data contracts and invariants that allow the three workstreams to be developed in parallel without waiting for neighboring implementations.

These contracts are not product database schemas, Android models, server API contracts, or canonical CSV schema changes. Phase 1 remains a PowerShell data-tooling Shadow Mode workflow.

## 2. Design constraints

- Current GitHub code and configuration override this document if they conflict.
- Phase 1 follows the repository's current PowerShell style: `[pscustomobject]`, arrays, and validation/helper functions.
- No new external library is approved by this document.
- No Room/server DB/schema change is approved.
- No API/auth contract change is approved.
- No canonical or Android seed automatic write is approved.
- GREEN means fast-review candidate, not production approval.
- Business identity, POI discovery, matching, and production application remain separate concerns.
- Original evidence must be preserved even when normalized values are derived.
- Missing or ambiguous values must not be invented.

## 3. Contract conventions

### 3.1 Contract identity

Every top-level contract object includes:

- `ContractType`: exact string identifying the contract
- `ContractVersion`: integer, initially `1`

A consumer must reject an unexpected `ContractType` or unsupported `ContractVersion` rather than silently reinterpret the object.

### 3.2 Strings, nulls, and arrays

For Phase 1 PowerShell contracts:

- Text fields use `''` when a value is absent or not safely determinable.
- Arrays are always present and use `@()` when empty.
- Numeric coordinate values may be `$null` when absent.
- Latitude and longitude must either both be present or both be absent.
- No consumer may convert an absent optional string into a guessed value.

### 3.3 Stable tracing

Every business-level top contract includes `SourceRowNumber`, referring to the canonical CSV row number using the header-offset convention already used by current verification tooling.

`SourceRowNumber` is a trace key, not a permanent business identity.

### 3.4 Codes over free text

Machine decisions use stable codes in addition to human-readable evidence. Workstreams must not invent new status, reason, warning, or conflict codes inside an implementation PR without an explicit contract change.

## 4. Contract: `NormalizedBusiness`

### 4.1 Producer and consumers

- Producer: Workstream A — Business Identity / Normalization
- Consumers: Workstream B — POI Discovery; Workstream C — Matching / Evaluation

### 4.2 Fields

| Field | Type | Required | Rule |
| --- | --- | --- | --- |
| `ContractType` | string | yes | exact `NormalizedBusiness` |
| `ContractVersion` | int | yes | `1` |
| `SourceRowNumber` | int | yes | canonical row trace, > 1 |
| `OriginalName` | string | yes | source business name, preserving source meaning |
| `NormalizedName` | string | yes | deterministic comparison representation; may be empty only if original name is unusable |
| `BaseName` | string | yes | safely identified base business name; otherwise `''` |
| `BranchName` | string | yes | explicit/safely parsed branch; otherwise `''` |
| `OriginalRoadAddress` | string | yes | source road address or `''` |
| `OriginalLotAddress` | string | yes | source lot address or `''` |
| `PreferredAddress` | string | yes | trimmed road address when available, otherwise trimmed lot address, otherwise `''` |
| `Province` | string | yes | safely normalized province-level component or `''` |
| `City` | string | yes | safely parsed city component or `''` |
| `District` | string | yes | safely parsed district/county component or `''` |
| `Dong` | string | yes | safely parsed dong/eup/myeon component or `''` |
| `RoadName` | string | yes | safely parsed road name or `''` |
| `BuildingMain` | string | yes | main building number or `''` |
| `BuildingSub` | string | yes | sub building number or `''` |
| `Floor` | string | yes | explicit material floor signal or `''` |
| `Unit` | string | yes | explicit material unit/ho signal or `''` |
| `AddressParseStatus` | string | yes | `COMPLETE`, `PARTIAL`, or `UNPARSED` |
| `NormalizationWarnings` | string[] | yes | warning codes; `@()` when none |

### 4.3 Required invariants

- `PreferredAddress` must be exactly one preserved source address after trimming; it is not a rewritten synthetic address.
- `OriginalName`, `OriginalRoadAddress`, and `OriginalLotAddress` preserve source meaning and are never replaced by normalized forms.
- `BuildingMain`, `BuildingSub`, `Floor`, `Unit`, and `BranchName` may only be filled from deterministic parsing of source text.
- If parsing is ambiguous, the derived field remains empty and an appropriate warning is added.
- `AddressParseStatus=COMPLETE` means structural parsing completed without unresolved material components; it does not prove the address is currently valid.

### 4.4 Initial warning codes

- `NAME_EMPTY`
- `NAME_NORMALIZATION_UNCERTAIN`
- `BRANCH_UNCERTAIN`
- `ADDRESS_EMPTY`
- `ADDRESS_PARSE_PARTIAL`
- `ADDRESS_PARSE_FAILED`
- `BUILDING_NUMBER_UNCERTAIN`
- `FLOOR_UNIT_UNCERTAIN`

Warnings are descriptive and do not by themselves decide GREEN/YELLOW/RED.

## 5. Supporting record: `PoiQueryAttempt`

Workstream B preserves every configured query outcome so consumers can distinguish successful zero-result discovery from incomplete discovery.

| Field | Type | Required | Rule |
| --- | --- | --- | --- |
| `StrategyCode` | string | yes | approved query-strategy code |
| `Query` | string | yes | submitted query for `SUCCESS`/`FAILED`; deterministically generated would-be query for `SKIPPED` |
| `QueryOrder` | int | yes | 1-based configured execution order |
| `Status` | string | yes | `SUCCESS`, `FAILED`, or `SKIPPED` |
| `ResultCount` | int | yes | >= 0; 0 for failed/skipped attempts |
| `ErrorCode` | string | yes | stable operational error code or `''` |

Initial strategy codes:

- `NAME_FULL_ADDRESS`
- `NAME_ROAD_BUILDING`
- `NAME_LOCALITY_ROAD`
- `BASE_NAME_BUILDING`
- `BASE_NAME_LOCALITY`

The exact subset executed may be narrowed by deterministic preconditions in Workstream B. Adding or changing strategy codes requires an explicit contract change.

## 6. Supporting record: `PoiDiscoveryEvidence`

Each deduplicated candidate preserves every successful query path that found it.

| Field | Type | Required | Rule |
| --- | --- | --- | --- |
| `StrategyCode` | string | yes | approved strategy code |
| `Query` | string | yes | exact submitted query |
| `QueryOrder` | int | yes | 1-based configured order |
| `ResultPosition` | int | yes | 1-based provider result position |
| `ResultCount` | int | yes | total results returned for that query |

## 7. Contract: `PoiCandidate`

### 7.1 Producer and consumer

- Producer: Workstream B
- Consumer: Workstream C

### 7.2 Fields

| Field | Type | Required | Rule |
| --- | --- | --- | --- |
| `ContractType` | string | yes | exact `PoiCandidate` |
| `ContractVersion` | int | yes | `1` |
| `CandidateKey` | string | yes | deterministic run-level dedup key |
| `Provider` | string | yes | Phase 1 exact `NAVER_API_HUB_LOCAL` |
| `OriginalName` | string | yes | provider-returned display name after provider markup removal only; source meaning retained |
| `NormalizedName` | string | yes | deterministic comparison representation of `OriginalName` |
| `RoadAddress` | string | yes | provider road address or `''` |
| `LotAddress` | string | yes | provider lot address or `''` |
| `Latitude` | double/null | yes | WGS84 or `$null` |
| `Longitude` | double/null | yes | WGS84 or `$null` |
| `Phone` | string | yes | provider value or `''` |
| `Category` | string | yes | provider value or `''` |
| `ProviderLink` | string | yes | provider-returned stable link when actually available, otherwise `''` |
| `DiscoveredBy` | PoiDiscoveryEvidence[] | yes | at least one successful discovery evidence record |

### 7.3 Candidate normalization boundary

Workstream B is responsible only for provider-side candidate preparation needed by the contract, including `NormalizedName` and provider coordinate conversion/validation. It must not reproduce Workstream A's canonical-address parser or infer canonical identity fields.

Workstream C compares the preserved candidate addresses against `NormalizedBusiness` using deterministic matching helpers owned by C unless a later shared helper is explicitly approved. This avoids making B depend on A's implementation while preserving raw candidate evidence for matching.

### 7.4 CandidateKey rule

`CandidateKey` is only for deterministic deduplication within one discovery run. It must not be treated as a durable business ID or stored as canonical identity without a later dedicated design.

Workstream B must document its deterministic key rule in its implementation Issue and tests. The rule should prefer provider-stable identifiers when actually available; otherwise it may derive a run-level key from normalized provider evidence. No durable identity may be invented.

### 7.5 Coordinate invariants

- Both coordinates present or both absent.
- When present, they must parse numerically and pass the repository's Korea coordinate-range safety check.
- Invalid provider coordinates must not be silently converted to zero or another fallback value.
- Address-geocoding coordinates are not interchangeable with a verified business POI coordinate unless source semantics explicitly support that use.

## 8. Contract: `PoiDiscoveryBatch`

### 8.1 Why this wrapper exists

`PoiCandidate[]` alone cannot distinguish:

- a complete search that legitimately returned no candidates, and
- a search that failed before sufficient queries were completed.

That distinction is safety-critical. A discovery failure must not be interpreted as business absence or a normal no-candidate result.

### 8.2 Fields

| Field | Type | Required | Rule |
| --- | --- | --- | --- |
| `ContractType` | string | yes | exact `PoiDiscoveryBatch` |
| `ContractVersion` | int | yes | `1` |
| `SourceRowNumber` | int | yes | must match input `NormalizedBusiness` |
| `Status` | string | yes | `COMPLETE`, `PARTIAL`, or `FAILED` |
| `Candidates` | PoiCandidate[] | yes | `@()` when none |
| `QueryAttempts` | PoiQueryAttempt[] | yes | one record per configured query strategy considered |

### 8.3 Status semantics

`COMPLETE`
- all required query strategies for that input were successfully completed or deterministically skipped;
- no unresolved provider error prevents normal evaluation.

`PARTIAL`
- at least one usable query completed, but one or more provider/operational failures prevented full configured discovery;
- collected candidates are retained, but matching must treat the batch as incomplete.

`FAILED`
- discovery did not complete enough successful execution to support a normal no-candidate interpretation;
- candidates may contain partial evidence, but matching must treat the batch as incomplete.

### 8.4 Stop condition

Workstream B must not stop merely because the first query returned a non-empty result.

It may stop early only when its implementation Issue defines a deterministic `reliable candidate condition` compatible with the parent design and this contract. Otherwise configured strategies are exhausted.

A deterministic early stop counts as COMPLETE only when remaining strategies are explicitly recorded as `SKIPPED` because the approved early-stop condition was satisfied. The evidence trail remains intact, and early stop is never production approval.

## 9. Contract: `PoiMatchResult`

### 9.1 Producer and consumer

- Producer: Workstream C
- Consumer: later Integration / Review Report layer

### 9.2 Fields

| Field | Type | Required | Rule |
| --- | --- | --- | --- |
| `ContractType` | string | yes | exact `PoiMatchResult` |
| `ContractVersion` | int | yes | `1` |
| `SourceRowNumber` | int | yes | matches input business/batch |
| `EvaluationStatus` | string | yes | `COMPLETE` or `INCOMPLETE` |
| `Classification` | string | yes | `GREEN`, `YELLOW`, or `RED` |
| `SelectedCandidate` | PoiCandidate/null | yes | constrained by classification invariants below |
| `RankedCandidateKeys` | string[] | yes | ranking order for evaluated candidates |
| `ReasonCodes` | string[] | yes | decision-support codes |
| `ConflictCodes` | string[] | yes | material conflict codes |
| `Evidence` | object[] | yes | human-review comparison facts |
| `EvaluatedCandidateCount` | int | yes | >= 0 |
| `SurvivingCandidateCount` | int | yes | >= 0 and <= evaluated count |
| `ProductionAction` | string | yes | Phase 1 exact `NONE` |

### 9.3 Evaluation and classification invariants

- `COMPLETE` requires a `COMPLETE` discovery batch and a completed matcher evaluation.
- `INCOMPLETE` is required when discovery is `PARTIAL`/`FAILED` or matching cannot safely finish.
- `INCOMPLETE` must use `Classification=YELLOW` in Phase 1.
- `GREEN` requires `EvaluationStatus=COMPLETE` and a non-null `SelectedCandidate`.
- `RED` requires `EvaluationStatus=COMPLETE` and `SelectedCandidate=$null`.
- `YELLOW` may have a non-null review candidate or `$null` depending on available evidence.
- `ProductionAction` is always `NONE` for all classifications.

These rules prevent API/search incompleteness from being converted into an apparently complete negative result.

## 10. GREEN / YELLOW / RED semantics

### 10.1 GREEN

GREEN means:

- a strong candidate exists;
- no material hard conflict remains;
- available identity evidence satisfies the matcher Issue's reviewed criteria;
- the candidate is suitable for fast human confirmation.

GREEN does not mean:

- canonical approved;
- Android seed approved;
- current military benefit verified;
- business closure/move state resolved;
- production write authorized.

### 10.2 YELLOW

YELLOW means detailed human review is required. Typical causes include:

- discovery is incomplete;
- multiple plausible candidates;
- evidence is insufficient for GREEN;
- non-material ambiguity remains;
- important identity evidence cannot be safely parsed or compared.

All `PARTIAL` and `FAILED` discovery paths resolve to `EvaluationStatus=INCOMPLETE`, `Classification=YELLOW` in Phase 1.

### 10.3 RED

RED means a complete POI discovery and matching evaluation cannot safely recommend a candidate as the same business because:

- material identity conflicts eliminate available candidates, or
- discovery completed successfully but no acceptable candidate was found.

RED does not mean:

- the business is closed;
- the business does not exist;
- the military benefit ended.

## 11. Initial conflict codes

Hard/material conflict codes for Phase 1:

- `PROVINCE_CONFLICT`
- `CITY_DISTRICT_CONFLICT`
- `BUILDING_NUMBER_CONFLICT`
- `BRANCH_CONFLICT`
- `FLOOR_UNIT_CONFLICT`
- `INVALID_COORDINATE_PAIR`

A matcher may report multiple conflicts for one candidate.

Name differences are not automatically a hard `NAME_CONFLICT`; naming variation is evaluated through ranking/reason logic unless a later reviewed rule establishes a deterministic material contradiction.

## 12. Initial reason codes

- `NAME_EXACT`
- `NAME_COMPATIBLE`
- `ADDRESS_EXACT`
- `LOCALITY_MATCH`
- `ROAD_NAME_MATCH`
- `BUILDING_NUMBER_MATCH`
- `BRANCH_MATCH`
- `FLOOR_UNIT_MATCH`
- `REPEATED_DISCOVERY`
- `SINGLE_STRONG_CANDIDATE`
- `MULTIPLE_PLAUSIBLE_CANDIDATES`
- `INSUFFICIENT_IDENTITY_EVIDENCE`
- `NO_CANDIDATE`
- `DISCOVERY_PARTIAL_FAILURE`
- `DISCOVERY_FAILED`

Reason codes are not scores. Workstream C may use deterministic ranking internally, but it must expose enough structured reason/conflict evidence for regression tests and human review.

## 13. Evidence records

`PoiMatchResult.Evidence` is an array of review facts. Phase 1 does not approve a persisted evidence schema; each in-memory/report record must have at least:

- `EvidenceCode`
- `CandidateKey` or `''` when business-level
- `CanonicalValue`
- `CandidateValue`
- `Matched`: boolean or `$null` when not applicable

Evidence is review/debug context and must not contain secrets.

## 14. Module ownership boundaries

### Workstream A — Identity / Normalization

Owns:
- canonical row → `NormalizedBusiness`
- deterministic canonical name/address parsing
- normalization warnings

Must not own:
- provider API search
- candidate ranking
- GREEN/YELLOW/RED classification
- canonical/seed writes

### Workstream B — POI Discovery

Owns:
- `NormalizedBusiness` → `PoiDiscoveryBatch`
- adaptive query generation
- provider transport/calls
- provider candidate preparation required by `PoiCandidate`
- candidate collection and deduplication
- query/candidate evidence

Must not own:
- production approval
- final identity classification
- canonical-address identity parsing
- canonical/seed writes

### Workstream C — Matching / Evaluation

Owns:
- `NormalizedBusiness + PoiDiscoveryBatch` → `PoiMatchResult`
- deterministic candidate-side comparison parsing needed for matching
- hard constraints
- candidate ranking
- classification
- Golden Dataset regression
- matcher metrics

Must not own:
- Naver API transport/search implementation
- canonical/seed production writes
- guessed thresholds or unverifiable identity data

## 15. Parallel-development rule

A, B, and C must be implementable against contract fixtures without waiting for other implementation branches.

Examples:

- B tests use fixture `NormalizedBusiness` objects rather than invoking A.
- C tests use fixture `NormalizedBusiness` and `PoiDiscoveryBatch` objects rather than invoking A/B.
- A tests do not import provider/discovery/matcher modules.

Shared contract code, once implemented, is read-only to the three workstreams unless a contract-change Issue is opened.

## 16. Planned Contract Foundation implementation boundary

After owner approval of this design, a separate implementation plan/Issue may create a small shared foundation, expected to be limited to a location such as:

```text
tools/data/lib/poi-verification-contracts.ps1
tools/data/test-poi-verification-contracts.ps1
```

Exact paths must be rechecked against latest `dev` before implementation.

The foundation may contain only:

- contract constructors
- contract validators
- allowed status/code constants or equivalent helpers
- required-property validation
- coordinate-pair validation

It must not contain:

- business normalization logic
- Naver API querying
- adaptive query strategy behavior
- matching/ranking logic
- Golden Dataset evaluation logic
- canonical/seed writes

## 17. Golden Dataset contract expectations

The matcher implementation must be able to express reviewed expectations for:

- positive: existing exact verified pins and P2/P3 approved cases
- ambiguous: P2/P3 held cases
- negative: P2/P3 rejected cases

Required safety regressions include at minimum:

- `버섯집 초리골`: building-number mismatch must not become GREEN
- `짜장마을`: insufficient reliable evidence must not become GREEN
- `이지현미용실`: canonical 26 vs POI 23 must not become GREEN
- `인헤어`: canonical 902·2동 104호 vs POI 904 must not become GREEN

`거시기닭갈비` remains a cautionary approved example because name/branch/address evidence aligned while a public phone-number suffix differed. Phone mismatch must not silently become a universal hard identity rule without calibration and review.

## 18. Shadow Mode safety invariants

The following are contract-level invariants for all Phase 1 workstreams and integration:

1. `ProductionAction` is always `NONE`.
2. No contract constructor or validator writes canonical data.
3. No contract constructor or validator writes Android seed data.
4. GREEN never bypasses human review.
5. Discovery failure is distinguishable from a completed no-candidate search.
6. `INCOMPLETE` evaluation is always YELLOW in Phase 1.
7. Failed search is never closure evidence.
8. POI evidence is never military-benefit evidence.
9. Missing branch/address/floor/unit values remain missing rather than inferred.
10. Hard conflicts are evaluated before ranking can promote a candidate.
11. Known ambiguous/rejected Golden Dataset cases must not silently become GREEN.

## 19. Compatibility with current repository

Current `verify-canonical-benefit-poi.ps1` already:

- uses PowerShell custom objects;
- exposes helper functions under `-LibraryOnly`;
- separates API errors from ordinary matching results;
- preserves canonical row numbers in reports;
- validates Korea coordinate range;
- currently stops POI querying at the first query returning candidates.

Phase 1 contracts preserve the compatible parts while enabling the planned change from:

> result exists → stop

to:

> reliable candidate condition reached, or configured strategies exhausted → stop

The existing script itself is not modified by this design Issue.

## 20. Contract-change rule

Once the Contract Foundation is merged to `dev`, A/B/C implementation Issues consume Contract version 1 as frozen input/output behavior.

Any change to:

- top-level field names/types;
- required/empty/null semantics;
- allowed status values;
- warning/reason/conflict code sets;
- classification invariants;
- provider identity semantics;

must be handled as an explicit contract change and reconciled across all affected workstreams. A single implementation PR must not silently redefine the shared contract.

## 21. Acceptance criteria

This contract design is ready for implementation planning when the project owner confirms that:

- the four core/supporting contracts and their responsibilities are acceptable;
- strings/arrays/null rules are acceptable;
- discovery COMPLETE/PARTIAL/FAILED semantics are acceptable;
- `INCOMPLETE → YELLOW` is acceptable for Phase 1;
- GREEN/YELLOW/RED selected-candidate invariants are acceptable;
- `ProductionAction=NONE` is required for Phase 1;
- A/B/C may develop only against the frozen contract and fixtures;
- shared Contract Foundation code will be implemented before the three parallel workstream Issues begin;
- later contract changes are explicit rather than silently introduced inside A/B/C.

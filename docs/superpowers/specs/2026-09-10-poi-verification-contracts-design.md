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

The purpose of this document is to freeze the shared data contracts and invariants that allow those three workstreams to be developed in parallel without waiting for neighboring implementations.

The contracts are not product database schemas, Android models, server API contracts, or canonical CSV schema changes. Phase 1 remains a PowerShell data-tooling Shadow Mode workflow.

## 2. Design constraints

- Current GitHub code and configuration override this document if they conflict.
- Phase 1 uses the repository's current PowerShell object-oriented-by-convention style: `[pscustomobject]`, arrays, and validation/helper functions.
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
- A latitude and longitude must either both be present or both be absent.
- No consumer may convert an absent optional string into a guessed value.

### 3.3 Stable tracing

Every business-level top contract includes `SourceRowNumber`, referring to the canonical CSV row number including the header offset convention already used by current verification tooling.

`SourceRowNumber` is a trace key, not a permanent business identity.

### 3.4 Codes over free text

Machine decisions use stable codes in addition to human-readable evidence. Workstreams must not invent new status, reason, warning, or conflict codes inside an implementation PR without updating this contract through an explicit contract change.

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
| `OriginalName` | string | yes | source business name, trimmed only for storage |
| `NormalizedName` | string | yes | deterministic comparison representation; may be empty only if original name is unusable |
| `BaseName` | string | yes | name with safely identified branch suffix removed; otherwise `''` |
| `BranchName` | string | yes | explicit/safely parsed branch; otherwise `''` |
| `OriginalRoadAddress` | string | yes | source road address or `''` |
| `OriginalLotAddress` | string | yes | source lot address or `''` |
| `PreferredAddress` | string | yes | road address when available, otherwise lot address, otherwise `''` |
| `Province` | string | yes | safely normalized province-level component or `''` |
| `City` | string | yes | safely parsed city component or `''` |
| `District` | string | yes | safely parsed district/county component or `''` |
| `Dong` | string | yes | safely parsed dong/eup/myeon component or `''` |
| `RoadName` | string | yes | safely parsed road name or `''` |
| `BuildingMain` | string | yes | main building number or `''` |
| `BuildingSub` | string | yes | sub building number or `''` |
| `Floor` | string | yes | explicit material floor signal or `''` |
| `Unit` | string | yes | explicit material unit/ho signal or `''` |
| `AddressParseStatus` | string | yes | one of `COMPLETE`, `PARTIAL`, `UNPARSED` |
| `NormalizationWarnings` | string[] | yes | warning codes; `@()` when none |

### 4.3 Required invariants

- `PreferredAddress` must be exactly one of the preserved source addresses after trimming; it is not a rewritten synthetic address.
- `OriginalName`, `OriginalRoadAddress`, and `OriginalLotAddress` preserve source meaning and are never replaced by normalized forms.
- `BuildingMain`, `BuildingSub`, `Floor`, `Unit`, and `BranchName` may only be filled from deterministic parsing of source text.
- If parsing is ambiguous, leave the derived field empty and add an appropriate warning.
- `AddressParseStatus=COMPLETE` does not mean the address is factually current; it means the available address was structurally parsed without unresolved material components.

### 4.4 Initial warning codes

- `NAME_EMPTY`
- `NAME_NORMALIZATION_UNCERTAIN`
- `BRANCH_UNCERTAIN`
- `ADDRESS_EMPTY`
- `ADDRESS_PARSE_PARTIAL`
- `ADDRESS_PARSE_FAILED`
- `BUILDING_NUMBER_UNCERTAIN`
- `FLOOR_UNIT_UNCERTAIN`

Warnings are descriptive; they do not by themselves decide GREEN/YELLOW/RED.

## 5. Supporting record: `PoiQueryAttempt`

Workstream B must preserve every attempted query so the matcher and reviewer can distinguish successful zero-result searches from incomplete discovery.

| Field | Type | Required | Rule |
| --- | --- | --- | --- |
| `StrategyCode` | string | yes | approved query-strategy code |
| `Query` | string | yes | exact submitted query |
| `QueryOrder` | int | yes | 1-based execution order |
| `Status` | string | yes | `SUCCESS`, `FAILED`, or `SKIPPED` |
| `ResultCount` | int | yes | >= 0; 0 for failed/skipped attempts |
| `ErrorCode` | string | yes | stable error code or `''` |

Initial strategy codes may include:

- `NAME_FULL_ADDRESS`
- `NAME_ROAD_BUILDING`
- `NAME_LOCALITY_ROAD`
- `BASE_NAME_BUILDING`
- `BASE_NAME_LOCALITY`

The exact set used by Workstream B may be narrowed by its Issue, but new codes require a contract update.

## 6. Supporting record: `PoiDiscoveryEvidence`

Each deduplicated candidate preserves all query paths that found it.

| Field | Type | Required |
| --- | --- | --- |
| `StrategyCode` | string | yes |
| `Query` | string | yes |
| `QueryOrder` | int | yes |
| `ResultPosition` | int | yes |
| `ResultCount` | int | yes |

`ResultPosition` is 1-based within the provider response.

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
| `Provider` | string | yes | Phase 1: `NAVER_API_HUB_LOCAL` |
| `OriginalName` | string | yes | provider-returned business name with markup removed only where required for safe comparison/reporting |
| `RoadAddress` | string | yes | provider road address or `''` |
| `LotAddress` | string | yes | provider lot address or `''` |
| `Latitude` | double/null | yes | WGS84 or `$null` |
| `Longitude` | double/null | yes | WGS84 or `$null` |
| `Phone` | string | yes | provider value or `''` |
| `Category` | string | yes | provider value or `''` |
| `ProviderLink` | string | yes | provider-returned stable link when actually available, otherwise `''` |
| `DiscoveredBy` | object[] | yes | one or more `PoiDiscoveryEvidence` records |

### 7.3 CandidateKey rule

`CandidateKey` is only for deterministic deduplication within one discovery run. It must not be treated as a durable business ID or stored as canonical identity without a later dedicated design.

Workstream B must document the deterministic key rule in its implementation Issue and tests. The rule should prefer provider-stable identifiers when actually available; otherwise it may derive a run-level key from normalized provider evidence. No invented durable identity is allowed.

### 7.4 Coordinate invariants

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
| `QueryAttempts` | PoiQueryAttempt[] | yes | attempted/skipped query trace |

### 8.3 Status semantics

`COMPLETE`
- all required query strategies for that input were either successfully completed or safely skipped by deterministic preconditions;
- no unresolved provider error prevents evaluation.

`PARTIAL`
- at least one usable query completed, but one or more query attempts failed or an operational error prevented full configured discovery;
- collected candidates are retained, but matching must account for incompleteness.

`FAILED`
- discovery did not produce enough successful execution to support a normal no-candidate interpretation;
- `Candidates` may be empty or may contain partial evidence, but C must treat evaluation as incomplete.

### 8.4 Stop condition

Workstream B must not stop merely because the first query returned a non-empty result.

It may stop early only when its Issue defines a deterministic `reliable candidate condition` that is compatible with this contract and the parent design. Otherwise configured query strategies are exhausted.

Any such early-stop rule must preserve the query attempt/evidence trail and is not itself a production approval.

## 9. Contract: `PoiMatchResult`

### 9.1 Producer and consumers

- Producer: Workstream C
- Consumer: later Integration/Review Report layer

### 9.2 Fields

| Field | Type | Required | Rule |
| --- | --- | --- | --- |
| `ContractType` | string | yes | exact `PoiMatchResult` |
| `ContractVersion` | int | yes | `1` |
| `SourceRowNumber` | int | yes | matches input business/batch |
| `EvaluationStatus` | string | yes | `COMPLETE` or `INCOMPLETE` |
| `Classification` | string | yes | `GREEN`, `YELLOW`, or `RED` |
| `SelectedCandidate` | PoiCandidate/null | yes | best review candidate when applicable |
| `RankedCandidateKeys` | string[] | yes | ranking order for evaluated candidates |
| `ReasonCodes` | string[] | yes | decision-support codes |
| `ConflictCodes` | string[] | yes | material conflict codes |
| `Evidence` | object[] | yes | human-review comparison facts |
| `EvaluatedCandidateCount` | int | yes | >= 0 |
| `SurvivingCandidateCount` | int | yes | >= 0 and <= evaluated count |
| `ProductionAction` | string | yes | Phase 1 exact `NONE` |

### 9.3 Evaluation status rule

- `COMPLETE`: matcher received a `COMPLETE` discovery batch and completed its configured evaluation.
- `INCOMPLETE`: discovery was `PARTIAL`/`FAILED` or matcher itself could not complete safely.

`INCOMPLETE` must never be silently represented as a normal complete negative result.

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

Every GREEN must have `ProductionAction=NONE` in Phase 1.

### 10.2 YELLOW

YELLOW means detailed human review is required. Typical causes include:

- discovery is incomplete;
- multiple plausible candidates;
- evidence is insufficient for GREEN;
- non-material ambiguity remains;
- a candidate exists but important identity evidence cannot be safely parsed or compared.

A `PARTIAL` or `FAILED` discovery batch must produce `EvaluationStatus=INCOMPLETE` and must not produce a normal RED solely because no usable candidate remains.

### 10.3 RED

RED means the completed available POI evaluation cannot safely recommend the candidate as the same business, for example because:

- a material identity conflict exists, or
- discovery completed successfully but no acceptable candidate was found.

RED does not mean:

- the business is closed;
- the business does not exist;
- the military benefit ended.

## 11. Initial conflict codes

The following are hard/material conflict codes for Phase 1:

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

`PoiMatchResult.Evidence` is an array of review facts. Phase 1 does not require a persisted evidence schema; however each record must have at least:

- `EvidenceCode`
- `CandidateKey` or `''` when business-level
- `CanonicalValue`
- `CandidateValue`
- `Matched`: boolean or `$null` when not applicable

Evidence values are report/debug context and must not contain secrets.

## 14. Module ownership boundaries

### Workstream A — Identity / Normalization

Owns:
- canonical-row to `NormalizedBusiness`
- deterministic name/address parsing
- normalization warnings

Must not own:
- provider API search
- candidate ranking
- GREEN/YELLOW/RED classification
- canonical/seed writes

### Workstream B — POI Discovery

Owns:
- `NormalizedBusiness` to `PoiDiscoveryBatch`
- adaptive query generation
- provider calls
- candidate collection
- candidate deduplication
- query/candidate evidence

Must not own:
- production approval
- final identity classification
- canonical/seed writes

### Workstream C — Matching / Evaluation

Owns:
- `NormalizedBusiness + PoiDiscoveryBatch` to `PoiMatchResult`
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

A, B, and C must be implementable against contract fixtures without waiting for the other implementation branches.

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

`거시기닭갈비` remains a cautionary approved example because name/branch/address evidence aligned while a public phone-number suffix differed. Phone mismatch must not silently become a hard universal identity rule without calibration and review.

## 18. Shadow Mode safety invariants

The following are contract-level invariants for all Phase 1 workstreams and integration:

1. `ProductionAction` is always `NONE`.
2. No contract constructor or validator writes canonical data.
3. No contract constructor or validator writes Android seed data.
4. GREEN never bypasses human review.
5. Discovery failure is distinguishable from a completed no-candidate search.
6. Failed search is never closure evidence.
7. POI evidence is never military-benefit evidence.
8. Missing branch/address/floor/unit values remain missing rather than inferred.
9. Hard conflicts are evaluated before similarity/ranking can promote a candidate.
10. Known ambiguous/rejected Golden Dataset cases must not silently become GREEN.

## 19. Compatibility with current repository

Current `verify-canonical-benefit-poi.ps1` already:

- uses PowerShell custom objects;
- exposes helper functions under `-LibraryOnly`;
- separates API errors from ordinary matching results;
- preserves canonical row numbers in reports;
- validates Korea coordinate range;
- currently stops POI querying at the first query returning candidates.

Phase 1 contracts deliberately preserve the compatible parts while enabling the planned change from:

> result exists -> stop

to:

> reliable candidate condition reached, or configured strategies exhausted -> stop

The existing script itself is not modified by this design Issue.

## 20. Acceptance criteria

This contract design is ready for implementation planning when the project owner confirms that:

- the four top-level/supporting contracts and their responsibilities are acceptable;
- strings/arrays/null rules are acceptable;
- discovery COMPLETE/PARTIAL/FAILED semantics are acceptable;
- GREEN/YELLOW/RED semantics are acceptable;
- `ProductionAction=NONE` is required for Phase 1;
- A/B/C may develop only against the frozen contract and fixtures;
- shared contract code will be implemented before the three parallel workstream Issues begin;
- any later contract change is explicit rather than silently introduced inside A/B/C.

# Benefit Business Verification Pipeline Design

- Status: Approved direction / implementation pending
- Date: 2026-09-10
- Original design Issue: #19
- Reconciled after P3 merge
- Current baseline branch: `dev`
- P3 merge baseline: `edca54d23981501efa8ce602df98f5456973940c`
- Scope type: Data verification architecture / design only

## 1. Problem

MILIMAP has useful but separate flows for official military-benefit evidence and POI/coordinate validation. The current process still requires substantial manual work to discover POI candidates, compare addresses and branches, verify coordinates, and separately re-check whether a military benefit is still valid.

This does not scale for a service that must continuously maintain the current state of military-benefit businesses as businesses appear, move, close, start benefits, change benefits, or discontinue benefits.

The goal is not a one-time coordinate enrichment script. The goal is a reusable verification pipeline that can later support periodic and eventually near-event-driven monitoring without weakening approval standards.

## 2. Product-level goal

MiliSpot should maintain a trustworthy current view of:

> Businesses that currently exist and currently provide a military benefit, together with their verified current location, benefit details, explicit validity period when known, evidence source, and verification state.

The competitive capability is the ability to discover, verify, and track changes, not merely the number of rows stored.

## 3. Core principles

1. **Business identity, location, and military benefit are separate concerns.**
   - A business can remain the same while moving.
   - A business can remain open while its benefit changes or ends.
   - A valid benefit source does not prove that the current POI is correct.
   - A valid POI does not prove that a military benefit still exists.

2. **Evidence is first-class.**
   - No benefit, location, validity date, closure, or move is invented from inference alone.
   - Each accepted data change preserves source, verification date, and status.

3. **Discovery is broader than approval.**
   - Government and municipality sources may provide strong official evidence.
   - A business-owned official website/SNS/blog may provide direct evidence.
   - Personal blogs, communities, unverified social posts, and user submissions are discovery signals only until stronger evidence is found.

4. **Human approval remains in the loop initially.**
   - Search, candidate collection, comparison, change detection, and triage should be automated.
   - Humans should approve or reject prepared evidence instead of searching from scratch.

5. **Fail closed.**
   - Uncertain candidates remain unapproved.
   - Search failure is not proof of closure.
   - Similar name is not proof of identity.
   - Address-geocoding coordinates are not automatically equivalent to a verified business POI.

6. **Increase throughput without lowering approval criteria.**

## 4. Conceptual model

```text
Business Identity
│
├─ Location Observation
│  ├─ POI identity
│  ├─ road / lot address
│  ├─ coordinate
│  ├─ observedAt
│  └─ evidence
│
├─ Military Benefit Observation
│  ├─ benefit description
│  ├─ eligible target
│  ├─ usage conditions
│  ├─ verification method
│  ├─ validFrom
│  ├─ validUntil
│  ├─ observedAt
│  └─ evidence
│
└─ Current State
   ├─ location state
   ├─ benefit state
   ├─ last verified evidence
   └─ release eligibility
```

This is a conceptual model only. It does not approve a Room, server DB, API, or canonical schema change. Persistent schema design requires a separate Issue/ADR and user approval.

## 5. Location state model

The location subsystem should support review candidates for states such as:

- `ACTIVE_LOCATION`
- `MOVE_SUSPECTED`
- `MOVED`
- `CLOSURE_SUSPECTED`
- `CLOSED`
- `LOCATION_UNKNOWN`

One failed map/API search must never be sufficient to set `CLOSED`.

## 6. Military benefit state model

The benefit subsystem should support review logic for states such as:

- `DISCOVERED`
- `VERIFICATION_REQUIRED`
- `ACTIVE`
- `CHANGED`
- `EXPIRED`
- `DISCONTINUED`
- `UNKNOWN`

No item moves to `ACTIVE` without evidence satisfying the applicable source/verification policy.

## 7. Benefit validity and review time

The pipeline must distinguish actual benefit validity from internal re-verification scheduling.

- `validFrom`: actual start date only when supported by the source
- `validUntil`: actual end date only when supported by the source
- `observedAt`: when evidence was observed
- `lastVerifiedAt`: when evidence was last verified
- `nextReviewAt`: internal operational re-check time, not a user-visible expiration date

If a source has no end date, `validUntil` remains unknown. `nextReviewAt` must never be presented as the benefit end date.

## 8. Source hierarchy and exposure policy

### 8.1 Strong evidence candidates

- Government / municipality / public institution
- Official business website
- Official business SNS account
- Official business blog or directly controlled business page

These can become release evidence only after business identity, content meaning, date/context, and current applicability are verified.

### 8.2 Discovery-only sources

- Personal blog posts
- General community posts
- Unverified social posts
- User submissions

These are internal discovery signals. They must not be shown to users as verified military-benefit evidence without stronger confirmation.

## 9. Target pipeline

```text
                 SOURCE LAYER
                       │
   Government | Business Web/SNS | Discovery Signals
                       ↓
                 Source Adapter
                       ↓
                 Normalization
                       ↓
                 Business Identity
                Entity Resolution
                       │
             ┌─────────┴─────────┐
             ▼                   ▼
      Location Verification   Benefit Verification
             │                   │
             └─────────┬─────────┘
                       ▼
                 Change Detection
                       ↓
                Risk Classification
                 GREEN/YELLOW/RED
                       ↓
                   Review Queue
                       ↓
                 Human Approval
                       ↓
                  Current State
                       ↓
                    Canonical
                       ↓
               Release Candidate
                       ↓
                  Android Seed
```

## 10. Phase 1 — POI Verification Core / Shadow Mode

### 10.1 Scope

- reusable business-name normalization
- reusable address normalization
- structured address parsing where safely deterministic
- branch/floor/unit signals when materially identifying
- adaptive POI query generation
- multi-query candidate collection
- candidate deduplication
- hard-constraint filtering
- deterministic entity matching
- candidate ranking
- GREEN / YELLOW / RED classification with explicit reasons
- review queue output
- Golden Dataset regression tests
- metrics comparing automated behavior with existing manual ground truth

### 10.2 Shadow Mode restrictions

Phase 1 must not:

- modify canonical automatically
- modify Android seed automatically
- auto-approve GREEN results
- change Room/server schema
- change API contracts
- add a new external dependency without separate approval

GREEN means “strong fast-review candidate,” not “automatically approved production data.”

## 11. Phase 1 matching design

### 11.1 Normalization

Preserve original values while deriving comparison-safe values such as:

- normalized business name
- base business name
- explicit branch name
- province / city / district
- road name
- main/sub building number
- dong when safely determinable
- floor / unit when materially identifying

### 11.2 Adaptive query generation

Queries progress from strict to broader forms. The system must not stop merely because the first query returned any result.

Conceptual order:

1. business name + full canonical address
2. business name + road + building number
3. business name + district/dong + road
4. normalized/base business name + building number
5. normalized/base business name + local area

The algorithm stops only when a sufficiently strong candidate condition is met or configured strategies are exhausted.

### 11.3 Candidate aggregation

Use deterministic structures such as:

- `HashSet<Query>` to avoid duplicate queries
- `Dictionary<Query, SearchResult[]>` for run-level result reuse
- `Dictionary<PoiKey, PoiCandidate>` to merge the same POI found through multiple queries

Candidate evidence retains which queries found the POI, returned names/addresses, coordinates, and traceable source identifiers/URLs when available.

### 11.4 Hard constraints before ranking

Similarity must not override material identity conflicts.

Strong conflict examples:

- road/building-number contradiction
- clearly different branch
- incompatible city/district
- materially contradictory floor/unit where identifying
- known different business at the candidate address

Hard conflict must be evaluated before fuzzy/name ranking.

### 11.5 Ranking signals

Only candidates surviving hard constraints may use signals such as:

- exact normalized name
- name containment/extension
- branch compatibility
- address component agreement
- repeated discovery across query variants
- optional string similarity for ranking only
- optional coordinate proximity as secondary evidence

Distance thresholds must not be invented. If used, calibrate them from verified historical data and report the observed distribution.

## 12. Golden Dataset and regression safety

P1/P2/P3 manual decisions are now reusable ground truth.

Current P3 merged baseline:

- release candidates: 249
- exact map pins: 111
- coordinate-unconfirmed: 138
- bundled seed version: 7

P2/P3 unresolved breakdown:

- already reviewed but coordinate-unconfirmed hold/reject: 23
- remaining newly prioritized coordinate-unconfirmed group: 115

Expected Golden Dataset groups:

- positive: existing exact verified pins and approved P2/P3 cases
- ambiguous: held/review-required P2/P3 cases
- negative: rejected/mismatched cases

Known regression cases that must not silently become GREEN:

- `버섯집 초리골`: building-number mismatch
- `짜장마을`: reliable evidence insufficient
- `이지현미용실`: canonical building 26 vs POI 23
- `인헤어`: canonical 902·2동 104호 vs POI 904

`거시기닭갈비` is an approved location case with an auxiliary phone-number discrepancy and should be preserved as a cautionary positive rather than treated as a perfect identity fixture.

Primary safety gate:

> A known ambiguous or rejected case must not silently become GREEN without an explicit reviewed reason and test expectation change.

Metrics should include, where measurable without guessing:

- candidate recall on known positives
- GREEN precision on labeled data
- false-GREEN count
- manual deep-review rate
- no-candidate rate
- average API calls per row

## 13. Change detection design

The long-term pipeline should compare observations instead of treating every row as new.

Conceptual fingerprints may include:

- location fingerprint: normalized POI identity/address/coordinate evidence
- benefit fingerprint: benefit description/target/conditions/verification method
- evidence fingerprint: source identity/content version or stable source marker

Fingerprints are optimization aids, not truth. Changed fingerprints create review candidates; unchanged fingerprints may permit expensive downstream work to be skipped when policy allows.

## 14. Future phases

### Phase 2 — Benefit Verification Core

- normalize benefit text and target/condition fields
- track explicit validity periods
- detect material benefit changes
- produce benefit review queues
- build benefit Golden Dataset

### Phase 3 — Snapshot / Incremental Change Detection

- persist audit snapshots outside product DB initially
- compare previous/current observations
- skip unchanged work where safe
- surface new, changed, moved, closure-suspected, expired, and discontinued candidates

### Phase 4 — Multi-source adapters

- government/municipality adapters
- business website adapter
- business-owned SNS/blog adapters where lawful and operationally feasible
- submission/discovery-signal adapters

Each source requires its own terms/API/licensing/republication review before production use.

### Phase 5 — Periodic execution

- scheduled pipeline runs
- re-check according to evidence age/risk/operational policy
- produce review queues without weakening approval standards

### Phase 6 — Web/SNS discovery expansion

- detect new public benefit signals
- deduplicate already-seen content using stable IDs/hashes where possible
- route only relevant new/changed material to expensive parsing or AI-assisted extraction

### Phase 7 — Near-event-driven monitoring

Long-term target only. External change feeds, APIs, webhooks, polling, or other detectors may trigger the existing verification pipeline incrementally. This phase must reuse the same verification core instead of introducing a separate approval path.

## 15. Human review policy

The purpose of automation is to remove manual discovery/comparison work, not accountability.

- GREEN: strong candidate; fast human confirmation in early phases
- YELLOW: ambiguous; detailed manual verification required
- RED: material conflict or insufficient evidence; hold/reject unless new evidence appears

Classification must always expose supporting evidence and reason.

## 16. Repository integration boundary

Phase 1 should primarily remain under `tools/data/**` and related data test/report paths.

Exact implementation filenames are not approved by this design. They must be determined from the latest `dev` and the implementation Issues immediately before work starts.

The three planned parallel Workstreams are:

- A: Business Identity / Normalization
- B: POI Discovery / Candidate Collection
- C: Matching / Evaluation

They must use contract-first development and separate file ownership. Shared orchestration is connected later by a single Integration Owner.

## 17. Explicit non-goals

- production DB redesign
- Room migration
- server database decision
- authentication change
- API contract change
- new Android UI
- automatic production data approval
- SNS crawler implementation
- real-time monitoring implementation
- inferred benefit values or inferred expiry dates

## 18. Risks

1. false identity match
2. false closure inference
3. stale benefit evidence
4. source volatility
5. terms/licensing limitations
6. automation bias toward GREEN
7. Golden Dataset regional/source bias
8. pressure to smuggle persistent schema changes into Phase 1

## 19. Validation strategy

For Phase 1 implementation:

- regression tests against manually labeled P1/P2/P3 cases
- existing repository data validation tests
- explicit false-GREEN / recall / review-rate metrics
- relevant PowerShell script tests
- no canonical/seed diff in Shadow Mode
- Android tests only when Android product files or release-seed behavior actually change
- report both tests run and tests not run

## 20. Implementation sequencing

1. P3 campaign completed and merged to `dev`.
2. Reconcile and merge this design plus current collaboration/status docs.
3. Before implementation, inspect latest `dev` and freeze the Phase 1 contracts.
4. Create three purpose-level implementation Issues for Workstreams A/B/C.
5. Three developers branch independently from the same current `dev` baseline.
6. Merge independently testable module PRs.
7. Use one Integration Owner to connect shared orchestration on latest `dev`.
8. Run Phase 1 Shadow Mode against combined P1/P2/P3 ground truth.
9. Evaluate matcher safety and workload reduction before any production auto-application policy.
10. Only then open a separate Issue for production application rules or subsequent Benefit Verification phases.

## 21. Acceptance criteria

This design is the approved implementation direction when all of the following remain true:

- the tracked object is the current state of a military-benefit business, not merely a coordinate
- location and benefit are independently verified
- unofficial community/blog/user content is discovery-only until stronger evidence exists
- explicit benefit validity dates and internal review dates are distinct
- human approval remains in early pipeline phases
- Phase 1 is Shadow Mode and does not auto-write canonical/seed
- the architecture supports periodic, incremental, and eventual near-event-driven monitoring without replacing the verification core

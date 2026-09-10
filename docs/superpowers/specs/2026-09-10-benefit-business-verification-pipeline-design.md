# Benefit Business Verification Pipeline Design

- Status: Proposed for review
- Date: 2026-09-10
- Issue: #19
- Baseline branch: `dev`
- Baseline commit at design start: `881dd13bd83132497d7c6d5af118c342cd8e335f`
- Scope type: Data verification architecture / design only

## 1. Problem

MILIMAP currently has useful but separate verification flows for official military-benefit evidence and POI/coordinate validation. The current process still requires substantial manual work to discover POI candidates, compare addresses and branches, verify coordinates, and separately re-check whether a military benefit is still valid.

This does not scale well for a service that must continuously maintain the current state of military-benefit businesses as businesses appear, move, close, start benefits, change benefits, or discontinue benefits.

The design goal is therefore not to build a one-time coordinate enrichment script. It is to establish a reusable verification pipeline that can later support periodic and eventually near-event-driven monitoring without weakening data approval standards.

## 2. Product-level goal

MiliSpot should maintain a trustworthy current view of:

> Businesses that currently exist and currently provide a military benefit, together with their verified current location, benefit details, validity period when explicitly known, evidence source, and verification state.

The long-term competitive capability is not only the number of businesses stored. It is the ability to discover and verify changes and keep the data current.

## 3. Core design principles

1. **Business identity, location, and military benefit are separate concerns.**
   - A business can remain the same while moving.
   - A business can remain open while its benefit changes or ends.
   - A valid benefit source does not prove that the current POI is correct.
   - A valid POI does not prove that a military benefit still exists.

2. **Evidence is first-class.**
   - No benefit, location, validity date, closure, or move is invented from inference alone.
   - Each accepted data change must preserve source, verification date, and status.

3. **Discovery is broader than approval.**
   - Government and municipality sources may provide strong official evidence.
   - A business's own official website/SNS/blog may provide direct business evidence.
   - Personal blogs, communities, and user submissions are discovery signals only until stronger evidence is found.

4. **Human approval remains in the loop initially.**
   - The system should automate search, candidate collection, comparison, change detection, and triage.
   - Humans should primarily approve or reject prepared evidence rather than search from scratch.

5. **Fail closed.**
   - Uncertain candidates remain unapproved.
   - A search failure is not proof of closure.
   - A similar name is not proof of identity.
   - Address-geocoding coordinates are not automatically equivalent to business POI coordinates.

6. **Throughput may increase; approval criteria must not be weakened.**

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

This is a conceptual model only. It does **not** approve a Room, server DB, API, or canonical schema change. Persistent schema design requires a separate Issue/ADR.

## 5. Location state model

The location subsystem should be able to represent or infer review candidates for states such as:

- `ACTIVE_LOCATION`: current location is verified.
- `MOVE_SUSPECTED`: evidence suggests the same business may have moved.
- `MOVED`: a move has been explicitly verified and approved.
- `CLOSURE_SUSPECTED`: the business may no longer operate at the known location.
- `CLOSED`: closure has explicit sufficient evidence.
- `LOCATION_UNKNOWN`: current location cannot be safely verified.

One failed map/API search must never be sufficient to set `CLOSED`.

## 6. Military benefit state model

The benefit subsystem should support review logic for states such as:

- `DISCOVERED`: a potential military benefit signal was found.
- `VERIFICATION_REQUIRED`: evidence is insufficient for release.
- `ACTIVE`: current military-benefit evidence is verified.
- `CHANGED`: the benefit differs materially from the previously verified state.
- `EXPIRED`: a source-explicit validity period has passed.
- `DISCONTINUED`: sufficient evidence confirms the benefit ended.
- `UNKNOWN`: current validity cannot be safely determined.

No item moves to `ACTIVE` without evidence that satisfies the applicable source/verification policy.

## 7. Benefit validity and review time

The pipeline must distinguish user-visible benefit validity from internal re-verification scheduling.

- `validFrom`: actual benefit start date only when supported by the source.
- `validUntil`: actual benefit end date only when supported by the source.
- `observedAt`: when MiliSpot observed the evidence.
- `lastVerifiedAt`: when the evidence was last verified.
- `nextReviewAt`: an internal operational re-check time, not a user-visible benefit expiration date.

If a source says only “military personnel receive 10% discount” with no end date, `validUntil` must remain unknown. The system may still schedule a future `nextReviewAt` internally.

## 8. Source hierarchy and exposure policy

### 8.1 Strong evidence sources

- Government / municipality / public institution source
- Official business website
- Official business SNS account
- Official business blog or directly controlled business page

These can become release evidence only after business identity, content meaning, date/context, and current applicability are verified.

### 8.2 Discovery-only sources

- Personal blog posts
- General community posts
- Unverified social posts
- User submissions

These must not be exposed directly to end users as verified military-benefit evidence. They create an internal discovery candidate that triggers a search for stronger current evidence.

## 9. Target pipeline architecture

```text
                 SOURCE LAYER
                       │
   ┌───────────┬───────┼──────────┐
   │           │       │          │
Government   Business  Web/SNS   Submission
Municipality Website   /Blog     /Community
   │           │       │          │
   └───────────┴───────┴──────────┘
                       ↓
                 Source Adapter
                       ↓
                 Normalization
                       ↓
                 Store Identity
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

## 10. Phase 1: POI Verification Core in Shadow Mode

The first implementation must remain intentionally narrow.

### 10.1 Scope

- Reusable business-name and address normalization
- Structured address parsing where safely deterministic
- Adaptive POI query generation
- Multiple-query candidate collection
- Candidate deduplication
- Hard-constraint filtering
- Deterministic entity matching
- Candidate ranking
- GREEN / YELLOW / RED classification with explicit reasons
- Review queue output
- Golden Dataset regression tests using existing manually reviewed POI cases
- Metrics comparing current and v2 behavior

### 10.2 Shadow Mode restrictions

Phase 1 must not:

- modify canonical data automatically
- modify Android seed automatically
- auto-approve GREEN results
- change Room/server schema
- change API contracts
- add a new external dependency unless separately approved

A GREEN result means “strong fast-review candidate,” not “automatically approved production data.”

## 11. Phase 1 matching design

### 11.1 Normalization

Normalize while preserving original values. Candidate comparison may use:

- normalized business name
- province / city / district
- road name
- main/sub building number
- dong
- floor / unit when materially identifying
- branch name when explicit

### 11.2 Adaptive query generation

Queries should progress from strict to broader forms rather than stopping at the first non-empty result.

Conceptual order:

1. business name + full canonical address
2. business name + road + building number
3. business name + district/dong + road
4. normalized/base business name + building number
5. normalized/base business name + local area

The algorithm stops only when a sufficiently strong candidate condition is met or the configured query strategies are exhausted.

### 11.3 Candidate aggregation

Use deterministic in-memory structures such as:

- `HashSet<Query>` to avoid duplicate queries
- `Dictionary<Query, SearchResult[]>` for run-level result reuse
- `Dictionary<PoiKey, PoiCandidate>` to merge the same POI found through multiple queries

Candidate evidence should retain which queries found the POI, result metadata, returned names/addresses, and coordinates.

### 11.4 Hard constraints before similarity ranking

Similarity must not override material identity conflicts.

Examples of strong conflict signals:

- road/building-number contradiction
- clearly different branch
- incompatible city/district
- materially contradictory floor/unit where it identifies a different business
- known different business at the candidate address

Known regression cases such as `버섯집 초리골` must remain non-GREEN when a building-number mismatch exists. Cases such as `짜장마을` must remain non-GREEN when reliable evidence is insufficient.

### 11.5 Ranking signals

Only candidates that survive hard constraints may use ranking signals such as:

- exact normalized name
- name containment/extension
- branch compatibility
- address component agreement
- repeated discovery across query variants
- optional string similarity (for ranking only)
- optional coordinate proximity as secondary evidence

Distance thresholds must not be invented. If proximity is used, calibrate it from verified historical data and report the observed distribution.

## 12. Golden Dataset and regression safety

Existing manually reviewed results should become a reusable regression set.

Expected groups:

- positive: existing exact verified pins, approved P1/P2/P3 cases
- ambiguous: held/review-required P2/P3 cases
- negative: rejected/mismatched cases

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

The long-term pipeline should compare observations rather than repeatedly treating every row as new.

Conceptual fingerprints may be derived from normalized evidence, for example:

- location fingerprint: normalized POI identity/address/coordinate evidence
- benefit fingerprint: benefit description/target/conditions/verification method
- evidence fingerprint: source identity/content version or stable source markers

Fingerprints are optimization aids, not truth by themselves. A changed fingerprint creates a review candidate; an unchanged fingerprint may allow expensive downstream work to be skipped when policy permits.

## 14. Future phases

### Phase 2 — Benefit Verification Core

- Normalize benefit text and applicable target/condition fields
- Track explicit validity periods
- Detect material benefit changes
- Produce benefit review queues
- Build benefit Golden Dataset

### Phase 3 — Snapshot / Incremental Change Detection

- Persist audit snapshots outside product DB initially
- Compare previous and current observations
- Skip unchanged work where safe
- Surface new, changed, moved, closure-suspected, expired, and discontinued candidates

### Phase 4 — Multi-source adapters

- Government/municipality source adapters
- Business website adapter
- Business-owned SNS/blog adapters where lawful and operationally feasible
- Submission/discovery-signal adapters

Each source requires its own terms/API/licensing/republication review before production use.

### Phase 5 — Periodic execution

- Scheduled pipeline runs
- Re-check according to evidence age/risk/operational policy
- Produce review queues without weakening approval standards

### Phase 6 — Web/SNS discovery expansion

- Detect new public benefit signals
- Deduplicate already-seen content using stable IDs/hashes where possible
- Route only relevant new/changed material to expensive parsing or AI-assisted extraction

### Phase 7 — Near-event-driven monitoring

Long-term target only. External change feeds, APIs, webhooks, polling, or other detectors may trigger the existing verification pipeline incrementally. This phase must reuse the same verification core instead of introducing a separate approval path.

## 15. Human review policy

The purpose of automation is to remove manual discovery and comparison work, not remove accountability.

- GREEN: strong candidate; fast human confirmation in early phases
- YELLOW: ambiguous; detailed manual verification required
- RED: material conflict or insufficient evidence; hold/reject unless new evidence appears

No classification should hide the supporting evidence or reason.

## 16. Integration with current repository

The first implementation should primarily remain under `tools/data` and related data test/report paths.

Likely logical components, subject to implementation-time inspection:

```text
tools/data/
  poi-matcher-core.ps1        # normalization / query / matching rules
  verify-canonical-benefit-poi.ps1  # orchestration / API / report
  ...tests or fixtures...

data/.../reports/            # generated review/audit outputs as policy allows
```

Exact file names and locations are not approved by this document and must be confirmed against the latest `dev` and active Issue before implementation.

## 17. Explicit non-goals of this design Issue

- no production DB redesign
- no Room migration
- no server database decision
- no authentication change
- no API contract change
- no new Android UI
- no automatic production data approval
- no SNS crawler implementation
- no real-time monitoring implementation
- no inferred benefit values or inferred expiry dates

## 18. Risks

1. **False identity match** — similar business names or branches can produce unsafe coordinates.
2. **False closure inference** — temporary search/API absence can look like closure.
3. **Stale benefit evidence** — official lists themselves may lag reality.
4. **Source volatility** — websites/SNS content can move or disappear.
5. **Terms/licensing** — collection and redistribution rights vary by source.
6. **Automation bias** — reviewers may trust GREEN classifications too easily.
7. **Historical-data bias** — Golden Dataset may overrepresent current regions/source types.
8. **Schema pressure** — observation history may eventually require persistent modeling; this must not be smuggled into Phase 1.

## 19. Validation strategy

For the design itself:

- verify consistency with `AGENTS.md`
- verify consistency with `docs/data-policy.md`
- keep current GitHub code/config as the source of truth over stale documents
- ensure no Phase 1 requirement requires an unapproved schema/API/dependency change

For Phase 1 implementation later:

- regression tests against manually labeled cases
- data validation tests already used by the repository
- explicit metrics for false GREEN / recall / review-rate reduction
- full relevant script tests
- Android tests only if Android product files or release-seed behavior are changed
- report tests actually run and tests not run

## 20. Implementation sequencing rule

Work is divided by purpose-level Issue/PR, with commits used as checkpoints.

Recommended order:

1. Finish the current P3 campaign without expanding its scope.
2. Rebase/reconcile this design against the new `dev` baseline after P3 merge.
3. Implement Phase 1 POI Verification Core in Shadow Mode.
4. Evaluate matcher safety and workload reduction against the combined P1/P2/P3 ground truth.
5. Only after evidence supports it, open a separate Issue for production application rules.
6. Implement Benefit Verification Core and temporal validity in a later purpose-level Issue.
7. Add snapshot/change detection and source adapters incrementally.

## 21. Acceptance criteria for this design

This design is considered approved when the project owner confirms that:

- the system's primary tracked object is a military-benefit business current state, not just a coordinate
- location and benefit are independently verified
- unofficial community/blog/user content is discovery-only until stronger evidence exists
- explicit benefit validity dates and internal review dates are distinct
- human approval remains in early pipeline phases
- Phase 1 is Shadow Mode and does not auto-write canonical/seed
- long-term architecture supports periodic, incremental, and eventually near-event-driven monitoring without replacing the verification core


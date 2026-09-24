# Phase 2 Adapter Architecture Design

- Status: Approved — written spec reviewed by user; A1.1 merged; A1.2 is the next delivery
- Date: 2026-09-24
- Repository baseline: `dev@1244df177888748173d352e735ab4882736e185c`
- Scope type: Architectural / source-adapter and evidence-location extension
- Implementation checkpoint: A1.1 merged via PR #52; `dev@650b3f96ccd89c9b2c26ed13ce99915ad4e69275` at documentation integration time
- Parent design: `docs/superpowers/specs/2026-09-24-benefit-verification-core-design.md`
- Related direction: `docs/superpowers/specs/2026-09-10-benefit-business-verification-pipeline-design.md`
- Related policy: `docs/data-policy.md`

## 1. Purpose

Phase 2 Core Foundation can qualify sources, bind them to businesses, extract benefit claims, validate evidence, compare claims, and produce deterministic benefit states. The remaining bottleneck is that real official sources often contain many businesses in one page or document.

The current generic flow can inspect an entire document when binding and extracting. On multi-business pages this can mix another business's claims into the target business's comparison. The 2026-09-24 live smoke exposed this on the DDC source: multiple businesses were present in one HTML table, and whole-document extraction conservatively produced a source conflict for a single canonical business.

This design adds a source-neutral evidence preparation layer so that Phase 2 can:

1. fetch and normalize a source once,
2. break it into source-native content units,
3. locate only the evidence relevant to the intended business,
4. pass that evidence slice into the existing binding, extraction, validation, and comparison core,
5. preserve fail-closed behavior,
6. support later PDF, official SNS/blog, and discovery adapters without replacing the core.

The design is optimized for the current workload while remaining source-agnostic.

## 2. Current workload and design rationale

Current held workload snapshot used for this design:

- held rows: 247,
- rows with strong official/public source types: 221,
- HTML or other web format: 229,
- text-readable PDF candidates: 18,
- XLSX in the held set: 0.

Most currently actionable official evidence is therefore HTML, while PDF is a smaller second group. This makes **HTML-first implementation** efficient.

HTML-first is an implementation priority, not an architectural constraint. The long-term architecture must support official websites, public documents, official SNS/blog sources, and discovery signals through the same downstream verification core.

## 3. Selected architecture

```text
Canonical Business / Benefit
          |
          v
Existing Source or Discovery Candidate
          |
          v
Source Qualification
          |
          v
Source Adapter
          |
          v
SourceObservation
          |
          v
SourceContentUnit[]
          |
          v
Relevant Evidence Locator
          |
          v
RelevantEvidenceSlice[]
          |
          v
Business Binding
          |
          v
Claim Extraction
   +------+------+
   |             |
   v             v
Deterministic    LLM-assisted fallback
   |             |
   +------+------+
          |
          v
Evidence Validation
          |
          v
Currentness Evaluation
          |
          v
Claim Comparison
          |
          v
BenefitState / ReviewClass
          |
          v
Human Review

ProductionAction = NONE
```

The new architectural boundary is the section from **Source Adapter** through **RelevantEvidenceSlice**. The existing Phase 2 verification core remains authoritative for binding, extraction validation, currentness, claim comparison, benefit state, and review classification.

## 4. Design principles

### 4.1 Source-agnostic core

HTML, PDF, SNS, and blog sources may need different retrieval and parsing strategies, but they must converge into common evidence contracts before business verification.

### 4.2 Evidence before claims

A claim must always be traceable to a source evidence slice. A transformed summary or LLM output is not a substitute for source evidence.

### 4.3 Deterministic first

Use deterministic parsing, row/section selection, and structured extraction whenever possible. LLM processing is a bounded extraction fallback for already-located evidence.

### 4.4 Precision over recall

Selecting the wrong business row is more harmful than failing closed.

If the system cannot isolate the intended business safely:

```text
AMBIGUOUS / NOT_FOUND
-> NEEDS_VERIFICATION
```

It must not guess.

### 4.5 Absence is not termination

404, deletion, parsing failure, search failure, unsupported format, missing row, or unavailable current evidence do not prove that a benefit ended.

### 4.6 Officiality is not currentness

An official source can be historical. Current applicability must be evaluated independently.

### 4.7 Human approval remains mandatory

The system remains in Shadow Mode. No result automatically changes canonical data, seed data, or production state.

## 5. Source Adapter boundary

A Source Adapter has three responsibilities:

1. retrieve or accept the source content,
2. normalize it into source-native content units,
3. preserve provenance.

It does not decide:

- business identity,
- benefit state,
- currentness,
- review class,
- whether a claim is correct.

Conceptual flow:

```text
SourceCandidate
    |
    v
Adapter Resolver
    |
    v
Source-specific Adapter
    |
    v
SourceObservation
```

Adapter resolution prefers the most specific supported adapter and falls back to a generic adapter when safe.

Example future registry:

```text
MMA_HTML
DDC_HTML
PAJU_HTML
YANGJU_HTML
HTML_GENERIC
PDF_TEXT
INSTAGRAM
NAVER_BLOG
```

Only adapters required by the active milestone are implemented. Future adapter names are design directions, not pre-approved code.

## 6. SourceObservation and SourceContentUnit

These are conceptual in-process contracts. They do not approve a persistent database schema or external API contract.

### 6.1 SourceObservation

Conceptual fields:

```text
SourceObservation
- SourceRowNumber
- SourceUrl
- SourceKind
- SourceFormat
- FetchStatus
- ObservedAt
- SourceMetadata
- ContentUnits[]
```

A SourceObservation represents one retrieved source at one observation point.

### 6.2 SourceContentUnit

Conceptual fields:

```text
SourceContentUnit
- UnitType
- UnitReference
- RawText
- StructuredFields
- PublishedAt
- Metadata
```

Examples:

- HTML: table row, table, section,
- PDF: page, paragraph, table row,
- SNS: post,
- blog: post or paragraph,
- CSV/XLSX: record/row.

Adapters normalize source structure into these units; they do not decide which unit belongs to the target business.

## 7. Relevant Evidence Locator

The locator receives:

```text
NormalizedBusiness
+
SourceContentUnit[]
```

and returns an evidence location result containing zero or more `RelevantEvidenceSlice` objects.

Its sole responsibility is:

> Identify the smallest safely attributable source region relevant to the target business.

### 7.1 Location result states

Conceptual states:

- `LOCATED`
- `AMBIGUOUS`
- `NOT_FOUND`

No numeric confidence score is introduced in v1. Decisions must be explainable through evidence signals and reason codes.

### 7.2 Matching evidence

Examples:

- `NAME_MATCH`
- `ADDRESS_MATCH`
- `PHONE_MATCH`
- `BRANCH_MATCH`
- `MULTIPLE_NAME_MATCHES`
- `ADDRESS_CONFLICT`
- `PHONE_CONFLICT`
- `BRANCH_CONFLICT`

Hard identity conflicts must not be overridden by text similarity.

### 7.3 Generic and source-specific locator strategies

Preferred order:

```text
Generic deterministic locator
        |
        +-- safe match --> LOCATED
        |
        +-- insufficient structure --> source-specific locator
                                      |
                                      +-- unique safe match --> LOCATED
                                      +-- multiple plausible --> AMBIGUOUS
                                      +-- none --> NOT_FOUND
```

A source-specific strategy may understand source layout, but it must return the same common evidence-slice contract.

## 8. RelevantEvidenceSlice

A RelevantEvidenceSlice is the minimum original source region that can be safely attributed to the intended business.

Conceptual fields:

```text
RelevantEvidenceSlice
- SourceRowNumber
- SourceUrl
- SourceFormat
- LocatorMethod
- ScopeType
- EvidenceReference
- RawEvidenceText
- IdentityEvidence
- ObservedAt
```

Examples of `EvidenceReference`:

- `HTML_TABLE_1_ROW_27`
- `PDF_PAGE_7_TABLE_1_ROW_3`
- `INSTAGRAM_POST_<id>`
- `BLOG_POST_<id>_PARAGRAPH_12`
- `CSV_ROW_84`

`RawEvidenceText` must be derived from the source. It must not be an AI-authored paraphrase.

### 8.1 Full-document scope

`FULL_DOCUMENT` is allowed only when there is adequate evidence that the source itself concerns one business or one directly applicable program scope.

A multi-business directory must never fall back to full-document extraction merely because the locator failed.

## 9. Backward-compatible integration with the existing core

The design prefers additive integration over rewriting the Phase 2 Core.

Existing binding and extraction entrypoints should accept an optional evidence slice or equivalent scoped input.

Conceptual behavior:

```text
EvidenceSlice present
-> bind/extract from scoped evidence

EvidenceSlice absent
-> preserve existing behavior for legacy tests/callers
```

The full Phase 2 adapter path must use scoped evidence whenever a multi-business source requires it.

The existing `BoundBenefitSource` shape should remain unchanged unless implementation proves a contract extension is necessary. Any such change requires explicit review because shared contract changes have wider impact.

## 10. Claim extraction

Extraction operates after relevant evidence has been isolated.

Preferred order:

```text
RelevantEvidenceSlice
        |
        v
Structured deterministic extraction
        |
        +-- insufficient -->
Generic deterministic text extraction
        |
        +-- insufficient -->
LLM-assisted extraction
        |
        +-- failure -->
Human claim review
```

An LLM may extract candidate values such as:

- benefit description,
- eligible target,
- usage condition,
- verification method,
- explicit validFrom,
- explicit validUntil,
- evidence span/reference.

An LLM must not decide:

- officiality,
- business identity,
- currentness,
- material change,
- ACTIVE / CHANGED / ENDED,
- GREEN / YELLOW / RED.

LLM output remains a candidate until evidence validation succeeds.

## 11. Evidence trust model

Evidence sources have different roles.

### 11.1 Strong evidence candidates

Examples:

- government,
- municipality,
- public institution,
- official business website,
- later: independently verified official business SNS/blog account.

Strong evidence status still requires source qualification and business binding.

### 11.2 Supporting / discovery signals

Examples:

- personal blogs,
- customer reviews,
- community posts,
- general social posts,
- user-submitted leads.

These sources can identify candidate businesses or benefits but do not independently justify a strong verified state.

### 11.3 Unusable / unverified evidence

Examples:

- source-less screenshots,
- unverifiable reposts,
- inaccessible content without sufficient provenance,
- content whose business identity materially conflicts.

Weak evidence is not discarded; it is routed into discovery rather than silently promoted.

## 12. Official SNS/blog account qualification

Future social adapters require a separate account-identity gate because a platform domain does not establish the business account's officiality.

Potential qualification evidence includes:

- compatible business name,
- matching address,
- matching phone,
- official website linking to the social account,
- social profile linking to the official website,
- explicit official store-directory linkage.

The design prefers boolean/evidence tuples over arbitrary scores.

Example evidence:

```text
BUSINESS_NAME_MATCH
PHONE_MATCH
WEBSITE_BACKLINK_MATCH
```

The current v1 officiality states remain:

- `VERIFIED_OFFICIAL`
- `UNVERIFIED`
- `REJECTED`

No SourceKind or persistent schema extension is approved by this document. Social-specific contract expansion belongs to the later SNS milestone and requires separate approval.

## 13. Currentness and ending semantics

### 13.1 Currentness is separate from officiality

Possible currentness states remain conceptually:

- `CURRENT`
- `UNKNOWN`
- `NOT_CURRENT`

A source being observed today does not make its benefit claim current.

### 13.2 NOT_CURRENT is not automatically ENDED

A historical campaign can be over while the same business offers a different current military benefit.

### 13.3 ENDED requires positive evidence

`ENDED` is permitted only when validated evidence directly supports termination, for example:

- explicit discontinuation wording,
- an explicit `validUntil` that has passed for the verified benefit/program.

The following never prove `ENDED` by themselves:

- 404,
- deleted SNS post,
- missing search result,
- missing row,
- fetch timeout,
- unsupported file,
- parser failure,
- LLM failure,
- absence from a page whose completeness is not established.

## 14. Claim conflicts and composite evidence

Claims are resolved per claim rather than by universal source ranking.

Conflict analysis considers:

1. same business/branch,
2. same benefit program,
3. currentness for the relevant period,
4. authority/directness for the claim,
5. whether sources can be explicitly combined.

"Newest source always wins" is not a valid general rule.

Composite official evidence remains allowed when linkage is explicit, for example:

- source A defines a common military-benefit program,
- source B explicitly lists the business as a participant.

Unclear linkage remains `NEEDS_VERIFICATION`.

## 15. Fallback routing

Fallback behavior is reason-specific and deterministic.

### 15.1 Failure categories

**Source failures**
- `SOURCE_FETCH_FAILED`
- `SOURCE_UNSUPPORTED`
- `SOURCE_NOT_FOUND`
- `SOURCE_UNVERIFIED`

**Identity / locator failures**
- `LOCATOR_AMBIGUOUS`
- `LOCATOR_NOT_FOUND`
- `BUSINESS_BINDING_AMBIGUOUS`
- `BUSINESS_BINDING_CONFLICT`

**Extraction failures**
- deterministic extraction failed after safe location,
- LLM extraction failed.

**Semantic/evidence failures**
- `CURRENTNESS_UNKNOWN`
- `SOURCE_CONFLICT`
- evidence-validation conflict,
- claim conflict.

### 15.2 Conceptual next actions

- `CONTINUE`
- `TRY_SOURCE_SPECIFIC_LOCATOR`
- `TRY_LLM_EXTRACTION`
- `TRY_PDF_ADAPTER`
- `TRY_OFFICIAL_DISCOVERY`
- `HUMAN_REVIEW`
- `STOP_UNRESOLVED`

Example routing:

| Condition | Next action |
| --- | --- |
| existing URL fetch fails | official discovery |
| generic locator lacks enough structure | source-specific locator |
| locator ambiguous | human identity review |
| binding conflict | human identity review |
| safe slice + deterministic extraction fails | LLM extraction |
| text-readable PDF parser unavailable | PDF adapter |
| OCR-required PDF | human review in initial PDF milestone |
| currentness unknown | official discovery |
| only weak blog/review signal exists | official discovery |
| two strong current sources conflict | human review |
| validated explicit termination | deterministic core evaluation |

Identity ambiguity must not be resolved by asking an LLM to choose a business.

## 16. Loop prevention and bounded fallback

One verification run must track attempted source/strategy combinations so that it does not repeatedly rediscover or retry the same path.

Conceptually:

```text
AttemptHistory
- source
- strategy
- input identity
- status
```

Retries must be bounded. If supported fallbacks are exhausted:

```text
NEEDS_VERIFICATION
+ explicit ReasonCode[]
+ human review target
```

is the correct result.

## 17. Efficiency and reuse

### 17.1 Fetch once, reuse many

The same URL shared by many canonical rows should be fetched once per verification run where practical.

### 17.2 Parse once, locate many

Source parsing should produce reusable `SourceObservation` / `SourceContentUnit[]` results.

Example:

```text
MMA URL
 -> fetch once
 -> parse once
 -> content units
 -> reused by many canonical businesses
```

### 17.3 Per-run cache first

Milestone A prioritizes in-run reuse. Persistent cross-run caching, ETag/Last-Modified handling, and scheduled refresh policies are deferred.

A cached observation is never equivalent to currentness.

### 17.4 LLM minimization

LLM input should normally be a RelevantEvidenceSlice, not an entire multi-business page or a large social feed.

LLM use is avoided when deterministic structured extraction succeeds.

### 17.5 Discovery minimization

Existing qualified evidence is revalidated before broad discovery. Discovery runs only when the existing evidence path cannot establish what is needed.

## 18. Metrics

Recommended operational metrics:

```text
EvaluatedRows
UniqueSourceUrls
ExternalFetchCount
SourceFetchFailures
FetchCacheHits

AdapterParseCount
AdapterReuseCount

LocatorLocated
LocatorAmbiguous
LocatorNotFound
CrossBusinessClaimLeakageCount

BindingStrong
BindingPlausible
BindingAmbiguous
BindingConflict

ExtractionComplete
ExtractionPartial
ExtractionFailed
DeterministicExtractionCount
LlmInvocationCount
LlmAvoidedCount
DiscoveryInvocationCount

ACTIVE
CHANGED
ENDED
NEEDS_VERIFICATION

GREEN
YELLOW
RED

FalseGreenCount
FalseEndedCount
ProductionActionNoneCount
```

Provider cost is not guessed before a provider/model is selected. Later provider integrations should record real request and token/usage data so cost can be computed from observed usage.

## 19. Testing strategy

Testing proceeds in four layers.

### 19.1 Unit and contract tests

Validate:

- provenance is preserved,
- slices contain source-backed raw text,
- exact single-row location succeeds,
- duplicate plausible rows become `AMBIGUOUS`,
- missing business becomes `NOT_FOUND`,
- address/branch/phone hard conflicts cannot be silently selected.

### 19.2 Golden regression

Existing known-risk fixtures remain safety gates, including:

- 버섯집 초리골 building 12 vs 23,
- 이지현미용실 26 vs 23,
- 인헤어 902·2동104호 vs 904.

Add a multi-business HTML regression based on the DDC failure mode.

Required invariant:

```text
Cross-business claim leakage = 0
```

### 19.3 Source-family live smoke

Representative live official sources should include supported source families such as:

- MMA,
- DDC,
- Paju,
- Yangju.

Sample selection should include easy and difficult identity cases rather than only clean rows.

### 19.4 Official HTML hold shadow run

After Golden and smoke validation, run the supported official HTML held workload in Shadow Mode to establish a real baseline.

Coverage is measured, not pre-forced to an arbitrary threshold. The first milestone prioritizes precision over recall.

## 20. Milestone A safety gates

Required:

```text
Golden false-row selection = 0
False GREEN = 0
False ENDED = 0
Cross-business claim leakage = 0
Known hard-conflict bypass = 0
ProductionAction != NONE = 0
```

Fetch/parse reuse must also be observable.

For ordinary source requests within a run, the design target is:

```text
fetch once per unique source
parse once per unique source/adapter result
reuse for multiple businesses
```

Redirect and explicitly bounded retry behavior may be counted separately when implemented.

No arbitrary live-workload locator coverage threshold is set before the baseline is measured.

## 21. Failure taxonomy as input to later milestones

After Milestone A, unresolved rows are classified by reason.

Examples:

- unstructured text but safe evidence slice exists -> LLM extraction candidate,
- text-readable PDF -> PDF milestone,
- source missing/stale/currentness unknown -> discovery milestone,
- business identity ambiguous/conflicting -> human identity review,
- unsupported scanned document -> manual review or later OCR milestone.

This prevents designing LLM/PDF/discovery behavior against assumptions rather than observed failures.

## 22. Implementation milestones

### Milestone A — Official HTML evidence scoping

Goal: eliminate cross-business evidence mixing and establish a deterministic HTML baseline.

Scope:

- evidence-location foundation,
- SourceObservation / SourceContentUnit concept as needed,
- RelevantEvidenceSlice,
- generic structured HTML locator,
- targeted source-family HTML strategies,
- optional scoped input to existing binding/extraction,
- per-run fetch/parse reuse,
- regression and shadow validation.

Source-family priority:

- MMA,
- DDC,
- Paju,
- Yangju.

No LLM, PDF library, SNS provider, discovery provider, canonical mutation, seed mutation, or Android change.

### Milestone B — Unstructured official evidence

Separate approval is required for any new external provider/dependency.

Scope candidates:

- LLM-assisted extraction adapter,
- text-readable PDF adapter,
- evidence validation integration,
- usage instrumentation.

OCR-required PDF remains deferred unless separately approved.

### Milestone C — Official SNS/blog and discovery

Scope candidates:

- official social account qualification,
- official SNS/blog content adapters,
- weak-signal discovery routing,
- official-source discovery provider.

Any new API/provider/authentication/secret-management dependency requires explicit approval.

### Milestone D — Representative Phase 2 validation

Run representative held-workload validation and human audit.

Evaluate:

- safety gates,
- source-family performance,
- locator coverage,
- deep manual review requirements,
- LLM/discovery usage,
- false-GREEN,
- false-ENDED.

Only then decide whether Phase 2 can be marked complete.

## 23. First implementation issue boundary

The first implementation issue should remain small.

### Problem

Multi-business official HTML sources can cause another business's evidence to enter the target business's binding/extraction path.

### In scope

- scoped evidence-location contracts or internal representations,
- generic structured HTML evidence locator,
- safe integration with existing binding/extraction,
- provenance retention,
- Golden/regression coverage,
- no silent full-document fallback for multi-business pages.

### Out of scope

- LLM,
- PDF parsing,
- OCR,
- SNS,
- blogs,
- broad web discovery,
- canonical changes,
- seed changes,
- Android changes,
- Room schema,
- server DB,
- authentication,
- external API changes,
- new external dependencies.

Exact filenames are selected during implementation planning against the latest `dev`.

## 24. Approved architectural direction

This design approves the following direction, subject to the written-spec review gate before implementation planning:

- Source Adapter layer,
- SourceObservation / SourceContentUnit concepts,
- RelevantEvidenceSlice,
- locator before business binding/extraction,
- source-specific adapters behind a common evidence pipeline,
- HTML-first implementation with source-agnostic architecture,
- explicit trust roles for strong evidence and discovery signals,
- deterministic-first extraction,
- bounded LLM extraction fallback,
- reason-based fallback routing,
- per-run fetch/parse reuse,
- precision-first locator behavior,
- fail-closed semantics,
- Shadow Mode and human approval.

## 25. Not approved by this design

This design does not approve:

- Room schema changes,
- server database changes,
- Android data schema changes,
- authentication changes,
- external API contract changes,
- automatic production updates,
- automatic canonical edits,
- automatic seed edits,
- any LLM provider/model/SDK,
- any PDF parsing library,
- any SNS provider/API,
- any search/discovery provider,
- any new external dependency,
- persistent scheduler/history architecture,
- OCR/HWP/HWPX implementation.

Those decisions require separate evidence, design, and approval at the milestone where they become necessary.

## 26. Review gate

The next step after this spec is reviewed and approved is to invoke the implementation-planning workflow for **Milestone A only**.

Implementation must not begin before:

1. this written spec is reviewed and approved,
2. the Milestone A implementation plan is written and reviewed,
3. the execution method is selected.

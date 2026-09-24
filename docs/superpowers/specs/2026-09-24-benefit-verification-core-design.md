# Phase 2 Benefit Verification Core Design

- Status: Design approved — user approved written Phase 2 design
- Date: 2026-09-24
- Repository baseline: `dev@9a435159cb26b793057797cafe37e8f922fe3a81`
- Scope type: Architectural / new verification subsystem
- Parent direction: `docs/superpowers/specs/2026-09-10-benefit-business-verification-pipeline-design.md`
- Related policy: `docs/data-policy.md`
- Roadmap: `docs/roadmap.md`

## 1. Purpose

Phase 2 builds a reusable verification core for the **military benefit itself**, independently from POI/location verification.

The product-level goal remains:

> Maintain a trustworthy current view of businesses that currently exist and currently provide a military benefit, together with their verified current location, benefit details, explicit validity period when known, evidence source, and verification state.

Phase 1 established a Shadow Mode pipeline for business identity and POI/location evidence. Phase 2 must reuse that evidence where useful, but it must not collapse location truth and benefit truth into one decision.

The immediate operational problem is that benefit verification still requires a human to repeatedly:

1. find or reopen official sources,
2. determine whether the source is actually official,
3. determine whether it refers to the intended business/branch,
4. read the relevant benefit text,
5. compare it with the canonical benefit fields,
6. decide whether the benefit is active, changed, ended, or still uncertain.

Phase 2 automates as much of this evidence preparation and deterministic comparison work as possible while preserving human approval.

## 2. Design intent

Phase 2 is designed to reduce manual discovery and comparison work without lowering approval standards.

Success means the system can:

- revalidate existing official evidence,
- discover replacement official evidence in a controlled way when needed,
- qualify source officiality,
- bind evidence to the intended business,
- extract benefit claims from supported document formats,
- verify extracted claims against the original source,
- compare claims with canonical benefit data,
- produce deterministic `BenefitState`, `ReviewClass`, and reason codes,
- preserve enough evidence for a human to review the result quickly,
- fail closed when discovery, fetching, extraction, binding, currentness, or evidence validation is insufficient.

Success does **not** mean automatic production data updates in Phase 2.

## 3. Existing truth and relationship to prior design

This spec refines only the Phase 2 portion of the broader 2026-09-10 pipeline design. It does not replace the long-term architecture.

Where this Phase 2 spec is more specific, it governs Phase 2 v1. In particular:

- Phase 2 v1 narrows strong-evidence web sources to government, municipality, public institution, and official business websites.
- Official SNS/blog sources remain a valid long-term direction but are deferred from Phase 2 v1.
- The earlier broad conceptual benefit states are simplified for Phase 2 v1 into a small final state model plus reason codes.
- Officiality and currentness are treated as separate properties.
- LLM use is restricted to extraction assistance, not final verification decisions.

This spec does **not** approve any Room schema, server database, API contract, authentication flow, persistent schema, or new external dependency.

## 4. Core principles

### 4.1 Separate identity, location, and benefit

Business Identity, Location Verification, and Benefit Verification remain separate concerns.

Phase 1 evidence may help Phase 2 bind an official benefit source to the intended business, but Phase 1 `GREEN` is not a prerequisite for running Phase 2.

Examples:

- Phase 1 YELLOW + strong benefit source binding may still produce a high-confidence benefit observation.
- Phase 1 GREEN does not prove a military benefit still exists.
- Phase 2 benefit evidence does not prove current map coordinates are correct.

### 4.2 Evidence first

No benefit, target, condition, verification method, validity date, currentness, or ending state is invented from inference alone.

Every accepted claim must remain traceable to source evidence.

### 4.3 Search result is not evidence

Search results and snippets are discovery signals only.

A discovered source becomes usable evidence only after:

1. the actual document/page is retrieved,
2. the source is qualified,
3. the document is bound to the intended business/program,
4. the relevant content is extracted,
5. the extracted claims are validated against the original content.

### 4.4 Official does not mean current

An official 2022 notice is still official, but it may not prove that a benefit is currently active.

Officiality and current applicability must be evaluated separately.

### 4.5 LLM output is not verified evidence

LLM output is an extraction candidate.

A claim extracted by an LLM must be checked against the original source before it can enter deterministic benefit verification.

### 4.6 Failure does not mean benefit ended

The following must never be sufficient to infer `ENDED`:

- no search result,
- source URL returns 404,
- fetch timeout,
- parser failure,
- unsupported document format,
- LLM failure,
- missing current page,
- Phase 1 POI failure.

### 4.7 GREEN is not production approval

Phase 2 is Shadow Mode. Every result remains subject to human approval.

## 5. Phase 2 v1 architecture

The selected approach is a staged evidence pipeline.

```text
Canonical Benefit Row
        |
        +---- Phase 1 identity/location evidence
        |
        v
Existing Official URL Revalidation
        |
        v
Controlled Official Source Discovery
        |
        v
Source Qualification
        |
        v
Business Binding
        |
        v
Document Extraction
   +----+----------------+
   |                     |
   v                     v
Deterministic       LLM-assisted
structured          unstructured
extraction          extraction
   |                     |
   +----------+----------+
              |
              v
Evidence Validation
              |
              v
Claim-level Verification
              |
              v
Deterministic Benefit Evaluation
              |
              +--> BenefitState
              +--> ReviewClass
              +--> ReasonCode[]
              |
              v
Shadow Review Artifact / Human Review

ProductionAction = NONE
```

Each stage owns one responsibility and must not silently take over another stage's decision.

## 6. Conceptual contracts

These are conceptual in-process/file contracts only. They do not approve a persistent schema.

```text
CanonicalBenefitRow
        ↓
OfficialSourceCandidate[]
        ↓
QualifiedOfficialSource[]
        ↓
BoundOfficialSource[]
        ↓
ExtractedBenefitEvidence[]
        ↓
ValidatedBenefitEvidence[]
        ↓
BenefitClaimVerification[]
        ↓
BenefitVerificationResult
```

Exact implementation filenames and serialization format are intentionally not fixed by this design. They must be chosen against the latest `dev` during implementation planning.

## 7. Source discovery

### 7.1 Discovery order

Phase 2 must prefer existing evidence over broad discovery.

```text
1. Revalidate existing canonical official URL
2. If current evidence is sufficient, stop discovery for that need
3. Otherwise perform controlled official-source discovery
4. Retrieve actual candidate document/page
5. Qualify source before using content as evidence
```

This avoids unnecessary search cost and makes provenance easier to preserve.

### 7.2 Phase 2 v1 strong-evidence source scope

Allowed strong-evidence candidates:

- government,
- municipality,
- public institution,
- official business website,
- existing canonical URLs that belong to one of the above categories.

Deferred from Phase 2 v1 strong evidence:

- official Instagram,
- official Naver Blog,
- other business SNS,
- other social platforms.

Discovery-only / not strong evidence in Phase 2 v1:

- personal blogs,
- communities,
- reviews,
- unverified social posts,
- user submissions.

Later phases may expand supported source adapters without changing the core verification principles.

### 7.3 Discovery operational status

Discovery status is operational, not semantic:

- `COMPLETE`: planned discovery strategies completed normally,
- `PARTIAL`: some query/fetch paths failed,
- `FAILED`: usable discovery execution could not complete.

Rules:

- `FAILED` does not imply `ENDED`.
- `PARTIAL` does not imply `ENDED`.
- zero candidates does not imply `ENDED`.

## 8. Source qualification

### 8.1 Qualification result

Conceptual officiality states:

- `VERIFIED_OFFICIAL`
- `UNVERIFIED`
- `REJECTED`

Only qualified sources may become strong evidence.

### 8.2 Government / municipality / public institution

Qualification must establish that:

- the domain/source is controlled by the relevant institution,
- the actual document is provided by that institution,
- the content is not merely an external personal source linked from an official page.

Official hosting proves source ownership, not current applicability or benefit meaning.

### 8.3 Official business website

A business name match alone is insufficient.

An official business website candidate requires:

- business name compatibility, and
- at least one additional identity signal.

Additional identity signals may include:

- address,
- branch name,
- phone number,
- corporate/business entity name,
- explicit linkage from an official store directory.

Clear identity conflict must prevent strong-evidence qualification for the intended business.

## 9. Business binding

Source officiality and business identity are separate gates.

Conceptual binding states:

- `STRONG`
- `PLAUSIBLE`
- `AMBIGUOUS`
- `CONFLICT`

### 9.1 STRONG

Examples:

- compatible business name + matching address,
- compatible business name + explicit branch match,
- compatible business name + matching phone number,
- official participant record with enough identifiers to isolate the intended branch.

### 9.2 PLAUSIBLE

The source likely refers to the business, but branch or identity detail is insufficient for high-confidence automated review.

### 9.3 AMBIGUOUS

The source cannot distinguish among multiple plausible businesses/branches.

### 9.4 CONFLICT

Examples:

- incompatible road/building number,
- explicitly different branch,
- incompatible locality,
- materially different phone/business identity when identifying.

A hard identity conflict cannot be overridden by textual similarity.

## 10. Relationship to Phase 1

Phase 1 identity/location evidence is an input signal for Phase 2 Business Binding.

Phase 2 must not require Phase 1 `GREEN` as an execution precondition.

If Phase 1 has unresolved identity evidence but the benefit source independently binds the intended business strongly, benefit verification may continue.

If identity uncertainty materially affects benefit binding, Phase 2 must fail closed, for example:

```text
BenefitState = NEEDS_VERIFICATION
ReviewClass = YELLOW or RED
ReasonCode includes BUSINESS_BINDING_AMBIGUOUS or BUSINESS_BINDING_CONFLICT
```

## 11. Composite Official Evidence

Phase 2 may combine multiple official documents when no single document contains the entire proof.

Example:

- official document A describes a common military-discount program,
- official document B lists the intended business as a participant.

The documents may be combined only when all required links are explicit enough to avoid guessing:

- same program/campaign,
- same operating authority or explicitly connected authorities,
- business participation is explicit,
- common benefit policy is explicit,
- the relationship between documents is directly supportable.

If the linkage is unclear, do not combine them. The result remains `NEEDS_VERIFICATION`.

## 12. Supported source formats

Phase 2 v1 supports:

- HTML,
- text-readable PDF,
- CSV,
- XLSX or equivalent structured attachment directly linked from an official page.

Deferred:

- OCR-required scanned PDF,
- HWP/HWPX-specific parsing,
- image-only benefit content,
- login/session-dependent pages.

Finding an unsupported but official document is not semantic failure. It is evidence that requires manual verification.

## 13. Document extraction

### 13.1 Structured sources

Use deterministic extraction first for structured documents such as:

- CSV,
- XLSX,
- clearly structured tables,
- safely parseable structured HTML.

Deterministic extraction means reading the declared value accurately. It does not mean the value is automatically current or applicable to the intended business.

### 13.2 Unstructured sources

Free-form HTML and text-readable PDFs may use LLM-assisted extraction.

The LLM's role is limited to transforming source text into claim candidates such as:

- business name,
- branch name,
- benefit description,
- eligible target,
- usage condition,
- verification method,
- validFrom,
- validUntil,
- evidence span/reference.

### 13.3 LLM non-responsibilities

The LLM must not be the authority that decides:

- whether the source is official,
- whether the source is current,
- whether the business binding is strong enough,
- whether a change is material,
- whether the benefit is ACTIVE / CHANGED / ENDED,
- whether the review class is GREEN / YELLOW / RED.

Those are deterministic pipeline decisions based on validated evidence.

### 13.4 Provider abstraction

This design approves only an abstract LLM-assisted extraction boundary.

It does not select:

- OpenAI,
- Anthropic,
- Google,
- any specific model,
- SDK,
- new external dependency,
- secret-management mechanism.

Any dependency or provider integration requiring repository changes needs the applicable approval before implementation.

## 14. Evidence validation

Extracted values must be checked against the source before they become verified claim evidence.

Validation should establish, where applicable:

- evidence span/reference exists in the source,
- percentages and monetary values match the source,
- explicit dates match the source,
- target/condition text is supportable from the source,
- business/branch text is supportable from the source.

If an extracted value conflicts with the source, the system must not silently correct and accept it.

Instead, mark that claim unusable and preserve a warning/reason.

Conceptual validation states:

- `VALIDATED`
- `UNKNOWN`
- `CONFLICT`
- `INVALID`

One invalid claim does not require discarding every other valid claim from the same document.

## 15. Date semantics

Document dates and benefit-validity dates are distinct.

Examples:

- "posted on 2026-04-03" → document publication metadata,
- "effective from 2026-04-03" → `validFrom`,
- "available until 2026-12-31" → `validUntil`.

Rules:

- do not infer `validFrom` from publication date,
- do not infer `validUntil` when the source does not state an end,
- `observedAt` is evidence observation time,
- `lastVerifiedAt` is verification time,
- `nextReviewAt` is an internal scheduling concept and is not an expiry date.

Phase 2 v1 must not introduce an arbitrary "older than N months means expired" rule.

## 16. Extraction operational status

Extraction status is operational:

- `COMPLETE`
- `PARTIAL`
- `FAILED`

Examples:

- source parsed and required extracted claims validated → COMPLETE,
- some claims usable but others unavailable/invalid → PARTIAL,
- parsing/extraction failed entirely → FAILED.

`FAILED` must never be converted into `ENDED`.

## 17. Claim-level verification

The verification unit is an individual benefit claim, not an entire page.

### 17.1 Lifecycle / identity-critical claims

- `BusinessBinding`
- `BenefitExistence`
- `CurrentApplicability`

### 17.2 Benefit detail claims

- `BenefitDescription`
- `EligibleTarget`
- `UsageCondition`
- `VerificationMethod`
- `ValidFrom`
- `ValidUntil`

Conceptual claim comparison results:

- `CONFIRMED`
- `CHANGED`
- `ENDED`
- `UNKNOWN`
- `CONFLICT`
- `NOT_APPLICABLE`

These are not persistent schema requirements; they define verification behavior.

## 18. Material change semantics

Formatting differences must not create unnecessary `CHANGED` results.

Examples likely semantically equivalent when source context supports it:

- "10% 할인"
- "이용금액 10% 할인"
- "결제금액의 10% 할인"

Material changes include user-relevant differences such as:

- discount percentage or monetary benefit,
- eligible target,
- usage condition,
- verification method,
- explicit validity period.

Examples:

- 10% → 20%,
- active duty only → active duty + military civilian,
- always available → weekdays only,
- military ID → Nara Sarang Card required,
- no stated end → explicit end date.

The implementation plan must define deterministic normalization/comparison rules where possible. LLM semantic judgment must not become the sole final change detector.

## 19. Currentness

Officiality and currentness are separate.

Currentness may be supported by:

- a currently operated official lookup/list system observed now,
- explicit current program wording,
- explicit validity dates,
- an official page/document that clearly states present applicability.

Currentness must not be derived only from `observedAt=today`.

A historical notice/PDF that remains online but has no evidence of current operation may be official yet still yield unknown current applicability.

## 20. Claim-specific evidence resolution

Conflicting official evidence must not be resolved using a universal source ranking such as:

- government always beats business website, or
- business website always beats government.

Resolve conflicts per claim by considering:

1. whether both sources refer to the same business/branch,
2. whether they refer to the same military-benefit program,
3. which source is explicitly current for the relevant period,
4. which source has more direct authority for the specific claim,
5. whether the evidence can be safely combined instead of treated as conflicting.

Example:

- municipality list may strongly prove program participation,
- official business website may strongly prove a current detailed discount condition.

If a real conflict remains unresolved:

```text
BenefitState = NEEDS_VERIFICATION
ReviewClass = RED
ReasonCode includes SOURCE_CONFLICT
```

Preserve both conflicting evidence records.

## 21. Final BenefitState

Phase 2 v1 uses four final states:

- `ACTIVE`
- `CHANGED`
- `ENDED`
- `NEEDS_VERIFICATION`

This simplifies the broader earlier conceptual model while preserving reasons separately.

### 21.1 ACTIVE

Use when:

- business binding is sufficiently supported,
- benefit existence is confirmed,
- current applicability is confirmed.

Not every detail claim must be known for the state itself to be ACTIVE.

### 21.2 CHANGED

Use when current official evidence clearly supports a material change from canonical benefit data.

A disagreement between unresolved official sources is not automatically `CHANGED`; it is `NEEDS_VERIFICATION` with conflict reasons.

### 21.3 ENDED

Use only with explicit ending evidence, such as:

- explicit discontinuation statement,
- explicit `validUntil` that has passed and is proven to apply to the intended benefit/business.

Search absence, 404, stale source, or parser failure is not enough.

### 21.4 NEEDS_VERIFICATION

Use when the pipeline cannot safely establish the relevant lifecycle truth.

Common reasons include:

- insufficient currentness,
- ambiguous business binding,
- source conflict,
- extraction failure,
- unsupported source format,
- insufficient evidence.

## 22. Mapping from earlier conceptual states

The broader 2026-09-10 design listed states such as:

- DISCOVERED,
- VERIFICATION_REQUIRED,
- ACTIVE,
- CHANGED,
- EXPIRED,
- DISCONTINUED,
- UNKNOWN.

For Phase 2 v1:

- DISCOVERED becomes an intermediate pipeline condition, not a final `BenefitState`,
- VERIFICATION_REQUIRED / UNKNOWN map to `NEEDS_VERIFICATION`,
- EXPIRED maps to `ENDED` with an explicit-validity-end reason,
- DISCONTINUED maps to `ENDED` with an explicit-discontinuation reason.

This avoids state explosion while retaining meaning in `ReasonCode[]`.

## 23. ReviewClass

`ReviewClass` describes evidence confidence/safety, not benefit lifecycle state.

Values:

- `GREEN`
- `YELLOW`
- `RED`

Examples:

```text
ACTIVE + GREEN
= current benefit and material use information are strongly supported

ACTIVE + YELLOW
= current benefit is supported, but relevant detail remains incomplete

CHANGED + GREEN
= a material change is strongly supported

CHANGED + YELLOW
= change appears supported but detail/completeness needs review

ENDED + GREEN
= explicit ending evidence is strong

NEEDS_VERIFICATION + YELLOW
= incomplete or ambiguous evidence

NEEDS_VERIFICATION + RED
= material identity/source conflict or other strong safety concern
```

Important:

- RED does not mean the benefit ended.
- ENDED can be GREEN.
- GREEN means fast-review candidate, not production approval.

A separate future `ReviewPriority` may be introduced if operational urgency needs to be represented. It must not be conflated with ReviewClass in Phase 2 v1.

## 24. Reason codes

The final result should expose explicit reasons instead of relying only on state labels.

The exact enumeration belongs in the contract/planning stage, but Phase 2 must be able to represent reasons including:

- source not found,
- source fetch failed,
- source unsupported,
- source officiality unresolved,
- business binding ambiguous,
- business binding conflict,
- currentness insufficient,
- extraction failed,
- extraction/source mismatch,
- claim unknown,
- material change,
- explicit validity end,
- explicit discontinuation,
- source conflict,
- composite evidence used.

Reason codes must be auditable and deterministic.

## 25. Conceptual final result

```text
BenefitVerificationResult
├─ SourceRowNumber
├─ BusinessIdentity
├─ BenefitState
├─ ReviewClass
├─ ReasonCode[]
├─ ClaimResults[]
├─ Evidence[]
├─ Warnings[]
└─ ProductionAction = NONE
```

The result must preserve enough provenance to answer:

- which source was used,
- which document/content supported the claim,
- when it was observed,
- how it was bound to the business,
- how the claim was extracted,
- whether the extraction was validated,
- which rule produced the final state/review class.

## 26. Shadow Mode restrictions

Phase 2 v1 must not:

- modify canonical automatically,
- modify Android seed automatically,
- modify product DB automatically,
- auto-approve GREEN results,
- remove a benefit automatically because a source disappeared,
- introduce a persistent schema without separate approval,
- change API contracts without separate approval,
- add a new external dependency without separate approval.

Every Phase 2 result must use:

```text
ProductionAction = NONE
```

## 27. Operational scope

The Phase 2 core must be capable of processing all current canonical rows.

Current policy baseline records:

- 496 total canonical rows,
- 249 release candidates,
- 247 rows held because latest benefit evidence is insufficient.

Initial operational validation should not require a full 496-row run before confidence is established.

Recommended validation expansion:

```text
Deterministic fixtures / contract tests
        ↓
small operational smoke
        ↓
representative sample centered on 247 held rows
        +
positive controls sampled from 249 release candidates
        ↓
human audit
        ↓
larger batch / optional full run after safety gate
```

The 247 held rows are operational workload, not automatically labeled Golden truth.

## 28. Benefit Golden Dataset

Golden data must contain only human-reviewed cases with known expectations.

Expected groups:

- ACTIVE positive,
- CHANGED,
- ENDED,
- NEEDS_VERIFICATION,
- conflict/ambiguity safety cases.

Do not invent real business outcomes to fill missing groups.

Where real CHANGED/ENDED examples are insufficient, use clearly labeled synthetic fixtures for algorithm tests only. Synthetic fixtures must never be written into production benefit data.

## 29. Testing strategy

Testing should proceed in layers.

### 29.1 Unit tests

Cover isolated behavior such as:

- source qualification,
- business binding,
- date semantics,
- benefit normalization,
- evidence span/source matching,
- material-change comparison,
- state evaluation,
- review-class evaluation,
- reason-code generation.

### 29.2 Contract tests

Verify that stage boundaries preserve required fields and status semantics.

Examples:

- Discovery → Qualification,
- Qualification → Binding,
- Extraction → Evidence Validation,
- Claim Verification → Evaluation.

### 29.3 Regression tests

Known ambiguous/conflict cases must not silently become GREEN.

Any changed Golden expectation must require an explicit reviewed reason.

### 29.4 Operational tests

Run against real supported official sources to measure:

- source discovery behavior,
- fetch behavior,
- extraction behavior,
- business binding quality,
- state/review distribution,
- manual review workload.

### 29.5 LLM safety tests

If LLM-assisted extraction is implemented, test that:

- unsupported discounts are rejected,
- invented dates are rejected,
- invalid JSON fails closed,
- timeout fails closed,
- source mismatch fails closed,
- LLM failure never becomes ACTIVE or ENDED by itself.

The safety target is not "the LLM never makes a mistake." The target is "an LLM mistake cannot silently become trusted benefit truth."

## 30. Metrics

Where measurable without guessing, Phase 2 operational reports should include:

- Discovery COMPLETE / PARTIAL / FAILED,
- qualified official source rate,
- Business Binding STRONG / PLAUSIBLE / AMBIGUOUS / CONFLICT,
- Extraction COMPLETE / PARTIAL / FAILED,
- Evidence Validation failure/rejection rate,
- BenefitState distribution,
- ReviewClass distribution,
- false-GREEN count on labeled data,
- manual deep-review rate,
- source-conflict rate,
- existing-source reuse rate,
- discovery fallback rate,
- average external requests per row.

If LLM extraction is used:

- LLM invocation rate,
- LLM extraction failure rate,
- LLM output rejection rate by Evidence Validation.

Small operational samples must be reported as sample observations, not population precision claims.

## 31. Human audit

After representative Shadow Mode runs, sample GREEN results must be reviewed manually against original evidence.

A simple audit vocabulary may include:

- `SUPPORTED`
- `AMBIGUOUS`
- `CONFLICT`

This is an audit observation, not automatic production approval.

For example, `SUPPORTED 5/5` in a small sample must not be reported as population precision = 100%.

## 32. Phase 2 completion gate

Phase 2 may be considered implementation-complete only after all of the following are demonstrated:

### Contract

Phase 2 internal contracts are fixed and regression-tested.

### Integration

The staged path is connected:

```text
Discovery
→ Qualification
→ Binding
→ Extraction
→ Evidence Validation
→ Claim Verification
→ Benefit Evaluation
```

### Safety

Search/fetch/parser/LLM failures cannot become false ACTIVE or ENDED outcomes.

### Regression

Known ambiguity/conflict cases cannot silently become GREEN.

### Evidence

Final decisions are traceable back to source evidence.

### Shadow Mode

`ProductionAction = NONE` for every run.

### Non-write

No automatic canonical, seed, app, or production DB modification occurs.

### Operational validation

Supported real official sources are exercised with a smoke test and representative sample.

### Human audit

GREEN sample results receive direct evidence review.

### Metrics

Safety and workload metrics are reported with limitations.

### Closeout

Evidence, remaining risks, unsupported source classes, and known recall/efficiency limitations are documented before the roadmap marks Phase 2 complete.

## 33. Explicit non-goals

Phase 2 v1 does not include:

- automatic production approval,
- automatic canonical/seed updates,
- Room schema changes,
- server DB introduction,
- API contract changes,
- authentication changes,
- SNS/Instagram/Naver Blog as strong-evidence sources,
- personal blog/community evidence as strong evidence,
- OCR pipeline,
- HWP/HWPX parser,
- periodic scheduler,
- snapshot/history persistence,
- broad discovery of entirely new benefit programs,
- near-event-driven monitoring,
- LLM provider commitment,
- unapproved new external libraries.

These belong to later phases or separate approval decisions.

## 34. Risks

### 34.1 False business binding

Same-name businesses or branch ambiguity may attach valid benefit evidence to the wrong business.

Mitigation: explicit Business Binding gate, Phase 1 evidence reuse, hard conflict handling.

### 34.2 Stale official evidence

Official content can remain online long after operational relevance ends.

Mitigation: separate officiality from currentness; no age-only expiry rule.

### 34.3 Composite evidence overreach

Two official documents may look related but belong to different programs or periods.

Mitigation: explicit program/authority/business linkage requirements; otherwise fail closed.

### 34.4 LLM hallucination or extraction drift

The LLM may invent percentages, dates, or conditions.

Mitigation: evidence validation against original source; deterministic final evaluation.

### 34.5 Source volatility

HTML structure, URLs, attachment formats, or public access can change.

Mitigation: operational status separate from semantic state; failures do not imply ENDED.

### 34.6 Review workload remains high

A conservative system may produce many YELLOW/NEEDS_VERIFICATION results.

Mitigation: measure deep-review rate and optimize after safety evidence, not before.

### 34.7 Hidden architecture creep

Source discovery or LLM integration may pressure the implementation into new persistence, dependencies, or API contracts.

Mitigation: this spec does not approve those changes; stop for explicit approval if implementation requires them.

## 35. Design decisions locked by this spec

Phase 2 v1 adopts the following decisions:

1. staged evidence pipeline,
2. Phase 1 GREEN is not a prerequisite,
3. claim-level verification,
4. BenefitState and ReviewClass are separate,
5. detail incompleteness may yield ACTIVE + YELLOW rather than forcing NEEDS_VERIFICATION,
6. existing official URLs are revalidated before discovery fallback,
7. v1 strong-evidence discovery is limited to government/municipality/public institution/official business website,
8. business website qualification requires business name plus at least one additional identity signal,
9. composite official evidence is allowed only with explicit linkage,
10. officiality and currentness are separate,
11. supported v1 source formats are HTML, text-readable PDF, and structured attachments,
12. LLM use is extraction-only and followed by Evidence Validation,
13. final BenefitState/ReviewClass decisions are deterministic,
14. no arbitrary evidence-age expiry threshold,
15. `ENDED` requires explicit ending evidence,
16. unresolved official-source conflict becomes NEEDS_VERIFICATION + RED,
17. Phase 2 remains Shadow Mode with human approval for every production change,
18. the core is designed for all canonical rows, while initial validation focuses on held workload plus positive controls.

## 36. Decisions intentionally deferred to implementation planning or separate approval

This design intentionally does not freeze:

- exact source discovery provider/API,
- exact LLM provider/model,
- exact contract filenames,
- exact PowerShell/module filenames,
- persistent storage format,
- database/schema changes,
- external dependency selection,
- secret-management changes,
- API/auth changes,
- exact team workstream assignment,
- exact numeric confidence thresholds not grounded in verified data,
- production auto-application policy.

These must be decided from the latest `dev`, with separate approval where required.

## 37. Acceptance of the design

This written design is ready to transition to implementation planning only after user review confirms that it accurately captures the agreed Phase 2 scope and safety constraints.

After that approval, the next step is to create the detailed implementation plan with the writing-plans workflow. No implementation should begin before that plan is reviewed and its execution method is selected.

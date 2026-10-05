# Phase 4 P4-3 — OCR Trust Model Redesign 2

Date: 2026-10-06  
Status: DESIGN APPROVED / WRITTEN SPEC REVIEW REQUIRED / IMPLEMENTATION NOT AUTHORIZED  
Base: `dev` at `3f40d5c566568b424c83f539aa6554150e74d14d`

## 1. Purpose

This redesign revisits the trust model for the bounded PDF OCR fallback after the
historical P4-3A and P4-3A2 rejections.

Historical results remain authoritative and unchanged:

- P4-3A: `REJECTED` under the original rule that treated relevant OCR
  word-to-word overlap as unsafe.
- P4-3A2: `P4_3A2_REJECTED`, reason
  `GATE_A_CONFIDENCE_REJECTED`.
- P4-3A2 nevertheless validated useful structural behavior:
  - clear Gray/RGB PSM11 produced usable structural rows at confidence threshold 0;
  - exact word-to-proven-cell containment remained safe;
  - `SAME_CELL_OVERLAP_V1` ratio 0.25 passed the bounded overlap safety controls;
  - PSM3/4/6 physical containment failures remained incomplete;
  - the mild degraded fixture was rejected by structural conflict before any
    confidence-only distinction could be established.

The failed assumption was not that Tesseract was unusable. The failed assumption
was that one mandatory fixed confidence threshold had to separate trustworthy and
untrustworthy OCR while preserving otherwise valid clear evidence.

This redesign therefore changes the acceptance authority from a mandatory global
confidence threshold to structural provenance, deterministic reconstruction, and
required coverage.

## 2. Fixed scope

This redesign deliberately keeps the OCR candidate fixed.

In scope:

- PDF-only OCR fallback;
- the existing image-only `OCR_FALLBACK_CANDIDATE` entry point;
- local/offline execution;
- Tesseract 5.5.3 family already evaluated by P4-3A/P4-3A2;
- official `tessdata_fast/kor.traineddata` already evaluated;
- Korean, OEM 1, DPI 300;
- PSM11 as the positive path;
- PSM3/4/6 as regression controls;
- exactly one clearly mapped full-page embedded scan image per page;
- PdfPig-decoded 8-bit `DeviceGray` or `DeviceRGB`;
- ruled-grid documents only;
- existing exact pixel-grid proof;
- existing exact word-to-cell containment;
- existing `SAME_CELL_OVERLAP_V1` policy with selected ratio 0.25;
- existing downstream PDF evidence contracts.

Out of scope for this redesign:

- alternative OCR engines or models;
- alternative PSM/OEM search;
- cell-crop OCR;
- new OCR preprocessing strategies;
- adaptive geometry tolerances;
- borderless table inference;
- OCR-driven grid movement;
- semantic row inference from OCR reading order;
- new public API contracts;
- DB/auth/schema changes;
- canonical/seed/app automatic writes;
- product binary/model packaging;
- P4-3B implementation.

Any change to those boundaries requires a separately approved redesign.

## 3. Safety invariants

The OCR fallback remains fail-closed and `ProductionAction=NONE`.

Confidence can never:

- create or repair physical cell membership;
- choose between conflicting OCR alternatives;
- deduplicate competing records automatically;
- repair unsafe ordering;
- create missing text;
- infer a table row or column;
- strengthen business binding;
- create semantic `NOT_FOUND`;
- create or strengthen a benefit claim;
- create `GREEN`, `ACTIVE`, or currentness;
- change `PARTIAL` or `FAILED` into `COMPLETE`.

Only a structurally `COMPLETE` OCR document may enter the existing locator.

## 4. Primary trust model

Acceptance authority is ordered as follows:

```text
runtime/model identity
  -> supported image structure
  -> ruled-grid proof
  -> exact word-to-cell provenance
  -> same-cell representation consistency
  -> deterministic cell-text reconstruction
  -> required structural coverage
  -> COMPLETE or PARTIAL/FAILED
```

Confidence remains observed and auditable, but it is not an independent mandatory
acceptance gate in v1 of this redesign.

### 4.1 Runtime and input identity

The OCR runtime, model identity, language, OEM, DPI, PSM role, image eligibility,
and material extraction configuration must be exact and auditable.

A wrong runtime/model identity, malformed OCR output, empty word output, crash,
timeout, nonzero exit, or resource violation is a runtime/trust failure and must
fail closed.

### 4.2 Physical structure authority

The physical structure authority remains:

```text
decoded image pixels -> ruled grid -> proven cell
```

OCR hierarchy does not create table topology.

Every relevant OCR word must be fully contained in exactly one proven cell.
Zero-cell or multi-cell membership is unusable. Cross-cell ambiguity is a hard
provenance failure.

No nearest-cell, centroid, majority, or pixel-tolerance rescue is allowed.

### 4.3 Same-cell representation consistency

Only words that independently have unique membership in the same proven cell may
reach the overlap classifier.

The existing classes remain:

- `SAFE_ADJACENT`: distinct neighboring records whose sequence is deterministic;
- `DUPLICATE`: overlapping records that appear to repeat the same visual region;
- `CONFLICTING`: competing text for the same visual region;
- `ORDERING_UNSAFE`: deterministic reconstruction is not possible.

Only absent overlap or `SAFE_ADJACENT` may remain usable.

`DUPLICATE`, `CONFLICTING`, and `ORDERING_UNSAFE` make the relevant evidence
unsafe. Confidence must never select a winner.

The accepted overlap policy remains `SAME_CELL_OVERLAP_V1`, selected ratio 0.25,
unless a future redesign explicitly changes it.

### 4.4 Deterministic reconstruction

After cell membership and representation consistency pass, text inside each
relevant proven cell must have one deterministic reconstruction.

Tesseract hierarchy may support within-cell ordering only after physical cell
membership is proven.

It must not:

- create rows or columns;
- move words between cells;
- repair grid failures;
- choose conflicting alternatives.

If one deterministic cell text cannot be reconstructed, the result is incomplete.

### 4.5 Required structural coverage

The OCR layer must prove the required structural coverage needed to construct the
bounded technical row representation.

Missing required headers, missing required relevant fields, empty relevant cells,
or otherwise incomplete required coverage produces `PARTIAL`.

The OCR layer does not invent missing values.

## 5. Confidence policy

P4-3A2 showed that a mandatory global confidence threshold is not a reliable
acceptance axis for this bounded candidate:

- clear Gray/RGB was structurally usable at threshold 0;
- the clear controls became incomplete at threshold 50 and above;
- the mild degraded control was already structurally unsafe because of
  `CONFLICTING` overlaps at threshold 0.

Therefore no fixed confidence threshold is selected by this redesign.

### 5.1 Role in v1

Raw Tesseract confidence is preserved as diagnostic evidence.

It may corroborate an independently detected structural or coverage problem, but
it has no independent authority to change adapter completeness in this v1.

In particular:

```text
structural/coverage PASS + low confidence only
-> remains eligible for COMPLETE
-> record confidence diagnostics
```

and:

```text
structural/coverage failure
-> PARTIAL or FAILED by the independent failure
-> confidence may be recorded as supporting diagnostic evidence
```

This prevents a return to an arbitrary global threshold while retaining the raw
signal for audit, future analysis, and reproducibility.

### 5.2 Explicit prohibitions

Do not introduce:

- per-word hard confidence thresholds;
- average-cell confidence thresholds;
- expected-text matching to rescue or reject OCR;
- adaptive confidence thresholds by business or document;
- confidence-based selection among duplicate/conflicting words.

A future design may give confidence independent rejection authority only after a
separate bounded proof and approval.

## 6. Product-side trust boundary

The intended future flow remains:

```text
PDF bytes
 -> supported full-page image
 -> ruled-grid proof
 -> Tesseract words
 -> exact word-to-cell containment
 -> same-cell overlap classification
 -> deterministic cell text reconstruction
 -> required structural coverage
 -> OCR document COMPLETE
 -> existing PDF_ROW
 -> existing locator
 -> existing binding
 -> SCOPED_PDF_CELL
 -> existing validation
```

Public downstream contracts remain unchanged:

- `PDF_ROW`
- `UnitReference`
- `PhysicalPath`
- `FieldReference`
- `SourceText`
- `SCOPED_PDF_CELL`

The OCR layer proves only:

> a string was deterministically reconstructed from a specific proven physical
> PDF cell within the supported OCR boundary.

It does not prove:

- business identity;
- current business existence;
- benefit truth;
- current benefit validity;
- `GREEN`;
- `ACTIVE`;
- lifecycle state.

## 7. Status semantics

Existing adapter statuses remain sufficient.

### `UNSUPPORTED`

Use when the input is outside the bounded capability, such as unsupported image
mapping, color/depth/layout, borderless structure, or other excluded PDF forms.

### `FAILED`

Use for runtime/trust-chain failures, including:

- wrong runtime/model identity;
- OCR crash or nonzero exit;
- timeout/resource violation;
- malformed or oversized OCR output;
- empty word output;
- cleanup-critical runtime failure.

### `PARTIAL`

Use when the supported execution path runs but safe evidence reconstruction cannot
be proven, including:

- cross-cell ambiguity;
- uncontained relevant words;
- duplicate overlap;
- conflicting overlap;
- ordering-unsafe overlap;
- non-deterministic cell reconstruction;
- required structural coverage missing.

### `COMPLETE`

Allowed only when all mandatory structural trust conditions pass:

1. runtime/model identity is valid;
2. image structure is supported;
3. ruled-grid proof succeeds;
4. every relevant word has unique proven-cell membership;
5. all relevant overlaps are absent or `SAFE_ADJACENT`;
6. no duplicate/conflicting/ordering ambiguity remains;
7. deterministic cell-text reconstruction succeeds;
8. required structural coverage is complete;
9. no runtime/trust failure occurred.

Raw confidence values are not an additional mandatory PASS condition.

Only `COMPLETE` may enter the existing locator. `PARTIAL`, `FAILED`, and
`UNSUPPORTED` must not produce semantic absence or benefit claims.

## 8. Diagnostics and execution identity

The evaluation and future implementation must preserve sufficient evidence to
audit each accepted or rejected OCR word.

At minimum, diagnostics should preserve conceptually equivalent fields for:

- OCR text;
- raw bounding box;
- Tesseract hierarchy/order;
- raw confidence;
- proven-cell membership;
- overlap class;
- accepted/rejected reason;
- reconstructed cell text.

Exact internal names remain an implementation-plan decision.

The future material execution/extraction identity must include:

- exact Tesseract build/version;
- exact Korean model source/version/hash;
- language/OEM/DPI/PSM role;
- supported image eligibility version;
- pixel-grid configuration/version;
- exact-containment policy version;
- `SAME_CELL_OVERLAP_V1`;
- structural coverage policy version;
- trust-model version for this redesign.

Confidence is still part of raw OCR evidence even though it is not an independent
acceptance gate.

## 9. Revised evaluation

The next technical evaluation must reuse the existing fixed OCR candidate and
historical fixtures where possible. It must not reopen engine/model/config search.

### Gate A — Structural Trust

Central question:

> Can structurally safe OCR become usable evidence while structural and coverage
> failures remain fail-closed without relying on a mandatory confidence threshold?

Required positive evidence:

- clear Gray PSM11 -> `COMPLETE`;
- clear RGB PSM11 -> `COMPLETE`;
- usable technical rows > 0;
- all relevant positive words have unique proven-cell membership;
- overlap is absent or `SAFE_ADJACENT`;
- deterministic reconstruction succeeds;
- required structural coverage succeeds;
- low confidence alone does not make the positive incomplete.

Required negative evidence:

- cross-cell ambiguity -> `PARTIAL`;
- duplicate -> `PARTIAL`;
- conflicting overlap -> `PARTIAL`;
- ordering unsafe -> `PARTIAL`;
- missing required coverage -> `PARTIAL`;
- empty word output -> `FAILED`;
- the existing mild Gray fixture remains `PARTIAL` because of its recorded
  `CONFLICTING` overlaps;
- PSM3/4/6 physical containment failures remain incomplete and are never rescued.

Any structural-safety regression rejects the candidate.

### Gate B — Business Isolation

Only after Gate A passes:

```text
Business A lookup -> A row only
Business B lookup -> B row only
cross-business leakage = 0
```

OCR `COMPLETE` does not imply business-binding success.

Incomplete OCR observations must never become semantic `NOT_FOUND`, absence,
currentness, or benefit claims.

Any cross-business leakage is a hard rejection.

### Gate C — Operational Safety

Only after Gates A-B pass, validate:

- PDF open = 1;
- bounded image decode;
- grid build = 1;
- Tesseract invocation <= 1 per document run;
- multiple business lookups reuse one OCR/index result;
- timeout/crash/nonzero exit fail closed;
- malformed or oversized output fails closed;
- wrong runtime/model identity fails closed;
- bounded pixel/grid work;
- temp cleanup;
- no hard-memory guarantee without an actual enforcement mechanism.

Failure blocks dependency review.

### Gate D — Multi-page Scope

Multi-page remains a scope gate.

If proven safely:

- `MULTIPAGE_APPROVED`.

If not proven:

- `MULTIPAGE_NOT_APPROVED`.

A safe single-page core may still receive a conditional result if all mandatory
single-page safety gates pass. No per-page/business OCR workaround may be added
merely to rescue this gate.

### Gate E — Windows/Ubuntu Determinism

Compare at least:

- OCR word set/count where material;
- bounding boxes where material;
- unique cell membership;
- overlap classification;
- accepted/rejected word set;
- reconstructed cell text;
- reconstructed technical rows;
- final adapter status.

Classification:

- Level A: semantically identical -> PASS;
- Level B: only non-semantic diagnostic variance, including confidence variance,
  while structural assignment, reconstructed text, rows, and final status remain
  identical -> PASS;
- Level C: semantic/structural/text/status difference -> REJECT.

Confidence variance alone is not a determinism failure because confidence has no
independent acceptance authority in this redesign.

## 10. Evaluation result states

The revised evaluation must end in exactly one of:

### `P4_3_REDESIGN2_APPROVED_FOR_DEPENDENCY_REVIEW`

All mandatory gates pass and no unresolved core safety issue remains.

This authorizes dependency review only, not product implementation.

### `P4_3_REDESIGN2_CONDITIONALLY_APPROVED`

Core single-page safety passes but a bounded optional scope restriction remains,
such as multi-page not approved.

This also authorizes only bounded dependency review.

### `P4_3_REDESIGN2_REJECTED`

Any mandatory structural provenance, reconstruction, coverage, business
isolation, operational fail-closed, or cross-platform determinism gate fails.

There is no rejection path based solely on raw confidence.

## 11. Product dependency review

Even an approved technical evaluation does not approve Tesseract/model packaging
as a product dependency.

Before P4-3B, report and review at least:

- exact Tesseract build;
- exact runtime/DLL supply;
- exact Korean model source/version/hash;
- licensing;
- Windows/Ubuntu reproducibility;
- runtime footprint;
- execution/trust-model identity;
- resource bounds;
- supported and unsupported cases;
- multi-page status;
- determinism classification.

The user must explicitly approve the exact product dependency.

Before that approval:

- no product binary/model packaging;
- no production OCR adapter;
- no P4-3B implementation.

## 12. P4-3B entry gate

P4-3B requires all of:

1. this written redesign spec reviewed and approved;
2. revised technical evaluation completed with an implementable result;
3. exact product dependency explicitly approved;
4. a separate P4-3B implementation plan reviewed and approved.

Only then may product implementation begin.

## 13. Historical preservation

This redesign does not rewrite prior evidence.

The repository must continue to preserve:

- P4-3A `REJECTED`;
- P4-3A2 `P4_3A2_REJECTED / GATE_A_CONFIDENCE_REJECTED`;
- the P4-3A2 fixed matrix and rejection handover;
- historical test/evaluation artifacts as evidence.

The new trust model applies only to the new redesign/evaluation cycle.

## 14. Completion boundary

P4-3 remains incomplete until the revised evaluation, dependency gate, P4-3B
implementation, integration tests, CI, review, and closeout all succeed.

Phase 4 remains incomplete until P4-3 and the later Phase 4 integration/closeout
work are completed.

Until then:

- product dependency = `NOT_APPROVED`;
- P4-3B = `BLOCKED`;
- `ProductionAction=NONE`;
- no canonical/seed/apps automatic writes.

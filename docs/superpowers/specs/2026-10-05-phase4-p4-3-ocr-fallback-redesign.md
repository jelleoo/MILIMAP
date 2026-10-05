# Phase 4 P4-3 — PDF OCR Fallback Redesign

Date: 2026-10-05  
Status: APPROVED REDESIGN / IMPLEMENTATION NOT AUTHORIZED  
Base: `dev` at `4a688a8ca4d67a7b1217b62eced06d770a6db8ac`

## 1. Why this redesign exists

The original P4-3 design treated any relevant OCR word-box overlap as unsafe. P4-3A correctly rejected that design under its approved rules:

- Windows portable Tesseract supply: PASS
- exact runtime/model identity: PASS
- offline Korean OCR: PASS
- clear Gray/RGB matrix: 16 OCR runs, 80 threshold evaluations
- usable positive controls: 0
- final P4-3A verdict: `REJECTED`
- product dependency: `NOT_APPROVED`
- P4-3B: `BLOCKED`

The decisive observation was that PSM 11 produced Korean words that were each fully contained inside the same proven physical cell, while neighboring word boxes overlapped each other by one pixel. This is not the same condition as a word crossing a cell boundary or belonging ambiguously to multiple cells.

The redesign therefore separates **physical cell provenance** from **same-cell OCR representation overlap**.

The historical P4-3A result remains unchanged and authoritative for the old overlap policy.

## 2. Safety invariants that do not change

P4-3 remains:

- PDF-only
- entered only from the existing image-only `OCR_FALLBACK_CANDIDATE`
- local/offline
- based on PdfPig single-open image handoff
- limited to safely decoded full-page scan images
- ruled-grid only
- fail-closed
- `ProductionAction=NONE`

Still forbidden:

- OCR fallback after `PDF_GRID_UNSUPPORTED`, `PARTIAL`, or `FAILED`
- cloud OCR
- borderless-table inference
- reading-order row inference
- nearest/centroid/majority-cell assignment
- OCR-driven grid movement
- adaptive tolerance widening
- confidence overriding physical ambiguity
- automatic lifecycle/currentness/benefit truth
- canonical/seed/apps writes
- DB/auth/API/persistent-schema changes
- P4-3B implementation before the new evaluation and dependency approval gates

## 3. Revised provenance model

Every OCR word is evaluated against the proven pixel grid **before** any word-to-word overlap logic.

For each word bbox:

1. Fully contained in exactly one proven cell:
   - `CellMembership = UNIQUE`
   - eligible for same-cell overlap validation.
2. Fully contained in zero proven cells:
   - unusable.
3. Belongs to, crosses, or overlaps more than one cell so that cell membership is not unique:
   - hard reject.

No pixel allowance is introduced at the cell boundary. “One pixel” is not a safety rule.

The key distinction is:

```text
cross-cell ambiguity
= physical provenance failure
= HARD REJECT
```

versus:

```text
same-cell word overlap
= OCR representation/duplication question
= classify separately
```

## 4. Same-cell overlap classes

Only pairs of words that are both independently proven to belong to the same single cell reach this classifier.

### SAFE_ADJACENT

A same-cell overlap may remain usable when the words represent distinct adjacent text and their sequence can be reconstructed deterministically.

Required properties:

- both words have unique membership in the same proven cell;
- they are distinct OCR records;
- hierarchy/order is internally consistent;
- physical text order is deterministic;
- they do not represent the same visual region twice;
- they do not contain conflicting alternatives for the same region.

A `SAFE_ADJACENT` event is audit information, not a completeness failure.

### DUPLICATE

If two OCR records appear to represent the same visual text region redundantly, the cell is unsafe.

P4-3 v1 does not auto-deduplicate by choosing one record.

### CONFLICTING

If overlapping records compete for the same visual region with different text, the cell is unsafe.

Confidence must not choose the winner.

### ORDERING_UNSAFE

If hierarchy and physical ordering cannot produce one deterministic cell text sequence, the cell is unsafe.

## 5. OCR hierarchy usage

Tesseract fields such as block/paragraph/line/word order may be used only after cell membership is proven.

Allowed use:

- verify within-cell ordering;
- detect duplicates/conflicts;
- reconstruct text inside one proven cell.

Forbidden use:

- create table rows;
- infer table columns;
- override the pixel grid;
- rescue cross-cell ambiguity.

The physical structure authority remains:

```text
decoded pixels -> ruled grid -> proven cell
```

## 6. Confidence policy

Confidence remains reject-only.

It may reject text that is not trustworthy enough, but it must never:

- make cell membership safe;
- turn duplicate/conflicting overlap into safe text;
- strengthen binding;
- create `GREEN`, `ACTIVE`, or currentness;
- increase provenance strength.

The redesigned evaluation must include a control where the grid remains safe while text quality is degraded, so OCR confidence can be measured independently of grid failure.

No production confidence threshold is selected by this design.

## 7. Product-side data flow

The intended future flow is:

```text
PDF bytes
 -> PdfPig single-open
 -> supported full-page decoded image
 -> pixel ruled-grid proof
 -> Tesseract words
 -> exact word-to-cell containment
 -> same-cell overlap classification
 -> accepted deterministic word sequence
 -> cell SourceText
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

No OCR-specific BenefitState, locator, or evaluator is introduced.

## 8. Status semantics

Existing adapter statuses remain sufficient.

### UNSUPPORTED

Input or structure is outside the bounded OCR capability.

### FAILED

Runtime/trust failure, such as wrong engine/model identity, crash, timeout, malformed output, or resource violation.

### PARTIAL

The supported path ran but relevant evidence safety cannot be proven.

Examples include:

- cross-cell ambiguity;
- duplicate overlap;
- conflicting overlap;
- ordering-unsafe overlap;
- low-confidence relevant text;
- incomplete relevant coverage.

A `PARTIAL` observation cannot produce semantic `LOCATED`, `NOT_FOUND`, or claims.

### COMPLETE

Allowed only when:

- grid/header/relevant coverage are safe;
- every relevant word has unique cell membership;
- same-cell overlaps are absent or classified `SAFE_ADJACENT`;
- confidence gate passes;
- provenance validation passes.

Only `COMPLETE` may enter the existing locator.

## 9. Diagnostics

The implementation may use internal diagnostics conceptually equivalent to:

- `OCR_WORD_CELL_UNCONTAINED`
- `OCR_WORD_CELL_AMBIGUOUS`
- `OCR_SAME_CELL_ADJACENT_OVERLAP`
- `OCR_SAME_CELL_DUPLICATE_OVERLAP`
- `OCR_SAME_CELL_CONFLICTING_OVERLAP`
- `OCR_SAME_CELL_ORDERING_UNSAFE`

Exact names are an implementation-plan decision.

`SAFE_ADJACENT` must remain auditable even though it does not lower completeness.

## 10. Execution/config identity

The old evaluation semantics must not be confused with the redesigned semantics.

The future execution/extraction identity must include a new overlap-policy/config version, for example:

- `OCR_CONFIG_V2`, or
- an explicit `SAME_CELL_OVERLAP_V1` policy identifier.

Engine version, model hash, OCR material config, pixel-grid config, image-eligibility config, and overlap-policy version must all participate in the future identity.

## 11. P4-3A2 purpose

P4-3A2 is a new technical evaluation. It does not rewrite P4-3A history.

Its central question is:

> Can same-cell OCR word overlap be accepted safely when physical cell membership remains unique, while cross-cell ambiguity, duplicate/conflicting overlap, ordering ambiguity, and low-confidence relevant text remain fail-closed?

P4-3A2 is not a general OCR-engine search.

Primary candidate remains the previously observed exact Tesseract family/config, with PSM 11 as the positive path because it showed zero containment failures in the old matrix.

PSM 3/4/6 remain safety regression controls.

## 12. P4-3A2 Gate A — revised acceptance proof

Required positive evidence:

- Gray/RGB ruled-grid controls;
- PSM 11;
- usable positive row(s) greater than zero;
- acceptance caused only by unique cell membership plus safe-adjacent overlap handling.

Required negatives:

- cross-cell ambiguity rejects;
- duplicate overlap rejects;
- conflicting overlap rejects;
- ordering conflict rejects;
- low-confidence relevant text rejects.

If no usable positive survives, result is `P4_3A2_REJECTED` and later gates stop.

## 13. P4-3A2 Gate B — safety regression

PSM 3/4/6 old containment failures must remain incomplete.

The new same-cell policy must not rescue physical provenance failures.

Deterministic synthetic controls must also keep duplicate/conflict/ordering/cross-cell cases rejected.

Any safety regression means `P4_3A2_REJECTED`.

## 14. P4-3A2 Gate C — business isolation

Once usable rows exist:

```text
Business A lookup -> A row only
Business B lookup -> B row only
cross-business leakage = 0
```

Leakage greater than zero is a hard rejection.

Incomplete observations must still never become semantic absence or claims.

## 15. P4-3A2 Gate D — operational safety

After Gates A-C pass, evaluate the previously blocked operational requirements:

- PdfPig open = 1;
- bounded image decode;
- grid build = 1;
- Tesseract invocation <= 1 per document/run;
- multiple business lookups reuse one OCR/index result;
- timeout/crash/nonzero exit fail closed;
- malformed/oversized output fail closed;
- wrong engine/model identity fail closed;
- oversized pixel/grid work fail closed;
- temp cleanup;
- no hard-memory claim without an actual mechanism.

Failure blocks approval for dependency review.

## 16. P4-3A2 Gate E — multi-page

Multi-page is a scope gate, not necessarily a whole-candidate blocker.

If proven safely:

- `MULTIPAGE_APPROVED`

If not:

- `MULTIPAGE_NOT_APPROVED`
- future P4-3B v1 may be single-page only, provided all mandatory single-page gates pass.

No per-page/business OCR fallback is introduced just to rescue this gate.

## 17. P4-3A2 Gate F — Windows/Ubuntu determinism

Compare:

- unique cell membership;
- overlap classification;
- accepted/rejected words;
- cell assignment;
- normalized cell text;
- final evaluation row;
- final status.

Classification:

- Level A: pass;
- Level B: only non-semantic variance with proven acceptance margin: pass;
- Level C: semantic difference: reject.

Level C is a hard blocker.

## 18. P4-3A2 final result

Exactly one:

### `P4_3A2_APPROVED_FOR_DEPENDENCY_REVIEW`

All mandatory gates pass. This means only that product dependency review may begin.

### `P4_3A2_CONDITIONALLY_APPROVED`

Core safety is proven, but a bounded scope restriction remains, such as multi-page not approved.

Unresolved core safety cannot use this status.

### `P4_3A2_REJECTED`

Any core provenance, isolation, operational fail-closed, confidence, or cross-platform determinism gate fails.

## 19. Product dependency gate

Even `APPROVED_FOR_DEPENDENCY_REVIEW` does not approve a product dependency.

Before P4-3B, report at least:

- exact Tesseract build;
- runtime supply method;
- required DLL/runtime set;
- exact model source/version/hash;
- licensing findings;
- Windows/Ubuntu reproducibility;
- runtime footprint;
- material OCR config;
- overlap-policy/config identity;
- resource bounds;
- unsupported cases;
- multi-page status;
- determinism classification.

The user must explicitly approve the exact product dependency.

Before that approval:

- no product binary/model packaging;
- no production OCR adapter;
- no P4-3B implementation.

## 20. P4-3B entry gate

P4-3B requires all of:

1. this redesign spec approved;
2. P4-3A2 completed with an implementable result;
3. explicit product dependency approval;
4. separate P4-3B implementation plan approved.

Only then may product implementation begin.

## 21. P4-3 completion

P4-3 becomes complete only after:

- historical P4-3A rejection remains preserved;
- P4-3A2 closes;
- product dependency is explicitly approved if implementation proceeds;
- P4-3B implementation and regression pass;
- exact-head CI passes;
- whole-branch review has Critical 0 / Important 0;
- protected-path diff is zero;
- handover/current-work accurately reflect the result.

Phase 4 still requires P4-4 Integration/Closeout afterward.

## 22. Expected phase state after this redesign

```text
Phase 4 Multi-source Adapters
  P4-0 Foundation                    COMPLETE
  P4-1 HWPX Generic Adapter         COMPLETE
  P4-2 PDF Native Adapter           COMPLETE
  P4-3 OCR Fallback
       original P4-3 design         superseded for overlap semantics
       P4-3A                         REJECTED (historical, preserved)
       P4-3 redesign                 APPROVED
       P4-3A2                        NEXT
       product dependency            NOT_APPROVED
       P4-3B                         BLOCKED
  P4-4 Integration/Closeout         LATER
```

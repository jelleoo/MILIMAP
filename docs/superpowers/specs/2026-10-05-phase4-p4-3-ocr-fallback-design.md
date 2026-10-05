# Phase 4 P4-3 — PDF OCR Fallback Design

Date: 2026-10-05
Status: APPROVED DESIGN / IMPLEMENTATION NOT AUTHORIZED
Base: `dev` at `170285cf3e9860dd0c113306300712996bb6c8f8`

## 1. Problem

P4-2 provides a bounded native PDF adapter for digital text with explicit ruled-grid geometry. It intentionally leaves image-only PDFs unsupported and emits `OCR_FALLBACK_CANDIDATE` when no usable native text exists.

P4-3 must add a bounded fallback path for a narrow class of scanned PDFs without weakening the existing Phase 4 safety model:

- preserve exact source snapshot identity and physical provenance,
- keep business isolation and fail-closed behavior,
- never use OCR confidence as semantic truth,
- avoid business-by-business OCR work,
- avoid a second PDF parser/cache architecture,
- introduce no product OCR dependency until a separate technical evaluation passes and the dependency is explicitly approved.

This design does not authorize product implementation.

## 2. Scope decision

P4-3 is **PDF-only**.

Included:

- PDF sources already recognized by the existing Phase 4 document path,
- only the explicit P4-2 `OCR_FALLBACK_CANDIDATE` branch,
- local/offline OCR only,
- Tesseract `5.5.3` plus an official Korean `kor.traineddata` model as the **P4-3A evaluation candidate**,
- PdfPig `0.1.16` embedded-image extraction,
- one clearly mapped full-page scan image per PDF page,
- PdfPig-decoded 8-bit `DeviceGray` or `DeviceRGB` pixels only,
- scanned tables with explicit ruled-grid boundaries,
- reuse of the existing `PDF_ROW`, locator, binding, extraction and validation contracts.

Excluded:

- HWPX embedded-image OCR,
- cloud OCR,
- multiple-image page inference,
- partial-page image inference,
- OCR retry after `PDF_GRID_UNSUPPORTED`, `PARTIAL` or `FAILED`,
- borderless table inference,
- reading-order row inference,
- semantic merged-cell reconstruction,
- cross-page row stitching,
- a separate PDF rasterizer,
- JPEG/JPX/JBIG2 or complex color-space decoding extensions,
- OCR-driven lifecycle/currentness decisions,
- OCR incremental reuse,
- canonical/seed/apps writes,
- DB, API, auth or data-schema changes.

## 3. Delivery split

P4-3 is split into two independently gated work items.

### P4-3A — OCR Technical Evaluation

Purpose:

- prove or reject technical feasibility,
- measure deterministic behavior and resource costs,
- verify cross-platform runtime/model supply,
- produce a dependency decision.

P4-3A does **not** add a production OCR adapter or product runtime dependency.

Final P4-3A result must be exactly one of:

- `APPROVED`
- `CONDITIONALLY_APPROVED`
- `REJECTED`

### P4-3B — Product implementation

P4-3B may begin only after:

1. P4-3A completes,
2. the evaluation result is reviewed,
3. the user explicitly approves the product Tesseract dependency,
4. a separate implementation plan is written and approved.

## 4. Runtime architecture

The intended product flow is:

```text
official PDF bytes
        |
        v
existing P4-2 PdfPig native parse
        |
        +-- native safe ruled-grid --> existing native PDF_ROW path
        |
        +-- PARTIAL / FAILED / PDF_GRID_UNSUPPORTED --> stop, no OCR
        |
        +-- OCR_FALLBACK_CANDIDATE
                |
                v
        OCR eligibility gate
                |
                v
 single clearly mapped full-page embedded scan image
                |
                v
 8-bit DeviceGray / DeviceRGB decoded pixels
                |
                v
       pixel ruled-grid proof
                |
                v
       Tesseract OCR once
                |
                v
 TSV bbox + text + confidence
                |
                v
 bbox must belong to exactly one proven cell
                |
                v
      shared semantic header map
                |
                v
             PDF_ROW
                |
                v
 existing locator -> binding -> SCOPED_PDF_CELL -> validation
```

No OCR-specific BenefitState, locator or evaluator is introduced.

## 5. OCR fallback trigger

OCR is eligible only when the existing native adapter returns the explicit image-only fallback signal:

```text
native letters = 0
AND native adapter diagnostic = OCR_FALLBACK_CANDIDATE
```

OCR is not used to bypass or reinterpret native uncertainty.

No OCR fallback for:

- `PDF_GRID_UNSUPPORTED`
- `PARTIAL`
- `FAILED`
- native-safe `COMPLETE`

A native-safe document must always execute OCR zero times.

## 6. Embedded-image eligibility

P4-3 v1 accepts only a deliberately narrow image shape.

Required:

- exactly one candidate scan image on the page,
- image placement maps unambiguously to the page,
- the image represents the full-page scan according to fixed rules,
- PdfPig exposes decoded pixels without another image decoder,
- 8-bit `DeviceGray` or 8-bit `DeviceRGB`,
- coordinate transform from image pixels to PDF page coordinates is deterministic.

Rejected as unsupported:

- multiple candidate images,
- partial-page image composition,
- unsupported bit depth,
- unsupported/complex color space,
- unsupported filters or undecodable pixels,
- masks/transparency that make physical text/grid meaning ambiguous,
- ambiguous placement/transform.

The exact full-page coverage tolerance is **not preselected**. P4-3A must measure and justify a fixed value before P4-3B.

## 7. Single-open PdfPig handoff

P4-3 must preserve the Phase 4 work-count goal: native parse once.

The existing PdfPig child process should be extended, if P4-3A proves this feasible, so a single PDF open can produce:

- the existing native letters/paths projection,
- image metadata needed for OCR eligibility,
- bounded decoded pixel handoff for eligible pages.

The design must not become:

```text
PdfPig parse #1 -> native
PdfPig parse #2 -> image extraction
```

Decoded image data must not be emitted as unbounded JSON/base64.

The intended handoff is a bounded temporary grayscale/RGB image artifact, owned by the parent run and deleted on success or failure. It is not a History Store artifact and is not canonical evidence by itself.

P4-3A must explicitly prove or reject this single-open handoff.

## 8. Pixel ruled-grid safety

OCR text does not define the table structure.

The adapter must first prove a physical pixel grid from visible ruled lines:

```text
decoded pixels
 -> horizontal / vertical ruled-line detection
 -> deterministic snapping
 -> closed rectangular cell topology
 -> semantic header mapping
```

Allowed:

- fixed, versioned thresholds,
- deterministic horizontal/vertical line detection,
- closed rectangular cells,
- component-isolated page-local tables.

Forbidden:

- text alignment as a column boundary,
- whitespace as an inferred border,
- nearest-cell assignment,
- Tesseract reading-order rows,
- adaptive tolerance widening,
- borderless-table heuristics.

All grid thresholds remain evaluation outputs until P4-3A provides evidence. Accepted values must later be frozen into `OCR_CONFIG_V1` and its extraction/config identity.

## 9. OCR bbox containment

Tesseract output is accepted only after physical containment validation.

For each OCR word box:

- contained in zero proven cells -> unusable,
- contained in exactly one proven cell -> eligible,
- overlaps or belongs to more than one cell -> ambiguous/unusable.

Centroid-only assignment is forbidden.

OCR word ordering is permitted only **inside an already proven cell**, using a fixed deterministic line grouping and top-to-bottom / left-to-right ordering policy.

OCR ordering must never create table rows or columns.

## 10. Confidence policy

OCR confidence is a **reject-only safety signal**.

It may be used to reject a relevant word/cell/row. It must never:

- create or strengthen `STRONG` binding,
- create `GREEN`,
- create `ACTIVE`,
- establish currentness,
- increase provenance strength,
- override identity conflicts.

The existing public document field reference contract remains:

```text
FieldReference
PhysicalReference
SourceText
```

OCR bbox and confidence remain internal validation/diagnostic material.

The exact confidence threshold and aggregation policy are not preselected. P4-3A must determine whether a stable safe threshold exists using Korean controls. If no safe threshold can be justified, the candidate must not be marked `APPROVED`.

## 11. Existing provenance contract

P4-3 reuses the current PDF physical record shape.

Example:

```text
PDF_PAGE_1_TABLE_1_ROW_2
page/1/table/1/row/2
page/1/table/1/row/2/cell/2
```

Expected OCR adapter identity, subject to implementation naming review:

```text
AdapterId        = PDF_OCR_GRID
AdapterVersion   = 1
ExtractionMethod = STRUCTURED_PDF_OCR_ROW
ExtractorId      = TESSERACT
ExtractorVersion = 5.5.3
```

The same downstream path remains:

```text
PDF_ROW
 -> locator
 -> business binding
 -> RelevantEvidenceSlice
 -> SCOPED_PDF_CELL
 -> benefit claim validation
```

The adapter must preserve a verifiable chain from:

```text
PDF bytes
 -> embedded image
 -> image placement
 -> decoded pixels
 -> pixel grid
 -> OCR word bbox
 -> proven cell
 -> PDF_ROW
```

Changes to snapshot, page/image identity, table/row/cell position, source text, OCR engine identity, Korean model identity or material OCR configuration must invalidate reuse/trust.

## 12. Relevant unsafe structure

A safe row does not make the document complete if another relevant structure is unsafe.

Examples that force incomplete status include:

- another relevant table with unsafe cell boundaries,
- identity-bearing mapped cells with low-confidence OCR,
- relevant OCR bbox crossing cell boundaries,
- relevant duplicated/overlapping OCR text,
- an identity-bearing row whose physical completeness cannot be established.

Partial safe units may be retained for audit, but incomplete observations must not feed semantic location or claim extraction.

## 13. Adapter status mapping

### UNSUPPORTED

Use when the input is outside the bounded v1 capability.

Examples:

- multiple/partial images,
- unsupported pixels/color space,
- image decoding unavailable,
- no safe ruled grid,
- no safe semantic BusinessName header,
- unsupported full-page transform.

Required outcome:

- no semantic `LOCATED`,
- no semantic `NOT_FOUND`,
- no claims.

### FAILED

Use when the input is eligible in principle but runtime/trust fails.

Examples:

- Tesseract missing/crash,
- timeout,
- wrong engine identity,
- wrong/missing model,
- model hash mismatch,
- malformed TSV,
- resource-bound violation,
- unexpected helper failure.

Required outcome:

- no semantic `LOCATED`,
- no semantic `NOT_FOUND`,
- no claims.

### PARTIAL

Use when OCR/grid processing succeeded in part but complete relevant coverage cannot be proven.

Examples:

- safe rows plus another unsafe relevant row,
- low-confidence relevant identity/benefit cell,
- ambiguous relevant OCR containment.

Required outcome:

- audit-only safe units may exist,
- no semantic `LOCATED` or `NOT_FOUND`,
- no claim extraction.

### COMPLETE

Allowed only when:

- image type/placement is supported,
- ruled-grid topology is safe,
- semantic header is safe,
- all relevant rows are structurally accounted for,
- OCR containment is safe,
- confidence gate passes,
- provenance/index validation succeeds.

Only `COMPLETE` may flow into the existing locator, where `LOCATED`, `AMBIGUOUS` or `NOT_FOUND` may then be produced.

`NOT_FOUND` is evidence of safe complete coverage plus no business match. It must never mean “OCR failed to read the business.”

## 14. Run-local reuse

No new OCR cache framework is introduced.

Existing run-local source/snapshot/template reuse remains authoritative.

Target work counts for a shared OCR-eligible PDF:

```text
external fetch      = 1
snapshot            = 1
PdfPig open/parse   = 1
OCR eligibility     = 1
Tesseract invocation <= 1
OCR index build     = 1
business lookup     = N
```

Native-safe target:

```text
PdfPig open/parse   = 1
Tesseract invocation = 0
```

Incomplete OCR results must also be cached within the run so every business lookup does not rerun OCR.

The intended OCR template identity includes at least:

- exact snapshot identity,
- OCR adapter/version,
- PdfPig `0.1.16`,
- Tesseract engine identity,
- Korean model SHA-256,
- material OCR config hash,
- material pixel-grid config hash.

No PDF/HWPX POST_FETCH incremental reuse is added in P4-3.

## 15. Instrumentation

P4-3B must make native-vs-OCR work observable.

At minimum the run must allow tests to prove equivalent metrics to:

- PDF native parse count,
- PDF OCR invocation count,
- PDF OCR reuse count.

Exact property names are implementation-plan details.

Required proofs:

- native-safe PDF: OCR invocation = 0,
- OCR candidate shared by multiple business lookups: OCR invocation = 1,
- subsequent business lookups reuse the same read-only OCR/index result,
- cross-business leakage = 0.

## 16. Process isolation and resource safety

PdfPig and Tesseract remain separate child-process safety boundaries.

```text
PowerShell parent
  +-- PdfPig child
  +-- Tesseract child
```

Tesseract runtime must be guarded by:

- wall deadline,
- kill-process-tree behavior,
- bounded stdout/stderr,
- bounded TSV output,
- bounded temporary directory,
- cleanup on success/failure,
- exit-code validation,
- exact engine identity validation,
- exact Korean model identity/hash validation.

P4-3A must measure candidate limits for:

- pixel width/height,
- total decoded pixels,
- decoded image bytes,
- pages,
- grid work,
- cells,
- TSV rows/bytes,
- OCR wall time,
- temp disk usage,
- observed working set.

No hard memory ceiling may be claimed unless actually implemented and demonstrated.

## 17. Multi-page policy

P4-3A may evaluate whether multiple eligible full-page scan images can be sent through one bounded Tesseract invocation while preserving exact page mapping.

P4-3A must prove:

- deterministic input order,
- deterministic mapping from OCR output page to original PDF page,
- safe failure behavior,
- Windows/Linux compatibility,
- one OCR process for the document.

If this cannot be proven, P4-3B v1 must be reduced to single-page OCR-eligible PDFs. Multi-page support is not assumed by this design.

## 18. Runtime/model supply policy

Tesseract `5.5.3` and official `kor.traineddata` are evaluation candidates only.

P4-3A must verify:

- exact engine version on Windows and Ubuntu,
- repeatable acquisition/install procedure,
- engine/runtime license,
- model source and SHA-256,
- model license/provenance,
- offline execution after setup,
- operational complexity,
- binary/model footprint.

P4-3A must not commit Tesseract binaries or traineddata into the product repository merely to force reproducibility.

If exact cross-platform supply cannot be made acceptably reproducible, the dependency must be `CONDITIONALLY_APPROVED` or `REJECTED`, not silently normalized to whatever package-manager version is available.

## 19. P4-3A fixture provenance

Primary technical evaluation uses synthetic data, not real benefit truth.

Synthetic fixtures must use clearly fictional businesses/benefits and must not enter canonical/seed data.

For each fixture record:

- purpose,
- generator/version,
- PDF SHA-256,
- expected image shape,
- expected table topology,
- expected accepted/rejected rows,
- license.

Prefer reproducible generator source plus committed deterministic fixture bytes/hashes where practical.

Any existing ReportLab/PIL tooling is fixture-authoring infrastructure only, not a product/runtime dependency.

## 20. P4-3A minimum positive controls

At minimum:

- 8-bit DeviceGray full-page Korean ruled-grid scan,
- 8-bit DeviceRGB equivalent,
- two-business table,
- multiline cell,
- clear vs intentionally degraded confidence control,
- OCR bbox near/crossing a cell boundary,
- evaluation-only multi-page control.

Controls should include Korean business-name/address/phone/benefit-like fields solely for OCR/provenance testing. They are not real benefit claims.

## 21. P4-3A minimum negative controls

At minimum:

- native-safe PDF -> OCR must not run,
- native text but no grid -> OCR must not run,
- multiple embedded images,
- partial-page image,
- unsupported bit depth,
- unsupported color space,
- undecodable pixels,
- ambiguous placement,
- borderless table,
- broken relevant grid boundary,
- merged semantic header/value cell,
- duplicate semantic header,
- missing BusinessName header,
- OCR bbox crossing cells,
- overlapping OCR words,
- low-confidence relevant identity field,
- malformed PDF,
- Tesseract executable missing,
- wrong engine version,
- wrong/missing Korean model,
- model hash mismatch,
- timeout,
- malformed TSV,
- excessive TSV output,
- excessive pixel/grid work.

Each negative control must specify the expected rejection stage/diagnostic class.

## 22. Determinism gate

P4-3A must compare repeated runs and Windows/Ubuntu results.

Classify determinism:

### Level A

Raw OCR outputs, physical assignments and final rows are equivalent under the comparison contract.

### Level B

Some non-semantic diagnostics/confidence values differ, but all of the following remain identical:

- accepted/rejected OCR word set,
- cell assignment,
- normalized cell text,
- final `PDF_ROW`,
- final adapter status.

Level B is acceptable only with explicit margin evidence proving platform variance cannot cross the configured acceptance boundary.

### Level C

Any semantic row/cell acceptance or final row/status differs.

A Level C result is a hard blocker for `APPROVED`.

## 23. Confidence calibration gate

P4-3A must test Korean text across:

- clear text,
- small text,
- degraded text,
- boundary-near text,
- intentional OCR confusion,
- addresses,
- phone numbers,
- benefit-like text.

The purpose is not to maximize OCR accuracy. The purpose is to establish whether a conservative reject boundary can be stable enough to protect provenance and identity.

If no defensible reject-only threshold exists, P4-3A must not return `APPROVED`.

## 24. Cross-business isolation gate

At least one scanned ruled-grid fixture must contain two businesses.

Required:

```text
lookup Business A -> A row only
lookup Business B -> B row only
cross-business leakage = 0
```

Any leakage is a hard blocker.

## 25. Failure gate

All runtime/identity/resource failures must remain fail-closed.

For every failure control:

- no claim,
- no `NOT_FOUND`,
- no `ENDED`,
- no partial semantic consumption,
- no currentness inference,
- no canonical/seed/apps mutation.

## 26. Optional official representative control

P4-3A may add an official scanned PDF only if a suitable current source is actually accessible at evaluation time.

If used, record:

- source URL,
- checked timestamp,
- fetch/HTTP status,
- content hash,
- observed adapter/layout result.

This is a layout/provenance control only. It must not manufacture or update benefit truth.

If the source is inaccessible, record `NOT_OBSERVED`. Historical bytes must not be substituted as current evidence.

## 27. P4-3A approval criteria

`APPROVED` requires all applicable hard gates to pass:

1. exact Tesseract candidate identity proven,
2. Korean model provenance/hash proven,
3. Windows and Ubuntu supply reproducible,
4. offline execution demonstrated,
5. PdfPig single-open image handoff proven,
6. supported Gray/RGB controls pass,
7. ruled-grid topology deterministic,
8. Korean OCR and cell containment pass,
9. confidence remains reject-only and has a defensible gate,
10. two-business leakage is zero,
11. native-safe OCR invocation is zero,
12. OCR candidate Tesseract invocation is at most one per run/document,
13. repeated business lookup reuses the OCR result,
14. unsupported cases fail closed,
15. runtime failures fail closed,
16. cross-platform result is Level A or justified Level B,
17. engine/model/config identity can participate in execution/extraction identity,
18. resource measurements and candidate production bounds are documented,
19. no product canonical/seed/apps changes,
20. no real benefit truth is created or changed.

If a hard gate fails, the result must be `CONDITIONALLY_APPROVED` or `REJECTED`.

## 28. P4-3A deliverables

The technical evaluation should leave:

- evaluation harness,
- reproducible synthetic controls,
- fixture provenance/hashes,
- Windows/Ubuntu CI evidence,
- runtime/model provenance,
- deterministic comparison evidence,
- resource measurements,
- failure matrix,
- final evaluation report,
- explicit `APPROVED`, `CONDITIONALLY_APPROVED` or `REJECTED` decision.

It must not leave a production OCR adapter enabled.

## 29. Expected future change surface

P4-3A should remain evaluation-scoped and avoid production behavior changes wherever possible.

P4-3B, if later approved, is expected to touch only the PDF data pipeline area, such as:

- the isolated PDF native helper,
- a bounded OCR runtime/helper boundary,
- PDF observation conversion/orchestration,
- run-context metrics/reuse,
- PDF OCR fixtures/tests,
- docs/handover/current-work.

P4-3B must not modify protected canonical/seed/apps, DB/auth/API/data-schema contracts without a separate explicit approval.

## 30. Test strategy

P4-3A:

- evaluation-specific Windows/Ubuntu matrix,
- repeated OCR determinism tests,
- image eligibility negative controls,
- ruled-grid positive/negative controls,
- confidence calibration,
- two-business isolation,
- runtime/model identity faults,
- resource-limit faults,
- native-safe OCR-zero proof,
- one-run OCR-at-most-once proof.

P4-3B, only if later approved:

- targeted OCR runtime tests,
- PDF observation tests,
- scoped PDF/binding/extraction regression,
- whole data suite,
- Android unit/lint/debug build regression where the repository gate requires it,
- protected path diff checks,
- exact-head CI.

## 31. Risks

### OCR nondeterminism

Different platform builds or model/runtime differences may move confidence/bbox outputs. This is why P4-3A has a hard determinism gate.

### False structural confidence

OCR accuracy does not prove table geometry. Pixel ruled-grid proof remains independent and mandatory.

### Coverage remains narrow

The first version intentionally rejects common scanned-PDF variants such as multi-image composition, unsupported compression/color spaces and borderless tables.

### Resource amplification

Large decoded images and OCR output can be significantly larger than source PDF bytes. Pixel/output/work budgets must be measured before production.

### Runtime supply complexity

Windows/Linux exact-version supply may be harder than the OCR algorithm itself. Failure to make supply reproducible blocks product approval.

### Existing PDF validation cost

P4-2 already has strict repeated validation/hashing behavior. P4-3 must not claim zero-rehash or introduce an unrelated trust optimization.

## 32. Non-negotiable safety properties

- `ProductionAction=NONE`
- no automatic canonical/seed/apps write
- no OCR confidence -> semantic strength
- no OCR failure -> absence
- no incomplete observation -> `NOT_FOUND`
- no incomplete observation -> claims
- no business-by-business OCR
- no second PDF parser/cache architecture
- no historical bytes presented as current evidence
- no product Tesseract dependency without explicit post-evaluation approval

## 33. Phase position

After this design:

```text
Phase 4 Multi-source Adapters
  P4-0 Foundation             COMPLETE
  P4-1 HWPX Generic Adapter  COMPLETE
  P4-2 PDF Native Adapter    COMPLETE
  P4-3 OCR Fallback
       P4-3 design           APPROVED
       P4-3A evaluation      NEXT
       P4-3B implementation  BLOCKED ON EVALUATION + DEPENDENCY APPROVAL
  P4-4 Integration/Closeout  LATER
```

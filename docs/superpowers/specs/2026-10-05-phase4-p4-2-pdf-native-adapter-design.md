# Phase 4 P4-2 PDF Native Adapter Design

**Date:** 2026-10-05  
**Status:** Approved conversational design; written-spec review required before implementation planning.  
**Baseline:** `dev@53443468ec48a30c33a0b089c55357fa7d14818f`  
**Previous phase:** P4-1 HWPX Generic Adapter merged in PR #114; Issue #113 closed.

## 1. Problem

MILIMAP can identify PDF bytes and preserve a byte-backed snapshot. P4-0 also established synthetic PDF row provenance contracts such as `PDF_ROW`, `PDF_PAGE_n_TABLE_n_ROW_n`, and page/table/row/cell physical references.

What is still missing is a native PDF adapter that proves, from the original PDF bytes, that a business identity and benefit fields belong to the same safe physical row/cells.

P4-2 is not a general PDF text-extraction feature.

The required outcome is:

> Accept only digital PDF table structures whose page, grid, row, cell, and text containment can be proven deterministically enough to prevent cross-business evidence leakage, then reuse the existing MILIMAP document provenance, locator, binding, extraction, and validation pipeline.

## 2. Goals

P4-2 will:

1. support a deliberately narrow native PDF subset;
2. derive page/table/row/cell provenance from original PDF bytes;
3. use actual vector geometry plus native text coordinates rather than reading order alone;
4. preserve business isolation before benefit claims are accepted;
5. reuse `BenefitDocumentValidationIndex` and existing downstream verification;
6. reuse `BenefitSourceRunContext` for one fetch/parse/index per source/run;
7. add a distinct `SCOPED_PDF_CELL` extraction method;
8. leave OCR to P4-3;
9. fail closed when geometry, text containment, or parser behavior is not trustworthy.

## 3. Non-goals

P4-2 does not include:

- OCR;
- scanned/image-only extraction;
- borderless-table inference;
- reading-order-only evidence;
- general multi-column prose parsing;
- arbitrary table reconstruction;
- semantic merged-cell reconstruction;
- cross-page row stitching;
- heuristic logical-grid repair;
- PDF POST_FETCH incremental reuse;
- new lifecycle inference;
- automatic canonical/seed/app mutation;
- automatic production approval;
- SNS/blog discovery;
- legacy HWP work;
- general PDF support claims.

## 4. Existing Boundaries Reused

The following remain authoritative:

- original source bytes are evidence identity;
- `ProductionAction=NONE`;
- source absence is not benefit ending or business closure;
- operational `PARTIAL`, `FAILED`, and `UNSUPPORTED` observations do not produce semantic `LOCATED` or `NOT_FOUND`;
- existing locator/business-binding/claim-validation rules remain authoritative;
- PDF incremental capability remains `NONE`;
- parser results are extraction candidates, not truth by themselves.

## 5. Architectural Shape

P4-2 adds one PDF-specific physical parser/adapter in front of the existing document verification core.

```text
Official PDF bytes
        |
        v
byte-backed immutable snapshot
        |
        v
native PDF parser
        |
        v
page normalization
        |
        v
vector ruled-grid validation
        |
        v
native text -> single-cell containment
        |
        v
semantic header validation
        |
        v
BenefitDocumentValidationIndex
        |
        v
PDF_ROW SourceContentUnit
        |
        v
existing Find-BenefitBusinessEvidence
        |
        v
existing Get-BenefitBusinessBinding
        |
        v
SCOPED_PDF_CELL extraction
        |
        v
existing scoped validation
```

Only the front physical interpretation layer is PDF-specific.

Do not add a PDF-specific locator, matcher, benefit evaluator, history model, or lifecycle evaluator.

## 6. Initial Supported PDF Subset

The initial adapter supports only:

- digital-text PDFs;
- explicit ruled-grid tables represented by trustworthy vector geometry;
- page-local independent tables;
- axis-aligned table geometry after deterministic page rotation normalization;
- one explicit semantic header row per supported table;
- unmerged semantic header cells;
- unmerged semantic data cells;
- native glyph/text objects whose physical cell membership can be uniquely proven;
- multiple independent tables/pages when each is validated separately.

The initial adapter does not support:

- image-only documents;
- arbitrary skew/perspective correction;
- borderless tables;
- multi-row semantic headers;
- positional field guessing;
- merged semantic cells;
- cross-page business-row continuation;
- general prose or multi-column reading-order interpretation.

Unsupported layouts remain candidates for later evidence-driven expansion or P4-3 OCR where appropriate.

## 7. Page Coordinate Normalization

A page must be normalized into one deterministic coordinate space before table construction.

Supported page rotations:

- 0 degrees;
- 90 degrees;
- 180 degrees;
- 270 degrees.

The adapter may use parser-provided page boxes and rotation metadata.

It must not:

- infer arbitrary skew;
- perform perspective correction;
- rotate a table heuristically to make it fit;
- modify coordinates based on a searched business result.

After normalization, supported grid boundaries must be axis-aligned.

## 8. Ruled-grid Recognition

A supported table requires actual vector evidence sufficient to construct closed rectangular cells.

Candidate boundaries may originate from:

- line/path segments;
- rectangle edges;

when the selected parser exposes them deterministically.

The grid algorithm may use a small versioned snapping tolerance for ordinary PDF coordinate imprecision.

It must not:

- grow tolerance per document until a grid appears;
- extend boundaries because text suggests a cell;
- fabricate missing grid edges from reading order;
- choose arbitrarily between multiple plausible topologies.

If more than one plausible grid topology remains after the fixed policy, that table is unusable.

The exact numeric tolerances are not fixed in this design. They must be measured during the parser technical evaluation and then frozen in a versioned extraction configuration.

## 9. Table Discovery

Every independent physical grid on a page is inspected in physical order.

Do not stop at the first grid.

Decorative/unrelated grids may be skipped.

A grid becomes a candidate business table only if it contains one safe semantic header row using the existing shared header map.

## 10. Semantic Header Rules

Reuse `Get-BenefitScopedHeaderMap`.

Do not create a PDF-only semantic dictionary.

A supported table requires:

- exactly one `BusinessName` semantic mapping;
- no duplicate mapping of the same semantic field;
- one physical header row only;
- no positional guessing;
- no multi-row header composition.

The following exact aliases observed in the Suwon representative PDF should be added to the shared map only after implementation tests prove no regressions:

```text
영업소 주소(도로명) -> Address
소재지전화          -> Phone
```

These are exact aliases, not fuzzy rules.

Do not add rules such as “contains 주소 -> Address” or “contains 전화 -> Phone”.

Because the map is shared, XLSX/HWPX and other existing-family regressions must cover the change.

## 11. Cell Merge Policy

Semantic evidence cells must have a provably one-to-one physical grid cell.

The adapter does not reconstruct semantic merged cells.

Decorative merged regions may be ignored only when they do not alter the proven semantic column/row boundaries.

If a semantic header or mapped evidence cell spans more than one physical grid cell, the relevant header/row is unusable.

## 12. Native Text Containment

Each native character/glyph/text object used as evidence must be assignable to exactly one physical cell.

Cell assignment must consider physical bounds, not only a centroid.

Reject or isolate the relevant row when:

- text bounds cross more than one semantic cell;
- membership is ambiguous near boundaries;
- coordinates are invalid, NaN, or infinite;
- duplicate/overlapping text makes source text ambiguous;
- Unicode decoding for the evidence field is not trustworthy;
- a text object simultaneously occupies table and non-table regions in a way the bounded policy cannot prove.

Do not assign ambiguous text to whichever cell is closest.

## 13. Text Ordering

Raw PDF content-stream order is not evidence-row order.

Within a proven cell, text ordering should be derived deterministically from geometry:

```text
contained text objects
 -> physical line grouping
 -> top-to-bottom
 -> left-to-right within line
```

Exact line-grouping/spacing tolerances are part of the versioned PDF extraction configuration and must be fixed after technical evaluation.

Document titles, page headers, page footers, or neighboring table text must never be copied into a business cell simply because they are near it.

## 14. Multiple Pages and Cross-page Boundaries

Each page is validated independently.

Multiple complete page-local tables are allowed.

Repeated table headers on later pages must be validated independently on those pages.

P4-2 does not stitch one business row across pages.

A row that begins on one page and continues on another is unsupported for native evidence.

## 15. Relevant Failure Isolation

Use the smallest failure boundary that remains physically trustworthy.

Examples:

- unrelated decorative grid -> skip;
- safe business table with one unsafe relevant row -> retain safe units for audit, overall `PARTIAL`;
- recognized semantic header hint in unsafe geometry -> rejection hint only, not evidence, overall `PARTIAL`;
- no safe semantic business table in an otherwise valid native-text PDF -> `UNSUPPORTED`;
- parser/document structure untrustworthy -> `FAILED`.

Do not silently filter malformed semantic structures and then claim complete absence.

## 16. Operational Status

Use the existing global operational states.

```text
whole PDF structure/parser trust lost
  -> FAILED

image-only/scanned PDF
  -> UNSUPPORTED
  + OCR_FALLBACK_CANDIDATE diagnostic

native text exists but no supported ruled semantic table
  -> UNSUPPORTED

recognized relevant table but some relevant row/cell/geometry unsafe
  -> PARTIAL

all relevant supported structure safe
  -> COMPLETE
```

`OCR_FALLBACK_CANDIDATE` is a diagnostic concept, not a new global operational state.

`PARTIAL`, `FAILED`, and `UNSUPPORTED` must not yield semantic `LOCATED` or `NOT_FOUND`.

## 17. Provenance Contract

P4-2 reuses the existing P4-0 PDF row contract.

Example:

```text
UnitType      = PDF_ROW
UnitReference = PDF_PAGE_1_TABLE_1_ROW_2
PhysicalPath  = page/1/table/1/row/2
```

Mapped fields retain:

- `FieldReference`;
- `PhysicalReference`;
- `SourceText`.

Example:

```text
BusinessName
  FieldReference     = PDF_PAGE_1_TABLE_1_ROW_2/BusinessName
  PhysicalReference  = page/1/table/1/row/2/cell/1
```

Do not add parser-specific bbox objects to the public document validation contract.

The PDF adapter must first prove physical geometry from original bytes, then create the existing `BenefitDocumentValidationIndex`.

## 18. Private Geometry Witness

PDF-specific geometry data stays behind the PDF adapter boundary.

Conceptually:

```text
original PDF bytes
 -> parser output
 -> normalized geometry witness
 -> validated grid/cell containment
 -> existing document validation index
```

The geometry witness may contain parser-specific page, glyph, vector, and coordinate information internally.

It is not a new public evidence contract.

If future requirements need persisted bbox evidence or non-grid text-block provenance, that is a separate contract-design decision.

## 19. Parser Dependency Policy

P4-2 requires a native PDF runtime that does not currently exist in the repository.

Therefore the current dependency decision is:

`NEW_DEPENDENCY_APPROVAL_REQUIRED`

The primary evaluation candidate is PdfPig.

This design does not approve adding PdfPig to the repository.

## 20. PdfPig Evaluation Baseline

Evaluate the current stable PdfPig line first, with an exact pinned version if adopted.

The technical evaluation must verify at least:

- Korean text decoding;
- page box and rotation behavior;
- glyph/letter bounds;
- vector line/path access;
- ruled-grid reconstruction feasibility;
- encrypted/password document detection;
- scanned/image-only classification;
- malformed/truncated PDF fail-closed mapping;
- deterministic physical projection;
- Windows compatibility;
- GitHub Actions compatibility;
- licensing/transitive dependency implications;
- bounded resource behavior;
- practical PowerShell/.NET integration.

If a core provenance requirement fails, do not force PdfPig into the design.

The next realistic candidate is Apache PDFBox.

A custom PDF parser is not the fallback.

## 21. Dependency Technical Gate Result

The parser evaluation ends in exactly one of:

```text
PDFPIG_APPROVED_FOR_P4_2
PDFPIG_REJECTED_EVALUATE_PDFBOX
PDF_NATIVE_PATH_BLOCKED
```

Even `PDFPIG_APPROVED_FOR_P4_2` does not itself authorize adding the dependency.

The user must separately approve the new external dependency before P4-2 product implementation begins.

## 22. Parser Types Must Not Leak Downstream

Parser-native types must stay inside the PDF adapter boundary.

Do not expose parser objects such as pages, letters, rectangles, paths, or words to:

- locator;
- business binding;
- extraction;
- validation;
- history.

Convert parser output into MILIMAP-owned deterministic physical projection first.

This keeps downstream architecture independent from a specific PDF library.

## 23. Parser Output Is Not Evidence

The native parser returning text or coordinates is insufficient.

Required progression:

```text
parser output
 -> page normalization
 -> grid validation
 -> cell containment validation
 -> semantic header validation
 -> PDF row projection
 -> BenefitDocumentValidationIndex
```

No parser-provided “table” result is automatically trusted as evidence.

MILIMAP’s own safety policy remains the authority.

## 24. Execution Identity

Original PDF bytes and their content hash remain evidence identity.

The following are execution/configuration identity:

- parser ID;
- parser version;
- adapter ID/version;
- page normalization policy;
- grid snapping tolerance;
- glyph/cell containment tolerance;
- text line grouping/ordering policy;
- header-map/config hash.

Material changes must alter the extraction/execution identity rather than being misinterpreted as a real-world PDF content change.

## 25. Versioned PDF Extraction Configuration

Geometry/text tolerances must not be scattered as unexplained literals.

The implementation should define one versioned extraction policy, conceptually:

`PDF_GRID_CONFIG_V1`

It should capture all material deterministic parsing policies.

The exact representation is an implementation-plan decision.

Per-document automatic tolerance growth is prohibited.

## 26. Test Fixture Dependency Separation

A tool used to generate deterministic test PDFs is not automatically an approved product parser dependency.

Keep separate decisions for:

- product runtime PDF parser;
- test-only fixture generation.

Do not rely exclusively on PDFs generated by the same library being evaluated as the parser.

At least one independent/real document control should cross-check parser behavior.

## 27. Run-context Integration

Reuse the existing `BenefitSourceRunContext`.

Do not create a PDF-specific cache framework.

Generalize the source-snapshot path to allow:

- HTML;
- XLSX;
- HWPX;
- PDF.

PDF snapshot:

```text
Text        = ''
Bytes       = original PDF bytes
ContentHash = SHA-256(original bytes)
```

## 28. Parse-once Behavior

Conceptual PDF observation entrypoint:

`Get-BenefitRunPdfObservation`

For one PDF used by N businesses:

```text
fetch        = 1
snapshot     = 1
native parse = 1
grid/index   = 1
lookup       = N
```

Use the existing run-local template cache.

The cache identity must distinguish snapshot plus material parser/adapter/config identity.

Conceptually:

```text
SnapshotId
| PDF_GRID
| AdapterVersion
| ParserId
| ParserVersion
| ExtractionConfigHash
```

Implementation should follow the existing cache-key conventions rather than inventing a separate framework.

## 29. Cache Incomplete Results Too

Within one run, cache defined PDF parsing outcomes including:

- `COMPLETE`;
- `PARTIAL`;
- `FAILED`;
- `UNSUPPORTED`.

Do not re-open/reparse an image-only or malformed PDF separately for every business.

P4-3 may later add one OCR operation over the same run-local source boundary.

## 30. Scoped Pipeline Integration

After dependency approval and implementation, the scoped source runner should accept:

- HTML;
- XLSX;
- HWPX;
- PDF.

Dispatch conceptually:

```text
HTML -> Get-BenefitRunHtmlObservation
XLSX -> Get-BenefitRunXlsxObservation
HWPX -> Get-BenefitRunHwpxObservation
PDF  -> Get-BenefitRunPdfObservation
```

A native PDF adapter failure must not silently fall back to the old unstructured `PdfTextExtractor` path.

The existing `PdfTextExtractor` seam is not the trusted P4-2 scoped adapter.

## 31. Scoped PDF Extraction

A validated PDF row uses:

`SCOPED_PDF_CELL`

The method family becomes:

```text
HTML  -> SCOPED_HTML_CELL
JSONP -> SCOPED_JSONP_FIELD
XLSX  -> SCOPED_XLSX_CELL
HWPX  -> SCOPED_HWPX_CELL
PDF   -> SCOPED_PDF_CELL
```

PDF-specific semantic evaluation is not added.

## 32. DocumentValidationIndex Reuse

Reuse the current common document index and downstream validation.

No PDF-only semantic validator is needed.

PDF-specific geometry is already proven before the index is constructed.

The existing locator/binding/extraction/validation layers receive the same document index contract used by HWPX.

## 33. Incremental Reuse

P4-2 run-local parse caching is not Phase 3 incremental reuse.

Keep:

`Get-BenefitIncrementalCapability(PDF) = NONE`

PDF POST_FETCH reuse is not part of P4-2.

Any future promotion requires its own reproducibility/provenance evidence.

## 34. P4-3 OCR Boundary

P4-2 must distinguish reasons that may be useful to P4-3.

Examples may include:

- image-only;
- encrypted;
- unsupported grid;
- unusable relevant row;
- ambiguous text containment;
- OCR fallback candidate.

Exact diagnostic code names must follow current allowed-code conventions during implementation planning.

OCR is not implemented in P4-2.

A native layout ambiguity is not automatically solved by OCR.

## 35. Two-stage Delivery Model

P4-2 is intentionally split.

### P4-2A — Parser Technical Evaluation

Read-only/probe work to determine whether PdfPig satisfies the required geometry/provenance/runtime gates.

No product dependency is added.

Output:

- parser candidate evidence;
- Suwon representative compatibility evidence;
- deterministic/safety findings;
- recommended dependency decision;
- one of the three technical-gate statuses.

### Dependency Approval Gate

If P4-2A concludes `PDFPIG_APPROVED_FOR_P4_2`, the user must explicitly approve adding the external dependency.

### P4-2B — Native PDF Adapter

Only after dependency approval:

- add the approved parser runtime;
- implement bounded ruled-grid adapter;
- integrate run-context;
- add scoped PDF extraction;
- run complete regression/CI;
- close out P4-2.

This separation prevents dependency selection and product implementation from being hidden inside one change.

## 36. P4-2A Validation

The technical evaluation must demonstrate:

- correct Korean decoding on the representative Suwon PDF;
- deterministic page/rotation geometry;
- actual vector grid access;
- row/cell reconstruction feasibility under the bounded policy;
- exact business-name/address/phone cell containment where present;
- encrypted/image-only/malformed classification feasibility;
- no need for reading-order-only inference;
- realistic Windows and CI integration.

The Suwon PDF is a layout/identity control only.

It is not a benefit-positive/currentness control because the observed table does not provide per-business benefit/condition/validity columns.

## 37. P4-2B Parser / Geometry Tests

After implementation, cover at least:

- valid digital-text ruled-grid PDF;
- invalid/truncated PDF;
- encrypted/password PDF;
- image-only PDF;
- page rotation;
- multiple pages;
- multiple independent tables;
- boundary-crossing glyph;
- overlapping/duplicate text;
- malformed vector/grid;
- merged semantic cells;
- ambiguous semantic header;
- repeated header/footer;
- cross-page row continuation.

## 38. Cross-business Leakage Gate

A deterministic valid PDF fixture must contain at least two synthetic businesses:

```text
Business A | Address A | Phone A | Benefit A
Business B | Address B | Phone B | Benefit B
```

Required:

- A lookup selects only A row;
- B lookup selects only B row;
- A evidence contains no B benefit text;
- B evidence contains no A benefit text;
- duplicate-name alternatives remain ambiguous under existing locator rules;
- ambiguous cases expose no claims.

Cross-business leakage must be zero.

This is a merge blocker.

## 39. Byte-derived Provenance Gate

Positive tests must start from a real parseable PDF byte sequence.

The P4-0 signature-only synthetic PDF marker is not a valid positive P4-2 fixture.

Required flow:

```text
PDF bytes
 -> native parser
 -> geometry/grid
 -> cell containment
 -> validation index
```

Then reject mutations including:

- page/table/row path;
- cell physical reference;
- source text;
- structured field value;
- parser/extractor metadata;
- validation index from another snapshot;
- caller-invented row.

The test must demonstrate that the index was derived from original PDF bytes, not just internally consistent caller data.

## 40. Operational Safety Tests

Pin:

```text
malformed document
 -> FAILED

image-only
 -> UNSUPPORTED + OCR fallback diagnostic

native text but no supported semantic ruled grid
 -> UNSUPPORTED

unsafe relevant row/cell
 -> PARTIAL

fully safe bounded structure
 -> COMPLETE
```

For `PARTIAL`, `FAILED`, and `UNSUPPORTED`:

- no `LOCATED`;
- no `NOT_FOUND`;
- no validated benefit claim.

Absence never implies `ENDED`.

## 41. Run-context Performance Gate

For at least two businesses using one PDF source in one run:

- `ExternalFetchCount = 1`;
- native PDF parse count = 1;
- PDF geometry/index build = 1;
- `AdapterReuseCount >= 1`.

Do not add a public validation bypass merely to eliminate small strict-contract checks.

Measure before adding deeper trust/cache optimization.

## 42. Shared Header Regression Gate

If the two Suwon aliases are added to `Get-BenefitScopedHeaderMap`, existing families must remain passing.

At minimum cover:

- XLSX;
- HWPX;
- scoped HTML behavior where applicable.

The change must remain exact-alias-only.

## 43. Existing-family Regression Gate

P4-2 must preserve:

- HTML;
- MMA JSONP;
- XLSX;
- HWPX;
- Phase 3 History;
- incremental reuse behavior.

Explicitly confirm:

- PDF incremental capability remains `NONE`;
- HWPX incremental capability remains `NONE`;
- `ProductionAction=NONE`;
- protected data/app paths unchanged.

## 44. Synthetic PDF Fixture Policy

Positive fixture PDFs must be genuinely parseable.

They should cover:

- Korean text;
- vector grid;
- multiple rows;
- multiple businesses;
- multiline cells;
- repeated header/footer;
- malformed/merged variants where feasible.

A fixture generation tool is a separate test-dependency decision from the product parser.

Avoid validating only parser-generated documents against the same parser.

## 45. Real-source Validation

Use the current Suwon official PDF as a representative live control only when it remains available.

Record:

- exact URL/source chain status;
- observation time;
- HTTP/content type;
- PDF signature;
- size;
- content hash;
- page count;
- native-text status;
- grid geometry;
- business identity row/cells;
- parser result.

Do not treat publication/file year as per-business validity.

Do not treat the Suwon document as a benefit-positive control when no per-business benefit columns exist.

Do not commit the live PDF as a repository fixture until redistribution/legal/privacy considerations are separately confirmed.

## 46. P4-2 Completion Criteria

P4-2 may be called complete only after all applicable conditions pass:

- PdfPig technical evaluation succeeds;
- external dependency is explicitly approved;
- bounded ruled-grid parser implemented;
- byte-derived PDF row/cell provenance passes;
- `SCOPED_PDF_CELL` integrated;
- cross-business leakage = 0;
- incomplete observation semantic promotion = 0;
- same-source fetch/parse/index reuse gate passes;
- full data suite passes;
- Android unit/lint/debug build passes;
- exact PR HEAD CI passes;
- canonical/seed/apps diff is empty;
- `ProductionAction=NONE`;
- PDF incremental reuse remains `NONE`;
- current Suwon native layout/identity control is validated.

P4-2 completion does not mean Phase 4 completion.

P4-3 OCR fallback and P4-4 integration/closeout remain separate work.

## 47. Expected Change Area After Approval

Exact paths must be rechecked at implementation time.

Likely new runtime areas:

- PDF geometry/provenance adapter code;
- PDF observation conversion code;
- PDF parser/runtime supply/version metadata;
- PDF targeted test support and fixtures;
- PDF scoped end-to-end tests.

Likely modified areas:

- `benefit-source-run-context.ps1`;
- `invoke-scoped-benefit-source.ps1`;
- `extract-benefit-evidence.ps1`;
- shared semantic header map;
- README/current-work/handover docs.

Prefer no semantic changes to:

- locator;
- business binding;
- claim validation;
- History schema;
- incremental capability logic beyond confirming PDF remains `NONE`.

## 48. Risks

### Layout fidelity

Vector lines do not automatically prove a valid table. Clipping, overlapping paths, rotations, duplicate graphics, and ambiguous topology must fail closed.

### Text fidelity

PDF text may be visually correct but internally encoded in unexpected ways. Korean decoding and glyph ordering must be verified on real and independent fixtures.

### Provenance

A caller-provided row/index must never masquerade as byte-derived PDF evidence.

### Performance

Page scanning, glyph/grid intersection, hashing, and geometry normalization may become expensive. P4-2 requires parse-once behavior but does not preemptively create a second cache architecture.

### Security

Malformed PDFs can contain expensive/deep object graphs. The selected runtime and adapter require resource bounds and fail-closed behavior.

### Coverage

One Suwon PDF proves only one observed layout family.

### OCR boundary

Native ambiguity or scan-only documents must not be interpreted as absence. P4-3 remains a separate evidence path.

## 49. Approval State

Approved conversational sections:

- Section 1 — Scope / Architecture
- Section 2 — Grid / Geometry Safety
- Section 3 — Dependency Validation
- Section 4 — Pipeline Integration
- Section 5 — Testing / Completion Gate

This written spec still requires explicit user review before implementation planning.

Implementation is not authorized by this document.

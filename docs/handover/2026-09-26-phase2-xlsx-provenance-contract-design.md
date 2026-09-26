# Phase 2 XLSX row/cell provenance contract design

## 1. Baseline

- Checked `origin/dev`: `bf0940c` (2026-09-26).
- Issue: #85. Inventory basis: Issue #82 / merged PR #84.
- `SourceFormat` already includes `XLSX`; `BenefitSourceDocument` already preserves `Bytes`.
- Primary control is Yangju's official 2026 attachment: `음식점` row 22, `가마골 백숙`. `거석골` is absent from that observed workbook and that absence is not discontinuation evidence.

## 2. Problem

An XLSX row must be bound to immutable original ZIP bytes and exact workbook cells before it can provide business identity or benefit evidence.

## 3. Existing contract limitation

The lifecycle `SourceDocument -> Snapshot -> SourceObservation -> SourceContentUnit -> RelevantEvidenceSlice` is already sufficient. Its scoped validation is not: `BenefitSourceSnapshot` hashes UTF-8 `Text`, and `SourceContentUnit` / `RelevantEvidenceSlice` accept only HTML `TABLE_ROW` and JSONP `JSON_OBJECT`.

## 4. Exact proposed contract delta

Extend the existing contracts with one format-specific path only:

1. Make `BenefitSourceSnapshot` binary-aware for `SourceFormat=XLSX`.
2. Add one `SourceContentUnit.UnitType`: `XLSX_ROW`.
3. Add the matching `RelevantEvidenceSlice` shape: `ScopeType=XLSX_ROW`, `LocatorMethod=STRUCTURED_XLSX_ROW`.

No new top-level source format, generic attachment abstraction, PDF unit, reason code, lifecycle state, or persistent schema is proposed.

## 5. Binary snapshot rule

`BenefitSourceSnapshot` remains the only snapshot contract and keeps `SnapshotId`, `SourceUrl`, `SourceFormat`, `Text`, `ObservedAt`, and `ContentHash`.

For `XLSX` only, it additionally carries non-empty original `Bytes` and follows these rules:

- `ContentHash = SHA-256(original Bytes)`, calculated before workbook parsing, decompression, normalization, or text reconstruction.
- `SnapshotId` continues to be derived from `SourceUrl`, `SourceFormat`, `ObservedAt`, and that single authoritative `ContentHash`.
- `Text` is the empty string for XLSX and is not hashed. `Bytes` is mandatory for XLSX; no reconstructed worksheet text can substitute for it.
- For HTML and JSONP, the current required non-empty `Text`, UTF-8 text hash, and snapshot-id semantics remain exactly unchanged. Their objects need not gain a `Bytes` property.
- `Assert-ScopeSnapshot` branches by source format: it preserves the legacy text rule for HTML/JSONP and requires valid raw bytes plus their hash for XLSX. Other currently unsupported binary formats do not gain scoped snapshot support from this change.

This is a binary-aware extension of the existing snapshot, not a new snapshot type or parallel hash. A second binary hash field would duplicate the sole provenance root and make slice validation ambiguous.

## 6. XLSX_ROW content unit

An XLSX row unit has only the properties needed to resolve and verify its physical source:

```text
ContractType       SourceContentUnit
ContractVersion    1
SnapshotId         snapshot id
UnitType           XLSX_ROW
UnitReference      XLSX_SHEET_{SheetIndex}_ROW_{RowNumber}
SheetName          workbook sheet name
SheetIndex         one-based document order in workbook.xml
HeaderRowNumber    one-based worksheet header row
RowNumber          one-based selected data row
StructuredFields   semantic field -> normalized string
FieldReferences    semantic field -> XLSX cell reference object
```

`SheetName` and `SheetIndex` must both resolve to the same unique `<sheet>` in the original `xl/workbook.xml`. The validator follows that sheet's `r:id` through `xl/_rels/workbook.xml.rels`; it derives the worksheet part from the original package rather than storing a redundant, forgeable part path. `HeaderRowNumber` is required because the existing semantic header mapping must be proven, not assumed. It must be before `RowNumber`.

`RawStart`, `RawLength`, `RawFragment`, and `RawEvidenceText` are intentionally absent for XLSX. A compressed package has no single stable global text span, and serializing a worksheet row as “raw text” would falsely imply that reconstructed text is the provenance root.

## 7. CellReference shape

Each `FieldReferences[$semanticField]` is:

```text
FieldReference        XLSX_SHEET_{SheetIndex}_ROW_{RowNumber}/{semanticField}
HeaderCellReference   A1 header coordinate, for example B2
OriginalHeader        decoded header text, for example 업소명
CellReference         selected-row A1 coordinate, for example B22
CellType              normalized OOXML cell type: s, inlineStr, str, or n
RawValue              source-cell lexical payload
```

`SheetName` is not repeated per field: the enclosing unit supplies it and the validator rejects any cell reference outside that unit's selected row. `HeaderCellReference` and `OriginalHeader` retain the existing header-to-semantic-field guarantee; the header and value cells must be in the same column.

`RawValue` is the source payload before semantic normalization: `<v>` text for `s`, `str`, and `n`; for `inlineStr`, the source `<is>` text-node sequence preserving XML whitespace. The validator rereads the original package and checks type, lexical payload, and decoded value. `StructuredFields` stores only the decoded value after the existing conservative text normalization (trim, no display formatting, formula evaluation, date inference, or benefit inference). Missing cells never become invented empty fields. Formula, error, boolean, date-specialized, or unsupported cell representations in a selected semantic field fail closed in this first capability.

For the observed positive control the conceptual references are `BusinessName=B22`, `Address=C22`, `Phone=D22`, `Menu=E22`, and `BenefitDescription=F22`, with their corresponding row-2 headers.

## 8. RelevantEvidenceSlice shape

The XLSX branch keeps all common slice identity fields:

```text
SourceRowNumber, SnapshotId, ContentHash, SourceUrl, SourceFormat, ObservedAt,
LocatorMethod=STRUCTURED_XLSX_ROW, ScopeType=XLSX_ROW,
EvidenceReference=UnitReference, SheetName, SheetIndex, HeaderRowNumber,
RowNumber, StructuredFields, FieldReferences, IdentityEvidence
```

It adds no raw-text span fields and embeds no workbook bytes. `ContentHash` is the original-byte hash from the snapshot, and `Assert-ScopeSliceAgainstSnapshot` reconstructs an `XLSX_ROW` unit from the slice and validates it against those bytes. HTML and JSONP slice property requirements remain unchanged.

## 9. Validation invariants

- The selected row belongs to the raw-byte-bound snapshot, and its sheet, header row, data row, and every claimed cell exist in the original package.
- Every value-cell reference is on the selected row, is in the same column as its mapped header cell, and has the exact original type/raw payload plus the allowed normalized semantic value.
- A field reference from another row, another sheet, or a different cell with the same displayed text fails; a `UnitReference` cannot make it valid.
- Duplicate or ambiguous identity candidates cannot produce `LOCATED`; absent identity cannot produce `ENDED`.
- Only malformed rows that cannot contribute to the candidate set may be isolated. A malformed selected row, selected sheet, or package provenance path fails closed.

## 10. Identity before claim extraction

The required order is:

```text
original XLSX bytes -> validated snapshot -> sheet/row candidates
-> identity match using business name plus address/phone/branch evidence
-> exactly one bound XLSX_ROW slice -> benefit claim materialization
```

The locator must not search discount cells first or allow a benefit value to establish a business identity. Duplicate identity candidates yield `AMBIGUOUS` with no slice. A missing `거석골` candidate yields `NOT_FOUND` / review-needed handling only; it is never `ENDED`, `VALID_UNTIL`, or an explicit discontinuation claim.

## 11. Run-context reuse

Reuse the current URL payload cache for one attachment fetch per exact URL/run. Add one XLSX template cache entry keyed by `SnapshotId|XLSX_GENERIC|1`:

- parse/unzip the validated snapshot once;
- retain a minimal in-memory sheet-row index: resolved sheets, their header map, and parsed row-cell records needed to construct verified units;
- reuse that index for multiple canonical lookups without re-download, re-unzip, re-hash, or full workbook scanning per claim.

The same validated index is the only input for XLSX provenance revalidation; it carries the source `SnapshotId` and raw-byte `ContentHash`. A validator rejects an index whose identity differs from the slice/snapshot, so an index from another snapshot is never reused. The index is not a new contract and does not need a speculative business-name index. A bounded iteration over already parsed rows is sufficient; identity ambiguity stays visible instead of being overwritten by an index choice.

## 12. No-dependency feasibility and XLSX package validation

PowerShell 7.6.6 exposes `System.IO.Compression.ZipArchive` and `System.Xml.XmlReader`, so the needed bounded validation is feasible without a third-party XLSX library.

The future adapter/validator must use an in-memory read-only ZIP and XML path:

1. Verify non-empty XLSX bytes and the raw-byte snapshot hash before parsing.
2. Require exactly one readable `[Content_Types].xml`, `xl/workbook.xml`, and `xl/_rels/workbook.xml.rels`; reject duplicate or traversal/external worksheet relationship targets.
3. Resolve the unit's unique sheet name and document index through workbook XML and relationships, then require its worksheet entry.
4. Read optional `xl/sharedStrings.xml` only when an `s` cell needs it. Resolve a shared-string index exactly once; support `inlineStr` by reading its source text nodes; retain numeric lexical values without Excel display formatting.
5. Locate the exact `<row r>` and exact `<c r>` cells. Sparse rows and missing cells are normal only when they are not claimed; a claimed missing cell fails. Duplicate selected row/cell coordinates, invalid references, or malformed selected-sheet XML fail closed.
6. Verify every header/value coordinate, header mapping, cell type, raw value, and normalized semantic value. A selected formula field is unsupported rather than evaluated.

Malformed semantic data in an unrelated row may be isolated as a row diagnostic only when the worksheet XML is well-formed and the row cannot contribute a candidate. Malformed selected-sheet XML, a malformed selected row, or any ambiguity affecting identity fails the selected lookup closed.

## 13. Unchanged behavior

The Yangju posting date and filename date are publication context only. Workbook presence is evidence of a listed benefit at its observed context, not a per-row validity range. The capability must not invent `VALID_UNTIL`, classify absence as `ENDED`, produce automatic GREEN, or change `ProductionAction` from `NONE`.

- HTML `TABLE_ROW`, JSONP `JSON_OBJECT`, and their existing span/property provenance shapes.
- Existing HTML/JSONP text snapshot hashes and snapshot IDs.
- Existing field/span provenance validation for those formats.
- `BenefitState`, `ReviewClass`, `ProductionAction`, source qualification, and business-binding rules.
- Canonical/seed/apps data, canonical URL correction, database/schema, auth/API, dependencies, PDF/HWP/OCR, discovery, transport retry, and Phase 3 persistence.

## 14. Expected implementation files after approval

- `tools/data/lib/benefit-evidence-location-contracts.ps1`
- `tools/data/test-benefit-evidence-location-contracts.ps1`
- `tools/data/lib/benefit-evidence/convert-xlsx-source-observation.ps1` (new)
- `tools/data/test-convert-xlsx-source-observation.ps1` (new)
- `tools/data/lib/benefit-evidence/benefit-source-run-context.ps1`
- `tools/data/test-benefit-source-run-context.ps1`
- `tools/data/lib/benefit-evidence/invoke-scoped-benefit-source.ps1`
- targeted locator/scoped integration tests and synthetic XLSX fixtures under `tools/data/testdata/benefit-evidence-xlsx/` (new)

No implementation file is changed by this design-only issue.

## 15. TDD plan

First add contract tests, then implement the minimum snapshot/unit/slice validators, then add the adapter and reuse tests. Required tests include:

- raw-byte hash/snapshot identity; a one-byte change fails even if decoded cells display the same values;
- current HTML/JSONP snapshot and provenance regressions unchanged;
- valid shared-string, inline-string, numeric, sparse-row, and missing-cell handling;
- selected row/sheet membership, header mapping, exact field cell, raw value, and normalized semantic-value checks;
- cross-row forgery, same-display-value cross-cell forgery, wrong sheet, and wrong header/column rejection;
- duplicate/ambiguous identity produces no `LOCATED` slice;
- malformed unrelated row cannot contaminate the selected business; malformed selected row fails closed;
- one exact URL fetch, one snapshot parse, and cache reuse across multiple business lookups.

## 16. Live controls

After deterministic fixtures are green, use `가마골 백숙` as the positive live control without treating its canonical benefit as expected truth. Use absent `거석골` to verify no `ENDED` inference. Live tests must preserve the official page-to-attachment provenance chain and remain review-only.

## 17. Safety gates

- False GREEN = 0; false ENDED = 0; cross-business claim leakage = 0.
- Every materialized field has a selected-row cell and mapped header from the original bytes.
- `ProductionAction=NONE`; canonical/seed/apps diff = 0.

## 18. Efficiency gates

- One fetch per exact URL/run, one ZIP/XML parse per snapshot/run, no per-business full-file hashing or re-unzip, and no full workbook scan per claim.

## 19. Remaining risks

- The official attachment returns a nonstandard `application/octer-stream`; transport must continue to require XLSX signature/package validation rather than trusting MIME type.
- XLSX formulas, merged-header layouts, encrypted packages, and unsupported OOXML cell types are intentionally fail-closed, not silently interpreted.
- The Yangju workbook lacks row-level validity dates; source publication context cannot prove individual currentness.
- The canonical source linkage correction remains a separate approved task.

## 20. Verdict

**APPROVED_DESIGN_NO_DEPENDENCY**

The bounded XLSX row/cell provenance capability can use existing .NET ZIP/XML facilities. This approves only the design for review; no parser or adapter implementation is authorized by this document.

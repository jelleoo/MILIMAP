# Phase 4 P4-1 HWPX Generic Adapter Design

**Date:** 2026-10-05  
**Status:** Approved conversational design; implementation blocked until P4-0 PR #112 is merged and `dev` is refreshed.  
**Authority:** Current GitHub code first; approved Phase 4 multi-source adapter design; P4-0 reviewed HEAD `bc36bf6a7d9dc6024e5b44294d5667c162170487`.

## Problem

P4-0 defines safe HWPX recognition, byte-backed snapshots, document-row provenance contracts, and the locator bridge, but it intentionally does not prove that a document row was actually extracted from real HWPX bytes. P4-1 must close that gap for a bounded HWPX subset.

The goal is to turn a trusted HWPX package into row-scoped evidence with physical provenance:

```text
original HWPX bytes
  -> section
  -> table
  -> row
  -> cell
  -> BenefitDocumentValidationIndex
  -> HWPX_ROW SourceContentUnit
  -> existing locator / binding / claim validation
```

P4-1 is successful only when the downstream evidence can be traced back to the actual HWPX package structure and the same document is fetched and parsed once per run.

## Scope

P4-1 includes:

- Native HWPX package/XML parsing without a new external dependency.
- Table-based evidence only.
- Safe package and XML validation.
- Independent inspection of every table in every trusted section.
- Reuse of the existing `Get-BenefitScopedHeaderMap` semantic mapping.
- Text-only extraction from supported semantic cells.
- Construction of the existing P4-0 `BenefitDocumentValidationIndex`.
- HWPX `SourceContentUnit` and `RelevantEvidenceSlice` flow through the existing locator, business binding, extraction, and validation pipeline.
- Run-context fetch-once and parse-once behavior.
- Deterministic synthetic HWPX fixtures, tamper tests, cross-business leakage tests, and scoped end-to-end tests.
- Exact-head CI and existing-family regression validation.

## Non-scope

P4-1 does not include:

- PDF parsing.
- OCR.
- Legacy binary HWP.
- Paragraph/block evidence outside tables.
- Multi-row semantic header composition.
- Column-position guessing.
- Generic logical-table stitching across multiple physical tables.
- Full support for arbitrary inline HWPX objects.
- HWPX POST_FETCH incremental reuse.
- A new document parser abstraction shared with PDF.
- Official SNS/blog or general web discovery.
- Production mutation, automatic benefit approval, canonical/seed/app writes.
- New database, API, authentication, schema, or external-library changes.

## Preconditions

Implementation must not begin until:

1. PR #112 is merged.
2. Issue #111 is closed by the merge.
3. The new `origin/dev` SHA is recorded.
4. P4-1 work is rebased/created from that refreshed `dev`.

The design may be reviewed and planned before that merge, but implementation must use the post-merge `dev` state.

## Architecture

Use a thin HWPX-specific adapter and reuse the existing document provenance and verification core.

```text
Official HWPX bytes
        |
        v
convert-hwpx-source-observation.ps1
  - package validation
  - safe XML parsing
  - table/header detection
  - cell text extraction
  - row provenance construction
        |
        v
BenefitDocumentValidationIndex
        |
        v
SourceContentUnit(HWPX_ROW)
        |
        v
existing Find-BenefitBusinessEvidence
        |
        v
existing Get-BenefitBusinessBinding
        |
        v
existing Invoke-BenefitEvidenceExtraction
        |
        v
existing ConvertTo-ValidatedBenefitEvidence
```

The adapter stops at structural interpretation and provenance. It must not introduce HWPX-specific business matching, benefit-state evaluation, lifecycle inference, or production actions.

### Adapter boundary

Create a dedicated HWPX observation adapter, centered on a file such as:

`tools/data/lib/benefit-evidence/convert-hwpx-source-observation.ps1`

Do not place ZIP/XML parsing inside `benefit-evidence-location-contracts.ps1`. P4-0 contract files should remain unchanged unless implementation proves a minimal contract correction is necessary.

Do not create a shared PDF/HWPX parser layer in P4-1. PDF and HWPX share downstream provenance contracts, not physical parsing mechanics.

## HWPX Package Validation

P4-1 builds on P4-0 HWPX recognition and keeps fail-closed package handling.

The package must satisfy the existing bounded ZIP/package checks, including:

- valid ZIP package signature,
- bounded entry count,
- bounded individual entry size,
- bounded total uncompressed size,
- no unsafe paths,
- no backslash paths,
- no case-insensitive duplicate entry names,
- exact HWPX mimetype,
- required `Contents/content.hpf`,
- required section XML entries.

P4-1 additionally requires that the root metadata and section references needed for parsing are internally trustworthy and resolve to unique safe package entries.

If package/root membership cannot be trusted, the whole observation fails closed.

## Safe XML Parsing

XML parsing must use a configuration that prevents external expansion and recovery behavior from becoming evidence.

Requirements:

- DTD processing disabled/prohibited.
- External entity resolution disabled.
- External resolver disabled.
- Malformed XML is not auto-repaired and used as evidence.
- Only package-local, validated section entries may be parsed.

### Failure isolation

Use hierarchical fail-closed behavior:

- Unsafe/broken package structure -> whole document `FAILED`.
- Untrustworthy root metadata / section membership -> whole document `FAILED`.
- One malformed section with other section boundaries still trustworthy -> discard that section and mark observation `PARTIAL`.
- One unsupported table/header/row inside a trustworthy section -> isolate only that smallest provable unit and mark observation `PARTIAL`.
- No usable semantic BusinessName header anywhere in an otherwise trusted document -> `UNSUPPORTED`.

A `PARTIAL` observation may retain parsed units for diagnostics/audit, but the existing semantic locator contract remains unchanged: incomplete observations must not expose a usable `LOCATED` or `NOT_FOUND` result.

## Supported Table Subset

P4-1 supports physical tables only.

Each trusted section is scanned in document order. Every table is inspected independently.

Do not:

- use only the first valid table,
- merge separate tables into one logical table,
- infer evidence from non-table paragraphs.

Unrelated decorative tables are skipped.

A valid document may contain multiple independently usable evidence tables.

## Semantic Header Rules

Reuse `Get-BenefitScopedHeaderMap`. Do not create an HWPX-specific semantic dictionary.

A table is eligible only when one physical row can act as a clear semantic header.

Rules:

- the semantic header need not be the first physical row;
- title/decorative rows may precede it;
- `BusinessName` must map exactly once;
- the same semantic field mapping more than once makes that header unusable;
- multi-row semantic header composition is unsupported;
- column-position inference is unsupported.

Examples of reused fields include `BusinessName`, `Address`, `Phone`, `Branch`, `BenefitDescription`, `EligibleTarget`, `UsageCondition`, and `VerificationMethod`.

## Merged-cell Policy

Merged cells are allowed only when they are irrelevant to semantic evidence.

For every cell used as:

- a semantic header, or
- a mapped evidence value,

the physical cell must be unmerged (`rowSpan=1`, `colSpan=1`).

Decorative/title merged cells may exist elsewhere.

If a semantic header cell is merged, that header is unusable. If a mapped evidence cell is merged, that row is unusable. P4-1 does not reconstruct logical grids from row/column spans.

## Cell Text Extraction

Semantic cells support only a bounded text subset.

Allowed:

- ordinary text nodes/runs,
- paragraph boundaries,
- explicit line breaks,
- tabs.

Rules:

- preserve run order;
- do not insert spaces merely because text is split across runs;
- preserve explicit paragraph/line/tab boundaries with deterministic separators;
- trim only outer whitespace;
- do not rewrite meaningful internal text.

Unsupported complex content in a semantic header/value cell makes the affected header/row unusable. Examples include nested tables, pictures, equations, notes/footnotes, or other inline structures whose provenance cannot be represented safely by the current row/cell contract.

Complex content outside semantic evidence cells does not invalidate the whole table by itself.

## Physical Provenance

P4-1 must derive document rows from actual HWPX bytes and populate the existing P4-0 document provenance contract.

For an HWPX row:

```text
UnitReference = HWPX_SECTION_<n>_TABLE_<n>_ROW_<n>
PhysicalPath  = section/<n>/table/<n>/row/<n>
```

Each mapped field must retain:

- `FieldReference`,
- `PhysicalReference`,
- `SourceText`.

Example:

```text
FieldReference:
  HWPX_SECTION_2_TABLE_1_ROW_4/BusinessName

PhysicalReference:
  section/2/table/1/row/4/cell/1

SourceText:
  고려이발관
```

Do not fabricate XML byte offsets. The physical truth for P4-1 is package structure: section -> table -> row -> cell.

The adapter must construct the `BenefitDocumentValidationIndex` from parsed bytes, then use `New-BenefitDocumentSourceContentUnit` or the equivalent existing P4-0 construction path to create exact indexed units.

## Observation Status

Use the existing status model.

```text
package/root membership not trustworthy -> FAILED
all relevant parsed structure trustworthy -> COMPLETE
some trusted sections/tables/rows isolated -> PARTIAL
trusted document but no usable semantic BusinessName header -> UNSUPPORTED
```

Do not infer lifecycle truth from absence:

- business not found does not mean closed;
- missing benefit row does not mean benefit ended.

## Run-context Integration

Extend the existing `BenefitSourceRunContext`; do not add an HWPX-specific cache.

Required behavior for one HWPX source used by multiple businesses:

```text
fetch                = 1
snapshot              = 1
HWPX ZIP/XML parse    = 1
validation index      = 1
business lookups      = N
```

### Snapshot

Generalize the current run-context snapshot path so HWPX behaves like other byte-backed formats:

```text
Text        = ''
Bytes       = original HWPX bytes
ContentHash = SHA-256(original bytes)
```

Payload/document trust must compare HWPX bytes, not text.

### Template cache

Cache the parsed HWPX template/observation material with the existing template-cache pattern, conceptually:

`SnapshotId | HWPX_GENERIC | AdapterVersion`

Successful, partial, failed, and unsupported parser results should all avoid repeat ZIP/XML parsing for the same run-local payload.

P4-1 guarantees parse-once. It does not introduce a new trusted fast path solely to skip downstream contract validation.

## Scoped Pipeline Integration

Extend `Invoke-ScopedPhase2BenefitSourceCandidate` from the current HTML/XLSX set to:

- HTML,
- XLSX,
- HWPX.

PDF remains outside this scoped orchestration in P4-1.

Dispatch:

```text
HTML -> Get-BenefitRunHtmlObservation
XLSX -> Get-BenefitRunXlsxObservation
HWPX -> Get-BenefitRunHwpxObservation
```

The HWPX observation carries its `DocumentValidationIndex` into the existing locator.

## Binding / Extraction / Validation Bridge

P4-0 public slice validation already accepts a `DocumentValidationIndex`. P4-1 should thread that existing contract through the current scoped downstream calls.

Add an optional `DocumentValidationIndex` parameter where needed to:

- `Get-BenefitBusinessBinding`,
- `Invoke-BenefitEvidenceExtraction`,
- `ConvertTo-ValidatedBenefitEvidence`.

Existing callers must remain source-compatible.

HWPX scoped claims must use a distinct extraction method:

`SCOPED_HWPX_CELL`

Do not let HWPX fall through to `SCOPED_HTML_CELL`.

Existing binding semantics stay unchanged. A strong binding still requires the existing compatible identity evidence; HWPX does not receive a weaker or special trust rule.

## Incremental Reuse

P4-1 run-context caching is not Phase 3 incremental reuse.

Keep:

`Get-BenefitIncrementalCapability(HWPX) = NONE`

Do not add HWPX `POST_FETCH` reuse in this task.

## Test Strategy

### Parser/package contract tests

Cover at least:

- valid deterministic HWPX fixture -> observation can be built;
- missing/invalid required package members -> fail closed;
- unsafe path / duplicate entry -> fail closed;
- malformed root metadata -> `FAILED`;
- one malformed section -> `PARTIAL`;
- DTD/external entity attempt -> rejected;
- package bounds remain enforced.

### Table/header tests

Cover at least:

- merged decorative title row + unmerged semantic header/data -> accepted;
- merged BusinessName header -> unusable;
- merged mapped evidence cell -> row unusable;
- zero BusinessName header -> `UNSUPPORTED`;
- duplicate BusinessName or duplicate semantic mapping -> header unusable;
- multiple independent usable tables -> all eligible rows represented;
- multi-row header and positional guessing remain unsupported.

### Cell-text tests

Cover at least:

- adjacent runs concatenate without invented whitespace;
- explicit paragraph/line boundaries are deterministic;
- supported text remains faithful;
- nested table/picture/equation/unsupported semantic content makes the affected unit unusable.

### Provenance/tamper tests

Starting from a real deterministic fixture built into HWPX bytes, reject mutations such as:

- changed section/table/row path,
- changed cell physical reference,
- changed source text,
- changed structured field value,
- changed adapter/extractor metadata,
- validation index from another snapshot,
- caller-invented row not present in the parsed index.

These tests are the proof that P4-1 closes the P4-0 synthetic-index gap for the supported HWPX subset.

### Cross-business leakage gate

Use at least two businesses in one HWPX table.

Verify:

- business A locates only A row;
- A evidence never contains B benefit data;
- business B locates only B row;
- unresolved same-name alternatives remain ambiguous/conflicting according to existing locator rules;
- absent business becomes `NOT_FOUND` only from a `COMPLETE` observation;
- absence never becomes `ENDED`.

This is a merge gate.

### Scoped end-to-end test

Verify the supported path:

```text
official candidate
 -> fetch
 -> HWPX classification
 -> byte snapshot
 -> HWPX_GENERIC observation
 -> locator
 -> STRONG binding
 -> HWPX row slice
 -> SCOPED_HWPX_CELL claims
 -> validated evidence
```

Production behavior must remain `ProductionAction=NONE`.

### Run-context reuse test

For two businesses using the same HWPX URL in one run:

- `ExternalFetchCount = 1`,
- `AdapterParseCount = 1`,
- `AdapterReuseCount >= 1`,
- second business does not reopen/reparse the package.

Also verify failed/unsupported HWPX parse results are not repeatedly parsed within the same run.

### Regression gates

Must preserve:

- HTML scoped behavior,
- MMA JSONP behavior,
- XLSX scoped behavior,
- Phase 3 history/incremental reuse,
- XLSX POST_FETCH capability,
- PDF/HWPX incremental capability `NONE`,
- PDF scoped orchestration disabled.

Run the complete `tools/data/test-*.ps1` suite, Android unit tests, lint, debug build, and exact PR HEAD GitHub `verify-data` / `verify`.

Do not predeclare the future total number of tests; report the observed baseline and result at implementation time.

## Live-source Validation

No confirmed real official HWPX benefit source is currently available in the approved evidence inventory.

Therefore:

- deterministic structural fixture validation may be `PASS`;
- real official HWPX validation remains `NOT_OBSERVED` until a genuine source is identified;
- do not fabricate an official HWPX source or benefit row to claim live validation.

If a real source is later found during P4-1, record source, check date, and status separately before using it as evidence.

## Expected Change Area

Likely new file:

- `tools/data/lib/benefit-evidence/convert-hwpx-source-observation.ps1`

Likely modified files:

- `tools/data/lib/benefit-evidence/benefit-source-run-context.ps1`
- `tools/data/lib/benefit-evidence/invoke-scoped-benefit-source.ps1`
- `tools/data/lib/benefit-source/bind-benefit-source.ps1`
- `tools/data/lib/benefit-evidence/extract-benefit-evidence.ps1`
- `tools/data/lib/benefit-evidence/validate-benefit-evidence.ps1`

Likely tests/fixtures:

- HWPX adapter contract tests,
- run-context regression tests,
- scoped HWPX end-to-end tests,
- deterministic HWPX ZIP/XML fixture helpers.

P4-0 core contract files should remain unchanged unless post-merge implementation inspection proves a minimal contract defect.

## Risks

1. **HWPX format variance.** The table-only, text-only subset intentionally rejects layouts that cannot be proved safely.
2. **Merged-cell prevalence.** Real government documents may use merged semantic cells; P4-1 will fail closed rather than reconstruct them.
3. **No live HWPX source.** Fixture success does not prove production coverage of arbitrary HWPX documents.
4. **PARTIAL semantics.** Safely parsed rows in a partial observation are diagnostic only because the existing locator cannot claim semantic location from incomplete processing.
5. **Performance.** P4-1 removes repeated ZIP/XML parsing, but downstream strict validation may still hash/copy structures; optimize only if measurements justify it.
6. **Unmerged dependency on P4-0.** Implementation against pre-merge `dev` would be invalid. The merge gate is mandatory.

## Completion Criteria

P4-1 is complete only when all of the following are true:

- P4-0 is merged and P4-1 is based on refreshed `dev`;
- HWPX package/XML security tests pass;
- table-only semantic rules pass;
- byte-derived provenance and tamper tests pass;
- cross-business leakage gate passes;
- scoped HWPX end-to-end path passes;
- same-source fetch-once / parse-once gate passes;
- complete data regression passes;
- Android unit/lint/debug build passes;
- exact PR HEAD `verify-data` and `verify` pass;
- no new external dependency;
- no canonical/seed/apps data mutation;
- `ProductionAction=NONE`;
- HWPX incremental reuse capability remains `NONE`;
- live official HWPX status is accurately reported as observed or `NOT_OBSERVED`.

P4-1 completion does not mean Phase 4 completion. P4-2 PDF native adapter, P4-3 OCR fallback, and P4-4 integration/closeout remain separate work.

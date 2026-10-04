# Phase 4 P4-1 HWPX Generic Adapter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Parse a bounded table-based HWPX subset from original bytes into strict row/cell provenance, reuse that parse once per run, and feed the existing MILIMAP locator, binding, extraction, and validation pipeline without weakening current safety contracts.

**Architecture:** Add one thin native HWPX adapter that safely opens the HWPX ZIP/XML package, resolves trusted sections from `Contents/content.hpf`, extracts only supported table rows, and builds the existing P4-0 `BenefitDocumentValidationIndex`. Extend the existing run-context and scoped pipeline to carry that index through existing locator/binding/claim validation; do not add a parallel cache, evaluator, or document abstraction.

**Tech Stack:** PowerShell 7, .NET `System.IO.Compression`, .NET `System.Xml`, existing MILIMAP benefit-verification contracts and test scripts. No new external dependency.

**Spec:** `docs/superpowers/specs/2026-10-05-phase4-p4-1-hwpx-generic-adapter-design.md`

## Global Constraints

- **Merge gate:** Do not implement from pre-merge `dev`. PR #112 must be merged, Issue #111 must be closed, and P4-1 must start from refreshed `origin/dev` containing reviewed P4-0 HEAD `bc36bf6a7d9dc6024e5b44294d5667c162170487`.
- Current GitHub code/config is authoritative. Re-read post-merge files before editing; if file structure or signatures changed, update this plan before implementation.
- HWPX support is **native, table-only, text-only** for semantic evidence cells.
- Semantic header/data cells must be unmerged; decorative/title merged cells may exist.
- Reuse the existing `Get-BenefitScopedHeaderMap`; do not create an HWPX-specific semantic dictionary.
- Do not support paragraph-only evidence, multi-row header composition, positional column guessing, logical table stitching, PDF, OCR, legacy HWP, SNS/blog discovery, or production mutation.
- Do not add a new external library, database mechanism, authentication mechanism, API contract, or data schema.
- Do not modify `data/canonical`, `data/seed`, or `apps` data/behavior for this feature.
- Keep `ProductionAction=NONE`.
- Keep `Get-BenefitIncrementalCapability(HWPX)=NONE`; run-context parse caching is not Phase 3 incremental reuse.
- If no real official HWPX benefit source is found, report live validation as `NOT_OBSERVED`; never fabricate benefit evidence.
- P4-1 completion does not complete Phase 4.

## File Structure

**Create**
- `tools/data/lib/benefit-evidence/convert-hwpx-source-observation.ps1` — safe HWPX package/XML parsing plus table/header/cell-to-document-index conversion.
- `tools/data/testdata/benefit-evidence-hwpx/test-support.ps1` — deterministic HWPX ZIP/XML fixture builder; synthetic structure only, never benefit truth.
- `tools/data/test-hwpx-source-observation.ps1` — package/XML security, table/header/cell rules, byte-derived provenance, and tamper tests.
- `tools/data/test-phase2-scoped-hwpx.ps1` — scoped HWPX end-to-end and cross-business leakage tests.
- `docs/handover/2026-10-05-phase4-p4-1-hwpx-generic-adapter.md` — final evidence, RED→GREEN ledger, tests, non-runs, risks, next step.

**Modify**
- `tools/data/lib/benefit-evidence/benefit-source-run-context.ps1:4-7,62-94,236-259` — dot-source HWPX adapter, byte-backed HWPX snapshot trust, `Get-BenefitRunHwpxObservation`, parse-once caching.
- `tools/data/lib/benefit-evidence/invoke-scoped-benefit-source.ps1:64-168` — accept HWPX, dispatch adapter, thread `DocumentValidationIndex`.
- `tools/data/lib/benefit-source/bind-benefit-source.ps1:48-86` — optional `DocumentValidationIndex` for scoped document-slice assertion.
- `tools/data/lib/benefit-evidence/extract-benefit-evidence.ps1:114-142` — optional `DocumentValidationIndex`, `SCOPED_HWPX_CELL`.
- `tools/data/lib/benefit-evidence/validate-benefit-evidence.ps1:70-84` — optional `DocumentValidationIndex` for scoped claim validation.
- `tools/data/test-benefit-source-run-context.ps1` — HWPX fetch/snapshot/parse reuse and byte-mismatch tests.
- `tools/data/test-bind-benefit-source.ps1` — HWPX slice binding contract regression.
- `tools/data/test-extract-benefit-evidence.ps1` — HWPX scoped claim method/reference regression.
- `tools/data/test-validate-benefit-evidence.ps1` — HWPX validation-index threading and foreign-row rejection.
- `tools/data/README.md` — accurate supported-source status.
- `docs/current-work.md` — P4-1 status only after implementation evidence exists.

**Prefer no change**
- `tools/data/lib/benefit-evidence/document-source-provenance.ps1`
- `tools/data/lib/benefit-evidence-location-contracts.ps1`
- `tools/data/lib/benefit-evidence/find-business-evidence-slice.ps1`

If P4-1 cannot be implemented without changing these P4-0 contracts, stop and review the discovered contract defect before widening scope.

## Review Focus

1. **Manifest/spine ambiguity or unsafe section href** — duplicate IDs, duplicate spine references, missing manifest targets, traversal, or non-section targets must fail closed; Task 1 pins these cases.
2. **Namespace variance** — equivalent namespace prefixes must not matter, while wrong HWPX namespace URIs must not be treated as trusted table/text nodes; Task 1/2 pins this.
3. **Nested tables** — a table nested inside a semantic cell must make that cell/row unusable and must not be separately promoted as a top-level evidence table; Task 2 pins this.
4. **Mixed text structure** — adjacent runs must concatenate without invented spaces; paragraph/line/tab separators must be deterministic; unsupported inline objects in semantic cells must fail closed; Task 2 pins this.
5. **Cached failure/partial results** — the same malformed/partial HWPX source used by multiple businesses must be fetched/parsed once and must never produce semantic `LOCATED` or `NOT_FOUND`; Tasks 3 and 5 pin this.

---

## Mandatory Execution Preflight

Before Task 1:

1. `git fetch origin --prune`.
2. Confirm PR #112 is merged and Issue #111 is closed.
3. Record the new `origin/dev` SHA in the P4-1 handover draft.
4. Confirm reviewed P4-0 HEAD is an ancestor of refreshed dev:
   `git merge-base --is-ancestor bc36bf6a7d9dc6024e5b44294d5667c162170487 origin/dev`
   Expected: exit code 0.
5. Create a new isolated P4-1 branch/worktree from refreshed `origin/dev`; do not reuse the P4-0 implementation branch.
6. Re-open the files listed above and compare signatures/line ranges with this plan. If material differences exist, revise the plan before editing code.

---

### Task 1: Safe HWPX Package and Section Reader

**Files:**
- Create: `tools/data/testdata/benefit-evidence-hwpx/test-support.ps1`
- Create: `tools/data/test-hwpx-source-observation.ps1`
- Create: `tools/data/lib/benefit-evidence/convert-hwpx-source-observation.ps1`

**Interfaces:**
- Consumes: byte-backed HWPX `BenefitSourceSnapshot`; existing `Test-BenefitHwpxBinaryPackage -Bytes`.
- Produces: `Read-InternalBenefitHwpxPackage -Snapshot <BenefitSourceSnapshot> -> pscustomobject` with exact properties `Status`, `Sections`, `Diagnostics`.
- Each successful section record has exact properties `SectionOrdinal` (1-based spine order), `EntryName`, and `Xml` (safely parsed XML document).
- `Status` is `COMPLETE`, `PARTIAL`, or `FAILED`; no semantic location status is produced here.

- [ ] **Step 1: Add deterministic HWPX package fixture helpers**

In `test-support.ps1`, add fixture-only helpers that generate a byte[] ZIP with:
- exact `mimetype=application/hwp+zip`;
- `Contents/content.hpf` containing manifest + spine;
- one or more `Contents/sectionN.xml` entries;
- configurable content.hpf override, section XML override, and extra entries for negative cases.

Use synthetic business strings only. Do not copy real benefit data into fixtures.

- [ ] **Step 2: Write RED package/root security assertions**

In `test-hwpx-source-observation.ps1`, assert:

```powershell
$result = Read-InternalBenefitHwpxPackage -Snapshot $snapshot
Assert-HwpxEqual $result.Status 'COMPLETE' 'valid package resolves trusted section'

Assert-HwpxEqual (Read-InternalBenefitHwpxPackage -Snapshot $malformedRoot).Status 'FAILED' 'malformed content.hpf fails closed'
Assert-HwpxEqual (Read-InternalBenefitHwpxPackage -Snapshot $unsafeHref).Status 'FAILED' 'unsafe spine href fails closed'
Assert-HwpxEqual (Read-InternalBenefitHwpxPackage -Snapshot $duplicateId).Status 'FAILED' 'duplicate manifest identity fails closed'
Assert-HwpxEqual (Read-InternalBenefitHwpxPackage -Snapshot $missingTarget).Status 'FAILED' 'missing section target fails closed'
```

Also add the Review Focus case: duplicate spine itemref / duplicate resolved section must fail closed rather than parse the same physical section twice.

- [ ] **Step 3: Write RED XML safety and partial-section assertions**

Add:
- DTD / external entity content in `content.hpf` -> `FAILED`;
- wrong OPF namespace -> `FAILED`;
- equivalent XML prefixes with the same trusted namespace URI -> accepted;
- one malformed section among two trusted spine sections -> `PARTIAL`, with only the valid section in `Sections`;
- DTD/external entity in one section -> that section is isolated and overall status `PARTIAL`.

Expected RED: function missing or current code cannot parse content.hpf/spine.

- [ ] **Step 4: Run the new test to observe RED**

Run:

```powershell
& .\tools\data\test-hwpx-source-observation.ps1
```

Expected: FAIL because `Read-InternalBenefitHwpxPackage` / adapter file does not exist yet.

- [ ] **Step 5: Implement `Read-InternalBenefitHwpxPackage`**

Signature:

```powershell
function Read-InternalBenefitHwpxPackage {
    param([Parameter(Mandatory)]$Snapshot)
}
```

Required behavior:
- assert `Snapshot.SourceFormat -ceq 'HWPX'`, empty Text, non-empty byte[] through existing snapshot contracts;
- re-check `Test-BenefitHwpxBinaryPackage -Bytes $Snapshot.Bytes` before semantic parsing;
- open the byte[] with `IO.MemoryStream` + `IO.Compression.ZipArchive` in read mode;
- rely on P4-0 package bounds and independently build an ordinal, case-insensitive entry lookup with no duplicates;
- parse `Contents/content.hpf` using `XmlReaderSettings` with DTD prohibited and `XmlResolver=$null`;
- resolve section membership/order from OPF manifest + spine only;
- every spine `itemref.idref` must resolve exactly once to a manifest item whose normalized package-local href resolves under `Contents/` to `section[0-9]+.xml`;
- reject traversal, absolute paths, duplicate manifest IDs, duplicate resolved section entries, missing targets, or non-section targets;
- parse each resolved section with the same safe XML settings;
- assign `SectionOrdinal` from spine order starting at 1, independent of filename suffix;
- root/manifest/spine trust failures -> `FAILED`;
- isolated section parse failure -> `PARTIAL` plus diagnostic and continue.

Do not execute scripts, resolve external resources, or inspect BinData for evidence.

- [ ] **Step 6: Run Task 1 tests to GREEN**

Run:

```powershell
& .\tools\data\test-hwpx-source-observation.ps1
& .\tools\data\test-discover-official-benefit-sources.ps1
```

Expected: PASS. P4-0 HWPX recognition remains unchanged.

- [ ] **Step 7: Commit Task 1**

```bash
git add tools/data/lib/benefit-evidence/convert-hwpx-source-observation.ps1 tools/data/test-hwpx-source-observation.ps1 tools/data/testdata/benefit-evidence-hwpx/test-support.ps1
git commit -m "feat: add safe HWPX package reader"
```

---

### Task 2: Table/Header/Cell Extraction and Byte-Derived Document Provenance

**Files:**
- Modify: `tools/data/lib/benefit-evidence/convert-hwpx-source-observation.ps1`
- Modify: `tools/data/test-hwpx-source-observation.ps1`
- Modify: `tools/data/testdata/benefit-evidence-hwpx/test-support.ps1`

**Interfaces:**
- Consumes: Task 1 `Read-InternalBenefitHwpxPackage`; existing `Get-BenefitScopedHeaderMap`, `New-BenefitDocumentValidationIndex`, `New-BenefitDocumentSourceContentUnit`, `New-BenefitSourceObservation`.
- Produces:
  - `ConvertTo-InternalBenefitHwpxObservation -Document <BenefitSourceDocument> -Snapshot <BenefitSourceSnapshot> -> SourceObservation`
  - `ConvertTo-BenefitHwpxObservation -Document <BenefitSourceDocument> [-Snapshot <BenefitSourceSnapshot>] -> SourceObservation`
- Adapter metadata is fixed:
  - `AdapterId='HWPX_GENERIC'`
  - `AdapterVersion='1'`
  - `ExtractionMethod='STRUCTURED_HWPX_ROW'`
  - `ExtractorId='BUILTIN_HWPX_XML'`
  - `ExtractorVersion='1'`
- `ExtractionConfigHash` is SHA-256 over a deterministic UTF-8 config string containing the adapter/extractor versions, table-only/unmerged/text-only rules, and the sorted key/value pairs returned by `Get-BenefitScopedHeaderMap`.

- [ ] **Step 1: Write RED table/header mapping tests**

Extend the fixture helper with table/row/cell XML builders and assert:

```powershell
$observation = ConvertTo-BenefitHwpxObservation -Document $document
Assert-HwpxEqual $observation.AdapterStatus 'COMPLETE' 'supported table parses completely'
Assert-HwpxEqual $observation.ContentUnits[0].UnitReference 'HWPX_SECTION_1_TABLE_1_ROW_2' 'physical row identity is stable'
Assert-HwpxEqual $observation.ContentUnits[0].StructuredFields.BusinessName '합성가게 A' 'semantic header map is reused'
```

Add cases:
- decorative merged title row + unmerged semantic header/data -> accepted;
- BusinessName header merged -> unusable;
- mapped data cell merged -> that row unusable;
- no BusinessName header -> `UNSUPPORTED`;
- duplicate BusinessName or duplicate semantic field -> header unusable;
- multiple top-level tables -> all usable rows represented independently;
- multi-row semantic header and positional guessing -> unsupported, never inferred.

- [ ] **Step 2: Write RED cell-text and nested-table tests**

Pin:
- adjacent `hp:run/hp:t` fragments become one string with no invented space;
- paragraph boundary uses one deterministic newline;
- explicit `hp:lineBreak` uses newline;
- explicit `hp:tab` uses tab;
- outer whitespace is trimmed;
- nested table/picture/equation/note/unsupported inline object inside a semantic cell makes that header/row unusable;
- a nested table is not enumerated as another top-level evidence table;
- equivalent namespace prefix with correct paragraph namespace works; wrong namespace URI is ignored/rejected as unsupported structure.

For cell spans, accept a provable 1x1 span from the supported HWPX cell-span representation; reject span >1 or conflicting/invalid span metadata. Do not expand a logical grid.

- [ ] **Step 3: Write RED provenance/tamper assertions**

From bytes produced by the fixture, assert the adapter creates:

```text
HWPX_SECTION_<1-based spine ordinal>_TABLE_<1-based top-level table ordinal>_ROW_<1-based row ordinal>
section/<section>/table/<table>/row/<row>/cell/<1-based cell ordinal>
```

Then mutate copies and assert rejection through existing P4-0 contract functions:
- physical path;
- cell physical reference;
- `SourceText`;
- structured field value;
- adapter/extractor metadata;
- cross-snapshot validation index;
- caller-invented unit reference.

This test must use an index generated by the HWPX adapter from fixture bytes, not `New-DocumentTestRowRecord`.

- [ ] **Step 4: Run Task 2 tests to observe RED**

Run:

```powershell
& .\tools\data\test-hwpx-source-observation.ps1
```

Expected: package tests remain PASS; table/provenance assertions FAIL because conversion is not implemented.

- [ ] **Step 5: Implement table-only conversion**

Implement the two produced functions. Required rules:

- inspect only top-level HWPX tables in each trusted section, in document order; a table under another table is never a separate evidence table;
- number section/table/row/cell physical identities from 1 in document order;
- only one physical row may act as the semantic header;
- header text is the supported extracted text after outer trim and must match an existing `Get-BenefitScopedHeaderMap` key; do not normalize/guess new aliases;
- BusinessName must map exactly once; duplicate mapped semantic fields make the header unusable;
- mapped semantic header/data cells must be provably unmerged;
- after the header, a row without a non-empty BusinessName value is skipped;
- if a mapped semantic value cell is unsupported, mark that row unusable and emit an HWPX parser diagnostic;
- build `RawEvidenceText` deterministically from non-empty mapped field values in physical column order joined by `' | '`;
- build field references with exact `FieldReference`, `PhysicalReference`, and `SourceText`;
- construct one `BenefitDocumentValidationIndex` from the parsed rows, then content units from that index;
- package reader `FAILED` -> observation `FAILED`;
- package reader `PARTIAL` or any isolated relevant table/header/row failure -> observation `PARTIAL`;
- trusted document with no usable BusinessName semantic header -> `UNSUPPORTED`;
- otherwise -> `COMPLETE`.

A `PARTIAL` observation may retain safely built content units for audit, but downstream slice production remains forbidden by existing contracts.

- [ ] **Step 6: Run Task 2 targeted regressions**

Run:

```powershell
& .\tools\data\test-hwpx-source-observation.ps1
& .\tools\data\test-document-source-provenance.ps1
& .\tools\data\test-benefit-evidence-location-contracts.ps1
```

Expected: PASS. No P4-0 contract change required.

- [ ] **Step 7: Commit Task 2**

```bash
git add tools/data/lib/benefit-evidence/convert-hwpx-source-observation.ps1 tools/data/test-hwpx-source-observation.ps1 tools/data/testdata/benefit-evidence-hwpx/test-support.ps1
git commit -m "feat: convert HWPX tables to document evidence"
```

---

### Task 3: Run-context HWPX Snapshot and Parse-once Reuse

**Files:**
- Modify: `tools/data/lib/benefit-evidence/benefit-source-run-context.ps1:4-7,62-94,236-259`
- Modify: `tools/data/test-benefit-source-run-context.ps1`

**Interfaces:**
- Consumes: Task 2 `ConvertTo-InternalBenefitHwpxObservation`.
- Produces: `Get-BenefitRunHwpxObservation -Context <BenefitSourceRunContext> -Document <BenefitSourceDocument> -> SourceObservation`.
- Cache key: `"$($snapshot.SnapshotId)|HWPX_GENERIC|1"`.

- [ ] **Step 1: Write RED HWPX snapshot identity tests**

Add assertions that:
- `Get-BenefitRunSourceSnapshot` accepts COMPLETE HWPX;
- snapshot Text is empty and Bytes/content hash match the cached original HWPX payload;
- an untrusted HWPX document wrapper with different bytes from the cached payload is rejected;
- HTML/XLSX behavior remains unchanged.

Expected RED: current source snapshot accepts only HTML/XLSX.

- [ ] **Step 2: Write RED parse-once/reuse tests**

Use two normalized businesses and the same candidate URL/run context. Assert:

```powershell
Assert-ScopeEqual $context.Metrics.ExternalFetchCount 1 'HWPX source fetched once'
Assert-ScopeEqual $context.Metrics.AdapterParseCount 1 'HWPX ZIP/XML parsed once'
Assert-ScopeTrue ($context.Metrics.AdapterReuseCount -ge 1) 'second HWPX observation reuses parsed template'
```

Add Review Focus coverage with a PARTIAL/malformed-section fixture: two calls must still produce `AdapterParseCount=1`; the cached incomplete result is reused rather than reparsed.

- [ ] **Step 3: Run RED**

Run:

```powershell
& .\tools\data\test-benefit-source-run-context.ps1
```

Expected: FAIL on HWPX snapshot/observation support.

- [ ] **Step 4: Generalize `Get-BenefitRunSourceSnapshot`**

Change allowed formats from `HTML/XLSX` to `HTML/XLSX/HWPX`.

For untrusted wrappers:
- HTML compares Text;
- XLSX/HWPX compare byte[] using sequence equality.

When creating a snapshot:
- HTML remains text-backed;
- XLSX/HWPX remain byte-backed with original payload bytes.

Do not add `ValidatedHwpxSnapshot` or a new trust registry in this task; strict downstream document-index validation remains enabled.

- [ ] **Step 5: Implement `Get-BenefitRunHwpxObservation`**

Dot-source `convert-hwpx-source-observation.ps1` at the top of run-context.

Signature:

```powershell
function Get-BenefitRunHwpxObservation {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$Document)
}
```

Behavior:
- require COMPLETE/HWPX;
- get cached byte-backed snapshot;
- use key `SnapshotId|HWPX_GENERIC|1`;
- first call invokes `ConvertTo-InternalBenefitHwpxObservation`, increments `AdapterParseCount`, and caches the template;
- later calls increment `AdapterReuseCount`;
- every call records one PARSE attempt with cache-hit flag/status;
- reconstruct a fresh `New-BenefitSourceObservation` for the current SourceRowNumber using cached units/diagnostics/index;
- attach the cached `DocumentValidationIndex` to the returned observation through the existing P4-0 constructor path.

- [ ] **Step 6: Run Task 3 regressions to GREEN**

Run:

```powershell
& .\tools\data\test-benefit-source-run-context.ps1
& .\tools\data\test-hwpx-source-observation.ps1
& .\tools\data\test-phase2-scoped-xlsx.ps1
```

Expected: PASS.

- [ ] **Step 7: Commit Task 3**

```bash
git add tools/data/lib/benefit-evidence/benefit-source-run-context.ps1 tools/data/test-benefit-source-run-context.ps1
git commit -m "feat: reuse HWPX parsing per source run"
```

---

### Task 4: Thread DocumentValidationIndex Through Binding, Extraction, and Validation

**Files:**
- Modify: `tools/data/lib/benefit-source/bind-benefit-source.ps1:48-86`
- Modify: `tools/data/lib/benefit-evidence/extract-benefit-evidence.ps1:114-142`
- Modify: `tools/data/lib/benefit-evidence/validate-benefit-evidence.ps1:70-84`
- Modify: `tools/data/test-bind-benefit-source.ps1`
- Modify: `tools/data/test-extract-benefit-evidence.ps1`
- Modify: `tools/data/test-validate-benefit-evidence.ps1`

**Interfaces:**
- Existing signatures gain one optional parameter: `[AllowNull()]$DocumentValidationIndex=$null`.
- Existing HTML/JSONP/XLSX callers remain source-compatible.
- HWPX scoped extraction uses `ExtractionMethod='SCOPED_HWPX_CELL'`.

- [ ] **Step 1: Write RED HWPX binding assertion**

Build a COMPLETE HWPX observation from Task 2 fixture bytes, locate/create its slice using the existing document index, and call:

```powershell
Get-BenefitBusinessBinding -Source $qualified -Business $business -CanonicalPhone $phone -EvidenceSlice $slice -DocumentValidationIndex $observation.DocumentValidationIndex
```

Assert STRONG for exact name+address/phone, and assert a slice validated against the wrong document index is rejected.

- [ ] **Step 2: Write RED extraction assertions**

Call:

```powershell
Invoke-BenefitEvidenceExtraction -Source $bound -Document $document -EvidenceSlice $slice -DocumentValidationIndex $index
```

Assert:
- benefit claim value comes only from that HWPX row;
- `ExtractionMethod -ceq 'SCOPED_HWPX_CELL'`;
- `EvidenceReference` is the indexed HWPX field reference;
- another business row never appears in the claim.

- [ ] **Step 3: Write RED validation assertions**

Call:

```powershell
ConvertTo-ValidatedBenefitEvidence -Extraction $extraction -Document $document -EvidenceSlice $slice -DocumentValidationIndex $index
```

Assert COMPLETE for the valid indexed row and INVALID/rejection for a foreign/tampered row reference.

- [ ] **Step 4: Run RED**

Run:

```powershell
& .\tools\data\test-bind-benefit-source.ps1
& .\tools\data\test-extract-benefit-evidence.ps1
& .\tools\data\test-validate-benefit-evidence.ps1
```

Expected: HWPX calls fail because the optional parameter is not threaded and extraction falls through to `SCOPED_HTML_CELL`.

- [ ] **Step 5: Add optional document-index parameters**

In all three functions, forward `DocumentValidationIndex` into `Assert-RelevantBenefitEvidenceSlice` / scoped claim validation while preserving existing `XlsxValidationIndex`.

In `Invoke-BenefitEvidenceExtraction`, map:
- JSONP -> `SCOPED_JSONP_FIELD`
- XLSX -> `SCOPED_XLSX_CELL`
- HWPX -> `SCOPED_HWPX_CELL`
- HTML -> `SCOPED_HTML_CELL`

Do not enable unscoped HWPX extraction and do not touch the old PDF extractor path.

- [ ] **Step 6: Run Task 4 regressions to GREEN**

Run the three tests above plus:

```powershell
& .\tools\data\test-document-source-provenance.ps1
& .\tools\data\test-phase2-scoped-xlsx.ps1
```

Expected: PASS.

- [ ] **Step 7: Commit Task 4**

```bash
git add tools/data/lib/benefit-source/bind-benefit-source.ps1 tools/data/lib/benefit-evidence/extract-benefit-evidence.ps1 tools/data/lib/benefit-evidence/validate-benefit-evidence.ps1 tools/data/test-bind-benefit-source.ps1 tools/data/test-extract-benefit-evidence.ps1 tools/data/test-validate-benefit-evidence.ps1
git commit -m "feat: validate scoped HWPX document claims"
```

---

### Task 5: Scoped HWPX Orchestration and Cross-business Leakage Gate

**Files:**
- Modify: `tools/data/lib/benefit-evidence/invoke-scoped-benefit-source.ps1:64-168`
- Create: `tools/data/test-phase2-scoped-hwpx.ps1`
- Reuse: `tools/data/testdata/benefit-evidence-hwpx/test-support.ps1`

**Interfaces:**
- Consumes: Task 3 `Get-BenefitRunHwpxObservation`; Task 4 document-index-aware binding/extraction/validation.
- Produces: existing `Invoke-ScopedPhase2BenefitSourceCandidate` now accepts official HTML/XLSX/HWPX source formats without changing its return shape.

- [ ] **Step 1: Write RED supported HWPX end-to-end test**

Use an official PUBLIC_OFFICIAL candidate and RequestInvoker returning HWPX bytes. Assert:

```text
Document.SourceFormat = HWPX
Observation.AdapterId = HWPX_GENERIC
LocationResult.Status = LOCATED
Bound.BusinessBindingStatus = STRONG
Extraction claim method = SCOPED_HWPX_CELL
Validation.Status = COMPLETE
```

The returned record shape must remain identical to existing scoped source records.

- [ ] **Step 2: Write RED cross-business leakage gate**

Create one HWPX source with:
- row A: business A identity + synthetic benefit A;
- row B: business B identity + synthetic benefit B.

Using the same run context/source:
- A lookup returns exactly A row/slice/benefit;
- B lookup returns exactly B row/slice/benefit;
- A output contains no B benefit text and vice versa;
- duplicate corroborated same-name alternatives remain AMBIGUOUS;
- complete absence may return `NOT_FOUND`;
- absence never introduces `BenefitState=ENDED`.

- [ ] **Step 3: Write RED incomplete-source semantics**

With a two-section fixture where one trusted section is malformed:
- observation is `PARTIAL`;
- location `OperationalStatus='PARTIAL'`;
- `LocationResult.Status` is null;
- slices count is 0;
- validation does not claim success from the remaining row;
- two business lookups still keep `AdapterParseCount=1`.

Also assert PDF remains rejected by this runner in P4-1.

- [ ] **Step 4: Run RED**

Run:

```powershell
& .\tools\data\test-phase2-scoped-hwpx.ps1
```

Expected: FAIL because scoped runner currently accepts only HTML/XLSX.

- [ ] **Step 5: Extend scoped preparation to HWPX**

In `Invoke-ScopedPhase2BenefitSourceCandidate`:
- allowed formats become `HTML/XLSX/HWPX`;
- dispatch HWPX to `Get-BenefitRunHwpxObservation`;
- create `$documentValidationIndex` from the observation when present;
- pass it to `Find-BenefitBusinessEvidence`, `Get-BenefitBusinessBinding`, `Invoke-BenefitEvidenceExtraction`, and `ConvertTo-ValidatedBenefitEvidence`;
- add HWPX-specific preparation failure diagnostic (for example `HWPX_PREPARATION_FAILED`) and fail closed with existing allowed reason code `SOURCE_UNSUPPORTED` or `EXTRACTION_FAILED` as appropriate;
- do not rename unrelated established diagnostics solely for cleanup;
- do not add PDF to the allowed set.

- [ ] **Step 6: Run Task 5 targeted regressions to GREEN**

Run:

```powershell
& .\tools\data\test-phase2-scoped-hwpx.ps1
& .\tools\data\test-phase2-scoped-xlsx.ps1
& .\tools\data\test-phase2-benefit-shadow-mode.ps1
& .\tools\data\test-find-business-evidence-slice.ps1
& .\tools\data\test-benefit-incremental-reuse.ps1
```

Expected: PASS. The existing incremental test must still report HWPX capability `NONE`.

- [ ] **Step 7: Commit Task 5**

```bash
git add tools/data/lib/benefit-evidence/invoke-scoped-benefit-source.ps1 tools/data/test-phase2-scoped-hwpx.ps1
git commit -m "feat: integrate scoped HWPX evidence"
```

---

### Task 6: Full Regression, Handover, and Merge Evidence

**Files:**
- Create: `docs/handover/2026-10-05-phase4-p4-1-hwpx-generic-adapter.md`
- Modify: `docs/current-work.md`
- Modify: `tools/data/README.md`
- Modify only if a regression proves necessary: tests already listed above.

**Interfaces:**
- Consumes: Tasks 1-5.
- Produces: reviewable P4-1 branch/PR evidence only. No new runtime behavior belongs in this task.

- [ ] **Step 1: Run all P4-1 targeted tests**

Run at minimum:

```powershell
& .\tools\data\test-hwpx-source-observation.ps1
& .\tools\data\test-document-source-provenance.ps1
& .\tools\data\test-benefit-source-run-context.ps1
& .\tools\data\test-bind-benefit-source.ps1
& .\tools\data\test-extract-benefit-evidence.ps1
& .\tools\data\test-validate-benefit-evidence.ps1
& .\tools\data\test-phase2-scoped-hwpx.ps1
& .\tools\data\test-phase2-scoped-xlsx.ps1
& .\tools\data\test-find-business-evidence-slice.ps1
& .\tools\data\test-benefit-incremental-reuse.ps1
```

Expected: all PASS.

- [ ] **Step 2: Run the complete data suite**

Run:

```powershell
$ErrorActionPreference = 'Stop'
Get-ChildItem -LiteralPath tools/data -Filter 'test-*.ps1' |
  Sort-Object Name |
  ForEach-Object { & $_.FullName }
```

Record the observed baseline and final count. Do not predeclare a count.

- [ ] **Step 3: Run Android regression from `apps/android`**

Run:

```powershell
.\gradlew.bat assembleDebugUnitTest testDebugUnitTest --stacktrace
.\gradlew.bat lintDebug assembleDebug --stacktrace
```

Expected: unit tests PASS, lint PASS, debug APK build PASS. If local Java environment prevents execution, record the exact non-run reason and rely on exact-head CI only after reporting the limitation.

- [ ] **Step 4: Run protected-diff and whitespace gates**

Run from repo root:

```powershell
git diff --check
git diff origin/dev -- data/canonical data/seed apps
```

Expected:
- `git diff --check`: no output / success.
- protected-data/app diff: empty.
- no dependency/workflow changes.

Also explicitly confirm `Get-BenefitIncrementalCapability(HWPX)` remains `NONE` and no production-action path was added.

- [ ] **Step 5: Write handover and status docs**

Handover must include:
- refreshed `origin/dev` base SHA;
- Issue/PR numbers once created;
- changed files;
- RED→GREEN task ledger and commit SHAs;
- parser-supported subset;
- exact adapter/extractor/config metadata;
- targeted/full test results;
- Android results;
- exact-head CI results;
- live HWPX validation status (`NOT_OBSERVED` unless a real official source was actually checked);
- tests not run;
- protected diff result;
- remaining risks;
- next task: P4-2 PDF native adapter;
- explicit statement: Phase 4 is not COMPLETE.

Update README/current-work only with facts already proven by tests.

- [ ] **Step 6: Commit closeout docs**

```bash
git add docs/handover/2026-10-05-phase4-p4-1-hwpx-generic-adapter.md docs/current-work.md tools/data/README.md
git commit -m "docs: record P4-1 HWPX adapter evidence"
```

- [ ] **Step 7: Open the P4-1 PR without auto-merge**

PR scope must be only P4-1 and reference its Issue. State clearly:
- no external dependency;
- no PDF/OCR;
- no production mutation;
- HWPX reuse capability remains NONE;
- live official HWPX is NOT_OBSERVED unless actually checked.

Do not merge automatically.

- [ ] **Step 8: Require exact PR HEAD CI before merge recommendation**

Exact final PR HEAD must pass:
- `verify-data`;
- `verify`.

After CI, perform one whole-branch read-only review focused on Critical/Important findings. Only then recommend merge.

---

## Implementation Report Contract

Every implementation report for this plan must include:

- **변경한 파일**
- **구현 내용**
- **실행한 테스트**
- **실행하지 못한 테스트**
- **남은 위험**
- **다음 작업**

End each report with:
- Phase: Phase 4 — Multi-source Adapters
- Stage: P4-1 HWPX Generic Adapter
- Status: exact current implementation/review/merge state

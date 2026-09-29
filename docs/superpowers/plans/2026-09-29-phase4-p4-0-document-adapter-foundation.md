# Phase 4 P4-0 Document Adapter Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the minimal byte-backed source and physical-provenance foundation required for later PDF/HWPX adapters without introducing a parser dependency or changing production approval behavior.

**Architecture:** Keep the existing `SourceDocument -> Snapshot -> SourceObservation -> SourceContentUnit -> EvidenceSlice` pipeline. P4-0 only teaches the shared contracts to recognize HWPX, preserve PDF/HWPX bytes, and validate document-row units against an exact validation index; it does not parse real PDF/HWPX documents or enable scoped Phase 4 orchestration yet.

**Tech Stack:** PowerShell 7, existing .NET runtime, `System.IO.Compression` for test/package inspection, existing MILIMAP benefit verification/history helpers. No new external library is permitted in P4-0.

**Spec:** `docs/superpowers/specs/2026-09-29-phase4-multi-source-adapters-design.md`

## Global Constraints

- Baseline implementation starts from the latest `origin/dev`; the design baseline was `28a6845684e94cd3490fcc1c4112ef6fce402205`.
- `ProductionAction = NONE` remains unchanged.
- No canonical, seed, or app automatic writes.
- No automatic `ENDED` or `CLOSED` inference from source absence.
- Existing HTML, JSONP, and XLSX semantics must remain unchanged.
- No external dependency is added in P4-0.
- PDF/HWPX incremental reuse capability remains `NONE` in P4-0.
- PDF/HWPX real parsing, OCR, layout-specific adapters, scheduler, SNS/blog, discovery, and legacy HWP are out of scope.
- Work must follow TDD RED -> GREEN and remain one Issue/PR-sized change.

## Review Focus

1. A response claiming `application/pdf` but carrying non-PDF bytes must not become a trusted PDF document; add this case to Task 1.
2. A generic ZIP with an `.hwpx` name but missing the HWPX mimetype/package markers must remain `UNSUPPORTED`; add this case to Task 1.
3. Byte-backed PDF/HWPX snapshots must hash their bytes, reject payload mutation, and leave existing XLSX behavior unchanged; add this case to Task 2.
4. A PDF/HWPX `SourceContentUnit` that is not an exact member of its validation index must be rejected so callers cannot fabricate physical provenance; add this case to Task 3.
5. Merely recognizing PDF/HWPX must not silently enable Phase 3 post-fetch reuse; add explicit `NONE` assertions to Task 4.

---

## File Structure

### Existing files to modify

- `tools/data/lib/benefit-verification-contracts.ps1`
  - Add `HWPX` to the existing SourceFormat vocabulary only.
- `tools/data/lib/benefit-source/discover-official-benefit-sources.ps1`
  - Add byte-first bounded PDF/HWPX classification helpers while preserving HTML/CSV/XLSX behavior.
- `tools/data/lib/benefit-evidence-location-contracts.ps1`
  - Generalize byte-backed snapshots and dispatch document units/slices through a focused helper file.
- `tools/data/lib/benefit-evidence/find-business-evidence-slice.ps1`
  - Allow locator validation/slice construction to use a document validation index carried by an observation.
- `tools/data/lib/history/benefit-incremental-reuse.ps1`
  - No capability expansion; touch only if a defensive explicit guard is required by tests.
- Existing tests:
  - `tools/data/test-benefit-verification-contracts.ps1`
  - `tools/data/test-discover-official-benefit-sources.ps1`
  - `tools/data/test-benefit-evidence-location-contracts.ps1`
  - `tools/data/test-find-business-evidence-slice.ps1`
  - `tools/data/test-benefit-incremental-reuse.ps1`

### New files

- `tools/data/lib/benefit-evidence/document-source-provenance.ps1`
  - Own the strict PDF/HWPX validation-index and document-row `SourceContentUnit` validation helpers.
- `tools/data/test-document-source-provenance.ps1`
  - Deterministic contract tests for PDF/HWPX document-row provenance.
- `tools/data/testdata/benefit-evidence-document/test-support.ps1`
  - Synthetic PDF/HWPX package/validation-index fixtures only; no canonical benefit truth.
- `docs/handover/2026-09-29-phase4-p4-0-document-adapter-foundation.md`
  - Record implemented boundary, tests, non-goals, and remaining P4-1+ work.

---

### Task 1: Add safe PDF/HWPX source classification

**Files:**
- Modify: `tools/data/lib/benefit-verification-contracts.ps1`
- Modify: `tools/data/lib/benefit-source/discover-official-benefit-sources.ps1`
- Modify: `tools/data/test-benefit-verification-contracts.ps1`
- Modify: `tools/data/test-discover-official-benefit-sources.ps1`
- Create: `tools/data/testdata/benefit-evidence-document/test-support.ps1`

**Interfaces:**
- Consumes: existing `Get-BenefitSourceFormat -Url -ContentType -Bytes` and `Get-BenefitSourceDocument -Candidate -RequestInvoker`.
- Produces:
  - `Test-BenefitPdfBinaryPackage -Bytes ([byte[]]) -> [bool]`
  - `Test-BenefitHwpxBinaryPackage -Bytes ([byte[]]) -> [bool]`
  - unchanged `Get-BenefitSourceFormat` signature returning `HWPX` for a safely recognized HWPX package.
- HWPX fixture recognition requires a ZIP package whose `mimetype` entry is exactly `application/hwp+zip` and whose expected document package structure includes `Contents/content.hpf` plus at least one `Contents/section*.xml` entry.
- PDF recognition requires a valid PDF header signature from the fetched bytes; content type/extension alone is not sufficient when bytes are present.

- [ ] **Step 1: Write failing SourceFormat contract tests**

Add `HWPX` to the expected SourceFormat set in `test-benefit-verification-contracts.ps1`.

Add tests in `test-discover-official-benefit-sources.ps1` asserting:
- synthetic HWPX bytes + generic/octet-stream MIME -> `HWPX`;
- `.hwpx` URL + arbitrary ZIP -> `UNSUPPORTED`;
- `application/pdf` + valid PDF signature bytes -> `PDF`;
- `application/pdf` + non-PDF bytes -> `UNSUPPORTED`;
- existing XLSX extensionless/octet-stream package detection still -> `XLSX`;
- existing HTML/CSV text cases remain unchanged.

- [ ] **Step 2: Run RED**

Run:
```powershell
pwsh -NoProfile -File tools/data/test-benefit-verification-contracts.ps1
pwsh -NoProfile -File tools/data/test-discover-official-benefit-sources.ps1
```

Expected: FAIL because `HWPX` is not an allowed SourceFormat and PDF/HWPX byte validation helpers do not exist.

- [ ] **Step 3: Implement the minimal classification helpers**

In `benefit-verification-contracts.ps1`, add only `HWPX` to SourceFormat.

In `discover-official-benefit-sources.ps1`, implement:

```powershell
function Test-BenefitPdfBinaryPackage {
    param([AllowNull()][byte[]]$Bytes)
}

function Test-BenefitHwpxBinaryPackage {
    param([AllowNull()][byte[]]$Bytes)
}
```

Keep `Get-BenefitSourceFormat -Url -ContentType -Bytes` public signature unchanged. When bytes are present for a claimed PDF/HWPX/XLSX attachment, prefer validated bytes/package structure over content type or filename. Do not broaden support to legacy HWP.

- [ ] **Step 4: Run GREEN**

Run the two tests from Step 2.

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tools/data/lib/benefit-verification-contracts.ps1 tools/data/lib/benefit-source/discover-official-benefit-sources.ps1 tools/data/test-benefit-verification-contracts.ps1 tools/data/test-discover-official-benefit-sources.ps1 tools/data/testdata/benefit-evidence-document/test-support.ps1
git commit -m "feat: recognize bounded PDF and HWPX sources"
```

---

### Task 2: Generalize immutable snapshots for byte-backed document formats

**Files:**
- Modify: `tools/data/lib/benefit-evidence-location-contracts.ps1`
- Modify: `tools/data/test-benefit-evidence-location-contracts.ps1`

**Interfaces:**
- Consumes: existing `New-BenefitSourceSnapshot -SourceUrl -SourceFormat -Text -Bytes -ObservedAt`.
- Produces: the same constructor and `Assert-ScopeSnapshot`, now treating `XLSX`, `PDF`, and `HWPX` as byte-backed formats.
- Byte-backed snapshots require non-empty `Bytes`, empty `Text`, SHA-256 content identity from bytes, and an owned byte copy.

- [ ] **Step 1: Write failing byte-backed snapshot tests**

Add tests asserting:
- PDF snapshot accepts valid non-empty bytes with empty text and exposes `Bytes`;
- HWPX snapshot does the same;
- PDF/HWPX `ContentHash` equals the byte hash and differs when bytes differ;
- mutating caller bytes after construction does not mutate the stored snapshot;
- byte-backed snapshot validation rejects missing/empty bytes or non-empty `Text`;
- XLSX snapshot tests still pass unchanged.

- [ ] **Step 2: Run RED**

```powershell
pwsh -NoProfile -File tools/data/test-benefit-evidence-location-contracts.ps1
```

Expected: FAIL because current snapshot logic treats only XLSX as byte-backed.

- [ ] **Step 3: Implement byte-backed snapshot handling**

Update only the binary-format branch inside `Assert-ScopeSnapshot` and `New-BenefitSourceSnapshot` so `@('XLSX','PDF','HWPX')` share byte hashing/copy rules. Do not alter HTML/JSONP text hashing semantics.

- [ ] **Step 4: Run GREEN**

Run the Task 2 test.

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tools/data/lib/benefit-evidence-location-contracts.ps1 tools/data/test-benefit-evidence-location-contracts.ps1
git commit -m "feat: support byte-backed document snapshots"
```

---

### Task 3: Add the strict document-row provenance bridge

**Files:**
- Create: `tools/data/lib/benefit-evidence/document-source-provenance.ps1`
- Create: `tools/data/test-document-source-provenance.ps1`
- Modify: `tools/data/lib/benefit-evidence-location-contracts.ps1`
- Modify: `tools/data/test-benefit-evidence-location-contracts.ps1`

**Interfaces:**
- Consumes: byte-backed PDF/HWPX snapshots from Task 2 and existing scoped field names from `Get-BenefitScopedHeaderMap`.
- Produces:

```powershell
function New-BenefitDocumentValidationIndex {
    param(
        [Parameter(Mandatory)]$Snapshot,
        [Parameter(Mandatory)][string]$AdapterId,
        [Parameter(Mandatory)][string]$AdapterVersion,
        [Parameter(Mandatory)][string]$ExtractionMethod,
        [Parameter(Mandatory)][string]$ExtractorId,
        [Parameter(Mandatory)][string]$ExtractorVersion,
        [Parameter(Mandatory)][string]$ExtractionConfigHash,
        [Parameter(Mandatory)][object[]]$Units
    )
}

function Assert-BenefitDocumentValidationIndex {
    param([Parameter(Mandatory)]$ValidationIndex,[Parameter(Mandatory)]$Snapshot)
}

function New-BenefitDocumentSourceContentUnit {
    param(
        [Parameter(Mandatory)]$Snapshot,
        [Parameter(Mandatory)]$ValidationIndex,
        [Parameter(Mandatory)][string]$UnitReference
    )
}

function Assert-ScopeDocumentUnit {
    param(
        [Parameter(Mandatory)]$Unit,
        [Parameter(Mandatory)]$Snapshot,
        [Parameter(Mandatory)]$ValidationIndex
    )
}
```

Validation-index unit records use the exact common shape:
- `UnitType = PDF_ROW | HWPX_ROW`;
- deterministic `UnitReference`;
- deterministic `PhysicalPath`;
- `RawEvidenceText`;
- `StructuredFields` dictionary;
- `FieldReferences` dictionary;
- extraction metadata inherited from the validation index.

For each field reference, require:
- `FieldReference`;
- `PhysicalReference`;
- `SourceText`.

The content-unit constructor selects one exact unit from the validation index and copies it. It does not accept caller-supplied field values. This prevents a caller from pairing an arbitrary benefit value with a valid physical reference.

- [ ] **Step 1: Write failing document provenance tests**

In `test-document-source-provenance.ps1`, create synthetic PDF/HWPX indexes and assert:
- valid PDF/HWPX rows construct `ContractType='SourceContentUnit'`;
- `UnitType`, `UnitReference`, `PhysicalPath`, and extraction metadata are preserved;
- each field's `SourceText` equals the structured value supplied by the validated index;
- missing/duplicate unit references are rejected;
- a unit copied from another snapshot is rejected;
- altered `StructuredFields`, `FieldReferences`, `ExtractionMethod`, or `PhysicalPath` are rejected;
- invalid config hash is rejected;
- PDF/HWPX indexes cannot validate each other's units.

Also extend `test-benefit-evidence-location-contracts.ps1` to assert `Assert-ScopeUnit` dispatches PDF/HWPX only when a document validation index is supplied.

- [ ] **Step 2: Run RED**

```powershell
pwsh -NoProfile -File tools/data/test-document-source-provenance.ps1
pwsh -NoProfile -File tools/data/test-benefit-evidence-location-contracts.ps1
```

Expected: FAIL because document validation-index/unit functions do not exist.

- [ ] **Step 3: Implement the provenance bridge**

Dot-source `document-source-provenance.ps1` from the existing contract module and extend:
- `Assert-ScopeUnit` with an optional `DocumentValidationIndex`;
- `Assert-ScopeObservation` with the same optional index;
- `New-BenefitSourceObservation` with the same optional index.

For PDF/HWPX, dispatch only to `Assert-ScopeDocumentUnit`; do not reuse HTML raw-span logic or invent byte offsets.

When creating a PDF/HWPX observation with a strict index, attach `DocumentValidationIndex` to the returned observation for later locator use. Do not add run-context trust/caching yet; P4-1/P4-2 own that.

- [ ] **Step 4: Run GREEN**

Run the two Task 3 tests.

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tools/data/lib/benefit-evidence/document-source-provenance.ps1 tools/data/test-document-source-provenance.ps1 tools/data/lib/benefit-evidence-location-contracts.ps1 tools/data/test-benefit-evidence-location-contracts.ps1
git commit -m "feat: add document provenance contracts"
```

---

### Task 4: Extend locator/slice contracts without enabling parsing or reuse

**Files:**
- Modify: `tools/data/lib/benefit-evidence-location-contracts.ps1`
- Modify: `tools/data/lib/benefit-evidence/find-business-evidence-slice.ps1`
- Modify: `tools/data/test-find-business-evidence-slice.ps1`
- Modify: `tools/data/test-benefit-incremental-reuse.ps1`
- Test: `tools/data/test-document-source-provenance.ps1`

**Interfaces:**
- Consumes: PDF/HWPX `SourceObservation` carrying `DocumentValidationIndex`.
- Produces: existing `Find-BenefitBusinessEvidence -Observation -Business -CanonicalPhone` behavior for document-row observations with no new public caller argument required; it discovers `Observation.DocumentValidationIndex` internally.
- Extends existing `New-RelevantBenefitEvidenceSlice`, `Assert-ScopeSliceShape`, `Assert-ScopeSliceAgainstSnapshot`, and `Assert-RelevantBenefitEvidenceSlice` to preserve document-row provenance.
- PDF slice:
  - `ScopeType='PDF_ROW'`
  - `LocatorMethod='STRUCTURED_PDF_ROW'`
- HWPX slice:
  - `ScopeType='HWPX_ROW'`
  - `LocatorMethod='STRUCTURED_HWPX_ROW'`
- Slice retains `PhysicalPath`, extraction metadata, structured fields, and field references from the exact source unit.
- `Get-BenefitIncrementalCapability` remains `NONE` for PDF/HWPX.

- [ ] **Step 1: Write failing locator/slice tests**

Build two-business synthetic PDF and HWPX observations from Task 3 fixtures.

Assert:
- strong identity evidence selects exactly one row and produces exactly one slice;
- Business A never receives Business B benefit field;
- same-name unresolved alternatives return `AMBIGUOUS` with no slice;
- no matching row returns `NOT_FOUND` only when observation status is `COMPLETE`;
- `PARTIAL/FAILED/UNSUPPORTED` observations cannot claim `NOT_FOUND`;
- slice physical/extraction metadata exactly matches the selected unit/index;
- altered slice metadata fails `Assert-RelevantBenefitEvidenceSlice`.

In `test-benefit-incremental-reuse.ps1`, add PDF and HWPX source documents and assert both capabilities are `NONE`.

- [ ] **Step 2: Run RED**

```powershell
pwsh -NoProfile -File tools/data/test-find-business-evidence-slice.ps1
pwsh -NoProfile -File tools/data/test-document-source-provenance.ps1
pwsh -NoProfile -File tools/data/test-benefit-incremental-reuse.ps1
```

Expected: FAIL because slices/locator do not yet understand PDF/HWPX.

- [ ] **Step 3: Implement the minimal document slice path**

Extend only the format dispatch required to construct and validate document-row slices. Keep `Get-BenefitEvidenceCandidate` identity comparison logic unchanged; it should continue consuming `StructuredFields` rather than format-specific internals.

Do not modify `Invoke-ScopedPhase2BenefitSourceCandidate` in P4-0. Real PDF/HWPX sources therefore remain unsupported by the scoped runner until their adapters are implemented.

Do not add PDF/HWPX to `POST_FETCH` capability.

- [ ] **Step 4: Run GREEN**

Run the three Task 4 tests.

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tools/data/lib/benefit-evidence-location-contracts.ps1 tools/data/lib/benefit-evidence/find-business-evidence-slice.ps1 tools/data/test-find-business-evidence-slice.ps1 tools/data/test-document-source-provenance.ps1 tools/data/test-benefit-incremental-reuse.ps1
git commit -m "feat: route document rows through scoped locator"
```

---

### Task 5: P4-0 regression, CI-equivalent verification, and handover

**Files:**
- Create: `docs/handover/2026-09-29-phase4-p4-0-document-adapter-foundation.md`
- Modify only if required for accurate status: `tools/data/README.md`, `docs/current-work.md`
- No canonical/seed/app data edits.

**Interfaces:**
- Consumes: Tasks 1-4.
- Produces: a bounded P4-0 handover that states contracts are ready but PDF/HWPX parsing, OCR, scoped orchestration, and post-fetch reuse are not yet implemented.

- [ ] **Step 1: Run all targeted tests once**

```powershell
pwsh -NoProfile -File tools/data/test-benefit-verification-contracts.ps1
pwsh -NoProfile -File tools/data/test-discover-official-benefit-sources.ps1
pwsh -NoProfile -File tools/data/test-benefit-evidence-location-contracts.ps1
pwsh -NoProfile -File tools/data/test-document-source-provenance.ps1
pwsh -NoProfile -File tools/data/test-find-business-evidence-slice.ps1
pwsh -NoProfile -File tools/data/test-benefit-incremental-reuse.ps1
```

Expected: PASS.

- [ ] **Step 2: Run the complete data suite exactly as CI does**

```powershell
$ErrorActionPreference = 'Stop'
Get-ChildItem -LiteralPath tools/data -Filter 'test-*.ps1' |
  Sort-Object Name |
  ForEach-Object { & $_.FullName }
```

Expected: all `tools/data/test-*.ps1` scripts PASS, with the total count updated from the actual run rather than copied from the previous 56/56 baseline.

- [ ] **Step 3: Run Android CI-equivalent local gates**

From `apps/android` on Windows:

```powershell
.\gradlew.bat assembleDebugUnitTest testDebugUnitTest --stacktrace
.\gradlew.bat lintDebug assembleDebug --stacktrace
```

Expected: unit/build/lint commands succeed. If local Android tooling is unavailable, report `NOT_RUN` and require the exact PR HEAD's GitHub `verify` job before merge.

- [ ] **Step 4: Verify protected paths and scope**

Run:

```powershell
git status --short
git diff --name-only origin/dev...HEAD
```

Confirm:
- no `data/canonical/**` change;
- no Android seed data change;
- no `apps/**` source change;
- no external package/dependency file added;
- no automatic production action introduced.

- [ ] **Step 5: Write the P4-0 handover**

Record:
- changed files;
- exact contract additions;
- exact tests run and their observed counts;
- tests not run;
- remaining risks;
- next task;
- explicit statement that PDF/HWPX format recognition is not parser support;
- explicit statement that `ProductionAction=NONE` and PDF/HWPX reuse capability `NONE` remain unchanged.

- [ ] **Step 6: Commit documentation**

```bash
git add docs/handover/2026-09-29-phase4-p4-0-document-adapter-foundation.md tools/data/README.md docs/current-work.md
git commit -m "docs: record phase 4 document adapter foundation"
```

Only add `tools/data/README.md` or `docs/current-work.md` if their content actually changed.

- [ ] **Step 7: Open the P4-0 PR and wait for required checks**

Create one Issue for P4-0 and one PR targeting `dev`. Require the exact PR HEAD to pass:
- `verify-data`
- `verify`

Do not merge based on an earlier green commit.

- [ ] **Step 8: Final implementation report**

Report exactly:
- changed files;
- implementation;
- tests executed;
- tests not executed;
- remaining risk;
- next work item.

Do not call Phase 4 COMPLETE. P4-0 completion means only the shared document-adapter foundation is merged.

---

## Follow-on Phase 4 sequence — not implemented by this plan

After P4-0 is merged, re-read the then-current `dev` before writing each next plan.

1. **P4-1 HWPX generic adapter**
   - Use built-in ZIP/XML processing where sufficient.
   - Build strict section/table/row/cell validation indexes.
   - Add run-context parse reuse and scoped integration.
   - Live official HWPX remains `NOT_OBSERVED` unless a real source is found.

2. **P4-2 PDF native adapter**
   - Evaluate and obtain approval for the external PDF runtime before adding it.
   - Current candidate to evaluate first: PdfPig, because it is .NET-compatible, Apache-2.0, and exposes glyph/word position data needed for bounded provenance.
   - The runtime decision is not approved by this plan.
   - Validate against the Suwon representative PDF if still available and materially suitable.

3. **P4-3 OCR fallback**
   - Add fallback orchestration only after native PDF extraction is stable.
   - Native success must produce OCR invocation count 0.
   - An OCR engine/runtime requires its own explicit dependency approval if a concrete engine is introduced.
   - If no real OCR-required official source exists, keep live status `NOT_OBSERVED` and do not fabricate evidence.

4. **P4-4 integration and bounded closeout**
   - Scoped PDF/HWPX orchestration.
   - Cross-business leakage gate.
   - Fetch/parse/OCR count regressions.
   - Existing HTML/JSONP/XLSX and Phase 3 history/reuse regression.
   - Only then assess whether any document adapter has evidence to promote from reuse capability `NONE`.

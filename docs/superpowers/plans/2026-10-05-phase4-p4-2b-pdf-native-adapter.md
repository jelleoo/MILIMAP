# Phase 4 P4-2B PDF Native Adapter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the approved bounded native PDF path for digital-text ruled-grid official PDFs using exact PdfPig 0.1.16 behind an isolated .NET 8 helper process, while reusing MILIMAP's existing document provenance, locator, binding, extraction, validation, and run-context flow.

**Architecture:** PdfPig stays inside a small `tools/data` .NET helper that reads PDF bytes and emits deterministic primitive JSON geometry. PowerShell validates that projection, reconstructs only approved ruled-grid tables, builds existing `PDF_ROW` provenance, caches one parsed/indexed observation per source/run, and sends only existing MILIMAP contracts downstream. No PdfPig CLR type crosses into domain code.

**Tech Stack:** PowerShell 7, .NET 8, PdfPig 0.1.16 exact pin, existing `BenefitDocumentValidationIndex`, existing `BenefitSourceRunContext`, GitHub Actions Android CI.

**Spec:** `docs/superpowers/specs/2026-10-05-phase4-p4-2-pdf-native-adapter-design.md`

## Global Constraints

- Start from refreshed `origin/dev` containing merge `24a64aa96338ddbc7fe7f315f5c1fa01aa21b7b1` or a newer verified dev state.
- Issue: #117.
- Approved dependency: **PdfPig 0.1.16 exact**. No prerelease/floating version and no second PDF dependency without new approval.
- PdfPig types must remain inside the helper process.
- Native support is limited to digital-text, explicit ruled-grid, page-local tables, one semantic header row, unmerged semantic cells, and unique text-to-cell containment.
- No OCR, no borderless-table inference, no cross-page row stitching, no multi-row header inference, no fuzzy/positional guessing.
- `ProductionAction=NONE`.
- PDF incremental reuse remains `NONE`.
- `PARTIAL`, `FAILED`, and `UNSUPPORTED` must not become semantic `LOCATED` or `NOT_FOUND`.
- Absence never implies `ENDED` or closure.
- Do not modify DB architecture, auth, API contracts, persistent schema, `data/canonical/**`, `data/seed/**`, or `apps/**`.
- Do not commit the live Suwon PDF.
- Suwon is identity/layout control only, not benefit-positive/currentness truth.
- No auto-merge.

## Approved Geometry Policy

Versioned config: `PDF_GRID_CONFIG_V1`

Initial fixed values from P4-2A:
- coordinate snap: 0.5 pt
- thin filled rectangle threshold: 0.75 pt
- full glyph containment epsilon: 0.01 pt
- within-cell baseline grouping: 1.0 pt

All material values plus sorted shared-header mappings must contribute to `ExtractionConfigHash`. Never widen tolerances per document.

## File Structure

**Create**
- `tools/data/pdf-native/Milimap.PdfNative.csproj`
- `tools/data/pdf-native/Program.cs`
- `tools/data/pdf-native/packages.lock.json`
- `tools/data/pdf-native/README.md`
- `tools/data/lib/benefit-evidence/pdf-native-runtime.ps1`
- `tools/data/lib/benefit-evidence/convert-pdf-source-observation.ps1`
- `tools/data/test-pdf-native-runtime.ps1`
- `tools/data/test-pdf-source-observation.ps1`
- `tools/data/test-phase2-scoped-pdf.ps1`
- `tools/data/testdata/benefit-evidence-pdf/test-support.ps1`
- `tools/data/testdata/benefit-evidence-pdf/README.md`
- `docs/handover/2026-10-05-phase4-p4-2b-pdf-native-adapter.md`

**Modify**
- `tools/data/lib/benefit-evidence-location-contracts.ps1` — exact reviewed shared aliases only.
- `tools/data/lib/benefit-evidence/benefit-source-run-context.ps1`
- `tools/data/lib/benefit-evidence/invoke-scoped-benefit-source.ps1`
- `tools/data/lib/benefit-evidence/extract-benefit-evidence.ps1`
- targeted existing tests for run-context/extraction/incremental capability
- `tools/data/README.md`
- `docs/current-work.md` only at closeout
- `.github/workflows/android-ci.yml` only if current `verify-data` does not build/restore the helper automatically.

## Review Focus

1. Parser success without safe grid evidence must not become adapter `COMPLETE`.
2. Unsafe relevant rows must produce `PARTIAL`, not be filtered into false complete absence.
3. Timeout/crash/schema/hash/output-limit failures must fail closed and clean temporary files/processes.
4. New exact header aliases must not introduce fuzzy behavior or regress XLSX/HWPX.
5. Same PDF used by multiple businesses must fetch/parse/index once and lookup many.

---

### Task 1: Add the Exact PdfPig 0.1.16 Helper Boundary

**Files:** helper project, lockfile, README, `test-pdf-native-runtime.ps1`.

**Interfaces:**
- Command: `dotnet <Milimap.PdfNative.dll> inspect --input <pdfPath>`
- Deterministic schema-1 JSON:
  - `SchemaVersion`, `ParserId`, `ParserVersion`, `FileSha256`, `OpenStatus`, `Encrypted`, `Pages[]`, `Diagnostics[]`
  - each page: `PageNumber`, `RotationDegrees`, `Width`, `Height`, `Letters[]`, `Paths[]`, `ImageCount`

- [ ] Write RED tests for exact 0.1.16 pin, locked restore, missing-file structured failure, deterministic minimal valid PDF projection, and absence of PdfPig CLR type names in JSON.
- [ ] Create `net8.0` project with exact PdfPig 0.1.16 and lockfile.
- [ ] Implement strict native inspection: SHA-256, pages, dimensions/rotation, letters/bounds/baselines, primitive vector geometry, image count, encrypted/malformed diagnostics.
- [ ] Document Apache-2.0, .NET 8 runtime, helper-process boundary, build/locked-restore commands.
- [ ] Run:
  - `pwsh -NoProfile -File .\tools\data\test-pdf-native-runtime.ps1`
  - `dotnet restore .\tools\data\pdf-native\Milimap.PdfNative.csproj --locked-mode`
  - `dotnet build .\tools\data\pdf-native\Milimap.PdfNative.csproj -c Release --no-restore`
- [ ] Commit: `feat: add isolated PdfPig native projection helper`

---

### Task 2: Add the Bounded PowerShell Runtime Boundary

**Files:** `pdf-native-runtime.ps1`, runtime tests.

**Produces:** `Invoke-BenefitPdfNativeProjection -Bytes <byte[]> -TimeoutMilliseconds <int>`.

- [ ] Write RED tests for byte/hash identity, timeout termination, non-zero exit, malformed JSON, wrong schema/parser/version/hash, output quota, and temp-file cleanup.
- [ ] Implement separate-process invocation; do not `Add-Type` PdfPig into PowerShell.
- [ ] Validate schema/parser/version/hash before returning a projection.
- [ ] Map encrypted/parser-failure/timeout/crash/schema-mismatch/image-only candidate to bounded internal diagnostics.
- [ ] Add initial wall-time and maximum-output limits; record peak working set where available without claiming a hard memory sandbox.
- [ ] Run runtime tests to GREEN.
- [ ] Commit: `feat: add bounded PDF native runtime boundary`

---

### Task 3: Convert Native Geometry into Safe PDF_ROW Provenance

**Files:** converter, PDF observation tests, deterministic test support.

**Adapter metadata**
- `AdapterId=PDF_GRID`
- `AdapterVersion=1`
- `ExtractionMethod=STRUCTURED_PDF_ROW`
- `ExtractorId=PDFPIG`
- `ExtractorVersion=0.1.16`
- config `PDF_GRID_CONFIG_V1`

- [ ] Create genuine parseable, redistribution-safe fixtures covering:
  - two businesses with BusinessName/Address/Phone/BenefitDescription
  - Korean text and multiline cell
  - decorative grid before business table
  - multiple independent tables/pages
  - native text/no grid
  - image-only
  - malformed/truncated/encrypted
  - ambiguous/missing BusinessName
  - duplicate semantic mapping
  - merged/broken semantic cell
  - boundary-crossing/overlapping glyph
  - cross-page continuation
  - repeated header/footer
- [ ] Write RED tests before converter implementation.
- [ ] Normalize only 0/90/180/270 page rotation.
- [ ] Reconstruct only closed axis-aligned ruled cells using fixed `PDF_GRID_CONFIG_V1`; multiple plausible topology is unusable.
- [ ] Reuse `Get-BenefitScopedHeaderMap`; require exactly one BusinessName and no duplicate semantic mapping.
- [ ] Assign evidence glyphs only when their full bounds belong to exactly one supported cell.
- [ ] Order text deterministically by physical baseline then X inside an already-proven cell.
- [ ] Build existing `BenefitDocumentValidationIndex`, `PDF_PAGE_n_TABLE_n_ROW_n`, and exact cell physical references. Do not add bbox to the shared contract.
- [ ] Status rules:
  - structural/parser trust lost -> `FAILED`
  - image-only -> `UNSUPPORTED` + OCR-candidate diagnostic
  - native text but no supported semantic grid -> `UNSUPPORTED`
  - unsafe relevant row/cell -> `PARTIAL`
  - all supported relevant structure safe -> `COMPLETE`
- [ ] Add tamper and cross-snapshot rejection tests.
- [ ] Run PDF observation tests to GREEN.
- [ ] Commit: `feat: add ruled-grid PDF source observation`

---

### Task 4: Add the Two Approved Exact Shared Header Aliases

**File:** `tools/data/lib/benefit-evidence-location-contracts.ps1`

Exact mappings:
- `영업소 주소(도로명)` -> `Address`
- `소재지전화` -> `Phone`

- [ ] Add RED tests proving exact mappings and no fuzzy/contains behavior.
- [ ] Add only those two exact aliases.
- [ ] Run existing HTML/XLSX/HWPX header/observation regressions plus PDF observation tests.
- [ ] Commit: `feat: recognize reviewed official header aliases`

---

### Task 5: Add Run-context Parse-once and Scoped PDF Integration

**Files:** run-context, scoped source orchestration, extraction, targeted tests, new scoped PDF E2E test.

**Produces:** `Get-BenefitRunPdfObservation`; extraction method `SCOPED_PDF_CELL`.

- [ ] Write RED tests for one source/two businesses:
  - external fetch = 1
  - native helper/parse = 1
  - grid/index build = 1
  - second lookup reuses cached observation
  - incomplete outcomes are cached too
  - PDF snapshot is byte-backed with `Text=''`
  - payload/document byte mismatch rejected
- [ ] Extend run-context snapshot support minimally from HTML/XLSX/HWPX to PDF.
- [ ] Cache identity must include snapshot + PDF_GRID + adapter version + PdfPig 0.1.16 + extraction config hash.
- [ ] Add PDF scoped dispatch; never fall back to old `PdfTextExtractor`.
- [ ] Add `SCOPED_PDF_CELL` using existing field references/detail map.
- [ ] E2E safety:
  - Business A cannot receive B evidence
  - duplicate name remains ambiguous
  - incomplete observations expose no semantic status/claims
  - complete safe absence may be `NOT_FOUND` only, never `ENDED`
  - `ProductionAction=NONE`
- [ ] Confirm PDF incremental capability remains `NONE`; HWPX remains NONE; HTML/XLSX unchanged.
- [ ] Run targeted tests to GREEN.
- [ ] Commit: `feat: integrate scoped PDF evidence path`

---

### Task 6: Production Resource-bound Hardening

**Files:** helper, runtime wrapper, runtime/observation tests.

- [ ] Add RED tests for oversized source bytes, page count, letters/paths, projection bytes, timeout, child crash, and deep/malformed PDFs.
- [ ] Choose conservative initial numeric limits from P4-2A/Suwon measurements plus synthetic tests; document rationale.
- [ ] Enforce source-byte limit before parser open and page/letter/path/projection limits after available counts.
- [ ] Enforce wall timeout and child cleanup. If hard portable memory capping is unavailable, report that honestly rather than claiming it.
- [ ] Ensure quota/timeout failure never yields partial semantic evidence.
- [ ] Run hardening tests to GREEN.
- [ ] Commit: `fix: bound native PDF processing`

---

### Task 7: Representative Suwon Live Control and Full Regression

**Files:** README/current-work/handover only after verified state.

- [ ] Re-fetch Suwon PDF read-only; record time, URL/final URL, HTTP/content type, size/signature, SHA-256, source drift.
- [ ] Run production PDF path and verify current supported layout:
  - `고려이발관` unique physical cell
  - address/phone exact cells via approved aliases
  - byte-derived provenance
  - no invented BenefitDescription/currentness/ACTIVE claim
- [ ] Run complete `tools/data/test-*.ps1` suite.
- [ ] Run locked restore/build for helper.
- [ ] Run Android unit/lint/debug build using current CI-equivalent commands.
- [ ] Run `git diff --check`, protected-path diff, clean-status/temp-binary checks.
- [ ] Write `docs/handover/2026-10-05-phase4-p4-2b-pdf-native-adapter.md` with files, implementation, tests, not-run tests, dependency/lock/license, resource limits, reuse metrics, Suwon result, risks, and next step.
- [ ] Update `tools/data/README.md` and `docs/current-work.md` only with verified facts.
- [ ] Commit: `docs: close out P4-2 native PDF adapter`

---

### Task 8: PR, Exact-head CI, and Whole-branch Review

- [ ] Create PR linked to Issue #117. State bounded ruled-grid scope, PdfPig 0.1.16, no OCR, protected paths unchanged, PDF incremental reuse NONE, Phase 4 incomplete.
- [ ] Ensure CI `verify-data` can restore/build the helper. If not, make the smallest workflow change necessary and explain it.
- [ ] Require successful `verify-data` and Android `verify` on the **exact final PR HEAD**.
- [ ] Perform whole-branch read-only review focused on:
  - cross-business leakage
  - unsafe geometry silently filtered
  - PdfPig type leakage
  - runtime failure semantic promotion
  - alias regressions
  - process cleanup/quota behavior
  - parse-once metrics
  - dependency/version/lock/license
- [ ] Fix all Critical/Important findings RED->GREEN.
- [ ] Re-run exact-head CI after any final fix.
- [ ] Report merge readiness. Do not merge without explicit user instruction.

## Expected Implementation Report

Report:
- 변경한 파일
- 구현 내용
- 실행한 테스트
- 실행하지 못한 테스트
- PdfPig dependency/version/license/lock
- Suwon live control
- fetch/parse/index reuse metrics
- protected-path diff
- 남은 위험
- 다음 작업

End with:
- Phase: Phase 4 — Multi-source Adapters
- Stage: P4-2B PDF Native Adapter
- PDF incremental reuse: NONE
- ProductionAction: NONE
- Next: P4-3 OCR fallback only after P4-2B merge

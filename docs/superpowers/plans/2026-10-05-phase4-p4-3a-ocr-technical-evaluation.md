# Phase 4 P4-3A OCR Technical Evaluation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Decide whether Tesseract 5.5.3 + official Korean `kor.traineddata`, using only PdfPig 0.1.16-decoded full-page scan images, is safe and reproducible enough to approve as a future P4-3B product dependency.

**Architecture:** Keep all executable work in an evaluation-only harness under `tools/data/evaluation/p4-3a-ocr/`. Open each PDF once with PdfPig, emit bounded Gray/RGB image artifacts, prove pixel ruled-grid geometry independently of OCR, invoke externally supplied Tesseract, compare Windows/Ubuntu results, then write one gate result: `APPROVED`, `CONDITIONALLY_APPROVED`, or `REJECTED`. Do not implement the production OCR adapter.

**Tech Stack:** PowerShell 7, .NET 8, PdfPig 0.1.16 in an evaluation-only locked project, externally supplied Tesseract 5.5.3, official `kor.traineddata`, existing ReportLab/PIL fixture-authoring tooling, temporary GitHub Actions Windows/Ubuntu matrix.

**Spec:** `docs/superpowers/specs/2026-10-05-phase4-p4-3-ocr-fallback-design.md`

## Global Constraints

- Start from design commit `04bcd651991d73a26d3114bafe01974050e996ec`, based on verified `dev` `170285cf3e9860dd0c113306300712996bb6c8f8`; refresh `origin/dev` before execution and let current GitHub code win.
- P4-3A is evaluation only. No product OCR adapter, Tesseract packaging, model vendoring, run-context integration, or production `PDF_ROW` emission.
- Do not modify `tools/data/pdf-native/**`, `tools/data/lib/**`, `data/canonical/**`, `data/seed/**`, or `apps/**`.
- OCR is evaluated only for the explicit image-only shape corresponding to `OCR_FALLBACK_CANDIDATE`.
- Supported candidate shape: one clearly mapped full-page embedded image per page, PdfPig-decoded 8-bit `DeviceGray` or `DeviceRGB`.
- No second PDF open, separate rasterizer, cloud OCR, borderless/reading-order inference, nearest-cell assignment, adaptive tolerance widening, or merged-cell reconstruction.
- Pixel grid defines structure; OCR text never defines rows/columns.
- Confidence is reject-only; it never strengthens binding, lifecycle, currentness, or BenefitState.
- Synthetic controls are fictional technical fixtures, never benefit truth.
- `ProductionAction=NONE`; incremental reuse remains `NONE`.
- P4-3B remains blocked until the user explicitly approves the product dependency after reviewing P4-3A.

## File Structure

**Create and retain**
- `tools/data/evaluation/p4-3a-ocr/Milimap.P4_3A.OcrEval.csproj`
- `tools/data/evaluation/p4-3a-ocr/packages.lock.json`
- `tools/data/evaluation/p4-3a-ocr/Program.cs`
- `tools/data/evaluation/p4-3a-ocr/invoke-tesseract-eval.ps1`
- `tools/data/evaluation/p4-3a-ocr/run-evaluation.ps1`
- `tools/data/evaluation/p4-3a-ocr/test-evaluation.ps1`
- `tools/data/evaluation/p4-3a-ocr/README.md`
- `tools/data/evaluation/p4-3a-ocr/fixtures/generate-fixtures.py`
- `tools/data/evaluation/p4-3a-ocr/fixtures/manifest.json`
- deterministic fixture PDFs/images under the same `fixtures/` directory
- `docs/handover/2026-10-05-phase4-p4-3a-ocr-technical-evaluation.md`
- update `docs/current-work.md` only after the gate result is known

**Temporary; remove before closeout**
- `.github/workflows/p4-3a-ocr-evaluation.yml`
- Tesseract binaries, `kor.traineddata`, raw TSV, PGM/PPM temp files, CI artifacts

## Review Focus

1. Decoded-image ambiguity: image objects without safely decoded pixels must reject. Task 2.
2. Multi/partial image pages: no largest-image heuristic. Task 2.
3. OCR boxes crossing cells: no centroid/nearest-cell assignment. Task 3.
4. Confidence drift across platforms: Level B requires a margin proof. Tasks 3 and 5.
5. Runtime/model drift: exact engine/model identity mismatch must reject. Tasks 1, 4, 5.

---

### Task 1: Evaluation Harness + Runtime Identity

**Files:** create the evaluation project, `Program.cs`, Tesseract wrapper, tests, README.

**Interfaces**
- `Program inspect --input <pdf> --artifact-dir <dir>` -> deterministic JSON containing `SchemaVersion=1`, `ProbeId=MILIMAP_P4_3A_OCR_EVAL`, PdfPig version, PDF SHA-256, `OpenCount`, status, page/image primitives, diagnostics.
- `invoke-tesseract-eval.ps1` -> engine version, model SHA-256, invocation count, normalized TSV words, timing/output measurements, diagnostics.

- [ ] Write RED tests for nonexistent PDF, valid PDF `OpenCount=1`, missing/wrong Tesseract identity, and missing/wrong Korean model identity.
- [ ] Run: `pwsh -NoProfile -File .\tools\data\evaluation\p4-3a-ocr\test-evaluation.ps1 -Group Contract`. Expected: FAIL before implementation.
- [ ] Implement isolated .NET 8 project with exact locked PdfPig 0.1.16; no product-project reference and no bundled Tesseract/model.
- [ ] Implement the wrapper so engine/model identity is verified before accepting OCR output.
- [ ] Re-run `-Group Contract`. Expected: PASS.
- [ ] Run locked restore/build and verify `git diff -- tools/data/pdf-native tools/data/lib` is empty.
- [ ] Commit: `test: add P4-3A OCR evaluation harness`.

---

### Task 2: Reproducible Fixtures + Single-open Image Handoff

**Files:** create fixture generator/manifest and modify evaluation harness/tests.

**Interfaces**
- Manifest fields: fixture name, purpose, generator version, SHA-256, expected image class, expected grid class, expected eligibility, license.
- Supported handoff emits `page-<n>-image-<n>.pgm` or `.ppm` plus source/page/image/placement/pixel-hash metadata.

- [ ] Write RED tests for Gray/RGB full-page positives and multi-image, partial-page, unsupported-bit-depth, unsupported-color-space, undecodable negatives.
- [ ] Run `-Group ImageEligibility`. Expected: FAIL.
- [ ] Generate deterministic fictional Korean controls including two-business, multiline, degraded-confidence, boundary-crossing, multi-page, multi-image, partial-page, borderless, broken-grid, merged-header, missing-name-header, 1-bit, and CMYK cases.
- [ ] Implement one-open PdfPig image inspection/decoding. Emit PGM/PPM only for safely decoded 8-bit Gray/RGB full-page candidates; do not reopen the PDF.
- [ ] Re-run `-Group ImageEligibility`. Expected: positives PASS; negatives fail closed with no OCR-eligible artifact.
- [ ] Commit: `test: prove bounded P4-3A image handoff`.

---

### Task 3: Pixel Grid + Korean OCR + Confidence Gate

**Files:** modify `Program.cs`, wrapper, runner, tests, README.

**Interfaces**
- `Program grid --input <pnm> --metadata <inspect-json> --page <n> --image <n>` -> fixed candidate config, table/cell rectangles, diagnostics.
- `run-evaluation.ps1` -> accepted/rejected OCR words, cell assignment, normalized cell text, confidence observations, evaluation-only row projection.

- [ ] Write RED tests for ruled-grid Gray/RGB positives; borderless/broken/merged/missing-header negatives; boundary-crossing and overlapping OCR-word rejection; multiline ordering inside a proven cell only.
- [ ] Run `-Group GridOcr`. Expected: FAIL.
- [ ] Implement evaluation-only pixel ruled-grid detection using fixed recorded thresholds. No text/whitespace-derived boundaries or adaptive widening.
- [ ] Run the real exact Tesseract candidate over a small documented material-config matrix; record every tested config rather than hand-picking output.
- [ ] Measure clear/degraded/address/phone/benefit-like Korean confidence and propose a reject threshold only if a stable safety margin exists.
- [ ] Re-run `-Group GridOcr`. Expected: deterministic physical cells, two-business isolation, unsafe text/topology rejected, confidence used only for rejection.
- [ ] Commit: `test: evaluate P4-3A Korean OCR provenance`.

---

### Task 4: Failure/Resource/Work-count + Multi-page Feasibility

**Files:** modify wrapper, runner, tests, README.

**Interfaces**
- Runner exposes `PdfOpenCount`, `ImageDecodeCount`, `TesseractInvocationCount`, `GridBuildCount`, `LookupCount`.
- Evaluation test doubles cover runtime/model/output/timeout fault classes without modifying product code.

- [ ] Write RED tests: native-safe PDF -> OCR count 0; two-business OCR fixture -> PDF open 1, OCR 1, grid build 1, two lookups, leakage 0; all runtime/output/resource failures produce no accepted semantic row and no evaluation `NOT_FOUND`.
- [ ] Run `-Group Safety`. Expected: FAIL.
- [ ] Add conservative measured limits for pixel dimensions/count, decoded bytes, grid work/cells, TSV bytes/rows, stdout/stderr, wall time, temp footprint, and observed working set. Do not claim a hard memory ceiling unless enforced.
- [ ] Add deterministic test doubles for wrong version/model, malformed/oversized output, delayed timeout, and non-zero exit.
- [ ] Evaluate multi-page input with one Tesseract invocation and exact page mapping. If not deterministic, record `MULTIPAGE_NOT_APPROVED` and constrain future P4-3B v1 to single-page OCR.
- [ ] Re-run `-Group Safety`. Expected: fail-closed negatives, bounded positive controls, no repeated OCR per business.
- [ ] Commit: `test: bound P4-3A OCR evaluation runtime`.

---

### Task 5: Windows/Ubuntu Supply + Determinism

**Files:** temporary `.github/workflows/p4-3a-ocr-evaluation.yml`; retained harness changes only if required for comparison.

- [ ] On `windows-latest` and `ubuntu-latest`, establish a documented evaluation-only way to supply exact Tesseract 5.5.3 and official Korean model; record source, version, hash, license, model SHA-256. If either platform cannot reproduce the candidate, approval is blocked; do not substitute another version.
- [ ] Create the temporary matrix workflow to run the exact retained harness/fixture commit and upload normalized evidence.
- [ ] Repeat positive controls per platform and compare raw/normalized OCR, accepted/rejected words, cell assignment, cell text, final row/status.
- [ ] Classify: Level A = comparison contract matches; Level B = only non-semantic diagnostics/confidence differ and margin proof preserves identical accepted words/cells/rows/status; Level C = any semantic acceptance/cell/row/status differs.
- [ ] Level C blocks `APPROVED`.
- [ ] Record run ID, commit SHA, job results, runtime/model provenance, artifact hashes, classification, and multi-page result.
- [ ] Remove the temporary workflow before final closeout; retain no binary/model/raw OCR artifacts.

---

### Task 6: Gate Decision + Safety Closeout

**Files:** create handover; update current-work only with proven facts; retain evaluation harness/fixtures.

- [ ] Evaluate all hard gates from the spec. `APPROVED` requires exact runtime/model identity, reproducible Windows/Ubuntu supply, offline OCR, single-open handoff, Gray/RGB positives, deterministic ruled-grid/containment, defensible reject-only confidence gate, leakage 0, native-safe OCR 0, OCR candidate <=1 invocation, lookup reuse, fail-closed negatives, Level A or justified B, resource evidence, and no product/protected-path changes.
- [ ] Otherwise choose `CONDITIONALLY_APPROVED` with exact blockers or `REJECTED`; Korean recognition alone is never enough.
- [ ] Write `docs/handover/2026-10-05-phase4-p4-3a-ocr-technical-evaluation.md` with base/design/plan SHAs, fixture/harness hashes, runtime/model provenance, tested configs, single-open/grid/OCR/confidence/work-count/failure/resource/multi-page results, CI evidence, tests run/not run, risks, and next user decision.
- [ ] Run:
  - `pwsh -NoProfile -File .\tools\data\evaluation\p4-3a-ocr\test-evaluation.ps1 -Group All`
  - locked restore/build of the evaluation project
  - `git diff --check origin/dev...HEAD`
  - `git diff origin/dev...HEAD -- data/canonical data/seed apps tools/data/pdf-native tools/data/lib`
  - repository `verify-data` gate or exact current equivalent on final HEAD
- [ ] Android unit/lint/debug is `NOT_RUN_EVALUATION_ONLY` unless current CI policy runs it automatically, because product/app code must remain unchanged.
- [ ] Update `docs/current-work.md` with only the proven P4-3A status; do not mark P4-3 or Phase 4 complete.
- [ ] Commit retained evaluation evidence/docs.
- [ ] Stop. If `APPROVED`, ask for explicit Tesseract/model **product dependency approval** before writing any P4-3B implementation plan.

## Test Method Summary

- RED/GREEN groups: `Contract`, `ImageEligibility`, `GridOcr`, `Safety`, `All`.
- Fixture regeneration + SHA-256 manifest.
- Exact engine/model identity negatives.
- Real Korean OCR controls and repeated runs.
- Two-business leakage = 0.
- PdfPig open = 1; native-safe OCR = 0; OCR-eligible shared run <=1.
- Windows/Ubuntu Level A/B/C comparison.
- Resource/failure matrix.
- Locked evaluation-project restore/build.
- Final `verify-data` and protected-path diff.

## Risks

- Exact Tesseract 5.5.3 supply may fail on one platform.
- PdfPig decoded-image support may be narrower than expected.
- Synthetic fixtures may encourage over-tuning; config must pass negative/degraded controls.
- Confidence may drift across platform builds.
- Pixel-grid thresholds may create false certainty if broken/merged structures are not kept unsupported.
- Decoded pixels/TSV can amplify resource usage.
- A successful evaluation is feasibility evidence only; product integration still requires P4-3B design-plan execution after dependency approval.

## Phase Position

```text
Phase 4
  P4-0 COMPLETE
  P4-1 COMPLETE
  P4-2 COMPLETE
  P4-3
    design APPROVED
    P4-3A technical evaluation THIS PLAN
    P4-3B BLOCKED ON EVALUATION + EXPLICIT DEPENDENCY APPROVAL
  P4-4 LATER
```

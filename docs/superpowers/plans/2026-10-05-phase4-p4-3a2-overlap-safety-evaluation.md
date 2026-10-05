# Phase 4 P4-3A2 Same-cell Overlap Safety Evaluation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove or reject the redesigned OCR acceptance rule that permits only safely classified same-cell adjacent word-box overlap while preserving exact physical cell provenance, fail-closed negatives, business isolation, operational bounds, and Windows/Ubuntu determinism.

**Architecture:** Preserve the merged P4-3A harness unchanged as historical evidence. Add a separate evaluation-only layer under `tools/data/evaluation/p4-3a2-ocr/` that reuses the retained P4-3A PdfPig inspect/grid primitives and committed controls read-only, but owns the revised TSV contract, overlap classifier, confidence calibration, row-isolation probe, operational tests, and cross-platform evidence. No production OCR adapter or product dependency is added.

**Tech Stack:** PowerShell 7, retained .NET 8/PdfPig 0.1.16 P4-3A inspection/grid helper, externally supplied Tesseract `v5.5.3.20260724`/5.5.3 family, official `tessdata_fast/kor.traineddata` SHA-256 `6b85e11d9bbf07863b97b3523b1b112844c43e713df8b66418a081fd1060b3b2`, Python/Pillow only for authoring new fictional evaluation fixtures, temporary GitHub Actions Windows/Ubuntu evaluation workflow.

**Spec:** `docs/superpowers/specs/2026-10-05-phase4-p4-3-ocr-fallback-redesign.md`

## Global Constraints

- Start from approved redesign commit `ce9c8a623fb07950570bb09f4f8840cd74e46a04`, whose product-code base is `dev` `4a688a8ca4d67a7b1217b62eced06d770a6db8ac`; refresh `origin/dev` before execution and let newer GitHub code win if it conflicts.
- Historical P4-3A remains `REJECTED`. Do not edit `tools/data/evaluation/p4-3a-ocr/**`, Issue #119, PR #120, or the P4-3A rejected handover to make A2 appear retroactive.
- P4-3A2 is evaluation only. No production OCR adapter, binary/model packaging, run-context product integration, production `PDF_ROW`, or product dependency.
- Do not modify `tools/data/pdf-native/**`, `tools/data/lib/**`, `data/canonical/**`, `data/seed/**`, or `apps/**`.
- OCR remains PDF-only and corresponds only to the image-only `OCR_FALLBACK_CANDIDATE` shape.
- Supported image shape remains exactly one clearly mapped full-page embedded image per page, PdfPig-decoded 8-bit `DeviceGray` or `DeviceRGB`.
- Exact word-to-cell containment is unchanged: no cell-boundary pixel allowance, centroid/nearest/majority assignment, adaptive widening, OCR-driven grid movement, borderless inference, or reading-order table inference.
- Same-cell overlap is not automatically safe. Only the selected fixed/versioned classifier may emit `SAFE_ADJACENT`; duplicate, conflict, ordering uncertainty, and cross-cell ambiguity remain blocking.
- Confidence is reject-only and never resolves geometry/duplicate/conflict ambiguity or strengthens binding/lifecycle/currentness.
- The overlap classifier may evaluate only the bounded candidate same-region ratios `0.25`, `0.50`, and `0.75`. Select the **lowest** candidate that passes every required positive and negative control. If none passes, Gate A fails. Do not add another threshold without redesign review.
- Confidence candidates remain `0`, `50`, `80`, `90`, `95`. Select a threshold only if clear required fields remain usable while a safe-grid degraded-text control becomes incomplete. Do not interpolate an unreviewed threshold.
- PSM 11 is the positive candidate. PSM 3/4/6 are safety-regression controls and must not become usable through the new overlap rule.
- `ProductionAction=NONE`; synthetic controls are fictional technical data, never benefit truth.
- P4-3B and Tesseract/model product dependency remain `BLOCKED` / `NOT_APPROVED` until P4-3A2 closeout is reviewed and the user explicitly approves the exact dependency.

## File Structure

**Create**
- `tools/data/evaluation/p4-3a2-ocr/invoke-tesseract-eval.ps1` — A2-only exact runtime/model wrapper retaining TSV hierarchy and one-process document OCR.
- `tools/data/evaluation/p4-3a2-ocr/run-evaluation.ps1` — unique cell membership, overlap classifier, deterministic cell text, confidence matrix, row-isolation/work-count orchestration.
- `tools/data/evaluation/p4-3a2-ocr/test-evaluation.ps1` — TDD groups `Contract`, `OverlapPolicy`, `Acceptance`, `Safety`, `DeterminismContract`, `All`.
- `tools/data/evaluation/p4-3a2-ocr/README.md` — evaluation scope, exact inputs/config, commands, historical separation.
- `tools/data/evaluation/p4-3a2-ocr/fixtures/generate-fixtures.py` — author only A2-specific fictional safe-grid/degraded-text controls.
- `tools/data/evaluation/p4-3a2-ocr/fixtures/manifest.json`
- A2-specific committed fictional fixture PDFs under `tools/data/evaluation/p4-3a2-ocr/fixtures/`.
- `docs/handover/2026-10-05-phase4-p4-3a2-overlap-safety-evaluation.md` only when the final gate result is known.

**Read-only dependencies**
- `tools/data/evaluation/p4-3a-ocr/Milimap.P4_3A.OcrEval.csproj`
- `tools/data/evaluation/p4-3a-ocr/Program.cs`
- `tools/data/evaluation/p4-3a-ocr/fixtures/gray.pdf`
- `tools/data/evaluation/p4-3a-ocr/fixtures/rgb.pdf`
- `tools/data/evaluation/p4-3a-ocr/fixtures/multipage.pdf`
- other retained P4-3A negative fixtures as needed.

**Temporary; remove before closeout**
- `.github/workflows/p4-3a2-ocr-evaluation.yml`
- downloaded/extracted Tesseract runtime, Korean model, raw TSV, PGM/PPM, normalized CI evidence artifacts.

**Update only after final verdict**
- `docs/current-work.md`

## Review Focus

1. Near-duplicate boxes shifted a few pixels must not evade duplicate/conflict rejection merely because they are not exact-coordinate duplicates. Task 2 adds high-overlap same-text and different-text controls around the candidate same-region policy.
2. Transitive vertical-overlap line grouping must not merge two physical text lines through a bridging word. Task 2 adds a three-word bridge control and requires `ORDERING_UNSAFE`, not a guessed line.
3. Empty or whitespace-only OCR word output on an otherwise eligible page must not become `COMPLETE` or semantic absence. Tasks 1 and 4 add explicit empty-output fail-closed tests.
4. Multi-page list-mode OCR must preserve page-to-input mapping; reordered/missing/extra TSV page numbers must produce `MULTIPAGE_NOT_APPROVED` or failure, never remap heuristically. Task 4 tests exact page-number mapping.
5. Process-start failure and oversized stdout/stderr must clean temporary files and return failure without accepted rows. Task 4 adds start-failure/output-limit/cleanup tests.

---

### Task 1: A2 Harness Boundary + Hierarchical TSV Contract

**Files:**
- Create: `tools/data/evaluation/p4-3a2-ocr/invoke-tesseract-eval.ps1`
- Create: `tools/data/evaluation/p4-3a2-ocr/test-evaluation.ps1`
- Create: `tools/data/evaluation/p4-3a2-ocr/README.md`
- Read only: `tools/data/evaluation/p4-3a-ocr/Milimap.P4_3A.OcrEval.csproj`

**Interfaces:**
- Consumes: retained P4-3A `inspect` / `grid` executable contract and committed PNM handoff; exact model hash above.
- Produces: `Invoke-P43a2TesseractEvaluation -Executable <path> -ModelPath <path> -Inputs <string[]> -Psm <3|4|6|11>`.
- Each returned OCR word has exact fields `Page, Block, Paragraph, Line, Word, Left, Top, Width, Height, Confidence, Text`.
- Result includes `ProbeId='MILIMAP_P4_3A2_OCR_EVAL'`, `SchemaVersion=1`, `OverlapPolicyCandidates=@(0.25,0.50,0.75)`, engine/model identity, invocation count, elapsed time, normalized words, and diagnostics.

- [ ] **Step 1: Write failing Contract tests**
  - Assert the retained P4-3A project builds locked and its `ProbeId` remains `MILIMAP_P4_3A_OCR_EVAL`.
  - Assert `git diff origin/dev...HEAD -- tools/data/evaluation/p4-3a-ocr` is empty.
  - Assert missing/wrong executable, missing/wrong model, malformed TSV hierarchy, empty word output, and unsupported input count fail closed.
  - Assert a synthetic valid TSV preserves block/paragraph/line/word numbers exactly.

- [ ] **Step 2: Run Contract and verify RED**

Run:
`pwsh -NoProfile -File .\tools\data\evaluation\p4-3a2-ocr\test-evaluation.ps1 -Group Contract`

Expected: FAIL because the A2 wrapper does not exist.

- [ ] **Step 3: Implement the A2 wrapper**

Implement `Invoke-P43a2TesseractEvaluation` with the same exact engine/model identity requirements as historical P4-3A, but an A2-local TSV parser that retains hierarchy. Single-page input invokes Tesseract exactly once. Multiple inputs are not accepted until Task 4 adds list-mode mapping.

- [ ] **Step 4: Re-run Contract**

Expected: PASS; historical P4-3A directory remains byte-for-byte unmodified relative to `origin/dev`.

- [ ] **Step 5: Commit**

`git add tools/data/evaluation/p4-3a2-ocr`
`git commit -m "test: add P4-3A2 OCR evaluation boundary"`

---

### Task 2: Unique Cell Membership + Same-cell Overlap Classifier

**Files:**
- Create/Modify: `tools/data/evaluation/p4-3a2-ocr/run-evaluation.ps1`
- Modify: `tools/data/evaluation/p4-3a2-ocr/test-evaluation.ps1`

**Interfaces:**
- `Get-P43a2CellMembership -Cells <object[]> -Word <object>` -> `Status=UNIQUE|NONE|AMBIGUOUS`, `CellId` only for `UNIQUE`.
- `Get-P43a2OverlapClass -A <word> -B <word> -SameRegionRatio <double>` -> `NONE|SAFE_ADJACENT|DUPLICATE|CONFLICTING|ORDERING_UNSAFE`.
- Same-region score is fixed as `intersectionArea / min(areaA, areaB)`.
- `Resolve-P43a2OcrCells -Cells <object[]> -Words <object[]> -ConfidenceThreshold <double> -SameRegionRatio <double>` -> `Status=COMPLETE|PARTIAL`, accepted/rejected words, diagnostics, deterministic cell text.
- Deterministic physical line grouping uses vertical bbox-overlap connectivity inside one proven cell; components order top-to-bottom, words within a component left-to-right. A transitive component that cannot produce a consistent total order is `ORDERING_UNSAFE`.

- [ ] **Step 1: Write failing OverlapPolicy tests**

Pin all of:
- word fully in exactly one cell -> `UNIQUE`;
- zero-cell / cross-cell -> blocking and never rescued by overlap policy;
- 1-pixel same-cell adjacent boxes -> candidate `SAFE_ADJACENT`;
- high-overlap same-text near-duplicate -> `DUPLICATE`;
- high-overlap different-text -> `CONFLICTING`;
- exact same physical order key with non-identical records -> `ORDERING_UNSAFE`;
- same TSV line with word-number reversal against physical left-to-right order -> `ORDERING_UNSAFE`;
- transitive vertical bridge that would merge two physical lines -> `ORDERING_UNSAFE`;
- confidence cannot turn any blocking overlap class safe.

For each same-region candidate `0.25/0.50/0.75`, record pass/fail over the same fixed controls.

- [ ] **Step 2: Run OverlapPolicy and verify RED**

Run:
`pwsh -NoProfile -File .\tools\data\evaluation\p4-3a2-ocr\test-evaluation.ps1 -Group OverlapPolicy`

Expected: FAIL before classifier implementation.

- [ ] **Step 3: Implement minimal classifier**

Do not add text-specific exceptions, business-name exceptions, pixel allowances, adaptive thresholds, or confidence tie-breakers. `SAFE_ADJACENT` is permitted only after both words independently have `UNIQUE` membership in the same cell.

- [ ] **Step 4: Select classifier candidate mechanically**

Run the fixed controls for `0.25`, `0.50`, `0.75`. Select the lowest candidate that passes every positive/negative control. If none passes, emit `GATE_A_CLASSIFIER_REJECTED` and stop the plan after recording evidence.

- [ ] **Step 5: Re-run OverlapPolicy**

Expected: PASS with exactly one recorded selected fixed policy or an explicit Gate A rejection; no silent fallback.

- [ ] **Step 6: Commit**

`git add tools/data/evaluation/p4-3a2-ocr/run-evaluation.ps1 tools/data/evaluation/p4-3a2-ocr/test-evaluation.ps1`
`git commit -m "test: classify safe same-cell OCR overlap"`

---

### Task 3: Real PSM11 Acceptance + Confidence Gate + PSM Regression

**Files:**
- Create: `tools/data/evaluation/p4-3a2-ocr/fixtures/generate-fixtures.py`
- Create: `tools/data/evaluation/p4-3a2-ocr/fixtures/manifest.json`
- Create: A2-specific degraded-text PDFs
- Modify: `tools/data/evaluation/p4-3a2-ocr/run-evaluation.ps1`
- Modify: `tools/data/evaluation/p4-3a2-ocr/test-evaluation.ps1`
- Modify: `tools/data/evaluation/p4-3a2-ocr/README.md`

**Interfaces:**
- `Invoke-P43a2AcceptanceMatrix -Executable -ModelPath -SameRegionRatio` runs retained `gray.pdf` and `rgb.pdf`, PSM 11, two repetitions each, plus PSM 3/4/6 regression runs.
- A2 degraded fixture keeps the exact ruled grid black/unchanged while degrading **text pixels only**; grid must remain `COMPLETE` before confidence is evaluated.
- Confidence candidates are exactly `0,50,80,90,95`.
- Evaluation row projection is technical-only: physical table row + reconstructed cell texts; it is not production `PDF_ROW`.

- [ ] **Step 1: Write failing Acceptance tests**

Assert:
- retained Gray/RGB PSM 11 produces at least one usable positive row with selected overlap policy;
- PSM 3/4/6 retain their prior containment failures and remain incomplete;
- clear positive acceptance is not caused by cell-boundary tolerance;
- safe-grid degraded-text fixture reaches OCR and becomes incomplete due confidence, not grid failure;
- candidate confidence threshold preserves all required clear header/business-name cells and at least one benefit field per fictional business;
- no threshold is accepted if clear/degraded confidence classes overlap so no fixed candidate separates them;
- repeated Gray/RGB PSM 11 results have identical membership/classification/status.

- [ ] **Step 2: Run Acceptance and verify RED**

Expected: FAIL because A2 fixtures/matrix are missing.

- [ ] **Step 3: Author only A2-specific fixtures**

Generate fictional Gray/RGB safe-grid degraded-text controls by drawing the grid at full black strength and degrading only text. Record generator version, file SHA-256, pixel hash, purpose, expected grid class, and fictional expected row strings in the A2 manifest. Do not regenerate or rewrite historical P4-3A fixtures.

- [ ] **Step 4: Implement the real acceptance matrix**

Use historical P4-3A inspect/grid helper read-only. Run exact Tesseract/model with PSM 11 positives and PSM 3/4/6 regressions. Run each clear Gray/RGB PSM 11 twice. Evaluate the five fixed confidence thresholds against the same OCR output; do not rerun OCR per threshold.

- [ ] **Step 5: Select confidence threshold mechanically**

Choose the lowest fixed threshold that:
1. keeps every required clear header/business identity word and at least one benefit field per row usable, and
2. makes the safe-grid degraded control incomplete because at least one required relevant word falls below threshold.

If no fixed threshold satisfies both, emit `GATE_A_CONFIDENCE_REJECTED` and stop later gates.

- [ ] **Step 6: Re-run Acceptance**

Expected: Gate A and Gate B PASS with PSM 11 usable positive > 0, PSM 3/4/6 still incomplete, or explicit `P4_3A2_REJECTED` evidence without proceeding.

- [ ] **Step 7: Commit**

`git add tools/data/evaluation/p4-3a2-ocr`
`git commit -m "test: prove P4-3A2 revised OCR acceptance"`

---

### Task 4: Business Isolation + Operational Safety + Multi-page Scope

**Files:**
- Modify: `tools/data/evaluation/p4-3a2-ocr/invoke-tesseract-eval.ps1`
- Modify: `tools/data/evaluation/p4-3a2-ocr/run-evaluation.ps1`
- Modify: `tools/data/evaluation/p4-3a2-ocr/test-evaluation.ps1`
- Modify: `tools/data/evaluation/p4-3a2-ocr/README.md`

**Interfaces:**
- `New-P43a2EvaluationRows -Cells -CellText` -> technical row objects with page/table/row ordinals and four fixture columns; no product provenance contract.
- `Find-P43a2EvaluationRow -Rows -BusinessName` -> exactly one row or `AMBIGUOUS/NOT_FOUND` technical lookup result.
- Result counters: `PdfOpenCount`, `PageReadCount`, `ImageDecodeCount`, `GridBuildCount`, `OcrInvocationCount`, `LookupCount`.
- Multi-page `Invoke-P43a2TesseractEvaluation` creates one temporary Tesseract image-list input for >1 page and requires TSV `page_num` to map exactly 1..N in input order.

- [ ] **Step 1: Write failing Safety tests**

Assert:
- Business A lookup returns only A row fields; Business B returns only B; leakage = 0;
- duplicate/conflict/cross-cell/low-confidence PARTIAL results expose no accepted technical row and no technical `NOT_FOUND`;
- native-text retained control executes OCR 0;
- two-business single-page control: PDF open 1, image decode 1, grid build 1, OCR 1, two lookups, no repeated OCR;
- empty OCR words, process-start failure, wrong identity, timeout, nonzero exit, malformed TSV, oversized TSV/stdout/stderr, oversized image/grid work all fail closed;
- temp artifacts are removed on success and failure;
- multipage uses one OCR process invocation and exact TSV page mapping, otherwise returns `MULTIPAGE_NOT_APPROVED`;
- missing/duplicate/out-of-order TSV page mapping is never repaired heuristically.

- [ ] **Step 2: Run Safety and verify RED**

Expected: FAIL before operational orchestration.

- [ ] **Step 3: Implement row isolation and work-count reuse**

Build the technical row projection only after the whole relevant evaluation result is `COMPLETE`. Perform two fictional business lookups against the same accepted row set. Do not source product locator/binding code or emit product claims.

- [ ] **Step 4: Implement fail-closed resource/fault handling**

Record/enforce bounded input pixels, decoded bytes, grid cells/work, TSV bytes/rows, stdout/stderr, wall time, and temp footprint. Measure working set but do not claim a portable hard-memory ceiling unless an enforcement mechanism is actually implemented.

- [ ] **Step 5: Evaluate multi-page scope**

Use retained `multipage.pdf`. If one-process list-mode yields deterministic exact page mapping and all other safety gates hold, record `MULTIPAGE_APPROVED`; otherwise record `MULTIPAGE_NOT_APPROVED` and constrain any future P4-3B v1 recommendation to single-page only. Multi-page failure alone does not rescue or reject unrelated single-page evidence.

- [ ] **Step 6: Re-run Safety**

Expected: Gate C/D PASS; Gate E is explicitly `MULTIPAGE_APPROVED` or `MULTIPAGE_NOT_APPROVED`.

- [ ] **Step 7: Commit**

`git add tools/data/evaluation/p4-3a2-ocr`
`git commit -m "test: bound P4-3A2 OCR safety and isolation"`

---

### Task 5: Windows/Ubuntu Determinism Evidence

**Files:**
- Create temporarily: `.github/workflows/p4-3a2-ocr-evaluation.yml`
- Modify only if comparison contract requires it: `tools/data/evaluation/p4-3a2-ocr/*.ps1`
- Remove workflow before final closeout.

**Interfaces:**
- `Export-P43a2DeterminismEvidence` -> normalized JSON containing exact engine/model/config identity, fixture hash, membership, overlap class, accepted/rejected word identities, cell assignment, normalized cell text, row projection, status, confidence distances from selected threshold, and non-semantic timing separately.
- Comparison result: `LEVEL_A|LEVEL_B|LEVEL_C`.

- [ ] **Step 1: Write DeterminismContract tests**

Assert normalized evidence excludes absolute paths/timing/temp names; semantic arrays are deterministically ordered; a changed cell assignment/text/status is Level C; confidence-only change with identical semantic acceptance can only be Level B when the recorded threshold margin is positive and larger than the observed aligned-word confidence delta.

- [ ] **Step 2: Run DeterminismContract and verify RED**

Expected: FAIL before exporter/comparator.

- [ ] **Step 3: Implement normalized evidence + comparator**

No fuzzy word alignment. Words align only by deterministic page/cell/classification/physical-order identity after accepted semantics match; inability to align required words is Level C.

- [ ] **Step 4: Add temporary Windows/Ubuntu workflow**

Windows evaluation supply:
- download the exact recorded Tesseract installer used by P4-3A;
- verify installer SHA-256 `bee9e3434bd94fd65387d9be28cd467a41f61b1275383b55b0f59a1331270ae4`;
- extract evaluation runtime without installer execution/admin/PATH mutation;
- obtain the exact official Korean model and verify SHA above.

Ubuntu evaluation supply:
- build/use official Tesseract 5.5.3 source identity only; do not substitute another engine version;
- use the same Korean model bytes/hash;
- record compiler/runtime/Leptonica provenance and resulting engine identity.

If exact 5.5.3 cannot be supplied on either platform, Gate F fails rather than substituting a different version.

- [ ] **Step 5: Run exact retained commit on both platforms**

Run selected PSM/config/policy/confidence over the same committed fixture bytes, upload only normalized evaluation evidence, and compare.

- [ ] **Step 6: Classify determinism**

- Level A: semantic comparison contract and relevant confidence values match.
- Level B: semantic outputs match; only permitted non-semantic/confidence values differ, and threshold-margin proof holds.
- Level C: any semantic membership/classification/accepted-word/cell-text/row/status difference, unaligned required word, or threshold decision difference.

Level C => `P4_3A2_REJECTED`.

- [ ] **Step 7: Remove temporary workflow and binary/model/raw OCR artifacts**

Retain run IDs, exact commit SHA, source/model hashes, normalized aggregate evidence/hash, and classification in handover; do not retain raw OCR fragments if they are unnecessary for audit.

- [ ] **Step 8: Commit retained harness changes if any**

`git commit -m "test: verify P4-3A2 cross-platform determinism"`

---

### Task 6: Gate Decision + Closeout

**Files:**
- Create: `docs/handover/2026-10-05-phase4-p4-3a2-overlap-safety-evaluation.md`
- Modify: `docs/current-work.md`
- Modify: `tools/data/evaluation/p4-3a2-ocr/README.md`

**Interfaces:**
- Final result exactly one of `P4_3A2_APPROVED_FOR_DEPENDENCY_REVIEW`, `P4_3A2_CONDITIONALLY_APPROVED`, `P4_3A2_REJECTED`.
- Multi-page scope recorded independently as `MULTIPAGE_APPROVED|MULTIPAGE_NOT_APPROVED`.

- [ ] **Step 1: Evaluate gates in order**

Mandatory for `APPROVED_FOR_DEPENDENCY_REVIEW`:
- Gate A: PSM 11 Gray/RGB usable positive > 0 with fixed selected overlap policy and defensible fixed confidence threshold;
- Gate B: cross-cell/duplicate/conflict/ordering negatives reject and PSM 3/4/6 remain incomplete;
- Gate C: two-business leakage = 0;
- Gate D: operational fail-closed/work-count/resource gates pass;
- Gate F: Level A or justified Level B.

Gate E may reduce future scope to single-page without rejecting otherwise safe single-page evidence.

Unresolved core safety is always `REJECTED`, never `CONDITIONALLY_APPROVED`.

- [ ] **Step 2: Write factual handover**

Record:
- base/spec/plan/head SHAs;
- historical P4-3A rejection preserved;
- exact runtime/model/config;
- selected or rejected same-region candidate;
- selected or rejected confidence threshold;
- Gray/RGB PSM 11 repetition results;
- PSM 3/4/6 regression results;
- negative classifier controls;
- business isolation;
- fault/resource/work counts;
- multi-page scope;
- Windows/Ubuntu supply and determinism;
- tests run/not run;
- protected-path diff;
- cleanup;
- remaining risks;
- exact final verdict.

- [ ] **Step 3: Run final local gates**

Run:
- `pwsh -NoProfile -File .\tools\data\evaluation\p4-3a2-ocr\test-evaluation.ps1 -Group All -TesseractExecutable <absolute> -KoreanModelPath <absolute>`
- locked restore/build of `tools/data/evaluation/p4-3a-ocr/Milimap.P4_3A.OcrEval.csproj`
- repository current `verify-data` gate / exact CI-equivalent
- `git diff --check origin/dev...HEAD`
- `git diff origin/dev...HEAD -- tools/data/evaluation/p4-3a-ocr tools/data/pdf-native tools/data/lib data/canonical data/seed apps`

Expected protected/historical diff: 0.

Android is `NOT_RUN_EVALUATION_ONLY` locally unless current repository CI policy runs it automatically.

- [ ] **Step 4: Update current-work with only proven status**

Do not change historical `P4-3A = REJECTED`. Add P4-3A2 result separately. Product dependency remains `NOT_APPROVED` and P4-3B remains `BLOCKED` even when the verdict is `APPROVED_FOR_DEPENDENCY_REVIEW`.

- [ ] **Step 5: Commit closeout evidence**

`git add docs/current-work.md docs/handover/2026-10-05-phase4-p4-3a2-overlap-safety-evaluation.md tools/data/evaluation/p4-3a2-ocr`
`git commit -m "docs: close out P4-3A2 OCR safety evaluation"`

- [ ] **Step 6: Stop for human dependency decision**

If approved/conditional, report the exact Tesseract runtime supply, required DLL/runtime set, model source/hash, licensing findings, Windows/Ubuntu reproducibility, footprint/resource evidence, selected config/policy, unsupported cases, multi-page status, and determinism class. Do not write a P4-3B plan until the user explicitly approves the exact product dependency.

## Test Method Summary

- TDD groups: `Contract`, `OverlapPolicy`, `Acceptance`, `Safety`, `DeterminismContract`, `All`.
- Historical P4-3A harness diff = 0.
- Fixed overlap-policy candidates: `0.25/0.50/0.75`; lowest all-controls-passing rule only.
- Exact cell containment; cross-cell ambiguity always reject.
- Duplicate/conflict/order synthetic negatives plus transitive line-bridge negative.
- Real PSM 11 Gray/RGB positives, two repetitions; PSM 3/4/6 regression.
- Safe-grid text-only degradation for confidence; fixed thresholds `0/50/80/90/95`.
- Two-business leakage = 0.
- PdfPig open 1; grid build 1; OCR <=1/document/run; lookup reuse.
- Fault/output/resource/temp-cleanup matrix.
- Multi-page explicit approved/not-approved scope.
- Windows/Ubuntu Level A/B/C evidence.
- Repository verify-data and protected-path diff.

## Risks

- A fixed same-region ratio may not separate real adjacent overlap from near-duplicate/conflicting OCR; failure means A2 rejection, not threshold expansion.
- Tesseract PSM 11 hierarchy can be sparse; the classifier must not turn hierarchy gaps into table structure or guessed text order.
- A safe-grid degraded-text fixture may still fail to create a defensible confidence separation; no threshold is better than an invented one.
- One-process multi-page Tesseract list mode may not provide stable page mapping; future scope may need single-page-only v1.
- Exact Tesseract 5.5.3 supply/build may differ across Windows/Ubuntu; Level C semantic variance blocks approval.
- Synthetic controls can overfit; classifier rules must remain identity/text-independent and pass actual PSM 11 output plus negatives.
- Evaluation-only resource limits are feasibility evidence, not a product hard-memory sandbox.
- Even a successful A2 result is not permission to add Tesseract/model to the product.

## Phase Position

```text
Phase 4 Multi-source Adapters
  P4-0 Foundation                    COMPLETE
  P4-1 HWPX Generic Adapter         COMPLETE
  P4-2 PDF Native Adapter           COMPLETE
  P4-3 OCR Fallback
       P4-3A                         REJECTED (historical)
       redesign spec                 APPROVED
       P4-3A2                        THIS PLAN
       product dependency            NOT_APPROVED
       P4-3B                         BLOCKED
  P4-4 Integration/Closeout         LATER
```

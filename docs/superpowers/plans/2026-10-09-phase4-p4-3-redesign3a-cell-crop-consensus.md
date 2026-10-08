# Phase 4 P4-3 Redesign 3A Cell-Crop OCR Consensus Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Evaluate whether exact proven-cell cropping plus fixed PSM 6/11 batch OCR can recover mandatory text fidelity and provide a fail-closed dual-view consensus signal without changing the OCR engine/model or product code.

**Architecture:** Add a new evaluation-only harness under `tools/data/evaluation/p4-3-redesign3a-ocr/`. Reuse historical PDF inspection/grid artifacts and fixture authorities read-only, prepare deterministic inner-cell crops once per fixture, execute one image-list batch per PSM, reconstruct each crop independently, then evaluate clear fidelity and false-consensus safety. Stop after Gates A-D regardless of outcome.

**Tech Stack:** PowerShell 7; retained .NET 8/PdfPig 0.1.16 historical P4-3A helper read-only; exact Windows Tesseract `v5.5.3.20260724` / engine 5.5.3; official `tessdata_fast/kor.traineddata`; PNM P5/P6 byte cropping using built-in .NET/PowerShell only.

**Spec:** `docs/superpowers/specs/2026-10-09-phase4-p4-3-redesign3a-cell-crop-consensus.md` at approved spec branch HEAD `789102f90112faec2f3b3e7883ba4758b8ec0490`.

## Problem

Redesign 2 proved that full-page OCR can be structurally safe while mandatory reconstructed text remains wrong. Redesign 3A must isolate whether the segmentation unit is the cause, not broaden the candidate search. It changes only the OCR input unit from full page to exact proven-cell interiors and requires two fixed segmentation views to agree before any runtime-like trust signal exists.

## Scope

- New evaluation-only Redesign 3A harness.
- Exact cell-inner crops from the existing proven grid.
- PSM 6 primary and PSM 11 verifier only.
- One batch OCR process per PSM per prepared fixture/run.
- Existing clear Gray/RGB, mild-degraded Gray, degraded Gray/RGB controls only.
- Existing authored fixture text as evaluation-only truth.
- Gates A-D only, then mandatory human review.

## Non-scope

- No product OCR adapter or P4-3B.
- No other OCR engine/model/build.
- No PSM/OEM/DPI search.
- No resize, thresholding, denoise, sharpening, line removal, contrast tuning, deskew, padding, adaptive crop, or other preprocessing.
- No fuzzy matching, character repair, whitespace-deletion joining, dictionary/user-word tuning, or expected-text runtime correction.
- No borderless inference.
- No API/schema/DB/auth/canonical/seed/apps changes.
- No dependency packaging.
- No Gates E-H in this execution cycle.

## Global Constraints

- Execution authority starts from `dev` merge baseline `4b57a4fbf45b730033f63d7de90d7030791b8c79` plus the approved spec/plan commits. Refresh `origin/dev` before implementation; newer GitHub truth wins if it conflicts.
- Historical paths are read-only:
  - `tools/data/evaluation/p4-3a-ocr/**`
  - `tools/data/evaluation/p4-3a2-ocr/**`
  - `tools/data/evaluation/p4-3-redesign2-ocr/**`
- Protected paths remain unchanged:
  - `tools/data/pdf-native/**`
  - `tools/data/lib/**`
  - `data/canonical/**`
  - `data/seed/**`
  - `apps/**`
- Exact runtime:
  - Tesseract Windows build `v5.5.3.20260724` / engine 5.5.3.
  - installer SHA-256 `bee9e3434bd94fd65387d9be28cd467a41f61b1275383b55b0f59a1331270ae4`.
  - `tesseract.exe` SHA-256 `c66f0f12ed76f6aa455dac97684bbc86756d6a732380bee09122454cfda3f420`.
  - `libtesseract-5.dll` SHA-256 `54d54528b453ce3a5ba79487687f8df43e7b194b9ea97beba74200453fe1fb46`.
  - `libleptonica-6.dll` SHA-256 `1869b44e3d46fd830620b042477e5d60a950779582f38f60291547efb27792f1`.
- Exact Korean model:
  - official `tessdata_fast` commit `87416418657359cb625c412a48b6e1d6d41c29bd`;
  - `kor.traineddata` SHA-256 `6b85e11d9bbf07863b97b3523b1b112844c43e7b194b9ea97beba74200453fe1fb46` is not authoritative and must not be used;
  - authoritative model SHA-256 is `6b85e11d9bbf07863b97b3523b1b112844c43e713df8b66418a081fd1060b3b2`.
- Language `kor`, OEM 1, DPI 300.
- PSM roles fixed: PSM 6 primary, PSM 11 verifier.
- Crop policy fixed: `PROVEN_CELL_CROP_V1`.
- Consensus policy fixed: `OCR_CELL_CONSENSUS_V1`.
- Same-cell overlap safety remains equivalent to the approved Redesign 2 fixed ratio 0.25; do not search/tune another ratio.
- Normalization semantics remain exactly `TEXT_FIDELITY_NORMALIZATION_V1`.
- Confidence remains `DIAGNOSTIC_ONLY_V1`.
- `ProductionAction=NONE` at every result boundary.
- Product dependency remains `NOT_APPROVED`; P4-3B remains `BLOCKED`.
- No push, PR, merge, dependency approval, or later-gate execution before the final human-review stop.

## File Structure

**Create**
- `tools/data/evaluation/p4-3-redesign3a-ocr/crop-cells.ps1` — exact P5/P6 validation and deterministic proven-cell crop-set preparation.
- `tools/data/evaluation/p4-3-redesign3a-ocr/invoke-tesseract-batch.ps1` — exact runtime/model boundary, image-list execution, TSV page-map validation, one invocation per PSM batch.
- `tools/data/evaluation/p4-3-redesign3a-ocr/run-evaluation.ps1` — historical fixture preparation, crop-local reconstruction, truth/fidelity, consensus, Gates A-D, final early-gate decision.
- `tools/data/evaluation/p4-3-redesign3a-ocr/test-evaluation.ps1` — TDD groups `CropProvenance`, `BatchMapping`, `ClearFidelity`, `ConsensusSafety`, `AllReached`.
- `tools/data/evaluation/p4-3-redesign3a-ocr/README.md` — exact scope, commands, measured first-cycle result.

**Read-only**
- `tools/data/evaluation/p4-3a-ocr/Milimap.P4_3A.OcrEval.csproj`
- `tools/data/evaluation/p4-3a-ocr/Program.cs`
- `tools/data/evaluation/p4-3a-ocr/fixtures/gray.pdf`
- `tools/data/evaluation/p4-3a-ocr/fixtures/rgb.pdf`
- `tools/data/evaluation/p4-3a-ocr/fixtures/generate-fixtures.py`
- `tools/data/evaluation/p4-3a-ocr/fixtures/manifest.json`
- `tools/data/evaluation/p4-3a2-ocr/fixtures/manifest.json`
- `tools/data/evaluation/p4-3a2-ocr/fixtures/mild-degraded-gray.pdf`
- `tools/data/evaluation/p4-3a2-ocr/fixtures/degraded-gray.pdf`
- `tools/data/evaluation/p4-3a2-ocr/fixtures/degraded-rgb.pdf`
- Redesign 2 harness for behavioral comparison only; do not dot-source it as runtime implementation.

**Temporary; never commit**
- exact Tesseract installer/runtime/model;
- crop PGM/PPM artifacts;
- Tesseract image-list files;
- raw TSV/output logs;
- probe scratch directories.

## Test Method

- TDD for every task: RED -> minimal GREEN -> targeted regression -> fresh task review -> commit.
- Historical helper restore/build remains locked.
- Exact runtime/model supply is repo-external and hash-verified before real OCR gates.
- Synthetic unit controls test failure semantics without creating new quality fixtures.
- Real OCR quality uses only existing committed fixtures.
- Full current `tools/data/test-*.ps1` suite runs at first-cycle completion.
- Android local remains `NOT_RUN_EVALUATION_ONLY` unless product/protected paths unexpectedly change; if they do, stop for scope review.

## Review Focus

1. **PNM coordinate/row semantics** — a crop at exact `X0/Y0/X1/Y1` must copy the same top-origin pixel rectangle used by the grid helper; a one-row/one-column offset must be caught by a byte-level crop test in Task 1.
2. **Batch page identity** — multiple TSV word rows per page are normal, but exactly one level-1 page record per logical crop page must exist; missing/duplicate/out-of-range level-1 page records must fail in Task 2.
3. **Crop-local overlap** — duplicate/conflicting/ordering-unsafe OCR words inside one crop must never be joined into trusted text; Task 3 pins the fixed 0.25 safety semantics.
4. **Correlated wrong agreement** — PSM6 and PSM11 agreeing on the same wrong mandatory text must become `FALSE_CONSENSUS`, not a consensus PASS; Task 4 tests both synthetic and historical degraded evidence.
5. **Degraded control recovery** — cell cropping may make an old full-page empty-output fixture produce words. If that occurs, evaluate its authored truth/consensus; never require it to remain empty and never reinterpret non-empty output as a failure of the historical experiment. Task 4 pins both empty and recovered-output paths.

---

### Task 1: Evaluation Boundary + Gate A Proven Cell-Crop Preparation

**Files:**
- Create: `tools/data/evaluation/p4-3-redesign3a-ocr/crop-cells.ps1`
- Create: `tools/data/evaluation/p4-3-redesign3a-ocr/run-evaluation.ps1`
- Create: `tools/data/evaluation/p4-3-redesign3a-ocr/test-evaluation.ps1`
- Create: `tools/data/evaluation/p4-3-redesign3a-ocr/README.md`

**Interfaces:**
- `Get-P43R3aPnmDescriptor -Path <string> -ExpectedSha256 <string>`
  -> validates the exact retained P5/P6 artifact shape and returns `Magic, Width, Height, Components, HeaderLength, PixelByteLength, SourceSha256`.
- `New-P43R3aCellCropSet -ImagePath <string> -ImageSha256 <string> -Cells <object[]> -OutputDirectory <string>`
  -> `Status, Code, Policy='PROVEN_CELL_CROP_V1', SourcePixelSha256, CropBuildCount=1, Crops[]`.
- Each crop exposes `Ordinal, CellId, Row, Column, X0, Y0, X1, Y1, Width, Height, Components, ArtifactPath, CropSha256`.
- `Prepare-P43R3aFixture -PdfPath <string> -ArtifactDirectory <string>`
  -> uses the historical helper read-only exactly once for inspect and once for grid, then returns `PdfOpenCount, PageReadCount, ImageDecodeCount, GridBuildCount, CropBuildCount, Cells, Crops, SourcePixelSha256, FixtureHash`.
- `Invoke-P43R3aGateA -PreparedFixture <object>`
  -> `GATE_A_CROP_PROVENANCE_PASS|GATE_A_CROP_PROVENANCE_FAILED`.

- [ ] **Step 1: Write failing `CropProvenance` tests**

Pin all of the following:

- exact P5 Gray and P6 RGB header parsing;
- source SHA mismatch -> fail closed;
- top-left, middle, and bottom-right known rectangles copy byte-exact expected rows/columns, proving coordinate orientation and exclusive `X1/Y1`;
- zero/negative/out-of-bounds rectangle -> fail;
- duplicate CellId -> fail;
- duplicate Row/Column -> fail;
- missing one of the retained 12 required CellIds -> fail;
- crop count other than 12 for the retained fixture -> fail;
- repeated crop preparation from the same source/cells produces identical crop hashes;
- crop filenames/order derive only from proven ordinal/CellId, not OCR text;
- clear Gray and clear RGB real fixture preparation each reports PDF open 1, decode 1, grid 1, crop build 1, 12 deterministic crops;
- historical and protected diffs remain zero.

- [ ] **Step 2: Run `CropProvenance` and verify RED**

Run:

`pwsh -NoProfile -File .\tools\data\evaluation\p4-3-redesign3a-ocr\test-evaluation.ps1 -Group CropProvenance`

Expected: FAIL because Redesign 3A crop functions do not yet exist.

- [ ] **Step 3: Implement exact PNM crop preparation**

Use built-in byte operations only.

The PNM reader accepts only the retained deterministic artifact shape:

```text
P5|P6
<width> <height>
255
<raw pixels>
```

No general PNM comments/alternate max values/format conversion are added.

Crop bytes must be the source row slices for `x in [X0,X1)`, `y in [Y0,Y1)`, with the same component count. Emit the same compact PNM header shape for each crop.

Do not resize, pad, recolor, threshold, or remove grid/text pixels.

- [ ] **Step 4: Implement real fixture preparation and Gate A**

`Prepare-P43R3aFixture` must:

1. call the historical P4-3A helper `inspect` once;
2. require image-only `ELIGIBLE`, exactly one mapped image, supported Gray/RGB bytes;
3. call historical `grid` once;
4. require grid `COMPLETE` and exactly 12 cells;
5. convert the proven cell IDs/coordinates without modification;
6. build one crop set;
7. never call OCR.

`Invoke-P43R3aGateA` passes only when every provenance/count/hash invariant is true.

- [ ] **Step 5: Re-run `CropProvenance`**

Expected: PASS for synthetic controls and clear Gray/RGB real preparation.

If Gate A fails on retained clear controls, record:

`P4_3_REDESIGN3A_REJECTED / GATE_A_CROP_PROVENANCE_FAILED`

Stop Tasks 2-5 except rejection verification/reporting explicitly authorized by human review.

- [ ] **Step 6: Commit**

```bash
git add tools/data/evaluation/p4-3-redesign3a-ocr
git commit -m "test: prove P4-3 redesign3a crop provenance"
```

---

### Task 2: Gate B Exact Batch OCR + Logical Page Mapping

**Precondition:** Gate A passes.

**Files:**
- Create: `tools/data/evaluation/p4-3-redesign3a-ocr/invoke-tesseract-batch.ps1`
- Modify: `tools/data/evaluation/p4-3-redesign3a-ocr/run-evaluation.ps1`
- Modify: `tools/data/evaluation/p4-3-redesign3a-ocr/test-evaluation.ps1`
- Modify: `tools/data/evaluation/p4-3-redesign3a-ocr/README.md`

**Interfaces:**
- `ConvertFrom-P43R3aBatchTsv -Text <string> -ExpectedPageCount <int>`
  -> validates TSV hierarchy and returns `Pages[]` with one logical page descriptor per crop plus mapped word records preserving `Page, Block, Paragraph, Line, Word, Left, Top, Width, Height, Confidence, Text`.
- `Invoke-P43R3aTesseractBatch -Executable <string> -ModelPath <string> -Crops <object[]> -Psm <6|11>`
  -> `Status, Code, Psm, InvocationCount, EngineVersion, EngineBuild, ModelSha256, Pages, Words, Diagnostics, ProductionAction='NONE'`.
- Every mapped word/result page additionally exposes the already-prepared `CropOrdinal` and `CellId`.
- `Invoke-P43R3aGateB -PreparedFixture <object> -Executable <string> -ModelPath <string>`
  -> one real PSM6 batch and one real PSM11 batch, then `GATE_B_BATCH_MAPPING_PASS|GATE_B_BATCH_MAPPING_FAILED|GATE_B_BATCH_MAPPING_NOT_EVALUATED`.

- [ ] **Step 1: Write failing `BatchMapping` contract tests**

Use a process seam for parser/mapping faults and assert:

- public batch API accepts only PSM 6 or 11;
- exact runtime/model identity is mandatory;
- crop ordinals must be exactly 1..N and CellIds unique;
- image-list order follows crop ordinal exactly;
- one level-1 TSV page record exists for every expected page 1..N;
- multiple level-5 word records on the same page are valid;
- missing level-1 page -> fail;
- duplicated level-1 page -> fail;
- extra/out-of-range page -> fail;
- malformed TSV/word bbox/confidence -> fail;
- no word records for a required crop page -> `BATCH_REQUIRED_PAGE_EMPTY`;
- runtime/model mismatch, timeout, nonzero exit, oversized output -> fail closed;
- no `ConfidenceThreshold` or confidence-based winner exists;
- no per-cell fallback invocation is exposed.

- [ ] **Step 2: Run `BatchMapping` and verify RED**

Run:

`pwsh -NoProfile -File .\tools\data\evaluation\p4-3-redesign3a-ocr\test-evaluation.ps1 -Group BatchMapping`

Expected: FAIL before the batch wrapper exists.

- [ ] **Step 3: Implement the exact batch wrapper**

Runtime boundary:

- verify the official Korean model hash ending `...60b3b2`;
- verify engine identity `v5.5.3.20260724 / 5.5.3`;
- create one temporary image-list file containing absolute crop paths in ordinal order;
- invoke Tesseract exactly once for the requested PSM;
- use `-l kor --oem 1 --psm <6|11> --dpi 300 -c tessedit_create_tsv=1`;
- parse and validate exact page-map identity;
- map logical page N to crop ordinal N / its CellId;
- clean the list/output scratch on success/failure.

Do not call the historical single-input wrapper repeatedly.

- [ ] **Step 4: Run real Gate B on one prepared clear fixture**

Using exact verified runtime/model, prepare clear Gray once, then run:

- PSM6 batch exactly once;
- PSM11 batch exactly once.

Require:

- each invocation count = 1;
- 12 logical pages map exactly to 12 crops/CellIds;
- mapping/order is identical between PSM6 and PSM11;
- all required crop pages contain word output;
- no heuristic page repair.

If the installed Tesseract image-list behavior cannot satisfy exact mapping, Gate B fails. Do not fall back to 12 individual invocations.

- [ ] **Step 5: Re-run `BatchMapping`**

Expected: PASS only if synthetic negative controls and the real exact-runtime batch mapping both pass.

If Gate B fails:

`P4_3_REDESIGN3A_REJECTED / GATE_B_BATCH_MAPPING_FAILED`

If exact supply cannot be reproduced:

`P4_3_REDESIGN3A_NOT_EVALUATED`

Stop later gates.

- [ ] **Step 6: Commit**

```bash
git add tools/data/evaluation/p4-3-redesign3a-ocr
git commit -m "test: prove P4-3 redesign3a batch OCR mapping"
```

---

### Task 3: Gate C Crop-Local Reconstruction + Clear Fidelity

**Precondition:** Gates A-B pass.

**Files:**
- Modify: `tools/data/evaluation/p4-3-redesign3a-ocr/run-evaluation.ps1`
- Modify: `tools/data/evaluation/p4-3-redesign3a-ocr/test-evaluation.ps1`
- Modify: `tools/data/evaluation/p4-3-redesign3a-ocr/README.md`

**Interfaces:**
- `Get-P43R3aOverlapClass -A <word> -B <word>`
  -> `NONE|SAFE_ADJACENT|DUPLICATE|CONFLICTING|ORDERING_UNSAFE`, fixed ratio 0.25.
- `Resolve-P43R3aCropText -PageWords <object[]> -CellId <string>`
  -> `Status='COMPLETE|PARTIAL', Text, Diagnostics, RawWordConfidences`.
- `ConvertTo-P43R3aCellTexts -BatchResult <object>`
  -> one cell result per prepared crop, keyed by CellId.
- `Get-P43R3aFixtureGroundTruth`
  -> asserts historical clear/A2 authority and exposes authored 12-cell text for clear, mild-degraded, degraded Gray/RGB fixtures.
- `Normalize-P43R3aFidelityText -Text <string>`
  -> exact `TEXT_FIDELITY_NORMALIZATION_V1` semantics.
- `Evaluate-P43R3aFidelity -Fixture <string> -FixtureHash <string> -Psm <6|11> -CellTexts <object[]>`
  -> per-cell evidence plus mandatory/all-cell match counts.
- `Invoke-P43R3aGateC -GrayPrepared <object> -RgbPrepared <object> -Executable <string> -ModelPath <string>`
  -> `GATE_C_CLEAR_FIDELITY_PASS|GATE_C_CLEAR_FIDELITY_FAILED|GATE_C_CLEAR_FIDELITY_NOT_EVALUATED`.

- [ ] **Step 1: Write failing crop-local reconstruction tests**

Pin:

- safe adjacent words reconstruct deterministically despite enumeration order;
- confidence 1 is not rejected when structure/text is otherwise safe;
- duplicate same-region text -> PARTIAL;
- conflicting same-region text -> PARTIAL;
- ordering reversal -> PARTIAL;
- transitive vertical bridge/non-clique line -> PARTIAL;
- multiline reconstruction is deterministic;
- fixed overlap ratio remains 0.25 and is not a parameter search;
- expected text is absent from reconstruction signatures.

- [ ] **Step 2: Write failing fidelity-authority tests**

Assert:

- historical clear generator/manifest blob/hash identities are unchanged;
- A2 manifest blob is unchanged and its `expectedRows` is accepted only after the manifest/fixture hash is verified;
- clear Gray/RGB and all three A2 fixtures expose the same authored 3x4 table without reading OCR output;
- normalization only folds allowed horizontal whitespace/CRLF/outer whitespace;
- decomposed Korean, changed digit, punctuation change, or character substitution remains unequal;
- exact low-confidence text passes fidelity;
- high-confidence wrong text fails fidelity;
- mandatory roles remain 4 header + 2 business-name + 2 benefit = 8.

- [ ] **Step 3: Run `ClearFidelity` and verify RED**

Run:

`pwsh -NoProfile -File .\tools\data\evaluation\p4-3-redesign3a-ocr\test-evaluation.ps1 -Group ClearFidelity`

Expected: FAIL before reconstruction/fidelity functions exist.

- [ ] **Step 4: Implement crop-local reconstruction and truth/fidelity**

Port only the already-proven overlap/reconstruction semantics into Redesign 3A-local functions.

Do not dot-source Redesign 2 `run-evaluation.ps1`; historical evaluation remains immutable and isolated.

For A2 fixtures, read authored expected rows only from the verified historical manifest after asserting its exact Git blob and fixture hash. Never infer expected text from OCR.

- [ ] **Step 5: Execute the fixed clear matrix**

For clear Gray and clear RGB:

1. prepare each fixture once;
2. retain that crop set for all OCR repetitions;
3. run PSM6 twice;
4. run PSM11 twice;
5. do not reopen/redecode/regrid for repetition.

Total clear quality OCR processes:

`2 fixtures x 2 repetitions x 2 PSM = 8`.

Each PSM path independently must achieve mandatory 8/8 on every repetition.

Measure all-cell matches /12 but do not change the gate after observation.

Repeated outputs for the same fixture/PSM must be identical for mapped words, reconstructed cell text, fidelity state, and diagnostics except elapsed time.

- [ ] **Step 6: Re-run `ClearFidelity`**

PASS requires:

- Gray PSM6 mandatory 8/8, both repetitions;
- Gray PSM11 mandatory 8/8, both repetitions;
- RGB PSM6 mandatory 8/8, both repetitions;
- RGB PSM11 mandatory 8/8, both repetitions;
- no mandatory NOT_EVALUATED;
- repetition determinism.

Any mandatory mismatch:

`P4_3_REDESIGN3A_REJECTED / GATE_C_CLEAR_FIDELITY_FAILED`

Stop Task 4 quality evaluation after preserving the factual failure evidence.

- [ ] **Step 7: Commit**

```bash
git add tools/data/evaluation/p4-3-redesign3a-ocr
git commit -m "test: qualify P4-3 redesign3a clear cell fidelity"
```

---

### Task 4: Gate D Dual-PSM Consensus Safety

**Precondition:** Gates A-C pass.

**Files:**
- Modify: `tools/data/evaluation/p4-3-redesign3a-ocr/run-evaluation.ps1`
- Modify: `tools/data/evaluation/p4-3-redesign3a-ocr/test-evaluation.ps1`
- Modify: `tools/data/evaluation/p4-3-redesign3a-ocr/README.md`

**Interfaces:**
- `Compare-P43R3aCellConsensus -Psm6Cells <object[]> -Psm11Cells <object[]>`
  -> per-cell `CELL_CONSENSUS|CELL_DISAGREEMENT|CELL_NOT_EVALUATED`, preserving both texts/confidences.
- `Evaluate-P43R3aConsensusSafety -Fixture <string> -FixtureHash <string> -Psm6Cells <object[]> -Psm11Cells <object[]> -GroundTruth <object>`
  -> per-cell consensus + fidelity classification including `FALSE_CONSENSUS`.
- `Invoke-P43R3aGateD -ClearEvidence <object> -Executable <string> -ModelPath <string>`
  -> evaluates clear agreement plus mild/degraded controls and returns `GATE_D_CONSENSUS_SAFETY_PASS|GATE_D_CONSENSUS_SAFETY_FAILED|GATE_D_CONSENSUS_SAFETY_NOT_EVALUATED`.
- `Get-P43R3aEarlyGateDecision -GateA -GateB -GateC -GateD`
  -> exact final first-cycle verdict and safety statuses.

- [ ] **Step 1: Write failing consensus unit tests**

Pin:

- exact normalized PSM6/PSM11 equality -> CELL_CONSENSUS;
- one-character difference -> CELL_DISAGREEMENT regardless of confidence;
- missing/untrusted PSM result -> CELL_NOT_EVALUATED;
- both agree on authored truth -> safe consensus;
- both agree on the same wrong mandatory text -> FALSE_CONSENSUS;
- correct PSM6 + wrong PSM11 -> disagreement/fail closed, never pick PSM6 by confidence;
- wrong PSM6 + correct PSM11 -> disagreement/fail closed;
- confidence 1 vs 99 does not select a winner.

- [ ] **Step 2: Run `ConsensusSafety` and verify RED**

Run:

`pwsh -NoProfile -File .\tools\data\evaluation\p4-3-redesign3a-ocr\test-evaluation.ps1 -Group ConsensusSafety`

Expected: FAIL before consensus functions exist.

- [ ] **Step 3: Implement consensus and false-consensus classification**

Consensus compares only normalized reconstructed strings.

Ground truth participates only in the evaluation-only safety classifier to distinguish:

- correct consensus;
- false consensus;
- disagreement;
- not evaluated.

It must not feed back into either OCR path or choose a winner.

- [ ] **Step 4: Execute mild-degraded safety control**

Prepare `mild-degraded-gray.pdf` once.

Run exactly:

- PSM6 batch once;
- PSM11 batch once.

For every mandatory cell:

- same correct text -> safe;
- disagreement -> fail closed and safe against false acceptance;
- same wrong text -> FALSE_CONSENSUS and hard rejection;
- missing/untrusted output -> NOT_EVALUATED/fail closed.

A single mandatory FALSE_CONSENSUS -> Gate D failure.

- [ ] **Step 5: Execute old degraded Gray/RGB controls**

Prepare each old degraded fixture once.

Run one PSM6 and one PSM11 batch per fixture.

Historical full-page empty output is not a required Redesign 3A outcome.

If a crop path is empty/untrusted:

- preserve FAILED/NOT_EVALUATED;
- emit no consensus, row, absence, or claim.

If cell cropping recovers words:

- verify the fixture hash and authored `expectedRows` from the historical A2 manifest;
- reconstruct and compare PSM6/PSM11;
- detect FALSE_CONSENSUS exactly as for mild degradation;
- do not label recovered output as a historical-regression failure merely because the old full-page experiment returned zero words.

This step exists specifically to avoid overfitting the new design to the prior execution shape.

- [ ] **Step 6: Implement the early-gate decision**

Rules:

- any A-D explicit failure -> `P4_3_REDESIGN3A_REJECTED` with the exact first failing gate reason;
- any required gate NOT_EVALUATED without an explicit failure -> `P4_3_REDESIGN3A_NOT_EVALUATED`;
- A-D all pass -> `P4_3_REDESIGN3A_EARLY_GATES_PASS`.

Every outcome also returns:

- `NextAction='HUMAN_REVIEW_STOP'`;
- `ProductDependency='NOT_APPROVED'`;
- `P43B='BLOCKED'`;
- `ProductionAction='NONE'`;
- Gates E-H = `BLOCKED_NOT_AUTHORIZED`.

- [ ] **Step 7: Re-run `ConsensusSafety`**

Expected PASS as a test group only when all assertions faithfully classify the measured evidence. The measured Gate D itself remains evidence-driven.

If Gate D rejects, do not tune crop/PSM/normalization or start preprocessing.

- [ ] **Step 8: Commit**

```bash
git add tools/data/evaluation/p4-3-redesign3a-ocr
git commit -m "test: evaluate P4-3 redesign3a consensus safety"
```

---

### Task 5: First-Cycle Verification + Result Recording + Human Review Stop

**Precondition:** Tasks 1-4 have reached a factual first-cycle verdict. This task verifies and records; it does not rescue a rejected candidate.

**Files:**
- Modify: `tools/data/evaluation/p4-3-redesign3a-ocr/README.md`
- Modify Redesign 3A evaluation code only if a verification bug prevents faithful reporting; any semantic change requires a fresh RED/GREEN cycle and task review.

**Interfaces:**
- `test-evaluation.ps1 -Group AllReached -TesseractExecutable <absolute-exe> -KoreanModelPath <absolute-model>`
  -> runs only Gates A-D and their reached controls; never fabricates later-gate PASS values.

- [ ] **Step 1: Re-run the exact first-cycle matrix from a clean tree**

Verify exact runtime/model hashes, then run:

- `CropProvenance`;
- `BatchMapping`;
- `ClearFidelity` if Gate B reached/passed;
- `ConsensusSafety` if Gate C reached/passed;
- `AllReached` for the reached first-cycle path.

If an earlier gate is rejected, `AllReached` must validate that later gates are blocked rather than attempt them.

- [ ] **Step 2: Run repository regression verification**

Run:

- historical helper `dotnet restore --locked-mode`;
- historical helper Release build `--no-restore`;
- historical P4-3A/P4-3A2/Redesign2 relevant contract checks;
- full current sorted `tools/data/test-*.ps1` suite with failure propagation;
- `git diff --check`;
- historical P4-3A diff = 0;
- historical P4-3A2 diff = 0;
- historical Redesign 2 diff = 0;
- protected-path diff = 0.

Android local:

`NOT_RUN_EVALUATION_ONLY`

If a protected/product path changed unexpectedly, stop instead of expanding scope.

- [ ] **Step 3: Verify efficiency counters**

Report, without rounding away actual counts:

- per prepared fixture: PDF open, page read, image decode, grid build, crop build;
- clear quality OCR process count;
- mild/degraded safety OCR process count;
- total OCR process count;
- no per-cell OCR fallback;
- no business lookup OCR path exists in this first cycle.

For the clear Gray/RGB matrix, target OCR count is exactly 8.

If batch mapping passed but the implementation used 96 per-cell processes, the design is non-compliant even if fidelity passes.

- [ ] **Step 4: Record the factual result in README**

README must contain:

- branch/HEAD at measurement time;
- exact runtime/model identities/hashes;
- Gate A result;
- Gate B result;
- Gate C per-fixture/per-PSM mandatory and all-cell counts;
- Gate D clear/degraded consensus classification;
- every mandatory mismatch or FALSE_CONSENSUS;
- invocation/reuse counters;
- final first-cycle verdict;
- tests run;
- tests not run;
- historical/protected diffs;
- remaining risks.

Do not claim population accuracy, live-source validation, dependency approval, P4-3B eligibility, or Phase 4 completion.

- [ ] **Step 5: Remove repo-external evaluation supply and temporary artifacts**

After evidence is recorded:

- delete dedicated Tesseract/model evaluation directory;
- verify no crop/list/TSV/probe scratch remains;
- verify no runtime/model binary appears in Git status.

Do not remove shared SDKs or unrelated local tools.

- [ ] **Step 6: Commit result recording**

```bash
git add tools/data/evaluation/p4-3-redesign3a-ocr
git commit -m "docs: record P4-3 redesign3a early-gate result"
```

- [ ] **Step 7: Whole-branch read-only review**

Review `origin/dev...HEAD` against the approved spec/plan.

Critical or Important issue -> stop and report; do not push.

- [ ] **Step 8: HUMAN REVIEW STOP**

Report:

- branch/worktree/final HEAD;
- Task commit SHAs;
- changed files;
- exact runtime/model hashes;
- Gate A-D results and reasons;
- clear Gray/RGB PSM6/PSM11 mandatory and all-cell counts;
- per-cell disagreement/FALSE_CONSENSUS evidence;
- degraded-control outcomes, including whether cropping recovered previously empty output;
- PDF/decode/grid/crop/OCR counters;
- full data-suite result;
- historical A/A2/Redesign2/protected diffs;
- Android NOT_RUN reason;
- tests not run;
- remaining risks;
- final first-cycle verdict.

Do not push.
Do not open PR.
Do not merge.
Do not approve dependency.
Do not start Gates E-H.
Do not start preprocessing.
Do not start another engine/model evaluation.

---

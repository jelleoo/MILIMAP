# Phase 4 P4-3 Redesign 3C Content-Tight Crop Evaluation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Determine whether deterministic removal of exact-white excess margins, followed by a fixed 10 px white border, recovers mandatory OCR fidelity while every OCR/model/reconstruction rule remains the historical Redesign 3A fast-model baseline.

**Architecture:** Add one Redesign 3C-local crop-transform helper, then feed its transformed crops directly into the existing Redesign 3A fast-model batch/reconstruction/fidelity path. Run Gray first and stop immediately on failure; implement/run RGB, consensus, and degraded gates only if earlier gates actually pass.

**Tech Stack:** PowerShell 7; historical .NET 8/PdfPig 0.1.16 image/grid helper through Redesign 3A; fixed Tesseract `v5.5.3.20260724`; pinned official `tessdata_fast/kor.traineddata`; built-in .NET byte/hash/process APIs; no new dependency.

**Spec:** `docs/superpowers/specs/2026-10-12-phase4-p4-3-redesign3c-content-tight-crop.md` at approved spec HEAD `2b482a628d68455d4d7b23410dbb0aa4ab99c3f2`.

## Global Constraints

- Implementation base is latest `origin/dev`; approved baseline is `4c21fcc878760f6ce5d581d346bdd5b9281b0c9a`. Refresh before execution and stop if newer changes alter P4-3 assumptions.
- Experimental reference is Redesign 3A, not Redesign 3B.
- Single changed variable: `PROVEN_CELL_CROP_V1` -> `CONTENT_TIGHT_WHITE255_BORDER10_V1`.
- Fixed fast model:
  - source commit `87416418657359cb625c412a48b6e1d6d41c29bd`;
  - Git blob `60986d44497689f3abace0b148199476d93292e1`;
  - bytes `1677415`;
  - SHA-256 `6b85e11d9bbf07863b97b3523b1b112844c43e713df8b66418a081fd1060b3b2`.
- Fixed runtime:
  - `tesseract v5.5.3.20260724`;
  - `tesseract.exe` SHA-256 `c66f0f12ed76f6aa455dac97684bbc86756d6a732380bee09122454cfda3f420`;
  - `libtesseract-5.dll` SHA-256 `54d54528b453ce3a5ba79487687f8df43e7b194b9ea97beba74200453fe1fb46`;
  - `libleptonica-6.dll` SHA-256 `1869b44e3d46fd830620b042477e5d60a950779582f38f60291547efb27792f1`.
- OCR configuration remains `kor`, OEM1, DPI argument 300, PSM6/11 only.
- Reuse Redesign 3A batch, reconstruction, overlap, normalization, fidelity, and determinism semantics unchanged.
- No `tessdata_best` quality OCR, resize, thresholding, binarization, morphology, line removal, sharpening, denoise, adaptive border, border search, PSM/OEM/DPI search, whitespace repair, geometry-aware reconstruction, or alternate OCR engine.
- Historical evaluation trees are read-only:
  - `tools/data/evaluation/p4-3a-ocr/**`
  - `tools/data/evaluation/p4-3a2-ocr/**`
  - `tools/data/evaluation/p4-3-redesign2-ocr/**`
  - `tools/data/evaluation/p4-3-redesign3a-ocr/**`
  - `tools/data/evaluation/p4-3-redesign3b-ocr/**`
- Protected paths remain unchanged:
  - `tools/data/pdf-native/**`
  - `tools/data/lib/**`
  - `data/canonical/**`
  - `data/seed/**`
  - `apps/**`
- `ProductionAction=NONE`, Product dependency `NOT_APPROVED`, P4-3B `BLOCKED`, P4-3/Phase 4 `NOT COMPLETE`.
- Push/PR/merge happen only after human review of the completed evaluation result.

## File Structure

**Create**
- `tools/data/evaluation/p4-3-redesign3c-ocr/content-tight-crops.ps1` — exact-white content bounds, fixed 10 px border generation, transform provenance.
- `tools/data/evaluation/p4-3-redesign3c-ocr/run-evaluation.ps1` — Gate A, B1, conditional B2/C/D, early-stop verdict.
- `tools/data/evaluation/p4-3-redesign3c-ocr/test-evaluation.ps1` — synthetic contracts, actual reached runner, reporting verification.
- `tools/data/evaluation/p4-3-redesign3c-ocr/README.md` — commands and factual measurement/closeout.

**Read-only reuse**
- Redesign 3A `crop-cells.ps1`
- Redesign 3A `invoke-tesseract-batch.ps1`
- Redesign 3A `run-evaluation.ps1`
- existing historical fixtures and ground truth.

**Never commit**
- Tesseract runtime/model supply;
- transformed PGM/PPM crops;
- raw TSV/stderr;
- reached evidence JSON.

## Review Focus

1. **Generated border mistaken for source evidence** — tests must distinguish source content rectangle from generated white pixels and prohibit provenance claims outside the original cell.
2. **Exact-white classifier accidentally becomes a threshold** — tests pin only exact 255 / 255,255,255 as background; 254 and anti-aliased values remain content.
3. **PNM row/channel copy mistakes** — tests cover P5/P6, edge pixels, one-pixel content, and exact byte-for-byte content preservation.
4. **Transform rebuilding between OCR repetitions** — B1 tests require one transform build and reuse of identical transformed crop hashes for all four calls.
5. **Early-stop leakage** — any B1 rejection must leave RGB/consensus/degraded preparation and OCR counts at zero.

---

### Task 1: Content-Tight Transform + Gate A

**Files:**
- Create: `tools/data/evaluation/p4-3-redesign3c-ocr/content-tight-crops.ps1`
- Create: `tools/data/evaluation/p4-3-redesign3c-ocr/run-evaluation.ps1`
- Create: `tools/data/evaluation/p4-3-redesign3c-ocr/test-evaluation.ps1`
- Create: `tools/data/evaluation/p4-3-redesign3c-ocr/README.md`

**Interfaces:**
- `Get-P43R3cContentBounds -Path <string> -ExpectedSha256 <string>` -> `Status, Code, X0,Y0,X1,Y1,Width,Height,NonWhitePixelCount,Components`.
- `New-P43R3cContentTightCropSet -PreparedFixture <object> -OutputDirectory <string>` -> `Status, Code, Policy, BorderPixels, TransformBuildCount, Crops[], ProductionAction`.
- Every transformed crop exposes historical batch fields `Ordinal,CellId,ArtifactPath,CropSha256,Width,Height` plus source-crop/content-bounds provenance.
- `Invoke-P43R3cGateA -PreparedFixture <object> -TransformedSet <object>` -> `GATE_A_CONTENT_TIGHT_PROVENANCE_PASS|GATE_A_CONTENT_TIGHT_PROVENANCE_NOT_EVALUATED`.

- [ ] **Step 1: Write failing `Transform` tests**

Pin exact cases:

- P5 all-white -> `EMPTY_CONTENT`;
- P6 all-white -> `EMPTY_CONTENT`;
- P5 value 254 counts as content;
- P6 any one component 254 counts as content;
- one-pixel content gives 21x21 output;
- content touching source edge is valid;
- generated border is exactly 10 px each side;
- P5/P6 source content region is copied byte-for-byte;
- malformed PNM/source-hash mismatch fails closed;
- output hash repeats exactly in separate directories;
- expected text is not an input/property consumed by the transform;
- no OCR/process invocation occurs.

- [ ] **Step 2: Run `Transform` and verify RED**

Run:

`pwsh -NoProfile -File .\tools\data\evaluation\p4-3-redesign3c-ocr\test-evaluation.ps1 -Group Transform`

Expected: FAIL because 3C transform functions do not exist.

- [ ] **Step 3: Implement exact-white transform**

Use Redesign 3A PNM parsing semantics. Do not add image libraries.

For each source crop:

1. verify source hash;
2. scan raw pixels;
3. compute minimal non-white rectangle;
4. allocate output P5/P6 bytes;
5. fill exact-white border;
6. copy source rectangle bytes exactly;
7. hash output;
8. record provenance.

No interpolation or color conversion.

- [ ] **Step 4: Implement Gate A authority checks**

Before transformation, require historical `Invoke-P43R3aGateA $PreparedFixture` PASS.

Gate A independently rechecks source/output hashes, geometry, 10 px border, copied content bytes, cell identity/order, and one transform build.

- [ ] **Step 5: Run `Transform` GREEN**

Expected: all synthetic transform/provenance controls PASS, quality OCR = 0.

- [ ] **Step 6: Commit**

```bash
git add tools/data/evaluation/p4-3-redesign3c-ocr
git commit -m "test: prove P4-3 redesign3c content-tight transform"
```

---

### Task 2: Gate B1 Clear Gray + Early Stop

**Precondition:** Task 1 PASS and exact historical fast-model/runtime supply available.

**Files:**
- Modify: `tools/data/evaluation/p4-3-redesign3c-ocr/run-evaluation.ps1`
- Modify: `tools/data/evaluation/p4-3-redesign3c-ocr/test-evaluation.ps1`
- Modify: `tools/data/evaluation/p4-3-redesign3c-ocr/README.md`

**Interfaces:**
- `Invoke-P43R3cGateB1 -PreparedFixture <object> -TransformedSet <object> -Executable <string> -ModelPath <string>`
  -> `GATE_B1_CLEAR_GRAY_FIDELITY_PASS|FAILED|NOT_EVALUATED`, four runs, determinism, counts.
- `Invoke-P43R3cFirstCycle -Executable <string> -ModelPath <string> -ArtifactDirectory <string>`
  -> A/B1 plus explicit later-gate block states and final reached verdict.

- [ ] **Step 1: Write failing `GrayFidelity` tests**

Assert:

- transformed crops, not original crops, are passed to historical `Invoke-P43R3aTesseractBatch`;
- exact fast model/runtime contract is inherited from 3A wrapper;
- one Gray prepare + one transform build;
- PSM6 x2 then PSM11 x2;
- maximum four quality calls;
- each PSM requires mandatory 8/8;
- mandatory mismatch or NOT_EVALUATED rejects;
- words/text/fidelity/diagnostics nondeterminism rejects;
- elapsed-only difference does not reject;
- B1 failure blocks B2/C/D with zero downstream preparation/OCR.

- [ ] **Step 2: Run `GrayFidelity` RED**

Expected: FAIL before B1 exists.

- [ ] **Step 3: Implement B1 by composing historical helpers**

Reuse directly:

- `Prepare-P43R3aFixture`;
- `Invoke-P43R3aTesseractBatch`;
- `ConvertTo-P43R3aCellTexts`;
- `Evaluate-P43R3aFidelity`.

Do not create a new OCR wrapper.

- [ ] **Step 4: Run synthetic `GrayFidelity` GREEN**

Actual quality OCR = 0.

- [ ] **Step 5: Run actual first measurement once**

Acquire only the exact historical fast-model/runtime supply.

Run:

- Gate A transform proof;
- PSM6 x2;
- PSM11 x2.

Absolute B1 quality ceiling = 4.

If B1 fails:

`P4_3_REDESIGN3C_REJECTED / GATE_B1_CLEAR_GRAY_FIDELITY_FAILED`.

Do not execute Tasks 3-4 quality work.

- [ ] **Step 6: Record measurement before cleanup**

Persist externally first, then copy factual summary into README. Record transformed dimensions/hashes and OCR fidelity/counts.

- [ ] **Step 7: Fresh Task 2 review and commit**

Critical/Important must be resolved before continuation.

```bash
git add tools/data/evaluation/p4-3-redesign3c-ocr
git commit -m "test: evaluate P4-3 redesign3c Gray fidelity"
```

---

### Task 3: Gate B2 RGB + Gate C Consensus

**Precondition:** Actual Gate B1 PASS. If not, mark `NOT_RUN_GATE_B1_FAILED` and do not implement/run this task's quality path.

**Files:**
- Modify: `tools/data/evaluation/p4-3-redesign3c-ocr/run-evaluation.ps1`
- Modify: `tools/data/evaluation/p4-3-redesign3c-ocr/test-evaluation.ps1`
- Modify: `tools/data/evaluation/p4-3-redesign3c-ocr/README.md`

**Interfaces:**
- `Invoke-P43R3cGateB2 -PreparedFixture <object> -TransformedSet <object> -Executable <string> -ModelPath <string>` -> `GATE_B2_CLEAR_RGB_FIDELITY_PASS|FAILED|NOT_EVALUATED`, max four OCR.
- `Invoke-P43R3cGateC -GrayGate <object> -RgbGate <object>` -> `GATE_C_CLEAR_CONSENSUS_PASS|FAILED|NOT_EVALUATED`, additional OCR 0.

- [ ] **Step 1: Write RED tests only if B1 PASS**

Pin one RGB prepare/transform, PSM6x2/PSM11x2, exact 8/8 acceptance, deterministic repeats, and zero-OCR Gate C.

- [ ] **Step 2: Implement B2/C by reusing B1/historical semantics**

No new reconstruction/normalization logic.

- [ ] **Step 3: Run actual B2/C only after B1 PASS**

B2 max +4 OCR; C +0.

Failure blocks Task 4.

- [ ] **Step 4: Review and commit**

`git commit -m "test: evaluate P4-3 redesign3c RGB fidelity and consensus"`

---

### Task 4: Gate D Degraded Safety

**Precondition:** Actual A/B1/B2/C PASS. Otherwise `NOT_RUN_<EARLIER_GATE>_FAILED`.

**Files:**
- Modify: `tools/data/evaluation/p4-3-redesign3c-ocr/run-evaluation.ps1`
- Modify: `tools/data/evaluation/p4-3-redesign3c-ocr/test-evaluation.ps1`
- Modify: `tools/data/evaluation/p4-3-redesign3c-ocr/README.md`

**Interfaces:**
- `Invoke-P43R3cGateD -Executable <string> -ModelPath <string> -ArtifactRoot <string>` -> `GATE_D_DEGRADED_SAFETY_PASS|GATE_D_FALSE_CONSENSUS_FAILED|GATE_D_DEGRADED_SAFETY_NOT_EVALUATED`, max six OCR calls.

- [ ] **Step 1: Write RED safety tests if prior gates PASS**

Pin:

- same correct -> `CORRECT_CONSENSUS`;
- disagreement -> safe fail-closed;
- same wrong -> `FALSE_CONSENSUS` hard reject;
- unavailable/empty -> NOT_EVALUATED;
- exact same transform policy on all degraded fixtures;
- no tuning/retry.

- [ ] **Step 2: Implement and run only the reached degraded path**

Three fixtures, PSM6/11 once each, max 6 OCR.

- [ ] **Step 3: Review and commit**

`git commit -m "test: evaluate P4-3 redesign3c degraded safety"`

---

### Task 5: Reached Verification + Closeout

**Precondition:** A factual first-cycle result exists.

**Files:**
- Modify: `README.md`
- Modify evaluation code only for proven reporting-contract defects; semantic fixes require their own RED/GREEN cycle.

**Interfaces:**
- `test-evaluation.ps1 -Group AllReached ...` replays only reached gates and never invokes blocked ones.

- [ ] **Step 1: Add reached-reporting RED/GREEN contracts**

Preserve:

- first failing gate;
- blocked gate states;
- first measurement counts;
- final verification counts separately;
- accepted final vocabulary:
  - `P4_3_REDESIGN3C_EARLY_GATES_PASS`
  - `P4_3_REDESIGN3C_REJECTED`
  - `P4_3_REDESIGN3C_NOT_EVALUATED`.

- [ ] **Step 2: Run one authorized reached verification**

Replay only the reached path from fresh external scratch.

One replay ceiling equals the first-cycle reached ceiling:

- B1 rejection: 4 OCR;
- B2/C rejection: 8 OCR;
- D reached: 14 OCR.

- [ ] **Step 3: Run regression suite**

Required:

- historical helper locked restore/build;
- relevant A/A2/Redesign2/Redesign3A/Redesign3B contract checks;
- all Redesign 3C synthetic/reached groups;
- full sorted `tools/data/test-*.ps1` suite;
- `git diff --check origin/dev...HEAD`;
- historical tracked/untracked diff = 0;
- protected tracked/untracked diff = 0.

Android local remains `NOT_RUN_EVALUATION_ONLY`.

- [ ] **Step 4: Record factual README closeout**

Include:

- source/runtime/model identities;
- transformed crop policy and per-cell output dimensions/hashes;
- reached Gate states;
- fidelity tables;
- deterministic comparison;
- exact preparation/transform/OCR counts;
- first vs verification counts;
- tests run/not run;
- remaining risks;
- final verdict.

No population/live/product claim.

- [ ] **Step 5: Clean dedicated supply and scratch**

Only after durable result recording and review.

Do not touch shared SDK/unrelated tools.

- [ ] **Step 6: Whole-branch review**

Residual Critical/Important = 0.

- [ ] **Step 7: Commit and HUMAN REVIEW STOP**

```bash
git add tools/data/evaluation/p4-3-redesign3c-ocr
git commit -m "docs: record P4-3 redesign3c content-tight result"
```

Do not push, create PR, merge, start another preprocessing strategy, or approve a dependency before human review.

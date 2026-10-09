# Phase 4 P4-3 Redesign 3B Best-Model Evaluation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Evaluate whether replacing only the Korean OCR model with one pinned official `tessdata_best/kor.traineddata` candidate recovers mandatory text fidelity and remains fail-closed under the existing Redesign 3A crop, reconstruction, and trust boundaries.

**Architecture:** Add a new evaluation-only harness under `tools/data/evaluation/p4-3-redesign3b-ocr/`. Reuse merged Redesign 3A preparation/crop/reconstruction/fidelity behavior read-only, add a model-supply authority that proves the pinned best-model bytes before OCR, and run cost-ordered Gray -> RGB -> consensus -> degraded gates with immediate early stop after the first disqualifying result.

**Tech Stack:** PowerShell 7; retained .NET 8/PdfPig 0.1.16 helper through Redesign 3A; exact Windows Tesseract `v5.5.3.20260724` / engine 5.5.3; one pinned official `tesseract-ocr/tessdata_best` Korean model candidate; built-in .NET SHA-1/SHA-256 hashing only.

**Spec:** `docs/superpowers/specs/2026-10-10-phase4-p4-3-redesign3b-best-model-evaluation.md` at approved spec HEAD `8b628f24156915081f44b3c9f687b0f4fffeff81`.

## Global Constraints

- Implementation authority starts from current `dev` merge baseline `928783e7050a8a9c312c2d768ea359af341d0dc7` plus the approved spec/plan commits. Refresh `origin/dev` before execution; if newer GitHub truth conflicts with this plan, stop for review.
- Historical evaluation paths are read-only:
  - `tools/data/evaluation/p4-3a-ocr/**`
  - `tools/data/evaluation/p4-3a2-ocr/**`
  - `tools/data/evaluation/p4-3-redesign2-ocr/**`
  - `tools/data/evaluation/p4-3-redesign3a-ocr/**`
- Protected product paths remain unchanged:
  - `tools/data/pdf-native/**`
  - `tools/data/lib/**`
  - `data/canonical/**`
  - `data/seed/**`
  - `apps/**`
- Exact Tesseract runtime identities remain unchanged from Redesign 3A:
  - build `v5.5.3.20260724` / engine 5.5.3;
  - installer SHA-256 `bee9e3434bd94fd65387d9be28cd467a41f61b1275383b55b0f59a1331270ae4`;
  - `tesseract.exe` SHA-256 `c66f0f12ed76f6aa455dac97684bbc86756d6a732380bee09122454cfda3f420`;
  - `libtesseract-5.dll` SHA-256 `54d54528b453ce3a5ba79487687f8df43e7b194b9ea97beba74200453fe1fb46`;
  - `libleptonica-6.dll` SHA-256 `1869b44e3d46fd830620b042477e5d60a950779582f38f60291547efb27792f1`.
- Exact OCR configuration: language `kor`, OEM 1, DPI 300, PSM6 primary, PSM11 verifier.
- Candidate model source identity:
  - repository `tesseract-ocr/tessdata_best`;
  - annotated tag `4.1.0`;
  - tag object `f0c187c74d3038e6d135fd080e30909af350eae0`;
  - target commit `e2aad9b983032bb1beff9133104a67cdbb87ca4d`;
  - tree `23d6207aa77e8f11abd8b300e12d2d94df300fb6`;
  - `kor.traineddata` Git blob `c82615b5228c9981c33a0985b32224d97b7fb43a`;
  - byte size `12528128`;
  - Apache-2.0.
- Candidate SHA-256 is not invented in the plan. The exact downloaded bytes must first prove the pinned Git blob identity, then have SHA-256 calculated and frozen before any quality OCR.
- Model-only experiment: no preprocessing, no alternate model/version, no Tesseract/PSM/OEM/DPI search, no crop/geometry/normalization/reconstruction changes.
- `PROVEN_CELL_CROP_V1`, overlap ratio `0.25`, `TEXT_FIDELITY_NORMALIZATION_V1`, and `DIAGNOSTIC_ONLY_V1` remain unchanged.
- `ProductionAction=NONE`, Product dependency `NOT_APPROVED`, P4-3B `BLOCKED`.
- No push, PR, merge, product dependency approval, preprocessing, other engine/model search, or later operational gates in this execution cycle.

## File Structure

**Create**
- `tools/data/evaluation/p4-3-redesign3b-ocr/model-supply.ps1` — candidate source/byte identity authority; pins blob identity and freezes calculated SHA-256.
- `tools/data/evaluation/p4-3-redesign3b-ocr/invoke-tesseract-best-batch.ps1` — Redesign 3A-equivalent batch contract with best-model authority instead of the historical fast-model hash.
- `tools/data/evaluation/p4-3-redesign3b-ocr/run-evaluation.ps1` — cost-ordered Gates A/B1/B2/C/D and reached-path verdict.
- `tools/data/evaluation/p4-3-redesign3b-ocr/test-evaluation.ps1` — TDD groups `ModelSupply`, `BestBatch`, `GrayFidelity`, `RgbConsensus`, `DegradedSafety`, `AllReached`.
- `tools/data/evaluation/p4-3-redesign3b-ocr/README.md` — commands, candidate identity, measured evidence, invocation counts, final verdict.

**Read-only reuse**
- `tools/data/evaluation/p4-3-redesign3a-ocr/crop-cells.ps1`
- `tools/data/evaluation/p4-3-redesign3a-ocr/run-evaluation.ps1`
- `tools/data/evaluation/p4-3-redesign3a-ocr/invoke-tesseract-batch.ps1` for model-independent parser/process behavior only; do not call its fast-model public batch function for best-model quality.
- historical fixtures/manifest authorities under P4-3A/P4-3A2.

**Temporary; never commit**
- Tesseract runtime supply;
- pinned `tessdata_best/kor.traineddata`;
- candidate-download metadata scratch;
- prepared crops;
- image lists;
- TSV/log scratch.

## Test Method

- TDD for every task: RED -> minimal GREEN -> targeted regression -> review -> commit.
- No actual quality OCR before Gate A has frozen candidate byte identity and SHA-256.
- Synthetic seams exercise supply/mapping/failure semantics without quality calls.
- Real quality runs use only existing committed fixtures.
- Fast-model baseline is not rerun.
- Full sorted `tools/data/test-*.ps1` suite runs after the reached first-cycle result is recorded.
- Android local remains `NOT_RUN_EVALUATION_ONLY` unless a protected/product path changes; such a change is a scope violation.

## Review Focus

1. **Self-referential model trust** — a file cannot prove itself merely by having a newly calculated SHA-256; Task 1 must independently verify the pinned Git blob object identity before freezing SHA-256.
2. **Historical helper mutation** — Redesign 3A must remain byte-for-byte historical evidence; Task 2/6 tests pin historical/protected diff=0.
3. **Gray early-stop leakage** — a failed Gray gate must not prepare RGB or launch RGB/degraded OCR; Task 3 asserts downstream invocation count remains zero.
4. **Ground-truth leakage** — authored expected text must never select a model/PSM or influence reconstruction; Task 4/5 tests prove consensus/fidelity remain evaluation-only.
5. **Recovered degraded output** — non-empty output from an old empty degraded fixture must be evaluated, not rejected for differing from historical execution shape; Task 5 pins both empty and recovered branches.

---

### Task 1: Candidate Model Supply Authority

**Files:**
- Create: `tools/data/evaluation/p4-3-redesign3b-ocr/model-supply.ps1`
- Create: `tools/data/evaluation/p4-3-redesign3b-ocr/test-evaluation.ps1`
- Create: `tools/data/evaluation/p4-3-redesign3b-ocr/README.md`

**Interfaces:**
- `Get-P43R3bGitBlobSha1 -Path <string>` -> lowercase Git blob object SHA-1 calculated as SHA1("blob <length>\0" + exact bytes).
- `Get-P43R3bModelDescriptor -ModelPath <string>` -> `Status, Code, Filename, SizeBytes, GitBlobSha1, Sha256, SourceRepository, SourceTag, SourceTagObject, SourceCommit, License, FrozenAtUtc`.
- `Invoke-P43R3bGateA -Executable <string> -ModelPath <string>` -> `GATE_A_MODEL_SUPPLY_PASS|GATE_A_MODEL_SUPPLY_NOT_EVALUATED`, plus frozen descriptor and runtime identity.

- [ ] **Step 1: Write failing `ModelSupply` tests**

Assert:

- exact Git blob SHA computation with a small known byte fixture;
- missing file -> NOT_EVALUATED;
- filename other than `kor.traineddata` -> NOT_EVALUATED;
- size other than `12528128` -> NOT_EVALUATED;
- Git blob SHA other than `c82615b5228c9981c33a0985b32224d97b7fb43a` -> NOT_EVALUATED;
- SHA-256 is lowercase 64-hex and is calculated only after blob identity succeeds;
- descriptor contains the exact pinned repository/tag/tag-object/commit/license values;
- runtime EXE/DLL hashes and version remain exact Redesign 3A identities;
- candidate bytes modified after descriptor creation are detected before OCR;
- no OCR process seam is called by Gate A.

- [ ] **Step 2: Run `ModelSupply` and verify RED**

Run:

`pwsh -NoProfile -File .\tools\data\evaluation\p4-3-redesign3b-ocr\test-evaluation.ps1 -Group ModelSupply`

Expected: FAIL because supply functions do not exist.

- [ ] **Step 3: Implement model supply authority**

Use built-in .NET hashing only.

The authority must verify, in order:

1. file exists;
2. filename exactly `kor.traineddata`;
3. byte size exactly `12528128`;
4. calculated Git blob SHA-1 exactly `c82615b5228c9981c33a0985b32224d97b7fb43a`;
5. calculate and freeze SHA-256;
6. verify fixed Tesseract runtime hashes/version.

Do not accept caller-provided SHA-256 as authority.

- [ ] **Step 4: Re-run `ModelSupply`**

Expected: synthetic controls PASS with zero quality OCR.

- [ ] **Step 5: Commit**

```bash
git add tools/data/evaluation/p4-3-redesign3b-ocr
git commit -m "test: prove P4-3 redesign3b model supply"
```

---

### Task 2: Best-Model Batch Boundary

**Precondition:** Gate A authority exists.

**Files:**
- Create: `tools/data/evaluation/p4-3-redesign3b-ocr/invoke-tesseract-best-batch.ps1`
- Modify: `tools/data/evaluation/p4-3-redesign3b-ocr/test-evaluation.ps1`
- Modify: `tools/data/evaluation/p4-3-redesign3b-ocr/README.md`

**Interfaces:**
- `Invoke-P43R3bTesseractBatch -Executable <string> -ModelDescriptor <object> -Crops <object[]> -Psm <6|11>`
  -> same result shape as Redesign 3A batch: `Status, Code, Psm, InvocationCount, EngineVersion, EngineBuild, ModelSha256, Pages, Words, Diagnostics, ElapsedMilliseconds, ProductionAction`.
- Consumes model-independent `ConvertFrom-P43R3aBatchTsv`, `Invoke-InternalP43R3aProcess`, and crop PNM validation behavior read-only.

- [ ] **Step 1: Write failing `BestBatch` tests**

Using process seams, assert:

- only PSM6/11 accepted;
- frozen model descriptor required;
- model bytes are revalidated against descriptor SHA-256 and pinned Git blob before each quality invocation;
- no fast-model hash or fast-model fallback is accepted;
- crop ordinals/page mapping exactly 1..N;
- malformed/missing/duplicate/extra page fails closed;
- empty required crop page fails;
- timeout/nonzero exit/output-limit fails closed;
- invocation count is exactly one per batch;
- batch arguments remain `-l kor --oem 1 --psm <6|11> --dpi 300 -c tessedit_create_tsv=1`;
- expected text is absent from invocation inputs.

- [ ] **Step 2: Run `BestBatch` and verify RED**

Run:

`pwsh -NoProfile -File .\tools\data\evaluation\p4-3-redesign3b-ocr\test-evaluation.ps1 -Group BestBatch`

Expected: FAIL before best-model batch boundary exists.

- [ ] **Step 3: Implement the minimal best-model batch wrapper**

Reuse Redesign 3A model-independent parsing/process behavior rather than copy-changing unrelated logic.

The only intentional semantic difference from the 3A public batch boundary is candidate model authority.

No per-cell fallback and no retry.

- [ ] **Step 4: Re-run `BestBatch`**

Expected: PASS with synthetic process seam; actual quality OCR count 0.

- [ ] **Step 5: Commit**

```bash
git add tools/data/evaluation/p4-3-redesign3b-ocr
git commit -m "test: prove P4-3 redesign3b best-model batch boundary"
```

---

### Task 3: Gate B1 Gray Fidelity + Early Stop

**Precondition:** Tasks 1-2 PASS and exact candidate supply is acquired/frozen.

**Files:**
- Create: `tools/data/evaluation/p4-3-redesign3b-ocr/run-evaluation.ps1`
- Modify: `tools/data/evaluation/p4-3-redesign3b-ocr/test-evaluation.ps1`
- Modify: `tools/data/evaluation/p4-3-redesign3b-ocr/README.md`

**Interfaces:**
- `Invoke-P43R3bGateB1 -GrayPrepared <object> -Executable <string> -ModelDescriptor <object>`
  -> `GATE_B1_CLEAR_GRAY_FIDELITY_PASS|GATE_B1_CLEAR_GRAY_FIDELITY_FAILED|GATE_B1_CLEAR_GRAY_FIDELITY_NOT_EVALUATED`.
- Return includes four runs (PSM6 x2, PSM11 x2), determinism evidence, preparation counters, and `QualityInvocationCount`.
- `Invoke-P43R3bFirstCycle` orchestrator starts with A then B1 and must leave later gates blocked if B1 does not PASS.

- [ ] **Step 1: Write failing `GrayFidelity` tests**

Assert controlled cases:

- exact 8/8 both PSMs, deterministic -> PASS;
- PSM6 7/8 -> FAILED;
- PSM11 7/8 -> FAILED;
- mandatory PARTIAL/NOT_EVALUATED -> FAILED;
- nondeterministic repeat -> FAILED;
- unavailable model before any observed quality -> NOT_EVALUATED;
- after any observed disqualifying Gray evidence, later supply loss preserves REJECTED;
- Gray failure yields RGB invocation count 0, consensus count 0, degraded count 0;
- Gray preparation count = one;
- exactly four actual quality batches on completed Gray matrix.

- [ ] **Step 2: Run `GrayFidelity` and verify RED**

Expected: FAIL before Gate B1 exists.

- [ ] **Step 3: Implement Gate B1 and orchestrator early-stop boundary**

Reuse Redesign 3A:

- `Prepare-P43R3aFixture`;
- `ConvertTo-P43R3aCellTexts`;
- `Evaluate-P43R3aFidelity`;
- historical ground-truth authority.

Do not modify 3A.

- [ ] **Step 4: Run actual Gate A + Gate B1 only**

Acquire the exact pinned candidate outside the repo.

Before OCR, record:

- pinned source identity;
- exact byte size;
- exact Git blob SHA;
- calculated SHA-256.

Prepare clear Gray once.

Run exactly:

- PSM6 x2;
- PSM11 x2.

If any mandatory path fails:

`P4_3_REDESIGN3B_REJECTED / GATE_B1_CLEAR_GRAY_FIDELITY_FAILED`.

Stop quality evaluation. Do not prepare/run RGB or degraded OCR.

- [ ] **Step 5: Re-run `GrayFidelity` assertions against observed verdict**

Expected: test group PASS as verification even if candidate itself is REJECTED.

- [ ] **Step 6: Commit**

```bash
git add tools/data/evaluation/p4-3-redesign3b-ocr
git commit -m "test: evaluate P4-3 redesign3b Gray fidelity"
```

---

### Task 4: Gate B2 RGB Fidelity + Gate C Clear Consensus

**Precondition:** Gate B1 actual result PASS.

**Files:**
- Modify: `tools/data/evaluation/p4-3-redesign3b-ocr/run-evaluation.ps1`
- Modify: `tools/data/evaluation/p4-3-redesign3b-ocr/test-evaluation.ps1`
- Modify: `tools/data/evaluation/p4-3-redesign3b-ocr/README.md`

**Interfaces:**
- `Invoke-P43R3bGateB2 -RgbPrepared <object> -Executable <string> -ModelDescriptor <object>`
  -> RGB fidelity status/evidence.
- `Compare-P43R3bCellConsensus -Psm6Cells <object[]> -Psm11Cells <object[]>`
  -> `CELL_CONSENSUS|CELL_DISAGREEMENT|CELL_NOT_EVALUATED`.
- `Invoke-P43R3bGateC -GrayGate <object> -RgbGate <object>`
  -> `GATE_C_CLEAR_CONSENSUS_PASS|GATE_C_CLEAR_CONSENSUS_FAILED|GATE_C_CLEAR_CONSENSUS_NOT_EVALUATED`.

- [ ] **Step 1: Write failing `RgbConsensus` tests**

Assert:

- RGB uses exactly four batches and one preparation;
- any RGB mandatory mismatch/PARTIAL/nondeterminism -> B2 FAILED;
- Gate C launches zero OCR;
- exact normalized PSM6 == PSM11 == truth -> consensus PASS;
- PSM disagreement -> Gate C FAILED;
- equal same wrong text is not accepted merely because PSMs agree;
- confidence cannot select a winner;
- expected text is used only by evaluation classifier, never reconstruction/model selection;
- B2 failure blocks C/D.

- [ ] **Step 2: Run `RgbConsensus` and verify RED**

Expected: FAIL before B2/C functions exist.

- [ ] **Step 3: Implement B2 and zero-OCR clear consensus**

Reuse Gray gate mechanics without creating a parameter search.

- [ ] **Step 4: Run actual B2 only if actual B1 PASS**

Prepare RGB once; run PSM6 x2 and PSM11 x2.

If B2 fails, record:

`P4_3_REDESIGN3B_REJECTED / GATE_B2_CLEAR_RGB_FIDELITY_FAILED`.

Do not run degraded quality.

If B2 passes, evaluate Gate C from existing B1/B2 evidence with zero additional OCR.

- [ ] **Step 5: Re-run `RgbConsensus`**

Expected: assertions PASS and measured gate state preserved.

- [ ] **Step 6: Commit**

```bash
git add tools/data/evaluation/p4-3-redesign3b-ocr
git commit -m "test: evaluate P4-3 redesign3b RGB fidelity and consensus"
```

---

### Task 5: Gate D Degraded False-Consensus Safety

**Precondition:** Actual Gates A/B1/B2/C all PASS.

**Files:**
- Modify: `tools/data/evaluation/p4-3-redesign3b-ocr/run-evaluation.ps1`
- Modify: `tools/data/evaluation/p4-3-redesign3b-ocr/test-evaluation.ps1`
- Modify: `tools/data/evaluation/p4-3-redesign3b-ocr/README.md`

**Interfaces:**
- `Evaluate-P43R3bConsensusSafety -Fixture <string> -FixtureHash <string> -Psm6Cells <object[]> -Psm11Cells <object[]>`
  -> per-cell safety state including `CORRECT_CONSENSUS|CELL_DISAGREEMENT|FALSE_CONSENSUS|CELL_NOT_EVALUATED`.
- `Invoke-P43R3bGateD -Executable <string> -ModelDescriptor <object>`
  -> `GATE_D_DEGRADED_SAFETY_PASS|GATE_D_FALSE_CONSENSUS_FAILED|GATE_D_DEGRADED_SAFETY_NOT_EVALUATED`.

- [ ] **Step 1: Write failing `DegradedSafety` tests**

Assert:

- both PSMs same authored truth -> correct consensus;
- disagreement -> fail closed, never select a winner;
- same wrong mandatory text -> `FALSE_CONSENSUS` and hard rejection;
- missing/untrusted -> NOT_EVALUATED, no semantic absence;
- historical empty output is not required;
- recovered words are evaluated against historical authored truth;
- no new fixture is created;
- exactly six quality OCR processes for completed three-fixture degraded matrix;
- one FALSE_CONSENSUS preserves first-failure reason and cannot be rescued by later cells.

- [ ] **Step 2: Run `DegradedSafety` and verify RED**

Expected: FAIL before Gate D exists.

- [ ] **Step 3: Implement Gate D**

For each committed fixture:

- prepare once;
- PSM6 once;
- PSM11 once;
- classify safety.

No retry/tuning.

- [ ] **Step 4: Run actual Gate D only if A/B1/B2/C actual PASS**

Maximum additional OCR = 6.

Any mandatory FALSE_CONSENSUS:

`P4_3_REDESIGN3B_REJECTED / GATE_D_FALSE_CONSENSUS_FAILED`.

- [ ] **Step 5: Re-run `DegradedSafety`**

Expected: assertions PASS and measured evidence preserved.

- [ ] **Step 6: Commit**

```bash
git add tools/data/evaluation/p4-3-redesign3b-ocr
git commit -m "test: evaluate P4-3 redesign3b degraded consensus safety"
```

---

### Task 6: Reached-Path Verification, Result Recording, and Human Review Stop

**Precondition:** A factual first-cycle outcome has been reached at A, B1, B2, C, or D.

**Files:**
- Modify: `tools/data/evaluation/p4-3-redesign3b-ocr/README.md`
- Modify Redesign 3B evaluation code only for verified reporting-contract bugs; any semantic change needs its own RED/GREEN cycle.

**Interfaces:**
- `test-evaluation.ps1 -Group AllReached -TesseractExecutable <path> -BestModelPath <path>`
  -> replays only the gates that are authorized/reached by the actual candidate result; never fabricates PASS for blocked gates.

- [ ] **Step 1: Verify exact reached-path semantics**

Assert final vocabulary:

- `P4_3_REDESIGN3B_EARLY_GATES_PASS`;
- `P4_3_REDESIGN3B_REJECTED`;
- `P4_3_REDESIGN3B_NOT_EVALUATED`.

Preserve the first failing reached gate reason.

Blocked later gates must be explicit `NOT_RUN_<EARLIER_GATE>_FAILED` or equivalent approved state and must launch zero OCR.

- [ ] **Step 2: Re-run actual reached path from clean scratch**

Do not exceed the spec cost ceiling for one complete replay:

- B1-only rejection: max 4 quality OCR;
- B2/C rejection: max 8 quality OCR;
- D reached: max 14 quality OCR.

No fast baseline rerun.

Record first measurement and final verification counts separately.

- [ ] **Step 3: Run repository regression verification**

Run:

- locked historical helper restore/build;
- relevant historical P4-3A Contract;
- P4-3A2 Contract;
- Redesign 2 Contract;
- Redesign 3A relevant contract/reached-reporting checks;
- all Redesign 3B reached/synthetic groups;
- full sorted `tools/data/test-*.ps1` suite with failure propagation;
- `git diff --check origin/dev...HEAD`;
- historical P4-3A/A2/Redesign2/Redesign3A diff = 0;
- protected-path diff/untracked = 0.

Android local: `NOT_RUN_EVALUATION_ONLY`.

- [ ] **Step 4: Verify efficiency counters**

Report actual:

- candidate model size/SHA-256;
- Gray/RGB/degraded preparation counts;
- PSM6/PSM11 invocation counts;
- first measurement total;
- final reached verification total;
- overall cycle total;
- per-cell fallback = 0;
- per-business OCR = 0;
- fast baseline rerun = 0;
- Gate C extra OCR = 0.

- [ ] **Step 5: Record the factual result in README**

Include:

- branch/measurement HEAD;
- exact runtime identities;
- pinned best-model source metadata and calculated SHA-256;
- Gate A/B1/B2/C/D status;
- per-fixture/per-PSM fidelity counts;
- determinism;
- consensus/false-consensus observations for reached gates only;
- elapsed time and model-size diagnostics;
- tests run/not run;
- historical/protected diff;
- final verdict;
- remaining risks.

Do not claim:

- population accuracy;
- live-source compatibility;
- product suitability;
- cross-OS determinism;
- dependency approval;
- P4-3B readiness;
- Phase 4 completion.

- [ ] **Step 6: Remove dedicated evaluation supply and scratch**

Remove only the dedicated candidate/runtime directory and invocation-owned temporary artifacts.

Do not remove shared SDKs or unrelated tools.

- [ ] **Step 7: Commit result recording**

```bash
git add tools/data/evaluation/p4-3-redesign3b-ocr
git commit -m "docs: record P4-3 redesign3b best-model result"
```

- [ ] **Step 8: Whole-branch review**

Review `origin/dev...HEAD` against the approved spec/plan.

Critical/Important issue -> fix or stop; do not push.

- [ ] **Step 9: HUMAN REVIEW STOP**

Final report:

- branch/worktree/final HEAD;
- task commit SHAs;
- changed files;
- calculated candidate SHA-256 and pinned source identity;
- Gate results/first failure;
- fidelity tables;
- consensus/degraded evidence only where reached;
- OCR/process/preparation counters;
- full data-suite result;
- historical/protected diffs;
- Android NOT_RUN reason;
- remaining risks;
- final status:
  - Product dependency `NOT_APPROVED`;
  - P4-3B `BLOCKED`;
  - P4-3 `NOT COMPLETE`;
  - Phase 4 `NOT COMPLETE`;
  - `ProductionAction=NONE`.

Do not push.
Do not open PR.
Do not merge.
Do not begin preprocessing.
Do not test another model/engine.

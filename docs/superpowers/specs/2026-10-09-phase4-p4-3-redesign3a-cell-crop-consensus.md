# Phase 4 P4-3 — OCR Redesign 3A: Proven Cell-Crop OCR + Dual-PSM Consensus

Date: 2026-10-09  
Status: DESIGN APPROVED IN CHAT / WRITTEN SPEC REVIEW REQUIRED  
Base: `dev` at `4b57a4fbf45b730033f63d7de90d7030791b8c79`

## 1. Purpose

Redesign 3A evaluates whether the rejected Redesign 2 OCR candidate can recover required text fidelity by changing only the **OCR input segmentation strategy**, while preserving the proven structural-safety boundary.

Redesign 2 established:

- Gate A1 structural trust = `GATE_A1_STRUCTURAL_PASS`;
- Gate A2 text fidelity = `GATE_A2_TEXT_FIDELITY_REJECTED`;
- Clear Gray/RGB PSM11 remained structurally `COMPLETE`, but mandatory text fidelity was only 6/8;
- representative mandatory mismatches included `주소` -> `즈 ㅅ\n구수` and `전화번호` -> `전 화 번 호`;
- raw confidence did not explain the failure and remains diagnostic-only.

Therefore Redesign 3A does **not** relax provenance, overlap, coverage, or fail-closed rules. It isolates one hypothesis:

> Full-page OCR segmentation may be causing avoidable recognition/reconstruction errors. If OCR is constrained to already-proven cell interiors, can the fixed Tesseract/model candidate recover exact required text while remaining fail-closed?

This is an evaluation-only redesign. It does not approve a product OCR dependency or P4-3B.

## 2. Approved strategy

Redesign 3A fixes the OCR engine/model/runtime and changes only the bounded input strategy.

The candidate is:

```text
PDF bytes
 -> existing image-only eligibility
 -> PDF open once
 -> image decode once
 -> existing ruled-grid proof
 -> exact proven inner-cell crops
 -> one batch OCR with PSM 6
 -> one batch OCR with PSM 11
 -> per-cell deterministic reconstruction
 -> exact normalized dual-PSM consensus
 -> evaluation-only ground-truth fidelity
 -> HUMAN REVIEW STOP
```

The two PSM paths are not a candidate search:

- PSM 6 = primary bounded single-block view;
- PSM 11 = verifier sparse-text view.

No other PSM/OEM/DPI combination is explored in Redesign 3A.

## 3. Fixed runtime and model

Redesign 3A keeps the exact previously evaluated candidate:

- Windows Tesseract build: `v5.5.3.20260724` / engine 5.5.3;
- installer SHA-256:
  `bee9e3434bd94fd65387d9be28cd467a41f61b1275383b55b0f59a1331270ae4`;
- `tesseract.exe` SHA-256:
  `c66f0f12ed76f6aa455dac97684bbc86756d6a732380bee09122454cfda3f420`;
- `libtesseract-5.dll` SHA-256:
  `54d54528b453ce3a5ba79487687f8df43e7b194b9ea97beba74200453fe1fb46`;
- `libleptonica-6.dll` SHA-256:
  `1869b44e3d46fd830620b042477e5d60a950779582f38f60291547efb27792f1`;
- official `tessdata_fast/kor.traineddata`;
- model source commit:
  `87416418657359cb625c412a48b6e1d6d41c29bd`;
- model SHA-256:
  `6b85e11d9bbf07863b97b3523b1b112844c43e7b194b9ea97beba74200453fe1fb46` is **not** the model hash and must never be used as one;
- authoritative Korean model SHA-256:
  `6b85e11d9bbf07863b97b3523b1b112844c43e713df8b66418a081fd1060b3b2`;
- language `kor`;
- OEM 1;
- DPI 300.

The duplicated hash line above intentionally distinguishes the DLL hash from the Korean-model hash. Implementations must assert the authoritative model hash ending in `...60b3b2`.

No runtime/model substitution is allowed. A different engine/model requires a separate redesign.

## 4. Scope

Redesign 3A may:

- reuse the existing P4-3A PDF image eligibility and decoded PGM/PPM artifacts read-only;
- reuse the existing ruled-grid proof read-only;
- build deterministic crops from already-proven cell interiors;
- evaluate PSM 6 and PSM 11 only;
- batch multiple proven cell crops into one OCR invocation per PSM when exact input-to-output mapping is proven;
- reconstruct text independently per crop/cell;
- compare PSM 6 and PSM 11 by exact normalized equality;
- reuse the historical synthetic clear/degraded fixtures and pre-authored ground truth read-only;
- measure process counts, reuse, deterministic mapping, fidelity, and false-consensus risk.

## 5. Non-scope

Redesign 3A must not introduce or evaluate:

- another OCR engine;
- another Korean model;
- another Tesseract version/build;
- scaling or super-resolution;
- binarization;
- threshold search;
- sharpening;
- denoise;
- line removal;
- contrast tuning;
- deskew;
- new rasterizer;
- new product dependency;
- PSM search beyond fixed 6 and 11 roles;
- alternate OEM/DPI search;
- outward crop padding;
- OCR-driven crop movement;
- adaptive margins;
- nearest-cell, centroid, or majority assignment;
- new geometry tolerance;
- OCR text correction;
- character/jamo repair;
- whitespace-deletion heuristics that join characters;
- fuzzy/edit-distance/semantic matching;
- expected-text-driven OCR correction;
- canonical business/benefit data as OCR ground truth;
- dictionary/user-word tuning;
- borderless table inference;
- product OCR adapter;
- API/schema/DB/auth changes;
- canonical/seed/apps writes;
- P4-3B implementation.

A failure in Redesign 3A may motivate a later Redesign 3B, but does not authorize it.

## 6. Historical preservation

The following paths are historical evidence and remain read-only:

- `tools/data/evaluation/p4-3a-ocr/**`
- `tools/data/evaluation/p4-3a2-ocr/**`
- `tools/data/evaluation/p4-3-redesign2-ocr/**`

Their conclusions remain separate:

- P4-3A = `REJECTED`;
- P4-3A2 = `P4_3A2_REJECTED / GATE_A_CONFIDENCE_REJECTED`;
- Redesign 2 A1 = `GATE_A1_STRUCTURAL_PASS`;
- Redesign 2 A2 = `GATE_A2_TEXT_FIDELITY_REJECTED`;
- Redesign 2 final = `P4_3_REDESIGN2_REJECTED`.

Redesign 3A adds a new evaluation cycle and does not rewrite those results.

## 7. Safety invariants

The evaluation remains fail-closed and `ProductionAction=NONE`.

No OCR result may:

- create or change cell geometry;
- move text between proven cells;
- repair grid failures;
- infer a missing row/column;
- infer semantic `NOT_FOUND`;
- create a benefit claim;
- create `GREEN`, `ACTIVE`, lifecycle, or currentness state;
- modify canonical, seed, or app data.

Confidence remains `DIAGNOSTIC_ONLY_V1`.

Confidence may be preserved for audit but may not:

- select between PSM 6 and PSM 11;
- resolve disagreement;
- rescue wrong text;
- reject otherwise matching text by itself;
- create consensus.

## 8. Proven cell-crop authority

The crop source is only the already-proven grid-cell interior.

For the retained P4-3A grid helper, cells already expose bounded inner coordinates equivalent to:

- `CellId`
- `Row`
- `Column`
- `X0`
- `Y0`
- `X1`
- `Y1`

Redesign 3A uses those exact inner coordinates. It does not add padding or move boundaries.

Each crop must preserve at minimum:

- source fixture/PDF identity;
- source decoded pixel hash;
- cell ID;
- row/column;
- crop rectangle;
- source component count;
- crop width/height;
- crop bytes hash;
- crop-policy version.

A crop is valid only if:

- its source image identity matches the inspected image;
- it lies exactly within one proven cell interior;
- dimensions are positive and bounded;
- emitted bytes are deterministic;
- a repeated preparation from identical source pixels/cell coordinates yields the same crop hash.

Crop preparation must not use OCR output or expected text.

## 9. No preprocessing in the first cycle

The first Redesign 3A cycle uses the original decoded pixels inside each proven inner-cell rectangle.

There is no:

- resize;
- interpolation;
- thresholding;
- color conversion beyond what the retained PNM representation already contains;
- border erasure;
- line removal;
- denoise/sharpen;
- contrast modification.

This isolates the value of **segmentation change alone**.

If Redesign 3A fails, preprocessing may be considered only in a separately approved follow-up design.

## 10. Batch OCR mapping

A naive per-cell design would create 12 OCR processes per PSM per page. That is explicitly forbidden because it introduces a product-scale bottleneck and makes evaluation success depend on an operationally unacceptable execution pattern.

The target evaluation shape per prepared page is:

```text
PDF open                 1
Image decode             1
Grid build               1
Crop-set build           1
PSM 6 batch OCR          1
PSM 11 batch OCR         1
Total OCR invocations    2
```

For the retained 12-cell clear fixture, batch input order must map deterministically:

```text
crop 1  -> OCR logical page 1  -> CellId 1
...
crop 12 -> OCR logical page 12 -> CellId 12
```

This mapping is a gate, not an assumption.

The batch path must fail closed on:

- missing logical page;
- duplicated logical page;
- extra logical page;
- page number outside 1..N;
- output count inconsistent with the prepared crop set;
- malformed TSV;
- unsupported input list;
- runtime/model identity failure;
- empty required crop output.

Redesign 3A must not silently fall back to 12 independent Tesseract invocations when batch mapping fails. That failure blocks the candidate and triggers human review.

## 11. Per-cell reconstruction

Each OCR logical page is already bound to exactly one proven crop/cell before OCR.

Therefore Redesign 3A does not run a second full-page word-to-cell geometry inference.

Inside each crop, OCR words may be reconstructed only for that crop's CellId.

Reconstruction must remain deterministic and preserve:

- OCR text;
- raw bbox relative to crop;
- hierarchy/order;
- raw confidence;
- PSM;
- CropId/CellId;
- reconstructed cell text.

Competing/unsafe records inside the crop still fail closed. Redesign 3A does not use confidence to choose a winner.

## 12. Consensus policy

Runtime-like consensus uses only deterministic normalized equality between the two fixed segmentation views.

Policy:

`OCR_CELL_CONSENSUS_V1`

Normalization semantics reuse the already-approved `TEXT_FIDELITY_NORMALIZATION_V1` representation rules:

- CRLF -> LF;
- leading/trailing whitespace trim;
- repeated horizontal whitespace within a line -> one ASCII space;
- deterministic line-ending representation.

Forbidden normalization remains:

- Korean/jamo correction;
- character substitution;
- punctuation deletion;
- digit repair;
- removal of meaningful single spaces to force character joining;
- fuzzy/edit-distance/semantic equivalence.

Per cell:

- PSM6 normalized text == PSM11 normalized text -> `CELL_CONSENSUS`;
- otherwise -> `CELL_DISAGREEMENT`;
- missing/failed/untrusted result -> `CELL_NOT_EVALUATED`.

Confidence cannot change these states.

## 13. Ground-truth authority

Evaluation-only fidelity reuses the pre-existing synthetic fixture authority from Redesign 2.

Generator blob:

`6231ed473349063ce3b0d12fc7b2cff0bef1d114`

Manifest blob:

`cde2a581ec2c4a1fb26481992908b5dcab2740ac`

Clear Gray SHA-256:

`07182f75f5305bb4611458aeaea880aa57fa78d120030b0f9b6446bd56e5ec17`

Clear RGB SHA-256:

`415645682f805899bdc0852feefec37ae596a3821b97a7ab344fc7d267c61c24`

Mandatory roles remain:

- header cells: 4;
- business-name cells: 2;
- benefit cells: 2.

Mandatory count = 8.

All 12 cells remain an additional metric.

Expected text is evaluation-only. It must not enter crop generation, OCR invocation, consensus selection, runtime reconstruction, business binding, or product code.

## 14. Gate A — Crop Provenance

Central question:

> Can the existing proven grid be converted into deterministic OCR crops without weakening physical provenance?

Required positive evidence on retained clear Gray/RGB:

- source image eligibility remains unchanged;
- PDF open = 1 per prepared fixture;
- image decode = 1;
- grid build = 1;
- exactly 12 proven cells -> exactly 12 crops;
- every crop rectangle exactly equals the proven inner-cell rectangle;
- crop hashes repeat identically from the same source;
- no OCR/expected text participates in crop geometry.

Required negative controls should be synthetic metadata/unit controls rather than new quality fixtures:

- out-of-range rectangle -> fail;
- zero/negative dimension -> fail;
- duplicate CellId -> fail;
- missing required CellId -> fail;
- source pixel-hash mismatch -> fail;
- crop set count mismatch -> fail.

Failure -> `P4_3_REDESIGN3A_REJECTED / GATE_A_CROP_PROVENANCE_FAILED`.

Gate B must not run after Gate A failure.

## 15. Gate B — Batch Mapping

Central question:

> Can one exact Tesseract 5.5.3 batch invocation map N prepared crops to the same N CellIds without heuristic repair?

Evaluate both PSM 6 and PSM 11 batch paths.

Required positive evidence:

- exact runtime/model identity;
- one process invocation per PSM batch;
- logical OCR pages map exactly 1..N in input order;
- every OCR output record is attributable to exactly one prepared crop/CellId;
- mapping is identical across repetition.

Required negative controls:

- missing page;
- duplicate page;
- extra page;
- reordered/invalid mapping;
- malformed TSV;
- empty required crop result;
- wrong runtime/model identity.

No per-cell process fallback is allowed.

Failure -> `P4_3_REDESIGN3A_REJECTED / GATE_B_BATCH_MAPPING_FAILED`.

## 16. Gate C — Clear Cell Fidelity

Gate C runs only after A and B pass.

For clear Gray and clear RGB:

- prepare each fixture once;
- reuse the same deterministic crop set for repeated OCR runs;
- execute PSM 6 and PSM 11 two times each;
- do not re-open/re-decode/re-grid merely to repeat OCR.

For **each PSM path independently**, every repetition must achieve:

- mandatory fidelity = 8/8;
- no mandatory `FIDELITY_MISMATCH`;
- no mandatory `FIDELITY_NOT_EVALUATED`.

Whole-table fidelity 12/12 is measured and reported but is not silently promoted into a broader product contract.

The evaluator must report exact per-cell:

- expected text;
- reconstructed text;
- normalized expected/actual;
- PSM;
- raw confidence;
- fidelity state.

Any mandatory mismatch in either PSM path:

`P4_3_REDESIGN3A_REJECTED / GATE_C_CLEAR_FIDELITY_FAILED`.

No OCR settings, crop boundaries, fixture bytes, expected text, or normalization may be changed after seeing the result.

## 17. Gate D — Consensus Safety

Gate D determines whether dual-PSM agreement is a safe runtime-like trust signal for this bounded candidate.

### Clear controls

For all mandatory cells and repetitions:

```text
PSM6 normalized text
==
PSM11 normalized text
==
authored normalized ground truth
```

must hold.

A PSM6-correct / PSM11-wrong pair still fails because runtime cannot know which is correct.

### Mild degraded control

The existing mild degraded fixture remains a safety control.

For each mandatory cell:

- disagreement -> fail closed and is safe;
- both agree on authored truth -> safe;
- both agree on the same wrong text -> `FALSE_CONSENSUS` and hard rejection;
- any untrusted/missing result -> not evaluated/fail closed.

A single mandatory `FALSE_CONSENSUS` rejects Redesign 3A.

### Old degraded controls

Existing degraded Gray/RGB empty-word behavior remains an operational negative.

Empty output must remain:

- failed/not evaluated;
- no semantic absence;
- no business row;
- no claim;
- no consensus fabrication.

Gate D PASS requires no mandatory false consensus.

Failure -> `P4_3_REDESIGN3A_REJECTED / GATE_D_CONSENSUS_SAFETY_FAILED`.

## 18. First-cycle result and mandatory human stop

The first Redesign 3A implementation cycle ends after Gates A-D.

Exact allowed outcomes:

### `P4_3_REDESIGN3A_EARLY_GATES_PASS`

Means only:

- crop provenance is proven;
- batch mapping is proven;
- clear mandatory fidelity is 8/8 for both fixed PSM paths;
- no mandatory false consensus is observed in the approved degraded controls.

This is **not** dependency approval and **not** P4-3B permission.

After this outcome:

`HUMAN_REVIEW_STOP`

### `P4_3_REDESIGN3A_REJECTED`

Any Gate A-D mandatory failure.

After rejection:

- later gates remain blocked;
- dependency remains `NOT_APPROVED`;
- P4-3B remains `BLOCKED`;
- no automatic pivot to preprocessing or another model.

### `P4_3_REDESIGN3A_NOT_EVALUATED`

Use when exact runtime/model/fixture authority or another required prerequisite cannot be reproduced reliably.

Later gates remain blocked.

## 19. Later gates — only after new human approval

If and only if `P4_3_REDESIGN3A_EARLY_GATES_PASS` is human-reviewed and approved, a later implementation plan may evaluate:

- Gate E — technical business isolation;
- Gate F — operational safety, reuse, timeout/fault/resource bounds;
- Gate G — multipage scope;
- Gate H — Windows/Ubuntu semantic determinism;
- exact dependency-review evidence.

These later gates are not part of the first Redesign 3A implementation cycle.

## 20. Efficiency and bottleneck requirements

The evaluation must prove that the candidate does not depend on per-business or per-cell OCR process spawning.

For one prepared single-page document:

- PDF open target: 1;
- page/image decode target: 1;
- grid build target: 1;
- crop-set build target: 1;
- PSM6 OCR invocation target: 1;
- PSM11 OCR invocation target: 1;
- business lookup count must not affect OCR invocation count in later gates.

For Gray/RGB, two OCR repetitions each, expected quality-evaluation process count is:

```text
2 fixtures
x 2 repetitions
x 2 PSMs
= 8 OCR processes
```

rather than a naive:

```text
2 fixtures
x 2 repetitions
x 2 PSMs
x 12 cells
= 96 OCR processes
```

This process-count reduction is a design target to be measured, not claimed before Gate B proves the batch path.

## 21. Reuse and duplication rules

Reuse read-only:

- existing P4-3A inspect/image eligibility;
- existing P4-3A grid proof;
- historical fixtures;
- historical ground-truth identities;
- exact runtime/model identity rules;
- existing safety concepts for timeout/output/identity failure;
- `TEXT_FIDELITY_NORMALIZATION_V1` semantics.

Create only Redesign 3A-owned behavior for:

- crop-set preparation;
- batch input/output mapping;
- per-crop/cell OCR reconstruction;
- dual-PSM consensus;
- Redesign 3A gate orchestration.

Do not modify historical evaluation code to make it shared. Historical immutability is more important than eliminating a few lines of local evaluation code.

## 22. Expected repository boundary

First-cycle implementation should be isolated under a new evaluation directory such as:

`tools/data/evaluation/p4-3-redesign3a-ocr/**`

Expected retained files may include:

- batch-runtime wrapper;
- evaluation runner;
- tests;
- README;
- a Redesign 3A-local crop helper if required.

Any helper must use existing platform/runtime capabilities only. No new external package or product dependency is approved by this spec.

Protected paths remain untouched:

- `tools/data/pdf-native/**`;
- `tools/data/lib/**`;
- `data/canonical/**`;
- `data/seed/**`;
- `apps/**`.

## 23. Test strategy

Use TDD for every implementation task.

At minimum verify:

- crop provenance positive and negative controls;
- exact crop hashes across repeat preparation;
- batch mapping contract and fail-closed negatives;
- exact runtime/model identity;
- PSM6/PSM11 invocation count;
- repeated-output determinism;
- per-PSM clear mandatory fidelity;
- clear dual-PSM consensus;
- mild-degraded false-consensus detection;
- old-degraded empty-output safety;
- confidence has no decision authority;
- expected text does not leak into crop/runtime/consensus paths;
- historical P4-3A/P4-3A2/Redesign2 diff = 0;
- protected-path diff = 0;
- full current data suite;
- `git diff --check`.

Android local remains `NOT_RUN_EVALUATION_ONLY` unless a protected/product path changes unexpectedly, in which case scope must stop for review.

## 24. Failure interpretation

Redesign 3A must preserve useful diagnostic separation.

### Same wrong text from PSM6 and PSM11

```text
wrong + agreement
-> FALSE_CONSENSUS
-> Redesign 3A rejected
```

Interpretation: bounded cell crop plus same-engine dual segmentation does not provide a safe runtime trust signal. A later engine/model redesign may be considered separately.

### PSM6 correct, PSM11 wrong

```text
correct + disagreement
-> fail closed
-> Gate C/D failure
```

Interpretation: segmentation strategy remains unstable; verifier strategy would need separate redesign.

### Both correct

```text
correct + agreement
-> candidate may pass early gates
-> human review before later gates
```

### Clear pass but degraded false consensus

```text
clear fidelity pass
+ degraded same wrong agreement
-> hard rejection
```

Interpretation: the consensus rule is not safe enough for runtime use.

## 25. Risks

### Correlated OCR error

PSM 6 and PSM 11 use the same engine/model, so both may agree on the same wrong text. Gate D explicitly tests this with existing degraded controls.

### Synthetic-fixture limitation

Passing retained fictional controls is not population accuracy, live-source validation, or current-benefit truth.

### Context loss

Cropping may remove useful page-level context and can make OCR worse. Gate C must reject that result rather than add padding or tuning.

### Batch mapping

Image-list/page-number semantics may not safely preserve input identity. Gate B proves or rejects this before fidelity is interpreted.

### Ruled-grid dependency

Redesign 3A still depends on the existing supported ruled-grid shape. It does not solve borderless PDFs.

### Overfitting

No crop, PSM, fixture, normalization, or threshold may be changed after observing the first fixed matrix merely to rescue the candidate.

## 26. Product dependency and P4-3B

Even `P4_3_REDESIGN3A_EARLY_GATES_PASS` does not approve Tesseract/model packaging.

Until later gates and a separate dependency review succeed:

- product dependency = `NOT_APPROVED`;
- P4-3B = `BLOCKED`;
- P4-3 = `NOT COMPLETE`;
- Phase 4 = `NOT COMPLETE`;
- `ProductionAction=NONE`.

## 27. Completion boundary

This written spec authorizes only the design of the Redesign 3A evaluation.

Implementation may begin only after:

1. this written spec is reviewed and approved;
2. a separate implementation plan is written and reviewed;
3. the user approves execution of that plan.

No implementation, experiment, preprocessing, engine/model comparison, product dependency, or P4-3B work is authorized by the spec alone.

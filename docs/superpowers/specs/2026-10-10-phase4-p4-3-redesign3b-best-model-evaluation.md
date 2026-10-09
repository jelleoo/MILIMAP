# Phase 4 P4-3 — OCR Redesign 3B: Official Korean Best-Model Evaluation

Date: 2026-10-10<br>
Status: DESIGN APPROVED IN CHAT / WRITTEN SPEC REVIEW REQUIRED<br>
Base: `dev` at `928783e7050a8a9c312c2d768ea359af341d0dc7`

## 1. Purpose

Redesign 3B evaluates one narrowly bounded hypothesis after the merged Redesign 3A rejection:

> Does replacing only the Korean OCR model from the fixed official `tessdata_fast/kor.traineddata` candidate to a pinned official `tessdata_best/kor.traineddata` candidate recover mandatory Korean text fidelity while preserving all previously proven structural, provenance, reconstruction, fail-closed, and efficiency boundaries?

Redesign 3A established:

- Gate A — crop provenance = PASS;
- Gate B — batch mapping = PASS;
- Gate C — clear fidelity = FAILED;
- Gate D = `NOT_RUN_GATE_C_FAILED`;
- final = `P4_3_REDESIGN3A_REJECTED / GATE_C_CLEAR_FIDELITY_FAILED`;
- clear Gray/RGB PSM6 mandatory = 5/8, all-cell = 7/12;
- clear Gray/RGB PSM11 mandatory = 6/8, all-cell = 8/12;
- representative failures included `전화번호` -> `전 화 번 호`, PSM11 `주소` -> `즈 ㅅ\n구수`, and PSM6 mandatory structural NOT_EVALUATED observations;
- exact cell cropping alone did not improve the PSM11 mandatory score over Redesign 2.

Therefore Redesign 3B does not reopen crop geometry, PSM search, preprocessing, normalization, confidence, overlap policy, or product integration. It changes **one variable only: the Korean trained model**.

This remains an evaluation-only redesign. It does not approve any product OCR dependency or P4-3B production implementation.

## 2. Why model-only is the next experiment

The retained clear controls are already synthetic, high-contrast, ruled-grid fixtures with deterministic source bytes, proven geometry, exact crops, and repeatable OCR output. Redesign 3A showed that changing the segmentation unit from full-page to exact cell crops did not recover required fidelity.

The next lowest-dimensional experiment is therefore the official accuracy-oriented Tesseract model family, not a preprocessing parameter search.

Redesign 3B intentionally avoids changing multiple variables at once. If `tessdata_best/kor` also fails on the same unchanged clear crops, the model-only hypothesis is rejected cleanly and preprocessing or another OCR engine may be considered in a later separately approved redesign.

## 3. Fixed baseline

The following remain fixed from Redesign 3A.

### OCR runtime

- Windows Tesseract build: `v5.5.3.20260724` / engine 5.5.3;
- installer SHA-256:
  `bee9e3434bd94fd65387d9be28cd467a41f61b1275383b55b0f59a1331270ae4`;
- `tesseract.exe` SHA-256:
  `c66f0f12ed76f6aa455dac97684bbc86756d6a732380bee09122454cfda3f420`;
- `libtesseract-5.dll` SHA-256:
  `54d54528b453ce3a5ba79487687f8df43e7b194b9ea97beba74200453fe1fb46`;
- `libleptonica-6.dll` SHA-256:
  `1869b44e3d46fd830620b042477e5d60a950779582f38f60291547efb27792f1`.

### OCR configuration

- language: `kor`;
- OEM: `1`;
- DPI: `300`;
- PSM 6: primary bounded-cell view;
- PSM 11: verifier sparse-text view;
- no additional Tesseract option override.

### Structural and text policies

- `PROVEN_CELL_CROP_V1`;
- ruled-grid authority unchanged;
- fixed same-cell overlap ratio `0.25`;
- `TEXT_FIDELITY_NORMALIZATION_V1`;
- confidence `DIAGNOSTIC_ONLY_V1`;
- no confidence-based acceptance, rescue, selection, or rejection;
- `ProductionAction=NONE`.

## 4. Historical fast-model baseline

The Redesign 3A baseline remains historical evidence and is not rerun merely to create a comparator.

Pinned historical fast model:

- repository: `tesseract-ocr/tessdata_fast`;
- source commit: `87416418657359cb625c412a48b6e1d6d41c29bd`;
- `kor.traineddata` Git blob:
  `60986d44497689f3abace0b148199476d93292e1`;
- file size: `1,677,415` bytes;
- SHA-256:
  `6b85e11d9bbf07863b97b3523b1b112844c43e713df8b66418a081fd1060b3b2`.

Authoritative historical result:

| Fixture | PSM | Mandatory | All-cell |
| --- | ---: | ---: | ---: |
| Gray | 6 | 5/8 | 7/12 |
| Gray | 11 | 6/8 | 8/12 |
| RGB | 6 | 5/8 | 7/12 |
| RGB | 11 | 6/8 | 8/12 |

No Redesign 3B gate depends on rerunning this fast baseline.

## 5. Redesign 3B candidate model

The only new evaluation candidate is one pinned official `tessdata_best` Korean model.

Source identity checked 2026-10-10:

- repository: `tesseract-ocr/tessdata_best`;
- annotated tag: `4.1.0`;
- tag object SHA:
  `f0c187c74d3038e6d135fd080e30909af350eae0`;
- GitHub tag verification: valid signed tag;
- tag target commit:
  `e2aad9b983032bb1beff9133104a67cdbb87ca4d`;
- tree:
  `23d6207aa77e8f11abd8b300e12d2d94df300fb6`;
- `kor.traineddata` Git blob:
  `c82615b5228c9981c33a0985b32224d97b7fb43a`;
- file size:
  `12,528,128` bytes;
- repository README states these are the most accurate trained models and require the LSTM engine;
- repository data license: Apache-2.0.

The candidate is evaluation-only.

The exact downloaded candidate bytes must have their SHA-256 calculated and recorded **before the first OCR quality invocation**. The evaluation must then use only that exact file for the entire cycle.

No OCR result may be observed before model source identity, byte size, and SHA-256 are frozen in the evaluation record.

A later run with different candidate bytes is a new evaluation and may not be silently substituted.

## 6. Single-variable rule

Redesign 3B changes:

```text
tessdata_fast/kor
        ↓
tessdata_best/kor
```

and nothing else.

The following must remain byte-for-byte or semantically identical to the approved Redesign 3A boundary:

- source PDF fixtures;
- decoded source image bytes;
- ruled-grid proof;
- cell rectangles;
- crop bytes;
- crop hashes;
- crop order;
- OCR batching shape;
- PSM roles;
- OEM;
- DPI;
- TSV parsing;
- page-to-crop mapping;
- crop-local reconstruction;
- overlap classification;
- fidelity normalization;
- mandatory role definitions;
- authored ground truth.

If any of those must change to make the best model pass, Redesign 3B is not the experiment being run.

## 7. Scope

Redesign 3B may:

- reuse the merged Redesign 3A evaluation functions read-only;
- prepare the exact same Gray/RGB proven-cell crops;
- use the exact same historical clear and degraded fixtures;
- acquire the single pinned official `tessdata_best/kor.traineddata` candidate outside the repository;
- calculate and record its SHA-256 before OCR;
- invoke the fixed Tesseract runtime with the pinned best model;
- evaluate PSM 6 and PSM 11 only;
- measure exact fidelity, consensus, false-consensus behavior, determinism, invocation counts, model size, and elapsed time;
- compare new best-model results to the already-committed fast-model historical result.

## 8. Non-scope

Redesign 3B must not introduce or evaluate:

- another Tesseract version/build;
- another `tessdata_best` version or commit;
- `tessdata` standard model comparison;
- custom/fine-tuned Korean model;
- another OCR engine;
- preprocessing of any kind;
- scaling or super-resolution;
- interpolation search;
- binarization;
- threshold search;
- white-border tuning;
- sharpening;
- denoise;
- line removal;
- contrast tuning;
- deskew;
- crop padding;
- adaptive crop margin;
- OCR-driven crop movement;
- alternate grid geometry;
- alternate overlap ratio;
- PSM search beyond fixed 6 and 11;
- OEM search;
- DPI search;
- dictionary/user-word tuning;
- expected-text-driven OCR correction;
- Korean/jamo repair;
- character substitution;
- forced whitespace deletion to join Korean characters;
- fuzzy/edit-distance/semantic equivalence;
- product OCR adapter;
- runtime packaging into the app/product;
- API/schema/DB/auth changes;
- canonical/seed/apps writes;
- P4-3B production implementation.

## 9. Historical preservation and reuse

The following paths are historical evidence and remain read-only:

- `tools/data/evaluation/p4-3a-ocr/**`
- `tools/data/evaluation/p4-3a2-ocr/**`
- `tools/data/evaluation/p4-3-redesign2-ocr/**`
- `tools/data/evaluation/p4-3-redesign3a-ocr/**`

Redesign 3B must not refactor Redesign 3A merely to make its fast-model wrapper generic.

Instead Redesign 3B may dot-source and reuse stable Redesign 3A helper behavior such as:

- PNM validation;
- exact crop generation;
- fixture preparation;
- Gate A preparation authority;
- TSV parser/process boundary where model-independent;
- crop-local reconstruction;
- overlap logic;
- ground-truth authority;
- fidelity normalization.

The 3B-owned model invocation boundary must preserve the Redesign 3A batch contract while changing only the candidate model identity.

Any deliberate behavioral divergence from Redesign 3A outside model identity is a design violation.

## 10. Safety invariants

Every Redesign 3B outcome remains fail-closed.

No OCR output may:

- modify grid geometry;
- move text between cells;
- create or repair rows/columns;
- infer semantic `NOT_FOUND`;
- create a benefit claim;
- create `GREEN`, `ACTIVE`, lifecycle, or currentness state;
- modify canonical, seed, app, or product data.

Expected text is evaluation-only and may not enter:

- crop generation;
- OCR invocation;
- OCR ordering;
- overlap resolution;
- text reconstruction;
- consensus;
- model selection;
- runtime binding.

Confidence remains diagnostic only.

## 11. Gate A — Candidate model supply

Gate A answers:

> Is the exact, pinned official best-model candidate available with trustworthy identity before any quality result is observed?

Required evidence:

- repository = `tesseract-ocr/tessdata_best`;
- tag = `4.1.0`;
- tag object = `f0c187c74d3038e6d135fd080e30909af350eae0`;
- target commit = `e2aad9b983032bb1beff9133104a67cdbb87ca4d`;
- blob = `c82615b5228c9981c33a0985b32224d97b7fb43a`;
- byte size = `12,528,128`;
- filename = `kor.traineddata`;
- license = Apache-2.0;
- calculated SHA-256 recorded before OCR;
- fixed Tesseract runtime identities still match the approved hashes;
- Tesseract runtime reports `v5.5.3.20260724`.

Gate A does not run clear/degraded OCR.

Failure or unverifiable supply:

`P4_3_REDESIGN3B_NOT_EVALUATED / GATE_A_MODEL_SUPPLY_NOT_EVALUATED`.

Do not substitute another model.

## 12. Gate B1 — Clear Gray fidelity

Gate B1 runs only after Gate A passes.

Prepare the historical clear Gray fixture once using the unchanged Redesign 3A preparation/crop authority.

Then execute:

- PSM6, repetition 1;
- PSM6, repetition 2;
- PSM11, repetition 1;
- PSM11, repetition 2.

Maximum actual OCR processes at this gate: `4`.

Acceptance for **each PSM independently**:

- mandatory fidelity = `8/8`;
- no mandatory `FIDELITY_MISMATCH`;
- no mandatory `FIDELITY_NOT_EVALUATED`;
- mapped words, reconstructed text, fidelity state, and diagnostics repeat identically across the two repetitions.

Whole-table `/12` remains diagnostic and must be reported.

Any mandatory failure or repetition nondeterminism:

`P4_3_REDESIGN3B_REJECTED / GATE_B1_CLEAR_GRAY_FIDELITY_FAILED`.

Stop before RGB and degraded controls.

No tuning/retry after observing the failure.

## 13. Gate B2 — Clear RGB fidelity

Gate B2 runs only after Gate B1 passes.

Prepare historical clear RGB once using the unchanged Redesign 3A preparation/crop authority.

Execute the same four fixed runs:

- PSM6 x2;
- PSM11 x2.

Maximum additional actual OCR processes: `4`.

Acceptance is identical to Gate B1:

- PSM6 mandatory 8/8 on both repetitions;
- PSM11 mandatory 8/8 on both repetitions;
- no mandatory mismatch/NOT_EVALUATED;
- deterministic repeated evidence.

Failure:

`P4_3_REDESIGN3B_REJECTED / GATE_B2_CLEAR_RGB_FIDELITY_FAILED`.

Stop before consensus/degraded evaluation.

## 14. Gate C — Clear dual-PSM consensus

Gate C uses only already-produced B1/B2 evidence.

Additional OCR processes: `0`.

For every mandatory clear cell:

```text
Normalize(PSM6 reconstructed text)
==
Normalize(PSM11 reconstructed text)
==
Normalize(authored ground truth)
```

must hold.

A correct result from one PSM cannot rescue disagreement with the other PSM.

States:

- exact normalized agreement = `CELL_CONSENSUS`;
- disagreement = `CELL_DISAGREEMENT`;
- missing/untrusted reconstruction = `CELL_NOT_EVALUATED`.

Gate C PASS requires every mandatory cell in Gray and RGB to be exact correct consensus.

Failure:

`P4_3_REDESIGN3B_REJECTED / GATE_C_CLEAR_CONSENSUS_FAILED`.

## 15. Gate D — Degraded false-consensus safety

Gate D runs only after Gates A, B1, B2, and C pass.

Use only the existing committed controls:

- `mild-degraded-gray.pdf`;
- `degraded-gray.pdf`;
- `degraded-rgb.pdf`.

No new fixture may be authored.

For each fixture:

- PSM6 once;
- PSM11 once.

Maximum additional actual OCR processes: `6`.

Per mandatory cell:

- both PSMs agree on authored truth -> safe consensus;
- PSM6 != PSM11 -> fail closed, no acceptance;
- both PSMs agree on the same wrong text -> `FALSE_CONSENSUS`, hard rejection;
- missing/untrusted result -> `CELL_NOT_EVALUATED`, no semantic absence.

Historical degraded fixtures are not required to remain empty. If best-model cell crops recover words, evaluate those words against the pre-authored truth. Do not classify recovery itself as a regression.

A single mandatory `FALSE_CONSENSUS` rejects the candidate.

Failure:

`P4_3_REDESIGN3B_REJECTED / GATE_D_FALSE_CONSENSUS_FAILED`.

## 16. Early-cycle outcome

Allowed final first-cycle outcomes:

### `P4_3_REDESIGN3B_EARLY_GATES_PASS`

Requires A, B1, B2, C, D all PASS.

Meaning only:

- the pinned official best model passed this bounded synthetic early matrix;
- no mandatory false consensus was observed in the retained degraded controls.

It does **not** mean production approval.

### `P4_3_REDESIGN3B_REJECTED`

Any observed disqualifying quality/safety failure.

Preserve the first failing reached gate reason.

### `P4_3_REDESIGN3B_NOT_EVALUATED`

Use when required candidate/runtime/fixture authority cannot be established and no prior disqualifying observation exists.

All outcomes:

- `ProductDependency=NOT_APPROVED`;
- `P43B=BLOCKED`;
- `P4-3=NOT COMPLETE`;
- `Phase4=NOT COMPLETE`;
- `ProductionAction=NONE`;
- `NextAction=HUMAN_REVIEW_STOP`.

## 17. Gate ordering and cost ceiling

The gate order is intentionally cost-biased:

```text
A model supply
  ↓
B1 Gray fidelity     max 4 OCR
  ↓
B2 RGB fidelity      +4 OCR
  ↓
C clear consensus    +0 OCR
  ↓
D degraded safety    +6 OCR
  ↓
HUMAN REVIEW STOP
```

Maximum first measurement: `14` actual OCR processes.

If Gray fails, stop at `4`.

If Gray passes but RGB fails, stop at `8`.

Do not rerun the historical fast baseline.

Do not run a separate real batch-mapping probe before B1. The batch mapping contract is already proven in Redesign 3A for the same runtime, crop shape, TSV mapping, and PSM roles; B1's actual batch results must still satisfy the exact mapping contract.

## 18. Performance evidence

The best model is materially larger than the historical fast model:

- fast Korean model: `1,677,415` bytes;
- best Korean candidate: `12,528,128` bytes.

Redesign 3B must record:

- candidate bytes;
- candidate SHA-256;
- per-batch elapsed milliseconds;
- observed best-model median/range by fixture/PSM;
- comparison to committed historical fast-model elapsed evidence where the comparison is semantically valid.

No latency threshold is introduced in this early cycle.

Accuracy/safety gates cannot be waived because best is slower, and the model cannot be rejected solely because it is slower without a separately approved product-feasibility threshold.

## 19. Efficiency and duplication rules

Required:

- clear fixture preparation once per fixture;
- one OCR batch process per PSM/repetition;
- no per-cell process;
- no per-row process;
- no per-business OCR;
- no OCR retry after a measured quality failure;
- no duplicate fast-baseline measurement;
- Gate C reuses B evidence;
- later gates blocked immediately after the first disqualifying result.

Historical Redesign 3A code remains immutable evidence.

Redesign 3B should own only the minimum model-specific invocation/orchestration delta.

## 20. Expected repository boundary

The evaluation should be isolated under a new directory such as:

`tools/data/evaluation/p4-3-redesign3b-ocr/**`

Likely responsibilities:

- candidate-model supply/identity contract;
- best-model batch invocation boundary;
- Redesign 3B gate orchestration;
- tests;
- result README.

The exact file decomposition belongs to the implementation plan.

No product/protected path is authorized.

Protected paths remain:

- `tools/data/pdf-native/**`;
- `tools/data/lib/**`;
- `data/canonical/**`;
- `data/seed/**`;
- `apps/**`.

## 21. Test strategy

Use TDD for implementation.

At minimum test:

- exact candidate source metadata contract;
- model filename/size/hash mismatch rejection;
- exact fixed runtime identity;
- only PSM6/11 allowed;
- no fast-model fallback;
- no alternate best-model fallback;
- Redesign 3A crop/provenance behavior reused unchanged;
- batch mapping fail-closed behavior preserved;
- Gray early-stop semantics;
- RGB not invoked after Gray rejection;
- clear exact fidelity;
- repetition determinism;
- clear consensus with zero extra OCR;
- disagreement cannot be confidence-rescued;
- false-consensus classification;
- empty/untrusted degraded output never creates semantic absence;
- recovered degraded words evaluated rather than rejected merely for recovery;
- expected text does not leak into runtime/model choice;
- historical P4-3A/P4-3A2/Redesign2/Redesign3A diff = 0;
- protected-path diff = 0;
- full current data suite;
- `git diff --check`.

Android local remains `NOT_RUN_EVALUATION_ONLY` unless a protected/product path changes unexpectedly; such a change is a scope violation and must stop the work rather than expand testing.

## 22. Interpretation rules

### Best model fails Gate B1

Conclusion allowed:

> The pinned official `tessdata_best/kor` candidate did not recover mandatory fidelity on the unchanged clear Gray cell crops.

Do not claim all preprocessing or all OCR engines are invalid.

### Gray passes, RGB fails

Conclusion allowed:

> The model-only candidate is sensitive to the retained Gray/RGB representation under otherwise fixed conditions.

A later image-conditioning design may be considered separately.

### Clear fidelity passes, consensus fails

Conclusion allowed:

> Recognition improved, but fixed PSM6/PSM11 runtime trust remains unstable.

Do not pick the correct PSM using ground truth or confidence.

### Clear/consensus passes, degraded false consensus occurs

Conclusion allowed:

> The candidate is accurate on retained clear controls but unsafe as a runtime consensus signal under the retained degraded control.

Product dependency remains blocked.

### A-D all pass

Conclusion allowed:

> The model-only candidate passed the bounded synthetic early gates.

This does not establish population accuracy, live-source compatibility, business isolation, resource safety, multipage support, cross-OS determinism, or product suitability.

## 23. Later gates — not authorized by this spec

Even after early-gates PASS, do not proceed automatically to:

- business isolation;
- timeout/resource/fault qualification beyond inherited batch safety;
- multipage;
- Windows/Ubuntu semantic determinism;
- product packaging;
- APK/runtime size feasibility;
- dependency approval;
- P4-3B implementation.

Those require a separate reviewed implementation/design continuation.

## 24. Risks

### Same-engine correlated error

`tessdata_best` still uses the same Tesseract engine. PSM6/PSM11 may agree on the same wrong result. Gate D is mandatory before any runtime-like trust claim.

### Synthetic-control limitation

The retained fixtures do not measure population accuracy or live government-document compatibility.

### Larger model

The candidate is substantially larger and may be slower. Early-cycle success does not imply product packaging is acceptable.

### Model age/source choice

Redesign 3B intentionally evaluates the single pinned signed 4.1.0 source identity rather than searching multiple best-model commits. This improves causal clarity but does not prove another model release could not behave differently.

### Ruled-grid dependency

All existing ruled-grid/crop limitations remain.

## 25. Completion boundary

This written spec authorizes only the Redesign 3B evaluation design.

Implementation may begin only after:

1. this written spec is reviewed and approved;
2. a separate implementation plan is written and reviewed;
3. the user approves execution of that plan.

No implementation, model download for quality evaluation, OCR experiment, preprocessing, other model/engine search, product dependency approval, or P4-3B work is authorized by the spec alone.

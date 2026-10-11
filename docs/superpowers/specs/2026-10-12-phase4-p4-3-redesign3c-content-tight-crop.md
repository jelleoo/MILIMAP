# Phase 4 P4-3 — OCR Redesign 3C: Content-Tight Proven-Cell Crop Evaluation

Date: 2026-10-12
Status: DESIGN AUTO-APPROVED BY PROJECT WORKFLOW / WRITTEN SPEC SELF-REVIEW REQUIRED
Base: `dev@4c21fcc878760f6ce5d581d346bdd5b9281b0c9a`

## 1. Problem

P4-3 OCR remains blocked after four rejected evaluation cycles.

The latest two controlled experiments establish:

- Redesign 3A: fixed Tesseract 5.5.3 + pinned `tessdata_fast/kor` + exact proven-cell crops still failed clear mandatory fidelity.
- Redesign 3B: changing only the Korean model to pinned `tessdata_best/kor` produced the same mandatory scores and was rejected at Gray Gate B1.

Historical clear Gray results:

| Candidate | PSM6 mandatory / all | PSM11 mandatory / all |
| --- | --- | --- |
| Redesign 3A fast model | 5/8 / 7/12 | 6/8 / 8/12 |
| Redesign 3B best model | 5/8 / 7/12 | 6/8 / 8/12 |

Representative failures are stable across cycles:

- header text split into extra word boundaries, e.g. `전화번호` reconstructed with internal spaces;
- PSM11 header misrecognition for `주소`;
- PSM6 overlap/reconstruction failures on mandatory cells;
- address text split into per-syllable word tokens.

The next experiment must isolate one new cause without reopening model search or adding a preprocessing sweep.

## 2. Design conclusion

Redesign 3C evaluates **content-tight cropping inside the already proven cell**, while returning to the efficient historical fast-model baseline.

The single experimental difference from Redesign 3A is:

```text
PROVEN_CELL_CROP_V1
        ↓
CONTENT_TIGHT_WHITE255_BORDER10_V1
```

Everything after that transform remains the Redesign 3A path.

```text
PDF
→ historical image eligibility
→ historical ruled-grid proof
→ PROVEN_CELL_CROP_V1
→ deterministic exact-white margin trim
→ 10 px generated white border
→ historical Tesseract fast-model batch
→ historical reconstruction
→ historical fidelity evaluation
```

No scaling, binarization, threshold search, sharpening, line removal, model change, OCR text repair, or reconstruction change is part of Redesign 3C.

## 3. Why this approach

The existing exact cell crops remove page/grid context but still contain large blank regions around short strings. Tesseract's own quality guidance notes that OCR of small regions can be affected by excessive borders and recommends cropping to the text region with a reasonable border. It also mentions rescaling as a possible remedy, but Redesign 3C does not choose scaling first because the retained clear fixture already uses roughly 32-pixel rendered text and there is no evidence that insufficient glyph size is the dominant failure.

Three candidate approaches were considered.

### A. Content-tight crop + fixed white border — selected

Advantages:

- one causal variable;
- no new dependency;
- no parameter search;
- directly targets excessive blank-area segmentation;
- preserves original text pixels exactly;
- can reuse Redesign 3A OCR batch/reconstruction/fidelity code read-only;
- lowest implementation and OCR cost.

Risk:

- real scanned backgrounds may not contain exact-white margins, so synthetic success would not establish live applicability.

### B. Fixed 2x scaling — not selected for this cycle

It is deterministic and cheap, but changes glyph dimensions without evidence that the current glyphs are too small. It can also move the input into an overly large character-size regime. It remains a later isolated hypothesis if justified.

### C. Geometry-aware whitespace reconstruction — deferred

This directly targets Tesseract word-boundary splitting, but changes the text trust/reconstruction policy rather than only the OCR input. A spacing rule could silently join legitimate whitespace and would need a separate safety design. It must not be mixed into this cycle.

## 4. Experimental reference

Redesign 3C compares against **Redesign 3A**, not Redesign 3B.

Reason:

- 3B showed no mandatory fidelity improvement from the larger best model;
- retaining the best model would add model size/latency without observed quality benefit;
- using the historical fast-model baseline means only the crop-input policy changes relative to 3A.

Pinned fast model:

- repository: `tesseract-ocr/tessdata_fast`;
- source commit: `87416418657359cb625c412a48b6e1d6d41c29bd`;
- `kor.traineddata` Git blob: `60986d44497689f3abace0b148199476d93292e1`;
- bytes: `1677415`;
- SHA-256: `6b85e11d9bbf07863b97b3523b1b112844c43e713df8b66418a081fd1060b3b2`.

Runtime remains the exact Redesign 3A runtime:

- Tesseract build `v5.5.3.20260724`;
- engine 5.5.3;
- `tesseract.exe` SHA-256 `c66f0f12ed76f6aa455dac97684bbc86756d6a732380bee09122454cfda3f420`;
- `libtesseract-5.dll` SHA-256 `54d54528b453ce3a5ba79487687f8df43e7b194b9ea97beba74200453fe1fb46`;
- `libleptonica-6.dll` SHA-256 `1869b44e3d46fd830620b042477e5d60a950779582f38f60291547efb27792f1`;
- language `kor`;
- OEM 1;
- DPI argument 300;
- PSM6 primary, PSM11 verifier.

## 5. Content-tight transform

Policy name:

`CONTENT_TIGHT_WHITE255_BORDER10_V1`

Input authority is only a valid `PROVEN_CELL_CROP_V1` PGM/PPM artifact from the historical Redesign 3A preparation.

### 5.1 Background definition

No tunable threshold exists.

For PGM:

- background pixel = exactly `255`;
- content pixel = any value other than `255`.

For PPM:

- background pixel = exactly `255,255,255`;
- content pixel = any pixel where at least one component is not `255`.

This includes anti-aliased glyph pixels without choosing a grayscale threshold.

### 5.2 Content rectangle

For every valid crop, compute the minimal axis-aligned rectangle containing all content pixels.

Required result fields:

- source cell ID / row / column;
- source crop SHA-256;
- source width / height / components;
- content `X0,Y0,X1,Y1` in source-crop coordinates;
- content width / height;
- non-white pixel count;
- border policy;
- output width / height;
- output SHA-256.

If no content pixel exists:

`CONTENT_BOUNDS_NOT_EVALUATED / EMPTY_CONTENT`.

Do not infer semantic absence.

### 5.3 Output artifact

Output contains:

1. a generated exact-white 10 px border on all four sides;
2. exact source pixels from the minimal content rectangle;
3. no pixel from outside the proven source cell.

Output dimensions:

```text
width  = contentWidth  + 20
height = contentHeight + 20
```

The source content pixels must be copied byte-for-byte.

For PGM the generated border byte is `255`.

For PPM each generated border pixel is `255,255,255`.

No alpha, interpolation, resampling, color conversion, thresholding, morphology, or compression is allowed.

### 5.4 Determinism

Identical source crop bytes must produce identical:

- content rectangle;
- non-white count;
- output dimensions;
- output bytes;
- output hash.

Expected text and OCR output may not enter this transform.

## 6. Provenance and safety

The transform must preserve a chain:

```text
fixture/PDF
→ decoded source pixels
→ proven grid cell
→ original crop hash
→ content rectangle
→ generated-white border policy
→ transformed crop hash
→ OCR batch
```

The generated border is preprocessing metadata, not source evidence.

No transformed coordinate may be used to change original grid/cell identity.

No OCR result may:

- change the content rectangle;
- move a crop;
- choose a border size;
- create row/column geometry;
- create semantic `NOT_FOUND`;
- create a benefit claim;
- create lifecycle/currentness state;
- modify canonical/seed/app data.

`ProductionAction=NONE` remains invariant.

## 7. Scope

Redesign 3C may:

- reuse Redesign 3A preparation and crop artifacts read-only;
- add deterministic content-tight transformation under a new 3C evaluation path;
- reuse Redesign 3A fast-model batch wrapper directly;
- reuse Redesign 3A reconstruction, overlap, ground-truth, fidelity, and determinism semantics;
- evaluate the retained clear/degraded fixtures;
- record transform ratios and OCR process counts.

## 8. Non-scope

Do not add or evaluate:

- `tessdata_best` in quality OCR;
- another model or OCR engine;
- resizing or interpolation;
- binarization or threshold tuning;
- contrast/sharpen/denoise;
- line removal;
- deskew;
- adaptive border;
- border-size search;
- non-white threshold search;
- PSM/OEM/DPI search;
- character/jamo correction;
- forced whitespace joining;
- geometry-aware text reconstruction;
- dictionary/user-word tuning;
- product OCR integration;
- new external library;
- API/schema/DB/auth change;
- canonical/seed/apps write.

## 9. Historical preservation

Read-only:

- `tools/data/evaluation/p4-3a-ocr/**`;
- `tools/data/evaluation/p4-3a2-ocr/**`;
- `tools/data/evaluation/p4-3-redesign2-ocr/**`;
- `tools/data/evaluation/p4-3-redesign3a-ocr/**`;
- `tools/data/evaluation/p4-3-redesign3b-ocr/**`.

Do not refactor historical helpers merely to remove small evaluation glue.

Prefer direct reuse of Redesign 3A public helpers whenever possible.

## 10. Gate A — Transform provenance

No OCR.

For clear Gray first, prove all 12 transformed crops:

- originate from the exact proven 3A crop objects;
- source hash still matches;
- content bounds are inside the source crop;
- content is non-empty;
- output pixels equal exact source content pixels plus exact 10px white border;
- no source pixel outside the content rectangle appears;
- output hash is deterministic;
- cell/order identity remains 1..12;
- transform build count = 1.

Gate:

`GATE_A_CONTENT_TIGHT_PROVENANCE_PASS`

Failure/unavailable authority:

`P4_3_REDESIGN3C_NOT_EVALUATED / GATE_A_CONTENT_TIGHT_PROVENANCE_NOT_EVALUATED`.

Do not run quality OCR.

## 11. Gate B1 — Clear Gray fidelity

Runs only after Gate A PASS.

Prepare Gray once, transform once, reuse the same transformed 12 crops.

Quality matrix:

- PSM6 x2;
- PSM11 x2.

Maximum quality OCR: `4`.

Acceptance for each PSM independently:

- mandatory fidelity = 8/8;
- no mandatory mismatch;
- no mandatory NOT_EVALUATED;
- repeated words/text/fidelity/diagnostics identical.

All-cell score remains diagnostic.

Any disqualifying observation:

`P4_3_REDESIGN3C_REJECTED / GATE_B1_CLEAR_GRAY_FIDELITY_FAILED`.

Stop immediately.

Do not run RGB, consensus, or degraded quality OCR.

The historical 3A fast baseline is not rerun separately.

## 12. Gate B2 — Clear RGB fidelity

Only after B1 PASS.

RGB prepare once, transform once.

- PSM6 x2;
- PSM11 x2.

Maximum additional OCR: `4`.

Same acceptance as B1.

Failure:

`P4_3_REDESIGN3C_REJECTED / GATE_B2_CLEAR_RGB_FIDELITY_FAILED`.

## 13. Gate C — Clear dual-PSM consensus

Only after B1/B2 PASS.

Additional OCR: `0`.

Reuse already-produced evidence.

Every mandatory cell in Gray and RGB must satisfy:

```text
Normalize(PSM6)
==
Normalize(PSM11)
==
Normalize(authored truth)
```

Confidence cannot choose a winner.

Failure:

`P4_3_REDESIGN3C_REJECTED / GATE_C_CLEAR_CONSENSUS_FAILED`.

## 14. Gate D — Degraded safety

Only after A/B1/B2/C PASS.

Use only committed:

- `mild-degraded-gray.pdf`;
- `degraded-gray.pdf`;
- `degraded-rgb.pdf`.

For each:

- prepare once;
- apply the same fixed content-tight policy;
- PSM6 x1;
- PSM11 x1.

Maximum additional OCR: `6`.

Per mandatory cell:

- same correct text -> `CORRECT_CONSENSUS`;
- different text -> `CELL_DISAGREEMENT`, safe fail-closed;
- same wrong text -> `FALSE_CONSENSUS`, hard reject;
- missing/untrusted -> `CELL_NOT_EVALUATED`.

Gate D PASS requires:

- no `FALSE_CONSENSUS`;
- no `CELL_NOT_EVALUATED`.

A `CELL_DISAGREEMENT` is allowed as fail-closed evidence.

## 15. Early-cycle verdict

Allowed:

- `P4_3_REDESIGN3C_EARLY_GATES_PASS`;
- `P4_3_REDESIGN3C_REJECTED`;
- `P4_3_REDESIGN3C_NOT_EVALUATED`.

Preserve the first failing reached gate.

Even EARLY_GATES_PASS does not approve product use.

Always:

- Product dependency = `NOT_APPROVED`;
- P4-3B = `BLOCKED`;
- P4-3 = `NOT COMPLETE`;
- Phase 4 = `NOT COMPLETE`;
- `ProductionAction=NONE`;
- next action = human review stop.

## 16. Efficiency budget

First measurement:

```text
Gate A transform proof   0 OCR
B1 Gray                  max 4
B2 RGB                   +4
C consensus              +0
D degraded               +6
------------------------------
absolute maximum         14
```

Gray failure stops at 4.

No:

- fast baseline rerun;
- mapping-only OCR probe;
- per-cell OCR;
- per-row OCR;
- per-business OCR;
- quality retry after failure;
- preprocessing parameter search.

Preparation/transform counts must be explicit and separate from OCR process counts.

## 17. Implementation boundary

Expected new path:

`tools/data/evaluation/p4-3-redesign3c-ocr/**`

Likely responsibilities:

- `content-tight-crops.ps1` — exact-white trim and fixed border transform;
- `run-evaluation.ps1` — gates and early stop;
- `test-evaluation.ps1` — TDD and reached-path verification;
- `README.md` — factual result.

Do not add a new OCR batch wrapper unless current Redesign 3A public wrapper cannot consume transformed crop objects. If small adapter glue is unavoidable, keep it 3C-local and document why.

## 18. Testing

At minimum test:

- exact PGM white/content classification;
- exact PPM white/content classification;
- anti-aliased non-255 pixels retained;
- empty all-white crop -> NOT_EVALUATED;
- one-pixel content;
- edge content;
- exact 10px border on all sides;
- source content copied byte-for-byte;
- no neighboring/source-outside pixels;
- deterministic output hash;
- malformed PNM fail closed;
- source crop mutation detected;
- 12-cell identity/order preserved;
- expected text cannot influence transform;
- no OCR in Gate A;
- B1 exact four-call ceiling;
- B1 failure blocks all later OCR;
- historical 3A/3B/protected diff = 0;
- full current data suite;
- `git diff --check`.

## 19. Interpretation

### Gray fails

Allowed:

> Fixed exact-white content trimming with a 10px generated white border did not recover required mandatory fidelity on the retained clear Gray control under the historical fast-model OCR path.

Do not claim all preprocessing fails.

### Gray passes, RGB fails

Allowed:

> The content-tight policy is representation-sensitive under the retained Gray/RGB controls.

### Clear passes, degraded fails

Allowed:

> The transform can improve clear controls without establishing safe degraded-input behavior.

### A-D pass

Allowed:

> The fixed content-tight policy passed the bounded synthetic early gates.

Still unproven:

- live source behavior;
- noisy/non-white scan trimming;
- business isolation;
- multipage;
- cross-OS determinism;
- product packaging/runtime feasibility.

## 20. Completion boundary

This spec authorizes only Redesign 3C evaluation.

No product OCR dependency, P4-3B implementation, alternate preprocessing, geometry-aware reconstruction, new model, or new OCR engine is approved by any result in this cycle.

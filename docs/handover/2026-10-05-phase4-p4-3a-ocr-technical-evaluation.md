# P4-3A OCR technical evaluation — rejected closeout

Date: 2026-10-05
Status: P4-3A = REJECTED (user-confirmed final verdict)
Base: `170285cf3e9860dd0c113306300712996bb6c8f8`
Pre-closeout harness checkpoint: `13457651983ef88243768e474bb6d5b84f312624`; evaluation-only Task 3 changes are retained with this report. No accepted semantic row or production adapter is implemented.
Design: `04bcd651991d73a26d3114bafe01974050e996ec`
Plan: `e618795961f00a08a2eafea72a5c40fbae5aedea`

The user confirmed the executed bounded matrix and final rejection. Windows portable supply/runtime identity/offline execution passed, but mandatory Gray/RGB usable-positive acceptance failed. Product dependency = NOT_APPROVED; P4-3B = BLOCKED. Phase 4 is NOT COMPLETE. No geometry/confidence policy has been relaxed.

## Candidate identity and material options

- Engine: official Windows Tesseract `v5.5.3.20260724`, Leptonica `1.87.0`.
- Installer SHA-256: `bee9e3434bd94fd65387d9be28cd467a41f61b1275383b55b0f59a1331270ae4`.
- Portable supply: existing JetBrains Toolbox 7-Zip 26.01 extracts the verified NSIS installer, without installer execution/admin rights. EXE plus 55 root DLLs; no registry/PATH/shortcut changes. Absolute-path offline execution succeeded.
- Source: `https://github.com/tesseract-ocr/tesseract/releases/download/5.5.3/tesseract-ocr-w64-setup-5.5.3.20260724.exe`; Tesseract engine/model Apache-2.0 (not a blanket license claim for all bundled DLLs; transitive runtime redistribution was not approved). Extraction commands: existing `7z.exe l -slt <verified-installer>`, then `7z.exe e <verified-installer> -o<dedicated-outside-repo-temp> -y <tesseract.exe-and-root-DLL-names>`; no installer plugins, training tools, shortcuts or installer language data selected. All calls used absolute executable paths, no global PATH registration.
- Extracted root binaries total 97,632,889 bytes. Core SHA-256: `tesseract.exe` = `c66f0f12ed76f6aa455dac97684bbc86756d6a732380bee09122454cfda3f420`; `libtesseract-5.dll` = `54d54528b453ce3a5ba79487687f8df43e7b194b9ea97beba74200453fe1fb46`; `libleptonica-6.dll` = `1869b44e3d46fd830620b042477e5d60a950779582f38f60291547efb27792f1`. Offline runtime version includes Leptonica 1.87.0; full binary inventory hashes were measured locally before cleanup.
- Model: official `tesseract-ocr/tessdata_fast`, commit `87416418657359cb625c412a48b6e1d6d41c29bd`, `kor.traineddata`.
- Model SHA-256: `6b85e11d9bbf07863b97b3523b1b112844c43e713df8b66418a081fd1060b3b2`.
- Language `kor`; OEM `1`; PSM `3`, `4`, `6`, `11`; DPI `300`; `tessedit_create_tsv=1`.
- Full-page PdfPig-decoded PGM/PPM, one OCR invocation per eligible run; no cell crop/retry, rasterizer, or preprocessing library. No additional OCR option override.
- Grid: `EVAL_PIXEL_GRID_V1_BLACK32_H800_V400_FULL_BORDER_INSET3`, fixed independently of OCR; 12 cells in each clear control.
- Reject thresholds `0`, `50`, `80`, `90`, `95` are evaluated against the same OCR output, not separate OCR invocations.

## Executed matrix

Each clear fixture/configuration ran twice. Word/containment/overlap-event counts below are per run and match in both repetitions and both image formats. COMPLETE/PARTIAL totals aggregate both repetitions and all five thresholds (10 evaluations per fixture/PSM).

| PSM | Gray COMPLETE/PARTIAL | RGB COMPLETE/PARTIAL | Words/run | Non-contained boxes/run | Overlap pair rejection events/run at threshold 0 |
| --- | --- | --- | --- | --- | --- |
| 3 | 0 / 10 | 0 / 10 | 73 | 5 | 10 |
| 4 | 0 / 10 | 0 / 10 | 40 | 2 | 2 |
| 6 | 0 / 10 | 0 / 10 | 30 | 2 | 2 |
| 11 | 0 / 10 | 0 / 10 | 40 | 0 | 2 |

Total clear matrix: 16 OCR invocations, 80 threshold evaluations, COMPLETE=0, PARTIAL=80. All clear runs have one PDF open, one page read, one decode, one grid build, and one OCR invocation. Gray/RGB are fictional technical controls, not benefit truth.

Observed clear-run OCR time=155–294 ms, total inspection/grid/identity/OCR/resolution=524–800 ms. These are local measured timings, not a stress/resource ceiling proof. Fixture provenance is committed in `tools/data/evaluation/p4-3a-ocr/fixtures/manifest.json`; Gray PDF SHA-256=`07182f75f5305bb4611458aeaea880aa57fa78d120030b0f9b6446bd56e5ec17`, RGB=`415645682f805899bdc0852feefec37ae596a3821b97a7ab344fc7d267c61c24`, degraded=`920249969709ec17f5294e314b978bd094a5111018f01b39489414b16d6b5861`.

The degraded control has eight recorded attempts (four PSM loop slots, twice each), all rejected by the unchanged pixel-grid gate before OCR. Its stored result does not retain PSM because that early return precedes OCR configuration; no PSM-specific degraded confidence result is claimed. Grid=UNSUPPORTED, OCR count=0; degraded confidence=NOT_OBSERVED.

## Threshold results

Every entry below is PARTIAL. Values are rejection-list entries per clear run, identical for Gray/RGB and both repetitions; overlapping words can appear more than once in this list. They are not unique rejected-word counts and need not increase monotonically with the threshold.

| PSM | threshold 0 | 50 | 80 | 90 | 95 | Observed confidence min/max |
| --- | --- | --- | --- | --- | --- | --- |
| 3 | 25 | 46 | 64 | 68 | 72 | 0 / 96.99633 |
| 4 | 6 | 8 | 7 | 7 | 26 | 7.252998 / 96.992851 |
| 6 | 6 | 8 | 7 | 7 | 22 | 7.252998 / 97.005417 |
| 11 | 4 | 5 | 7 | 10 | 26 | 22.024605 / 97.019066 |

Overlap pair events at threshold 0 are derived from the recorded rejection entries: `(entries - non-contained boxes) / 2`; every word has nonnegative confidence and the resolver adds both members of each overlapping pair. This is not a count of unique affected words.

## Geometry failure interpretation

Non-contained boxes and same-cell word overlap are distinct. A failed containment box is not automatically proven to cross two cells; it may touch a excluded border region. PSM 11 has no cell-containment failure but still fails overlapping-word rejection.

Observed PSM 11 address syllables include `람` (Left=568, Width=36, confidence=93.270836) and `로` (Left=603, Width=26, confidence=92.522896): horizontal overlap of one pixel. Another `리`/`로` pair overlaps by one pixel with confidence above 93. These are word-to-word overlaps inside a proven address cell, not evidence that the cell grid moved or that these words crossed a cell boundary.

No centroid/nearest/majority assignment, one-pixel allowance, confidence override, OCR-driven grid adjustment, or per-cell OCR was used. The tested candidate configuration family is REJECTED because no usable clear positive survives the approved exact-containment/overlap policy. No safe/useful confidence threshold is established by this matrix.

## Matrix scope and remaining evidence

The approved Task 3 plan requires a small documented material-config matrix but does not enumerate a mandatory PSM/OEM/model Cartesian product. The executed bounded set is the four PSM values above, one pinned fast model, OEM 1, and the fixed options above. No explicitly named additional material configuration in the plan is identified as unexecuted. This does not claim all official models, all PSM modes, or all OCR strategies were tested, nor retroactively claim the numeric matrix was specified in the approved plan.

Other official model variants, engine/strategy changes, crop OCR, rasterizers, preprocessing libraries, and geometry-policy changes have not been evaluated or authorized by this checkpoint. Small/boundary-near/intentional-confusion confidence coverage is not a completed independent calibration. Two-business accepted-row lookup/isolation is NOT_RUN_NO_USABLE_ROWS; repeated local status/count agreement is not Windows/Ubuntu Level A/B proof.

Task 4 = NOT_RUN_CORE_ACCEPTANCE_GATE_FAILED. Task 5 = NOT_RUN_CORE_ACCEPTANCE_GATE_FAILED. Windows/Ubuntu semantic determinism = NOT_RUN; no Level A/B/C is claimed. The mandatory Task 3 positive gate failed, so additional resource/fault stress or cross-platform semantic verification cannot qualify this candidate for product dependency approval. Multipage OCR/lookup reuse/resource-ceiling/fault-stress evidence is not proven. Already performed Windows portable supply = PASS is retained independently of those unexecuted tasks.

The user accepted this bounded matrix for the final decision; no additional PSM/OEM/model/engine/crop/preprocessing/rasterizer/geometry experiment was run. Next: OCR fallback design reconsideration, not P4-3B implementation.

## Evidence retention and verification

Historical local aggregate evidence: ignored `tmp/p43a/calibration-results.json`, SHA-256 `2b1730cdeec74b37f2178da2dae2b847dbfa3df8044faf0f424ff1037fa10a36`, measured/asserted before cleanup and then deleted because it included OCR word fragments. The matrix tables above retain its aggregate counts. Full binary hashes were measured in ignored `tmp/p43a/portable-binary-hashes.json`; core hashes are retained above. Raw OCR output cannot be replayed from this handover.

Cleanup = PASS (2026-10-05, after allowed OCR/geometry tests). Resolved exact target `C:\Users\PC\AppData\Local\Temp\milimap-p43a-portable-20261005` was checked before deletion: 60 files removed, including EXE/DLLs, official model, raw TSV/stderr and handoff PGM. The earlier ignored `tmp/p43a/tesseract-setup.exe`, `kor.traineddata`, and raw-word-containing calibration aggregate were also deleted. All four explicit target checks confirm absence; P4-3A/p43a temporary directory inventory=0. Per-test PGM/PPM directories were removed by their finally blocks. No installer/runtime/model/raw OCR/temp image artifact is staged or committed. Aggregate historical matrix counts and measured hashes above remain the durable evidence; raw OCR output is not retained in Git. Supplier files can be acquired again from the recorded official identities; deleted raw OCR output is not recoverable from this checkout.

## Closeout verification

- Contract: PASS; includes locked restore and Release build, warnings=0/errors=0, runtime/model identity negatives.
- ImageEligibility: PASS; Gray/RGB bounded handoff and unsupported-image negatives.
- GridOcr: PASS for actual TSV mechanics, exact containment/overlap rejection, within-cell multiline ordering and physical grid controls. This is not a usable Korean-positive PASS; the matrix acceptance result remains REJECTED.
- Matrix assertions: PASS for all 8 clear fixture/PSM combinations, two repetitions, five thresholds, all PARTIAL; one open/OCR per eligible run. No additional matrix experiment.
- Safety/All dispatch: explicitly blocked with NOT_RUN_CORE_ACCEPTANCE_GATE_FAILED, preventing the former empty Safety branch from returning false PASS. This adds no Task 4/5 implementation.
- Existing CI-equivalent verify-data suite: PASS 62/62. Exact workflow top-level `tools/data/test-*.ps1` scripts ran sorted by Name. Initial run stopped at `test-pdf-native-runtime.ps1` because dotnet was not in PATH; rerun with the existing evaluation SDK in process-local PATH passed all scripts. No system/user PATH edit. Full output inspected; no missing group is counted as passed.
- Task 4/5 tests: NOT_RUN_CORE_ACCEPTANCE_GATE_FAILED.
- Android: NOT_RUN_EVALUATION_ONLY; exact-head GitHub CI NOT_RUN (no push/PR in this closeout).
- Protected production paths: changes=0; no production dependency added. No claims/lifecycle evaluation or real benefit truth created.
- Remaining risks: candidate usability failure, incomplete degraded/small/confusion calibration, unproven resource/fault/multipage/cross-platform/accepted-row leakage gates. Any follow-up alternative needs a new reviewed design; none is implicitly approved.
- Retained harness limitations (not a production-safe generic OCR API): output limits are checked after ReadToEndAsync, not a hard streaming memory ceiling; the evaluated model path was the pinned file named kor.traineddata, while arbitrary caller model filenames/sibling files are not a validated supply path; process-start-failure cleanup, empty-word output, semantic header rejection, accepted-row lookups and multipage handling are not approved. These are deferred/unverified with Task 4/5 rather than silently counted as safety PASS. The evaluated pinned-path run is distinct from arbitrary future callers.
- Fresh whole-branch read-only closeout review: Critical=0, Important=0; minor per-run/aggregate table wording clarified. This review accepts rejected evaluation closeout only, not a product implementation. No push/PR/merge performed.

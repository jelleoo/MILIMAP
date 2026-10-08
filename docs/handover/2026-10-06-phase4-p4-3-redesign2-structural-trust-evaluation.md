# Phase 4 P4-3 Redesign 2 — Rejection Closeout

Final verdict: `P4_3_REDESIGN2_REJECTED` (human approved).
Reason: `GATE_A2_TEXT_FIDELITY_REJECTED`.
`PRE_BUSINESS_TRUST_PASS = NO`; `ProductionAction=NONE`.
Closeout verified: 2026-10-09 (Asia/Seoul).

## Objective and authority

Evaluate whether the fixed OCR candidate can preserve exact physical cell
provenance, safe same-cell overlap, deterministic reconstruction and required
coverage, then qualify reconstructed text against historical synthetic ground
truth. This is evaluation-only, not a product adapter or real benefit truth.

The fixed candidate passed Gate A1 structural trust but failed mandatory Gate A2
text fidelity. Physical provenance and deterministic structural reconstruction
do not by themselves prove OCR text fidelity for this candidate.

- Fetched dev: `3f40d5c566568b424c83f539aa6554150e74d14d`.
- Approved amended spec ref: `origin/docs/phase4-p4-3-ocr-trust-redesign2`,
  HEAD `ab2fc04e38f3957077c73a6b416ad9fa643d07e8`.
- Approved amendment plan ref:
  `origin/plan/phase4-p4-3-redesign2-text-fidelity-amendment`,
  HEAD `c86fb78a032db27c6ba8c893460241be7ac91915`.
- Original Task 6 closeout structure read at approved original plan HEAD
  `7ae348b7d2e50c38ed79ab2639de7d6d6c5fd118`.
- These documents were read without cherry-picking. Amended spec and the human
  A2 rejection verdict override obsolete combined-Gate-A wording.

Branch: `codex/phase4-p4-3-redesign2-structural-trust-evaluation`.
Worktree: `C:\Users\PC\AndroidStudioProjects\MILIMAP\.worktrees\phase4-p4-3-redesign2-ocr`.
Exact measured implementation HEAD:
`92f21beec97ea683fa9717d7a7eb76de28de20e2`.
Closeout adds documentation and assertions only; the containing commit identifies
the closeout HEAD (a document cannot contain its own final commit hash).

| Checkpoint | Preserved commit |
| --- | --- |
| Task 1 runtime boundary | `136f21633a5782335813392da4b5da19c9bf892d` |
| Gate A1 | `f8d023fed151fe6f93ea580ecc9507d4776b6925` |
| Task 2B.1 ground truth | `83c37dc9a937018ab082772d6f9965a56bd9475f` |
| Task 2B.2 fidelity comparison | `4433f689dcbff7ddbe6f494179fe525130a34a1e` |
| Task 2B.3 actual A2 / review fixes | `92f21beec97ea683fa9717d7a7eb76de28de20e2` |

## Exact tested supply and configuration

- Windows portable Tesseract `v5.5.3.20260724` / 5.5.3;
  Leptonica 1.87.0. Portable Windows supply = PASS, not product approval.
- Installer SHA-256:
  `bee9e3434bd94fd65387d9be28cd467a41f61b1275383b55b0f59a1331270ae4`.
- EXE SHA-256:
  `c66f0f12ed76f6aa455dac97684bbc86756d6a732380bee09122454cfda3f420`.
- Official `tessdata_fast/kor.traineddata`, source commit
  `87416418657359cb625c412a48b6e1d6d41c29bd`, SHA-256
  `6b85e11d9bbf07863b97b3523b1b112844c43e713df8b66418a081fd1060b3b2`.
- Language kor, OEM 1, DPI 300, PSM11 clear positive path; PSM3/4/6 regression
  roles only. Existing PdfPig 0.1.16 inspection/grid helper, locked .NET 8 build.
- `SAME_CELL_OVERLAP_V1`, fixed ratio `0.25`;
  `STRUCTURAL_TRUST_V1`; confidence `DIAGNOSTIC_ONLY_V1`.
- No new engine/model/configuration, fixture, threshold, ratio, preprocessing,
  crop or reconstruction strategy was introduced during closeout.

## Gate A1: GATE_A1_STRUCTURAL_PASS

| Fixed control | Words/run | Structural result | Technical rows |
| --- | ---: | --- | ---: |
| Clear Gray PSM11, 2 identical repetitions | 40 | COMPLETE | 2 |
| Clear RGB PSM11, 2 identical repetitions | 40 | COMPLETE | 2 |
| Mild Gray PSM11 | 39 | PARTIAL / CONFLICTING 2 | 0 |
| Clear Gray/RGB PSM3 | 73 each | PARTIAL / containment failures 5 | 0 |
| Clear Gray/RGB PSM4 | 40 each | PARTIAL / containment failures 2 | 0 |
| Clear Gray/RGB PSM6 | 30 each | PARTIAL / containment failures 2 | 0 |
| Old degraded Gray/RGB PSM11 | 0 each | FAILED / EMPTY_WORD_OUTPUT | 0 |

Clear repetitions were identical for words/bbox/hierarchy/confidence, cells,
reconstructed text and diagnostics. Exact containment, overlap and required
coverage controls passed. Cross-cell, duplicate, conflict, ordering reversal,
transitive line bridge and missing required coverage negatives remain blocking.
Old degraded acceptance/fidelity = NOT_EVALUATED: empty output is an operational
negative, not evidence of text fidelity or confidence rejection.

## Gate A2 authority and measured fidelity

Ground truth is the pre-authored fictional 3x4 table in
`tools/data/evaluation/p4-3a-ocr/fixtures/generate-fixtures.py`, not OCR output
or canonical business/benefit values.

- Generator Git blob: `6231ed473349063ce3b0d12fc7b2cff0bef1d114`.
- Historical manifest Git blob: `cde2a581ec2c4a1fb26481992908b5dcab2740ac`.
- Gray PDF SHA-256:
  `07182f75f5305bb4611458aeaea880aa57fa78d120030b0f9b6446bd56e5ec17`.
- RGB PDF SHA-256:
  `415645682f805899bdc0852feefec37ae596a3821b97a7ab344fc7d267c61c24`.

`TEXT_FIDELITY_NORMALIZATION_V1` permits CRLF -> LF, outer whitespace trim and
horizontal whitespace folding only. Comparison is ordinal; no character/jamo,
punctuation or numeric repair, fuzzy equivalence or OCR-driven answer key.
Expected text stays outside the resolver/runtime and product paths.

| Clear control | Repetitions | Mandatory matches | All-cell matches | Gate A2 |
| --- | --- | ---: | ---: | --- |
| Gray PSM11 | 2 identical | 6/8 each | 8/12 each | REJECTED |
| RGB PSM11 | 2 identical | 6/8 each | 8/12 each | REJECTED |

The same four cells mismatched in both fixtures and both repetitions. Expected
and actual below are also their normalized values; `\n` represents a retained
line break.

| Cell / role | Expected | Reconstructed actual | Raw contributing confidences |
| --- | --- | --- | --- |
| 2 / HEADER (mandatory) | `주소` | `즈 ㅅ\n구수` | 22.024605, 89.565918, 74.8918 |
| 3 / HEADER (mandatory) | `전화번호` | `전 화 번 호` | 93.004196, 93.302788, 93.2752, 96.983627 |
| 6 / AUXILIARY | `가상시 가람로 12` | `가 상 시 가 람 로 12` | 91.062492, 93.304901, 68.908859, 93.295303, 93.270836, 92.522896, 95.703575 |
| 10 / AUXILIARY | `가상시 누리로 23` | `가 상 시 누 리 로 23` | 93.050415, 93.229424, 93.211922, 93.17038, 93.294464, 93.010117, 96.98922 |

The actual rejection cause is the two mandatory header mismatches. Auxiliary
mismatches contribute to the all-cell audit metric, not independent rejection.

Confidence remains diagnostic-only. A low-confidence word can be structurally
accepted yet textually wrong; high-confidence words can also be textually wrong.
This is not a confidence threshold failure, Gate A1 failure, failure of the
same-cell overlap model, or a claim that Tesseract in general is unusable.

## Final gate and product states

| Item | Final state |
| --- | --- |
| Final verdict | P4_3_REDESIGN2_REJECTED |
| Reason | GATE_A2_TEXT_FIDELITY_REJECTED |
| PRE_BUSINESS_TRUST_PASS | NO |
| Gate B — business isolation | NOT_RUN_GATE_A2_FAILED |
| Gate C — operational/resource/fault | NOT_RUN_GATE_A2_FAILED |
| Gate D — multipage | NOT_RUN_GATE_A2_FAILED |
| Gate E — cross-platform determinism | NOT_RUN_GATE_A2_FAILED |
| Windows/Ubuntu determinism | NOT_RUN_GATE_A2_FAILED |
| Product dependency | NOT_APPROVED |
| P4-3B | BLOCKED |
| P4-3 / Phase 4 | NOT COMPLETE |
| ProductionAction | NONE |

Historical cycles remain separate: P4-3A = REJECTED;
P4-3A2 = P4_3A2_REJECTED / GATE_A_CONFIDENCE_REJECTED.
Neither is retroactively described as passing.

## Closeout verification

Rejection-specific assertions exercise the existing decision and verify A1 PASS
and A2 REJECTED -> final REJECTED, never PRE_BUSINESS_TRUST_PASS, no downstream
PASS fabrication, dependency NOT_APPROVED, P4-3B BLOCKED and ProductionAction
NONE. Exact low-confidence text still passes fidelity. These assertions passed
on the first run; no verdict/runtime implementation was changed to force RED.

Executed in closeout:

- Redesign 2 Contract: PASS (exact model hash/runtime contract; external process
  is controlled in this group, not an OCR-quality measurement).
- StructuralTrust: PASS / GATE_A1_STRUCTURAL_PASS, same 13 fixed probes.
- TextFidelity synthetic assertions and real clear controls: PASS as tests;
  measured Gate A2 remains REJECTED, same 4 fixed PSM11 probes.
- Historical helper locked restore/build: PASS, warnings 0 / errors 0.
- Current full data suite: 62/62 PASS; sorted `tools/data/test-*.ps1` executed
  with failure propagation, complete result read.
- Historical P4-3A diff = 0; historical P4-3A2 diff = 0; protected product paths
  (`tools/data/pdf-native`, `tools/data/lib`, canonical/seed/apps) diff = 0.
- Task 1 runtime wrapper unintended diff = 0; prior commits are not rewritten.
- `git diff --check` and approved plan-base diff-check: PASS, new warnings 0.
  Dev-range retains only the two inherited approved original-spec trailing
  whitespace warnings on lines 3/4; closeout does not alter approved documents.

Not executed: Task 3/Isolation, Task 4/Safety/multipage, Task 5/DeterminismContract
and Windows/Ubuntu evaluation — NOT_RUN_GATE_A2_FAILED. `All` was not run because
it would require skipped gates; no placeholders were implemented.
Android local = NOT_RUN_EVALUATION_ONLY (no product/app changes).
CI = NOT_RUN_LOCAL_CLOSEOUT_ONLY (no push/PR).

No installer/runtime/model/raw TSV/image is committed. Portable extraction used
existing 7-Zip outside Git; no installer execution, elevation, registry, shortcut
or persistent PATH changes. SDK PATH additions for tests are process-local.
Supply/temp cleanup: PASS after reached-group/data verification. The exact
dedicated repo-external `milimap-p43r2-evaluation-20261006` directory was checked
for expected contents/no reparse points, then removed: installer, Tesseract EXE,
55 DLLs and Korean model. The target no longer exists. Raw TSV/temp PGM/PPM lived
in per-probe directories removed by the probe's finally block; remaining
`milimap-p43r2-probe-*` directories = 0. Ignored fictional result summaries/test
logs remain local, not committed. Common .NET SDK and unrelated evaluation
directories were not removed. Synthetic TextFidelity assertions passed again
after supply cleanup; repeating actual OCR now requires reacquiring the same
approved, hash-verified evaluation supply, not a new strategy/model.

## Remaining risks and next action

Structural safety does not establish arbitrary OCR character fidelity. Evidence
is bounded to fictional fixtures and this exact candidate; it is not a population
accuracy, real-source benefit validity, business-isolation or cross-platform proof.
No product dependency is approved and no downstream gate can be inferred as PASS.

Next action: **separately approved OCR strategy redesign**.
Input strategy / cell-crop OCR, preprocessing, OCR engine/model or bounded text
reconstruction are possible future design dimensions only, not selected or
approved work. Closeout does not start any of them. Push/PR/merge require separate
human approval.

# P4-3A2 rejection closeout

Date: 2026-10-05

## Authority and scope

Final human-approved verdict: `P4_3A2_REJECTED`.
Reason: `GATE_A_CONFIDENCE_REJECTED`.
Historical `P4-3A = REJECTED` is unchanged. Task 6 is documentation/verification
closeout only; no Task 4/5 implementation or new OCR experiment is authorized.

- Branch: `codex/phase4-p4-3a2-overlap-safety-evaluation`.
- Dev baseline: `4a688a8ca4d67a7b1217b62eced06d770a6db8ac`.
- Approved redesign HEAD: `ce9c8a623fb07950570bb09f4f8840cd74e46a04`.
- Approved plan / implementation base: `e34e6e9fb23d33453142f70e3e40044fabf88614`.
- Task 1: `c123fe4`; Task 2: `f1bfbf7d641974d18b1f9805a79c59934100493e`.
- Task 3 measured implementation: `0c57ac49239a3b1231eec0690f30fab0cbd94b24`.
- Final Task 6 commit is the docs-only commit containing this handover; its exact
  SHA is reported separately after commit, avoiding a self-referential hash.

## Tested supply and fixed configuration

Windows portable supply PASS: Tesseract `v5.5.3.20260724` / 5.5.3,
Leptonica 1.87.0, EXE plus 55 root DLLs. Installer was extracted using existing
JetBrains Toolbox 7-Zip 26.01; no installer execution, UAC, registry, shortcuts
or persistent user/machine PATH modification. Executable was called by absolute
path. This is evaluation supply evidence, not Windows CI reproducibility proof.

| Component | SHA-256 |
| --- | --- |
| Official 5.5.3 Windows installer | `bee9e3434bd94fd65387d9be28cd467a41f61b1275383b55b0f59a1331270ae4` |
| tesseract.exe | `c66f0f12ed76f6aa455dac97684bbc86756d6a732380bee09122454cfda3f420` |
| libtesseract-5.dll | `54d54528b453ce3a5ba79487687f8df43e7b194b9ea97beba74200453fe1fb46` |
| Official kor.traineddata | `6b85e11d9bbf07863b97b3523b1b112844c43e713df8b66418a081fd1060b3b2` |

Model: official `tessdata_fast`, commit
`87416418657359cb625c412a48b6e1d6d41c29bd`; language kor, OEM 1, DPI 300.
PSM 11 is the positive path; PSM 3/4/6 are regression controls only.
No other engine/model/OEM/PSM/crop/preprocessing strategy was evaluated.

Fixed overlap candidates: 0.25/0.50/0.75; lowest passing synthetic-control
candidate selected: `SAME_CELL_OVERLAP_V1`, ratio `0.25`.
Fixed confidence candidates: 0/50/80/90/95; **none qualifies**.
Geometry/ordering/confidence policies were not relaxed to fit OCR output.

## Gate A matrix

Clear Gray and RGB each yield 40 words; two repetitions per format are identical
in words, bbox, hierarchy and confidence. Each grid is COMPLETE.
Original degraded Gray/RGB each yields zero words with grid COMPLETE:
`OperationalStatus=FAILED`, `OperationalCode=EMPTY_WORD_OUTPUT`,
`AcceptanceStatus=NOT_EVALUATED`, `ConfidenceEvidence=NOT_OBSERVED`.
These operational negatives have no confidence evaluations and do not determine
the confidence rejection verdict.

Exactly one additional fictional mild Gray fixture was fixed before OCR:
1600x900 DeviceGray, text-only GaussianBlur radius 0.6, no resize, original grid
drawn last. Its 28,097 grid pixels match clear Gray exactly. PDF SHA-256:
`a8679aa5450789cb706b15670036db02101a40e88349d8a2f917d9a593401945`.
Grid-mask SHA-256:
`b590dd27cfc812007744e443421cfcf2ec05e925d3d8f2637f0769f8643d917e`.
Mild produces 39 words, grid COMPLETE, confidence OBSERVED; no subsequent tuning.

| Threshold | Clear Gray/RGB per run | Clear low-confidence words | Mild Gray | Mild low-confidence words | Mild conflicts |
| ---: | --- | ---: | --- | ---: | ---: |
| 0 | COMPLETE / 2 rows | 0 | PARTIAL / 0 rows | 0 | 2 |
| 50 | PARTIAL / 0 rows | 1 | PARTIAL / 0 rows | 1 | 2 |
| 80 | PARTIAL / 0 rows | 3 | PARTIAL / 0 rows | 4 | 2 |
| 90 | PARTIAL / 0 rows | 6 | PARTIAL / 0 rows | 6 | 2 |
| 95 | PARTIAL / 0 rows | 26 | PARTIAL / 0 rows | 23 | 2 |

Clear/mild each records two SAFE_ADJACENT events per evaluation. Mild already has
two CONFLICTING events at threshold 0. Its incompleteness is therefore not
confidence-only. No fixed threshold both preserves required clear evidence and
separates mild by confidence alone. Gate A fails; Task 4/5 remain stopped.
Technical rows are fictional completeness controls, not verified benefit truth
or a proof of OCR correctness/business identity isolation.

## Safety regression evidence

Ratio 0.25 controls PASS: exact unique containment, cross-cell/outside/ambiguous
rejection, adjacent overlap, duplicate/conflict/order/transitive-bridge negatives.
Confidence does not rescue physical ambiguity.

| PSM | Words per Gray/RGB run | Containment failures per image | Result at all five thresholds |
| ---: | ---: | --- | --- |
| 3 | 73 | 5 ambiguous-cell failures; also 1 conflict | PARTIAL / 0 rows |
| 4 | 40 | 2 uncontained words | PARTIAL / 0 rows |
| 6 | 30 | 2 uncontained words | PARTIAL / 0 rows |

One complete fixed matrix uses 13 OCR invocations, 13 PDF opens, 13 image decodes,
13 grid builds and 55 threshold evaluations. The two empty-word runs contribute
no threshold evaluations. These counts do not prove resource/fault guarantees.

## Final verification and intentionally unexecuted gates

- Contract: PASS, including locked restore/build of the existing evaluation
  project, hierarchy/TSV/input/identity negatives and operational separation.
- OverlapPolicy: PASS for the fixed candidates; selected ratio remains 0.25.
- Acceptance: PASS assertions of the fixed matrix and explicit REJECTED stop.
  This does **not** mean Gate A acceptance PASS.
- Repository CI-equivalent `tools/data/test-*.ps1`: PASS (62 tests).
- Task 4: `NOT_RUN_GATE_A_FAILED` (business isolation, fault/resource/multipage).
- Task 5: `NOT_RUN_GATE_A_FAILED`; Windows/Ubuntu determinism: NOT_RUN.
- Safety / DeterminismContract / All: NOT_RUN; no missing gate implemented.
- Multipage: NOT_APPROVED; Android local: `NOT_RUN_EVALUATION_ONLY`.
- Historical P4-3A and protected production paths: diff 0.
- Plan-base `git diff --check`: PASS; dev-base check has only two inherited
  approved spec trailing-space warnings (lines 3/4), new warnings 0.

## Cleanup and remaining boundary

After the final fixed tests, repo-external
`C:/Users/PC/AppData/Local/Temp/milimap-p43a2-evaluation-20261005` is removed:
portable EXE/DLLs, installer extraction, model, preview/PNM and temporary OCR
outputs. Cleanup PASS: 61 files removed and the exact directory's absence was
verified. Hashes/results above are preserved before deletion. No installer,
EXE/DLL, traineddata or raw OCR output is committed. Existing unrelated SDK,
Python and extractor installations are retained; no system installation cleanup
is required because none occurred.

Product dependency: `NOT_APPROVED`; P4-3B: `BLOCKED`;
P4-3 / Phase 4: `NOT COMPLETE`; ProductionAction remains NONE.
Real-source OCR, two-business isolation, hard resource limits, fault handling,
multipage and cross-OS determinism remain unproven. Any alternative model,
engine, geometry policy, cell-crop or preprocessing needs a separately approved
OCR fallback redesign. No push/PR is performed for this local closeout.

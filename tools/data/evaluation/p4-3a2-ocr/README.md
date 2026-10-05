# P4-3A2 evaluation boundary

Evaluation only. Historical P4-3A remains REJECTED and is read-only. Reuse its
locked PdfPig 0.1.16 inspect/grid primitives; do not add a parser/product adapter.
No engine/model binaries are packaged. Product dependency is NOT_APPROVED;
P4-3B is BLOCKED, ProductionAction=NONE.

Task 1 supplies the A2 hierarchical TSV contract and exact runtime/model checks.
TSV preserves Page/Block/Paragraph/Line/Word without normalization/renumbering.
Malformed TSV or empty word output fails closed; no valid prefix escapes a
malformed TSV. Structurally valid whitespace-only ruled-line decoration is not
text; an output consisting only of decoration still fails EMPTY_WORD_OUTPUT.
Only one image input is accepted until the separately gated multipage task.

Run with the existing .NET 8 SDK on process-local PATH:
`pwsh -NoProfile -File tools/data/evaluation/p4-3a2-ocr/test-evaluation.ps1 -Group Contract`

External future OCR supply must be exact Tesseract v5.5.3.20260724/5.5.3,
official tessdata_fast/kor.traineddata SHA-256
`6b85e11d9bbf07863b97b3523b1b112844c43e713df8b66418a081fd1060b3b2`,
kor/OEM1/DPI300, PSM11 positive and PSM3/4/6 regressions only. No global PATH,
registry or installer execution is needed or authorized by this boundary.

Overlap candidates are exactly 0.25/0.50/0.75 and confidence 0/50/80/90/95.
Task 2 selected SAME_CELL_OVERLAP_V1 ratio 0.25 mechanically: all three bounded
ratios pass the fixed synthetic controls; lowest passing ratio wins. Exact
containment and duplicate/conflict/order/bridge rejection are unchanged.

## Task 3 bounded evaluation: P4_3A2_REJECTED

Task 3 resumed under explicit human approval to separate operational failure and
add exactly **one** mild Gray control. No fixture/config tuning followed OCR.
Human review confirmed final `P4_3A2_REJECTED`, reason
`GATE_A_CONFIDENCE_REJECTED`. Task 6 records rejection closeout only.
Task 4/5 are `NOT_RUN_GATE_A_FAILED`; resource/fault hardening, business isolation,
multipage and Windows/Ubuntu determinism remain NOT_RUN. Product dependency
remains NOT_APPROVED; P4-3B remains BLOCKED; Phase 4 is NOT COMPLETE.

Runtime: portable Tesseract `v5.5.3.20260724`, Leptonica 1.87.0, 55 root DLLs.
Installer SHA-256:
`bee9e3434bd94fd65387d9be28cd467a41f61b1275383b55b0f59a1331270ae4`.
EXE SHA-256:
`c66f0f12ed76f6aa455dac97684bbc86756d6a732380bee09122454cfda3f420`.
Model: official tessdata_fast commit `87416418657359cb625c412a48b6e1d6d41c29bd`,
kor.traineddata hash above. Language kor, OEM1, DPI300, PSM11 positive;
PSM3/4/6 regression only. Supply is repo-external, no installer execution,
registry/shortcut/system PATH changes or binary/model commitment.

Mild authoring was fixed before OCR: 1600x900 DeviceGray, text-only GaussianBlur
radius **0.6**, no resize; historical black grid topology/coordinates/width3
drawn last. Its 28,097 grid pixels are byte-identical to clear Gray.
Grid-mask SHA-256:
`b590dd27cfc812007744e443421cfcf2ec05e925d3d8f2637f0769f8643d917e`.
Mild PDF SHA-256:
`a8679aa5450789cb706b15670036db02101a40e88349d8a2f917d9a593401945`.
The manifest records independent fictional strings and byte/pixel hashes.
`generate-fixtures.py --check` verifies actual PDF/grid bytes and the fixed
three-file set (two retained old controls plus one mild). `--mild-only` refuses
to overwrite an already authored mild control. Pypdf/Pillow are existing
authoring/integrity tools, not product parsers/dependencies or OCR preprocessing.

Measured complete bounded matrix: 13 OCR invocations, 13 PDF opens, 13 image
decodes and 13 grid builds. Five thresholds share each run's OCR output; there
are **55 confidence evaluations**, not 65: the two failed old controls have none.
Repeated clear Gray/RGB word/bbox/hierarchy/confidence outputs match exactly.

| Control | Runs | Words/run | Grid | Operational | Acceptance | Confidence evidence |
| --- | ---: | ---: | --- | --- | --- | --- |
| Clear Gray PSM11 | 2 | 40 | COMPLETE | COMPLETE | EVALUATED | OBSERVED |
| Clear RGB PSM11 | 2 | 40 | COMPLETE | COMPLETE | EVALUATED | OBSERVED |
| Gray/RGB PSM3 | 1 each | 73 | COMPLETE | COMPLETE | EVALUATED | OBSERVED |
| Gray/RGB PSM4 | 1 each | 40 | COMPLETE | COMPLETE | EVALUATED | OBSERVED |
| Gray/RGB PSM6 | 1 each | 30 | COMPLETE | COMPLETE | EVALUATED | OBSERVED |
| Old degraded Gray/RGB PSM11 | 1 each | 0 | COMPLETE | FAILED: EMPTY_WORD_OUTPUT | NOT_EVALUATED | NOT_OBSERVED |
| Mild Gray PSM11 | 1 | 39 | COMPLETE | COMPLETE | EVALUATED | OBSERVED |

The old degraded operational failures are fail-closed negative evidence only.
They are **not** confidence rejection evidence and are excluded from the
threshold decision. Unknown operational errors likewise do not become
GATE_A_CONFIDENCE_REJECTED.

| Threshold | Clear Gray/RGB status/technical rows per run | Clear low-confidence count | Mild status/rows | Mild low-confidence count | Mild conflicts |
| ---: | --- | ---: | --- | ---: | ---: |
| 0 | COMPLETE / 2 | 0 | PARTIAL / 0 | 0 | 2 |
| 50 | PARTIAL / 0 | 1 | PARTIAL / 0 | 1 | 2 |
| 80 | PARTIAL / 0 | 3 | PARTIAL / 0 | 4 | 2 |
| 90 | PARTIAL / 0 | 6 | PARTIAL / 0 | 6 | 2 |
| 95 | PARTIAL / 0 | 26 | PARTIAL / 0 | 23 | 2 |

Clear/mild each have 2 SAFE_ADJACENT audit events per evaluation. Mild already
has 2 CONFLICTING events at threshold0, so its failure is never confidence-only.
PSM3 retains 5 ambiguous-cell containment failures and 1 conflict per image;
PSM4/6 retain 2 uncontained words per image. All fixed thresholds remain PARTIAL,
usable rows0. Confidence cannot rescue those physical failures.

Selected confidence threshold: **none**.
Reason: `GATE_A_CONFIDENCE_REJECTED` from the word-producing mild control:
no candidate both preserves required clear evidence and separates mild solely
by confidence. It is not derived from the old EMPTY_WORD_OUTPUT controls.
The required fixed threshold is absent; Task 3 cannot authorize Task 4.
No classifier, geometry tolerance, engine/model/PSM/OEM or threshold was changed.
Technical rows are completeness probes, not verified OCR correctness, production
claims, identity lookup/isolation proof, or real-world benefit truth.

Commands (existing .NET SDK on process-local PATH; absolute evaluation runtime):

```powershell
pwsh -NoProfile -File tools/data/evaluation/p4-3a2-ocr/test-evaluation.ps1 -Group Contract
pwsh -NoProfile -File tools/data/evaluation/p4-3a2-ocr/test-evaluation.ps1 -Group OverlapPolicy
pwsh -NoProfile -File tools/data/evaluation/p4-3a2-ocr/test-evaluation.ps1 -Group Acceptance -TesseractExecutable <absolute-exe> -KoreanModelPath <absolute-model> -FixturePythonExecutable <existing-python>
```

Acceptance test PASS means the observed result and stop conditions are recorded
correctly; it **does not mean the OCR acceptance gate passed**. No Group All or
later-gate placeholder is made GREEN. Current process output limits are post-read,
not a portable hard-memory ceiling. Final closeout runs only Contract,
OverlapPolicy, Acceptance, locked restore/build and the repository data suite.
Safety, DeterminismContract and All are not run because Gate A failed;
Android local is `NOT_RUN_EVALUATION_ONLY`. No missing later gate is implemented
to manufacture a passing All result.

Repo-external evaluation runtime/model/installer extraction and temporary OCR
outputs are removed after final verification; hashes and aggregate results are
preserved in the [rejection handover](../../../../docs/handover/2026-10-05-phase4-p4-3a2-overlap-safety-evaluation.md).

Task diff-check is measured against the approved plan HEAD; inherited approved
spec lines3/4 contain trailing Markdown hard-break spaces relative to origin/dev.
Those two warnings are unchanged and were not fixed by this evaluation task.

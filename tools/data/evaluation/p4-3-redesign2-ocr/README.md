# P4-3 Redesign 2 evaluation boundary

Evaluation only; historical P4-3A and P4-3A2 remain rejected and read-only.
Product dependency NOT_APPROVED; P4-3B BLOCKED; ProductionAction NONE.

Task 1 delegates single-page runtime handling to the unchanged A2 wrapper, not
its acceptance harness. New identity: MILIMAP_P4_3_REDESIGN2_OCR_EVAL / schema1,
STRUCTURAL_TRUST_V1, DIAGNOSTIC_ONLY_V1. Raw TSV word text, hierarchy, bbox and
confidence remain unchanged. Confidence has no completeness authority and the
new public interface has no threshold or candidate-search parameter/field.

Exact supply: Windows Tesseract v5.5.3.20260724 / 5.5.3, Korean tessdata_fast
commit 87416418657359cb625c412a48b6e1d6d41c29bd, model SHA-256
6b85e11d9bbf07863b97b3523b1b112844c43e713df8b66418a081fd1060b3b2;
kor/OEM1/DPI300; PSM11 positive, PSM3/4/6 regression only.
Installer SHA-256: bee9e3434bd94fd65387d9be28cd467a41f61b1275383b55b0f59a1331270ae4.
EXE SHA-256: c66f0f12ed76f6aa455dac97684bbc86756d6a732380bee09122454cfda3f420.
Portable runtime extracted outside Git using existing 7-Zip, no installer
execution/registry/shortcut/persistent PATH changes. No binaries/models packaged.

Contract command: `pwsh -NoProfile -File tools/data/evaluation/p4-3-redesign2-ocr/test-evaluation.ps1 -Group Contract -KoreanModelPath <absolute-official-model>`.
Contract process responses are controlled; real model hash/identity/TSV parser
and mapping execute. It is not a claim of actual OCR quality.
Task 3+ require the separate human gate after Task 2. All is not implemented.

## Task 2: GATE_A_PASS — human review stop

Structural authority only: exact unique cell membership, fixed
SAME_CELL_OVERLAP_V1 / 0.25, deterministic reconstruction and all 12 proven
3x4 cells populated. Raw confidence is retained in Words/AcceptedWords and
RawConfidence, not consulted for completeness. No threshold or matrix exists.
Only physical/coverage diagnostics block evidence; unsafe observations expose
no accepted words/cell text/usable rows.

| Retained control | Words per run | Structural result | Usable technical rows |
| --- | ---: | --- | ---: |
| Clear Gray PSM11, twice | 40 | COMPLETE | 2 |
| Clear RGB PSM11, twice | 40 | COMPLETE | 2 |
| Mild Gray PSM11 | 39 | PARTIAL: CONFLICTING x2 | 0 |
| Gray/RGB PSM3 | 73 each | PARTIAL: containment x5, conflict x1 | 0 |
| Gray/RGB PSM4 | 40 each | PARTIAL: containment x2 | 0 |
| Gray/RGB PSM6 | 30 each | PARTIAL: containment x2 | 0 |
| Old degraded Gray/RGB PSM11 | 0 each | FAILED / EMPTY_WORD_OUTPUT; NOT_EVALUATED | 0 |

Clear repetitions match raw words/bbox/hierarchy/confidence, physical cells,
reconstructed text and diagnostics. Clear raw confidence range is 22.024605..97.019066:
one required header-cell word per run (`구수`, cell2, bbox417/119/60/14) remains
accepted by exact structural provenance. This is not a claim that the OCR text
matches the authored Korean header: spelling/content correctness is unproven.
The technical coverage gate means all physical cells contain reconstructed
text, not production header interpretation or business binding.

Fixed synthetic negatives reject cross-cell, duplicate, conflict, order reversal,
transitive line bridge and missing required coverage. Confidence 1 on a valid
required word remains COMPLETE; high-confidence conflicts remain PARTIAL.
Single complete matrix: 13 OCR calls, each with one PDF open/decode/grid build;
no new fixture, tuning, engine/model/config/ratio or confidence policy search.

Run StructuralTrust with the existing .NET SDK on process-local PATH and exact
portable supply:
`pwsh -NoProfile -File tools/data/evaluation/p4-3-redesign2-ocr/test-evaluation.ps1 -Group StructuralTrust -TesseractExecutable <absolute-exe> -KoreanModelPath <absolute-model>`.

Task 3 isolation, Task 4 operations/multipage, Task 5 Windows/Ubuntu determinism
and Task 6 final approval/closeout are NOT_RUN. GATE_A_PASS is not a full technical
approval, dependency approval or Phase 4 completion. Runtime/model stay outside
Git pending human review and later approved tasks; final cleanup is not claimed.

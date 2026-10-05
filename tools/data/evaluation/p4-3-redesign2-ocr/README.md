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
Portable runtime extracted outside Git using existing 7-Zip, no installer
execution/registry/shortcut/persistent PATH changes. No binaries/models packaged.

Contract command: `pwsh -NoProfile -File tools/data/evaluation/p4-3-redesign2-ocr/test-evaluation.ps1 -Group Contract -KoreanModelPath <absolute-official-model>`.
Contract process responses are controlled; real model hash/identity/TSV parser
and mapping execute. It is not a claim of actual OCR quality. Gate A is NOT_RUN.
Task 3+ require the separate human gate after Task 2. All is not implemented.

# P4-3A2 evaluation boundary

Evaluation only. Historical P4-3A remains REJECTED and is read-only. Reuse its
locked PdfPig 0.1.16 inspect/grid primitives; do not add a parser/product adapter.
No engine/model binaries are packaged. Product dependency is NOT_APPROVED;
P4-3B is BLOCKED, ProductionAction=NONE.

Task 1 supplies the A2 hierarchical TSV contract and exact runtime/model checks.
TSV preserves Page/Block/Paragraph/Line/Word without normalization/renumbering.
Malformed or empty words fail closed; no valid prefix escapes a malformed TSV.
Only one image input is accepted until the separately gated multipage task.

Run with the existing .NET 8 SDK on process-local PATH:
`pwsh -NoProfile -File tools/data/evaluation/p4-3a2-ocr/test-evaluation.ps1 -Group Contract`

External future OCR supply must be exact Tesseract v5.5.3.20260724/5.5.3,
official tessdata_fast/kor.traineddata SHA-256
`6b85e11d9bbf07863b97b3523b1b112844c43e713df8b66418a081fd1060b3b2`,
kor/OEM1/DPI300, PSM11 positive and PSM3/4/6 regressions only. No global PATH,
registry or installer execution is needed or authorized by this boundary.

Overlap candidates are exactly 0.25/0.50/0.75 and confidence 0/50/80/90/95.
Classifier, real acceptance, resource/fault hardening, multipage and determinism
are not yet implemented/approved. Current process output limits are post-read,
not a claimed streaming memory ceiling. Contract PASS is not Gate A acceptance.

# P4-3A OCR technical evaluation

Evaluation-only .NET 8 helper with exact locked PdfPig 0.1.16 (Apache-2.0).
No product project reference, production adapter, OCR dependency packaging,
canonical mutation, or semantic lifecycle inference is authorized here.
Tesseract 5.5.3 and an official Korean model must be externally supplied;
the wrapper rejects engine/model identity mismatches before OCR.

Run `pwsh -NoProfile -File test-evaluation.ps1 -Group Contract` with .NET 8 on PATH.
Current stage: Task 1 contract; image/grid/OCR stages are not yet implemented.
No approval verdict is inferred from contract tests.

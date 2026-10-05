# P4-3A OCR technical evaluation

Evaluation-only .NET 8 helper with exact locked PdfPig 0.1.16 (Apache-2.0).
No product project reference, production adapter, OCR dependency packaging,
canonical mutation, or semantic lifecycle inference is authorized here.
Tesseract 5.5.3 and an official Korean model must be externally supplied;
the wrapper rejects engine/model identity mismatches before OCR.

Run `pwsh -NoProfile -File test-evaluation.ps1 -Group Contract` with .NET 8 on PATH.
Image handoff: a single PdfDocument open and one page materialization; the same
page objects are used for native inspection and image decoding. Only full-page,
axis-aligned, unmasked 8-bit DeviceGray/RGB Flate pixels are accepted. Synthetic
coverage tolerance is zero. Other image shapes fail closed. Original PDF hash,
page/image placement and independent decoded PNM hashes bind the handoff.
Current stage: Tasks 1–2; grid/OCR stages are not yet implemented.
No approval verdict is inferred from contract tests.

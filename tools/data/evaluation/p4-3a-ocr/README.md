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
Final technical verdict: P4-3A = REJECTED. Windows portable supply and real Korean
TSV execution succeeded, but all 80 clear Gray/RGB threshold evaluations were
PARTIAL under unchanged exact-containment / overlapping-word rejection. The
evaluation-only grid/TSV harness is retained; it emits no production PDF_ROW.
Task 4/5 are NOT_RUN_CORE_ACCEPTANCE_GATE_FAILED, not implemented or passed.
Safety/All explicitly reject execution instead of silently reporting success.
Run Contract, ImageEligibility, and GridOcr separately; GridOcr requires external
engine/model paths and checks mechanics, not usable-positive acceptance. The
historical matrix and cleanup evidence are in the P4-3A handover. Product OCR
dependency is NOT_APPROVED; P4-3B is BLOCKED. No approval follows from test PASS.

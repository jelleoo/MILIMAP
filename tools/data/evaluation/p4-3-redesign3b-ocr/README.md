# P4-3 Redesign 3B model supply and best batch boundary

Evaluation-only Task 1 proves the candidate model and unchanged Redesign 3A
runtime. Task 2 adds the best-model batch boundary. Tests perform real version
probes and intercept quality execution; actual quality OCR remains unrun.
`ProductionAction=NONE`, product dependency `NOT_APPROVED`, P4-3B `BLOCKED`.

The candidate is `tesseract-ocr/tessdata_best`, annotated tag `4.1.0`, tag object
`f0c187c74d3038e6d135fd080e30909af350eae0` (verification `valid`), commit
`e2aad9b983032bb1beff9133104a67cdbb87ca4d`, tree
`23d6207aa77e8f11abd8b300e12d2d94df300fb6`, Apache-2.0.
`kor.traineddata` must contain exactly 12528128 bytes and Git blob
`c82615b5228c9981c33a0985b32224d97b7fb43a`.
The source tag/signature evidence was verified during controller supply preflight;
the offline harness independently checks the pinned blob bytes, then calculates
and freezes SHA256. The actual supplied candidate SHA256 is
`f888d4038348a0c3d25151e7f452bda0d74ca275b18cab146798bcbb94084fff`.
Caller-provided SHA256 never establishes authority.

Gate A additionally checks exact runtime EXE/DLL hashes and version
`tesseract v5.5.3.20260724`, engine 5.5.3. Only its exact returned `Descriptor`
object gains process-local authority. `Get-P43R3bModelDescriptor` alone does not
authorize OCR. `Assert-P43R3bModelAuthority -Descriptor ... -Executable ...
-ModelPath ...` rejects copied, authored, changed or spoofed descriptors, changed
model bytes, different paths, and changed runtime bytes before any later OCR.
The private module keeps reference proofs in a ConditionalWeakTable; no
registration API is exported. Reloading the supply module invalidates old proofs.

```powershell
pwsh -NoProfile -File tools/data/evaluation/p4-3-redesign3b-ocr/test-evaluation.ps1 -Group ModelSupply
pwsh -NoProfile -File tools/data/evaluation/p4-3-redesign3b-ocr/test-evaluation.ps1 -Group ModelSupply -TesseractExecutable <absolute-exe> -KoreanModelPath <absolute-kor.traineddata>
```

The first command checks synthetic failure controls and explicitly reports real
authority `NOT_RUN_NO_SUPPLY`. The second uses real supplied bytes, verifies Gate
A, and checks authority forgery and tampering without quality OCR. Runtime/model
downloads and test scratch stay outside Git. No install, registry or PATH change
is needed.

`Invoke-P43R3bTesseractBatch -Executable <string> -ModelDescriptor <object>
-Crops <object[]> -Psm <6|11>` accepts only the exact descriptor issued by a
successful Gate A in this process. Load `invoke-tesseract-best-batch.ps1`, then
obtain Gate A and pass its `Descriptor`. Loading the batch script again preserves
existing supply authority. The optional `ModelPath` in
`Assert-P43R3bModelAuthority` resolves only from its private reference proof;
its returned runtime includes that validated path. Explicit paths remain checked.

The boundary revalidates the model SHA256, pinned Git blob and runtime bytes
before every batch. It uses the historical 3A PNM validator, TSV parser and bounded
process runner read-only; the 3A fast-model public batch is never called. Crops
must map to ordinals `1..N` for `1 <= N <= 12`. Exactly one quality invocation
uses `-l kor --oem 1 --psm <6|11> --dpi 300 -c tessedit_create_tsv=1` and a
10-second deadline. No retry, per-cell fallback, expected text, or fast model
enters the invocation. Invalid mapping, empty required pages, malformed TSV,
timeout, nonzero exit and output limits fail closed with no published pages/words.
Image-list scratch is removed on success and failure. Return fields remain the
3A batch shape, including `InvocationCount` and `ProductionAction=NONE`.

The review finding for bounded glue duplication is
`APPROVED_BY_DESIGN_CONSTRAINT` by the human. Crop identity validation, image-list
ordering/lifecycle and page-to-ordinal-to-CellId mapping exist only inside the
frozen 3A fast-model public wrapper; no model-independent orchestration helper is
available. This evaluation boundary retains only that bounded glue, with parity
assertions for ordering, mapping, failure publication and cleanup. The 3A PNM
validator, TSV parser and process runner remain shared read-only. This acceptance
does not authorize historical refactoring, new abstractions, production OCR or
generalization beyond the approved evaluation interface.

```powershell
pwsh -NoProfile -File tools/data/evaluation/p4-3-redesign3b-ocr/test-evaluation.ps1 -Group BestBatch
pwsh -NoProfile -File tools/data/evaluation/p4-3-redesign3b-ocr/test-evaluation.ps1 -Group BestBatch -TesseractExecutable <absolute-exe> -KoreanModelPath <absolute-kor.traineddata>
```

The first command proves no-supply API/authority rejection and reports the real
authority matrix `NOT_RUN_NO_SUPPLY`. The second obtains real Gate A authority
for a temporary model copy and exercises 1/2/12-page PSM6/11 success cases and
fail-closed process controls using a synthetic process seam. Its 17 intercepted
batch calls are not actual quality OCR. Supplied original bytes remain unchanged.
Synthetic PASS does not establish real OCR mapping or text-fidelity acceptance.

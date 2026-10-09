# P4-3 Redesign 3B model supply

Evaluation-only Task 1 proves the candidate model and unchanged Redesign 3A
runtime. It performs version probes only; quality OCR remains unrun.
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

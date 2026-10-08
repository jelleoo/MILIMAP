# P4-3 Redesign 3A evaluation

Evaluation-only proven-cell crop preparation (`PROVEN_CELL_CROP_V1`). Historical
P4-3A inspection/grid helpers and committed fixtures are consumed read-only.
Product dependency remains `NOT_APPROVED`; P4-3B remains `BLOCKED`;
`ProductionAction=NONE`. Gate A never invokes OCR; Task 2 adds Gate B batch mapping.

Build the retained helper with its locked dependencies, then run:

```powershell
dotnet restore tools/data/evaluation/p4-3a-ocr/Milimap.P4_3A.OcrEval.csproj --locked-mode
dotnet build tools/data/evaluation/p4-3a-ocr/Milimap.P4_3A.OcrEval.csproj -c Release --no-restore
pwsh -NoProfile -File tools/data/evaluation/p4-3-redesign3a-ocr/test-evaluation.ps1 -Group CropProvenance
```

Dot-source `run-evaluation.ps1`; call `Prepare-P43R3aFixture -PdfPath ...
-ArtifactDirectory ...` with a fresh temporary directory, then
`Invoke-P43R3aGateA -PreparedFixture $prepared`. Preparation performs one inspect,
one grid build, and one 12-crop build. Keep the returned preparation in the same
PowerShell session: Gate A requires its process-local helper authority and
revalidates source/crop bytes against an independent preparation snapshot.
Caller-authored or copied preparation objects fail closed.

PNM inputs accept only exact LF headers `P5|P6\n<width> <height>\n255\n`
and exact bounded raw byte lengths. Crops copy top-origin rows for
`[X0,X1) x [Y0,Y1)` without moving helper coordinates or changing pixels.
All 12 unique IDs and their proven 3x4 row/column positions are required.
Filenames and input order derive from numeric CellId/ordinal only. The low-level
crop-set function validates supplied metadata; it does not grant helper authority.
Existing output files are never overwritten.

Gate A clear Gray/RGB tests check original fixture/pixel hashes, identical repeat
crop hashes, 12 crops, and PDF open/page read/decode/grid/crop build counts of one.
Synthetic byte controls prove orientation and exclusive ends; negative controls
cover invalid coordinates, count/identity collisions, source hash and preparation
tampering. Artifacts stay temporary; no new fixture/dependency is introduced.
Fidelity, consensus and the final technical verdict remain later tasks.
Gate A failure blocks later evaluation.

Measured Task 1 (2026-10-09): Gray and RGB each
`GATE_A_CROP_PROVENANCE_PASS`, 12 deterministic crops, all five preparation
counts 1, OCR invocations 0. `CropProvenance` and historical `ImageEligibility`
pass; historical/protected diff is zero. This is Gate A evidence only.

Gate B requires the same helper-minted preparation and revalidates Gate A before
OCR. Dot-source the runner and call `Invoke-P43R3aGateB -PreparedFixture $prepared
-Executable <absolute-exe> -ModelPath <absolute-kor.traineddata>`. Each PSM uses
one temporary UTF-8 image list in exact crop ordinal order and one OCR process:
`-l kor --oem 1 --psm 6|11 --dpi 300 -c tessedit_create_tsv=1`. The exact retained
EXE, libtesseract, Leptonica and official Korean model hashes are mandatory,
along with `tesseract v5.5.3.20260724` / engine version `5.5.3`.

`ConvertFrom-P43R3aBatchTsv` validates one level-1 page for each ordinal 1..N,
hierarchy/parent records, finite confidence, positive bounded boxes and word
output for every required page. Batch results preserve word hierarchy, geometry,
confidence and text, adding `CropOrdinal` and `CellId` to every page/word.
Confidence is diagnostic only, including zero. No threshold, winner selection,
page repair or per-cell retry exists. Missing/duplicate/extra pages, empty required
pages, supply mismatch, 10-second OCR timeout, nonzero exit or bounded-output
failure publish no pages/words. Stdout is capped at 1 MiB and stderr at 64 KiB;
version checks have a 3-second deadline. Temporary list scratch is cleaned in all
paths. No raw OCR words or runtime/model binaries are committed.

Focused synthetic controls use a process seam, with real identity/hash checks:

```powershell
pwsh -NoProfile -File tools/data/evaluation/p4-3-redesign3a-ocr/test-evaluation.ps1 -Group BatchMapping -Executable <absolute-exe> -ModelPath <absolute-kor.traineddata>
```

Add `-RunRealGateB` only when an actual Gray Gate B pair is authorized. It prepares
Gray once and runs one PSM6 plus one PSM11 batch. Without the switch, output
explicitly reports synthetic PASS and real Gate B NOT_RUN; synthetic success does
not establish real-runtime mapping. Supply failure means NOT_EVALUATED; an actual
batch/mapping failure means `P4_3_REDESIGN3A_REJECTED /
GATE_B_BATCH_MAPPING_FAILED` and later gates stop.

Measured Task 2 (2026-10-09): exact Gray `GATE_B_BATCH_MAPPING_PASS`; all five
preparation counts 1; PSM6 1 invocation / 12 pages / 41 words (197 ms), PSM11
1 invocation / 12 pages / 40 words (217 ms). Both map page/ordinal/CellId exactly
1..12, with word output on every page. This proves mapping only, not text fidelity
or consensus. First failing gate: none among reached Gates A/B; later gates unrun.

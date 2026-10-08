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
Task 3 adds crop-local fidelity; consensus and the final technical verdict remain
unreached after the measured Gate C failure below.
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

Gate C reconstructs each mapped crop locally using retained `SAME_CELL_OVERLAP_V1`
semantics: fixed same-region area ratio 0.25, duplicate/conflicting boxes and
unsafe hierarchy order fail closed, and each physical vertical component must
be a clique (a transitive line bridge is unsafe). Deterministic spatial ordering
joins words with one space and lines with LF. Raw confidence, including 1, remains
diagnostic. No expected text enters OCR, overlap classification or reconstruction.

Ground truth asserts the unchanged historical clear generator blob
`6231ed473349063ce3b0d12fc7b2cff0bef1d114`, clear manifest blob
`cde2a581ec2c4a1fb26481992908b5dcab2740ac`, A2 manifest blob
`ede9c602fbea2ae5a76e7dcfdc067f242c1929b7`, and all five historical PDF SHA256
identities. A2 `expectedRows` are read only after these checks. Clear authored
literals match all three A2 authored tables. `TEXT_FIDELITY_NORMALIZATION_V1`
replaces CRLF with LF, trims outer whitespace, and folds `[\p{Zs}\t]+` into one
space. It preserves internal line breaks, Korean decomposition, digits,
punctuation and character substitutions. Each PSM independently requires all
4 headers, 2 business names and 2 benefits (8/8); all-cell /12 is diagnostic.
An unsafe cell is `FIDELITY_NOT_EVALUATED`, never an exact-text match.

```powershell
pwsh -NoProfile -File tools/data/evaluation/p4-3-redesign3a-ocr/test-evaluation.ps1 -Group ClearFidelity
```

This runs synthetic reconstruction, historical authority, fidelity, fixed-matrix
and fail-closed controls with zero quality OCR calls. An authorized actual clear
measurement adds `-RunRealGateC -Executable <absolute-exe> -ModelPath
<absolute-kor.traineddata>`. It prepares Gray/RGB once each and retains those
12-crop sets for PSM6 twice and PSM11 twice: exactly 8 quality OCR processes.
Mapped words, text, fidelity and diagnostics must repeat identically, excluding
elapsed time. A successful executable assertion verifies the measured gate
decision; it does not claim actual quality acceptance when the gate fails.

Measured Task 3 (2026-10-09): `P4_3_REDESIGN3A_REJECTED /
GATE_C_CLEAR_FIDELITY_FAILED`. Each batch mapped all 12 pages. There were exactly
8 quality calls; Gray and RGB each had PDF open/page read/decode/grid/crop build
counts `1/1/1/1/1`. Every fixture/PSM pair had identical repeated mapped words,
reconstructed text, fidelity state and diagnostics. No normalization expansion,
parameter tuning, additional quality rerun or Task 4 quality evaluation followed.

| Fixture | PSM | Repeat 1 mandatory / all | Repeat 2 mandatory / all | Words per batch | Elapsed ms (1, 2) |
| --- | --- | --- | --- | --- | --- |
| Gray | 6 | 5/8 / 7/12 | 5/8 / 7/12 | 41 | 208, 203 |
| Gray | 11 | 6/8 / 8/12 | 6/8 / 8/12 | 40 | 201, 216 |
| RGB | 6 | 5/8 / 7/12 | 5/8 / 7/12 | 41 | 249, 233 |
| RGB | 11 | 6/8 / 8/12 | 6/8 / 8/12 | 40 | 248, 250 |

Every nonmatching cell is listed below. Rows apply identically to **both Gray and
RGB and both repetitions**, so they cover all 36 nonmatch observations. Literal
`\n` denotes an internal LF. `NOT_EVALUATED` means reconstruction was PARTIAL;
the other rows are `FIDELITY_MISMATCH` from COMPLETE reconstruction.

| PSM | Cell / role | Fidelity state | Expected | Reconstructed |
| --- | --- | --- | --- | --- |
| 6 | 2 / HEADER | NOT_EVALUATED | 주소 | 주소 즈 |
| 6 | 3 / HEADER | MISMATCH | 전화번호 | 전 화 번 호 |
| 6 | 6 / AUXILIARY | MISMATCH | 가상시 가람로 12 | 가 상 시 가 람 로 12 |
| 6 | 9 / BUSINESS_NAME | NOT_EVALUATED | 가상 누리 식당 | 가스 \| 상 누리 식당 |
| 6 | 10 / AUXILIARY | MISMATCH | 가상시 누리로 23 | 가 상 시 누 리 로 23 |
| 11 | 2 / HEADER | MISMATCH | 주소 | 즈 ㅅ\n구수 |
| 11 | 3 / HEADER | MISMATCH | 전화번호 | 전 화 번 호 |
| 11 | 6 / AUXILIARY | MISMATCH | 가상시 가람로 12 | 가 상 시 가 람 로 12 |
| 11 | 10 / AUXILIARY | MISMATCH | 가상시 누리로 23 | 가 상 시 누 리 로 23 |

Mandatory mismatches and mandatory NOT_EVALUATED disqualify the candidate.
Synthetic controls and the measured-decision assertions PASS; the actual Gate C
is FAILED. First failing reached gate is C; Task 4 remains BLOCKED and
Gate D is `NOT_RUN_GATE_C_FAILED`.
Product dependency remains NOT_APPROVED, P4-3B BLOCKED, ProductionAction NONE.

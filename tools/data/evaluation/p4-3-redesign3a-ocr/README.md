# P4-3 Redesign 3A evaluation

Evaluation-only proven-cell crop preparation (`PROVEN_CELL_CROP_V1`). Historical
P4-3A inspection/grid helpers and committed fixtures are consumed read-only.
Product dependency remains `NOT_APPROVED`; P4-3B remains `BLOCKED`;
`ProductionAction=NONE`. Task 1 implements Gate A only and never invokes OCR.

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
Later batch mapping, fidelity, consensus and final technical verdict are outside
Task 1. Gate A failure blocks later evaluation.

Measured Task 1 (2026-10-09): Gray and RGB each
`GATE_A_CROP_PROVENANCE_PASS`, 12 deterministic crops, all five preparation
counts 1, OCR invocations 0. `CropProvenance` and historical `ImageEligibility`
pass; historical/protected diff is zero. This is Gate A evidence only.

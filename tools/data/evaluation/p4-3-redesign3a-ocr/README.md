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
Task 3 adds crop-local fidelity; the final verdict is rejection at Gate C.
Consensus remains unreached after that measured failure.
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

## Task 5 final reached verification (2026-10-09)

Final first-cycle verdict: `P4_3_REDESIGN3A_REJECTED`, first failing reached gate
`GATE_C_CLEAR_FIDELITY_FAILED`. `HUMAN_REVIEW_STOP` applies. Task 4 never started;
the final verification repeats only reached A/B/C and asserts blocked D. Executable
and synthetic assertions PASS describes verification correctness, not candidate
acceptance. No tuning or rescue experiment followed.

Branch: `codex/phase4-p4-3-redesign3a-cell-crop-consensus`.
Worktree: `C:/Users/PC/AndroidStudioProjects/MILIMAP/.worktrees/phase4-p4-3-redesign3a-ocr`.
Clean code HEAD at final measurement:
`c0d19e5e2f84f306b36368e485a22d6fd47a4083`. Initial result-recording commit
`af5bd94` changed documentation only. The later review reporting fix described
below has separate no-OCR checks; actual OCR and 62-test measurements belong to
the original clean code HEAD, not the subsequent reporting fix.
Task commits: 1 `befbd07`, 2 `24d1885`, 3 `5561a1b` plus fix `d3dfea7`,
4 `NOT_RUN_GATE_C_FAILED`, 5 verification wrapper `c0d19e5` plus this result record.

Exact identities were rechecked before final verification:

| Artifact | SHA256 |
| --- | --- |
| Retained installer | `bee9e3434bd94fd65387d9be28cd467a41f61b1275383b55b0f59a1331270ae4` |
| tesseract.exe | `c66f0f12ed76f6aa455dac97684bbc86756d6a732380bee09122454cfda3f420` |
| libtesseract-5.dll | `54d54528b453ce3a5ba79487687f8df43e7b194b9ea97beba74200453fe1fb46` |
| libleptonica-6.dll | `1869b44e3d46fd830620b042477e5d60a950779582f38f60291547efb27792f1` |
| official tessdata_fast/kor.traineddata | `6b85e11d9bbf07863b97b3523b1b112844c43e713df8b66418a081fd1060b3b2` |

Runtime observed `tesseract v5.5.3.20260724`, engine 5.5.3 / Leptonica 1.87.0.
Model source commit is `87416418657359cb625c412a48b6e1d6d41c29bd`.
Fixed language `kor`, OEM 1, PSM 6/11, DPI 300, overlap ratio 0.25,
`DIAGNOSTIC_ONLY_V1` and `TEXT_FIDELITY_NORMALIZATION_V1` remain unchanged.
Executable came from the dedicated supply's `runtime/tesseract.exe`; model came
from sibling `tessdata/kor.traineddata`, not `runtime/tessdata`.

```powershell
pwsh -NoProfile -File tools/data/evaluation/p4-3-redesign3a-ocr/test-evaluation.ps1 -Group AllReached -TesseractExecutable <absolute-exe> -KoreanModelPath <absolute-kor.traineddata>
```

`AllReached` is a reached-rejection verification interface, not a Task 4 runner.
It prepares clear Gray/RGB once each, validates Gate A, runs the Gray Gate B pair,
then passes the same original preparations/crops into Gate C. Earlier authority
or mapping failure blocks the clear matrix. It never invokes consensus or later
gates. The approved CLI names are aliases of the existing Executable/ModelPath.

Final actual Gate A: Gray/RGB `GATE_A_CROP_PROVENANCE_PASS`.
Final actual Gate B: `GATE_B_BATCH_MAPPING_PASS`; Gray PSM6/11 each one invocation,
12 pages exactly mapped page/ordinal/CellId 1..12, words 41/40, elapsed 193/206 ms.
Final actual Gate C: `GATE_C_CLEAR_FIDELITY_FAILED`:

| Fixture | PSM | Repeat 1 mandatory / all | Repeat 2 mandatory / all | Words per batch | Final verification elapsed ms (1, 2) |
| --- | --- | --- | --- | --- | --- |
| Gray | 6 | 5/8 / 7/12 | 5/8 / 7/12 | 41 | 204, 190 |
| Gray | 11 | 6/8 / 8/12 | 6/8 / 8/12 | 40 | 206, 205 |
| RGB | 6 | 5/8 / 7/12 | 5/8 / 7/12 | 41 | 237, 238 |
| RGB | 11 | 6/8 / 8/12 | 6/8 / 8/12 | 40 | 237, 253 |

All eight batches are COMPLETE for mapping. Every fixture/PSM repetition has
identical mapped words, reconstructed text, fidelity and diagnostics. All 36
nonmatch observations, including every mandatory mismatch/NOT_EVALUATED, exactly
repeat the preceding cell table; normalized expected/actual equal those literal
values (LF preserved). PSM6 per run: mandatory 5 matches, 1 mismatch, 2 not evaluated;
all cells 7 matches, 3 mismatches, 2 not evaluated. PSM11 per run: mandatory 6 matches,
2 mismatches; all cells 8 matches, 4 mismatches. High confidence cannot rescue
cell 3 `전화번호` -> `전 화 번 호` in both PSMs. Cell 2 has different reconstructed
text and PSM6 is untrusted; cell 9 is PSM6 untrusted while PSM11 matches authored
text. These are Gate C diagnostic observations, not evaluated consensus states.

Gate D clear consensus, mild-degraded safety and original degraded Gray/RGB:
`NOT_RUN_GATE_C_FAILED`. Per-cell `CELL_DISAGREEMENT` / `FALSE_CONSENSUS` classifications
are `NOT_EVALUATED`; no Gate D PASS or safe-consensus claim exists. Whether cropping
recovers the historical empty degraded output is UNKNOWN because degraded OCR
was not run. Gates E-H and Windows/Ubuntu semantic determinism remain
`NOT_RUN_GATE_C_FAILED`, with no business lookup OCR path implemented.

Efficiency counts distinguish original measurement from authorized final verification:

| Actual OCR processes | First measurement (Tasks 2/3) | Task 5 final verification | Overall cycle |
| --- | --- | --- | --- |
| Gray mapping pair (B) | 2 | 2 | 4 |
| Clear Gray/RGB quality matrix (C) | 8 | 8 | 16 |
| Mild/original degraded safety (D) | 0 | 0 | 0 |
| Total OCR | 10 | 10 | 20 |

The clear target is exactly 8 **per matrix**; overall clear 16 includes the
separately authorized final verification. Task 5 has no duplicate actual clear
matrix outside AllReached. Each final Gray/RGB preparation has PDF open/page read/
decode/grid/crop-build `1/1/1/1/1`, 12 crops; the same Gray crops serve B and C.
Separate CropProvenance controls create their own preparations with zero OCR.
Synthetic process seams launch zero actual OCR. Bounded version probes are identity
checks, not OCR: 10 probes accompany the 10 final OCR batches, plus one standalone
`--version` recheck. No per-cell OCR fallback or per-business OCR exists.

Verification at the clean measured code HEAD:

- Historical helper `dotnet restore --locked-mode` and Release build `--no-restore`
  PASS, zero warnings/errors; shared SDK used through process-local PATH.
- Historical P4-3A / P4-3A2 / Redesign 2 `-Group Contract` PASS. Initial Redesign 2
  invocation omitted its required model path and failed that prerequisite; corrected
  exact-model invocation PASS, no actual OCR and no historical edits.
- CropProvenance, BatchMapping synthetic, ClearFidelity synthetic and actual
  AllReached verification PASS; actual C acceptance FAILED.
- Current sorted `tools/data/test-*.ps1` suite run once with failure propagation:
  **62/62 PASS**. Complete commands/output retained in ignored task-5-report.md.
- `git diff --check` PASS; historical A/A2/Redesign2 and protected pdf-native/lib/
  canonical/seed/apps diff and untracked counts all zero against origin/dev.

Not run: ConsensusSafety/Task 4 and degraded OCR (Gate C failure); later Gates E-H,
product business isolation, multipage and Windows/Ubuntu semantic validation;
Android `NOT_RUN_EVALUATION_ONLY` because product/protected paths did not change;
CI, push, PR and merge. No preprocessing, additional engine/model or parameter search.

Cleanup completed after evidence preservation: exact dedicated directory
`C:/Users/PC/AppData/Local/Temp/milimap-p43r3a-supply-a8d080c784684f9c8a3d15571afa0359`
was resolved and validated (61 entries, reparse points 0), then removed with native
PowerShell `Remove-Item -LiteralPath`. Installer, portable runtime and model are
absent; a future authorized measurement requires reacquisition. Invocation-owned
crop/list/reached scratch cleaned in finally paths; final R3A temporary-directory
inventory is zero. No broad temporary glob was deleted. Shared SDK remains present
and unrelated local tools were untouched. Git status contains no runtime/model,
images or raw TSV/list/probe outputs; no such artifacts are committed.

Remaining risks: synthetic controls do not measure population accuracy, live-source
validation or current-benefit truth; ruled-grid limitations persist; correlated
same-engine errors and degraded crop behavior remain unevaluated after rejection.
Product dependency `NOT_APPROVED`; P4-3B `BLOCKED`; `ProductionAction=NONE`;
P4-3 / Phase 4 `NOT COMPLETE`. Stop for human review; no subsequent quality work.

Task 5 review fix: AllReached output/assertions now branch on the actually reached
gate, so failed A reports null B/C as blocked and unavailable/failed B reports
null C as blocked. No candidate, runner, crop, OCR or fidelity decisions changed.
New `-Group ReachedReporting` verifies the real public child CLI with explicit
nonexistent executable/model paths, plus A-block rendering from an unproven
preparation. `-Group ClearFidelity` checks synthetic unavailable-model and observed
mapping-failure rendering, as well as unchanged reached-C rejection rendering.
Both targeted commands PASS after the reporting fix, with **zero actual OCR**.
The supply was not reacquired; actual quality measurements and the full 62-test
suite were not rerun during this fix. The controller owns final post-review
verification and whole-branch review. Full-suite historical JSON parser object
table output was pre-existing diagnostic noise; it did not invalidate 62/62 PASS.

Final-review result-contract fix: unavailable prerequisites now use the exact
`P4_3_REDESIGN3A_NOT_EVALUATED` final verdict. A later zero-invocation supply failure
preserves an already observed B mapping failure or C batch, mandatory fidelity or
repeat-determinism failure as FAILED / `P4_3_REDESIGN3A_REJECTED`, retaining original
evidence and invocation counts. Without disqualifying observations, incomplete
evaluation remains NOT_EVALUATED. Gate C PASS alone also remains an intermediate
result: final AllReached is NOT_EVALUATED while D is `NOT_RUN_TASK4_NOT_IMPLEMENTED`.
ClearFidelity mixed-sequence controls and the real absent-supply ReachedReporting
CLI PASS with **zero actual OCR**. This separate code/reporting fix does not rerun
or replace the actual eight-call C matrix, original measurement HEAD `c0d19e5`,
62-test measurement or overall cycle total of 20 OCR calls. No supply was acquired;
Task 4, consensus and degraded-quality evaluation remain unreached. The controller
owns the fresh full data-suite check at the final fixed HEAD.

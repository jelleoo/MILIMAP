# P4-3 Redesign 3B best-model evaluation

Evaluation-only Task 1 proves the candidate model and unchanged Redesign 3A
runtime. Task 2 adds the best-model batch boundary. Tests perform real version
probes and intercept quality execution. Task 3 measures clear Gray fidelity and
stops the first cycle at its failed Gate B1.
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

## Gray fidelity and early stop (Task 3)

Dot-source `run-evaluation.ps1`. `Invoke-P43R3bGateB1 -GrayPrepared ...
-Executable ... -ModelDescriptor ...` accepts the historical helper-derived Gray
preparation and the exact Gate A reference descriptor. It reuses the 3A
preparation authority, cell text reconstruction, ground truth and fidelity
functions without changing historical files. The matrix retains the same 12
crops for PSM6 x2 then PSM11 x2. Both independent paths must have 8/8 mandatory
matches with identical repeated words, texts, fidelity and diagnostics. Elapsed
time is recorded separately. Completed mandatory PARTIAL/NOT_EVALUATED or a
nondeterministic repeat rejects the candidate. Supply loss before disqualifying
evidence is NOT_EVALUATED; supply loss after an observed failure retains REJECTED.

`Invoke-P43R3bFirstCycle -Executable ... -ModelPath ... -ArtifactDirectory ...`
first proves and freezes Gate A, prepares the locked clear Gray fixture once,
then runs B1. B2/RGB, C/consensus and D/degraded are blocked placeholders in Task
3. Intermediate B1 PASS alone cannot establish a successful first-cycle verdict.
There is no extra real page-mapping probe, retry, tuning or alternative fixture.

```powershell
pwsh -NoProfile -File tools/data/evaluation/p4-3-redesign3b-ocr/test-evaluation.ps1 -Group GrayFidelity
pwsh -NoProfile -File tools/data/evaluation/p4-3-redesign3b-ocr/test-evaluation.ps1 -Group GrayFidelity -ObservedResultPath <external-first-cycle.json>
```

Both commands perform zero actual quality OCR. The second verifies the recorded
first measurement. The separately authorized first-measurement option is
`-RunRealGateB1 -Executable ... -ModelPath ... -ArtifactDirectory <fresh-absolute-external-directory>`;
it requires a new repository-external directory, records raw TSV/stderr there,
guards the four-call budget and compares physical calls with returned counts.
The existing measurement must not be replayed under Task 3.

Measured 2026-10-10 KST, frozen at `2026-10-09T17:03:44.4946521Z`:
Gate A model/runtime `GATE_A_MODEL_SUPPLY_PASS`, Gray crop provenance
`GATE_A_CROP_PROVENANCE_PASS`, B1 `GATE_B1_CLEAR_GRAY_FIDELITY_FAILED`, first
cycle `P4_3_REDESIGN3B_REJECTED`. The candidate is the exact pinned source/blob,
12528128 bytes and SHA256 documented above. The 3A runtime hashes and
`tesseract v5.5.3.20260724` were independently reproved before quality.

| PSM | Repeat | Mandatory | All cells | Words | Batch elapsed ms |
| --- | --- | --- | --- | --- | --- |
| 6 | 1 | 5/8 | 7/12 | 40 | 271 |
| 6 | 2 | 5/8 | 7/12 | 40 | 261 |
| 11 | 1 | 6/8 | 8/12 | 39 | 278 |
| 11 | 2 | 6/8 | 8/12 | 39 | 259 |

All four batches were COMPLETE, each with 12 mapped pages and one invocation.
PSM6 and PSM11 repeats have identical words/texts/fidelity/diagnostics; raw TSV
and raw stderr are also byte-identical within each repeated pair. All batch
diagnostic arrays are empty. Stderr contains only 12 crop page-list notices.
Gray PDF open/page read/image decode/grid build/crop build = `1/1/1/1/1`, 12
crops, reused throughout. Reported quality calls = physical quality calls = 4,
version probes = 1. RGB/consensus/degraded calls = `0/0/0`; B2/C/D are each
`NOT_RUN_GATE_B1_FAILED`. Product approval remains `NOT_APPROVED`, P4-3B `BLOCKED`.

Every nonmatching cell is below; each row applies to both repeats of that PSM.
Texts preserve all characters and spaces. `\n` denotes the actual internal newline.

| PSM | Cell / role | Fidelity state | Expected | Reconstructed |
| --- | --- | --- | --- | --- |
| 6 | 2 / HEADER | NOT_EVALUATED (PARTIAL) | `주소` | `주소 즈` |
| 6 | 3 / HEADER | MISMATCH | `전화번호` | `전 화 번호` |
| 6 | 6 / AUXILIARY | MISMATCH | `가상시 가람로 12` | `가 상 시 가 람 로 12` |
| 6 | 9 / BUSINESS_NAME | NOT_EVALUATED (PARTIAL) | `가상 누리 식당` | `가스 \| 상 누리 식당` |
| 6 | 10 / AUXILIARY | MISMATCH | `가상시 누리로 23` | `가 상 시 누 리 로 23` |
| 11 | 2 / HEADER | MISMATCH | `주소` | `즈 ㅅ\n수소` |
| 11 | 3 / HEADER | MISMATCH | `전화번호` | `전 화 번호` |
| 11 | 6 / AUXILIARY | MISMATCH | `가상시 가람로 12` | `가 상 시 가 람 로 12` |
| 11 | 10 / AUXILIARY | MISMATCH | `가상시 누리로 23` | `가 상 시 누 리 로 23` |

PSM6 has CONFLICTING overlap at cell 2 (one record pair) and cell 9 (two pairs),
making those mandatory cells PARTIAL; cell 6 has one SAFE_ADJACENT pair. PSM11
has one SAFE_ADJACENT pair each at auxiliary cells 6 and 10. All other cell
diagnostic arrays are empty. Raw confidence is diagnostic only; e.g. PSM6 cell 2
has `[83.932114,96.925598]`, cell 9 has
`[53.506325,93.101936,96.985504,94.889915,96.998039]`, and the incorrect
`전 화 번호` has `[93.240875,93.302353,90.917862]` for both PSMs. No confidence
threshold, repair or normalization beyond the historical policy was applied.

Task 3's minimal determinism comparison glue is human-approved
`APPROVED_BY_DESIGN_CONSTRAINT` for this 3B evaluation only. The frozen 3A
comparison exists inside its public Gray/RGB quality gate and has no independent
callable helper. This approval covers only the same JSON depth 12, selected
`CellId,Status,Text` text fields, and batch-plus-cell flattened diagnostics
representation already used by 3A. No sorting, tolerance, added exclusion or
canonicalization was introduced; elapsed time remains outside those four
evidence representations. It does not extend Task2 crop/mapping approval to
other semantics or authorize production reuse, historical refactoring, broader
comparison policies or future OCR quality runs.

The GrayFidelity suite checks six isolated comparison contracts: all four
representations identical; words-only, texts-only, fidelity-only and
diagnostics-only changes each reject; elapsed-only difference passes. Each case
asserts the literal four equality flags for both PSMs and compares them with the
frozen 3A gate on the same synthetic evidence, with every historical and 3B batch
intercepted before any process invocation. Initial execution of these new tests
PASSed because the approved existing behavior already implements the contract;
no artificial RED or production change was made. Historical parity is synthetic
verification and performs zero real fast-model OCR.

Historical 3A Gray measurements were 5/8 and 6/8 mandatory for PSM6/11; this
best-model measurement also yields 5/8 and 6/8. That comparison is diagnostic
only and does not authorize tuning. The only premeasurement launcher failure
was synthetic function restoration (`Invoke-P43R3bGateA` missing), before any
Gate A, preparation or OCR. Its zero-call harness error was reproduced by a
regression assertion and fixed by restoring the captured functions. A fresh
Gate A-only preflight passed; the actual quality matrix then ran exactly once.
Observed-result assertions subsequently PASS without another actual OCR call.

## Reached verification and factual result (Task 6)

Branch `codex/phase4-p4-3-redesign3b-best-model-evaluation`, final implementation
HEAD `15fa95533552d415d21f9ff627c424913b370c47`. Task 3 first measurement was
captured before its implementation commit; its unchanged evidence remains
authoritative. The later result-recording commit is resolved from Git in the
controller's final report, rather than self-referenced in this file.

`AllReached` accepts `-TesseractExecutable` and `-BestModelPath`. Without supply
it verifies reporting and synthetic Gray contracts with zero actual quality
OCR. With both supply paths it requires `-ObservedResultPath` pointing to the
original B1 rejection. The original gate/counts are checked before any Gate A,
preparation or process call. A fresh repository-external `-ArtifactDirectory`
is required (or a unique external temporary directory is generated). The only
implemented/reached replay is A+B1, PSM6 x2 then PSM11 x2, one Gray preparation,
at most four quality calls. No blocked gate is invoked. This is an evaluation
verification interface; running it requires separately authorized quality work.

```powershell
pwsh -NoProfile -File tools/data/evaluation/p4-3-redesign3b-ocr/test-evaluation.ps1 -Group AllReached
pwsh -NoProfile -File tools/data/evaluation/p4-3-redesign3b-ocr/test-evaluation.ps1 -Group AllReached -TesseractExecutable <absolute-exe> -BestModelPath <absolute-kor.traineddata> -ObservedResultPath <original-first-cycle.json> -ArtifactDirectory <fresh-external-directory>
```

The sole authorized final verification ran 2026-10-10 KST, UTC
`2026-10-09T17:31:37.0054872Z` to `2026-10-09T17:31:39.7270283Z`.
Gate A independently froze the exact same 12528128-byte pinned model and runtime
at `2026-10-09T17:31:37.0709263Z`, before preparing or executing quality OCR.
The model source/blob/SHA256 are as documented above. Runtime engine 5.5.3,
build `tesseract v5.5.3.20260724`, exact SHA256 identities:

| Runtime file | SHA256 |
| --- | --- |
| `tesseract.exe` | `c66f0f12ed76f6aa455dac97684bbc86756d6a732380bee09122454cfda3f420` |
| `libtesseract-5.dll` | `54d54528b453ce3a5ba79487687f8df43e7b194b9ea97beba74200453fe1fb46` |
| `libleptonica-6.dll` | `1869b44e3d46fd830620b042477e5d60a950779582f38f60291547efb27792f1` |

| Gate | First measurement | Final verification |
| --- | --- | --- |
| A | `GATE_A_MODEL_SUPPLY_PASS` | `GATE_A_MODEL_SUPPLY_PASS` |
| Gray provenance | `GATE_A_CROP_PROVENANCE_PASS` | `GATE_A_CROP_PROVENANCE_PASS` |
| B1 | `GATE_B1_CLEAR_GRAY_FIDELITY_FAILED` | `GATE_B1_CLEAR_GRAY_FIDELITY_FAILED` |
| B2 | `NOT_RUN_GATE_B1_FAILED` | `NOT_RUN_GATE_B1_FAILED` |
| C | `NOT_RUN_GATE_B1_FAILED` | `NOT_RUN_GATE_B1_FAILED` |
| D | `NOT_RUN_GATE_B1_FAILED` | `NOT_RUN_GATE_B1_FAILED` |
| Verdict | `P4_3_REDESIGN3B_REJECTED` | `P4_3_REDESIGN3B_REJECTED` |

Final verification was four COMPLETE batches with null codes and empty batch
diagnostics. The first failing reached gate is B1. Verification records its
first observation as PSM6 repeat1, `MANDATORY_FIDELITY_FAILED`. Original JSON
predates the `FirstFailure` detail field: reporting explicitly marks that
detail `NOT_RECORDED`, without modifying the source evidence or inventing it.
The original recorded B1 failure and rejected verdict remain authoritative even
if a replay unexpectedly returns another valid verdict. Accepted final vocabulary
is `P4_3_REDESIGN3B_EARLY_GATES_PASS`, `P4_3_REDESIGN3B_REJECTED` or
`P4_3_REDESIGN3B_NOT_EVALUATED`; none of the blocked gates gains PASS.

| Fixture | PSM | Repeat | Mandatory | All cells | Words | Verification ms |
| --- | --- | --- | --- | --- | --- | --- |
| clear Gray | 6 | 1 | 5/8 | 7/12 | 40 | 264 |
| clear Gray | 6 | 2 | 5/8 | 7/12 | 40 | 263 |
| clear Gray | 11 | 1 | 6/8 | 8/12 | 39 | 283 |
| clear Gray | 11 | 2 | 6/8 | 8/12 | 39 | 287 |

The four verification runs reproduce every nonmatch, reconstruction, raw word
confidence and geometry diagnostic in the Task 3 table above. Both PSMs have
all four words/texts/fidelity/diagnostics equality flags true within their
repeated pairs. Corresponding first/verification representations are also
identical under the same historical comparison; raw TSV bytes match across
cycles. Raw TSV and stderr match within each verification PSM pair. Cross-cycle
stderr bytes differ because the 12 ordered page-list notices contain different
scratch paths; verification stderr is 1469 bytes per run, only those 12 notices,
with no warning/error text. This observation does not change comparison policy.
Consensus/false-consensus and degraded behavior are `NOT_RUN_GATE_B1_FAILED`;
there is no evidence to assess them. Tasks 4/5 were not implemented.

| PSM | First range / median ms | Verification range / median ms | All four range / median ms |
| --- | --- | --- | --- |
| 6 | 261–271 / 266 | 263–264 / 263.5 | 261–271 / 263.5 |
| 11 | 259–278 / 268.5 | 283–287 / 285 | 259–287 / 280.5 |

Batch elapsed totals are 1069 ms first, 1097 ms verification, 2166 ms combined.
The measured verification A/preparation/B1 interval is 2721.5411 ms. Timing and
12528128-byte model size are diagnostics, not an accuracy or performance claim.

| Observed counter | First | Verification | Overall |
| --- | --- | --- | --- |
| Physical / returned quality OCR | 4 / 4 | 4 / 4 | 8 / 8 |
| PSM6 / PSM11 quality OCR | 2 / 2 | 2 / 2 | 4 / 4 |
| Gray / RGB / degraded preparations | 1 / 0 / 0 | 1 / 0 / 0 | 2 / 0 / 0 |
| Version probes for these actual cycles | 1 | 1 | 2 |
| RGB / consensus / degraded quality OCR | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 |
| Per-cell fallback / per-business OCR | 0 / 0 | 0 / 0 | 0 / 0 |
| Fast baseline rerun / Gate C extra OCR | 0 / 0 | 0 / 0 | 0 / 0 |

Each cycle opens/reads/decodes/builds grid/builds crops once (`1/1/1/1/1`),
prepares 12 crops and reuses them. Physical process-boundary counters are checked
against returned invocation counts; overall 8 is reported only after the four
verification quality calls actually ran. Previous ModelSupply/BestBatch test
version probes are separate zero-quality contract checks, not part of these
two actual quality cycles. No mapping probe, retry or further quality work ran.

Task 6 reporting RED was the missing reporting function; GREEN verified original
rejection preservation, explicit blocked statuses, independently checked counts
and final vocabulary. The first AllReached launcher stopped on the original
JSON's absent detail field before Gate A, preparation, scratch creation or OCR
(quality=0). A narrow legacy-evidence regression reproduced that error; its
minimal reporting-only fix GREENed, followed by the sole four-call replay.
AllReached synthetic/observed assertions and actual reporting assertions PASS.
The implementation runner and acceptance semantics were unchanged by Task 6.

Controller locked historical helper restore/build and A/A2/R2 Contract plus
3A ClearFidelity/ReachedReporting checks PASSed with zero actual quality OCR
(historical build warnings=0/errors=0). The final full sorted
`tools/data/test-*.ps1` suite PASSed 62/62, exit 0, controller session `58388`;
the controller read its entire output. Final real-authority ModelSupply PASSed
with three version probes and zero quality OCR. BestBatch PASSed six success
and eleven failure controls, seventeen intercepted batches, one version probe
and zero actual quality OCR. These are captured controller results, not reruns
by the documentation worker. A subsequent no-supply `AllReached` check against
the unchanged original JSON PASSed, exit 0: reporting controls, Gray synthetic
controls, six determinism/parity contracts and observed-result assertions;
replay `NOT_RUN_NO_SUPPLY`, actual quality OCR=0.
Task 6 staged review approved the change with residual Critical/Important=0;
the LF/CRLF advisory remains a recorded Minor observation. Historical/protected
final diff verification, whole-branch fresh review and result-recording commit
remain controller-owned and pending. Android local is `NOT_RUN_EVALUATION_ONLY`.

External first evidence SHA256 is
`07bcbb75effe2fa86efed4bd851cd4afc842fc83b0e4dd6c7ae65ed35813f529`;
verification evidence SHA256 is
`ef9d1d2c3f1168856c9901509abc011e459cfe70c6afa8c9b15f51b0e103a992`.
The former invocation-owned verification directory was
`C:/Users/PC/AppData/Local/Temp/milimap-p43r3b-reached-20261010-task6-verification`
(`verification-cycle.json`, `reached-report.json`, four TSV/stderr pairs, one
Gray inspect/source PGM and twelve crop PGMs). The former first evidence was in
`C:/Users/PC/AppData/Local/Temp/milimap-p43r3b-gray-first-20261010-task3-measurement`.
Controller dedicated cleanup PASSed 2026-10-12, exit 0: exact supply directory
`C:/Users/PC/AppData/Local/Temp/milimap-p43r3b-supply-14ab2907b43141d98f576700c9a50a82`
(three surviving installer/best/historical-fast files), first-measurement
directory (23 files) and verification directory (24 files) were removed after
Task 6 review. All three exact paths were checked for reparse points and verified
absent afterward. Captured identities, hashes, fidelity and counts remain in
this permanent record; raw outputs were intentionally removed. Extracted runtime
and empty failed-launcher directory were already absent before cleanup. Shared
`milimap-p42a-pdfpig-eval/sdk` was not touched; its `dotnet.exe` was already absent
before cleanup. No shared SDK or unrelated tool was removed.

The bounded Task 2 glue and exact Task 3 comparison approval remain the only
design-constraint tradeoffs. They do not authorize broader duplication,
preprocessing, another model/engine or production use. This result applies only
to the locked synthetic clear Gray fixture on this Windows/runtime identity;
population accuracy, live-source compatibility, product suitability and
cross-OS determinism remain unestablished. Product dependency `NOT_APPROVED`,
P4-3B `BLOCKED`, P4-3 `NOT COMPLETE`, Phase 4 `NOT COMPLETE`,
`ProductionAction=NONE`. Human review stop; no push, PR, merge or deployment.

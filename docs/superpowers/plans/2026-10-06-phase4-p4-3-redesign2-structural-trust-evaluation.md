# Phase 4 P4-3 Redesign 2 Structural Trust Evaluation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove or reject the revised PDF OCR trust model in which structural provenance, deterministic reconstruction, and required coverage are the acceptance authority while raw Tesseract confidence is diagnostic-only.

**Architecture:** Preserve P4-3A and P4-3A2 byte-for-byte as historical evidence. Add a separate evaluation-only harness under `tools/data/evaluation/p4-3-redesign2-ocr/` that reuses the existing P4-3A PdfPig/grid helper, the exact P4-3A2 OCR runtime/model wrapper semantics, and committed fixtures read-only, but owns a new structural acceptance model with no confidence threshold parameter or confidence-based completeness decision. No production OCR adapter or product dependency is introduced.

**Tech Stack:** PowerShell 7, retained .NET 8/PdfPig 0.1.16 P4-3A inspection/grid helper, exact Tesseract 5.5.3 semantics/config, Windows evaluation build `v5.5.3.20260724`, exact upstream Ubuntu 5.5.3, official `tessdata_fast/kor.traineddata` commit `87416418657359cb625c412a48b6e1d6d41c29bd` SHA-256 `6b85e11d9bbf07863b97b3523b1b112844c43e713df8b66418a081fd1060b3b2`, temporary GitHub Actions Windows/Ubuntu evaluation workflow.

**Spec:** `docs/superpowers/specs/2026-10-06-phase4-p4-3-ocr-trust-redesign2.md`

## Problem

P4-3A2 proved useful structural behavior but rejected the candidate because no approved global confidence threshold could preserve clear evidence while independently separating the degraded control. The next evaluation must determine whether the fixed OCR candidate is safe when completeness is decided by physical provenance, representation consistency, deterministic reconstruction, and required coverage instead of a mandatory confidence threshold.

## Scope

- Evaluate the approved Redesign 2 trust model only.
- Keep the OCR engine/model/config fixed.
- Reuse historical clear, degraded, mild, regression, and multipage fixtures read-only.
- Preserve raw confidence for diagnostics and determinism evidence only.
- Evaluate structural Gate A, business isolation, operational safety, multipage scope, and Windows/Ubuntu determinism.
- Produce an auditable final verdict and dependency-review recommendation.

## Non-scope

- No alternative OCR engine/model.
- No PSM/OEM search beyond PSM11 positive and PSM3/4/6 regression roles.
- No crop OCR, new preprocessing, or fixture tuning.
- No new geometry tolerance or overlap ratio search.
- No borderless inference or OCR-driven table topology.
- No product `PDF_ROW` implementation, product OCR adapter, runtime/model packaging, DB/auth/API/schema change, canonical/seed/apps write, or P4-3B implementation.

## Global Constraints

- Execution base must include approved spec commit `bb8b077b79e843e85900340237be74f91ade1d62`, whose current `dev` product base is `3f40d5c566568b424c83f539aa6554150e74d14d`. Refresh GitHub refs before execution; newer GitHub truth wins if it conflicts.
- Historical `tools/data/evaluation/p4-3a-ocr/**` and `tools/data/evaluation/p4-3a2-ocr/**` are read-only evidence. Their Git diff against execution base must remain zero.
- Do not modify `tools/data/pdf-native/**`, `tools/data/lib/**`, `data/canonical/**`, `data/seed/**`, or `apps/**`.
- OCR remains PDF-only and may enter only from the existing image-only `OCR_FALLBACK_CANDIDATE` shape.
- Supported image shape remains exactly one clearly mapped full-page embedded scan image per page, PdfPig-decoded 8-bit `DeviceGray` or `DeviceRGB`.
- Runtime/model config is fixed: Korean, OEM 1, DPI 300; PSM11 positive; PSM3/4/6 regression only.
- Windows runtime identity remains `v5.5.3.20260724` / 5.5.3. Ubuntu must use exact upstream 5.5.3; version substitution is forbidden.
- Korean model is fixed to official `tessdata_fast/kor.traineddata` commit/hash in the header.
- Exact word-to-cell containment is unchanged: no pixel allowance, centroid, nearest-cell, majority assignment, adaptive widening, OCR-driven grid movement, or reading-order table inference.
- Same-cell policy is fixed to `SAME_CELL_OVERLAP_V1`, same-region ratio `0.25`. Do not search `0.50`, `0.75`, or any new ratio in Redesign 2.
- Raw confidence is `DIAGNOSTIC_ONLY_V1`: no per-word threshold, cell-average threshold, confidence matrix, expected-text rescue, or confidence-based completeness decision.
- Confidence may never rescue physical ambiguity, duplicate/conflicting overlap, ordering failure, missing coverage, binding, lifecycle, currentness, or claims.
- `ProductionAction=NONE`; all technical rows are fictional evaluation artifacts and never benefit truth.
- Product dependency remains `NOT_APPROVED`; P4-3B remains `BLOCKED` regardless of evaluation result until separate explicit dependency approval and P4-3B plan approval.

## File Structure

**Create**
- `tools/data/evaluation/p4-3-redesign2-ocr/invoke-tesseract-eval.ps1` — Redesign 2 runtime adapter. For single-page runs, reuse the historical A2 wrapper semantics read-only and re-publish a Redesign 2 identity; add only Redesign 2-local multipage support when Task 4 reaches that gate.
- `tools/data/evaluation/p4-3-redesign2-ocr/run-evaluation.ps1` — structural cell provenance, fixed overlap policy, deterministic reconstruction, required coverage, technical row isolation, gate orchestration.
- `tools/data/evaluation/p4-3-redesign2-ocr/test-evaluation.ps1` — TDD groups `Contract`, `StructuralTrust`, `Isolation`, `Safety`, `DeterminismContract`, `All`.
- `tools/data/evaluation/p4-3-redesign2-ocr/README.md` — scope, commands, exact runtime/model identity, confidence diagnostic-only semantics, final verdict.
- `docs/handover/2026-10-06-phase4-p4-3-redesign2-structural-trust-evaluation.md` — create only after final gate outcome is known.

**Read-only dependencies**
- `tools/data/evaluation/p4-3a-ocr/Milimap.P4_3A.OcrEval.csproj`
- `tools/data/evaluation/p4-3a-ocr/Program.cs`
- `tools/data/evaluation/p4-3a-ocr/fixtures/gray.pdf`
- `tools/data/evaluation/p4-3a-ocr/fixtures/rgb.pdf`
- `tools/data/evaluation/p4-3a-ocr/fixtures/multipage.pdf`
- `tools/data/evaluation/p4-3a2-ocr/invoke-tesseract-eval.ps1`
- `tools/data/evaluation/p4-3a2-ocr/fixtures/manifest.json`
- `tools/data/evaluation/p4-3a2-ocr/fixtures/degraded-gray.pdf`
- `tools/data/evaluation/p4-3a2-ocr/fixtures/degraded-rgb.pdf`
- `tools/data/evaluation/p4-3a2-ocr/fixtures/mild-degraded-gray.pdf`

**Temporary; remove before closeout**
- `.github/workflows/p4-3-redesign2-ocr-evaluation.yml`
- downloaded/extracted/build Tesseract runtime, Korean model, raw TSV, PGM/PPM, and normalized CI evidence artifacts.

**Update only after final verdict**
- `docs/current-work.md`

## Test Method

- TDD for every task: RED -> minimal GREEN -> targeted regression -> commit.
- Re-run historical locked restore/build and assert historical P4-3A/P4-3A2 diffs remain zero.
- Gate A uses the already committed clear/mild/degraded/regression evidence; no new OCR-quality fixture is authored.
- Full repository data test suite runs before closeout.
- Exact-head GitHub CI `verify` and `verify-data` are required before merge.
- Android local testing remains `NOT_RUN_EVALUATION_ONLY` unless a protected/product path changes unexpectedly, in which case stop and review scope.

## Risks

- Removing the mandatory confidence threshold could accidentally become a blanket acceptance relaxation if structural and coverage negatives are not pinned.
- Copying old A2 acceptance code could silently retain confidence semantics; Redesign 2 must have its own prefixed acceptance functions and no confidence threshold argument.
- Cross-platform Tesseract may vary in bbox or text; semantic/structural variance must reject rather than be hand-waved as confidence noise.
- Multipage support could change execution semantics or page mapping; it remains a conditional scope gate and cannot weaken the single-page proof.
- Technical business isolation must not be confused with production business binding or semantic absence.

## Review Focus

1. **Low-confidence but structurally valid required text** must remain eligible for `COMPLETE`; Task 2 asserts at least one clear required word below 50 remains accepted and that no confidence threshold exists in the API.
2. **Structural conflict with high confidence** must still reject; Task 2 reuses mild Gray and synthetic conflict controls and requires `PARTIAL` regardless of raw confidence.
3. **Missing required coverage with otherwise clean geometry** must reject; Task 2 removes one required cell from an in-memory control and requires `PARTIAL / REQUIRED_COVERAGE_MISSING`.
4. **Incomplete OCR must never become technical or semantic absence**; Task 3 requires no accepted rows and no `NOT_FOUND`-like result when source evidence is not `COMPLETE`.
5. **Cross-OS diagnostic variance must not hide semantic variance**; Task 5 allows Level B only for confidence/environment/timing differences while any relevant bbox, cell assignment, overlap class, reconstructed text, technical row, or final-status difference is Level C.

---

### Task 1: Redesign 2 Harness Boundary + Diagnostic-only Confidence Contract

**Files:**
- Create: `tools/data/evaluation/p4-3-redesign2-ocr/invoke-tesseract-eval.ps1`
- Create: `tools/data/evaluation/p4-3-redesign2-ocr/test-evaluation.ps1`
- Create: `tools/data/evaluation/p4-3-redesign2-ocr/README.md`
- Read only: historical P4-3A/P4-3A2 paths listed above.

**Interfaces:**
- `Invoke-P43R2TesseractEvaluation -Executable <path> -ModelPath <path> -Inputs <string[]> -Psm <3|4|6|11>`
- Single-page execution delegates to the read-only P4-3A2 wrapper contract, then republishes a Redesign 2 result.
- Result fields include `ProbeId='MILIMAP_P4_3_REDESIGN2_OCR_EVAL'`, `SchemaVersion=1`, `TrustModelVersion='STRUCTURAL_TRUST_V1'`, `ConfidencePolicy='DIAGNOSTIC_ONLY_V1'`, exact engine/model identity, invocation count, elapsed time, raw OCR words, diagnostics, `ProductionAction='NONE'`.
- OCR word fields remain exactly `Page, Block, Paragraph, Line, Word, Left, Top, Width, Height, Confidence, Text`.
- There is no `ConfidenceThreshold`, `ConfidenceCandidates`, or confidence-based status parameter in the Redesign 2 interface.

- [ ] **Step 1: Write failing Contract tests**

Assert:
- both historical evaluation directories have diff 0 against the execution base;
- historical P4-3A2 wrapper still accepts only the exact engine/model identity and preserves raw confidence;
- new Redesign 2 result identity/policy fields exist;
- the public Redesign 2 wrapper exposes no confidence-threshold argument or candidate list;
- missing executable/model, wrong model hash, wrong engine version, malformed TSV, empty word output, and unsupported input count fail closed;
- raw confidence is preserved byte-for-value in the mapped Redesign 2 words;
- no product/protected path is modified.

- [ ] **Step 2: Run Contract and verify RED**

Run:
`pwsh -NoProfile -File .\tools\data\evaluation\p4-3-redesign2-ocr\test-evaluation.ps1 -Group Contract`

Expected: FAIL because the Redesign 2 harness does not exist.

- [ ] **Step 3: Implement the minimal runtime adapter**

Dot-source only the read-only A2 runtime wrapper, not A2 `run-evaluation.ps1`. Map its single-page result into the new Redesign 2 identity without changing OCR words, bbox, hierarchy, confidence, engine/model validation, or fail-closed behavior.

- [ ] **Step 4: Re-run Contract**

Expected: PASS; historical directories and protected paths remain unchanged.

- [ ] **Step 5: Commit**

`git add tools/data/evaluation/p4-3-redesign2-ocr`

`git commit -m "test: add P4-3 redesign2 evaluation boundary"`

---

### Task 2: Gate A — Structural Trust + Required Coverage

**Files:**
- Create/Modify: `tools/data/evaluation/p4-3-redesign2-ocr/run-evaluation.ps1`
- Modify: `tools/data/evaluation/p4-3-redesign2-ocr/test-evaluation.ps1`
- Modify: `tools/data/evaluation/p4-3-redesign2-ocr/README.md`

**Interfaces:**
- `Get-P43R2CellMembership -Cells <object[]> -Word <object>` -> `Status=UNIQUE|NONE|AMBIGUOUS`, `CellId` only for `UNIQUE`.
- `Get-P43R2OverlapClass -A <bound-word> -B <bound-word>` -> `NONE|SAFE_ADJACENT|DUPLICATE|CONFLICTING|ORDERING_UNSAFE`; same-region ratio is fixed internally to `0.25`.
- `Resolve-P43R2OcrCells -Cells <object[]> -Words <object[]> -RequiredCellIds <string[]>` -> `Status=COMPLETE|PARTIAL`, `AcceptedWords`, `RejectedWords`, `Diagnostics`, `CellText`, raw confidence preserved.
- `New-P43R2StructuralEvidence -Cells <object[]> -Ocr <object> -RequiredCellIds <string[]>` -> separates operational status from structural acceptance; no threshold matrix.
- `Invoke-P43R2GateAMatrix -Executable -ModelPath` -> clear repetitions, mild/degraded controls, PSM3/4/6 regressions, final `GATE_A_PASS|P4_3_REDESIGN2_REJECTED`.

**Fixed Gate A coverage:** for the retained 3x4 clear Gray/RGB fictional table, all 12 proven cells are required in the technical control. Required cell IDs come from the proven grid/fixture contract, never from OCR text.

- [ ] **Step 1: Write failing StructuralTrust tests**

Pin:
- exact unique containment; zero-cell and cross-cell remain blocking;
- fixed ratio 0.25 produces the previously accepted `SAFE_ADJACENT` controls and still rejects duplicate/conflict/order cases;
- resolver has no confidence-threshold parameter;
- low confidence alone does not add a blocking diagnostic;
- synthetic structurally valid required word with confidence 1 remains eligible;
- missing one required cell yields `PARTIAL / REQUIRED_COVERAGE_MISSING`;
- empty OCR output is operational `FAILED / EMPTY_WORD_OUTPUT`, not structural absence;
- mild Gray remains `PARTIAL` because of recorded `CONFLICTING` overlap;
- clear Gray/RGB PSM11 each become `COMPLETE` with 2 technical rows, repeated twice identically;
- at least one clear required word with confidence below 50 remains accepted, proving no hidden threshold;
- PSM3/4/6 retain prior physical containment failures and remain `PARTIAL`;
- old degraded Gray/RGB remain operational negatives and cannot become absence.

- [ ] **Step 2: Run StructuralTrust and verify RED**

Run:
`pwsh -NoProfile -File .\tools\data\evaluation\p4-3-redesign2-ocr\test-evaluation.ps1 -Group StructuralTrust -TesseractExecutable <absolute-exe> -KoreanModelPath <absolute-model>`

Expected: FAIL before Redesign 2 structural functions exist.

- [ ] **Step 3: Implement structural provenance and reconstruction**

Port only the already proven physical/overlap semantics into Redesign 2-prefixed functions:
- exact containment;
- fixed `SAME_CELL_OVERLAP_V1 / 0.25`;
- deterministic within-cell reconstruction;
- no confidence filtering;
- explicit required coverage check.

Do not source A2 `run-evaluation.ps1` and do not copy its confidence-decision or threshold-matrix functions.

- [ ] **Step 4: Implement the fixed Gate A matrix**

Reuse read-only:
- P4-3A `gray.pdf`, `rgb.pdf`;
- A2 `mild-degraded-gray.pdf`, `degraded-gray.pdf`, `degraded-rgb.pdf`;
- PSM3/4/6 against clear Gray/RGB.

Do not create, tune, or substitute fixtures. Run clear Gray/RGB PSM11 twice each. Raw confidence is measured and reported but never passed into completeness logic.

- [ ] **Step 5: Re-run StructuralTrust**

Expected PASS only if all required positive and negative controls hold.

If any Gate A requirement fails:
- verdict = `P4_3_REDESIGN2_REJECTED`;
- stop Tasks 3-5;
- proceed only to Task 6 rejection closeout.

If Gate A passes:
- record `GATE_A_PASS`;
- commit;
- **STOP FOR HUMAN REVIEW before Task 3**.

- [ ] **Step 6: Commit**

`git add tools/data/evaluation/p4-3-redesign2-ocr`

`git commit -m "test: prove P4-3 redesign2 structural trust gate"`

---

### Task 3: Gate B — Technical Business Isolation

**Precondition:** Gate A has passed and human review explicitly authorizes continuation.

**Files:**
- Modify: `tools/data/evaluation/p4-3-redesign2-ocr/run-evaluation.ps1`
- Modify: `tools/data/evaluation/p4-3-redesign2-ocr/test-evaluation.ps1`
- Modify: `tools/data/evaluation/p4-3-redesign2-ocr/README.md`

**Interfaces:**
- `New-P43R2EvaluationRows -Cells <object[]> -CellText <object[]> -SourceStatus <string>` -> fictional technical rows only when `SourceStatus='COMPLETE'`.
- `Find-P43R2EvaluationRow -Rows <object[]> -BusinessName <string> -SourceStatus <string>` -> `FOUND|TECHNICAL_NO_MATCH|AMBIGUOUS|UNAVAILABLE`.
- `UNAVAILABLE` is mandatory when OCR source evidence is not `COMPLETE`; the function must never emit product `NOT_FOUND`.

- [ ] **Step 1: Write failing Isolation tests**

Assert:
- fictional Business A lookup returns only A row fields;
- Business B returns only B row fields;
- cross-business leakage = 0;
- duplicate matching business names return `AMBIGUOUS`;
- complete source with absent fictional query may return only `TECHNICAL_NO_MATCH`, never product `NOT_FOUND`;
- `PARTIAL`, `FAILED`, or `UNSUPPORTED` source yields `UNAVAILABLE`, no accepted rows, no absence signal, and no claims;
- OCR `COMPLETE` alone does not assert production business binding.

- [ ] **Step 2: Run Isolation and verify RED**

Run:
`pwsh -NoProfile -File .\tools\data\evaluation\p4-3-redesign2-ocr\test-evaluation.ps1 -Group Isolation`

Expected: FAIL before technical row isolation exists.

- [ ] **Step 3: Implement technical row projection and lookup**

Construct rows only from already proven grid row/column ordinals and reconstructed cell text. Do not import or emit production locator/binding/evaluator contracts.

- [ ] **Step 4: Re-run Isolation**

Expected: PASS with leakage 0 and incomplete-source absence leakage 0.

If Gate B fails, final verdict is `P4_3_REDESIGN2_REJECTED`; stop Tasks 4-5 and go to Task 6.

- [ ] **Step 5: Commit**

`git add tools/data/evaluation/p4-3-redesign2-ocr`

`git commit -m "test: prove P4-3 redesign2 OCR isolation"`

---

### Task 4: Gates C-D — Operational Safety + Multi-page Scope

**Precondition:** Gates A-B pass.

**Files:**
- Modify: `tools/data/evaluation/p4-3-redesign2-ocr/invoke-tesseract-eval.ps1`
- Modify: `tools/data/evaluation/p4-3-redesign2-ocr/run-evaluation.ps1`
- Modify: `tools/data/evaluation/p4-3-redesign2-ocr/test-evaluation.ps1`
- Modify: `tools/data/evaluation/p4-3-redesign2-ocr/README.md`

**Interfaces:**
- Single-page work counters: `PdfOpenCount`, `PageReadCount`, `ImageDecodeCount`, `GridBuildCount`, `OcrInvocationCount`, `LookupCount`.
- Retain A2 evaluation process bounds for equivalent single-process calls: identity deadline 3000 ms, OCR deadline 10000 ms, stdout limit 1,048,576 bytes, stderr limit 65,536 bytes, TSV maximum 10,000 lines.
- `Invoke-P43R2TesseractEvaluation` may accept multiple page images only in this task; Redesign 2-local list-mode must map TSV `page_num` exactly 1..N in input order.
- Multipage result is `MULTIPAGE_APPROVED|MULTIPAGE_NOT_APPROVED`; it is a scope result, not permission to weaken single-page gates.

- [ ] **Step 1: Write failing Safety tests**

Assert:
- two fictional business lookups reuse one accepted OCR/index result;
- single-page PDF open 1, image decode 1, grid build 1, OCR invocation 1;
- process-start failure, wrong identity, timeout, nonzero exit, malformed TSV, empty words, oversized stdout/stderr, and >10,000 TSV lines fail closed;
- temp artifacts are removed on success and failure;
- incomplete operational results expose no rows and no absence;
- retained native-text control invokes OCR 0;
- multi-page uses one OCR process invocation for the document-level page list;
- page numbers must map exactly 1..N; missing, duplicated, extra, or reordered page mapping is never repaired heuristically.

- [ ] **Step 2: Run Safety and verify RED**

Run:
`pwsh -NoProfile -File .\tools\data\evaluation\p4-3-redesign2-ocr\test-evaluation.ps1 -Group Safety -TesseractExecutable <absolute-exe> -KoreanModelPath <absolute-model>`

Expected: FAIL before Redesign 2 operational orchestration.

- [ ] **Step 3: Implement work-count reuse and fail-closed process handling**

Preserve the existing evaluation bounds above. Measure working-set/runtime information for reporting, but do not claim a portable hard-memory ceiling without an enforcement mechanism.

- [ ] **Step 4: Evaluate retained multipage fixture**

Use `tools/data/evaluation/p4-3a-ocr/fixtures/multipage.pdf` only.

If exact list-mode mapping and all per-page structural conditions pass, record `MULTIPAGE_APPROVED`. Otherwise record `MULTIPAGE_NOT_APPROVED` and constrain any eventual dependency recommendation to single-page only. Do not alter single-page acceptance or add per-page/business OCR retries to rescue multipage.

- [ ] **Step 5: Re-run Safety**

Expected:
- Gate C PASS, otherwise `P4_3_REDESIGN2_REJECTED`;
- Gate D exactly one of `MULTIPAGE_APPROVED` or `MULTIPAGE_NOT_APPROVED`.

- [ ] **Step 6: Commit**

`git add tools/data/evaluation/p4-3-redesign2-ocr`

`git commit -m "test: bound P4-3 redesign2 OCR operations"`

---

### Task 5: Gate E — Windows/Ubuntu Semantic Determinism

**Precondition:** Gates A-C pass. Gate D may be approved or not approved.

**Files:**
- Create temporarily: `.github/workflows/p4-3-redesign2-ocr-evaluation.yml`
- Modify if required by evidence contract: `tools/data/evaluation/p4-3-redesign2-ocr/*.ps1`
- Remove temporary workflow before final closeout.

**Interfaces:**
- `Export-P43R2DeterminismEvidence` -> normalized JSON containing runtime/model/config identity, fixture hash, raw word identity, raw confidence, bbox, proven-cell membership, overlap class, accepted/rejected reason, reconstructed cell text, technical rows, and final status; absolute paths/timing/temp names remain separate non-semantic metadata.
- `Compare-P43R2DeterminismEvidence -Windows <object> -Ubuntu <object>` -> `LEVEL_A|LEVEL_B|LEVEL_C`.
- Level B is limited to confidence values and environment/timing/supply-path diagnostics only. Any relevant bbox, membership, overlap class, accepted/rejected set, reconstructed text, row, or final-status difference is Level C.

- [ ] **Step 1: Write failing DeterminismContract tests**

Assert:
- normalized semantic evidence has deterministic ordering;
- absolute paths, temp names, and timing do not affect semantic comparison;
- confidence-only change -> Level B when all structural/text/status evidence is identical;
- environment/package-path-only change -> Level B;
- relevant bbox change -> Level C;
- cell membership, overlap class, reconstructed text, technical row, or final-status change -> Level C;
- inability to align required accepted words deterministically -> Level C.

- [ ] **Step 2: Run DeterminismContract and verify RED**

Run:
`pwsh -NoProfile -File .\tools\data\evaluation\p4-3-redesign2-ocr\test-evaluation.ps1 -Group DeterminismContract`

Expected: FAIL before exporter/comparator.

- [ ] **Step 3: Implement normalized evidence and comparator**

Do not add fuzzy text/word alignment, confidence margins, bbox tolerances, or semantic rescue rules.

- [ ] **Step 4: Add temporary exact-runtime Windows/Ubuntu workflow**

Windows:
- use the exact previously recorded `v5.5.3.20260724` portable supply path;
- verify the known installer/runtime identity and exact model hash before OCR.

Ubuntu:
- build/use exact upstream Tesseract 5.5.3 from official source/tag;
- reject any substituted Tesseract version;
- use the same exact model hash.

Both:
- run the same Gate A accepted clear controls and mandatory structural negatives;
- export normalized evidence;
- upload raw normalized JSON only as temporary CI evidence.

- [ ] **Step 5: Compare evidence**

- Level A -> PASS.
- Level B -> PASS only under the narrow diagnostic-only rule above.
- Level C -> `P4_3_REDESIGN2_REJECTED`.

If exact Ubuntu 5.5.3 cannot be reproduced, Gate E is not proven and the candidate cannot enter dependency review.

- [ ] **Step 6: Remove the temporary workflow and commit retained evaluation code**

`git rm .github/workflows/p4-3-redesign2-ocr-evaluation.yml`

`git add tools/data/evaluation/p4-3-redesign2-ocr`

`git commit -m "test: verify P4-3 redesign2 OCR determinism"`

---

### Task 6: Final Verdict + Closeout

**Files:**
- Create: `docs/handover/2026-10-06-phase4-p4-3-redesign2-structural-trust-evaluation.md`
- Modify: `tools/data/evaluation/p4-3-redesign2-ocr/README.md`
- Modify: `docs/current-work.md`

**Interfaces:**
- Final verdict is exactly one:
  - `P4_3_REDESIGN2_APPROVED_FOR_DEPENDENCY_REVIEW`
  - `P4_3_REDESIGN2_CONDITIONALLY_APPROVED`
  - `P4_3_REDESIGN2_REJECTED`
- Conditional approval is allowed only when mandatory single-page Gates A-C and Gate E pass and the remaining restriction is Gate D `MULTIPAGE_NOT_APPROVED`.
- Any failure in structural trust, isolation, operational fail-closed behavior, or semantic determinism is `REJECTED`.
- No verdict approves product dependency or P4-3B.

- [ ] **Step 1: Write final-verdict assertions**

Assert:
- Gate A/B/C/E must pass for any approved result;
- Gate D approved -> eligible for `APPROVED_FOR_DEPENDENCY_REVIEW`;
- Gate D not approved with mandatory gates pass -> `CONDITIONALLY_APPROVED` with explicit single-page restriction;
- any mandatory gate failure -> `REJECTED`;
- raw confidence alone never produces rejection or approval;
- dependency remains `NOT_APPROVED`;
- P4-3B remains `BLOCKED`;
- `ProductionAction=NONE`.

- [ ] **Step 2: Run all implemented groups**

Run targeted groups that the reached gates authorize, then:

`pwsh -NoProfile -File .\tools\data\evaluation\p4-3-redesign2-ocr\test-evaluation.ps1 -Group All ...`

`All` may pass only if every gate required by the reached verdict has actually been executed. It must not manufacture green placeholders for skipped mandatory gates.

If Gate A/B failed earlier, Task 6 runs rejection-specific closeout assertions instead of implementing/running skipped downstream gates.

- [ ] **Step 3: Run repository verification**

Run:
- historical helper locked restore/build;
- all current `tools/data/test-*.ps1`;
- `git diff --check` against the approved plan base;
- historical P4-3A diff = 0;
- historical P4-3A2 diff = 0;
- protected-path diff = 0.

Record Android local as `NOT_RUN_EVALUATION_ONLY` unless scope unexpectedly touched product paths, in which case stop instead of expanding scope.

- [ ] **Step 4: Write closeout evidence**

Handover must include:
- exact branch/head;
- runtime/model identities and hashes;
- Gate A structural matrix;
- confidence diagnostics showing no threshold authority;
- business isolation result;
- operational/fault/resource result;
- multipage scope;
- Windows/Ubuntu determinism level;
- executed and skipped tests;
- historical/protected diffs;
- final verdict;
- remaining risks;
- dependency status `NOT_APPROVED`;
- P4-3B `BLOCKED`;
- next action.

- [ ] **Step 5: Update current-work and README**

Preserve P4-3A and P4-3A2 rejection history. Add Redesign 2 as a new cycle; never rewrite A2 as if it passed retroactively.

- [ ] **Step 6: Commit**

`git add docs/current-work.md docs/handover/2026-10-06-phase4-p4-3-redesign2-structural-trust-evaluation.md tools/data/evaluation/p4-3-redesign2-ocr/README.md`

`git commit -m "docs: close out P4-3 redesign2 OCR evaluation"`

- [ ] **Step 7: Human review before push/PR/merge**

Report:
- changed files;
- implementation/evaluation result;
- tests run;
- tests not run;
- remaining risks;
- next work;
- current Phase 4 status.

Do not push, open PR, approve product dependency, or begin P4-3B until explicit human review.

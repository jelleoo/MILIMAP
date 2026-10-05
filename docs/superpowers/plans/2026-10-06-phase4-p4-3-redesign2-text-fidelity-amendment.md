# Phase 4 P4-3 Redesign 2 Text Fidelity Amendment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the mandatory evaluation-only Gate A2 text-fidelity qualification after the already-passed Gate A1 structural evaluation, without rewriting historical evidence, changing OCR runtime behavior, or advancing to business isolation until A2 is human-reviewed.

**Architecture:** Preserve the current Redesign 2 implementation commits as the completed runtime boundary and Gate A1 structural checkpoint. Add a separate fidelity layer inside the existing `tools/data/evaluation/p4-3-redesign2-ocr/` harness that compares structurally reconstructed clear-fixture cell text against pre-existing synthetic ground truth authored in the historical P4-3A fixture generator. Expected text never enters the structural resolver or product runtime; Gate A2 only qualifies or rejects the fixed OCR candidate.

**Tech Stack:** PowerShell 7 evaluation harness, retained .NET 8/PdfPig 0.1.16 grid helper, exact Tesseract 5.5.3 configuration already used by Gate A1, historical P4-3A clear fixture generator/manifest read-only.

**Spec:** `docs/superpowers/specs/2026-10-06-phase4-p4-3-ocr-trust-redesign2.md` at approved amendment commit `ab2fc04e38f3957077c73a6b416ad9fa643d07e8`.

## Execution Checkpoint

Continue the existing local implementation branch/worktree only after verifying:

- branch: `codex/phase4-p4-3-redesign2-structural-trust-evaluation`;
- Task 1 commit exists unchanged: `136f21633a5782335813392da4b5da19c9bf892d`;
- Gate A1 / current HEAD exists unchanged: `f8d023fed151fe6f93ea580ecc9507d4776b6925`;
- worktree is clean before amendment work;
- Task 1 result remains PASS;
- Task 2 result is recorded as `GATE_A1_STRUCTURAL_PASS`, not as a combined A1+A2 pass.

Do not amend or rewrite either completed implementation commit.

## Global Constraints

- Historical `tools/data/evaluation/p4-3a-ocr/**` and `tools/data/evaluation/p4-3a2-ocr/**` remain read-only.
- Protected/product paths remain unchanged: `tools/data/pdf-native/**`, `tools/data/lib/**`, `data/canonical/**`, `data/seed/**`, `apps/**`.
- OCR engine/model/config, PSM roles, geometry, overlap policy, ratio `0.25`, and structural completeness behavior remain unchanged from approved Gate A1.
- Raw confidence remains `DIAGNOSTIC_ONLY_V1`; Gate A2 decisions never use a confidence threshold.
- Expected text is evaluation-only and may not enter `Resolve-P43R2OcrCells`, runtime OCR invocation, business binding, locator, claim evaluation, or product code.
- Gate A2 authority is exact normalized text equality against historical synthetic ground truth only.
- Allowed normalization is versioned `TEXT_FIDELITY_NORMALIZATION_V1`: CRLF -> LF, leading/trailing whitespace trim, repeated horizontal whitespace within a line -> one ASCII space, deterministic line-ending representation.
- Forbidden normalization: character/jamo correction, Unicode look-alike replacement that changes characters, punctuation deletion, numeric correction, edit distance, fuzzy matching, semantic/pronunciation equivalence.
- Gate A2 mandatory roles are header, business-name, and benefit cells. Whole-table 12-cell fidelity is reported as an additional metric.
- Any mandatory mismatch -> `GATE_A2_TEXT_FIDELITY_REJECTED` and `P4_3_REDESIGN2_REJECTED`.
- Missing/corrupt ground truth or fixture identity/hash mismatch -> `GATE_A2_TEXT_FIDELITY_NOT_EVALUATED`; Gate B remains blocked.
- Only A1 PASS + A2 PASS -> `PRE_BUSINESS_TRUST_PASS`.
- Task 3 and later tasks remain blocked until human review explicitly approves continuation after Gate A2.
- Product dependency remains `NOT_APPROVED`; P4-3B remains `BLOCKED`; `ProductionAction=NONE`.

## Ground Truth Authority

Gate A2 must not invent a new answer key.

Read-only authority:

- `tools/data/evaluation/p4-3a-ocr/fixtures/generate-fixtures.py`
  - Git blob SHA: `6231ed473349063ce3b0d12fc7b2cff0bef1d114`
  - authored clear table:
    - row 1: `업체명 | 주소 | 전화번호 | 혜택`
    - row 2: `가상 가람 식당 | 가상시 가람로 12 | 031-123-4567 | 시험 할인 10%`
    - row 3: `가상 누리 식당 | 가상시 누리로 23 | 031-234-5678 | 시험 할인 20%\n방문 시 적용`
- `tools/data/evaluation/p4-3a-ocr/fixtures/manifest.json`
  - Git blob SHA: `cde2a581ec2c4a1fb26481992908b5dcab2740ac`
  - `gray.pdf` SHA-256:
    `07182f75f5305bb4611458aeaea880aa57fa78d120030b0f9b6446bd56e5ec17`
  - `rgb.pdf` SHA-256:
    `415645682f805899bdc0852feefec37ae596a3821b97a7ab344fc7d267c61c24`

The implementation may copy these historical literals into a Redesign 2-local evaluation constant for deterministic testing, but must assert the historical generator/manifest identity and fixture hashes before treating the copy as valid ground truth. OCR output must never generate, update, or auto-correct this authority.

## File Structure

**Modify**
- `tools/data/evaluation/p4-3-redesign2-ocr/run-evaluation.ps1` — add fidelity normalization, historical ground-truth contract, per-cell comparison, Gate A2 result, and pre-business gate calculation.
- `tools/data/evaluation/p4-3-redesign2-ocr/test-evaluation.ps1` — add `TextFidelity` test group and gate assertions.
- `tools/data/evaluation/p4-3-redesign2-ocr/README.md` — rename previous Gate A result to Gate A1 and document A2 semantics/current status.

**Read only**
- historical generator/manifest and clear Gray/RGB PDFs listed above.

No new fixture PDF, OCR model, external dependency, or product file is created.

## Review Focus

1. **A structurally accepted wrong Korean character** must fail fidelity even if confidence is high or provenance is perfect; TextFidelity tests require exact normalized mismatch.
2. **A low-confidence correct string** must pass fidelity; tests use a structurally accepted word/cell with low raw confidence and unchanged expected text.
3. **Ground-truth drift or wrong fixture bytes** must yield `NOT_EVALUATED`, never PASS or REJECT based on an untrusted answer key.
4. **Whitespace representation differences** must normalize only within `TEXT_FIDELITY_NORMALIZATION_V1`; punctuation/characters/numbers remain material.
5. **Expected text must not leak into structural or product behavior**; tests inspect the Redesign 2 structural resolver signature and protected-path diff.

---

### Task 2B.1: Historical Ground Truth Contract + Fidelity Normalization

**Files:**
- Modify: `tools/data/evaluation/p4-3-redesign2-ocr/run-evaluation.ps1`
- Modify: `tools/data/evaluation/p4-3-redesign2-ocr/test-evaluation.ps1`

**Interfaces:**
- `Get-P43R2ClearFixtureGroundTruth` -> object containing:
  - `Policy='TEXT_FIDELITY_GROUND_TRUTH_V1'`
  - historical generator blob SHA;
  - historical manifest blob SHA;
  - expected Gray/RGB fixture SHA-256;
  - 12 fixed cells with `CellId`, `Row`, `Column`, `FieldRole`, `ExpectedText`.
- `Normalize-P43R2FidelityText -Text <string>` -> normalized string under `TEXT_FIDELITY_NORMALIZATION_V1`.
- Mandatory field roles:
  - row 1 columns 1-4 -> `HEADER`;
  - rows 2-3 column 1 -> `BUSINESS_NAME`;
  - rows 2-3 column 4 -> `BENEFIT`;
  - address/phone cells remain `AUXILIARY` for all-cell reporting.

- [ ] **Step 1: Write failing TextFidelity contract tests**

Assert:
- historical generator/manifest files exist and remain unmodified;
- Gray/RGB fixture hashes exactly match the approved manifest values;
- the Redesign 2 ground-truth object contains exactly 12 cells and the literal table above;
- mandatory roles contain 4 header + 2 business-name + 2 benefit cells;
- `Normalize-P43R2FidelityText` converts CRLF to LF, trims outer whitespace, folds repeated horizontal whitespace within lines, and preserves line structure deterministically;
- changing `업체명` to `업쳬명`, deleting punctuation, changing a digit, or changing any other character remains unequal after normalization;
- no fuzzy/edit-distance/semantic matcher is exposed.

- [ ] **Step 2: Run TextFidelity and verify RED**

Run:
`pwsh -NoProfile -File .\tools\data\evaluation\p4-3-redesign2-ocr\test-evaluation.ps1 -Group TextFidelity`

Expected: FAIL because the fidelity contract/functions do not exist.

- [ ] **Step 3: Implement ground-truth + normalization functions**

Use the historical authored table only. Keep the constant evaluation-local. Do not parse OCR output to build expected text and do not call the historical fixture generator to rewrite fixtures.

- [ ] **Step 4: Re-run TextFidelity contract**

Expected: PASS for source/hash/normalization assertions.

- [ ] **Step 5: Commit**

`git add tools/data/evaluation/p4-3-redesign2-ocr/run-evaluation.ps1 tools/data/evaluation/p4-3-redesign2-ocr/test-evaluation.ps1`

`git commit -m "test: add P4-3 redesign2 text fidelity contract"`

---

### Task 2B.2: Gate A2 Per-cell Fidelity Evaluation

**Files:**
- Modify: `tools/data/evaluation/p4-3-redesign2-ocr/run-evaluation.ps1`
- Modify: `tools/data/evaluation/p4-3-redesign2-ocr/test-evaluation.ps1`

**Interfaces:**
- `Evaluate-P43R2TextFidelity -Fixture <string> -FixtureHash <string> -StructuralStatus <string> -CellText <object[]> -WordEvidence <object[]>` -> result with:
  - `Gate='A2_TEXT_FIDELITY'`
  - `NormalizationPolicy='TEXT_FIDELITY_NORMALIZATION_V1'`
  - `Status='PASS|REJECTED|NOT_EVALUATED'`
  - `Code='GATE_A2_TEXT_FIDELITY_PASS|GATE_A2_TEXT_FIDELITY_REJECTED|GATE_A2_TEXT_FIDELITY_NOT_EVALUATED'`
  - `MandatoryMatchCount`, `MandatoryCellCount=8`
  - `AllCellMatchCount`, `AllCellCount=12`
  - per-cell evidence: `Fixture, CellId, FieldRole, ExpectedText, ReconstructedText, NormalizedExpected, NormalizedActual, Status, RawWordConfidences`.
- Cell status is exactly `FIDELITY_MATCH|FIDELITY_MISMATCH|FIDELITY_NOT_EVALUATED`.

- [ ] **Step 1: Write failing per-cell fidelity tests**

Assert:
- exact expected/actual -> `FIDELITY_MATCH`;
- low raw confidence with exact text -> `FIDELITY_MATCH`;
- high raw confidence with one wrong Korean character -> `FIDELITY_MISMATCH`;
- one wrong digit or punctuation character -> `FIDELITY_MISMATCH`;
- allowed whitespace-only representation difference -> `FIDELITY_MATCH`;
- source structural status other than `COMPLETE` -> `NOT_EVALUATED`;
- wrong Gray/RGB fixture hash -> `NOT_EVALUATED`;
- missing/duplicate expected or reconstructed cell -> `NOT_EVALUATED`, never silently dropped;
- any mandatory mismatch -> gate `REJECTED`;
- auxiliary-only mismatch is reported in all-cell metric but does not independently reject v1 mandatory fidelity;
- raw confidence values are preserved in evidence but do not change the equality result.

- [ ] **Step 2: Run TextFidelity and verify RED**

Expected: FAIL before `Evaluate-P43R2TextFidelity` exists.

- [ ] **Step 3: Implement the minimal per-cell evaluator**

Compare only normalized expected and reconstructed text after structural `COMPLETE` and ground-truth/fixture identity checks. Do not repair actual text or choose OCR alternatives.

- [ ] **Step 4: Re-run TextFidelity**

Expected: synthetic unit controls PASS.

- [ ] **Step 5: Commit**

`git add tools/data/evaluation/p4-3-redesign2-ocr/run-evaluation.ps1 tools/data/evaluation/p4-3-redesign2-ocr/test-evaluation.ps1`

`git commit -m "test: evaluate P4-3 redesign2 text fidelity"`

---

### Task 2B.3: Execute Gate A2 on Existing Clear Evidence + Human Review Stop

**Files:**
- Modify: `tools/data/evaluation/p4-3-redesign2-ocr/run-evaluation.ps1`
- Modify: `tools/data/evaluation/p4-3-redesign2-ocr/test-evaluation.ps1`
- Modify: `tools/data/evaluation/p4-3-redesign2-ocr/README.md`

**Interfaces:**
- `Invoke-P43R2GateA2 -Executable -ModelPath` reuses the existing fixed Gate A1 clear Gray/RGB PSM11 path and their structural reconstruction, then applies `Evaluate-P43R2TextFidelity`.
- `Get-P43R2PreBusinessTrustDecision -GateA1 <object> -GateA2 <object>`:
  - A1 PASS + A2 PASS -> `PRE_BUSINESS_TRUST_PASS`;
  - A2 REJECTED -> `P4_3_REDESIGN2_REJECTED / GATE_A2_TEXT_FIDELITY_REJECTED`;
  - A2 NOT_EVALUATED -> `PRE_BUSINESS_TRUST_NOT_PROVEN / GATE_A2_TEXT_FIDELITY_NOT_EVALUATED`.
- This task must not invoke Gate B.

- [ ] **Step 1: Write failing real Gate A2 assertions**

For each clear Gray/RGB PSM11 repetition:
- structural result remains `COMPLETE`;
- fixture hash matches historical authority;
- exactly 8 mandatory and 12 total cells are evaluated;
- exact per-cell expected/actual strings are reported;
- raw contributing confidences are included;
- no confidence threshold/candidate decision appears;
- repeated OCR runs yield the same fidelity statuses for the same fixture.

Also assert:
- the previously observed required-header character error, if reproduced, appears as `FIDELITY_MISMATCH` rather than a confidence failure;
- Gate B function/group is not invoked by Gate A2 execution.

- [ ] **Step 2: Run real Gate A2**

Run:
`pwsh -NoProfile -File .\tools\data\evaluation\p4-3-redesign2-ocr\test-evaluation.ps1 -Group TextFidelity -TesseractExecutable <absolute-exe> -KoreanModelPath <absolute-model>`

Expected outcome is evidence-driven, not preselected:
- all mandatory matches -> `GATE_A2_TEXT_FIDELITY_PASS`;
- >=1 mandatory mismatch -> `GATE_A2_TEXT_FIDELITY_REJECTED`;
- untrusted/missing ground truth -> `GATE_A2_TEXT_FIDELITY_NOT_EVALUATED`.

Do not alter OCR settings, normalization, fixtures, or expected text to influence the result.

- [ ] **Step 3: Re-run prior Gate A1 regression**

Run:
- Contract group;
- StructuralTrust group;
- historical A2 Contract;
- current full data suite.

Expected:
- Task 1 behavior unchanged;
- `GATE_A1_STRUCTURAL_PASS` unchanged;
- 62 existing data tests still PASS unless GitHub truth has legitimately added tests, in which case report the current exact count;
- historical A/A2/protected diffs remain zero.

- [ ] **Step 4: Update README with factual result**

Record:
- Task 1 PASS;
- Gate A1 `GATE_A1_STRUCTURAL_PASS`;
- Gate A2 exact result;
- mandatory/all-cell match counts;
- per-cell mismatches without hiding characters;
- confidence only as diagnostics;
- Task 3 status.

Do not create final closeout/current-work changes yet unless Gate A2 is rejected and human review later authorizes rejection closeout.

- [ ] **Step 5: Commit**

`git add tools/data/evaluation/p4-3-redesign2-ocr`

`git commit -m "test: run P4-3 redesign2 text fidelity gate"`

- [ ] **Step 6: HUMAN REVIEW STOP**

Always stop here.

Report:
- existing Task 1 and Gate A1 commit SHAs;
- Task 2B.1 / 2B.2 / 2B.3 commit SHAs;
- changed files;
- historical ground-truth source/blob/fixture hashes;
- Gray/RGB mandatory match counts;
- Gray/RGB all-cell match counts;
- exact mismatching cells and expected/actual values;
- contributing raw confidence for mismatches;
- Gate A2 verdict;
- `PRE_BUSINESS_TRUST_PASS` or blocked/rejected state;
- Task 3 eligibility;
- Contract / StructuralTrust / TextFidelity / data-suite results;
- historical A/A2/protected diffs;
- tests not run;
- remaining risks.

Do not start Task 3, push, open PR, merge, approve dependency, or begin P4-3B without new explicit human approval.

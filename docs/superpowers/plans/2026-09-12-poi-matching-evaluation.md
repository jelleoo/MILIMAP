# POI Matching Evaluation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the isolated Workstream C matcher that turns one validated `NormalizedBusiness` and `PoiDiscoveryBatch` into a safe, deterministic `PoiMatchResult`.

**Architecture:** `evaluate-poi-match.ps1` imports the read-only shared contract and performs candidate-local extraction only from preserved candidate name/address text. It records all comparison facts as contract evidence, discards material conflicts before tuple-based ordering, and permits a GREEN only for one unopposed strong candidate. The test script supplies complete synthetic contracts plus repository-traceable Golden fixtures; it never calls Naver or invokes A/B production flows.

**Tech Stack:** PowerShell 7, existing `poi-verification-contracts.ps1`, direct test-script assertions.

**Spec:** `docs/superpowers/specs/2026-09-10-benefit-business-verification-pipeline-design.md`; `docs/superpowers/specs/2026-09-10-poi-verification-contracts-design.md`; GitHub Issue #30.

## Global Constraints

- Base all implementation on `origin/dev` commit `2d50b14ca2720d11e7605f73bc7104cc0118734e`.
- Modify only `tools/data/lib/poi-matching/**`, `tools/data/test-evaluate-poi-match.ps1`, optional C fixture paths, and this plan.
- Do not modify shared contracts, Workstream A/B files, legacy orchestration, canonical data, Android seed/product files, dependencies, or API/auth interfaces.
- Validate both inputs with `Assert-NormalizedBusiness` and `Assert-PoiDiscoveryBatch`; reject unequal source rows.
- Use only contract-provided reason/conflict codes and set every result `ProductionAction` to `NONE`.
- Treat `PARTIAL` and `FAILED` discovery as `INCOMPLETE` + `YELLOW`; never infer closure from them.
- Evaluate material conflicts before ranking; missing information is not a conflict.
- Use deterministic boolean evidence tuples, not fuzzy scores or fixed numeric thresholds.

---

### Task 1: Define matcher behavior with failing tests

**Files:**
- Create: `tools/data/test-evaluate-poi-match.ps1`

**Interfaces:**
- Consumes: `New-NormalizedBusiness`, `New-PoiCandidate`, `New-PoiDiscoveryBatch`, and contract validators from `tools/data/lib/poi-verification-contracts.ps1`.
- Produces: executable behavior contract for `Invoke-PoiMatchEvaluation -Business $normalizedBusiness -DiscoveryBatch $poiDiscoveryBatch`.

- [ ] **Step 1: Add focused assertion and fixture helpers**

Create `Assert-Equal`, `Assert-True`, and `Assert-Throws`; construct valid synthetic business/candidate/batch records with successful discovery evidence. Keep Golden fixtures in a separate named section and cite their canonical/report source paths in comments.

- [ ] **Step 2: Add the initial failing public-interface tests**

```powershell
$result = Invoke-PoiMatchEvaluation -Business $strongBusiness -DiscoveryBatch $strongBatch
Assert-PoiMatchResult $result
Assert-Equal $result.Classification 'GREEN' 'A single strong candidate is GREEN'
Assert-Equal $result.ProductionAction 'NONE' 'C never approves production writes'
Assert-Throws { Invoke-PoiMatchEvaluation -Business $business -DiscoveryBatch $wrongRowBatch } 'Source rows must agree'
```

Also add assertions for input-contract rejection, no candidates RED, PARTIAL/FAILED INCOMPLETE YELLOW, conflict precedence, deterministic ranked keys, selected-candidate consistency, allowed reason/conflict codes, and evidence validation.

- [ ] **Step 3: Add the full safety behavior matrix**

Use synthetic fixtures for province, city/district, branch, floor/unit, competing candidates, insufficient evidence, and repeated discovery. Assert that name compatibility cannot reverse a building mismatch and that stable ordering never manufactures a GREEN winner for an evidence tie.

- [ ] **Step 4: Add repository-traceable Golden safety cases**

Create five documented fixtures using the source facts below:

```text
data/canonical/capital-area-military-benefits.csv:
  버섯집 초리골 — canonical 초리골길 12
data/canonical/reports/poi-coordinate-review-candidates-20260910-final.csv:
  버섯집 초리골 — POI 초리골길 23; 짜장마을 unresolved; 거시기닭갈비 덕정본점 at 엄상동길 22-25
data/canonical/reports/poi-coordinate-review-candidates-20260910-p3.csv:
  이지현미용실 — 26 vs POI 23; 인헤어 — 902·2동 104호 vs POI 904
```

For P3 records lacking a preserved full POI address, label the fixture as a minimal synthetic carrier of the report-confirmed building number; do not claim an unrecorded provider address. Assert the four ambiguous/rejected cases are not GREEN and assert the `거시기닭갈비` phone discrepancy alone does not create a hard conflict.

- [ ] **Step 5: Run the new test before implementation**

Run: `pwsh -NoProfile -File tools/data/test-evaluate-poi-match.ps1`

Expected: FAIL because `tools/data/lib/poi-matching/evaluate-poi-match.ps1` and `Invoke-PoiMatchEvaluation` do not exist. Record the RED result before adding production code.

- [ ] **Step 6: Commit the behavior contract**

```bash
git add tools/data/test-evaluate-poi-match.ps1 docs/superpowers/plans/2026-09-12-poi-matching-evaluation.md
git commit -m "test: define POI matching safety behavior"
```

### Task 2: Implement hard-conflict-first match evaluation

**Files:**
- Create: `tools/data/lib/poi-matching/evaluate-poi-match.ps1`
- Test: `tools/data/test-evaluate-poi-match.ps1`

**Interfaces:**
- Consumes: `Invoke-PoiMatchEvaluation -Business <NormalizedBusiness> -DiscoveryBatch <PoiDiscoveryBatch>`.
- Produces: a validator-clean `PoiMatchResult` with `RankedCandidateKeys`, optional `SelectedCandidate`, allowed codes, and reviewable `New-PoiMatchEvidence` records.

- [ ] **Step 1: Implement read-only contract import and safe comparison helpers**

Dot-source `../poi-verification-contracts.ps1`. Add local helpers for Korean comparison-text normalization, province aliases, full-address equality, candidate locality presence, road-context building-number extraction, branch suffix comparison, floor/unit extraction, successful repeated-discovery detection, unique code accumulation, and ordinal candidate-key ordering. Helpers return empty/missing rather than guessed values.

- [ ] **Step 2: Evaluate each candidate and preserve evidence**

For each candidate, produce `New-PoiMatchEvidence` for name, address/locality/road/building/branch/floor-unit, repeat discovery, and every applicable conflict. Compare a building number only when canonical `RoadName` is found in the candidate `RoadAddress` and a following road number is unambiguous. Record province/city-district/branch/floor-unit conflicts only where both sides supply safely comparable values.

- [ ] **Step 3: Remove conflicted candidates before deterministic ranking**

Build a candidate record with booleans for exact/compatible name, exact address, locality, road, building, branch, floor/unit, and repeated discovery. Exclude all records with a material conflict. Sort surviving records by the ordered boolean evidence tuple, then `CandidateKey` using ordinal comparison only for stable output.

- [ ] **Step 4: Classify without score thresholds**

Return `INCOMPLETE/YELLOW` with the discovery failure reason for PARTIAL/FAILED batches. For COMPLETE batches: return RED + `NO_CANDIDATE` for zero candidates, RED with conflict evidence when none survive, GREEN only for exactly one unopposed strong candidate, and YELLOW with either `MULTIPLE_PLAUSIBLE_CANDIDATES` or `INSUFFICIENT_IDENTITY_EVIDENCE` otherwise. Only GREEN has a selected candidate; every result has `ProductionAction='NONE'` and passes `Assert-PoiMatchResult`.

- [ ] **Step 5: Run the C test and fix failures**

Run: `pwsh -NoProfile -File tools/data/test-evaluate-poi-match.ps1`

Expected: PASS, including all safety-gate and validator assertions.

- [ ] **Step 6: Commit the minimal matcher**

```bash
git add tools/data/lib/poi-matching/evaluate-poi-match.ps1 tools/data/test-evaluate-poi-match.ps1
git commit -m "feat: implement POI matching evaluation"
```

### Task 3: Regression, metrics, scope audit, and review-ready PR

**Files:**
- Modify only if required by a failed C test: `tools/data/lib/poi-matching/evaluate-poi-match.ps1`, `tools/data/test-evaluate-poi-match.ps1`

**Interfaces:**
- Consumes: completed C implementation and all existing `tools/data/test-*.ps1` scripts.
- Produces: measured C fixture metrics and a clean Issue #30 PR against `dev`.

- [ ] **Step 1: Run C metrics from labeled fixtures**

Print fixture counts by expected group and result, false GREEN count, GREEN precision, manual-review rate, no-match count/rate, C API calls/row `0`, and state that Candidate Recall is not measured outside A/B/C Integration Shadow Mode.

- [ ] **Step 2: Run CI-equivalent data regression**

Run:

```powershell
Get-ChildItem -LiteralPath tools/data -Filter 'test-*.ps1' |
  Sort-Object Name |
  ForEach-Object { & $_.FullName }
```

Expected: every data test exits successfully, including `test-evaluate-poi-match.ps1`.

- [ ] **Step 3: Audit diff scope and whitespace**

Run:

```bash
git diff --check origin/dev...HEAD
git diff --name-only origin/dev...HEAD
git status --short
```

Expected: no whitespace errors, only the C matcher/test/plan paths, and no uncommitted files.

- [ ] **Step 4: Commit any regression-only correction**

```bash
git add tools/data/lib/poi-matching/evaluate-poi-match.ps1 tools/data/test-evaluate-poi-match.ps1
git commit -m "test: add golden matcher regression"
```

Run this step only if Task 3 changes tracked matcher/test files after the Task 2 commit.

- [ ] **Step 5: Create the non-merged PR**

```bash
gh pr create --base dev --head data/poi-matching-evaluation \
  --title "data: [C] add POI matching and evaluation" \
  --body "Closes #30"
```

Do not merge the pull request. Report its URL, every commit SHA, tests actually run, metrics, unmeasured Candidate Recall, and the required A/B/C Integration handoff.

# POI Contract Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the approved Phase 1 POI verification contracts as a small reusable PowerShell foundation so Workstreams A/B/C can develop independently against one shared object shape and validator set.

**Architecture:** Add one shared contract library under `tools/data/lib` and one focused PowerShell test file. The library owns constructors, constants/code validation, structural validation, coordinate-pair validation, and cross-field contract invariants only; it must not contain normalization, Naver search, matching/ranking, Golden Dataset, canonical writes, or seed writes.

**Tech Stack:** PowerShell 7+, `[pscustomobject]`, existing repository script-test pattern

**Spec:** `docs/superpowers/specs/2026-09-10-poi-verification-contracts-design.md`

## Global Constraints

- Baseline: latest `dev` after PR #25 merge (`c2d3dd617d11da690b996b94efdb2a38474f9f82` at plan creation).
- No new external dependency.
- No Room/server DB/schema change.
- No API/auth contract change.
- No canonical or Android seed write.
- Phase 1 `ProductionAction` is always `NONE`.
- Discovery `PARTIAL`/`FAILED` must never validate as a complete RED; incomplete evaluation is `YELLOW`.
- Contract changes are explicit and are not introduced silently by Workstream A/B/C.
- Existing `verify-canonical-benefit-poi.ps1` is not modified in this Issue.

---

### Task 1: Contract constants and shared validation primitives

**Files:**
- Create: `tools/data/lib/poi-verification-contracts.ps1`
- Test: `tools/data/test-poi-verification-contracts.ps1`

**Interfaces:**
- Produces: `Get-PoiVerificationContractDefinition`, `Assert-PoiContractTypeAndVersion`, `Assert-PoiCoordinatePair`, `Assert-PoiAllowedCode`
- Consumes: none beyond built-in PowerShell/.NET

- [ ] **Step 1: Write failing tests for contract version, allowed codes, and coordinate-pair rules**

Tests must verify at minimum:
- supported `ContractVersion=1` passes;
- unsupported version throws;
- unexpected `ContractType` throws;
- valid/invalid status, provider, warning, reason, conflict, and production-action codes are distinguished;
- both coordinates absent passes;
- both valid Korea-range coordinates pass;
- one coordinate without the other throws;
- nonnumeric or out-of-range coordinates throw.

- [ ] **Step 2: Run the focused test and verify failure**

Run:
```powershell
pwsh -NoProfile -File .\tools\data\test-poi-verification-contracts.ps1
```

Expected: FAIL because the shared library/functions do not yet exist.

- [ ] **Step 3: Implement minimal constants and validation helpers**

Use deterministic in-script definitions for these approved code sets:
- `AddressParseStatus`: `COMPLETE`, `PARTIAL`, `UNPARSED`
- query attempt status: `SUCCESS`, `FAILED`, `SKIPPED`
- discovery status: `COMPLETE`, `PARTIAL`, `FAILED`
- evaluation status: `COMPLETE`, `INCOMPLETE`
- classification: `GREEN`, `YELLOW`, `RED`
- provider: `NAVER_API_HUB_LOCAL`
- production action: `NONE`
- warning, reason, conflict, and query strategy codes exactly as listed in the approved spec.

`Assert-PoiCoordinatePair` must use the existing repository safety range: latitude 33.0-39.5, longitude 124.0-132.0.

- [ ] **Step 4: Run focused test and verify pass**

Run the same command and require exit code 0.

- [ ] **Step 5: Commit checkpoint**

Commit only the library/test progress for this task.

---

### Task 2: Supporting record constructors and validators

**Files:**
- Modify: `tools/data/lib/poi-verification-contracts.ps1`
- Modify: `tools/data/test-poi-verification-contracts.ps1`

**Interfaces:**
- Produces: `New-PoiQueryAttempt`, `Assert-PoiQueryAttempt`, `New-PoiDiscoveryEvidence`, `Assert-PoiDiscoveryEvidence`, `New-PoiMatchEvidence`, `Assert-PoiMatchEvidence`
- Consumes: Task 1 validation primitives

- [ ] **Step 1: Add failing positive/negative tests**

Verify exact required fields and invariants:
- `PoiQueryAttempt`: 1-based `QueryOrder`, nonnegative `ResultCount`, valid status, failed/skipped result count is 0, `ErrorCode` string present;
- `PoiDiscoveryEvidence`: valid strategy, nonempty query, 1-based order/position, nonnegative result count;
- `PoiMatchEvidence`: `EvidenceCode`, `CandidateKey`, `CanonicalValue`, `CandidateValue`, `Matched` boolean or null.

- [ ] **Step 2: Run test and verify the new cases fail**

- [ ] **Step 3: Implement minimal constructors/validators**

Constructors return `[pscustomobject][ordered]` with every contract field present. Optional strings normalize missing input to `''`; arrays are not used in these leaf records.

- [ ] **Step 4: Run focused test and verify pass**

- [ ] **Step 5: Commit checkpoint**

---

### Task 3: `NormalizedBusiness` foundation

**Files:**
- Modify: `tools/data/lib/poi-verification-contracts.ps1`
- Modify: `tools/data/test-poi-verification-contracts.ps1`

**Interfaces:**
- Produces: `New-NormalizedBusiness`, `Assert-NormalizedBusiness`
- Consumes: approved v1 field names from the spec

- [ ] **Step 1: Write failing tests**

Cover:
- all required properties are present;
- `ContractType=NormalizedBusiness`, version 1;
- `SourceRowNumber > 1`;
- missing optional text becomes `''`;
- warnings always exist as an array;
- invalid warning/address-parse code throws;
- `PreferredAddress` is either trimmed `OriginalRoadAddress`, trimmed `OriginalLotAddress`, or `''`; synthetic rewritten address is rejected;
- no parsing/business normalization behavior is performed by the constructor itself.

- [ ] **Step 2: Run focused test and verify failure**

- [ ] **Step 3: Implement minimal constructor/validator**

The constructor stores values only. It must not infer branch, road, building, floor, unit, or locality fields.

- [ ] **Step 4: Run focused test and verify pass**

- [ ] **Step 5: Commit checkpoint**

---

### Task 4: `PoiCandidate` and `PoiDiscoveryBatch` foundation

**Files:**
- Modify: `tools/data/lib/poi-verification-contracts.ps1`
- Modify: `tools/data/test-poi-verification-contracts.ps1`

**Interfaces:**
- Produces: `New-PoiCandidate`, `Assert-PoiCandidate`, `New-PoiDiscoveryBatch`, `Assert-PoiDiscoveryBatch`
- Consumes: `PoiDiscoveryEvidence[]`, `PoiQueryAttempt[]`, coordinate validator

- [ ] **Step 1: Write failing tests for candidate shape**

Verify:
- exact contract type/version;
- `CandidateKey` nonempty;
- provider valid;
- `OriginalName` and `NormalizedName` fields present;
- coordinates obey both-or-neither/range rule;
- `DiscoveredBy` always array and at least one evidence record for a discovered candidate;
- invalid nested evidence throws.

- [ ] **Step 2: Write failing tests for discovery batch semantics**

Verify:
- `SourceRowNumber > 1`;
- candidate/query arrays are always present;
- all nested candidates/attempts validate;
- `COMPLETE` cannot contain a failed query attempt that leaves unresolved discovery failure;
- `FAILED` and `PARTIAL` remain distinguishable from complete empty results;
- empty `Candidates` with all required query attempts successful/skipped may be `COMPLETE`.

- [ ] **Step 3: Run focused test and verify failure**

- [ ] **Step 4: Implement minimal constructors/validators**

Do not implement query generation, API calls, candidate dedup, or early-stop behavior.

- [ ] **Step 5: Run focused test and verify pass**

- [ ] **Step 6: Commit checkpoint**

---

### Task 5: `PoiMatchResult` invariants

**Files:**
- Modify: `tools/data/lib/poi-verification-contracts.ps1`
- Modify: `tools/data/test-poi-verification-contracts.ps1`

**Interfaces:**
- Produces: `New-PoiMatchResult`, `Assert-PoiMatchResult`
- Consumes: `PoiCandidate`, `PoiMatchEvidence[]`, approved reason/conflict codes

- [ ] **Step 1: Write failing classification-invariant tests**

Required cases:
- valid GREEN = `EvaluationStatus=COMPLETE` + non-null selected candidate + `ProductionAction=NONE`;
- GREEN without selected candidate throws;
- GREEN with INCOMPLETE throws;
- valid RED = `EvaluationStatus=COMPLETE` + selected candidate null + `ProductionAction=NONE`;
- RED with selected candidate throws;
- RED with INCOMPLETE throws;
- valid YELLOW may have or omit selected candidate;
- `EvaluationStatus=INCOMPLETE` requires `Classification=YELLOW`;
- `ProductionAction` other than `NONE` throws;
- `SurvivingCandidateCount <= EvaluatedCandidateCount`;
- ranked candidate keys and nested selected candidate validate;
- invalid reason/conflict/evidence code or shape throws.

- [ ] **Step 2: Run focused test and verify failure**

- [ ] **Step 3: Implement minimal match-result constructor/validator**

No hard-constraint, score, rank computation, or classification decision algorithm belongs here. The caller provides the result; the foundation only verifies it satisfies the approved contract.

- [ ] **Step 4: Run focused test and verify pass**

- [ ] **Step 5: Commit checkpoint**

---

### Task 6: Regression gate and final scope verification

**Files:**
- Modify only if required by test corrections: `tools/data/lib/poi-verification-contracts.ps1`, `tools/data/test-poi-verification-contracts.ps1`
- No product/data file changes

**Interfaces:**
- Consumes: complete Contract Foundation
- Produces: validated base suitable for Workstreams A/B/C

- [ ] **Step 1: Run focused contract tests**

```powershell
pwsh -NoProfile -File .\tools\data\test-poi-verification-contracts.ps1
```

Require exit code 0.

- [ ] **Step 2: Run all repository data tests**

From repository root, execute every existing `tools/data/test-*.ps1` script plus the new contract test using the same PowerShell environment. Record exact pass/fail counts; do not infer success for unrun scripts.

- [ ] **Step 3: Inspect git diff**

Confirm the implementation Issue changes only the approved contract library/test (and this plan/current-work documentation only if intentionally included). Explicitly confirm no changes under:
- `data/canonical/**`
- Android assets/source
- Room schema
- `verify-canonical-benefit-poi.ps1`

- [ ] **Step 4: Confirm no hidden business logic entered the foundation**

Search/review for provider HTTP calls, normalization regex/business parsing, ranking/scoring, canonical writes, seed writes. If present, remove them from this Issue.

- [ ] **Step 5: Create the implementation PR**

PR body must report changed files, focused tests, all data-test results, unrun tests, remaining risks, branch/head SHA, and state that Phase 1 production action remains `NONE`.

- [ ] **Step 6: Merge only after required CI/diff gates pass**

No cross-review is required unless the Issue/branch policy explicitly adds it. After merge, update `docs/current-work.md` only if needed to mark Contract Foundation as available and then create the three A/B/C implementation Issues.

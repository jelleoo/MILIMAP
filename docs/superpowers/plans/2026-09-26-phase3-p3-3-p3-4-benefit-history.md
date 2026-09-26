# Phase 3 P3-3/P3-4 Benefit History and Incremental Reuse Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Project Phase 2 Benefit results into Phase 3 observations/comparisons and safely reuse downstream deterministic work only at source-family checkpoints proven safe.

**Architecture:** A Benefit history adapter consumes existing Phase 2 result/evidence objects and trusted `ContentHash` values. A Benefit domain comparator reuses Phase 2 claim-comparison semantics instead of duplicating them. Incremental reuse is introduced through the smallest composability seam necessary; HTML/XLSX may use post-fetch reuse when safe, while MMA JSONP remains conservative until a complete evidence checkpoint is proven.

**Tech Stack:** PowerShell 7, existing Phase 2 Benefit Verification Core, Phase 3 History Core/Store.

**Spec:** `docs/superpowers/specs/2026-09-26-phase3-snapshot-incremental-change-detection-design.md`

## Global Constraints

- Phase 2 contracts/state semantics are not redesigned.
- Benefit history never converts absence into `ENDED`.
- Existing `BenefitSourceSnapshot.ContentHash` is reused; do not rehash the same raw source solely for Phase 3.
- `EVIDENCE_CHANGE_ONLY` is audit-only by default.
- `BENEFIT_CHANGE_SUSPECTED` requires comparable previous/current observations with unchanged input/execution.
- `BENEFIT_ABSENCE_SUSPECTED` requires COMPLETE safe identity absence.
- Unsupported/unsafe incremental checkpoints execute the existing Phase 2 path normally.
- ProductionAction remains `NONE`.
- No live network is required for deterministic tests.

## Review Focus

- Same source content observed at a later time must create a new observation but may reuse prior semantics.
- Canonical benefit edits must become `CANONICAL_INPUT_CHANGED`, not external benefit change.
- MMA LIST equality alone must never skip DETAIL/linkage work.
- A COMPLETE XLSX/HTML absence and a PARTIAL/FAILED locator must route differently.
- Claim/provenance reorder must not create false semantic changes.

---

### Task 1: Create the Benefit history projection adapter

**Files:**
- Create: `tools/data/lib/history/benefit-history-adapter.ps1`
- Create: `tools/data/test-benefit-history-adapter.ps1`

**Interfaces:**
- Consumes: `NormalizedBusiness`, canonical benefit row/record, `BenefitVerificationResult`, `EvidenceDiagnostics[]`.
- Produces: `New-BenefitHistoryInputProjection -BusinessId -Business -Benefit -SourceMetadata -> object`
- Produces: `New-BenefitHistoryEvidenceProjection -EvidenceDiagnostics -> object`
- Produces: `New-BenefitHistorySemanticProjection -Result -> object`
- Produces: `ConvertTo-BenefitHistoryObservation -... -> HistoryObservation`

- [ ] **Step 1: Write projection/fingerprint tests**

Pin:
- source row number/collector/note do not affect InputFingerprint;
- benefit description/target/condition/method/source URL/binding identity inputs do;
- same trusted ContentHash with different ObservedAt gives same EvidenceFingerprint;
- HTML/XLSX physical provenance movement with same validated semantic claim may change evidence but not semantic projection;
- BenefitState/ReviewClass/claim result/value/material reasons affect semantic projection;
- `ProductionAction` remains `NONE`.

- [ ] **Step 2: Run RED**

Run: `pwsh -NoProfile -File tools/data/test-benefit-history-adapter.ps1`  
Expected: FAIL.

- [ ] **Step 3: Implement minimal adapter**

Use the shared canonical serializer/fingerprint helper. Sort claim tuples by stable semantic keys. Use existing EvidenceDiagnostics `ContentHash` rather than hashing raw text/bytes again.

- [ ] **Step 4: Run GREEN**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tools/data/lib/history/benefit-history-adapter.ps1 tools/data/test-benefit-history-adapter.ps1
git commit -m "feat: add benefit history adapter"
```

### Task 2: Add the Benefit domain comparator

**Files:**
- Create: `tools/data/lib/history/compare-benefit-history.ps1`
- Create: `tools/data/test-compare-benefit-history.ps1`
- Reuse: `tools/data/lib/benefit-verification/compare-benefit-claims.ps1`

**Interfaces:**
- Produces: `Resolve-BenefitHistoryChange -PreviousProjection -CurrentProjection -> { ChangeCandidates; ReasonCodes; ChangedClaimTypes }`

- [ ] **Step 1: Write comparator tests**

Assert:
- `10% -> 20%` validated description -> `BENEFIT_CHANGE_SUSPECTED`;
- target change -> same candidate with changed claim type;
- provenance-only evidence change + same semantics -> no Benefit domain candidate;
- COMPLETE prior located -> COMPLETE current NOT_FOUND identity result -> `BENEFIT_ABSENCE_SUSPECTED`;
- PARTIAL/FAILED current locator -> no absence candidate;
- explicit Phase 2 `ENDED` remains semantic output but Phase 3 does not invent/end a lifecycle state;
- equivalent wording handled by existing `Compare-BenefitClaim` remains non-material.

- [ ] **Step 2: Run RED**

Run: `pwsh -NoProfile -File tools/data/test-compare-benefit-history.ps1`  
Expected: FAIL.

- [ ] **Step 3: Implement by calling existing Phase 2 comparison semantics**

Do not copy regex/amount/date comparison logic into Phase 3.

- [ ] **Step 4: Run GREEN plus Phase 2 comparison regression**

Run:
```bash
pwsh -NoProfile -File tools/data/test-compare-benefit-history.ps1
pwsh -NoProfile -File tools/data/test-compare-benefit-claims.ps1
pwsh -NoProfile -File tools/data/test-evaluate-benefit-state.ps1
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tools/data/lib/history/compare-benefit-history.ps1 tools/data/test-compare-benefit-history.ps1
git commit -m "feat: add benefit change candidate comparator"
```

### Task 3: Prove the smallest Phase 2 composability seam for post-fetch reuse

**Files:**
- Modify only if required after latest-`dev` inspection:
  - `tools/data/lib/benefit-evidence/benefit-source-run-context.ps1`
  - `tools/data/lib/benefit-evidence/invoke-scoped-benefit-source.ps1`
  - `tools/data/invoke-phase2-benefit-shadow-mode.ps1`
- Create: `tools/data/test-phase3-benefit-reuse-boundary.ps1`

**Interfaces:**
- Required capability: obtain a fetched COMPLETE HTML/XLSX source document and its trusted snapshot/content hash before expensive downstream scoped work, then either continue existing Phase 2 processing or reuse a prior semantic reference.
- No approved contract change to Phase 2 public result shapes unless separately escalated.

- [ ] **Step 1: Inspect the latest call path and choose the minimum seam**

Document in the Issue/PR whether existing `BenefitSourceRunContext` already permits reuse without duplicate fetch. If yes, add no Phase 2 production refactor. If not, stop and propose one narrow helper extraction preserving behavior.

- [ ] **Step 2: Write failing boundary tests**

For HTML and XLSX fixtures assert one fetch produces a trusted hash before downstream work, and continuing the normal path preserves existing outputs. For MMA assert LIST-only equality is not declared safe.

- [ ] **Step 3: Run RED**

Run: `pwsh -NoProfile -File tools/data/test-phase3-benefit-reuse-boundary.ps1`.

- [ ] **Step 4: Implement only the minimum seam**

No new parser/cache/index layer. Existing in-run payload/template caches remain the authority inside a run.

- [ ] **Step 5: Run targeted Phase 2 regressions**

Run:
```bash
pwsh -NoProfile -File tools/data/test-benefit-source-run-context.ps1
pwsh -NoProfile -File tools/data/test-phase2-scoped-html.ps1
pwsh -NoProfile -File tools/data/test-phase2-scoped-xlsx.ps1
pwsh -NoProfile -File tools/data/test-phase2-scoped-mma-jsonp.ps1
```
Expected: PASS.

- [ ] **Step 6: Commit**

Commit only if a seam was actually needed. If no production change was needed, commit the boundary test with the next task.

### Task 4: Add Benefit incremental reuse orchestration

**Files:**
- Create: `tools/data/invoke-phase3-benefit-history.ps1`
- Create: `tools/data/test-phase3-benefit-history.ps1`

**Interfaces:**
- Consumes: canonical rows with `businessId`, History Store, Phase 2 scoped runner/seam.
- Produces: `Invoke-Phase3BenefitHistory -Rows -HistoryRoot -RepositoryRevision -RequestInvoker -UseScopedEvidence -> run result`
- Result exposes observations, comparisons, review candidates, and metrics including `ReuseEligible/Applied/Rejected`, `AvoidedParseCount`, `AvoidedExtractionCount`, `AvoidedEvaluationCount`.

- [ ] **Step 1: Write reuse safety tests**

Use deterministic HTML/XLSX fixtures:
- first run computes and commits;
- second run same Input/Evidence/Execution fetches current source, creates a new observation, and reuses semantic result;
- ObservedAt differs while EvidenceFingerprint remains same;
- parse/extraction/evaluation counters do not increase on reuse;
- input change forces recompute and yields `CANONICAL_INPUT_CHANGED`;
- repository revision/version change forces recompute and yields processor change handling;
- previous/current PARTIAL/FAILED prevents reuse;
- dirty-working-tree execution flag prevents reuse;
- MMA remains conservative and does not reuse on LIST-only equality.

- [ ] **Step 2: Run RED**

Run: `pwsh -NoProfile -File tools/data/test-phase3-benefit-history.ps1`  
Expected: FAIL.

- [ ] **Step 3: Implement capability-gated reuse**

Supported initial capabilities:
- scoped HTML: POST_FETCH only when fetched/qualified evidence boundary is COMPLETE and prior comparable observation is compatible;
- scoped XLSX: POST_FETCH under the same rule using trusted raw-byte ContentHash/index path;
- MMA JSONP: NONE unless this task can prove a complete safe evidence checkpoint without architecture change. Default is recompute.

- [ ] **Step 4: Run GREEN and safety regressions**

Run the new test plus scoped HTML/XLSX/MMA and Phase 2 shadow tests.  
Expected: PASS, `ProductionAction != NONE = 0`.

- [ ] **Step 5: Commit**

```bash
git add tools/data/invoke-phase3-benefit-history.ps1 tools/data/test-phase3-benefit-history.ps1
git commit -m "feat: add benefit history incremental reuse"
```

### Task 5: P3-3/P3-4 final gate

**Files:**
- No new production files expected.

- [ ] **Step 1: Run all Benefit Phase 3 targeted tests**
- [ ] **Step 2: Run all relevant Phase 2 regressions**
- [ ] **Step 3: Confirm no protected-path writes and no new live request requirement**
- [ ] **Step 4: Run full `tools/data/test-*.ps1` once on final PR HEAD**
- [ ] **Step 5: Report actual avoided work metrics and remaining bottleneck**

The report must state that provider fetch reduction is not generally achieved yet and that MMA may remain non-reused by design.

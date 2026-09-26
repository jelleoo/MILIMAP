# Phase 3 P3-0 Stable Business Identity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one immutable opaque `businessId` to every canonical business row without changing any existing canonical value, Android seed identity, or release semantics.

**Architecture:** A small identity library owns format/uniqueness validation. An explicit one-time migration script assigns `biz-<32 lowercase hex>` IDs and atomically replaces the canonical CSV only after a full round-trip check. Existing data pipelines continue to read their named columns and ignore `businessId` unless Phase 3 explicitly consumes it.

**Tech Stack:** PowerShell 7, .NET `Guid`, CSV import/export, existing GitHub Actions `verify-data`.

**Spec:** `docs/superpowers/specs/2026-09-26-phase3-snapshot-incremental-change-detection-design.md`

## Global Constraints

- `businessId` format is exactly `^biz-[0-9a-f]{32}$`.
- New IDs are issued only by explicit migration/assignment code using `.NET Guid.NewGuid().ToString("N")`.
- IDs are opaque and never recomputed from name/address/phone/location.
- Existing canonical row count and every pre-existing field value must remain unchanged.
- Android `seed-*` IDs remain unchanged.
- Existing row-number-based release tooling remains unchanged.
- No new external dependency.
- No automatic canonical write after P3-0.
- No benefit value may be invented or changed.

## Review Focus

- CSV values containing commas/quotes/newlines must survive migration semantically unchanged.
- Re-running the migration against an already migrated canonical file must never issue replacement IDs.
- Duplicate, missing, uppercase, or malformed IDs must fail validation rather than being silently repaired.
- A partial/temp write failure must leave the original canonical file intact.
- Existing converters/release builders must produce the same product data because they must ignore the added column.

---

### Task 1: Add the canonical business ID contract

**Files:**
- Create: `tools/data/lib/identity/canonical-business-id.ps1`
- Create: `tools/data/test-canonical-business-id.ps1`

**Interfaces:**
- Produces: `Test-CanonicalBusinessId -Value <string> -> bool`
- Produces: `Assert-CanonicalBusinessId -Value <string>`
- Produces: `Assert-CanonicalBusinessIds -Rows <object[]> -> void`
- Produces: `New-CanonicalBusinessId -> string`

- [ ] **Step 1: Write the failing tests**

In `test-canonical-business-id.ps1`, add assertions for:
- `biz-0123456789abcdef0123456789abcdef` accepted;
- missing/blank rejected;
- uppercase hex rejected;
- wrong prefix/length rejected;
- duplicate IDs across two rows rejected;
- `New-CanonicalBusinessId` matches the exact regex and two successive calls differ.

- [ ] **Step 2: Run the test to verify RED**

Run: `pwsh -NoProfile -File tools/data/test-canonical-business-id.ps1`  
Expected: FAIL because the identity functions do not exist.

- [ ] **Step 3: Implement the minimal contract**

Implement the four exact interfaces in `canonical-business-id.ps1`. Use ordinal duplicate detection. `New-CanonicalBusinessId` returns `'biz-' + [Guid]::NewGuid().ToString('N')`.

- [ ] **Step 4: Run the targeted test**

Run: `pwsh -NoProfile -File tools/data/test-canonical-business-id.ps1`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tools/data/lib/identity/canonical-business-id.ps1 tools/data/test-canonical-business-id.ps1
git commit -m "feat: add canonical business id contract"
```

### Task 2: Add the explicit one-time migration tool

**Files:**
- Create: `tools/data/add-canonical-business-ids.ps1`
- Create: `tools/data/test-add-canonical-business-ids.ps1`

**Interfaces:**
- Consumes: P3-0 Task 1 identity helpers.
- Produces: `Invoke-CanonicalBusinessIdMigration -InputCsv <string> -OutputCsv <string> -> summary object`
- Script CLI parameters: `-InputCsv`, `-OutputCsv`; migration never defaults to the repository canonical path.

- [ ] **Step 1: Write the failing migration tests**

Use temp CSV fixtures and assert:
- a file with no `businessId` gains one valid unique ID per row;
- all original property values compare equal after import before/after;
- row order/count are unchanged;
- an already fully migrated file preserves every existing ID;
- mixed missing/present IDs fail closed rather than partially assigning;
- malformed/duplicate existing IDs fail;
- input and output must be distinct explicit paths;
- a simulated write/validation failure leaves the input file untouched.

- [ ] **Step 2: Run RED**

Run: `pwsh -NoProfile -File tools/data/test-add-canonical-business-ids.ps1`  
Expected: FAIL because migration function/script does not exist.

- [ ] **Step 3: Implement migration staging**

Implement `Invoke-CanonicalBusinessIdMigration` so it:
1. imports the complete input;
2. rejects mixed/invalid pre-existing IDs;
3. adds `businessId` as the first column only when every row lacks it;
4. writes to a caller-selected output/temp path;
5. re-imports output and verifies row count, IDs, and all old field values;
6. returns `Rows`, `AssignedCount`, `PreservedCount`, `Validated=$true`.

Do not replace repository canonical in this task.

- [ ] **Step 4: Run targeted tests**

Run: `pwsh -NoProfile -File tools/data/test-add-canonical-business-ids.ps1`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tools/data/add-canonical-business-ids.ps1 tools/data/test-add-canonical-business-ids.ps1
git commit -m "feat: add business id migration tool"
```

### Task 3: Migrate the canonical CSV once and pin it with a repository validation test

**Files:**
- Modify: `data/canonical/capital-area-military-benefits.csv`
- Create: `tools/data/test-canonical-business-ids.ps1`

**Interfaces:**
- Consumes: Task 1 validator and Task 2 explicit migration.
- Produces: repository-level invariant that all 496 canonical rows have valid unique IDs.

- [ ] **Step 1: Add the repository validation test before changing canonical**

The test imports `data/canonical/capital-area-military-benefits.csv`, expects exactly 496 rows, requires `businessId` on every row, and calls `Assert-CanonicalBusinessIds`.

- [ ] **Step 2: Run RED**

Run: `pwsh -NoProfile -File tools/data/test-canonical-business-ids.ps1`  
Expected: FAIL because current canonical has no `businessId`.

- [ ] **Step 3: Generate the migrated CSV into a temporary path**

Run the explicit migration against the canonical input and a temp output. Do not hand-edit IDs.

- [ ] **Step 4: Verify the migration before replacement**

Compare imported old/new rows excluding `businessId` and assert:
- 496 rows before and after;
- the original 22 columns remain present;
- every original field value is equal by row;
- 496 valid unique IDs exist.

- [ ] **Step 5: Replace canonical atomically and rerun the validator**

Replace only after Step 4 succeeds.  
Run: `pwsh -NoProfile -File tools/data/test-canonical-business-ids.ps1`  
Expected: PASS.

- [ ] **Step 6: Verify existing product conversion semantics**

Run:
```bash
pwsh -NoProfile -File tools/data/test-convert-benefits.ps1
pwsh -NoProfile -File tools/data/test-build-release-benefit-seed.ps1
pwsh -NoProfile -File tools/data/test-release-artifact-pipeline.ps1
```
Expected: PASS with no required Android seed schema change.

- [ ] **Step 7: Check protected diffs**

Confirm this task changes canonical only by adding the new ID column/values and does not modify `data/seed/**` or `apps/**`.

- [ ] **Step 8: Commit**

```bash
git add data/canonical/capital-area-military-benefits.csv tools/data/test-canonical-business-ids.ps1
git commit -m "data: assign stable canonical business ids"
```

### Task 4: Final P3-0 regression gate

**Files:**
- No new production files expected.

**Interfaces:**
- Produces: merge-ready P3-0 evidence.

- [ ] **Step 1: Run all P3-0 targeted tests**

Run:
```bash
pwsh -NoProfile -File tools/data/test-canonical-business-id.ps1
pwsh -NoProfile -File tools/data/test-add-canonical-business-ids.ps1
pwsh -NoProfile -File tools/data/test-canonical-business-ids.ps1
```
Expected: PASS.

- [ ] **Step 2: Run the full data suite once on final HEAD**

Run:
```bash
pwsh -NoProfile -Command "Get-ChildItem tools/data -Filter 'test-*.ps1' | Sort-Object Name | ForEach-Object { & $_.FullName }"
```
Expected: all PASS.

- [ ] **Step 3: Run `git diff --check` and protected-path diff review**

Expected: no whitespace errors; no `data/seed/**` or `apps/**` changes.

- [ ] **Step 4: Record implementation report**

Report changed files, implementation, tests run/not run, remaining risks, next work, and concise Phase 3 progress. P3-0 does not authorize any later canonical mutation.

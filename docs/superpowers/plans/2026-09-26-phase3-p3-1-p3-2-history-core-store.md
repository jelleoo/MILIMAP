# Phase 3 P3-1/P3-2 History Core and Store Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the deterministic shared History Core plus crash-safe file store used by both Benefit and Location without teaching the core any Phase 1/2 domain semantics.

**Architecture:** P3-1 defines immutable contracts, canonical serialization, four fingerprint utilities, and common comparison precedence. P3-2 persists immutable artifacts/observations/comparisons using staging, committed run manifests, rebuildable indexes, a short exclusive writer lock, and baseline compare-and-swap.

**Tech Stack:** PowerShell 7, built-in .NET SHA-256/filesystem/JSON, no external libraries.

**Spec:** `docs/superpowers/specs/2026-09-26-phase3-snapshot-incremental-change-detection-design.md`

## Global Constraints

- History is file-based under an explicit caller-provided root, never the product DB.
- History Core contains no Naver/MMA/HTML/XLSX/domain enum interpretation.
- `HistoryContractVersion=1`, `FingerprintSchemaVersion=1`, `ComparatorVersion=1`.
- Observations and comparisons are immutable once committed.
- Latest indexes are derived caches and must be rebuildable.
- Only COMMITTED runs may supply baselines.
- `LatestObservation` and `LatestComparableObservation` are separate.
- Single writer uses built-in .NET exclusive file access only during commit.
- No automatic retry/merge when the expected baseline moved.
- No canonical/seed/apps write.

## Review Focus

- Malicious/invalid IDs or path fragments must never escape the supplied history root.
- Corrupt or stale indexes must fail closed or rebuild from committed history, never silently override truth.
- Crash after manifest commit but before index update must remain recoverable.
- Two writers from the same baseline must not both commit a stale comparison chain.
- Canonical serialization must remain invariant under culture and declared order-insensitive array reorder.

---

### Task 1: Define immutable history contracts

**Files:**
- Create: `tools/data/lib/history/history-contracts.ps1`
- Create: `tools/data/test-history-contracts.ps1`

**Interfaces:**
- Produces: `New-HistoryArtifactReference`, `Assert-HistoryArtifactReference`
- Produces: `New-HistoryObservation`, `Assert-HistoryObservation`
- Produces: `New-ObservationComparison`, `Assert-ObservationComparison`
- Produces: `New-HistoryRunManifest`, `Assert-HistoryRunManifest`
- Produces: `New-HistoryIndexEntry`, `Assert-HistoryIndexEntry`

- [ ] **Step 1: Write failing contract tests**

Pin exact allowed values:
- Domain: `LOCATION|BENEFIT`
- OperationalStatus: `COMPLETE|PARTIAL|FAILED`
- RunCommitStatus: `PREPARED|COMMITTED|ABORTED`
- ExecutionStatus: `COMPLETE|PARTIAL|FAILED`
- DeltaDimensions: `INPUT|EVIDENCE|SEMANTIC|EXECUTION`

Tests reject malformed business IDs, blank fingerprints, duplicate artifact references, previous/current self-linkage, unknown codes, and malformed committed manifests.

- [ ] **Step 2: Run RED**

Run: `pwsh -NoProfile -File tools/data/test-history-contracts.ps1`  
Expected: FAIL.

- [ ] **Step 3: Implement minimal constructors/assertions**

Use explicit ordered objects and exact version fields. Do not add Location/Benefit-specific properties.

- [ ] **Step 4: Run GREEN**

Run: `pwsh -NoProfile -File tools/data/test-history-contracts.ps1`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tools/data/lib/history/history-contracts.ps1 tools/data/test-history-contracts.ps1
git commit -m "feat: add phase3 history contracts"
```

### Task 2: Add one canonical serializer and fingerprint helper

**Files:**
- Create: `tools/data/lib/history/history-fingerprints.ps1`
- Create: `tools/data/test-history-fingerprints.ps1`

**Interfaces:**
- Consumes: Task 1 contracts.
- Produces: `ConvertTo-HistoryCanonicalJson -Value <object> -OrderInsensitivePaths <string[]> -> string`
- Produces: `Get-HistorySha256 -Text <string> -> 64-char lowercase hex`
- Produces: `Get-HistoryFingerprint -Projection <object> -SchemaVersion 1 -OrderInsensitivePaths <string[]> -> string`
- Produces: `New-HistoryFingerprintSet -InputProjection <object> -EvidenceProjection <object> -SemanticProjection <object> -ExecutionProjection <object> -> object` with exactly `InputFingerprint`, `EvidenceFingerprint`, `SemanticFingerprint`, and `ExecutionFingerprint`.
- Produces: `Get-HistoryDeltaDimensions -Previous <HistoryObservation> -Current <HistoryObservation> -> string[]`

- [ ] **Step 1: Write the fingerprint mutation matrix**

Tests cover:
- same semantic object with reordered hashtable/property construction -> same JSON/hash;
- declared order-insensitive arrays reordered -> same hash;
- order-sensitive array reordered -> different hash;
- `$null` distinct from empty string/empty array;
- invariant floating-point representation under non-English current culture;
- schema version participates in the hash;
- `New-HistoryFingerprintSet` emits all four non-empty 64-char fingerprints from the four projections;
- changing each of Input/Evidence/Semantic/Execution fingerprint yields the expected delta dimension.

- [ ] **Step 2: Run RED**

Run: `pwsh -NoProfile -File tools/data/test-history-fingerprints.ps1`  
Expected: FAIL.

- [ ] **Step 3: Implement canonical serialization**

Implement one recursive serializer with explicit type handling. Reject unsupported opaque types instead of calling arbitrary `ToString()`.

- [ ] **Step 4: Run GREEN**

Run: `pwsh -NoProfile -File tools/data/test-history-fingerprints.ps1`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tools/data/lib/history/history-fingerprints.ps1 tools/data/test-history-fingerprints.ps1
git commit -m "feat: add canonical history fingerprints"
```

### Task 3: Add common comparison precedence

**Files:**
- Create: `tools/data/lib/history/compare-history-observations.ps1`
- Create: `tools/data/test-compare-history-observations.ps1`

**Interfaces:**
- Consumes: Task 1 observations and Task 2 fingerprints.
- Produces: `Compare-HistoryObservations -Previous <HistoryObservation|null> -Current <HistoryObservation> -DomainChangeResolver <scriptblock> -> ObservationComparison`

- [ ] **Step 1: Write precedence tests**

Assert:
- no previous -> `BASELINE_ESTABLISHED`;
- current non-comparable/FAILED -> `OPERATIONAL_FAILURE` + `COMPARISON_UNAVAILABLE`;
- Input delta takes precedence over domain resolver -> `CANONICAL_INPUT_CHANGED`;
- Execution delta takes precedence -> `PROCESSOR_OUTPUT_CHANGED`;
- Evidence-only delta with unchanged semantics -> `EVIDENCE_CHANGE_ONLY`;
- only comparable observations with unchanged input/execution invoke the domain resolver.

- [ ] **Step 2: Run RED**

Run: `pwsh -NoProfile -File tools/data/test-compare-history-observations.ps1`  
Expected: FAIL.

- [ ] **Step 3: Implement precedence only**

The core does not know Location/Benefit candidate codes. The scriptblock returns domain candidates/reasons when allowed.

- [ ] **Step 4: Run GREEN**

Run: `pwsh -NoProfile -File tools/data/test-compare-history-observations.ps1`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tools/data/lib/history/compare-history-observations.ps1 tools/data/test-compare-history-observations.ps1
git commit -m "feat: add common history comparison precedence"
```

### Task 4: Build the content-addressed history store

**Files:**
- Create: `tools/data/lib/history/history-store.ps1`
- Create: `tools/data/test-history-store.ps1`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: `New-HistoryStoreLayout -Root <string> -> layout object`
- Produces: `Write-HistoryArtifact -Store <layout> -ContentHash <hex> -Extension <safe token> -Bytes/Text -> ArtifactReference`
- Produces: `Read-HistoryObservation -Store -ObservationId -> object`
- Produces: `Get-HistoryLatestEntry -Store -BusinessId -Domain -ComparableOnly -> HistoryIndexEntry|null`
- Produces: `Rebuild-HistoryIndexes -Store -> summary`

- [ ] **Step 1: Write fail-first store tests**

Cover:
- root path traversal rejection;
- three observations with A/A/B content produce 3 observations but 2 physical artifacts;
- failed latest observation does not replace latest comparable;
- PREPARED/ABORTED run data is never returned as baseline;
- deleted/stale index can be rebuilt exactly;
- malformed committed JSON/hash/reference fails closed.

- [ ] **Step 2: Run RED**

Run: `pwsh -NoProfile -File tools/data/test-history-store.ps1`  
Expected: FAIL.

- [ ] **Step 3: Implement path-safe immutable store primitives**

All paths derive from validated IDs/hash tokens. Never enumerate full artifact directories for existence checks; address artifacts directly by hash.

- [ ] **Step 4: Run GREEN**

Run: `pwsh -NoProfile -File tools/data/test-history-store.ps1`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tools/data/lib/history/history-store.ps1 tools/data/test-history-store.ps1
git commit -m "feat: add immutable phase3 history store"
```

### Task 5: Add staged run commit, writer lock, CAS, and crash recovery

**Files:**
- Create: `tools/data/lib/history/commit-history-run.ps1`
- Create: `tools/data/test-commit-history-run.ps1`

**Interfaces:**
- Consumes: Task 4 store.
- Produces: `New-HistoryRunId -> string`
- Produces: `Prepare-HistoryRun -Store -RunManifest -Artifacts -Observations -Comparisons -> prepared run`
- Produces: `Commit-HistoryRun -Store -PreparedRun -ExpectedBaselines <hashtable> -FaultInjector <scriptblock?> -> result`
- Result codes include `COMMITTED`, `BASELINE_MOVED`, `WRITER_LOCKED`, `ABORTED`.

- [ ] **Step 1: Write concurrency/crash tests**

Pin:
- lock uses exclusive handle and second writer fails fast;
- network/processing is outside this API and therefore outside lock scope;
- run A commits from obs-10, run B still expecting obs-10 -> `BASELINE_MOVED/RETRY_REQUIRED`;
- duplicate `businessId+domain` in one run rejected;
- fault after artifacts, after observations, before manifest commit -> not a baseline;
- fault after manifest commit before index update -> committed history remains valid and index rebuild recovers.

- [ ] **Step 2: Run RED**

Run: `pwsh -NoProfile -File tools/data/test-commit-history-run.ps1`  
Expected: FAIL.

- [ ] **Step 3: Implement staged publish and CAS**

Use `FileShare.None` for `.writer-lock`. Re-read latest comparable entries after acquiring the lock and before publish. Do not auto-retry.

- [ ] **Step 4: Run GREEN**

Run: `pwsh -NoProfile -File tools/data/test-commit-history-run.ps1`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tools/data/lib/history/commit-history-run.ps1 tools/data/test-commit-history-run.ps1
git commit -m "feat: add crash safe history commits"
```

### Task 6: P3-1/P3-2 regression gate

**Files:**
- No new production files expected.

**Interfaces:**
- Produces: stable shared core ready for domain adapters.

- [ ] **Step 1: Run all new core/store tests**

Run all five new `test-history-*.ps1` / comparison tests.  
Expected: PASS.

- [ ] **Step 2: Run existing Phase 1/2 contract and runner regressions**

Run:
```bash
pwsh -NoProfile -File tools/data/test-phase1-poi-shadow-mode.ps1
pwsh -NoProfile -File tools/data/test-phase2-benefit-shadow-mode.ps1
pwsh -NoProfile -File tools/data/test-benefit-source-run-context.ps1
```
Expected: PASS; one-way dependency preserved.

- [ ] **Step 3: Confirm protected-path non-write**

No changes under `data/canonical/**`, `data/seed/**`, or `apps/**`.

- [ ] **Step 4: Run full data suite once on final PR HEAD**

Expected: PASS.

- [ ] **Step 5: Record implementation report**

Include changed files, tests, unrun tests, remaining risks, next work, and Phase 3 progress.

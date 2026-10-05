# Phase 4 P4-2A PdfPig Technical Evaluation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Determine whether PdfPig 0.1.16 can safely supply the native page/text/vector geometry required by MILIMAP's bounded P4-2 PDF design, without adding a product dependency or implementing the production PDF adapter.

**Architecture:** Run PdfPig only in an isolated throwaway .NET probe, outside product code, against the current Suwon representative PDF plus independent negative/compatibility controls. Record deterministic geometry/runtime evidence, exercise the same probe on Windows and Linux CI, and end with exactly one parser-gate decision; product dependency installation and P4-2B implementation remain blocked.

**Tech Stack:** PowerShell 7, .NET 8 throwaway console probe, PdfPig 0.1.16 (temporary evaluation restore only), GitHub Actions temporary evaluation workflow, current MILIMAP repository/docs. No product dependency change.

**Spec:** `docs/superpowers/specs/2026-10-05-phase4-p4-2-pdf-native-adapter-design.md`

## Global Constraints

- Baseline: refreshed `origin/dev` must contain `53443468ec48a30c33a0b089c55357fa7d14818f` or a newer verified dev state. Current GitHub code wins if it changed.
- P4-2A is technical evaluation only. Do not implement the production PDF adapter.
- Do not add PdfPig or any PDF package to an existing repository project/lockfile/package manifest.
- Temporary `dotnet restore` of PdfPig 0.1.16 is allowed only inside the isolated evaluation workspace/workflow defined by this plan.
- Do not use a 0.1.17 prerelease build for the primary result.
- Do not modify core architecture, DB, auth, API contracts, persistent data schema, canonical data, seed data, or app code.
- Do not implement OCR, PDF scoped orchestration, `SCOPED_PDF_CELL`, run-context PDF support, or header aliases in P4-2A.
- Do not commit the Suwon PDF to the repository.
- Do not treat canonical benefit values as expected truth.
- The Suwon PDF is a native-layout/identity control, not a benefit-positive/currentness control.
- If a live source changed or is unavailable, record the exact observation; do not substitute a fake source and call it live validation.
- P4-2A ends with exactly one status:
  - `PDFPIG_APPROVED_FOR_P4_2`
  - `PDFPIG_REJECTED_EVALUATE_PDFBOX`
  - `PDF_NATIVE_PATH_BLOCKED`
- Even `PDFPIG_APPROVED_FOR_P4_2` does not authorize adding PdfPig to product code. Stop for explicit user dependency approval.
- `ProductionAction=NONE`; PDF incremental reuse remains `NONE`.
- P4-2 and Phase 4 remain incomplete after P4-2A.

## File Structure

**Create and retain**
- `docs/handover/2026-10-05-phase4-p4-2a-pdfpig-technical-evaluation.md` — authoritative P4-2A evidence and gate decision.

**Temporary evaluation artifacts — do not retain in final branch diff**
- `$env:TEMP/milimap-p42a-pdfpig-eval/` on Windows, equivalent OS temp directory on Linux — throwaway .NET probe project, restored PdfPig package, downloaded controls, JSON evidence.
- `.github/workflows/p4-2a-pdfpig-probe.yml` — temporary branch-only push workflow used solely to prove Windows/Linux runner compatibility; remove it after evidence is captured and before the final evaluation commit/PR is presented.

**Do not modify in P4-2A**
- `tools/data/lib/**`
- `tools/data/test-*.ps1`
- `apps/**`
- `data/canonical/**`
- `data/seed/**`
- product package/dependency manifests

## Review Focus

1. **Live source drift** — if the Suwon URL returns different bytes/hash or becomes unavailable, report `SOURCE_CHANGED` / `NOT_OBSERVED`; never silently reuse the prior local copy as current evidence. Task 2 pins this.
2. **Visual text vs decoded text** — Korean text that renders correctly elsewhere but decodes incorrectly in PdfPig must fail the Korean-fidelity gate rather than be hand-corrected. Task 2 pins this.
3. **Path access without usable grid semantics** — exposing vector paths is insufficient unless the probe can deterministically recover the ruled grid/cell containment needed by the approved scope. Task 3 pins this.
4. **Parser recovery on malformed/encrypted/image-only input** — a successful API call must not be counted as safe support when the adapter could not distinguish these cases fail-closed. Task 3 pins this.
5. **Platform variance** — Windows/Linux differences in letter/path counts, Unicode text, page geometry, or physical row projection must block `PDFPIG_APPROVED_FOR_P4_2`. Task 4 pins this.

---

### Task 1: Establish an Isolated PdfPig 0.1.16 Evaluation Harness

**Files:**
- Create temporarily outside the repo: `milimap-p42a-pdfpig-eval/PdfPigProbe.csproj`
- Create temporarily outside the repo: `milimap-p42a-pdfpig-eval/Program.cs`
- No retained repository file in this task.

**Interfaces:**
- Consumes: PDF file path plus optional expected text string.
- Produces: deterministic UTF-8 JSON to stdout and `evaluation.json` with exact top-level properties:
  - `ProbeSchemaVersion`
  - `PdfPigVersion`
  - `Runtime`
  - `Os`
  - `FileSha256`
  - `OpenStatus`
  - `Encrypted`
  - `Pages`
  - `Diagnostics`
- Each page record contains:
  - `PageNumber`
  - `RotationDegrees`
  - `Width`
  - `Height`
  - `LetterCount`
  - `ImageCount`
  - `PathCount`
  - `DecodedTextSha256`
  - `ContainsExpectedText`
  - `Letters` with text and bounding rectangle values sufficient for later cell-containment analysis
  - `Paths` with the public vector/path geometry needed for ruled-grid evaluation

- [ ] **Step 1: Verify the evaluation package/version without touching the repo**

From an OS temp directory:

```powershell
dotnet --info
dotnet new console --framework net8.0 --name PdfPigProbe
Set-Location PdfPigProbe
dotnet add package PdfPig --version 0.1.16
dotnet list package --include-transitive
```

Record .NET SDK/runtime, exact PdfPig version, transitive packages, restore source, and package license/project metadata in a temporary evidence note.

Expected: the package is restored only under the throwaway project/user NuGet cache. No repository manifest changes.

- [ ] **Step 2: Write the probe contract test first**

Before implementing the parser body, make the temporary program support:

```text
PdfPigProbe <pdfPath> [expectedText]
```

and write a throwaway PowerShell assertion that runs it with a nonexistent path and requires:
- non-zero exit;
- JSON diagnostic containing `FILE_NOT_FOUND`;
- no unhandled stack trace as the only machine output.

Expected RED: the initial empty console app does not satisfy the JSON contract.

- [ ] **Step 3: Run the probe contract assertion to confirm RED**

Run the throwaway assertion.

Expected: FAIL because the probe has not implemented the contract.

- [ ] **Step 4: Implement the minimal PdfPig probe**

Use PdfPig 0.1.16 public APIs only.

Required behavior:
- SHA-256 the source file before opening;
- attempt PdfPig open with no password;
- report whether encryption/password handling prevents native inspection;
- enumerate pages;
- record page dimensions/rotation;
- enumerate native letters/text;
- record image count;
- enumerate page vector paths using the public page path API;
- emit invariant-culture numeric values;
- sort/serialize output deterministically;
- never mutate or rewrite the PDF.

Do not implement MILIMAP grid reconstruction in this task.

- [ ] **Step 5: Run the harness contract to GREEN**

Run:
- nonexistent path case;
- one minimal parseable PDF available to the evaluation environment.

Expected: deterministic JSON contract; repeated runs on the same input produce the same evidence fields except explicitly excluded runtime metadata.

- [ ] **Step 6: Record, but do not commit, the harness source and package graph hash**

Hash:
- `Program.cs`;
- `PdfPigProbe.csproj`;
- `obj/project.assets.json`.

These hashes let Windows/Linux runs prove they executed the same probe/package graph.

Do not commit the throwaway project to MILIMAP.

---

### Task 2: Validate Current Suwon Korean Text and Native Geometry Access

**Files:**
- Temporary: downloaded Suwon PDF under the evaluation workspace.
- Modify later in Task 5 only: P4-2A handover.

**Interfaces:**
- Consumes: Task 1 probe.
- Produces: one `suwon-evaluation.json` plus recorded source metadata.

Representative source from the approved research:
`https://www.suwon.go.kr/webcontent/ckeditor/2026/5/28/4e5d92bd-869b-41d9-8179-cbc3ffba48c7.pdf`

Prior observation for comparison only:
- observed 2026-10-05 11:07:27 +09:00;
- SHA-256 `61fd1311b7d5a853b8fcbd5a61bf986006ad7e447aa45dbb67dfe57d0fce66d7`;
- one page;
- native Korean text;
- `고려이발관` observed in the first physical data row.

The prior hash is not expected truth. A changed current hash is a source-change observation, not an automatic failure.

- [ ] **Step 1: Fetch the live PDF into temp and record the current source observation**

Record:
- observation time;
- requested/final URL;
- HTTP status;
- redirect chain;
- content type;
- size;
- first PDF signature bytes;
- SHA-256.

If unavailable, mark live control `NOT_OBSERVED` and do not use an old local copy as current evidence.

- [ ] **Step 2: Run the probe twice against the exact downloaded bytes**

Use expected text `고려이발관`.

Assert:
- open succeeds;
- page count is at least 1;
- expected Korean string is present in native decoded text;
- page letter count > 0;
- page path count > 0;
- repeated runs produce equal page geometry, text hash, letter count, image count, and path count.

Failure of Korean decoding or deterministic native geometry blocks PdfPig approval.

- [ ] **Step 3: Compare parser output with the prior visual/layout observation without importing prior truth**

Check whether the parser exposes enough page-native letter and vector data to independently locate the observed business-name text and its surrounding ruled geometry.

Do not assert benefit/currentness fields: the representative PDF does not provide a per-business benefit-positive control.

- [ ] **Step 4: Pin live-source drift behavior**

If current SHA differs from the prior observed SHA:
- add diagnostic `SOURCE_CHANGED_SINCE_RESEARCH`;
- use only the current bytes for P4-2A evaluation;
- visually/read-only re-check the current document layout before carrying forward any prior row-count statement.

If the URL is unavailable:
- `LiveSuwonStatus=NOT_OBSERVED`;
- do not issue `PDFPIG_APPROVED_FOR_P4_2` solely from synthetic/upstream samples unless an equivalent independent Korean ruled-grid control is found and explicitly documented.

---

### Task 3: Prove Bounded Ruled-grid Feasibility and Fail-closed Input Classification

**Files:**
- Modify temporarily: evaluation probe/harness only.
- Temporary: independent/upstream control PDFs and JSON results.
- No retained product code.

**Interfaces:**
- Consumes: Task 1 page letters/paths.
- Produces: throwaway `grid-evaluation.json` with:
  - `GridCandidateCount`
  - `ClosedCellCount`
  - `AmbiguousTopology`
  - `ExpectedBusinessCell`
  - `ExpectedBusinessContainment`
  - `NegativeControls`

- [ ] **Step 1: Write the grid feasibility assertions before the temporary algorithm**

For the current Suwon control, require the probe to demonstrate:
- at least one ruled-grid candidate from actual vector geometry;
- the `고려이발관` native glyphs/text are contained by exactly one reconstructed physical cell;
- the cell is part of one deterministic row/grid topology;
- no reading-order-only or positional-column fallback is used.

Expected RED: Task 1 exposes raw paths/letters but has no grid feasibility projection.

- [ ] **Step 2: Implement only the minimum throwaway grid reconstruction needed for evaluation**

This is not production adapter code.

Use fixed, explicitly recorded tolerances for the probe run:
- normalize standard page rotation;
- derive horizontal/vertical boundary candidates from public vector path geometry;
- snap only within one fixed small tolerance selected from observed coordinate noise;
- construct closed rectangular cells;
- assign expected business-name glyph bounds only when containment is unique.

Record the exact numeric tolerances in `grid-evaluation.json`.

Do not generalize to borderless tables, merged semantic cells, or cross-page rows.

- [ ] **Step 3: Run the Suwon ruled-grid feasibility assertion to GREEN**

Expected:
- deterministic grid/cell result on repeated runs;
- exact expected-name text belongs to one physical cell;
- no ambiguous topology.

If this cannot be demonstrated, PdfPig fails the core P4-2 provenance gate regardless of text extraction success.

- [ ] **Step 4: Exercise independent negative/compatibility controls**

Use independent or upstream-licensed temporary controls where available. Record exact source URL/path, license, SHA-256, and why each is appropriate.

Probe at least:
- truncated/malformed PDF;
- encrypted/password-protected PDF;
- image-only/scanned PDF;
- multi-page digital PDF;
- a PDF without a ruled business table.

Required decision evidence:
- malformed input can be mapped to fail-closed parser failure;
- encrypted/password input can be detected/rejected for initial P4-2 scope;
- image-only input can be distinguished from safe digital-text grid support;
- non-grid native text does not become a successful ruled-grid result.

If a specific control cannot be sourced reproducibly, mark it `NOT_OBSERVED`; do not fabricate a PASS.

- [ ] **Step 5: Check resource-bounding feasibility**

Record whether PdfPig/API usage permits the future adapter to bound or pre-check:
- file size before parser open;
- page count;
- per-page letter count;
- per-page path count;
- elapsed parse time;
- process memory from the probe host;
- cancellation/process isolation options if parser internals offer no direct bound.

The evaluation does not need to implement final production limits, but it must identify a viable bounded-execution strategy. If no viable strategy exists, do not approve PdfPig.

---

### Task 4: Prove Windows/Linux Runner Reproducibility Without Retaining a Product Dependency

**Files:**
- Create temporarily on the P4-2A evaluation branch: `.github/workflows/p4-2a-pdfpig-probe.yml`
- Remove before final P4-2A branch diff is presented.
- Temporary CI artifacts: probe JSON outputs only.

**Interfaces:**
- Consumes: exact Task 1 probe source/project hashes and a redistribution-safe independent fixture/control.
- Produces: Windows/Linux GitHub Actions evidence with matching parser/package/projection fields.

- [ ] **Step 1: Create a temporary push-only evaluation workflow on the isolated P4-2A branch**

Matrix:
- `windows-latest`
- `ubuntu-latest`

Required steps:
- checkout evaluation branch;
- set up .NET 8;
- reconstruct/download the exact throwaway probe source from a branch-local temporary evaluation directory or commit the probe only for this disposable workflow commit;
- restore exact `PdfPig 0.1.16`;
- run the same redistribution-safe control;
- upload JSON evidence.

The workflow must not touch Android/product dependencies or protected data.

- [ ] **Step 2: Pin cross-platform assertions**

For the same control bytes and probe hash, require equality for:
- PdfPig version;
- file SHA-256;
- page count;
- rotation;
- width/height within exact serialized parser values or one documented representation normalization;
- native decoded text hash;
- letter count;
- image count;
- path count;
- grid candidate/cell projection used by the probe.

Any material Windows/Linux difference blocks `PDFPIG_APPROVED_FOR_P4_2` until explained and safely normalized.

- [ ] **Step 3: Run the temporary workflow and capture exact run/job evidence**

Record:
- workflow run ID;
- commit SHA;
- Windows job result;
- Linux job result;
- artifact hashes;
- any platform differences.

Do not merge this workflow.

- [ ] **Step 4: Remove the temporary workflow and throwaway harness from the branch**

Before final evaluation reporting:

```powershell
git rm .github/workflows/p4-2a-pdfpig-probe.yml
# remove any branch-local throwaway probe files if they were used for CI
git status --short
```

Expected final retained product/repo diff from P4-2A: documentation only (spec/plan/handover as applicable), with no product package reference and no workflow file.

---

### Task 5: Write the Technical Gate Decision and Stop Before Product Dependency Approval

**Files:**
- Create: `docs/handover/2026-10-05-phase4-p4-2a-pdfpig-technical-evaluation.md`
- Optionally update only after facts are proven: `docs/current-work.md`

**Interfaces:**
- Consumes: Tasks 1-4 evidence.
- Produces: one authoritative gate status and dependency recommendation.

- [ ] **Step 1: Evaluate every mandatory approval condition**

`PDFPIG_APPROVED_FOR_P4_2` requires all of:
- exact PdfPig 0.1.16 evaluation;
- Korean native decoding observed on a current independent/live control;
- public page/letter/vector APIs sufficient for the approved ruled-grid scope;
- deterministic single-cell containment demonstrated without reading-order inference;
- malformed/encrypted/image-only cases can be mapped fail-closed or the missing case is explicitly blocking;
- viable resource-bounding strategy;
- Windows/Linux runner compatibility with no unexplained material projection difference;
- no product dependency was added.

If the core PdfPig provenance/runtime gates fail but PDFBox remains realistic:
- `PDFPIG_REJECTED_EVALUATE_PDFBOX`.

If the bounded native approach itself cannot be made trustworthy:
- `PDF_NATIVE_PATH_BLOCKED`.

Do not choose the first status merely because PdfPig successfully opens the file.

- [ ] **Step 2: Write the handover**

Include:
- current dev/base SHA;
- approved spec/plan commits;
- PdfPig exact version/package graph/license findings;
- temporary probe hash;
- Suwon current observation metadata and whether source drift occurred;
- Korean decoding result;
- page/vector/grid/cell-containment result;
- negative-control results including any `NOT_OBSERVED`;
- resource-bound findings;
- Windows/Linux CI run IDs/results;
- gate decision;
- evidence that product dependency manifests were unchanged;
- tests not run and why;
- remaining risks;
- exact next decision required from the user.

If gate = `PDFPIG_APPROVED_FOR_P4_2`, the next decision is **explicit approval to add PdfPig as a product dependency**. Do not start P4-2B.

- [ ] **Step 3: Run repository-safety closeout checks**

From repo root:

```powershell
git diff --check
git diff origin/dev -- data/canonical data/seed apps
git status --short
```

Expected:
- whitespace check PASS;
- protected-path diff empty;
- no product dependency/project manifest diff;
- no temporary workflow/harness left in final diff.

Because P4-2A changes no product code, the complete data/Android suite is not a mandatory technical gate for this evaluation. Record it as `NOT_RUN_NO_PRODUCT_CODE_CHANGE` unless execution happens to modify retained executable repo code, in which case stop and reassess scope.

- [ ] **Step 4: Commit only retained evaluation documentation**

```bash
git add docs/handover/2026-10-05-phase4-p4-2a-pdfpig-technical-evaluation.md docs/current-work.md
git commit -m "docs: record P4-2A PdfPig evaluation"
```

If `docs/current-work.md` does not need a factual update yet, omit it from the commit.

- [ ] **Step 5: Stop at the dependency approval gate**

Do not:
- add PdfPig to product dependency manifests;
- implement PDF adapter files;
- modify scoped runner/run-context;
- add shared header aliases;
- create P4-2B implementation commits.

Report the gate result to the user and wait for explicit dependency approval or the next parser-evaluation decision.

---

## P4-2A Implementation Report Contract

Every P4-2A execution report must include:

- **변경한 파일**
- **조사/검증 내용**
- **실행한 probe/tests**
- **실행하지 못한 probe/tests**
- **Suwon live status**
- **Windows/Linux compatibility**
- **PdfPig package/version/license/transitive findings**
- **gate result**
- **protected-path/product-dependency diff**
- **남은 위험**
- **다음 결정**

End with:

- Phase: Phase 4 — Multi-source Adapters
- Stage: P4-2A PdfPig Technical Evaluation
- Status: exact gate state
- P4-2B: BLOCKED until explicit dependency approval

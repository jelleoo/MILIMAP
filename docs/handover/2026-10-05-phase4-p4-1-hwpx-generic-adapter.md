# Phase 4 P4-1 — HWPX Generic Adapter handover

## Authority and boundary

- Issue #113; [PR #114](https://github.com/jelleoo/MILIMAP/pull/114) targets `dev`. Exact final PR HEAD/CI are recorded in the PR and implementation report; no auto-merge.
- Refreshed base: `b0b0bb18e4e1a19e045477a884256ac51d8a9605`. P4-0 reviewed `bc36bf6a7d9dc6024e5b44294d5667c162170487` is an ancestor; PR #112 is merged.
- Approved spec/plan source commits `6e01633b09f9356bdde8ee4238f5a95931fdda4c` / `ffe96b542d34340396e5bb1c4043bf452d804c42` are included without technical edits as `88e9591` / `5271523`.
- Phase 4 is **not COMPLETE**. Next: **P4-2 PDF native adapter**.

## Implemented subset

Native ZIP/XML reader uses existing bounded package classification (256 entries, 16 MiB per entry, 64 MiB total), safe XML readers with DTD prohibited and resolver null, trusted OPF manifest/spine resolution and trusted section/paragraph namespaces. Duplicate IDs/targets, missing targets, external/traversal/non-section hrefs and malformed root fail closed. An unusable section is isolated with a PARTIAL diagnostic.

Only top-level tables with one explicit header containing BusinessName are supported. Header aliases reuse `Get-BenefitScopedHeaderMap`; no new normalization policy. Selected header/data cells must prove row/column span 1. Merged titles may be skipped, but merged semantic cells, ambiguous headers, unsupported inline objects or nested-table semantic content are rejected. Paragraph/line boundaries are LF, tabs remain TAB, runs concatenate in order, and only outer cell whitespace is trimmed. No OCR, PDF parser, legacy HWP, paragraph-only evidence, multi-row header inference, positional guessing or cross-table stitching.

Original byte-backed snapshots feed the existing `BenefitDocumentValidationIndex`. Unit and field references preserve section/table/row/cell ordinals, exact decoded SourceText, adapter/extractor/config metadata and snapshot binding. The existing locator/binding/extraction/validation consume the index; claim extraction method is `SCOPED_HWPX_CELL`. PARTIAL/FAILED/UNSUPPORTED observations retain operational state and cannot become semantic LOCATED/NOT_FOUND. Absence never implies ENDED or lifecycle truth.

Metadata:

| Field | Value |
|---|---|
| AdapterId / AdapterVersion | `HWPX_GENERIC` / `1` |
| Row ExtractionMethod | `STRUCTURED_HWPX_ROW` |
| ExtractorId / ExtractorVersion | `BUILTIN_HWPX_XML` / `1` |
| ExtractionConfigHash | `98ee91ad5a59d9e3c81508ae1ba3df75edf5fd69c847348b1319734223a325e5` |
| Claim ExtractionMethod | `SCOPED_HWPX_CELL` |

Config hash covers versions, table/unmerged/text rules, paragraph/line/tab/trim policy and the sorted existing header map. It is not a workbook or benefit truth hash.

## RED → GREEN ledger

| Task | Observed RED | GREEN / commit |
|---|---|---|
| 1 package/XML reader | `Read-InternalBenefitHwpxPackage` missing | Package/security tests PASS; `400411aa91b2cf10fa22df7151bb7c37ea40cfe8` |
| 2 table/text/provenance | `ConvertTo-BenefitHwpxObservation` missing | Byte-derived table/text/provenance tests PASS; `d46208725f6690562452b56539f6ea27f43fb059` |
| 3 run-context | Source snapshot rejected HWPX | Cache/one-parse tests PASS; `f062cd4b46699630de5de6f33325bd1a44952262` |
| 4 downstream index | Binding/extraction/validation lacked DocumentValidationIndex parameter | Scoped validation and foreign-row rejection PASS; `29384d741f994aa554d6d2e43d9da73747420e7e` |
| 5 scoped dispatch | Unsupported-format fallback produced no observation | Full HWPX scoped controls PASS; `ba1cfd0efd1f8985d2b3bacf6048e08d4a3b4983` |
| 6 regression/handover | Verification-only task; no runtime behavior added | Results below; documentation commit in branch history |

Task 3 also fixed the existing byte-copy helper's pipeline enumeration so cached binary payloads preserve `byte[]`. Locator already consumes the observation's attached document index, so no parallel locator parameter/path was added.

## Files

- New parser: `tools/data/lib/benefit-evidence/convert-hwpx-source-observation.ps1`
- Existing run-context, scoped invoke, extraction, validation and source binding helpers (optional document-index plumbing only)
- New `test-hwpx-source-observation.ps1`, `test-phase2-scoped-hwpx.ps1`, synthetic fixture builder `testdata/benefit-evidence-hwpx/test-support.ps1`
- Existing run-context/binding/extraction/validation tests
- Approved spec/plan, this handover, current-work and tools/data README

## Verification observed locally

- Pre-implementation CI-equivalent in-process data suite: **57/57 PASS**.
- Task 6 targeted tests: HWPX parser, document provenance, run-context, binding, extraction, validation, scoped HWPX/XLSX, locator, incremental reuse: all PASS.
- Final complete CI-equivalent `tools/data/test-*.ps1`, sorted and executed in one PowerShell process with ErrorActionPreference Stop: **59/59 PASS**. Includes HTML, MMA JSONP, XLSX and History/incremental regressions.
- Shared-source synthetic controls: actual requests **1**, actual package-reader calls **1**, ExternalFetchCount **1**, AdapterParseCount **1**, AdapterReuseCount **1**. The same snapshot-bound index is reused, wrapper semantic state is isolated.
- Synthetic business A/B claim leakage **0**; foreign-row and tampered physical/reference/text/metadata/cross-snapshot evidence rejected; PARTIAL semantic promotion **0**; unsupported PDF stays unsupported; HWPX incremental capability **NONE**.
- Android: `assembleDebugUnitTest testDebugUnitTest --stacktrace` PASS, **99 tests / 0 failures / 0 errors / 1 skipped**; `lintDebug assembleDebug --stacktrace` PASS, **0 errors / 25 existing warnings**, debug APK built. Android-directory Gradle daemon contract is Java 17.
- `git diff --check`: PASS. `git diff origin/dev -- data/canonical data/seed apps`: empty. No dependency, workflow, schema, auth, DB or API changes. ProductionAction remains NONE.
- Initial exact HEAD `23580c4b76a7d0e1a32012fa1ec1c31639c92f97`: `verify-data` and `verify` both PASS in [CI run 37220118547](https://github.com/jelleoo/MILIMAP/actions/runs/37220118547).
- After that CI, one fresh-context whole-branch read-only review found four Important acceptance/text-fidelity defects (no Critical/Minor). All four were reproduced with raw-byte fixture tests before changes and minimally fixed: preserve whitespace-only `hp:t`; reject unsupported recognized semantic headers instead of losing conditions; retain and reject malformed row/cell namespaces before selectors can hide them; reject child content in line/tab separators, including nested tables. Scoped regressions prove PARTIAL/status null/no claims and cached failure reuse; safely unmapped decorative complex cells remain ignorable. Final full suite/Android verification was repeated after fixes. Final exact-head CI must rerun after push; initial CI is not represented as final CI.

### Review rulings and retained boundaries

The reviewer deliberately excluded the following; executor checked each and retained these boundaries:

- Live compatibility remains unproven (`NOT_OBSERVED`); no invented official source.
- Full-suite/Android/CI results were verified by executor, not redundantly by reviewer.
- Paragraph-only, multi-row headers, arbitrary inline, PDF/OCR and legacy HWP remain non-scope.
- Real layout metadata such as `linesegarray` may limit supported coverage; reject rather than infer.
- Wholly foreign-namespace tables remain unrecognized/unsupported; malformed rows inside recognized tables now block semantic absence.
- Decorative tables/unmapped complex columns/merged titles remain safely skippable; no evidence is inferred from them.
- Empty BusinessName rows are skipped as approved, not promoted to identity candidates.
- Multiple eligible headers and duplicate mappings retain conservative rejection.
- Unused manifest/resources do not supply evidence outside trusted spine membership.
- `cellAddr`/logical grids/unusual merged layouts get no reconstruction; exact physical ordinals and selected-cell unmerged checks remain the boundary.
- Repeated hash/index scans and deep-input costs are unmeasured future bottlenecks; existing bounds/strict validation remain, no speculative cache or parser.
- Public mutable validation-index behavior is inherited from P4-0, not expanded into a new trust bypass.
- No unexpected parse-once exception gap was reproduced; defined failure/partial/unsupported results are cached.
- Incremental reuse stays NONE; production mutation and lifecycle inference remain prohibited.
- Historical pending-CI prose was replaced with actual initial CI/review evidence; final exact status remains in PR/report.

Implementation rulings: native worktree lookup could not resolve this chat's repository, so a verified ignored repo-local isolated worktree was used (risk: manual worktree lifecycle). Locator already accepts the attached document index, so no duplicate index parameter/path was added (regressions verify this). Approved docs' trailing whitespace was normalized without technical edits (only Markdown line-break rendering may differ). No deferred Minor findings.

## Non-runs and remaining risks

Live official HWPX validation: **NOT_OBSERVED**. No new live request was made; synthetic fixture identities/benefits are not real data or expected benefit truth. Real document compatibility remains unproven until a scoped official source is available.

HWPX package/index parse is once per run-context payload, not once per business. Strict existing snapshot/provenance validation remains active; P4-1 does not introduce a zero-rehash trust optimization. Repeated contract validation can still cost full-byte hashing/index scans on larger documents. This is a known future performance concern, not a parallel cache/parser implementation.

The supported subset deliberately rejects heterogeneous/merged/unsupported evidence. No production auto-approval/write, new lifecycle inference or HWPX incremental reuse was added. PDF/OCR/live compatibility/general layout expansion were not run or implemented because they are out of scope. The one skipped Android test and existing lint warnings are not represented as new passes.

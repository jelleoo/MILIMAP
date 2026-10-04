# Phase 4 P4-0 — Document Adapter Foundation

Checked: 2026-10-05. Issue #111. Implementation and local verification complete; review/CI/merge pending. Phase 4 is not COMPLETE.

## Authority and scope

Preflight `git fetch origin --prune` confirmed `origin/dev` at `28a6845684e94cd3490fcc1c4112ef6fce402205`, unchanged from the approved baseline. Approved design/plan commits `65ae04f` / `b46c852` were cleanly integrated as `2e799cd` / `f395f88`. Implementation uses isolated branch `codex/phase4-p4-0-document-foundation`.

Only classification, byte snapshots, synthetic document provenance contracts, and locator/slice bridging are implemented. PDF/HWPX format recognition is **not parser support**. No real PDF/HWPX parsing, OCR, layout adapter, scoped production orchestration, document POST_FETCH reuse, discovery expansion, dependency, schema/API/auth change, or production auto-approval is included.

## Changes and RED → GREEN ledger

| Task | Changes | Observed RED | GREEN / commit |
| --- | --- | --- | --- |
| 1 | `benefit-verification-contracts.ps1`, `benefit-source/discover-official-benefit-sources.ps1`, contract/discovery tests, synthetic fixture helper | HWPX enum rejected; valid HWPX classified UNSUPPORTED | Contract/discovery PASS; `dc5cdfc` |
| 2 | `benefit-evidence-location-contracts.ps1` and its test | Byte-backed PDF snapshot rejected because Text was required | Snapshot contract and XLSX converter PASS; `a963056` |
| 3 | `benefit-evidence/document-source-provenance.ps1`, location contracts, new provenance test, fixture helper | Missing index constructor; forged field raw-span metadata accepted | Document/location/HTML/JSONP tests PASS; `f2f088d` |
| 4 | Locator, location contracts, document/locator/incremental tests | Locator did not pass the document index; index-less empty COMPLETE observation accepted | Locator/provenance/incremental/location tests PASS; `50fc0ab` |
| 5 | This handover, current-work, README, legacy PDF fixture correction | Full suite caught legacy fake PDF bytes `1,2,3` incorrectly standing for a PDF source | Fixture now uses synthetic PDF signature; unchanged Phase 2 runner regression and full suite PASS |

All code/test paths above are under `tools/data/`. The approved spec/plan are included under `docs/superpowers/`. Task 5 does not add production behavior or manufacture a RED for documentation.

## Contract boundary

- HWPX adds one SourceFormat value. PDF recognition checks a bounded version signature; HWPX checks bounded ZIP marker parts/mimetype with duplicate/unsafe-path rejection. Neither validates a fully parsed document. Legacy binary HWP remains unsupported.
- PDF/HWPX snapshots preserve original `byte[]` defensively with byte SHA-256 as provenance root and empty Text. HTML/JSONP text hashes and XLSX semantics remain unchanged.
- `BenefitDocumentValidationIndex` binds SnapshotId, ContentHash, SourceFormat, AdapterId/Version, ExtractionMethod, ExtractorId/Version, ExtractionConfigHash and exact indexed rows. PDF uses page/table/row identity; HWPX uses section/table/row identity. Fields preserve exact per-cell references and source text.
- Document units/slices reject fabricated RawStart/RawLength/RawFragment. Unit and slice values, physical paths and extraction metadata must equal the indexed record. Cross-snapshot indexes and altered fields/references fail closed.
- The index validates synthetic record consistency; it does **not** prove a caller-provided record was parsed from bytes. P4-1/P4-2 adapters must establish that physical source provenance. No synthetic benefit is claimed as real truth.
- Locator reuses existing business identity/conflict logic. A strong row cannot suppress an unresolved same-name alternative. Incomplete observations cannot return semantic NOT_FOUND; complete identity absence is never ENDED.
- PDF/HWPX reuse capability remains `NONE`; `ProductionAction` remains `NONE`. Existing HTML/JSONP/XLSX and Phase 3 behavior are preserved by regression tests.

## Verification

Six plan-targeted scripts PASS: `test-benefit-verification-contracts.ps1`, `test-discover-official-benefit-sources.ps1`, `test-benefit-evidence-location-contracts.ps1`, `test-document-source-provenance.ps1`, `test-find-business-evidence-slice.ps1`, `test-benefit-incremental-reuse.ps1`.

Baseline: 56/56 PASS. Final CI-equivalent single-process run:

```powershell
$ErrorActionPreference = 'Stop'
Get-ChildItem -LiteralPath tools/data -Filter 'test-*.ps1' |
  Sort-Object Name |
  ForEach-Object { & $_.FullName }
```

Observed final result: **57/57 PASS**, including HTML/JSONP/XLSX converters, scoped runners, History Core/commit/comparison, P3-4/P3-6 incremental reuse and closeout regressions. An initial run stopped at the historical PDF fixture; after correcting the fixture, the complete suite was rerun successfully.

Android from `apps/android`:

- `gradlew.bat assembleDebugUnitTest testDebugUnitTest --stacktrace`: PASS (41s).
- `gradlew.bat lintDebug assembleDebug --stacktrace`: PASS (40s), debug APK produced.
- Initial launch without Java environment failed; rerun used installed Android Studio JBR and existing SDK in process-local environment only. `gradlew --version` confirms daemon compatible with Java 17 from existing daemon criteria.

`git diff --check` PASS. `git diff origin/dev -- data/canonical data/seed apps` empty. No dependency or CI/workflow change. Whole-branch read-only code review found no Critical/Important findings. Exact PR HEAD must still pass GitHub `verify-data` and `verify` before merge; local success is not a substitute.

NOT_RUN: real PDF/HWPX parsing/live validation, OCR, document run-context reuse, document production orchestration (out of scope). No live source requests were made.

## Efficiency and remaining risk

No parallel cache, hasher, fingerprint or BenefitState system was added. Observation validation checks the document index once and validates its units against that index. Direct document constructors/slice boundaries intentionally retain strict validation; bulk parser/index-reuse optimization is deferred to adapter work. ZIP format classification may inspect package markers separately from future parsing, once at the source boundary, not per business.

Signature/package recognition cannot establish authenticity, valid document semantics, lifecycle currentness or correct layout. Document evidence currently exists only as deterministic synthetic controls. Native PDF runtime and OCR dependency decisions require separate approval; HWPX live evidence remains NOT_OBSERVED.

Next after merge and a fresh dev check: **P4-1 HWPX generic adapter**. Do not mark Phase 4 COMPLETE.

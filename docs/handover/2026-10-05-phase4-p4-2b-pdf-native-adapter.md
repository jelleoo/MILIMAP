# Phase 4 P4-2B — Bounded PDF Native Adapter

## Authority / delivery boundary

- Issue #117; base `origin/dev`: `24a64aa96338ddbc7fe7f315f5c1fa01aa21b7b1` (fetched and verified).
- P4-2A PR #116 MERGED / Issue #115 CLOSED; approved plan included from `adbc6aaa807a5c3cf65e9eddfd84778eaae3be25` as `63f6d0b`.
- Branch: `codex/phase4-p4-2b-pdf-native-adapter`; implementation HEAD `e85cf35c12b28226208911fd027dc583f24f8108`. Documentation/review follow-up HEAD is the PR HEAD, not a self-referential hash in this file.
- Bounded native implementation only; Phase 4 is **not COMPLETE**. No auto-merge.
- PdfPig **0.1.16 exact** (`[0.1.16]`, lock request `[0.1.16, 0.1.16]`), Apache-2.0, .NET 8 child process. Product dependency explicitly approved by Issue #117 mission; no other external product dependency.
- ReportLab/PIL are fixture-authoring tools already available locally, not product/CI dependencies. Independently authored synthetic PDFs are CC0-1.0 and never real benefit truth.

## Files / implementation

- `tools/data/pdf-native/`: locked executable project, primitive projection, build/license README; ignored bin/obj.
- `lib/benefit-evidence/pdf-native-runtime.ps1`: process isolation, bounded stdout/stderr, identity/schema checks, timeout/kill-tree/temp cleanup. PdfPig types never enter PowerShell/domain contracts.
- `lib/benefit-evidence/convert-pdf-source-observation.ps1`: actual bytes → native geometry → deterministic cell containment → existing `BenefitDocumentValidationIndex` / `PDF_ROW`.
- Shared header map: only `영업소 주소(도로명)` → Address and `소재지전화` → Phone exact aliases.
- Run-context/scoped/extraction files: existing PayloadCache/TemplateCache, snapshot/config/parser-bound key, `SCOPED_PDF_CELL`, existing locator/binding/validation. No lifecycle policy or alternate evaluator.
- New native/runtime, observation and scoped tests plus independent PDF controls; legacy HWPX malformed-PDF test now checks native FAILED/null/zero claims rather than format exclusion.
- README/current-work/this handover and approved plan. No canonical, seed, apps, API/schema, auth or DB changes.

## Geometry / provenance policy

`PDF_GRID_CONFIG_V1`: snap **0.5 pt**, thin rectangle **0.75 pt**, full glyph containment epsilon **0.01 pt**, baseline grouping **1.0 pt**. Fixed orthogonal rotation normalization (0/90/180/270), component-isolated page-local tables, one exact semantic header, no fuzzy/positional matching. Policy and sorted shared header map feed `ExtractionConfigHash`.

Glyphs must be fully contained in exactly one closed cell. Visible duplicate/overlapping text, boundary crossing, broken/merged semantic cells and ambiguous headers fail closed. Whitespace is excluded only from visible-ink overlap detection, not full containment or text preservation. Physical page/table/row/cell references and exact field SourceText are checked against the byte-bound index. Unsafe relevant rows retain only safe audit units with overall PARTIAL; downstream consumes no partial semantic evidence. Later-page parser trust failure discards all evidence.

No OCR, borderless/reading-order inference, multi-row header inference, semantic merged-cell reconstruction or cross-page row stitching. Existing PdfTextExtractor fallback is not invoked. PDF and HWPX incremental capability remain **NONE**; `ProductionAction=NONE`.

## Resource policy / measured bottleneck

| Bound | Initial value / enforcement |
|---|---|
| Source bytes | 10 MiB before helper open; both wrapper and helper |
| Pages | 32 after document opens, before page enumeration |
| Letters | 20,000/page; 100,000 total after page becomes observable |
| Paths | 2,048/page; 16,384 total path commands after page becomes observable |
| Grid work | 512 segments/page before component search; 128 coordinates/axis; 4,096 cells/grid |
| Glyph geometry work | 128 glyphs/cell; shared document budget of 500,000 glyph/cell checks and 100,000 overlap comparisons before corresponding loops |
| Geometry wall time | Cooperative 10-second deadline shared across all pages; failure clears all units |
| JSON / stderr | 16 MiB / 64 KiB; bounded streaming reads, terminate on excess |
| Child wall time | 10 seconds default after process starts; kill process tree and clean own temp folder |
| PdfPig token stack | 128, strict parsing, missing fonts rejected, clip paths enabled |

These conservative initial limits leave margin over P4-2A's observed 59,009-byte, one-page, 1,097-letter, 26-path control. They are not hostile-input capacity claims. Some allocations happen before counts are available; no portable hard memory cap is implemented or claimed. Peak working set is sampled, not a memory ceiling. First cold helper restore/build is outside the parse deadline; locked build/restore failures yield no evidence.

Synthetic two-business instrumentation: external fetch **1**, native parser **1**, document-index creation **1**, adapter reuse **1**, leakage **0**. Incomplete results are cached too. Same index object is reused read-only; no second parser/cache architecture.

Additional local measurement on committed two-business PDF: first scoped call **630 ms / 26 byte-hash calls**, second **58 ms / 17 byte-hash calls**. Existing strict snapshot/unit/slice validation repeats hashes; this implementation does **not** claim zero-rehash PDF validation. Approved scope measures this before considering a future trust optimization. No PDF POST_FETCH reuse was added.

## Current Suwon source observation

Requested official URL:
`https://www.suwon.go.kr/webcontent/ckeditor/2026/5/28/4e5d92bd-869b-41d9-8179-cbc3ffba48c7.pdf`

- Checked: **2026-10-05T14:09:04.4342131+09:00**, GET; redirects disabled.
- HTTP **302**, Location `https://www.suwon.go.kr/sw-www/firewall_warning.jsp`.
- Final requested host remains `www.suwon.go.kr`; firewall redirect **not followed**.
- Content-Type absent; body **0 bytes**; no `%PDF` signature, snapshot or PDF content hash.
- Fetch measurement **94 ms**. Current PDF parse/physical identity check **NOT_OBSERVED**; source drift **NOT_DETERMINED**.
- Live-control applicability for P4-2 closeout: **`NOT_APPLICABLE_SOURCE_UNAVAILABLE`**. The approved design requires the current Suwon PDF as a representative native-layout control only when it remains available; the official endpoint did not provide PDF bytes in this observation. This does not convert the current layout into PASS, and no current Suwon layout claim is made.
- Initial request's harness failed on absent Content-Type before persisting response metadata; one capture-only retry followed an offline null-header serialization check. Retry preserved the above HTTP metadata; attempting the PDF byte-hash helper on empty bytes was a capture harness error, not a native parser/source finding. No further requests were made.
- Original bytes were never committed. No historical hash/bytes replaced current evidence. No current claim for 고려이발관/name/address/phone cell location can be made from this blocked request.
- P4-2A's separate previously observed identity/layout evidence remains historical only. No BenefitDescription, discount, eligibility, validity, ACTIVE or currentness was inferred.

## Task RED → GREEN / commits

| Task | Observed RED / GREEN | Commit |
|---|---|---|
| 1 | Missing isolated helper project → genuine native PDF deterministic JSON, exact lock, no CLR types | `b3734d36c71dbbcb66f25762852c3e3d540548da` |
| 2 | Missing runtime boundary → real child success/faults, hash/schema checks, deadline/output/cleanup | `1252a798aaa86a9b0640ec701596f11f475d2365` |
| 3 | Missing converter → native Korean/two-business/multiline/grid/rotations/tamper/later-page tests | `42e6ed5114fbcf8eb2c051dd42e2ba151562868c` |
| 4 | Exact reviewed header fields absent → exact aliases; nonexact labels remain unmapped | `e36d43cd94a116d3542226099bce65498c188ed8` |
| 4 follow-up | Git treated standard PDF trailing spaces as text → binary fixture attributes, exact bytes preserved | `b69f366` |
| 5 | Scoped PDF observation absent → existing scoped path, fetch/parse/index once, isolation/incomplete/absence gates | `51fd6dd19a47e789067be7e7b5de4c9561334a97` |
| 6 | Oversized bytes reached parser; 513 segments unbounded → byte/count/output/wall/grid-work limits | `e85cf35c12b28226208911fd027dc583f24f8108` |
| 7 | Regression/docs gate, not new production behavior | documentation commit in this PR |
| 8 | Exact-head CI + fresh whole-branch read-only review | PR checks/review follow-up evidence |

Duplicate-name control was corrected to strong + same-name name-only alternative (the first fixture had explicit contradictory address/phone). Geometry/locator safety rules were not weakened. Excess-letter fixture uses 20,001 native glyphs at a visible origin; off-page glyphs clipped by strict parser are not counted as visible text.

## Verification

- Before implementation: existing full data suite **59/59 PASS**.
- Targeted helper/runtime, PDF observation/scoped and HTML/XLSX/HWPX/JSONP/header/run-context/history/incremental regressions **PASS**.
- Complete current data suite in exact CI same-process script order: **62/62 PASS**.
- `dotnet restore tools/data/pdf-native/Milimap.PdfNative.csproj --locked-mode`; `dotnet build ... -c Release --no-restore`: **PASS** (SDK 8.0.425, runtime 8.0.31 locally).
- Android `gradlew.bat assembleDebugUnitTest testDebugUnitTest --stacktrace`: **PASS**, 37 seconds.
- Android `gradlew.bat lintDebug assembleDebug --stacktrace`: **PASS**, 32 seconds; debug APK produced. Existing native-library strip warning is not a build failure.
- `git diff --check origin/dev...HEAD` **PASS**; protected path diff (`data/canonical`, `data/seed`, `apps`) **empty**. Temp outputs/helper binaries remain ignored.
- Runtime/review HEAD `84a47fc77b55d2489c4811f2832a12fb22203a81` passed exact-head `verify-data` and Android `verify` in run `37287580653`. Any later docs-only closeout HEAD must also pass both jobs before merge.

Not run/available: current Suwon physical identity/benefit verification (firewall redirect, no PDF); OCR, arbitrary PDF families, portable hard-memory enforcement. No population precision/recall claim. Existing historical sources and deterministic controls are not current live truth.

## Remaining risks / next

### Whole-branch review / final fix pass

Fresh read-only review of `24a64aa..9901749` found no Critical and three Important findings. The same review resumed after a usage-limit interruption; no second reviewer/re-review was used. All three entered one RED→GREEN fix pass:

1. Mixed identity-less mapped evidence falsely allowed COMPLETE/NOT_FOUND. Actual `empty-name.pdf` now yields PARTIAL even with safe A present; B locator remains operational PARTIAL, semantic null, zero claims. Safe A is audit-only.
2. A safe first table hid a damaged second table discarded before header validation. Independently authored `unsafe-lower-table.pdf` proves this from actual bytes; uncovered exact native identity-header hints now cause PARTIAL without constructing rows/claims. Hint-only regions do not count as physical tables (`uncovered-heading.pdf` ordinal RED→GREEN).
3. Allowed glyph workload could monopolize PowerShell after child timeout. Genuine crowded/spread grid controls prove per-cell and shared document comparison budgets plus deadline enforcement. A 600-glyph case now rejects by cell quota in **525 ms geometry** (native **573 ms**), versus the review's **4,804 ms** unbounded geometry measurement; this is a local control, not a throughput benchmark.

Review exclusions remain explicit limitations, not hidden PASS claims: current Suwon unavailable; CI checked separately on exact HEAD; no hard OS memory ceiling/parser-security audit/general invisible-text or paint-order visual-fidelity guarantee; skew/OCR/borderless/merged reconstruction out of scope; no demonstrated nested-projection bypass; OS-denied termination/deletion races not fault-injected; whitespace containment remains strict; repeated hashes and existing internal index-mutability model are unchanged; dependency/fixture approval and incremental/lifecycle/protected boundaries are preserved. No independent Minor finding was deferred.

Initial exact HEAD `9901749e4d0e0c3f24c05596f5849342bb2a4f55` passed both jobs in [run 37267090989](https://github.com/jelleoo/MILIMAP/actions/runs/37267090989). That run is **not** final-fix CI evidence. [PR #118](https://github.com/jelleoo/MILIMAP/pull/118) must show both jobs successful on the new final HEAD after this fix pass. Local full suite and Android gates are re-executed after the fix pass; final report/check surface records their result.

- Current official PDF live layout remains **NOT_OBSERVED** from this environment. A future available official PDF is still required before making any current Suwon native-layout claim, but the present live-control gate is **`NOT_APPLICABLE_SOURCE_UNAVAILABLE`** and does not block merging the bounded adapter implementation.
- Native parser can allocate before observable count checks; child isolation/deadline/output limits are not an OS memory sandbox.
- Fixed geometry supports only tested ruled-grid subsets; unsafe/unknown structures must stay operationally unresolved, never semantic absence.
- Strict repeated PDF hashing is an observed downstream overhead; optimization requires its own safety proof, not another cache.
- Whole-branch review is complete with Critical 0 / Important 0 after fixes. A final docs-only exact-head CI pass is the remaining merge gate.
- P4-2 bounded native adapter closeout status: **COMPLETE subject to final docs-only exact-head CI before merge**. Current Suwon native layout remains NOT_OBSERVED because the source was unavailable; this is not a positive live validation claim.
- Next: **P4-3 OCR fallback only after P4-2B merge**. Phase 4 is not COMPLETE.

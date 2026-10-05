# P4-2A — PdfPig technical evaluation

## Decision and scope

Gate: `PDFPIG_APPROVED_FOR_P4_2`.

This approves the evaluated parser candidate, **not a product dependency or adapter**. P4-2B remains `BLOCKED` pending explicit PdfPig dependency approval. Phase 4 and P4-2 are not COMPLETE. No product code, contract, normalization, lifecycle, cache, dependency manifest, or protected data was changed.

Authority: Issue [#115](https://github.com/jelleoo/MILIMAP/issues/115), current `origin/dev` / base `53443468ec48a30c33a0b089c55357fa7d14818f`; PR #114 was MERGED and Issue #113 CLOSED at preflight. `git fetch origin --prune` preceded evaluation.

Approved sources, included without redesign:

- Spec: `995cf29ac6998fd95270fbda0417ea95349e87e5` → branch commit `5507754`.
- Plan: `539b29224d559c20c0d36adea7677c2a444fc816` → branch commit `5b430b1`.
- Isolated branch: `codex/phase4-p4-2a-pdfpig-evaluation`.

## Runtime, package and licensing

The throwaway project targeted `net8.0` with **PdfPig 0.1.16**, restored from `https://api.nuget.org/v3/index.json`. No prerelease was used.

- Local Windows: official portable SDK **8.0.425**, runtime **8.0.31**, Windows 10.0.26300 x64. SDK archive SHA-512 was checked against Microsoft's release metadata before extraction in OS temp.
- CI Windows: Windows 10.0.26100 x64; CI Linux: Ubuntu 24.04 x64.
- Both CI runners selected installed SDK **10.0.401**, despite setup also installing 8.0.425; the project still built for `net8.0`, and both probe outputs report **.NET 8.0.31**. This is recorded as observed, not claimed to be an SDK-8-only CI build.
- NuGet license: **Apache-2.0**; package repository: [UglyToad/PdfPig](https://github.com/UglyToad/PdfPig), source revision `a7bb35662bbbf405efddad50aedc9bcdcf515afc` from the downloaded nuspec.
- Resolved **net8.0** package graph: one direct `PdfPig/0.1.16`, **zero transitive NuGet packages**. Package contains seven managed PdfPig assemblies; zero transitive packages does not mean a single DLL. Legacy framework dependency groups are different and were not evaluated.
- Nupkg SHA-256: `d67171846ea8c28f50359137065fec4514266d7a32b23eae6c5f2ebed8ffcfc4`.
- NuGet content SHA-512: `qQcbsNMYVY+K5ELptax2S8thNMk0+rSQq3H/KdYj3LLcko8yTCz8y5KIvsKxIyAuTN0ZYNnfsZkM+0EvxTwHVA==`.

The local SDK/package cache and console project are OS-temp evaluation material, not product installation. No product manifest or lockfile was modified.

## Probe identity and evidence retention

Exact probe source is recoverable at temporary evaluation commit **`93a0c90c7b999cb247370367ce17578d5538fe57`**, under `.evaluation-p4-2a/`. That directory and the evaluation workflow are removed from the final branch diff.

| Item | SHA-256 |
| --- | --- |
| `Program.cs` | `a8482f69e0bab157643f57d9306f7a25a3ae74cb543c247f82d9f74a98b7d097` |
| `PdfPigProbe.csproj` | `4812cd1710878489e4690f161293964a21b84cd642cc7377d163aa9eda4aea12` |
| `grid-probe.py` | `a4151f6b4a3bb1dbefa1f6a97f7bc2ac91706b8cedd4f6792ecb582e3d6d3413` |
| Local `project.assets.json` | `fd2bfaad02ea0a82f89abd506135387c17fbd61f0c32119a5d6b152808e405b5` |
| Windows CI `project.assets.json` | `3ade9ffdcfbd0e02eda6bb57657ebf96ed3514e0014e022ba54ad7e0247e9dd6` |
| Linux CI `project.assets.json` | `6b6a7d85a1df20bc6296f541dd6c313c01135b14da8861954dfdbc688a2583eb` |
| Independent control generator, OS-temp `make-controls.py` | `40ccb929b0d4dfe5edb44e72945caccddbe0e59232097c7f1093b1bed08ad502` |

Source/project/grid hashes match local and both CI platforms. Assets files include platform-specific absolute paths, so their raw hashes differ; each recorded package listing independently resolves only PdfPig 0.1.16. No claim of identical raw assets files is made.

The console emitted invariant-culture JSON with schema/version/runtime/OS/file hash/open status/encryption/pages/diagnostics, and per-page rotation, dimensions, native glyph bounding boxes/baselines, vector commands and image/letter/path counts. Full raw outputs live in OS temp and CI artifacts, not the repository. CI artifact retention is **7 days**; the hashes and findings below remain in this handover, and the evaluation source/control bytes remain recoverable through the temporary commit. Suwon bytes were never committed.

## Current Suwon observation

One new read-only GET, followed by local-only repeated probes:

```text
CheckedAt: 2026-10-05T12:36:15.5190955+09:00
RequestMethod: GET
RequestedUrl / FinalUrl:
https://www.suwon.go.kr/webcontent/ckeditor/2026/5/28/4e5d92bd-869b-41d9-8179-cbc3ffba48c7.pdf
HttpStatus: 200
Redirects: []
ContentType: application/pdf; charset=UTF-8
ByteSize: 59009
Signature: %PDF-1.4
SHA256: 61fd1311b7d5a853b8fcbd5a61bf986006ad7e447aa45dbb67dfe57d0fce66d7
SourceDrift: NO_CHANGE_OBSERVED
```

The new bytes match the historical research hash; historical bytes were not substituted for this request. The official host served the document directly. A current parent-page link chain was not investigated in this evaluation.

PdfPig opened the current bytes twice successfully with strict parsing (`UseLenientParsing=false`, `SkipMissingFonts=false`, `ClipPaths=true`, `MaxStackDepth=128`):

- One page, rotation **0**, **841 × 595 pt**, **1097 letters**, **26 paths**, **0 images**.
- Native Korean `고려이발관` decoded; no OCR or image text extraction.
- Decoded-text SHA-256: `73084de63e8ca8a7258503766b918bd717a5dbd1c8b19a8fc878a3cb0d21c9a3`.
- Final repeated **entire Pages projection** (including letters and paths) matched exactly.
- Final repeated grid JSON SHA-256: `ee6a547201ecfe3492610cbfb32a66d4f85fb41002ddad24257f2caaf4f0245a` for both runs.

This is **layout/identity evidence only**. The observed header is `연번 | 업소명 | 영업자 | 영업소 주소(도로명) | 소재지전화`; there is no row-level benefit-description column. No benefit-positive, ACTIVE, currentness, discount, or eligibility conclusion is drawn.

## Vector grid and physical containment

The temporary geometry helper consumes only PdfPig-exported JSON, not PDF bytes; it is not a second PDF parser. It uses axis-aligned stroked lines and thin filled rectangular paths to prove closed adjacent cells. Fixed tolerances, in points:

```text
Coordinate snap: 0.5
Thin filled rectangle: 0.75
Full glyph containment epsilon: 0.01
Within-cell baseline grouping: 1.0
```

No automatic tolerance widening, reading-order row inference, text-derived columns, nearest-cell assignment or borderless-table heuristic was used. Within already-proven cells only, glyphs are ordered by baseline and X coordinate.

Observed **1 grid**, **95 closed cells** (5 columns × 19 physical rows, header included). `고려이발관` occupies exactly one cell:

```text
Page: 1
Table: 1
Physical row: 2 (header included)
Cell: 2 (business-name column)
BBox, bottom-left page coordinates:
(95.41545, 463.191) -> (284.2085, 476.744)
Glyph indices: [25, 26, 27, 28, 29]
Text: 고려이발관
Containment: EXACTLY_ONE_CELL
AmbiguousTopology: false (within the evaluated probe)
```

The same physically bounded row provides address cell 4, `경기도 수원시 팔달구 팔달로 135, 1층 (화서동)`, and phone cell 5, `031-255-7060`. These are observed identity strings, not canonical expected truth. Glyphs from neighboring rows/cells were not used in this cell.

The prototype is deliberately bounded to rotation-0 axis-aligned grids. Its successful topology check is not a general proof for every malformed/merged/overlapping PDF layout.

## Independent negative / compatibility controls

Authored synthetic controls were generated independently with existing ReportLab/PIL tooling, not with PdfPig. They are released for this evaluation under **CC0-1.0**, contain no real business benefit claims, and are recoverable as exact PDF bytes at the temporary commit's `.evaluation-p4-2a/controls/` paths.

| Control | Exact SHA-256 | Observed result and purpose |
| --- | --- | --- |
| `grid.pdf` | `9adab416cc10d22556a87d9fc91578aa220a17344eb346ad69678dc46eb6312c` | Native open; one grid / six cells; Business A unique containment. Independent positive geometry control. |
| `truncated.pdf` | `730b494fb87894df60bff156c4f04dbb5c32614976607132c031657707695f15` | First 64 bytes of grid control; FAILED / PdfDocumentFormatException / no pages. |
| `encrypted.pdf` | `75c9317813e6650adc00c5b3d1619f06294a3f049f883552d699df95c20337bd` | UNSUPPORTED / encrypted / PdfDocumentEncryptedException / no pages; no password attempted. |
| `image-only.pdf` | `eb9d47fad924249b0be42586e7a7f8f3e09a3955c68073b9446a123afc2c864d` | Raw open; zero letters / one image / zero paths / zero grids. Future adapter must reject native evidence; OCR candidate only. |
| `multipage.pdf` | `3a5d3f45187f220fb921d7c6872a488e0d69214786cbf56276771dc3b1b25b2a` | Two native pages; table only on page 1 / six cells; no cross-page stitching. |
| `native-no-grid.pdf` | `71e502ddb41dc782ca06bdf150aafebe9d29e54231230f01e5fae0e46bb0aa53` | Native letters but no paths/grid; future table-only adapter must return unsupported, not semantic absence. |

Raw `OpenStatus=COMPLETE` only means parser open, **not** production adapter COMPLETE, LOCATED, NOT_FOUND, or ENDED. The negative results demonstrate a feasible fail-closed strategy; they do not implement a product adapter.

## Resource bounding feasibility

One local fresh-process Suwon probe measured **285 ms wall time** including process startup, parse and JSON serialization, with sampled peak working set **65,826,816 bytes** (~62.8 MiB; 10 ms sampling). This is a small-file feasibility measurement, not a parser-only timing, hostile-file benchmark, or production limit.

Viable future strategy:

- Reject oversized input bytes before parser open.
- Bound page count, per-page letters/paths and emitted projection size; those count checks can occur only after corresponding parser work and cannot alone prevent pre-allocation.
- Retain PdfPig's configured stack-depth bound; strict exceptions fail closed.
- Use an isolated process with a wall deadline and OS-observed memory limit / termination. The evaluation process monitor supports timeout termination; an in-process token alone does not prove bounded native parse time or memory.
- Keep output quotas and fail closed on termination; do not convert failure into absence/lifecycle evidence.

**Feasible with process isolation**, not demonstrated as hard guarantees for adversarial inputs. Final numeric quotas and the production containment/security test matrix remain P4-2 implementation decisions after dependency approval. No production resource-limit system was added here.

## Windows / Linux compatibility

Successful exact evaluation HEAD: `93a0c90c7b999cb247370367ce17578d5538fe57`.

[Actions run 37260668733](https://github.com/jelleoo/MILIMAP/actions/runs/37260668733): Windows and Ubuntu matrix jobs both **SUCCESS**. Same exact probe/project/grid source hashes, PdfPig version and six CC0 control-byte hashes.

Downloaded artifacts were compared, not merely inferred from green jobs:

- All **six full native JSON projections**, excluding only descriptive `Runtime` / `Os`, exactly equal: file hash, open/diagnostics, all page dimensions/rotation/counts, text hashes, **every glyph and vector command**.
- All **four grid JSON projections** exactly equal, including all physical cell projections and candidate/containment results.
- No unexplained material platform difference observed on these controls.

Artifact identifiers / archive digests:

- Windows `11324686052`, `sha256:14e682f3036967c0ecc40a0c1ae75142c77f09b6845fa474a203044b298a09c9`.
- Ubuntu `11325080300`, `sha256:cc6b52ada5c367abf292714d5bf8e94e7039389b79c58e4a03706ec82933cbd7`.

Earlier runs `37260511506` and `37260582636` were **FAILED evaluation harness runs**, not parser acceptance evidence: every control assertion passed, but the expected truncated-file native exit 1 remained as PowerShell's last native exit code. Explicit success exit after all assertions fixed the wrapper; no negative assertion was relaxed. Temporary `-text` attributes also ensured Git checkout preserved exact probe/control bytes. Both temporary workflow and attributes are removed from final diff.

Linux Korean/Suwon-byte compatibility is **NOT_OBSERVED**: the current Suwon PDF was tested locally on Windows, not redistributed into CI. Cross-platform equality is demonstrated for the independent CC0 controls, not extrapolated to all fonts or PDFs.

## Task / probe ledger

| Task | RED / expectation | Result |
| --- | --- | --- |
| 1 | Initial console incorrectly exited success for missing file | GREEN: structured FILE_NOT_FOUND, nonzero exit; minimal independent native PDF opens; required JSON and metadata recorded. |
| 2 | Current-byte Korean/native geometry plus repeat determinism assertions | PASS on newly fetched current Suwon bytes, two final full projections identical. |
| 3 | Raw probe lacked GridCandidateCount; later glyph-top ordering split phone/address numeric runs | GREEN: physical vector grid; baseline-based ordering within proven cells preserves phone `031-255-7060` / address `135`; unique containment; all six controls observed. |
| 4 | Identical source/bytes/platform projections and negative gates | PASS after harness-only corrections; six native / four grid comparisons exact. |
| 5 | Gate needs geometry, fail-closed strategy, bounds, platform evidence and clean final diff | APPROVED for candidate evaluation only; docs-only closeout. |

Executed: temp project restore/build, missing-file assertion, current Suwon HTTP capture, repeated raw/grid probes, independent controls, bounded-process timing/memory sampling, Windows/Linux matrix, downloaded full-projection comparisons, and Git scope/whitespace/status checks.

Not run:

- Full data and Android unit/lint/build suites: **`NOT_RUN_NO_PRODUCT_CODE_CHANGE`**.
- Real benefit-positive/currentness PDF validation: **NOT_OBSERVED** (Suwon is identity/layout only).
- Linux Korean/Suwon, rotations 90/180/270, comprehensive merged/overlapping/boundary-crossing glyph rejection, malformed later-page isolation, hostile fonts and large-file resource limits: **NOT_OBSERVED**.
- Product adapter/provenance pipeline integration and PDF reuse: **NOT_IMPLEMENTED**; reuse remains NONE.

## Final retained scope / next decision

Retained files only:

1. Approved P4-2 spec.
2. Approved P4-2A plan.
3. This handover.

Final scope checks: `git diff --check`; protected diff against `origin/dev` for `data/canonical`, `data/seed`, `apps` empty; `tools/data`, dependency manifests and workflows unchanged relative to base; temporary probe/workflow absent from final tree; clean status after commit. Historical evaluation commits intentionally retain the approved temporary harness/control sources for reproducibility. No Suwon PDF is present in that history.

Remaining risks: font/layout coverage is narrow, geometry tolerances require production negative tests, memory/time isolation needs implementation and quotas, official benefit-positive evidence is absent, and downloadable CI artifacts expire. These limit product readiness, not the observed parser feasibility decision.

Next decision is explicit **PdfPig product dependency approval**, followed by a separately authorized P4-2B implementation. Do not infer that authorization from this gate or PR. No merge or automatic follow-on implementation.

- Phase: Phase 4 — Multi-source Adapters
- Stage: P4-2A PdfPig Technical Evaluation
- Gate: `PDFPIG_APPROVED_FOR_P4_2`
- P4-2B: `BLOCKED`

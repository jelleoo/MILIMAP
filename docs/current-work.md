# 현재 작업 안내

이 문서는 팀원과 Codex가 저장소를 clone한 뒤 가장 먼저 확인하는 현재 개발 진입점입니다.

## 현재 기준선

- 개발 기준 브랜치: `dev`
- Phase 1 code baseline: `97d6070113196e922fb76af7508314b6eda8e7b7`
- Phase 2 Task 6 merge baseline: `d43c00ee07b471a55ed7ece4abecc1dc242ed8ce`
- Phase 2 Core Foundation: Issue #43 / Task 7 validation PR #50
- current dev baseline: `24a64aa96338ddbc7fe7f315f5c1fa01aa21b7b1` (P4-2B preflight fetch, 2026-10-05)
- 기준일: 2026-10-05
- Phase 1 A — Business Identity / Normalization: PR #37 merged
- Phase 1 B — POI Discovery: PR #34 merged
- Phase 1 C — POI Matching / Evaluation: PR #36 merged
- Phase 1 Integration: PR #39 merged
- Candidate diagnostics / provenance: PR #41 merged
- Phase 1 Integration closeout: Issue #38 / PR #42 (`Closes #38`)
- release candidates: 249
- exact map pins: 111
- coordinate-unconfirmed: 138
- latest-benefit-evidence 부족 canonical hold: 247
- Android bundled seed version: 7

현재 코드/설정이 이 문서와 다르면 최신 `dev` 코드와 해당 Issue/PR을 우선합니다. release data 수치는 이번 closeout에서 변경하지 않았다.

## Phase 4 P4-0 — Document Adapter Foundation

Issue #111의 P4-0 foundation은 PR #112로 `dev`에 병합됐다. reviewed HEAD `bc36bf6a7d9dc6024e5b44294d5667c162170487`가 위 dev baseline의 ancestor임을 확인했다.

- PDF signature / bounded HWPX ZIP marker 분류, original-byte immutable snapshot, synthetic `PDF_ROW` / `HWPX_ROW` index/unit/slice provenance와 locator bridge
- P4-0의 format recognition 자체는 parser 지원이 아니다. Native HWPX/PDF table parsing은 아래 후속 범위에서 추가하며 OCR은 미구현이다.
- `ProductionAction=NONE`, PDF/HWPX reuse capability `NONE`; canonical/seed/apps 변경 없음
- local data suite 57/57 및 Android unit/lint/debug build PASS
- [P4-0 handover](handover/2026-09-29-phase4-p4-0-document-adapter-foundation.md)

## Phase 4 P4-1 — HWPX Generic Adapter

Issue #113의 native ZIP/XML table-only adapter와 scoped 경로는 PR #114로 `dev`에 병합됐다. 위 최신 baseline에서 이 병합을 확인했다.

- trusted OPF manifest/spine과 section namespace, bounded ZIP, DTD/external entity 차단
- 단일 명시적 header와 unmerged semantic cells만 지원; paragraph-only, nested table/unsupported inline, positional guessing은 지원하지 않음
- original bytes → section/table/row/cell provenance → 기존 locator/binding/extraction/validation; claim method `SCOPED_HWPX_CELL`
- shared-source fetch 1 / package parse 1 / adapter reuse 1; PARTIAL observation의 semantic LOCATED/NOT_FOUND 차단
- local complete data suite 59/59 PASS; Android unit/lint/debug build PASS
- live official HWPX validation: `NOT_OBSERVED`; synthetic fixture는 실제 혜택 truth가 아님
- `ProductionAction=NONE`, HWPX incremental reuse capability `NONE`, dependency/protected paths 변경 없음
- [P4-1 handover](handover/2026-10-05-phase4-p4-1-hwpx-generic-adapter.md); 다음은 P4-2 PDF native adapter

Phase 4 전체는 COMPLETE가 아니다.

## Phase 4 P4-2B — Bounded PDF Native Adapter

Issue #117: isolated .NET 8 / locked PdfPig 0.1.16(승인된 Apache-2.0 dependency) → primitive glyph/vector projection → fixed ruled-grid validation → 기존 `PDF_ROW` document index / scoped pipeline을 구현했다. `SCOPED_PDF_CELL`, exact reviewed address/phone header aliases, run-context fetch 1 / native parse 1 / index 1 / reuse 1을 synthetic bytes로 검증했다.

- digital-text / page-local ruled-grid / 단일 명시적 header / unmerged mapped cells만 지원
- OCR, borderless inference, cross-page stitching, PDF POST_FETCH reuse는 지원하지 않음
- PARTIAL/FAILED/UNSUPPORTED의 semantic LOCATED/NOT_FOUND 및 claim 생성 차단
- local CI-order data suite 62/62 PASS, locked restore/build 및 Android unit/lint/debug build PASS
- current Suwon identity/layout control: `NOT_OBSERVED` (2026-10-05 공식 URL HTTP 302 → firewall warning, body 0 bytes). 과거 source/hash를 현재 evidence로 대체하지 않음. P4-2 closeout의 live-control applicability는 `NOT_APPLICABLE_SOURCE_UNAVAILABLE`로 기록하며, 이는 current Suwon layout PASS를 의미하지 않는다.
- `ProductionAction=NONE`, PDF/HWPX incremental capability `NONE`, canonical/seed/apps diff 0
- runtime/review HEAD `84a47fc77b55d2489c4811f2832a12fb22203a81`의 `verify-data` / `verify`는 SUCCESS, whole-branch review Critical 0 / Important 0. docs-only closeout HEAD도 두 CI job이 다시 SUCCESS여야 merge한다.
- P4-2 bounded native adapter는 구현/회귀 기준 COMPLETE이며 final docs-only exact-head CI 통과 후 merge-ready. Phase 4 전체는 COMPLETE가 아니다.
- [P4-2B handover](handover/2026-10-05-phase4-p4-2b-pdf-native-adapter.md); 다음은 P4-2B 병합 후 P4-3 OCR fallback

## Phase 4 P4-3A — OCR Technical Evaluation

- Technical evaluation: `REJECTED` (사용자 최종 판정, 2026-10-05).
- Windows portable Tesseract 5.5.3 supply, exact runtime/model identity 및 offline Korean OCR 실행은 성공했다. 그러나 bounded Gray/RGB matrix의 OCR 16회 / threshold 평가 80건은 모두 PARTIAL이었다.
- PSM 3/4/6 containment failure 및 PSM 11 동일 address cell 내부 정상 Korean word bbox overlap으로 usable positive가 0건이다. Exact-containment / overlapping-word rejection 및 confidence reject-only 정책은 완화하지 않았다.
- Task 4/5: `NOT_RUN_CORE_ACCEPTANCE_GATE_FAILED`; Windows/Ubuntu semantic determinism은 미검증이다.
- Product dependency: `NOT_APPROVED`; P4-3B: `BLOCKED`. 평가 harness는 production OCR adapter가 아니다.
- Phase 4: `NOT COMPLETE`. 다음 단계는 OCR fallback design 재검토이며, 다른 engine/model/crop/preprocessing/geometry 전략은 새 설계 승인 없이 진행하지 않는다.
- [P4-3A rejected handover](handover/2026-10-05-phase4-p4-3a-ocr-technical-evaluation.md)

## Phase 2 closeout (2026-09-26)

Phase 2 Benefit Verification Core의 scoped HTML, MMA JSONP, XLSX 경로와 fixed representative closeout **evidence matrix**를 완료했다(Issue #92 / PR #93 merged). current-code fixed-12 live replay는 replayable raw capture가 없어 `NOT_RUN_NO_REPLAYABLE_RAW_CAPTURE`이며, Phase 2는 현재 구현된 source-family 경계 안에서 `COMPLETE`다.

최근 완료된 항목:

- scoped generic HTML path와 business-bound extraction
- DDC generic HTML live stall 진단/최적화: Issue #77 / PR #78
- early representative benefit validation: Issue #76 / PR #79
  - fixed 12-row source/failure-stratified sample 완료
  - GREEN / YELLOW / RED = 0 / 12 / 0
  - ENDED = 0
  - `ProductionAction != NONE` = 0
  - canonical / seed / apps write = 0
- MMA JSONP live compatibility 복구: Issue #80 / PR #81
  - live list 2,497 records
  - empty business-name rows 446 isolated from identity candidates
  - usable JSONP content units 2,051
  - live adapter status `COMPLETE`
  - shared-source fetch 1 / parse 1 / reuse 1
  - row 4/5 remain safely `NEEDS_VERIFICATION / YELLOW / NOT_FOUND`
  - final live parse observation approximately 41 seconds
- official attachment capability inventory: Issue #82 / PR #84
  - Suwon PDF: deterministic business identity observed, but no per-business validity/detail columns
  - Yangju XLSX: deterministic business row binding observed for 가마골 백숙; 거석골 absent from observed workbook without ENDED inference
  - primary next capability selected: XLSX row/cell provenance
  - verdict: `APPROVAL_REQUIRED` because scoped physical provenance contract needs a minimal XLSX extension
- XLSX row/cell provenance and run-context reuse: Issues #88/#90, PRs #89/#91
  - raw workbook bytes, exact sheet/row/cell references, ZIP/XML fail-closed validation
  - one fetch/parse per shared attachment run; validated index reuse adds no per-business workbook hash or ZIP/XML parse
  - Yangju committed control: 가마골 백숙 is LOCATED/STRONG/VALIDATED; 거석골 absence is COMPLETE/NOT_FOUND only, never ENDED
- Phase 2 closeout: Issue #92
  - fixed rows `2, 4, 5, 22, 74, 75, 118, 119, 139, 280, 337, 338`; no sample substitution
  - completion evidence combines prior authoritative fixed-12 bounded live evidence, Issue #80 / PR #81 MMA post-fix live validation, the committed Yangju XLSX artifact, and current HTML / JSONP / XLSX deterministic regressions
  - observed real-source GREEN rows = `0`; GREEN human audit = `NOT_APPLICABLE`, not a positive audit
  - current deterministic controls: false ENDED / cross-business leakage / hard-conflict bypass / `ProductionAction != NONE` / protected-path writes = `0`

현재 확인된 주요 Phase 2 병목:

- DDC: row-scoped benefit extraction은 가능하지만 individual currentness evidence가 부족함
- MMA: live compatibility는 복구됐지만 일부 canonical businesses는 current official list에서 safe identity를 찾지 못함
- XLSX: workbook-level observation is not individual currentness; the positive control has a validated benefit-description cell but no invented lifecycle claim
- PDF: bounded native ruled-grid adapter가 구현되었고 현재 PR #118 closeout 단계다. OCR/borderless/general PDF는 여전히 미지원이다.
- long heterogeneous live batch의 transport latency/retry/isolation은 별도 operational concern이며 현재 source adapter issue와 섞지 않음

Phase 3 snapshot/history는 P3-0~P3-7까지 `dev`에 병합됐고 bounded closeout을 완료했다. PDF/HWP/OCR, SNS/blog strong-evidence expansion, general discovery, periodic execution은 later phases로 남는다.

## Phase 1 상태

**Phase 1 POI Verification Core / Shadow Mode의 구현과 validation은 완료 상태다.** Phase 1은 canonical이나 Android seed를 자동 수정하지 않으며, GREEN도 automatic production approval이 아니다.

Phase 1 closeout evidence와 남은 위험은 [`docs/handover/2026-09-24-phase1-poi-shadow-validation.md`](handover/2026-09-24-phase1-poi-shadow-validation.md)에 기록했다.

### 구현 범위

```text
Canonical business row
        ↓
Normalization / Business Identity
        ↓
Adaptive POI Query
        ↓
Candidate Collection / Dedup
        ↓
Hard Constraint Matching
        ↓
GREEN / YELLOW / RED
        ↓
Review artifact + Metrics
```

- A는 `NormalizedBusiness`를 제공한다.
- B는 `PoiDiscoveryBatch`와 candidate/query evidence를 제공한다.
- C는 `PoiMatchResult`와 reason/conflict/evidence를 제공한다.
- Integration Shadow runner는 row report, summary, CandidateDiagnosticJson을 생성한다.
- `PoiMatchResult.ProductionAction`은 Phase 1에서 항상 `NONE`이다.

### Operational validation 결과

2026-09-24 initial smoke:

- 6 rows, 23 provider queries
- `PARTIAL` / `FAILED`: 0
- GREEN / YELLOW / RED: 2 / 2 / 2

2026-09-24 representative sample:

- 24 rows, 100 provider queries, 72 artifacts
- discovery/evaluation `COMPLETE`: 24 / 24
- `ProductionAction=NONE`: 24 / 24
- canonical / seed / apps diff: 0
- Sample A unresolved workload: GREEN / YELLOW / RED = 5 / 7 / 6
- Sample B positive controls: GREEN / YELLOW / RED = 3 / 3 / 0, candidate discovery = 6 / 6

Sample A GREEN human audit은 5 SUPPORTED, 0 AMBIGUOUS, 0 CONFLICT였다. 이 표본 관측치는 전체 population precision이나 혜택 유효성 판단이 아니다.

## Phase 2 Benefit Verification Core 상태

Phase 2 provider-neutral Core는 Contract, existing-source fetch/qualification/binding, scoped evidence extraction/validation, claim comparison/evaluation, and shadow integration을 구현했고 closeout gate를 통과했다. 범위는 현재 구현된 official HTML, MMA JSONP, XLSX source families로 한정된다.

현재 흐름:

```text
Canonical benefit row
        ↓
Existing official source first
        ↓
Officiality + Business Binding
        ↓
Evidence Extraction / Validation
        ↓
Claim Comparison
        ↓
BenefitState / ReviewClass
        ↓
Shadow review artifact
```

Task 7 Golden fixture는 real source-cited historical provenance와 synthetic algorithm fixture를 분리한다. historical release evidence는 현재 `ACTIVE` truth로 자동 승격하지 않으며, source/binding conflict fixture는 silent GREEN을 허용하지 않는다. Issue #92 closeout은 fixed 12-row evidence matrix, scoped HTML/MMA JSONP/XLSX regressions, and committed Yangju live-control artifact를 함께 검증한다; it does not replay all 12 rows through current code.

2026-09-24 existing-source live smoke는 canonical에 이미 저장된 공식 URL 5건을 source-stratified로 직접 fetch했다.

- fetch COMPLETE: 5 / 5
- VERIFIED_OFFICIAL: 5 / 5
- NEEDS_VERIFICATION: 5 / 5
- GREEN / YELLOW / RED: 0 / 4 / 1
- `ENDED`: 0
- external requests: 5
- `ProductionAction=NONE`: 5 / 5

이 smoke는 population 정확도 측정이 아니라 fail-closed operational validation이다. DDC sample은 structured extraction은 COMPLETE였지만 복수 업소 claim이 한 row 비교에 함께 들어가 `SOURCE_CONFLICT + RED`가 발생했다. 안전성은 유지됐지만 향후 adapter에서 business-bound row-scoped extraction이 필요하다.

### 완료 경계와 아직 구현하지 않은 범위

- general official-source discovery/search provider
- LLM provider/model/SDK
- PDF text extraction capability/dependency
- OCR/HWP pipeline
- full 247 hold workload validation
- periodic execution (Phase 3 file history persistence는 별도로 구현됨)

이들은 현재 Phase 2 Core closeout의 blocker가 아니다. full 247-row validation is `NOT_RUN`, and future real-source GREEN은 그 row가 human audit을 통과하기 전까지 production approval을 받을 수 없다.

## Phase 3 Snapshot / Incremental Change Detection 상태

- P3-0 `businessId`: PR #96 merged
- P3-1/P3-2 History contracts, fingerprints, file store, dedup, rebuild, CAS: PR #98 merged
- P3-3 Benefit history: PR #100 merged; P3-4 post-fetch reuse: PR #102 merged
- P3-5 Location history: PR #104 merged; P3-6 matcher reuse: PR #106 merged
- P3-7 pure ReviewItem routing, COMMITTED read-only audit scanner, A/B/C representative matrix: PR #108 merged; Issue #107 completed
- 2026-09-28 local gates: data scripts 56/56 PASS; Android unit 99 tests (0 failures/errors, 1 skipped), lint 0 errors/25 warnings, debug build PASS; protected paths unchanged
- Bounded Phase 3 closeout status: `COMPLETE`. PR #108 final HEAD와 merge commit `d40e479b2f9e2b39839f338ef11259f126840460`의 post-merge CI run #209에서 `verify-data`와 `verify`가 모두 성공했고 parent Issue #94도 completed 상태다.

근거와 20개 parent gate는 [Phase 3 closeout handover](handover/2026-09-27-phase3-snapshot-incremental-closeout.md)에 기록한다. 이는 full 496-row current-state validation이나 periodic scheduler, provider-fetch reduction, automatic closure/ending, production auto-write, DB persistence를 포함하지 않는다.

## 안전 경계

- Contract v1은 A/B/C가 읽기 전용으로 사용한다.
- POI identity/location evidence는 군인 혜택의 현재 유효성 근거가 아니다.
- GREEN은 fast-review candidate일 뿐 모든 row는 final human approval 대상이다.
- RED는 폐업, 업체 부재, 혜택 종료를 뜻하지 않는다.
- operational observation은 실행 시점의 provider 결과이며 canonical 변경 권한을 만들지 않는다.

## 다음 액션

1. Phase 3 이후 product/UX 작업을 별도 설계·Issue로 시작한다.
2. PDF/HWP/OCR, SNS/blog, and general discovery는 source-expansion issue로 별도 판단한다.
3. 모든 후속 Phase에서도 `ProductionAction=NONE`, canonical/seed automatic write 금지, and GREEN human approval requirement를 유지한다.

장기 개발 방향은 [`docs/roadmap.md`](roadmap.md)를 확인한다.

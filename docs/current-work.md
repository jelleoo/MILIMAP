# 현재 작업 안내

이 문서는 팀원과 Codex가 저장소를 clone한 뒤 가장 먼저 확인하는 현재 개발 진입점입니다.

## 현재 기준선

- 개발 기준 브랜치: `dev`
- Phase 1 code baseline: `97d6070113196e922fb76af7508314b6eda8e7b7`
- Phase 2 Task 6 merge baseline: `d43c00ee07b471a55ed7ece4abecc1dc242ed8ce`
- Phase 2 Core Foundation: Issue #43 / Task 7 validation PR #50
- current dev baseline: `1e504809743ffce89a0d141b274fff2dc694680f` (PR #91 merged)
- 기준일: 2026-09-26
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

## 2026-09-26 Phase 2 최신 상태

Phase 2 Benefit Verification Core의 scoped HTML, MMA JSONP, XLSX 경로와 fixed representative closeout **evidence matrix**를 완료했다. current-code fixed-12 live replay는 replayable raw capture가 없어 `NOT_RUN_NO_REPLAYABLE_RAW_CAPTURE`이며, 이 branch의 Issue #92 evidence가 병합되면 roadmap Phase 2 상태는 현재 구현 범위에서 `COMPLETE`다.

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
- PDF: safe machine text/layout extraction runtime과 page/row provenance가 아직 승인되지 않음
- long heterogeneous live batch의 transport latency/retry/isolation은 별도 operational concern이며 현재 source adapter issue와 섞지 않음

Phase 2 이후의 다음 설계 대상은 Phase 3 snapshot/history이며, PDF/HWP/OCR, SNS/blog strong-evidence expansion, general discovery, and periodic execution은 later phases로 남는다.

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
- snapshot/history persistence and periodic execution

이들은 현재 Phase 2 Core closeout의 blocker가 아니다. full 247-row validation is `NOT_RUN`, and future real-source GREEN은 그 row가 human audit을 통과하기 전까지 production approval을 받을 수 없다.

## 안전 경계

- Contract v1은 A/B/C가 읽기 전용으로 사용한다.
- POI identity/location evidence는 군인 혜택의 현재 유효성 근거가 아니다.
- GREEN은 fast-review candidate일 뿐 모든 row는 final human approval 대상이다.
- RED는 폐업, 업체 부재, 혜택 종료를 뜻하지 않는다.
- operational observation은 실행 시점의 provider 결과이며 canonical 변경 권한을 만들지 않는다.

## 다음 액션

1. Phase 3 snapshot/history 설계를 별도 승인 절차로 시작한다.
2. PDF/HWP/OCR, SNS/blog, and general discovery는 source-expansion issue로 별도 판단한다.
3. 모든 후속 Phase에서도 `ProductionAction=NONE`, canonical/seed automatic write 금지, and GREEN human approval requirement를 유지한다.

장기 개발 방향은 [`docs/roadmap.md`](roadmap.md)를 확인한다.

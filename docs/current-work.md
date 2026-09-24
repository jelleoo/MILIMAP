# 현재 작업 안내

이 문서는 팀원과 Codex가 저장소를 clone한 뒤 가장 먼저 확인하는 현재 개발 진입점입니다.

## 현재 기준선

- 개발 기준 브랜치: `dev`
- Phase 1 code baseline: `97d6070113196e922fb76af7508314b6eda8e7b7`
- Phase 2 Task 6 merge baseline: `d43c00ee07b471a55ed7ece4abecc1dc242ed8ce`
- Phase 2 Core Foundation: Issue #43 / Task 7 validation PR #50
- 기준일: 2026-09-24
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

## Phase 2 Benefit Verification Core Foundation 상태

Phase 2 provider-neutral Core Foundation은 Contract, existing-source fetch/qualification/binding, evidence extraction/validation, claim comparison/evaluation, Shadow integration까지 구현됐고 Task 7에서 Golden safety와 existing-source operational smoke를 검증 중이다.

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

Task 7 Golden fixture는 real source-cited historical provenance와 synthetic algorithm fixture를 분리한다. historical release evidence는 현재 `ACTIVE` truth로 자동 승격하지 않으며, source/binding conflict fixture는 silent GREEN을 허용하지 않는다.

2026-09-24 existing-source live smoke는 canonical에 이미 저장된 공식 URL 5건을 source-stratified로 직접 fetch했다.

- fetch COMPLETE: 5 / 5
- VERIFIED_OFFICIAL: 5 / 5
- NEEDS_VERIFICATION: 5 / 5
- GREEN / YELLOW / RED: 0 / 4 / 1
- `ENDED`: 0
- external requests: 5
- `ProductionAction=NONE`: 5 / 5

이 smoke는 population 정확도 측정이 아니라 fail-closed operational validation이다. DDC sample은 structured extraction은 COMPLETE였지만 복수 업소 claim이 한 row 비교에 함께 들어가 `SOURCE_CONFLICT + RED`가 발생했다. 안전성은 유지됐지만 향후 adapter에서 business-bound row-scoped extraction이 필요하다.

### 아직 승인/구현하지 않은 범위

- general official-source discovery/search provider
- LLM provider/model/SDK
- PDF text extraction dependency
- XLSX parsing dependency
- OCR/HWP pipeline
- representative 247 hold workload validation
- positive control validation
- human GREEN audit

따라서 **Phase 2 Core Foundation 완료와 roadmap Phase 2 COMPLETE는 동일하지 않다.**

## 안전 경계

- Contract v1은 A/B/C가 읽기 전용으로 사용한다.
- POI identity/location evidence는 군인 혜택의 현재 유효성 근거가 아니다.
- GREEN은 fast-review candidate일 뿐 모든 row는 final human approval 대상이다.
- RED는 폐업, 업체 부재, 혜택 종료를 뜻하지 않는다.
- operational observation은 실행 시점의 provider 결과이며 canonical 변경 권한을 만들지 않는다.

## 다음 액션

1. Task 7 PR #50에서 Golden regression, live existing-source smoke evidence, deterministic data-tool suite, Android CI, protected-path diff를 최종 확인한다.
2. Issue #43의 provider-neutral Core Foundation 완료 조건을 closeout한다. 이 closeout은 roadmap Phase 2 COMPLETE를 의미하지 않는다.
3. full Phase 2로 넘어가기 전에 discovery provider, LLM/free-text extraction, PDF/XLSX adapter 중 필요한 항목을 별도 Issue/ADR 수준으로 승인받는다.
4. 승인된 adapter 이후 247 hold 중심 representative validation + positive controls + human GREEN audit를 수행한다.

장기 개발 방향은 [`docs/roadmap.md`](roadmap.md)를 확인한다.

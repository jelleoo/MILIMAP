# 현재 작업 안내

이 문서는 팀원과 Codex가 저장소를 clone한 뒤 가장 먼저 확인하는 현재 개발 진입점입니다.

## 현재 기준선

- 개발 기준 브랜치: `dev`
- 최신 확인 dev commit: `93c2e4455cb6628dfc1c2ffe0050b48524dedd89`
- Phase 1 Workstream A merge: PR #37 / Issue #28 완료
- Phase 1 Workstream B merge: PR #34 / Issue #29 완료
- Phase 1 Workstream C merge: PR #36 / Issue #30 완료
- Integration: Issue #38 OPEN — 별도 Shadow Mode runner 구현 진행 중
- Contract Foundation merge baseline: `761a04294a9bbf42f0767e200cc191f7f998828a`
- P3 data merge baseline: `edca54d23981501efa8ce602df98f5456973940c`
- 기준일: 2026-09-23
- release candidates: 249
- exact map pins: 111
- coordinate-unconfirmed: 138
- latest-benefit-evidence 부족 canonical hold: 247
- Android bundled seed version: 7

현재 코드/설정이 이 문서와 다르면 최신 `dev` 코드와 해당 Issue/PR을 우선합니다.

장기 개발 방향:
`docs/roadmap.md`

현재는 Phase 1만 실행 단위로 구체화합니다. Phase 2 이후의 담당자·세부 Issue·구현 파일은 지금 확정하지 않으며, Phase 1 완료 후 최신 `dev`와 실제 결과를 기준으로 다시 논의합니다.

## 현재 개발 목표

현재 구현 Phase는 **Benefit Business Verification Pipeline — Phase 1: POI Verification Core / Shadow Mode**입니다.

목표는 사람이 업체마다 지도 검색과 주소 대조를 처음부터 수행하는 비용을 줄이는 것입니다.

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
Ranking
        ↓
GREEN / YELLOW / RED
        ↓
Review Queue + Metrics
```

Phase 1은 자동으로 canonical이나 Android seed를 수정하지 않습니다. GREEN도 자동 production 승인 상태가 아닙니다.

전체 설계:
`docs/superpowers/specs/2026-09-10-benefit-business-verification-pipeline-design.md`

공통 Contract 설계:
`docs/superpowers/specs/2026-09-10-poi-verification-contracts-design.md`

공통 Contract Foundation:
`tools/data/lib/poi-verification-contracts.ps1`

Contract Foundation 테스트:
`tools/data/test-poi-verification-contracts.ps1`

## 왜 지금 이 Phase를 하는가

P2/P3 수동 검증을 통해 충분한 실제 판단 사례를 확보했습니다. 다음 115건을 같은 수동 방식으로 바로 반복하기보다, 이 결과를 Golden Dataset으로 사용해 자동 후보 탐색·비교 파이프라인을 먼저 검증합니다.

현재 좌표 미확정 138건은 다음처럼 구분합니다.

- P2/P3에서 이미 검토했으나 미확정: 23건
- 아직 새로운 우선순위 검토가 필요한 나머지: 115건

## Phase 1 Workstream 상태

세 Workstream은 공통 Contract Foundation을 읽기 전용 기준으로 사용하고, 다른 Workstream 구현을 기다리지 않고 fixture/mock으로 독립 개발합니다.

### Workstream A — Business Identity / Normalization

- 상태: **완료 / dev merge**
- Issue: #28 `[DATA][A] Identity / Normalization Core 구현` — closed
- PR: #37 `feat(data): add identity normalization core` — merged
- merge commit: `93c2e4455cb6628dfc1c2ffe0050b48524dedd89`
- 담당: 현민
- 전용 경로: `tools/data/lib/identity/**`, `tools/data/test-normalize-business.ps1`, 필요 시 `tools/data/testdata/identity/**`
- 출력 Contract: `NormalizedBusiness`

책임:
- 업체명 정규화
- 주소 정규화와 안전한 구조화
- 도로명/건물번호/지점/floor-unit identity 신호 추출
- normalization warning 기록

하지 않을 일:
- Naver POI API 검색
- 최종 후보 ranking
- GREEN/YELLOW/RED 판정
- canonical/seed 수정

### Workstream B — POI Discovery / Candidate Collection

- 상태: **완료 / dev merge**
- Issue: #29 `[DATA][B] POI Discovery Engine 구현` — closed
- PR: #34 `data: [B] multi-query POI discovery engine (#29)` — merged
- merge commit: `40de886c7f87a8ff75439438349be4d4487f077b`
- 담당: 재찬
- 구현 경로: `tools/data/lib/poi-discovery/discover-poi-candidates.ps1`
- 테스트: `tools/data/test-discover-poi-candidates.ps1`
- 입력 Contract: `NormalizedBusiness`
- 출력 Contract: `PoiDiscoveryBatch` + `PoiCandidate[]`

구현된 책임:
- adaptive query 생성
- strict query부터 broader query까지 후보 탐색
- 첫 non-empty result에서 무조건 중단하지 않기
- 여러 query 결과 aggregation
- POI dedup
- query/candidate evidence 보존
- COMPLETE/PARTIAL/FAILED discovery 상태 보고
- 정상 0건과 provider/API 실패 구분

B는 최종 production 승인, identity 분류, hard constraint/ranking, canonical/seed 수정을 수행하지 않습니다.

### Workstream C — Matching / Evaluation

- 상태: **완료 / dev merge**
- Issue: #30 `[DATA][C] POI Matching / Evaluation 구현` — closed
- PR: #36 `feat: implement POI matching evaluation` — merged
- merge commit: `40ac4bffec22ebc1534564201e5e07435f00497f`
- 담당: 프로젝트 오너 (`ilwoo-maker`)
- 후속 역할: Integration Owner
- 전용 경로: `tools/data/lib/poi-matching/**`, `tools/data/test-evaluate-poi-match.ps1`, 필요 시 `tools/data/testdata/poi-matching/**`
- 입력 Contract: `NormalizedBusiness + PoiDiscoveryBatch`
- 출력 Contract: `PoiMatchResult`

책임:
- hard constraints 우선 적용
- surviving candidate ranking
- GREEN/YELLOW/RED 분류
- reason/conflict/evidence 출력
- Golden Dataset regression tests
- false GREEN, recall, manual review rate 등 실제 측정 가능한 metrics

하지 않을 일:
- 검색 API 자체 구현
- canonical/seed 자동 반영
- Integration orchestration 동시 수정
- 임의 threshold 생성

C는 Contract fixture와 B의 frozen output shape로 독립 개발되었으며, 실제 A+B+C 연결은 세 Workstream이 모두 `dev`에 병합된 뒤 Issue #38에서 진행합니다.

## 공통 Contract 규칙

- `ContractType` + `ContractVersion=1` 사용
- 없는 text는 `''`, 빈 배열은 `@()`
- 좌표는 둘 다 존재하거나 둘 다 `$null`
- 원본 상호/주소 evidence 보존
- 애매한 지점·건물번호·층/호는 추측하지 않음
- discovery 실패와 정상 no-candidate를 반드시 구분
- `PARTIAL`/`FAILED` discovery 또는 matcher incompleteness는 `INCOMPLETE + YELLOW`
- GREEN은 fast-review candidate일 뿐 production 승인 아님
- RED는 폐업/업체 부재/혜택 종료 의미가 아님
- Phase 1 `PoiMatchResult.ProductionAction`은 항상 `NONE`
- `tools/data/lib/poi-verification-contracts.ps1`은 A/B/C 구현 PR에서 임의 수정하지 않음

## Golden Dataset 기준

Phase 1은 기존 사람 검토 결과를 회귀검증 기준으로 사용합니다.

- positive: 기존 exact verified pins + P2/P3 승인 사례
- ambiguous: P2/P3 보류 사례
- negative: P2/P3 반려 사례

알려진 safety regression 예:

- `버섯집 초리골`: 건물번호 불일치 → GREEN 금지
- `짜장마을`: 신뢰 가능한 근거 부족 → GREEN 금지
- `이지현미용실`: canonical 26 vs POI 23 → GREEN 금지
- `인헤어`: canonical 902·2동 104호 vs POI 904 → GREEN 금지

`거시기닭갈비`는 상호·지점·주소가 일치했지만 전화번호 차이가 있었던 cautionary positive로 보존합니다.

## Integration

A/B/C는 모두 `dev`에 병합되었고, 별도 Integration Issue #38에서 Shadow Mode runner를 구현 중입니다. Integration Owner는 프로젝트 오너입니다.

Integration Owner의 책임:
- 최신 `dev`에서 세 모듈 연결
- 별도 `tools/data/invoke-phase1-poi-shadow-mode.ps1` runner 유지; legacy `verify-canonical-benefit-poi.ps1`는 유지
- deterministic mock Shadow Mode 회귀검증
- P1/P2/P3 Golden Dataset 회귀검증
- metric reconciliation
- false GREEN 확인
- canonical/Android seed가 자동 수정되지 않았는지 확인

GREEN은 fast-review candidate일 뿐 모든 row는 최종 human approval 대상입니다. operational live Shadow run은 credentials와 명시적 report path가 있을 때만 별도로 read-only 수행하며, 현재는 **NOT RUN**입니다. Issue #38과 Phase 1 완료 선언은 deterministic implementation verification만으로 자동 완료하지 않습니다.

Phase 2 이후의 방향은 `docs/roadmap.md`에서 확인하고, 구체 설계와 Issue 생성은 Phase 1 완료 후 다시 논의합니다.

## 현재 하지 않을 작업

- 남은 115건 대규모 수동 좌표 캠페인
- canonical 자동 좌표 반영
- Android seed 자동 반영
- GREEN 자동 production 승인
- Benefit Verification Core 구현
- Snapshot/change history persistence
- SNS crawler
- 정기 scheduler
- event-driven monitoring
- Room/server DB/schema 변경
- API/auth 변경
- 신규 외부 dependency 추가

## 다음 액션

1. Integration #38의 deterministic runner/test/Golden/report 검증을 완료한다.
2. deterministic 검증과 별도로 credentials가 이용 가능할 때만 operational live Shadow run을 read-only로 수행한다.
3. 사람 검토와 Issue #38 완료조건 확인 전에는 Phase 1 완료나 production apply를 선언하지 않는다.
4. Phase 2 설계와 Issue 분할은 Integration/Shadow Mode Gate 이후 최신 결과를 기준으로 다시 논의한다.

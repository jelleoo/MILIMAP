# 현재 작업 안내

이 문서는 팀원과 Codex가 저장소를 clone한 뒤 가장 먼저 확인하는 현재 개발 진입점입니다.

## 현재 기준선

- 개발 기준 브랜치: `dev`
- 현재 dev 기준 commit: `dc2bfc42feba20f92341b620876d88c5614d563e`
- P3 data merge baseline: `edca54d23981501efa8ce602df98f5456973940c`
- 기준일: 2026-09-10
- release candidates: 249
- exact map pins: 111
- coordinate-unconfirmed: 138
- latest-benefit-evidence 부족 canonical hold: 247
- Android bundled seed version: 7

현재 코드/설정이 이 문서와 다르면 최신 `dev` 코드와 해당 Issue/PR을 우선합니다.

## 현재 개발 목표

다음 구현 Phase는 **Benefit Business Verification Pipeline — Phase 1: POI Verification Core / Shadow Mode**입니다.

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

## 왜 지금 이 Phase를 하는가

P2/P3 수동 검증을 통해 충분한 실제 판단 사례를 확보했습니다. 다음 115건을 같은 수동 방식으로 바로 반복하기보다, 이 결과를 Golden Dataset으로 사용해 자동 후보 탐색·비교 파이프라인을 먼저 검증합니다.

현재 좌표 미확정 138건은 다음처럼 구분합니다.

- P2/P3에서 이미 검토했으나 미확정: 23건
- 아직 새로운 우선순위 검토가 필요한 나머지: 115건

## 예정된 3인 병렬 Workstream

아래 3개 구현 Issue는 아직 생성하지 않았습니다. 먼저 공통 Contract 설계 승인과 Contract Foundation 구현을 끝낸 뒤 각각 생성합니다.

### Workstream A — Business Identity / Normalization

책임:

- canonical row → `NormalizedBusiness`
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

책임:

- `NormalizedBusiness` → `PoiDiscoveryBatch`
- adaptive query 생성
- strict query부터 broader query까지 후보 탐색
- 첫 non-empty result에서 무조건 중단하지 않기
- 여러 query 결과 aggregation
- POI dedup
- `PoiCandidate[]`와 query/candidate evidence 보존
- COMPLETE/PARTIAL/FAILED discovery 상태 보고

하지 않을 일:

- 최종 production 승인
- 최종 identity 분류
- canonical/seed 수정

### Workstream C — Matching / Evaluation

책임:

- `NormalizedBusiness + PoiDiscoveryBatch` → `PoiMatchResult`
- hard constraints 우선 적용
- surviving candidate ranking
- GREEN/YELLOW/RED 분류
- reason/conflict/evidence 출력
- Golden Dataset regression tests
- false GREEN, recall, manual review rate 등 실제 측정 가능한 metrics

하지 않을 일:

- 검색 API 자체 구현
- canonical/seed 자동 반영
- 임의 threshold 생성

## 확정 대상으로 제안된 공통 Contract

Issue #24에서 아래 Contract를 구현 수준으로 고정합니다.

- `NormalizedBusiness`
- `PoiCandidate`
- `PoiDiscoveryBatch`
- `PoiMatchResult`
- supporting records: query attempt / discovery evidence / match evidence

핵심 규칙:

- `ContractType` + `ContractVersion=1` 사용
- 없는 text는 `''`, 빈 배열은 `@()`
- 좌표는 둘 다 존재하거나 둘 다 `$null`
- 원본 상호/주소 evidence 보존
- 애매한 지점·건물번호·층/호는 추측하지 않음
- discovery 실패와 정상 no-candidate를 반드시 구분
- `PARTIAL`/`FAILED` discovery를 정상 RED로 오판하지 않음
- GREEN은 fast-review candidate일 뿐 production 승인 아님
- Phase 1 `PoiMatchResult.ProductionAction`은 항상 `NONE`
- Contract 변경은 A/B/C 구현 PR 내부에서 임의로 하지 않음

정확한 필드·타입·허용 상태/코드와 불변조건은 Contract spec을 단일 기준으로 사용합니다.

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

`거시기닭갈비`처럼 상호·지점·주소는 일치했지만 부가 정보에 불일치가 있었던 승인 사례는 단순 완벽 positive로 취급하지 않고 주의 사례로 보존합니다.

## 병렬 개발 시작 절차

각 팀원은 구현 Issue가 만들어진 뒤 다음 순서로 시작합니다.

```text
1. git fetch origin
2. 최신 dev 확인
3. AGENTS.md 읽기
4. docs/current-work.md 읽기
5. 전체 설계 spec 읽기
6. Contract spec 읽기
7. 자기 Issue 확인
8. 수정 허용/금지 경로와 다른 활성 Issue의 예약 파일 확인
9. 최신 origin/dev에서 자기 branch/worktree 생성
10. Codex에 Issue 번호와 경계 전달
11. 독립 구현/테스트/PR
```

B와 C는 다른 Workstream 구현을 기다리지 않고 frozen Contract에 맞춘 fixture/mock으로 개발할 수 있어야 합니다.

## Integration

세 Workstream이 각각 독립 PR로 병합된 뒤 공용 orchestration 연결은 한 명의 Integration Owner만 수행합니다.

Integration Owner의 책임:

- 최신 `dev`에서 세 모듈 연결
- 공용 orchestration 파일 단독 수정
- 전체 Shadow Mode 실행
- P1/P2/P3 Golden Dataset 회귀검증
- metric reconciliation
- false GREEN 확인
- canonical/Android seed가 자동 수정되지 않았는지 확인

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

1. Issue #24의 Contract spec을 프로젝트 오너가 검토·승인한다.
2. 승인된 Contract만 구현하는 작은 Contract Foundation Issue/PR을 진행한다.
3. Foundation을 `dev`에 병합한다.
4. Workstream A/B/C 구현 Issue 3개를 만든다.
5. 세 팀원이 독립 branch/worktree에서 병렬 개발한다.
6. 세 PR 병합 후 Integration Issue를 별도로 진행한다.

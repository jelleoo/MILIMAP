# MILIMAP Development Roadmap

- Status: Directional roadmap
- Date: 2026-09-10
- Current development branch: `dev`
- Current active phase: Phase 1 — POI Verification Core / Shadow Mode

이 문서는 MILIMAP의 장기 개발 방향을 팀원이 한눈에 확인하기 위한 로드맵입니다.

현재 실행 단위는 **Phase 1만 구체화**되어 있습니다. Phase 2 이후는 방향과 목적만 공유하며, 미래 담당자·세부 Issue·구현 파일·Contract는 지금 고정하지 않습니다.

항상 최신 `dev`, 해당 시점의 Issue/PR, 승인된 ADR/docs가 이 문서보다 우선합니다.

## 운영 원칙

1. 현재 Phase에 필요한 실제 구현 Issue만 생성합니다.
2. 미래 Phase의 세부 Issue와 담당자는 미리 확정하지 않습니다.
3. 다음 Phase에 진입하기 전에 최신 `dev`와 직전 Phase 결과를 다시 검토합니다.
4. 공통 Contract나 공유 경계가 필요한 경우 병렬 구현 전에 먼저 고정합니다.
5. 각 구현은 목적 단위 Issue와 PR로 작게 진행합니다.
6. 핵심 아키텍처, 데이터베이스 방식, 외부 라이브러리, 인증 방식, API 계약, 데이터 스키마 변경은 별도 승인 없이 진행하지 않습니다.
7. 데이터 변경에는 출처, 확인일, 상태를 남기며 혜택 데이터를 추측하지 않습니다.
8. 이전 Phase의 안전 Gate를 통과하기 전 다음 Phase의 production 적용을 선행하지 않습니다.

---

## 전체 흐름

```text
Phase 1 — POI Verification Core / Shadow Mode
        ↓
Phase 1 Integration + Shadow Mode Gate
        ↓
Phase 2 — Benefit Verification Core
        ↓
Phase 3 — Snapshot / Incremental Change Detection
        ↓
Phase 4 — Multi-source Adapters
        ↓
Phase 5 — Periodic Execution
        ↓
Phase 6 — Web/SNS Discovery Expansion
        ↓
Phase 7 — Near-event-driven Monitoring
```

---

## Phase 1 — POI Verification Core / Shadow Mode

### 상태

현재 진행 중입니다.

현재 병렬 구현 Issue:

- #28 — Business Identity / Normalization Core
- #29 — POI Discovery Engine
- #30 — POI Matching / Evaluation

공통 Contract Foundation은 `dev`에 병합되어 있습니다.

### 목표

사람이 업체마다 지도 검색과 주소 대조를 처음부터 수행하는 비용을 줄이고, canonical 업체와 실제 POI 후보를 안전하게 비교할 수 있는 reusable verification core를 만듭니다.

### 핵심 구성

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

### Shadow Mode 원칙

- canonical 자동 수정 금지
- Android seed 자동 수정 금지
- GREEN 자동 production 승인 금지
- 검색 실패를 폐업/업체 부재로 해석하지 않음
- POI 근거를 군인 혜택 근거로 사용하지 않음
- Phase 1 `ProductionAction`은 항상 `NONE`

### Phase 1 완료 조건

Issue #28/#29/#30의 구현 PR이 각각 `dev`에 병합된 것만으로 Phase 1이 완료되지는 않습니다.

세 모듈 병합 후 별도의 Integration Issue를 열어 다음을 완료해야 합니다.

1. 최신 `dev`에서 A/B/C 모듈 연결
2. 전체 Shadow Mode 실행
3. P1/P2/P3 Golden Dataset 회귀검증
4. 알려진 ambiguous/rejected 사례의 false GREEN 확인
5. 실제 Candidate Recall / GREEN Precision / Manual Review Rate / No-match / API Calls per Row 등 측정 가능한 metric 정리
6. canonical 및 Android seed가 자동 수정되지 않았는지 확인
7. 실행 결과와 남은 위험을 보고

이 Gate를 통과한 시점을 Phase 1 완료로 봅니다.

### Phase 1 이후

Phase 1 결과를 바탕으로 Phase 2를 바로 구현하지 않습니다.

먼저 팀에서 다음을 다시 논의합니다.

- Phase 1 matcher/discovery 품질
- 실제 수동 검토량 감소 효과
- false GREEN 및 보류 패턴
- 현재 데이터/코드 구조
- Phase 2에 필요한 Contract와 병렬화 방식

그 후 최신 `dev` 기준으로 Phase 2의 실제 Issue를 생성합니다.

---

## Phase 2 — Benefit Verification Core

### 방향

POI 위치가 아니라 **군인 혜택 자체가 현재 유효한지**를 검증하는 core를 구축합니다.

### 예상 관심 영역

- 혜택 설명 정규화
- 적용 대상/조건/인증 방법 구조화
- 출처와 현재 적용 가능성 검증
- 명시된 `validFrom` / `validUntil` 처리
- 혜택 변경·종료·불명확 상태 탐지
- benefit review queue
- benefit Golden Dataset

### 중요한 원칙

- POI 존재 여부와 혜택 유효성은 별도 검증합니다.
- 근거가 없는 혜택 종료일을 만들지 않습니다.
- `validUntil`과 내부 `nextReviewAt`을 혼동하지 않습니다.
- 비공식 정보는 사실이 아니라 탐색 단서로 사용합니다.

### 현재 확정하지 않는 것

- 담당자
- 세부 Issue
- 구현 파일
- persistent schema
- API 계약
- 자동 production 적용 정책

구체 설계는 Phase 1 완료 후 다시 논의합니다.

---

## Phase 3 — Snapshot / Incremental Change Detection

### 방향

매 실행마다 모든 대상을 처음부터 검증하는 대신, **이전 관찰 결과와 현재 관찰 결과를 비교해 실제 변경 후보를 찾는 구조**로 발전시킵니다.

### 예상 관심 영역

- 이전/현재 observation 비교
- location/benefit/evidence fingerprint
- 신규·변경·이동 의심·폐업 의심·혜택 변경·혜택 종료 후보 탐지
- 안전한 경우 unchanged 작업 생략
- audit 가능한 snapshot/history

persistent schema나 저장 방식은 이 Phase 시작 전에 별도 논의와 승인이 필요합니다.

---

## Phase 4 — Multi-source Adapters

### 방향

검증 가능한 데이터 출처를 확장해 특정 단일 소스에 의존하지 않는 구조를 만듭니다.

### 예상 소스 범주

- 정부/지자체/공공기관
- 사업자 공식 웹사이트
- 사업자 공식 SNS/블로그
- 사용자 제보 및 커뮤니티 등 discovery signal

각 소스는 API/이용약관/라이선스/재배포 가능 범위를 별도로 확인해야 합니다.

비공식 소스는 강한 근거가 확보되기 전까지 discovery-only로 취급합니다.

---

## Phase 5 — Periodic Execution

### 방향

검증 core를 수동 실행 도구에서 **주기적으로 재검증할 수 있는 운영 pipeline**으로 발전시킵니다.

### 예상 관심 영역

- scheduled execution
- evidence age와 risk에 따른 재확인
- 변경 후보 review queue 생성
- 실패/재시도/실행 이력
- 처리량 확대와 승인 기준 분리

처리량에는 인위적인 제한을 두지 않습니다. 대신 승인 기준은 낮추지 않고, 불확실한 후보는 빠르게 보류하며, 중간 품질 checkpoint와 최종 일괄 재검토를 통해 대량 작업에서 발생할 수 있는 검증 오류를 차단합니다.

---

## Phase 6 — Web/SNS Discovery Expansion

### 방향

기존 목록을 재검증하는 것에서 더 나아가 **새로운 군인 혜택 신호를 발견하는 능력**을 확장합니다.

### 예상 관심 영역

- 새로운 공개 혜택 신호 발견
- 이미 본 콘텐츠 중복 제거
- 관련성 높은 신규/변경 정보만 후속 검증으로 전달
- AI-assisted extraction이 필요한 지점 분리

이 단계에서도 발견과 승인은 분리합니다.

발견된 게시글이나 커뮤니티 정보만으로 verified benefit을 생성하지 않습니다.

---

## Phase 7 — Near-event-driven Monitoring

### 방향

장기적으로는 외부 변화가 발생한 시점에 가깝게 기존 verification pipeline을 증분 실행할 수 있는 구조를 목표로 합니다.

### 예상 트리거

- 제공 가능한 공식 API/change feed
- webhook
- polling
- 기타 변경 감지 신호

이 Phase는 별도의 검증 규칙을 만들지 않고 기존 location/benefit verification core를 재사용해야 합니다.

실시간성보다 검증 정확성과 근거 보존이 우선입니다.

---

## 장기적으로 지켜야 할 서비스 기준

MILIMAP이 장기적으로 유지해야 할 진실은 다음과 같습니다.

> 현재 실제로 존재하며, 현재 군인에게 유효한 혜택을 제공하는 업소를 지속적으로 발견·검증·추적하고, 그 최신 위치와 최신 혜택을 사용자에게 제공한다.

이를 위해 항상 다음을 분리해서 다룹니다.

- Business Identity
- Location Observation
- Benefit Observation
- Evidence Record
- Current State / Release Eligibility

POI는 혜택 근거가 아니며, 공식 혜택 데이터 한 행은 현재 위치의 증거가 아닙니다.

---

## 다음 Phase를 시작하는 방법

Phase가 완료되면 곧바로 이 문서의 다음 항목을 구현하지 않습니다.

다음 절차를 거칩니다.

```text
현재 Phase 완료
        ↓
결과 / 위험 / metric 검토
        ↓
최신 dev 확인
        ↓
다음 Phase 설계 논의
        ↓
필요 시 Contract / ADR 승인
        ↓
실제 구현 Issue 생성
        ↓
담당 결정
        ↓
개발 / PR / dev merge
```

즉, **로드맵은 미리 공유하지만 실제 Issue와 담당자는 해당 Phase에 도달했을 때 최신 코드와 결과를 기준으로 결정합니다.**

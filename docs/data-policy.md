# 데이터 정책

## 기본 원칙

- 혜택, 대상, 조건, 상태와 좌표를 추측해서 생성하지 않습니다.
- 출처를 설명할 수 없는 데이터를 Production seed에 추가하지 않습니다.
- 공공데이터, 지자체 자료, 업체 직접 근거, 자체 조사/발견 신호를 구분합니다.
- 수집과 저장소 재배포가 허용되는지 확인하고 불명확하면 병합하지 않습니다.
- 개인정보, 운영 DB dump와 비밀정보를 저장소에 넣지 않습니다.
- 데이터 변경에는 출처, 확인일, 상태를 보존합니다.

## 신뢰성 정보

Production에 사용하는 혜택은 가능한 범위에서 다음 정보를 유지합니다.

- `sourceType`
- `sourceLabel`
- `sourceUrl`
- `sourceId`
- `lastVerifiedAt`
- `verificationMethod`
- `status`
- `eligibleTarget`
- `usageCondition`

상태의 개념적 의미는 다음과 같습니다.

- `ACTIVE`: 출처와 최근 확인 근거가 있어 현재 제공 중으로 판단
- `NEEDS_VERIFICATION`: 정보 또는 좌표의 추가 확인이 필요
- `ENDED`: 종료 근거가 확인됨

확인되지 않은 항목을 `ACTIVE`로 바꾸지 않습니다. 향후 Benefit Verification Pipeline의 상태 모델은 별도 설계/Issue에 따라 확장할 수 있으며, 기존 canonical/Room schema를 이 문서만으로 변경하지 않습니다.

## Business Identity, 위치, 혜택의 분리

다음 세 가지는 서로 다른 검증 대상입니다.

1. 동일한 실제 영업장인지에 대한 Business Identity
2. 현재 POI/주소/좌표가 맞는지에 대한 Location Verification
3. 현재 군 혜택이 유효한지에 대한 Benefit Verification

POI가 정확하다는 사실만으로 군 혜택이 현재 유효하다고 판단하지 않습니다. 반대로 최신 공식 혜택 목록에 있다는 사실만으로 현재 POI 좌표가 정확하다고 판단하지 않습니다.

## 출처 계층과 노출 정책

- 정부·지자체·공공기관: 강한 공식 근거 후보
- 업체 공식 홈페이지/SNS/블로그: 업체 직접 근거 후보
- 개인 블로그·커뮤니티·미확인 SNS·사용자 제보: 내부 discovery signal만 허용

비공식 discovery signal은 사용자에게 검증된 혜택 근거로 직접 노출하지 않습니다. 더 강한 최신 근거를 찾기 위한 탐색 단서로만 사용합니다.

## 정규화와 중복

- 원본 값을 보존한 뒤 업체명과 주소의 정규화 값을 비교에 사용합니다.
- 업체명, 도로명주소, source ID, 출처와 혜택 내용을 함께 비교합니다.
- 단순히 이름이 같거나 건수를 늘리기 위해 두 데이터를 병합하지 않습니다.
- NULL 주소, 특수문자, 지번·도로명 차이와 동일 주소의 복수 업체를 별도로 검토합니다.
- 좌표가 없는 데이터는 지도 표시 가능 데이터와 구분하고 좌표를 임의 생성하지 않습니다.
- 좌표에는 `좌표출처`, `좌표출처URL`, `좌표검증상태`를 함께 기록합니다.
- 결과 없음, 복수 결과, 지역/주소/건물번호/지점 불일치는 좌표를 비워 두고 검토 대상으로 분리합니다.
- fuzzy/string similarity는 후보 ranking 보조 신호일 수 있지만 명확한 주소·건물번호·지점 충돌을 덮어쓰지 않습니다.

## 현재 release seed 기준

2026-09-10 P3 병합 직후 기준 Android release seed는 249건입니다.

- release candidates: 249
- exact map pins: 111
- coordinate-unconfirmed: 138
- bundled seed version: 7
- 최신 혜택 근거 부족으로 release에서 보류된 canonical 행: 247

정확 지도 핀은 실제 POI의 동일 영업장임이 상호·주소·지점 등 엄격한 근거로 검증된 행만 유지합니다. 좌표가 확정되지 않은 release candidate는 목록/상세에서 유지할 수 있지만 잘못된 지도 핀을 만들기 위해 좌표를 추정하지 않습니다.

P2/P3에서 이미 검토했으나 좌표 미확정인 보류·반려는 23건이고, 그 외 신규 우선순위 검증 대상은 115건입니다. 다음 대규모 수동 캠페인보다 Phase 1 POI Verification Core를 먼저 구현해 P1/P2/P3 수동 결과를 Golden Dataset으로 사용합니다.

## Geocoding과 POI 검증

주소 Geocoding 결과는 실제 영업장 POI 검증과 동일하지 않습니다.

- 원본 시·도, 도로명과 건물번호가 일치하는 단일 Geocoding 결과라도 감사/탐색용 좌표 후보로 취급합니다.
- Naver/API HUB 등의 POI 결과는 실제 상호·주소·지점 identity를 별도로 검증합니다.
- reference POI 또는 기존 좌표가 있다는 사실만으로 승인을 정당화하지 않습니다.
- `확인 후보` 또는 GREEN 분류는 초기 Phase에서 자동 production 승인 상태가 아닙니다.

## Benefit validity와 재검토 시점

혜택 기간을 다룰 때 실제 근거가 있는 유효기간과 내부 재검토 시점을 구분합니다.

- `validFrom`: 출처가 명시한 실제 시작일만 기록
- `validUntil`: 출처가 명시한 실제 종료일만 기록
- `observedAt`: 근거를 관측한 시점
- `lastVerifiedAt`: 근거를 마지막으로 검증한 시점
- `nextReviewAt`: 내부 운영상 재검토 시점

출처에 종료일이 없으면 `validUntil`을 추정하지 않습니다. `nextReviewAt`은 혜택 종료일이 아닙니다.

## Shadow Mode 원칙

Benefit Business Verification Pipeline의 Phase 1은 Shadow Mode입니다.

- 검색 자동화 가능
- 후보 수집·중복 제거 가능
- hard constraint와 ranking 가능
- GREEN/YELLOW/RED 분류 및 review queue 생성 가능
- canonical 자동 수정 금지
- Android seed 자동 수정 금지
- GREEN 자동 승인 금지

처리량은 늘릴 수 있지만 승인 기준은 낮추지 않습니다. 불확실한 후보는 보류하고 근거와 판정 이유를 남깁니다.

## Data PR 요구사항

Data PR에는 다음을 기록합니다.

- 출처와 원문 URL
- 수집일 또는 확인일
- endpoint와 요청 조건(실제 키 제외)
- 입력, 출력과 건수
- 정규화 및 중복 기준
- schema와 재현 명령
- 검증 결과와 미확인 항목
- 재배포 권한 또는 라이선스 상태
- 변경 전/후 release candidate, exact pin, coordinate-unconfirmed 수치
- 실행한 테스트와 실행하지 못한 테스트

대용량, 자주 변경되는 운영 데이터와 라이선스가 불명확한 원본은 Git 외부 저장소를 검토합니다.

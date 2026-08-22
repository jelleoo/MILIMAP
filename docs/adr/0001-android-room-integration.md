# ADR 0001: MiliPercent Room 기반 Android 통합

- 상태: Proposed
- 날짜: 2026-08-22
- 관련 이슈: https://github.com/jelleoo/MILIMAP/issues/4
- 결정 참여자: Android 공동 개발팀

## 배경

MILIMAP과 MiliPercent에는 서로 다른 Android 구현이 있다.

- MILIMAP은 모노레포, 네이버 지도, 현재 위치, 지도 마커, 상세 UX, 수도권 Seed를 제공한다.
- MiliPercent는 Room, Repository, ViewModel, UiState, Navigation Compose, Room migration 및 테스트 구조를 제공한다.
- MILIMAP Android는 `SQLiteOpenHelper`와 `AppController`가 데이터·상태·인증·화면 책임을 함께 가진다.
- MiliPercent Android는 장기 확장에 더 적합한 단방향 데이터 흐름과 단일 Room 저장소를 가진다.
- 두 앱 모두 외부 배포 이력이 없으므로 기존 applicationId, 서명, 사용자 DB와의 업데이트 호환성 제약은 없다.

기준 커밋은 다음과 같다.

- MILIMAP: `dev@8e7b47a285f742faaa8d527fa34e31905de575e6`
- MiliPercent: `main@5e3d7331d59979e172a67921fb45acedde11da26`

## 결정

다음 결정을 팀 승인 대상으로 제안한다.

1. 공동 저장소와 모노레포 구조는 MILIMAP을 유지한다.
2. `apps/android`의 Core 기준선은 MiliPercent를 사용한다.
3. Room을 유일한 로컬 데이터 Source of Truth로 사용한다.
4. UI 상태는 `Repository -> ViewModel -> UiState -> Compose` 흐름으로 전달한다.
5. MILIMAP의 `SQLiteOpenHelper`, `AppController`, 로컬 사용자·즐겨찾기·첫 가입자 관리자 구조는 새 기준선에 이식하지 않는다.
6. MILIMAP의 네이버 지도, 마커, 현재 위치, 상세 UX와 검증 데이터는 새 구조에 맞춰 단계적으로 이식한다.
7. 두 저장소의 Git history를 `--allow-unrelated-histories`로 병합하지 않는다. MiliPercent의 정확한 source commit을 문서와 PR에 기록하고 tracked Android 파일만 가져온다.
8. 통합 작업은 최신 `dev`에서 분기한 공유 통합 브랜치에서 수행하고, 핵심 기능 동등성을 회복한 뒤에만 `dev`로 최종 병합한다.
9. 전체 통합 기간에는 package와 applicationId를 `com.example.milipercent`로 유지한다. Naver Cloud Console에는 이 개발 package를 등록하고, 출시용 applicationId 결정은 통합 완료 후 별도 Issue로 처리한다.
10. 실제 비밀값은 커밋하지 않는다. 저장소에는 키 이름과 주입 구조만 둔다.

## 목표 데이터 흐름

```text
MMA API ---------+
Manual Seed -----+--> Repository --> Room --> ViewModel --> UiState --> Compose UI
Verified Data ---+

LocationDataSource --> ViewModel --> UiState --> Naver Map
```

지도는 별도 DB나 별도 전역 Controller를 만들지 않는다. Room에서 관찰한 혜택 중 유효한 좌표를 가진 항목만 지도용 UiModel로 변환한다.

## 통합 범위

첫 Core 기준선에 포함한다.

- Room Entity, DAO, Database, migration, exported schema
- Repository와 local/remote data source
- ViewModel, UiState, Navigation Compose
- MMA API 전체 페이지 수집, 재시도, 서울 필터
- MiliPercent Manual Seed 12건과 검증 로더
- Unit test, Android test, Room migration test
- Debug 빌드 전용 `MANUAL_LOCAL` 관리 도구

첫 Core 기준선에서 제외한다.

- Naver Map과 현재 위치
- MILIMAP 484건 Seed의 즉시 복사
- 사용자 로그인과 즐겨찾기
- Firebase/Auth, 서버, iOS, PostGIS
- 대규모 UI 재설계

## 데이터 호환성

읽기 전용 비교 결과는 다음과 같다.

- MiliPercent Manual Seed: 12건, 좌표 없음
- MILIMAP Seed: 484건, 좌표 339건
- 정규화한 업체명 또는 업체명+주소가 일치하는 두 Seed 항목: 0건

따라서 지도 코드는 좌표가 전혀 없는 데이터셋에서도 정상 동작해야 한다. 실제 마커 동등성은 484건 데이터의 출처·중복·좌표를 검증해 Room에 반영한 뒤 확인한다.

## 결과와 위험

### 긍정적 결과

- DB와 화면 상태의 기준이 하나로 정리된다.
- API 실패 시 Room 캐시를 유지할 수 있다.
- 지도·위치·데이터 기능을 독립적으로 테스트하고 교체할 수 있다.
- Room schema와 migration history를 보존할 수 있다.
- 기존 `dev`는 통합 기간에도 동작 가능한 상태로 유지된다.

### 부정적 결과와 비용

- 통합 브랜치를 일정 기간 관리해야 한다.
- Core 교체 후 지도·위치가 복구될 때까지 통합 브랜치 내부에는 기능 공백이 존재한다.
- MILIMAP Seed와 동적 MMA 데이터의 중복 분석이 별도로 필요하다.
- Naver Cloud Console에 개발 package `com.example.milipercent`를 별도로 등록해야 한다.

## 고려했으나 채택하지 않은 대안

### 관련 없는 Git history의 직접 병합

Gradle root, package, manifest와 동일 역할 파일의 대규모 충돌을 만들므로 제외한다.

### SQLiteOpenHelper와 Room을 함께 유지

데이터 Source of Truth가 둘이 되어 동기화와 장애 복구가 불명확하므로 제외한다.

### AppController와 ViewModel을 함께 유지

화면 상태와 이벤트 소유권이 분산되므로 제외한다.

### Core, Map, Location, Data를 한 PR에 병합

리뷰와 rollback 단위를 잃고 실패 원인을 분리하기 어려우므로 제외한다.

### Core를 dev에 바로 병합

지도와 현재 위치가 복구되기 전에 공동 개발 기준에서 기존 기능이 사라지므로 제외한다.

## 승인 조건

이 ADR이 `Accepted`로 변경되고 Issue #4에서 팀 합의가 확인되기 전에는 Android Core 교체를 시작하지 않는다.

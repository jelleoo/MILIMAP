# Android Room Integration Design

## Summary

MILIMAP을 공동 모노레포로 유지하고 MiliPercent의 Android Core를 `apps/android`의 새 기준선으로 사용한다. 기존 MILIMAP의 지도·현재 위치·UX·검증 데이터는 Room/Repository/ViewModel 구조에 맞춰 작은 단계로 이식한다. 작업은 Issue [#4](https://github.com/jelleoo/MILIMAP/issues/4)와 ADR 0001의 범위 안에서 수행한다.

## Goals

- Room을 Android 앱의 유일한 로컬 DB로 만든다.
- `Repository -> ViewModel -> UiState -> Compose` 흐름을 유지한다.
- 목록, 서울 25개 구 필터, 검색, 상세, API 캐시와 Manual Seed를 보존한다.
- 네이버 지도, 좌표 마커, 마커 클릭 상세 이동과 현재 위치를 새 구조에서 복구한다.
- 데이터 출처, 검증일, 상태와 좌표를 손실하지 않는다.
- 각 단계가 독립적으로 검토·검증·rollback 가능하게 한다.
- 핵심 기능이 복구되기 전까지 현재 `dev`의 동작을 유지한다.

## Non-goals

- 기존 SQLite 사용자·즐겨찾기·첫 가입자 관리자 구조 이식
- Firebase/Auth 도입
- 서버, iOS, PostGIS 구현
- 484건 Seed의 무검증 복사
- 전국 데이터 확장
- Marker clustering
- 전체 UI 재설계
- 두 Git history의 직접 병합

## Source Baselines

| Source | Branch and commit | Role |
| --- | --- | --- |
| MILIMAP | `dev@8e7b47a285f742faaa8d527fa34e31905de575e6` | 모노레포, 지도·위치·UX·데이터 원본 |
| MiliPercent | `main@5e3d7331d59979e172a67921fb45acedde11da26` | Android Core 기준선 |

MiliPercent 로컬 프로젝트의 untracked 파일, `.git`, `.idea`, `.gradle`, `build`, `app/build`, `local.properties`는 통합 대상이 아니다. source commit에 포함된 tracked 파일만 가져온다.

## Git and Rollback Strategy

1. 최신 `origin/dev`의 정확한 commit을 확인한다.
2. Android 교체 전에 해당 commit에 annotated tag `android-mvp-before-room-integration-20260822`를 만들고 원격에 보존한다.
3. 최신 `dev`에서 `feature/android-room-integration`을 만든다.
4. 단계별 브랜치는 공유 통합 브랜치에서 분기하고 PR target도 공유 통합 브랜치로 한다.
5. 공유 통합 브랜치를 공개한 뒤에는 history를 강제로 재작성하지 않는다.
6. `dev`에 새 변경이 생기면 검증 시점마다 공유 통합 브랜치에 merge하고 전체 gate를 다시 실행한다.
7. Core·Map·Location·검증 데이터가 함께 동작한 뒤 공유 통합 브랜치에서 `dev`로 최종 PR을 연다.
8. 중대한 회귀는 후속 수정으로 덮지 않고 해당 단계 PR을 revert한다.

문서 및 phase branch 이름은 저장소 prefix 규칙을 따른다.

- `docs/issue-4-android-integration-design`
- `feature/android-room-integration`
- `chore/android-core-baseline`
- `chore/android-secret-preparation`
- `feature/android-naver-map-room`
- `feature/android-current-location`
- `data/android-benefit-contract`
- `data/android-benefit-reconciliation`

## Target Architecture

```text
Remote MMA API --> Verified MMA Enrichment --+
Manual Seed ---------------------------------+--> BenefitRepository --> Room --> BenefitViewModel --> BenefitUiState
Verified Non-MMA Seed -----------------------+                                              |
                                                                 +--> List / Detail
                                                                 +--> BenefitMapItem --> Naver Map

Android Location Provider --> LocationDataSource --> Location ViewModel/State --> Naver Map
```

### Data ownership

- Room의 `benefits` 테이블이 사용자에게 보이는 혜택의 유일한 기준이다.
- 동적 MMA 행은 검증된 enrichment를 메모리에서 적용한 뒤 `MMA_API` source transaction으로 Room을 교체한다.
- 검증된 bundled Seed의 여러 source는 전체 parsing·validation 후 하나의 Room transaction에서 함께 교체한다.
- 한 source의 refresh는 다른 source의 행을 삭제하지 않는다.
- 전체 parsing·validation 성공 전에는 기존 source 데이터를 교체하지 않는다.
- `ENDED` 데이터는 일반 사용자 Flow에서 제외하되 관리·검증 경로에서는 조회 가능해야 한다.

### UI state ownership

- Composable은 상태 표시와 이벤트 전달만 담당한다.
- ViewModel은 필터, 검색, 선택과 loading/error 상태를 소유한다.
- Repository는 remote/local 동기화와 entity/model mapping을 담당한다.
- Activity는 객체 조립과 Android permission entry point만 담당한다.

### Map boundary

지도는 기존 MILIMAP model 전체에 의존하지 않고 다음 목적의 작은 UI model을 사용한다.

```kotlin
data class BenefitMapItem(
    val id: String,
    val name: String,
    val category: String?,
    val latitude: Double,
    val longitude: Double,
)
```

- latitude 또는 longitude가 없는 혜택은 map item으로 변환하지 않는다.
- Marker 갱신 key는 `id`, `latitude`, `longitude`, `name`, `category` 변화를 포함한다.
- Marker click은 `BenefitDetailRoute(id)`로 연결한다.
- Naver key가 비어 있는 CI/로컬 환경에서도 compile과 목록 사용이 가능해야 한다.
- 지도 SDK가 없거나 key가 비어 있을 때는 기존 MILIMAP의 offline fallback 또는 명확한 빈 지도 안내를 제공한다.

### Location boundary

- Permission 요청과 결과는 UI/Activity Result 경계에서 처리한다.
- 위치 공급자 접근은 `LocationDataSource` 또는 동등한 작은 Android adapter로 분리한다.
- ViewModel은 Android `Activity`나 `LocationManager`를 보관하지 않는다.
- 권한 거부, 위치 미지원, null last-known location은 정상 상태로 표현하며 지도와 목록은 계속 사용할 수 있어야 한다.

## Core Baseline Import

첫 Core 단계는 `apps/android`만 MiliPercent tracked Android project로 교체한다. MILIMAP root의 `.github`, `data`, `docs`, `infra`, `packages`, `services`, `tools`는 유지한다.

유지할 MiliPercent 구성은 다음과 같다.

- Gradle wrapper 9.5.0과 Version Catalog
- AGP 9.3.1, compile/target SDK 37, min SDK 24
- Gradle runtime JDK 17, Java compile target 11
- Room database v2, schema v1/v2와 migration test
- API client, XML parser, 전체 pagination과 retry
- 서울 필터와 데이터 분석
- list/detail Navigation과 ViewModels
- Manual Seed loader와 12건 production Seed
- Debug 전용 `MANUAL_LOCAL` CRUD
- 기존 unit/instrumentation test

첫 Core 단계에서 namespace와 applicationId는 `com.example.milipercent`로 유지한다. 기존 MILIMAP의 Map dependency, location permission, SQLiteOpenHelper, AppController, SessionStore와 account/admin UI는 가져오지 않는다.

`apps/android/README.md`, `docs/current-status.md`와 필요한 로컬 설정 예시는 실제 새 기준선과 일치하도록 같은 PR에서 최소 수정한다.

## Package and Secrets

두 앱은 외부 배포 이력이 없으므로 update compatibility 제약은 없다. 그래도 원인 분리를 위해 전체 통합 기간에는 package와 applicationId를 `com.example.milipercent`로 유지한다. Naver Cloud Console에는 이 개발 package를 등록한다. 출시용 reverse-domain applicationId 선정과 package rename은 통합 범위에서 제외하고 별도 Issue로 처리한다.

실제 key 값은 Git에 넣지 않는다. 예시와 주입 구조만 유지한다.

```properties
MMA_API_URL=YOUR_MMA_API_URL
MMA_SERVICE_KEY=YOUR_MMA_SERVICE_KEY
NAVER_MAP_NCP_KEY_ID=YOUR_NCP_KEY_ID
```

- MMA 값은 BuildConfig로 전달한다.
- Naver Map client ID는 manifest placeholder로 전달한다.
- 빈 값에서도 CI compile이 가능해야 한다.
- 요청 URL이나 예외 로그에 service key를 출력하지 않는다.

## Data Reconciliation

현재 데이터 상태는 다음과 같다.

| Dataset | Rows | Coordinates |
| --- | ---: | ---: |
| MiliPercent Manual Seed | 12 | 0 |
| MILIMAP Seed | 484 | 339 |

두 Seed 사이 정규화한 업체명 또는 업체명+주소 일치는 0건이다. 그러나 MILIMAP의 484건에는 `MMA_API`, `LOCAL_GOV`, `PUBLIC_EVIDENCE`가 섞여 있으므로 동적 MMA 데이터와의 중복은 별도로 검사해야 한다.

### Contract before import

MILIMAP 필드를 손실 없이 표현하기 위해 import보다 먼저 Room contract를 확정한다.

- 기존 유지: `sourceType`, `sourceRowNumber`, `sourceUrl`, `lastVerifiedDate`, `verificationMethod`, `status`, `eligibleTarget`, `usageCondition`, `latitude`, `longitude`
- 추가: `category`, `sourceLabel`, `sourceReferencesJson`
- source type에 `LOCAL_GOV`, `PUBLIC_EVIDENCE`를 추가하고, `MMA_API`, `MANUAL_SEED`, `MANUAL_LOCAL`의 기존 의미는 유지한다.
- `benefitType`과 `category`는 의미가 다르므로 같은 컬럼으로 합치지 않는다.
- `sourceUrl`은 대표 출처 URL을 유지한다. 원본에 ` | `로 구분된 복수 URL이 있으면 각 URL을 검증한 뒤 JSON 배열로 `sourceReferencesJson`에 모두 보존한다.
- `category`, `sourceLabel`, `sourceReferencesJson` 추가는 database v2에서 v3로 올리고, explicit `MIGRATION_2_3`, exported schema 3과 migration test를 같은 PR에 포함한다.

### Reconciliation pipeline

1. 두 데이터셋을 공통 비교 레코드로 변환한다.
2. 업체명·주소의 앞뒤/연속 공백과 서울 표기를 정규화한다.
3. 공공 source ID가 있으면 최우선 식별자로 사용한다.
4. 이름+주소 exact match는 자동 후보로만 분류하고 provenance 충돌을 확인한다.
5. 이름만 같거나 주소만 비슷한 항목은 사람이 검토한다.
6. 체인점 가능성이 있는 동일 이름·다른 주소는 자동 병합하지 않는다.
7. MILIMAP의 `MMA_API` Seed 행은 별도 혜택으로 삽입하지 않는다. 동일한 실시간 MMA 행을 source ID 또는 검증된 업체명+주소로 찾았을 때 좌표·출처 보강 후보로만 사용한다.
8. `LOCAL_GOV`와 `PUBLIC_EVIDENCE` 행은 동적 MMA 데이터 및 MiliPercent Manual Seed와 충돌하지 않는다고 확인된 경우에만 bundled Seed 후보로 사용한다.
9. 출처·검증일·상태가 없는 값은 추측해 채우지 않는다.
10. pipeline은 `mma_benefit_enrichment.json`, `verified_benefits_seed.json`, 입력·출력 건수와 제외 사유를 담은 reconciliation report를 생성한다.
11. repository는 MMA refresh 때 stable benefit ID로 enrichment를 적용한 후 `MMA_API` 행을 교체한다. 매칭되지 않은 enrichment는 자동 적용하지 않고 report에 남긴다.
12. bundled Seed loader는 모든 항목을 먼저 검증한 뒤 `LOCAL_GOV`와 `PUBLIC_EVIDENCE` source를 하나의 Room transaction에서 교체한다.

지도 PR은 synthetic map item으로 상태와 click 경로를 검증할 수 있지만, 실제 Marker 동등성은 이 pipeline 이후 최종 gate에서 확인한다.

## Error Handling

- MMA 첫 페이지 또는 중간 페이지 실패: 기존 Room cache를 유지하고 저장된 목록과 갱신 실패 안내를 표시한다.
- 응답 total count 변경 또는 실제 수집 건수 불일치: 해당 refresh 전체를 실패 처리하며 부분 교체하지 않는다.
- Seed JSON parse/validation 실패: 기존 Seed source를 유지하고 로그에는 key나 전체 민감 데이터를 남기지 않는다.
- Map key 없음: 앱을 crash시키지 않고 목록 또는 fallback 지도를 제공한다.
- 좌표 없음: marker를 만들지 않고 나머지 혜택을 정상 표시한다.
- 위치 권한 거부/위치 없음: 현재 위치 overlay만 비활성화하고 지도·검색·상세를 유지한다.
- Room migration 실패: destructive migration을 사용하지 않고 migration test 실패로 merge를 차단한다.

## Phase and PR Design

### Phase 0: Governance and rollback

- Issue #4와 ADR 0001을 팀이 검토한다.
- ADR을 `Accepted`로 변경한다.
- 최신 dev backup tag를 원격에 보존한다.
- 두 source baseline에서 build/test 결과를 기록한다.

### Phase 1: Android Core baseline

- `apps/android`를 MiliPercent tracked files 기준으로 교체한다.
- monorepo root와 CI 위치를 유지한다.
- 문서와 설정 예시를 새 기준선에 맞춘다.
- 지도·위치·484건 데이터는 포함하지 않는다.

### Phase 2: Package and secret preparation

- 통합 applicationId `com.example.milipercent`와 Naver Cloud 개발 package 등록을 확인한다.
- Naver Map key 주입 구조를 준비한다.
- key 없는 CI와 개발 환경의 동작을 보장한다.

### Phase 3: Naver Map

- Map SDK, manifest metadata와 map component를 추가한다.
- Room UI state를 `BenefitMapItem`으로 변환한다.
- null coordinate filter, marker update와 marker click navigation을 검증한다.
- 기존 목록·검색·상세 동작을 유지한다.

### Phase 4: Current location

- location adapter와 UI state를 추가한다.
- permission, denied, unavailable과 success 경로를 검증한다.
- 현재 위치 overlay와 중심 이동을 제공한다.

### Phase 5: Data contract

- `category`, `sourceLabel`, `sourceReferencesJson`을 Room과 domain/detail model에 추가한다.
- `LOCAL_GOV`, `PUBLIC_EVIDENCE` source type과 bundled Seed의 다중-source transaction을 추가한다.
- database v3, `MIGRATION_2_3`, schema 3과 migration test를 함께 추가한다.

### Phase 6: Data reconciliation

- 동적 MMA 데이터와 MILIMAP Seed의 중복을 분석한다.
- 검증된 비-MMA Seed, MMA enrichment와 reconciliation report를 재현 가능한 pipeline으로 생성한다.
- MMA refresh가 enrichment 좌표·출처를 유지하고 미매칭 값을 추측 적용하지 않는지 검증한다.
- production Seed와 실제 marker를 검증한다.

### Phase 7: Final integration

- integration branch에 최신 dev를 반영한다.
- 전체 자동 검증과 emulator smoke test를 수행한다.
- 기능 동등성 체크리스트가 충족된 후 `dev` PR을 연다.

로그인, 즐겨찾기와 제품 관리자 기능은 최종 통합 이후 새 Issue에서 설계한다.

## Verification Gates

모든 Android 제품 코드 PR은 `apps/android`에서 다음을 통과해야 한다.

```powershell
.\gradlew.bat lintDebug testDebugUnitTest assembleDebug
```

Room·Navigation·UI 계측 변경은 가능한 환경에서 다음을 추가 실행한다.

```powershell
.\gradlew.bat connectedDebugAndroidTest
```

각 단계의 직접 테스트는 먼저 실패를 확인한 뒤 최소 구현으로 통과시킨다. 외부 API integration test는 key와 네트워크 의존성을 명시하고 일반 unit gate와 분리한다.

최종 수동 smoke checklist는 다음과 같다.

- key 없이 앱 시작 및 cached/Seed 목록 표시
- MMA key 사용 시 전체 page 갱신 및 실패 시 cache 유지
- 서울 자치구 필터, 한글 업체명·주소 검색
- 목록에서 상세 이동과 뒤로가기
- Naver key 사용 시 지도 표시
- 좌표 없는 데이터가 있어도 crash 없음
- 실제 좌표 Marker와 Marker click 상세 이동
- 위치 권한 허용·거부 흐름
- 현재 위치 overlay와 중심 이동
- Manual Seed와 MMA refresh 간 source 격리
- `ENDED` 데이터 일반 목록 제외

## Team Coordination

Core 기준선 PR은 한 명이 책임지고 다른 팀원은 같은 핵심 파일을 동시에 수정하지 않는다. Core가 통합 브랜치에 들어간 뒤 Map, Data, UI/Test를 분리할 수 있다.

다음 파일은 작업 소유자를 명시한다.

- `app/build.gradle.kts`
- `gradle/libs.versions.toml`
- `AndroidManifest.xml`
- `MainActivity.kt`
- Navigation graph
- `BenefitEntity`
- `BenefitDatabase`
- `BenefitRepository`
- `BenefitViewModel`

각 PR에는 실제 실행한 검증, 생략한 검증과 이유, source commit, 데이터 provenance, rollback 방법을 기록한다.

## Definition of Done

- 공식 Android 앱은 MILIMAP의 `apps/android` 하나다.
- Room이 유일한 DB이고 AppController/SQLiteOpenHelper 의존이 없다.
- 목록·검색·상세가 정상이다.
- 지도·Marker·Marker click 상세 이동이 정상이다.
- 위치 권한과 현재 위치가 정상이고 거부 상태도 안전하다.
- MMA 건수 차이와 Seed 중복 처리 기준이 문서화됐다.
- production 데이터의 출처·검증일·상태가 보존됐다.
- lint, unit test, debug assemble이 통과한다.
- 주요 Room/Navigation 계측 테스트 결과가 기록됐다.
- backup tag, 단계별 PR과 최종 `dev` PR 기록이 남아 있다.

계측 테스트는 초기에는 로컬 emulator에서 실행하고 결과를 PR에 기록한다. Emulator 기반 CI 추가는 통합 완료 후 별도 Issue로 평가한다.

## Pending Team Decisions

- Naver Cloud Console package 등록 담당자
- 통합 작업 책임자와 backup tag 생성·push 담당자
- 단계별 파일 소유자와 PR reviewer

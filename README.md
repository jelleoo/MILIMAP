# 군 장병 지역 혜택 탐색 플랫폼

현역 군인이 현재 위치나 방문 예정 지역을 기준으로 신뢰할 수 있는 군인 할인·우대 혜택을 발견하는 서비스입니다.

## 현재 구현 상태

기준: `dev` / 2026-09-10 P3 병합 이후

- Android 네이티브 MVP: 구현됨
- Room 기반 로컬 데이터 계층: 구현됨 (schema v4)
- Repository -> ViewModel -> UiState -> Compose 구조: 적용됨
- 병무청 나라사랑가게 OpenAPI 동기화: 구현됨
- 네이버 지도 SDK 및 현재 위치 탐색: 구현됨
- 로그인·세션·찜·관리자 수동 혜택 관리: 로컬 MVP 구현됨
- Android release seed: 249건
  - 정확 지도 핀: 111건
  - 좌표 미확정: 138건
  - bundled seed version: 7
- 최신 혜택 근거 부족으로 release에서 보류된 canonical 행: 247건
- 서버·iOS: 책임 영역만 정의했으며 구현 전

현재 활성 개발 목표와 팀별 작업 경계는 [`docs/current-work.md`](docs/current-work.md)를 먼저 확인하세요.
전체 데이터 검증 방향은 [`docs/superpowers/specs/2026-09-10-benefit-business-verification-pipeline-design.md`](docs/superpowers/specs/2026-09-10-benefit-business-verification-pipeline-design.md)를 따릅니다.

## 저장소 구조

```text
MILIMAP/
├─ apps/
│  └─ android/          # Kotlin + Jetpack Compose Android 앱
├─ services/
│  └─ api/              # 향후 서버 영역; 구현 방식은 아직 Pending
├─ packages/
│  └─ contracts/        # 향후 앱/서버 공용 계약
├─ data/
│  ├─ canonical/        # 검증 상태를 포함한 정본·보고서
│  └─ seed/             # 원천/초기 데이터 및 release artifact
├─ tools/
│  └─ data/             # 데이터 수집·정규화·검증 도구
├─ docs/                # 현재 상태, 설계, ADR, 협업 규칙
└─ infra/               # 향후 배포 영역
```

## Android 앱 실행

현재 코드 기준 주요 환경:

- JDK 17 (Gradle runtime)
- compileSdk 37
- targetSdk 37
- minSdk 24
- Java source/target 11

실행 순서:

1. 저장소를 복제합니다.
2. `dev`를 최신화합니다.
3. Android Studio에서 `apps/android` 폴더를 엽니다.
4. `apps/android/local.properties.example`을 `local.properties`로 복사합니다.
5. SDK 경로와 필요한 로컬 API 설정을 입력합니다.
6. Gradle Sync 후 `app` 구성을 실행합니다.

주요 `local.properties` 항목:

```properties
sdk.dir=C\:\\Users\\YOUR_NAME\\AppData\\Local\\Android\\Sdk
MMA_API_URL=YOUR_MMA_API_URL
MMA_SERVICE_KEY=YOUR_DATA_GO_KR_SERVICE_KEY
NAVER_MAP_NCP_KEY_ID=YOUR_NCP_KEY_ID
```

실제 키와 개인 설정 파일은 커밋하지 않습니다. 자세한 내용은 [`docs/local-development.md`](docs/local-development.md)와 [`apps/android/README.md`](apps/android/README.md)를 참고하세요.

## 검증 명령

Windows PowerShell:

```powershell
cd apps/android
.\gradlew.bat lintDebug testDebugUnitTest assembleDebug
```

macOS/Linux:

```bash
cd apps/android
./gradlew lintDebug testDebugUnitTest assembleDebug
```

Android instrumentation은 emulator/실기기가 있을 때 별도로 실행합니다. APK 또는 androidTest APK의 컴파일 성공과 실제 device test 실행은 구분해서 보고합니다.

## 팀 개발 규칙

- `main`은 검증된 안정 버전, `dev`는 기본 통합 개발 브랜치입니다.
- 구현은 최신 `dev`에서 Issue 전용 브랜치로 분기합니다.
- 한 브랜치 = 한 Issue = 한 목적을 기본으로 합니다.
- 같은 브랜치나 같은 작업 폴더를 여러 사람이 공유하지 않습니다.
- Issue에 수정 허용/금지 경로를 기록하고 공용 핵심 파일은 통합 담당자 한 명만 수정합니다.
- 교차 리뷰는 기본 필수 gate가 아닙니다. Issue에서 요구한 경우에만 필수입니다.
- 리뷰 여부와 별개로 Issue 범위, diff, 필수 테스트/CI, 데이터 검증 결과를 확인한 뒤 `dev`에 병합합니다.
- API 키, `local.properties`, 서명 키, 개인정보는 커밋하지 않습니다.
- 혜택/좌표 데이터 변경에는 출처, 확인일, 상태를 보존합니다.

세부 협업 규칙은 [`docs/team-workflow.md`](docs/team-workflow.md), Agent 규칙은 [`AGENTS.md`](AGENTS.md)를 따릅니다.

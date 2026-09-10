# MILIMAP Android

현재 Android 기준선은 `dev`의 Room / Repository / ViewModel / UiState / Compose 구조입니다.

## Current baseline

- namespace: `com.example.milipercent`
- applicationId: `com.example.militarybenefits`
- Room database: version 4
- migrations: `MIGRATION_1_2`, `MIGRATION_2_3`, `MIGRATION_3_4`
- compileSdk: 37
- targetSdk: 37
- minSdk: 24
- Gradle runtime: JDK 17
- Java source/target: 11
- bundled release seed version: 7

## Implemented MVP

현재 Android MVP에는 다음이 포함됩니다.

- Discover / Saved / Account / Admin / BenefitDetail navigation
- 이름/주소 검색 및 지역 탐색
- Naver Map 및 현재 위치
- Room 기반 혜택 저장 및 seed synchronization
- MMA API pagination/retry/cache/reconciliation
- 로그인·세션
- 사용자별 찜
- 관리자 수동 혜택 관리
- 좌표가 확정된 release candidate 지도 표시

2026-09-10 P3 병합 직후 release seed는 249건이며 정확 지도 핀 111건, 좌표 미확정 138건입니다. 좌표 미확정 항목에 좌표를 추정해서 넣지 않습니다.

## Open in Android Studio

Repository root가 아니라 `apps/android`를 엽니다.

Windows에서는 가능하면 저장소를 ASCII 문자만 포함한 경로(예: `C:\Users\PC\AndroidStudioProjects\MILIMAP`)에 둡니다. 과거 한글 경로에서 Gradle test worker class loading 문제가 재현된 적이 있습니다.

Gradle launcher/daemon runtime은 JDK 17 기준을 사용합니다. Java compile source/target은 11입니다.

## Local configuration

`local.properties.example`을 `local.properties`로 복사하고 개인 SDK/API 설정을 입력합니다. 실제 키는 commit하지 않습니다.

주요 항목:

```properties
sdk.dir=C\:\\Users\\YOUR_NAME\\AppData\\Local\\Android\\Sdk
MMA_API_URL=YOUR_MMA_API_URL
MMA_SERVICE_KEY=YOUR_DATA_GO_KR_SERVICE_KEY
NAVER_MAP_NCP_KEY_ID=YOUR_NCP_KEY_ID
```

`local.properties`에 넣은 값은 Git에는 포함되지 않지만 BuildConfig로 들어가는 값은 APK에서 추출될 수 있습니다. 공개 배포 전 API-key exposure는 별도 보안 Issue로 해결해야 합니다.

## Verification

기본 Android gate:

```powershell
.\gradlew.bat lintDebug testDebugUnitTest assembleDebug
```

androidTest 컴파일/생성까지 확인할 때:

```powershell
.\gradlew.bat compileDebugAndroidTestKotlin assembleDebugAndroidTest
```

Emulator 또는 실기기가 준비된 경우 실제 instrumentation:

```powershell
.\gradlew.bat connectedDebugAndroidTest
```

androidTest APK가 빌드되었다는 사실과 emulator/device에서 instrumentation이 실제 실행됐다는 사실은 구분해서 보고합니다.

## Architecture rules

- Room은 Android 로컬 Source of Truth입니다.
- Repository -> ViewModel -> UiState -> Compose 흐름을 유지합니다.
- 새 직접 SQLite/AppController 경로를 추가하지 않습니다.
- Room schema/migration, 인증 방식, API 계약, dependency 변경은 별도 승인 없이 진행하지 않습니다.
- seed version과 Room schema version은 서로 다른 개념입니다.

현재 팀 전체 작업과 Phase는 `../../docs/current-work.md`, 아키텍처 기준은 `../../docs/architecture.md`, 협업 규칙은 `../../docs/team-workflow.md`를 참고합니다.

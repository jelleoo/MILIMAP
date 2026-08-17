# 군 장병 지역 혜택 탐색 플랫폼

현역 군인이 현재 위치나 방문 예정 지역을 기준으로 신뢰할 수 있는 군인 할인·우대 혜택을 발견하는 서비스입니다. 

## 현재 구현 상태

- Android 네이티브 MVP: 구현됨
- 병무청 나라사랑가게 OpenAPI 동기화: 구현됨
- 네이버 지도 SDK 및 현재 위치 탐색: 구현됨
- 수도권 자체 조사 데이터 484건: 앱 내장
- 로그인·찜·관리자 CRUD: 기기 로컬 MVP로 구현됨
- 서버·iOS: 책임 영역만 정의했으며 아직 구현 전

## 저장소 구조

```text
military-benefit-platform/
├─ apps/
│  ├─ android/          # Kotlin + Jetpack Compose Android 앱
│  └─ ios/              # 향후 SwiftUI 앱
├─ services/
│  └─ api/              # 향후 인증·혜택·찜·관리자 서버
├─ packages/
│  └─ contracts/        # 앱과 서버가 공유할 API 계약·스키마
├─ data/
│  └─ seed/             # 검증 가능한 원천/초기 혜택 데이터
├─ tools/
│  └─ data/             # 데이터 변환·검증 도구
├─ docs/                # 아키텍처·로컬 실행·보안 문서
└─ infra/               # 향후 배포·클라우드 설정
```

이 구조에서는 제품별 실행 코드를 `apps`, 백엔드 실행 코드를 `services`, 여러 클라이언트가 공유하는 계약을 `packages`, 운영 데이터를 `data`에 분리합니다.

## Android 앱 실행

필요 환경:

- Android Studio 2026.1.1 이상 권장
- JDK 17
- Android SDK 35
- Android 8.0(API 26) 이상 기기 또는 에뮬레이터

실행 순서:

1. 저장소를 복제합니다.
2. Android Studio에서 `apps/android` 폴더를 엽니다.
3. `apps/android/local.properties.example`을 `local.properties`로 복사합니다.
4. 로컬 Android SDK 경로를 설정합니다.
5. 실제 네이버 지도와 병무청 API를 사용할 경우 본인의 API 키를 추가합니다.
6. Gradle Sync 후 `app` 구성을 실행합니다.

```properties
sdk.dir=C\:\\Users\\YOUR_NAME\\AppData\\Local\\Android\\Sdk
NAVER_MAP_NCP_KEY_ID=YOUR_NCP_KEY_ID
MMA_SERVICE_KEY=YOUR_DATA_GO_KR_SERVICE_KEY
```

API 키가 없어도 수도권 내장 데이터와 대체 지도로 앱을 실행할 수 있습니다. 자세한 내용은 [로컬 개발 가이드](docs/local-development.md)와 [Android 앱 문서](apps/android/README.md)를 참고하세요.

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

Pull Request에도 같은 Android 검사가 자동 실행되고, 성공한 디버그 APK가 GitHub Actions artifact로 저장됩니다.

## 팀 개발 규칙

- `main`에는 직접 푸시하지 않고 기능 브랜치와 Pull Request를 사용합니다.
- 예: `feature/android-map-search`, `feature/api-auth`, `fix/android-location`.
- API 키, `local.properties`, 서명 키는 절대 커밋하지 않습니다.
- 혜택 데이터 변경에는 출처 URL과 확인일을 함께 기록합니다.
- 아직 구현되지 않은 영역은 해당 디렉터리의 README에서 범위를 먼저 합의합니다.

자세한 규칙은 [CONTRIBUTING.md](CONTRIBUTING.md)를 참고하세요.

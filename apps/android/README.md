# MILIMAP Android

현재 Android Core 기준선은 MiliPercent의 Room/Repository/ViewModel 구현입니다.

## Source baseline

- MiliPercent source: `5e3d7331d59979e172a67921fb45acedde11da26`
- Package/applicationId: `com.example.milipercent`
- Room database: version 2

## Open in Android Studio

Repository root가 아니라 `apps/android`를 엽니다. JDK 17과 Android SDK 37을 사용합니다.

Windows에서는 저장소를 ASCII 문자만 포함한 경로(예: `C:\Users\PC\AndroidStudioProjects\MILIMAP`)에 두고 `apps/android`를 여세요. 현재 제어 저장소처럼 한글 경로에서는 AGP 설정을 우회해도 Gradle 단위 테스트 클래스 탐색이 실패할 수 있습니다.

CI는 launcher JDK 17을 사용하지만 `gradle/gradle-daemon-jvm.properties`는 daemon toolchainVersion=25를 지정합니다. Gradle이 필요하면 해당 daemon JDK를 자동으로 준비합니다.

## Local configuration

`local.properties.example`을 `local.properties`로 복사하고 개인 SDK 경로와 MMA 값을 설정합니다. 실제 key는 commit하지 않습니다. Key가 없으면 API 갱신은 실패할 수 있지만 기존 Room/Seed 목록은 유지됩니다.

## Verification

```powershell
.\gradlew.bat lintDebug testDebugUnitTest assembleDebug
```

Emulator가 준비된 경우:

```powershell
.\gradlew.bat connectedDebugAndroidTest
```

## Current phase

목록, 서울 25개 구 필터, 검색, 상세, MMA 동기화, Room cache, Manual Seed와 Debug 전용 MANUAL_LOCAL 관리가 포함됩니다. Naver Map, 현재 위치, 검증 데이터 통합, 로그인과 즐겨찾기는 후속 Issue에서 진행합니다.

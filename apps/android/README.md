# MILIMAP Android

현재 Android Core 기준선은 MiliPercent의 Room/Repository/ViewModel 구현입니다.

## Source baseline

- MiliPercent source: `5e3d7331d59979e172a67921fb45acedde11da26`
- Package/applicationId: `com.example.milipercent`
- Room database: version 2

## Open in Android Studio

Repository root가 아니라 `apps/android`를 엽니다. JDK 17과 Android SDK 37을 사용합니다.

Windows에서는 저장소를 ASCII 문자만 포함한 경로(예: `C:\Users\PC\AndroidStudioProjects\MILIMAP`)에 두고 `apps/android`를 여세요. 현재 제어 저장소처럼 한글 경로에서는 AGP 설정을 우회해도 Gradle 단위 테스트 클래스 탐색이 실패할 수 있습니다.

Gradle launcher와 daemon runtime은 모두 JDK 17 계약을 사용합니다. `gradle/gradle-daemon-jvm.properties`의 `toolchainVersion=17`을 유지하며, 로컬에 JDK 17이 없으면 Gradle이 지원 플랫폼용 JDK를 자동으로 준비할 수 있습니다. `.\gradlew.bat --version`의 `Daemon JVM` 항목에서 Java 17 기준을 확인할 수 있습니다.

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

MMA refresh는 값이 완전히 같은 API 행만 입력 순서대로 한 건으로 정리합니다. 정규화한 업체명과 주소가 같지만 내용이 다른 행은 stable ID 충돌로 간주해 Room 교체 전에 실패하며 기존 cache를 유지합니다. 교체 후 실제 source 건수가 예상 entity 수와 다르면 성공을 보고하지 않습니다. Manual Seed ID는 trim한 뒤 중복을 검증합니다.

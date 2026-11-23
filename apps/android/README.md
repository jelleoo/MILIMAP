# MILIMAP Android

## 실행 환경

- Android Studio
- Gradle 실행용 JDK 17
- Android SDK 37
- Android 7.0(API 24) 이상 기기 또는 에뮬레이터

## 앱 실행

1. Android Studio에서 저장소의 `apps/android` 폴더를 엽니다.
2. Gradle 동기화가 끝나면 상단에서 `app`과 실행할 기기를 선택합니다.
3. **Run**을 눌러 앱을 실행합니다.

앱에 포함된 혜택 데이터로 검색과 상세 화면을 둘러볼 수 있습니다. 네이버 지도와 병무청 나라사랑가게 동기화는 아래 설정을 추가하면 사용할 수 있습니다.

## API 설정

[설정 예시](local.properties.example)를 참고해 `local.properties`에 필요한 항목을 추가합니다.

| 설정 | 용도 |
| --- | --- |
| `NAVER_MAP_NCP_KEY_ID` | 네이버 클라우드 Maps Client ID |
| `MMA_API_URL` | 병무청 나라사랑가게 API 주소 |
| `MMA_SERVICE_KEY` | 공공데이터포털 서비스 키 |

네이버 클라우드의 **Mobile Dynamic Map** 설정에 앱 패키지 이름 `com.example.militarybenefits`를 등록합니다. 설정을 저장한 뒤 앱을 다시 실행하세요.

`local.properties`는 각자의 PC에 보관하세요. 실제 병무청 서비스 키를 넣은 빌드는 로컬 테스트에 사용하세요.

## 빌드 및 테스트

`apps/android` 폴더에서 실행합니다.

**Windows**

```powershell
.\gradlew.bat lintDebug testDebugUnitTest assembleDebug
```

**macOS / Linux**

```bash
./gradlew lintDebug testDebugUnitTest assembleDebug
```

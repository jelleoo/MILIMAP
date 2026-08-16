# 군 장병 지역 혜택 탐색 Android MVP

Kotlin과 Jetpack Compose로 만든 네이티브 Android 앱입니다. 앱을 열면 위치 권한을 요청하고 바로 현재 위치 중심의 지도와 군 장병 혜택 마커를 표시합니다. 서비스명은 아직 정하지 않아 임시 명칭 `군 혜택 지도`를 사용합니다.

## 구현 기능

- 네이버 지도 Android SDK 3.23.3 연동
- 첫 진입 즉시 현재 위치 탐색과 지도 마커 표시
- 병무청 나라사랑가게 OpenAPI XML 전체 페이지 동기화
- 자체 조사·지자체·병무청 데이터를 합친 수도권 484건 내장 DB
- 좌표가 있는 339건의 오프라인 마커와 API 실패 시 폴백 지도
- 지역 검색, 목적지 검색, 음식·카페·미용·숙박 필터
- 혜택 상세, 대상, 조건, 인증 방법, 출처, 최근 확인일, 상태 표시
- 로컬 회원가입·로그인, 사용자별 찜
- 관리자 혜택 등록·조회·수정·종료 처리

## API 키 설정

`local.properties.example`을 복사해 `local.properties`를 만들고 다음 값을 입력합니다.

```properties
sdk.dir=C\:\\Users\\YOUR_NAME\\AppData\\Local\\Android\\Sdk
NAVER_MAP_NCP_KEY_ID=YOUR_NCP_KEY_ID
MMA_SERVICE_KEY=YOUR_DATA_GO_KR_SERVICE_KEY
```

네이버 클라우드 Maps 애플리케이션에는 다음을 설정합니다.

- API: Dynamic Map
- Android 패키지명: `com.example.militarybenefits`
- 인증값: NCP Key ID

키가 비어 있어도 앱은 실행됩니다. 이 경우 네이버 지도 대신 수도권 좌표 폴백 지도를 사용하며, 나라사랑가게 API 대신 내장 DB를 보여줍니다.

## 빌드와 설치

```powershell
.\gradlew.bat assembleDebug
```

빌드 결과는 `app/build/outputs/apk/debug/app-debug.apk`입니다. Android Studio에서 프로젝트를 열고 실제 기기를 연결해 Run해도 됩니다.

## MVP 계정 정책

현재 로그인과 찜은 서버 없이 기기 로컬 DB에서 동작합니다. 첫 번째로 만든 계정에 해당 기기의 관리자 권한이 부여됩니다. 외부 사용자에게 배포하기 전에는 Firebase/Supabase 인증과 서버 DB로 바꾸고, 공공데이터 서비스 키도 서버 프록시 뒤로 옮기는 것이 안전합니다.

## 데이터 갱신

수도권 CSV를 앱 자산으로 다시 변환하려면 저장소 루트에서 다음 스크립트를 사용합니다.

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\data\convert-benefits.ps1 `
  -SourceCsv ".\data\seed\capital-area-military-benefits-20260815.csv" `
  -DestinationJson ".\apps\android\app\src\main\assets\benefits.seed.json"
```

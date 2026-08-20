# 로컬 개발 가이드

## 저장소 복제

```powershell
git clone https://github.com/jelleoo/MILIMAP.git
cd MILIMAP
```

## 작업 브랜치

제품과 문서 작업은 최신 `dev`에서 별도 브랜치를 만든 뒤 `dev` 대상 Pull Request로 반영합니다. `main`과 `dev`에는 직접 커밋하거나 푸시하지 않습니다.

```powershell
git switch dev
git pull --ff-only
git switch -c feature/issue-summary
```

문서, 데이터, 유지보수 작업에는 각각 `docs/`, `data/`, `chore/` 접두사를 사용합니다.

## Android

Android Studio의 `Open`에서 저장소 루트가 아니라 `apps/android`를 선택합니다.

Windows에서는 다음처럼 로컬 설정을 만듭니다.

```powershell
Copy-Item apps\android\local.properties.example apps\android\local.properties
```

`sdk.dir`을 자신의 Android SDK 경로로 바꿉니다. API 키 없이도 내장 데이터로 실행할 수 있습니다.

실기기 실행 전 확인:

- 개발자 옵션과 USB 또는 무선 디버깅 활성화
- `adb devices -l`에서 상태가 `device`인지 확인
- Android 8.0(API 26) 이상인지 확인

## 네이버 지도

네이버 클라우드 콘솔에서 Dynamic Map을 활성화하고 Android 패키지명 `com.example.militarybenefits`를 등록합니다. 발급받은 NCP Key ID는 개인의 `local.properties`에만 보관합니다.

## 병무청 API

공공데이터포털에서 병무청 나라사랑가게조회서비스 활용 신청 후 서비스 키를 발급받습니다. MVP에서는 Android 앱이 직접 호출하지만, 배포 전에는 `services/api`의 서버 프록시로 이전해야 합니다.

## 데이터 갱신

저장소 루트에서 실행합니다.

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\data\convert-benefits.ps1 `
  -SourceCsv ".\data\seed\capital-area-military-benefits-20260815.csv" `
  -DestinationJson ".\apps\android\app\src\main\assets\benefits.seed.json"
```

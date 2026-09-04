# 데이터 도구

`convert-benefits.ps1`은 수도권 CSV를 Android 앱의 초기 JSON 자산으로 변환합니다. 입력과 출력 경로를 반드시 인자로 받으므로 저장소 루트에서 다음처럼 실행합니다.

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\data\convert-benefits.ps1 `
  -SourceCsv ".\data\seed\capital-area-military-benefits-20260815.csv" `
  -DestinationJson ".\apps\android\app\src\main\assets\benefits.seed.json"
```

## 좌표 보강

`geocode-benefits.ps1`은 좌표가 비어 있는 행만 네이버 Geocoding API로 조회합니다. 다음 조건을 모두 만족하는 단일 결과만 자동 반영합니다.

- 입력 주소와 반환 주소의 시·도가 일치
- 반환된 도로명과 건물번호가 입력 주소에 포함
- 위도·경도가 대한민국 WGS84 범위 안에 있음

결과가 없거나 여러 개이거나 주소가 일치하지 않으면 좌표를 비워 둔 채 검토 보고서에 기록합니다. 검색 결과의 첫 장소를 임의로 사용하지 않습니다.

키는 Git에 올리지 않는 `apps/android/local.properties` 또는 환경 변수에 둡니다.

```properties
NAVER_MAP_NCP_KEY_ID=발급받은_Client_ID
NAVER_MAP_NCP_SECRET=발급받은_Client_Secret
```

먼저 API 호출 없는 사전 점검을 실행합니다.

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\data\geocode-benefits.ps1 `
  -SourceCsv ".\data\seed\capital-area-military-benefits-20260815.csv" `
  -DestinationCsv ".\data\reports\capital-area-benefits-geocoding-preview.csv" `
  -ReportCsv ".\data\reports\geocoding-preview-report.csv" `
  -SummaryJson ".\data\reports\geocoding-preview-summary.json" `
  -DryRun
```

실제 좌표 보강은 `-DryRun`만 제외해 별도 결과 파일로 생성합니다. 결과 CSV와 검토 보고서를 확인한 뒤에만 seed 원본과 Android JSON을 갱신합니다.

Android의 `benefits.seed.json`은 로컬 DB가 처음 만들어질 때만 들어갑니다. 이미 앱을 실행한 개발 기기에서 갱신된 seed를 확인하려면 앱 데이터 삭제 또는 앱 재설치가 필요합니다. 이 작업은 해당 기기의 로컬 계정, 찜과 관리자 수정 데이터도 함께 삭제하므로 필요한 데이터가 없는 개발 기기에서만 진행합니다.

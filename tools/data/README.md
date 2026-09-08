# 데이터 도구

`data/canonical/capital-area-military-benefits.csv`가 22열 정본입니다. `convert-benefits.ps1`은 정본 전체를 출시 전 중간 JSON으로 변환하고, `build-release-benefit-seed.ps1`은 최신 공식 혜택 후보만 골라 Android Room 초기 시드를 만듭니다. 중간 JSON은 Git에 저장하지 않고 임시 경로에 생성합니다.

기존 출시 시드에 있는 세부 지역명(예: 파주시의 읍·면·동)은 `-DistrictReferenceJson`으로 보존합니다. 새 정본 행에 기존 ID가 없으면 정본의 `시군구`를 사용합니다. 업소명과 주소로 계산한 안정 ID는 유지되므로, 같은 업소가 다음 시드에도 남아 있으면 사용자의 찜도 유지됩니다.

```powershell
$canonicalSource = Join-Path ([IO.Path]::GetTempPath()) 'milimap-canonical-source.json'

& .\tools\data\convert-benefits.ps1 `
  -SourceCsv '.\data\canonical\capital-area-military-benefits.csv' `
  -DestinationJson $canonicalSource `
  -DistrictReferenceJson '.\apps\android\app\src\main\assets\benefits.seed.json'
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
  -SourceCsv ".\data\canonical\capital-area-military-benefits.csv" `
  -DestinationCsv ".\data\reports\capital-area-benefits-geocoding-preview.csv" `
  -ReportCsv ".\data\reports\geocoding-preview-report.csv" `
  -SummaryJson ".\data\reports\geocoding-preview-summary.json" `
  -DryRun
```

실제 좌표 보강은 `-DryRun`만 제외해 별도 결과 파일로 생성합니다. 결과 CSV와 검토 보고서를 확인한 뒤에만 seed 원본과 Android JSON을 갱신합니다.

Android의 `benefits.seed.json`은 로컬 DB가 처음 만들어질 때만 들어갑니다. 이미 앱을 실행한 개발 기기에서 갱신된 seed를 확인하려면 앱 데이터 삭제 또는 앱 재설치가 필요합니다. 이 작업은 해당 기기의 로컬 계정, 찜과 관리자 수정 데이터도 함께 삭제하므로 필요한 데이터가 없는 개발 기기에서만 진행합니다.

## 정본 POI 좌표 감사

`verify-canonical-benefit-poi.ps1`은 정본 CSV를 변경하지 않고, 업소명과 주소가 모두 일치하는 NAVER API HUB 지역 검색 POI만 좌표 제안 보고서에 기록합니다. 먼저 `업소명 + 전체 주소`로 검색하고 결과가 없을 때만 쉼표 앞 도로명·건물번호로 한 번 더 검색합니다. 보조 검색을 사용해도 최종 후보는 원본의 전체 상호·전체 주소와 단일 일치해야 합니다. API HUB의 `mapx`와 `mapy`는 WGS84 경도·위도로 변환하기 전에 각각 10,000,000으로 나눕니다. 단일 상호·주소 일치, 숫자 좌표, 대한민국 좌표 범위를 모두 만족하지 않으면 좌표를 비워 둡니다.

이 도구는 `openapi.naver.com` 검색 API나 NCP Geocoding API를 호출하지 않습니다. API HUB 지역 검색에 인증된 별도 키를 `apps/android/local.properties` 또는 같은 이름의 환경 변수에 둡니다.

```properties
NAVER_API_HUB_CLIENT_ID=API_HUB_지역검색_Client_ID
NAVER_API_HUB_CLIENT_SECRET=API_HUB_지역검색_Client_Secret
```

`NAVER_MAP_NCP_KEY_ID`와 `NAVER_MAP_NCP_SECRET`은 지도 SDK·기존 지오코딩 도구의 설정이므로, API HUB 지역 검색 인증이 확인되지 않은 한 이 두 값을 대신 사용하지 않습니다.

먼저 기존 좌표 보유 행 5건만 스모크 감사합니다.

```powershell
pwsh -NoProfile -File .\tools\data\verify-canonical-benefit-poi.ps1 `
  -InputCsv '.\data\canonical\capital-area-military-benefits.csv' `
  -OutputCsv .\data\canonical\reports\poi-coordinate-smoke-api-hub.csv `
  -SummaryJson .\data\canonical\reports\poi-coordinate-smoke-api-hub-summary.json `
  -LocalPropertiesPath 'C:\Users\PC\AndroidStudioProjects\MILIMAP\apps\android\local.properties' `
  -OnlyExistingCoordinates -MaxRows 5
```

긴 감사는 `-StartRow`와 `-MaxRows`로 분할 실행할 수 있으며, `-StartRow`는 보고서의 원본 CSV 행 번호도 함께 보존합니다. 스모크 보고서를 검토한 뒤에만 전체 감사를 실행합니다. 이 단계의 결과는 정본 CSV나 Android Room 시드를 자동 수정하지 않습니다.

감사에서 `확인 후보`로 나온 행은 `export-poi-coordinate-review-candidates.ps1`로 별도 검토 목록을 만듭니다. 이 목록은 정본 CSV 행 번호와 감사 제안 좌표를 함께 보여 주지만, 기본값이 `검토결정=미검토`, `정본반영여부=아니오`이므로 자동 반영 경로로 사용할 수 없습니다.

```powershell
pwsh -NoProfile -File .\tools\data\export-poi-coordinate-review-candidates.ps1 `
  -CanonicalCsv '.\data\canonical\capital-area-military-benefits.csv' `
  -AuditReportCsv .\data\canonical\reports\poi-coordinate-audit-api-hub-20260906.csv `
  -OutputCsv .\data\canonical\reports\poi-coordinate-review-candidates-20260906.csv
```

## 현재 공식 혜택 근거가 있는 좌표 검증 우선순위

`build-coordinate-verification-priority-queue.ps1`은 최신 공식 혜택 목록과 일치 후보인 업소만 골라 좌표 재검증 순서를 만듭니다. `P1`은 API HUB에서 상호·주소가 일치한 후보, `P2`는 상호만 일치해 지도 화면 대조가 필요한 후보, `P3`는 새 POI 확인이 필요한 후보입니다. 이 도구도 기본값을 `검토결정=미검토`, `정본반영여부=아니오`로 남기며 정본을 수정하지 않습니다.

```powershell
$benefitReports = @(
  '.\data\canonical\reports\ddc-benefit-comparison-20260906.csv',
  '.\data\canonical\reports\yangju-benefit-comparison-20260906.csv'
)

& .\tools\data\build-coordinate-verification-priority-queue.ps1 `
  -CanonicalCsv '.\data\canonical\capital-area-military-benefits.csv' `
  -CoordinateAuditCsv .\data\canonical\reports\poi-coordinate-audit-api-hub-20260906.csv `
  -BenefitReviewCsv $benefitReports `
  -OutputCsv .\data\canonical\reports\coordinate-verification-priority-queue-20260906.csv `
  -SummaryJson .\data\canonical\reports\coordinate-verification-priority-queue-20260906-summary.json
```

`P2` 행을 다시 감사할 때는 단일 상호 일치 POI의 주소만 참고 정보로 기록합니다. 이때 `제안위도`, `제안경도`, `좌표출처URL`은 빈 값으로 유지해야 하며, 참고 POI가 있다는 이유만으로 좌표를 제안하거나 승인해서는 안 됩니다.

P2의 수동 대조에는 `export-coordinate-map-screen-review-queue.ps1`을 사용합니다. 원본 주소, 참고 POI 주소, 실제 API HUB 조회어에 대한 세 네이버 지도 검색 URL을 만들며, `지도대조결과=미검토`, `검토결정=미검토`, `정본반영여부=아니오`, 좌표 공란으로 시작합니다. 원본 또는 참고 주소 검색에서 결과가 없더라도 API HUB의 도로명·건물번호 보조 조회어로 POI가 열릴 수 있으므로, 세 경로의 화면 결과를 각각 확인해야 합니다. API 응답의 강조 태그는 지도 검색어와 보고서 상호에서 제거합니다.

```powershell
pwsh -NoProfile -File .\tools\data\export-coordinate-map-screen-review-queue.ps1 `
  -PriorityQueueCsv .\data\canonical\reports\coordinate-verification-priority-queue-20260906-v3.csv `
  -OutputCsv .\data\canonical\reports\coordinate-map-screen-review-queue-p2-20260906-v3.csv
```

`poi-coordinate-map-screen-verification-p1-20260906.csv`는 P1 7건을 실제 네이버 지도 POI 화면에서 대조한 기록이다. 출시 준비도는 사람의 별도 승인 필드가 아니라 정본 `확인 완료`와 단일 `감사판정=확인 후보`를 함께 확인해 지도 핀 표시 여부를 정한다.

`export-coordinate-map-screen-review-queue.ps1`의 기본 대상은 `P2`다. API 참고 POI가 없는 `P3` 미확인군을 별도 대기열로 만들 때는 `-QueuePriority P3`를 명시한다. 이 경우에도 참고 POI와 좌표 제안은 공란이며, `지도대조결과=미검토`, `검토결정=미검토`, `정본반영여부=아니오`로 시작한다.

```powershell
pwsh -NoProfile -File .\tools\data\export-coordinate-map-screen-review-queue.ps1 `
  -PriorityQueueCsv .\data\canonical\reports\coordinate-verification-priority-queue-20260906-v3.csv `
  -OutputCsv .\data\canonical\reports\coordinate-map-screen-review-queue-p3-20260907.csv `
  -QueuePriority P3
```

## 혜택 최신 근거 재확인

`export-benefit-verification-queue.ps1`은 정본에서 `혜택상태=이용 가능`인 행을 전수 검토 큐로 내보냅니다. 이 도구는 기존 혜택 정보·상태를 변경하지 않으며, 각 행의 기본값을 `검증결과=미검토`, `정본반영여부=아니오`로 설정합니다. 검토자는 현재 공식 근거의 링크와 확인일을 입력한 뒤에만 별도 정본 반영안을 만들 수 있습니다.

```powershell
pwsh -NoProfile -File .\tools\data\export-benefit-verification-queue.ps1 `
  -CanonicalCsv '.\data\canonical\capital-area-military-benefits.csv' `
  -OutputCsv .\data\canonical\reports\benefit-verification-queue-20260906.csv
```

### 동두천시 공식 목록 대조

`compare-ddc-benefits.ps1`은 동두천시 공식 목록을 읽어 해당 출처를 사용하는 정본 행의 상호·주소·전화·할인을 비교합니다. 결과의 `현재 공식 목록 일치 후보`는 최신 공식 근거와의 기계적 일치를 뜻할 뿐, 정본 상태나 상세정보를 자동으로 바꾸지 않습니다. 주소·전화·할인 차이, 복수 후보와 목록 미발견은 모두 검토 대상으로 남습니다.

```powershell
pwsh -NoProfile -File .\tools\data\compare-ddc-benefits.ps1 `
  -CanonicalCsv '.\data\canonical\capital-area-military-benefits.csv' `
  -OutputCsv .\data\canonical\reports\ddc-benefit-comparison-20260906.csv `
  -SummaryJson .\data\canonical\reports\ddc-benefit-comparison-20260906-summary.json
```

### 파주시 공식 목록 대조

`compare-paju-benefits.ps1`은 음식점·숙박·미용업 분류의 파주시 공식 목록과 정본 행을 대조합니다. 공식 표에는 상호·주소·전화번호는 있지만 개별 할인 조건이 없으므로, 상호·주소·전화가 일치해도 `공식 참여업소 일치 후보`로만 기록하고 할인 정보는 자동 확정하지 않습니다.

```powershell
pwsh -NoProfile -File .\tools\data\compare-paju-benefits.ps1 `
  -CanonicalCsv '.\data\canonical\capital-area-military-benefits.csv' `
  -OutputCsv .\data\canonical\reports\paju-benefit-comparison-20260906.csv `
  -SummaryJson .\data\canonical\reports\paju-benefit-comparison-20260906-summary.json
```

### 양주시 공식 목록 대조

`compare-yangju-benefits.ps1`은 2026-07-30 양주시 위생과 공지의 2026-07-24 기준 XLSX 목록과 기존 양주 정본 행을 비교합니다. 상호·주소·전화가 일치하면 `현재 공식 목록 일치 후보`로 기록합니다. 상호만 달라져도 주소·전화가 같으면 `상호 변경 가능성`으로 보류하고, 전화 변경·목록 미발견도 자동 변경하지 않습니다. 공식 목록을 화면 대조해 전사한 입력 CSV는 출처 원문을 보존하는 비교용 파일이며 정본이 아닙니다.

```powershell
pwsh -NoProfile -File .\tools\data\compare-yangju-benefits.ps1 `
  -CanonicalCsv '.\data\canonical\capital-area-military-benefits.csv' `
  -OfficialCsv .\data\canonical\reports\yangju-official-food-list-20260724.csv `
  -OutputCsv .\data\canonical\reports\yangju-benefit-comparison-20260906.csv `
  -SummaryJson .\data\canonical\reports\yangju-benefit-comparison-20260906-summary.json
```

## 출시 준비도 안전 게이트

`build-release-readiness-report.ps1`은 정본·POI 좌표 검토 목록·공식 혜택 출시 후보 목록을 읽어 출시 준비도를 표시합니다. 정본 `확인 완료`와 단일 `감사판정=확인 후보`가 함께 있는 행만 지도 핀을 표시합니다. 그 외 모든 출시 후보는 `위치 확인 필요`로 목록·상세에 노출하고 지도 핀에는 표시하지 않습니다. `혜택근거상태=공식 최신 근거 확인`인 행은 사람 승인 없이 출시 후보가 됩니다. 이 도구는 정본 CSV, 좌표, Room 시드, 앱 UI를 수정하지 않습니다.

```powershell
$benefitReports = @(
  '.\data\canonical\reports\ddc-benefit-comparison-20260906.csv',
  '.\data\canonical\reports\yangju-benefit-comparison-20260906.csv'
)

& .\tools\data\build-release-readiness-report.ps1 `
  -CanonicalCsv '.\data\canonical\capital-area-military-benefits.csv' `
  -CoordinateReviewCsv .\data\canonical\reports\poi-coordinate-review-candidates-20260906.csv `
  -BenefitReviewCsv $benefitReports `
  -OutputCsv .\data\canonical\reports\release-readiness-20260906.csv `
  -SummaryJson .\data\canonical\reports\release-readiness-20260906-summary.json
```

`build-official-benefit-release-candidates.ps1`은 동두천·파주·양주 비교 결과에서 최신 공식 근거가 충분한 업소를 자동으로 후보화합니다. 동두천·양주는 공식 개별 할인 문구를, 파주는 공식 참여 목록과 공통 정책에 따른 공통 문구를 내보냅니다. 이 후보 목록을 출시 준비도와 출시 시드의 유일한 혜택 근거 입력으로 사용합니다.

## Android 출시 시드 좌표 정책

`apply-canonical-coordinate-policy.ps1`은 전체 감사용 시드에서 정본 `재확인 필요`와 `미확인` 행의 위도·경도를 함께 비웁니다. 실제 출시 시드는 아래 `build-release-benefit-seed.ps1`으로 만듭니다. 이 변환기는 최신 공식 혜택 후보만 포함하고, 정본 `확인 완료`와 엄격 POI 감사가 함께 충족된 좌표만 유지합니다.

```powershell
pwsh -NoProfile -File .\tools\data\apply-canonical-coordinate-policy.ps1 `
  -CanonicalCsv '.\data\canonical\capital-area-military-benefits.csv' `
  -SourceJson '.\apps\android\app\src\main\assets\benefits.seed.json' `
  -DestinationJson '.\apps\android\app\src\main\assets\benefits.seed.json'
```

변환기는 대응 정본이 없거나 좌표가 한쪽만 있는 시드를 오류로 중단합니다. Android는 좌표가 모두 비어 있는 행을 목록·상세에 `위치 확인 필요`로 노출하고 지도 핀에서 제외합니다. 내장 시드 버전을 올려 기존 설치 앱에도 이 좌표 정책이 다시 적용되도록 합니다.

### 공식 혜택 출시 후보와 Android 시드 생성

```powershell
& .\tools\data\build-official-benefit-release-candidates.ps1 `
  -CanonicalCsv '.\data\canonical\capital-area-military-benefits.csv' `
  -DdcComparisonCsv .\data\canonical\reports\ddc-benefit-comparison-20260906.csv `
  -PajuComparisonCsv .\data\canonical\reports\paju-benefit-comparison-20260906.csv `
  -YangjuComparisonCsv .\data\canonical\reports\yangju-benefit-comparison-20260906.csv `
  -OutputCsv .\data\canonical\reports\official-benefit-release-candidates-20260906.csv

& .\tools\data\build-release-benefit-seed.ps1 `
  -CanonicalCsv '.\data\canonical\capital-area-military-benefits.csv' `
  -CandidateCsv .\data\canonical\reports\official-benefit-release-candidates-20260906.csv `
  -CoordinateReviewCsv .\data\canonical\reports\poi-coordinate-review-candidates-20260906.csv `
  -SourceJson $canonicalSource `
  -DestinationJson .\apps\android\app\src\main\assets\benefits.seed.json
```

`test-release-artifact-pipeline.ps1`은 정본 496건 → 중간 시드 → 공식 출시 후보 249건 → Android 출시 시드 249건을 재생성하고, 결과가 커밋된 `benefits.seed.json`과 같은지 검사합니다. GitHub Actions도 `data/**`, `tools/data/**`, Android 자산 변경 시 이 검사를 실행합니다.

## 나라사랑가게 좌표 캐시

병무청 나라사랑가게 API 응답에는 위도·경도가 없습니다. `build-mma-coordinate-cache.ps1`은 다음 순서로 Android용 좌표 캐시를 만듭니다.

1. API의 `totalCount`를 읽고 전체 페이지를 수집
2. 주소가 서울특별시·경기도·인천광역시로 시작하는 항목만 선택
3. 업체명·주소가 기존 검증 seed와 정확히 일치하면 좌표 재사용
4. 나머지는 네이버 Geocoding API에서 시·도, 도로명과 건물번호가 일치하는 단일 결과만 채택
5. 검증 실패 항목은 캐시에서 제외하고 CSV 보고서로 분리

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\data\build-mma-coordinate-cache.ps1
```

입력 키는 `apps/android/local.properties` 또는 같은 이름의 환경 변수에서 읽습니다.

```properties
MMA_SERVICE_KEY=공공데이터포털_서비스키
NAVER_MAP_NCP_KEY_ID=네이버_지도_Client_ID
NAVER_MAP_NCP_SECRET=네이버_지도_Client_Secret
```

`NAVER_MAP_NCP_SECRET`은 이 로컬 생성 과정에서만 사용하며 앱과 Git에는 포함하지 않습니다. `mma.coordinates.seed.json`은 주소 지오코딩 검증 결과를 보존하는 감사용 캐시입니다. 새 엄격 기준인 “지도 POI 상호와 주소 모두 일치”를 통과한 값이 아니므로, 현재 Android 지도 핀이나 API 동기화에는 연결하지 않습니다. 이 캐시의 좌표를 사용하려면 별도 POI 감사와 정본 반영이 먼저 필요합니다.

API 호출 없이 수집·필터·기존 좌표 재사용 범위만 확인하려면 `-DryRun`을 사용하고 출력 경로를 임시 파일로 지정합니다.

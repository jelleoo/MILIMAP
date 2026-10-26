# 데이터 도구

`data/canonical/capital-area-military-benefits.csv`가 `businessId`를 포함한 23열 정본입니다. `convert-benefits.ps1`은 정본 전체를 출시 전 중간 JSON으로 변환하고, `build-release-benefit-seed.ps1`은 최신 공식 혜택 후보만 골라 Android Room 초기 시드를 만듭니다. 중간 JSON은 Git에 저장하지 않고 임시 경로에 생성합니다.

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

Android는 내장 seed 버전이 올라갈 때만 `benefits.seed.json`을 Room에 다시 동기화합니다. 번들 행은 갱신·정리하되 사용자 찜과 원격·수동 데이터는 보존합니다. 새 seed를 반영하는 데이터 변경에서는 `BUNDLED_SEED_VERSION`도 함께 올리고, 개발 기기에서 기존 데이터가 유지되는지 동기화 테스트로 확인합니다.

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
  '.\data\canonical\reports\ddc-benefit-comparison-20260908.csv',
  '.\data\canonical\reports\paju-benefit-comparison-20260906.csv',
  '.\data\canonical\reports\yangju-benefit-comparison-20260906.csv'
)

& .\tools\data\build-coordinate-verification-priority-queue.ps1 `
  -CanonicalCsv '.\data\canonical\capital-area-military-benefits.csv' `
  -CoordinateAuditCsv .\data\canonical\reports\poi-coordinate-audit-api-hub-20260906.csv `
  -BenefitReviewCsv $benefitReports `
  -OutputCsv .\data\canonical\reports\coordinate-verification-priority-queue-20260908.csv `
  -SummaryJson .\data\canonical\reports\coordinate-verification-priority-queue-20260908-summary.json
```

`P2` 행을 다시 감사할 때는 단일 상호 일치 POI의 주소만 참고 정보로 기록합니다. 이때 `제안위도`, `제안경도`, `좌표출처URL`은 빈 값으로 유지해야 하며, 참고 POI가 있다는 이유만으로 좌표를 제안하거나 승인해서는 안 됩니다.

P2의 수동 대조에는 `export-coordinate-map-screen-review-queue.ps1`을 사용합니다. 원본 주소, 참고 POI 주소, 실제 API HUB 조회어에 대한 세 네이버 지도 검색 URL을 만들며, `지도대조결과=미검토`, `검토결정=미검토`, `정본반영여부=아니오`, 좌표 공란으로 시작합니다. 원본 또는 참고 주소 검색에서 결과가 없더라도 API HUB의 도로명·건물번호 보조 조회어로 POI가 열릴 수 있으므로, 세 경로의 화면 결과를 각각 확인해야 합니다. API 응답의 강조 태그는 지도 검색어와 보고서 상호에서 제거합니다.

```powershell
pwsh -NoProfile -File .\tools\data\export-coordinate-map-screen-review-queue.ps1 `
  -PriorityQueueCsv .\data\canonical\reports\coordinate-verification-priority-queue-20260908.csv `
  -OutputCsv .\data\canonical\reports\coordinate-map-screen-review-queue-p2-20260908.csv
```

`poi-coordinate-map-screen-verification-p1-20260906.csv`는 초기 P1 7건을 실제 네이버 지도 POI 화면에서 대조한 기록이다. 이후 같은 기준의 수동 대조 결과는 날짜별 `poi-coordinate-review-candidates-*.csv`에 추가한다. 출시 준비도는 사람의 별도 승인 필드가 아니라 정본 `확인 완료`와 단일 `감사판정=확인 후보`를 함께 확인해 지도 핀 표시 여부를 정한다.

`export-coordinate-map-screen-review-queue.ps1`의 기본 대상은 `P2`다. API 참고 POI가 없는 `P3` 미확인군을 별도 대기열로 만들 때는 `-QueuePriority P3`를 명시한다. 이 경우에도 참고 POI와 좌표 제안은 공란이며, `지도대조결과=미검토`, `검토결정=미검토`, `정본반영여부=아니오`로 시작한다.

```powershell
pwsh -NoProfile -File .\tools\data\export-coordinate-map-screen-review-queue.ps1 `
  -PriorityQueueCsv .\data\canonical\reports\coordinate-verification-priority-queue-20260908.csv `
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
  -OutputCsv .\data\canonical\reports\ddc-benefit-comparison-20260908.csv `
  -SummaryJson .\data\canonical\reports\ddc-benefit-comparison-20260908-summary.json
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
  '.\data\canonical\reports\ddc-benefit-comparison-20260908.csv',
  '.\data\canonical\reports\paju-benefit-comparison-20260906.csv',
  '.\data\canonical\reports\yangju-benefit-comparison-20260906.csv'
)

& .\tools\data\build-release-readiness-report.ps1 `
  -CanonicalCsv '.\data\canonical\capital-area-military-benefits.csv' `
  -CoordinateReviewCsv .\data\canonical\reports\poi-coordinate-review-candidates-20260908.csv `
  -BenefitReviewCsv $benefitReports `
  -OutputCsv .\data\canonical\reports\release-readiness-20260908.csv `
  -SummaryJson .\data\canonical\reports\release-readiness-20260908-summary.json
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
  -DdcComparisonCsv .\data\canonical\reports\ddc-benefit-comparison-20260908.csv `
  -PajuComparisonCsv .\data\canonical\reports\paju-benefit-comparison-20260906.csv `
  -YangjuComparisonCsv .\data\canonical\reports\yangju-benefit-comparison-20260906.csv `
  -OutputCsv .\data\canonical\reports\official-benefit-release-candidates-20260908.csv

& .\tools\data\build-release-benefit-seed.ps1 `
  -CanonicalCsv '.\data\canonical\capital-area-military-benefits.csv' `
  -CandidateCsv .\data\canonical\reports\official-benefit-release-candidates-20260908.csv `
  -CoordinateReviewCsv .\data\canonical\reports\poi-coordinate-review-candidates-20260908.csv `
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


## Phase 2 Benefit Verification Core / Shadow Mode

Phase 2 provider-neutral Core는 기존 canonical 혜택 행을 자동 수정하지 않고, 현재 공식 근거를 다시 관측해 사람이 검토할 Shadow 결과를 만든다.

```text
Canonical benefit row
        ↓
Business Identity / Normalization
        ↓
Existing official source first
        ↓
Fetch → Officiality Qualification → Business Binding
        ↓
Evidence Extraction → Evidence Validation
        ↓
Claim Comparison
        ↓
BenefitState / ReviewClass
        ↓
BenefitVerificationResult + row report + summary + evidence diagnostics
```

핵심 안전 규칙:

- 기존 canonical 공식 URL을 먼저 시도하고, 증거가 부족할 때만 injectable discovery boundary를 사용한다.
- fetch/search/parser/extractor 실패는 혜택 종료 근거가 아니다.
- `ENDED`는 strong official binding과 explicit validated ending evidence가 있을 때만 허용한다.
- unresolved source conflict는 `NEEDS_VERIFICATION + RED`다.
- `ProductionAction`은 항상 `NONE`이고 GREEN도 최종 사람 승인이 필요하다.
- `data/canonical`, `data/seed`, `apps` 아래로 Shadow 결과를 export할 수 없다.
- general web-search provider, LLM provider, PDF/HWP/OCR text extractor는 현재 Core에 내장하지 않고 injectable boundary로만 둔다. XLSX는 raw-byte/sheet/row/cell provenance가 있는 scoped path만 지원하며, generic attachment fallback은 없다.

주요 구현:

- `lib/benefit-verification-contracts.ps1`: Phase 2 in-memory contract
- `lib/benefit-source/*`: existing-source discovery/fetch, officiality qualification, business binding
- `lib/benefit-evidence/*`: deterministic scoped HTML, MMA JSONP, and XLSX extraction plus evidence validation
- `lib/benefit-verification/*`: claim comparison, deterministic BenefitState/ReviewClass
- `invoke-phase2-benefit-shadow-mode.ps1`: orchestration, metrics, diagnostics, protected export
- `testdata/phase2-benefit-golden.psd1`: source-cited historical provenance와 synthetic safety fixture를 분리한 Golden data

### Current scoped source families

The current scoped path supports HTML table rows, MMA JSONP list-to-detail evidence, XLSX rows with raw-byte-bound sheet/row/cell provenance, and the bounded HWPX/PDF subsets below. It does not relabel JSONP as HTML; legacy HWP/OCR, SNS/blog and discovery signals are not strong verification evidence. `ProductionAction` remains `NONE` for every family.

P4-0 added byte-first PDF/HWPX recognition and original-byte snapshots, plus validated synthetic `PDF_ROW` / `HWPX_ROW` provenance indexes and locator slices. Recognition itself is not parser support; bounded native parsing was added subsequently below. OCR and PDF/HWPX POST_FETCH reuse remain unsupported. See the [P4-0 handover](../../docs/handover/2026-09-29-phase4-p4-0-document-adapter-foundation.md).

P4-1 adds native bounded HWPX ZIP/XML parsing for tables with one explicit semantic header and unmerged mapped cells. It reuses `Get-BenefitScopedHeaderMap`, `BenefitDocumentValidationIndex`, and the existing scoped pipeline. `HWPX_ROW` evidence is byte-derived with exact section/table/row/cell paths; claims use `SCOPED_HWPX_CELL`. A shared run-context fetches/parses once and reuses the same document validation index. Ambiguous headers, unsafe XML, merged semantic cells and unsupported inline/nested-table content fail closed; PARTIAL observations cannot produce LOCATED/NOT_FOUND. Paragraph-only evidence, multi-row header inference, positional guessing, cross-table stitching and legacy HWP are not supported. HWPX incremental capability remains `NONE`. Live official HWPX validation is `NOT_OBSERVED`; synthetic tests are not real benefit truth. See the [P4-1 handover](../../docs/handover/2026-10-05-phase4-p4-1-hwpx-generic-adapter.md).

P4-2B adds an isolated .NET 8 helper with exact locked **PdfPig 0.1.16 (Apache-2.0)**, not a PowerShell `Add-Type` dependency. The helper produces primitive native glyph/vector JSON; a fixed `PDF_GRID_CONFIG_V1` proves page-local ruled cells before `PDF_ROW` evidence can enter the existing locator/binding/extraction/validation path (`SCOPED_PDF_CELL`). No OCR, borderless inference, merged semantic-cell reconstruction, cross-page stitching or old `PdfTextExtractor` fallback is used. Shared run-context fetch/native parse/document-index build occurs once; defined incomplete outcomes are cached too. Repeated strict byte validation remains and is not claimed to be zero-rehash. PDF incremental reuse remains `NONE`.

Runtime defaults: source 10 MiB, 32 pages, 20,000 letters/page (100,000 total), 2,048 paths/page, 16,384 total path commands, 512 grid segments/page, 16 MiB projection, 64 KiB stderr and 10-second child deadline. PowerShell geometry also has a shared document budget of 500,000 glyph/cell checks, 100,000 overlap comparisons, 128 glyphs/cell and a cooperative 10-second deadline. Limits are checked before open or as counts become available, not a portable hard-memory sandbox. Identity-less mapped evidence or uncovered exact native identity headers make the observation PARTIAL even alongside safe tables; rejection hints never create evidence or change proven table ordinals. PARTIAL/FAILED/UNSUPPORTED never yields LOCATED/NOT_FOUND or validated claims. See [helper build instructions](pdf-native/README.md) and [P4-2B handover](../../docs/handover/2026-10-05-phase4-p4-2b-pdf-native-adapter.md). Current Suwon live control is `NOT_OBSERVED`: official URL returned a firewall-warning redirect; no historical PDF was substituted.

### A1 scoped HTML evidence path

A1의 scoped HTML 경로는 기존 Phase 2 Shadow Mode를 대체하지 않는 **opt-in** 경로다. 호출자는 검증할 canonical 행과 원본 CSV 행 번호를 함께 넘기고, 이미 승인된 HTTP boundary인 `RequestInvoker`를 주입한다.

```powershell
. ./tools/data/invoke-phase2-benefit-shadow-mode.ps1

$run = Invoke-Phase2BenefitShadowMode `
  -Rows $selectedRows `
  -SourceRowNumbers $originalCsvRowNumbers `
  -UseScopedHtmlEvidence `
  -RequestInvoker $httpInvoker

$run.PreparationSummary
```

scoped 경로의 순서는 다음과 같다.

```text
existing PUBLIC_OFFICIAL source
        ↓
per-run cached fetch
        ↓
officiality qualification
        ↓
generic HTML observation
        ↓
business row locator
        ↓
RelevantEvidenceSlice
        ↓
scoped binding
        ↓
scoped deterministic extraction
        ↓
independent scoped validation
        ↓
existing claim comparison / BenefitState evaluator
```

안전 경계:

- `-UseScopedHtmlEvidence`를 생략하면 기존 legacy Shadow Mode 동작과 반환 shape를 유지한다.
- scoped A1에서는 `DiscoveryInvoker`, `UnstructuredExtractor`, `PdfTextExtractor`, `SpreadsheetExtractor`를 함께 사용할 수 없다.
- `-SourceRowNumbers`는 `Rows.Count`와 같아야 하고, 중복 없이 모두 1보다 커야 하며, explicit `-SourceRowNumberOffset`과 동시에 사용할 수 없다.
- 같은 exact URL은 한 run 안에서만 fetch reuse되며 path/query 대소문자와 query identity를 보존한다.
- 같은 snapshot은 `SnapshotId + AdapterId + AdapterVersion` 기준으로 parse reuse된다.
- cache에는 source payload/template만 저장하고 `SourceRowNumber`, BusinessIdentity, locator 결과, slice, binding, claim, BenefitState/ReviewClass를 저장하지 않는다.
- fetch/parser/locator 실패나 ambiguity는 whole-page legacy extraction으로 fallback하지 않는다.
- fetch 실패는 `NOT_FOUND`나 `ENDED`가 아니며 GREEN 근거도 아니다.
- `LOCATED`는 대상 business row를 안전하게 특정했다는 뜻일 뿐, 혜택의 존재·현재성·종료를 확정한 것이 아니다. Generic A1 detail-only extraction은 정상적으로도 `NEEDS_VERIFICATION`에 머물 수 있다.
- `ProductionAction`은 계속 `NONE`이며 모든 결과는 사람 검토 대상이다.

`PreparationSummary` counter 의미:

| Counter | 의미 |
| --- | --- |
| `SourceEvaluations` | business/source 조합 평가 수 |
| `UniqueRequestKeys` | run 안에서 관측한 exact request URL key 수 |
| `ExternalFetchCount` | 실제 underlying `RequestInvoker` 호출 수 |
| `FetchCacheHits` | exact URL payload cache hit 수 |
| `SourceFetchFailures` | cache miss에서 실제 fetch가 실패한 unique source 수 |
| `AdapterParseCount` | 실제 `ConvertTo-BenefitHtmlTemplate` 실행 수 |
| `AdapterReuseCount` | parsed template reuse 수 |
| `LocatorLocated` / `LocatorAmbiguous` / `LocatorNotFound` | COMPLETE locator의 semantic 결과 수 |
| `LocationNotAttempted` | fetch/qualification/parser 단계에서 locator semantic 결과까지 가지 못한 평가 수 |
| `LlmInvocationCount` | A1에서는 항상 0 |

Location counter 합계는 항상 `SourceEvaluations`와 일치해야 한다. `LocationNotAttempted`는 semantic absence가 아니다.

A1 deterministic closeout 보고는 품질 통계 대신 다음처럼 기록한다.

```text
FixtureSafety:
  tested cases = deterministic scoped fixture cases
  wrong-row selections = 0 in tested cases
  cross-business claim leaks = 0 in tested cases
  false-GREEN = 0 in tested failure/ambiguity cases
  false-ENDED = 0 in tested failure/cross-business-ending cases

LiveAudit:
  Status = NOT_RUN
  AuditedRowCount = 0
  LocatedPrecision = null
  FalseGreenCount = null
  FalseEndedCount = null
```

위 값은 **테스트한 fixture에 대한 safety evidence**이지 population precision/recall 주장이나 실제 source-family 지원 선언이 아니다. Generic synthetic HTML 표가 통과해도 MMA/DDC/Paju/Yangju가 모두 지원된다는 뜻이 아니다. 실제 entry URL, pagination, detail traversal, attachment, PDF/XLSX 요구사항은 A2 source-family inventory에서 별도로 확인해야 한다.

Evidence diagnostic export는 original `SourceRowNumber`, source URL, snapshot hash/time, adapter version, selected slice text, table/row/field reference, binding evidence, validated claim을 보존한다. Shadow export는 기존과 동일하게 `data/canonical`, `data/seed`, `apps` 아래에 쓸 수 없다.

### Deterministic regression

전체 데이터 도구 테스트:

```powershell
Get-ChildItem .\tools\data\test-*.ps1 |
  Sort-Object Name |
  ForEach-Object {
    & pwsh -NoProfile -File $_.FullName
    if ($LASTEXITCODE -ne 0) { throw "FAILED: $($_.Name)" }
  }
```

Golden fixture는 다음을 고정한다.

- historical official-release evidence는 현재 `ACTIVE` truth로 재사용하지 않는다.
- explicit validated ending synthetic case는 `ENDED` 규칙을 따른다.
- source conflict / binding conflict synthetic case는 silent GREEN이 될 수 없다.
- historical/source-cited fixture와 synthetic algorithm fixture를 명시적으로 구분한다.

### Existing-source live smoke — 2026-09-24

Task 7에서는 GitHub Actions runner에서 canonical에 이미 저장된 공식 URL만 직접 fetch했다. general web search, discovery provider, LLM, PDF/XLSX 신규 dependency는 사용하지 않았다. 5개 source-stratified sample에서 외부 요청은 각 1회였고 모두 `ProductionAction=NONE`이었다.

| CSV row | source | fetch | officiality | binding | extraction | BenefitState | ReviewClass |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 5 | MMA public data / 투오프커피 | COMPLETE | VERIFIED_OFFICIAL | AMBIGUOUS | FAILED | NEEDS_VERIFICATION | YELLOW |
| 75 | Paju municipal HTML / 두둑한한판 | COMPLETE | VERIFIED_OFFICIAL | AMBIGUOUS | FAILED | NEEDS_VERIFICATION | YELLOW |
| 118 | DDC municipal HTML / 개성연출 | COMPLETE | VERIFIED_OFFICIAL | AMBIGUOUS | COMPLETE | NEEDS_VERIFICATION | RED |
| 339 | Yangju municipal HTML / 거시기닭갈비 | COMPLETE | VERIFIED_OFFICIAL | AMBIGUOUS | FAILED | NEEDS_VERIFICATION | YELLOW |
| 280 | Suwon municipal PDF / 고려이발관 | COMPLETE | VERIFIED_OFFICIAL | AMBIGUOUS | FAILED | NEEDS_VERIFICATION | YELLOW |

관측 결과:

- fetch COMPLETE: 5 / 5
- VERIFIED_OFFICIAL: 5 / 5
- `ENDED`: 0
- GREEN: 0
- YELLOW: 4
- RED: 1
- external requests: 5 total
- `ProductionAction=NONE`: 5 / 5

이 표본은 정확도나 population 성능 추정치가 아니다. 현재 Core가 실제 source에서도 실패를 종료/승인으로 오인하지 않는지 확인하는 operational smoke다.

DDC sample은 structured extraction 자체는 COMPLETE였지만, 한 공식 페이지의 복수 업소 혜택 claim이 한 canonical row 비교에 함께 들어가 `SOURCE_CONFLICT + RED`가 발생했다. 안전성 관점에서는 fail-closed지만, 향후 adapter 작업에서는 **business-bound row-scoped extraction**이 필요하다는 효율성 위험으로 남긴다.

Paju/Yangju HTML과 Suwon PDF는 현재 adapter 경계에서 충분한 row-specific evidence를 만들지 못해 `EXTRACTION_PROVIDER_NOT_CONFIGURED` 또는 binding ambiguity로 검토 대기 상태를 유지했다.

### Live smoke 실행 원칙

운영 smoke는 CI의 상시 deterministic test로 두지 않는다. 필요할 때 source-stratified canonical row를 소수 선택하고, `Invoke-Phase2BenefitShadowMode`에 실제 HTTP `RequestInvoker`를 주입해 실행한 뒤 로그/보고서만 보존한다.

- existing canonical official URL만 fetch한다.
- discovery provider는 승인 전 사용하지 않는다.
- unsupported PDF/HWP/OCR/free-text는 missing-adapter reason으로 fail closed한다; XLSX is accepted only through its validated row/cell path.
- smoke 후 `git diff -- data/canonical data/seed apps`가 비어 있는지 확인한다.
- smoke 결과를 release 승인이나 canonical 자동 수정 근거로 사용하지 않는다.

Phase 2 Core closeout is recorded by the fixed representative validation in [`docs/handover/2026-09-26-phase2-benefit-verification-closeout.md`](../../docs/handover/2026-09-26-phase2-benefit-verification-closeout.md). It does not expand support to PDF/HWP/OCR, SNS/blog, or general discovery; any future real-source GREEN still requires human audit.

## Phase 3 Snapshot / Incremental History

P3-0~P3-6은 stable canonical `businessId`와 별도의 file History Store, fingerprint, Location/Benefit observation·comparison, 보수적 증분 재사용을 구현했다. P3-7은 `lib/history/phase3-review-audit.ps1`의 pure review projection과 `invoke-phase3-review-audit.ps1`의 read-only COMMITTED-history scanner를 제공한다. Scanner는 기존 store를 입력받아 `Items`와 `Summary`를 반환하며 index rebuild, provider fetch, domain re-evaluation, canonical/seed/apps write를 하지 않는다.

`test-phase3-review-audit.ps1`은 route fail-closed, COMMITTED authority, comparison linkage, unique-artifact validation reuse를 검증한다. `test-phase3-closeout-validation.ps1`은 A/B/C 대표 matrix의 deterministic comparator 결과와 historical provenance 경계를 검증한다. 전체 Phase 3 근거와 limitations는 [closeout handover](../../docs/handover/2026-09-27-phase3-snapshot-incremental-closeout.md)를 참조한다. PR #108은 `dev`에 병합됐고 merge commit `d40e479b2f9e2b39839f338ef11259f126840460`의 post-merge CI run #209에서 `verify-data`와 `verify`가 모두 성공했다. Issue #107과 parent Issue #94도 완료되어 bounded Phase 3 closeout은 `COMPLETE`다.

## Phase 5 P5-0 — Manual single-business Benefit cycle

Issue [#126](https://github.com/jelleoo/MILIMAP/issues/126). Base:
`4c21fcc878760f6ce5d581d346bdd5b9281b0c9a`. This is a bounded manual composition,
not scheduling, multi-business execution, automatic approval, or Phase completion.
P4-3B remains BLOCKED; the evaluated OCR dependency remains NOT_APPROVED and
Phase 4 remains NOT_COMPLETE. The earlier adapter-limit notes above describe
their historical checkpoints; current scoped native support also includes bounded
HWPX tables and digital-text ruled-grid PDF. Production OCR is still unavailable.

### Bounded design and implementation ledger

Only `invoke-phase5-benefit-cycle.ps1`, `test-phase5-benefit-cycle.ps1` and this
README belong to P5-0. Existing Core, adapter, fingerprint, schema and History
writer/commit implementations stay unchanged. No new dependency or source policy.

1. RED: runner missing. GREEN: canonical selection, official-source/URL eligibility,
   existing single-source pipeline, committed-only Review, atomic derived output.
2. RED: committed same-RunId reentry fetched again. GREEN: terminal-state check
   before fetch; recover the requested run through the existing read-only scanner,
   not the latest observation index. Compare persisted input/execution fingerprints.
3. RED: preexisting staging fetched; overlapping launch was not excluded. GREEN:
   inspect staging and use a small per-RunId exclusive launch claim in existing
   History TempRoot. CAS/writer lock remain owned by existing History code.
4. RED: primary checkout paths were misidentified as external from a linked worktree.
   GREEN: check both current worktree and Git common repository roots; reject
   repository outputs/reparse ancestors. Resolve Git roots once per cycle.
5. Targeted regression, final read-only review, full data suite, protected diff,
   then local checkpoint. No live/provider/OCR execution is part of these tests.

Final read-only review: Critical0/Important1/Minor0. The Important finding was
derived output inside History observation directories. Its isolated-store RED
produced an unintended committed cycle; the minimum GREEN rejects report output
equal to/inside History root before fetch, with no files created. No other
Critical/Important finding was identified; the fix is covered by the safety test.

The first full-suite invocation reached P5-0 but exposed a test-fixture scope
error: GetNewClosure's dynamic module could not resolve the script-local runner
under CI-style `&` invocation (standalone `-File` had passed). The immediate
nested collision callback now retains the test's original script session state;
both invocation modes pass with the same concurrency assertions. No production
change or assertion weakening was needed. The complete suite is rerun afterward.

### Calling the runner

The file follows the existing dot-sourced PowerShell entrypoint style:

```powershell
. ./tools/data/invoke-phase5-benefit-cycle.ps1

# Read canonical input only. Set explicit values for this manual attempt.
$rows = @(Import-Csv -LiteralPath $canonicalCsv)
$store = New-HistoryStoreLayout -Root $externalHistoryDirectory
$result = Invoke-Phase5BenefitCycle -Store $store -Rows $rows `
    -BusinessId $selectedBusinessId -RunId $runId -ObservedAt $observedAt `
    -RepositoryRevision $revision -SourceRowNumberOffset 2 `
    -OutputDirectory $externalReportDirectory `
    -RepositoryStateProvider $repositoryStateProvider -RequestInvoker $httpInvoker

$result
```

`Rows` must contain valid, unique existing canonical businessIds; exactly one is
selected. No IDs or source URLs are generated. `SourceRowNumberOffset` defaults
to1 and describes the current input array position (use2 for a CSV with a header),
not a separately persisted historical row-number assertion. RunId is a lowercase
filename-safe token, ObservedAt an explicit timestamp, revision an explicit
lowercase40-character SHA. RepositoryStateProvider is the existing caller-supplied
cleanliness evidence; unknown/dirty state cannot enable incremental reuse.

History and reports must be outside both repository roots, and reports must also
be outside the History root so scanners cannot mistake derived views for records.
Callers must also
create the store outside the repository: New-HistoryStoreLayout itself creates
directories before this runner sees it. Do not place the store/report under
canonical/seed/apps or another linked worktree. Paths traversing existing reparse
points are rejected. The runner does not modify global configuration or credentials.

Source eligibility requires one existing PUBLIC_OFFICIAL candidate and the
existing safe HTTP URI gate. Missing, business-website, SNS/review or known
unsupported suffix sources fail before fetch. Allowed lexical suffixes are empty,
html/htm/do/php/aspx/asp/jsp/xlsx/hwpx/pdf. An extension is only preflight eligibility:
actual MIME/bytes/package/layout/qualification are still validated by existing
Phase2 code. Unknown returned formats fail closed. Approved MMA entry uses its
existing LIST/DETAIL dispatch; arbitrary JSONP endpoints are not enabled.

### Result, reentry and recovery

- `Status`/`OperationalStatus` describe execution and observation; `CommitCode`
  separately preserves COMMITTED, ABORTED, BASELINE_MOVED or WRITER_LOCKED. A
  committed failed observation is not operational success. Do not infer success
  from the old helper's RunManifest.ExecutionStatus alone.
- BenefitState/ReviewClass and authoritative Comparison/Review are read from
  committed records only. New-Phase3ReviewItem preserves the existing route and
  ReviewKey; no payload-equality override or new review queue contract exists.
- First execution returns actual existing metrics plus observed FetchCacheHits
  and AdapterReuseCount. Recovery returns Metrics=null because work counters are
  not persisted by History. Missing values are never invented as zeros.
- Stable `<RunId>.json` output is written through an exclusive temporary file and
  no-overwrite rename. Existing equivalent authoritative view is preserved;
  conflicting/malformed output fails explicitly. Reports are derived views, not
  an authority over History. No append-only review export or duplicate ReviewKey
  is produced on sequential same-RunId reentry.
- COMMITTED reentry never fetches, recommits or deletes History/staging. It uses
  the existing committed-history scanner once to find the supplied run, validates
  input/revision/time/semantic references, and rebuilds a missing output. A later
  run moving the latest index cannot redirect recovery to that newer observation.
- Commit success followed by output failure retains CommitCode=COMMITTED and
  OutputStatus=FAILED. Reenter with the same pinned selection/RunId/time/revision
  after correcting only the output problem. Do not perform the source run again.
- New RunId means a new current fetch. RECORD_ONLY is returned only when the
  existing comparator actually routes it there. Real material changes retain
  HUMAN_DOMAIN_REVIEW; failures remain OPERATIONAL_DIAGNOSTIC where comparable
  history permits that comparison. A first failed baseline is still represented
  by the existing comparison policy, not a wrapper-invented route.

The launch claim is `.p5-<RunId>.claim` inside existing Store.TempRoot, not the
History `.writer-lock`. It is acquired before fetch and prevents overlapping
P5-0 launches of the same RunId in the same store, even with different report
directories. History fetch/parse/evaluate stay outside the writer lock. Only
the successful committed owner removes its own claim. Failed/interrupted claims
remain with a small diagnostic outcome; BASELINE_MOVED/WRITER_LOCKED cannot be
silently retried on reentry. ABORTED/ambiguous terminal/staging states block.

Stale claims, interrupted staging and cross-version/non-P5 writers require manual
inspection; there is no automatic lease stealing, retry scheduler or cleanup.
Tests prove sequential reentry, atomic exclusive-claim behavior and deterministic
overlapping calls. They do not claim a distributed execution service or protection
against callers bypassing this entrypoint. Existing History CAS remains the final
authority for competing different-RunId writers. Recovery scans committed history
once (an existing cost); normal execution does not introduce a history-wide scan.

### Offline acceptance

```powershell
pwsh -NoProfile -File ./tools/data/test-phase5-benefit-cycle.ps1
```

The tests inject only synthetic HTTP and use isolated external temporary stores.
They exercise real normalization/scoped parsing/extraction/evaluation/comparison/
commit. Expected controls: first fetch1/parse1/extract1/evaluate1; same RunId
fetch0/metrics unknown; unchanged new RunId fetch1/parse0/reuse1; changed material
ReviewRoute preserved; failure parse0/extract0 with no false absence/ending;
BASELINE_MOVED/WRITER_LOCKED no authoritative Review or artifact publication;
output-failure recovery without work; invalid inputs/source/staging no network.
ProductionAction is always NONE. No canonical/seed/apps writes are authorized.

P4-3 evaluation branch/evidence stay untouched. Before periodic execution, validate
the manual one-cycle path operationally, define authorized credentials/budgets and
stale-attempt recovery, then separately design scheduling/backoff and any batch or
cross-run incident grouping. This file does not authorize those later steps.

Final local verification (2026-10-24): Base/Recovery/Safety PASS in both `-File`
and CI-style `&` invocation; applicable Benefit incremental/adapter, History
store/commit, Review and scoped HTML/XLSX regressions PASS. The final complete
data suite passed63/63 after the test-fixture scope correction. Existing portable
.NET SDK8.0.426 was configured process-locally for native PDF regression in the
nonadmin Windows environment; no SDK/dependency was installed. Android, live HTTP,
OCR and CI were NOT_RUN (no product changes/no remote actions). Diff whitespace
and protected-path checks PASS; exactly three reserved files changed. P4-3 HEAD
3196d92cbde23ce7064a3c1e6fbcffd25592fc04 stayed clean and unchanged. Local checkpoint
only; Issue126 remains open, no push/PR/merge.

### PR review follow-up (2026-10-25)

The initial PR CI `verify-data` run exposed hidden `.p5-*.claim` lookup behavior
on Ubuntu. The prior claim is now inspected with `-Force`, preserving the actual
failed-attempt reason without retrying. A Windows Hidden-file regression also
reproduced the failure before the fix. Whole-PR review additionally found that
terminal-dot and DOS device-name RunIds could reach execution on Windows. These
identities, including reserved names with extensions, are now rejected before
fetch or History writes. Both defects have RED -> minimal GREEN regressions;
Core, adapters, contracts and the previous bounded live-smoke evidence are unchanged.

Follow-up focused tests PASS in both invocation modes; the complete local data
suite was rerun after the production fixes and passed 63/63. No live HTTP or OCR
was rerun. Exact pushed-HEAD data and Android CI remain required before approval.

## Phase 5 P5-1 — Bounded sequential manual Benefit batch

Issue [#128](https://github.com/jelleoo/MILIMAP/issues/128), base
`c134f94af27665dc3ab95da4732d8a8f73afeb3a`. Manual, sequential, 1–10 explicit
existing businessIds; no scheduling, shared RunContext or production approval.
Only the two P5-0 internal preflight/verified-recovery helpers are extracted;
its public parameters, result/error behavior and existing policies are unchanged.

```powershell
. ./tools/data/invoke-phase5-benefit-batch.ps1
$options = @{
    CanonicalCsvPath = $canonicalCsv
    BusinessIds = $selectedBusinessIds # explicit order, unique, count1–10
    Store = $existingExternalHistoryStore
    BatchWorkspaceRoot = $externalBatchWorkspace
    ObservedAt = $fixedObservationTime
    RepositoryRevision = $actualCheckoutRevision
}
$plan = New-Phase5BenefitBatchPlan @options # read-only preview, no source requests
# Freeze/review this BatchId before the manual attempt.
$result = Invoke-Phase5BenefitBatch @options -BatchId $plan.BatchId `
    -RepositoryStateProvider $repositoryStateProvider -RequestInvoker $httpInvoker
$recovery = Invoke-Phase5BenefitBatch @options -BatchId $plan.BatchId `
    -Mode RecoverOnly -RepositoryStateProvider $repositoryStateProvider
```

Read the entire operator-supplied canonical CSV once per invocation before
selection. Preserve record ordinals + header offset2, not a new multiline-CSV
physical-line policy. Validate all selected identities/sources/paths and actual
checkout revision before HTTP. The input is a trusted operator snapshot, not an
authenticated source of benefit truth. Observation time is explicitly frozen,
not silently substituted for actual request time or canonical verification date.

PlanCore v1 includes full ordered input digest/path, selected order, original
ordinals, business/source identity/input fingerprints, revision/time, normalized
History/workspace roots, every effective History subroot, and fixed10 bound. Existing canonical JSON/SHA helpers
derive `batch-<full hash>` and domain-separated business RunIds. Derived IDs are
excluded from their own digest inputs. Changed input/order/time/revision/root
rejects the previous BatchId. Digests establish integrity, not authenticity.

Exclusive immutable `plan.json`, one atomic derived `summary.json`, and stable
`items/<RunId>.json` reports live under `<BatchWorkspaceRoot>/<BatchId>` outside
Git and History. Workspace/History overlap in either direction and existing
reparse ancestors are rejected. Existing plan bytes must equal the recomputed
canonical plan, including version; no overwrite. Plan/summary metadata limit1MiB.
Summary is neither authority nor a trusted resume cursor; no append-only Review
copies. Existing per-business output equivalence/recovery behavior is reused.

A batch-only exclusive guard coordinates the same content-bound batch. Existing
History single-writer/CAS remain authoritative for distinct batches and standalone
callers. No automatic retry, lease theft, stale deletion or batch index repair.
A handled stop may release its own guard; interrupted/unclassified failures or
summary-output failures retain it for manual examination. Fresh commits are
independent; a later failure does not roll back earlier commits.

RecoverOnly reads verified COMMITTED records, preserves ReviewKeys/evidence,
never executes pending/failed businesses or writes History. Missing derived
reports may be rebuilt. COMMITTED takes precedence over residual per-run claim/
staging for read-only recovery; residue blocks Execute and is never deleted.
A stale batch guard blocks both modes. Unknown historical work metrics stay null.

Use existing read-only History audit plus selected index/artifact validation.
Fresh persisted index must match current observation; a cleared or regressed comparable pointer inconsistent with committed comparable history blocks execution. Noncomparable failure may
advance LatestObservationId while retaining prior LatestComparableObservationId.
IndexRepairRequired is unavailable from P5-0; never assume false. Existing Core
may rebuild on missing indexes/recovery stages, including first-time businesses;
that behavior and lock cost stay unchanged. Batch does no repair.

Continue on verified COMMITTED/COMPLETE, or a safely committed FAILED/PARTIAL/
UNSUPPORTED with existing OPERATIONAL_DIAGNOSTIC routing. An initial failed
baseline can legitimately route RECORD_ONLY: preserve it and stop rather than
invent a diagnostic route. Stop on CAS/lock, unresolved state, invalid shared
History, unclassified cycle error or committed output failure. Correct only the
output problem and use RecoverOnly; no source rerun is needed.

FINISHED denotes traversal, not current-benefit approval. Summary separates
executed/recovered/not-started, commit, operational and ReviewRoute counts.
Each metric exposes KnownSum/ObservedCount/MissingCount; Total=null when coverage
is incomplete. Never zero-fill recovery or infer work from commit status. A cycle
that throws without returning remains an attempted failure with unknown work.

Three new businesses sharing one HTML URL still fetch3/parse3. Existing individual
POST_FETCH reuse and durable artifact dedup remain. Remaining costs: repeated
input/path checks, source fetch/parse, initial History audit, per-recovery full
scans, indexed artifact integrity reads and possible existing Core rebuilds.
Ten businesses is a count limit, not a hard wall-clock limit. Cross-business
sharing requires separate approval and isolation tests; no parallel cache added.

Offline tests: `test-phase5-benefit-batch.ps1` Plan/Execution/Recovery/Safety and
P5-0 Base/Recovery/Safety/Parity. Synthetic fictional inputs, external temporary
stores and injected transport exercise actual Benefit/History/Review, CAS and
writer lock. No real benefit truth, live HTTP or OCR is implied. Before periodic
execution, separately approve source budgets, stale-state procedures and retry/
backoff after the manual path is operationally verified.

`ProductionAction=NONE`; OCR dependency NOT_APPROVED; P4-3B BLOCKED;
Phase4 NOT_COMPLETE. This checkpoint does not authorize push/PR/merge or P5-2.

P5-1 local checkpoint verification (2026-10-25 KST): Plan/Execution/Recovery/Safety
and P5-0 Base/Recovery/Safety/Parity PASS; related Benefit/History/Review/run-context
regressions PASS. Final CI-style sorted `&` invocation of all tools/data/test-*.ps1
passed64/64 using existing portable .NET8.0.426 process-locally. No SDK/dependency
installation. Actual CSV read1, first shared-URL3 businesses fetch3/parse3/commits3;
recovery3 adds HTTP0/History writes0 with unchanged ReviewKeys; mixed metrics
KnownSum2/Observed2/Missing1/Total=null. Actual Core CAS movement and writer lock
stop after one request, leaving two businesses unstarted. Latest failed observation
retains prior comparable pointer; stale/corrupt cases reject before requests.

One fresh whole-change review identified Important2: effective History subroots
were missing from PlanCore, and cleared/regressed comparable index pointers could
bypass comparison. Both were reproduced RED and fixed minimally, then targeted
and the final full suite passed. No deferred Minor findings. The review was not
rerun; coverage and full regression verify the correction pass. Protected/Core/
adapter/evaluation diff0; whitespace check PASS. Android, remote CI, live HTTP and
OCR NOT_RUN (no product changes, no push or execution authorization). Local commit
only; branch/worktree retained for human review, no P5-2 implementation.

## Phase 5 P5-2A — Read-only Benefit batch operational inspection

Issue [#130](https://github.com/jelleoo/MILIMAP/issues/130), based on dev
`db50d6c357366350fca5f235ffc3211ce7ff1634`. This inspector returns one diagnostic
object through the PowerShell pipeline. It does not execute or recover a cycle,
create a Store, write reports, claim a batch, repair indexes or fetch sources.

```powershell
. ./tools/data/inspect-phase5-benefit-batch.ps1
$inspection = Inspect-Phase5BenefitBatch `
    -Store $existingStoreLayout -CanonicalCsvPath $canonicalCsv `
    -BusinessIds $orderedBusinessIds -BatchWorkspaceRoot $batchWorkspace `
    -BatchId $frozenBatchId -ObservedAt $frozenObservationTime `
    -RepositoryRevision $frozenRepositoryRevision
```

Pass an existing layout; do not call New-HistoryStoreLayout just to inspect an
unknown/missing directory. Paths are operator inputs, not destinations taken
from untrusted JSON. Traversal/reparse boundaries are rejected. Frozen plan
metadata is checked against the 1MiB bound before loading. The v1 format verifier
uses existing canonical JSON/SHA helpers and the existing BatchId/RunId formulas;
no new normalization or History contract is introduced. The canonical input
identity is the existing parsed-row digest, not a claim about raw CSV byte hash.

PlanState describes stored self-consistency, not authenticated historical truth.
CurrentCompatibility separately compares the current canonical/revision/selection
and roots. Historical revision or current input mismatch does not make an
otherwise valid plan INVALID, but blocks recovery consideration. Missing plan
is reported MISSING, not History corruption, and is never created by inspection.
A copied archive is not silently rebound to another History/workspace root.

One existing committed-History audit is followed by selected-record validation
and existing P5-1 index checks. There is no per-business full recovery helper.
Manifest identity, input/execution fingerprints when currently comparable,
evidence/semantic projections, comparison/ReviewKeys and artifacts remain strict.
Historical work metrics are unavailable and stay null. Legitimate failed latest
B with retained comparable A is accepted; regressed A/A remains rejected.

Outputs separate PlanState, CurrentCompatibility, HistoryState, GuardState and
per-business RunState, CommitStatus, OperationalStatus, DerivedReportState,
FingerprintState, claims/staging, reasons and RecoveryConsideration. COMMITTED
is not benefit approval; operational failure is not NOT_FOUND or ENDED.
ABORTED is a legitimate terminal, while PREPARED/bare terminal directories are
unresolved. Shared malformed/ambiguous History blocks recovery assessment.

A committed missing report remains COMMITTED/MISSING; the inspector never rebuilds
it. PRESENT_IDENTITY_ONLY checks basic IDs/time/revision/ReviewKey, not complete
report equivalence with the existing output writer. Conflicting/unreadable derived
identity blocks consideration without rewriting committed History.

Guard presence blocks recovery regardless of age or readability. No PID/age-based
staleness proof or deletion advice is supplied. COMMITTED with per-run residue may
remain conditionally assessable; ResidueBlocksExecute reports the separate Execute
blocker. No guard/staging/claim is acquired, removed or stolen.

RecoveryConsideration is CONDITIONAL, BLOCKED, NOT_APPLICABLE or INCONCLUSIVE.
ExecutionAuthorized=false and ProductionAction=NONE always. CONDITIONAL only means
an operator may consider the existing recovery path, which must revalidate its own
current guards/identities and output policy; this object is never an execution
permit or resume cursor.

Critical plan/input/selected-record/index/guard state is checked again. A detected
change yields INCONCLUSIVE_CONCURRENT_CHANGE. This is a best-effort observation,
not an atomic History snapshot or guarantee that state will remain unchanged.
No writer lock or automatic read-retry loop is added.

Costs remain proportional to the existing History: a no-follow metadata traversal
rejects internal reparse entries before the global audit can follow them; that
audit scans committed records and hashes unique artifact references. Selected
strict helpers may re-read/hash artifacts. No persistent cache/index or public
trust bypass is added; selected count<=10 is not a History-size/time bound.

Offline checks: test-inspect-phase5-benefit-batch.ps1 Plan/History/Safety/All,
existing P5-0/P5-1 tests, then the complete sorted tools/data/test-*.ps1 suite.
Fictional fixtures are constructed outside each inspected measurement window.
Every inspection asserts HTTP0 and unchanged History/workspace directory lists
and SHA-256 inventories, with mutation/network entrypoints trapped. The design-stage
independent builder check was NOT completed (capacity error); no prior independent
validation is claimed.

No P5-2B transport/budget implementation, scheduler, new dependency, Core/adapter
change or production write is included. OCR dependency NOT_APPROVED; P4-3B BLOCKED;
Phase4 NOT_COMPLETE. This local checkpoint does not authorize push/PR/merge.
The whole-change review found one Important diagnostic identity bug: absent plan
plus changed current input could substitute another batch's resolved RunIds.
The regression was observed RED before correction. Inspection now keeps the
requested BatchId-derived RunIds; current plan metadata is used only when its
BatchId matches. With no matching frozen/current plan, SourceRowNumber is null
and fingerprints remain NOT_VERIFIED; recovery stays BLOCKED. Tests also create
the other batch's actual committed records and verify no observation/ReviewKey
substitution. No independent re-review is claimed after this correction pass.
Local checkpoint verification (2026-10-25 KST): inspector Plan/History/Safety and
missing-plan/other-batch identity regression PASS; existing P5-0
Base/Recovery/Safety/Parity and P5-1 Plan/Execution/Recovery/Safety PASS.
Complete CI-style sorted tools/data/test-*.ps1 suite passed65/65 after the review
correction, using the already available portable .NET8.0.426 process-locally.
All65 per-script logs are retained outside Git. The early targeted native Git
read warning did not recur in final full regression. Whole-change review:
Critical0/Important1/Minor0; the Important finding was reproduced RED and fixed.
No remaining known Critical/Important finding; no independent correction re-review.
Exactly3reserved files; protected/Core/adapter/evaluation diff0; diff-check PASS.
Android/remote CI/live HTTP/OCR NOT_RUN (data-only local checkpoint; no execution
or push authorization). Ready for human Draft PR review, not periodic execution.
Final PR-preparation review found one Important concurrency-classification issue:
a selected valid comparison changed after the global audit but before its first
file stamp was detected as P52_AUDITED_REVIEW_CHANGED yet reported as invalid
History. The existing DuringAudit regression first failed RED (BLOCKED instead
of INCONCLUSIVE_CONCURRENT_CHANGE). An internal exception marker now routes that
detected version difference to INCONCLUSIVE_CONCURRENT_CHANGE / HistoryState
INCONCLUSIVE, including every item's recovery consideration. Ordinary corruption
remains blocked. Inspector All and P5-0/P5-1 focused parity PASS after correction;
full data regression and exact-head CI are required for the final PR HEAD.

The first post-fix full-suite attempt exposed a test-fixture scope error: a
GetNewClosure callback could not resolve script-scoped assertion/serialization
functions under CI's ampersand invocation. Fixture validation and serialization
now occur before the callback, which only performs the intended captured file
write. No assertion was relaxed. Inspector All passes in both -File and CI-style
ampersand modes; the full final suite is rerun after this test-only correction.

Final local PR gate: complete CI-style data regression65/65 PASS after both the
concurrency correction and fixture-scope correction. Inspector All passes in both
invocation modes; P5-0/P5-1 focused parity and all existing full-suite regressions
PASS. Failed checkpoints remain recorded; no live HTTP/OCR was executed. Exact
pushed-head verify-data and verify must still succeed before merge approval.

## Phase 5 P5-2B — Optional strict network execution policy

Issue #132 adds explicit `-NetworkPolicy` to `New-Phase5BenefitBatchPlan` and
`Invoke-Phase5BenefitBatch`. Omitting it retains the exact Plan v1, caller
RequestInvoker and legacy result shape. P5-0, adapters, History Core, evidence,
Review and fingerprint contracts are unchanged.

`New-Phase5BenefitNetworkPolicy` creates pure canonical configuration. Strict
Plan v2 binds the complete policy, its existing canonical-JSON SHA-256 fingerprint
and the transport/runtime identity into BatchId. Existing BatchId-derived RunIds
are preserved. A caller RequestInvoker is rejected in strict mode; no callback,
Verified flag or trust switch can enable a custom transport. Plan preview and
historical v2 inspection do not instantiate transport or run qualification.
The inspector validates policy/identity/fingerprint/BatchId/RunIds and includes
frozen policy in current-input compatibility. Its v1 validation remains strict.
ExecutionAuthorized=false and ProductionAction=NONE remain mandatory.

Strict transport uses owned .NET HTTP/1.1 GET with Connection: close, fresh handler
per reservation, no proxy/cookies/credentials/redirect/decompression, and an atomic
one-connect gate. A framework reconnect cannot silently consume another physical
request: the additional connect is rejected before connecting. Original HTTPS
hostname and certificate validation remain intact. URLs require exact approved
hosts, port443 and frozen destinations. MMA permits only its existing fixed LIST
and numeric DETAIL URL shapes; business matching and code linkage stay in the MMA
adapter. DNS results are checked for unsafe addresses before connection; connection
uses a validated address without a second DNS resolution or address fallback.

Qualification evidence is restricted to the exact frameworks .NET10.0.12 and
.NET10.0.14 / Microsoft Windows 10.0.26300 / X64 /
P52_HTTP11_SINGLE_CONNECTION_V1. Other environments fail closed at Execute.
No Linux qualification or operational source compatibility is claimed.

Issue #135 adds only the exact .NET10.0.14 framework identity. On 2026-10-26,
actual Windows10.0.26300 / .NET10.0.14 / X64 / PowerShell7.6.9 first failed the
new qualification assertion, then passed after the exact-version extension.
The existing local transport All matrix also passed on that actual runtime:
counting HTTPS, redirect/retry suppression, TLS/chain and separate client/server
AIA attribution, address safety, size/deadline/reset/reconnect limits, atomic
admission/sticky stop, and loaded-type provenance/reload rejection controls.
The .NET10.0.12 positive identity check is synthetic in this run; its prior
physical qualification evidence remains historical. The embedded C# source
and its pinned digest are unchanged. Version ranges and caller trust switches
are not supported. Offline PASS, production predicate approval and official
source compatibility are separate: this extension grants neither DDC access
nor private raw-HTML retention permission. Issue #134 remains an independent
human live-access gate; LiveHTTP=NOT_AUTHORIZED and ProductionAction=NONE.
Tests use local counting TLS servers and the private exchange/handler core via
reflection. Their test-only custom-root chain does not install a certificate,
change the system trust store, or affect the strict public Send path; production
has no caller certificate/address/handler override. Servers and certificate/key
handles are disposed. Tests cover keep-alive closure/reconnect, redirect, auth
challenge, timeout, reset, bounded headers/body/chunks and untrusted TLS. Qualification
is evidence for this profile, not a universal proof for future runtimes or changed
transport code. Profile changes require requalification, never legacy fallback.

The policy's provisional test ceilings are 0..20 attempts, timeout<=30000ms,
body<=32MiB, headers<=64KiB (whole KiB), MaxInFlight1, Redirect0 and Retry0.
They are not approved operational limits for all official sources. No official
source HTTP or production activation is part of this implementation checkpoint.
Budgets are per batch, not an aggregate limit across independently created batches.

Reservations are atomic/nonrefundable. FirstStopReason is sticky outside fetch
exceptions. Pre-cycle and post-cycle checks prevent subsequent pristine cycles.
Budget0 starts no cycle or History commit. Mid-cycle denial (including MMA DETAIL)
may reach the existing legitimate diagnostic commit; the separate policy stop is
reported and prior commits remain authoritative. An ordinary source timeout
consumes its reservation but is not labeled budget exhaustion. No benefit approval,
NOT_FOUND or ENDED is inferred from policy failure.

The immutable strict plan is the one-shot execution seal. It is written with
WriteThrough and Flush(true) before any request; a prior seal blocks Execute both
before guard creation and after guard acquisition. Interrupted/partial seals and
existing claims remain blocked. Even a crash after sealing and before dispatch
requires operator review; Execute does not resume or reset its budget. RecoverOnly
can reproduce verified committed results without requests or new History commits.
There is no automatic retry, stale guard/claim/seal deletion, rollback or repair.
Existing safe owner-guard lifecycle and transport handle disposal are preserved.

Strict-only NetworkExecution separates ReservationsConsumed, AttemptedCount,
DeniedCount, RespondedCount, UnknownOutcomeCount, nullable PhysicalRequestCount,
FirstStopReason and TransportQualification. AttemptedCount means dispatch entry,
not confirmed server receipt. Headers may be observed before a body failure.
PhysicalRequestCount is null after a real dispatch because dispatch does not prove
server receipt; zero is known only before dispatch. Legacy ExternalFetchCount
still counts logical invoker calls, including a denied DETAIL. Historical recovery
network metrics remain null; they are not reconstructed from History.

Offline batch integration substitutes only the internal dispatch function in tests;
there is no public strict-mode injection parameter. It exercises real P5-0,
MMA LIST/DETAIL, XLSX, History commits and committed recovery. Runtime qualification
is separately exercised by the counting-server tests. No actual source response,
History operational data, binary or raw evidence is committed.

Remaining costs: fresh TLS connection per admitted request; per-business P5-0
fetch/parse state; existing global History/recovery scans. No shared cache,
scheduler, new persistent budget ledger, dependency or production write is added.
P4-3B=BLOCKED; OCR dependency=NOT_APPROVED; Phase4=NOT_COMPLETE.

P5-2B final review corrections (offline):
- An owned X509 chain policy disables certificate issuer downloads, retains normal
  verification/system trust and server-auth purpose, and leaves online revocation
  disabled as in the original .NET client default. The missing-intermediate client
  chain test records issuer HTTP0 and PartialChain. The first combined fixture
  observed one AIA request; a raw ClientHello with no client chain validation
  reproduced that request in Windows test-server credential construction. Server
  preparation is measured separately and is not mislabeled as a client request.
- Framework initial-header and trailer limit failures latch
  RESPONSE_HEADERS_EXCEEDED before fetch can catch them. Batch regression preserves
  the current diagnostic commit and leaves two subsequent businesses unstarted.
- DNS and exchange share one cancellation deadline. A controlled150ms resolver-phase
  delay plus200ms response delay is canceled near the single300ms budget; an expired
  deadline dispatches0. This is a local timing fixture, not an OS DNS latency claim.
- Strict RecoverOnly requires an existing frozen plan and creates no seal/guard on
  pristine input. The subsequent first Execute remains possible. Sealed committed
  recovery stays network0/History-write0.
- Inspector Network fixtures have an isolated workspace; legacy All assertions are
  retained. Without a frozen policy and without a provably matching current v1 plan,
  compatibility is UNAVAILABLE rather than a guessed input mismatch.
The whole-change review found Critical0/Important5; each Important was reproduced
RED and corrected. The frozen-policy diagnostic was also corrected under the
explicit mission requirement. No independent re-review is claimed. Final focused
and full data verification are recorded after these corrections.

A denied internal reconnect also latches TRANSPORT_RECONNECT_BLOCKED, preventing
further pristine cycles. The additional author regression was observed RED before
the owned accounting was connected to the one-connect gate.
The first full CI-style suite found an additional invocation-scope defect:
-File had passed, but ampersand invocation could not resolve the named internal
request function from GetNewClosure. Fetch swallowed that error; observed dispatch
and reservations were both0. The owned invoker now captures its internal Function
CommandInfo rather than resolving the function name inside the closure. The same
ampersand Network regression changed RED to GREEN without counter correction or
public transport injection. The failed full-suite log is retained outside Git;
full regression is rerun after this one-line orchestration fix.

Final local checkpoint verification (2026-10-26 KST): complete sorted CI-style
ampersand tools/data/test-*.ps1 suite PASS66/66 after the invocation-scope fix.
P5-0 Base/Recovery/Safety/Parity, P5-1 legacy and Network, inspector All including
v2/historical/missing-policy isolation, and policy/transport tests PASS. Both
-File and ampersand Network invocation were verified during the correction.
Existing portable .NET SDK8.0.426 was used process-locally for the PDF regressions;
PowerShell transport qualification used its own .NET10.0.12 runtime. Failed and
final per-script logs remain outside Git. Protected/Core/adapter/evaluation diff0;
exactly seven reserved files. No official-source HTTP, quality OCR, new dependency,
Android execution, remote CI, push, PR or merge occurred in this checkpoint.
Numeric source-operational limits and any live smoke still require human approval.
Timeout is cooperative .NET cancellation, not an OS process/resource guarantee.
Independent whole-change review was performed once before its RED/GREEN correction
pass; no independent re-review of the corrections is claimed.

## C-Lite PR 1 — inactive HTML scoped-evidence contracts (Issue #137)

`lib/history/benefit-scoped-evidence.ps1` defines validation functions only. No
production runner imports it. It does not open a store, write artifacts, fetch a
source, activate reuse, suppress RAW capture, or change any existing fingerprint.
Existing `RAW_SOURCE_PAYLOAD` behavior and historical artifacts remain unchanged.

Run the offline synthetic contract tests:

```powershell
pwsh -NoProfile -File tools/data/test-benefit-scoped-evidence.ps1
```

### Exact v1 shape and types

All listed properties are required, case-sensitive, and closed to additional
properties. Objects are PSCustomObjects; arrays must be real one-dimensional
arrays (including `[]`), never null or implicitly wrapped scalars. Integers are
Int32/Int64 only, not boolean, floating point or numeric strings. Booleans must
be Boolean. All timestamps remain the original ISO string, explicit offset and
fractional digits included. `ConvertFrom-BenefitScopedEvidenceJson` checks every
JSON object for duplicate/escaped/case-colliding names before deserialization,
then uses `DateKind String`. Callers must not feed untrusted JSON through a lossy
reader first. No truncation or repair occurs.

`BENEFIT_SCOPED_EVIDENCE` / `BenefitScopedEvidence` / version 1 contains:

- `RetentionProfile='C_LITE_V1'`, `Mode=LOCATED_FIELDS|OUTCOME_ONLY`, `BusinessId`.
- `Capture={ObservationId,RunId,ObservedAt,SourceRowNumber}`; row >=2 is capture
  provenance, not business identity.
- `Links={InputFingerprint,EvidenceFingerprint,SemanticFingerprint,
  ExecutionFingerprint,EvidenceArtifactReference,SemanticArtifactReference}`.
- `Source={Url,Format,ContentHash,HashKind,SnapshotId,ObservedAt,TextLengthUtf16}`;
  Format HTML, HashKind HTML_TEXT_UTF8_SHA256. Hash covers the original decoded
  markup-bearing response string encoded as UTF8, not HTTP wire bytes. SnapshotId
  uses the existing URL/format/original timestamp/hash identity. Spans are UTF16.
- `Adapter={Id,Version}`: HTML_GENERIC / string `1`, or both null if unobserved.
- `Outcome={ObservationOperationalStatus,Comparable,FetchStatus,
  OfficialityStatus,AdapterStatus,LocationOperationalStatus,LocationStatus,
  BindingStatus,ExtractionStatus,ValidationStatus,CoverageKind,ContentUnitCount,
  CandidateReferences,CandidateReferenceCount,IdentityEvidenceCodes,ReasonCodes,
  ClaimValidationCounts}`. CoverageKind is ADAPTER_SUPPORTED_TABLE_ROWS, not
  website-wide coverage.
- `Scope={Type,Reference,TableStart,TableLength,RowStart,RowLength}`, TABLE_ROW;
  null in OUTCOME_ONLY.
- `Fields[]={Key,HeaderText,DecodedValue,HeaderStart,HeaderLength,CellStart,
  CellLength,FieldReference}`. Existing header map and physical references apply.
- `Claims[]={ClaimType,FieldKey,EvidenceReference,ExtractionMethod,
  ValidationStatus,SemanticClaimOrdinal}`; method SCOPED_HTML_CELL, status VALIDATED.

History operational status is COMPLETE/PARTIAL/FAILED; Comparable is boolean.
Captured FetchStatus is COMPLETE. Officiality is VERIFIED_OFFICIAL/UNVERIFIED/
REJECTED or null when unobserved. Adapter/location operational codes are
COMPLETE/PARTIAL/FAILED/UNSUPPORTED or null. Location semantic codes are LOCATED/
AMBIGUOUS/NOT_FOUND or null; noncomplete location cannot have a semantic result.
Binding codes are STRONG/PLAUSIBLE/AMBIGUOUS/CONFLICT or unobserved null.
Extraction/validation codes are COMPLETE/PARTIAL/FAILED or unobserved null.
A placeholder FAILED result does not claim that a stage actually executed.
ReasonCodes use the existing Benefit registry; IdentityEvidenceCodes are the
existing NAME_MATCH/FULL_NAME_MATCH/FULL_ADDRESS_MATCH/BRANCH_MATCH/PHONE_MATCH.
No arbitrary diagnostic text or exception messages belong in this artifact.

`ClaimValidationCounts` is null when unavailable; otherwise exactly
`{Total,Validated,Invalid,Conflict,Unknown}`, nonnegative measured result counts,
Total = sum of the other four. These are not execution counters. A measured zero
is 0, never null. CandidateReferenceCount is null only with an empty reference
array, otherwise equals its measured array length. ContentUnitCount is nullable.
Never invent metadata for an unobserved stage.

### Capture, claim linkage, outcomes and reuse

`Assert-BenefitScopedEvidenceCapture` validates the original source document and
slice using the existing strict provenance path; source fields and exact cell
references must match. Each retained claim has exactly one extracted claim,
validated claim and Result claim, then one ordinal in the **canonical stored**
BenefitHistorySemantic Claims array. It reuses existing scoped whitespace
comparison and domain semantic conversion, without new normalization. Duplicate,
ambiguous, wrong-source, wrong-cell or incomplete linkage is rejected.

LOCATED_FIELDS requires complete fetch/adapter/location/extraction/validation,
VERIFIED_OFFICIAL, LOCATED, STRONG, complete comparable History, no nonvalidated
claim counts, and full semantic-claim coverage. Unlinked UNKNOWN/unbound semantic
claims cannot be hidden behind a valid subset. A VALIDATED claim's domain
ClaimResult may still be UNKNOWN; validation never upgrades benefit truth.
Zero-claim identity-only evidence is representable but not initially reuse eligible.

PARTIAL/FAILED/mixed validation uses OUTCOME_ONLY with `Scope=null`, `Fields=[]`,
`Claims=[]`, even when the existing History assessment is COMPLETE/comparable.
AMBIGUOUS, NOT_FOUND and unsupported/partial adapter outcomes also use receipts;
they are not reuse eligible. NOT_FOUND remains identity absence, never ENDED.
A failed fetch has no captured HTML artifact: the narrow metadata-only exception
requires noncomplete/noncomparable History, SOURCE_FETCH_NOT_COMPLETE, no trusted
payload hash or supported format, unknown presence and no absence eligibility.
Deleting a mandatory scoped reference never activates that exception.

`BENEFIT_REUSE_DECISION` / BenefitReuseDecision version 2 preserves v1's fields
(ProcessingMode, ReusedFromObservationId, Capability, PreviousPayloadCheckpoint,
CurrentPayloadCheckpoint, InputMatch, ExecutionMatch, PayloadMatch,
RepositoryClean, PreviousComparable, ReuseApplied, ReasonCodes) and adds exactly
`OwnerObservationId,OwnerRunId,BusinessId,ScopedEvidenceReference`.
All match/clean/comparable/applied flags are true Boolean for an applied record;
capability POST_FETCH, processing mode REUSED_IDENTICAL_EVIDENCE, reason REUSE_ELIGIBLE.

Read-only relationship validators check supplied capture/previous/current records,
COMMITTED manifest membership/revision, four fingerprints, canonical E/S hashes,
scoped artifact hash, source and checkpoint identity, fresh observation identity
using the existing formula, and empty successful baseline-to-current comparison.
The immutable artifact remains owned by its capture run and source timestamp.
Later reuse requires the prior owned v2 proof; there is no recursive History walk.
The caller must obtain authentic manifests/observations/artifact bytes from the
existing audited History readers. These pure validators do not attest to caller-
constructed records or filesystem authenticity. After HTML removal, a persisted
receipt cannot independently re-prove membership in the original source; it
checks an immutable capture attestation, not a reconstructed/padded HTML document.

### Frozen descriptor candidates and compatibility

The classifier hashes two exact BenefitHistoryExecution v1 descriptors using the
existing serializer and matched manifest revision. All six version fields are
frozen at 1. Legacy Configuration is null; C-Lite Configuration is exactly
`{HtmlEvidenceRetentionProfile:'C_LITE_V1'}`. It never reverses a fingerprint.
Missing/unsupported configurations or revision mismatch return PROFILE_UNKNOWN,
not Legacy. Removing a scoped reference does not change the execution fingerprint,
so a C-Lite observation stays C-Lite and fails its artifact requirement.

A recognized descriptor is only a **profile candidate**, not execution/runtime
qualification or authorization to recover/reuse. Unknown historical configurations
remain readable through existing Core readers but cannot silently obtain trusted
C-Lite recovery. Legacy RAW references remain readable and immutable. The first
Legacy-to-C-Lite transition must recompute; no migration or RAW deletion is added.

### Limits and activation boundary

All size limits are UTF8 bytes unless explicitly UTF16: URL 2048; identifiers and
references 128 ASCII with existing patterns; timestamp 64 ASCII; hashes 64 lowercase
hex; header 256; decoded field 4096; combined header/value text 16384. At most 10
fields, 6 scoped claims, 16 candidate references, 8 identity codes, 32 reasons;
codes <=64 ASCII. These ceilings do not introduce new header aliases (current
HTML supports eight semantic fields and four benefit claim header families).
Canonical scoped/E/S artifacts are each <=65536 bytes, reuse audit <=16384, newly
prepared JSON payload total <=196608. BundleSize checks size only, not validity;
shape, source, linkage and byte/hash checks remain independently mandatory.

Oversized, forbidden or inconsistent evidence must fail before future Prepare;
never truncate semantic projections or persist only their valid subset. A consumed
one-shot GET/seal is not permission to retry after a retention failure. This PR
adds no persistence or execution integration and changes no Plan v1/v2, Inspector,
Review semantics, transport policy or History contract. An activation PR must
handle byte-verified store reads, exception/output leakage, pre-Prepare failure,
strict one-shot outcomes and current-path performance explicitly.

LiveHTTP=NOT_AUTHORIZED; ProductionAction=NONE; P4-3B=BLOCKED;
OCR dependency=NOT_APPROVED; Phase4=NOT_COMPLETE.

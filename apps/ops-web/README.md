# MILIMAP Ops Console (`apps/ops-web`)

개발자·운영자 전용 **내부 데이터 자동화 모니터링 및 수동 확인 웹 콘솔**입니다.
앱 사용자(장병)용 서비스가 아니며, `ProductionAction=NONE` 원칙을 유지한 채 자동 파이프라인이 애매하게 판정한 항목을 사람이 직접 확인하고 `BenefitReleaseApprovalLedger` (v1) JSON을 생성해 검증기(`tools/data/validate-benefit-release-approvals.ps1`)에 전달하는 용도입니다.

---

## 1. 주요 기능

1. **자동화 현황 대시보드 (`자동화 현황`)**
   - 번들 시드 기준선 (`seedVersion`, 총 건수, 지도 핀 커버리지)
   - 주간 공식 출처 드리프트 점검 결과 (`weekly-drift-summary.json` — 병무청, 동두천시, 파주시, 양주시)
   - Phase 5 검증 버킷 분포 (`DOMAIN_REVIEW`, `DIAGNOSTIC_HOLD`, `FAST_REVIEW`) 및 각 버킷별 수동 확인 화면 바로가기 버튼
2. **애매한 데이터 · 직접 확인 대기열 (`직접 확인 대기열`)**
   - “직접 확인이 필요합니다” 안내 문구와 사유 코드(`ReasonCodes`, `DiagnosticReasons`) 표시
   - **공식 출처 직접 확인 ↗** (http/https 안전 URL만 허용) 및 **네이버 지도에서 직접 확인 ↗** 링크 제공
   - 정본 CSV vs 최신 관측 결과 비교
   - `tools/data/lib/release/approval-release-contracts.ps1` 계약과 동일한 규칙으로 `BenefitReleaseApprovalLedger` (v1) 레코드 작성·내보내기

---

## 2. 로컬 실행 및 스냅샷 생성

### 스냅샷 JSON 생성 (선택 입력)
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/data/build-ops-dashboard-snapshot.ps1 `
  -WeeklyDriftSummaryJson "C:/path/to/weekly-drift-summary.json" `
  -ReviewQueueSummaryJson "C:/path/to/review-queue-summary.json" `
  -OutputJson "apps/ops-web/public/ops-snapshot.json"
```
(주간 드리프트/리뷰 큐 파일 없이 실행하면 `apps/android/app/src/main/assets/benefits.seed.manifest.json` 기준선만 담긴 스냅샷을 생성합니다. 대시보드 화면에서 JSON 파일을 직접 드래그 앤 드롭으로 불러올 수도 있습니다.)

### 개발 서버 실행 & 검증
```powershell
Set-Location apps/ops-web
npm.cmd install
npm.cmd run dev
npm.cmd run typecheck
npm.cmd run test
npm.cmd run build
```

### 내보낸 승인 원장 검증
대시보드에서 내려받은 `benefit-release-approval-ledger.json`을 검증기로 확인합니다:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/data/validate-benefit-release-approvals.ps1 `
  -HistoryRoot "C:/path/to/history-store" `
  -CanonicalCsvPath "data/canonical/capital-area-military-benefits.csv" `
  -CoordinateReviewCsvPath "data/canonical/reports/poi-coordinate-review-candidates-20261123-v14.csv" `
  -ApprovalLedgerJsonPath "C:/path/to/benefit-release-approval-ledger.json"
```

---

## 3. 무료 배포 및 개발자 전용 잠금 (Cloudflare Pages + Access)

1. **Cloudflare Pages 연결**
   - Git 저장소 연결 후 아래 설정 지정:
     - **Root directory:** `apps/ops-web`
     - **Build command:** `npm run build`
     - **Build output directory:** `dist`
     - (`public/_redirects`로 SPA 라우팅 폴백 처리, `wrangler.jsonc` 포함)
2. **Cloudflare Zero Trust Access로 개발자 전용 잠금 (50명까지 영구 무료)**
   - Cloudflare Dashboard → **Zero Trust** → **Access** → **Applications** → **Add an application (Self-hosted)**
   - 배포된 `<project>.pages.dev` (또는 커스텀 도메인) 등록
   - **Policy**에 `Allow` 규칙으로 팀 개발자 이메일/도메인 또는 GitHub 조직 멤버만 허용
   - 별도 로그인 서버나 인증 DB 코드 없이 외부 사용자의 무단 접근을 앞단에서 차단할 수 있습니다.

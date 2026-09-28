# 현재 상태

- 기준 브랜치: `dev`
- Phase 1 code baseline: `97d6070113196e922fb76af7508314b6eda8e7b7`
- Phase 2 Task 6 merge baseline: `d43c00ee07b471a55ed7ece4abecc1dc242ed8ce`
- Task 7 validation: Issue #43 / PR #50
- 데이터 기준 commit: `edca54d23981501efa8ce602df98f5456973940c`
- current dev baseline: `d40e479b2f9e2b39839f338ef11259f126840460` (P3-7 PR #108 merged)
- 기준일: 2026-09-28
- Phase 1 closeout evidence: [`docs/handover/2026-09-24-phase1-poi-shadow-validation.md`](handover/2026-09-24-phase1-poi-shadow-validation.md)

코드 baseline과 data baseline은 구분한다. Phase 3 history/review closeout은 `dev`에 병합됐고 release data는 수정하지 않았다. 구현 상태가 이 문서와 다르면 최신 `dev` 코드와 설정, 해당 Issue/Pull Request, 승인된 ADR 순으로 우선한다.

## 브랜치와 협업 상태

- `main`: 검증된 안정 버전
- `dev`: 기본 통합 개발 브랜치
- 구현 작업: 최신 `origin/dev`에서 Issue 전용 브랜치 생성
- 한 브랜치 = 한 Issue = 한 목적
- 병렬 작업: 별도 clone 또는 Git worktree 사용
- 병합 전: Issue 범위, diff, 필수 테스트/CI, 데이터 검증, 공용 파일 충돌 여부 확인
- Phase 1 Integration closeout: Issue #38 / PR #42 (`Closes #38`)

## 현재 구현된 Android MVP

현재 Android 앱은 `apps/android`에 있으며 다음 구조를 사용한다.

- namespace: `com.example.milipercent`
- applicationId: `com.example.militarybenefits`
- compileSdk / targetSdk: 37 / 37
- minSdk: 24
- Gradle runtime: JDK 17
- Java source/target: 11
- Room database: version 4
- migrations: `MIGRATION_1_2`, `MIGRATION_2_3`, `MIGRATION_3_4`
- Room entities: Benefit, SeedState, User, Favorite
- data flow: Repository -> ViewModel -> UiState -> Compose
- navigation: Discover, Saved, Account, Admin, BenefitDetail
- Naver Map 및 현재 위치: 구현됨
- MMA API 동기화: 구현됨
- 로그인/세션/찜/관리자 수동 혜택 관리: 로컬 MVP 구현됨
- bundled seed synchronization: 구현됨

## 현재 release 데이터 상태

P3 data baseline 기준이며 이번 closeout에서 변경하지 않았다.

- release candidates: 249
- exact map pins: 111
- coordinate-unconfirmed release candidates: 138
- latest-benefit-evidence 부족으로 release에서 보류된 canonical 행: 247
- bundled seed version: 7

## Phase 1 POI Verification Core / Shadow Mode

Phase 1 A/B/C, Integration Shadow runner, candidate diagnostics/provenance가 `dev`에 병합됐고 validation evidence를 완료했다.

- initial operational smoke: 6 rows, 23 provider queries, `PARTIAL` / `FAILED` 0, GREEN / YELLOW / RED = 2 / 2 / 2
- representative operational sample: 24 rows, 100 provider queries, discovery/evaluation `COMPLETE` 24 / 24, `ProductionAction=NONE` 24 / 24, 72 artifacts
- representative run에서 canonical / seed / apps diff: 0
- Sample A unresolved workload: GREEN / YELLOW / RED = 5 / 7 / 6; small stratified sample weighted GREEN estimate 약 24.4%, deep manual review estimate 약 75.6%
- Sample B positive controls: candidate discovery 6 / 6, GREEN / YELLOW / RED = 3 / 3 / 0
- Sample A GREEN human audit: SUPPORTED 5, AMBIGUOUS 0, CONFLICT 0

Phase 1은 POI identity/location verification만 다룬다. GREEN은 automatic production approval이 아니며, RED는 폐업 또는 혜택 종료를 뜻하지 않는다. 혜택의 현재 유효성은 별도 검증 범위다.

## Phase 2 Benefit Verification Core

Phase 2 provider-neutral Core는 현재 공식 HTML, MMA JSONP, XLSX source-family 범위에서 Issue #92 / PR #93 closeout까지 완료했다. 아래 2026-09-24 smoke는 과거 관측이며, 현재-code fixed-12 live replay가 아니다.

- Contract v1: 구현/테스트 완료
- existing-source-first fetch/discovery boundary: 구현/테스트 완료
- source qualification / business binding: 구현/테스트 완료
- scoped HTML, MMA JSONP, XLSX row/cell provenance: 구현/테스트 완료
- Evidence Validation: 구현/테스트 완료
- claim comparison / deterministic BenefitState + ReviewClass: 구현/테스트 완료
- Shadow Mode orchestration / metrics / diagnostics / protected export: 구현/테스트 완료
- Golden safety fixture: Task 7 추가

2026-09-24 live existing-source smoke:

| row | source | fetch | officiality | binding | extraction | state | review |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 5 | MMA / 투오프커피 | COMPLETE | VERIFIED_OFFICIAL | AMBIGUOUS | FAILED | NEEDS_VERIFICATION | YELLOW |
| 75 | Paju / 두둑한한판 | COMPLETE | VERIFIED_OFFICIAL | AMBIGUOUS | FAILED | NEEDS_VERIFICATION | YELLOW |
| 118 | DDC / 개성연출 | COMPLETE | VERIFIED_OFFICIAL | AMBIGUOUS | COMPLETE | NEEDS_VERIFICATION | RED |
| 339 | Yangju / 거시기닭갈비 | COMPLETE | VERIFIED_OFFICIAL | AMBIGUOUS | FAILED | NEEDS_VERIFICATION | YELLOW |
| 280 | Suwon PDF / 고려이발관 | COMPLETE | VERIFIED_OFFICIAL | AMBIGUOUS | FAILED | NEEDS_VERIFICATION | YELLOW |

- fetch COMPLETE 5 / 5
- VERIFIED_OFFICIAL 5 / 5
- GREEN / YELLOW / RED = 0 / 4 / 1
- `ENDED` 0
- `ProductionAction=NONE` 5 / 5
- external request count = 5

이 결과는 small operational smoke이며 population precision/recall 또는 247 hold 대표성의 근거가 아니다. DDC는 페이지 fetch와 structured extraction이 성공했지만 복수 업소의 claim이 한 canonical row 비교에 함께 들어가 `SOURCE_CONFLICT + RED`가 발생했다. 이는 false-GREEN이 아니라 보수적 fail-closed 결과지만, 후속 adapter의 row-scoped extraction 개선 대상이다.

Phase 2 `COMPLETE`는 구현된 HTML/MMA JSONP/XLSX core의 bounded closeout만 뜻한다. [Phase 2 closeout](handover/2026-09-26-phase2-benefit-verification-closeout.md)의 fixed-12는 authoritative evidence matrix이며 current-code live replay는 `NOT_RUN_NO_REPLAYABLE_RAW_CAPTURE`다. Observed real-source GREEN 0건으로 GREEN human audit은 `NOT_APPLICABLE`이다. PDF/HWP/OCR, SNS/blog, general discovery, full 247-row validation은 별도 후속 범위다.

## Phase 3 Snapshot / Incremental Change Detection

P3-0~P3-6은 PR #96/#98/#100/#102/#104/#106으로, P3-7은 PR #108로 `dev`에 병합됐다. P3-7은 pure ReviewItem routing, COMMITTED authority 기반 read-only audit scanner, A/B/C representative validation을 제공한다. 2026-09-28 local verification은 data suite 56/56 PASS, Android unit 99 tests(0 failures/errors, 1 skipped), lint 0 errors/25 warnings, debug build PASS다. PR #108 최종 HEAD와 merge commit `d40e479b2f9e2b39839f338ef11259f126840460`의 post-merge CI run #209에서 `verify-data`와 `verify`가 모두 성공했다. Issue #107과 parent Issue #94도 완료되어 bounded Phase 3 closeout은 `COMPLETE`다. 이는 population/current-state validation을 뜻하지 않는다. 근거는 [Phase 3 closeout](handover/2026-09-27-phase3-snapshot-incremental-closeout.md)에 있다.

## 서버·iOS 상태

- `services/api`: 책임 영역만 마련되어 있으며 실제 서버 구현 방식은 Pending
- `packages/contracts`: 향후 공용 계약 영역이며 현재 서버 API 계약 확정 전
- iOS: 구현 전
- 운영 DB 종류/공간 인덱스/배포 구조: 승인된 결정 없음

## 알려진 제약과 위험

- Android의 `local.properties` 값은 Git에는 들어가지 않지만 일부 BuildConfig 값은 APK에서 추출 가능하므로 공개 배포 전 API-key 노출 위험을 별도 Issue로 해결해야 한다.
- 이번 P3-7 closeout에서는 실기기/emulator instrumentation 및 androidTest APK 빌드를 실행하지 않았다. Android 검증 범위는 unit/lint/debug build다.
- 정확 지도 핀이 없는 138건은 잘못된 좌표를 추정하지 않고 위치 미확정 상태를 유지한다.
- 최신 혜택 근거 부족 247건은 좌표 검증과 별개의 혜택 재검증 대상이다.
- Phase 1 operational sample은 작고 unresolved workload가 파주시 중심이다.
- positive controls 3 / 6이 YELLOW여서 matcher recall 및 fast-review efficiency 개선 여지가 있다.
- provider 결과는 2026-09-24 시점 observation이다.
- 2026-09-24 Phase 2 smoke의 공식 source fetch 5/5와 `NEEDS_VERIFICATION` 5/5는 당시 관측이다; 이후 scoped adapter 구현을 평가하는 현재 수치가 아니다.
- PDF/HWP/OCR, SNS/blog와 general discovery는 아직 fail-closed 후속 범위이며, XLSX는 승인된 row/cell 경로에서만 지원한다.
- Phase 3는 full 496-row 현재 상태 검증, scheduler, Location provider-fetch reduction, 자동 MOVED/CLOSED/ENDED, product DB persistence, human adjudication 완료를 뜻하지 않는다.

## 다음 우선순위

1. Phase 3 이후 product/UX 작업은 별도 설계·Issue로 시작한다.
2. PDF/HWP/OCR, SNS/blog, general discovery, periodic execution은 각각 별도 승인 범위로 다룬다.
3. `ProductionAction=NONE`, canonical/seed/apps 자동 수정 금지, GREEN human approval 경계를 유지한다.

기술 사항이 확정되지 않은 항목은 `Pending`이며 이 문서만으로 승인된 아키텍처 결정으로 간주하지 않는다.

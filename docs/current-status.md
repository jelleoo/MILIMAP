# 현재 상태

- 기준 브랜치: `dev`
- Phase 1 code baseline: `97d6070113196e922fb76af7508314b6eda8e7b7`
- Phase 2 Task 6 merge baseline: `d43c00ee07b471a55ed7ece4abecc1dc242ed8ce`
- Task 7 validation: Issue #43 / PR #50
- 데이터 기준 commit: `edca54d23981501efa8ce602df98f5456973940c`
- 기준일: 2026-09-24
- Phase 1 closeout evidence: [`docs/handover/2026-09-24-phase1-poi-shadow-validation.md`](handover/2026-09-24-phase1-poi-shadow-validation.md)

코드 baseline과 data baseline은 구분한다. 이번 closeout은 Phase 1 구현과 Shadow validation evidence를 기록하는 docs-only 변경이며 release data를 수정하지 않는다. 구현 상태가 이 문서와 다르면 최신 `dev` 코드와 설정, 해당 Issue/Pull Request, 승인된 ADR 순으로 우선한다.

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

## Phase 2 Benefit Verification Core Foundation

Phase 2 provider-neutral Core는 Task 1~6에서 구현됐고 Task 7에서 Golden safety와 existing-source smoke를 검증한다.

- Contract v1: 구현/테스트 완료
- existing-source-first fetch/discovery boundary: 구현/테스트 완료
- source qualification / business binding: 구현/테스트 완료
- deterministic HTML/CSV extraction + injectable free-text/PDF/XLSX boundary: 구현/테스트 완료
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

### Phase 2가 아직 COMPLETE가 아닌 이유

다음 항목은 별도 승인/구현/검증이 필요하다.

- general official-source discovery provider
- LLM/free-text extraction provider
- PDF text extraction adapter/dependency
- XLSX parsing adapter/dependency
- 247 hold 중심 representative validation
- positive controls
- human GREEN audit

따라서 Issue #43의 Core Foundation closeout과 roadmap Phase 2 COMPLETE는 구분한다.

## 서버·iOS 상태

- `services/api`: 책임 영역만 마련되어 있으며 실제 서버 구현 방식은 Pending
- `packages/contracts`: 향후 공용 계약 영역이며 현재 서버 API 계약 확정 전
- iOS: 구현 전
- 운영 DB 종류/공간 인덱스/배포 구조: 승인된 결정 없음

## 알려진 제약과 위험

- Android의 `local.properties` 값은 Git에는 들어가지 않지만 일부 BuildConfig 값은 APK에서 추출 가능하므로 공개 배포 전 API-key 노출 위험을 별도 Issue로 해결해야 한다.
- 실기기/emulator instrumentation은 P3 PR에서 실행하지 않았고 androidTest APK 컴파일/생성까지만 확인했다.
- 정확 지도 핀이 없는 138건은 잘못된 좌표를 추정하지 않고 위치 미확정 상태를 유지한다.
- 최신 혜택 근거 부족 247건은 좌표 검증과 별개의 혜택 재검증 대상이다.
- Phase 1 operational sample은 작고 unresolved workload가 파주시 중심이다.
- positive controls 3 / 6이 YELLOW여서 matcher recall 및 fast-review efficiency 개선 여지가 있다.
- provider 결과는 2026-09-24 시점 observation이다.
- Phase 2 live smoke에서 공식 source fetch는 5/5 성공했지만 모든 sample이 NEEDS_VERIFICATION으로 남아 현재 adapter/binding recall이 낮다.
- DDC structured HTML은 한 페이지의 복수 업소 claim을 row-scoped로 제한하지 못해 conservative SOURCE_CONFLICT가 발생할 수 있다.
- unsupported free-text/PDF/XLSX는 승인된 adapter가 생길 때까지 fail-closed가 정상 동작이다.

## 다음 우선순위

1. PR #50에서 Task 7 Golden + docs + final deterministic CI를 검토하고 Issue #43 Core Foundation closeout 조건을 확인한다.
2. discovery/search, LLM/free-text, PDF/XLSX adapter는 새 외부 provider/dependency가 필요한 경우 별도 승인 후 작은 Issue/PR로 진행한다.
3. adapter가 준비된 뒤 247 hold 중심 representative validation + positive controls + human GREEN audit를 수행한다.
4. 이 후속 validation 전에는 roadmap Phase 2를 COMPLETE로 표시하지 않는다.

기술 사항이 확정되지 않은 항목은 `Pending`이며 이 문서만으로 승인된 아키텍처 결정으로 간주하지 않는다.

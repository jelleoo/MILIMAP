# 현재 상태

- 기준 브랜치: `dev`
- 기준 commit: `edca54d23981501efa8ce602df98f5456973940c`
- 기준일: 2026-09-10
- 기준 이벤트: P3 POI 좌표 검증 PR #21 병합

이 문서는 현재 저장소 상태를 요약합니다. 구현 상태가 이 문서와 다르면 최신 `dev` 코드와 설정, 해당 Issue/Pull Request, 승인된 ADR 순으로 우선합니다. 현재 진행 중인 작업은 `docs/current-work.md`를 봅니다.

## 브랜치와 협업 상태

- `main`: 검증된 안정 버전
- `dev`: 기본 통합 개발 브랜치
- 구현 작업: 최신 `origin/dev`에서 Issue 전용 브랜치 생성
- 한 브랜치 = 한 Issue = 한 목적
- 병렬 작업: 별도 clone 또는 Git worktree 사용
- Issue의 수정 예정 경로를 파일 예약 경계로 사용
- 공용 핵심 파일: Issue에 지정한 통합 담당자 한 명만 수정
- 교차 리뷰: 기본 필수 gate가 아니며 Issue에서 요구할 때만 필수
- 병합 전: Issue 범위, diff, 필수 테스트/CI, 데이터 검증, 공용 파일 충돌 여부 확인

## 현재 구현된 Android MVP

현재 Android 앱은 `apps/android`에 있으며 다음 구조를 사용합니다.

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

P3 병합 직후 기준:

- release candidates: 249
- exact map pins: 111
- coordinate-unconfirmed release candidates: 138
- latest-benefit-evidence 부족으로 release에서 보류된 canonical 행: 247
- bundled seed version: 7

P2/P3에서 이미 사람 검토를 거쳤지만 좌표가 확정되지 않은 보류·반려는 23건이며, 그 외 새 우선순위 검증 대상은 115건입니다. 이 115건을 다시 대규모 수동 검증으로 바로 처리하지 않고, Phase 1 POI Verification Core를 먼저 구현해 수동 P1/P2/P3 결과를 Golden Dataset으로 활용하는 방향이 현재 계획입니다.

## 현재 데이터 검증 방향

장기 목표는 단순 좌표 채우기가 아니라 다음 상태를 독립적으로 검증하고 추적하는 것입니다.

- Business Identity
- current Location / POI
- current Military Benefit
- source/evidence
- explicit validity period when known
- change over time

Phase 1은 `POI Verification Core / Shadow Mode`입니다. 자동 검색·후보 수집·비교·분류·review queue 생성을 구현하되 canonical 또는 Android seed를 자동 승인/수정하지 않습니다.

전체 설계는 `docs/superpowers/specs/2026-09-10-benefit-business-verification-pipeline-design.md`를 따릅니다.

## 서버·iOS 상태

- `services/api`: 책임 영역만 마련되어 있으며 실제 서버 구현 방식은 Pending
- `packages/contracts`: 향후 공용 계약 영역이며 현재 서버 API 계약 확정 전
- iOS: 구현 전
- 운영 DB 종류/공간 인덱스/배포 구조: 승인된 결정 없음

## 알려진 제약과 위험

- Android의 `local.properties` 값은 Git에는 들어가지 않지만 일부 BuildConfig 값은 APK에서 추출 가능하므로 공개 배포 전 API-key 노출 위험을 별도 Issue로 해결해야 합니다.
- 실기기/emulator instrumentation은 P3 PR에서 실행하지 않았고 androidTest APK 컴파일/생성까지만 확인했습니다.
- 정확 지도 핀이 없는 138건은 잘못된 좌표를 추정하지 않고 위치 미확정 상태를 유지합니다.
- 최신 혜택 근거 부족 247건은 좌표 검증과 별개의 혜택 재검증 대상입니다.

## 다음 우선순위

1. Benefit Business Verification Pipeline 공통 설계와 협업 기준을 최신 `dev`에 고정
2. `docs/current-work.md`를 팀원/Codex 공통 진입점으로 운영
3. Phase 1 공통 입력·출력 Contract 확정
4. Phase 1을 독립 Workstream 3개로 분리한 구현 Issue 생성
5. 세 명이 최신 `dev`에서 독립 브랜치로 병렬 개발
6. Integration Owner가 Shadow Mode pipeline을 조립하고 P1/P2/P3 ground truth로 검증
7. 검증 결과에 따라 남은 좌표 미확정군 처리 정책을 후속 Issue에서 결정

기술 사항이 확정되지 않은 항목은 `Pending`이며 이 문서만으로 승인된 아키텍처 결정으로 간주하지 않습니다.

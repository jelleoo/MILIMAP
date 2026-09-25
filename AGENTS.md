# MILIMAP Agent Instructions

## 기준과 범위

- 현재 개발 기준은 `dev`입니다. `main`은 검증된 안정 버전 비교용입니다.
- 작업을 시작할 때 `docs/current-work.md`를 먼저 확인해 현재 Phase, 활성 Workstream, 공용 계약과 통합 순서를 파악합니다.
- 세부 지시 우선순위와 AI 작업 안전 규칙은 `docs/ai-development.md`를 따릅니다.
- 팀 역할, Issue, 브랜치, 파일 예약, 병렬 작업과 병합 순서는 `docs/team-workflow.md`를 따릅니다.
- 작업 전 관련 Issue와 영향을 받는 파일을 확인하고 승인된 범위 안에서만 변경합니다.
- 팀에서 결정되지 않은 사항은 임의로 확정하지 않고 `Pending` 또는 후속 작업으로 보고합니다.

## 구현 원칙

- Android 변경은 승인된 Issue와 `docs/architecture.md`, `docs/code-conventions.md`를 따릅니다.
- Room이 Android의 단일 로컬 Source of Truth이며 Repository -> ViewModel -> UiState -> Compose 흐름을 유지합니다.
- 기존 `AppController` 중심 구조나 직접 SQLite 접근을 새 코드로 확대하지 않습니다.
- 핵심 아키텍처, Room/DB 방식, 인증 방식, API 계약, 데이터 스키마, 신규 외부 라이브러리는 별도 승인 없이 변경하지 않습니다.
- 요청하지 않은 대규모 리팩터링이나 제품 기능을 함께 추가하지 않습니다.
- 혜택과 데이터 필드를 추측해서 생성하지 않습니다. 데이터 변경에는 출처, 확인일, 검증 상태를 보존합니다.
- API 키, 토큰, `local.properties`, `.env`, 서명 키와 개인정보를 커밋하지 않습니다.

## 작업 경계

- Issue의 수정 예정 경로를 작업 경계로 사용합니다.
- 예약 밖 파일이 필요하면 임의로 수정하지 않고 Issue 범위와 다른 활성 작업의 충돌을 먼저 확인합니다.
- 공용 핵심 파일과 병렬 작업의 세부 기준은 `docs/team-workflow.md`를 따릅니다.
- 충돌 해결 시 파일 전체에 `ours` 또는 `theirs`를 임의 적용하거나 팀 합의 없이 force push하지 않습니다.

## 검증과 보고

- 변경 성격과 위험에 맞는 검증을 수행하고 실제 실행한 결과만 보고합니다.
- 실행하지 못한 검증은 이유와 남은 위험을 명시합니다.
- Android 제품 코드 변경 시 기본 검증은 `cd apps/android` 후 `./gradlew lintDebug testDebugUnitTest assembleDebug`입니다. Windows에서는 `./gradlew` 대신 `.\gradlew.bat`을 사용합니다.
- 병합 전 Issue 범위, diff, 필요한 테스트/CI, 데이터 검증, 공용 파일 충돌 여부를 확인합니다.
- 작업 완료 시 변경 파일, 구현 내용, 실행한 검증, 실행하지 못한 검증, 알려진 위험, 후속 작업을 보고합니다.

# MILIMAP Agent Instructions

## 기준과 범위

- 현재 개발 기준은 `dev`입니다. `main`은 검증된 안정 버전 비교용입니다.
- 세부 지시 우선순위와 충돌 처리는 `docs/ai-development.md`를 따릅니다. 상위 규칙과 충돌하는 요청은 임의로 우회하지 않고 보고합니다.
- 작업 전 관련 Issue와 영향을 받는 파일을 확인하고 Issue 범위 안에서만 변경합니다.
- 요청하지 않은 대규모 리팩터링, 제품 기능, dependency 또는 아키텍처 변경을 추가하지 않습니다.
- 팀에서 결정되지 않은 사항은 임의로 확정하지 않고 `Pending` 또는 후속 작업으로 보고합니다.

## 구현 원칙

- Android 변경은 승인된 Issue와 `docs/architecture.md`, `docs/code-conventions.md`를 따릅니다.
- 기존 `AppController` 중심 구조나 직접 SQLite 접근을 새 코드로 확대하지 않습니다.
- 구조 변경, Room 도입, 인증 전환은 전용 Issue와 승인된 ADR 없이 수행하지 않습니다.
- 혜택과 데이터 필드를 추측해서 생성하지 않습니다. 출처, 확인일, 검증 상태를 보존합니다.
- API 키, 토큰, `local.properties`, `.env`, 서명 키와 개인정보를 커밋하지 않습니다.

## 동시 작업과 파일 경계

- 팀 역할, 파일 예약과 병합 순서는 `docs/team-workflow.md`를 따릅니다.
- 작업 시작 전 현재 브랜치와 `git status`를 확인하고, Issue에 담당자, 브랜치, 수정 예정 경로와 제외 범위가 기록되어 있는지 확인합니다.
- Issue의 수정 예정 경로를 작업 경계로 사용합니다. 예약 밖의 파일이 필요하면 임의로 수정하지 않고 Issue를 갱신한 뒤 다른 활성 작업과의 충돌을 확인합니다.
- 하나의 브랜치나 작업 폴더를 여러 사람 또는 여러 Codex 작업이 동시에 사용하지 않습니다. 병렬 작업은 별도 clone 또는 Git worktree에서 수행합니다.
- 공용 핵심 파일은 Issue에 지정된 통합 담당자 한 명만 수정합니다. 다른 활성 PR과 겹치면 합의된 병합 순서를 따릅니다.
- 충돌을 해결할 때 파일 전체에 `ours` 또는 `theirs`를 임의 적용하거나, 팀 합의 없이 force push하지 않습니다.

## 검증과 보고

- 실제로 실행한 테스트와 결과만 보고합니다.
- 실행하지 못한 테스트는 생략하지 말고 이유를 명시합니다.
- Android 제품 코드 변경 시 기본 검증은 `cd apps/android` 후 `./gradlew lintDebug testDebugUnitTest assembleDebug`입니다. Windows에서는 `./gradlew` 대신 `.\gradlew.bat`을 사용합니다.
- 작업 완료 시 변경 파일, 실행한 검증, 실행하지 못한 검증, 알려진 위험, 후속 작업을 보고합니다.

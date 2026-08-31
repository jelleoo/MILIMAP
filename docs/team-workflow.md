# 팀 작업 경계와 Codex 운영

이 문서는 세 명의 팀원이 Codex를 동시에 사용하더라도 같은 브랜치나 파일을 중복 수정하지 않도록 작업 경계와 병합 순서를 정의합니다.

## 기본 역할

역할은 기본 책임을 뜻하며 영구적인 독점 권한이 아닙니다. 다른 영역을 작업할 때는 Issue에서 담당자와 리뷰어를 명시적으로 변경합니다.

| 영역 | 초기 주 담당 | 책임 | 기본 경로 |
| --- | --- | --- | --- |
| 제품·디자인·QA | `@jelleoo` | Figma, 사용자 흐름, 화면 상태, 문구, 완료 조건, 디자인 QA | `docs/design/**` |
| Android 클라이언트 | `@ilwoo-maker` | Compose, 지도·위치, ViewModel, API 연결, 로컬 저장소와 기기 검증 | `apps/android/**` |
| 서버·데이터 | `Pending` | API, DB, 공공 API 수집, 데이터 검증과 배포 | `services/api/**`, `data/**`, `tools/data/**`, `infra/**` |

공동 계약인 `packages/contracts/**`는 서버·데이터 담당자가 제안하고 Android 담당자가 소비자 관점에서 검토합니다. 세 번째 팀원의 GitHub ID가 확정될 때까지 서버·데이터 경로의 리뷰는 `@jelleoo`와 `@ilwoo-maker`가 임시로 담당합니다.

## 작업 시작 조건

모든 구현 작업은 다음 조건을 만족한 뒤 시작합니다.

1. Issue에 담당자 한 명과 교차 리뷰어 한 명이 지정되어 있습니다.
2. Issue에 브랜치 이름, 작업 영역, 수정 예정 경로와 수정하지 않을 경로가 기록되어 있습니다.
3. 다른 `In Progress` Issue가 같은 파일을 예약하지 않았는지 확인합니다.
4. 최신 `origin/dev`에서 Issue 전용 브랜치를 만듭니다.
5. Codex에는 Issue 번호, 허용 경로, 제외 범위와 완료 조건을 함께 전달합니다.

한 사람은 원칙적으로 구현 Issue 하나만 `In Progress`로 둡니다. 리뷰와 작은 문서 보완은 예외로 할 수 있습니다.

## 파일 예약

Issue의 `수정 예정 경로`는 해당 작업의 파일 예약 목록입니다. 경로는 가능한 한 파일 단위로 적고, 새 파일은 예상 디렉터리와 이름을 적습니다.

작업 중 예약되지 않은 파일의 변경이 필요해지면 다음 순서로 처리합니다.

1. 변경 이유와 영향을 확인합니다.
2. 다른 작업이 해당 파일을 예약했는지 확인합니다.
3. Issue의 예약 목록을 갱신하고 관련 담당자에게 알립니다.
4. 충돌이 없음을 확인한 뒤 수정합니다.

단순히 빌드를 통과시키기 위해 다른 담당자의 파일을 함께 정리하거나 재작성하지 않습니다.

## 공용 핵심 파일

다음 경로는 여러 기능이 모이기 쉬운 공용 핵심 파일입니다.

- `apps/android/app/src/main/java/com/example/militarybenefits/MilitaryBenefitApp.kt`
- `apps/android/app/src/main/java/com/example/militarybenefits/AppController.kt`
- `apps/android/app/src/main/java/com/example/militarybenefits/data/Models.kt`
- `apps/android/app/src/main/java/com/example/militarybenefits/data/BenefitDatabase.kt`
- `apps/android/app/src/main/AndroidManifest.xml`
- Android Gradle 설정 파일
- `packages/contracts/**`
- 향후 navigation, DB schema와 migration 파일

공용 핵심 파일은 동시에 하나의 활성 PR만 수정합니다. Issue에 `공용 파일 통합 담당자`와 먼저 병합할 PR을 적습니다. 다른 작업은 가능하면 새 파일과 안정된 인터페이스를 사용하고, 선행 PR이 병합된 뒤 최신 `dev`를 반영합니다.

## 브랜치와 작업 폴더

- 한 브랜치에는 한 Issue와 한 목적만 담습니다.
- 두 사람 또는 두 Codex 작업이 하나의 브랜치를 공유하지 않습니다.
- 하나의 로컬 작업 폴더에서 여러 Codex 작업을 동시에 실행하지 않습니다.
- 같은 컴퓨터에서 병렬 작업해야 하면 별도 clone 또는 Git worktree를 사용합니다.
- `main`과 `dev`에서 직접 구현하지 않습니다.

worktree 예시:

```powershell
git fetch origin
git worktree add ..\MILIMAP-issue-12 -b feature/android-issue-12 origin/dev
```

각 worktree의 `local.properties`와 로컬 비밀정보는 별도로 설정하며 저장소에 커밋하지 않습니다.

## 디자인, 계약과 구현 순서

화면과 API가 함께 필요한 기능은 다음 순서를 사용합니다.

```text
Issue와 완료 조건 합의
→ Figma의 READY 화면과 모든 상태 확정
→ API 요청·응답 계약 합의
→ packages/contracts 변경 먼저 병합
→ Android mock 구현과 서버 구현 병렬 진행
→ dev에서 통합 및 실기기 검증
```

Figma는 성공 화면뿐 아니라 로딩, 빈 결과, 네트워크 오류, 권한 거부와 인증 필요 상태를 포함합니다. 구현 시작 뒤 디자인이 바뀌면 Figma만 수정하지 않고 Issue에 변경 내용과 영향을 기록합니다.

## 동기화와 충돌 처리

PR을 Ready for review로 바꾸기 전에 최신 `dev`를 반영하고 검증합니다. 초보 팀의 기본 방식은 강제 push가 필요하지 않은 merge입니다.

```powershell
git fetch origin
git merge origin/dev
```

공용 핵심 파일에서 충돌이 발생하면 Codex가 임의로 `ours` 또는 `theirs` 전체를 선택하지 않습니다. 브랜치 담당자가 양쪽 Issue의 목적을 확인하고 해결하며, 판단이 필요한 경우 사람에게 중단 보고합니다. `--force`와 `--force-with-lease` push는 팀 합의 없이 사용하지 않습니다.

## 리뷰와 병합

- PR 작성자는 자신의 PR을 승인하지 않습니다.
- 최소 한 명의 다른 팀원이 Issue 완료 조건, 파일 경계, 사용자 영향과 실제 검증 결과를 확인합니다.
- Android 결과는 제품·디자인 담당자가 화면과 흐름을, 서버·데이터 담당자가 계약과 데이터 영향을 추가로 확인할 수 있습니다.
- CI와 필수 리뷰가 끝난 PR만 `dev`에 병합합니다.
- 서로 의존하는 PR은 Issue에 합의한 순서대로 병합합니다.
- `dev`에서 `main`으로의 반영은 릴리스 PR로만 수행합니다.

## Codex 작업 요청 최소 형식

```text
Issue: #번호
담당 브랜치: feature/...
목표: ...
수정 허용: 정확한 파일 또는 경로
수정 금지: 다른 담당 영역과 공용 파일
완료 조건: ...
검증: ...

시작 전에 현재 브랜치, git status, Issue의 파일 예약 충돌을 확인한다.
허용 범위 밖의 변경이 필요하면 수정하지 말고 먼저 보고한다.
```

작업 완료 보고에는 변경 파일, 실행한 검증, 실행하지 못한 검증, 알려진 위험과 후속 작업을 포함합니다.

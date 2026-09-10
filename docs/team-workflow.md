# 팀 작업 경계와 Codex 운영

이 문서는 세 명의 팀원이 Codex를 동시에 사용하더라도 같은 브랜치나 파일을 중복 수정하지 않도록 작업 경계와 병합 순서를 정의합니다.

현재 활성 Phase와 Workstream은 `docs/current-work.md`를 먼저 확인합니다.

## 기본 원칙

- 역할은 영구적인 독점 권한이 아니라 현재 Issue 단위의 책임입니다.
- 한 브랜치 = 한 Issue = 한 목적을 기본으로 합니다.
- Issue는 작업 목적 단위로 나누고 commit은 진행 checkpoint 단위로 나눕니다.
- 한 사람이 원칙적으로 구현 Issue 하나만 `In Progress`로 둡니다.
- 교차 리뷰는 기본 필수 gate가 아닙니다. Issue가 명시적으로 요구할 때만 필수입니다.
- 리뷰를 생략하더라도 테스트, CI, diff, 데이터 검증, 공용 파일 충돌 검사는 생략하지 않습니다.

## 현재 역할 뼈대

| 영역 | 초기 주 담당 | 책임 | 기본 경로 |
| --- | --- | --- | --- |
| 제품·디자인·QA | `@jelleoo` | Figma, 사용자 흐름, 화면 상태, 문구, 완료 조건, 디자인 QA | `docs/design/**` |
| Android 클라이언트 | `@ilwoo-maker` | Compose, 지도·위치, ViewModel, API 연결, Room, 기기 검증 | `apps/android/**` |
| 서버·데이터 | `Pending` | 데이터 검증 파이프라인 및 향후 서버 영역 | `data/**`, `tools/data/**`, `services/api/**`, `infra/**` |

이 표는 기본 소유 영역이며 현재 Phase의 실제 분업은 `docs/current-work.md`와 해당 Issue가 우선합니다.

## 작업 시작 조건

모든 구현 작업은 다음 조건을 만족한 뒤 시작합니다.

1. 최신 `origin/dev`를 fetch합니다.
2. `AGENTS.md`와 `docs/current-work.md`를 읽습니다.
3. 자기 Issue의 목표, 범위, 제외 범위, 수정 예정 경로, 완료 조건을 확인합니다.
4. 다른 활성 Issue가 같은 파일을 예약하지 않았는지 확인합니다.
5. 최신 `origin/dev`에서 Issue 전용 브랜치를 만듭니다.
6. Codex에는 Issue 번호와 함께 허용 경로, 금지 경로, 완료 조건을 전달합니다.

## 파일 예약

Issue의 `수정 예정 경로`는 해당 작업의 파일 예약 목록입니다.

- 가능한 한 파일 또는 좁은 디렉터리 단위로 적습니다.
- 새 파일도 예상 디렉터리와 책임을 적습니다.
- 예약 밖 파일이 필요해지면 먼저 Issue 범위를 갱신하고 충돌 여부를 확인합니다.
- 단순히 빌드를 통과시키기 위해 다른 담당자의 파일을 함께 정리하거나 재작성하지 않습니다.

## 공용 핵심 파일

다음 유형은 공용 핵심 파일로 취급합니다.

- Android 의존성 조립 지점 (`MainActivity.kt` 등)
- navigation graph / route definitions
- `BenefitDatabase.kt`, migration, Room schema
- Android Gradle 및 Manifest
- `packages/contracts/**`
- canonical schema를 정의하거나 전역적으로 소비하는 코드
- 기존 데이터 orchestration entrypoint

공용 핵심 파일은 동시에 하나의 활성 구현 PR만 수정합니다. 병렬 Workstream이 공통 파일에 연결되어야 하면 각 모듈 PR을 먼저 병합하고, 별도 Integration Owner가 최신 `dev`에서 조립합니다.

## 브랜치와 작업 폴더

- `main`과 `dev`에서 직접 구현하지 않습니다.
- 두 사람 또는 두 Codex 작업이 하나의 브랜치를 공유하지 않습니다.
- 하나의 로컬 작업 폴더에서 여러 Codex 작업을 동시에 실행하지 않습니다.
- 같은 컴퓨터에서 병렬 작업하면 별도 clone 또는 Git worktree를 사용합니다.

예시:

```powershell
git fetch origin
git worktree add ..\MILIMAP-issue-XX -b feature/issue-XX origin/dev
```

각 worktree의 `local.properties`와 개인 비밀정보는 별도로 설정하며 커밋하지 않습니다.

## Contract-first 병렬 개발

여러 Workstream이 데이터를 주고받는 경우 구현 전에 공통 입력/출력 Contract를 고정합니다.

예를 들어 Phase 1 POI Verification Core에서는 다음 개념 계약을 먼저 확정합니다.

- `NormalizedBusiness`
- `PoiCandidate`
- `PoiMatchResult`

각 Workstream은 다른 모듈의 실제 구현을 기다리지 않고 fixture/mock 입력으로 독립 테스트할 수 있어야 합니다. 공통 Contract 변경이 필요하면 임의로 바꾸지 말고 관련 Issue와 `docs/current-work.md`에 영향을 기록한 뒤 조정합니다.

## 동기화와 충돌 처리

PR 병합 전 최신 `dev`를 반영하고 필요한 검증을 다시 실행합니다.

```powershell
git fetch origin
git merge origin/dev
```

공용 파일에서 충돌이 발생하면 Codex가 임의로 `ours` 또는 `theirs` 전체를 선택하지 않습니다. 두 Issue의 목적과 계약을 확인하고 통합 담당자가 해결합니다. 팀 합의 없이 `--force` 또는 `--force-with-lease` push를 사용하지 않습니다.

## 리뷰와 병합

교차 리뷰는 기본 필수 조건이 아닙니다. 다음 gate를 만족하면 Issue 정책에 따라 `dev` 병합을 진행할 수 있습니다.

- Issue 범위 밖 변경 없음
- 예약된 파일 경계 준수
- 필수 로컬 테스트 통과
- 해당되는 GitHub CI 통과
- 생성 데이터/정본/seed count 및 diff 검증 통과
- 미검증 데이터 또는 추측 데이터 없음
- 공용 핵심 파일 충돌 없음
- 실제 실행하지 않은 테스트를 통과했다고 보고하지 않음

핵심 아키텍처, DB 방식, 신규 외부 라이브러리, 인증 방식, API 계약, 데이터 스키마 변경은 리뷰 여부와 상관없이 사전 사용자 승인이 필요합니다.

서로 의존하는 PR은 Issue 또는 `docs/current-work.md`에 적힌 병합 순서를 따릅니다. `dev`에서 `main` 반영은 릴리스 목적 PR로 진행합니다.

## Codex 작업 요청 최소 형식

```text
Issue: #번호
담당 브랜치: feature/...
목표: ...
수정 허용: 정확한 파일 또는 경로
수정 금지: 다른 담당 영역과 공용 파일
완료 조건: ...
검증: ...

시작 전에 AGENTS.md, docs/current-work.md, 관련 설계 문서와 Issue를 읽는다.
현재 브랜치, git status, 최신 dev, 파일 예약 충돌을 확인한다.
작업 후 변경 파일, 구현 내용, 실행한 테스트, 실행하지 못한 테스트, 남은 위험, 다음 작업을 보고한다.
```

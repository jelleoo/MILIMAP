# 현재 상태

- 기준 브랜치: `dev`
- 기준 commit: `a675c6caf85a1431642d6d3b858e77d258baacf5`
- 기준일: 2026-08-20

이 문서는 현재 저장소에서 확인할 수 있는 상태를 요약합니다. 구현 상태가 이 문서와 다르면 최신 `dev` 코드와 해당 Issue, Pull Request, 승인된 ADR을 우선합니다.

## 브랜치와 협업 상태

- `main`: 검증된 안정 버전
- `dev`: 기본 통합 개발 브랜치
- 작업 브랜치: 최신 `dev`에서 분기하고 Pull Request를 통해 `dev`에 병합
- 안정 버전 반영: `dev`에서 `main`으로 향하는 Pull Request
- `main`과 `dev` 직접 commit/push 금지
- 공동개발 규칙은 `chore/collaboration-foundation` 작업에서 도입

## 현재 구현된 Android MVP

- Kotlin과 Jetpack Compose 기반 Android 앱
- 네이버 지도 SDK와 현재 위치 중심 탐색
- 병무청 나라사랑가게 OpenAPI 동기화 및 실패 시 내장 데이터 사용
- 검색, 카테고리 필터, Marker, 혜택 상세
- 수도권 seed 484건과 좌표 보유 데이터 339건을 현재 문서상 사용
- 기기 로컬 회원가입, 로그인, 찜과 관리자 CRUD

위 기능은 현재 MVP 동작에 대한 설명이며 운영 서비스에 적합하다는 의미는 아닙니다. 데이터 건수와 검증 상태는 별도 데이터 Issue에서 다시 대조해야 합니다.

## 알려진 제약

- Android 데이터 계층이 `SQLiteOpenHelper`에 직접 의존합니다.
- `AppController`가 화면 상태, 탐색, 인증, 데이터 접근 등 여러 책임을 가집니다.
- 로컬 `users` 테이블과 첫 계정 관리자 정책은 기기 단위 MVP 전용입니다.
- Room, Repository, ViewModel, UiState 기반 전환은 아직 구현되지 않았습니다.
- `src/test`, `src/androidTest`와 Room schema가 현재 저장소에 없습니다.
- 공공 API 키가 Android 빌드에 포함될 수 있어 공개 배포 전 서버 프록시가 필요합니다.
- 서버와 iOS는 책임 영역만 문서화되어 있고 구현되지 않았습니다.

## 다음 우선순위

1. 공동개발 문서, Issue/PR 템플릿과 소유권 기준 확정
2. 팀원의 실제 GitHub ID와 역할 확정
3. Android 목표 구조와 전환 범위를 Issue 및 ADR로 결정
4. 데이터 출처, 건수, 좌표와 재배포 조건 검증
5. 제품 코드 변경은 위 결정 이후 별도 Issue와 작은 PR로 진행

기술 사항이 확정되지 않은 항목은 `Pending`이며 이 문서만으로 승인된 아키텍처 결정으로 간주하지 않습니다.

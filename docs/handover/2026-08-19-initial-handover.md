# 2026-08-19 초기 인수인계

이 문서는 2026-08-19 인수인계 시점의 고정 스냅샷입니다. 이후 상태는 `docs/current-status.md`에서 갱신하며 과거 내용을 최신 사실처럼 자동 수정하지 않습니다.

## 저장소 기준

- Repository: `jelleoo/MILIMAP`
- 현재 개발 기준: `dev`
- 안정 버전: `main`
- 확인 기준 commit: `a675c6caf85a1431642d6d3b858e77d258baacf5`
- 작업 브랜치는 `dev`에서 만들고 Pull Request를 통해 `dev`에 병합
- `dev`에서 `main`으로의 반영도 Pull Request 사용
- `main`과 `dev` 직접 commit/push 금지

## 당시 구현 상태

- Android 네이티브 MVP, 지도와 현재 위치 탐색
- 병무청 나라사랑가게 OpenAPI 동기화와 내장 데이터 폴백
- 검색, 카테고리, Marker와 상세 화면
- 수도권 seed 484건, 이 중 좌표 보유 339건으로 문서화
- 기기 로컬 로그인, 찜과 관리자 기능
- 서버와 iOS는 구현 전

## 확인된 기술 제약

- Android 앱은 `SQLiteOpenHelper`와 `AppController`에 여러 책임이 집중되어 있습니다.
- 로컬 사용자 DB와 첫 계정 관리자 정책은 운영 인증으로 사용하지 않습니다.
- 앱에 포함되는 공공 API 키 구조는 공개 배포 전에 서버 프록시로 전환해야 합니다.
- Room, Repository, ViewModel, UiState 기반 전환 범위는 당시 확정되지 않았습니다.
- Android 자동 테스트 소스와 DB Migration 검증 기반이 부족합니다.

## 초기 역할

- `@jelleoo`: Map / UX, Repository 관리
- `@ilwoo-maker`: Android Core
- Data: 담당자의 실제 GitHub ID 확인 대기

역할은 초기 작업 분담 기준이며 영구적인 소유권이 아닙니다. 모든 주요 PR은 다른 영역 담당자의 교차 리뷰를 받을 수 있습니다.

## 확정하지 않은 항목

- Data 담당자의 GitHub ID
- 구체적인 Room 전환 범위와 순서
- 인증, 서버와 iOS 착수 시점
- namespace와 applicationId
- 병합 방식과 고위험 변경의 승인 인원
- 공개 저장소 라이선스
- seed 데이터의 공식 건수와 재배포 조건

미확정 항목은 후속 Issue와 ADR에서 결정하며 이 스냅샷만으로 승인된 결정으로 간주하지 않습니다.

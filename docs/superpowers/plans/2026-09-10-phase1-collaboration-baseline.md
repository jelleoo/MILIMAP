# Phase 1 Collaboration Baseline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** P3 이후 최신 `dev`를 기준으로 팀원과 Codex가 동일한 현재 상태, 데이터 정책, 아키텍처, 협업 규칙과 Phase 1 방향을 읽을 수 있게 문서 기준선을 정리한다.

**Architecture:** 제품 코드나 데이터 스키마는 변경하지 않는다. 최신 GitHub 코드/PR/ADR을 기준으로 현재 상태 문서를 교정하고, Benefit Business Verification Pipeline 설계와 `docs/current-work.md`를 `dev`의 공용 진입점으로 만든다.

**Tech Stack:** Markdown, GitHub Issues/PRs, existing Kotlin/Gradle and PowerShell repository structure

**Spec:** `docs/superpowers/specs/2026-09-10-benefit-business-verification-pipeline-design.md`

## Global Constraints

- 제품 코드, canonical/seed 데이터, Room schema, API 계약, 인증 방식, 신규 dependency를 변경하지 않는다.
- 현재 GitHub 코드/config > Issue/PR > 승인 ADR/docs > 과거 자료 순으로 판단한다.
- 데이터 수치는 P3 merged baseline과 대조한다.
- 교차 리뷰는 기본 필수 gate가 아니지만 테스트/CI/diff/data validation gate는 유지한다.
- Phase 1 실제 구현과 3개 구현 Issue 생성은 이번 작업 범위 밖이다.

---

### Task 1: P3 기준선 확정

**Files:**
- No product file changes

**Interfaces:**
- Consumes: PR #21 validated P3 result
- Produces: merged `dev` baseline

- [x] PR #21의 head SHA, local validation, GitHub CI, diff scope를 확인한다.
- [x] 잘못된 다음 단계 숫자 24를 23으로 정정한다.
- [x] 최신 사용자 결정에 따라 교차 리뷰 요청을 제거한다.
- [x] PR #21을 `dev`에 병합한다.

### Task 2: 현재 상태/정책 문서 갱신

**Files:**
- Modify: `README.md`
- Modify: `apps/android/README.md`
- Modify: `docs/current-status.md`
- Modify: `docs/data-policy.md`
- Modify: `docs/architecture.md`

**Interfaces:**
- Consumes: latest `dev` code, Room v4, seed v7, P3 counts
- Produces: current documentation consistent with repository reality

- [x] Room/SDK/feature 상태를 실제 코드와 대조한다.
- [x] P3 이후 249/111/138/247/seed v7 기준으로 데이터 설명을 갱신한다.
- [x] 서버 DB/PostGIS 등 승인되지 않은 장기 기술을 Pending으로 되돌린다.
- [x] 역사적 spec/plan 문서는 변경하지 않고 현재 상태 문서만 교정한다.

### Task 3: 팀 협업 진입점 갱신

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/team-workflow.md`
- Create: `docs/current-work.md`

**Interfaces:**
- Consumes: approved parallel-work direction
- Produces: clone 이후 팀원/Codex가 현재 작업을 찾는 entrypoint

- [x] `AGENTS.md`에서 `docs/current-work.md`를 첫 진입점으로 연결한다.
- [x] 교차 리뷰를 전역 필수 gate에서 제거한다.
- [x] Issue file reservation, independent branch/worktree, integration-owner rule을 유지한다.
- [ ] Phase 1 Workstream과 아직 생성되지 않은 구현 Issue 상태를 `docs/current-work.md`에 명시한다.

### Task 4: 공통 설계 최신 dev 반영

**Files:**
- Create: `docs/superpowers/specs/2026-09-10-benefit-business-verification-pipeline-design.md`

**Interfaces:**
- Consumes: draft PR #20 design + P3 ground truth
- Produces: current `dev`-compatible approved design baseline

- [ ] P3가 완료됐음을 반영한다.
- [ ] Golden Dataset에 P2/P3 승인/보류/반려 결과를 사용할 수 있음을 명시한다.
- [ ] Phase 1 Shadow Mode와 non-goals를 유지한다.

### Task 5: 최종 검증과 PR

**Files:**
- Documentation only

**Interfaces:**
- Consumes: all documentation updates
- Produces: one purpose-level docs PR ready for merge

- [ ] branch diff에 제품 코드/데이터 변경이 없는지 확인한다.
- [ ] current docs에서 Room v2, 미복구 Naver Map/login, 9 pins/240 no-coordinate 같은 폐기된 현재상태 문구가 남지 않았는지 확인한다.
- [ ] 문서 간 review policy와 Phase 1 설명이 일치하는지 확인한다.
- [ ] PR을 만들고 최종 diff를 확인한 뒤 `dev`에 병합한다.

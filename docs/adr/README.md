# Architecture Decision Records

ADR은 되돌리기 어렵거나 여러 영역에 영향을 주는 기술 및 데이터 결정을 기록합니다. 대화만으로 결정을 확정하지 않습니다.

## 상태

- `Proposed`: 검토 중이며 구현 기준이 아님
- `Accepted`: 팀이 승인하여 현재 기준으로 사용
- `Rejected`: 검토 후 채택하지 않음
- `Superseded`: 새 ADR로 대체됨

`Proposed` ADR을 구현 근거로 사용하거나 팀 합의 없이 `Accepted`로 변경하지 않습니다.

## 파일 이름

```text
NNNN-short-decision-title.md
```

번호는 기존 ADR 다음 순번을 사용합니다. 한 ADR에는 하나의 결정만 기록합니다.

## 기본 형식

```markdown
# ADR NNNN: 제목

- 상태: Proposed
- 날짜: YYYY-MM-DD
- 결정 참여자:

## 배경

## 고려한 선택지

## 결정

## 결과와 위험

## 후속 작업
```

ADR을 변경하거나 대체할 때 과거 기록을 삭제하지 않고 새 ADR에서 대체 관계를 연결합니다.

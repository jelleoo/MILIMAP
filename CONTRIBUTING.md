# 기여 가이드

## 기본 흐름

1. 최신 `main`에서 작업 브랜치를 만듭니다.
2. 한 브랜치에는 하나의 목적만 담습니다.
3. 로컬 검증을 통과시킨 뒤 Pull Request를 엽니다.
4. 최소 한 명의 리뷰 후 병합합니다.

브랜치 예시:

- `feature/android-favorites`
- `feature/api-benefits`
- `fix/android-map-permission`
- `data/seoul-cafe-verification`
- `docs/local-setup`

커밋 메시지는 `영역: 변경 요약` 형식을 권장합니다.

```text
android: 현재 위치 권한 흐름 추가
data: 마포구 카페 혜택 출처 갱신
docs: 네이버 지도 키 설정 보완
```

## Pull Request 체크리스트

- 변경 목적과 사용자 영향을 설명했는가?
- Android 변경이면 lint·test·assemble을 실행했는가?
- 새 환경변수는 예제 파일과 문서에만 추가했는가?
- 로그, 스크린샷, CSV에 비밀정보가 포함되지 않았는가?
- 혜택 데이터 변경에는 근거 출처와 확인일이 있는가?

## 데이터 품질 원칙

- 근거 없는 혜택을 생성하지 않습니다.
- 정확하지 않은 필드는 추측하지 않고 비워둡니다.
- 종료·변경 가능성이 있는 정보에는 `확인 필요` 상태를 사용합니다.
- 동일 업체는 정규화된 업체명과 주소를 기준으로 중복을 점검합니다.

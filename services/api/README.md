# API 서버

정식 서비스에서 인증, 혜택 검색, 찜, 관리자 CRUD, 공공데이터 동기화를 담당할 영역입니다. 현재 MVP는 Android 로컬 DB를 사용하므로 서버 코드는 아직 없습니다.

권장 시작 구성:

- Kotlin + Spring Boot
- PostgreSQL + PostGIS
- OpenAPI 기반 계약
- 관리자·사용자 권한 분리
- 병무청 API 주기 수집 및 주소 정규화
- Geocoding 결과 캐시와 혜택 최신성 작업

구현 전 `packages/contracts`에 엔드포인트와 오류 형식을 먼저 정의합니다.

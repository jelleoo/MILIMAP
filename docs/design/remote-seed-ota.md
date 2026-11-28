# Remote Seed OTA 운영 계약

이 계약은 승인된 Android 번들 시드의 배포를 GitHub Actions와 정적 HTTPS 호스팅으로 확장한다. Room v4와 `seed_state.benefits`는 기기의 설치 상태를 관리한다. 출처 점검과 검토 Issue는 `ProductionAction=NONE`을 유지한다.

## 공개 시드 설정

1. Cloudflare Pages Direct Upload 프로젝트 `milimap-data`를 만들고 production branch를 `dev`로 지정한다. 실제 주소가 `https://milimap-data.pages.dev`와 일치하는지 확인한다.
2. GitHub `public-benefit-seed` 환경을 만들고 배포 대상 브랜치를 보호된 `dev`로 제한한다. 환경에 `PUBLIC_BENEFIT_SEED_CLOUDFLARE_API_TOKEN`과 `PUBLIC_BENEFIT_SEED_CLOUDFLARE_ACCOUNT_ID`를 등록한다. Cloudflare Pages 쓰기 권한은 필요한 계정으로 제한한다.
3. 공개 릴리스 변경이 승인되고 배포 준비가 된 뒤 저장소 변수 `MILIMAP_PUBLIC_SEED_ENABLED=true`를 켠다. 첫 게시에는 `dev`에서 Deploy Public Benefit Seed를 `bootstrap=true`로 실행한다. 이 옵션은 매니페스트 HTTP 404에만 초기화를 허용한다.
4. 세 공개 JSON의 HTTP 상태와 캐시 헤더, 두 본문의 SHA-256, 기존 Ops 주소의 Zero Trust Access 상태를 확인한다. 공개 게시물에는 정본 CSV, 변경 리포트, 검토 원장, Ops 스냅샷을 포함하지 않는다.

루트의 `benefits.seed.manifest.json`은 재검증하며, 두 본문은 `/v/<seedVersion>/` 아래로 게시한다. 공개 디렉터리에 최신과 직전 버전의 본문을 둔다. 시드 경로는 한 번 게시하면 같은 버전으로 교체하지 않는다. `BUNDLED_SEED_VERSION`과 번들 매니페스트의 일치, 정본과의 정합성, 현 기준 데이터 검증의 고정 입력·기대값은 기존 Data PR 검증에 포함한다. 잘못된 시드는 마지막 정상 내용에 더 높은 버전을 부여하고 승인·머지해 복구한다.

## 주간 Ops 게시

월요일 04:00 KST에 GitHub 기본 브랜치 `dev`에서 실행한다. 주간 및 일반 Ops 작업은 같은 게시 잠금을 얻은 뒤 `dev`를 체크아웃하고 새 점검 결과를 생성한다. 유효한 점검 결과가 있을 때 Ops에 게시하며, 조회 실패가 있는 예약 실행은 게시를 시도한 뒤 Actions 상태를 실패로 기록한다. `include_live_drift=false` 수동 실행은 빌드 검증을 수행한다.

`MILIMAP_DRIFT_REVIEW_ISSUES=true`인 경우 주간 워크플로는 성공적으로 확인된 출처별 변경 묶음을 공개 본문에 안전한 출처 ID, 건수, 실행 링크로 요약한다. 이전에 처리한 동일 지문의 Issue는 새로 열지 않는다. Issue는 수동 승인과 릴리스 컷의 입력이다.

# 파주 공식 상세 혜택 경로 및 A1 재사용 가능성 조사

- **조사 Issue:** [#66](https://github.com/jelleoo/MILIMAP/issues/66)
- **조사 시각:** 2026-09-25 UTC
- **결론:** `NEW_CAPABILITY_REQUIRED`
- **범위:** 지정된 파주시 목록 3개와, 그 HTML에서 직접 확인된 군장병 할인 안내 및 신청서 첨부물만 한 단계씩 조사했다. 일반 웹 검색, SNS, 자동 크롤링, 인증 우회 및 파일 파싱은 하지 않았다.

## 기준선

- GitHub 기준선: `origin/dev@4e7504db9b1d7a2b9621fd8d052f01e1f9983032` (PR #65 병합 commit)
- 조사 branch/worktree: `codex/phase2-a2-paju-detail-probe`
- 현재 branch의 코드와 frozen A1 계약을 읽기 전용으로만 사용했다. canonical은 아래 두 control의 상호·도로명주소·전화번호 동일성 비교에만 사용했고, canonical/seed의 혜택 값은 조사 근거나 결과에 사용하지 않았다.

## 지정 entry 직접 캡처

세 요청은 모두 HTTPS `200`, 리디렉션 `0`, `text/html; charset=UTF-8`이었다. 아래 SHA-256은 임시 저장소의 직접 응답 body에 대한 값이며 raw 응답은 repository에 넣지 않았다.

| ID | 요청/최종 URL | UTC 관측 시각 | SHA-256 | 공식성·연결성 | 확인한 행 구조와 현재성 |
| --- | --- | --- | --- | --- | --- |
| PAJU-1001 | `https://www.paju.go.kr/user/soldier/BD_discountStoreList.do?q_ctgCd=1001` | `2026-09-25T10:54:03.8739853Z` | `06ac7d4644ae2214beab1ed1dfe9bffaead6a2fae2f66c4e5f0c2000fb13d020` | 사용자가 지정한 파주시(`paju.go.kr`) 공식 entry | 음식점 152행. 각 행은 연번·지역·업종·`업소명(할인현황)`·소재지·전화번호만 가지며, 행 링크·상세 식별자·할인 값은 없다. 렌더링된 기준일은 비어 있고, HTML 주석의 기준일 표기는 현재성 근거가 아니다. |
| PAJU-1002 | `https://www.paju.go.kr/user/soldier/BD_discountStoreList.do?q_ctgCd=1002` | `2026-09-25T10:54:04.1907437Z` | `13754f6231f2d717b9984f4d4e5006d9657be6c5ac53cab5db07b301466b705b` | 사용자가 지정한 파주시 공식 entry | 숙박업 16행. 위와 동일하게 상호·주소·전화 식별 정보만 있고 행별 할인 상세/링크/유효기간이 없다. |
| PAJU-1004 | `https://www.paju.go.kr/user/soldier/BD_discountStoreList.do?q_ctgCd=1004` | `2026-09-25T10:54:04.3931994Z` | `d16b0e9270ad540bf9379906f7046714680ea95d2677b628cd19f9595cd323c8` | 사용자가 지정한 파주시 공식 entry | 미용업 24행. 위와 동일하게 상호·주소·전화 식별 정보만 있고 행별 할인 상세/링크/유효기간이 없다. |

세 entry의 탭 URL에는 `q_ctgCd`라는 **업종** parameter만 있고, 사업자별 ID 또는 상세 endpoint로 이어지는 `<a>`, form action, data attribute, 군장병 할인 관련 XHR 호출은 발견되지 않았다. 페이지에 있는 검색/login 및 다른 사이트 공통 스크립트 호출은 이 혜택의 상세 경로가 아니므로 따라가지 않았다.

HTML 주석에는 `https://paju.noblapp.com`을 “파주시 스마트 전자지도”로 표기한 **주석 처리된** anchor가 있었다. 현재 DOM의 활성 링크가 아니므로 활성 직접 링크만 한 단계씩 확인한다는 조사 제한에 따라 요청하지 않았다. 이 주석은 현재 공식 상세 근거 또는 현재성 증거가 아니다.

## 직접 연결된 공식 리소스

목록 navigation의 활성 링크 `군장병 할인 안내`만을 한 단계 따라갔다. 이 안내 페이지는 같은 파주시 도메인의 공식 HTML이고 다시 목록 URL로 연결된다.

| ID | 요청/최종 URL | HTTP/형식/redirect | UTC 관측 시각·SHA-256 | 공식성·식별자 연결 | 혜택·현재성 필드와 한계 |
| --- | --- | --- | --- | --- | --- |
| PAJU-GUIDE | `https://www.paju.go.kr/www/www_02/health/health_03/health_03_09/health_03_09_01.jsp` | `200`; `text/html; charset=UTF-8`; `0` | `2026-09-25T10:55:52Z`; `8bc7e0bee877eb4b3f81b01d92835a19b694051576bc1fb4b3260559b6161ef3` | 목록에서 직접 연결된 `paju.go.kr` 공식 안내. 이 페이지는 목록을 다시 링크하고, “할인업소 197개소(음식점 152, 숙박업 16, 목욕장업 5, 미용업 24)”라고 집계한다. | 정책 수준으로 기간 `연중`, 대상 `관내 주둔 군장병 및 사회복무요원`, 내용 `10%이상 할인 또는 그에 상응하는 서비스 제공`을 제공한다. 개별 상호·주소·전화·사업자별 할인 조건·인증 방법·유효 종료일은 없다. 따라서 각 목록 행에 직접 귀속되는 상세 claim은 아니다. |
| PAJU-APPLICATION-HWPX | `https://www.paju.go.kr/webcontent/ckeditor/2026/9/21/cd7de2b2-4d91-4242-a175-ebe43afc067f.hwpx` | `200`; 응답 `Content-Type` 미제공; `0` | `2026-09-25T10:57:53.4145050Z`; `9ddb2341888b0fbeb7b0aeb3643bd53433cf7ba504547a51288fce8c1997a7ad` | 안내 페이지가 `군장병 할인업소 지정 신청서`로 직접 링크한 파주시 첨부물 | 신청용 HWPX다. 파일 파싱은 이번 Spike 제외 범위이며, URL/링크 label만으로 현행 개별 할인 근거가 되지 않는다. |
| PAJU-APPLICATION-PDF | `https://www.paju.go.kr/webcontent/ckeditor/2026/9/21/69a5c043-23c9-4a72-b00b-01c123625d3e.pdf` | `200`; `application/pdf`; `0` | `2026-09-25T10:57:53.5109739Z`; `ed1ad859e04210292ee0ccf25317010aa6605b5978d36e63be88130e6adf9fd8` | 동일 안내 페이지가 직접 링크한 신청서 PDF | 신청용 PDF다. PDF 파싱은 이번 Spike 제외 범위이며, URL/링크 label만으로 현행 개별 할인 근거가 되지 않는다. |

첨부물은 직접 링크됨을 기록하기 위해 메타데이터와 SHA-256만 확인했다. raw HWPX/PDF, HTML, header, cookie 또는 token은 repository에 저장하지 않았다.

## 독립 사업자 control

| Control | 공식 목록의 직접 식별 근거 | canonical identity-only 비교 | 공식 혜택 근거와 판정 |
| --- | --- | --- | --- |
| 음식점 `두둑한한판` | PAJU-1001의 첫 data 행: `두둑한한판` / `파주시 광탄면 보광로 646` / `031-949-7646` | 상호·도로명주소·전화번호 세 값의 정확 일치 1건 | PAJU-GUIDE의 197개소 집계 및 공통 정책에는 포함될 수 있으나, 이 상호를 언급하거나 개별 상세 혜택·조건·인증방법·종료일을 제공하지 않는다. |
| 숙박업 `게이트호텔` | PAJU-1002의 첫 data 행: `게이트호텔` / `파주시 광탄면 보광로 505` / `031-947-2888` | 상호·도로명주소·전화번호 세 값의 정확 일치 1건 | 위와 같다. 업종이 다른 두 control 모두 목록의 identity 행과 정책 페이지가 분리되어 있고, 사업자별 detail link가 없다. |

두 control의 정책 수준 관측값은 동일하다: 혜택 `10%이상 할인 또는 그에 상응하는 서비스 제공`, 대상 `관내 주둔 군장병 및 사회복무요원`, 기간 `연중`. 그러나 이를 두 사업자에 각각 확정하는 개별 source text, 사업자별 이용조건, 인증방법, 유효 종료일은 관측하지 못했다. 이 표는 canonical의 기존 혜택을 재사용하거나 보강하지 않는다.

## A1 재사용 판정

실제 직접 캡처를 read-only로 현재 A1에 넣은 결과는 다음과 같다.

| 단계 | PAJU-1001 / PAJU-1002 / PAJU-1004 / PAJU-GUIDE 결과 | 영향 |
| --- | --- | --- |
| `BenefitSourceDocument` | `200` HTML을 각각 문서로 표현할 수 있음 | fetch/source-document 경계는 재사용 가능 |
| `ConvertTo-BenefitHtmlObservation` | 모두 `AdapterStatus=UNSUPPORTED`, `ContentUnits=0`, diagnostics 0 | 목록 header `업소명 (할인현황)`은 frozen map의 정확한 `업소명`이 아니며, guide는 사업자명 필드가 없는 정책 표다. |
| `Find-BenefitBusinessEvidence` / slice | 실행 가능한 content unit이 없음 | identity slice를 만들 수 없음 |
| binding → extraction → validation → evaluation | 실행하지 않음 | observation/slice가 없는 상태에서 downstream을 호출하면 근거 없는 claim을 만들게 되므로 fail-closed로 중단함 |

또한 현재 A1 snapshot/document는 URL과 원문 하나를 함께 보존하고, 선택한 physical row의 cell provenance만 claim으로 추출한다. 파주에는 (1) 업체별 identity만 있는 목록과 (2) 집계·공통 정책만 있는 안내라는 서로 다른 두 원문이 있다. 기존 경로에는 이 둘을 “동일한 197개소 집단”이라는 근거로 결합하고, 결합 한계 및 두 URL의 provenance를 claim에 남기는 기능이 없다.

## 최종 판정 — `NEW_CAPABILITY_REQUIRED`

공식 파주시 상세 정책 source는 존재하며, 목록 및 안내의 업종별 수량은 `152 + 16 + 5 + 24 = 197`로 안내의 집계와 일치한다. 두 독립 control에서도 공식 목록의 사업자 identity는 확인했다. 따라서 공식 source 부재나 접근 실패 때문에 막힌 `BLOCKED_EVIDENCE`는 아니다.

그러나 `REUSE_PATH_IDENTIFIED`의 조건도 충족하지 않는다. 현재 A1은 실제 캡처에서 observation 단계가 `UNSUPPORTED`이고, 더 근본적으로 한 문서의 업체 행과 다른 문서의 집계 정책을 개별 claim으로 결합할 수 없다. 이 경로를 사용하려면 최소한 파주 목록 구조를 안전하게 해석하는 scoped adapter와, 목록 identity와 집계 정책을 명시적으로 연계·감사 가능하게 보존하는 새 capability/계약 검토가 필요하다. 이는 기존 A1 재사용만으로 해결되지 않는다.

다음 구현 전에는 그 capability가 사업자별 상세 근거를 요구할지, 집계 정책의 적용 범위·제외·현재성을 어떤 독립 증거로 보장할지 설계 승인과 테스트가 필요하다. 이번 Spike에서는 이를 설계하거나 구현하지 않았다.

## 미확인 사항과 위험

- 관측은 위 UTC 시점의 직접 응답에 한정된다. 목록의 빈 rendered 기준일과 HTML 주석의 날짜는 현재성 증거가 아니다.
- `paju.noblapp.com`은 비활성 HTML 주석에만 있으므로 접근하지 않았다. 활성 공식 링크가 될 경우 별도 안전성/공식성/redirect 검증이 필요하다.
- HWPX/PDF 신청서의 본문은 파싱하지 않았다. 이들은 현재 개별 혜택 근거로 가정할 수 없다.
- 구체 HTTP adapter를 도입하는 후속 작업은 DNS, redirect target, content-type/size, timeout을 실제 요청마다 다시 안전하게 검증해야 한다.
- 이 문서는 파주시 3개 지정 entry와 직접 연결된 리소스에 대한 capability 조사일 뿐, 파주시 전체 또는 Phase 2 A2의 완료 선언이 아니다.

## 다음 작업

`NEW_CAPABILITY_REQUIRED` 결과를 검토한 뒤에만, 파주 목록 identity와 공통 정책 source를 안전하게 연결할 수 있는 최소 후속 capability의 설계·승인 범위를 별도 결정한다. 승인 전에는 A2 구현, A3, 데이터 변경을 시작하지 않는다.

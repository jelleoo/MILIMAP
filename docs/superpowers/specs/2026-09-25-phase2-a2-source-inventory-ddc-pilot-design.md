# Phase 2 A2 — 출처별 조사와 DDC 우선 시범 적용 설계

- 상태: **PROPOSED — 문서 검토 대기. 구현 계획 및 제품 구현 미승인**
- 작성일: 2026-09-25
- 기준선: `dev@71b8e28518b95429cf878e0d8b3baf2b2ba2ebde`
- 설계 Issue: #62
- 선행 작업: A1.1–A1.5 병합 완료, 마지막 PR #61
- 설계 방식: Superpowers `brainstorming`의 architectural 경로
- 상위 설계: [Phase 2 adapter architecture](2026-09-24-phase2-adapter-architecture-design.md)
- 연결 계획: [A1 evidence scoping plan](../plans/2026-09-24-phase2-milestone-a1-evidence-scoping.md), 특히 12–13절

## 1. 의도와 승인 경계

사용자가 동의한 방향은 **출처별 실제 구조 조사 → 동두천(DDC) 우선 시범 적용 → 확인된 필요에 따라 다른 출처를 작은 PR로 연결**하는 것이다. 목적은 코드를 많이 추가하는 것이 아니라, 공식 자료를 업체별로 반복 조사하는 일을 줄이면서 다른 업체의 혜택을 잘못 연결하지 않는 것이다.

A1은 공통 원문·표·행·셀 근거와 scoped 검증 경로를 마련했다. A2는 실제 출처가 그 경로에 들어갈 수 있는지 확인하고 필요한 차이만 보완한다. 이 문서는 A2의 조사 기준과 첫 DDC 시범 적용을 정의한다. 네 출처의 구현을 한꺼번에 승인하지 않는다.

대화에서의 방향 승인은 이 설계서 작성까지다. 이 문서 검토·승인 후 `writing-plans`로 첫 구현 계획을 작성하고, 사용자가 그 계획과 실행 방식을 확인한 뒤 구현한다. 별도 승인 없는 외부 라이브러리, provider, DB, 인증, API, 데이터 스키마 변경은 계속 금지된다.

## 2. 문제, 범위, 비대상

| 항목 | 결정 |
| --- | --- |
| 해결할 문제 | 공식 목록의 실제 구조·완전성·근거 위치를 확인하지 않고 범용 HTML 파서가 모든 업체를 처리한다고 가정하는 문제 |
| A2 조사 범위 | DDC, Paju, MMA, Yangju의 진입 URL, 실제 조회 자원, 형식, 페이지/상세/첨부 의존성, 식별 정보와 혜택 근거의 위치 |
| 첫 시범 적용 | 확보한 DDC 원문으로 A1 경로를 먼저 실행하고, 재현된 차이가 있을 때만 필요한 출처별 처리를 설계·추가 |
| 이번 문서 PR | 이 설계서와 `docs/ai-development.md`의 Superpowers 설계 규칙만 변경 |
| 제품 코드 비대상 | canonical/seed/apps, lifecycle 판정 변경, 자동 운영 반영, 무제한 크롤링, 검색 provider, LLM, PDF/XLSX/HWP/OCR 추출, SNS 인증 |
| 후속 검증 | 대표 검토 대상 데이터와 사람의 근거 대조는 A3에서 별도 계획 |

DDC 원문이 확보되지 않으면 DDC 구현은 보류한다. 조사·접근 결과는 남길 수 있으나, 추측한 원문이나 합성 표로 DDC 지원 완료를 선언하지 않는다. 다른 출처로 시범 대상을 바꾸려면 이유와 새 경계를 사용자에게 확인한다.

## 3. 확인된 사실과 아직 확보하지 못한 증거

### 3.1 저장소에서 확인한 사실

아래는 기준선 코드의 관찰이며 현재 사이트의 구조나 혜택 유효성을 증명하지 않는다.

| 출처 | 저장소 근거 | 설계에 주는 의미 |
| --- | --- | --- |
| DDC | `tools/data/compare-ddc-benefits.ps1`은 군 장병 할인업소 caption과 업소명/주소/전화번호/할인 열을 읽는다. | 식별 정보와 할인 cell을 같은 표에서 얻을 가능성이 있어 첫 후보로 선정한다. |
| Paju | `tools/data/compare-paju-benefits.ps1`은 category별 URL에서 업소명/소재지/전화번호를 읽으며 이름 header를 prefix로 찾는다. | 실제 header와 상세 근거의 위치를 별도 확인해야 한다. prefix 규칙을 공통 계약에 그대로 복사하지 않는다. |
| MMA | Android `BenefitReconciler.kt`의 `MMA_SOURCE_URL`은 나라사랑가게 목록을 가리킨다. | Android API 연결이 존재한다는 사실과 A2 HTML 지원 여부는 별개다. Android 코드는 변경하지 않는다. |
| Yangju | `tools/data/compare-yangju-benefits.ps1`은 별도 `OfficialCsv`를 입력받고 기존/대체 게시글 URL을 가진다. | CSV 비교 도구가 있다고 원문 첨부파일 추출까지 구현된 것은 아니다. |

### 3.2 2026-09-25 조사 시도

| 출처 | 관찰 수준과 결과 | 현재 판단 |
| --- | --- | --- |
| DDC | 웹 조회 도구가 지정 URL에서 redirect loop를 보고했다. 원문 HTML은 확보하지 못했다. | 원문 확보 대기. 사이트 전체 장애 또는 직접 HTTP 응답 코드를 단정하지 않는다. |
| Paju | 웹 도구의 과거 수집 텍스트에 업체 목록과 스마트 전자지도 상세 안내가 있다. 이 조회본의 열은 업소명/소재지/전화번호를 포함한다. | 구조 조사 단서만 확보. 최신 raw HTML, span, 전체 목록 완전성, 상세 사이트의 계약은 미확인이다. |
| MMA | 지정 목록의 웹 조회가 실패했다. | 원문 확보 대기. 검색·페이지 이동·API 대체 경로를 추정하지 않는다. |
| Yangju | 기존 게시글의 웹 조회본은 2025년 한시 행사와 상시 목록을 별도 HWP 첨부로 안내한다. 첨부 내용은 읽지 않았다. | 첨부 의존성을 기록한다. 현재 혜택이나 대체 게시글의 최신성을 확정하지 않는다. |

**이번에 새로 저장한 공식 원문 snapshot은 없다.** 웹 도구의 정리된 텍스트·검색 결과·오래된 수집 시점은 원본 HTML과 같은 증거가 아니다. 조회 시도일을 원문 발행일이나 사업장 혜택 확인일로 바꾸지 않는다. 과거 대화의 header 표현과 현재 조회본이 다르면 실제 확보한 raw snapshot의 header만 구현 근거로 사용한다.

## 4. 조사 산출물: 지원 가능성 목록

첫 후속 작업은 실행 가능한 어댑터 목록이 아니라 **근거가 붙은 조사 보고서**다. 표는 출처 이름만이 아니라 정확한 URL과 page/category/attachment별 자원 단위로 나눈다. JSON/DB 영속 스키마나 런타임 registry를 새로 만들지 않는다.

자원별 최소 기록:

| 구분 | 기록할 내용 |
| --- | --- |
| 조회 정체성 | SourceFamily, 기존 진입 URL, 실제 요청 URL 원문 문자열, method, 공개 요청의 query/profile 구분, 조회 시도 시각과 수집 방법 |
| 연결 경로 | 직접 관찰한 redirect/detail/attachment 관계와 그 관계의 원문 위치. 관찰하지 못한 최종 URL은 공란 |
| 원문 | 조회 성공/실패, 실제로 확보한 content type/encoding, 원문 보관 위치, 원문 text hash, 가능한 경우 raw byte hash, 보관 적합성 |
| 구조 | 표 caption/header의 실제 문자열, table/row/cell 구조, hidden/nested/merged cell 등 제한, pagination 또는 JS/API 의존성 |
| 근거 종류 | 업체명/주소/지점/전화, 할인 설명/대상/조건/인증, 현재성/프로그램 연결 근거가 각각 어디에 있는지 또는 미확인인지 |
| 완전성 | 특정 응답/표까지 읽었는지, 다음 page/category/attachment를 아직 읽지 않았는지, 목록 전체성은 무엇으로 입증하는지 |
| 구현 판정 | 원문 미확보 / A1 재사용 입증 / 작은 출처별 차이 재현 / 별도 계약·의존성 필요 / 미지원. 미지원 사유와 다음 행동 포함 |

원문 보관 hash와 A1 `ContentHash`를 혼동하지 않는다. A1의 `ContentHash`는 snapshot의 UTF-8 text 기준이며 원본 전송 bytes의 hash와 다를 수 있다. 식별자와 증거 chain은 실제 입력 text를 기준으로 검증한다.

공개 원문에 불필요한 개인정보·쿠키·토큰이 있으면 그대로 fixture에 커밋하지 않는다. 원본 보관과 합성 회귀 fixture를 구분한다. 값을 익명화하거나 HTML을 잘라낸 자료는 별도 파생/합성 자료이고, 원본과 같은 hash·offset·현재성 증거라고 표시할 수 없다.

## 5. 선택한 접근과 대안

**선택: 재사용 우선, 출처별 차이는 재현된 것만 추가.** 먼저 확보한 원문을 기존 A1에 넣어 결과를 측정한다. 이미 충분하면 전용 parser를 만들지 않고 fixture, 적합성 기록, 필요한 문서만 추가한다.

대안 1인 범용 parser의 무제한 확장은 사이트 하나의 예외가 모든 출처의 안전 조건을 약화시킬 수 있어 선택하지 않는다. 대안 2인 출처마다 전체 검증 pipeline을 복제하는 방식은 binding/validation/evaluator가 서로 달라질 위험이 있어 선택하지 않는다.

새 runtime registry, 임의 scriptblock parser hook, 자동 provider 탐색도 미리 만들지 않는다. 실제 DDC 원문이 요구하는 작은 차이를 확인한 뒤 구현 계획에서 가장 좁은 인터페이스를 선택한다.

## 6. DDC 시범 적용의 증거 gate

### 6.1 원문 확보

공식 진입 URL에서 승인된 조회 수단으로 response를 확보한다. 원문 HTML, 조회 시각, 정확한 요청 식별자, 캡처 방법을 고정한다. 도구 오류나 차단이 있으면 접근 실패로 기록하고 우회용 인증·proxy·새 provider를 임의 도입하지 않는다.

정리된 웹 텍스트를 HTML로 재조립하거나 기존 비교 도구의 `OfficialRows`를 게시자 원문으로 바꾸지 않는다. 원문을 읽는 승인된 실행 환경이 확보되지 않으면 제품 구현 gate는 열리지 않는다.

### 6.2 기존 경로의 적합성 확인

고정한 원문과 사람 또는 직접 원문 대조로 정한 expected unit/field를 사용한다. 기대값을 검사 대상 parser의 출력으로 자동 생성하지 않는다.

확인할 것은 A1이 원문을 받는지, 정확한 대상 table/row/cell을 보존하는지, positive business를 찾는지, 무관한 업체·표·안내문이 섞이지 않는지다. locator 성공률과 혜택 상태 확정률을 구분한다. `LOCATED`인데 현재성 근거가 없어 `NEEDS_VERIFICATION`인 결과는 정상일 수 있다.

### 6.3 세 가지 후속 결정

| 관찰 결과 | 다음 산출물 |
| --- | --- |
| A1이 원문을 안전하게 처리함 | 재사용 근거와 positive/negative 회귀 fixture. 불필요한 전용 parser 없음 |
| 제한된 표 선택 또는 구조 차이 재현 | 그 차이만 처리하는 DDC 전용 설계·계획. 기존 계약으로 독립 검증 가능한지 먼저 증명 |
| raw input 미확보, 첨부/JS/API/계약 확장 필요 | 차단 사유와 필요한 승인 범위를 기록. 성공·지원 완료로 계산하지 않음 |

도메인만 같다고 임의의 표를 DDC 혜택 표로 취급하지 않는다. 필요하면 확인한 exact endpoint/query와 원문 caption/header의 조합으로 출처 범위를 제한한다. 실제 selector는 raw evidence 없이 여기서 추측해 확정하지 않는다.

## 7. 데이터 흐름과 유지할 인터페이스

```text
고정한 source candidate와 공식 원문
  -> 기존 fetch / officiality 경계
  -> 같은 run 안의 source-level payload 재사용
  -> 원문으로 검증된 generic 또는 최소 출처별 HTML 처리
  -> SourceObservation / 원래 위치를 가진 SourceContentUnit
  -> 기존 business locator
  -> RelevantEvidenceSlice
  -> 기존 scoped binding / extraction / independent validation
  -> 기존 comparison / evaluator
  -> Shadow review artifact, ProductionAction=NONE
```

현재 `Get-BenefitRunHtmlObservation`은 `HTML_GENERIC` / version `1`을 직접 사용한다. 다른 adapter를 선택하는 runtime resolver가 이미 있다고 가정하지 않는다. 전용 adapter가 정말 필요하면 선택부, parse-cache key, 진단 identity와 영향을 받는 공용 파일을 구현 계획에 함께 명시한다.

유지할 원칙:

- 원본 `BenefitSourceDocument`와 snapshot text는 변경하지 않는다. caption/header/cell은 원본 절대 위치로 검증한다.
- `SourceRowNumber`는 canonical의 원본 행 번호다. HTML physical row index와 구분하고, source-level cache에 넣지 않는다.
- cache는 정확한 URL과 동일 run/request profile 경계를 유지한다. parse 재사용은 실제 `SnapshotId + AdapterId + AdapterVersion`으로 구분한다.
- qualification과 business binding, 선택된 slice, claim과 state는 공유 캐시에 넣지 않는다.
- header를 다른 글자로 덮어써 validator를 통과시키거나, 정규화한 mini-document를 원본처럼 사용하지 않는다.
- binding/extraction/validation/evaluator는 기존 구현을 재사용한다. 비교 도구의 옛 판정이나 canonical 값은 새로 관측한 source evidence가 아니다.

### 공통 계약과 header alias의 제한

A1의 `Get-BenefitScopedHeaderMap`과 원문 membership 검증은 authoritative하다. 원문 header가 map에 없는데 adapter 혼자 별칭을 인식한다고 안전한 slice가 되는 것은 아니다.

DDC가 기존 map으로 표현되지 않으면 **header별 원문 의미와 독립 검증 방식을 먼저 설계 변경으로 제시**한다. 공통 map, 계약 버전, 병합 셀 해석을 이 문서 승인만으로 확장하지 않는다. 신규 adapter가 필요하면 generic과 다른 명시적 identity/version으로 기록하며, 기존 generic 기본 호출은 그대로 유지한다.

## 8. 실패·완전성·혜택 의미의 경계

| 조건 | 허용 결과 |
| --- | --- |
| 원문 조회 실패 | `SOURCE_FETCH_FAILED`, 미해결. `NOT_FOUND`나 `ENDED` 아님 |
| 미지원 형식/구조 | `SOURCE_UNSUPPORTED`, 사용 가능한 slice 없음 |
| 파싱 일부 실패 또는 원문 위치 구성 실패 | `EXTRACTION_FAILED`, 미해결. 실패한 입력의 근거를 추출하지 않음 |
| 지원하는 응답을 완전히 읽었지만 대상 없음 | `SOURCE_NOT_FOUND`. 해당 응답의 미발견이며 사이트 전체 부재 아님 |
| 같은 이름의 배제되지 않은 복수 후보 | `AMBIGUOUS`, usable slice 없음 |
| 명시적 업체/주소/지점/전화 모순 | 기존 conflict 우선순위 유지. 연락처 일치로 주소 모순을 덮지 않음 |
| slice/field/URL provenance 불일치 | 기존 mismatch 거부. 다른 행이나 페이지에서 문구를 찾아 구제하지 않음 |
| 할인 상세는 있으나 현재성 근거 없음 | `NEEDS_VERIFICATION` 가능. 공식 source나 최근 fetch라는 이유로 ACTIVE 확정 금지 |

기존 A1.5의 source-preparation 예외 격리를 보존한다. 한 원문의 처리 실패가 뒤의 정상 업체까지 멈추게 하지 않되, 잘못된 호출 계약이나 보안 위반을 성공처럼 숨기지 않는다.

파싱 `COMPLETE`는 계약이 정의하는 응답 단위의 처리 완료이지 전체 사이트, 모든 category 또는 모든 benefit program을 읽었다는 뜻이 아니다. 필요한 페이지가 빠져 있다면 조사 보고서의 전체성도 미확인이다. 범위를 줄여 이미 알려진 후보나 모순을 제거하고 단일 후보를 만들어서는 안 된다.

페이지 전체의 할인 안내, 한시 행사, 표 밖 공통 조건을 모든 행에 자동으로 붙이지 않는다. 이번 DDC pilot은 기존 detail-only 계약을 유지한다. 공통 프로그램과 업체 참여를 결합하는 증거가 필요하면 별도 설계로 넘긴다.

## 9. 테스트와 검증 계획

아래는 앞으로 수행할 검증이며 이 문서 작성으로 실행됐다는 뜻이 아니다.

| 검증 묶음 | 최소 확인 |
| --- | --- |
| 실제 구조 positive | 확보한 DDC response에서 원문 대조 expected row와 정확한 cell/reference가 선택됨 |
| 업체 분리 | 동일 문서의 다른 업체 할인·종료 문구가 대상 업체의 claim/state에 들어가지 않음 |
| 식별 safety | strong + name-only 대안, 건물 12/23·26/23·902/904, 층·호·지점·전화 conflict의 기존 회귀 유지 |
| 구조 drift | 기대 caption/header 상실, 중복 header, nested/merged/malformed 구조는 근거 없이 수리하거나 부분 생략하지 않음 |
| 원문 provenance | URL/row/header/cell/value 변조를 독립 검증에서 거부; literal text를 태그처럼 삭제해 축약 claim을 통과시키지 않음 |
| 재사용 | 같은 자원은 한 run에서 fetch/parse 재사용, 업체 wrapper와 mutable field는 독립; 다른 query/version은 다른 key |
| 실패 분리 | timeout, 빈 HTML, PDF/XLSX/HWP 의존성은 지원 성공으로 승격하지 않음. 뒤의 정상 행은 계속 처리 |
| 호환성과 export | sparse row ID, named/positional legacy 호출, original source/field provenance와 protected output 경계 유지 |

변경이 필요한 동작은 먼저 재현 테스트를 만들고 실제 RED를 확인한 뒤 최소 수정으로 GREEN을 만든다. 이미 통과하는 적합성 확인은 baseline/회귀 증거로 기록하며 억지로 TDD 실패 이력으로 바꾸지 않는다.

구현 완료 gate는 관련 집중 테스트, 전체 data suite, 최종 HEAD CI, 보호 경로 diff다. 가능한 실행 환경에서는 별도 프로세스와 CI의 동일 프로세스 방식을 모두 확인한다. 실행할 수 없는 명령은 이유와 대체 확인을 보고하며, 사용자의 PC에서 매번 같은 테스트를 반복하도록 요구하지 않는다.

실제 원문 보관·사용 조건을 만족하지 못하면 구조를 반영한 합성 fixture로 회귀를 만들 수 있지만, 합성 통과만으로 live-source support를 입증할 수 없다. 전체 source-family 지원과 사람의 감사는 따로 기록한다.

## 10. 출처별 후속 분리와 완료 기준

- **DDC:** 원문 확보와 generic 적합성부터. 작은 구조 차이만 확인되면 시범 연결 대상으로 진행한다.
- **Paju:** 목록 identity와 상세 혜택을 분리한다. 다른 host의 상세 지도 링크가 보인다는 이유로 해당 내용·인증·검색 API가 승인된 것은 아니다.
- **MMA:** 실제 응답·페이지/검색·상세 위치를 조사한다. 기존 Android API의 권한이나 키를 데이터 도구에서 자동 재사용하지 않는다.
- **Yangju:** 한시/상시 프로그램과 각각의 첨부를 구분한다. 첨부 미지원은 명시적 제한이지 HTML 목록 미발견이나 혜택 종료가 아니다.

각 출처의 구현 Issue는 조사 근거와 파일 예약을 갖고 개별 계획으로 나눈다. DDC가 성공했다고 다른 세 출처도 지원된 것으로 계산하지 않는다.

이번 첫 설계의 완료는 사용자 검토 가능한 문서와 다음 gate가 준비되는 것이다. 후속 DDC pilot 완료는 원문 기반 positive/negative 근거, 적합성 또는 최소 변경, 계약 호환성, 최종 CI를 갖춘 상태다. 원문 미확보인 출처는 조사 완료와 별개로 구현 보류로 남는다.

A2 전체 closeout 시에는 각 조사 대상의 지원/부분 지원/미지원 범위와 사유를 명시한다. 사용자가 선택한 실제 지원 범위가 구현·검증되었는지 확인하고, 미지원 대상을 목록에서 지워 완료율을 높이지 않는다. A2의 정확한 작업 수와 비율은 구현 계획이 정해진 뒤 계산한다.

## 11. 예상 변경 영역과 위험

이번 설계 PR의 실제 수정 파일은 두 개뿐이다.

1. `docs/superpowers/specs/2026-09-25-phase2-a2-source-inventory-ddc-pilot-design.md`
2. `docs/ai-development.md` — 이후에도 Superpowers로 설계하는 운영 원칙

후속 작업에서 예상하는 영역은 조사 문서, source-family test fixture/전용 테스트, 필요할 경우 `tools/data/lib/benefit-evidence/`의 최소 출처 처리와 연결부다. **아직 특정 신규 production filename, 공통 계약 변경, registry나 dependency를 승인하지 않는다.** 원문 차이를 확인한 구현 계획에서 정확한 파일을 예약한다.

주요 위험과 대응:

- 접근 불가: 도구 접근 실패와 사이트 장애를 구분하고 원문 확보 gate에서 멈춘다.
- 실제 구조 변화: header/caption/offset을 fixture와 연결하고 구조 drift를 fail-closed로 처리한다.
- 범위 축소에 의한 false single match: 알려진 동일 프로그램의 후보를 임의 제외하지 않는다.
- 공통 조건의 잘못된 결합: detail-only 원칙과 lifecycle 별도 판정을 유지한다.
- shared helper 변경의 파급: 공통 파일은 단일 integration owner가 다루고 legacy/A1 suite를 보존한다.
- 미검증 정확도 주장: snapshot 적합성, 합성 회귀, live smoke, human audit를 서로 다른 증거로 보고한다.

## 12. A3 전달과 다음 gate

A3에는 실제 지원 자원·형식·제한, 요청/파싱 수, 실패 사유, 고정한 fixture와 원문 provenance를 전달한다. canonical 검토 대상 수나 출시 후보 수를 과거 대화에서 복사하지 않는다. A3 계획에서 원본 파일과 출시 후보 보고서의 hash를 고정하고 원본 행 번호로 대상 집합을 다시 도출한다.

`LocatedCoverage`와 `ResolvedBenefitCoverage`는 별도로 보고하며 inaccessible/unsupported/unresolved 대상을 분모에서 제거하지 않는다. 사람의 감사 전에는 population precision, false-GREEN/ENDED가 검증됐다고 말하지 않는다.

다음 순서:

**이 설계서 사용자 검토 → Superpowers writing-plans → 원문 확보·적합성 및 첫 DDC delivery 계획 검토 → 실행 방식 승인 → 구현.**

원문 확보가 계속 막히면 조사 산출물만 마무리하고 DDC 구현은 보류한다. 접근 실패가 새로운 provider·인증·라이브러리 도입을 자동 승인하지 않는다.

## 근거와 조사 경로

저장소 근거는 위에 기록한 기준선에 고정한다.

- `tools/data/compare-ddc-benefits.ps1`
- `tools/data/compare-paju-benefits.ps1`
- `tools/data/compare-yangju-benefits.ps1`
- `apps/android/app/src/main/java/com/example/milipercent/data/BenefitReconciler.kt`
- `tools/data/lib/benefit-evidence-location-contracts.ps1`
- `tools/data/lib/benefit-evidence/convert-html-source-observation.ps1`
- `tools/data/lib/benefit-evidence/benefit-source-run-context.ps1`
- `tools/data/lib/benefit-evidence/invoke-scoped-benefit-source.ps1`

2026-09-25 조회 시도한 공개 URL:

- DDC: https://www.ddc.go.kr/ddc/contents.do?key=1570
- Paju: https://www.paju.go.kr/user/soldier/BD_discountStoreList.do?q_ctgCd=1001
- MMA: https://www.mma.go.kr/about/udgg/list.do?mc=mma0003357
- Yangju 기존 게시글: https://www.yangju.go.kr/www/selectBbsNttView.do?bbsNo=13&key=202&nttNo=198019

이 링크들은 조사 출발점이다. 본 문서의 3.2절에 적은 확보 수준을 넘어 현재 혜택이나 최신 원문을 검증했다는 주장이 아니다.

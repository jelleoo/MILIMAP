# 2026-09-24 Phase 1 POI Shadow validation closeout

이 문서는 Phase 1 POI Verification Core / Shadow Mode의 구현 및 operational validation evidence를 고정해 인수인계하는 closeout 기록이다. 이 기록은 POI identity/location 검증 범위만 다루며, 군인 혜택의 현재 유효성, production 승인, canonical 좌표 변경을 승인하지 않는다.

## Implementation baseline

- Repository: `jelleoo/MILIMAP`
- Phase 1 A — Business Identity / Normalization: PR #37
- Phase 1 B — POI Discovery: PR #34
- Phase 1 C — POI Matching / Evaluation: PR #36
- Phase 1 Integration: PR #39
- Candidate diagnostics / provenance: PR #41
- Phase 1 code baseline: `97d6070113196e922fb76af7508314b6eda8e7b7`

Phase 1 runner는 Shadow Mode로만 동작한다. `ProductionAction`은 `NONE`이며, canonical·seed·Android product data를 자동 수정하지 않는다.

## Initial operational smoke

2026-09-24 initial operational smoke는 6 rows, 23 provider queries를 실행했다.

- `PARTIAL` / `FAILED`: 0
- GREEN / YELLOW / RED: 2 / 2 / 2
- row 451 `짜장마을`: 2026-09-10 historical `SOURCE_LIMITED / ambiguous` 기록을 삭제하지 않고, 2026-09-24 operational identity observation을 별도 provenance로 보존했다. 이는 혜택 유효성이나 production approval이 아니다.
- row 339 `거시기닭갈비`: multi-candidate 결과의 후보별 근거를 기존 row report만으로 audit할 수 없는 observability gap을 확인했다. Issue #40 및 PR #41이 CandidateDiagnosticJson과 provenance 보존으로 이를 보강했다.

## Representative operational sample

2026-09-24 representative operational sample은 24 rows를 독립 Shadow run으로 실행했다.

- provider queries: 100
- discovery: `COMPLETE` 24 / 24
- evaluation: `COMPLETE` 24 / 24
- `PARTIAL` / `FAILED`: 0
- `ProductionAction=NONE`: 24 / 24
- artifacts: 72 (row별 report CSV, summary JSON, candidate diagnostics JSON)
- canonical / seed / apps diff: 0

### Sample A — unresolved workload

Sample A는 좌표 `재확인 필요` release candidates에서 업종별 systematic stratified sampling으로 선택한 18 rows다.

- GREEN / YELLOW / RED: 5 / 7 / 6
- raw fast-review: 27.8%
- raw deep manual review: 72.2%

업종별 population/sample은 음식 79 / 10, 미용·뷰티 16 / 3, 숙박 9 / 3, 카페 7 / 2였다. 이 구성으로 산출한 stratified weighted operational estimate는 다음과 같다.

- GREEN: 약 24.4%
- YELLOW: 약 43.1%
- RED: 약 32.5%
- deep manual review: 약 75.6%

이 값은 작은 stratified sample 기반 운영 추정치이며 전체 population의 확정 비율로 해석하지 않는다.

### Sample B — positive controls

Sample B는 좌표 `확인 완료` release candidates에서 파주시·동두천시·양주시별 systematic selection으로 선택한 6 rows다.

- candidate discovery: 6 / 6 관측
- GREEN / YELLOW / RED: 3 / 3 / 0
- GREEN fast-review recall: 3 / 6 관측

known valid controls 일부가 YELLOW에 남은 것은 conservative matcher의 알려진 efficiency / recall limitation이다. 이 결과는 canonical을 자동 수정하거나 기존 확인 완료 상태를 강제로 맞추는 근거가 아니다.

### Sample A GREEN human audit

Sample A GREEN rows 232, 406, 418, 438, 453의 canonical business와 selected provider POI identity를 candidate diagnostics와 row report로 사람 검토했다.

- SUPPORTED: 5
- AMBIGUOUS: 0
- CONFLICT: 0

`5 / 5`는 이 unresolved GREEN sample에 대한 human-audit precision observation일 뿐 전체 population precision으로 일반화하지 않는다.

## Execution note

대표 sample 실행 전에 local wrapper filename quoting 오류가 있었다. 오류는 runner/provider 호출 전 발생했고 provider calls와 artifacts는 모두 0이었다. output root가 비어 있음을 확인한 뒤 local wrapper의 path 조립만 수정해 실제 live run을 수행했다. 이는 repository code bug나 provider failure가 아니다.

## Remaining risks and boundaries

- Phase 1은 POI identity/location verification만 다룬다. 군인 혜택의 현재 유효성은 검증하지 않는다.
- GREEN도 automatic production approval이 아니다.
- RED도 폐업 또는 혜택 종료를 뜻하지 않는다.
- operational sample 규모가 작다.
- unresolved workload가 파주시 중심이어서 지역 일반화에 제한이 있다.
- positive controls 중 3 / 6이 YELLOW여서 recall 및 fast-review efficiency 개선 여지가 있다.
- provider 결과는 2026-09-24 시점 observation이다.

## Next state

Phase 1 implementation과 Shadow validation closeout evidence는 이 문서에 기록됐다. 다음 작업은 Phase 2 implementation이 아니라 최신 결과를 바탕으로 한 Phase 2 design discussion이다. Phase 2 담당, Contract, 구현 파일, Issue는 아직 확정하지 않았다.

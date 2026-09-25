# Phase 2 A2.1 DDC captured-source reuse assessment

## Scope and source provenance

- Outcome: **GAP_REPRODUCED**.
- Exact source: `https://www.ddc.go.kr/ddc/contents.do?key=1570`.
- Direct capture completed at `2026-09-25T03:35:25.4618814+00:00`, HTTP 200, without redirects.
- Content type: `text/html;charset=UTF-8`; strict UTF-8 decoding and string round-trip passed. No HTTP content encoding was observed.
- Byte SHA-256 and A1 UTF-8 text SHA-256: `f99e682d154a65f55f6f4d263cfaf3094eb59a1378b07015332b99cfb4d29f9c`.
- Pinned canonical SHA-256: `4ceaaeb5fc98f7bbb22cf1aa12a4c0100b260fef4c0340abc8ace1066482c92d`.

The raw response, headers, transport logs, decoded text, and local `expected.psd1` oracle remain in the OS temporary capture area. They are not committed because this task has not established a repository storage/license policy for redistributing raw external content. The report contains only hashes, bounded observations, and test conclusions.

## Independent direct-source oracle

Before invoking the A1 parser or locator, the raw response was inspected at original UTF-16 offsets. Two distinct canonical rows were selected from physical rows of the first DDC table. The independent oracle verifies the original row, header, and cell spans directly:

| Canonical source row | Physical source unit | Business, address, phone cells | Benefit cell |
| --- | --- | --- | --- |
| 179 | `HTML_TABLE_1_ROW_3` | `업소명` `초코파이`; `주소` `큰시장로 42(생연동)`; `전화번호` `031-861-7922` | Header `할인`; value `10% (포장, 방문 시)`; row span `524735+213`, cell span `524860+28` |
| 157 | `HTML_TABLE_1_ROW_8` | `업소명` `그집순대국`; `주소` `장고갯로157, 제1동(생연동)`; `전화번호` `031-863-2254` | Header `할인`; value `5%`; row span `525809+210`, cell span `526023+11` |

Both controls have separate canonical rows and separate physical source rows. The oracle is an offline, raw-inspection control; it is not derived from parser, locator, or comparison output. It confirmed both original row/header/cell controls against the captured text.

## A1 replay and safety result

The unmodified capture reaches `COMPLETE` HTML observation; both independently selected businesses are located in their expected physical units, and both government-host qualifications are `VERIFIED_OFFICIAL`. The raw-provenance gate then fails before binding, extraction, validation, evaluation, or tamper testing can be claimed:

| Canonical source row | Expected raw span from direct oracle | Actual A1 content-unit span | Result |
| --- | --- | --- | --- |
| 179 | `524735+213` | `524713+213` | start is 22 UTF-16 code units before the raw `<tr>` start |
| 157 | `525809+210` | `525787+210` | start is 22 UTF-16 code units before the raw `<tr>` start |

For both controls, the parser retains the expected unit reference and the expected `BusinessName`/`BenefitDescription` values, but its `RawStart` is consistently 22 code units early while its length is unchanged. This makes the resulting slice fail exact original-row provenance despite matching cell values. The independent oracle remains the source of expected spans; it was not changed to fit parser output.

A separate offline cache inspection did establish `AdapterParseCount=1`, `AdapterReuseCount=1`, and `ExternalFetchCount=0` for the same captured snapshot while locating both controls. That cache behavior does not cure the provenance gap.

The result is a capture-specific technical compatibility check, not a live re-verification, human audit, population accuracy measurement, or claim that either benefit remains current. No `ACTIVE`, `ENDED`, or production action is authorized by this assessment.

## Next gate

- `GAP_REPRODUCED` is recorded at the exact capture hash. A2.2, if approved, must scope only the parser/content-unit raw-span defect with its own source-retention, test-fixture, and TDD plan.
- Binding/extraction/validation/evaluation and source-provenance tamper tests are **NOT_RUN** because the first required exact-span gate failed. The gap must not be bypassed by changing an oracle or by treating value-only agreement as source provenance.
- No production code, raw fixture, canonical/seed data, application data, workflow, dependency, or A2.2 implementation is included here.

No A2.2 implementation is included in this work.

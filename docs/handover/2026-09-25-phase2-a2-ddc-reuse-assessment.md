# Phase 2 A2.1 DDC captured-source reuse assessment

## Scope and source provenance

- Outcome: **REUSE_VERIFIED_FOR_CAPTURE**.
- Exact source: `https://www.ddc.go.kr/ddc/contents.do?key=1570`.
- Direct capture completed at `2026-09-25T03:35:25.4618814+00:00`, HTTP 200, without redirects.
- Content type: `text/html;charset=UTF-8`; strict UTF-8 decoding and string round-trip passed. No HTTP content encoding was observed.
- Raw byte SHA-256 and untrimmed decoded-capture text SHA-256: `f99e682d154a65f55f6f4d263cfaf3094eb59a1378b07015332b99cfb4d29f9c`.
- A1 `BenefitSourceDocument` and `observation.Snapshot.Text` SHA-256: `4c608fa6e81ae1dcdc9facbdf59636d3258597e29fa0678f4c7f4b949cf055ad`.
- Pinned canonical SHA-256: `4ceaaeb5fc98f7bbb22cf1aa12a4c0100b260fef4c0340abc8ace1066482c92d`.

The raw response, headers, transport logs, decoded text, and local `expected.psd1` oracle remain in the OS temporary capture area. They are not committed because this task has not established a repository storage/license policy for redistributing raw external content. The report contains only hashes, bounded observations, and test conclusions.

## Independent direct-source oracle

Before invoking the A1 parser or locator, the untrimmed decoded raw response was inspected at original UTF-16 offsets. Two distinct canonical rows were selected from physical rows of the first DDC table. The independent oracle verifies the original row, header, and cell spans directly:

| Canonical source row | Physical source unit | Business, address, phone cells | Benefit cell |
| --- | --- | --- | --- |
| 179 | `HTML_TABLE_1_ROW_3` | `업소명` `초코파이`; `주소` `큰시장로 42(생연동)`; `전화번호` `031-861-7922` | Header `할인`; value `10% (포장, 방문 시)`; row span `524735+213`, cell span `524860+28` |
| 157 | `HTML_TABLE_1_ROW_8` | `업소명` `그집순대국`; `주소` `장고갯로157, 제1동(생연동)`; `전화번호` `031-863-2254` | Header `할인`; value `5%`; row span `525809+210`, cell span `526023+11` |

Both controls have separate canonical rows and separate physical source rows. The oracle is an offline, raw-inspection control; it is not derived from parser, locator, or comparison output. It confirmed both original row/header/cell controls against the captured text.

## Same-snapshot provenance diagnosis and A1 replay

The previous `GAP_REPRODUCED` conclusion compared offsets from different string representations. The direct raw/oracle string B preserves 11 leading CRLF pairs; the frozen `New-BenefitSourceDocument` constructor applies `ConvertTo-BenefitText`, which calls `.Trim()`. Document text C and snapshot text D therefore remove exactly 22 leading UTF-16 code units. This is a replay representation mismatch, not an A1 parser defect.

| Representation | Length | A1 UTF-8 text hash | First code point / BOM | CRLF / LF / CR |
| --- | ---: | --- | --- | --- |
| B: strict UTF-8 raw decode and oracle source | 563,424 | `f99e682d154a65f55f6f4d263cfaf3094eb59a1378b07015332b99cfb4d29f9c` | `13` (`CR`), no BOM | 5,646 / 5,646 / 5,646 |
| C: `BenefitSourceDocument.Text` | 563,402 | `4c608fa6e81ae1dcdc9facbdf59636d3258597e29fa0678f4c7f4b949cf055ad` | `60` (`<`), no BOM | 5,635 / 5,635 / 5,635 |
| D: `observation.Snapshot.Text` | 563,402 | `4c608fa6e81ae1dcdc9facbdf59636d3258597e29fa0678f4c7f4b949cf055ad` | `60` (`<`), no BOM | 5,635 / 5,635 / 5,635 |

The raw body is 586,470 bytes, has no UTF-8 BOM, and hashes to `f99e682d154a65f55f6f4d263cfaf3094eb59a1378b07015332b99cfb4d29f9c`. Strict `GetString`, `ReadAllText`, `Get-Content -Raw`, and a `WriteAllText`/`ReadAllText` round trip all preserve B exactly. `B -ceq C` is false; `C -ceq D` is true. The only observed representation difference is the 22-code-unit leading whitespace trim; no newline normalization or Unicode-code-point/UTF-16 conversion occurred.

The original oracle is retained unchanged. Its expected complete raw-row fragment was ordinally located exactly once in D, and that D-local index was compared to the parser's span:

| Canonical source row | Oracle B offset / length | Parser D offset / length | `D.IndexOf(B raw row fragment, Ordinal)` | Same-D result |
| --- | --- | --- | --- | --- |
| 179 | `524735+213` | `524713+213` | `524713` (one match) | Parser position begins `<tr>`; applying the B offset to D does not. `Assert-ScopeUnit` passes. |
| 157 | `525809+210` | `525787+210` | `525787` (one match) | Parser position begins `<tr>`; applying the B offset to D does not. `Assert-ScopeUnit` passes. |

Thus, on the exact same immutable D snapshot, each content unit starts at the physical `<tr>` and preserves the raw row fragment. The A1 physical-unit invariant holds.

Both controls then completed the previously blocked stages: `VERIFIED_OFFICIAL` qualification, `STRONG` binding, one scoped `BENEFIT_DESCRIPTION` extracted and `VALIDATED`, and source-URL tamper rejection. Each evaluation remains `NEEDS_VERIFICATION` / `YELLOW` with `CURRENTNESS_INSUFFICIENT`; the row detail does not establish lifecycle or current applicability. The offline replay performed zero external fetches, one adapter parse, and cached-template reuse.

The result is capture-specific technical compatibility, not a live re-verification, human audit, population accuracy measurement, or a claim that either benefit remains current. No `ACTIVE`, `ENDED`, or production action is authorized by this assessment.

## Next gate

- `REUSE_VERIFIED_FOR_CAPTURE` applies only to this exact captured snapshot and two independent direct controls. A future fixture/CI decision still needs separately approved raw-content retention and path reservation.
- The original raw oracle remains authoritative for B. The replay provenance gate must use the immutable D snapshot representation at its boundary; converting B's numeric offsets without accounting for the frozen document trim is invalid.
- No production code, raw fixture, canonical/seed data, application data, workflow, dependency, or A2.2 implementation is included here.

No A2.2 implementation is included in this work.

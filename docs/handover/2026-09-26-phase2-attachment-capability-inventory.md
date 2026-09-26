# Phase 2 official attachment capability inventory

## Baseline and check

- `origin/dev`: `f6a27fca26ae670362f29f0b1adad2c63adc0489`
- Issue: #82
- Checked: 2026-09-26T01:49:48Z (attachment fetch); structure inspection immediately afterwards.
- This is read-only evidence inventory. No canonical value was used as benefit truth.

## Exact sources inspected

| Source | Provenance and transport |
|---|---|
| Suwon PDF | Direct official URL: `https://www.suwon.go.kr/webcontent/ckeditor/2026/5/28/4e5d92bd-869b-41d9-8179-cbc3ffba48c7.pdf`; HTTP 200; `application/pdf; charset=UTF-8`; `%PDF-1.4`; 59,009 bytes; final URL unchanged. |
| Yangju page | `https://www.yangju.go.kr/health/selectBbsNttView.do?key=2716&bbsNo=81&nttNo=206761`; official post title `군장병 할인·우대 업소 참여 모집 및 업소현황`, displayed 2026-07-30. Its attachment markup names the XLSX and directly links `downloadBbsFile.do?key=2716&bbsNo=81&atchmnflNo=200411`. |
| Yangju XLSX | Directly linked attachment URL above; HTTP 200; reported `application/octer-stream; charset=UTF-8`; `PK\x03\x04`; 19,032 bytes; final URL unchanged. |

The Yangju page describes recruitment and an annual list. Its publication date and the filename date are publication context, not per-business validity/currentness proof. The old canonical 2025 event URL must be corrected to this page/attachment chain before attachment parsing could be used for a current source.

## Suwon PDF observations

- One A4 landscape page; Hancom PDF producer; no encryption or forms.
- Rendering shows a crisp, structured table headed `군입대 장병 무료이발 봉사업소 현황(2026.5.28.기준)`, with columns `연번 | 업소명 | 영업자 | 영업소 주소(도로명) | 소재지전화`. It is visually text/table based rather than a scanned image; a machine-readable text layer was not independently verified because the available runtime lacks `pypdf` and a usable `pdftotext` executable.
- `고려이발관` is visible at page 1, table row 1 with address `경기도 수원시 팔달구 팔달로 135, 1층 (화서동)` and telephone `031-255-7060`. This supports deterministic identity selection by name/address/phone without treating any canonical benefit value as truth.
- The document supplies a document-level `2026.5.28.기준` as-of date and identifies the free-barber-service program, but has no per-business benefit-detail, condition, or validity-range column. The as-of date is not a per-business `VALID_UNTIL` or indefinite-currentness assertion.
- A PDF capability would need page plus bounded text/table-row provenance and an approved text/layout extraction runtime. One PDF fetch/snapshot could be shared; safe machine selection remains contingent on that runtime.

## Yangju XLSX observations

- Workbook sheets: 음식점 `A1:F40`, 숙박업 `A1:G4`, 목욕장업 `A1:E4`, 이미용업 `A1:G18`.
- 음식점 header row is `연번 | 업소명 | 소재지 | 전화번호 | 메뉴 | 할인내용`; frozen panes start below row 2. No merged-cell dependency was observed in the inspected sheet XML.
- `가마골 백숙` is 음식점 row 22 (record 20): address `양주시 장흥면 북한산로 1028`, phone `031-861-4800`, menu `백숙, 삼계탕`, attachment value `만두한판 서비스 제공`. The first three identity fields allow deterministic selection without canonical benefit values.
- `거석골` was not present in the workbook shared strings. This is absence from the observed attachment, not a benefit-end inference.
- The sheet carries no per-row start/end/currentness column. It proves a listed benefit description only; currentness remains limited to official publication context and requires conservative evaluation.

## Capability comparison and safety

| Question | XLSX | PDF |
|---|---|---|
| Smallest physical unit | workbook → sheet → row, with exact header/value cell references | page → table row with header/value cells; machine-safe text/layout extraction is still needed |
| Deterministic binding observed | Yes for 가마골 백숙 (name/address/phone) | Yes for 고려이발관 on page 1 (name/address/phone); its available claim fields remain limited |
| Shared fetch/parse | Yes: one URL/workbook can serve rows 337 and 338 | Yes: one URL/document can serve bounded page-row selections after an approved extraction runtime |
| Claim before identity | No; select row using identity first | Must be required, but cannot yet be demonstrated |
| Malformed isolation | Row-level isolation is feasible | Unknown pending text/table structure |

The existing high-level `SourceDocument → Snapshot → SourceObservation → ContentUnit → EvidenceSlice` model has the needed lifecycle shape. However, frozen `SourceContentUnit` validation currently accepts only HTML `TABLE_ROW` and JSONP `JSON_OBJECT` physical units. XLSX sheet/row/cell provenance therefore cannot be represented without extending the shared contract; PDF page/text-row provenance has the same issue.

## Recommendation and verdict

**Primary recommendation: XLSX row/cell provenance capability for the Yangju official attachment chain.** It is the smallest observed attachment capability with deterministic business binding and a bounded physical unit. It should require one attachment fetch and parse per exact URL/run, immutable snapshot reuse, then bounded sheet-row lookup; no whole-workbook reparse/hash per business.

Optional secondary capability: approve and then perform a bounded Suwon PDF text/layout implementation discovery; do not generalize a PDF adapter from this one-page observation.

**Verdict: APPROVAL_REQUIRED.** A safe XLSX implementation requires a shared `SourceContentUnit`/`EvidenceSlice` physical-provenance extension for workbook/sheet/row/cell and corresponding validation tests. That is outside Issue #82's no-shared-contract-change boundary. No parser was implemented.

If approved, expected implementation files are the attachment observation/provenance contract plus an XLSX adapter, run-context reuse, targeted malformed-workbook/row-binding tests, and live controls for 가마골 백숙 plus absent/ambiguous handling for 거석골. Safety gates: no automatic GREEN, `ProductionAction=NONE`, no end-date inference, and fail closed on missing or ambiguous identity.

## Remaining bottlenecks

- Direct attachment content type is nonstandard `application/octer-stream`; magic signature must remain authoritative for XLSX transport classification.
- The Yangju page-to-attachment link must be retained as provenance when correcting source linkage.
- XLSX has no row-level currentness dates.
- Suwon has observed table/identity evidence, but safe machine extraction, exact text spans, and its limited claim/currentness fields need a separate bounded PDF capability decision.

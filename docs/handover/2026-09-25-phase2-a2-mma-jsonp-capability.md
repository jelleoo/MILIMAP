# Phase 2 A2 MMA JSONP capability handover

- Date: 2026-09-25
- Issue: #70
- Baseline: `dev@18ec08a578cf1018123052524747b40167c3dfb8`
- Outcome: **NEW_CAPABILITY_REQUIRED**
- Scope: read-only capability investigation; no product/runtime/data changes

## 1. Question

Does the official Military Manpower Administration (MMA) `나라사랑 가게조회` flow expose auditable per-business benefit evidence, and can the current Phase 2 A1/Core path consume it without changing shared contracts?

## 2. Official provenance path

The official entry page is:

`https://www.mma.go.kr/about/udgg/list.do?mc=mma0003357`

The spike observed that the page's own inline/direct JavaScript references the following first-party data endpoints.

### List endpoint

```text
GET https://open.mma.go.kr/caisGGGS/mmanrsrListAjaxJsonCallNew.json?jbc_cd=&udggeopjong_gbcd=&callback=MmaSpikeList
```

Observed behavior:
- HTTP 200
- redirect count: 0
- no login or API key required
- response Content-Type: `application/json`
- body representation: JSONP
- wrapper: `MmaSpikeList({...})`
- top-level fields: `success`, `list`
- `success=true`
- observed list size: 2,498 rows

### Detail endpoint

```text
GET https://open.mma.go.kr/caisGGGS/mmanrsrSangSeAjaxJsonCall.json?udgigwan_cd={institutionCode}&callback={callback}
```

The `udgigwan_cd` value comes from the list payload.

Observed behavior for both controls:
- HTTP 200
- redirect count: 0
- no login or API key required
- response Content-Type: `application/json`
- body representation: JSONP
- top-level fields: `success`, `udgigwanVO`
- `success=true`

The observed provenance chain is therefore:

```text
official mma.go.kr entry
  -> entry JavaScript
  -> official open.mma.go.kr list JSONP
  -> udgigwan_cd
  -> official open.mma.go.kr detail JSONP
```

This chain was directly observed during the Spike. No guessed endpoint, search-derived alternate API, or authentication bypass was used.

## 3. Relevant payload fields

The observed list/detail payloads expose per-business identity and benefit-related values, including the following fields or directly corresponding values.

| Meaning | Observed field |
| --- | --- |
| Business name | per-business name field in list/detail payload |
| Address | per-business address field |
| Phone | per-business phone field |
| Industry/category | per-business category field |
| Institution/business key | `udgigwan_cd` |
| Benefit detail | `udsangse_cn` |
| Eligible target | `uddaesang_cn` |
| Usage/region restriction | `udjyjehan_cn` |
| Required evidence | `udjbjaryo_cn` |
| Agreement start | `hyjeokyong_sjdt` |
| Agreement end | `hyjeokyong_jrdt` |

The payload therefore contains individual-business evidence rather than only a program-level policy.

## 4. Independent business controls

Canonical benefit values were not used as expected truth. Canonical data, where consulted, was restricted to identity-only comparison.

### Control A — `(유)투투여행사`

- institution code: `2789`
- category: travel agency
- observed benefit: service fee 3% discount
- target, evidence requirement, region restriction, and agreement period were present
- list identity and detail payload referred to the same business/institution key

### Control B — `(주) 예쁜떡 오늘`

- institution code: `2740`
- category: cafe
- observed benefit: purchase cost 5% discount
- target, evidence requirement, region restriction, and agreement period were present
- list identity and detail payload referred to the same business/institution key

For both controls, the list identity and detail JSONP produced matching per-business evidence through `udgigwan_cd`.

## 5. Current A1/Core compatibility

The current shared contracts do not directly support this source representation.

At baseline:
- `SourceFormat` is limited to `HTML`, `CSV`, `XLSX`, `PDF`, and `UNSUPPORTED`.
- `ConvertTo-BenefitHtmlObservation` only accepts `HTML` snapshots.
- the scoped observation path uses `HTML_GENERIC` and HTML table/row provenance.
- the current location/content-unit contract assumes HTML table-row references for this path.

Therefore:
- JSONP must not be relabeled as HTML.
- stripping the callback and pretending the result is an existing supported format would bypass the current provenance/type boundary.
- a new approved source-format/capability boundary is required before MMA can enter the Phase 2 evidence path safely.

## 6. Final outcome

**NEW_CAPABILITY_REQUIRED**

The Spike established both:
1. an auditable official path to per-business benefit evidence, and
2. a representation mismatch with the current A1/Core contracts.

This is not `BLOCKED_EVIDENCE`: the official evidence exists and is reachable.

This is not `REUSE_PATH_IDENTIFIED`: the current frozen A1 path cannot consume JSONP safely without extending shared source/observation capabilities.

No adapter, provider, contract, schema, dependency, product code, canonical data, or seed data was changed in this Spike.

## 7. Design inputs for the next task

A later implementation design should explicitly address:

- JSONP callback-name validation and safe wrapper removal
- source representation and provenance for the original JSONP text
- whether the shared `SourceFormat` contract adds `JSON`, `JSONP`, or a more general structured-data representation
- stable mapping from list `udgigwan_cd` to detail response
- list/detail provenance retention when a claim is derived from the detail endpoint
- fail-closed behavior for missing/mismatched institution codes
- payload schema drift
- agreement-date parsing and currentness interpretation
- separation between an observed agreement end date and a lifecycle conclusion

### Sentinel risk

An agreement end value equivalent to `9999-12-31` was observed as a sentinel-like value.

No rule is approved that interprets this as indefinitely active. The currentness evaluator must not treat the sentinel as a verified lifecycle state without an explicit design decision and supporting source semantics.

## 8. Remaining risk

This handover records the observed MMA capability and field structure from the 2026-09-25 Spike. It does not claim that:
- all 2,498 records remain unchanged,
- all rows have complete benefit/currentness fields,
- agreement dates alone prove current applicability,
- a JSONP adapter design has been approved,
- MMA integration or Phase 2 is complete.

The next implementation step requires a separate architecture/design decision because it touches shared source-format and observation contracts.

# Phase 2 Early Representative Benefit Validation

- Issue: #76
- Validation baseline: `dev@c4ab1c1701a7b4c1aa7a108b6a45f15e310871de`
- Validation date: 2026-09-25
- Production action: shadow only
- Canonical / seed / app mutation: none

## Purpose

This validation measured the current Phase 2 benefit-verification capabilities on a small, source/failure-stratified sample before approving another source adapter.

It does **not** estimate precision or coverage for the full canonical population and does not mark Phase 2 complete.

The sample was fixed before execution:

```text
2, 4, 5, 22, 74, 75, 118, 119, 139, 280, 337, 338
```

The selection covers:

- review-only / currently ineligible existing-source type
- MMA JSONP
- official SNS/blog
- Paju official list HTML
- DDC scoped HTML
- Suwon PDF
- Yangju official HTML / attachment-backed source

## Execution method

The repository itself contains no persistent live-validation workflow for this sample. A temporary, unmerged validation branch used a one-off GitHub Actions runner so the existing PowerShell pipeline could make live HTTPS requests.

Authoritative bounded validation run:

- workflow: `Issue 76 Live Validation`
- run: `36158432914`
- temporary run HEAD: `dde02e75a2a5c748612c60f48b6d193b87a89396`
- result: SUCCESS

The temporary harness/workflow are **not** part of this handover PR and do not change production code.

Each of the 12 sample rows was executed independently to prevent one live source from blocking the remaining sample. Shared-source groups were then executed separately to measure fetch/parse reuse.

A prior all-12-in-one execution also completed in 155.56 seconds, but later requests in that long run experienced transient source fetch failures that did not reproduce in the bounded row executions. The bounded row executions are therefore used for row-level source classification; the long-run behavior is retained as an operational-efficiency observation.

## Representative results

All 12 rows completed without harness exceptions in the authoritative bounded run.

| Row | Business | Source class | Observed pipeline result | State / review |
| ---: | --- | --- | --- | --- |
| 2 | 레드폴바버샵 강남신사점 | 이용 후기 | Existing-source policy does not admit 후기/리뷰 as verified source candidates; no external request | NEEDS_VERIFICATION / YELLOW |
| 4 | 우동명가기리야마본진 | MMA JSONP | Official list fetched, but live `MMA_JSONP_LIST` observation failed to yield a safe usable location/binding | NEEDS_VERIFICATION / YELLOW |
| 5 | 투오프커피 | MMA JSONP | Same live MMA list-stage failure/ambiguity as row 4 | NEEDS_VERIFICATION / YELLOW |
| 22 | 쵸리 | 업체 공식 SNS | Current existing-source policy excludes official SNS/blog from verified source candidates; no external request | NEEDS_VERIFICATION / YELLOW |
| 74 | 게이트호텔 | Paju official HTML | Fetch COMPLETE / VERIFIED_OFFICIAL, but generic HTML adapter UNSUPPORTED and no per-business verified benefit evidence produced | NEEDS_VERIFICATION / YELLOW |
| 75 | 두둑한한판 | Paju official HTML | Same Paju limitation as row 74 | NEEDS_VERIFICATION / YELLOW |
| 118 | 개성연출 | DDC official HTML | HTML_GENERIC COMPLETE, LOCATED, STRONG binding, extraction COMPLETE, BENEFIT_DESCRIPTION validated; currentness still insufficient | NEEDS_VERIFICATION / YELLOW |
| 119 | 고미나 헤어모드 | DDC official HTML | HTML_GENERIC COMPLETE, LOCATED, STRONG binding, extraction COMPLETE, BENEFIT_DESCRIPTION validated; currentness still insufficient | NEEDS_VERIFICATION / YELLOW |
| 139 | 정헤어샾 | DDC official HTML | HTML_GENERIC COMPLETE, but current source row was NOT_FOUND; binding remains ambiguous | NEEDS_VERIFICATION / YELLOW |
| 280 | 고려이발관 | Suwon official PDF | Fetch COMPLETE / VERIFIED_OFFICIAL, PDF source format unsupported by current scoped path | NEEDS_VERIFICATION / YELLOW |
| 337 | 가마골 백숙 | Yangju official page | Fetch COMPLETE / VERIFIED_OFFICIAL, current HTML entry does not expose a supported row-level source unit | NEEDS_VERIFICATION / YELLOW |
| 338 | 거석골 | Yangju official page | Same unsupported source shape as row 337 | NEEDS_VERIFICATION / YELLOW |

Aggregate:

```text
Evaluated rows:          12
Harness exceptions:       0

GREEN / YELLOW / RED:   0 / 12 / 0

ACTIVE:                    0
CHANGED:                   0
ENDED:                     0
NEEDS_VERIFICATION:       12

ProductionAction != NONE:  0
Individual external requests: 10
```

No population-level rate is inferred from these 12 rows.

## Failure / unresolved classification

The sample separates the unresolved workload into materially different causes.

### 1. Supported extraction, currentness still insufficient — 2 rows

Rows:

- 118
- 119

The DDC HTML path safely located the exact business, established STRONG binding, extracted the business-scoped benefit description, and validated the claim. The remaining blocker is currentness/lifecycle evidence, not HTML extraction.

This confirms that adding another parser would not resolve these two rows.

### 2. Existing capability present, but live source compatibility / identity selection unresolved — 3 rows

Rows:

- 4
- 5
- 139

Rows 4 and 5 use the implemented MMA JSONP source family, but the live list observation currently reports `MMA_JSONP_LIST` failure/ambiguous binding before detail evidence can be used.

Row 139 uses the supported DDC HTML path, but the current official source did not locate the canonical business.

These are not missing transport adapters.

### 3. Source shape unsupported by the current scoped capability — 5 rows

Rows:

- 74
- 75
- 280
- 337
- 338

Observed cases:

- Paju: official HTML fetch succeeds, but the direct source is an identity list and does not establish the row-level benefit detail required by the current verification contract.
- Suwon: official PDF fetch succeeds, but PDF extraction is intentionally not implemented.
- Yangju: official HTML fetch succeeds, but per-business details depend on attachment/source structures outside the current scoped HTML path.

The prior A2 source inventory is consistent with these observations. In particular, the observed Paju entry is insufficient as a per-business benefit source, and Yangju's newer official inventory is attachment-backed.

### 4. Existing source type intentionally not admitted as strong verification evidence — 2 rows

Rows:

- 2
- 22

The current candidate policy deliberately excludes 후기/리뷰 and official SNS/blog from the existing verified-source path. These rows perform no external verification request in the scoped run.

This is a policy/capability boundary, not a fetch failure.

## Safety gates

Observed result:

| Safety gate | Result |
| --- | --- |
| False GREEN | 0 |
| False ENDED | 0 |
| Cross-business claim leakage | 0 observed |
| Known hard-conflict bypass | 0 observed |
| `ProductionAction != NONE` | 0 |
| Canonical writes | 0 |
| Seed writes | 0 |
| App writes | 0 |
| LLM invocation in scoped grouped runs | 0 |

No sample row reached GREEN or ENDED.

The grouped DDC run preserved independent business outcomes on one shared HTML snapshot: rows 118/119 were safely located while row 139 remained NOT_FOUND. No claim was copied across those identities.

## GREEN human audit

GREEN rows produced:

```text
0
```

Therefore there is no GREEN audit packet and no row that can be marked `HUMAN_AUDITED`. The human-audit requirement has no applicable row in this sample; this must not be interpreted as a positive human audit result.

## Fetch / parse efficiency

Shared-source runs demonstrated the intended run-context reuse.

### MMA rows 4 + 5

```text
ExternalFetchCount: 1
FetchCacheHits:      1
AdapterParseCount:   1
AdapterReuseCount:   1
```

### DDC rows 118 + 119 + 139

```text
ExternalFetchCount: 1
FetchCacheHits:      2
AdapterParseCount:   1
AdapterReuseCount:   2
```

### Yangju rows 337 + 338

```text
ExternalFetchCount: 1
FetchCacheHits:      1
AdapterParseCount:   1
AdapterReuseCount:   1
```

No duplicate fetch/parse defect was demonstrated for exact shared sources.

The DDC performance fix from PR #78 remains effective: the three-business shared-source run completed in 16.28 seconds with one physical fetch and one parse.

## Operational bottlenecks

### Deep-review burden

All 12 sample rows remained YELLOW.

This means the current sample produces no fast-review candidates and requires manual follow-up for every row. This is a sample observation only and is not extrapolated to the full hold population.

### Long mixed live execution

The all-12-in-one run completed in 155.56 seconds and showed source fetch failures in the latter portion of that execution, while the same sources fetched successfully in bounded executions.

This suggests that a long heterogeneous live run needs operational isolation/bounds before it is used as a large-batch production mechanism. The observation does not establish a specific production-code defect, so no architecture/runtime change is made in Issue #76.

### Currentness

The strongest successful extraction cases, DDC rows 118 and 119, still remain `CURRENTNESS_INSUFFICIENT`. The current source exposes row-level discount text but no individual validity/currentness field was established by the prior A2 inventory.

This is an evidence limitation, not an extraction-performance problem.

## Next capability decision

### Primary: diagnose current MMA live JSONP compatibility

The next smallest task justified by this sample is **not a new source adapter**.

The MMA JSONP capability already exists and deterministic fixture regressions pass, but both live representative MMA rows failed at the list-stage observation/binding path:

```text
MMA_JSONP_LIST
AdapterStatus = FAILED
BusinessBindingStatus = AMBIGUOUS
```

A separate bounded diagnosis should determine whether the live MMA JSONP response changed in callback, schema, field representation, identity normalization, or another already-approved compatibility boundary.

The diagnosis should preserve the existing provenance/linkage contracts and should not broaden into a new provider or source architecture unless separately approved.

### Secondary candidate: official attachment capability design

Three sample rows depend on unsupported document/attachment sources:

- Suwon PDF: row 280
- Yangju attachment-backed source family: rows 337, 338

This justifies a **separate design/inventory step** for official attachment evidence, but the 12-row sample is insufficient to choose a universal PDF/XLSX/HWP implementation order for the full workload.

Yangju requires additional care: the prior source inventory identified the canonical legacy page as a 2025 time-limited event, while a separate 2026 official page points to a current XLSX inventory. Source linkage/currentness must therefore be resolved before treating attachment parsing alone as the solution.

### Not recommended from this validation

- Paju-specific parser expansion: the inspected official list does not establish per-business discount detail/currentness, so parser work alone would not solve the evidence gap.
- SNS/blog verification expansion: still outside the approved strong-evidence path.
- LLM extraction: no evidence from this validation justifies it.
- automatic production mutation: all results remain shadow-only.

## Remaining risks

- MMA live JSONP schema/callback/identity behavior may drift from the deterministic fixtures.
- Official endpoints can be transiently unavailable during longer heterogeneous batches.
- DDC source rows can disappear or change without providing explicit lifecycle semantics.
- The sample is intentionally small and source-stratified; it does not quantify full-population coverage.
- `9999-12-31` remains uninterpreted by design.
- PDF/XLSX/HWP and SNS/blog remain outside the current approved verification capability.

## Completion status

Issue #76 completion criteria are satisfied for this bounded early representative validation:

- the fixed 12-row sample was executed;
- all 12 rows received a deterministic shadow result;
- GREEN count was zero, so no GREEN human-audit row exists;
- unsupported, insufficient, and identity/source failures are separated;
- safety gates were checked;
- fetch/parse efficiency was measured on shared sources;
- the next capability decision is evidence-based;
- no production data or protected product path was modified.

This result does **not** mark roadmap Phase 2 COMPLETE.

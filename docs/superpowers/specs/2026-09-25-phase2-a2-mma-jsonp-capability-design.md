# Phase 2 A2.2 MMA JSONP Capability Design

- Status: Draft for user review
- Date: 2026-09-25
- Issue: #72
- Baseline: `dev@bd05c15467730a6aca684ec1ec5723d88ff05241`
- Scope type: Architectural / source-format and evidence-provenance extension
- Parent design: `docs/superpowers/specs/2026-09-24-phase2-adapter-architecture-design.md`
- Spike evidence: `docs/handover/2026-09-25-phase2-a2-mma-jsonp-capability.md`

## 1. Purpose

The MMA Spike confirmed that the official `나라사랑 가게조회` page exposes auditable per-business benefit evidence through first-party JSONP endpoints.

Observed chain:

```text
mma.go.kr official entry
  -> open.mma.go.kr list JSONP
  -> udgigwan_cd
  -> open.mma.go.kr detail JSONP
```

The current Phase 2 A1 path is intentionally HTML-specific. Its contracts validate physical HTML table/row spans and reject non-HTML source shapes. Reusing that path by relabeling JSONP as HTML would weaken provenance guarantees.

This design adds the minimum JSONP capability needed for MMA while preserving the existing downstream verification core and all current HTML safety guarantees.

## 2. Design goals

The capability must:

1. represent JSONP explicitly rather than hiding it behind `HTML` or plain `JSON`,
2. preserve the original response text and callback wrapper in the source snapshot,
3. validate the callback wrapper before parsing the JSON payload,
4. preserve list-to-detail linkage through `udgigwan_cd`,
5. create source-backed structured content units with auditable field references,
6. reuse existing business location, extraction, validation, comparison, and review logic where safe,
7. fail closed on malformed wrapper, schema drift, ambiguous identity, or broken list/detail linkage,
8. keep `ProductionAction=NONE`,
9. introduce no new external dependency.

## 3. Non-goals

This design does not approve:

- Android changes,
- canonical or seed changes,
- DB or persistent schema changes,
- authentication changes,
- external API contract changes,
- new libraries,
- broad JSON/JSONP framework support,
- generic discovery,
- PDF/XLSX/SNS/blog work,
- automatic canonical updates,
- interpreting `9999-12-31` as indefinitely active,
- marking Phase 2 complete.

## 4. Selected approach

Use an explicit `JSONP` source format and an MMA-specific structured adapter.

```text
MMA list JSONP
    |
    v
callback validation
    |
    v
JSON parse
    |
    v
MMA list SourceObservation
    |
    v
business identity location
    |
    v
selected udgigwan_cd
    |
    v
MMA detail JSONP
    |
    v
callback + institution-code validation
    |
    v
detail SourceObservation / evidence slice
    |
    v
existing scoped extraction + validation
    |
    v
claim comparison / BenefitState / ReviewClass
```

The new capability is additive. Existing HTML code paths remain unchanged in behavior.

## 5. Why `JSONP`, not `JSON`

The source body is observed as callback-wrapped JSON despite an `application/json` Content-Type.

Example shape:

```text
MmaSpikeList({"success":true,"list":[...]})
```

The wrapper is part of the retrieved source representation and is relevant evidence for safe parsing. Treating the source as plain JSON would require removing part of the original body before snapshotting or would blur the distinction between raw and normalized representations.

Therefore:

- `BenefitSourceDocument.Text` preserves the original JSONP body,
- `BenefitSourceSnapshot.Text` preserves the same original body,
- `SourceFormat='JSONP'`,
- parsed JSON is an adapter-internal normalized representation, not a replacement for the source snapshot.

## 6. Source format contract

The in-process `SourceFormat` allowed set gains:

```text
JSONP
```

Resulting conceptual set:

```text
HTML
CSV
XLSX
PDF
JSONP
UNSUPPORTED
```

This is an internal Phase 2 contract extension. It does not change Android, database, server, or external API schemas.

### 6.1 Format detection

The generic fetcher must not classify every `application/json` response as JSONP.

JSONP detection is only safe when all of the following hold:

- the candidate belongs to the explicitly supported MMA JSONP path,
- the response body passes the JSONP wrapper validator,
- the callback name matches the callback requested for that endpoint.

A generic `application/json -> JSONP` rule is not introduced.

## 7. JSONP wrapper validation

The adapter must validate the raw response before JSON parsing.

Accepted conceptual grammar:

```text
optional surrounding whitespace
expectedCallback
(
  exactly one JSON object
)
optional semicolon
optional surrounding whitespace
```

Validation rules:

- callback must equal the expected callback exactly,
- callback must not be inferred from arbitrary response text,
- leading/trailing executable statements are rejected,
- multiple callback invocations are rejected,
- missing closing parenthesis is rejected,
- non-object root JSON is rejected for the MMA endpoints,
- JSON parse failure is fail-closed,
- `success != true` is not usable evidence.

The original raw text remains preserved even after successful normalization.

## 8. MMA source roles

MMA uses two distinct source roles.

### 8.1 List source

Purpose:

- discover official MMA business records,
- expose business identity,
- expose `udgigwan_cd`,
- provide the official linkage key to detail evidence.

The list response may contain benefit fields, but the implementation should prefer the detail response for final scoped claim extraction when the detail endpoint is available and valid.

### 8.2 Detail source

Purpose:

- provide the selected institution's per-business benefit evidence,
- carry the fields used for downstream benefit claims,
- preserve the institution key that links the detail to the selected list record.

A detail response must never be accepted only because the URL contains the requested code. The returned payload must also support the same institution identity/linkage.

## 9. Provenance model

MMA verification uses a two-source provenance chain.

```text
List snapshot
  -> selected list unit
  -> udgigwan_cd
  -> detail request
  -> detail snapshot
  -> selected detail unit
```

Both source snapshots must remain independently auditable.

The detail evidence slice is the direct source for benefit claims. The list evidence is linkage/identity provenance.

No attempt is made to concatenate list and detail bodies into one synthetic source document.

## 10. JSONP content units

Current `SourceContentUnit` is implemented with HTML-specific fields and assertions. JSONP support must not weaken those assertions.

The implementation should separate common unit identity from format-specific physical references.

Conceptually, both formats share:

```text
SourceContentUnit
- SnapshotId
- UnitType
- UnitReference
- RawStart
- RawLength
- RawFragment
- RawEvidenceText
- StructuredFields
- FieldReferences
```

HTML retains its existing table-specific fields and checks.

JSONP adds a source-native unit type such as:

```text
JSON_OBJECT
```

and physical references such as:

```text
JSONP_LIST_ITEM_<index>
JSONP_DETAIL_OBJECT
```

The exact implementation shape may use separate constructors/assertions rather than making every field optional in one loose constructor.

### 10.1 Required invariant

A JSONP unit must be reconstructable from the original JSONP snapshot and its stored source span/reference.

The adapter must not create a structured field without a source-backed field reference.

## 11. Field references

Each structured field must retain a source-backed reference.

Conceptual JSONP field reference:

```text
FieldReference
- FieldReference
- PropertyName
- ValueStart
- ValueLength
```

Example:

```text
JSONP_DETAIL_OBJECT/udsangse_cn
```

The implementation may store additional offsets needed to prove that the normalized value came from the original raw snapshot.

A field value is valid only when:

- the referenced property exists in the parsed selected object,
- the referenced raw source span belongs to the selected object,
- the normalized structured value corresponds to that raw property value.

No field may be accepted solely from an in-memory object if its provenance cannot be tied back to the raw source snapshot.

## 12. Structured field mapping

The MMA adapter maps observed MMA properties into existing semantic fields.

Required benefit mappings:

```text
udsangse_cn      -> BenefitDescription
uddaesang_cn     -> EligibleTarget
udjyjehan_cn     -> UsageCondition
udjbjaryo_cn     -> VerificationMethod
hyjeokyong_sjdt  -> ValidFrom
hyjeokyong_jrdt  -> ValidUntilObserved
```

Identity mappings include the observed business name, address, phone, category, and `udgigwan_cd`.

The exact raw property names for identity fields must be fixture-backed during implementation. They must not be guessed from canonical columns.

## 13. Business location

The existing identity logic remains authoritative.

The list adapter creates one content unit per MMA business record with normalized identity fields and the institution code.

The existing locator strategy may be reused if the generic locator is generalized to consume structured units independently of HTML physical layout.

Required behavior remains:

- exact/normalized business name evidence,
- address/phone/branch supporting evidence where available,
- hard conflicts remain conflicts,
- one unique strong candidate -> `LOCATED`,
- multiple plausible candidates -> `AMBIGUOUS`,
- no candidate -> `NOT_FOUND`.

The institution code is not itself proof that a canonical business matches an MMA record. It becomes trusted linkage only after the list record is safely located.

## 14. List-to-detail linkage

After one MMA list record is safely located:

1. read its `udgigwan_cd`,
2. construct the supported detail request using that exact code,
3. fetch the detail JSONP,
4. validate callback and payload,
5. verify the returned detail belongs to the same institution/business key,
6. only then expose detail benefit evidence.

Failure cases:

- missing institution code,
- empty code,
- malformed code,
- multiple selected list rows,
- detail response missing institution identity,
- returned code differs from requested/selected code,
- detail `success != true`.

All fail closed to a non-usable evidence result. They do not imply benefit termination.

## 15. Evidence slice design

The current `RelevantEvidenceSlice` implementation hardcodes:

- `ScopeType='TABLE_ROW'`,
- `LocatorMethod='STRUCTURED_HTML_ROW'`,
- HTML table references.

Those assumptions must be generalized without weakening HTML validation.

For MMA, conceptual values are:

```text
ScopeType='JSON_OBJECT'
LocatorMethod='STRUCTURED_JSONP_OBJECT'
EvidenceReference='JSONP_DETAIL_OBJECT'
```

The slice continues to preserve:

- source row number,
- source URL,
- source format,
- snapshot ID,
- content hash,
- raw source fragment,
- normalized evidence text,
- structured fields,
- field references,
- identity evidence,
- observation timestamp.

Format-specific slice validation must dispatch by `SourceFormat` / `ScopeType`.

HTML slices continue to use the current exact table/row validation unchanged.

## 16. Extraction and validation

The existing scoped deterministic extraction path is conceptually reusable because it already consumes semantic `StructuredFields` and `FieldReferences`.

However, HTML-specific method names must not be reused for JSONP.

Conceptual extraction method:

```text
SCOPED_JSONP_FIELD
```

Validation continues to require:

- source URL match,
- exact field-reference match,
- extracted value equals the selected structured source value,
- evidence text equals or is deterministically derived from the same selected source field.

The implementation should generalize the scoped extractor/validator by source shape rather than duplicate claim-comparison logic.

## 17. Agreement dates and currentness

Observed MMA fields:

```text
hyjeokyong_sjdt
hyjeokyong_jrdt
```

These are evidence fields, not automatic lifecycle decisions.

Rules:

- a normal start date may produce a source-backed `VALID_FROM` claim,
- a normal explicit end date may produce a source-backed `VALID_UNTIL` claim,
- whether the end date proves `ENDED` still belongs to existing claim comparison/currentness logic,
- missing dates do not prove active or ended,
- `9999-12-31` is preserved as an observed sentinel-like raw value,
- `9999-12-31` must not by itself produce `CURRENT`, `ACTIVE`, or "indefinite" semantics.

A dedicated sentinel interpretation rule is deferred until official source semantics justify one.

## 18. Error handling

New JSONP failures should be represented through diagnostics and existing fail-closed states rather than throwing uncontrolled pipeline errors.

Examples:

```text
JSONP_CALLBACK_MISMATCH
JSONP_WRAPPER_INVALID
JSONP_PARSE_FAILED
JSONP_SCHEMA_UNSUPPORTED
MMA_INSTITUTION_CODE_MISSING
MMA_INSTITUTION_CODE_MISMATCH
MMA_DETAIL_UNAVAILABLE
```

Whether these become global `ReasonCode` values or adapter-local diagnostic codes is an implementation-plan decision. The preferred default is adapter-local diagnostics unless downstream state evaluation specifically needs a new global reason.

No JSONP failure maps directly to `ENDED`.

## 19. Caching and request identity

The existing run context caches by request URL and parsed snapshot/adapter identity.

MMA requires two request classes:

- shared list request,
- detail request per selected `udgigwan_cd`.

Within one run:

- the list should be fetched once per exact request URL,
- its parsed list observation should be reused across canonical rows,
- each detail endpoint should be fetched once per exact detail request,
- detail parse results should be cacheable by snapshot + adapter version.

Callback values used only for JSONP transport must be deterministic within a run so cache identity is stable.

## 20. Security and trust boundary

No authentication bypass, undocumented host guessing, or arbitrary script execution is allowed.

The adapter:

- only accepts the approved MMA first-party hosts/path family,
- treats JSONP as text and data,
- never executes callback JavaScript,
- parses the enclosed JSON as data only,
- rejects unexpected executable content.

No new secret or credential is introduced.

## 21. Backward compatibility

Existing HTML behavior is a hard compatibility requirement.

The implementation must preserve:

- existing `HTML_GENERIC` adapter semantics,
- current HTML table/row physical reference checks,
- current A1 test fixtures,
- cross-business leakage prevention,
- current locator hard-conflict behavior,
- existing extraction/validation results for HTML fixtures,
- `ProductionAction=NONE`.

JSONP support must be additive. Passing old HTML tests through weaker generalized assertions is not acceptable.

## 22. Expected implementation boundaries

Likely affected areas:

- `tools/data/lib/benefit-verification-contracts.ps1`
- `tools/data/lib/benefit-source/discover-official-benefit-sources.ps1`
- `tools/data/lib/benefit-evidence-location-contracts.ps1`
- `tools/data/lib/benefit-evidence/benefit-source-run-context.ps1`
- a new MMA JSONP adapter under `tools/data/lib/benefit-evidence/**`
- scoped extraction/validation only where HTML-specific method names/shape assumptions must be generalized
- dedicated tests/fixtures under `tools/data/testdata/**` and `tools/data/test-*.ps1`

The exact file list is fixed during implementation planning against latest `dev`.

No Android, canonical, seed, Room, API, auth, dependency, or CI file is expected.

## 23. Testing strategy

Implementation must use deterministic fixtures first.

### Contract tests

Verify:

- `JSONP` is accepted only as the explicit new source format,
- existing formats remain unchanged,
- malformed source format still fails.

### Wrapper tests

Cover:

- valid callback/object,
- optional trailing semicolon,
- callback mismatch,
- missing close parenthesis,
- additional executable text,
- invalid JSON,
- unexpected JSON root,
- `success=false`.

### Provenance tests

Verify:

- raw JSONP snapshot is unchanged,
- unit spans/reference resolve to the original source,
- each structured field reference maps to the selected raw object/property,
- mutated references fail,
- cross-object references fail.

### Locator tests

Verify:

- one safe MMA business match locates,
- duplicate plausible businesses are ambiguous,
- hard address/phone/branch conflict cannot be selected,
- institution code alone cannot override identity conflict.

### Linkage tests

Verify:

- list-selected code fetches matching detail,
- missing code fails closed,
- mismatched detail code fails closed,
- detail from another list item cannot be attached.

### Extraction/validation tests

Verify:

- benefit/target/condition/verification fields produce source-backed claims,
- JSONP extraction uses JSONP-specific method/reference,
- field/value mutation invalidates evidence,
- `9999-12-31` remains observed data without active/ended inference.

### Regression tests

All existing A1 HTML tests must continue to pass unchanged.

Required invariants remain:

```text
False GREEN = 0
False ENDED = 0
Cross-business claim leakage = 0
Known hard-conflict bypass = 0
ProductionAction != NONE = 0
```

## 24. Delivery boundary

This capability should be implemented as one small architectural delivery focused only on MMA JSONP.

Success means:

- official MMA list/detail JSONP can be represented and scoped safely,
- at least two independent MMA controls pass end-to-end shadow verification through source-backed evidence,
- HTML regressions remain green,
- no protected product/data path changes occur.

Success does not mean:

- every MMA row is verified,
- canonical data is updated,
- Phase 2 is complete.

## 25. Next step after implementation

Do not immediately proceed through PDF -> XLSX -> LLM -> SNS/discovery.

After MMA JSONP capability is merged, run an **early representative Phase 2 validation** using currently supported source families.

Classify remaining failures by cause:

```text
supported + located + extracted
identity ambiguity/conflict
unsupported PDF
unsupported XLSX
unstructured text extraction gap
missing/stale source
SNS/blog only
other
```

Only capabilities that materially block representative validation should then receive new implementation work.

This prevents Phase 2 from duplicating the future multi-source/discovery roadmap.

## 26. Approval boundary

Approval of this design authorizes creation of an implementation plan only.

It does not authorize:

- implementation,
- merge,
- contract code changes,
- any protected architecture/data change beyond the exact implementation plan later reviewed by the user.

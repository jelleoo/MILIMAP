# Phase 4 Multi-source Adapters Design

- Status: Proposed design for review
- Date: 2026-09-29
- Baseline branch: `dev`
- Baseline commit: `28a6845684e94cd3490fcc1c4112ef6fce402205`
- Scope: official document source expansion only

## 1. Problem

Phase 2 Benefit Verification Core safely supports scoped official HTML, MMA JSONP, and XLSX evidence. Phase 3 adds immutable history, fingerprints, bounded incremental reuse, and review/audit routing. Official PDF and HWPX documents are still outside the supported scoped path because the current contracts and run context do not yet provide safe page/section/table/row provenance, and there is no approved PDF/HWPX extraction runtime.

Phase 4 must extend the existing verification pipeline to official PDF and HWPX documents without creating a second benefit-verification system, weakening business isolation, or introducing repeated fetch/parse/OCR work per business.

## 2. Goals

Phase 4 will:

1. add bounded support for official PDF and HWPX documents;
2. preserve exact physical provenance from source snapshot to field and claim;
3. prefer native extraction and use OCR only as a fallback;
4. reuse the existing `SourceObservation -> SourceContentUnit -> EvidenceSlice` flow whenever it can be extended safely;
5. reuse existing business binding, claim extraction, validation, BenefitState/ReviewClass, Phase 3 history, fingerprints, and review routing;
6. isolate format-specific parsing from downstream verification logic;
7. support one fetch and one parse/OCR per identical source/run, followed by many business lookups;
8. fail closed when the document layout, identity binding, or physical provenance cannot be proven.

## 3. Non-goals

Phase 4 does not include:

- official SNS/blog verification;
- general web, community, or user-report discovery;
- periodic scheduling;
- automatic canonical, seed, or app writes;
- automatic production approval;
- automatic `ENDED`, `CLOSED`, or equivalent lifecycle conclusions from absence;
- full validation of the 247 benefit-evidence hold rows;
- universal support for every public-sector PDF or HWP-family document;
- mandatory legacy binary HWP support.

Official SNS/blog and broader discovery remain later source-expansion work. Periodic execution remains a separate phase.

## 4. Safety invariants

The following existing boundaries remain unchanged:

- `ProductionAction = NONE`.
- GREEN remains a fast-review candidate, not production approval.
- POI evidence is not benefit-validity evidence.
- Source absence is not benefit ending or business closure.
- A parser/OCR result is evidence extraction, not truth by itself.
- Benefits are never invented, normalized into stronger claims, or assigned unsupported validity dates.
- Unsupported or ambiguous layouts fail closed.
- Existing HTML/JSONP/XLSX behavior must remain regression-compatible.

## 5. Architectural decision

Phase 4 uses a shared document-adapter boundary in front of the existing Benefit Verification Core.

```text
Official source
    |
    v
SourceDocument / immutable Snapshot
    |
    v
Format adapter
    |-- existing HTML
    |-- existing JSONP
    |-- existing XLSX
    |-- Phase 4 PDF
    `-- Phase 4 HWPX
    |
    v
SourceObservation / SourceContentUnit
    |
    v
Business locator
    |
    v
EvidenceSlice
    |
    v
Existing business binding
    |
    v
Existing claim extraction / validation
    |
    v
BenefitState / ReviewClass
    |
    v
Phase 3 history / comparison / review
```

The design does not require a new `PhysicalEvidenceUnit` type. Existing `SourceContentUnit` and `EvidenceSlice` contracts should be minimally extended if they can express PDF/HWPX provenance cleanly. A new shared type is justified only if repository-level implementation analysis demonstrates that extending the current contract would create duplicated or unsafe format-specific branching.

Format adapters stop at document structure and physical provenance. They do not decide benefit validity, review class, or production action.

## 6. Source-format classification

File extension and HTTP `Content-Type` are hints, not authoritative format classification.

Classification should prefer:

1. payload magic/package signature;
2. internal package structure validation;
3. content type and filename as supporting metadata.

This is required because official attachments may use incorrect or generic MIME types.

PDF classification must validate PDF structure/signature. ZIP-based formats such as XLSX and HWPX must be distinguished by internal package structure rather than the ZIP signature alone. Unclassifiable payloads are `UNSUPPORTED`.

## 7. Generic and layout-specific adapters

Phase 4 follows this order:

```text
validated source format
    |
    v
generic format adapter
    |
    +-- safe bounded structure found -> use it
    |
    `-- not safe -> inspect known layout-specific adapters
                   |
                   +-- exactly one applies -> use it
                   +-- none applies -> UNSUPPORTED
                   `-- more than one applies -> fail closed
```

Generic success stops further layout-adapter execution.

Layout-specific adapters must be thin. They may identify rows/blocks/fields for a known layout, but they must reuse shared fetch, snapshot, extraction runtime, provenance validation, business binding, claim validation, and history logic.

Applicability must be deterministic and based on structural markers, not guesswork.

## 8. PDF path

### 8.1 Native extraction first

PDF processing attempts native text/layout extraction first.

Native extraction is usable only when the implementation can establish a bounded source unit and link extracted fields to the original page/layout evidence. Extracting text alone is insufficient if row or block relationships are lost.

A typical successful reference may conceptually identify:

```text
page -> table/region -> row/block -> field/span
```

The exact internal representation is implementation-specific, but validation must prove that the field came from the claimed physical unit.

### 8.2 OCR fallback

OCR is used only when native extraction cannot produce a safe bounded unit, for example:

- no usable native text layer;
- native layout reconstruction is unsafe;
- required row/block provenance cannot be established.

OCR is not run when native extraction is already sufficient.

OCR output must preserve at least:

- source snapshot identity;
- page or bounded image region;
- extraction method;
- extractor identity/version;
- relevant extraction configuration;
- diagnostics sufficient to distinguish native and OCR evidence.

OCR confidence alone does not create STRONG business binding or a stronger BenefitState. OCR-derived fields must pass the same business-binding and validation rules as native fields.

If OCR cannot preserve safe identity/provenance, processing fails closed.

## 9. HWPX path

HWPX support is prioritized with PDF because its package structure can preserve section/table/row/cell relationships.

The HWPX adapter should map supported structures into the same downstream semantic fields used by existing adapters, while retaining references such as:

```text
section -> table -> row -> cell
```

Paragraph evidence may be supported only when it is bounded and business-isolated.

Parsing HWPX XML is not sufficient by itself; the adapter must prove that selected identity and benefit fields belong to the same safe source unit.

Legacy binary HWP is not a Phase 4 mandatory deliverable. If a real official source requires it, it becomes a bounded follow-up task with its own dependency and provenance analysis.

## 10. Physical provenance contract

Phase 4 keeps physical provenance separate from semantic benefit truth.

Each positive source unit must preserve enough information to validate:

- source snapshot identity;
- source format;
- deterministic unit reference;
- structured field values;
- physical field references;
- extraction method;
- adapter identity/version;
- relevant diagnostics.

Conceptual references may look like:

```text
PDF_PAGE_1_TABLE_1_ROW_4/BusinessName
HWPX_SECTION_1_TABLE_2_ROW_5/BenefitDescription
```

Names are illustrative. Final identifiers must be deterministic and validated against actual parser output.

The implementation should prefer format-specific validators behind one shared dispatch boundary rather than mixing PDF/HWPX rules into existing HTML/XLSX validators.

## 11. Business isolation

Business identity must be established before benefit claims are accepted.

The existing locator/binding rules remain authoritative where applicable. Phase 4 must prevent cross-business leakage such as combining Business A identity fields with Business B benefit fields.

A usable positive unit should retain business identity fields such as name plus supporting address, phone, or branch evidence when present.

Ambiguous duplicate business names, conflicting address/phone evidence, mixed rows, or broken physical containment must not produce a successful scoped evidence slice.

## 12. Error isolation and status

Existing high-level operational states remain:

- `COMPLETE`
- `PARTIAL`
- `FAILED`
- `UNSUPPORTED`

Existing location states remain preferred where applicable:

- `LOCATED`
- `AMBIGUOUS`
- `NOT_FOUND`

Format-specific details should be recorded through diagnostics/reason codes rather than creating a parallel state system.

Errors may be isolated to the smallest safely bounded unit. A malformed row may be excluded while other rows remain usable only when the parser can still prove document structure and row boundaries. If structural trust is lost, the adapter must fail at the broader document level.

Examples of format-specific diagnostics may include parser failure, unsupported layout, unusable row, OCR failure, ambiguous OCR identity, or invalid HWPX package structure. Exact codes are implementation-plan decisions and should reuse existing global reason enums where appropriate.

`NOT_FOUND` means only that the business was not found within the safely processed source context. It never means the benefit ended or the business closed.

## 13. Run-local reuse and bottleneck control

Phase 4 extends the existing `BenefitSourceRunContext` pattern rather than creating a second cache.

The target behavior is:

```text
source URL
   |
   v
fetch once
   |
   v
snapshot once
   |
   v
native parse once
   |
   +-- optional OCR once when required
   |
   v
document observation/index
   |
   +-- business A lookup
   +-- business B lookup
   `-- business N lookup
```

The following are prohibited design outcomes:

- refetching the same attachment per business;
- reparsing the same snapshot per business;
- repeating identical OCR per business;
- rehashing the same trusted artifact unnecessarily;
- creating a Phase 4-only fingerprint/reuse framework;
- creating separate PDF/HWPX BenefitState evaluators.

Run metrics should make duplicate work observable.

## 14. Phase 3 fingerprint and cross-run reuse integration

Phase 4 reuses the existing four-layer fingerprint model:

- InputFingerprint
- EvidenceFingerprint
- SemanticFingerprint
- ExecutionFingerprint

The original document `ContentHash` remains evidence identity where trusted.

Parser/adapter/OCR engine version and material configuration are execution concerns. A changed extractor/configuration must not be mislabeled as a real-world evidence change.

New PDF/HWPX adapters start with incremental reuse capability `NONE`.

An adapter may later be promoted to a safe post-fetch capability only after deterministic regression evidence demonstrates:

- identical input/evidence/execution produces identical safe projection;
- provenance remains reproducible;
- extractor identity/version/configuration are represented in execution identity;
- prior COMPLETE/comparable reuse requirements still hold.

Reuse is an optimization, not a default permission.

## 15. Dependency policy

Phase 4 may add a new PDF, HWPX, or OCR dependency only after explicit approval.

Before approval, the implementation task must compare realistic candidates on:

- extraction/layout fidelity;
- deterministic provenance support;
- Windows compatibility;
- CI compatibility;
- licensing;
- maintenance status;
- performance;
- additional runtime requirements;
- operational complexity.

No dependency is selected by this design document.

The preferred outcome is the smallest dependency set that satisfies the required provenance and safety gates. PDF, HWPX, and OCR are not required to share one library.

## 16. Testing strategy

Implementation should proceed from contracts and deterministic fixtures toward live validation.

### 16.1 Contract tests

Cover:

- valid PDF/HWPX unit references;
- valid field references;
- source snapshot identity;
- extraction metadata;
- invalid/mismatched provenance rejection;
- unsupported format rejection.

### 16.2 Parser and adapter fixtures

At minimum cover:

- structured PDF table;
- structured HWPX table;
- multiple businesses in one document;
- duplicate business names;
- missing fields;
- malformed row/unit;
- unsupported layout;
- deterministic layout-specific adapter selection.

### 16.3 OCR tests

At minimum prove:

- native-safe input -> OCR invocation count 0;
- native-insufficient input -> OCR invocation count 1;
- OCR failure -> fail closed;
- OCR identity ambiguity -> no strong binding;
- extractor/config change -> reuse rejected where relevant.

### 16.4 Cross-business leakage regression

A dedicated gate must prove that one business's identity cannot be combined with another business's benefit fields.

Observed cross-business leakage must be 0 in Phase 4 closeout evidence.

### 16.5 Reuse/performance regression

For a representative shared document with N businesses, verify the intended bounded behavior:

- fetch count = 1;
- native parse count = 1;
- OCR count <= 1 when OCR is required;
- business lookup count may scale with N;
- cached observation/index is reused.

### 16.6 Existing regression suite

Existing HTML, JSONP, XLSX, Phase 3 history/reuse, and protected-path safety tests must remain passing.

### 16.7 Live official-source validation

Use real official sources when available and record their observation date.

The known Suwon official PDF is an appropriate PDF representative control if still available and materially unchanged at validation time.

If no real official HWPX or OCR-required source is available, do not invent one. Use structural fixtures for deterministic implementation validation and record live-source status as `NOT_OBSERVED`, not PASS.

## 17. Closeout gate

Phase 4 may be called COMPLETE only when the implemented bounded scope satisfies all applicable gates.

### Functional

- supported PDF native path validated;
- supported HWPX native path validated;
- OCR fallback path validated when implemented/required;
- generic and layout-specific adapter selection behaves deterministically.

### Safety

- cross-business leakage = 0;
- false ENDED from absence = 0;
- unsupported layout forced interpretation = 0;
- `ProductionAction != NONE` = 0;
- automatic canonical/seed/apps writes = 0.

### Provenance

Every positive claim used by the Phase 4 path is traceable through:

```text
snapshot -> physical unit -> field reference -> extracted/validated claim
```

### Efficiency

Representative shared-source tests demonstrate one fetch and one parse/OCR per identical source/run rather than per business.

### Regression

Existing supported source families and Phase 3 history/reuse remain passing.

Live-source `NOT_OBSERVED` is not counted as a successful live gate. Where a real source is unavailable, closeout reporting must distinguish deterministic fixture coverage from live operational evidence.

## 18. Expected implementation areas

Exact files are intentionally not frozen in this design. Based on current `dev`, implementation is expected to touch a bounded subset of:

- benefit evidence/provenance contracts;
- source document/snapshot format handling;
- benefit source run context;
- scoped benefit source orchestration;
- new PDF observation/adapter code;
- new HWPX observation/adapter code;
- optional OCR adapter boundary;
- format-specific provenance validators;
- targeted data tests/fixtures;
- Phase 4 handover/status documentation.

Implementation planning must inspect the latest repository before fixing exact file names.

## 19. Risks and mitigations

### PDF text without trustworthy layout

Risk: extracted text order may mix rows or businesses.

Mitigation: native success requires bounded physical structure, not merely non-empty text. Otherwise use OCR fallback or fail closed.

### OCR misrecognition

Risk: wrong business identity or benefit text.

Mitigation: OCR is an extraction method only; it does not raise binding confidence by itself and must pass normal identity and claim validation.

### Over-generalized parser

Risk: a large generic parser silently interprets unsupported layouts.

Mitigation: keep generic parsing bounded and use thin, deterministic layout-specific adapters only when required.

### Contract duplication

Risk: Phase 4 creates a parallel physical-evidence hierarchy.

Mitigation: minimally extend existing `SourceContentUnit`/`EvidenceSlice` first. Introduce a new shared type only when implementation evidence justifies it.

### Repeated expensive work

Risk: PDF parse or OCR cost scales with business count.

Mitigation: run-local snapshot/observation reuse and explicit count-based performance regressions.

### Processor changes mistaken for source changes

Risk: new parser/OCR versions alter semantics and appear as real-world changes.

Mitigation: extractor identity/version/material config belong to ExecutionFingerprint; source bytes remain evidence identity.

## 20. Approval gates for implementation

Before implementation may proceed:

1. this design spec must be reviewed and approved;
2. an implementation plan must be written from the then-current `dev`;
3. any shared contract/API change must be explicitly called out in the plan;
4. any new external dependency must be separately compared and approved before introduction;
5. implementation must remain Issue/PR-sized and use isolated work where appropriate.

This design approves the architectural direction only. It does not approve a particular library, schema change, parser implementation, or automatic production mutation.

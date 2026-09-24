# Phase 2 Milestone A1 — Scoped HTML Evidence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver an independently testable, opt-in HTML scoping path that prevents another business's source row from entering the target business's binding, extraction, or validation, while reusing fetched and parsed source content within one run.

**Architecture:** A row-independent source snapshot and parsed-unit template are shared within a run; each business receives its own SourceObservation and RelevantEvidenceSlice. A conservative generic table parser and deterministic locator prepare the slice. Additive scoped inputs integrate with the existing verification core; an explicitly selected scoped run never falls back to whole-document extraction.

**Tech Stack:** Existing PowerShell 7 / .NET runtime and repository assertion-style tests. No package, SDK, parser library, provider, database, or Android dependency is added.

**Spec:** `docs/superpowers/specs/2026-09-24-phase2-adapter-architecture-design.md`, written revision `d792fec2e29596e4a78339a86aba0d0732064db9`. The user approved moving from that written spec into planning in the conversation. This plan itself is awaiting review and execution-method selection.

**Code baseline:** `dev@1244df177888748173d352e735ab4882736e185c`.

**Plan scope:** Milestone A's first executable sub-project, A1. This is not a plan to implement every source-family adapter, and completing A1 does not complete Milestone A or Phase 2. Section 13 assigns the remaining spec obligations to separate plans rather than leaving them implicitly approved.

## Global Constraints

- `ProductionAction = NONE`
- "The system remains in Shadow Mode. No result automatically changes canonical data, seed data, or production state."
- "Hard identity conflicts must not be overridden by text similarity."
- "A multi-business directory must never fall back to full-document extraction merely because the locator failed."
- "LLM output remains a candidate until evidence validation succeeds."
- "No SourceKind or persistent schema extension is approved by this document."
- "A cached observation is never equivalent to currentness."
- Preserve the existing `BoundBenefitSource`, `BenefitVerificationResult`, `SourceKind`, and global reason-code contracts. New location diagnostics live in the new location contract, not in the global ReasonCode enum.
- No changes under `data/canonical/**`, `data/seed/**`, or `apps/**`; no changes to POI A/B/C algorithms, legacy release generators, auth, database, external API contracts, or dependencies.
- Synthetic fixtures must be labelled `SYNTHETIC_ALGORITHM_ONLY / TEST_ONLY`; their businesses and benefits are not operational data. No invented real-business evidence.
- Each implementation PR reports changed files, behavior, tests run, tests not run, risks, and next work. No automatic merge or future milestone is authorized by this plan alone.

## Review Focus

1. A shared URL reused by multiple canonical rows must not reuse the first row's SourceRowNumber, BusinessIdentity, binding result, or selected slice — Tasks 1, 5, 6.
2. Malformed tables, duplicate headers, partial retrieval, and unsupported spans must not silently become an empty complete directory or a unique match — Tasks 2, 3.
3. A claim whose text also exists in another business's row must fail when its reference or field lies outside the selected slice; an extractor-supplied SourceRepresentation cannot certify itself — Tasks 1, 4.
4. Locator ambiguity or an explicitly supplied null/invalid slice must not invoke the legacy whole-document path, an LLM, or discovery — Tasks 3, 4, 6.
5. Zero labelled/audited examples, zero selected rows, and unchanged source bodies must not manufacture perfect precision, zero real-world errors, or current applicability — Tasks 5, 6, 7.

---

## 1. Scope and repository reconciliation

The executable deliverable is: supply one or more canonical rows and an injected HTTP boundary, select `-UseScopedHtmlEvidence`, and receive row-specific, source-grounded HTML evidence with independent final results and preparation diagnostics.

Three findings from the pinned code change how the high-level design is concretized:

| Finding | Consequence for this plan |
| --- | --- |
| `Invoke-Phase2BenefitShadowMode` creates `$seenUrls` inside the row loop. | Existing deduplication is per row, not cross-business/per-run caching. Add a separate row-independent run context; do not claim the optimization already exists. |
| `ConvertTo-ValidatedBenefitEvidence` can validate against `Extraction.SourceRepresentation`. | Scoped validation must independently check the original snapshot, selected unit, and exact field reference before accepting any derived representation. URL equality alone is insufficient. |
| `compare-yangju-benefits.ps1` consumes `OfficialCsv`; the repository README describes the municipal notice's XLSX attachment. | An HTML entry URL is not proof that the underlying business evidence is HTML. Do not implement an invented Yangju HTML row parser or claim that XLSX is unnecessary merely because no canonical URL ends in `.xlsx`. |

The historical counts in the spec describe the pinned canonical/release-report partition, not current support coverage. In particular, 203 official HTML-entry rows are not 203 verified parseable rows, and a shared MMA entry URL is not proof that one response contains every business. Pagination, details, query parameters, and linked attachments must be inventoried in the source-family plan.

### A1 boundaries

In scope: common source/slice representation, restricted generic HTML table parsing, deterministic row location, optional slice inputs for binding/extraction/validation, opt-in runner integration, per-run raw/parse reuse, offline safety tests and documentation.

Out of scope: MMA/DDC/Paju/Yangju live-specific parsers, automatic pagination/detail traversal, linked attachment parsing, lifecycle/date-policy changes, composite-program assembly, PDF/XLSX/LLM/social/search providers, persistent caches, scheduling, production data changes, and a whole-247-row performance claim.

A2 will consume this working boundary for source-family adapters. A3 will measure the actual official-entry workload and perform human audit. These are separate deliverables, not missing steps in A1.

## 2. Files and PR-sized delivery

Use separate small PRs for the delivery groups below. Rebase/reconcile against the latest `dev` before starting each group; do not overwrite another contributor's changes.

| Group | Task | Files created or modified |
| --- | --- | --- |
| A1.1 | 1 | Create `tools/data/lib/benefit-evidence-location-contracts.ps1`; create `tools/data/test-benefit-evidence-location-contracts.ps1` |
| A1.2 | 2–3 | Create `tools/data/lib/benefit-evidence/convert-html-source-observation.ps1`; create `tools/data/lib/benefit-evidence/find-business-evidence-slice.ps1`; create their two `test-*.ps1` files; create the synthetic fixture described below |
| A1.3 | 4 | Modify `tools/data/lib/benefit-source/bind-benefit-source.ps1`, `tools/data/lib/benefit-evidence/extract-benefit-evidence.ps1`, `tools/data/lib/benefit-evidence/validate-benefit-evidence.ps1` and their existing three tests |
| A1.4 | 5 | Create `tools/data/lib/benefit-evidence/benefit-source-run-context.ps1`; create `tools/data/test-benefit-source-run-context.ps1` |
| A1.5 | 6–7 | Create `tools/data/lib/benefit-evidence/invoke-scoped-benefit-source.ps1`; modify `tools/data/invoke-phase2-benefit-shadow-mode.ps1`; create `tools/data/test-phase2-scoped-html.ps1`; modify `tools/data/README.md` |

Synthetic fixture path: `tools/data/testdata/benefit-evidence-location/synthetic.psd1`.

The existing `tools/data/test-phase2-benefit-shadow-mode.ps1` remains a legacy regression test, not the home for another large suite. The new integration tests use `test-phase2-scoped-html.ps1`.

A1.1 through A1.5 are delivery labels, not existing GitHub issue numbers. Create only the next needed issue during approved execution; do not preassign future work or report imaginary issue/PR IDs.

## 3. Concrete contract decisions for plan review

### 3.1 Shared snapshot, row-specific observation

The spec's `SourceObservation.SourceRowNumber` is preserved on the per-business wrapper. It must not be stored on the shared cache payload.

```text
BenefitSourceSnapshot                  shared, read-only by convention
  SnapshotId                          URL + ObservedAt + ContentHash digest
  SourceUrl                           exact source identity
  SourceFormat
  Text                                exact decoded Document.Text
  ObservedAt                          timestamp of actual retrieval
  ContentHash                         SHA-256 of UTF-8 Text, not of original bytes

Parsed source template                shared, read-only by convention
  SnapshotId
  AdapterId / AdapterVersion
  AdapterStatus                       COMPLETE / PARTIAL / FAILED / UNSUPPORTED
  ContentUnits[]
  Diagnostics[]

SourceObservation                     fresh wrapper for each business
  SourceRowNumber
  SnapshotId / SourceUrl / SourceFormat / ObservedAt
  Snapshot
  AdapterId / AdapterVersion / AdapterStatus
  ContentUnits[]
  Diagnostics[]
```

No cached object contains BusinessIdentity, OfficialityStatus, CurrentnessStatus, binding, a selected slice, or a final BenefitState. Qualification is still performed for the current candidate/business. Reuse of bytes is not reuse of authority.

### 3.2 Source units and slices

A unit contains its absolute source span and original header/cell references, in addition to readable text:

```text
SourceContentUnit
  SnapshotId
  UnitType                            TABLE_ROW in A1
  UnitReference                       HTML_TABLE_<physical index>_ROW_<physical index>
  RawStart / RawLength                offsets in Snapshot.Text
  RawFragment                         exact substring at those offsets
  RawEvidenceText                     decoded row text; not an authored summary
  StructuredFields                    canonical field name -> source cell value
  FieldReferences                     canonical field name -> header/cell spans
```

`FieldReferences` entries contain `HeaderStart`, `HeaderLength`, `CellStart`, `CellLength`, `OriginalHeader`, and `FieldReference`. Cell spans must be inside the row span. Header spans may be outside the row, but must belong to that row's same table. All offsets are relative to the full snapshot, not to a reindexed single-row mini-table.

A `RelevantEvidenceSlice` carries `SourceRowNumber`, the snapshot identity and hash, `SourceUrl`, `SourceFormat`, `ObservedAt`, `LocatorMethod`, `ScopeType`, `EvidenceReference`, the selected unit's raw span/text/fields, and `IdentityEvidence[]`. A1 permits one selected row per location result. Multiple independently plausible rows produce ambiguity; composite evidence is not assembled here.

Two provenance checks are mandatory:

1. The slice must be a member of the observation made from the current source document, with the same URL/hash/reference/span.
2. Each accepted claim must come from a field within that exact slice, not merely from somewhere in a document with the same URL.

### 3.3 Semantic result versus operational status

```text
EvidenceLocationResult
  SourceRowNumber
  OperationalStatus                   COMPLETE / PARTIAL / FAILED / UNSUPPORTED
  Status                              LOCATED / AMBIGUOUS / NOT_FOUND, or null
  Slices[]                            exactly one only for LOCATED in A1
  CandidateReferences[]               diagnostic only
  Diagnostics[]
```

`NOT_FOUND` is valid only when the supported observation was completely processed. It means not found in this observation, not absent from the entire website. A failed/incomplete parser sets non-COMPLETE operational status, null location status, and no usable slices. It must not increment a completed NOT_FOUND counter.

Diagnostic strings such as `LOCATOR_AMBIGUOUS`, `LOCATOR_IDENTITY_CONFLICT`, `HTML_TABLE_PARTIAL`, and `SLICE_PROVENANCE_MISMATCH` are private to the new location/preparation report. Map to existing core reasons as follows:

| Preparation condition | Existing core reason |
| --- | --- |
| row identity ambiguous | `BUSINESS_BINDING_AMBIGUOUS` |
| explicit candidate identity conflict | `BUSINESS_BINDING_CONFLICT` |
| supported complete observation contains no target | `SOURCE_NOT_FOUND` |
| unsupported structure/format | `SOURCE_UNSUPPORTED` |
| parser failure or incomplete usable extraction | `EXTRACTION_FAILED` |
| invalid slice or field provenance | `EXTRACTION_SOURCE_MISMATCH` |
| no evidence of current applicability | `CURRENTNESS_INSUFFICIENT` |

Do not append the new diagnostic names to the existing global reason-code list.

### 3.4 Additive API surface proposed by this plan

- `Get-BenefitBusinessBinding`: optional `-EvidenceSlice`.
- `Invoke-BenefitEvidenceExtraction`: optional `-EvidenceSlice`.
- `ConvertTo-ValidatedBenefitEvidence`: optional `-EvidenceSlice`.
- `Invoke-Phase2BenefitShadowMode`: optional `-UseScopedHtmlEvidence` switch and `-SourceRowNumbers [int[]]`.
- Existing parameters, return contracts, and legacy default behavior remain compatible.

An omitted slice permits the legacy path. An explicitly supplied `$null`, invalid slice, or failed location does not. Test `$PSBoundParameters.ContainsKey('EvidenceSlice')`, not only `$null -ne $EvidenceSlice`.

The new runner switch is opt-in so legacy callers are not silently migrated. In the scoped path there is no implicit legacy fallback. Future default activation is a separate rollout decision after source-family validation.

## 4. Execution preflight and common test convention

No implementation has been performed while writing this document. All code blocks below describe work and tests to execute after plan approval.

- [ ] Establish the isolated execution workspace through `using-git-worktrees`; inspect repository instructions in that workspace.
- [ ] Confirm the approved spec revision and this plan are present. If the docs branch is not yet merged, explicitly carry the reviewed docs into the implementation workspace; do not pretend they are already on `dev`.
- [ ] Record the actual base SHA and dirty state. Stop before overwriting unrelated work.

```powershell
git status --short
git rev-parse HEAD
pwsh --version
```

Run the existing suite before product changes, both independently and in the same process used by CI. Do not use CI as the only local edit/debug loop when `pwsh` is available.

```powershell
$ErrorActionPreference = 'Stop'
Get-ChildItem -LiteralPath tools/data -Filter 'test-*.ps1' |
  Sort-Object Name |
  ForEach-Object {
    & pwsh -NoProfile -File $_.FullName
    if ($LASTEXITCODE -ne 0) { throw "FAILED: $($_.Name)" }
  }
```

New tests use the repository's lightweight assertion approach. Put these helpers in each new test file before its assertions; do not add a test-framework dependency:

```powershell
$ErrorActionPreference = 'Stop'
function Assert-ScopeEqual {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -cne $Expected) { throw "$Message (expected: $Expected, actual: $Actual)" }
}
function Assert-ScopeTrue {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
function Assert-ScopeThrows {
    param([scriptblock]$Action, [string]$Message)
    $caught = $false
    try { & $Action } catch { $caught = $true }
    if (-not $caught) { throw $Message }
}
```

For every new behavior: add its assertion first, observe the intended failure, then implement. A syntax error is not proof of a behavioral RED. Record the actual RED/GREEN commands and output in the task report.

## 5. Task 1 — Source, observation, and slice contracts

**Files:**
- Create: `tools/data/lib/benefit-evidence-location-contracts.ps1`
- Test: `tools/data/test-benefit-evidence-location-contracts.ps1`

**Interfaces produced:**

```text
Get-BenefitEvidenceTextHash -Text [string] -> string
ConvertFrom-ScopeHtmlText -Text [string] -> string
New-BenefitSourceSnapshot -SourceUrl -SourceFormat -Text -ObservedAt -> snapshot
New-BenefitSourceContentUnit -Snapshot -UnitReference -RawStart -RawLength
  -RawEvidenceText -StructuredFields -FieldReferences -> unit
New-BenefitSourceObservation -SourceRowNumber -Snapshot -AdapterId
  -AdapterVersion -AdapterStatus -ContentUnits -Diagnostics -> observation
New-RelevantBenefitEvidenceSlice -Observation -Unit -IdentityEvidence -> slice
Assert-RelevantBenefitEvidenceSlice -Slice -Document -SourceRowNumber -> void
New-BenefitEvidenceLocationResult -SourceRowNumber -OperationalStatus
  -Status -Slices -CandidateReferences -Diagnostics -> location result
```

All arrays preserve empty/single/multiple-element shape. All new objects have `ContractType` and `ContractVersion=1`, validated locally in the new file. Do not register these types by modifying the existing global contract definition. `SourceRowNumber` must be greater than 1.

- [ ] **Step 1: Add failing contract tests.**

```powershell
. (Join-Path $PSScriptRoot 'lib/benefit-verification-contracts.ps1')
$path = Join-Path $PSScriptRoot 'lib/benefit-evidence-location-contracts.ps1'
if (-not (Test-Path -LiteralPath $path)) { throw 'Scoped evidence contracts are missing' }
. $path
$raw = '<tr><td>Sample A</td></tr>'
$snapshot = New-BenefitSourceSnapshot -SourceUrl 'https://city.example.go.kr/list' -SourceFormat 'HTML' -Text $raw -ObservedAt '2026-09-24T00:00:00Z'
$unit = New-BenefitSourceContentUnit -Snapshot $snapshot -UnitReference 'HTML_TABLE_1_ROW_1' -RawStart 0 -RawLength $raw.Length -RawEvidenceText 'Sample A' -StructuredFields @{} -FieldReferences @{}
$o2 = New-BenefitSourceObservation -SourceRowNumber 2 -Snapshot $snapshot -AdapterId 'HTML_GENERIC' -AdapterVersion '1' -AdapterStatus 'COMPLETE' -ContentUnits @($unit) -Diagnostics @()
$o3 = New-BenefitSourceObservation -SourceRowNumber 3 -Snapshot $snapshot -AdapterId 'HTML_GENERIC' -AdapterVersion '1' -AdapterStatus 'COMPLETE' -ContentUnits @($unit) -Diagnostics @()
$slice = New-RelevantBenefitEvidenceSlice -Observation $o2 -Unit $unit -IdentityEvidence @('NAME_MATCH')
$doc = New-BenefitSourceDocument -SourceRowNumber 2 -Url $snapshot.SourceUrl -SourceFormat HTML -FetchStatus COMPLETE -Text $raw -ObservedAt $snapshot.ObservedAt
Assert-RelevantBenefitEvidenceSlice -Slice $slice -Document $doc -SourceRowNumber 2
Assert-ScopeEqual $o3.SourceRowNumber 3 'Row wrapper must be independent'
Assert-ScopeTrue (-not ($snapshot.PSObject.Properties.Name -contains 'SourceRowNumber')) 'Shared snapshot must not carry a canonical row'
Assert-ScopeThrows { Assert-RelevantBenefitEvidenceSlice -Slice $slice -Document $doc -SourceRowNumber 3 } 'Cross-row slice must be rejected'
$changed = New-BenefitSourceDocument -SourceRowNumber 2 -Url $snapshot.SourceUrl -SourceFormat HTML -FetchStatus COMPLETE -Text '<tr><td>Sample B</td></tr>' -ObservedAt $snapshot.ObservedAt
Assert-ScopeThrows { Assert-RelevantBenefitEvidenceSlice -Slice $slice -Document $changed -SourceRowNumber 2 } 'Same URL with changed content is not the same snapshot'
Assert-ScopeThrows { New-BenefitSourceContentUnit -Snapshot $snapshot -UnitReference 'bad' -RawStart 999 -RawLength 8 -RawEvidenceText 'x' -StructuredFields @{} -FieldReferences @{} } 'Out-of-range source span must fail'
```

- [ ] **Step 2: Run RED.** `pwsh -NoProfile -File tools/data/test-benefit-evidence-location-contracts.ps1`. Expected initial failure: scoped evidence contracts missing.
- [ ] **Step 3: Implement constructors and validators.** Constructors must validate the object they return, not rely on callers remembering an assertion. Use an exact source span and a deterministic decoded-text helper. The hash is a snapshot identifier, not proof of publisher authenticity.

```powershell
function Get-BenefitEvidenceTextHash {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    } finally { $sha.Dispose() }
}
function ConvertFrom-ScopeHtmlText {
    param([AllowEmptyString()][string]$Text)
    $withoutTags = $Text -replace '<[^>]+>', ' '
    return (([Net.WebUtility]::HtmlDecode($withoutTags)) -replace '\s+', ' ').Trim()
}
```

Use the helper only on parser-approved fragments; it is not a general HTML parser. Strip actual tags before decoding entities so an encoded less-than expression is not accidentally treated as markup.

`Assert-RelevantBenefitEvidenceSlice` checks type/version, row, exact URL, source format, retrieval timestamp, ContentHash, nonnegative/in-bounds span, exact RawFragment equality, decoded evidence text, all field spans, and nonempty stable references. Read-only convention is supplemented by making defensive copies of mutable field maps at row/slice boundaries.

- [ ] **Step 4: Extend RED/GREEN cases** for empty URL/text/reference, unknown type/version, negative offsets, forged StructuredFields, duplicate field references, a slice from a different observation, and explicit null. An empty observation is valid only as an operational result without a usable slice.
- [ ] **Step 5: Run GREEN and existing contract regression.**

```powershell
& pwsh -NoProfile -File tools/data/test-benefit-evidence-location-contracts.ps1
if ($LASTEXITCODE) { throw 'Scoped contracts failed' }
& pwsh -NoProfile -File tools/data/test-benefit-verification-contracts.ps1
if ($LASTEXITCODE) { throw 'Legacy contracts regressed' }
git add tools/data/lib/benefit-evidence-location-contracts.ps1 tools/data/test-benefit-evidence-location-contracts.ps1
git commit -m 'feat: define source-grounded evidence slice contracts'
```

Deliverable: shared content can be wrapped for multiple canonical rows without sharing their identity, and forged source spans cannot be accepted.

## 6. Task 2 — Restricted generic HTML observation parser

**Files:**
- Create: `tools/data/lib/benefit-evidence/convert-html-source-observation.ps1`
- Create: `tools/data/testdata/benefit-evidence-location/synthetic.psd1`
- Test: `tools/data/test-convert-html-source-observation.ps1`

**Consumes:** Task 1 snapshot, unit, and observation constructors.

**Produces:**

```text
ConvertTo-BenefitHtmlTemplate -Snapshot -> parsed template
ConvertTo-BenefitHtmlObservation -Document -> SourceObservation
```

The convenience observation function constructs a snapshot from `Document.Text`, calls the template parser, then creates a row-specific wrapper. The template function never accepts BusinessIdentity or SourceRowNumber; Task 5 caches that function's result.

- [ ] **Step 1: Add fixture and failing parsing tests.** The fixture contains two synthetic businesses, not live-source claims.

```powershell
@{
    FixtureKind = 'SYNTHETIC_ALGORITHM_ONLY'
    Status = 'TEST_ONLY'
    Html = @'
<table><thead><tr><th>업소명</th><th>주소</th><th>전화번호</th><th>할인</th></tr></thead>
<tbody>
<tr><td>검증가게 A</td><td>경기도 검증시 샘플로 12</td><td>031-000-0012</td><td>10% 할인</td></tr>
<tr><td>검증가게 B</td><td>경기도 검증시 샘플로 99</td><td>031-000-0099</td><td>30% 할인</td></tr>
</tbody></table>
'@
}
```

```powershell
. (Join-Path $PSScriptRoot 'lib/benefit-verification-contracts.ps1')
. (Join-Path $PSScriptRoot 'lib/benefit-evidence-location-contracts.ps1')
$parser = Join-Path $PSScriptRoot 'lib/benefit-evidence/convert-html-source-observation.ps1'
if (-not (Test-Path $parser)) { throw 'HTML observation parser is missing' }
. $parser
$f = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'testdata/benefit-evidence-location/synthetic.psd1')
$doc = New-BenefitSourceDocument -SourceRowNumber 2 -Url 'https://city.example.go.kr/list' -SourceFormat HTML -FetchStatus COMPLETE -Text $f.Html -ObservedAt '2026-09-24T00:00:00Z'
$o = ConvertTo-BenefitHtmlObservation -Document $doc
Assert-ScopeEqual $o.AdapterStatus 'COMPLETE' 'Supported table parses completely'
Assert-ScopeEqual @($o.ContentUnits).Count 2 'Both business rows must be retained before location'
Assert-ScopeEqual $o.ContentUnits[0].StructuredFields.BusinessName '검증가게 A' 'Name must come from its cell'
Assert-ScopeEqual $o.ContentUnits[1].StructuredFields.BenefitDescription '30% 할인' 'Second row must not disappear'
foreach ($u in @($o.ContentUnits)) {
    Assert-ScopeEqual $o.Snapshot.Text.Substring($u.RawStart, $u.RawLength) $u.RawFragment 'Unit must point into original HTML'
}
$namesOnly = $f.Html -replace '<th>할인</th>', '<th>비고</th>'
$d2 = New-BenefitSourceDocument -SourceRowNumber 2 -Url $doc.Url -SourceFormat HTML -FetchStatus COMPLETE -Text $namesOnly -ObservedAt $doc.ObservedAt
$o2 = ConvertTo-BenefitHtmlObservation -Document $d2
Assert-ScopeEqual @($o2.ContentUnits).Count 2 'Participation-only rows must remain locatable'
Assert-ScopeTrue (-not $o2.ContentUnits[0].StructuredFields.Contains('BenefitDescription')) 'Unknown remarks header must not manufacture a benefit field'
```

- [ ] **Step 2: Run RED.** `pwsh -NoProfile -File tools/data/test-convert-html-source-observation.ps1`.
- [ ] **Step 3: Implement the supported subset, not a universal HTML parser.** Accept balanced, non-nested tables with one unambiguous header row, unique recognized headers, and matching data-cell counts. Preserve all candidate tables and their physical indices; do not return after the first table. A table needs a recognized business-name column, not necessarily a discount column.

Field mapping is exact after whitespace normalization:

```powershell
$headerMap = @{
    '업소명'='BusinessName'; '업체명'='BusinessName'; '사업장명'='BusinessName'; '상호'='BusinessName'
    '주소'='Address'; '소재지'='Address'; '소재지도로명주소'='Address'
    '전화번호'='Phone'; '연락처'='Phone'; '전화'='Phone'
    '지점'='Branch'; '지점명'='Branch'
    '할인'='BenefitDescription'; '할인정보'='BenefitDescription'; '할인내용'='BenefitDescription'; '혜택'='BenefitDescription'
    '적용대상'='EligibleTarget'; '이용조건'='UsageCondition'; '인증방법'='VerificationMethod'
}
```

Two original headers mapping to the same canonical field make that candidate table ambiguous, rather than overwriting one value in a hashtable. Do not infer phone/address from the canonical row or from page footers.

Use match/group indices to retain absolute row, header, and cell spans. For each selected cell, the construction rule is:

```powershell
$fieldValue = ConvertFrom-ScopeHtmlText -Text $snapshot.Text.Substring($cellStart, $cellLength)
$fields[$canonicalField] = $fieldValue
$references[$canonicalField] = [pscustomobject]@{
    HeaderStart = $headerStart; HeaderLength = $headerLength
    CellStart = $cellStart; CellLength = $cellLength
    OriginalHeader = $originalHeader
    FieldReference = "$unitReference/$canonicalField"
}
```

These variables are the current full-document match coordinates and mapped header, not coordinates in a rewritten table. Use bounded regex execution time where regex is used. Do not evaluate scripts, follow links, or invent missing closing tags. Reject nested tables and `rowspan`/`colspan` greater than 1 in this generic version. Later source-family parsers may support a broader structure with their own tests.

A failed fetch is FAILED; non-HTML or unsupported layout is UNSUPPORTED; a malformed candidate business table among parsed tables makes the result PARTIAL and prevents a conclusive location; a completely processed supported empty business table can yield COMPLETE with zero units. An arbitrary page without a supported business table is UNSUPPORTED, not a complete empty directory.

- [ ] **Step 4: Pin edge behavior with table-driven tests.** For nested tables, duplicate canonical headers, mismatched cell counts, truncated rows, and merged cells, assert `AdapterStatus -ne 'COMPLETE'`. For two valid tables, assert both sets of rows survive. For `&amp;`, encoded angle brackets, `<br>`, and inline formatting, assert decoded values and original spans both remain correct. For a page-title date, assert no ValidUntil or lifecycle field is created.

```powershell
foreach ($bad in @(
    ($f.Html -replace '<th>주소</th>', '<th>업체명</th>'),
    ($f.Html -replace '<td>10% 할인</td>', '<td colspan="2">10% 할인</td>'),
    ($f.Html -replace '</tbody></table>', '')
)) {
    $d = New-BenefitSourceDocument -SourceRowNumber 2 -Url $doc.Url -SourceFormat HTML -FetchStatus COMPLETE -Text $bad -ObservedAt $doc.ObservedAt
    Assert-ScopeTrue ((ConvertTo-BenefitHtmlObservation -Document $d).AdapterStatus -ne 'COMPLETE') 'Malformed table cannot masquerade as a completed directory'
}
```

- [ ] **Step 5: Run GREEN and commit only parser/fixture/test files.**

```powershell
& pwsh -NoProfile -File tools/data/test-convert-html-source-observation.ps1
if ($LASTEXITCODE) { throw 'HTML parser tests failed' }
git add tools/data/lib/benefit-evidence/convert-html-source-observation.ps1 tools/data/test-convert-html-source-observation.ps1 tools/data/testdata/benefit-evidence-location/synthetic.psd1
git commit -m 'feat: parse source-grounded business table units'
```

## 7. Task 3 — Deterministic business-row locator

**Files:**
- Create: `tools/data/lib/benefit-evidence/find-business-evidence-slice.ps1`
- Test: `tools/data/test-find-business-evidence-slice.ps1`

**Consumes:** SourceObservation, Phase 1 NormalizedBusiness, `ConvertTo-IdentityComparisonText`, `Get-NormalizedAddressParts`, `Get-BenefitBindingAddressConflicts`.

**Produces:** `Find-BenefitBusinessEvidence -Observation -Business -CanonicalPhone '' -> EvidenceLocationResult`.

- [ ] **Step 1: Add a positive, wrong-row, and missing-row RED.**

```powershell
. (Join-Path $PSScriptRoot 'lib/benefit-source/bind-benefit-source.ps1')
. (Join-Path $PSScriptRoot 'lib/benefit-evidence/convert-html-source-observation.ps1')
$locator = Join-Path $PSScriptRoot 'lib/benefit-evidence/find-business-evidence-slice.ps1'
if (-not (Test-Path $locator)) { throw 'Business evidence locator is missing' }
. $locator
$f = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'testdata/benefit-evidence-location/synthetic.psd1')
$d = New-BenefitSourceDocument -SourceRowNumber 2 -Url 'https://city.example.go.kr/list' -SourceFormat HTML -FetchStatus COMPLETE -Text $f.Html -ObservedAt '2026-09-24T00:00:00Z'
$o = ConvertTo-BenefitHtmlObservation -Document $d
$b = New-NormalizedBusiness -SourceRowNumber 2 -OriginalName '검증가게 A' -NormalizedName '검증가게A' -BaseName '검증가게 A' -PreferredAddress '경기도 검증시 샘플로 12' -Province '경기도' -City '검증시' -RoadName '샘플로' -BuildingMain '12' -AddressParseStatus COMPLETE
$r = Find-BenefitBusinessEvidence -Observation $o -Business $b -CanonicalPhone '031-000-0012'
Assert-ScopeEqual $r.Status 'LOCATED' 'Exact business/address must locate'
Assert-ScopeEqual @($r.Slices).Count 1 'A1 must isolate one business row'
Assert-ScopeTrue ($r.Slices[0].RawEvidenceText -notmatch '검증가게 B|30%') 'Another business must not leak into the slice'
$missing = New-NormalizedBusiness -SourceRowNumber 2 -OriginalName '없는가게' -NormalizedName '없는가게' -AddressParseStatus UNPARSED
Assert-ScopeEqual (Find-BenefitBusinessEvidence -Observation $o -Business $missing).Status 'NOT_FOUND' 'Absent business in complete observation stays not found'
$wrong = New-NormalizedBusiness -SourceRowNumber 2 -OriginalName '검증가게 A' -NormalizedName '검증가게A' -PreferredAddress '경기도 검증시 샘플로 23' -Province '경기도' -City '검증시' -RoadName '샘플로' -BuildingMain '23' -AddressParseStatus COMPLETE
$conflict = Find-BenefitBusinessEvidence -Observation $o -Business $wrong -CanonicalPhone '031-000-0012'
Assert-ScopeTrue ($conflict.Status -ne 'LOCATED') 'Phone agreement must not override building-number conflict'
Assert-ScopeTrue ($conflict.Diagnostics.Code -contains 'LOCATOR_IDENTITY_CONFLICT') 'Explicit conflict must remain distinguishable from absence'
```

- [ ] **Step 2: Run RED.** `pwsh -NoProfile -File tools/data/test-find-business-evidence-slice.ps1`.
- [ ] **Step 3: Implement the decision table.** Normalize the source's observed name and identity fields, not canonical values injected into source gaps. Require compatible explicit full name plus at least one strong corroborator: full address, explicit branch, or phone. Do not use substring/base-name coincidence as sole name compatibility. Source address parsing uses empty metadata arguments; canonical locality must not fill missing source locality.

```powershell
$sourceAddress = Get-NormalizedAddressParts -RoadAddress $fields.Address -LotAddress '' -MetadataProvince '' -MetadataArea ''
$conflicts = @(Get-BenefitBindingAddressConflicts -Business $Business -AddressParts $sourceAddress)
foreach ($detail in @('Floor', 'Unit')) {
    if ($Business.$detail -and $sourceAddress.$detail -and
        (ConvertTo-IdentityComparisonText $Business.$detail) -cne (ConvertTo-IdentityComparisonText $sourceAddress.$detail)) {
        $conflicts += "${detail}_CONFLICT"
    }
}
```

Explicit branch/phone conflicts are also retained when the source identity is attributable. Unknown/unparsed floor, unit, or branch is not a matching signal. Existing identity-library behavior is reused but not weakened or rewritten.

Decision rules:

- Non-COMPLETE adapter result: copy the operational failure, null Status, empty slices.
- No plausible business-name candidate: NOT_FOUND. An address/phone match with an explicit different name is retained as an identity-review diagnostic, not silently promoted.
- Exactly one safely corroborated candidate, all alternatives explicitly excluded, no hard conflict: LOCATED.
- Multiple plausible rows, one name-only unresolved alternative, or insufficient corroboration: AMBIGUOUS.
- Only identity-conflicting named candidates: AMBIGUOUS with `LOCATOR_IDENTITY_CONFLICT`, empty usable slices. The source-processing task maps it to the existing binding-conflict reason and RED review.
- Do not choose a row because its discount agrees with canonical data.

- [ ] **Step 4: Add RED/GREEN cases for duplicate names, explicit branches, identical discounts on different rows, missing phones, floor/unit conflicts, multiple tables, and reversed row order.** Selection must be order-independent. Insert another name-compatible row with insufficient identifiers and require AMBIGUOUS rather than choosing the first row. Keep existing real-source-cited hard-conflict fixtures in their original suites; synthetic mutations must remain labelled synthetic.
- [ ] **Step 5: Run tests and commit.**

```powershell
& pwsh -NoProfile -File tools/data/test-find-business-evidence-slice.ps1
if ($LASTEXITCODE) { throw 'Locator tests failed' }
& pwsh -NoProfile -File tools/data/test-normalize-business.ps1
if ($LASTEXITCODE) { throw 'Identity regression failed' }
& pwsh -NoProfile -File tools/data/test-evaluate-poi-match.ps1
if ($LASTEXITCODE) { throw 'POI safety regression failed' }
git add tools/data/lib/benefit-evidence/find-business-evidence-slice.ps1 tools/data/test-find-business-evidence-slice.ps1
git commit -m 'feat: locate business evidence without guessing'
```

## 8. Task 4 — Optional scoped binding, extraction, and independent validation

**Files modified:**
- `tools/data/lib/benefit-source/bind-benefit-source.ps1`
- `tools/data/lib/benefit-evidence/extract-benefit-evidence.ps1`
- `tools/data/lib/benefit-evidence/validate-benefit-evidence.ps1`
- `tools/data/test-bind-benefit-source.ps1`
- `tools/data/test-extract-benefit-evidence.ps1`
- `tools/data/test-validate-benefit-evidence.ps1`

**Interfaces:** Append optional `-EvidenceSlice` to the three existing entrypoints listed in Section 3.4. Add `Test-ScopedBenefitExtractedClaim -Claim -Document -EvidenceSlice` in the validation file, returning the existing ValidatedBenefitClaim type.

- [ ] **Step 1: Append failing scoped binding/extraction tests to the existing suites.** In each test, import the parser and locator, load `synthetic.psd1`, construct the exact A business as in Task 3, and derive the slice from the parser/locator rather than hand-authoring trusted fields. Preserve the legacy assertions already in each file.

```powershell
$c = New-BenefitSourceCandidate -SourceRowNumber 2 -Url $d.Url -SourceKind PUBLIC_OFFICIAL
$q = New-QualifiedBenefitSource -Candidate $c -Document $d -OfficialityStatus VERIFIED_OFFICIAL -CurrentnessStatus UNKNOWN
$bound = Get-BenefitBusinessBinding -Source $q -Business $b -CanonicalPhone '031-000-0012' -EvidenceSlice $r.Slices[0]
Assert-ScopeEqual $bound.BusinessBindingStatus 'STRONG' 'Scoped address must bind without reading the other row'
$x = Invoke-BenefitEvidenceExtraction -Source $bound -Document $d -EvidenceSlice $r.Slices[0]
Assert-ScopeEqual @($x.Claims | Where-Object Value -eq '10% 할인').Count 1 'Extract only the selected benefit cell'
Assert-ScopeEqual @($x.Claims | Where-Object Value -eq '30% 할인').Count 0 'Reject other-row benefit'
$v = ConvertTo-ValidatedBenefitEvidence -Extraction $x -Document $d -EvidenceSlice $r.Slices[0]
Assert-ScopeEqual $v.Claims[0].ValidationStatus 'VALIDATED' 'Selected original cell must independently validate'
Assert-ScopeThrows { Get-BenefitBusinessBinding -Source $q -Business $b -EvidenceSlice $null } 'Explicit null is not the legacy no-slice path'
```

- [ ] **Step 2: Run RED individually.** Initially expect unknown `EvidenceSlice` parameter, not an unrelated parser failure.
- [ ] **Step 3: Add the explicit scoped branches.**

```powershell
if ($PSBoundParameters.ContainsKey('EvidenceSlice')) {
    if ($null -eq $EvidenceSlice) { throw 'Explicit scoped evidence cannot be null' }
    Assert-RelevantBenefitEvidenceSlice -Slice $EvidenceSlice -Document $Document -SourceRowNumber $Document.SourceRowNumber
    # In the binding function, Document is Source.Document and the expected row is Business.SourceRowNumber.
}
```

Binding consumes the slice's verified observed identity fields, with the existing conflict precedence and a mandatory conflict check for the new locator's floor/unit evidence. Preserve original Source.Document for provenance; do not overwrite it with a labelled synthetic mini-document. No source field is filled from canonical data.

Scoped extraction maps only recognized detail fields, without manufacturing lifecycle claims:

```powershell
$detailMap = @{
    BenefitDescription='BENEFIT_DESCRIPTION'
    EligibleTarget='ELIGIBLE_TARGET'
    UsageCondition='USAGE_CONDITION'
    VerificationMethod='VERIFICATION_METHOD'
}
foreach ($field in @('BenefitDescription','EligibleTarget','UsageCondition','VerificationMethod')) {
    if (-not $EvidenceSlice.StructuredFields.Contains($field)) { continue }
    $value = [string]$EvidenceSlice.StructuredFields[$field]
    if ([string]::IsNullOrWhiteSpace($value)) { continue }
    $reference = [string]$EvidenceSlice.FieldReferences[$field].FieldReference
    $claim = New-ExtractedBenefitClaim -ClaimType $detailMap[$field] -Value $value -EvidenceText $value -EvidenceReference $reference -SourceUrl $Document.Url -ExtractionMethod 'SCOPED_HTML_CELL'
    Assert-ExtractedBenefitClaim $claim
    $claims.Add($claim)
}
```

Initialize `$claims` as an empty generic List[object] in this branch. Return the existing extraction-result shape. A syntactically complete extraction with absent detail/lifecycle fields is not automatically an operational failure or a current benefit. The existing evaluator may correctly keep the row unresolved.

Do not emit BENEFIT_EXISTENCE, CURRENT_APPLICABILITY, VALID_FROM, or VALID_UNTIL from a generic directory caption, a retrieval timestamp, or an amount cell in A1. Do not implement a new renewal/expiry/program-resolution policy. This deliberately separates successful evidence location from complete benefit verification.

Scoped validation ignores extractor-authored SourceRepresentation as an authority. First validate slice membership against Document.Text. For each claim, require the expected detail ClaimType for the referenced original header, matching source URL, reference membership in the selected slice, source-backed cell text, and exact original value/numeric tokens. Return INVALID plus `EXTRACTION_SOURCE_MISMATCH` on a mismatch. Do not fall back to searching the entire source for that value. Legacy validation with no EvidenceSlice retains its old behavior for existing callers.

- [ ] **Step 4: Add adversarial validation RED/GREEN tests.**

```powershell
$foreign = New-ExtractedBenefitClaim -ClaimType BENEFIT_DESCRIPTION -Value '30% 할인' -EvidenceText '30% 할인' -EvidenceReference $o.ContentUnits[1].FieldReferences.BenefitDescription.FieldReference -SourceUrl $d.Url -ExtractionMethod 'SCOPED_HTML_CELL'
$forged = [pscustomobject]@{ SourceRowNumber=2; Status='COMPLETE'; Claims=@($foreign); ReasonCodes=@(); SourceRepresentation='30% 할인' }
$rejected = ConvertTo-ValidatedBenefitEvidence -Extraction $forged -Document $d -EvidenceSlice $r.Slices[0]
Assert-ScopeEqual $rejected.Claims[0].ValidationStatus 'INVALID' 'Other-row text cannot certify itself through SourceRepresentation'
$wrongMeaning = New-ExtractedBenefitClaim -ClaimType ELIGIBLE_TARGET -Value '10% 할인' -EvidenceText '10% 할인' -EvidenceReference $r.Slices[0].FieldReferences.BenefitDescription.FieldReference -SourceUrl $d.Url -ExtractionMethod 'SCOPED_HTML_CELL'
$rejectedMeaning = Test-ScopedBenefitExtractedClaim -Claim $wrongMeaning -Document $d -EvidenceSlice $r.Slices[0]
Assert-ScopeEqual $rejectedMeaning.ValidationStatus 'INVALID' 'Correct bytes under the wrong claim type are not valid evidence'
```

Also test equal text in both businesses with the wrong field reference; a source URL or content hash change; altered StructuredFields; claim references to page footers; explicit null slice for all three entrypoints; and that no injected extractor is invoked by the A1 scoped branch. The unscoped legacy tests must remain GREEN.

- [ ] **Step 5: Run all three suites and the legacy Phase 2 integration suite, then commit.**

```powershell
foreach ($test in @('test-bind-benefit-source.ps1','test-extract-benefit-evidence.ps1','test-validate-benefit-evidence.ps1','test-phase2-benefit-shadow-mode.ps1')) {
    & pwsh -NoProfile -File (Join-Path 'tools/data' $test)
    if ($LASTEXITCODE) { throw "FAILED: $test" }
}
git add tools/data/lib/benefit-source/bind-benefit-source.ps1 tools/data/lib/benefit-evidence/extract-benefit-evidence.ps1 tools/data/lib/benefit-evidence/validate-benefit-evidence.ps1 tools/data/test-bind-benefit-source.ps1 tools/data/test-extract-benefit-evidence.ps1 tools/data/test-validate-benefit-evidence.ps1
git commit -m 'feat: bind extract and validate only selected evidence'
```

## 9. Task 5 — Row-independent per-run fetch and parse reuse

**Files:**
- Create: `tools/data/lib/benefit-evidence/benefit-source-run-context.ps1`
- Test: `tools/data/test-benefit-source-run-context.ps1`

**Interfaces:**

```text
New-BenefitSourceRunContext -> RunContext
Get-BenefitRunSourceDocument -Context -Candidate -RequestInvoker -> fresh BenefitSourceDocument
Get-BenefitRunHtmlObservation -Context -Document -> fresh SourceObservation
```

RunContext owns rowless response payloads, parsed templates, a `Metrics` object, and bounded attempt records. The context is created once for one top-level scoped run and never kept in global state. Its implementation uses ordinal dictionaries; it must not merge case-sensitive paths or distinct query parameters.

- [ ] **Step 1: Write the cross-row reuse RED.**

```powershell
. (Join-Path $PSScriptRoot 'lib/benefit-source/discover-official-benefit-sources.ps1')
. (Join-Path $PSScriptRoot 'lib/benefit-evidence/convert-html-source-observation.ps1')
$contextPath = Join-Path $PSScriptRoot 'lib/benefit-evidence/benefit-source-run-context.ps1'
if (-not (Test-Path $contextPath)) { throw 'Source run context is missing' }
. $contextPath
$f = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'testdata/benefit-evidence-location/synthetic.psd1')
$counter = [pscustomobject]@{ Count=0 }
$html = $f.Html
$http = { param($Uri); $counter.Count++; [pscustomobject]@{StatusCode=200;ContentType='text/html';Text=$html;Bytes=$null} }.GetNewClosure()
$ctx = New-BenefitSourceRunContext
$c2 = New-BenefitSourceCandidate -SourceRowNumber 2 -Url 'https://city.example.go.kr/list?category=1' -SourceKind PUBLIC_OFFICIAL
$c3 = New-BenefitSourceCandidate -SourceRowNumber 3 -Url $c2.Url -SourceKind PUBLIC_OFFICIAL
$d2 = Get-BenefitRunSourceDocument -Context $ctx -Candidate $c2 -RequestInvoker $http
$d3 = Get-BenefitRunSourceDocument -Context $ctx -Candidate $c3 -RequestInvoker $http
$o2 = Get-BenefitRunHtmlObservation -Context $ctx -Document $d2
$o3 = Get-BenefitRunHtmlObservation -Context $ctx -Document $d3
Assert-ScopeEqual $counter.Count 1 'Shared request must execute once'
Assert-ScopeEqual $ctx.Metrics.AdapterParseCount 1 'Shared content must parse once'
Assert-ScopeEqual $d2.SourceRowNumber 2 'First row number is retained'
Assert-ScopeEqual $d3.SourceRowNumber 3 'Second row number is retained'
Assert-ScopeEqual $o3.SourceRowNumber 3 'Parsed template must receive a new row wrapper'
Assert-ScopeEqual $d2.ObservedAt $d3.ObservedAt 'Cache hit preserves the retrieval observation time'
$c4 = New-BenefitSourceCandidate -SourceRowNumber 4 -Url 'https://city.example.go.kr/list?category=2' -SourceKind PUBLIC_OFFICIAL
$null = Get-BenefitRunSourceDocument -Context $ctx -Candidate $c4 -RequestInvoker $http
Assert-ScopeEqual $counter.Count 2 'Different query parameters require different retrievals'
```

- [ ] **Step 2: Run RED.** `pwsh -NoProfile -File tools/data/test-benefit-source-run-context.ps1`.
- [ ] **Step 3: Implement reuse without identity or authorization leakage.** Use the existing `Get-BenefitSourceDocument` boundary on a cache miss and retain only rowless content/fetch metadata. On every hit reconstruct a new BenefitSourceDocument using the current Candidate.SourceRowNumber and the original ObservedAt. Never return the first row's document by reference.

```powershell
$document = New-BenefitSourceDocument -SourceRowNumber $Candidate.SourceRowNumber -Url $payload.Url -SourceFormat $payload.SourceFormat -FetchStatus $payload.FetchStatus -ContentType $payload.ContentType -Text $payload.Text -Bytes $payload.Bytes -ObservedAt $payload.ObservedAt -ReasonCodes @($payload.ReasonCodes)
```

The raw-fetch key is the exact request URL within one fixed RequestInvoker profile. Retain path/query case and parameters; do not remove category/page parameters or combine superficially similar URLs. A1 has one transport profile per context; reject switching the configured RequestInvoker within an existing context. No authorization/session-bearing responses may be reused between contexts.

The parsed key is SnapshotId + AdapterId + AdapterVersion. Cache the rowless template only. Observation and slice wrappers are regenerated and defensively copy mutable maps. Locator/binding/evaluation are always per business and are not cached by URL.

No transport retry is added in A1: one miss invokes the injected boundary once; a failed result is retained for this run and cannot trigger a storm across 159 referencing rows. A new run may retry normally. A failed payload must not expose an old successful body. Network attempts, cache hits, parses, and parse reuse have separate integer counters. `ExternalFetchCount` counts actual RequestInvoker calls, not wrapper calls.

- [ ] **Step 4: Add RED/GREEN tests for** a failed URL shared by many rows, a second run, case-sensitive paths, distinct query strings, mutated first-row fields, changed content under the same URL in a new run, and separate request profiles. Assert no cross-run reuse and no invented fresh ObservedAt on hits.
- [ ] **Step 5: Run GREEN and commit.**

```powershell
& pwsh -NoProfile -File tools/data/test-benefit-source-run-context.ps1
if ($LASTEXITCODE) { throw 'Source reuse tests failed' }
git add tools/data/lib/benefit-evidence/benefit-source-run-context.ps1 tools/data/test-benefit-source-run-context.ps1
git commit -m 'feat: reuse source payloads without sharing business state'
```

## 10. Task 6 — Opt-in scoped Shadow Mode integration

**Files:**
- Create: `tools/data/lib/benefit-evidence/invoke-scoped-benefit-source.ps1`
- Modify: `tools/data/invoke-phase2-benefit-shadow-mode.ps1`
- Test: `tools/data/test-phase2-scoped-html.ps1`

**Interfaces:**

```text
Invoke-ScopedPhase2BenefitSourceCandidate
  -Candidate -Business -CanonicalPhone -RunContext -RequestInvoker
  -> source record with existing Candidate/Document/Qualified/Bound/Extraction/Validation fields
     plus Observation, LocationResult, Slices, PreparationDiagnostics

Invoke-Phase2BenefitShadowMode
  existing parameters + -UseScopedHtmlEvidence + -SourceRowNumbers [int[]]
  -> existing Results/Rows/EvidenceDiagnostics/Summary plus PreparationSummary
```

`SourceRowNumbers`, when provided, must match Rows.Count, contain distinct values greater than 1, and cannot be combined with an explicitly supplied SourceRowNumberOffset. Without it, preserve the existing offset formula. This prevents filtered non-contiguous canonical input from losing its original row identity.

- [ ] **Step 1: Add a two-business/same-source RED with sparse original row numbers.**

```powershell
. (Join-Path $PSScriptRoot 'invoke-phase2-benefit-shadow-mode.ps1')
$f = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'testdata/benefit-evidence-location/synthetic.psd1')
$rows = @(
    [pscustomobject]@{業種='TEST';業所='TEST';業種Status='TEST_ONLY';業所Status='SYNTHETIC_ALGORITHM_ONLY';업소명='검증가게 A';시도='경기도';시군구='검증시';소재지도로명주소='경기도 검증시 샘플로 12';소재지지번주소='';업소전화번호='031-000-0012';할인정보='10% 할인';적용대상='';이용조건='';인증방법='';출처유형='지자체 공식 자료';출처URL='https://city.example.go.kr/list';최근확인일='2026-09-24'},
    [pscustomobject]@{업소명='검증가게 B';시도='경기도';시군구='검증시';소재지도로명주소='경기도 검증시 샘플로 99';소재지지번주소='';업소전화번호='031-000-0099';할인정보='30% 할인';적용대상='';이용조건='';인증방법='';출처유형='지자체 공식 자료';출처URL='https://city.example.go.kr/list';최근확인일='2026-09-24'}
)
$html = $f.Html
$counter = [pscustomobject]@{Count=0}
$http = { param($Uri); $counter.Count++; [pscustomobject]@{StatusCode=200;ContentType='text/html';Text=$html;Bytes=$null} }.GetNewClosure()
$run = Invoke-Phase2BenefitShadowMode -Rows $rows -SourceRowNumbers @(75,118) -UseScopedHtmlEvidence -RequestInvoker $http
Assert-ScopeEqual $counter.Count 1 'Two canonical rows share one fetch'
Assert-ScopeEqual $run.PreparationSummary.AdapterParseCount 1 'Two canonical rows share one parse'
Assert-ScopeEqual $run.Results[0].SourceRowNumber 75 'Sparse source row identity survives'
Assert-ScopeEqual $run.Results[1].BusinessIdentity.SourceRowNumber 118 'Business identity remains row-specific'
$a = @($run.EvidenceDiagnostics | Where-Object SourceRowNumber -eq 75)[0]
$b = @($run.EvidenceDiagnostics | Where-Object SourceRowNumber -eq 118)[0]
Assert-ScopeEqual @($a.ValidatedClaims | Where-Object Value -eq '30% 할인').Count 0 'B claim cannot reach A'
Assert-ScopeEqual @($b.ValidatedClaims | Where-Object Value -eq '10% 할인').Count 0 'A claim cannot reach B'
Assert-ScopeEqual @($a.ValidatedClaims | Where-Object Value -eq '10% 할인').Count 1 'A positive detail must not be discarded'
Assert-ScopeEqual $run.Results[0].BenefitState 'NEEDS_VERIFICATION' 'Located detail alone does not prove lifecycle/currentness'
Assert-ScopeTrue (@($run.Results | Where-Object ProductionAction -ne 'NONE').Count -eq 0) 'All outputs remain shadow-only'
```

The fixture's declaration, not extra operational schema fields, identifies it as synthetic. Keep both input rows limited to normal canonical columns when implementing this example.

- [ ] **Step 2: Run RED.** `pwsh -NoProfile -File tools/data/test-phase2-scoped-html.ps1`. Expected initial failure: unknown scoped-run parameter.
- [ ] **Step 3: Implement the scoped source path and explicit mode dispatch.** Retain the actual order required by the current APIs:

```text
candidate -> per-run fetch -> existing source qualification
          -> parsed observation -> locator -> scoped binding
          -> scoped extraction -> independently scoped validation
          -> existing comparison/evaluation -> final result
```

Qualification needs retrieved content; do not literally implement the high-level spec diagram as qualification before any fetch. Restrict A1 scoped execution to eligible existing PUBLIC_OFFICIAL HTML sources. Other types receive unsupported/unresolved diagnostics; they are not guessed or silently promoted.

For unqualified sources: preserve qualification evidence, produce no accepted claims, and stop the current source path. For non-COMPLETE parsing or non-LOCATED location: return empty extraction/validation claims and the mapped existing reasons. A hard identity conflict is preserved as a BoundBenefitSource conflict so existing evaluation returns RED. No nullable slice may be passed to a downstream function to activate its legacy fallback.

For a located source: retain the original document and pass the same validated slice explicitly to binding, extraction, and validation. If binding is not STRONG, do not admit decisive claims from that source. Do not reuse whole-page lifecycle/currentness text from a different unit; A1 scoped generic detail extraction has no lifecycle proof and must leave that question unresolved.

In scoped mode the supplied DiscoveryInvoker, UnstructuredExtractor, PdfTextExtractor, and SpreadsheetExtractor must all be null. Reject a contradictory invocation before any external request. Their absence does not mean the system attempted and failed every future provider. Record `DiscoveryExecution='NOT_REQUESTED'`, `LlmInvocationCount=0`, and the available preparation reason. For the existing evaluator's operational input, completed planned source preparation may use DiscoveryStatus COMPLETE without asserting that an external search was executed.

Runner dispatch must be explicit:

```powershell
if ($UseScopedHtmlEvidence) {
    $sourceRecord = Invoke-ScopedPhase2BenefitSourceCandidate -Candidate $candidate -Business $business -CanonicalPhone $canonicalPhone -RunContext $runContext -RequestInvoker $RequestInvoker
} else {
    $sourceRecord = Invoke-Phase2BenefitSourceCandidate -Candidate $candidate -Business $business -CanonicalPhone $canonicalPhone -RequestInvoker $countingRequest -UnstructuredExtractor $UnstructuredExtractor -SpreadsheetExtractor $SpreadsheetExtractor -PdfTextExtractor $PdfTextExtractor
}
```

Create the scoped RunContext outside the business loop. Keep the existing unscoped loop/fallback behavior and its regression expectations unchanged. Limit the new source helper to source preparation; do not duplicate the final benefit evaluator.

`PreparationSummary` contains `SourceEvaluations`, `UniqueRequestKeys`, `ExternalFetchCount`, `FetchCacheHits`, `AdapterParseCount`, `AdapterReuseCount`, `LocatorLocated`, `LocatorAmbiguous`, `LocatorNotFound`, `LocationNotAttempted`, and `LlmInvocationCount`. Location counters are per business/source evaluation, not per unique URL. Sum location statuses plus not-attempted to SourceEvaluations. Count adapter operational failures separately from absence. Retain the existing Get-Phase2BenefitShadowSummary -Rows interface; do not reintroduce a mandatory hidden metadata argument.

Each diagnostic retains row number, source URL, snapshot hash/time, adapter version, original unit/field references, raw evidence slice, binding evidence, validated claims, and mapped reasons. Export still uses the existing protected-path implementation; no new arbitrary output path or production writer is introduced.

- [ ] **Step 4: Add RED/GREEN integration regressions.**

```powershell
Assert-ScopeThrows { Invoke-Phase2BenefitShadowMode -Rows $rows -SourceRowNumbers @(75) -UseScopedHtmlEvidence -RequestInvoker $http } 'Mismatched row mapping must fail before fetching'
Assert-ScopeThrows { Invoke-Phase2BenefitShadowMode -Rows $rows -SourceRowNumbers @(75,75) -UseScopedHtmlEvidence -RequestInvoker $http } 'Duplicate source rows must fail'
Assert-ScopeThrows { Invoke-Phase2BenefitShadowMode -Rows $rows -UseScopedHtmlEvidence -RequestInvoker $http -DiscoveryInvoker { throw 'must not call' } } 'A1 cannot silently enable discovery'
$failure = Invoke-Phase2BenefitShadowMode -Rows $rows -UseScopedHtmlEvidence -RequestInvoker { param($Uri); throw 'timeout' }
Assert-ScopeEqual @($failure.Results | Where-Object BenefitState -eq 'ENDED').Count 0 'Transport failure is not ending evidence'
Assert-ScopeEqual @($failure.Results | Where-Object ReviewClass -eq 'GREEN').Count 0 'Failed retrieval cannot become GREEN'
```

Add an ambiguous duplicate-business source, failed parser, another business's ending phrase, a historical page heading, and a source with the correct discount but wrong address. Verify no full-document fallback, no cross-business claims, no unexpected provider calls, and no fabricated lifecycle result. An empty Rows array is supported and returns empty arrays, zero operational counts, and no requests; use AllowEmptyCollection where mandatory array binding would otherwise reject it.

- [ ] **Step 5: Run new and legacy integration suites, direct summary-interface tests, then commit.**

```powershell
& pwsh -NoProfile -File tools/data/test-phase2-scoped-html.ps1
if ($LASTEXITCODE) { throw 'Scoped integration failed' }
& pwsh -NoProfile -File tools/data/test-phase2-benefit-shadow-mode.ps1
if ($LASTEXITCODE) { throw 'Legacy Phase 2 regression failed' }
& pwsh -NoProfile -File tools/data/test-phase1-poi-shadow-mode.ps1
if ($LASTEXITCODE) { throw 'Phase 1 regression failed' }
git add tools/data/lib/benefit-evidence/invoke-scoped-benefit-source.ps1 tools/data/invoke-phase2-benefit-shadow-mode.ps1 tools/data/test-phase2-scoped-html.ps1
git commit -m 'feat: add opt-in scoped HTML shadow verification'
```

## 11. Task 7 — Integration closeout and truthful reporting

**Files:**
- Modify: `tools/data/README.md`
- Extend: `tools/data/test-phase2-scoped-html.ps1` for counter/empty-input/export assertions.

**Produces:** documented runnable scoped usage, reproducible offline verification, and A1 completion evidence. No population performance claim.

- [ ] **Step 1: Pin counter reconciliation and the empty-input case before implementation.**

```powershell
$p = $run.PreparationSummary
Assert-ScopeEqual ($p.LocatorLocated + $p.LocatorAmbiguous + $p.LocatorNotFound + $p.LocationNotAttempted) $p.SourceEvaluations 'Location counters must reconcile'
Assert-ScopeEqual $p.ExternalFetchCount 1 'Fetch count is physical boundary invocation count'
Assert-ScopeEqual $p.LlmInvocationCount 0 'A1 has no LLM'
$empty = Invoke-Phase2BenefitShadowMode -Rows @() -UseScopedHtmlEvidence -RequestInvoker { throw 'empty run must not fetch' }
Assert-ScopeEqual @($empty.Results).Count 0 'Empty input must stay empty'
Assert-ScopeEqual $empty.PreparationSummary.ExternalFetchCount 0 'Empty input has zero requests'
```

- [ ] **Step 2: Export to a controlled OS temporary directory, read the CSV/JSON back, and assert** the original SourceRowNumber, exact source URL, slice reference, and validation state survive. Reuse existing tests that reject `data/canonical`, `data/seed`, and `apps` outputs. Do not claim broader symlink/path-hardening was implemented by A1.
- [ ] **Step 3: Document scope and limitations in README.** Include this invocation shape with an injected transport, not a hardcoded provider/key:

```powershell
. ./tools/data/invoke-phase2-benefit-shadow-mode.ps1
$run = Invoke-Phase2BenefitShadowMode -Rows $selectedRows -SourceRowNumbers $originalCsvRowNumbers -UseScopedHtmlEvidence -RequestInvoker $httpInvoker
$run.PreparationSummary
```

Explain how the caller supplies its selected canonical rows, their original CSV row numbers, and one already-authorized RequestInvoker. No secret should be pasted into a report or committed. `LOCATED` means evidence attributed to a business, not benefit ACTIVE; no required coverage quota is used to loosen matching.

The quality report must distinguish measured tests from unaudited production data:

```text
FixtureSafety
  FixtureCaseCount
  WrongRowSelections
  CrossBusinessClaimLeaks
  FalseGreenCases
  FalseEndedCases

LiveAudit
  Status = NOT_RUN for A1
  AuditedRowCount = 0
  LocatedPrecision = null
  FalseGreenCount = null
  FalseEndedCount = null
```

Do not put guessed zeros into LiveAudit. The legacy Summary.FalseGreenCount is meaningful only for supplied GoldenExpectations; without labels it is not evidence of zero real-world false-GREEN. A1 positive locator and extraction cases must pass so a reject-everything implementation cannot meet the gate. A later human audit must explicitly record sample selection and denominator; all observed incorrect selections or GREEN/ENDED claims block the relevant adapter release.

- [ ] **Step 4: Run the full deterministic suite in both execution modes.**

```powershell
$ErrorActionPreference = 'Stop'
Get-ChildItem -LiteralPath tools/data -Filter 'test-*.ps1' | Sort-Object Name | ForEach-Object {
    & pwsh -NoProfile -File $_.FullName
    if ($LASTEXITCODE -ne 0) { throw "FAILED: $($_.Name)" }
}
# Same-process form used by the existing CI job:
Get-ChildItem -LiteralPath tools/data -Filter 'test-*.ps1' | Sort-Object Name | ForEach-Object { & $_.FullName }
```

- [ ] **Step 5: Check protected paths and scope.**

```powershell
git diff --check
git diff --exit-code origin/dev -- data/canonical data/seed apps
if ($LASTEXITCODE -ne 0) { throw 'Protected-path change detected' }
git diff --name-only origin/dev
```

Use the actual reviewed base SHA in a moving collaborative branch if origin/dev changes during execution. Also inspect untracked files before asserting non-write, not only the tracked diff.

- [ ] **Step 6: Verify Android CI on the final implementation PR HEAD.** Existing workflow commands are:

```powershell
Push-Location apps/android
try {
    & ./gradlew assembleDebugUnitTest testDebugUnitTest --stacktrace
    if ($LASTEXITCODE) { throw 'Android unit tests failed' }
    & ./gradlew lintDebug assembleDebug --stacktrace
    if ($LASTEXITCODE) { throw 'Android lint/build failed' }
} finally { Pop-Location }
```

On Windows use `./gradlew.bat`; the CI uses the Linux wrapper with JDK 17. If local Android tooling is unavailable, record NOT_RUN locally and verify the exact PR HEAD's `verify-data` and `verify` jobs through GitHub. Do not infer that an old green run covers a newer commit.

- [ ] **Step 7: Commit docs and obtain a whole-branch review.**

```powershell
git add tools/data/README.md tools/data/test-phase2-scoped-html.ps1
git commit -m 'docs: document scoped evidence use and safety limits'
```

Use requesting-code-review and verification-before-completion at execution time. An independent reviewer is preferable; if the execution environment lacks a reviewer/subagent tool, say that review was self-review and do not label it independent. No task or reviewer may remove a failing assertion merely to achieve GREEN without demonstrating the assertion contradicts the approved specification.

## 12. A1 completion evidence and risks

A1 is complete only when the optional path works end-to-end on supported offline HTML fixtures, legacy regressions pass, original row identity and source membership are preserved, cross-business leakage is absent in the tested cases, per-run request/parse reuse is measured, protected paths are unchanged, and final-HEAD CI is verified.

Remaining risks must be reported explicitly:

- Generic HTML coverage is intentionally narrow; real source-family pages may require pagination, different structures, or attachments.
- Selecting the right row does not establish currentness, program identity, complete conditions, or lifecycle state.
- Existing legacy callers remain on their original behavior until explicitly migrated; the new guard cannot be claimed to protect an unscoped call.
- URL equality alone is not provenance: cached payloads and claims require the snapshot/unit/field checks above.
- The existing core's campaign/expiry/composite-evidence semantics are not redesigned here; automatic renewal or different programs must not be silently collapsed.
- Human live audit is not an automated assistant self-review. Its absence must remain visible.

## 13. Remaining Milestone A plans and spec coverage

| Spec obligation | A1 task or next separately scoped deliverable |
| --- | --- |
| Common observations/units/slices | Tasks 1–3 |
| Scoped binding/extraction/validation; legacy compatibility | Task 4 |
| Per-run fetch/parse reuse | Task 5 |
| Shadow integration and reason-based stopping | Task 6 |
| Contract/Golden safety, counter semantics, docs/CI | Tasks 1–7 |
| DDC/Paju/MMA/Yangju source-specific strategies | A2 source-family plans after capability inventory |
| Actual official-entry workload run, source-family smoke, human audit | A3 validation plan after A2 |
| PDF/XLSX, LLM, official SNS/blog, discovery providers | Later milestones; separate dependency/access/design approvals |
| Cross-run caching, history, scheduling | Deferred from this architecture's initial implementation |

Before A2, inventory each family using actual retrieved content and repository provenance: entry URL, retrieved URL/request identity, response format, pagination/completeness, attachment links, adapter capability, and missing evidence type. Do not assume a public HTML landing page contains all records. Treat an attachment-backed Yangju row as an attachment requirement, not as solved by an empty HTML parser. A2 may reuse known DDC/Paju parsing knowledge but cannot import old release-candidate decisions as current evidence.

A3 derives the held set by original canonical CSV row numbers minus the pinned official-release-candidate report, not by guessing from `혜택상태`. Pin both input hashes and retain the original row mapping. Include unresolved/inaccessible/unsupported inputs in the report denominator. Measure located coverage separately from resolved-benefit coverage. All GREEN/ENDED results require explicit human audit; a source-family/identity-risk-stratified LOCATED sample is also audited. Zero observed errors in that audit is not a population error-rate guarantee.

If A2 finds a required contract change beyond these additive interfaces, stop and amend the relevant design before implementing it. Do not use A1 approval to add a PDF package, LLM, paid search service, SNS authentication, or a database.

## 14. Planning self-review and execution handoff

Planning checks performed against the approved spec and pinned code:

- Each new function consumed across tasks is named in an Interfaces block.
- No new global SourceKind/ReasonCode or existing result-shape replacement is required.
- Fetch/cache sharing and business-specific wrappers are separated.
- Slice proof is checked against original source content, not only extractor output.
- Operational failure is separate from complete NOT_FOUND and from semantic ending.
- A1 and the remaining A2/A3 acceptance scopes are explicit.
- Test/CI commands are planned commands, not claims that implementation tests have run.

Recommended execution method: **Native / executing-plans**, with task-sized delivery and whole-branch review. The tasks share closely related evidence interfaces; one implementation context reduces accidental signature drift. A capable independent reviewer should be used only when actually available. The ChatGPT session must not promise an unavailable subagent.

Before implementation, the user reviews this plan and confirms the execution method. The next action after that approval is the A1.1 contract task in an isolated workspace, not all of Phase 2 at once.

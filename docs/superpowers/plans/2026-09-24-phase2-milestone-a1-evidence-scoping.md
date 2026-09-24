# Phase 2 Milestone A1 — Scoped HTML Evidence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver an independently testable, opt-in HTML scoping path that prevents another business's row from entering the target business's binding, extraction, or validation, while reusing fetched and parsed content within one run.

**Architecture:** Share row-independent source snapshots and parsed-unit templates; create a fresh observation and evidence slice for each canonical business. A restricted generic table parser and deterministic locator prepare the slice. Additive scoped inputs connect it to the existing verification core; an explicitly selected scoped run cannot fall back to whole-document extraction.

**Tech Stack:** Existing PowerShell 7 / .NET runtime and repository assertion-style tests. No parser package, SDK, provider, database, or Android dependency is added.

**Spec:** `docs/superpowers/specs/2026-09-24-phase2-adapter-architecture-design.md`, originally written at revision `d792fec2e29596e4a78339a86aba0d0732064db9`. The user reviewed and approved the written spec and this plan. Native execution was selected. A1.1 merged via PR #52; A1.2 is the next delivery.

**Plan-time code baseline:** `dev@1244df177888748173d352e735ab4882736e185c`.

**Current execution checkpoint:** A1.1 is merged via PR #52; `dev@650b3f96ccd89c9b2c26ed13ce99915ad4e69275` at documentation integration time. A1.2 must re-read latest `dev` before implementation.

**Plan scope:** Milestone A's first executable sub-project, A1. Completing A1 does not complete Milestone A or Phase 2. A2 source-family adapters and A3 live validation receive separate plans after A1 provides a working boundary.

## Global Constraints

- `ProductionAction = NONE`
- "The system remains in Shadow Mode. No result automatically changes canonical data, seed data, or production state."
- "Hard identity conflicts must not be overridden by text similarity."
- "A multi-business directory must never fall back to full-document extraction merely because the locator failed."
- "LLM output remains a candidate until evidence validation succeeds."
- "No SourceKind or persistent schema extension is approved by this document."
- "A cached observation is never equivalent to currentness."
- Preserve the existing BoundBenefitSource, BenefitVerificationResult, SourceKind, and global ReasonCode contracts. New location diagnostics belong to the new preparation objects, not to the global enum.
- No changes under `data/canonical/**`, `data/seed/**`, or `apps/**`; no POI A/B/C algorithm, release-generator, authentication, database, external API, or dependency changes.
- Synthetic fixtures are labelled `SYNTHETIC_ALGORITHM_ONLY / TEST_ONLY`; their benefits and businesses are not operational data. Never invent evidence for real businesses.
- Each implementation report includes files, behavior, tests run, tests not run, remaining risks, and next work. This plan does not authorize automatic merge or future milestones.

## Review Focus

1. Shared URLs must not share a canonical row number, BusinessIdentity, binding result, or selected slice — Tasks 1, 5, 6.
2. Malformed tables, duplicate headers, unsupported spans, and partial observations must not become a complete empty directory or a unique match — Tasks 2, 3.
3. A value present elsewhere on the same page must fail when its field reference is outside the selected slice; SourceRepresentation cannot certify itself — Tasks 1, 4.
4. Ambiguity or an explicitly supplied null/invalid slice must not invoke legacy whole-document processing, LLM, or discovery — Tasks 3, 4, 6.
5. Empty inputs, unlabelled data, and unchanged source bodies must not manufacture perfect precision, zero real-world errors, or current applicability — Tasks 5, 6, 7.

---

## 1. Repository reconciliation and delivery boundary

The executable deliverable is: supply canonical rows and an injected HTTP boundary, opt into `-UseScopedHtmlEvidence`, and receive independent row results, source-grounded slices, and preparation diagnostics.

| Finding in pinned code | Planning consequence |
| --- | --- |
| `Invoke-Phase2BenefitShadowMode` creates `$seenUrls` inside the business loop. | Existing deduplication is per row. Cross-business fetch/parse caching is new work, not an existing capability. |
| `ConvertTo-ValidatedBenefitEvidence` can use `Extraction.SourceRepresentation` as validation text. | Scoped validation independently verifies the original snapshot, selected unit, original header, and cell reference. Matching a URL is insufficient. |
| `compare-yangju-benefits.ps1` consumes `OfficialCsv`; the README describes an XLSX attachment behind the municipal notice. | An HTML entry URL does not prove the underlying evidence is HTML. Do not invent a Yangju HTML row parser or conclude XLSX is unnecessary from URL suffixes alone. |

The spec's workload counts are a pinned canonical/release-report partition, not support measurements. In particular, 203 official HTML-entry rows are not 203 verified parseable rows. A shared MMA entry URL does not prove one response contains all businesses. A2 must inspect response bodies, pagination, details, queries, and attachments before promising coverage. PDF URL classification also does not prove that the file is text-readable.

### A1 scope

In scope: source/slice representations, restricted generic HTML table parsing, deterministic location, optional scoped inputs for binding/extraction/validation, opt-in runner integration, per-run payload/parse reuse, offline safety tests, documentation.

Out of scope: live source-family parsers, automatic pagination/detail traversal, attachment parsing, lifecycle/date-policy changes, composite-program assembly, LLM/PDF/XLSX/social/search providers, persistent caches, scheduling, production data changes, and a whole-workload accuracy claim.

A1 separates correct evidence attribution from complete benefit verification. A successfully located detail can still legitimately produce NEEDS_VERIFICATION because lifecycle/currentness is not established.

## 2. Files and PR-sized delivery

| Delivery group | Task | Files |
| --- | --- | --- |
| A1.1 | 1 | Create `tools/data/lib/benefit-evidence-location-contracts.ps1`, `tools/data/test-benefit-evidence-location-contracts.ps1`, and the two fixture/support files below |
| A1.2 | 2–3 | Create `tools/data/lib/benefit-evidence/convert-html-source-observation.ps1`, `tools/data/lib/benefit-evidence/find-business-evidence-slice.ps1`, `tools/data/test-convert-html-source-observation.ps1`, `tools/data/test-find-business-evidence-slice.ps1` |
| A1.3 | 4 | Modify `tools/data/lib/benefit-source/bind-benefit-source.ps1`, `tools/data/lib/benefit-evidence/extract-benefit-evidence.ps1`, `tools/data/lib/benefit-evidence/validate-benefit-evidence.ps1`, and their existing three tests |
| A1.4 | 5 | Create `tools/data/lib/benefit-evidence/benefit-source-run-context.ps1` and `tools/data/test-benefit-source-run-context.ps1` |
| A1.5 | 6–7 | Create `tools/data/lib/benefit-evidence/invoke-scoped-benefit-source.ps1` and `tools/data/test-phase2-scoped-html.ps1`; modify `tools/data/invoke-phase2-benefit-shadow-mode.ps1` and `tools/data/README.md` |

Fixture: `tools/data/testdata/benefit-evidence-location/synthetic.psd1`.
Test-only helpers: `tools/data/testdata/benefit-evidence-location/test-support.ps1`.

The existing `test-phase2-benefit-shadow-mode.ps1` remains the legacy regression suite, not the home for another large suite. A1.1–A1.5 are delivery labels, not existing GitHub issue IDs. Create only the next needed issue during approved execution; do not preassign future work. Each group receives its own small PR and reviewed base; no force pushes or unrelated cleanup.

## 3. Contract decisions proposed for plan approval

### 3.1 Share content, never business-specific decisions

```text
BenefitSourceSnapshot                 shared payload; no SourceRowNumber
  SnapshotId                          hash of URL, ObservedAt, ContentHash
  SourceUrl / SourceFormat
  Text                                exact decoded Document.Text
  ObservedAt                          actual retrieval observation time
  ContentHash                         SHA-256 of UTF-8 Text, not wire bytes

Parsed template                       shared; no SourceRowNumber
  SnapshotId
  AdapterId / AdapterVersion
  AdapterStatus                       COMPLETE / PARTIAL / FAILED / UNSUPPORTED
  ContentUnits[] / Diagnostics[]

SourceObservation                     new wrapper for each business
  SourceRowNumber
  SnapshotId / SourceUrl / SourceFormat / ObservedAt
  Snapshot
  AdapterId / AdapterVersion / AdapterStatus
  ContentUnits[] / Diagnostics[]
```

Never cache BusinessIdentity, officiality, currentness, binding, a selected slice, or final state by URL. Qualification is performed for the current candidate/business. Copy mutable field/reference maps defensively at wrapper boundaries; no caller mutates shared content.

### 3.2 Original spans and selected evidence

```text
SourceContentUnit
  SnapshotId / UnitType                TABLE_ROW in A1
  UnitReference                       physical HTML_TABLE_<n>_ROW_<n>
  TableStart / TableLength             original table span
  RawStart / RawLength / RawFragment   original row span and substring
  RawEvidenceText                     deterministic decoded row text
  StructuredFields                    canonical field -> observed cell value
  FieldReferences                     canonical field -> header/cell reference
```

Each field reference contains HeaderStart, HeaderLength, CellStart, CellLength, OriginalHeader, and FieldReference. Coordinates are absolute offsets into Snapshot.Text. Headers and cells must belong to the same original table, and cell spans must lie inside the selected row. Preserve physical references; do not reindex a selected row to row 1.

RelevantEvidenceSlice contains SourceRowNumber, snapshot identity/hash, SourceUrl, SourceFormat, ObservedAt, LocatorMethod, ScopeType, EvidenceReference, the unit's table/row spans/text/fields, and IdentityEvidence[]. It is constructed from a unit actually present in the observation. One usable row per location result is supported in A1. Composite/multi-row program inference is excluded.

A slice's hash is not proof of source authenticity. The provenance boundary consists of trusted retrieval/parsing, original span/header/cell checks, deterministic location, and business binding. Do not accept arbitrary hand-authored slices as authoritative just because their own hash matches.

### 3.3 Operational failure is not semantic absence

```text
EvidenceLocationResult
  SourceRowNumber
  OperationalStatus                   COMPLETE / PARTIAL / FAILED / UNSUPPORTED
  Status                              LOCATED / AMBIGUOUS / NOT_FOUND, or null
  Slices[]                            one for LOCATED; otherwise empty in A1
  CandidateReferences[]               diagnostic only
  Diagnostics[]                       { Code, Stage, EvidenceReference, Detail }
```

NOT_FOUND is valid only after complete supported processing of this observation. It does not claim site-wide absence. Parsing failure/partial input sets a non-COMPLETE operational status, null Status, and no usable slice.

Diagnostic Code strings are local to these objects. Map them to existing core reasons without changing the global enum:

| Preparation condition | Existing core reason |
| --- | --- |
| ambiguous row identity | BUSINESS_BINDING_AMBIGUOUS |
| explicit candidate identity conflict | BUSINESS_BINDING_CONFLICT |
| complete observation with no target | SOURCE_NOT_FOUND |
| unsupported structure/format | SOURCE_UNSUPPORTED |
| failed/incomplete parsing | EXTRACTION_FAILED |
| invalid slice/field provenance | EXTRACTION_SOURCE_MISMATCH |
| no current applicability evidence | CURRENTNESS_INSUFFICIENT |

### 3.4 Additive entrypoints

Append optional `-EvidenceSlice` to Get-BenefitBusinessBinding, Invoke-BenefitEvidenceExtraction, and ConvertTo-ValidatedBenefitEvidence. Append `-UseScopedHtmlEvidence` and `-SourceRowNumbers [int[]]` to Invoke-Phase2BenefitShadowMode. Preserve existing parameters and legacy defaults.

An omitted slice permits legacy behavior. An explicitly supplied null/invalid slice does not: use `$PSBoundParameters.ContainsKey('EvidenceSlice')`. Scoped mode is opt-in; switching the production default is a separate rollout decision after source-family validation.

## 4. Execution preflight

This document contains planned commands and test code, not completed implementation or test results.

- [ ] Establish an isolated workspace with using-git-worktrees and read repository instructions.
- [ ] Confirm the reviewed spec/plan are available. If the docs branch is not merged, carry the reviewed documents explicitly; do not pretend they are on dev.
- [ ] Record actual base SHA and dirty/untracked files. Stop before overwriting unrelated work.

```powershell
git status --short
git rev-parse HEAD
pwsh --version
```

- [ ] Run existing baseline tests before product edits. Later repeat both the independent-process and CI same-process forms.

```powershell
$ErrorActionPreference = 'Stop'
Get-ChildItem -LiteralPath tools/data -Filter 'test-*.ps1' | Sort-Object Name | ForEach-Object {
    & pwsh -NoProfile -File $_.FullName
    if ($LASTEXITCODE -ne 0) { throw "FAILED: $($_.Name)" }
}
```

Use local pwsh for iteration when available. Do not run repeated full Android CI jobs as the only debugging loop. For each behavior, write the assertion, observe the intended RED, then implement and obtain GREEN. A syntax error is not a behavioral RED. Preserve actual logs/commands in each task report.

## 5. Task 1 — Source and slice contracts with test support

**Files:** Create the contract file, its test file, synthetic.psd1, and test-support.ps1 listed in A1.1.

**Interfaces produced:**

```text
Get-BenefitEvidenceTextHash -Text -> string
ConvertFrom-ScopeHtmlText -Text -> string
Get-BenefitScopedHeaderMap -> IDictionary
New-BenefitSourceSnapshot -SourceUrl -SourceFormat -Text -ObservedAt -> snapshot
New-BenefitSourceContentUnit -Snapshot -UnitReference -TableStart -TableLength
  -RawStart -RawLength -RawEvidenceText -StructuredFields -FieldReferences -> unit
New-BenefitSourceObservation -SourceRowNumber -Snapshot -AdapterId -AdapterVersion
  -AdapterStatus -ContentUnits -Diagnostics -> observation
New-RelevantBenefitEvidenceSlice -Observation -Unit -IdentityEvidence -> slice
Assert-RelevantBenefitEvidenceSlice -Slice -Document -SourceRowNumber -> void
New-BenefitEvidenceLocationResult -SourceRowNumber -OperationalStatus -Status
  -Slices -CandidateReferences -Diagnostics -> location result
```

Snapshot/unit/observation/slice/location objects each have a local ContractType and ContractVersion=1. Constructors validate what they return. SourceRowNumber must exceed 1. Empty/single/multiple arrays retain array shape. Do not modify the global contract registry.

- [ ] **Step 1: Add the test fixture and helpers, then a failing contract test.** Fixture contents:

```powershell
@{
    FixtureKind = 'SYNTHETIC_ALGORITHM_ONLY'
    Status = 'TEST_ONLY'
    Html = @'
<table><thead><tr><th>업소명</th><th>주소</th><th>전화번호</th><th>할인</th></tr></thead>
<tbody>
<tr><td>테스트가게 A</td><td>서울특별시 마포구 테스트로 12</td><td>02-0000-0012</td><td>10% 할인</td></tr>
<tr><td>테스트가게 B</td><td>서울특별시 마포구 테스트로 99</td><td>02-0000-0099</td><td>30% 할인</td></tr>
</tbody></table>
'@
}
```

Test-support.ps1 is test-only and contains the following complete helpers. Runtime code must never import it.

```powershell
$ErrorActionPreference = 'Stop'
$dataRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
. (Join-Path $dataRoot 'lib/benefit-verification-contracts.ps1')
. (Join-Path $dataRoot 'lib/identity/normalize-business.ps1')
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
function Get-ScopeTestHtml {
    $fixture = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'synthetic.psd1')
    return [string]$fixture.Html
}
function New-ScopeTestDocument {
    param([int]$RowNumber=2, [string]$Html=(Get-ScopeTestHtml), [string]$Url='https://city.example.go.kr/list')
    return New-BenefitSourceDocument -SourceRowNumber $RowNumber -Url $Url -SourceFormat HTML -FetchStatus COMPLETE -Text $Html -ObservedAt '2026-09-24T00:00:00Z'
}
function New-ScopeTestRow {
    param([string]$Name='테스트가게 A', [string]$Building='12', [string]$Phone='02-0000-0012', [string]$Benefit='10% 할인')
    return [pscustomobject]@{
        업소명=$Name; 시도='서울특별시'; 시군구='마포구'
        소재지도로명주소="서울특별시 마포구 테스트로 $Building"; 소재지지번주소=''
        업소전화번호=$Phone; 할인정보=$Benefit; 적용대상=''; 이용조건=''; 인증방법=''
        출처유형='지자체 공식 자료'; 출처URL='https://city.example.go.kr/list'; 최근확인일='2026-09-24'
    }
}
function New-ScopeTestBusiness {
    param([int]$RowNumber=2, [string]$Name='테스트가게 A', [string]$Building='12')
    return ConvertTo-NormalizedBusiness -Row (New-ScopeTestRow -Name $Name -Building $Building) -SourceRowNumber $RowNumber
}
```

Contract test:

```powershell
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-location/test-support.ps1')
$path = Join-Path $PSScriptRoot 'lib/benefit-evidence-location-contracts.ps1'
if (-not (Test-Path $path)) { throw 'Scoped evidence contracts are missing' }
. $path
$rowHtml = '<tr><td>Sample A</td></tr>'
$html = '<table>' + $rowHtml + '</table>'
$d = New-ScopeTestDocument -Html $html
$s = New-BenefitSourceSnapshot -SourceUrl $d.Url -SourceFormat HTML -Text $d.Text -ObservedAt $d.ObservedAt
$u = New-BenefitSourceContentUnit -Snapshot $s -UnitReference 'HTML_TABLE_1_ROW_1' -TableStart 0 -TableLength $html.Length -RawStart 7 -RawLength $rowHtml.Length -RawEvidenceText 'Sample A' -StructuredFields @{} -FieldReferences @{}
$o2 = New-BenefitSourceObservation -SourceRowNumber 2 -Snapshot $s -AdapterId HTML_GENERIC -AdapterVersion '1' -AdapterStatus COMPLETE -ContentUnits @($u) -Diagnostics @()
$o3 = New-BenefitSourceObservation -SourceRowNumber 3 -Snapshot $s -AdapterId HTML_GENERIC -AdapterVersion '1' -AdapterStatus COMPLETE -ContentUnits @($u) -Diagnostics @()
$slice = New-RelevantBenefitEvidenceSlice -Observation $o2 -Unit $u -IdentityEvidence @()
Assert-RelevantBenefitEvidenceSlice -Slice $slice -Document $d -SourceRowNumber 2
Assert-ScopeEqual $o3.SourceRowNumber 3 'Independent row wrapper'
Assert-ScopeTrue (-not ($s.PSObject.Properties.Name -contains 'SourceRowNumber')) 'Shared payload must be rowless'
Assert-ScopeThrows { Assert-RelevantBenefitEvidenceSlice -Slice $slice -Document $d -SourceRowNumber 3 } 'Reject cross-row slice'
$changed = New-ScopeTestDocument -Html ($html -replace 'Sample A','Sample B')
Assert-ScopeThrows { Assert-RelevantBenefitEvidenceSlice -Slice $slice -Document $changed -SourceRowNumber 2 } 'Same URL is not same content'
foreach ($invalid in @($null, [pscustomobject]@{ContractType='Other';ContractVersion=1}, [pscustomobject]@{ContractType='RelevantEvidenceSlice';ContractVersion=99})) {
    Assert-ScopeThrows { Assert-RelevantBenefitEvidenceSlice -Slice $invalid -Document $d -SourceRowNumber 2 } 'Reject missing or invalid contract'
}
Assert-ScopeThrows { New-BenefitSourceContentUnit -Snapshot $s -UnitReference bad -TableStart 0 -TableLength $html.Length -RawStart 999 -RawLength 8 -RawEvidenceText x -StructuredFields @{} -FieldReferences @{} } 'Reject out-of-range span'
```

An empty field map in this contract test does not establish a locatable business; Task 3 still requires observed identity corroboration.

- [ ] **Step 2: Run RED.** `pwsh -NoProfile -File tools/data/test-benefit-evidence-location-contracts.ps1`; expected initial failure is the missing contract file.
- [ ] **Step 3: Implement constructors/validators and shared text/header helpers.**

```powershell
function Get-BenefitEvidenceTextHash {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function ConvertFrom-ScopeHtmlText {
    param([AllowEmptyString()][string]$Text)
    return (([Net.WebUtility]::HtmlDecode(($Text -replace '<[^>]+>', ' '))) -replace '\s+', ' ').Trim()
}
function Get-BenefitScopedHeaderMap {
    return @{
        '업소명'='BusinessName'; '업체명'='BusinessName'; '사업장명'='BusinessName'; '상호'='BusinessName'
        '주소'='Address'; '소재지'='Address'; '소재지도로명주소'='Address'
        '전화번호'='Phone'; '연락처'='Phone'; '전화'='Phone'; '지점'='Branch'; '지점명'='Branch'
        '할인'='BenefitDescription'; '할인정보'='BenefitDescription'; '할인내용'='BenefitDescription'; '혜택'='BenefitDescription'
        '적용대상'='EligibleTarget'; '이용조건'='UsageCondition'; '인증방법'='VerificationMethod'
    }
}
```

The text helper is for parser-approved fragments, not a general HTML parser. Strip actual tags before decoding entities. Snapshot identity is computed deterministically using the exact URL, original retrieval time, and ContentHash; do not trim/rewrite snapshot Text after hashing.

Validate URL/format/time/hash, local type/version, row identity, table and row span bounds, exact RawFragment equality, decoded text, and every field's original header/cell span. Canonical header mapping must match Get-BenefitScopedHeaderMap and decoded source value must equal StructuredFields. A field cannot claim the header/cell of a different row/table. Slice construction checks exact unit membership in the supplied observation. Defensively copy field maps; retain source-backed identity evidence rather than inferred canonical replacements.

- [ ] **Step 4: Run GREEN plus legacy contract regression and commit.**

```powershell
& pwsh -NoProfile -File tools/data/test-benefit-evidence-location-contracts.ps1
if ($LASTEXITCODE) { throw 'Scoped contracts failed' }
& pwsh -NoProfile -File tools/data/test-benefit-verification-contracts.ps1
if ($LASTEXITCODE) { throw 'Legacy contracts failed' }
git add tools/data/lib/benefit-evidence-location-contracts.ps1 tools/data/test-benefit-evidence-location-contracts.ps1 tools/data/testdata/benefit-evidence-location/synthetic.psd1 tools/data/testdata/benefit-evidence-location/test-support.ps1
git commit -m 'feat: define source-grounded evidence slice contracts'
```

## 6. Task 2 — Restricted generic HTML observation parser

**Files:** Create `convert-html-source-observation.ps1` and `test-convert-html-source-observation.ps1` at the paths in A1.2.

**Consumes:** Task 1 constructors and header mapping.
**Produces:** `ConvertTo-BenefitHtmlTemplate -Snapshot -> parsed template` and `ConvertTo-BenefitHtmlObservation -Document -> SourceObservation`. The template accepts no BusinessIdentity or SourceRowNumber. The convenience observation function constructs the snapshot, parses it, and creates a row-specific wrapper.

- [ ] **Step 1: Add parsing RED tests.**

```powershell
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-location/test-support.ps1')
. (Join-Path $PSScriptRoot 'lib/benefit-evidence-location-contracts.ps1')
$path = Join-Path $PSScriptRoot 'lib/benefit-evidence/convert-html-source-observation.ps1'
if (-not (Test-Path $path)) { throw 'HTML observation parser is missing' }
. $path
$d = New-ScopeTestDocument
$o = ConvertTo-BenefitHtmlObservation -Document $d
Assert-ScopeEqual $o.AdapterStatus COMPLETE 'Supported table parses fully'
Assert-ScopeEqual @($o.ContentUnits).Count 2 'Both rows retained before location'
Assert-ScopeEqual $o.ContentUnits[0].StructuredFields.BusinessName '테스트가게 A' 'Observed name cell'
Assert-ScopeEqual $o.ContentUnits[1].StructuredFields.BenefitDescription '30% 할인' 'Observed second-row benefit'
foreach ($u in @($o.ContentUnits)) { Assert-ScopeEqual $d.Text.Substring($u.RawStart,$u.RawLength) $u.RawFragment 'Original row span retained' }
$noBenefit = ConvertTo-BenefitHtmlObservation -Document (New-ScopeTestDocument -Html ($d.Text -replace '<th>할인</th>','<th>비고</th>'))
Assert-ScopeEqual @($noBenefit.ContentUnits).Count 2 'Participation-only rows remain locatable'
Assert-ScopeTrue (-not $noBenefit.ContentUnits[0].StructuredFields.Contains('BenefitDescription')) 'Remarks are not a recognized benefit field'
$twoTables = ConvertTo-BenefitHtmlObservation -Document (New-ScopeTestDocument -Html ($d.Text + $d.Text))
Assert-ScopeEqual @($twoTables.ContentUnits).Count 4 'Do not stop at first table'
foreach ($bad in @(
    ($d.Text -replace '<th>주소</th>','<th>업체명</th>'),
    ($d.Text -replace '<td>10% 할인</td>','<td colspan="2">10% 할인</td>'),
    ($d.Text -replace '</tbody></table>',''),
    ($d.Text -replace '<td>10% 할인</td>','<td><table><tr><td>10%</td></tr></table></td>')
)) {
    $result = ConvertTo-BenefitHtmlObservation -Document (New-ScopeTestDocument -Html $bad)
    Assert-ScopeTrue ($result.AdapterStatus -ne 'COMPLETE') 'Malformed or unsupported table cannot become a complete directory'
}
$encoded = ConvertTo-BenefitHtmlObservation -Document (New-ScopeTestDocument -Html ($d.Text -replace '10% 할인','10% &amp; &lt;조건&gt; 할인'))
Assert-ScopeEqual $encoded.ContentUnits[0].StructuredFields.BenefitDescription '10% & <조건> 할인' 'Decode entities without deleting encoded text'
```

- [ ] **Step 2: Run RED.** `pwsh -NoProfile -File tools/data/test-convert-html-source-observation.ps1`.
- [ ] **Step 3: Implement only a supported subset.** Accept balanced non-nested tables, one unambiguous header row, unique recognized headers, and equal header/data-cell counts. A candidate table requires an explicit business-name column, not a discount column. Preserve all candidate tables and their physical indices. Two headers mapping to one canonical field are ambiguous; do not overwrite one.

Use absolute match/group indices for table, row, header, and cell provenance. For each observed cell:

```powershell
$fields[$canonicalField] = ConvertFrom-ScopeHtmlText -Text $snapshot.Text.Substring($cellStart,$cellLength)
$references[$canonicalField] = [pscustomobject]@{
    HeaderStart=$headerStart; HeaderLength=$headerLength
    CellStart=$cellStart; CellLength=$cellLength; OriginalHeader=$originalHeader
    FieldReference="$unitReference/$canonicalField"
}
```

These are current full-document match coordinates, not offsets into rewritten text. Call New-BenefitSourceContentUnit with its actual table/row spans. Only copy source-observed values. Do not fill phone/address gaps from canonical data or page footers.

Use bounded regex execution times where regex is used. Reject nested tables and rowspan/colspan greater than 1; a future source-family parser may support them with its own fixtures. Never evaluate scripts, follow links, or fabricate closing tags. A malformed candidate business table among valid tables yields PARTIAL, preventing conclusive location. Failed fetch yields FAILED. Non-HTML or no supported business-table structure yields UNSUPPORTED. A genuinely empty, fully parsed supported business table can yield COMPLETE with zero units. COMPLETE concerns the retrieved observation only, never the entire website.

- [ ] **Step 4: Run GREEN and commit.**

```powershell
& pwsh -NoProfile -File tools/data/test-convert-html-source-observation.ps1
if ($LASTEXITCODE) { throw 'HTML parser tests failed' }
git add tools/data/lib/benefit-evidence/convert-html-source-observation.ps1 tools/data/test-convert-html-source-observation.ps1
git commit -m 'feat: parse source-grounded business table units'
```

## 7. Task 3 — Deterministic business-row locator

**Files:** Create `find-business-evidence-slice.ps1` and `test-find-business-evidence-slice.ps1` at the paths in A1.2.

**Consumes:** SourceObservation, NormalizedBusiness, ConvertTo-IdentityComparisonText, Get-NormalizedAddressParts, and Get-BenefitBindingAddressConflicts.
**Produces:** `Find-BenefitBusinessEvidence -Observation -Business -CanonicalPhone '' -> EvidenceLocationResult`.

- [ ] **Step 1: Add positive, ambiguous, absent, and conflicting RED tests.**

```powershell
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-location/test-support.ps1')
. (Join-Path $PSScriptRoot 'lib/benefit-source/bind-benefit-source.ps1')
. (Join-Path $PSScriptRoot 'lib/benefit-evidence/convert-html-source-observation.ps1')
$path = Join-Path $PSScriptRoot 'lib/benefit-evidence/find-business-evidence-slice.ps1'
if (-not (Test-Path $path)) { throw 'Business evidence locator is missing' }
. $path
$d = New-ScopeTestDocument
$o = ConvertTo-BenefitHtmlObservation -Document $d
$b = New-ScopeTestBusiness
$r = Find-BenefitBusinessEvidence -Observation $o -Business $b -CanonicalPhone '02-0000-0012'
Assert-ScopeEqual $r.Status LOCATED 'Name/address identify the right row'
Assert-ScopeEqual @($r.Slices).Count 1 'Exactly one usable row'
Assert-ScopeTrue ($r.Slices[0].RawEvidenceText -notmatch '테스트가게 B|30%') 'No other business evidence'
$absent = New-ScopeTestBusiness -Name '없는가게'
Assert-ScopeEqual (Find-BenefitBusinessEvidence -Observation $o -Business $absent).Status NOT_FOUND 'Not found in complete observation'
$wrong = New-ScopeTestBusiness -Building '23'
$c = Find-BenefitBusinessEvidence -Observation $o -Business $wrong -CanonicalPhone '02-0000-0012'
Assert-ScopeTrue ($c.Status -ne 'LOCATED') 'Phone match cannot override building conflict'
Assert-ScopeTrue (@($c.Diagnostics | Where-Object Code -eq 'LOCATOR_IDENTITY_CONFLICT').Count -gt 0) 'Conflict distinct from absence'
$duplicateHtml = $d.Text -replace '테스트가게 B','테스트가게 A' -replace '서울특별시 마포구 테스트로 99','' -replace '02-0000-0099',''
$duplicate = ConvertTo-BenefitHtmlObservation -Document (New-ScopeTestDocument -Html $duplicateHtml)
Assert-ScopeEqual (Find-BenefitBusinessEvidence -Observation $duplicate -Business $b -CanonicalPhone '02-0000-0012').Status AMBIGUOUS 'Unexcluded name-only alternative prevents unique selection'
$partial = ConvertTo-BenefitHtmlObservation -Document (New-ScopeTestDocument -Html ($d.Text -replace '</tbody></table>',''))
$p = Find-BenefitBusinessEvidence -Observation $partial -Business $b
Assert-ScopeTrue ($p.OperationalStatus -ne 'COMPLETE') 'Partial parse stays operational failure'
Assert-ScopeEqual $p.Status $null 'Partial parse is not semantic NOT_FOUND'
foreach ($numbers in @(@('12','23'),@('26','23'),@('902','904'))) {
    $source = ConvertTo-BenefitHtmlObservation -Document (New-ScopeTestDocument -Html ($d.Text.Replace('테스트로 12',"테스트로 $($numbers[0])")))
    $target = New-ScopeTestBusiness -Building $numbers[1]
    Assert-ScopeTrue ((Find-BenefitBusinessEvidence -Observation $source -Business $target).Status -ne 'LOCATED') 'Synthetic hard-number conflict must fail closed'
}
```

The number mutations are synthetic regression cases, not new observations about the real Golden businesses.

- [ ] **Step 2: Run RED.** `pwsh -NoProfile -File tools/data/test-find-business-evidence-slice.ps1`.
- [ ] **Step 3: Implement the decision rules.** Require an observed compatible explicit full name plus at least one strong corroborator: full address, explicit branch, or phone. Substring/base-name coincidence alone is insufficient. Source address parsing uses empty metadata so canonical locality cannot fill source gaps.

```powershell
$sourceAddress = Get-NormalizedAddressParts -RoadAddress $fields.Address -LotAddress '' -MetadataProvince '' -MetadataArea ''
$conflicts = @(Get-BenefitBindingAddressConflicts -Business $Business -AddressParts $sourceAddress)
foreach ($detail in @('Floor','Unit')) {
    if ($Business.$detail -and $sourceAddress.$detail -and
        (ConvertTo-IdentityComparisonText $Business.$detail) -cne (ConvertTo-IdentityComparisonText $sourceAddress.$detail)) {
        $conflicts += "${detail}_CONFLICT"
    }
}
```

Observed explicit branch/phone conflicts remain disqualifying. Unknown components do not count as matches. Keep the existing identity library unchanged.

Decision table:

- Non-COMPLETE observation: same operational status, null location status, no slices.
- No plausible name: NOT_FOUND; an address/phone match with a different explicit name is recorded for identity review, not silently promoted.
- One corroborated candidate and every alternative safely excluded: LOCATED.
- Multiple plausible candidates or an unexcluded name-only alternative: AMBIGUOUS.
- Only named identity-conflicting candidates: AMBIGUOUS plus LOCATOR_IDENTITY_CONFLICT, no usable slice; the source-processing task maps this to a core binding conflict and RED.

Do not use discount agreement to select the business. Preserve diagnostic signals as `{Code, Stage, EvidenceReference, Detail}` objects. CandidateReferences are for review, not for extraction.

- [ ] **Step 4: Pin explicit detail conflicts and order independence before implementing them.**

```powershell
$unitHtml = $d.Text.Replace('테스트로 12','테스트로 12, 101호')
$unitObservation = ConvertTo-BenefitHtmlObservation -Document (New-ScopeTestDocument -Html $unitHtml)
$otherUnit = New-ScopeTestBusiness -Building '12, 102호'
Assert-ScopeTrue ((Find-BenefitBusinessEvidence -Observation $unitObservation -Business $otherUnit -CanonicalPhone '02-0000-0012').Status -ne 'LOCATED') 'Unit conflict overrides same phone'
$reversed = $o.ContentUnits[0]
$o.ContentUnits[0] = $o.ContentUnits[1]
$o.ContentUnits[1] = $reversed
$again = Find-BenefitBusinessEvidence -Observation $o -Business $b -CanonicalPhone '02-0000-0012'
Assert-ScopeEqual $again.Slices[0].EvidenceReference $r.Slices[0].EvidenceReference 'Physical reference and selection do not depend on processing order'
```

- [ ] **Step 5: Run GREEN and existing identity/Golden regressions, then commit.**

```powershell
foreach ($test in @('test-find-business-evidence-slice.ps1','test-normalize-business.ps1','test-evaluate-poi-match.ps1')) {
    & pwsh -NoProfile -File (Join-Path tools/data $test)
    if ($LASTEXITCODE) { throw "FAILED: $test" }
}
git add tools/data/lib/benefit-evidence/find-business-evidence-slice.ps1 tools/data/test-find-business-evidence-slice.ps1
git commit -m 'feat: locate business evidence without guessing'
```

## 8. Task 4 — Scoped binding, extraction, and independent validation

**Files modified:** The three production files and three existing tests in A1.3.

**Interfaces:** Append optional EvidenceSlice to the three entrypoints in Section 3.4. Add `Test-ScopedBenefitExtractedClaim -Claim -Document -EvidenceSlice -> ValidatedBenefitClaim` in the validation file.

- [ ] **Step 1: Append the following setup and scoped assertions to each owning test file.** Import the exact new modules, not another test script. Existing assertions remain intact.

```powershell
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-location/test-support.ps1')
. (Join-Path $PSScriptRoot 'lib/benefit-source/bind-benefit-source.ps1')
. (Join-Path $PSScriptRoot 'lib/benefit-evidence/convert-html-source-observation.ps1')
. (Join-Path $PSScriptRoot 'lib/benefit-evidence/find-business-evidence-slice.ps1')
. (Join-Path $PSScriptRoot 'lib/benefit-evidence/extract-benefit-evidence.ps1')
. (Join-Path $PSScriptRoot 'lib/benefit-evidence/validate-benefit-evidence.ps1')
$d = New-ScopeTestDocument
$o = ConvertTo-BenefitHtmlObservation -Document $d
$b = New-ScopeTestBusiness
$r = Find-BenefitBusinessEvidence -Observation $o -Business $b -CanonicalPhone '02-0000-0012'
$slice = $r.Slices[0]
$c = New-BenefitSourceCandidate -SourceRowNumber 2 -Url $d.Url -SourceKind PUBLIC_OFFICIAL
$q = New-QualifiedBenefitSource -Candidate $c -Document $d -OfficialityStatus VERIFIED_OFFICIAL -CurrentnessStatus UNKNOWN
$bound = Get-BenefitBusinessBinding -Source $q -Business $b -CanonicalPhone '02-0000-0012' -EvidenceSlice $slice
Assert-ScopeEqual $bound.BusinessBindingStatus STRONG 'Bind observed scoped address without another row'
$x = Invoke-BenefitEvidenceExtraction -Source $bound -Document $d -EvidenceSlice $slice
Assert-ScopeEqual @($x.Claims | Where-Object Value -eq '10% 할인').Count 1 'Selected detail retained'
Assert-ScopeEqual @($x.Claims | Where-Object Value -eq '30% 할인').Count 0 'Other row excluded'
$v = ConvertTo-ValidatedBenefitEvidence -Extraction $x -Document $d -EvidenceSlice $slice
Assert-ScopeEqual $v.Claims[0].ValidationStatus VALIDATED 'Independent original-cell validation'
Assert-ScopeThrows { Get-BenefitBusinessBinding -Source $q -Business $b -EvidenceSlice $null } 'Null is not omitted slice'
Assert-ScopeThrows { Invoke-BenefitEvidenceExtraction -Source $bound -Document $d -EvidenceSlice $null } 'Null cannot enable whole-document extraction'
Assert-ScopeThrows { ConvertTo-ValidatedBenefitEvidence -Extraction $x -Document $d -EvidenceSlice $null } 'Null cannot enable legacy validation'
```

- [ ] **Step 2: Run RED individually.** Initial expected failure: unknown EvidenceSlice parameter. Add each entrypoint branch and its tests incrementally; do not change legacy assertions to hide unrelated regressions.
- [ ] **Step 3: Add explicit scoped branches.** Each entrypoint detects whether EvidenceSlice was supplied, rejects null, and validates against the original document and expected row. In binding, the document is Source.Document and expected row is Business.SourceRowNumber.

```powershell
if ($PSBoundParameters.ContainsKey('EvidenceSlice')) {
    if ($null -eq $EvidenceSlice) { throw 'Explicit scoped evidence cannot be null' }
    Assert-RelevantBenefitEvidenceSlice -Slice $EvidenceSlice -Document $Document -SourceRowNumber $Document.SourceRowNumber
}
```

Binding uses validated observed identity fields with existing conflict precedence and the locator's explicit floor/unit conflict guards. Preserve Source.Document; do not replace it with an authored mini-document. No observed field is filled from canonical input. Branches without EvidenceSlice retain legacy behavior.

Scoped extraction creates only recognized detail claims:

```powershell
$claims = [Collections.Generic.List[object]]::new()
$detailMap = @{BenefitDescription='BENEFIT_DESCRIPTION';EligibleTarget='ELIGIBLE_TARGET';UsageCondition='USAGE_CONDITION';VerificationMethod='VERIFICATION_METHOD'}
foreach ($field in @('BenefitDescription','EligibleTarget','UsageCondition','VerificationMethod')) {
    if (-not $EvidenceSlice.StructuredFields.Contains($field)) { continue }
    $value = [string]$EvidenceSlice.StructuredFields[$field]
    if ([string]::IsNullOrWhiteSpace($value)) { continue }
    $claim = New-ExtractedBenefitClaim -ClaimType $detailMap[$field] -Value $value -EvidenceText $value -EvidenceReference $EvidenceSlice.FieldReferences[$field].FieldReference -SourceUrl $Document.Url -ExtractionMethod SCOPED_HTML_CELL
    Assert-ExtractedBenefitClaim $claim
    $claims.Add($claim)
}
```

Return the existing extraction-result shape. Absent fields remain absent. Do not emit BENEFIT_EXISTENCE, CURRENT_APPLICABILITY, VALID_FROM, or VALID_UNTIL from a generic caption, retrieval date, or discount cell. No renewal/expiry/program policy is added. Successful detail extraction does not necessarily resolve BenefitState.

Scoped validation ignores extractor-authored SourceRepresentation as authority. Validate source/slice provenance, map the original header through Get-BenefitScopedHeaderMap, require the corresponding detail ClaimType, exact selected FieldReference, matching source URL, and the source-backed cell value/text. The generic extractor uses the full cell value, so exact normalized field equality is possible here. Return INVALID with EXTRACTION_SOURCE_MISMATCH for mismatch; never search the whole page to rescue it. Legacy unscoped validation remains unchanged.

- [ ] **Step 4: Append adversarial RED/GREEN assertions to the validation test after the setup above.**

```powershell
$foreign = New-ExtractedBenefitClaim -ClaimType BENEFIT_DESCRIPTION -Value '30% 할인' -EvidenceText '30% 할인' -EvidenceReference $o.ContentUnits[1].FieldReferences.BenefitDescription.FieldReference -SourceUrl $d.Url -ExtractionMethod SCOPED_HTML_CELL
$forged = [pscustomobject]@{SourceRowNumber=2;Status='COMPLETE';Claims=@($foreign);ReasonCodes=@();SourceRepresentation='30% 할인'}
$invalid = ConvertTo-ValidatedBenefitEvidence -Extraction $forged -Document $d -EvidenceSlice $slice
Assert-ScopeEqual $invalid.Claims[0].ValidationStatus INVALID 'SourceRepresentation cannot certify another business'
$wrongType = New-ExtractedBenefitClaim -ClaimType ELIGIBLE_TARGET -Value '10% 할인' -EvidenceText '10% 할인' -EvidenceReference $slice.FieldReferences.BenefitDescription.FieldReference -SourceUrl $d.Url -ExtractionMethod SCOPED_HTML_CELL
Assert-ScopeEqual (Test-ScopedBenefitExtractedClaim -Claim $wrongType -Document $d -EvidenceSlice $slice).ValidationStatus INVALID 'Correct bytes under wrong claim type fail'
$wrongRef = New-ExtractedBenefitClaim -ClaimType BENEFIT_DESCRIPTION -Value '10% 할인' -EvidenceText '10% 할인' -EvidenceReference 'HTML_TABLE_9_ROW_9/BenefitDescription' -SourceUrl $d.Url -ExtractionMethod SCOPED_HTML_CELL
Assert-ScopeEqual (Test-ScopedBenefitExtractedClaim -Claim $wrongRef -Document $d -EvidenceSlice $slice).ValidationStatus INVALID 'Matching text without selected field membership fails'
$slice.StructuredFields['BenefitDescription'] = '99% 할인'
Assert-ScopeThrows { Assert-RelevantBenefitEvidenceSlice -Slice $slice -Document $d -SourceRowNumber 2 } 'Mutated field must fail original-source check'
```

- [ ] **Step 5: Run GREEN and all related legacy tests, then commit.**

```powershell
foreach ($test in @('test-bind-benefit-source.ps1','test-extract-benefit-evidence.ps1','test-validate-benefit-evidence.ps1','test-phase2-benefit-shadow-mode.ps1')) {
    & pwsh -NoProfile -File (Join-Path tools/data $test)
    if ($LASTEXITCODE) { throw "FAILED: $test" }
}
git add tools/data/lib/benefit-source/bind-benefit-source.ps1 tools/data/lib/benefit-evidence/extract-benefit-evidence.ps1 tools/data/lib/benefit-evidence/validate-benefit-evidence.ps1 tools/data/test-bind-benefit-source.ps1 tools/data/test-extract-benefit-evidence.ps1 tools/data/test-validate-benefit-evidence.ps1
git commit -m 'feat: bind extract and validate only selected evidence'
```

## 9. Task 5 — Row-independent per-run fetch and parse reuse

**Files:** Create `benefit-source-run-context.ps1` and its test file at A1.4 paths.

**Produces:**

```text
New-BenefitSourceRunContext -> context
Get-BenefitRunSourceDocument -Context -Candidate -RequestInvoker -> fresh BenefitSourceDocument
Get-BenefitRunHtmlObservation -Context -Document -> fresh SourceObservation
```

Context owns rowless payloads/templates, Metrics, and attempt records. Create it once per top-level run, never in global state. Use ordinal dictionaries so path/query case remains significant.

- [ ] **Step 1: Add shared-source RED tests.**

```powershell
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-location/test-support.ps1')
. (Join-Path $PSScriptRoot 'lib/benefit-source/discover-official-benefit-sources.ps1')
. (Join-Path $PSScriptRoot 'lib/benefit-evidence/convert-html-source-observation.ps1')
$path = Join-Path $PSScriptRoot 'lib/benefit-evidence/benefit-source-run-context.ps1'
if (-not (Test-Path $path)) { throw 'Source run context is missing' }
. $path
$counter = [pscustomobject]@{Count=0}
$html = Get-ScopeTestHtml
$http = {param($Uri);$counter.Count++;[pscustomobject]@{StatusCode=200;ContentType='text/html';Text=$html;Bytes=$null}}.GetNewClosure()
$ctx = New-BenefitSourceRunContext
$c2 = New-BenefitSourceCandidate -SourceRowNumber 2 -Url 'https://city.example.go.kr/list?category=1' -SourceKind PUBLIC_OFFICIAL
$c3 = New-BenefitSourceCandidate -SourceRowNumber 3 -Url $c2.Url -SourceKind PUBLIC_OFFICIAL
$d2 = Get-BenefitRunSourceDocument -Context $ctx -Candidate $c2 -RequestInvoker $http
$d3 = Get-BenefitRunSourceDocument -Context $ctx -Candidate $c3 -RequestInvoker $http
$o2 = Get-BenefitRunHtmlObservation -Context $ctx -Document $d2
$o3 = Get-BenefitRunHtmlObservation -Context $ctx -Document $d3
Assert-ScopeEqual $counter.Count 1 'One underlying retrieval'
Assert-ScopeEqual $ctx.Metrics.AdapterParseCount 1 'One full-source parse'
Assert-ScopeEqual $d2.SourceRowNumber 2 'First document row'
Assert-ScopeEqual $d3.SourceRowNumber 3 'Fresh second document row'
Assert-ScopeEqual $o3.SourceRowNumber 3 'Fresh parsed observation wrapper'
Assert-ScopeEqual $d2.ObservedAt $d3.ObservedAt 'Cache hit keeps original retrieval time'
foreach ($url in @('https://city.example.go.kr/list?category=2','https://city.example.go.kr/List?category=1')) {
    $candidate = New-BenefitSourceCandidate -SourceRowNumber 4 -Url $url -SourceKind PUBLIC_OFFICIAL
    $null = Get-BenefitRunSourceDocument -Context $ctx -Candidate $candidate -RequestInvoker $http
}
Assert-ScopeEqual $counter.Count 3 'Different query/path identity does not collide'
$o2.ContentUnits[0].StructuredFields['BusinessName'] = 'mutated'
Assert-ScopeEqual $o3.ContentUnits[0].StructuredFields.BusinessName '테스트가게 A' 'Mutable row wrapper does not contaminate another row'
$fresh = New-BenefitSourceRunContext
$null = Get-BenefitRunSourceDocument -Context $fresh -Candidate $c2 -RequestInvoker $http
Assert-ScopeEqual $counter.Count 4 'No cross-run cache'
```

- [ ] **Step 2: Run RED.** `pwsh -NoProfile -File tools/data/test-benefit-source-run-context.ps1`.
- [ ] **Step 3: Implement separate payload and template caches.** Use existing Get-BenefitSourceDocument on a cache miss. Retain only rowless fetch metadata/content, and reconstruct fresh documents with current row number and original observation time:

```powershell
$document = New-BenefitSourceDocument -SourceRowNumber $Candidate.SourceRowNumber -Url $payload.Url -SourceFormat $payload.SourceFormat -FetchStatus $payload.FetchStatus -ContentType $payload.ContentType -Text $payload.Text -Bytes $payload.Bytes -ObservedAt $payload.ObservedAt -ReasonCodes @($payload.ReasonCodes)
```

Raw-fetch key: exact request URL within one fixed RequestInvoker profile. Keep query/category/page parameters and path case. Bind the context to the first nonnull RequestInvoker by identity; reject changing it inside that context. No session-bearing content is shared between contexts.

Parsed key: SnapshotId + AdapterId + AdapterVersion. Cache ConvertTo-BenefitHtmlTemplate's rowless result, then reconstruct observations with the current SourceRowNumber. Locator/binding/evaluation always run per business. Do not recalculate ObservedAt on cache hits or infer currentness from reuse.

No retry is added in A1: one cache miss invokes the boundary once; retain a failed result for this run so referencing rows do not create a retry storm. A new run can retry. Never reuse an old successful body after current fetch failure. ExternalFetchCount counts underlying RequestInvoker calls, not cache-wrapper calls. Counters: ExternalFetchCount, FetchCacheHits, AdapterParseCount, AdapterReuseCount, UniqueRequestKeys, SourceFetchFailures.

- [ ] **Step 4: Add failure/profile RED/GREEN cases.**

```powershell
$failureCount = [pscustomobject]@{Count=0}
$badHttp = {param($Uri);$failureCount.Count++;throw 'timeout'}.GetNewClosure()
$failedContext = New-BenefitSourceRunContext
foreach ($rowNumber in @(2,3,4)) {
    $candidate = New-BenefitSourceCandidate -SourceRowNumber $rowNumber -Url $c2.Url -SourceKind PUBLIC_OFFICIAL
    $failedDoc = Get-BenefitRunSourceDocument -Context $failedContext -Candidate $candidate -RequestInvoker $badHttp
    Assert-ScopeEqual $failedDoc.FetchStatus FAILED 'Failure retained without stale body'
    Assert-ScopeEqual $failedDoc.Text '' 'Failed response has no old successful text'
}
Assert-ScopeEqual $failureCount.Count 1 'Bounded failure reuse avoids retry storm'
Assert-ScopeThrows { Get-BenefitRunSourceDocument -Context $ctx -Candidate $c2 -RequestInvoker $badHttp } 'Cannot change request profile in an existing context'
```

- [ ] **Step 5: Run GREEN and commit.**

```powershell
& pwsh -NoProfile -File tools/data/test-benefit-source-run-context.ps1
if ($LASTEXITCODE) { throw 'Source reuse tests failed' }
git add tools/data/lib/benefit-evidence/benefit-source-run-context.ps1 tools/data/test-benefit-source-run-context.ps1
git commit -m 'feat: reuse source payloads without sharing business state'
```

## 10. Task 6 — Opt-in scoped Shadow Mode integration

**Files:** A1.5 source helper, runner, and new integration test.

**Produces:**

```text
Invoke-ScopedPhase2BenefitSourceCandidate
  -Candidate -Business -CanonicalPhone -RunContext -RequestInvoker
  -> existing source-record fields plus Observation, LocationResult, Slices, PreparationDiagnostics

Invoke-Phase2BenefitShadowMode
  existing arguments + -UseScopedHtmlEvidence + -SourceRowNumbers [int[]]
  -> existing Results/Rows/EvidenceDiagnostics/Summary; scoped mode also returns PreparationSummary
```

Explicit SourceRowNumbers must match Rows.Count, be distinct and greater than 1, and cannot coexist with explicitly supplied SourceRowNumberOffset. Otherwise preserve the original offset formula. Support an empty scoped Rows array without fetching.

- [ ] **Step 1: Add two-business/same-source RED with sparse original row numbers.**

```powershell
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-location/test-support.ps1')
. (Join-Path $PSScriptRoot 'invoke-phase2-benefit-shadow-mode.ps1')
$rows = @((New-ScopeTestRow), (New-ScopeTestRow -Name '테스트가게 B' -Building '99' -Phone '02-0000-0099' -Benefit '30% 할인'))
$html = Get-ScopeTestHtml
$counter = [pscustomobject]@{Count=0}
$http = {param($Uri);$counter.Count++;[pscustomobject]@{StatusCode=200;ContentType='text/html';Text=$html;Bytes=$null}}.GetNewClosure()
$run = Invoke-Phase2BenefitShadowMode -Rows $rows -SourceRowNumbers @(75,118) -UseScopedHtmlEvidence -RequestInvoker $http
Assert-ScopeEqual $counter.Count 1 'Two businesses share one fetch'
Assert-ScopeEqual $run.PreparationSummary.AdapterParseCount 1 'Two businesses share one parse'
Assert-ScopeEqual $run.Results[0].SourceRowNumber 75 'Original sparse row number'
Assert-ScopeEqual $run.Results[1].BusinessIdentity.SourceRowNumber 118 'Independent BusinessIdentity row number'
$a = @($run.EvidenceDiagnostics | Where-Object SourceRowNumber -eq 75)[0]
$b = @($run.EvidenceDiagnostics | Where-Object SourceRowNumber -eq 118)[0]
Assert-ScopeEqual @($a.ValidatedClaims | Where-Object Value -eq '30% 할인').Count 0 'B cannot contaminate A'
Assert-ScopeEqual @($b.ValidatedClaims | Where-Object Value -eq '10% 할인').Count 0 'A cannot contaminate B'
Assert-ScopeEqual @($a.ValidatedClaims | Where-Object Value -eq '10% 할인').Count 1 'Positive detail is retained'
Assert-ScopeEqual $run.Results[0].BenefitState NEEDS_VERIFICATION 'Located detail does not prove lifecycle'
Assert-ScopeTrue (@($run.Results | Where-Object ProductionAction -ne 'NONE').Count -eq 0) 'Shadow-only output'
```

- [ ] **Step 2: Run RED.** `pwsh -NoProfile -File tools/data/test-phase2-scoped-html.ps1`; expected initial failure is the new parameter not existing.
- [ ] **Step 3: Implement explicit scoped dispatch using the actual API order.**

```text
candidate -> cached fetch -> existing source qualification
          -> parsed observation -> locator -> scoped binding
          -> scoped extraction -> independent scoped validation
          -> existing comparison/evaluation -> result
```

Qualification needs retrieved content; do not literally follow a conceptual diagram that places qualification before all fetching. A1 opts into existing eligible PUBLIC_OFFICIAL HTML only. Other types receive unsupported/unresolved diagnostics, never silent promotion. Do not infer business evidence from linked attachments that were not retrieved/parsed.

Unqualified source: retain source diagnostics, accept no claims, stop the path. Non-COMPLETE parser or non-LOCATED result: empty usable claims and mapped existing reasons. Preserve hard identity conflicts through a BoundBenefitSource conflict so the existing evaluator returns RED. No failed-location branch passes null to activate legacy behavior.

Located source: preserve its original document and pass the same validated slice explicitly to binding, extraction, and validation. Do not admit decisive claims when binding is not STRONG. Do not carry another row's lifecycle or page-wide currentness text into a scoped claim. Generic A1 detail-only extraction can remain NEEDS_VERIFICATION; changing the evaluator to force GREEN is forbidden.

In scoped mode DiscoveryInvoker, UnstructuredExtractor, PdfTextExtractor, and SpreadsheetExtractor must be null. Reject contradictory arguments before any request. Record DiscoveryExecution=NOT_REQUESTED and LlmInvocationCount=0. For existing evaluator operational input, completion of the planned existing-source path can use DiscoveryStatus=COMPLETE without claiming an external search happened.

```powershell
if ($UseScopedHtmlEvidence) {
    $sourceRecord = Invoke-ScopedPhase2BenefitSourceCandidate -Candidate $candidate -Business $business -CanonicalPhone $canonicalPhone -RunContext $runContext -RequestInvoker $RequestInvoker
} else {
    $sourceRecord = Invoke-Phase2BenefitSourceCandidate -Candidate $candidate -Business $business -CanonicalPhone $canonicalPhone -RequestInvoker $countingRequest -UnstructuredExtractor $UnstructuredExtractor -SpreadsheetExtractor $SpreadsheetExtractor -PdfTextExtractor $PdfTextExtractor
}
```

Create scoped RunContext outside the business loop. Attribute each row's physical request count using before/after context metric deltas; a cache hit must not count as another network call. Existing unscoped loop/fallback behavior remains unchanged. Do not duplicate the benefit evaluator in the helper.

PreparationSummary contains SourceEvaluations, UniqueRequestKeys, ExternalFetchCount, FetchCacheHits, SourceFetchFailures, AdapterParseCount, AdapterReuseCount, LocatorLocated, LocatorAmbiguous, LocatorNotFound, LocationNotAttempted, and LlmInvocationCount. Location counts are per business/source evaluation, not unique URL. Status counts plus LocationNotAttempted equal SourceEvaluations. Failure before a semantic location is not NOT_FOUND.

Diagnostics retain original row number, source URL, snapshot hash/time, adapter version, slice text and table/row/field references, binding evidence, validated claims, and reasons. Preserve `Get-Phase2BenefitShadowSummary -Rows` compatibility; no new hidden required metadata argument. Add preparation-specific reporting separately rather than changing legacy metric meanings. Existing export paths remain protected.

- [ ] **Step 4: Add safety RED/GREEN tests.**

```powershell
Assert-ScopeThrows { Invoke-Phase2BenefitShadowMode -Rows $rows -SourceRowNumbers @(75) -UseScopedHtmlEvidence -RequestInvoker $http } 'Reject incomplete row map before fetch'
Assert-ScopeThrows { Invoke-Phase2BenefitShadowMode -Rows $rows -SourceRowNumbers @(75,75) -UseScopedHtmlEvidence -RequestInvoker $http } 'Reject duplicate row map'
Assert-ScopeThrows { Invoke-Phase2BenefitShadowMode -Rows $rows -UseScopedHtmlEvidence -RequestInvoker $http -DiscoveryInvoker {throw 'must not call'} } 'Scoped A1 cannot enable discovery'
Assert-ScopeThrows { Invoke-Phase2BenefitShadowMode -Rows $rows -UseScopedHtmlEvidence -RequestInvoker $http -UnstructuredExtractor {throw 'must not call'} } 'Scoped A1 cannot enable LLM fallback'
$failed = Invoke-Phase2BenefitShadowMode -Rows $rows -UseScopedHtmlEvidence -RequestInvoker {param($Uri);throw 'timeout'}
Assert-ScopeEqual @($failed.Results | Where-Object BenefitState -eq 'ENDED').Count 0 'Failure does not mean ending'
Assert-ScopeEqual @($failed.Results | Where-Object ReviewClass -eq 'GREEN').Count 0 'Failure does not mean approval'
$endingHtml = $html.Replace('30% 할인','혜택 종료')
$endingHttp = {param($Uri);[pscustomobject]@{StatusCode=200;ContentType='text/html';Text=$endingHtml;Bytes=$null}}.GetNewClosure()
$single = Invoke-Phase2BenefitShadowMode -Rows @($rows[0]) -UseScopedHtmlEvidence -RequestInvoker $endingHttp
Assert-ScopeTrue ($single.Results[0].BenefitState -ne 'ENDED') 'Another business ending cannot end A'
$ambiguousHtml = $html.Replace('테스트가게 B','테스트가게 A').Replace('서울특별시 마포구 테스트로 99','').Replace('02-0000-0099','')
$ambiguousHttp = {param($Uri);[pscustomobject]@{StatusCode=200;ContentType='text/html';Text=$ambiguousHtml;Bytes=$null}}.GetNewClosure()
$ambiguous = Invoke-Phase2BenefitShadowMode -Rows @($rows[0]) -UseScopedHtmlEvidence -RequestInvoker $ambiguousHttp
Assert-ScopeEqual @($ambiguous.EvidenceDiagnostics[0].ValidatedClaims).Count 0 'Ambiguity cannot fall back to whole page'
```

- [ ] **Step 5: Run new and legacy integration suites, then commit.**

```powershell
foreach ($test in @('test-phase2-scoped-html.ps1','test-phase2-benefit-shadow-mode.ps1','test-phase1-poi-shadow-mode.ps1')) {
    & pwsh -NoProfile -File (Join-Path tools/data $test)
    if ($LASTEXITCODE) { throw "FAILED: $test" }
}
git add tools/data/lib/benefit-evidence/invoke-scoped-benefit-source.ps1 tools/data/invoke-phase2-benefit-shadow-mode.ps1 tools/data/test-phase2-scoped-html.ps1
git commit -m 'feat: add opt-in scoped HTML shadow verification'
```

## 11. Task 7 — Closeout, export checks, and truthful reporting

**Files:** Extend `tools/data/test-phase2-scoped-html.ps1`; update `tools/data/README.md`.
**Produces:** documented scoped invocation and reproducible A1 safety evidence, not a population-performance claim.

- [ ] **Step 1: Pin counters and empty input before implementing them.** Append after Task 6's test setup:

```powershell
$p = $run.PreparationSummary
Assert-ScopeEqual ($p.LocatorLocated+$p.LocatorAmbiguous+$p.LocatorNotFound+$p.LocationNotAttempted) $p.SourceEvaluations 'Location counts reconcile'
Assert-ScopeEqual $p.ExternalFetchCount 1 'Count physical boundary calls'
Assert-ScopeEqual $p.LlmInvocationCount 0 'No LLM in A1'
$empty = Invoke-Phase2BenefitShadowMode -Rows @() -UseScopedHtmlEvidence -RequestInvoker {throw 'must not fetch'}
Assert-ScopeEqual @($empty.Results).Count 0 'Empty results'
Assert-ScopeEqual $empty.PreparationSummary.ExternalFetchCount 0 'No empty-run request'
```

AllowEmptyCollection is needed on relevant mandatory array parameters. Return explicit zero operational metrics without reading `.Sum` from an absent measurement object under StrictMode.

- [ ] **Step 2: Export to an OS temporary directory and verify round-trip provenance.**

```powershell
$dir = Join-Path ([IO.Path]::GetTempPath()) ('milimap-scope-' + [Guid]::NewGuid().ToString('N'))
try {
    $csv = Join-Path $dir 'rows.csv'
    $summary = Join-Path $dir 'summary.json'
    $evidence = Join-Path $dir 'evidence.json'
    Export-Phase2BenefitShadowMode -Run $run -RowReportCsv $csv -SummaryJson $summary -EvidenceDiagnosticJson $evidence
    $exported = @(Import-Csv -LiteralPath $csv)
    Assert-ScopeEqual ([int]$exported[0].SourceRowNumber) 75 'CSV original row survives'
    $diags = @(Get-Content -Raw -LiteralPath $evidence | ConvertFrom-Json)
    Assert-ScopeEqual $diags[0].Url 'https://city.example.go.kr/list' 'JSON source URL survives'
    Assert-ScopeTrue (@($diags[0].ValidatedClaims | Where-Object EvidenceReference -like 'HTML_TABLE_*').Count -gt 0) 'JSON field reference survives'
} finally {
    if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
}
```

Reuse the existing legacy protected-output tests for canonical/seed/apps. A1 does not claim new symlink/path-hardening beyond the existing implementation.

- [ ] **Step 3: Document invocation and limitations.** Include the concrete call shape below, explaining that callers supply selected canonical rows, original row numbers, and one already-authorized RequestInvoker. No secret or real personal data belongs in the example/report.

```powershell
. ./tools/data/invoke-phase2-benefit-shadow-mode.ps1
$run = Invoke-Phase2BenefitShadowMode -Rows $selectedRows -SourceRowNumbers $originalCsvRowNumbers -UseScopedHtmlEvidence -RequestInvoker $httpInvoker
$run.PreparationSummary
```

Document LOCATED versus resolved BenefitState, opt-in versus legacy behavior, unsupported parsing versus absence, and exact cache counter meanings. A source family is not supported merely because the generic synthetic fixture passes.

Use this closeout-report convention, not unearned quality statistics:

```text
FixtureSafety: tested case count, wrong-row selections, claim leaks,
               false-GREEN cases, false-ENDED cases
LiveAudit: Status=NOT_RUN, AuditedRowCount=0,
           LocatedPrecision=null, FalseGreenCount=null, FalseEndedCount=null
```

Legacy Summary.FalseGreenCount needs GoldenExpectations; an unlabelled run's zero is not evidence of zero real-world errors. Do not treat zero predictions as perfect precision. Positive locator/extraction tests are mandatory so rejecting everything cannot satisfy A1's gate.

- [ ] **Step 4: Run all deterministic tests independently and in CI's same-process form.**

```powershell
$ErrorActionPreference = 'Stop'
Get-ChildItem -LiteralPath tools/data -Filter 'test-*.ps1' | Sort-Object Name | ForEach-Object {
    & pwsh -NoProfile -File $_.FullName
    if ($LASTEXITCODE -ne 0) { throw "FAILED: $($_.Name)" }
}
Get-ChildItem -LiteralPath tools/data -Filter 'test-*.ps1' | Sort-Object Name | ForEach-Object { & $_.FullName }
```

- [ ] **Step 5: Check scope, protected files, and untracked artifacts.**

```powershell
git diff --check
git status --short
git diff --exit-code origin/dev -- data/canonical data/seed apps
if ($LASTEXITCODE -ne 0) { throw 'Protected-path change detected' }
git diff --name-only origin/dev
```

Use the recorded reviewed base SHA instead of a moving origin/dev when reconciling another contributor's changes. Check both committed delta and dirty/untracked state; a clean tracked diff alone is not proof of non-write.

- [ ] **Step 6: Verify final implementation PR HEAD CI.** Current workflow uses JDK 17 and these Android commands:

```powershell
Push-Location apps/android
try {
    & ./gradlew assembleDebugUnitTest testDebugUnitTest --stacktrace
    if ($LASTEXITCODE) { throw 'Android unit tests failed' }
    & ./gradlew lintDebug assembleDebug --stacktrace
    if ($LASTEXITCODE) { throw 'Android lint/build failed' }
} finally { Pop-Location }
```

On Windows use gradlew.bat. If local Android tooling is unavailable, report local NOT_RUN and verify the exact PR HEAD's verify-data and verify jobs through GitHub. An earlier green commit does not cover a newer commit. These are execution requirements, not tests run during this planning task.

- [ ] **Step 7: Commit docs, obtain whole-branch review, and report remaining risk.**

```powershell
git add tools/data/README.md tools/data/test-phase2-scoped-html.ps1
git commit -m 'docs: document scoped evidence use and safety limits'
```

Use requesting-code-review and verification-before-completion at execution time. Prefer an independent reviewer if actually available. Otherwise label self-review honestly; do not claim unavailable subagent review. Do not delete a failing assertion to get GREEN unless its conflict with the approved specification is demonstrated.

## 12. A1 completion criteria and remaining risks

A1 is complete only when supported offline HTML fixtures work end-to-end through the optional path, positive and negative tests pass, legacy suites pass, original row/source/field identity is preserved, tested cross-business leakage is zero, fetch/parse reuse is measured, protected paths are unchanged, and final-HEAD CI is verified.

Remaining risks:

- Generic HTML support is intentionally narrow; real pages may require details, pagination, different layouts, or attachments.
- Correct location alone does not prove program identity, currentness, complete conditions, or benefit lifecycle.
- Legacy unscoped callers keep their old behavior until explicitly migrated; scoped guards cannot be claimed to protect them.
- The new content hash is not publisher-authenticity proof; trust still requires actual retrieval, qualification, source membership, and binding.
- Expiry, automatic renewal, and multi-program/composite resolution are not redesigned in A1.
- Human audit is not assistant self-review. Its absence must stay visible.

## 13. Remaining Milestone A plans and spec coverage

| Spec obligation | A1 task or next deliverable |
| --- | --- |
| Common snapshots/observations/units/slices | Tasks 1–3 |
| Scoped binding/extraction/validation and legacy compatibility | Task 4 |
| Per-run fetch/parse reuse | Task 5 |
| Shadow integration and reason-based stopping | Task 6 |
| Contract/synthetic/legacy safety, counters, docs/CI | Tasks 1–7 |
| DDC/Paju/MMA/Yangju source-family strategies | A2 plans after actual capability inventory |
| Source-family smoke, official-entry workload run, human audit | A3 validation plan after A2 |
| PDF/XLSX, LLM, official SNS/blog, discovery providers | Later milestones with separate approvals |
| Cross-run cache, history, scheduling | Deferred from initial implementation |

Before A2, inventory actual entry/retrieved URLs, request identity, response format, pagination/completeness, attachment links, parsing capability, and missing evidence types. Do not assume a public HTML landing page contains all records. Treat attachment-backed Yangju data as an attachment requirement, not solved by an empty HTML parser. Source-specific parsing knowledge can be reused, but old release-candidate decisions cannot become current evidence.

A3 derives held rows using original canonical CSV row numbers minus the pinned official-release-candidate report, not guessed from 혜택상태. Pin both input hashes and preserve sparse row identity. Keep inaccessible/unsupported/unresolved inputs in the denominator. Measure located coverage separately from resolved-benefit coverage. Human audit covers all GREEN/ENDED outputs plus source-family/identity-risk-stratified LOCATED samples. Record sample size and selection; zero observed audit errors is not a population guarantee.

A2 contract changes beyond these additive interfaces require design review first. A1 approval cannot authorize a PDF package, LLM, paid search service, SNS authentication, or database.

## 14. Plan self-review and execution handoff

Planning review reconciled the approved spec with pinned code, named cross-task interfaces, added independent test setup, separated source-level caches from row-specific judgments, grounded validation in original fields, separated operational failures from absence, and separated fixture safety from unperformed human audit.

The tests/commands in this plan are not implementation or execution results. No product code is added by writing this document.

Recommended execution method: **Native / executing-plans**, with task-sized delivery and whole-branch review. Shared evidence interfaces benefit from one implementation context. Use a capable independent reviewer only when available; do not promise an unavailable subagent.

The user reviews this plan and confirms the execution method before implementation. Then begin A1.1 in an isolated workspace, not the whole Phase 2 architecture at once.

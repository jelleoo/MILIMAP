# MMA JSONP Source Capability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a fail-closed MMA JSONP source path that preserves raw provenance, links the official list record to its detail record by `udgigwan_cd`, and reuses the existing scoped benefit verification core without weakening HTML A1 guarantees.

**Architecture:** Keep the existing HTML path intact and add `JSONP` as an explicit in-process source format. A dedicated MMA adapter validates the JSONP envelope, emits JSONP-native source units/slices, performs list identity location before detail fetch, and passes detail fields into the existing extraction/validation/comparison pipeline. The mixed scoped runner dispatches MMA entry URLs to the MMA path and all other supported HTML sources to the existing HTML path.

**Tech Stack:** PowerShell, existing MILIMAP Phase 2 contracts, `ConvertFrom-Json`, deterministic character scanning for JSONP/object spans, existing identity normalization and shadow-mode test harness. No new external dependency.

**Spec:** `docs/superpowers/specs/2026-09-25-phase2-a2-mma-jsonp-capability-design.md`

## Global Constraints

- Baseline implementation starts from latest `origin/dev`; the approved spec baseline is `dev@bd05c15467730a6aca684ec1ec5723d88ff05241`.
- Add `JSONP` explicitly; do not relabel JSONP as HTML or plain JSON.
- Preserve the original JSONP response text in `BenefitSourceDocument.Text` and `BenefitSourceSnapshot.Text`.
- Never execute JSONP callback JavaScript; validate the expected callback and parse the enclosed JSON as data only.
- `udgigwan_cd` becomes a trusted linkage key only after one list business record is safely located.
- `9999-12-31` remains an observed raw value and must not imply `ACTIVE`, `CURRENT`, or indefinite validity.
- Existing HTML table/row provenance checks and all A1 fixtures must remain unchanged in behavior.
- `ProductionAction` remains `NONE`.
- No Android, canonical, seed, Room, server API, auth, persistent schema, CI, or dependency changes.
- No PDF/XLSX/SNS/blog/discovery implementation in this delivery.

## Review Focus

- JSONP with the correct callback followed by extra executable text must fail closed; Task 2 pins this.
- A valid detail response for a different `udgigwan_cd` must never attach to the selected list business; Task 4 pins this.
- Duplicate/same-name MMA list records must remain `AMBIGUOUS` instead of using institution code as an identity shortcut; Task 3 pins this.
- A forged JSONP field reference to another object/property must fail evidence validation; Tasks 2 and 4 pin this.
- Existing HTML scoped runs must produce the same adapter identity, references, leakage behavior, and shadow-only result after generalization; Tasks 1 and 5 pin this.

---

### Task 1: Add explicit JSONP contract support without weakening HTML contracts

**Files:**
- Modify: `tools/data/lib/benefit-verification-contracts.ps1`
- Modify: `tools/data/lib/benefit-evidence-location-contracts.ps1`
- Modify: `tools/data/test-benefit-verification-contracts.ps1`
- Modify: `tools/data/test-benefit-evidence-location-contracts.ps1`

**Interfaces:**
- Consumes: existing `BenefitSourceDocument`, `BenefitSourceSnapshot`, `SourceObservation`, `SourceContentUnit`, `RelevantEvidenceSlice` contracts.
- Produces:
  - `SourceFormat='JSONP'`
  - format-dispatched `Assert-ScopeUnit`
  - format-dispatched `Assert-ScopeSliceShape` / `Assert-ScopeSliceAgainstSnapshot`
  - `New-BenefitJsonpSourceContentUnit -Snapshot -UnitReference -RawStart -RawLength -RawEvidenceText -StructuredFields -FieldReferences`
  - JSONP slice support with `ScopeType='JSON_OBJECT'` and `LocatorMethod='STRUCTURED_JSONP_OBJECT'`.

- [ ] **Step 1: Write failing contract tests for JSONP while retaining exact existing HTML expectations**

Update the required source format set in `test-benefit-verification-contracts.ps1`:

```powershell
SourceFormat = @('HTML', 'CSV', 'XLSX', 'PDF', 'JSONP', 'UNSUPPORTED')
```

Add to `test-benefit-evidence-location-contracts.ps1` a minimal raw JSONP snapshot and JSONP unit/slice contract test:

```powershell
$jsonp = 'Cb({"success":true,"udgigwanVO":{"udgigwan_cd":"2789","udsangse_cn":"서비스 이용료 3% 할인"}})'
$jsonpSnapshot = New-BenefitSourceSnapshot -SourceUrl 'https://open.mma.go.kr/detail?callback=Cb' -SourceFormat JSONP -Text $jsonp -ObservedAt '2026-09-25T00:00:00Z'

$fields = [ordered]@{
    InstitutionCode='2789'
    BenefitDescription='서비스 이용료 3% 할인'
}
$refs = [ordered]@{
    InstitutionCode=[pscustomobject][ordered]@{PropertyName='udgigwan_cd';FieldReference='JSONP_DETAIL_OBJECT/udgigwan_cd'}
    BenefitDescription=[pscustomobject][ordered]@{PropertyName='udsangse_cn';FieldReference='JSONP_DETAIL_OBJECT/udsangse_cn'}
}
$unit = New-BenefitJsonpSourceContentUnit -Snapshot $jsonpSnapshot -UnitReference 'JSONP_DETAIL_OBJECT' -RawStart $jsonp.IndexOf('{"udgigwan_cd"') -RawLength '{"udgigwan_cd":"2789","udsangse_cn":"서비스 이용료 3% 할인"}'.Length -RawEvidenceText '서비스 이용료 3% 할인' -StructuredFields $fields -FieldReferences $refs
Assert-ScopeUnit $unit $jsonpSnapshot

$observation = New-BenefitSourceObservation -SourceRowNumber 2 -Snapshot $jsonpSnapshot -AdapterId 'MMA_JSONP_DETAIL' -AdapterVersion '1' -AdapterStatus COMPLETE -ContentUnits @($unit)
$slice = New-RelevantBenefitEvidenceSlice -Observation $observation -Unit $unit -IdentityEvidence @('FULL_NAME_MATCH')
Assert-ScopeEqual $slice.ScopeType 'JSON_OBJECT' 'JSONP slice keeps source-native scope'
Assert-ScopeEqual $slice.LocatorMethod 'STRUCTURED_JSONP_OBJECT' 'JSONP slice keeps source-native locator method'
```

Also retain an explicit existing HTML assertion:

```powershell
Assert-ScopeEqual $x.Slice.ScopeType 'TABLE_ROW' 'HTML slice scope stays TABLE_ROW'
Assert-ScopeEqual $x.Slice.LocatorMethod 'STRUCTURED_HTML_ROW' 'HTML locator identity stays unchanged'
```

- [ ] **Step 2: Run RED contract tests**

Run:

```powershell
pwsh -NoProfile -File tools/data/test-benefit-verification-contracts.ps1
pwsh -NoProfile -File tools/data/test-benefit-evidence-location-contracts.ps1
```

Expected: failures because `JSONP` and `New-BenefitJsonpSourceContentUnit` do not exist.

- [ ] **Step 3: Add JSONP to the internal source-format set**

In `benefit-verification-contracts.ps1` change only the allowed set:

```powershell
SourceFormat = @('HTML', 'CSV', 'XLSX', 'PDF', 'JSONP', 'UNSUPPORTED')
```

Do not change contract version or persistent schemas.

- [ ] **Step 4: Split unit/slice validation by source shape**

Keep current HTML logic in a dedicated validator, for example:

```powershell
function Assert-ScopeHtmlUnit {
    param($Unit, $Snapshot)
    # move current Assert-ScopeUnit HTML body here unchanged
}

function Assert-ScopeJsonpUnit {
    param($Unit, $Snapshot)
    if ($Snapshot.SourceFormat -cne 'JSONP' -or $Unit.UnitType -cne 'JSON_OBJECT') { throw 'JSONP unit source/type mismatch' }
    if ($Unit.UnitReference -cnotmatch '^JSONP_(?:LIST_ITEM_[1-9]\d*|DETAIL_OBJECT)$') { throw 'Invalid JSONP unit reference' }
    Assert-ScopeSpan $Unit.RawStart $Unit.RawLength 0 $Snapshot.Text.Length
    if ($Snapshot.Text.Substring([int]$Unit.RawStart,[int]$Unit.RawLength) -cne $Unit.RawFragment) { throw 'JSONP raw fragment mismatch' }
    if ($Unit.StructuredFields -isnot [Collections.IDictionary] -or $Unit.FieldReferences -isnot [Collections.IDictionary]) { throw 'JSONP fields and references must be dictionaries' }
    if ($Unit.StructuredFields.Count -ne $Unit.FieldReferences.Count) { throw 'JSONP fields and references must align' }
    foreach ($key in $Unit.StructuredFields.Keys) {
        if (-not $Unit.FieldReferences.Contains($key)) { throw 'Missing JSONP field reference' }
        $reference = $Unit.FieldReferences[$key]
        foreach ($property in @('PropertyName','FieldReference')) {
            if ($reference.PSObject.Properties.Name -notcontains $property) { throw "JSONP field reference is missing $property" }
        }
        if ([string]$reference.FieldReference -cne ($Unit.UnitReference + '/' + [string]$reference.PropertyName)) { throw 'JSONP field reference must belong to selected object' }
    }
}

function Assert-ScopeUnit {
    param($Unit, $Snapshot)
    Assert-ScopeSnapshot $Snapshot
    if ($Snapshot.SourceFormat -ceq 'HTML') { Assert-ScopeHtmlUnit $Unit $Snapshot; return }
    if ($Snapshot.SourceFormat -ceq 'JSONP') { Assert-ScopeJsonpUnit $Unit $Snapshot; return }
    throw 'Unsupported scoped source format'
}
```

Implement `New-BenefitJsonpSourceContentUnit` without adding HTML-only table coordinates to JSONP. Keep the common object fields plus `RawStart`, `RawLength`, `RawFragment`, `RawEvidenceText`, `StructuredFields`, and `FieldReferences`.

Update slice construction/validation so HTML still reconstructs and validates a table-row unit, while JSONP reconstructs and validates a JSON-object unit.

- [ ] **Step 5: Run GREEN contract tests**

Run the two commands from Step 2.

Expected: PASS, including existing HTML mutation/provenance tests.

- [ ] **Step 6: Commit Task 1**

```powershell
git add tools/data/lib/benefit-verification-contracts.ps1 tools/data/lib/benefit-evidence-location-contracts.ps1 tools/data/test-benefit-verification-contracts.ps1 tools/data/test-benefit-evidence-location-contracts.ps1
git commit -m "data: add JSONP evidence contracts"
```

---

### Task 2: Build the fail-closed MMA JSONP parser and source-backed units

**Files:**
- Create: `tools/data/lib/benefit-evidence/convert-mma-jsonp-source-observation.ps1`
- Create: `tools/data/test-convert-mma-jsonp-source-observation.ps1`
- Create: `tools/data/testdata/benefit-evidence-mma/mma-list.fixture.jsonp`
- Create: `tools/data/testdata/benefit-evidence-mma/mma-detail-2789.fixture.jsonp`
- Create: `tools/data/testdata/benefit-evidence-mma/mma-detail-2740.fixture.jsonp`

**Interfaces:**
- Consumes: `New-BenefitSourceSnapshot`, `New-BenefitJsonpSourceContentUnit`, `New-BenefitSourceObservation`.
- Produces:
  - `ConvertFrom-BenefitJsonpEnvelope -Text -ExpectedCallback`
  - `Get-BenefitJsonObjectSpans -JsonText`
  - `ConvertTo-MmaJsonpListTemplate -Snapshot -ExpectedCallback`
  - `ConvertTo-MmaJsonpDetailTemplate -Snapshot -ExpectedCallback`
  - `ConvertTo-MmaJsonpListObservation -Document -ExpectedCallback`
  - `ConvertTo-MmaJsonpDetailObservation -Document -ExpectedCallback`.

- [ ] **Step 1: Add sanitized deterministic MMA fixtures**

The fixtures must contain only the two observed controls and synthetic neighboring records needed for tests, not a dump of the 2,498-row live response.

List fixture shape:

```text
MmaTestList({"success":true,"list":[
  {"udgigwan_cd":"2789","<observed-name-key>":"(유)투투여행사","<observed-address-key>":"...","<observed-phone-key>":"..."},
  {"udgigwan_cd":"2740","<observed-name-key>":"(주) 예쁜떡 오늘","<observed-address-key>":"...","<observed-phone-key>":"..."}
]});
```

During implementation, replace the angle-bracket keys only with the exact raw property names captured from the approved Spike; do not infer names from canonical columns. If those names are not present in the handover, re-run the approved read-only MMA probe before writing the fixture and record the observed names in the test comment.

Detail fixtures must include exact observed keys:

```json
{
  "udgigwan_cd": "2789",
  "udsangse_cn": "서비스 이용료 3% 할인",
  "uddaesang_cn": "...",
  "udjyjehan_cn": "...",
  "udjbjaryo_cn": "...",
  "hyjeokyong_sjdt": "...",
  "hyjeokyong_jrdt": "..."
}
```

wrapped by the test callback.

- [ ] **Step 2: Write failing envelope tests**

In `test-convert-mma-jsonp-source-observation.ps1` cover:

```powershell
Assert-ScopeNoThrow { ConvertFrom-BenefitJsonpEnvelope -Text 'Cb({"success":true});' -ExpectedCallback 'Cb' } 'Valid JSONP envelope parses'
Assert-ScopeThrows { ConvertFrom-BenefitJsonpEnvelope -Text 'Wrong({"success":true})' -ExpectedCallback 'Cb' } 'Callback mismatch fails'
Assert-ScopeThrows { ConvertFrom-BenefitJsonpEnvelope -Text 'Cb({"success":true})alert(1)' -ExpectedCallback 'Cb' } 'Executable suffix fails'
Assert-ScopeThrows { ConvertFrom-BenefitJsonpEnvelope -Text 'Cb({"success":true}' -ExpectedCallback 'Cb' } 'Missing close parenthesis fails'
Assert-ScopeThrows { ConvertFrom-BenefitJsonpEnvelope -Text 'Cb([1,2,3])' -ExpectedCallback 'Cb' } 'Non-object root fails'
Assert-ScopeThrows { ConvertFrom-BenefitJsonpEnvelope -Text 'Cb({"success":false})' -ExpectedCallback 'Cb' } 'Unsuccessful MMA response is unusable'
```

Also test an escaped quote/brace inside a string so the object-span scanner cannot split on braces embedded in JSON strings.

- [ ] **Step 3: Run RED**

```powershell
pwsh -NoProfile -File tools/data/test-convert-mma-jsonp-source-observation.ps1
```

Expected: function/file missing failures.

- [ ] **Step 4: Implement strict envelope parsing**

Use an anchored callback pattern only to isolate the enclosed JSON; never `Invoke-Expression`.

Conceptual implementation:

```powershell
function ConvertFrom-BenefitJsonpEnvelope {
    param([string]$Text,[string]$ExpectedCallback)
    if ($ExpectedCallback -cnotmatch '^[A-Za-z_$][A-Za-z0-9_$]*$') { throw 'Invalid expected JSONP callback' }
    $pattern = '\A\s*' + [regex]::Escape($ExpectedCallback) + '\s*\((?<json>.*)\)\s*;?\s*\z'
    $match = [regex]::Match($Text,$pattern,[Text.RegularExpressions.RegexOptions]::Singleline,[TimeSpan]::FromSeconds(1))
    if (-not $match.Success) { throw 'JSONP wrapper invalid or callback mismatch' }
    $json = $match.Groups['json'].Value
    $value = $json | ConvertFrom-Json
    if ($null -eq $value -or $value -is [array]) { throw 'MMA JSONP root must be an object' }
    if ($value.PSObject.Properties.Name -notcontains 'success' -or [bool]$value.success -ne $true) { throw 'MMA JSONP response is unsuccessful' }
    [pscustomobject]@{ JsonText=$json; JsonStart=$match.Groups['json'].Index; Value=$value }
}
```

The scanner for object/array spans must walk characters while tracking string/escape/bracket depth; do not use a regex to parse nested JSON.

- [ ] **Step 5: Implement list/detail adapters**

List:
- require top-level `list` array,
- one unit per list object,
- map exact observed identity properties plus `udgigwan_cd`,
- references use `JSONP_LIST_ITEM_<1-based-index>/<raw-property-name>`.

Detail:
- require top-level `udgigwanVO` object,
- one `JSONP_DETAIL_OBJECT` unit,
- map identity fields plus:
  - `udsangse_cn -> BenefitDescription`
  - `uddaesang_cn -> EligibleTarget`
  - `udjyjehan_cn -> UsageCondition`
  - `udjbjaryo_cn -> VerificationMethod`
  - `hyjeokyong_sjdt -> ValidFrom`
  - `hyjeokyong_jrdt -> ValidUntilObserved`.

Each unit's `RawStart/RawLength/RawFragment` must resolve to the selected object in the original JSONP snapshot.

- [ ] **Step 6: Add provenance-forgery tests**

Mutate:
- another list item's field reference,
- detail `PropertyName`,
- raw span,
- structured value.

Each mutation must make `Assert-ScopeUnit` or `Assert-RelevantBenefitEvidenceSlice` throw.

- [ ] **Step 7: Run GREEN**

```powershell
pwsh -NoProfile -File tools/data/test-convert-mma-jsonp-source-observation.ps1
pwsh -NoProfile -File tools/data/test-benefit-evidence-location-contracts.ps1
```

Expected: PASS.

- [ ] **Step 8: Commit Task 2**

```powershell
git add tools/data/lib/benefit-evidence/convert-mma-jsonp-source-observation.ps1 tools/data/test-convert-mma-jsonp-source-observation.ps1 tools/data/testdata/benefit-evidence-mma
git commit -m "data: parse MMA JSONP evidence safely"
```

---

### Task 3: Reuse the identity locator for JSONP structured units

**Files:**
- Modify: `tools/data/lib/benefit-evidence/find-business-evidence-slice.ps1`
- Modify: `tools/data/test-find-business-evidence-slice.ps1`
- Modify: `tools/data/testdata/benefit-evidence-mma/mma-list.fixture.jsonp`

**Interfaces:**
- Consumes: JSONP list `SourceObservation` with semantic `BusinessName`, `Address`, `Phone`, `Branch`, `InstitutionCode`.
- Produces: existing `Find-BenefitBusinessEvidence` result with `LOCATED / AMBIGUOUS / NOT_FOUND`, where a located JSONP slice carries the selected institution code.

- [ ] **Step 1: Write failing locator tests with MMA list observation**

```powershell
$mmaObservation = ConvertTo-MmaJsonpListObservation -Document $mmaListDocument -ExpectedCallback 'MmaTestList'
$located = Find-BenefitBusinessEvidence -Observation $mmaObservation -Business $tourBusiness -CanonicalPhone $tourPhone
Assert-ScopeEqual $located.Status 'LOCATED' 'MMA list identity can locate one record'
Assert-ScopeEqual $located.Slices[0].StructuredFields.InstitutionCode '2789' 'Located MMA record carries institution code'
```

Add duplicate-name fixture rows:
- same normalized name with insufficient disambiguation -> `AMBIGUOUS`,
- same name but explicit address/phone conflict -> never `LOCATED`,
- a different business with institution code `2789` must not be selected solely because the code exists.

- [ ] **Step 2: Run RED**

```powershell
pwsh -NoProfile -File tools/data/test-find-business-evidence-slice.ps1
```

Expected: current locator/slice contracts reject JSONP unit/slice shape.

- [ ] **Step 3: Make locator source-shape neutral**

Do not change `Get-BenefitEvidenceCandidate` identity logic. It already consumes semantic `StructuredFields`.

Change only source-shape assumptions needed to produce a slice:

```powershell
if ($strong.Count -eq 1 -and $unexcluded.Count -eq 1) {
    $selected = $strong[0]
    $slice = New-RelevantBenefitEvidenceSlice -Observation $Observation -Unit $selected.Unit -IdentityEvidence $selected.Evidence
    ...
}
```

This call remains the same; Task 1's format-dispatched slice constructor owns HTML-vs-JSONP shape.

Ensure `InstitutionCode` is not read by `Get-BenefitEvidenceCandidate`; it is linkage metadata only.

- [ ] **Step 4: Run GREEN including HTML locator regression**

```powershell
pwsh -NoProfile -File tools/data/test-find-business-evidence-slice.ps1
pwsh -NoProfile -File tools/data/test-convert-html-source-observation.ps1
```

Expected: all existing HTML cases and new MMA cases PASS.

- [ ] **Step 5: Commit Task 3**

```powershell
git add tools/data/lib/benefit-evidence/find-business-evidence-slice.ps1 tools/data/test-find-business-evidence-slice.ps1 tools/data/testdata/benefit-evidence-mma/mma-list.fixture.jsonp
git commit -m "data: locate MMA JSONP business evidence"
```

---

### Task 4: Add two-stage MMA list/detail retrieval, linkage checks, and scoped extraction

**Files:**
- Modify: `tools/data/lib/benefit-evidence/benefit-source-run-context.ps1`
- Create: `tools/data/lib/benefit-evidence/invoke-mma-jsonp-benefit-source.ps1`
- Modify: `tools/data/lib/benefit-evidence/extract-benefit-evidence.ps1`
- Modify: `tools/data/lib/benefit-evidence/validate-benefit-evidence.ps1`
- Create: `tools/data/test-mma-jsonp-benefit-source.ps1`
- Modify: `tools/data/test-extract-benefit-evidence.ps1`
- Modify: `tools/data/test-validate-benefit-evidence.ps1`

**Interfaces:**
- Consumes:
  - canonical MMA entry candidate,
  - `NormalizedBusiness`,
  - shared `BenefitSourceRunContext`,
  - `RequestInvoker`.
- Produces:
  - `Invoke-MmaJsonpBenefitSourceCandidate -Candidate -Business -CanonicalPhone -RunContext -RequestInvoker`
  - source record compatible with `Get-Phase2BenefitEvaluation`,
  - detail evidence claims using `ExtractionMethod='SCOPED_JSONP_FIELD'`.

- [ ] **Step 1: Write failing two-stage retrieval tests**

Use a fake request invoker keyed by URL/path. Assert:

```powershell
$record = Invoke-MmaJsonpBenefitSourceCandidate -Candidate $entryCandidate -Business $tourBusiness -CanonicalPhone $tourPhone -RunContext $ctx -RequestInvoker $http

Assert-ScopeEqual $record.LocationResult.Status 'LOCATED' 'MMA list record is located before detail fetch'
Assert-ScopeEqual $record.Document.SourceFormat 'JSONP' 'Returned claim document is the detail JSONP document'
Assert-ScopeEqual $record.Qualified.OfficialityStatus 'VERIFIED_OFFICIAL' 'Detail open.mma.go.kr source is official'
Assert-ScopeEqual $record.Bound.BusinessBindingStatus 'STRONG' 'Located detail remains bound to selected business'
Assert-ScopeEqual @($record.Validation.Claims | Where-Object ClaimType -eq 'BENEFIT_DESCRIPTION').Count 1 'Detail benefit is validated'
Assert-ScopeEqual $record.Validation.Claims[0].ExtractionMethod 'SCOPED_JSONP_FIELD' 'JSONP method is explicit'
```

Track requests:
- first business: list + detail = 2,
- second business in same run: list cache hit + different detail = 1 additional request,
- same institution requested twice: detail cache hit.

- [ ] **Step 2: Add fail-closed linkage tests**

Cases:
- selected list unit missing `InstitutionCode`,
- detail response institution code differs from selected code,
- detail `success=false`,
- detail callback mismatch,
- detail response belongs to another list item,
- list identity ambiguous.

Every case must:
- produce no validated benefit claim,
- never produce `ENDED`,
- preserve a diagnostic,
- leave `ProductionAction` decisions to the unchanged downstream core.

- [ ] **Step 3: Run RED**

```powershell
pwsh -NoProfile -File tools/data/test-mma-jsonp-benefit-source.ps1
```

Expected: MMA invoker does not exist.

- [ ] **Step 4: Add generic run-context caching primitive for explicit JSONP requests**

Do not teach `Get-BenefitSourceFormat` that all `application/json` is JSONP.

Add a narrow helper such as:

```powershell
function Get-BenefitRunExplicitDocument {
    param($Context,$Candidate,[string]$SourceFormat,[scriptblock]$RequestInvoker)
    # cache by exact Candidate.Url
    # same metrics as Get-BenefitRunSourceDocument
    # construct BenefitSourceDocument with the supplied already-approved SourceFormat
}
```

Require `SourceFormat='JSONP'` only from the MMA invoker. Existing generic fetch behavior remains unchanged.

- [ ] **Step 5: Implement the MMA orchestration**

Constants must be exact approved first-party endpoints:

```powershell
$script:MmaEntryUrl = 'https://www.mma.go.kr/about/udgg/list.do?mc=mma0003357'
$script:MmaListUrl = 'https://open.mma.go.kr/caisGGGS/mmanrsrListAjaxJsonCallNew.json?jbc_cd=&udggeopjong_gbcd=&callback=MmaBenefitList'
$script:MmaDetailBaseUrl = 'https://open.mma.go.kr/caisGGGS/mmanrsrSangSeAjaxJsonCall.json'
```

Use a deterministic callback, e.g. `MmaBenefitList` and `MmaBenefitDetail`, so exact request URLs are cacheable.

Flow:

```powershell
entry candidate
  -> derived PUBLIC_OFFICIAL list candidate
  -> cached JSONP list document
  -> list observation
  -> Find-BenefitBusinessEvidence
  -> selected InstitutionCode
  -> derived PUBLIC_OFFICIAL detail candidate
  -> cached JSONP detail document
  -> detail observation
  -> assert detail InstitutionCode == selected InstitutionCode
  -> detail slice
  -> Get-BenefitBusinessBinding
  -> Invoke-BenefitEvidenceExtraction
  -> ConvertTo-ValidatedBenefitEvidence
```

The source record's `Document`, `Qualified`, `Bound`, `Extraction`, and `Validation` should describe the detail source used for claims. Add `LinkageObservation` or diagnostics for the list snapshot rather than synthesizing a combined document.

- [ ] **Step 6: Generalize scoped extraction method by slice source format**

In `Invoke-BenefitEvidenceExtraction`:

```powershell
$method = if ($EvidenceSlice.SourceFormat -ceq 'JSONP') { 'SCOPED_JSONP_FIELD' } else { 'SCOPED_HTML_CELL' }
```

Keep the same semantic detail mapping for:
- `BenefitDescription`,
- `EligibleTarget`,
- `UsageCondition`,
- `VerificationMethod`.

Add `ValidFrom` and `ValidUntilObserved` handling only when the adapter provides non-empty source-backed values:
- `ValidFrom -> VALID_FROM`,
- `ValidUntilObserved -> VALID_UNTIL`.

For `9999-12-31`, either omit the `VALID_UNTIL` claim and preserve it in diagnostics, or return a non-decisive/unknown lifecycle path; it must not become an `ENDED` or active-forever assertion. Pin the chosen behavior in the test. Preferred minimal behavior for this delivery: **omit a decisive `VALID_UNTIL` claim for exactly `9999-12-31` and preserve the observed value in the evidence slice/diagnostic.**

- [ ] **Step 7: Make scoped validation format-neutral**

`Test-ScopedBenefitExtractedClaim` should keep exact source URL/value/reference checks but accept both HTML and JSONP scoped references through `Assert-RelevantBenefitEvidenceSlice`.

Add the date semantic map:

```powershell
$fieldMap = @{
    BENEFIT_DESCRIPTION='BenefitDescription'
    ELIGIBLE_TARGET='EligibleTarget'
    USAGE_CONDITION='UsageCondition'
    VERIFICATION_METHOD='VerificationMethod'
    VALID_FROM='ValidFrom'
    VALID_UNTIL='ValidUntilObserved'
}
```

Do not weaken validation to substring-only matching.

- [ ] **Step 8: Run GREEN**

```powershell
pwsh -NoProfile -File tools/data/test-mma-jsonp-benefit-source.ps1
pwsh -NoProfile -File tools/data/test-extract-benefit-evidence.ps1
pwsh -NoProfile -File tools/data/test-validate-benefit-evidence.ps1
pwsh -NoProfile -File tools/data/test-benefit-source-run-context.ps1
```

Expected: PASS.

- [ ] **Step 9: Commit Task 4**

```powershell
git add tools/data/lib/benefit-evidence/benefit-source-run-context.ps1 tools/data/lib/benefit-evidence/invoke-mma-jsonp-benefit-source.ps1 tools/data/lib/benefit-evidence/extract-benefit-evidence.ps1 tools/data/lib/benefit-evidence/validate-benefit-evidence.ps1 tools/data/test-mma-jsonp-benefit-source.ps1 tools/data/test-extract-benefit-evidence.ps1 tools/data/test-validate-benefit-evidence.ps1
git commit -m "data: verify MMA JSONP list and detail evidence"
```

---

### Task 5: Integrate MMA into mixed scoped shadow mode and prove regressions

**Files:**
- Modify: `tools/data/lib/benefit-evidence/invoke-scoped-benefit-source.ps1`
- Modify: `tools/data/invoke-phase2-benefit-shadow-mode.ps1`
- Create: `tools/data/test-phase2-scoped-mma-jsonp.ps1`
- Modify: `tools/data/test-phase2-scoped-html.ps1`
- Modify: `tools/data/test-phase2-benefit-shadow-mode.ps1`

**Interfaces:**
- Consumes: existing canonical rows whose source URL is the official MMA entry and all existing scoped HTML rows.
- Produces:
  - new runner switch `-UseScopedEvidence`,
  - backward-compatible `-UseScopedHtmlEvidence`,
  - internal dispatch:
    - MMA entry -> `Invoke-MmaJsonpBenefitSourceCandidate`
    - otherwise -> existing `Invoke-ScopedPhase2BenefitSourceCandidate`.

- [ ] **Step 1: Write failing end-to-end MMA shadow test**

Create two canonical-like rows for the two Spike controls with `출처URL` equal to the official MMA entry. Use a fake request invoker serving the sanitized list/detail fixtures.

```powershell
$run = Invoke-Phase2BenefitShadowMode -Rows $rows -SourceRowNumbers @(4,5) -UseScopedEvidence -RequestInvoker $http

Assert-ScopeEqual @($run.Results).Count 2 'Two MMA controls complete shadow evaluation'
Assert-ScopeTrue (@($run.Results | Where-Object ProductionAction -ne 'NONE').Count -eq 0) 'MMA remains shadow-only'
Assert-ScopeEqual @($run.EvidenceDiagnostics | Where-Object SourceFormat -eq 'JSONP').Count 2 'Claim evidence is JSONP'
Assert-ScopeEqual @($run.EvidenceDiagnostics | Where-Object AdapterId -eq 'MMA_JSONP_DETAIL').Count 2 'MMA detail adapter identity is exposed'
Assert-ScopeTrue (@($run.EvidenceDiagnostics[0].ValidatedClaims | Where-Object ClaimType -eq 'BENEFIT_DESCRIPTION').Count -eq 1) 'First control has source-backed benefit'
Assert-ScopeTrue (@($run.EvidenceDiagnostics[1].ValidatedClaims | Where-Object ClaimType -eq 'BENEFIT_DESCRIPTION').Count -eq 1) 'Second control has source-backed benefit'
```

Do not assert that the result is automatically `ACTIVE` or `GREEN`; lifecycle/currentness remains governed by the existing core and canonical comparison.

- [ ] **Step 2: Add mixed-family test**

One MMA row plus one existing HTML fixture in the same `-UseScopedEvidence` run.

Assert:
- both evaluate,
- HTML retains `HTML_GENERIC`,
- MMA uses `MMA_JSONP_DETAIL`,
- no cross-source claim leakage,
- list fetch reused where applicable,
- no discovery/LLM/PDF/XLSX provider is invoked.

- [ ] **Step 3: Run RED**

```powershell
pwsh -NoProfile -File tools/data/test-phase2-scoped-mma-jsonp.ps1
```

Expected: `UseScopedEvidence` / MMA dispatch not implemented.

- [ ] **Step 4: Add source dispatch while preserving the old switch**

In `Invoke-Phase2BenefitShadowMode`:

```powershell
[switch]$UseScopedHtmlEvidence,
[switch]$UseScopedEvidence
```

Rules:
- reject both switches together,
- both prohibit discovery and external extraction providers,
- `UseScopedHtmlEvidence` preserves the exact old HTML-only behavior,
- `UseScopedEvidence` enables per-candidate dispatch.

Inside the scoped evaluator:

```powershell
if (Test-MmaBenefitEntryUrl -Url $existingCandidate.Url) {
    $sourceRecord = Invoke-MmaJsonpBenefitSourceCandidate ...
} else {
    $sourceRecord = Invoke-ScopedPhase2BenefitSourceCandidate ...
}
```

Do not make arbitrary `open.mma.go.kr` URLs generic entry points; only the approved MMA entry URL triggers the two-stage adapter.

- [ ] **Step 5: Keep diagnostics compatible**

Extend `ConvertTo-Phase2ScopedBenefitEvidenceDiagnostic` only with additive linkage diagnostics if needed, for example:

```powershell
LinkageSnapshotId
LinkageEvidenceReference
```

Existing HTML fields and values must remain unchanged.

- [ ] **Step 6: Run targeted GREEN suite**

```powershell
pwsh -NoProfile -File tools/data/test-phase2-scoped-mma-jsonp.ps1
pwsh -NoProfile -File tools/data/test-phase2-scoped-html.ps1
pwsh -NoProfile -File tools/data/test-benefit-source-run-context.ps1
pwsh -NoProfile -File tools/data/test-find-business-evidence-slice.ps1
pwsh -NoProfile -File tools/data/test-extract-benefit-evidence.ps1
pwsh -NoProfile -File tools/data/test-validate-benefit-evidence.ps1
pwsh -NoProfile -File tools/data/test-phase2-benefit-shadow-mode.ps1
```

Expected: all PASS.

- [ ] **Step 7: Run complete data regression scripts used by the Phase 2/A1 path**

From repository root, enumerate the existing Phase 2/A1 test scripts and run the same deterministic suite currently used by CI/project docs. At minimum include:

```powershell
pwsh -NoProfile -File tools/data/test-benefit-verification-contracts.ps1
pwsh -NoProfile -File tools/data/test-discover-official-benefit-sources.ps1
pwsh -NoProfile -File tools/data/test-benefit-evidence-location-contracts.ps1
pwsh -NoProfile -File tools/data/test-convert-html-source-observation.ps1
pwsh -NoProfile -File tools/data/test-bind-benefit-source.ps1
pwsh -NoProfile -File tools/data/test-extract-benefit-evidence.ps1
pwsh -NoProfile -File tools/data/test-validate-benefit-evidence.ps1
pwsh -NoProfile -File tools/data/test-evaluate-benefit-state.ps1
pwsh -NoProfile -File tools/data/test-phase2-scoped-html.ps1
pwsh -NoProfile -File tools/data/test-phase2-scoped-mma-jsonp.ps1
pwsh -NoProfile -File tools/data/test-phase2-benefit-shadow-mode.ps1
```

Expected: zero failures.

- [ ] **Step 8: Verify protected paths and diff**

```powershell
git diff --check origin/dev...HEAD
git diff --name-only origin/dev...HEAD
git status --short
```

Expected changed paths only under:
- `tools/data/lib/**`
- `tools/data/test*.ps1`
- `tools/data/testdata/benefit-evidence-mma/**`
- approved spec/plan docs if they are carried on the implementation branch.

Must not change:
- `apps/**`
- `data/canonical/**`
- `data/seed/**`
- `packages/contracts/**`
- Gradle/Room/auth/API/dependency files.

- [ ] **Step 9: Commit integration**

```powershell
git add tools/data/lib/benefit-evidence/invoke-scoped-benefit-source.ps1 tools/data/invoke-phase2-benefit-shadow-mode.ps1 tools/data/test-phase2-scoped-mma-jsonp.ps1 tools/data/test-phase2-scoped-html.ps1 tools/data/test-phase2-benefit-shadow-mode.ps1
git commit -m "data: integrate MMA JSONP shadow verification"
```

- [ ] **Step 10: Create PR against `dev`**

PR report must include:
- changed files,
- MMA list/detail implementation summary,
- all tests actually run,
- tests not run and why,
- remaining risks,
- no canonical/seed/apps writes,
- `ProductionAction=NONE`,
- next action: early representative Phase 2 validation, not automatic PDF/XLSX/LLM/SNS implementation.

Do not merge without the user's integration decision.

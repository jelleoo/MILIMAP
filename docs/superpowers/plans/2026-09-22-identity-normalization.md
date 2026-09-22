# Identity / Normalization Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Convert one canonical business row into a deterministic, evidence-preserving NormalizedBusiness Contract v1 object without promoting uncertain text into B search terms or C hard-constraint fields.

**Architecture:** Add a pure PowerShell library under tools/data/lib/identity. Helpers derive name/address components and approved warnings; one public function constructs and validates the frozen Contract. The module never invokes B/C, APIs, or orchestration.

**Tech Stack:** PowerShell 7.6.5, repository-native PSCustomObject, frozen tools/data/lib/poi-verification-contracts.ps1; no external dependencies.

**Spec:** docs/superpowers/specs/2026-09-10-benefit-business-verification-pipeline-design.md; docs/superpowers/specs/2026-09-10-poi-verification-contracts-design.md; Issue #28.

## Problem, scope, and risk summary

- **Problem:** canonical business names and addresses cannot safely be used as literal identity keys. A false extracted branch, building number, floor, unit, or locality would become an unsafe B query input or C hard-conflict signal.
- **In scope:** deterministic source preservation, name comparison representation, conservative branch parsing, administrative hierarchy, road/lot parsing, safe road building fields, and the C-compatible floor/unit subset.
- **Out of scope:** Contract changes; B/C/orchestration edits; API calls; POI ranking/classification; canonical or Android seed writes; persistence, schema, API/auth, and new dependencies.
- **Expected implementation files:** tools/data/lib/identity/normalize-business.ps1 and tools/data/test-normalize-business.ps1. No fixture file is planned; cited source strings are compact in-test data.
- **Test method:** each parser behavior begins as a failing PowerShell assertion, then turns green before its checkpoint commit; final gates run Contract, B, C, and every data test script.
- **Primary risk:** false structured evidence is more damaging than missed structure because B/C consume the values as identity evidence. This plan deliberately returns partial output rather than a best guess.

## Baseline and scope

- Implementation baseline: origin/dev 40ac4bffec22ebc1534564201e5e07435f00497f.
- B (PR #34) and C (PR #36) are merged. B queries OriginalName, BaseName, PreferredAddress, locality, RoadName, and BuildingMain/Sub; C uses structured identity fields as match/conflict evidence.
- Change only tools/data/lib/identity/normalize-business.ps1 and tools/data/test-normalize-business.ps1. This plan is the only documentation addition. Use cited in-test canonical strings; do not add a fixture file unless a compact test cannot express the case.
- Do not modify Contract v1, B/C, verify-canonical-benefit-poi.ps1, canonical/seed data, Android code, APIs, schema, credentials, or dependencies.

## Global Constraints

- Emit exactly the Contract v1 fields, empty-string/array rules, status values, and eight warning codes.
- Preserve trimmed source values in OriginalName, OriginalRoadAddress, and OriginalLotAddress. PreferredAddress is trimmed road, otherwise trimmed lot, otherwise empty.
- Emit empty strings instead of guesses. Warning output is duplicate-free and ordered as NAME_EMPTY, NAME_NORMALIZATION_UNCERTAIN, BRANCH_UNCERTAIN, ADDRESS_EMPTY, ADDRESS_PARSE_PARTIAL, ADDRESS_PARSE_FAILED, BUILDING_NUMBER_UNCERTAIN, FLOOR_UNIT_UNCERTAIN.
- COMPLETE describes safe structural parsing only; it does not verify the business, location, benefit, or candidate.
- Tests never rewrite canonical input.

## Review Focus

- 삼육사로902 must produce RoadName 삼육사로 and BuildingMain 902. Task 3.
- 서울대학로264번길 12 must retain 264번길 in RoadName. Task 3.
- 신풍로23번길63- 21층 must produce neither building nor floor. Task 4.
- 테스트 전문점 must not become a branch. Task 1.
- Unit/floor lists and ranges unsupported by current C must remain unstructured. Task 4.

---

## File structure and interfaces

- tools/data/lib/identity/normalize-business.ps1: A-only pure functions; dot-sources the frozen Contract library.
- tools/data/test-normalize-business.ps1: standalone assertion harness and deterministic unit/regression tests.
- docs/superpowers/plans/2026-09-22-identity-normalization.md: this execution plan.

~~~powershell
function ConvertTo-IdentityComparisonText {
    param([AllowNull()]$Value)
    # string: FormKC, invariant lowercase, then remove [\s,().·&-]
}

function Get-NormalizedNameParts {
    param([AllowNull()]$OriginalName, [AllowNull()][string[]]$LocalityHints=@())
    # @{ NormalizedName; BaseName; BranchName; Warnings }
}

function Get-AdministrativeAddressParts {
    param([AllowNull()]$Address)
    # @{ Province; City; District; Dong }
}

function Get-NormalizedAddressParts {
    param([string]$RoadAddress, [string]$LotAddress, [string]$MetadataProvince, [string]$MetadataArea)
    # @{ PreferredAddress; Province; City; District; Dong; RoadName; BuildingMain;
    #    BuildingSub; Floor; Unit; AddressParseStatus; Warnings }
}

function ConvertTo-NormalizedBusiness {
    param([Parameter(Mandatory)]$Row, [Parameter(Mandatory)][int]$SourceRowNumber)
    # returns validated NormalizedBusiness Contract v1
}
~~~

NormalizedName is the comparison key. BaseName and BranchName remain source-like trimmed display/query fragments: B inserts BaseName directly into queries, while C applies its own FormKC/compact comparison.

### Task 1: Name representation and conservative branch parsing

**Files:**

- Create: tools/data/lib/identity/normalize-business.ps1
- Create: tools/data/test-normalize-business.ps1

**Interfaces:**

- Produces ConvertTo-IdentityComparisonText and Get-NormalizedNameParts.
- Get-NormalizedNameParts returns ordered properties NormalizedName, BaseName, BranchName, Warnings.

- [ ] **Step 1: Write the failing name tests**

~~~powershell
. (Join-Path $PSScriptRoot 'lib/identity/normalize-business.ps1')
function Assert-Equal { param($Actual,$Expected,[string]$Message); if ($Actual -cne $Expected) { throw "$Message (expected: $Expected, actual: $Actual)" } }
function Assert-True { param([bool]$Condition,[string]$Message); if (-not $Condition) { throw $Message } }

$name = Get-NormalizedNameParts -OriginalName ' 레드폴바버샵 강남신사점 ' -LocalityHints @('강남','신사')
Assert-Equal $name.NormalizedName '레드폴바버샵강남신사점' 'Comparison form is deterministic'
Assert-Equal $name.BaseName '레드폴바버샵' 'Base is source-like for B'
Assert-Equal $name.BranchName '강남신사점' 'Proved locality branch is retained'

$parenthesized = Get-NormalizedNameParts -OriginalName '만복국수(철산점)'
Assert-Equal $parenthesized.BaseName '만복국수' 'Parenthesized explicit branch splits'
Assert-Equal $parenthesized.BranchName '철산점' 'Parenthesized branch remains source-like'

$negative = Get-NormalizedNameParts -OriginalName '테스트 전문점'
Assert-Equal $negative.BaseName '테스트 전문점' 'Generic type is not stripped'
Assert-Equal $negative.BranchName '' 'Generic type is not branch evidence'
~~~

- [ ] **Step 2: Confirm RED**

Run: pwsh -NoLogo -NoProfile -File tools/data/test-normalize-business.ps1

Expected: FAIL because the library and exported functions do not exist.

- [ ] **Step 3: Implement minimal name functions**

~~~powershell
function ConvertTo-IdentityComparisonText {
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return '' }
    return (([string]$Value).Normalize([Text.NormalizationForm]::FormKC).Trim().ToLowerInvariant() -replace '[\s,().·&-]', '')
}

function Get-NormalizedNameParts {
    param([AllowNull()]$OriginalName, [AllowNull()][string[]]$LocalityHints=@())
    # Split only terminal parenthesized *점, 본점, 직영점, N호점, or a terminal *점
    # whose stem exactly equals concatenated supplied locality-hint stems.
}
~~~

Keep the whole trimmed name as BaseName unless a listed form proves a suffix. Reject 전문점, 음식점, 상점, and 매장 as generic types. Unsupported branch-looking text yields BranchName empty and BRANCH_UNCERTAIN; blank input yields NAME_EMPTY.

- [ ] **Step 4: Confirm GREEN**

Run: pwsh -NoLogo -NoProfile -File tools/data/test-normalize-business.ps1

Expected: all Task 1 assertions pass.

- [ ] **Step 5: Commit checkpoint**

~~~powershell
git add tools/data/lib/identity/normalize-business.ps1 tools/data/test-normalize-business.ps1
git commit -m "feat(data): add conservative identity name parsing"
~~~

### Task 2: Administrative hierarchy and metadata conflict

**Files:**

- Modify: tools/data/lib/identity/normalize-business.ps1
- Modify: tools/data/test-normalize-business.ps1

**Interfaces:**

- Produces Get-AdministrativeAddressParts and administrative merge behavior in Get-NormalizedAddressParts.

- [ ] **Step 1: Write failing hierarchy/conflict tests**

~~~powershell
$seoul = Get-AdministrativeAddressParts '서울특별시 강남구'
Assert-Equal $seoul.Province '서울특별시' 'Province parses'
Assert-Equal $seoul.City '' 'District-only address has no City'
Assert-Equal $seoul.District '강남구' '구 is District'

$suwon = Get-AdministrativeAddressParts '경기도 수원시 권선구'
Assert-Equal $suwon.Province '경기도' 'Province is first'
Assert-Equal $suwon.City '수원시' '시 is City'
Assert-Equal $suwon.District '권선구' '구 is District'

$gapyeong = Get-AdministrativeAddressParts '경기도 가평군 가평읍'
Assert-Equal $gapyeong.City '' '군 is not City'
Assert-Equal $gapyeong.District '가평군' '군 is District'
Assert-Equal $gapyeong.Dong '가평읍' '읍 is Dong'

$conflict = Get-NormalizedAddressParts -RoadAddress '경기도 수원시 권선구 테스트로 1' -LotAddress '' -MetadataProvince '서울특별시' -MetadataArea '강남구'
Assert-Equal $conflict.Province '' 'Conflicted Province is blank'
Assert-Equal $conflict.District '' 'Conflicted District is blank'
Assert-Equal $conflict.AddressParseStatus 'PARTIAL' 'Conflict fails closed'
Assert-True (@($conflict.Warnings) -contains 'ADDRESS_PARSE_PARTIAL') 'Conflict is warned'
~~~

- [ ] **Step 2: Confirm RED**

Run: pwsh -NoLogo -NoProfile -File tools/data/test-normalize-business.ps1

Expected: FAIL because hierarchy parsing and conflict handling are absent.

- [ ] **Step 3: Implement exact hierarchy/merge rules**

~~~powershell
function Get-AdministrativeAddressParts {
    param([AllowNull()]$Address)
    # Recognize exact official province tokens/approved aliases first.
    # City: ...시 only; District: ...구 or ...군; Dong: ...동/...읍/...면.
}
~~~

Use metadata only to fill an empty component. When nonempty address and metadata values disagree, blank the derived component, set PARTIAL, and add ADDRESS_PARSE_PARTIAL; never choose either source as truth. Parse 경기도 광주시 as Province 경기도, City 광주시, never as 광주광역시. Both source addresses blank are UNPARSED plus ADDRESS_EMPTY; a nonblank address with no safe component is UNPARSED plus ADDRESS_PARSE_FAILED.

- [ ] **Step 4: Confirm GREEN**

Run: pwsh -NoLogo -NoProfile -File tools/data/test-normalize-business.ps1

Expected: Task 1 and 2 assertions pass.

- [ ] **Step 5: Commit checkpoint**

~~~powershell
git add tools/data/lib/identity/normalize-business.ps1 tools/data/test-normalize-business.ps1
git commit -m "feat(data): parse administrative identity components"
~~~

### Task 3: No-space road and safe building parsing

**Files:**

- Modify: tools/data/lib/identity/normalize-business.ps1
- Modify: tools/data/test-normalize-business.ps1

**Interfaces:**

- Extends Get-NormalizedAddressParts with RoadName, BuildingMain, and BuildingSub.

- [ ] **Step 1: Write failing cited canonical regressions**

~~~powershell
$gangnam = Get-NormalizedAddressParts -RoadAddress '서울특별시 강남구 강남대로84길23' -LotAddress '' -MetadataProvince '서울특별시' -MetadataArea '강남구'
Assert-Equal $gangnam.RoadName '강남대로84길' 'No-space numbered road stays intact'
Assert-Equal $gangnam.BuildingMain '23' 'Tail is building main'

$inHair = Get-NormalizedAddressParts -RoadAddress '경기도 동두천시 삼육사로902, 2동 104호(생연동)' -LotAddress '' -MetadataProvince '경기도' -MetadataArea '동두천시'
Assert-Equal $inHair.RoadName '삼육사로' 'Canonical row 136 road'
Assert-Equal $inHair.BuildingMain '902' 'Canonical row 136 main'
Assert-Equal $inHair.BuildingSub '' '2동 is not building sub'

$sculls = Get-NormalizedAddressParts -RoadAddress '경기도 시흥시 서울대학로264번길 12, 208동 1층 B-112호' -LotAddress '' -MetadataProvince '경기도' -MetadataArea '시흥시'
Assert-Equal $sculls.RoadName '서울대학로264번길' 'Canonical row 308 numeric road suffix'
Assert-Equal $sculls.BuildingMain '12' 'Canonical row 308 building main'
~~~

- [ ] **Step 2: Confirm RED**

Run: pwsh -NoLogo -NoProfile -File tools/data/test-normalize-business.ps1

Expected: FAIL because road/building properties remain empty.

- [ ] **Step 3: Implement longest-road conservative matching**

~~~powershell
# Match the longest completed road token ending 번길, 길, or 로.
# Only accept main[-sub] immediately after that completed suffix and before a separator/end.
# Never interpret (...동), (...층), (...호), lot numbers, dangling '-', or a competing
# numeric interpretation as BuildingMain/Sub.
~~~

Only split at a completed road suffix boundary, never at arbitrary digits. 23번길 with no building is PARTIAL; lot numbers never populate building fields.

- [ ] **Step 4: Confirm GREEN**

Run: pwsh -NoLogo -NoProfile -File tools/data/test-normalize-business.ps1

Expected: all Task 1–3 tests pass.

- [ ] **Step 5: Commit checkpoint**

~~~powershell
git add tools/data/lib/identity/normalize-business.ps1 tools/data/test-normalize-business.ps1
git commit -m "feat(data): parse conservative road identity fields"
~~~

### Task 4: C-compatible floor/unit subset and malformed numeric safety

**Files:**

- Modify: tools/data/lib/identity/normalize-business.ps1
- Modify: tools/data/test-normalize-business.ps1

**Interfaces:**

- Extends Get-NormalizedAddressParts with Floor, Unit, final parse status, and warnings.

- [ ] **Step 1: Write failing safe and fail-closed tests**

~~~powershell
Assert-Equal $sculls.Floor '1' '208동 does not suppress explicit floor'
Assert-Equal $sculls.Unit 'B-112' 'Alphanumeric unit is preserved'

$safe = Get-NormalizedAddressParts -RoadAddress '경기도 파주시 테스트로 10 지하1층 A-18호' -LotAddress '' -MetadataProvince '경기도' -MetadataArea '파주시'
Assert-Equal $safe.Floor '지하1' 'C-compatible basement floor'
Assert-Equal $safe.Unit 'A-18' 'C-compatible unit'

$multi = Get-NormalizedAddressParts -RoadAddress '경기도 파주시 테스트로 10 101호~102호' -LotAddress '' -MetadataProvince '경기도' -MetadataArea '파주시'
Assert-Equal $multi.Unit '' 'Unit range is not reduced to a singleton'
Assert-Equal $multi.AddressParseStatus 'PARTIAL' 'Unit range is partial'
Assert-True (@($multi.Warnings) -contains 'FLOOR_UNIT_UNCERTAIN') 'Unit range warning'

$malformed = Get-NormalizedAddressParts -RoadAddress '경기도 수원시 팔달구신풍로23번길63- 21층 (신풍동)' -LotAddress '' -MetadataProvince '경기도' -MetadataArea '수원시'
Assert-Equal $malformed.RoadName '신풍로23번길' 'Canonical row 301 keeps safe road'
Assert-Equal $malformed.BuildingMain '' '63-21 ambiguity has no main'
Assert-Equal $malformed.BuildingSub '' '63-21 ambiguity has no sub'
Assert-Equal $malformed.Floor '' 'Ambiguity has no floor'
Assert-Equal $malformed.AddressParseStatus 'PARTIAL' 'Malformed value is partial'
Assert-True (@($malformed.Warnings) -contains 'BUILDING_NUMBER_UNCERTAIN') 'Building ambiguity warning'
Assert-True (@($malformed.Warnings) -contains 'FLOOR_UNIT_UNCERTAIN') 'Floor ambiguity warning'
Assert-True (@($malformed.Warnings) -contains 'ADDRESS_PARSE_PARTIAL') 'Partial warning'
~~~

- [ ] **Step 2: Confirm RED**

Run: pwsh -NoLogo -NoProfile -File tools/data/test-normalize-business.ps1

Expected: FAIL because floor/unit handling is absent.

- [ ] **Step 3: Implement only C-symmetric signals and status rules**

~~~powershell
# Accepted floor: N층, B N층, or 지하 N층 -> N, BN, or 지하N.
# Accepted unit: N호 or letter-N호 -> N or uppercase letter-N.
# Reject ranges, lists, 203-2호, bare B101, and multiple distinct values.
~~~

A recognized Contract-unowned 208동 token alone does not make a safely parsed road address partial; it remains only in the preserved original address. COMPLETE requires a road PreferredAddress with safe RoadName/BuildingMain, at least one nonconflicting administrative component, and no numeric/floor-unit ambiguity. PARTIAL covers safe-but-incomplete road/lot parsing, conflicts, missing building, or rejected material number/floor/unit forms.

- [ ] **Step 4: Confirm GREEN**

Run: pwsh -NoLogo -NoProfile -File tools/data/test-normalize-business.ps1

Expected: all Task 1–4 tests pass, including row 301.

- [ ] **Step 5: Commit checkpoint**

~~~powershell
git add tools/data/lib/identity/normalize-business.ps1 tools/data/test-normalize-business.ps1
git commit -m "feat(data): preserve safe floor and unit identity evidence"
~~~

### Task 5: Public Contract composition and determinism

**Files:**

- Modify: tools/data/lib/identity/normalize-business.ps1
- Modify: tools/data/test-normalize-business.ps1

**Interfaces:**

- Produces ConvertTo-NormalizedBusiness -Row PSCustomObject -SourceRowNumber int.

- [ ] **Step 1: Write failing composer tests**

~~~powershell
$row = [pscustomobject]@{
    업소명=' 레드폴바버샵 강남신사점 '; 시도='서울특별시'; 시군구='강남구'
    소재지도로명주소=' 서울특별시 강남구 논현로151길 41, 2층 201호 '
    소재지지번주소=' 서울특별시 강남구 신사동 561 '
}
$business = ConvertTo-NormalizedBusiness -Row $row -SourceRowNumber 2
Assert-PoiContractTypeAndVersion $business 'NormalizedBusiness'
Assert-NormalizedBusiness $business
Assert-Equal $business.OriginalName '레드폴바버샵 강남신사점' 'Name is trimmed only'
Assert-Equal $business.OriginalRoadAddress '서울특별시 강남구 논현로151길 41, 2층 201호' 'Road evidence preserved'
Assert-Equal $business.OriginalLotAddress '서울특별시 강남구 신사동 561' 'Lot evidence preserved'
Assert-Equal $business.PreferredAddress $business.OriginalRoadAddress 'Road is preferred'
Assert-True ($business.NormalizationWarnings -is [array]) 'Warnings are always arrays'

$again = ConvertTo-NormalizedBusiness -Row $row -SourceRowNumber 2
Assert-Equal ($business | ConvertTo-Json -Depth 8 -Compress) ($again | ConvertTo-Json -Depth 8 -Compress) 'Output is deterministic'

$empty = ConvertTo-NormalizedBusiness -Row ([pscustomobject]@{ 업소명=''; 시도=''; 시군구=''; 소재지도로명주소=''; 소재지지번주소='' }) -SourceRowNumber 3
Assert-Equal $empty.AddressParseStatus 'UNPARSED' 'Empty address is unparsed'
Assert-True (@($empty.NormalizationWarnings) -contains 'ADDRESS_EMPTY') 'Empty address warning'
~~~

- [ ] **Step 2: Confirm RED**

Run: pwsh -NoLogo -NoProfile -File tools/data/test-normalize-business.ps1

Expected: FAIL because the public composer is absent.

- [ ] **Step 3: Implement the Contract boundary**

~~~powershell
function ConvertTo-NormalizedBusiness {
    param([Parameter(Mandatory)]$Row, [Parameter(Mandatory)][int]$SourceRowNumber)
    # Read only 업소명, 소재지도로명주소, 소재지지번주소, 시도, 시군구.
    # Compose New-NormalizedBusiness from helper output, Assert-NormalizedBusiness, return it.
}
~~~

Build name locality hints only from safe reconciled locality values. Do not mutate Row, access files/network, or return fields/codes outside Contract v1.

- [ ] **Step 4: Confirm GREEN**

Run: pwsh -NoLogo -NoProfile -File tools/data/test-normalize-business.ps1

Expected: every A assertion and Contract assertion passes.

- [ ] **Step 5: Commit checkpoint**

~~~powershell
git add tools/data/lib/identity/normalize-business.ps1 tools/data/test-normalize-business.ps1
git commit -m "feat(data): emit normalized business contract"
~~~

### Task 6: Regression and scope gate

**Files:**

- Verify only: tools/data/test-normalize-business.ps1
- Verify only: tools/data/test-poi-verification-contracts.ps1
- Verify only: tools/data/test-discover-poi-candidates.ps1
- Verify only: tools/data/test-evaluate-poi-match.ps1
- Verify only: all tools/data/test-*.ps1

- [ ] **Step 1: Run A, Contract, B, and C gates**

~~~powershell
pwsh -NoLogo -NoProfile -File tools/data/test-normalize-business.ps1
pwsh -NoLogo -NoProfile -File tools/data/test-poi-verification-contracts.ps1
pwsh -NoLogo -NoProfile -File tools/data/test-discover-poi-candidates.ps1
pwsh -NoLogo -NoProfile -File tools/data/test-evaluate-poi-match.ps1
~~~

Expected: all commands exit 0; B/C pass without source edits.

- [ ] **Step 2: Run every data test**

~~~powershell
Get-ChildItem -LiteralPath tools/data -Filter 'test-*.ps1' -File |
    Sort-Object Name |
    ForEach-Object { & pwsh -NoLogo -NoProfile -File $_.FullName; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE } }
~~~

Expected: every script exits 0; report exact count and any environment-limited test.

- [ ] **Step 3: Prove scope integrity**

~~~powershell
git diff --check origin/dev...HEAD
git diff --name-only origin/dev...HEAD
git diff --name-only origin/dev...HEAD -- tools/data/lib/poi-verification-contracts.ps1 tools/data/lib/poi-discovery tools/data/lib/poi-matching tools/data/verify-canonical-benefit-poi.ps1 data/canonical data/seed apps/android
~~~

Expected: whitespace check exits 0; implementation changes are only the A library/test paths, with the approved plan document as the sole documentation path; forbidden-path command prints nothing.

- [ ] **Step 4: Record the clean final checkpoint**

~~~powershell
git status --short
git log -1 --oneline
~~~

Expected: no untracked or unstaged implementation artifact remains; do not amend or create unrelated commits.

## Self-review

- Contract alignment: all output fields, statuses, and warnings come from frozen New-NormalizedBusiness and Assert-NormalizedBusiness; no contract change is proposed.
- B/C compatibility: BaseName remains query-ready; NormalizedName uses B-compatible cleanup; floor/unit forms are restricted to C current comparable grammar.
- Actual malformed coverage: row 136 (삼육사로902), row 308 (서울대학로264번길 12, 208동), and row 301 (신풍로23번길63- 21층) are explicit tests.
- False-evidence coverage: administrative conflict, generic branch suffix, building/dong confusion, numeric ambiguity, and unit range/list all fail closed.
- Placeholder scan: this plan contains no unresolved task, interface, warning code, or verification command.

## Execution handoff

Human review and approval are required before implementation. On approval, create an isolated worktree from then-current origin/dev, run git fetch origin, and confirm the baseline before Task 1. Do not begin implementation from this document before approval.


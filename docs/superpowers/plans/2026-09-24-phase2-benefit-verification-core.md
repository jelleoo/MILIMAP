# Phase 2 Benefit Verification Core Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Build the provider-neutral Phase 2 Benefit Verification Core that revalidates official benefit evidence, qualifies and binds sources, validates extracted claims, deterministically evaluates BenefitState/ReviewClass, and emits Shadow Mode review artifacts without writing production data.

**Architecture:** Follow the existing PowerShell data-tool pattern under tools/data. Add a separate Phase 2 contract and focused source, evidence, verification, and orchestration modules. Existing official URLs can be fetched directly. General web search, LLM extraction, spreadsheet parsing, and PDF text extraction remain injectable boundaries so this foundation can be implemented without silently selecting a new external dependency or provider.

**Tech Stack:** PowerShell 7+, .NET BCL, repository-local .ps1 files, existing Phase 1 NormalizedBusiness contract.

**Spec:** docs/superpowers/specs/2026-09-24-benefit-verification-core-design.md

## Global Constraints

- Start implementation from the latest dev. Plan-time baseline: dev@9a435159cb26b793057797cafe37e8f922fe3a81.
- Every final result has ProductionAction=NONE.
- Do not modify canonical data, Android seed/assets, Room/server DB, API contract, auth, or product UI.
- Do not add a web-search provider, LLM provider/model/SDK, PDF/XLSX library, or other external dependency without explicit approval.
- Officiality and currentness remain separate.
- Search/fetch/parser/extractor failure never implies ACTIVE or ENDED.
- ENDED requires validated explicit ending evidence.
- LLM output, when a provider is later supplied, remains extraction-only and must pass Evidence Validation.
- Phase 1 GREEN is not required to run Phase 2.
- Keep Phase 1 contract/module behavior unchanged.
- Synthetic test fixtures must never be confused with production benefit data.
- This plan implements the provider-neutral Core Foundation only. Full 247-row held-workload closeout requires separately approved live discovery and extraction adapters.

## File Map

Create:
- tools/data/lib/benefit-verification-contracts.ps1
- tools/data/lib/benefit-source/discover-official-benefit-sources.ps1
- tools/data/lib/benefit-source/qualify-official-benefit-source.ps1
- tools/data/lib/benefit-source/bind-benefit-source.ps1
- tools/data/lib/benefit-evidence/extract-benefit-evidence.ps1
- tools/data/lib/benefit-evidence/validate-benefit-evidence.ps1
- tools/data/lib/benefit-verification/compare-benefit-claims.ps1
- tools/data/lib/benefit-verification/evaluate-benefit-state.ps1
- tools/data/invoke-phase2-benefit-shadow-mode.ps1
- tools/data/test-benefit-verification-contracts.ps1
- tools/data/test-discover-official-benefit-sources.ps1
- tools/data/test-qualify-official-benefit-source.ps1
- tools/data/test-bind-benefit-source.ps1
- tools/data/test-extract-benefit-evidence.ps1
- tools/data/test-validate-benefit-evidence.ps1
- tools/data/test-compare-benefit-claims.ps1
- tools/data/test-evaluate-benefit-state.ps1
- tools/data/test-phase2-benefit-shadow-mode.ps1
- tools/data/testdata/phase2-benefit-golden.psd1

Modify after code/tests are green:
- tools/data/README.md
- docs/current-work.md
- docs/current-status.md

Do not mark docs/roadmap.md Phase 2 COMPLETE in this foundation plan.

## Review Focus

1. Existing official URL 404/timeout -> NEEDS_VERIFICATION, never ENDED.
2. Same-name different branch -> AMBIGUOUS/CONFLICT, never STRONG from name alone.
3. Old official page -> officiality may be valid while currentness remains UNKNOWN.
4. Extracted percentage/date absent from source -> INVALID with EXTRACTION_SOURCE_MISMATCH.
5. Conflicting official evidence -> NEEDS_VERIFICATION + RED + SOURCE_CONFLICT with both sources preserved.

---

### Task 1: Freeze Phase 2 Contracts

**Files:**
- Create: tools/data/lib/benefit-verification-contracts.ps1
- Create: tools/data/test-benefit-verification-contracts.ps1

**Interfaces:**
Produce constructors/assertions for:
- CanonicalBenefitRecord
- BenefitSourceCandidate
- BenefitSourceDocument
- QualifiedBenefitSource
- BoundBenefitSource
- ExtractedBenefitClaim
- ValidatedBenefitClaim
- BenefitClaimVerification
- BenefitVerificationResult

Required code sets:
- SourceDiscoveryStatus: COMPLETE, PARTIAL, FAILED
- SourceFormat: HTML, CSV, XLSX, PDF, UNSUPPORTED
- SourceKind: PUBLIC_OFFICIAL, BUSINESS_WEBSITE
- OfficialityStatus: VERIFIED_OFFICIAL, UNVERIFIED, REJECTED
- BusinessBindingStatus: STRONG, PLAUSIBLE, AMBIGUOUS, CONFLICT
- ExtractionStatus: COMPLETE, PARTIAL, FAILED
- EvidenceValidationStatus: VALIDATED, UNKNOWN, CONFLICT, INVALID
- ClaimType: BENEFIT_EXISTENCE, CURRENT_APPLICABILITY, BENEFIT_DESCRIPTION, ELIGIBLE_TARGET, USAGE_CONDITION, VERIFICATION_METHOD, VALID_FROM, VALID_UNTIL
- ClaimResult: CONFIRMED, CHANGED, ENDED, UNKNOWN, CONFLICT, NOT_APPLICABLE
- BenefitState: ACTIVE, CHANGED, ENDED, NEEDS_VERIFICATION
- ReviewClass: GREEN, YELLOW, RED
- ProductionAction: NONE

Required reason codes:
SOURCE_NOT_FOUND, SOURCE_FETCH_FAILED, SOURCE_UNSUPPORTED, SOURCE_OFFICIALITY_UNRESOLVED,
BUSINESS_BINDING_AMBIGUOUS, BUSINESS_BINDING_CONFLICT, CURRENTNESS_INSUFFICIENT,
DISCOVERY_PROVIDER_NOT_CONFIGURED, DISCOVERY_PARTIAL_FAILURE, DISCOVERY_FAILED,
EXTRACTION_PROVIDER_NOT_CONFIGURED, EXTRACTION_FAILED, EXTRACTION_SOURCE_MISMATCH,
CLAIM_UNKNOWN, DETAIL_INCOMPLETE, MATERIAL_CHANGE, EXPLICIT_VALIDITY_END,
EXPLICIT_DISCONTINUATION, SOURCE_CONFLICT, COMPOSITE_EVIDENCE_USED.

- [ ] **Step 1: Write failing contract tests**

~~~powershell
$ErrorActionPreference = 'Stop'
$contractPath = Join-Path $PSScriptRoot 'lib/benefit-verification-contracts.ps1'
if (Test-Path -LiteralPath $contractPath) { . $contractPath }

function Assert-Equal { param($Actual,$Expected,[string]$Message) if ($Actual -cne $Expected) { throw "$Message expected=$Expected actual=$Actual" } }
function Assert-Throws { param([scriptblock]$Action,[string]$Message) $threw=$false; try { & $Action } catch { $threw=$true }; if (-not $threw) { throw $Message } }

$benefit = New-CanonicalBenefitRecord -SourceRowNumber 2 -BusinessName '테스트 식당' -BenefitDescription '10% 할인' -EligibleTarget '현역 장병' -UsageCondition '평일' -VerificationMethod '군인증' -ExistingSourceType '지자체 공식 자료' -ExistingSourceUrl 'https://example.go.kr/benefit' -ExistingVerifiedOn '2026-09-01'
Assert-CanonicalBenefitRecord $benefit
Assert-Equal $benefit.ContractVersion 1 'contract version'

$result = New-BenefitVerificationResult -SourceRowNumber 2 -BenefitState 'ACTIVE' -ReviewClass 'YELLOW' -ReasonCodes @('DETAIL_INCOMPLETE')
Assert-BenefitVerificationResult $result
Assert-Equal $result.ProductionAction 'NONE' 'shadow action'

Assert-Throws { $x=New-BenefitVerificationResult -SourceRowNumber 2 -ProductionAction 'APPLY'; Assert-BenefitVerificationResult $x } 'non-NONE production action must fail'
Assert-Throws { $x=New-ValidatedBenefitClaim -ClaimType 'VALID_UNTIL' -Value '2026-12-31' -ValidationStatus 'VALIDATED' -EvidenceText ''; Assert-ValidatedBenefitClaim $x } 'validated claim requires source evidence'

Write-Output 'PASS: benefit verification contracts'
~~~

- [ ] **Step 2: Run RED**

Run:
~~~powershell
pwsh -NoProfile -File .\tools\data\test-benefit-verification-contracts.ps1
~~~

Expected: FAIL because the Phase 2 contract does not exist.

- [ ] **Step 3: Implement minimal contracts**

Use the same strict ordered-object pattern as tools/data/lib/poi-verification-contracts.ps1. Add ConvertTo-BenefitText, ConvertTo-BenefitArray, explicit allowed-code checks, and Assert-* functions. Assert-BenefitVerificationResult must reject any ProductionAction other than NONE.

Representative constructor:

~~~powershell
function New-BenefitVerificationResult {
    param([int]$SourceRowNumber,[string]$BenefitState='NEEDS_VERIFICATION',[string]$ReviewClass='YELLOW',[object[]]$ReasonCodes=@(),[object[]]$ClaimResults=@(),[object[]]$Evidence=@(),[object[]]$Warnings=@(),[string]$ProductionAction='NONE')
    [pscustomobject][ordered]@{ ContractType='BenefitVerificationResult'; ContractVersion=1; SourceRowNumber=$SourceRowNumber; BenefitState=$BenefitState; ReviewClass=$ReviewClass; ReasonCodes=@($ReasonCodes); ClaimResults=@($ClaimResults); Evidence=@($Evidence); Warnings=@($Warnings); ProductionAction=$ProductionAction }
}
~~~

- [ ] **Step 4: Run GREEN + Phase 1 contract regression**

~~~powershell
pwsh -NoProfile -File .\tools\data\test-benefit-verification-contracts.ps1
pwsh -NoProfile -File .\tools\data\test-poi-verification-contracts.ps1
~~~

Expected: PASS, PASS.

- [ ] **Step 5: Commit**

~~~bash
git add tools/data/lib/benefit-verification-contracts.ps1 tools/data/test-benefit-verification-contracts.ps1
git commit -m "feat: add benefit verification contracts"
~~~

---

### Task 2: Existing-Source Revalidation and Controlled Discovery Boundary

**Files:**
- Create: tools/data/lib/benefit-source/discover-official-benefit-sources.ps1
- Create: tools/data/test-discover-official-benefit-sources.ps1

**Interfaces:**
- Get-ExistingBenefitSourceCandidate -Benefit
- Invoke-OfficialBenefitSourceDiscovery -Benefit -Business -DiscoveryInvoker
- Get-BenefitSourceDocument -Candidate -RequestInvoker
- Test-BenefitSafeHttpUri -Url

DiscoveryInvoker:
param($Benefit,$Business) -> objects with Url, SourceKind, SourceLabel.

RequestInvoker:
param($Uri) -> object with StatusCode, ContentType, Text, Bytes.

- [ ] **Step 1: Write failing tests**

~~~powershell
$candidate = Get-ExistingBenefitSourceCandidate -Benefit $benefit
Assert-Equal $candidate.Url 'https://city.example.go.kr/current' 'existing URL first'
Assert-Equal $candidate.DiscoveryMethod 'EXISTING_CANONICAL_URL' 'existing source provenance'

Assert-Throws { Get-BenefitSourceDocument -Candidate (New-BenefitSourceCandidate -SourceRowNumber 2 -Url 'file:///etc/passwd') -RequestInvoker { param($Uri) throw 'must not call' } } 'reject non-http URL'

$doc = Get-BenefitSourceDocument -Candidate $candidate -RequestInvoker { param($Uri) [pscustomobject]@{ StatusCode=200; ContentType='text/html'; Text='<html>군인 할인</html>'; Bytes=$null } }
Assert-Equal $doc.FetchStatus 'COMPLETE' 'fetch complete'
Assert-Equal $doc.SourceFormat 'HTML' 'format detection'

$failed = Get-BenefitSourceDocument -Candidate $candidate -RequestInvoker { param($Uri) throw 'timeout' }
Assert-Equal $failed.FetchStatus 'FAILED' 'timeout stays operational failure'
Assert-True ($failed.ReasonCodes -contains 'SOURCE_FETCH_FAILED') 'explicit fetch reason'

$discovery = Invoke-OfficialBenefitSourceDiscovery -Benefit $benefitWithoutUrl -Business $business
Assert-Equal $discovery.Status 'FAILED' 'missing provider fails closed'
Assert-True ($discovery.ReasonCodes -contains 'DISCOVERY_PROVIDER_NOT_CONFIGURED') 'provider absence is explicit'
~~~

Also test rejection of localhost, loopback/link-local IP literals, embedded credentials, file/data schemes.

- [ ] **Step 2: Run RED**

~~~powershell
pwsh -NoProfile -File .\tools\data\test-discover-official-benefit-sources.ps1
~~~

Expected: FAIL.

- [ ] **Step 3: Implement provider-neutral discovery/fetch**

Rules:
- Existing canonical URL is emitted first but is not automatically official.
- No DiscoveryInvoker -> FAILED + DISCOVERY_PROVIDER_NOT_CONFIGURED.
- Discovery output is candidate URL metadata only; search snippets never become evidence.
- Safe fetch only accepts http/https and explicit public-looking hosts.
- Fetch exceptions -> FetchStatus=FAILED + SOURCE_FETCH_FAILED.
- Detect HTML/CSV/XLSX/PDF/UNSUPPORTED by content type and extension.
- Preserve ObservedAt; never assign benefit state here.

- [ ] **Step 4: Run GREEN**

~~~powershell
pwsh -NoProfile -File .\tools\data\test-discover-official-benefit-sources.ps1
pwsh -NoProfile -File .\tools\data\test-benefit-verification-contracts.ps1
~~~

Expected: PASS.

- [ ] **Step 5: Commit**

~~~bash
git add tools/data/lib/benefit-source/discover-official-benefit-sources.ps1 tools/data/test-discover-official-benefit-sources.ps1
git commit -m "feat: add official benefit source boundary"
~~~

---

### Task 3: Source Qualification and Business Binding

**Files:**
- Create: tools/data/lib/benefit-source/qualify-official-benefit-source.ps1
- Create: tools/data/lib/benefit-source/bind-benefit-source.ps1
- Create: tools/data/test-qualify-official-benefit-source.ps1
- Create: tools/data/test-bind-benefit-source.ps1

**Interfaces:**
- Get-QualifiedBenefitSource -Candidate -Document -Business
- Get-BenefitBusinessBinding -Source -Business -CanonicalPhone

- [ ] **Step 1: Write failing qualification tests**

~~~powershell
$gov = Get-QualifiedBenefitSource -Candidate $candidateGoKr -Document $documentGoKr -Business $business
Assert-Equal $gov.OfficialityStatus 'VERIFIED_OFFICIAL' '.go.kr public source'
Assert-Equal $gov.CurrentnessStatus 'UNKNOWN' 'official does not mean current'

$businessSite = Get-QualifiedBenefitSource -Candidate $candidateBusiness -Document $businessDoc -Business $business
Assert-Equal $businessSite.OfficialityStatus 'VERIFIED_OFFICIAL' 'business site requires identity corroboration'

$nameOnly = Get-QualifiedBenefitSource -Candidate $candidateBusiness -Document $nameOnlyDoc -Business $business
Assert-Equal $nameOnly.OfficialityStatus 'UNVERIFIED' 'name alone cannot prove official ownership'
~~~

In this provider-neutral foundation, automatic public-source verification is limited to hosts ending in .go.kr. Other public-institution domains remain UNVERIFIED until a later approved source registry/adapter supports them.

- [ ] **Step 2: Write failing binding tests**

~~~powershell
$strong = Get-BenefitBusinessBinding -Source $qualified -Business $business -CanonicalPhone '02-1234-5678'
Assert-Equal $strong.BusinessBindingStatus 'STRONG' 'name plus address binds'

$nameOnlyBinding = Get-BenefitBusinessBinding -Source $qualifiedNameOnly -Business $business -CanonicalPhone ''
Assert-True ($nameOnlyBinding.BusinessBindingStatus -ne 'STRONG') 'name alone not strong'

$wrongBranch = Get-BenefitBusinessBinding -Source $qualifiedWrongBranch -Business $business -CanonicalPhone '02-1234-5678'
Assert-Equal $wrongBranch.BusinessBindingStatus 'CONFLICT' 'explicit branch conflict'
~~~

Cover STRONG, PLAUSIBLE, AMBIGUOUS, CONFLICT; branch/building/locality conflict must outrank fuzzy/name compatibility.

- [ ] **Step 3: Run RED**

~~~powershell
pwsh -NoProfile -File .\tools\data\test-qualify-official-benefit-source.ps1
pwsh -NoProfile -File .\tools\data\test-bind-benefit-source.ps1
~~~

Expected: FAIL.

- [ ] **Step 4: Implement qualification and binding**

Qualification:
- successful .go.kr document -> VERIFIED_OFFICIAL,
- officiality does not set currentness,
- business website -> normalized business name + at least one address/branch/phone identity signal,
- unresolved ownership -> UNVERIFIED.

Binding:
- reuse NormalizedBusiness fields,
- name-only cannot become STRONG,
- explicit identity conflict -> CONFLICT,
- preserve matched/conflicted signals as evidence.

- [ ] **Step 5: Run GREEN + Phase 1 identity regressions**

~~~powershell
pwsh -NoProfile -File .\tools\data\test-qualify-official-benefit-source.ps1
pwsh -NoProfile -File .\tools\data\test-bind-benefit-source.ps1
pwsh -NoProfile -File .\tools\data\test-normalize-business.ps1
pwsh -NoProfile -File .\tools\data\test-evaluate-poi-match.ps1
~~~

Expected: all PASS.

- [ ] **Step 6: Commit**

~~~bash
git add tools/data/lib/benefit-source/qualify-official-benefit-source.ps1 tools/data/lib/benefit-source/bind-benefit-source.ps1 tools/data/test-qualify-official-benefit-source.ps1 tools/data/test-bind-benefit-source.ps1
git commit -m "feat: qualify and bind benefit sources"
~~~

---

### Task 4: Evidence Extraction and Evidence Validation

**Files:**
- Create: tools/data/lib/benefit-evidence/extract-benefit-evidence.ps1
- Create: tools/data/lib/benefit-evidence/validate-benefit-evidence.ps1
- Create: tools/data/test-extract-benefit-evidence.ps1
- Create: tools/data/test-validate-benefit-evidence.ps1

**Interfaces:**
- Invoke-BenefitEvidenceExtraction -Source -Document -UnstructuredExtractor -SpreadsheetExtractor -PdfTextExtractor
- Test-BenefitExtractedClaim -Claim -Document
- ConvertTo-ValidatedBenefitEvidence -Extraction -Document

- [ ] **Step 1: Write failing extraction tests**

~~~powershell
$html = '<table><tr><th>업소명</th><th>주소</th><th>할인</th></tr><tr><td>테스트 식당</td><td>서울 마포구 테스트로 12</td><td>10% 할인</td></tr></table>'
$htmlDoc = New-BenefitSourceDocument -SourceRowNumber 2 -Url 'https://city.example.go.kr/list' -SourceFormat 'HTML' -FetchStatus 'COMPLETE' -Text $html
$extraction = Invoke-BenefitEvidenceExtraction -Source $bound -Document $htmlDoc
Assert-Equal $extraction.Status 'COMPLETE' 'structured HTML extraction'
Assert-True (@($extraction.Claims | Where-Object { $_.ClaimType -eq 'BENEFIT_DESCRIPTION' -and $_.Value -eq '10% 할인' }).Count -eq 1) 'source benefit extracted'

$freeTextDoc = New-BenefitSourceDocument -SourceRowNumber 2 -Url 'https://city.example.go.kr/notice' -SourceFormat 'HTML' -FetchStatus 'COMPLETE' -Text '<p>현역 장병 혜택 안내</p>'
$noExtractor = Invoke-BenefitEvidenceExtraction -Source $bound -Document $freeTextDoc
Assert-Equal $noExtractor.Status 'FAILED' 'free text needs approved extractor'
Assert-True ($noExtractor.ReasonCodes -contains 'EXTRACTION_PROVIDER_NOT_CONFIGURED') 'missing extractor reason'

$pdfDoc = New-BenefitSourceDocument -SourceRowNumber 2 -Url 'https://city.example.go.kr/a.pdf' -SourceFormat 'PDF' -FetchStatus 'COMPLETE' -Bytes ([byte[]](1,2,3))
$pdf = Invoke-BenefitEvidenceExtraction -Source $bound -Document $pdfDoc
Assert-Equal $pdf.Status 'FAILED' 'PDF without adapter fails closed'
~~~

XLSX uses injected SpreadsheetExtractor in this foundation; do not install a parser.

- [ ] **Step 2: Write failing validation tests**

~~~powershell
$claim = New-ExtractedBenefitClaim -ClaimType 'BENEFIT_DESCRIPTION' -Value '20% 할인' -EvidenceText '현역 장병 20% 할인'
$validated = Test-BenefitExtractedClaim -Claim $claim -Document $docContaining20
Assert-Equal $validated.ValidationStatus 'VALIDATED' 'exact source support'

$invented = New-ExtractedBenefitClaim -ClaimType 'VALID_UNTIL' -Value '2026-12-31' -EvidenceText '2026-12-31까지'
$invalid = Test-BenefitExtractedClaim -Claim $invented -Document $docWithoutDate
Assert-Equal $invalid.ValidationStatus 'INVALID' 'invented date rejected'
Assert-True ($invalid.ReasonCodes -contains 'EXTRACTION_SOURCE_MISMATCH') 'mismatch reason'

$postDate = New-ExtractedBenefitClaim -ClaimType 'VALID_FROM' -Value '2026-04-03' -EvidenceText '게시일 2026-04-03'
$wrongMeaning = Test-BenefitExtractedClaim -Claim $postDate -Document $postDateDoc
Assert-True ($wrongMeaning.ValidationStatus -ne 'VALIDATED') 'publication date not validFrom'
~~~

- [ ] **Step 3: Run RED**

~~~powershell
pwsh -NoProfile -File .\tools\data\test-extract-benefit-evidence.ps1
pwsh -NoProfile -File .\tools\data\test-validate-benefit-evidence.ps1
~~~

Expected: FAIL.

- [ ] **Step 4: Implement deterministic extraction**

Supported without new dependency:
- HTML cleanup and conservative table parsing.
- CSV through ConvertFrom-Csv.
- Free-form HTML through UnstructuredExtractor only.
- PDF through PdfTextExtractor, then UnstructuredExtractor.
- XLSX through SpreadsheetExtractor.

Recognized structured headers:
- business: 업소명, 업체명, 상호
- address: 주소, 소재지, 소재지도로명주소
- phone: 전화번호, 연락처
- benefit: 할인, 할인정보, 할인내용, 혜택, 서비스

- [ ] **Step 5: Implement Evidence Validation**

Rules:
- evidence text must actually occur in source content after whitespace/entity normalization,
- extracted numeric amount/percentage/date must occur in evidence text and source,
- publication date wording cannot become validFrom/validUntil,
- mismatch becomes INVALID/UNKNOWN/CONFLICT, never silent repair,
- preserve source URL and evidence text.

- [ ] **Step 6: Run GREEN**

~~~powershell
pwsh -NoProfile -File .\tools\data\test-extract-benefit-evidence.ps1
pwsh -NoProfile -File .\tools\data\test-validate-benefit-evidence.ps1
pwsh -NoProfile -File .\tools\data\test-benefit-verification-contracts.ps1
~~~

Expected: PASS.

- [ ] **Step 7: Commit**

~~~bash
git add tools/data/lib/benefit-evidence/extract-benefit-evidence.ps1 tools/data/lib/benefit-evidence/validate-benefit-evidence.ps1 tools/data/test-extract-benefit-evidence.ps1 tools/data/test-validate-benefit-evidence.ps1
git commit -m "feat: extract and validate benefit evidence"
~~~

---

### Task 5: Claim Comparison and Deterministic Evaluation

**Files:**
- Create: tools/data/lib/benefit-verification/compare-benefit-claims.ps1
- Create: tools/data/lib/benefit-verification/evaluate-benefit-state.ps1
- Create: tools/data/test-compare-benefit-claims.ps1
- Create: tools/data/test-evaluate-benefit-state.ps1

**Interfaces:**
- Compare-BenefitClaim -ClaimType -CanonicalValue -EvidenceValue
- Compare-BenefitClaims -Benefit -ValidatedEvidence
- Invoke-BenefitStateEvaluation -Benefit -Sources -ClaimResults -OperationalStatus

- [ ] **Step 1: Write failing comparison tests**

~~~powershell
$same = Compare-BenefitClaim -ClaimType 'BENEFIT_DESCRIPTION' -CanonicalValue '10% 할인' -EvidenceValue '이용금액 10% 할인'
Assert-Equal $same.Result 'CONFIRMED' 'same explicit percentage'

$changed = Compare-BenefitClaim -ClaimType 'BENEFIT_DESCRIPTION' -CanonicalValue '10% 할인' -EvidenceValue '20% 할인'
Assert-Equal $changed.Result 'CHANGED' 'explicit percentage change'

$unknown = Compare-BenefitClaim -ClaimType 'ELIGIBLE_TARGET' -CanonicalValue '현역 장병' -EvidenceValue '군 관계자'
Assert-Equal $unknown.Result 'UNKNOWN' 'ambiguous semantics stay unknown'

$condition = Compare-BenefitClaim -ClaimType 'USAGE_CONDITION' -CanonicalValue '상시' -EvidenceValue '평일만'
Assert-Equal $condition.Result 'CHANGED' 'explicit usage restriction'
~~~

If deterministic rules cannot prove equivalence or material difference, return UNKNOWN.

- [ ] **Step 2: Write failing evaluation tests**

~~~powershell
$ended = Invoke-BenefitStateEvaluation -Benefit $benefit -Sources @($strongCurrentSource) -ClaimResults @($explicitEndClaim) -OperationalStatus $complete
Assert-Equal $ended.BenefitState 'ENDED' 'explicit ending evidence'
Assert-Equal $ended.ReviewClass 'GREEN' 'strong end can be fast review'

$failure = Invoke-BenefitStateEvaluation -Benefit $benefit -Sources @() -ClaimResults @() -OperationalStatus ([pscustomobject]@{ DiscoveryStatus='FAILED'; ExtractionStatus='FAILED' })
Assert-Equal $failure.BenefitState 'NEEDS_VERIFICATION' 'failure is not ended'

$conflict = Invoke-BenefitStateEvaluation -Benefit $benefit -Sources @($sourceA,$sourceB) -ClaimResults @($conflictingClaim) -OperationalStatus $complete
Assert-Equal $conflict.BenefitState 'NEEDS_VERIFICATION' 'no automatic source winner'
Assert-Equal $conflict.ReviewClass 'RED' 'material conflict is red'
Assert-True ($conflict.ReasonCodes -contains 'SOURCE_CONFLICT') 'conflict reason preserved'

$activeIncomplete = Invoke-BenefitStateEvaluation -Benefit $benefit -Sources @($strongCurrentSource) -ClaimResults @($existenceConfirmed,$currentConfirmed,$benefitConfirmed,$targetConfirmed,$usageUnknown,$methodUnknown) -OperationalStatus $complete
Assert-Equal $activeIncomplete.BenefitState 'ACTIVE' 'lifecycle can be active with detail gaps'
Assert-Equal $activeIncomplete.ReviewClass 'YELLOW' 'detail gaps block green'

$changedGreen = Invoke-BenefitStateEvaluation -Benefit $benefit -Sources @($strongCurrentSource) -ClaimResults @($existenceConfirmed,$currentConfirmed,$benefitChanged,$targetConfirmed,$usageConfirmed,$methodConfirmed) -OperationalStatus $complete
Assert-Equal $changedGreen.BenefitState 'CHANGED' 'material change'
Assert-Equal $changedGreen.ReviewClass 'GREEN' 'complete strong change'
Assert-Equal $changedGreen.ProductionAction 'NONE' 'green still shadow'
~~~

- [ ] **Step 3: Run RED**

~~~powershell
pwsh -NoProfile -File .\tools\data\test-compare-benefit-claims.ps1
pwsh -NoProfile -File .\tools\data\test-evaluate-benefit-state.ps1
~~~

Expected: FAIL.

- [ ] **Step 4: Implement conservative comparison**

Deterministic rules:
- normalized exact equality -> CONFIRMED,
- same explicit percentage/amount with only approved boilerplate difference -> CONFIRMED,
- explicit percentage/amount/date/availability restriction difference -> CHANGED,
- ambiguous semantic difference -> UNKNOWN,
- contradictory validated evidence for same claim -> CONFLICT.

No LLM call is allowed in this layer.

- [ ] **Step 5: Implement evaluation priority**

~~~text
1. unresolved source or identity conflict -> NEEDS_VERIFICATION + RED
2. validated explicit end/discontinuation + strong binding + no conflict -> ENDED + GREEN
3. current strong evidence + material change -> CHANGED; GREEN if detail coverage complete, otherwise YELLOW
4. current strong evidence + no material change -> ACTIVE; GREEN only when BenefitDescription, EligibleTarget, UsageCondition, VerificationMethod are CONFIRMED or explicitly NOT_APPLICABLE, otherwise YELLOW
5. everything else -> NEEDS_VERIFICATION + YELLOW
~~~

Unknown ValidFrom/ValidUntil alone does not downgrade an otherwise complete ACTIVE result.

- [ ] **Step 6: Run GREEN**

~~~powershell
pwsh -NoProfile -File .\tools\data\test-compare-benefit-claims.ps1
pwsh -NoProfile -File .\tools\data\test-evaluate-benefit-state.ps1
~~~

Expected: PASS.

- [ ] **Step 7: Commit**

~~~bash
git add tools/data/lib/benefit-verification/compare-benefit-claims.ps1 tools/data/lib/benefit-verification/evaluate-benefit-state.ps1 tools/data/test-compare-benefit-claims.ps1 tools/data/test-evaluate-benefit-state.ps1
git commit -m "feat: evaluate benefit state deterministically"
~~~

---

### Task 6: Integrate Phase 2 Shadow Mode

**Files:**
- Create: tools/data/invoke-phase2-benefit-shadow-mode.ps1
- Create: tools/data/test-phase2-benefit-shadow-mode.ps1

**Interfaces:**
- Invoke-Phase2BenefitShadowMode -Rows -RequestInvoker -DiscoveryInvoker -UnstructuredExtractor -SpreadsheetExtractor -PdfTextExtractor -SourceRowNumberOffset -GoldenExpectations -OperationalLiveRun
- Get-Phase2BenefitShadowSummary -Rows -GoldenExpectations -OperationalLiveRun
- Export-Phase2BenefitShadowMode -Run -RowReportCsv -SummaryJson -EvidenceDiagnosticJson

- [ ] **Step 1: Write failing end-to-end tests**

Use a synthetic .go.kr HTML-table source and test:
- source row number survives all stages,
- ProductionAction=NONE,
- evidence diagnostics preserve URL/text/status,
- 404/timeout -> NEEDS_VERIFICATION, never ENDED,
- unsupported PDF without adapter -> NEEDS_VERIFICATION,
- binding conflict -> NEEDS_VERIFICATION + RED,
- explicit end -> ENDED,
- active with missing detail -> ACTIVE + YELLOW,
- official-source conflict -> NEEDS_VERIFICATION + RED,
- fallback DiscoveryInvoker is called only when existing-source evidence is insufficient,
- no DiscoveryInvoker -> explicit DISCOVERY_PROVIDER_NOT_CONFIGURED,
- protected export paths under data/canonical, data/seed, apps are rejected.

Minimal runner assertion:

~~~powershell
$run = Invoke-Phase2BenefitShadowMode -Rows @($row) -RequestInvoker $request
Assert-Equal $run.Rows.Count 1 'one input row'
Assert-Equal $run.Rows[0].SourceRowNumber 2 'source row preserved'
Assert-Equal $run.Rows[0].ProductionAction 'NONE' 'no production action'
Assert-True (@($run.EvidenceDiagnostics).Count -eq 1) 'evidence trace retained'
~~~

- [ ] **Step 2: Run RED**

~~~powershell
pwsh -NoProfile -File .\tools\data\test-phase2-benefit-shadow-mode.ps1
~~~

Expected: FAIL.

- [ ] **Step 3: Implement orchestration**

Exact stage order per row:

~~~text
canonical row
-> ConvertTo-NormalizedBusiness
-> CanonicalBenefitRecord
-> existing source candidate
-> fetch
-> qualify
-> bind
-> extract
-> validate
-> claim compare
-> preliminary evaluation
-> if insufficient and DiscoveryInvoker exists: discover fallback sources and run the same stages
-> resolve composite/conflicting evidence
-> final deterministic evaluation
-> review row + evidence diagnostics
~~~

- [ ] **Step 4: Implement summary metrics**

Include:
- EvaluatedRows
- DiscoveryComplete/Partial/Failed
- QualifiedOfficialSourceRows
- BindingStrong/Plausible/Ambiguous/Conflict
- ExtractionComplete/Partial/Failed
- EvidenceValidationRejected
- Active/Changed/Ended/NeedsVerification
- Green/Yellow/Red
- FalseGreenCount on labeled fixtures
- FastReviewCandidates
- DeepManualReviewRequired
- AllRowsRequireFinalHumanApproval=true
- ExistingSourceReuseCount
- DiscoveryFallbackCount
- TotalExternalRequests
- AverageExternalRequests
- OperationalLiveShadowRun

Do not turn a small sample into a population precision claim.

- [ ] **Step 5: Implement protected export**

Reuse the Phase 1 protected-path approach under Phase 2 function names. Review CSV, summary JSON, and evidence JSON may not be exported into:
- data/canonical
- data/seed
- apps

- [ ] **Step 6: Run all Phase 2 tests**

~~~powershell
pwsh -NoProfile -File .\tools\data\test-benefit-verification-contracts.ps1
pwsh -NoProfile -File .\tools\data\test-discover-official-benefit-sources.ps1
pwsh -NoProfile -File .\tools\data\test-qualify-official-benefit-source.ps1
pwsh -NoProfile -File .\tools\data\test-bind-benefit-source.ps1
pwsh -NoProfile -File .\tools\data\test-extract-benefit-evidence.ps1
pwsh -NoProfile -File .\tools\data\test-validate-benefit-evidence.ps1
pwsh -NoProfile -File .\tools\data\test-compare-benefit-claims.ps1
pwsh -NoProfile -File .\tools\data\test-evaluate-benefit-state.ps1
pwsh -NoProfile -File .\tools\data\test-phase2-benefit-shadow-mode.ps1
~~~

Expected: all PASS.

- [ ] **Step 7: Run Phase 1 regressions**

~~~powershell
pwsh -NoProfile -File .\tools\data\test-normalize-business.ps1
pwsh -NoProfile -File .\tools\data\test-discover-poi-candidates.ps1
pwsh -NoProfile -File .\tools\data\test-evaluate-poi-match.ps1
pwsh -NoProfile -File .\tools\data\test-phase1-poi-shadow-mode.ps1
~~~

Expected: all PASS.

- [ ] **Step 8: Commit**

~~~bash
git add tools/data/invoke-phase2-benefit-shadow-mode.ps1 tools/data/test-phase2-benefit-shadow-mode.ps1
git commit -m "feat: integrate phase 2 benefit shadow mode"
~~~

---

### Task 7: Golden Safety, Existing-Source Smoke, and Documentation

**Files:**
- Create: tools/data/testdata/phase2-benefit-golden.psd1
- Modify: tools/data/test-phase2-benefit-shadow-mode.ps1
- Modify: tools/data/README.md
- Modify: docs/current-work.md
- Modify: docs/current-status.md

**Interfaces:**
Produces source-cited regression fixtures, deterministic safety metrics, and a documented live existing-source smoke.

- [ ] **Step 1: Add Golden fixture provenance**

Use real repository facts only as historical/source-cited references. Use synthetic fixtures only for algorithm paths.

~~~powershell
@{
    'positive-paju-composite' = @{
        FixtureKind = 'REAL_SOURCE_CITED'
        SourcePaths = @('data/canonical/reports/official-benefit-release-candidates-20260908.csv')
        ExpectedHistoricalLabel = 'OFFICIAL_RELEASE_CANDIDATE'
        SourceNote = 'Historical release evidence only; current state must be re-observed.'
    }
    'synthetic-explicit-end' = @{
        FixtureKind = 'SYNTHETIC_ALGORITHM_ONLY'
        ExpectedBenefitState = 'ENDED'
        ExpectedReviewClass = 'GREEN'
    }
    'synthetic-source-conflict' = @{
        FixtureKind = 'SYNTHETIC_ALGORITHM_ONLY'
        ExpectedBenefitState = 'NEEDS_VERIFICATION'
        ExpectedReviewClass = 'RED'
    }
}
~~~

- [ ] **Step 2: Add Golden regression tests**

Assert:
- ambiguous/conflict fixtures never silently become GREEN,
- synthetic explicit-end follows ENDED rule,
- historical release references do not automatically become current ACTIVE truth.

- [ ] **Step 3: Run all deterministic data-tool tests**

~~~powershell
Get-ChildItem .\tools\data\test-*.ps1 | Sort-Object Name | ForEach-Object { & pwsh -NoProfile -File $_.FullName; if ($LASTEXITCODE -ne 0) { throw "FAILED: $($_.Name)" } }
~~~

Expected: all PASS.

- [ ] **Step 4: Run a small live existing-source smoke**

Allowed in this foundation:
- fetch already-canonical official URLs,
- no general web search,
- no newly installed parser/LLM.

Use a small source-stratified sample from current official/municipality URLs and report:
- attempted rows,
- fetch status,
- officiality,
- binding,
- extraction status,
- BenefitState,
- ReviewClass,
- external request count,
- ProductionAction=NONE.

Unsupported free-text/PDF/XLSX paths must fail closed with exact missing-adapter reasons.

- [ ] **Step 5: Prove non-write invariant**

~~~bash
git diff -- data/canonical data/seed apps
~~~

Expected: no diff.

- [ ] **Step 6: Update documentation**

tools/data/README.md:
- Phase 2 Shadow Mode flow,
- existing-source-first behavior,
- injectable discovery/extractor boundaries,
- failure semantics,
- output artifacts,
- protected paths,
- deterministic test command,
- live existing-source smoke procedure.

docs/current-work.md and docs/current-status.md:
- implementation state,
- branch/PR once known,
- tests run,
- provider/dependency approvals still pending,
- no claim that Phase 2 is complete.

- [ ] **Step 7: Final verification**

~~~powershell
Get-ChildItem .\tools\data\test-*.ps1 | Sort-Object Name | ForEach-Object { & pwsh -NoProfile -File $_.FullName; if ($LASTEXITCODE -ne 0) { throw "FAILED: $($_.Name)" } }
~~~

~~~bash
git diff -- data/canonical data/seed apps
git status --short
~~~

Expected:
- all tests PASS,
- protected production paths unchanged,
- only planned code/test/docs files changed.

- [ ] **Step 8: Commit**

~~~bash
git add tools/data/testdata/phase2-benefit-golden.psd1 tools/data/test-phase2-benefit-shadow-mode.ps1 tools/data/README.md docs/current-work.md docs/current-status.md
git commit -m "docs: validate phase 2 benefit core foundation"
~~~

---

## PR Sequence

Do not create Issues/PRs until the implementation plan and execution method are approved.

1. Contract Foundation — Task 1.
2. Official Source Boundary — Tasks 2-3.
3. Evidence Extraction / Validation — Task 4.
4. Claim Verification / Evaluation — Task 5.
5. Integration / Shadow Foundation Validation — Tasks 6-7.

Do not let parallel branches redefine the shared contract independently.

## Explicit Provider / Dependency Gate

The Core Foundation can be implemented without changing the approved dependency/API surface. It cannot honestly finish the full Phase 2 representative validation on the 247 held rows by itself.

After the foundation smoke, stop and obtain explicit approval before adding any of:
- general official-source web-search API/provider,
- LLM provider/model/SDK,
- PDF text-extraction dependency,
- XLSX parsing dependency.

The follow-up adapter plan must identify provider/authentication/secret path, request limits/cost, terms/licensing, failure semantics, and tests. It must reuse this Core.

## Completion Criteria for This Plan

This provider-neutral foundation is complete when:
- contracts are frozen and tested,
- existing-source fetch/qualification/binding works fail-closed,
- deterministic structured extraction and Evidence Validation work,
- unsupported free-text/PDF/XLSX paths fail closed through injectable boundaries,
- claim comparison/state evaluation are deterministic,
- Shadow runner emits auditable evidence and ProductionAction=NONE,
- known ambiguity/conflict fixtures have zero silent false-GREEN outcomes,
- Phase 1 regressions pass,
- canonical/seed/apps remain unchanged,
- a small existing-official-source live smoke is documented,
- missing provider/adapter capabilities are reported rather than guessed.

Do not mark roadmap Phase 2 COMPLETE. Full completion requires separately approved adapter work, representative held-workload + positive-control validation, and human GREEN audit from the design spec.

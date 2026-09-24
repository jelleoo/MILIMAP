$ErrorActionPreference = 'Stop'

$runnerPath = Join-Path $PSScriptRoot 'invoke-phase2-benefit-shadow-mode.ps1'
if (-not (Test-Path -LiteralPath $runnerPath)) { throw 'Phase 2 shadow runner is not implemented' }
. $runnerPath

function Assert-Equal {
    param([AllowNull()]$Actual, [AllowNull()]$Expected, [Parameter(Mandatory)][string]$Message)
    if ($Actual -cne $Expected) { throw "$Message (expected: $Expected, actual: $Actual)" }
}
function Assert-True {
    param([bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw $Message }
}
function Assert-Throws {
    param([Parameter(Mandatory)][scriptblock]$Action, [Parameter(Mandatory)][string]$Message)
    $threw = $false
    try { & $Action } catch { $threw = $true }
    if (-not $threw) { throw $Message }
}

function New-Phase2TestRow {
    param(
        [string]$SourceUrl='https://city.example.go.kr/benefit',
        [string]$SourceType='지자체 공식 자료',
        [string]$BenefitDescription='10% 할인'
    )
    [pscustomobject]@{
        업소명='테스트 식당'
        시도='서울특별시'
        시군구='마포구'
        소재지도로명주소='서울특별시 마포구 테스트로 12'
        소재지지번주소=''
        할인정보=$BenefitDescription
        적용대상='현역 장병'
        이용조건='상시'
        인증방법='군인 신분증 확인'
        업소전화번호='02-1234-5678'
        출처유형=$SourceType
        출처URL=$SourceUrl
        최근확인일='2026-09-24'
    }
}

function New-Phase2TestResponse {
    param([Parameter(Mandatory)][string]$Url)
    $text = @"
사업장명: 테스트 식당
주소: 서울특별시 마포구 테스트로 12
전화번호: 02-1234-5678
혜택 제공
현재 적용
10% 할인
20% 할인
30% 할인
현역 장병
상시
군인 신분증 확인
혜택 종료
"@
    [pscustomobject]@{ StatusCode=200; ContentType='text/html; charset=utf-8'; Text=$text; Bytes=$null }
}

function New-Phase2TestClaims {
    param($Text, $Document, $Source)
    $description = if ($Document.Url -like '*conflict-a*') { '20% 할인' } elseif ($Document.Url -like '*conflict-b*') { '30% 할인' } else { '10% 할인' }
    $currentValue = if ($Document.Url -like '*ended*') { '혜택 종료' } else { '현재 적용' }
    @(
        [pscustomobject]@{ ClaimType='BENEFIT_EXISTENCE'; Value='혜택 제공'; EvidenceText='혜택 제공'; EvidenceReference='fixture:existence' },
        [pscustomobject]@{ ClaimType='CURRENT_APPLICABILITY'; Value=$currentValue; EvidenceText=$currentValue; EvidenceReference='fixture:current' },
        [pscustomobject]@{ ClaimType='BENEFIT_DESCRIPTION'; Value=$description; EvidenceText=$description; EvidenceReference='fixture:description' },
        [pscustomobject]@{ ClaimType='ELIGIBLE_TARGET'; Value='현역 장병'; EvidenceText='현역 장병'; EvidenceReference='fixture:target' },
        [pscustomobject]@{ ClaimType='USAGE_CONDITION'; Value='상시'; EvidenceText='상시'; EvidenceReference='fixture:usage' },
        [pscustomobject]@{ ClaimType='VERIFICATION_METHOD'; Value='군인 신분증 확인'; EvidenceText='군인 신분증 확인'; EvidenceReference='fixture:method' }
    )
}
$extractor = (Get-Command New-Phase2TestClaims).ScriptBlock

$script:requestCount = 0
$script:discoveryCount = 0
$activeRun = Invoke-Phase2BenefitShadowMode -Rows @(New-Phase2TestRow) -SourceRowNumberOffset 1 -RequestInvoker {
    param($Uri)
    $script:requestCount++
    New-Phase2TestResponse -Url $Uri.AbsoluteUri
} -DiscoveryInvoker {
    param($Benefit, $Business)
    $script:discoveryCount++
    throw 'Discovery must not run when existing evidence is sufficient'
} -UnstructuredExtractor $extractor

Assert-Equal $activeRun.Rows.Count 1 'One input row must produce one review row'
Assert-Equal $activeRun.Rows[0].SourceRowNumber 2 'SourceRowNumber must survive the full pipeline'
Assert-Equal $activeRun.Rows[0].BenefitState 'ACTIVE' 'Strong current evidence must become ACTIVE'
Assert-Equal $activeRun.Rows[0].ReviewClass 'GREEN' 'Complete strong evidence may be GREEN'
Assert-Equal $activeRun.Rows[0].ProductionAction 'NONE' 'Shadow mode must never write production'
Assert-True ($null -ne $activeRun.Results[0].BusinessIdentity) 'Final BenefitVerificationResult must carry BusinessIdentity'
Assert-BenefitVerificationResult $activeRun.Results[0]
Assert-Equal $script:discoveryCount 0 'Existing-source success must stop fallback discovery'
Assert-Equal $activeRun.Summary.ExistingSourceReuseCount 1 'Existing source reuse must be counted'
Assert-Equal $activeRun.Summary.DiscoveryFallbackCount 0 'Unused fallback must be counted as zero'
Assert-True (@($activeRun.EvidenceDiagnostics).Count -ge 1) 'Evidence diagnostics must remain auditable'

$script:discoveryCount = 0
$fallbackRun = Invoke-Phase2BenefitShadowMode -Rows @(New-Phase2TestRow -SourceUrl '' -SourceType '') -SourceRowNumberOffset 1 -RequestInvoker {
    param($Uri)
    New-Phase2TestResponse -Url $Uri.AbsoluteUri
} -DiscoveryInvoker {
    param($Benefit, $Business)
    $script:discoveryCount++
    [pscustomobject]@{ Url='https://city.example.go.kr/discovered'; SourceKind='PUBLIC_OFFICIAL'; SourceLabel='지자체 공식 자료' }
} -UnstructuredExtractor $extractor

Assert-Equal $script:discoveryCount 1 'Fallback discovery must run exactly once per insufficient row'
Assert-Equal $fallbackRun.Rows[0].BenefitState 'ACTIVE' 'Discovered strong current evidence may become ACTIVE'
Assert-Equal $fallbackRun.Summary.DiscoveryFallbackCount 1 'Fallback usage must be counted'

# A failed stale existing source must not poison a successful replacement official source.
$recoveredRun = Invoke-Phase2BenefitShadowMode -Rows @(New-Phase2TestRow -SourceUrl 'https://city.example.go.kr/stale') -SourceRowNumberOffset 1 -RequestInvoker {
    param($Uri)
    if ($Uri.AbsoluteUri -like '*stale*') { throw 'stale source unavailable' }
    New-Phase2TestResponse -Url $Uri.AbsoluteUri
} -DiscoveryInvoker {
    param($Benefit, $Business)
    [pscustomobject]@{ Url='https://city.example.go.kr/replacement'; SourceKind='PUBLIC_OFFICIAL'; SourceLabel='지자체 공식 자료' }
} -UnstructuredExtractor $extractor
Assert-Equal $recoveredRun.Rows[0].BenefitState 'ACTIVE' 'Successful replacement official evidence must recover from stale existing-source fetch failure'
Assert-Equal $recoveredRun.Rows[0].ReviewClass 'GREEN' 'Complete replacement official evidence may be GREEN'
Assert-Equal $recoveredRun.Summary.DiscoveryFallbackCount 1 'Replacement recovery must record fallback usage'

$noProviderRun = Invoke-Phase2BenefitShadowMode -Rows @(New-Phase2TestRow -SourceUrl '' -SourceType '') -SourceRowNumberOffset 1 -RequestInvoker {
    param($Uri)
    throw 'No fetch is expected without a candidate'
} -UnstructuredExtractor $extractor
Assert-Equal $noProviderRun.Rows[0].BenefitState 'NEEDS_VERIFICATION' 'Missing provider must remain unresolved'
Assert-True ($noProviderRun.Rows[0].ReasonCodes -contains 'DISCOVERY_PROVIDER_NOT_CONFIGURED') 'Missing discovery provider reason must be preserved'
Assert-True ($noProviderRun.Rows[0].BenefitState -ne 'ENDED') 'Missing provider must never imply ENDED'

$fetchFailure = Invoke-Phase2BenefitShadowMode -Rows @(New-Phase2TestRow) -SourceRowNumberOffset 1 -RequestInvoker {
    param($Uri)
    throw 'timeout'
} -UnstructuredExtractor $extractor
Assert-Equal $fetchFailure.Rows[0].BenefitState 'NEEDS_VERIFICATION' 'Fetch failure must remain unresolved'
Assert-True ($fetchFailure.Rows[0].BenefitState -ne 'ENDED') 'Fetch failure must never imply ENDED'

# Official PDF without an approved text adapter must fail closed.
$pdfRun = Invoke-Phase2BenefitShadowMode -Rows @(New-Phase2TestRow -SourceUrl 'https://city.example.go.kr/benefit.pdf') -SourceRowNumberOffset 1 -RequestInvoker {
    param($Uri)
    [pscustomobject]@{ StatusCode=200; ContentType='application/pdf'; Text=''; Bytes=([byte[]](1,2,3)) }
} -UnstructuredExtractor $extractor
Assert-Equal $pdfRun.Rows[0].BenefitState 'NEEDS_VERIFICATION' 'PDF without text adapter must remain unresolved'
Assert-True ($pdfRun.Rows[0].ReasonCodes -contains 'EXTRACTION_PROVIDER_NOT_CONFIGURED') 'Missing PDF adapter reason must be preserved'
Assert-True ($pdfRun.Rows[0].BenefitState -ne 'ENDED') 'Unsupported extraction path must never imply ENDED'

# Confirmed lifecycle with incomplete detail remains ACTIVE but requires human review.
$incompleteExtractor = {
    param($Text, $Document, $Source)
    @(
        [pscustomobject]@{ ClaimType='BENEFIT_EXISTENCE'; Value='혜택 제공'; EvidenceText='혜택 제공'; EvidenceReference='fixture:existence' },
        [pscustomobject]@{ ClaimType='CURRENT_APPLICABILITY'; Value='현재 적용'; EvidenceText='현재 적용'; EvidenceReference='fixture:current' },
        [pscustomobject]@{ ClaimType='BENEFIT_DESCRIPTION'; Value='10% 할인'; EvidenceText='10% 할인'; EvidenceReference='fixture:description' },
        [pscustomobject]@{ ClaimType='ELIGIBLE_TARGET'; Value='현역 장병'; EvidenceText='현역 장병'; EvidenceReference='fixture:target' }
    )
}
$incompleteRun = Invoke-Phase2BenefitShadowMode -Rows @(New-Phase2TestRow) -SourceRowNumberOffset 1 -RequestInvoker {
    param($Uri)
    New-Phase2TestResponse -Url $Uri.AbsoluteUri
} -UnstructuredExtractor $incompleteExtractor
Assert-Equal $incompleteRun.Rows[0].BenefitState 'ACTIVE' 'Confirmed lifecycle with missing detail may remain ACTIVE'
Assert-Equal $incompleteRun.Rows[0].ReviewClass 'YELLOW' 'Incomplete detail must require YELLOW review'
Assert-True ($incompleteRun.Rows[0].ReasonCodes -contains 'DETAIL_INCOMPLETE') 'Incomplete detail reason must survive orchestration'

$bindingConflict = Invoke-Phase2BenefitShadowMode -Rows @(New-Phase2TestRow) -SourceRowNumberOffset 1 -RequestInvoker {
    param($Uri)
    $response = New-Phase2TestResponse -Url $Uri.AbsoluteUri
    $response.Text = $response.Text -replace '서울특별시 마포구 테스트로 12', '서울특별시 마포구 테스트로 99'
    $response
} -UnstructuredExtractor $extractor
Assert-Equal $bindingConflict.Rows[0].BenefitState 'NEEDS_VERIFICATION' 'Binding conflict must fail closed'
Assert-Equal $bindingConflict.Rows[0].ReviewClass 'RED' 'Binding conflict must require RED review'
Assert-True ($bindingConflict.Rows[0].ReasonCodes -contains 'BUSINESS_BINDING_CONFLICT') 'Binding conflict reason must survive orchestration'

$endedRun = Invoke-Phase2BenefitShadowMode -Rows @(New-Phase2TestRow -SourceUrl 'https://city.example.go.kr/ended') -SourceRowNumberOffset 1 -RequestInvoker {
    param($Uri)
    New-Phase2TestResponse -Url $Uri.AbsoluteUri
} -UnstructuredExtractor $extractor
Assert-Equal $endedRun.Rows[0].BenefitState 'ENDED' 'Explicit validated ending must become ENDED'
Assert-Equal $endedRun.Rows[0].ReviewClass 'GREEN' 'Strong explicit ending may be GREEN fast review'
Assert-True ($endedRun.Rows[0].ReasonCodes -contains 'EXPLICIT_DISCONTINUATION') 'Ending reason must be preserved'
Assert-Equal $endedRun.Rows[0].ProductionAction 'NONE' 'ENDED remains shadow-only'

$conflictRun = Invoke-Phase2BenefitShadowMode -Rows @(New-Phase2TestRow -SourceUrl '' -SourceType '') -SourceRowNumberOffset 1 -RequestInvoker {
    param($Uri)
    New-Phase2TestResponse -Url $Uri.AbsoluteUri
} -DiscoveryInvoker {
    param($Benefit, $Business)
    @(
        [pscustomobject]@{ Url='https://city.example.go.kr/conflict-a'; SourceKind='PUBLIC_OFFICIAL'; SourceLabel='지자체 공식 자료' },
        [pscustomobject]@{ Url='https://city.example.go.kr/conflict-b'; SourceKind='PUBLIC_OFFICIAL'; SourceLabel='지자체 공식 자료' }
    )
} -UnstructuredExtractor $extractor
Assert-Equal $conflictRun.Rows[0].BenefitState 'NEEDS_VERIFICATION' 'Material multi-source conflict must remain unresolved'
Assert-Equal $conflictRun.Rows[0].ReviewClass 'RED' 'Material source conflict must be RED'
Assert-True ($conflictRun.Rows[0].ReasonCodes -contains 'SOURCE_CONFLICT') 'Multi-source conflict reason must survive orchestration'

$script:requestCount = 0
$dedupeRun = Invoke-Phase2BenefitShadowMode -Rows @(New-Phase2TestRow -SourceUrl '' -SourceType '') -SourceRowNumberOffset 1 -RequestInvoker {
    param($Uri)
    $script:requestCount++
    New-Phase2TestResponse -Url $Uri.AbsoluteUri
} -DiscoveryInvoker {
    param($Benefit, $Business)
    @(
        [pscustomobject]@{ Url='https://city.example.go.kr/dedupe'; SourceKind='PUBLIC_OFFICIAL'; SourceLabel='지자체 공식 자료' },
        [pscustomobject]@{ Url='https://city.example.go.kr/dedupe'; SourceKind='PUBLIC_OFFICIAL'; SourceLabel='지자체 공식 자료' }
    )
} -UnstructuredExtractor $extractor
Assert-Equal $script:requestCount 1 'Duplicate source URLs must be fetched once'

# A mixed complete/failed source set must be operationally PARTIAL and fail closed.
$mixedRun = Invoke-Phase2BenefitShadowMode -Rows @(New-Phase2TestRow -SourceUrl '' -SourceType '') -SourceRowNumberOffset 1 -RequestInvoker {
    param($Uri)
    if ($Uri.AbsoluteUri -like '*mixed-failed*') { throw 'timeout' }
    New-Phase2TestResponse -Url $Uri.AbsoluteUri
} -DiscoveryInvoker {
    param($Benefit, $Business)
    @(
        [pscustomobject]@{ Url='https://city.example.go.kr/mixed-complete'; SourceKind='PUBLIC_OFFICIAL'; SourceLabel='지자체 공식 자료' },
        [pscustomobject]@{ Url='https://city.example.go.kr/mixed-failed'; SourceKind='PUBLIC_OFFICIAL'; SourceLabel='지자체 공식 자료' }
    )
} -UnstructuredExtractor $extractor
Assert-Equal $mixedRun.Rows[0].BenefitState 'NEEDS_VERIFICATION' 'Mixed complete/failed extraction must fail closed as PARTIAL'
Assert-Equal $mixedRun.Summary.ExtractionComplete 1 'Mixed source run must count the complete source'
Assert-Equal $mixedRun.Summary.ExtractionFailed 1 'Mixed source run must count the failed source'

# HTTP 404 must remain operational failure, never semantic ending.
$notFoundRun = Invoke-Phase2BenefitShadowMode -Rows @(New-Phase2TestRow) -SourceRowNumberOffset 1 -RequestInvoker {
    param($Uri)
    [pscustomobject]@{ StatusCode=404; ContentType='text/html'; Text='not found'; Bytes=$null }
} -UnstructuredExtractor $extractor
Assert-Equal $notFoundRun.Rows[0].BenefitState 'NEEDS_VERIFICATION' 'HTTP 404 must remain unresolved'
Assert-True ($notFoundRun.Rows[0].BenefitState -ne 'ENDED') 'HTTP 404 must never imply ENDED'

# PDF without an injected text adapter must fail closed.
$pdfRun = Invoke-Phase2BenefitShadowMode -Rows @(New-Phase2TestRow -SourceUrl 'https://city.example.go.kr/benefit.pdf') -SourceRowNumberOffset 1 -RequestInvoker {
    param($Uri)
    [pscustomobject]@{ StatusCode=200; ContentType='application/pdf'; Text=''; Bytes=[byte[]](1,2,3) }
} -UnstructuredExtractor $extractor
Assert-Equal $pdfRun.Rows[0].BenefitState 'NEEDS_VERIFICATION' 'PDF without adapter must remain unresolved'
Assert-True ($pdfRun.Rows[0].ReasonCodes -contains 'EXTRACTION_PROVIDER_NOT_CONFIGURED') 'Missing PDF adapter reason must be preserved'

# Diagnostics must retain source provenance and validated evidence detail.
$activeDiagnostic = @($activeRun.EvidenceDiagnostics)[0]
Assert-Equal $activeDiagnostic.Url 'https://city.example.go.kr/benefit' 'Diagnostic must preserve source URL'
Assert-Equal $activeDiagnostic.FetchStatus 'COMPLETE' 'Diagnostic must preserve fetch status'
Assert-Equal $activeDiagnostic.BusinessBindingStatus 'STRONG' 'Diagnostic must preserve binding status'
Assert-True (@($activeDiagnostic.ValidatedClaims | Where-Object { $_.EvidenceText -eq '10% 할인' -and $_.ValidationStatus -eq 'VALIDATED' }).Count -gt 0) 'Diagnostic must preserve validated evidence text and status'
Assert-Equal $dedupeRun.Rows[0].BenefitState 'ACTIVE' 'Deduplicated evidence must still evaluate normally'

Assert-Equal ($activeRun.Summary.Green + $activeRun.Summary.Yellow + $activeRun.Summary.Red) $activeRun.Summary.EvaluatedRows 'Review-class metrics must reconcile'
Assert-Equal ($activeRun.Summary.Active + $activeRun.Summary.Changed + $activeRun.Summary.Ended + $activeRun.Summary.NeedsVerification) $activeRun.Summary.EvaluatedRows 'Benefit-state metrics must reconcile'
Assert-True $activeRun.Summary.AllRowsRequireFinalHumanApproval 'All shadow rows require final human approval'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
Assert-Throws {
    Export-Phase2BenefitShadowMode -Run $activeRun -RowReportCsv (Join-Path $repoRoot 'data/canonical/task6.csv') -SummaryJson (Join-Path $env:TEMP 'task6-summary.json') -EvidenceDiagnosticJson (Join-Path $env:TEMP 'task6-evidence.json')
} 'Canonical export path must be protected'
Assert-Throws {
    Export-Phase2BenefitShadowMode -Run $activeRun -RowReportCsv (Join-Path $env:TEMP 'task6.csv') -SummaryJson (Join-Path $repoRoot 'data/seed/task6.json') -EvidenceDiagnosticJson (Join-Path $env:TEMP 'task6-evidence.json')
} 'Seed export path must be protected'
Assert-Throws {
    Export-Phase2BenefitShadowMode -Run $activeRun -RowReportCsv (Join-Path $env:TEMP 'task6.csv') -SummaryJson (Join-Path $env:TEMP 'task6-summary.json') -EvidenceDiagnosticJson (Join-Path $repoRoot 'apps/task6.json')
} 'App export path must be protected'

Write-Host 'Phase 2 benefit shadow mode tests passed.'

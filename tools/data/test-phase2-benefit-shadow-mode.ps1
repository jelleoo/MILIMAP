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

$goldenPath = Join-Path $PSScriptRoot 'testdata/phase2-benefit-golden.psd1'
Assert-True (Test-Path -LiteralPath $goldenPath) 'Phase 2 Golden fixture must exist'
$phase2Golden = Import-PowerShellDataFile -LiteralPath $goldenPath
Assert-True ($phase2Golden.ContainsKey('positive-paju-composite')) 'Golden fixture must include the real-source-cited Paju reference'
Assert-True ($phase2Golden.ContainsKey('synthetic-explicit-end')) 'Golden fixture must include the explicit-ending algorithm case'
Assert-True ($phase2Golden.ContainsKey('synthetic-source-conflict')) 'Golden fixture must include the source-conflict algorithm case'
Assert-True ($phase2Golden.ContainsKey('synthetic-binding-conflict')) 'Golden fixture must include the binding-conflict algorithm case'

$historicalGolden = $phase2Golden['positive-paju-composite']
Assert-Equal $historicalGolden.FixtureKind 'REAL_SOURCE_CITED' 'Historical Golden reference must be distinguished from algorithm fixtures'
Assert-Equal $historicalGolden.Status 'HISTORICAL_REFERENCE_ONLY' 'Historical Golden reference must not claim current truth'
Assert-True (-not $historicalGolden.ContainsKey('ExpectedBenefitState')) 'Historical evidence must not encode a current BenefitState expectation'

$syntheticEndGolden = $phase2Golden['synthetic-explicit-end']
Assert-Equal $syntheticEndGolden.FixtureKind 'SYNTHETIC_ALGORITHM_ONLY' 'Explicit-ending Golden case must be synthetic'
Assert-Equal $syntheticEndGolden.ExpectedBenefitState 'ENDED' 'Explicit-ending Golden state must be ENDED'
Assert-Equal $syntheticEndGolden.ExpectedReviewClass 'GREEN' 'Explicit-ending Golden review class must be GREEN'

$syntheticConflictGolden = $phase2Golden['synthetic-source-conflict']
Assert-Equal $syntheticConflictGolden.ExpectedBenefitState 'NEEDS_VERIFICATION' 'Source-conflict Golden state must remain unresolved'
Assert-Equal $syntheticConflictGolden.ExpectedReviewClass 'RED' 'Source-conflict Golden review class must be RED'

$syntheticBindingGolden = $phase2Golden['synthetic-binding-conflict']
Assert-Equal $syntheticBindingGolden.ExpectedBenefitState 'NEEDS_VERIFICATION' 'Binding-conflict Golden state must remain unresolved'
Assert-Equal $syntheticBindingGolden.ExpectedReviewClass 'RED' 'Binding-conflict Golden review class must be RED'

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

# The approved Task 6 summary interface must work from review rows alone.
$directSummary = Get-Phase2BenefitShadowSummary -Rows $activeRun.Rows
Assert-Equal $directSummary.EvaluatedRows $activeRun.Summary.EvaluatedRows 'Direct summary interface must preserve evaluated row count'
Assert-Equal $directSummary.ExistingSourceReuseCount $activeRun.Summary.ExistingSourceReuseCount 'Direct summary interface must preserve existing-source reuse'
Assert-Equal $directSummary.TotalExternalRequests $activeRun.Summary.TotalExternalRequests 'Direct summary interface must preserve external request count'

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

# Historical official-release evidence is provenance only. A current re-fetch failure must remain unresolved.
$historicalReferenceRun = Invoke-Phase2BenefitShadowMode -Rows @(New-Phase2TestRow -SourceUrl $historicalGolden.SourceUrl -SourceType '지자체 공식 자료') -SourceRowNumberOffset 1 -RequestInvoker {
    param($Uri)
    throw 'historical source must be re-observed'
} -UnstructuredExtractor $extractor
Assert-Equal $historicalReferenceRun.Rows[0].BenefitState 'NEEDS_VERIFICATION' 'Historical release evidence must not automatically become current ACTIVE truth'
Assert-True ($historicalReferenceRun.Rows[0].ReviewClass -ne 'GREEN') 'Unrevalidated historical evidence must not silently become GREEN'

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
Assert-Equal $bindingConflict.Rows[0].BenefitState $syntheticBindingGolden.ExpectedBenefitState 'Golden binding-conflict state must match integration behavior'
Assert-Equal $bindingConflict.Rows[0].ReviewClass $syntheticBindingGolden.ExpectedReviewClass 'Golden binding-conflict review class must match integration behavior'
Assert-True ($bindingConflict.Rows[0].ReasonCodes -contains 'BUSINESS_BINDING_CONFLICT') 'Binding conflict reason must survive orchestration'

$endedRun = Invoke-Phase2BenefitShadowMode -Rows @(New-Phase2TestRow -SourceUrl 'https://city.example.go.kr/ended') -SourceRowNumberOffset 1 -RequestInvoker {
    param($Uri)
    New-Phase2TestResponse -Url $Uri.AbsoluteUri
} -UnstructuredExtractor $extractor
Assert-Equal $endedRun.Rows[0].BenefitState 'ENDED' 'Explicit validated ending must become ENDED'
Assert-Equal $endedRun.Rows[0].ReviewClass 'GREEN' 'Strong explicit ending may be GREEN fast review'
Assert-Equal $endedRun.Rows[0].BenefitState $syntheticEndGolden.ExpectedBenefitState 'Golden explicit-ending state must match integration behavior'
Assert-Equal $endedRun.Rows[0].ReviewClass $syntheticEndGolden.ExpectedReviewClass 'Golden explicit-ending review class must match integration behavior'
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
Assert-Equal $conflictRun.Rows[0].BenefitState $syntheticConflictGolden.ExpectedBenefitState 'Golden source-conflict state must match integration behavior'
Assert-Equal $conflictRun.Rows[0].ReviewClass $syntheticConflictGolden.ExpectedReviewClass 'Golden source-conflict review class must match integration behavior'
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


# TEMPORARY TASK 7 OPERATIONAL SMOKE.
# This block is intentionally removed after one CI observation so the final deterministic suite has no network dependency.
$liveRequestInvoker = {
    param($Uri)
    $response = Invoke-WebRequest -Uri $Uri.AbsoluteUri -MaximumRedirection 5 -TimeoutSec 20 -ErrorAction Stop
    $contentType = [string]$response.Headers.'Content-Type'
    [pscustomobject]@{
        StatusCode = [int]$response.StatusCode
        ContentType = $contentType
        Text = [string]$response.Content
        Bytes = $null
    }
}

$liveSmokeSamples = @(
    [pscustomobject]@{
        SourceRowNumber=5; Label='MMA public data'; Row=[pscustomobject]@{
            업소명='투오프커피'; 시도='서울특별시'; 시군구='강남구'; 소재지도로명주소='서울특별시 강남구역삼로9길20(역삼동, (1층))'; 소재지지번주소=''
            할인정보='서비스 이용료의 20% 할인(모든 음료가 가능하나 병 음료는 제외)'; 적용대상='동원훈련 이수자, 모범예비군, 복무중인사람'; 이용조건='없음 | 혜택기간: 2024-04-17~2027-04-17'; 인증방법='동원훈련이수증, 모범예비군증, 복무확인서'; 업소전화번호='070-7704-6600'
            출처유형='공공데이터'; 출처URL='https://www.mma.go.kr/about/udgg/list.do?mc=mma0003357'; 최근확인일='2026-08-15'
        }
    },
    [pscustomobject]@{
        SourceRowNumber=75; Label='Paju municipal HTML'; Row=[pscustomobject]@{
            업소명='두둑한한판'; 시도='경기도'; 시군구='파주시'; 소재지도로명주소='파주시 광탄면 보광로 646'; 소재지지번주소=''
            할인정보='10%할인'; 적용대상='파주시 관내 주둔 군 장병 및 사회복무요원'; 이용조건='업소별 세부 조건 및 중복할인 여부는 방문 전 확인'; 인증방법='군인 또는 사회복무요원 신분 확인자료(방문 전 업소 확인 권장)'; 업소전화번호='031-949-7646'
            출처유형='지자체 공식 자료'; 출처URL='https://www.paju.go.kr/user/soldier/BD_discountStoreList.do?q_ctgCd=1001'; 최근확인일='2026-08-15'
        }
    },
    [pscustomobject]@{
        SourceRowNumber=118; Label='DDC municipal HTML'; Row=[pscustomobject]@{
            업소명='개성연출'; 시도='경기도'; 시군구='동두천시'; 소재지도로명주소='경기도 동두천시 정장로 31-12, 1층'; 소재지지번주소=''
            할인정보='커트 2,000원'; 적용대상='군 장병'; 이용조건='업소별 할인율·적용 품목·중복 할인 여부는 방문 전 문의'; 인증방법='군인 신분 확인자료(방문 전 문의)'; 업소전화번호='031-863-4570'
            출처유형='지자체 공식 자료'; 출처URL='https://www.ddc.go.kr/ddc/contents.do?key=1570'; 최근확인일='2026-09-08'
        }
    },
    [pscustomobject]@{
        SourceRowNumber=339; Label='Yangju municipal HTML'; Row=[pscustomobject]@{
            업소명='거시기닭갈비'; 시도='경기도'; 시군구='양주시'; 소재지도로명주소='경기도 양주시 엄상동길 22-25'; 소재지지번주소=''
            할인정보='군 장병 대상 상시 할인(할인율·적용 품목은 업소별 상이, 방문 전 문의)'; 적용대상='군 장병'; 이용조건='상시 참여업소 목록이며 세부 할인율은 업소별 문의'; 인증방법='군인 신분 확인자료(방문 전 문의)'; 업소전화번호='031-859-9982'
            출처유형='지자체 공식 자료'; 출처URL='https://www.yangju.go.kr/www/selectBbsNttView.do?bbsNo=13&key=202&nttNo=198019'; 최근확인일='2026-08-15'
        }
    },
    [pscustomobject]@{
        SourceRowNumber=280; Label='Suwon municipal PDF'; Row=[pscustomobject]@{
            업소명='고려이발관'; 시도='경기도'; 시군구='수원시'; 소재지도로명주소='경기도 수원시 팔달구 팔달로 135, 1층 (화서동)'; 소재지지번주소=''
            할인정보='입영 시 무료 이발, 입영 후 제대 시까지 이용요금 50% 할인'; 적용대상='군 입영예정자 및 복무 중인 장병 본인(수원시민)'; 이용조건='수원시민 본인 대상; 방문 전 영업 및 적용 여부 확인'; 인증방법='입영통지서 또는 휴가 확인 서류와 신분증'; 업소전화번호='031-255-7060'
            출처유형='지자체 공식 자료'; 출처URL='https://www.suwon.go.kr/webcontent/ckeditor/2026/5/28/4e5d92bd-869b-41d9-8179-cbc3ffba48c7.pdf'; 최근확인일='2026-08-15'
        }
    }
)

$liveSmokeResults = @()
foreach ($sample in $liveSmokeSamples) {
    $run = Invoke-Phase2BenefitShadowMode -Rows @($sample.Row) -SourceRowNumberOffset ($sample.SourceRowNumber - 1) -RequestInvoker $liveRequestInvoker -OperationalLiveRun
    $diag = @($run.EvidenceDiagnostics)[0]
    $review = @($run.Rows)[0]
    $liveSmokeResults += [pscustomobject][ordered]@{
        Label=$sample.Label
        SourceRowNumber=$review.SourceRowNumber
        BusinessName=$review.BusinessName
        Url=$sample.Row.출처URL
        FetchStatus=$(if($null -ne $diag){$diag.FetchStatus}else{'NONE'})
        OfficialityStatus=$(if($null -ne $diag){$diag.OfficialityStatus}else{'NONE'})
        BusinessBindingStatus=$(if($null -ne $diag){$diag.BusinessBindingStatus}else{'NONE'})
        ExtractionStatus=$(if($null -ne $diag){$diag.ExtractionStatus}else{'NONE'})
        BenefitState=$review.BenefitState
        ReviewClass=$review.ReviewClass
        ReasonCodes=(@($review.ReasonCodes) -join '|')
        ExternalRequestCount=$review.TotalExternalRequests
        ProductionAction=$review.ProductionAction
    }
}
Write-Host 'TASK7_LIVE_SMOKE_BEGIN'
$liveSmokeResults | ConvertTo-Json -Depth 8 | Write-Host
Write-Host 'TASK7_LIVE_SMOKE_END'
Assert-True (@($liveSmokeResults | Where-Object ProductionAction -ne 'NONE').Count -eq 0) 'Live smoke must remain shadow-only'
Assert-True (@($liveSmokeResults | Where-Object BenefitState -eq 'ENDED').Count -eq 0) 'Operational fetch/extraction limitations must not invent ENDED'

Write-Host 'Phase 2 benefit shadow mode tests passed.'

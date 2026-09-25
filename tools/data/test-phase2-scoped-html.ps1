$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-location/test-support.ps1')
. (Join-Path $PSScriptRoot 'invoke-phase2-benefit-shadow-mode.ps1')

$rows = @(
    (New-ScopeTestRow),
    (New-ScopeTestRow -Name '테스트가게 B' -Building '99' -Phone '02-0000-0099' -Benefit '30% 할인')
)
$html = Get-ScopeTestHtml
$counter = [pscustomobject]@{ Count=0 }
$http = {
    param($Uri)
    $counter.Count++
    [pscustomobject]@{ StatusCode=200; ContentType='text/html'; Text=$html; Bytes=$null }
}.GetNewClosure()

$run = Invoke-Phase2BenefitShadowMode -Rows $rows -SourceRowNumbers @(75,118) -UseScopedHtmlEvidence -RequestInvoker $http

Assert-ScopeEqual $counter.Count 1 'Two businesses sharing one exact source URL must fetch once'
Assert-ScopeEqual $run.PreparationSummary.ExternalFetchCount 1 'Preparation summary counts one physical fetch'
Assert-ScopeEqual $run.PreparationSummary.AdapterParseCount 1 'Two businesses sharing one snapshot must parse once'
Assert-ScopeEqual $run.PreparationSummary.AdapterReuseCount 1 'Second business reuses parsed template'
Assert-ScopeEqual $run.Results[0].SourceRowNumber 75 'Original sparse first row number survives'
Assert-ScopeEqual $run.Results[1].BusinessIdentity.SourceRowNumber 118 'Original sparse second row number survives independently'
$a = @($run.EvidenceDiagnostics | Where-Object SourceRowNumber -eq 75)[0]
$b = @($run.EvidenceDiagnostics | Where-Object SourceRowNumber -eq 118)[0]
Assert-ScopeEqual @($a.ValidatedClaims | Where-Object Value -eq '30% 할인').Count 0 'B benefit cannot contaminate A'
Assert-ScopeEqual @($b.ValidatedClaims | Where-Object Value -eq '10% 할인').Count 0 'A benefit cannot contaminate B'
Assert-ScopeEqual @($a.ValidatedClaims | Where-Object Value -eq '10% 할인').Count 1 'A selected benefit detail survives'
Assert-ScopeEqual @($b.ValidatedClaims | Where-Object Value -eq '30% 할인').Count 1 'B selected benefit detail survives'
Assert-ScopeEqual $run.Results[0].BenefitState 'NEEDS_VERIFICATION' 'Located generic detail does not establish lifecycle'
Assert-ScopeEqual $run.Results[1].BenefitState 'NEEDS_VERIFICATION' 'Located generic detail does not establish lifecycle for B'
Assert-ScopeTrue (@($run.Results | Where-Object ProductionAction -ne 'NONE').Count -eq 0) 'Scoped A1 remains shadow-only'
Assert-ScopeEqual $a.DiscoveryExecution 'NOT_REQUESTED' 'Scoped A1 does not execute discovery'
Assert-ScopeEqual $a.SnapshotId $b.SnapshotId 'Shared retrieval preserves one snapshot identity'
Assert-ScopeEqual $a.AdapterId 'HTML_GENERIC' 'Diagnostic preserves adapter identity'
Assert-ScopeEqual $a.AdapterVersion '1' 'Diagnostic preserves adapter version'
Assert-ScopeTrue (@($a.Slices).Count -eq 1) 'Located source exposes exactly one diagnostic slice'
Assert-ScopeTrue (-not [string]::IsNullOrWhiteSpace([string]$a.Slices[0].EvidenceReference)) 'Diagnostic preserves physical unit reference'
Assert-ScopeTrue (-not [string]::IsNullOrWhiteSpace([string]$a.Slices[0].RawEvidenceText)) 'Diagnostic preserves selected source text'

$p = $run.PreparationSummary
Assert-ScopeEqual ($p.LocatorLocated + $p.LocatorAmbiguous + $p.LocatorNotFound + $p.LocationNotAttempted) $p.SourceEvaluations 'Location counts reconcile with source evaluations'
Assert-ScopeEqual $p.SourceEvaluations 2 'Two row/source evaluations are counted'
Assert-ScopeEqual $p.LocatorLocated 2 'Both synthetic businesses are safely located'
Assert-ScopeEqual $p.LlmInvocationCount 0 'A1 invokes no LLM'

$beforeInvalid = $counter.Count
Assert-ScopeThrows { Invoke-Phase2BenefitShadowMode -Rows $rows -SourceRowNumbers @(75) -UseScopedHtmlEvidence -RequestInvoker $http } 'Reject incomplete sparse row map before fetch'
Assert-ScopeThrows { Invoke-Phase2BenefitShadowMode -Rows $rows -SourceRowNumbers @(75,75) -UseScopedHtmlEvidence -RequestInvoker $http } 'Reject duplicate sparse row map before fetch'
Assert-ScopeThrows { Invoke-Phase2BenefitShadowMode -Rows $rows -SourceRowNumbers @(75,118) -SourceRowNumberOffset 1 -UseScopedHtmlEvidence -RequestInvoker $http } 'Explicit sparse rows cannot coexist with explicit offset'
Assert-ScopeThrows { Invoke-Phase2BenefitShadowMode -Rows $rows -UseScopedHtmlEvidence -RequestInvoker $http -DiscoveryInvoker { throw 'must not call' } } 'Scoped A1 cannot enable discovery'
Assert-ScopeThrows { Invoke-Phase2BenefitShadowMode -Rows $rows -UseScopedHtmlEvidence -RequestInvoker $http -UnstructuredExtractor { throw 'must not call' } } 'Scoped A1 cannot enable unstructured extraction'
Assert-ScopeThrows { Invoke-Phase2BenefitShadowMode -Rows $rows -UseScopedHtmlEvidence -RequestInvoker $http -PdfTextExtractor { throw 'must not call' } } 'Scoped A1 cannot enable PDF extraction'
Assert-ScopeThrows { Invoke-Phase2BenefitShadowMode -Rows $rows -UseScopedHtmlEvidence -RequestInvoker $http -SpreadsheetExtractor { throw 'must not call' } } 'Scoped A1 cannot enable spreadsheet extraction'
Assert-ScopeEqual $counter.Count $beforeInvalid 'Contradictory scoped arguments are rejected before any request'

$failedCounter = [pscustomobject]@{ Count=0 }
$failed = Invoke-Phase2BenefitShadowMode -Rows $rows -UseScopedHtmlEvidence -RequestInvoker {
    param($Uri)
    $failedCounter.Count++
    throw 'timeout'
}
Assert-ScopeEqual $failedCounter.Count 1 'Same failed source URL is fetched once per run'
Assert-ScopeEqual @($failed.Results | Where-Object BenefitState -eq 'ENDED').Count 0 'Fetch failure never means ending'
Assert-ScopeEqual @($failed.Results | Where-Object ReviewClass -eq 'GREEN').Count 0 'Fetch failure never means approval'
Assert-ScopeEqual $failed.PreparationSummary.SourceFetchFailures 1 'Physical failed source is counted once'
Assert-ScopeEqual $failed.PreparationSummary.LocationNotAttempted 2 'Fetch failure prevents semantic locator status for both row evaluations'
Assert-ScopeEqual $failed.PreparationSummary.LocatorNotFound 0 'Fetch failure is not semantic NOT_FOUND'
Assert-ScopeEqual @($failed.EvidenceDiagnostics | Where-Object { $_.LocationStatus -eq 'NOT_FOUND' }).Count 0 'Failure diagnostics do not claim source absence'

$endingHtml = $html.Replace('30% 할인','혜택 종료')
$endingHttp = {
    param($Uri)
    [pscustomobject]@{ StatusCode=200; ContentType='text/html'; Text=$endingHtml; Bytes=$null }
}.GetNewClosure()
$single = Invoke-Phase2BenefitShadowMode -Rows @($rows[0]) -UseScopedHtmlEvidence -RequestInvoker $endingHttp
Assert-ScopeTrue ($single.Results[0].BenefitState -ne 'ENDED') 'Another business ending text cannot end A'

$ambiguousHtml = $html.Replace('테스트가게 B','테스트가게 A').Replace('서울특별시 마포구 테스트로 99','').Replace('02-0000-0099','')
$ambiguousHttp = {
    param($Uri)
    [pscustomobject]@{ StatusCode=200; ContentType='text/html'; Text=$ambiguousHtml; Bytes=$null }
}.GetNewClosure()
$ambiguous = Invoke-Phase2BenefitShadowMode -Rows @($rows[0]) -UseScopedHtmlEvidence -RequestInvoker $ambiguousHttp
Assert-ScopeEqual $ambiguous.PreparationSummary.LocatorAmbiguous 1 'Same-name unresolved alternatives are counted ambiguous'
Assert-ScopeEqual @($ambiguous.EvidenceDiagnostics[0].ValidatedClaims).Count 0 'Ambiguity cannot fall back to whole-page extraction'
Assert-ScopeEqual @($ambiguous.EvidenceDiagnostics[0].Slices).Count 0 'Ambiguity exposes no usable slice'

$empty = Invoke-Phase2BenefitShadowMode -Rows @() -UseScopedHtmlEvidence -RequestInvoker { throw 'must not fetch' }
Assert-ScopeEqual @($empty.Results).Count 0 'Empty scoped input yields empty results'
Assert-ScopeEqual @($empty.Rows).Count 0 'Empty scoped input yields empty review rows'
Assert-ScopeEqual $empty.PreparationSummary.ExternalFetchCount 0 'Empty scoped input performs no request'
Assert-ScopeEqual $empty.PreparationSummary.SourceEvaluations 0 'Empty scoped input performs no source evaluation'

$dir = Join-Path ([IO.Path]::GetTempPath()) ('milimap-scope-' + [Guid]::NewGuid().ToString('N'))
try {
    $csv = Join-Path $dir 'rows.csv'
    $summary = Join-Path $dir 'summary.json'
    $evidence = Join-Path $dir 'evidence.json'
    Export-Phase2BenefitShadowMode -Run $run -RowReportCsv $csv -SummaryJson $summary -EvidenceDiagnosticJson $evidence
    $exported = @(Import-Csv -LiteralPath $csv)
    Assert-ScopeEqual ([int]$exported[0].SourceRowNumber) 75 'CSV preserves original sparse row number'
    $diags = @(Get-Content -Raw -LiteralPath $evidence | ConvertFrom-Json)
    Assert-ScopeEqual $diags[0].Url 'https://city.example.go.kr/list' 'JSON preserves source URL'
    Assert-ScopeTrue (@($diags[0].ValidatedClaims | Where-Object EvidenceReference -like 'HTML_TABLE_*').Count -gt 0) 'JSON preserves original field reference'
    Assert-ScopeTrue (-not [string]::IsNullOrWhiteSpace([string]$diags[0].SnapshotId)) 'JSON preserves snapshot identity'
} finally {
    if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
}

$legacyCounter = [pscustomobject]@{ Count=0 }
$legacyResponse = {
    param($Uri)
    $legacyCounter.Count++
    [pscustomobject]@{
        StatusCode=200
        ContentType='text/html'
        Text='사업장명: 테스트가게 A' + [Environment]::NewLine + '주소: 서울특별시 마포구 테스트로 12'
        Bytes=$null
    }
}.GetNewClosure()
$legacy = Invoke-Phase2BenefitShadowMode -Rows @($rows[0]) -RequestInvoker $legacyResponse
Assert-ScopeTrue ($legacy.PSObject.Properties.Name -notcontains 'PreparationSummary') 'Legacy path shape remains unchanged when scoped opt-in is omitted'

$legacyMapped = Invoke-Phase2BenefitShadowMode -Rows @($rows[0]) -SourceRowNumbers @(75) -RequestInvoker $legacyResponse
Assert-ScopeEqual $legacyMapped.Results[0].SourceRowNumber 75 'Explicit SourceRowNumbers preserves original row identity even without scoped opt-in'
Assert-ScopeThrows { Invoke-Phase2BenefitShadowMode -Rows @($rows[0]) -SourceRowNumbers @(75) -SourceRowNumberOffset 1 -RequestInvoker $legacyResponse } 'Explicit row map and explicit offset are mutually exclusive for the runner interface'

# SYNTHETIC_ALGORITHM_ONLY / TEST_ONLY: no live source assertions.
# Collect independent failures so one preparation exception cannot hide the
# other regressions. Any failed case still fails this test script and CI.
$followupFailures = [Collections.Generic.List[string]]::new()
$followupPassed = [Collections.Generic.List[string]]::new()
function Test-A15Followup {
    param([string]$Name, [scriptblock]$Action)
    try {
        & $Action
        $followupPassed.Add($Name)
        Write-Host "PASS A1.5 follow-up: $Name"
    } catch {
        $detail = "$Name -- $($_.Exception.Message)"
        $followupFailures.Add($detail)
        Write-Host "FAIL A1.5 follow-up: $detail"
    }
}
function Invoke-A15MixedInput {
    param([string]$ContentType, [AllowEmptyString()][string]$Text, [AllowNull()][byte[]]$Bytes=$null)
    $mixedRows = @((New-ScopeTestRow), (New-ScopeTestRow))
    $mixedRows[0].'출처URL' = 'https://city.example.go.kr/broken'
    $goodHtml = Get-ScopeTestHtml
    $mixedHttp = {
        param($Uri)
        if ($Uri.AbsolutePath -eq '/broken') {
            return [pscustomobject]@{StatusCode=200;ContentType=$ContentType;Text=$Text;Bytes=$Bytes}
        }
        return [pscustomobject]@{StatusCode=200;ContentType='text/html';Text=$goodHtml;Bytes=$null}
    }.GetNewClosure()
    return Invoke-Phase2BenefitShadowMode -Rows $mixedRows -SourceRowNumbers @(75,118) -UseScopedHtmlEvidence -RequestInvoker $mixedHttp
}
function Assert-A15MixedUnresolved {
    param($Run, [string]$Reason)
    Assert-ScopeEqual @($Run.Results).Count 2 'A preparation failure must not abort the next business'
    Assert-ScopeEqual $Run.Results[0].SourceRowNumber 75 'Failed preparation preserves original row identity'
    Assert-ScopeEqual $Run.Results[1].SourceRowNumber 118 'Subsequent business preserves original row identity'
    Assert-ScopeEqual $Run.Results[0].BenefitState 'NEEDS_VERIFICATION' 'Preparation failure remains unresolved'
    Assert-ScopeTrue ($Run.Results[0].ReviewClass -ne 'GREEN') 'Preparation failure is not approval'
    $bad = $Run.EvidenceDiagnostics[0]
    $good = $Run.EvidenceDiagnostics[1]
    Assert-ScopeTrue ($bad.ReasonCodes -contains $Reason) 'Preparation preserves the specific failure reason'
    Assert-ScopeTrue ($bad.ReasonCodes -notcontains 'SOURCE_NOT_FOUND') 'Preparation failure is not semantic absence'
    Assert-ScopeEqual @($bad.ValidatedClaims).Count 0 'Preparation failure cannot expose usable claims'
    Assert-ScopeEqual @($bad.Slices).Count 0 'Preparation failure cannot expose a usable slice'
    Assert-ScopeTrue ([string]::IsNullOrEmpty([string]$bad.LocationStatus)) 'No semantic location exists after preparation failure'
    Assert-ScopeEqual $good.LocationStatus 'LOCATED' 'Subsequent supported business is still located'
    Assert-ScopeEqual @($good.ValidatedClaims | Where-Object Value -eq '10% 할인').Count 1 'Rejecting everything must not satisfy failure isolation'
    $metrics = $Run.PreparationSummary
    Assert-ScopeEqual $metrics.LocationNotAttempted 1 'Failed preparation counts as location not attempted'
    Assert-ScopeEqual $metrics.LocatorLocated 1 'Positive control is retained in the denominator'
    Assert-ScopeEqual ($metrics.LocatorLocated+$metrics.LocatorAmbiguous+$metrics.LocatorNotFound+$metrics.LocationNotAttempted) $metrics.SourceEvaluations 'Mixed-input counters reconcile'
}

Test-A15Followup 'PDF without text is unsupported, next row continues' {
    $mixed = Invoke-A15MixedInput -ContentType 'application/pdf' -Text '' -Bytes ([byte[]]@(1,2,3))
    Assert-A15MixedUnresolved -Run $mixed -Reason 'SOURCE_UNSUPPORTED'
    Assert-ScopeEqual $mixed.PreparationSummary.AdapterParseCount 1 'Unsupported PDF never enters the HTML parser'
}
Test-A15Followup 'XLSX without text is unsupported, next row continues' {
    $mixed = Invoke-A15MixedInput -ContentType 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' -Text '' -Bytes ([byte[]]@(1,2,3))
    Assert-A15MixedUnresolved -Run $mixed -Reason 'SOURCE_UNSUPPORTED'
    Assert-ScopeEqual $mixed.PreparationSummary.AdapterParseCount 1 'Unsupported XLSX never enters the HTML parser'
}
Test-A15Followup 'Empty successful HTML is preparation failure, not absence' {
    $mixed = Invoke-A15MixedInput -ContentType 'text/html' -Text ''
    Assert-A15MixedUnresolved -Run $mixed -Reason 'EXTRACTION_FAILED'
}
Test-A15Followup 'Real HTML provenance-construction exception is isolated' {
    $brokenHtml = (Get-ScopeTestHtml).Replace('<td>10% 할인</td>', '<td title="<td>">10% 할인</td>')
    Assert-ScopeThrows { ConvertTo-BenefitHtmlObservation -Document (New-ScopeTestDocument -Html $brokenHtml) } 'Fixture must exercise a real parser/provenance exception'
    $mixed = Invoke-A15MixedInput -ContentType 'text/html' -Text $brokenHtml
    Assert-A15MixedUnresolved -Run $mixed -Reason 'EXTRACTION_FAILED'
}
Test-A15Followup 'Complete supported absence preserves SOURCE_NOT_FOUND' {
    $absent = Invoke-Phase2BenefitShadowMode -Rows @((New-ScopeTestRow -Name '없는 테스트업체' -Building '55' -Phone '')) -UseScopedHtmlEvidence -RequestInvoker $http
    $diagnostic = $absent.EvidenceDiagnostics[0]
    Assert-ScopeEqual $diagnostic.LocationStatus 'NOT_FOUND' 'Fully processed observation may report target absence'
    Assert-ScopeTrue ($diagnostic.ReasonCodes -contains 'SOURCE_NOT_FOUND') 'Semantic absence has its own core reason'
    Assert-ScopeTrue ($diagnostic.ReasonCodes -notcontains 'EXTRACTION_FAILED') 'Successful location processing is not a parser failure'
    Assert-ScopeEqual @($diagnostic.ValidatedClaims).Count 0 'Absent target cannot yield a claim'
    Assert-ScopeEqual $absent.Results[0].BenefitState 'NEEDS_VERIFICATION' 'Target absence alone cannot end a benefit'
}
Test-A15Followup 'Explicit name mismatch with same identity evidence remains conflict' {
    $mismatch = Invoke-Phase2BenefitShadowMode -Rows @((New-ScopeTestRow -Name '다른 테스트업체')) -UseScopedHtmlEvidence -RequestInvoker $http
    Assert-ScopeEqual $mismatch.Results[0].ReviewClass 'RED' 'Explicit name mismatch with agreeing address/phone is an identity conflict'
    Assert-ScopeTrue ($mismatch.Results[0].ReasonCodes -contains 'BUSINESS_BINDING_CONFLICT') 'Name mismatch conflict must survive the orchestration boundary'
    Assert-ScopeTrue ($mismatch.EvidenceDiagnostics[0].ReasonCodes -notcontains 'SOURCE_NOT_FOUND') 'Identity contradiction is not plain target absence'
}
Test-A15Followup 'Legacy positional RequestInvoker remains the third argument' {
    $before = $legacyCounter.Count
    $positional = Invoke-Phase2BenefitShadowMode @($rows[0]) 1 $legacyResponse
    Assert-ScopeEqual $legacyCounter.Count ($before+1) 'Old positional call still invokes its request boundary'
    Assert-ScopeEqual $positional.Results[0].SourceRowNumber 2 'Old positional call keeps offset semantics'
    Assert-ScopeTrue ($positional.PSObject.Properties.Name -notcontains 'PreparationSummary') 'Old positional call stays unscoped'
}
Test-A15Followup 'PARTIAL HTML cannot claim target absence' {
    $partialHtml = (Get-ScopeTestHtml).Replace('<td>30% 할인</td>', '')
    $mixed = Invoke-A15MixedInput -ContentType 'text/html' -Text $partialHtml
    Assert-A15MixedUnresolved -Run $mixed -Reason 'EXTRACTION_FAILED'
    Assert-ScopeEqual $mixed.EvidenceDiagnostics[0].AdapterStatus 'PARTIAL' 'Partial structure stays partial'
}
Test-A15Followup 'Unsupported HTML structure cannot claim target absence' {
    $mixed = Invoke-A15MixedInput -ContentType 'text/html' -Text '<html><body>No supported business table</body></html>'
    Assert-A15MixedUnresolved -Run $mixed -Reason 'SOURCE_UNSUPPORTED'
    Assert-ScopeEqual $mixed.EvidenceDiagnostics[0].AdapterStatus 'UNSUPPORTED' 'Unsupported structure stays unsupported'
}
if ($followupFailures.Count -gt 0) { throw ('A1.5 follow-up failures: ' + ($followupFailures -join '; ')) }
Assert-ScopeEqual $followupPassed.Count 9 'All nine independent A1.5 follow-up cases ran'
Write-Host 'Phase 2 scoped HTML shadow mode tests passed.'

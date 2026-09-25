$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-location/test-support.ps1')
. (Join-Path $PSScriptRoot 'lib/benefit-source/discover-official-benefit-sources.ps1')
. (Join-Path $PSScriptRoot 'lib/benefit-evidence/convert-html-source-observation.ps1')

$path = Join-Path $PSScriptRoot 'lib/benefit-evidence/benefit-source-run-context.ps1'
if (-not (Test-Path -LiteralPath $path)) { throw 'Source run context is missing' }
. $path

function New-RunCandidate {
    param([int]$RowNumber, [string]$Url='https://city.example.go.kr/list?category=1')
    return New-BenefitSourceCandidate -SourceRowNumber $RowNumber -Url $Url -SourceKind PUBLIC_OFFICIAL -SourceLabel 'fixture' -DiscoveryMethod TEST -ObservedAt '2026-09-24T00:00:00Z'
}

$html = Get-ScopeTestHtml
$counter = [pscustomobject]@{ Count=0 }
$http = {
    param($Uri)
    $counter.Count++
    return [pscustomobject]@{ StatusCode=200; ContentType='text/html'; Text=$html; Bytes=$null }
}.GetNewClosure()

$ctx = New-BenefitSourceRunContext
$c2 = New-RunCandidate -RowNumber 2
$c3 = New-RunCandidate -RowNumber 3

$d2 = Get-BenefitRunSourceDocument -Context $ctx -Candidate $c2 -RequestInvoker $http
$d3 = Get-BenefitRunSourceDocument -Context $ctx -Candidate $c3 -RequestInvoker $http

Assert-ScopeEqual $counter.Count 1 'Same exact URL must fetch once'
Assert-ScopeEqual $ctx.Metrics.ExternalFetchCount 1 'ExternalFetchCount counts underlying requests only'
Assert-ScopeEqual $ctx.Metrics.FetchCacheHits 1 'Second exact URL is a fetch cache hit'
Assert-ScopeEqual $ctx.Metrics.UniqueRequestKeys 1 'One exact URL creates one request key'
Assert-ScopeEqual $d2.SourceRowNumber 2 'First caller receives its own row number'
Assert-ScopeEqual $d3.SourceRowNumber 3 'Second caller receives its own row number'
Assert-ScopeEqual $d2.ObservedAt $d3.ObservedAt 'Cache hit preserves original retrieval time'
Assert-ScopeTrue (-not [object]::ReferenceEquals($d2, $d3)) 'Documents must be independently reconstructed'

$o2 = Get-BenefitRunHtmlObservation -Context $ctx -Document $d2
$o3 = Get-BenefitRunHtmlObservation -Context $ctx -Document $d3
Assert-ScopeEqual $ctx.Metrics.AdapterParseCount 1 'Same snapshot parses once'
Assert-ScopeEqual $ctx.Metrics.AdapterReuseCount 1 'Second observation reuses parsed template'
Assert-ScopeEqual $o2.SourceRowNumber 2 'First observation keeps first row number'
Assert-ScopeEqual $o3.SourceRowNumber 3 'Second observation keeps second row number'
$o2.ContentUnits[0].StructuredFields['BusinessName'] = 'mutated'
Assert-ScopeEqual $o3.ContentUnits[0].StructuredFields.BusinessName '테스트가게 A' 'Mutable row wrapper must not contaminate another wrapper'
$o2fresh = Get-BenefitRunHtmlObservation -Context $ctx -Document $d2
Assert-ScopeEqual $o2fresh.ContentUnits[0].StructuredFields.BusinessName '테스트가게 A' 'Cached parsed template must remain isolated from caller mutation'
Assert-ScopeEqual $ctx.Metrics.AdapterParseCount 1 'Fresh wrapper must not reparse the same snapshot'
Assert-ScopeEqual $ctx.Metrics.AdapterReuseCount 2 'Fresh wrapper is another parse-cache reuse'

foreach ($url in @('https://city.example.go.kr/list?category=2','https://city.example.go.kr/List?category=1')) {
    $null = Get-BenefitRunSourceDocument -Context $ctx -Candidate (New-RunCandidate -RowNumber 4 -Url $url) -RequestInvoker $http
}
Assert-ScopeEqual $counter.Count 3 'Path case and query identity must remain distinct'
Assert-ScopeEqual $ctx.Metrics.UniqueRequestKeys 3 'Exact URL dictionary keeps distinct path/query keys'

$freshCtx = New-BenefitSourceRunContext
$null = Get-BenefitRunSourceDocument -Context $freshCtx -Candidate $c2 -RequestInvoker $http
Assert-ScopeEqual $counter.Count 4 'A new run context must not reuse another run cache'
Assert-ScopeEqual $freshCtx.Metrics.ExternalFetchCount 1 'Fresh run metrics are independent'
Assert-ScopeEqual $freshCtx.Metrics.FetchCacheHits 0 'Fresh run begins without hits'

$failureCount = [pscustomobject]@{ Count=0 }
$badHttp = {
    param($Uri)
    $failureCount.Count++
    throw 'timeout'
}.GetNewClosure()
$failedCtx = New-BenefitSourceRunContext
$failedDocs = @()
foreach ($rowNumber in @(2,3,4)) {
    $failedDocs += Get-BenefitRunSourceDocument -Context $failedCtx -Candidate (New-RunCandidate -RowNumber $rowNumber) -RequestInvoker $badHttp
}
Assert-ScopeEqual $failureCount.Count 1 'Failed exact URL is reused without retry storm'
Assert-ScopeEqual $failedCtx.Metrics.ExternalFetchCount 1 'Failed retrieval counts one underlying request'
Assert-ScopeEqual $failedCtx.Metrics.SourceFetchFailures 1 'Repeated failed URL counts one source failure'
Assert-ScopeEqual $failedCtx.Metrics.FetchCacheHits 2 'Repeated failed URL still uses fetch cache'
Assert-ScopeEqual $failedCtx.Metrics.UniqueRequestKeys 1 'Failed URL remains one exact request key'
Assert-ScopeEqual $failedDocs[0].ObservedAt $failedDocs[1].ObservedAt 'Failure cache hit preserves original observation time'
Assert-ScopeEqual $failedDocs[1].ObservedAt $failedDocs[2].ObservedAt 'All failed wrappers share the one retrieval observation time'
for ($i=0; $i -lt $failedDocs.Count; $i++) {
    Assert-ScopeEqual $failedDocs[$i].SourceRowNumber ($i + 2) 'Failed wrapper preserves current caller row'
    Assert-ScopeEqual $failedDocs[$i].FetchStatus 'FAILED' 'Failed retrieval remains operational failure'
    Assert-ScopeEqual $failedDocs[$i].Text '' 'Failed retrieval cannot reuse successful source text'
    Assert-ScopeTrue ($failedDocs[$i].ReasonCodes -contains 'SOURCE_FETCH_FAILED') 'Failed retrieval preserves source failure reason'
}
Assert-ScopeThrows { Get-BenefitRunHtmlObservation -Context $failedCtx -Document $failedDocs[0] } 'Failed HTTP document must not be parsed into semantic observation'
Assert-ScopeEqual $failedCtx.Metrics.AdapterParseCount 0 'Failed HTTP fetch must not invoke the HTML parser'

$profileACount = [pscustomobject]@{ Count=0 }
$profileBCount = [pscustomobject]@{ Count=0 }
$profileA = { param($Uri); $profileACount.Count++; [pscustomobject]@{StatusCode=200;ContentType='text/html';Text=$html;Bytes=$null} }.GetNewClosure()
$profileB = { param($Uri); $profileBCount.Count++; [pscustomobject]@{StatusCode=200;ContentType='text/html';Text=$html;Bytes=$null} }.GetNewClosure()
$profileCtx = New-BenefitSourceRunContext
$null = Get-BenefitRunSourceDocument -Context $profileCtx -Candidate $c2 -RequestInvoker $profileA
$null = Get-BenefitRunSourceDocument -Context $profileCtx -Candidate $c3 -RequestInvoker $profileA
Assert-ScopeEqual $profileACount.Count 1 'Same RequestInvoker object is accepted and exact URL reuses cache'
Assert-ScopeThrows { Get-BenefitRunSourceDocument -Context $profileCtx -Candidate (New-RunCandidate -RowNumber 4 -Url 'https://city.example.go.kr/other') -RequestInvoker $profileB } 'Changing RequestInvoker profile in one context must be rejected'
Assert-ScopeEqual $profileBCount.Count 0 'Rejected RequestInvoker must never be called'

$partialHtml = (Get-ScopeTestHtml) -replace '<td>30% 할인</td>', ''
$partialCount = [pscustomobject]@{ Count=0 }
$partialHttp = { param($Uri); $partialCount.Count++; [pscustomobject]@{StatusCode=200;ContentType='text/html';Text=$partialHtml;Bytes=$null} }.GetNewClosure()
$partialCtx = New-BenefitSourceRunContext
$partialDoc2 = Get-BenefitRunSourceDocument -Context $partialCtx -Candidate $c2 -RequestInvoker $partialHttp
$partialDoc3 = Get-BenefitRunSourceDocument -Context $partialCtx -Candidate $c3 -RequestInvoker $partialHttp
$partialObs2 = Get-BenefitRunHtmlObservation -Context $partialCtx -Document $partialDoc2
$partialObs3 = Get-BenefitRunHtmlObservation -Context $partialCtx -Document $partialDoc3
Assert-ScopeEqual $partialObs2.AdapterStatus 'PARTIAL' 'Partial parser result remains partial'
Assert-ScopeEqual $partialObs3.AdapterStatus 'PARTIAL' 'Partial parser result is reusable without semantic promotion'
Assert-ScopeEqual $partialCtx.Metrics.AdapterParseCount 1 'Partial snapshot parses once'
Assert-ScopeEqual $partialCtx.Metrics.AdapterReuseCount 1 'Partial template is reusable'

# A live official page can contain many safe rows.  Reusing the parsed
# template must also reuse its position-only token stream; otherwise every
# provenance assertion rescans the full source text once per row/wrapper.
$tokenCounter = [pscustomobject]@{ Count=0 }
$originalTokenizer = (Get-Item -Path Function:Get-ScopeHtmlTagTokens).ScriptBlock
$fragmentCounter = [pscustomobject]@{ Count=0 }
$originalFragment = (Get-Item -Path Function:Get-ScopeElementFragment).ScriptBlock
$countingTokenizer = {
    param([string]$Text)
    $tokenCounter.Count++
    & $originalTokenizer $Text
}.GetNewClosure()
$countingFragment = {
    param($Text, $Start, $Length, $Tag)
    $fragmentCounter.Count++
    & $originalFragment @PSBoundParameters
}.GetNewClosure()
Set-Item -Path Function:Get-ScopeHtmlTagTokens -Value $countingTokenizer
Set-Item -Path Function:Get-ScopeElementFragment -Value $countingFragment
try {
    $tokenCtx = New-BenefitSourceRunContext
    $tokenDoc2 = Get-BenefitRunSourceDocument -Context $tokenCtx -Candidate $c2 -RequestInvoker $http
    $tokenDoc3 = Get-BenefitRunSourceDocument -Context $tokenCtx -Candidate $c3 -RequestInvoker $http
    $null = Get-BenefitRunHtmlObservation -Context $tokenCtx -Document $tokenDoc2
    $null = Get-BenefitRunHtmlObservation -Context $tokenCtx -Document $tokenDoc3
} finally {
    Set-Item -Path Function:Get-ScopeHtmlTagTokens -Value $originalTokenizer
    Set-Item -Path Function:Get-ScopeElementFragment -Value $originalFragment
}
Assert-ScopeEqual $tokenCounter.Count 1 'Parsed HTML token stream must be reused for all rows sharing one snapshot'
Assert-ScopeEqual $fragmentCounter.Count 0 'Parsed HTML element spans must be reused for all rows sharing one snapshot'

Write-Host 'Benefit source run context tests passed.'

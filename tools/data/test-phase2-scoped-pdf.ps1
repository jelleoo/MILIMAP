Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-location/test-support.ps1')
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-pdf/test-support.ps1')
. (Join-Path $PSScriptRoot 'lib/benefit-evidence/invoke-scoped-benefit-source.ps1')
function New-PdfScopedCandidate {param([int]$Row=2);New-BenefitSourceCandidate -SourceRowNumber $Row -Url 'https://city.example.go.kr/synthetic.pdf' -SourceKind PUBLIC_OFFICIAL -SourceLabel '지자체 공식 자료' -DiscoveryMethod TEST}
function New-PdfScopedBusiness {param([string]$Name='합성가게 A',[string]$Building='12',[int]$Row=2);ConvertTo-NormalizedBusiness -Row (New-ScopeTestRow -Name $Name -Building $Building) -SourceRowNumber $Row}
$bytes=(New-PdfTestDocument).Bytes
$calls=[pscustomobject]@{Fetch=0;Parse=0;Index=0}
$http={param($Uri)$calls.Fetch++;[pscustomobject]@{StatusCode=200;ContentType='application/pdf';Text='';Bytes=$bytes}}.GetNewClosure()
$context=New-BenefitSourceRunContext
$a=Invoke-ScopedPhase2BenefitSourceCandidate -Candidate (New-PdfScopedCandidate) -Business (New-PdfScopedBusiness) -CanonicalPhone '02-0000-0012' -RunContext $context -RequestInvoker $http
Assert-PdfEqual ($null -ne $a.Observation) $true 'PDF enters native scoped preparation'
Assert-PdfEqual $a.Observation.AdapterStatus 'COMPLETE' 'Safe PDF source complete'
Assert-PdfEqual $a.LocationResult.Status 'LOCATED' 'A located'
Assert-PdfEqual $a.Bound.BusinessBindingStatus 'STRONG' 'Existing binding reused'
Assert-PdfEqual $a.Extraction.Claims[0].Value "합성 A 혜택`n합성 조건 A" 'Only A evidence'
Assert-PdfEqual $a.Extraction.Claims[0].ExtractionMethod 'SCOPED_PDF_CELL' 'Explicit PDF method'
Assert-PdfEqual $a.Extraction.Claims[0].EvidenceReference 'PDF_PAGE_1_TABLE_1_ROW_2/BenefitDescription' 'Exact physical field provenance'
Assert-PdfEqual $a.Validation.Claims[0].ValidationStatus 'VALIDATED' 'Existing validation reused'
$reader=${function:Invoke-BenefitPdfNativeProjection};$indexBuilder=${function:New-BenefitDocumentValidationIndex}
Set-Item Function:Invoke-BenefitPdfNativeProjection {param($Bytes)$calls.Parse++;& $reader -Bytes $Bytes}
Set-Item Function:New-BenefitDocumentValidationIndex {param($Snapshot,$AdapterId,$AdapterVersion,$ExtractionMethod,$ExtractorId,$ExtractorVersion,$ExtractionConfigHash,$Units)$calls.Index++;& $indexBuilder @PSBoundParameters}
try {
    # Fresh context measures the actual helper/index entry points for both businesses.
    $context=New-BenefitSourceRunContext;$calls.Fetch=0
    $a=Invoke-ScopedPhase2BenefitSourceCandidate -Candidate (New-PdfScopedCandidate) -Business (New-PdfScopedBusiness) -CanonicalPhone '02-0000-0012' -RunContext $context -RequestInvoker $http
    $b=Invoke-ScopedPhase2BenefitSourceCandidate -Candidate (New-PdfScopedCandidate 3) -Business (New-PdfScopedBusiness -Name '합성가게 B' -Building 34 -Row 3) -CanonicalPhone '02-0000-0034' -RunContext $context -RequestInvoker $http
    Assert-PdfEqual $b.Extraction.Claims[0].Value '합성 B 혜택' 'B excludes A evidence'
    Assert-PdfEqual $b.Slices[0].EvidenceReference 'PDF_PAGE_1_TABLE_1_ROW_3' 'B own row'
    Assert-PdfEqual $a.Slices[0].RawEvidenceText.Contains('합성 B 혜택') $false 'A never leaks B'
    Assert-PdfEqual $b.Slices[0].RawEvidenceText.Contains('합성 A 혜택') $false 'B never leaks A'
    Assert-PdfEqual ([object]::ReferenceEquals($a.Observation.DocumentValidationIndex,$b.Observation.DocumentValidationIndex)) $true 'Same immutable source index reused'
} finally {Set-Item Function:Invoke-BenefitPdfNativeProjection $reader;Set-Item Function:New-BenefitDocumentValidationIndex $indexBuilder}
Assert-PdfEqual $calls.Fetch 1 'Underlying shared PDF fetch once'
Assert-PdfEqual $calls.Parse 1 'Native parse once'
Assert-PdfEqual $calls.Index 1 'Grid/document index build once'
Assert-PdfEqual $context.Metrics.ExternalFetchCount 1 'External fetch metric'
Assert-PdfEqual $context.Metrics.AdapterParseCount 1 'Parse metric'
Assert-PdfEqual $context.Metrics.AdapterReuseCount 1 'Reuse metric'
Assert-PdfEqual $a.Observation.Snapshot.Text '' 'Binary snapshot does not manufacture text'
$badDocument=Copy-ScopeContractData $a.Document;$badDocument.Bytes=(New-PdfTestDocument 'repeated').Bytes
Assert-PdfThrows {Get-BenefitRunPdfObservation -Context $context -Document $badDocument} 'Payload/document byte mismatch'
$absent=Invoke-ScopedPhase2BenefitSourceCandidate -Candidate (New-PdfScopedCandidate 4) -Business (New-PdfScopedBusiness -Name '없는 합성가게' -Row 4) -RunContext $context -RequestInvoker $http
Assert-PdfEqual $absent.LocationResult.Status 'NOT_FOUND' 'Complete identity absence only'
Assert-PdfEqual $absent.Extraction.Claims.Count 0 'Absence yields no lifecycle claims'
foreach($case in @(@('merged-value','PARTIAL'),@('native-no-grid','UNSUPPORTED'),@('image-only','UNSUPPORTED'),@('malformed-later','FAILED'))){
    $badBytes=(New-PdfTestDocument $case[0]).Bytes
    $badHttp={param($Uri)[pscustomobject]@{StatusCode=200;ContentType='application/pdf';Text='';Bytes=$badBytes}}.GetNewClosure()
    $badContext=New-BenefitSourceRunContext
    foreach($number in @(2,3)){
        $bad=Invoke-ScopedPhase2BenefitSourceCandidate -Candidate (New-PdfScopedCandidate $number) -Business (New-PdfScopedBusiness -Row $number) -RunContext $badContext -RequestInvoker $badHttp
        Assert-PdfEqual $bad.LocationResult.OperationalStatus $case[1] 'Incomplete remains operational'
        Assert-PdfEqual $bad.LocationResult.Status $null 'No LOCATED/NOT_FOUND from incomplete source'
        Assert-PdfEqual $bad.Slices.Count 0 'No incomplete usable slice'
        Assert-PdfEqual $bad.Extraction.Claims.Count 0 'No incomplete claims'
    }
    Assert-PdfEqual $badContext.Metrics.AdapterParseCount 1 'Incomplete outcomes cached too'
    Assert-PdfEqual $badContext.Metrics.AdapterReuseCount 1 'Incomplete observation reused'
}
$duplicateBytes=(New-PdfTestDocument 'duplicate-name').Bytes
$duplicateHttp={param($Uri)[pscustomobject]@{StatusCode=200;ContentType='application/pdf';Text='';Bytes=$duplicateBytes}}.GetNewClosure()
$duplicate=Invoke-ScopedPhase2BenefitSourceCandidate -Candidate (New-PdfScopedCandidate) -Business (New-PdfScopedBusiness) -CanonicalPhone '02-0000-0012' -RunContext (New-BenefitSourceRunContext) -RequestInvoker $duplicateHttp
Assert-PdfEqual $duplicate.LocationResult.Status 'AMBIGUOUS' 'Conflicting same-name alternative not discarded'
Assert-PdfEqual $duplicate.Slices.Count 0 'Ambiguity yields no evidence'
Write-Host 'Scoped PDF tests passed: leakage 0; fetch 1 / native parse 1 / grid-index 1 / reuse 1.'

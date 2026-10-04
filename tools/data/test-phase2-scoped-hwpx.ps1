Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-location/test-support.ps1')
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-hwpx/test-support.ps1')
. (Join-Path $PSScriptRoot 'lib/benefit-evidence/invoke-scoped-benefit-source.ps1')
function New-HwpxScopedCandidate {param([int]$Row=2);New-BenefitSourceCandidate -SourceRowNumber $Row -Url 'https://city.example.go.kr/synthetic.hwpx' -SourceKind PUBLIC_OFFICIAL -SourceLabel '지자체 공식 자료' -DiscoveryMethod TEST}
function New-HwpxScopedBusiness {param([string]$Name='합성가게 A',[string]$Building='12',[int]$Row=2);ConvertTo-NormalizedBusiness -Row (New-ScopeTestRow -Name $Name -Building $Building) -SourceRowNumber $Row}
$bytes=New-HwpxTestBytes -Sections @((New-HwpxTestSection))
$calls=[pscustomobject]@{Fetch=0;Parse=0}
$http={param($Uri)$calls.Fetch++;[pscustomobject]@{StatusCode=200;ContentType='application/hwp+zip';Text='';Bytes=$bytes}}.GetNewClosure()
$context=New-BenefitSourceRunContext
$reader=${function:Read-InternalBenefitHwpxPackage}
Set-Item Function:Read-InternalBenefitHwpxPackage -Value {param($Snapshot)$calls.Parse++;&$reader -Snapshot $Snapshot}
try {
    $a=Invoke-ScopedPhase2BenefitSourceCandidate -Candidate (New-HwpxScopedCandidate) -Business (New-HwpxScopedBusiness) -CanonicalPhone '02-0000-0012' -RunContext $context -RequestInvoker $http
    Assert-ScopeTrue ($null -ne $a.Observation) 'HWPX must enter scoped preparation instead of unsupported-format fallback'
    Assert-ScopeEqual $a.Document.SourceFormat HWPX 'Byte classification retained'
    Assert-ScopeEqual $a.Qualified.OfficialityStatus VERIFIED_OFFICIAL 'Official synthetic fixture candidate qualified'
    Assert-ScopeEqual $a.Observation.AdapterId HWPX_GENERIC 'Native generic adapter used'
    Assert-ScopeEqual $a.LocationResult.Status LOCATED 'Parsed A identity located'
    Assert-ScopeEqual $a.Bound.BusinessBindingStatus STRONG 'Existing identity rules bind strongly'
    Assert-ScopeEqual $a.Extraction.Claims[0].Value '합성 A 혜택' 'Only A benefit extracted'
    Assert-ScopeEqual $a.Extraction.Claims[0].ExtractionMethod SCOPED_HWPX_CELL 'Explicit HWPX extraction method'
    Assert-ScopeEqual $a.Extraction.Claims[0].EvidenceReference HWPX_SECTION_1_TABLE_1_ROW_2/BenefitDescription 'Exact cell field reference'
    Assert-ScopeEqual $a.Validation.Status COMPLETE 'HWPX validation completes'
    Assert-ScopeEqual $a.Validation.Claims[0].ValidationStatus VALIDATED 'Parsed field validated'
    $b=Invoke-ScopedPhase2BenefitSourceCandidate -Candidate (New-HwpxScopedCandidate 3) -Business (New-HwpxScopedBusiness -Name '합성가게 B' -Building 34 -Row 3) -CanonicalPhone '02-0000-0034' -RunContext $context -RequestInvoker $http
    Assert-ScopeEqual $b.Extraction.Claims[0].Value '합성 B 혜택' 'B never borrows A benefit'
    Assert-ScopeEqual $b.Slices[0].EvidenceReference HWPX_SECTION_1_TABLE_1_ROW_3 'B selects its own row'
    Assert-ScopeTrue (-not ($a.Slices[0].RawEvidenceText.Contains('합성 B 혜택'))) 'A slice excludes B benefit text'
    Assert-ScopeTrue (-not ($b.Slices[0].RawEvidenceText.Contains('합성 A 혜택'))) 'B slice excludes A benefit text'
}finally{Set-Item Function:Read-InternalBenefitHwpxPackage -Value $reader}
Assert-ScopeEqual $calls.Fetch 1 'Actual shared-source fetch once'
Assert-ScopeEqual $calls.Parse 1 'Actual shared-source package/XML parse once'
Assert-ScopeEqual $context.Metrics.ExternalFetchCount 1 'Fetch metric once'
Assert-ScopeEqual $context.Metrics.AdapterParseCount 1 'Parse metric once'
Assert-ScopeEqual $context.Metrics.AdapterReuseCount 1 'Second business reuses parsed index'
$absent=Invoke-ScopedPhase2BenefitSourceCandidate -Candidate (New-HwpxScopedCandidate 4) -Business (New-HwpxScopedBusiness -Name '없는 합성가게' -Row 4) -RunContext $context -RequestInvoker $http
Assert-ScopeEqual $absent.LocationResult.Status NOT_FOUND 'Complete absence is identity absence only'
Assert-ScopeEqual $absent.Extraction.Claims.Count 0 'Absence generates no lifecycle claims'
Assert-ScopeTrue ($absent.PSObject.Properties.Name -notcontains 'BenefitState') 'Scoped source does not manufacture ENDED'
foreach($case in @(@{Sections=@((New-HwpxTestSection),'<broken');Status='PARTIAL'},@{Sections=@((New-HwpxTestSection '<hp:p/>'));Status='UNSUPPORTED'})){
    $badBytes=New-HwpxTestBytes -Sections $case.Sections
    $badHttp={param($Uri)[pscustomobject]@{StatusCode=200;ContentType='application/hwp+zip';Text='';Bytes=$badBytes}}.GetNewClosure()
    $badContext=New-BenefitSourceRunContext
    foreach($number in @(2,3)){
        $bad=Invoke-ScopedPhase2BenefitSourceCandidate -Candidate (New-HwpxScopedCandidate $number) -Business (New-HwpxScopedBusiness -Row $number) -RunContext $badContext -RequestInvoker $badHttp
        Assert-ScopeEqual $bad.LocationResult.OperationalStatus $case.Status 'Operational failure remains operational'
        Assert-ScopeTrue ($null -eq $bad.LocationResult.Status) 'Incomplete HWPX cannot LOCATED/NOT_FOUND'
        Assert-ScopeEqual $bad.Slices.Count 0 'Incomplete result exposes no usable slice'
        Assert-ScopeTrue ($bad.Validation.Status -ne 'COMPLETE') 'Incomplete source cannot validate'
    }
    Assert-ScopeEqual $badContext.Metrics.AdapterParseCount 1 'Incomplete scoped source still parsed once'
}
$duplicateBytes=New-HwpxTestBytes -Sections @((New-HwpxTestSection (New-HwpxTestTable).Replace('합성가게 B','합성가게 A').Replace('테스트로 34','테스트로 12').Replace('02-0000-0034','02-0000-0012')))
$duplicateHttp={param($Uri)[pscustomobject]@{StatusCode=200;ContentType='application/hwp+zip';Text='';Bytes=$duplicateBytes}}.GetNewClosure()
$duplicate=Invoke-ScopedPhase2BenefitSourceCandidate -Candidate (New-HwpxScopedCandidate) -Business (New-HwpxScopedBusiness) -CanonicalPhone '02-0000-0012' -RunContext (New-BenefitSourceRunContext) -RequestInvoker $duplicateHttp
Assert-ScopeEqual $duplicate.LocationResult.Status AMBIGUOUS 'Two corroborated same-name rows remain ambiguous'
Assert-ScopeEqual $duplicate.Slices.Count 0 'Ambiguity cannot leak claims'
$pdfHttp={param($Uri)[pscustomobject]@{StatusCode=200;ContentType='application/pdf';Text='';Bytes=[Text.Encoding]::ASCII.GetBytes("%PDF-1.7`nsynthetic")}}
$pdf=Invoke-ScopedPhase2BenefitSourceCandidate -Candidate (New-HwpxScopedCandidate) -Business (New-HwpxScopedBusiness) -RunContext (New-BenefitSourceRunContext) -RequestInvoker $pdfHttp
Assert-ScopeTrue ($null -eq $pdf.Observation) 'PDF remains excluded from scoped runner'
Assert-ScopeTrue ($pdf.ReasonCodes -contains 'SOURCE_UNSUPPORTED') 'PDF fails closed'
Write-Host 'Scoped HWPX tests passed: cross-business leakage 0; shared source fetch 1 / parse 1 / reuse 1.'

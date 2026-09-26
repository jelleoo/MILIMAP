$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-location/test-support.ps1')
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-xlsx/test-support.ps1')
. (Join-Path $PSScriptRoot 'lib/benefit-evidence/invoke-scoped-benefit-source.ps1')

$row = [pscustomobject]@{ 업소명='가마골 백숙'; 시도='경기도'; 시군구='양주시'; 소재지도로명주소='양주시 장흥면 북한산로 1028'; 소재지지번주소=''; 업소전화번호='031-861-4800'; 할인정보=''; 적용대상=''; 이용조건=''; 인증방법=''; 출처유형='지자체 공식 자료'; 출처URL='https://city.example.go.kr/attachment'; 최근확인일='2026-09-26' }
$business = ConvertTo-NormalizedBusiness -Row $row -SourceRowNumber 2
$candidate = New-BenefitSourceCandidate -SourceRowNumber 2 -Url $row.출처URL -SourceKind PUBLIC_OFFICIAL -SourceLabel '지자체 공식 자료' -DiscoveryMethod TEST -ObservedAt '2026-09-26T00:00:00Z'
$fetch = [pscustomobject]@{ Count=0 }
[byte[]]$mainXlsxBytes = New-XlsxTestBytes
$http = { param($Uri) $fetch.Count++; [pscustomobject]@{StatusCode=200;ContentType='application/octer-stream';Text='';Bytes=$mainXlsxBytes} }.GetNewClosure()
$context = New-BenefitSourceRunContext
$result = Invoke-ScopedPhase2BenefitSourceCandidate -Candidate $candidate -Business $business -CanonicalPhone '031-861-4800' -RunContext $context -RequestInvoker $http
Assert-ScopeEqual $result.Qualified.OfficialityStatus VERIFIED_OFFICIAL 'Official XLSX source is qualified'
Assert-ScopeEqual $result.LocationResult.Status LOCATED 'XLSX identity is located'
Assert-ScopeEqual $result.Bound.BusinessBindingStatus STRONG 'Located XLSX row binds strongly'
Assert-ScopeEqual $result.Extraction.Status COMPLETE 'Scoped XLSX extraction completes'
Assert-ScopeEqual $result.Validation.Status COMPLETE 'Scoped XLSX validation completes'
$claim = @($result.Extraction.Claims | Where-Object ClaimType -eq BENEFIT_DESCRIPTION)[0]
Assert-ScopeEqual $claim.ExtractionMethod SCOPED_XLSX_CELL 'XLSX uses an explicit scoped extraction method'
Assert-ScopeEqual $claim.EvidenceReference XLSX_SHEET_1_ROW_22/BenefitDescription 'XLSX claim preserves the exact physical field reference'
Assert-ScopeEqual @($result.Validation.Claims | Where-Object ValidationStatus -eq VALIDATED).Count 1 'Scoped XLSX claim is validated'
Assert-ScopeTrue (@($result.Extraction.Claims | Where-Object ClaimType -in @('VALID_FROM','VALID_UNTIL')).Count -eq 0) 'XLSX row does not infer lifecycle dates'

$multiUrl = 'https://city.example.go.kr/multi-attachment'
$multiFirstRow = [pscustomobject]@{ 업소명='가마골 백숙'; 시도='경기도'; 시군구='양주시'; 소재지도로명주소='양주시 장흥면 북한산로 1028'; 소재지지번주소=''; 업소전화번호='031-861-4800'; 할인정보=''; 적용대상=''; 이용조건=''; 인증방법=''; 출처유형='지자체 공식 자료'; 출처URL=$multiUrl; 최근확인일='2026-09-26' }
$multiSecondRow = [pscustomobject]@{ 업소명='두번째 업소'; 시도='경기도'; 시군구='양주시'; 소재지도로명주소='양주시 장흥면 북한산로 1029'; 소재지지번주소=''; 업소전화번호='031-861-4801'; 할인정보=''; 적용대상=''; 이용조건=''; 인증방법=''; 출처유형='지자체 공식 자료'; 출처URL=$multiUrl; 최근확인일='2026-09-26' }
$multiFirstBusiness = ConvertTo-NormalizedBusiness -Row $multiFirstRow -SourceRowNumber 12
$multiSecondBusiness = ConvertTo-NormalizedBusiness -Row $multiSecondRow -SourceRowNumber 13
$multiFirstCandidate = New-BenefitSourceCandidate -SourceRowNumber 12 -Url $multiUrl -SourceKind PUBLIC_OFFICIAL -SourceLabel '지자체 공식 자료' -DiscoveryMethod TEST -ObservedAt '2026-09-26T00:00:00Z'
$multiSecondCandidate = New-BenefitSourceCandidate -SourceRowNumber 13 -Url $multiUrl -SourceKind PUBLIC_OFFICIAL -SourceLabel '지자체 공식 자료' -DiscoveryMethod TEST -ObservedAt '2026-09-26T00:00:00Z'
$multiFetch = [pscustomobject]@{ Count=0 }
[byte[]]$multiBytes = New-XlsxTestBytes -SecondName '두번째 업소' -SecondAddress '양주시 장흥면 북한산로 1029' -SecondPhone '031-861-4801' -SecondBenefit '음료 서비스'
$multiHttp = { param($Uri) $multiFetch.Count++; [pscustomobject]@{StatusCode=200;ContentType='application/octer-stream';Text='';Bytes=$multiBytes} }.GetNewClosure()
$multiContext = New-BenefitSourceRunContext
$script:scopedXlsxHashCount = 0
$script:originalScopedXlsxHash = (Get-Item Function:Get-BenefitEvidenceByteHash).ScriptBlock
function Get-BenefitEvidenceByteHash { param([Parameter(Mandatory)][byte[]]$Bytes); $script:scopedXlsxHashCount++; & $script:originalScopedXlsxHash -Bytes $Bytes }
try {
    $multiFirstResult = Invoke-ScopedPhase2BenefitSourceCandidate -Candidate $multiFirstCandidate -Business $multiFirstBusiness -CanonicalPhone '031-861-4800' -RunContext $multiContext -RequestInvoker $multiHttp
    $multiFirstHashCount = $script:scopedXlsxHashCount
    $multiSecondResult = Invoke-ScopedPhase2BenefitSourceCandidate -Candidate $multiSecondCandidate -Business $multiSecondBusiness -CanonicalPhone '031-861-4801' -RunContext $multiContext -RequestInvoker $multiHttp
    $multiSecondHashCount = $script:scopedXlsxHashCount - $multiFirstHashCount
} finally {
    Set-Item Function:Get-BenefitEvidenceByteHash -Value $script:originalScopedXlsxHash
    Remove-Variable -Scope Script -Name originalScopedXlsxHash -ErrorAction SilentlyContinue
}
Assert-ScopeEqual $multiFirstResult.LocationResult.Status LOCATED 'First valid XLSX business is located'
Assert-ScopeEqual $multiSecondResult.LocationResult.Status LOCATED 'Second valid XLSX business is located from the shared attachment'
Assert-ScopeEqual $multiFetch.Count 1 'Two valid scoped XLSX businesses fetch one attachment once'
Assert-ScopeEqual $multiContext.Metrics.ExternalFetchCount 1 'Two valid scoped XLSX businesses make one external fetch'
Assert-ScopeEqual $multiContext.Metrics.FetchCacheHits 1 'Second valid scoped XLSX business reuses the payload'
Assert-ScopeEqual $multiContext.Metrics.AdapterParseCount 1 'Two valid scoped XLSX businesses parse once'
Assert-ScopeEqual $multiContext.Metrics.AdapterReuseCount 1 'Second valid scoped XLSX business reuses the template and index'
Assert-ScopeTrue ($multiFirstHashCount -gt 0) 'First valid scoped XLSX business validates the workbook bytes'
Assert-ScopeEqual $multiSecondHashCount 0 'Second valid scoped XLSX business adds no workbook hash during binding, extraction, or validation'

$absentRow = [pscustomobject]@{ 업소명='없는 업소'; 시도='경기도'; 시군구='양주시'; 소재지도로명주소='양주시 장흥면 북한산로 1028'; 소재지지번주소=''; 업소전화번호='031-861-4800'; 할인정보=''; 적용대상=''; 이용조건=''; 인증방법=''; 출처유형='지자체 공식 자료'; 출처URL='https://city.example.go.kr/attachment'; 최근확인일='2026-09-26' }
$absentBusiness = ConvertTo-NormalizedBusiness -Row $absentRow -SourceRowNumber 3
$absentCandidate = New-BenefitSourceCandidate -SourceRowNumber 3 -Url $absentRow.출처URL -SourceKind PUBLIC_OFFICIAL -SourceLabel '지자체 공식 자료' -DiscoveryMethod TEST -ObservedAt '2026-09-26T00:00:00Z'
$hashBeforeSecond = 0
$script:scopedXlsxHashCount = 0
$script:originalScopedXlsxHash = (Get-Item Function:Get-BenefitEvidenceByteHash).ScriptBlock
function Get-BenefitEvidenceByteHash { param([Parameter(Mandatory)][byte[]]$Bytes); $script:scopedXlsxHashCount++; & $script:originalScopedXlsxHash -Bytes $Bytes }
try { $absentResult = Invoke-ScopedPhase2BenefitSourceCandidate -Candidate $absentCandidate -Business $absentBusiness -CanonicalPhone '031-861-4800' -RunContext $context -RequestInvoker $http; $hashBeforeSecond = $script:scopedXlsxHashCount } finally { Set-Item Function:Get-BenefitEvidenceByteHash -Value $script:originalScopedXlsxHash; Remove-Variable -Scope Script -Name originalScopedXlsxHash -ErrorAction SilentlyContinue }
Assert-ScopeEqual $fetch.Count 1 'Two scoped XLSX businesses fetch one attachment once'
Assert-ScopeEqual $context.Metrics.ExternalFetchCount 1 'Scoped XLSX external fetch count is one'
Assert-ScopeEqual $context.Metrics.FetchCacheHits 1 'Second scoped XLSX business reuses payload'
Assert-ScopeEqual $context.Metrics.AdapterParseCount 1 'Scoped XLSX parses once'
Assert-ScopeEqual $context.Metrics.AdapterReuseCount 1 'Second scoped XLSX business reuses template/index'
Assert-ScopeEqual $hashBeforeSecond 0 'Second scoped XLSX business adds no workbook hash'
Assert-ScopeEqual $absentResult.LocationResult.Status NOT_FOUND 'Missing business has semantic absence only after complete XLSX observation'
Assert-ScopeTrue (@($absentResult.Extraction.Claims | Where-Object ClaimType -in @('VALID_FROM','VALID_UNTIL')).Count -eq 0) 'Missing XLSX business does not infer lifecycle dates'

$partialCandidate = New-BenefitSourceCandidate -SourceRowNumber 20 -Url 'https://city.example.go.kr/partial-attachment' -SourceKind PUBLIC_OFFICIAL -SourceLabel '지자체 공식 자료' -DiscoveryMethod TEST -ObservedAt '2026-09-26T00:00:00Z'
$partialBusiness = ConvertTo-NormalizedBusiness -Row ([pscustomobject]@{ 업소명='가마골 백숙'; 시도='경기도'; 시군구='양주시'; 소재지도로명주소='양주시 장흥면 북한산로 1028'; 소재지지번주소=''; 업소전화번호='031-861-4800'; 할인정보=''; 적용대상=''; 이용조건=''; 인증방법=''; 출처유형='지자체 공식 자료'; 출처URL=$partialCandidate.Url; 최근확인일='2026-09-26' }) -SourceRowNumber 20
[byte[]]$partialXlsxBytes = New-XlsxTestBytes -FormulaBusinessName
$partialHttp = { param($Uri) [pscustomobject]@{StatusCode=200;ContentType='application/octer-stream';Text='';Bytes=$partialXlsxBytes} }.GetNewClosure()
$partialResult = Invoke-ScopedPhase2BenefitSourceCandidate -Candidate $partialCandidate -Business $partialBusiness -CanonicalPhone '031-861-4800' -RunContext (New-BenefitSourceRunContext) -RequestInvoker $partialHttp
Assert-ScopeEqual $partialResult.LocationResult.OperationalStatus PARTIAL 'Formula-backed XLSX identity is an operational partial failure'
Assert-ScopeTrue ($null -eq $partialResult.LocationResult.Status) 'Formula-backed XLSX identity cannot become semantic absence'
Assert-ScopeTrue ($partialResult.Extraction.ReasonCodes -notcontains 'SOURCE_NOT_FOUND') 'Formula-backed XLSX identity is never NOT_FOUND'

$unsupportedCandidate = New-BenefitSourceCandidate -SourceRowNumber 21 -Url 'https://city.example.go.kr/unsupported-identity-attachment' -SourceKind PUBLIC_OFFICIAL -SourceLabel '지자체 공식 자료' -DiscoveryMethod TEST -ObservedAt '2026-09-26T00:00:00Z'
$unsupportedBusiness = ConvertTo-NormalizedBusiness -Row ([pscustomobject]@{ 업소명='가마골 백숙'; 시도='경기도'; 시군구='양주시'; 소재지도로명주소='양주시 장흥면 북한산로 1028'; 소재지지번주소=''; 업소전화번호='031-861-4800'; 할인정보=''; 적용대상=''; 이용조건=''; 인증방법=''; 출처유형='지자체 공식 자료'; 출처URL=$unsupportedCandidate.Url; 최근확인일='2026-09-26' }) -SourceRowNumber 21
[byte[]]$unsupportedXlsxBytes = New-XlsxTestBytes -UnsupportedBusinessName
$unsupportedHttp = { param($Uri) [pscustomobject]@{StatusCode=200;ContentType='application/octer-stream';Text='';Bytes=$unsupportedXlsxBytes} }.GetNewClosure()
$unsupportedResult = Invoke-ScopedPhase2BenefitSourceCandidate -Candidate $unsupportedCandidate -Business $unsupportedBusiness -CanonicalPhone '031-861-4800' -RunContext (New-BenefitSourceRunContext) -RequestInvoker $unsupportedHttp
Assert-ScopeEqual $unsupportedResult.LocationResult.OperationalStatus PARTIAL 'Unsupported XLSX identity is an operational partial failure'
Assert-ScopeTrue ($null -eq $unsupportedResult.LocationResult.Status) 'Unsupported XLSX identity cannot become semantic absence'
Assert-ScopeTrue ($unsupportedResult.Extraction.ReasonCodes -notcontains 'SOURCE_NOT_FOUND') 'Unsupported XLSX identity is never NOT_FOUND'

$indexCandidate = New-BenefitSourceCandidate -SourceRowNumber 30 -Url 'https://city.example.go.kr/index-a' -SourceKind PUBLIC_OFFICIAL -SourceLabel '지자체 공식 자료' -DiscoveryMethod TEST -ObservedAt '2026-09-26T00:00:00Z'
$wrongIndexCandidate = New-BenefitSourceCandidate -SourceRowNumber 30 -Url 'https://city.example.go.kr/index-b' -SourceKind PUBLIC_OFFICIAL -SourceLabel '지자체 공식 자료' -DiscoveryMethod TEST -ObservedAt '2026-09-26T00:00:00Z'
$indexBusiness = ConvertTo-NormalizedBusiness -Row ([pscustomobject]@{ 업소명='가마골 백숙'; 시도='경기도'; 시군구='양주시'; 소재지도로명주소='양주시 장흥면 북한산로 1028'; 소재지지번주소=''; 업소전화번호='031-861-4800'; 할인정보=''; 적용대상=''; 이용조건=''; 인증방법=''; 출처유형='지자체 공식 자료'; 출처URL=$indexCandidate.Url; 최근확인일='2026-09-26' }) -SourceRowNumber 30
$indexContext = New-BenefitSourceRunContext
[byte[]]$indexXlsxBytes = New-XlsxTestBytes
[byte[]]$wrongIndexXlsxBytes = New-XlsxTestBytes -Benefit '다른 혜택'
$indexHttp = { param($Uri) [pscustomobject]@{StatusCode=200;ContentType='application/octer-stream';Text='';Bytes=$indexXlsxBytes} }.GetNewClosure()
$wrongIndexHttp = { param($Uri) [pscustomobject]@{StatusCode=200;ContentType='application/octer-stream';Text='';Bytes=$wrongIndexXlsxBytes} }.GetNewClosure()
$indexDocument = Get-BenefitRunSourceDocument -Context $indexContext -Candidate $indexCandidate -RequestInvoker $indexHttp
$indexObservation = Get-BenefitRunXlsxObservation -Context $indexContext -Document $indexDocument
$wrongIndexContext = New-BenefitSourceRunContext
$wrongIndexDocument = Get-BenefitRunSourceDocument -Context $wrongIndexContext -Candidate $wrongIndexCandidate -RequestInvoker $wrongIndexHttp
$wrongIndexObservation = Get-BenefitRunXlsxObservation -Context $wrongIndexContext -Document $wrongIndexDocument
Assert-ScopeThrows { Find-BenefitBusinessEvidence -Observation $indexObservation -Business $indexBusiness -CanonicalPhone '031-861-4800' -XlsxValidationIndex $wrongIndexObservation.XlsxValidationIndex } 'A cross-snapshot XLSX validation index fails closed'

Write-Host 'Phase 2 scoped XLSX tests passed.'

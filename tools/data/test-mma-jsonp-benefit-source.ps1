$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-location/test-support.ps1')

$invokerPath = Join-Path $PSScriptRoot 'lib/benefit-evidence/invoke-mma-jsonp-benefit-source.ps1'
if (-not (Test-Path -LiteralPath $invokerPath)) { throw 'MMA JSONP benefit source invoker is missing' }
. $invokerPath

function New-MmaTestBusiness {
    param([int]$SourceRowNumber, [ValidateSet('2789','2740')][string]$InstitutionCode)
    $row = if ($InstitutionCode -eq '2789') {
        [pscustomobject]@{ 업소명='(유)투투여행사'; 시도='서울특별시'; 시군구='테스트구'; 소재지도로명주소='서울특별시 테스트구 여행로 2789'; 소재지지번주소=''; 업소전화번호='02-2789-0000'; 할인정보=''; 적용대상=''; 이용조건=''; 인증방법=''; 출처유형='병무청 공식 자료'; 출처URL='https://www.mma.go.kr/about/udgg/list.do?mc=mma0003357'; 최근확인일='2026-09-25' }
    } else {
        [pscustomobject]@{ 업소명='(주) 예쁜떡 오늘'; 시도='서울특별시'; 시군구='테스트구'; 소재지도로명주소='서울특별시 테스트구 떡로 2740'; 소재지지번주소=''; 업소전화번호='02-2740-0000'; 할인정보=''; 적용대상=''; 이용조건=''; 인증방법=''; 출처유형='병무청 공식 자료'; 출처URL='https://www.mma.go.kr/about/udgg/list.do?mc=mma0003357'; 최근확인일='2026-09-25' }
    }
    return ConvertTo-NormalizedBusiness -Row $row -SourceRowNumber $SourceRowNumber
}

function New-MmaEntryCandidate {
    param([int]$SourceRowNumber)
    return New-BenefitSourceCandidate -SourceRowNumber $SourceRowNumber -Url 'https://www.mma.go.kr/about/udgg/list.do?mc=mma0003357' -SourceKind PUBLIC_OFFICIAL -SourceLabel '병무청 나라사랑 가게조회' -DiscoveryMethod EXISTING_CANONICAL_URL -ObservedAt '2026-09-25T00:00:00Z'
}

$fixtureRoot = Join-Path $PSScriptRoot 'testdata/benefit-evidence-mma'
$listText = Get-Content -Raw -LiteralPath (Join-Path $fixtureRoot 'mma-list.fixture.jsonp')
$detail2789Text = Get-Content -Raw -LiteralPath (Join-Path $fixtureRoot 'mma-detail-2789.fixture.jsonp')
$detail2740Text = Get-Content -Raw -LiteralPath (Join-Path $fixtureRoot 'mma-detail-2740.fixture.jsonp')
$listTransportText = $listText -replace '^MmaTestList','MmaBenefitList'
$detail2789TransportText = $detail2789Text -replace '^MmaTestDetail','MmaBenefitDetail'
$detail2740TransportText = $detail2740Text -replace '^MmaTestDetail','MmaBenefitDetail'
$requests = [Collections.Generic.List[string]]::new()
$http = {
    param($Uri)
    [void]$requests.Add([string]$Uri)
    if ($Uri -like '*mmanrsrListAjaxJsonCallNew.json*') { return [pscustomobject]@{StatusCode=200;ContentType='application/json';Text=$listTransportText;Bytes=$null} }
    if ($Uri -like '*udgigwan_cd=2789*') { return [pscustomobject]@{StatusCode=200;ContentType='application/json';Text=$detail2789TransportText;Bytes=$null} }
    if ($Uri -like '*udgigwan_cd=2740*') { return [pscustomobject]@{StatusCode=200;ContentType='application/json';Text=$detail2740TransportText;Bytes=$null} }
    throw "Unexpected fixture request: $Uri"
}.GetNewClosure()

$ctx = New-BenefitSourceRunContext
$tourBusiness = New-MmaTestBusiness -SourceRowNumber 2 -InstitutionCode 2789
$record = Invoke-MmaJsonpBenefitSourceCandidate -Candidate (New-MmaEntryCandidate -SourceRowNumber 2) -Business $tourBusiness -CanonicalPhone '02-2789-0000' -RunContext $ctx -RequestInvoker $http
Assert-ScopeEqual $record.LocationResult.Status LOCATED 'MMA list record is located before detail fetch'
Assert-ScopeEqual $record.Document.SourceFormat JSONP 'Returned claim document is the detail JSONP document'
Assert-ScopeEqual $record.Qualified.OfficialityStatus VERIFIED_OFFICIAL 'Detail open.mma.go.kr source is official'
Assert-ScopeEqual $record.Bound.BusinessBindingStatus STRONG 'Located detail remains bound to selected business'
Assert-ScopeEqual @($record.Validation.Claims | Where-Object ClaimType -eq BENEFIT_DESCRIPTION).Count 1 'Detail benefit is validated'
Assert-ScopeEqual $record.Validation.Claims[0].ExtractionMethod SCOPED_JSONP_FIELD 'JSONP method is explicit'
Assert-ScopeEqual $requests.Count 2 'First MMA business requests list and matching detail exactly once'

$riceBusiness = New-MmaTestBusiness -SourceRowNumber 3 -InstitutionCode 2740
$riceRecord = Invoke-MmaJsonpBenefitSourceCandidate -Candidate (New-MmaEntryCandidate -SourceRowNumber 3) -Business $riceBusiness -CanonicalPhone '02-2740-0000' -RunContext $ctx -RequestInvoker $http
Assert-ScopeEqual $requests.Count 3 'Second MMA business reuses list and requests only its own detail'
$tourRepeat = Invoke-MmaJsonpBenefitSourceCandidate -Candidate (New-MmaEntryCandidate -SourceRowNumber 2) -Business $tourBusiness -CanonicalPhone '02-2789-0000' -RunContext $ctx -RequestInvoker $http
Assert-ScopeEqual $requests.Count 3 'Same selected MMA institution reuses its detail request'
Assert-ScopeEqual $tourRepeat.Document.Url $record.Document.Url 'Cached detail preserves selected institution provenance'

$finiteDetail = $detail2789TransportText -replace '9999-12-31','2026-12-31'
$finiteHttp = { param($Uri) if ($Uri -like '*mmanrsrListAjaxJsonCallNew.json*') { [pscustomobject]@{StatusCode=200;ContentType='application/json';Text=$listTransportText;Bytes=$null} } else { [pscustomobject]@{StatusCode=200;ContentType='application/json';Text=$finiteDetail;Bytes=$null} } }.GetNewClosure()
$finiteRecord = Invoke-MmaJsonpBenefitSourceCandidate -Candidate (New-MmaEntryCandidate -SourceRowNumber 2) -Business $tourBusiness -CanonicalPhone '02-2789-0000' -RunContext (New-BenefitSourceRunContext) -RequestInvoker $finiteHttp
Assert-ScopeEqual @($finiteRecord.Validation.Claims | Where-Object ClaimType -eq VALID_UNTIL).Count 1 'Finite MMA agreement end produces one source-backed valid-until claim'
Assert-ScopeEqual (@($finiteRecord.Validation.Claims | Where-Object ClaimType -eq VALID_UNTIL)[0].ValidationStatus) VALIDATED 'Finite MMA agreement end validates against its selected source field'
Assert-ScopeEqual @($record.Validation.Claims | Where-Object ClaimType -eq VALID_UNTIL).Count 0 '9999-12-31 remains observed source data without a decisive valid-until claim'

function Invoke-MmaFailureCase {
    param([string]$ListBody=$listTransportText, [string]$DetailBody=$detail2789TransportText, [string]$ExpectedDiagnosticCode='')
    $failureHttp = {
        param($Uri)
        if ($Uri -like '*mmanrsrListAjaxJsonCallNew.json*') { return [pscustomobject]@{StatusCode=200;ContentType='application/json';Text=$ListBody;Bytes=$null} }
        return [pscustomobject]@{StatusCode=200;ContentType='application/json';Text=$DetailBody;Bytes=$null}
    }.GetNewClosure()
    $failure = Invoke-MmaJsonpBenefitSourceCandidate -Candidate (New-MmaEntryCandidate -SourceRowNumber 2) -Business (New-MmaTestBusiness -SourceRowNumber 2 -InstitutionCode 2789) -CanonicalPhone '02-2789-0000' -RunContext (New-BenefitSourceRunContext) -RequestInvoker $failureHttp
    Assert-ScopeEqual @($failure.Validation.Claims).Count 0 'Failed MMA linkage cannot validate a benefit claim'
    Assert-ScopeTrue (@($failure.PreparationDiagnostics).Count -gt 0) 'Failed MMA linkage preserves diagnostics'
    Assert-ScopeTrue (@($failure.Validation.Claims | Where-Object { $_.ClaimType -eq 'VALID_UNTIL' -and $_.Value -eq 'ENDED' }).Count -eq 0) 'Failed MMA linkage never implies ENDED'
    if ($ExpectedDiagnosticCode) { Assert-ScopeTrue (@($failure.PreparationDiagnostics | Where-Object Code -eq $ExpectedDiagnosticCode).Count -gt 0) "Expected diagnostic: $ExpectedDiagnosticCode" }
}

Invoke-MmaFailureCase -ListBody 'MmaBenefitList({"success":true,"list":[{"udgigwan_cd":"","udgigwan_yhnm":"(유)투투여행사","addr":"서울특별시 테스트구 여행로 2789","udgigwan_telno":"02-2789-0000","udggeopjong_gbnm":"여행사"}]});' -ExpectedDiagnosticCode MMA_INSTITUTION_CODE_MISSING
Invoke-MmaFailureCase -DetailBody ($detail2789TransportText -replace '"udgigwan_cd":"2789"','"udgigwan_cd":"2740"') -ExpectedDiagnosticCode MMA_INSTITUTION_CODE_MISMATCH
Invoke-MmaFailureCase -DetailBody 'MmaBenefitDetail({"success":false})' -ExpectedDiagnosticCode MMA_DETAIL_UNAVAILABLE
Invoke-MmaFailureCase -DetailBody ($detail2789TransportText -replace '^MmaBenefitDetail','WrongCallback') -ExpectedDiagnosticCode MMA_DETAIL_UNAVAILABLE
Invoke-MmaFailureCase -ListBody 'MmaBenefitList({"success":true,"list":[{"udgigwan_cd":"2789","udgigwan_yhnm":"(유)투투여행사","addr":"","udgigwan_telno":"","udggeopjong_gbnm":"여행사"},{"udgigwan_cd":"9992","udgigwan_yhnm":"(유)투투여행사","addr":"","udgigwan_telno":"","udggeopjong_gbnm":"여행사"}]});' -ExpectedDiagnosticCode MMA_LIST_UNUSABLE

Write-Host 'MMA JSONP benefit source tests passed.'

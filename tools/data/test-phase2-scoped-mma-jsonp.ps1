$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-location/test-support.ps1')
$runnerPath = Join-Path $PSScriptRoot 'invoke-phase2-benefit-shadow-mode.ps1'
. $runnerPath

function New-MmaShadowRow {
    param([ValidateSet('2789','2740')][string]$Code)
    if ($Code -eq '2789') { return [pscustomobject]@{업소명='(유)투투여행사';시도='서울특별시';시군구='테스트구';소재지도로명주소='서울특별시 테스트구 여행로 2789';소재지지번주소='';업소전화번호='02-2789-0000';할인정보='서비스 이용료 3% 할인';적용대상='군장병';이용조건='제휴 조건 적용';인증방법='군 신분증 제시';출처유형='병무청 공식 자료';출처URL='https://www.mma.go.kr/about/udgg/list.do?mc=mma0003357';최근확인일='2026-09-25'} }
    return [pscustomobject]@{업소명='(주) 예쁜떡 오늘';시도='서울특별시';시군구='테스트구';소재지도로명주소='서울특별시 테스트구 떡로 2740';소재지지번주소='';업소전화번호='02-2740-0000';할인정보='구매 금액 5% 할인';적용대상='군장병';이용조건='제휴 조건 적용';인증방법='군 신분증 제시';출처유형='병무청 공식 자료';출처URL='https://www.mma.go.kr/about/udgg/list.do?mc=mma0003357';최근확인일='2026-09-25'}
}
$root=Join-Path $PSScriptRoot 'testdata/benefit-evidence-mma'
$list=(Get-Content -Raw (Join-Path $root 'mma-list.fixture.jsonp')) -replace '^MmaTestList','MmaBenefitList'
$detail2789=(Get-Content -Raw (Join-Path $root 'mma-detail-2789.fixture.jsonp')) -replace '^MmaTestDetail','MmaBenefitDetail'
$detail2740=(Get-Content -Raw (Join-Path $root 'mma-detail-2740.fixture.jsonp')) -replace '^MmaTestDetail','MmaBenefitDetail'
$http={param($Uri) if($Uri -like '*mmanrsrListAjaxJsonCallNew*'){[pscustomobject]@{StatusCode=200;ContentType='application/json';Text=$list;Bytes=$null}}elseif($Uri -like '*2789*'){[pscustomobject]@{StatusCode=200;ContentType='application/json';Text=$detail2789;Bytes=$null}}else{[pscustomobject]@{StatusCode=200;ContentType='application/json';Text=$detail2740;Bytes=$null}}}.GetNewClosure()
$run=Invoke-Phase2BenefitShadowMode -Rows @((New-MmaShadowRow 2789),(New-MmaShadowRow 2740)) -SourceRowNumbers @(4,5) -UseScopedEvidence -RequestInvoker $http
Assert-ScopeEqual @($run.Results).Count 2 'Two MMA controls complete shadow evaluation'
Assert-ScopeTrue (@($run.Results | Where-Object ProductionAction -ne NONE).Count -eq 0) 'MMA remains shadow-only'
Assert-ScopeEqual @($run.EvidenceDiagnostics | Where-Object SourceFormat -eq JSONP).Count 2 'Claim evidence is JSONP'
Assert-ScopeEqual @($run.EvidenceDiagnostics | Where-Object AdapterId -eq MMA_JSONP_DETAIL).Count 2 'MMA detail adapter identity is exposed'
Assert-ScopeTrue ([string]$run.EvidenceDiagnostics[0].LinkageSnapshotId -match '^[0-9a-f]{64}$') 'MMA diagnostic exports list snapshot provenance'
Assert-ScopeEqual $run.EvidenceDiagnostics[0].LinkageEvidenceReference JSONP_LIST_ITEM_1 'MMA diagnostic exports selected list evidence reference'
Assert-ScopeEqual $run.EvidenceDiagnostics[0].LinkageInstitutionCodeReference 'JSONP_LIST_ITEM_1/udgigwan_cd' 'MMA diagnostic exports selected institution-code provenance'
Assert-ScopeTrue ((@($run.EvidenceDiagnostics[0].ValidatedClaims | Where-Object ClaimType -eq BENEFIT_DESCRIPTION).Count -eq 1)) 'First control has source-backed benefit'
Assert-ScopeTrue ((@($run.EvidenceDiagnostics[1].ValidatedClaims | Where-Object ClaimType -eq BENEFIT_DESCRIPTION).Count -eq 1)) 'Second control has source-backed benefit'

$htmlRow=New-ScopeTestRow -Name '테스트가게 A' -Building '12' -Phone '02-0000-0012'
$mixedHtml = Get-ScopeTestHtml
Assert-ScopeTrue (-not [string]::IsNullOrWhiteSpace($mixedHtml)) 'Mixed HTML fixture is materialized before the request boundary'
$mixedHttp={param($Uri) if($Uri -like '*mmanrsrListAjaxJsonCallNew*'){[pscustomobject]@{StatusCode=200;ContentType='application/json';Text=$list;Bytes=$null}}elseif($Uri -like '*2789*'){[pscustomobject]@{StatusCode=200;ContentType='application/json';Text=$detail2789;Bytes=$null}}elseif($Uri -like '*mma.go.kr*'){throw 'Unexpected MMA request'}else{[pscustomobject]@{StatusCode=200;ContentType='text/html';Text=$mixedHtml;Bytes=$null}}}.GetNewClosure()
$mixed=Invoke-Phase2BenefitShadowMode -Rows @((New-MmaShadowRow 2789),$htmlRow) -SourceRowNumbers @(6,7) -UseScopedEvidence -RequestInvoker $mixedHttp
Assert-ScopeEqual @($mixed.Results).Count 2 'Mixed MMA and HTML scoped evidence evaluates both rows'
Assert-ScopeEqual @($mixed.EvidenceDiagnostics | Where-Object AdapterId -eq MMA_JSONP_DETAIL).Count 1 'Mixed run keeps MMA adapter identity'
Assert-ScopeEqual @($mixed.EvidenceDiagnostics | Where-Object AdapterId -eq HTML_GENERIC).Count 1 'Mixed run keeps HTML adapter identity'
Assert-ScopeTrue (@($mixed.EvidenceDiagnostics[0].ValidatedClaims.Value + $mixed.EvidenceDiagnostics[1].ValidatedClaims.Value | Where-Object { $_ -eq '30% 할인' }).Count -eq 0) 'Mixed families cannot leak unrelated source claims'

$sentinelOnlyRow = New-MmaShadowRow 2789
$sentinelOnlyRow.할인정보 = ''
$sentinelOnlyRow.적용대상 = ''
$sentinelOnlyRow.이용조건 = ''
$sentinelOnlyRow.인증방법 = ''
$sentinelOnlyRun = Invoke-Phase2BenefitShadowMode -Rows @($sentinelOnlyRow) -SourceRowNumbers @(8) -UseScopedEvidence -RequestInvoker $http
Assert-ScopeEqual @($sentinelOnlyRun.EvidenceDiagnostics[0].ValidatedClaims | Where-Object ClaimType -eq VALID_UNTIL).Count 0 '9999-12-31 produces no downstream valid-until claim'
Assert-ScopeEqual $sentinelOnlyRun.Results[0].BenefitState NEEDS_VERIFICATION '9999-12-31 alone cannot produce a decisive lifecycle state'
Write-Host 'Phase 2 scoped MMA JSONP tests passed.'

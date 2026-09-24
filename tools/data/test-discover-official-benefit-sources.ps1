$ErrorActionPreference = 'Stop'

$contractPath = Join-Path $PSScriptRoot 'lib/benefit-verification-contracts.ps1'
$sourcePath = Join-Path $PSScriptRoot 'lib/benefit-source/discover-official-benefit-sources.ps1'
. $contractPath
if (Test-Path -LiteralPath $sourcePath) { . $sourcePath }

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

$benefit = New-CanonicalBenefitRecord -SourceRowNumber 2 -BusinessName '테스트 식당' -ExistingSourceType '지자체 공식 자료' -ExistingSourceUrl 'https://city.example.go.kr/current' -ExistingVerifiedOn '2026-09-24'
$benefitWithoutUrl = New-CanonicalBenefitRecord -SourceRowNumber 2 -BusinessName '테스트 식당'
$business = New-NormalizedBusiness -SourceRowNumber 2 -OriginalName '테스트 식당' -NormalizedName '테스트식당' -AddressParseStatus 'UNPARSED'

$candidate = Get-ExistingBenefitSourceCandidate -Benefit $benefit
Assert-Equal $candidate.Url 'https://city.example.go.kr/current' 'Existing URL must be emitted first'
Assert-Equal $candidate.SourceRowNumber 2 'Existing candidate must preserve source row'
Assert-Equal $candidate.SourceKind 'PUBLIC_OFFICIAL' 'Existing candidate remains a source-kind candidate only'
Assert-Equal $candidate.DiscoveryMethod 'EXISTING_CANONICAL_URL' 'Existing candidate provenance must be preserved'
Assert-True (-not [string]::IsNullOrWhiteSpace($candidate.ObservedAt)) 'Existing candidate must retain observation time'

$businessWebsiteBenefit = New-CanonicalBenefitRecord -SourceRowNumber 3 -BusinessName '테스트 식당' -ExistingSourceType '업체 공식 홈페이지' -ExistingSourceUrl 'https://business.example.com/benefit'
Assert-Equal (Get-ExistingBenefitSourceCandidate -Benefit $businessWebsiteBenefit).SourceKind 'BUSINESS_WEBSITE' 'Explicit official business website must retain business source kind'
foreach ($nonStrongSource in @('업체 공식 SNS', '이용 후기')) {
    $nonStrongBenefit = New-CanonicalBenefitRecord -SourceRowNumber 4 -BusinessName '테스트 식당' -ExistingSourceType $nonStrongSource -ExistingSourceUrl 'https://example.com/benefit'
    Assert-Equal (Get-ExistingBenefitSourceCandidate -Benefit $nonStrongBenefit) $null "Deferred/non-strong existing evidence must not become strong candidate: $nonStrongSource"
}

$noProvider = Invoke-OfficialBenefitSourceDiscovery -Benefit $benefitWithoutUrl -Business $business
Assert-Equal $noProvider.Status 'FAILED' 'Missing discovery provider must fail closed'
Assert-True ($noProvider.ReasonCodes -contains 'DISCOVERY_PROVIDER_NOT_CONFIGURED') 'Missing discovery provider reason must be preserved'

$unsafeUrls = @('file:///etc/passwd', 'data:text/plain,unsafe', 'http://localhost/benefit', 'http://127.0.0.1/benefit', 'http://10.0.0.1/benefit', 'http://172.16.0.1/benefit', 'http://192.168.0.1/benefit', 'http://169.254.169.254/latest', 'http://intranet/benefit', 'http://router.local/benefit', 'http://0.0.0.0/benefit', 'http://[::]/benefit', 'http://[fc00::1]/benefit', 'https://user:password@city.example.go.kr/benefit')
foreach ($url in $unsafeUrls) {
    Assert-Throws { Get-BenefitSourceDocument -Candidate (New-BenefitSourceCandidate -SourceRowNumber 2 -Url $url) -RequestInvoker { param($Uri) throw 'RequestInvoker must not run for unsafe URLs' } } "Unsafe URL must be rejected before fetch: $url"
}
Assert-True (Test-BenefitSafeHttpUri -Url 'https://city.example.go.kr/benefit') 'Public-looking HTTPS host must remain allowed'
Assert-True (Test-BenefitSafeHttpUri -Url 'http://public.example.com/benefit') 'Public-looking HTTP host must remain allowed'

$discovered = Invoke-OfficialBenefitSourceDiscovery -Benefit $benefitWithoutUrl -Business $business -DiscoveryInvoker {
    param($DiscoveryBenefit, $DiscoveryBusiness)
    @(
        [pscustomobject]@{ Url='https://city.example.go.kr/benefit'; SourceKind='PUBLIC_OFFICIAL'; SourceLabel='지자체 공식 자료' },
        [pscustomobject]@{ Url='https://business.example.com/benefit'; SourceKind='BUSINESS_WEBSITE'; SourceLabel='업체 공식 홈페이지' }
    )
}
Assert-Equal $discovered.Status 'COMPLETE' 'Valid injected discovery must complete'
Assert-Equal $discovered.Candidates.Count 2 'Valid injected discovery candidates must be preserved'
foreach ($discoveredCandidate in $discovered.Candidates) {
    Assert-BenefitSourceCandidate $discoveredCandidate
    Assert-Equal $discoveredCandidate.SourceRowNumber 2 'Discovery candidate must preserve source row'
    Assert-Equal $discoveredCandidate.DiscoveryMethod 'DISCOVERY_INVOKER' 'Discovery candidate provenance must be preserved'
    Assert-True (-not [string]::IsNullOrWhiteSpace($discoveredCandidate.ObservedAt)) 'Discovery candidate must retain observation time'
}
$invalidDiscovery = Invoke-OfficialBenefitSourceDiscovery -Benefit $benefitWithoutUrl -Business $business -DiscoveryInvoker { param($DiscoveryBenefit, $DiscoveryBusiness) [pscustomobject]@{ Url='https://city.example.go.kr/benefit'; SourceKind='UNCLASSIFIED'; SourceLabel='fixture' } }
Assert-Equal $invalidDiscovery.Status 'FAILED' 'Invalid discovery source kind must fail closed'

$html = Get-BenefitSourceDocument -Candidate $candidate -RequestInvoker { param($Uri) [pscustomobject]@{ StatusCode=200; ContentType='text/html; charset=utf-8'; Text='<html>군인 할인</html>'; Bytes=$null } }
Assert-Equal $html.FetchStatus 'COMPLETE' 'Successful HTML fetch must be complete'
Assert-Equal $html.SourceFormat 'HTML' 'HTML content type must be detected'
Assert-Equal $html.SourceRowNumber 2 'Fetched document must preserve source row'
Assert-Equal $html.Url $candidate.Url 'Fetched document must preserve URL'
Assert-True (-not [string]::IsNullOrWhiteSpace($html.ObservedAt)) 'Fetched document must retain observation time'

$failed = Get-BenefitSourceDocument -Candidate $candidate -RequestInvoker { param($Uri) throw 'timeout' }
Assert-Equal $failed.FetchStatus 'FAILED' 'Fetch exception must remain operational failure'
Assert-True ($failed.ReasonCodes -contains 'SOURCE_FETCH_FAILED') 'Fetch failure reason must be preserved'

$formatCases = @(
    @{ Url='https://city.example.go.kr/list.csv'; ContentType='text/csv'; Expected='CSV' },
    @{ Url='https://city.example.go.kr/list.xlsx'; ContentType='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'; Expected='XLSX' },
    @{ Url='https://city.example.go.kr/notice.pdf'; ContentType='application/pdf'; Expected='PDF' },
    @{ Url='https://city.example.go.kr/archive.bin'; ContentType='application/octet-stream'; Expected='UNSUPPORTED' }
)
foreach ($formatCase in $formatCases) {
    $formatCandidate = New-BenefitSourceCandidate -SourceRowNumber 2 -Url $formatCase.Url -SourceKind 'PUBLIC_OFFICIAL' -SourceLabel 'fixture' -DiscoveryMethod 'TEST'
    $document = Get-BenefitSourceDocument -Candidate $formatCandidate -RequestInvoker { param($Uri) [pscustomobject]@{ StatusCode=200; ContentType=$formatCase.ContentType; Text='fixture'; Bytes=$null } }.GetNewClosure()
    Assert-Equal $document.FetchStatus 'COMPLETE' "Fetch must complete for $($formatCase.Expected)"
    Assert-Equal $document.SourceFormat $formatCase.Expected "Source format must detect $($formatCase.Expected)"
}

Write-Host 'Official benefit source boundary tests passed.'

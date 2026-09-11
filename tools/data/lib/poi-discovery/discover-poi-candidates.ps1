Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'poi-verification-contracts.ps1')

function Join-PoiDiscoveryQuery {
    param([AllowEmptyCollection()][object[]]$Parts)
    return ((@($Parts | ForEach-Object { ConvertTo-PoiText $_ } | Where-Object { $_ }) -join ' ') -replace '\s+', ' ').Trim()
}

function Get-PoiDiscoveryQueryPlan {
    <# Only consumes A's supplied fields; never parses or repairs a source address.
       Ineligible strategies have no query and are omitted. Executable strategies
       keep contract order. Identical queries are recorded as SKIPPED by discovery.
       BASE_NAME_BUILDING keeps locality/road context to avoid nationwide number searches. #>
    param([Parameter(Mandatory)]$Business)
    Assert-NormalizedBusiness $Business
    $name = ConvertTo-PoiText $Business.OriginalName
    $base = ConvertTo-PoiText $Business.BaseName
    $address = ConvertTo-PoiText $Business.PreferredAddress
    $road = ConvertTo-PoiText $Business.RoadName
    $number = ConvertTo-PoiText $Business.BuildingMain
    if ($number -and (ConvertTo-PoiText $Business.BuildingSub)) { $number += '-' + $Business.BuildingSub }
    $area = Join-PoiDiscoveryQuery @($Business.Province, $Business.City, $Business.District)
    $locality = Join-PoiDiscoveryQuery @($area, $Business.Dong)
    $plan = [Collections.Generic.List[object]]::new()
    if ($name -and $address) {
        $plan.Add(@{ StrategyCode='NAME_FULL_ADDRESS'; Query=(Join-PoiDiscoveryQuery @($name, $address)) })
    }
    if ($name -and $road -and $number) {
        $plan.Add(@{ StrategyCode='NAME_ROAD_BUILDING'; Query=(Join-PoiDiscoveryQuery @($name, $area, $road, $number)) })
    }
    if ($name -and $locality -and $road) {
        $plan.Add(@{ StrategyCode='NAME_LOCALITY_ROAD'; Query=(Join-PoiDiscoveryQuery @($name, $locality, $road)) })
    }
    if ($base -and $road -and $number) {
        $plan.Add(@{ StrategyCode='BASE_NAME_BUILDING'; Query=(Join-PoiDiscoveryQuery @($base, $area, $road, $number)) })
    }
    if ($base -and $locality) {
        $plan.Add(@{ StrategyCode='BASE_NAME_LOCALITY'; Query=(Join-PoiDiscoveryQuery @($base, $locality)) })
    }
    for ($index = 0; $index -lt $plan.Count; $index++) {
        [pscustomobject][ordered]@{ StrategyCode=$plan[$index].StrategyCode; Query=$plan[$index].Query; QueryOrder=($index + 1) }
    }
}

function Get-PoiDiscoveryProviderField {
    param([AllowNull()]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [Collections.IDictionary]) { return $Object[$Name] }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $null
}

function ConvertTo-PoiDiscoveryProviderText {
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return '' }
    if ($Value -isnot [string]) { throw 'INVALID_PROVIDER_RESPONSE' }
    return $Value.Trim()
}

function ConvertTo-PoiDiscoveryCoordinates {
    param([AllowNull()]$MapX, [AllowNull()]$MapY)
    $x = ConvertTo-PoiText $MapX
    $y = ConvertTo-PoiText $MapY
    if (-not $x -and -not $y) { return @{ Latitude=$null; Longitude=$null } }
    if (-not $x -or -not $y) { throw 'INVALID_PROVIDER_COORDINATES' }
    $longitude = 0.0
    $latitude = 0.0
    $style = [Globalization.NumberStyles]::Float
    $culture = [Globalization.CultureInfo]::InvariantCulture
    if (-not [double]::TryParse($x, $style, $culture, [ref]$longitude) -or
        -not [double]::TryParse($y, $style, $culture, [ref]$latitude) -or
        [double]::IsNaN($longitude) -or [double]::IsNaN($latitude) -or
        [double]::IsInfinity($longitude) -or [double]::IsInfinity($latitude)) {
        throw 'INVALID_PROVIDER_COORDINATES'
    }
    # API HUB uses WGS84 x/y scaled by 10^7, matching the existing POI adapter.
    # Never guess other coordinate systems or silently turn bad pairs into null/zero.
    $longitude /= 10000000.0
    $latitude /= 10000000.0
    try { Assert-PoiCoordinatePair $latitude $longitude } catch { throw 'INVALID_PROVIDER_COORDINATES' }
    return @{ Latitude=$latitude; Longitude=$longitude }
}

function Get-PoiDiscoveryCandidateKey {
    param([Parameter(Mandatory)]$Candidate)
    # Local Search has no documented stable POI ID. A homepage may be shared by
    # branches. Hash ALL preserved evidence, not just name/link/coordinates. This
    # conservative run-level key merges exact observations only; never a business ID.
    # Length-prefixes avoid delimiter collisions; invariant numbers survive locales.
    $parts = @($Candidate.Provider, $Candidate.OriginalName, $Candidate.RoadAddress,
        $Candidate.LotAddress, $Candidate.Phone, $Candidate.Category, $Candidate.ProviderLink)
    foreach ($coordinate in @($Candidate.Latitude, $Candidate.Longitude)) {
        $parts += $(if ($null -eq $coordinate) { 'null' } else { $coordinate.ToString('R', [Globalization.CultureInfo]::InvariantCulture) })
    }
    $fingerprint = (@($parts | ForEach-Object { ([string]$_).Length.ToString([Globalization.CultureInfo]::InvariantCulture) + ':' + $_ }) -join '')
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($fingerprint)) } finally { $sha.Dispose() }
    return 'naver-local:' + [BitConverter]::ToString($hash).Replace('-', '').ToLowerInvariant()
}

function ConvertTo-PoiDiscoveryCandidate {
    param([Parameter(Mandatory)]$Item, [Parameter(Mandatory)]$Evidence)
    if ($Item -isnot [pscustomobject] -and $Item -isnot [Collections.IDictionary]) { throw 'INVALID_PROVIDER_RESPONSE' }
    $title = ConvertTo-PoiDiscoveryProviderText (Get-PoiDiscoveryProviderField $Item 'title')
    # Remove highlight markup before decoding entities so literal escaped brackets survive.
    $originalName = [Net.WebUtility]::HtmlDecode(($title -replace '<[^>]+>', '')).Trim()
    $coordinates = ConvertTo-PoiDiscoveryCoordinates (Get-PoiDiscoveryProviderField $Item 'mapx') (Get-PoiDiscoveryProviderField $Item 'mapy')
    $candidate = New-PoiCandidate -OriginalName $originalName -NormalizedName (($originalName -replace '[\s,().·&-]', '').ToLowerInvariant()) `
        -RoadAddress (ConvertTo-PoiDiscoveryProviderText (Get-PoiDiscoveryProviderField $Item 'roadAddress')) `
        -LotAddress (ConvertTo-PoiDiscoveryProviderText (Get-PoiDiscoveryProviderField $Item 'address')) `
        -Phone (ConvertTo-PoiDiscoveryProviderText (Get-PoiDiscoveryProviderField $Item 'telephone')) `
        -Category (ConvertTo-PoiDiscoveryProviderText (Get-PoiDiscoveryProviderField $Item 'category')) `
        -ProviderLink (ConvertTo-PoiDiscoveryProviderText (Get-PoiDiscoveryProviderField $Item 'link')) `
        -Latitude $coordinates.Latitude -Longitude $coordinates.Longitude -DiscoveredBy @($Evidence)
    if (-not $candidate.OriginalName -and -not $candidate.RoadAddress -and -not $candidate.LotAddress) { throw 'INVALID_PROVIDER_RESPONSE' }
    $candidate.CandidateKey = Get-PoiDiscoveryCandidateKey $candidate
    Assert-PoiCandidate $candidate
    return $candidate
}

function Invoke-PoiDiscovery {
    <#
    .SYNOPSIS
    Workstream B: discover candidates without approving or writing production data.
    .DESCRIPTION
    Dot-source this library, then call Invoke-PoiDiscovery -Business $normalized.
    Returns ONE PoiDiscoveryBatch containing Candidates[] and QueryAttempts[].
    Uses only the frozen contract; independent of A, C and legacy orchestration.

    Every eligible strategy is exhausted; there is no confidence-based early stop.
    Exact repeated queries are SKIPPED/DUPLICATE_QUERY (no fabricated evidence).
    Empty eligible plan => FAILED, never COMPLETE/no-candidate evidence.
    All executed queries succeed => COMPLETE, including genuine zero results.
    At least one succeeds and at least one fails => PARTIAL; none succeeds => FAILED.
    A malformed response (including any invalid/half coordinate pair) fails the whole
    query atomically. Other successful queries and their evidence are retained.
    No malformed query is represented as a successful zero-result search.

    At most five unique calls per row, five results per call; no automatic retries
    or paging beyond Local Search's supported start=1. COMPLETE means configured
    queries completed, NOT exhaustive provider coverage or a verified business.
    API Calls/Row = count of non-SKIPPED attempts (credentials must be configured).
    Missing credentials fail before any request. Exceptions/bodies/keys are never logged.
    Provider specification: https://api.ncloud-docs.com/docs/naver-api-hub-search-local
    .PARAMETER RequestInvoker
    Optional mock: param($Uri, $Headers), returning the decoded JSON response with
    an items ARRAY. A thrown exception records REQUEST_FAILED. No network in mocks.
    .PARAMETER ClientId
    API HUB client ID. Defaults to NAVER_API_HUB_CLIENT_ID, not Maps credentials.
    .PARAMETER ClientSecret
    API HUB secret. Defaults to NAVER_API_HUB_CLIENT_SECRET. Never written to output.
    #>
    param(
        [Parameter(Mandatory)]$Business,
        [string]$ClientId = $env:NAVER_API_HUB_CLIENT_ID,
        [string]$ClientSecret = $env:NAVER_API_HUB_CLIENT_SECRET,
        [scriptblock]$RequestInvoker
    )
    Assert-NormalizedBusiness $Business
    $plan = @(Get-PoiDiscoveryQueryPlan $Business)
    if ($plan.Count -gt 0 -and $null -eq $RequestInvoker -and
        ([string]::IsNullOrWhiteSpace($ClientId) -or [string]::IsNullOrWhiteSpace($ClientSecret))) {
        throw 'API_HUB_CREDENTIALS_REQUIRED'
    }
    $seenQueries = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $byKey = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $candidates = [Collections.Generic.List[object]]::new()
    $attempts = [Collections.Generic.List[object]]::new()
    $successCount = 0
    $failureCount = 0
    foreach ($entry in $plan) {
        if (-not $seenQueries.Add($entry.Query)) {
            $attempts.Add((New-PoiQueryAttempt -StrategyCode $entry.StrategyCode -Query $entry.Query -QueryOrder $entry.QueryOrder -Status 'SKIPPED' -ErrorCode 'DUPLICATE_QUERY'))
            continue
        }
        $uri = 'https://naverapihub.apigw.ntruss.com/search/v1/local?display=5&start=1&sort=random&format=json&query=' + [Uri]::EscapeDataString($entry.Query)
        $headers = @{ 'X-NCP-APIGW-API-KEY-ID'=$ClientId; 'X-NCP-APIGW-API-KEY'=$ClientSecret }
        $errorCode = ''
        $response = $null
        try {
            $response = if ($null -ne $RequestInvoker) { & $RequestInvoker $uri $headers } else {
                Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -TimeoutSec 20 -MaximumRedirection 0 -ErrorAction Stop
            }
        } catch { $errorCode = 'REQUEST_FAILED' }
        $queryCandidates = [Collections.Generic.List[object]]::new()
        if (-not $errorCode) {
            try {
                if ($null -eq $response -or ($response -isnot [pscustomobject] -and $response -isnot [Collections.IDictionary])) { throw 'INVALID_PROVIDER_RESPONSE' }
                if ($null -ne (Get-PoiDiscoveryProviderField $response 'errorCode') -or $null -ne (Get-PoiDiscoveryProviderField $response 'error')) { throw 'PROVIDER_ERROR' }
                # Preserve arrays, including []: PowerShell functions enumerate return values.
                if ($response -is [Collections.IDictionary]) { $items = $response['items'] } else {
                    $property = $response.PSObject.Properties['items']
                    $items = if ($null -eq $property) { $null } else { ,$property.Value }
                }
                if ($items -isnot [array] -or $items.Count -gt 5) { throw 'INVALID_PROVIDER_RESPONSE' }
                for ($position = 0; $position -lt $items.Count; $position++) {
                    if ($null -eq $items[$position]) { throw 'INVALID_PROVIDER_RESPONSE' }
                    $evidence = New-PoiDiscoveryEvidence -StrategyCode $entry.StrategyCode -Query $entry.Query -QueryOrder $entry.QueryOrder -ResultPosition ($position + 1) -ResultCount $items.Count
                    $queryCandidates.Add((ConvertTo-PoiDiscoveryCandidate -Item $items[$position] -Evidence $evidence))
                }
            } catch {
                $errorCode = if ($_.Exception.Message -in @('INVALID_PROVIDER_COORDINATES','PROVIDER_ERROR')) { $_.Exception.Message } else { 'INVALID_PROVIDER_RESPONSE' }
            }
        }
        if ($errorCode) {
            $failureCount++
            $attempts.Add((New-PoiQueryAttempt -StrategyCode $entry.StrategyCode -Query $entry.Query -QueryOrder $entry.QueryOrder -Status 'FAILED' -ErrorCode $errorCode))
            continue
        }
        $successCount++
        $attempts.Add((New-PoiQueryAttempt -StrategyCode $entry.StrategyCode -Query $entry.Query -QueryOrder $entry.QueryOrder -Status 'SUCCESS' -ResultCount $queryCandidates.Count))
        foreach ($candidate in $queryCandidates) {
            if ($byKey.ContainsKey($candidate.CandidateKey)) {
                $byKey[$candidate.CandidateKey].DiscoveredBy += $candidate.DiscoveredBy
            } else {
                $byKey.Add($candidate.CandidateKey, $candidate)
                $candidates.Add($candidate)
            }
        }
    }
    $status = if ($successCount -eq 0) { 'FAILED' } elseif ($failureCount -gt 0) { 'PARTIAL' } else { 'COMPLETE' }
    $batch = New-PoiDiscoveryBatch -SourceRowNumber $Business.SourceRowNumber -Status $status -Candidates $candidates.ToArray() -QueryAttempts $attempts.ToArray()
    Assert-PoiDiscoveryBatch $batch
    return $batch
}

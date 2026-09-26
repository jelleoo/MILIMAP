Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$benefitLibraryPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'benefit-verification-contracts.ps1'
. $benefitLibraryPath

function Get-BenefitObservationTime { return [DateTime]::UtcNow.ToString('o') }

function Test-BenefitSafeHttpUri {
    param([Parameter(Mandatory)][string]$Url)
    $uri = $null
    if (-not [Uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$uri)) { return $false }
    if ($uri.Scheme -notin @('http', 'https') -or -not [string]::IsNullOrEmpty($uri.UserInfo) -or [string]::IsNullOrWhiteSpace($uri.Host)) { return $false }
    $targetHost = $uri.Host.TrimEnd('.').ToLowerInvariant()
    if ($targetHost -eq 'localhost' -or $targetHost.EndsWith('.localhost') -or $targetHost.EndsWith('.local') -or -not $targetHost.Contains('.')) { return $false }
    $address = $null
    if ([Net.IPAddress]::TryParse($targetHost, [ref]$address)) {
        if ([Net.IPAddress]::IsLoopback($address) -or $address.IsIPv6LinkLocal -or $address.Equals([Net.IPAddress]::IPv6Any)) { return $false }
        $bytes = $address.GetAddressBytes()
        if ($address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork -and ($bytes[0] -eq 0 -or $bytes[0] -eq 10 -or $bytes[0] -eq 127 -or ($bytes[0] -eq 169 -and $bytes[1] -eq 254) -or ($bytes[0] -eq 192 -and $bytes[1] -eq 168) -or ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31))) { return $false }
        if ($address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6 -and (($bytes[0] -band 0xfe) -eq 0xfc)) { return $false }
    }
    return $true
}

function Test-BenefitXlsxBinaryPackage {
    param([AllowNull()][byte[]]$Bytes)
    if ($null -eq $Bytes -or $Bytes.Length -lt 4 -or $Bytes[0] -ne 0x50 -or $Bytes[1] -ne 0x4b -or $Bytes[2] -ne 0x03 -or $Bytes[3] -ne 0x04) { return $false }
    try {
        $stream = [IO.MemoryStream]::new($Bytes, $false)
        try {
            $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Read, $false)
            try {
                $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
                foreach ($entry in $archive.Entries) { [void]$names.Add($entry.FullName) }
                return $names.Contains('[Content_Types].xml') -and $names.Contains('xl/workbook.xml') -and $names.Contains('xl/_rels/workbook.xml.rels')
            } finally { $archive.Dispose() }
        } finally { $stream.Dispose() }
    } catch { return $false }
}

function Get-BenefitSourceFormat {
    param([Parameter(Mandatory)][string]$Url, [string]$ContentType='', [AllowNull()][byte[]]$Bytes=$null)
    $mediaType = ($ContentType -split ';', 2)[0].Trim().ToLowerInvariant()
    if ($mediaType -in @('text/html', 'application/xhtml+xml')) { return 'HTML' }
    if ($mediaType -in @('text/csv', 'application/csv')) { return 'CSV' }
    if ($mediaType -eq 'application/pdf') { return 'PDF' }
    if ($mediaType -in @('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'application/vnd.ms-excel')) { return 'XLSX' }
    if ($mediaType -in @('application/octet-stream', 'application/octer-stream') -and (Test-BenefitXlsxBinaryPackage -Bytes $Bytes)) { return 'XLSX' }
    switch ([IO.Path]::GetExtension(([Uri]$Url).AbsolutePath).ToLowerInvariant()) {
        '.html' { return 'HTML' }; '.htm' { return 'HTML' }; '.csv' { return 'CSV' }; '.xlsx' { return 'XLSX' }; '.pdf' { return 'PDF' }; default { return 'UNSUPPORTED' }
    }
}

function Get-ExistingBenefitSourceCandidate {
    param([Parameter(Mandatory)]$Benefit)
    Assert-CanonicalBenefitRecord $Benefit
    if ([string]::IsNullOrWhiteSpace([string]$Benefit.ExistingSourceUrl)) { return $null }
    $sourceType = ([string]$Benefit.ExistingSourceType).Trim()
    if ($sourceType -match '공식\s*(SNS|블로그)|후기|리뷰') { return $null }
    $sourceKind = if ($sourceType -match '업체\s*공식\s*(홈페이지|웹사이트)|official\s*business\s*website') { 'BUSINESS_WEBSITE' } elseif ($sourceType -match '지자체|정부|공공기관|공공데이터|공식\s*자료') { 'PUBLIC_OFFICIAL' } else { return $null }
    return New-BenefitSourceCandidate -SourceRowNumber $Benefit.SourceRowNumber -Url $Benefit.ExistingSourceUrl -SourceKind $sourceKind -SourceLabel $sourceType -DiscoveryMethod 'EXISTING_CANONICAL_URL' -ObservedAt (Get-BenefitObservationTime)
}

function Invoke-OfficialBenefitSourceDiscovery {
    param([Parameter(Mandatory)]$Benefit, [Parameter(Mandatory)]$Business, [AllowNull()][scriptblock]$DiscoveryInvoker=$null)
    Assert-CanonicalBenefitRecord $Benefit
    Assert-NormalizedBusiness $Business
    if ([int]$Benefit.SourceRowNumber -ne [int]$Business.SourceRowNumber) { throw 'Benefit and Business must preserve the same SourceRowNumber' }
    if ($null -eq $DiscoveryInvoker) { return [pscustomobject][ordered]@{ SourceRowNumber=$Benefit.SourceRowNumber; Status='FAILED'; Candidates=@(); ReasonCodes=@('DISCOVERY_PROVIDER_NOT_CONFIGURED') } }
    try {
        $candidates = @()
        foreach ($record in @(& $DiscoveryInvoker $Benefit $Business)) {
            if ($null -eq $record -or [string]::IsNullOrWhiteSpace([string]$record.Url)) { continue }
            $sourceKind = if ([string]::IsNullOrWhiteSpace([string]$record.SourceKind)) { 'PUBLIC_OFFICIAL' } else { [string]$record.SourceKind }
            $candidate = New-BenefitSourceCandidate -SourceRowNumber $Benefit.SourceRowNumber -Url $record.Url -SourceKind $sourceKind -SourceLabel ([string]$record.SourceLabel) -DiscoveryMethod 'DISCOVERY_INVOKER' -ObservedAt (Get-BenefitObservationTime)
            Assert-BenefitSourceCandidate $candidate
            $candidates += $candidate
        }
        return [pscustomobject][ordered]@{ SourceRowNumber=$Benefit.SourceRowNumber; Status='COMPLETE'; Candidates=@($candidates); ReasonCodes=@() }
    } catch { return [pscustomobject][ordered]@{ SourceRowNumber=$Benefit.SourceRowNumber; Status='FAILED'; Candidates=@(); ReasonCodes=@('DISCOVERY_FAILED') } }
}

function Get-BenefitSourceDocument {
    param([Parameter(Mandatory)]$Candidate, [AllowNull()][scriptblock]$RequestInvoker=$null)
    Assert-BenefitSourceCandidate $Candidate
    if (-not (Test-BenefitSafeHttpUri -Url $Candidate.Url)) { throw "Unsafe source URL: $($Candidate.Url)" }
    try {
        if ($null -eq $RequestInvoker) { throw 'RequestInvoker is not configured' }
        $response = & $RequestInvoker ([Uri]$Candidate.Url)
        if ($null -eq $response -or $response.PSObject.Properties.Name -notcontains 'StatusCode' -or [int]$response.StatusCode -lt 200 -or [int]$response.StatusCode -ge 300) { throw 'Fetch failed' }
        $contentType = if ($response.PSObject.Properties.Name -contains 'ContentType') { [string]$response.ContentType } else { '' }
        $text = if ($response.PSObject.Properties.Name -contains 'Text') { [string]$response.Text } else { '' }
        $bytes = if ($response.PSObject.Properties.Name -contains 'Bytes') { $response.Bytes } else { $null }
        return New-BenefitSourceDocument -SourceRowNumber $Candidate.SourceRowNumber -Url $Candidate.Url -SourceFormat (Get-BenefitSourceFormat -Url $Candidate.Url -ContentType $contentType -Bytes $bytes) -FetchStatus 'COMPLETE' -ContentType $contentType -Text $text -Bytes $bytes -ObservedAt (Get-BenefitObservationTime)
    } catch {
        return New-BenefitSourceDocument -SourceRowNumber $Candidate.SourceRowNumber -Url $Candidate.Url -SourceFormat 'UNSUPPORTED' -FetchStatus 'FAILED' -ObservedAt (Get-BenefitObservationTime) -ReasonCodes @('SOURCE_FETCH_FAILED')
    }
}

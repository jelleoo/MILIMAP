Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Command Test-BenefitSafeHttpUri -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'discover-official-benefit-sources.ps1')
}

function ConvertTo-BenefitSafeCsvCell {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrEmpty($Value)) { return '' }
    if ($Value -match '^[\s]*[=+\-@]' -or $Value[0] -eq "`t" -or $Value[0] -eq "`r" -or $Value[0] -eq "`n") {
        return "'" + $Value
    }
    return $Value
}

function ConvertTo-BenefitSafeCsvRows {
    param([AllowEmptyCollection()][object[]]$Rows)

    $safe = [Collections.Generic.List[object]]::new()
    foreach ($row in @($Rows)) {
        if ($null -eq $row) { continue }
        $ordered = [ordered]@{}
        foreach ($prop in $row.PSObject.Properties) {
            $rawVal = if ($null -eq $prop.Value) { '' } else { [string]$prop.Value }
            $ordered[$prop.Name] = ConvertTo-BenefitSafeCsvCell -Value $rawVal
        }
        $safe.Add([pscustomobject]$ordered)
    }
    return @($safe)
}

function Format-BenefitSafeMarkdownCell {
    param(
        [AllowNull()][string]$Value,
        [int]$MaxLength = 500
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return '-' }
    $sanitized = ($Value -replace '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', '')
    $sanitized = ($sanitized -replace '[\r\n]+', ' ').Trim()
    $sanitized = $sanitized.
        Replace('&', '&amp;').
        Replace('<', '&lt;').
        Replace('>', '&gt;').
        Replace('|', '\|').
        Replace('`', '\`').
        Replace('[', '\[').
        Replace(']', '\]').
        Replace('(', '\(').
        Replace(')', '\)')
    if ($MaxLength -gt 3 -and $sanitized.Length -gt $MaxLength) {
        $sanitized = $sanitized.Substring(0, $MaxLength - 3) + '...'
    }
    return $sanitized
}

function Invoke-BenefitBoundedHttpsGet {
    param(
        [Parameter(Mandatory)][uri]$Uri,
        [hashtable]$Headers = @{ 'User-Agent' = 'MILIMAP-Phase5-EvidenceVerifier/1.0' },
        [int]$TimeoutSeconds = 30,
        [int]$MaxResponseBytes = 20MB,
        [int]$MaximumRedirection = 0,
        [string]$ErrorPrefix = 'BOUNDED_HTTP'
    )

    if (-not $Uri.IsAbsoluteUri -or $Uri.Scheme -cne 'https' -or -not (Test-BenefitSafeHttpUri -Url $Uri.AbsoluteUri)) {
        throw "${ErrorPrefix}_URL_UNSAFE: $($Uri.OriginalString)"
    }
    if ($MaximumRedirection -lt 0) { $MaximumRedirection = 0 }
    if ($MaxResponseBytes -lt 1) {
        throw "${ErrorPrefix}_INVALID_LIMIT: MaxResponseBytes must be positive."
    }

    $webCmd = Get-Command Invoke-WebRequest -ErrorAction SilentlyContinue
    if ($null -ne $webCmd -and $webCmd.CommandType -eq [Management.Automation.CommandTypes]::Function) {
        $resp = Invoke-WebRequest -Uri $Uri -Headers $Headers -MaximumRedirection $MaximumRedirection -TimeoutSec $TimeoutSeconds
        if ([int]$resp.StatusCode -ne 200) {
            throw "${ErrorPrefix}_HTTP_FAILED: HTTP status $($resp.StatusCode)"
        }
        $rawStreamProp = $resp.PSObject.Properties['RawContentStream']
        [byte[]]$bytes = if ($resp.Content -is [byte[]]) {
            [byte[]]$resp.Content
        } elseif ($null -ne $rawStreamProp -and $null -ne $rawStreamProp.Value -and $rawStreamProp.Value.Length -gt 0) {
            if ($rawStreamProp.Value.Length -gt $MaxResponseBytes) {
                throw "${ErrorPrefix}_RESPONSE_TOO_LARGE: $($rawStreamProp.Value.Length) bytes"
            }
            $rawStreamProp.Value.Position = 0
            $ms = [IO.MemoryStream]::new()
            try {
                $rawStreamProp.Value.CopyTo($ms)
                $ms.ToArray()
            } finally {
                $ms.Dispose()
            }
        } else {
            [Text.Encoding]::UTF8.GetBytes([string]$resp.Content)
        }
        if ($bytes.Length -gt $MaxResponseBytes) {
            throw "${ErrorPrefix}_RESPONSE_TOO_LARGE: $($bytes.Length) bytes"
        }
        $text = if ($resp.Content -is [string] -and -not ($resp.Content -is [byte[]])) {
            [string]$resp.Content
        } else {
            [Text.Encoding]::UTF8.GetString($bytes)
        }
        return [pscustomobject][ordered]@{
            StatusCode = [int]$resp.StatusCode
            Content = $resp.Content
            Bytes = $bytes
            Text = $text
        }
    }

    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = ($MaximumRedirection -gt 0)
    if ($MaximumRedirection -gt 0) {
        $handler.MaxAutomaticRedirections = $MaximumRedirection
    }
    $client = [Net.Http.HttpClient]::new($handler, $true)
    $client.Timeout = [TimeSpan]::FromSeconds([Math]::Max(1, $TimeoutSeconds))
    try {
        $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get, $Uri)
        if ($null -ne $Headers) {
            foreach ($entry in $Headers.GetEnumerator()) {
                [void]$request.Headers.TryAddWithoutValidation([string]$entry.Key, [string]$entry.Value)
            }
        }
        try {
            $response = $client.Send($request, [Net.Http.HttpCompletionOption]::ResponseHeadersRead)
            try {
                $statusCode = [int]$response.StatusCode
                if ($statusCode -ne 200) {
                    throw "${ErrorPrefix}_HTTP_FAILED: HTTP status $statusCode"
                }
                if ($null -ne $response.Content -and $null -ne $response.Content.Headers.ContentLength -and $response.Content.Headers.ContentLength -gt $MaxResponseBytes) {
                    throw "${ErrorPrefix}_RESPONSE_TOO_LARGE: $($response.Content.Headers.ContentLength) bytes"
                }
                $stream = $response.Content.ReadAsStream()
                $memory = [IO.MemoryStream]::new()
                try {
                    $buffer = [byte[]]::new(16384)
                    $totalRead = 0L
                    while ($true) {
                        $read = $stream.Read($buffer, 0, $buffer.Length)
                        if ($read -le 0) { break }
                        $totalRead += $read
                        if ($totalRead -gt $MaxResponseBytes) {
                            throw "${ErrorPrefix}_RESPONSE_TOO_LARGE: $totalRead bytes"
                        }
                        $memory.Write($buffer, 0, $read)
                    }
                    $bytes = $memory.ToArray()
                    $text = [Text.Encoding]::UTF8.GetString($bytes)
                    return [pscustomobject][ordered]@{
                        StatusCode = $statusCode
                        Content = $bytes
                        Bytes = $bytes
                        Text = $text
                    }
                } finally {
                    $memory.Dispose()
                    $stream.Dispose()
                }
            } finally {
                $response.Dispose()
            }
        } finally {
            $request.Dispose()
        }
    } finally {
        $client.Dispose()
    }
}

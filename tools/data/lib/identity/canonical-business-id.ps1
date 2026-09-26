Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-CanonicalBusinessId {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return [bool]($Value -cmatch '^biz-[0-9a-f]{32}$')
}

function Assert-CanonicalBusinessId {
    param([AllowNull()][string]$Value)

    if (-not (Test-CanonicalBusinessId -Value $Value)) {
        throw "Invalid canonical businessId: '$Value'"
    }
}

function Assert-CanonicalBusinessIds {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rows)

    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($row in @($Rows)) {
        if ($null -eq $row -or $row.PSObject.Properties.Name -notcontains 'businessId') {
            throw 'Canonical row is missing businessId'
        }
        $id = [string]$row.businessId
        Assert-CanonicalBusinessId -Value $id
        if (-not $seen.Add($id)) {
            throw "Duplicate canonical businessId: $id"
        }
    }
}

function New-CanonicalBusinessId {
    return 'biz-' + [Guid]::NewGuid().ToString('N')
}

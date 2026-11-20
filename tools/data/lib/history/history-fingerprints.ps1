Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'history-contracts.ps1')

$script:HistoryHasNewtonsoftJson = $null -ne ('Newtonsoft.Json.JsonConvert' -as [type])

function ConvertTo-HistoryJsonString {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    if ($script:HistoryHasNewtonsoftJson) {
        return [Newtonsoft.Json.JsonConvert]::ToString([string]$Value)
    }
    return ConvertTo-Json -InputObject ([string]$Value) -Compress
}

function Write-HistoryCanonicalNode {
    param(
        [AllowNull()]$Value,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.HashSet[string]]$OrderInsensitive,
        [Parameter(Mandatory)][Text.StringBuilder]$Builder,
        [string]$Path=''
    )

    if ($null -eq $Value) { [void]$Builder.Append('null'); return }
    if ($Value -is [string] -or $Value -is [char]) { [void]$Builder.Append((ConvertTo-HistoryJsonString ([string]$Value))); return }
    if ($Value -is [bool]) { [void]$Builder.Append($(if ([bool]$Value) { 'true' } else { 'false' })); return }

    if ($Value -is [byte] -or $Value -is [sbyte] -or
        $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64] -or
        $Value -is [decimal]) {
        [void]$Builder.Append(([IFormattable]$Value).ToString($null,[Globalization.CultureInfo]::InvariantCulture))
        return
    }
    if ($Value -is [double]) {
        if ([double]::IsNaN([double]$Value) -or [double]::IsInfinity([double]$Value)) { throw 'Non-finite double is not supported in history serialization' }
        [void]$Builder.Append(([double]$Value).ToString('R',[Globalization.CultureInfo]::InvariantCulture))
        return
    }
    if ($Value -is [single]) {
        if ([single]::IsNaN([single]$Value) -or [single]::IsInfinity([single]$Value)) { throw 'Non-finite float is not supported in history serialization' }
        [void]$Builder.Append(([single]$Value).ToString('R',[Globalization.CultureInfo]::InvariantCulture))
        return
    }

    if ($Value -is [Collections.IDictionary]) {
        $keys = [Collections.Generic.List[string]]::new($Value.Count)
        foreach ($rawKey in $Value.Keys) {
            if ($rawKey -isnot [string]) { throw 'History object dictionary keys must be strings' }
            $keys.Add([string]$rawKey)
        }
        $keys.Sort([StringComparer]::CurrentCulture)
        [void]$Builder.Append('{')
        $first = $true
        foreach ($key in $keys) {
            if ($first) { $first = $false } else { [void]$Builder.Append(',') }
            [void]$Builder.Append((ConvertTo-HistoryJsonString $key))
            [void]$Builder.Append(':')
            $childPath = if ([string]::IsNullOrEmpty($Path)) { $key } else { $Path + '.' + $key }
            Write-HistoryCanonicalNode -Value $Value[$key] -OrderInsensitive $OrderInsensitive -Builder $Builder -Path $childPath
        }
        [void]$Builder.Append('}')
        return
    }

    if ($Value -is [Collections.IEnumerable] -and $Value -isnot [string]) {
        [void]$Builder.Append('[')
        $childPath = $Path + '[]'
        if ($OrderInsensitive.Contains($Path)) {
            $items = [Collections.Generic.List[string]]::new()
            foreach ($item in $Value) {
                $itemBuilder = [Text.StringBuilder]::new()
                Write-HistoryCanonicalNode -Value $item -OrderInsensitive $OrderInsensitive -Builder $itemBuilder -Path $childPath
                $items.Add($itemBuilder.ToString())
            }
            $items.Sort([StringComparer]::CurrentCulture)
            for ($i = 0; $i -lt $items.Count; $i++) {
                if ($i -gt 0) { [void]$Builder.Append(',') }
                [void]$Builder.Append($items[$i])
            }
        } else {
            $first = $true
            foreach ($item in $Value) {
                if ($first) { $first = $false } else { [void]$Builder.Append(',') }
                Write-HistoryCanonicalNode -Value $item -OrderInsensitive $OrderInsensitive -Builder $Builder -Path $childPath
            }
        }
        [void]$Builder.Append(']')
        return
    }

    if ($Value -is [pscustomobject]) {
        $names = [Collections.Generic.List[string]]::new()
        foreach ($prop in $Value.PSObject.Properties) {
            $memberType = [string]$prop.MemberType
            if ($memberType -ceq 'NoteProperty' -or $memberType -ceq 'Property' -or $memberType -ceq 'AliasProperty' -or $memberType -ceq 'ScriptProperty') {
                $names.Add([string]$prop.Name)
            }
        }
        $names.Sort([StringComparer]::CurrentCulture)
        [void]$Builder.Append('{')
        $first = $true
        foreach ($name in $names) {
            if ($first) { $first = $false } else { [void]$Builder.Append(',') }
            [void]$Builder.Append((ConvertTo-HistoryJsonString $name))
            [void]$Builder.Append(':')
            $childPath = if ([string]::IsNullOrEmpty($Path)) { $name } else { $Path + '.' + $name }
            Write-HistoryCanonicalNode -Value $Value.$name -OrderInsensitive $OrderInsensitive -Builder $Builder -Path $childPath
        }
        [void]$Builder.Append('}')
        return
    }

    throw ('Unsupported history serialization type: ' + $Value.GetType().FullName)
}

function ConvertTo-HistoryCanonicalNode {
    param(
        [AllowNull()]$Value,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.HashSet[string]]$OrderInsensitive,
        [string]$Path=''
    )
    $builder = [Text.StringBuilder]::new(256)
    Write-HistoryCanonicalNode -Value $Value -OrderInsensitive $OrderInsensitive -Builder $builder -Path $Path
    return $builder.ToString()
}

function ConvertTo-HistoryCanonicalJson {
    param(
        [Parameter(Mandatory)][AllowNull()]$Value,
        [string[]]$OrderInsensitivePaths=@()
    )
    $set = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($path in @($OrderInsensitivePaths)) {
        if ([string]::IsNullOrWhiteSpace([string]$path)) { throw 'Order-insensitive path cannot be blank' }
        [void]$set.Add([string]$path)
    }
    $builder = [Text.StringBuilder]::new(512)
    Write-HistoryCanonicalNode -Value $Value -OrderInsensitive $set -Builder $builder
    return $builder.ToString()
}

function Get-HistorySha256 {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
        return ([BitConverter]::ToString($hash) -replace '-','').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-HistoryFingerprint {
    param(
        [Parameter(Mandatory)]$Projection,
        [int]$SchemaVersion=1,
        [string[]]$OrderInsensitivePaths=@()
    )
    if ($SchemaVersion -lt 1) { throw 'Fingerprint schema version must be positive' }
    $material = [pscustomobject][ordered]@{
        SchemaVersion=$SchemaVersion
        Projection=$Projection
    }
    return Get-HistorySha256 -Text (ConvertTo-HistoryCanonicalJson -Value $material -OrderInsensitivePaths @($OrderInsensitivePaths | ForEach-Object { 'Projection.' + $_ }))
}

function New-HistoryFingerprintSet {
    param(
        [Parameter(Mandatory)]$InputProjection,
        [Parameter(Mandatory)]$EvidenceProjection,
        [Parameter(Mandatory)]$SemanticProjection,
        [Parameter(Mandatory)]$ExecutionProjection,
        [int]$SchemaVersion=1,
        [string[]]$InputOrderInsensitivePaths=@(),
        [string[]]$EvidenceOrderInsensitivePaths=@(),
        [string[]]$SemanticOrderInsensitivePaths=@(),
        [string[]]$ExecutionOrderInsensitivePaths=@()
    )
    return [pscustomobject][ordered]@{
        InputFingerprint=Get-HistoryFingerprint -Projection $InputProjection -SchemaVersion $SchemaVersion -OrderInsensitivePaths $InputOrderInsensitivePaths
        EvidenceFingerprint=Get-HistoryFingerprint -Projection $EvidenceProjection -SchemaVersion $SchemaVersion -OrderInsensitivePaths $EvidenceOrderInsensitivePaths
        SemanticFingerprint=Get-HistoryFingerprint -Projection $SemanticProjection -SchemaVersion $SchemaVersion -OrderInsensitivePaths $SemanticOrderInsensitivePaths
        ExecutionFingerprint=Get-HistoryFingerprint -Projection $ExecutionProjection -SchemaVersion $SchemaVersion -OrderInsensitivePaths $ExecutionOrderInsensitivePaths
    }
}

function Get-HistoryDeltaDimensions {
    param(
        [Parameter(Mandatory)]$Previous,
        [Parameter(Mandatory)]$Current
    )
    Assert-HistoryObservation $Previous
    Assert-HistoryObservation $Current
    $result = [Collections.Generic.List[string]]::new()
    if ([string]$Previous.InputFingerprint -cne [string]$Current.InputFingerprint) { $result.Add('INPUT') }
    if ([string]$Previous.EvidenceFingerprint -cne [string]$Current.EvidenceFingerprint) { $result.Add('EVIDENCE') }
    if ([string]$Previous.SemanticFingerprint -cne [string]$Current.SemanticFingerprint) { $result.Add('SEMANTIC') }
    if ([string]$Previous.ExecutionFingerprint -cne [string]$Current.ExecutionFingerprint) { $result.Add('EXECUTION') }
    return @($result)
}

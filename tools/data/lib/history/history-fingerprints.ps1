Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'history-contracts.ps1')

function ConvertTo-HistoryJsonString {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    return ConvertTo-Json -InputObject ([string]$Value) -Compress
}

function ConvertTo-HistoryCanonicalNode {
    param(
        [AllowNull()]$Value,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.HashSet[string]]$OrderInsensitive,
        [string]$Path=''
    )

    if ($null -eq $Value) { return 'null' }
    if ($Value -is [string] -or $Value -is [char]) { return ConvertTo-HistoryJsonString ([string]$Value) }
    if ($Value -is [bool]) { return $(if ([bool]$Value) { 'true' } else { 'false' }) }

    if ($Value -is [byte] -or $Value -is [sbyte] -or
        $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64] -or
        $Value -is [decimal]) {
        return ([IFormattable]$Value).ToString($null,[Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Value -is [double]) {
        if ([double]::IsNaN([double]$Value) -or [double]::IsInfinity([double]$Value)) { throw 'Non-finite double is not supported in history serialization' }
        return ([double]$Value).ToString('R',[Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Value -is [single]) {
        if ([single]::IsNaN([single]$Value) -or [single]::IsInfinity([single]$Value)) { throw 'Non-finite float is not supported in history serialization' }
        return ([single]$Value).ToString('R',[Globalization.CultureInfo]::InvariantCulture)
    }

    if ($Value -is [Collections.IDictionary]) {
        $keys = @($Value.Keys | ForEach-Object {
            if ($_ -isnot [string]) { throw 'History object dictionary keys must be strings' }
            [string]$_
        } | Sort-Object -CaseSensitive)
        $parts = [Collections.Generic.List[string]]::new()
        foreach ($key in $keys) {
            $childPath = if ([string]::IsNullOrEmpty($Path)) { $key } else { $Path + '.' + $key }
            $parts.Add((ConvertTo-HistoryJsonString $key) + ':' + (ConvertTo-HistoryCanonicalNode -Value $Value[$key] -OrderInsensitive $OrderInsensitive -Path $childPath))
        }
        return '{' + ($parts -join ',') + '}'
    }

    if ($Value -is [Collections.IEnumerable] -and $Value -isnot [string]) {
        $parts = @($Value | ForEach-Object {
            ConvertTo-HistoryCanonicalNode -Value $_ -OrderInsensitive $OrderInsensitive -Path ($Path + '[]')
        })
        if ($OrderInsensitive.Contains($Path)) {
            $parts = @($parts | Sort-Object -CaseSensitive)
        }
        return '[' + ($parts -join ',') + ']'
    }

    if ($Value -is [pscustomobject]) {
        $names = @($Value.PSObject.Properties | Where-Object { $_.MemberType -in @('NoteProperty','Property','AliasProperty','ScriptProperty') } | ForEach-Object { [string]$_.Name } | Sort-Object -CaseSensitive)
        $parts = [Collections.Generic.List[string]]::new()
        foreach ($name in $names) {
            $childPath = if ([string]::IsNullOrEmpty($Path)) { $name } else { $Path + '.' + $name }
            $parts.Add((ConvertTo-HistoryJsonString $name) + ':' + (ConvertTo-HistoryCanonicalNode -Value $Value.$name -OrderInsensitive $OrderInsensitive -Path $childPath))
        }
        return '{' + ($parts -join ',') + '}'
    }

    throw ('Unsupported history serialization type: ' + $Value.GetType().FullName)
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
    return ConvertTo-HistoryCanonicalNode -Value $Value -OrderInsensitive $set
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

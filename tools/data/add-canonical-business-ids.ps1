[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputCsv,
    [Parameter(Mandatory = $true)]
    [string]$OutputCsv
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/identity/canonical-business-id.ps1')

function Assert-CanonicalMigrationRoundTrip {
    param(
        [Parameter(Mandatory)][object[]]$BeforeRows,
        [Parameter(Mandatory)][object[]]$AfterRows,
        [Parameter(Mandatory)][string[]]$OriginalPropertyNames
    )

    if ($AfterRows.Count -ne $BeforeRows.Count) {
        throw 'Canonical businessId migration changed row count'
    }

    Assert-CanonicalBusinessIds -Rows $AfterRows

    for ($index = 0; $index -lt $BeforeRows.Count; $index++) {
        foreach ($name in $OriginalPropertyNames) {
            if ($name -ceq 'businessId') { continue }
            $beforeProperty = $BeforeRows[$index].PSObject.Properties[$name]
            $afterProperty = $AfterRows[$index].PSObject.Properties[$name]
            if ($null -eq $afterProperty) {
                throw "Canonical businessId migration removed property: $name"
            }
            $beforeValue = if ($null -eq $beforeProperty -or $null -eq $beforeProperty.Value) { '' } else { [string]$beforeProperty.Value }
            $afterValue = if ($null -eq $afterProperty.Value) { '' } else { [string]$afterProperty.Value }
            if ($beforeValue -cne $afterValue) {
                throw "Canonical businessId migration changed property '$name' on row $($index + 1)"
            }
        }
    }
}

function Invoke-CanonicalBusinessIdMigration {
    param(
        [Parameter(Mandatory)][string]$InputCsv,
        [Parameter(Mandatory)][string]$OutputCsv
    )

    $resolvedInput = [IO.Path]::GetFullPath($InputCsv)
    $resolvedOutput = [IO.Path]::GetFullPath($OutputCsv)
    if ($resolvedInput.Equals($resolvedOutput, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'InputCsv and OutputCsv must be different paths'
    }
    if (-not (Test-Path -LiteralPath $resolvedInput -PathType Leaf)) {
        throw "InputCsv does not exist: $resolvedInput"
    }

    $rows = @(Import-Csv -LiteralPath $resolvedInput -Encoding utf8)
    if ($rows.Count -eq 0) {
        throw 'Canonical businessId migration requires at least one data row'
    }

    $originalPropertyNames = @($rows[0].PSObject.Properties.Name)
    foreach ($row in $rows) {
        $rowPropertyNames = @($row.PSObject.Properties.Name)
        if ($rowPropertyNames.Count -ne $originalPropertyNames.Count) {
            throw 'Canonical rows do not share one schema'
        }
        for ($index = 0; $index -lt $originalPropertyNames.Count; $index++) {
            if ($rowPropertyNames[$index] -cne $originalPropertyNames[$index]) {
                throw 'Canonical rows do not share one ordered schema'
            }
        }
    }

    $idValues = @($rows | ForEach-Object {
        $property = $_.PSObject.Properties['businessId']
        if ($null -eq $property -or $null -eq $property.Value) { '' } else { ([string]$property.Value).Trim() }
    })
    $presentCount = @($idValues | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
    if ($presentCount -gt 0 -and $presentCount -lt $rows.Count) {
        throw 'Canonical businessId migration rejects mixed present and missing IDs'
    }

    $assignIds = $presentCount -eq 0
    if (-not $assignIds) {
        Assert-CanonicalBusinessIds -Rows $rows
    }

    $outputRows = [Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $rows.Count; $index++) {
        $record = [ordered]@{}
        $record['businessId'] = if ($assignIds) { New-CanonicalBusinessId } else { [string]$rows[$index].businessId }
        foreach ($property in $rows[$index].PSObject.Properties) {
            if ($property.Name -ceq 'businessId') { continue }
            $record[$property.Name] = $property.Value
        }
        $outputRows.Add([pscustomobject]$record)
    }
    Assert-CanonicalBusinessIds -Rows $outputRows.ToArray()

    $outputDirectory = Split-Path -Parent $resolvedOutput
    if ([string]::IsNullOrWhiteSpace($outputDirectory)) {
        throw 'OutputCsv must resolve to a directory'
    }
    New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

    $tempPath = Join-Path $outputDirectory ('.' + [IO.Path]::GetFileName($resolvedOutput) + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $outputRows.ToArray() | Export-Csv -LiteralPath $tempPath -NoTypeInformation -Encoding utf8
        $roundTripRows = @(Import-Csv -LiteralPath $tempPath -Encoding utf8)
        Assert-CanonicalMigrationRoundTrip -BeforeRows $rows -AfterRows $roundTripRows -OriginalPropertyNames $originalPropertyNames

        [IO.File]::Move($tempPath, $resolvedOutput, $true)
    } finally {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }

    return [pscustomobject][ordered]@{
        Rows=$rows.Count
        AssignedCount=$(if ($assignIds) { $rows.Count } else { 0 })
        PreservedCount=$(if ($assignIds) { 0 } else { $rows.Count })
        Validated=$true
    }
}

Invoke-CanonicalBusinessIdMigration -InputCsv $InputCsv -OutputCsv $OutputCsv

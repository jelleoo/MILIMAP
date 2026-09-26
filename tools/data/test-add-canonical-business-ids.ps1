$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot 'add-canonical-business-ids.ps1'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
function Assert-Equal {
    param([AllowNull()]$Actual, [AllowNull()]$Expected, [string]$Message)
    if ($Actual -ne $Expected) { throw "$Message (expected: $Expected, actual: $Actual)" }
}
function Assert-Throws {
    param([scriptblock]$Action, [string]$Message)
    $threw = $false
    try { & $Action } catch { $threw = $true }
    if (-not $threw) { throw $Message }
}

$root = Join-Path ([IO.Path]::GetTempPath()) ('milimap-business-id-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $root | Out-Null
try {
    $input = Join-Path $root 'input.csv'
    $output = Join-Path $root 'output.csv'

    $rows = @(
        [pscustomobject][ordered]@{ 업소명='쉼표,가게'; 비고='따옴표 "유지"'; 할인정보=('첫 줄' + [Environment]::NewLine + '둘째 줄') },
        [pscustomobject][ordered]@{ 업소명='일반가게'; 비고=''; 할인정보='10% 할인' }
    )
    $rows | Export-Csv -LiteralPath $input -NoTypeInformation -Encoding utf8

    $summary = & $scriptPath -InputCsv $input -OutputCsv $output
    $before = @(Import-Csv -LiteralPath $input -Encoding utf8)
    $after = @(Import-Csv -LiteralPath $output -Encoding utf8)

    Assert-Equal $after.Count $before.Count 'Migration must preserve row count'
    Assert-Equal $summary.Rows $before.Count 'Summary Rows must match migrated row count'
    Assert-Equal $summary.AssignedCount $before.Count 'All missing IDs must be assigned'
    Assert-Equal $summary.PreservedCount 0 'No IDs are preserved in an unmigrated file'
    Assert-True ([bool]$summary.Validated) 'Migration summary must confirm validation'
    Assert-Equal $after[0].PSObject.Properties[0].Name 'businessId' 'businessId must be the first column'

    for ($i = 0; $i -lt $before.Count; $i++) {
        Assert-True ([string]$after[$i].businessId -cmatch '^biz-[0-9a-f]{32}$') 'Each row must receive a valid ID'
        foreach ($property in $before[$i].PSObject.Properties) {
            Assert-Equal ([string]$after[$i].($property.Name)) ([string]$property.Value) "Original field '$($property.Name)' must round-trip unchanged"
        }
    }
    Assert-True ([string]$after[0].businessId -cne [string]$after[1].businessId) 'Assigned IDs must be unique'

    $preserveInput = Join-Path $root 'preserve.csv'
    $preserveOutput = Join-Path $root 'preserve-output.csv'
    @(
        [pscustomobject][ordered]@{ businessId='biz-00000000000000000000000000000001'; 업소명='A' },
        [pscustomobject][ordered]@{ businessId='biz-00000000000000000000000000000002'; 업소명='B' }
    ) | Export-Csv -LiteralPath $preserveInput -NoTypeInformation -Encoding utf8
    $preserveSummary = & $scriptPath -InputCsv $preserveInput -OutputCsv $preserveOutput
    $preserved = @(Import-Csv -LiteralPath $preserveOutput -Encoding utf8)
    Assert-Equal $preserveSummary.AssignedCount 0 'Already migrated file must issue no new IDs'
    Assert-Equal $preserveSummary.PreservedCount 2 'Already migrated IDs must be preserved'
    Assert-Equal $preserved[0].businessId 'biz-00000000000000000000000000000001' 'First existing ID must be preserved'
    Assert-Equal $preserved[1].businessId 'biz-00000000000000000000000000000002' 'Second existing ID must be preserved'

    $mixed = Join-Path $root 'mixed.csv'
    @(
        [pscustomobject][ordered]@{ businessId='biz-00000000000000000000000000000003'; 업소명='A' },
        [pscustomobject][ordered]@{ businessId=''; 업소명='B' }
    ) | Export-Csv -LiteralPath $mixed -NoTypeInformation -Encoding utf8
    Assert-Throws { & $scriptPath -InputCsv $mixed -OutputCsv (Join-Path $root 'mixed-output.csv') } 'Mixed present/missing IDs must fail closed'

    $invalid = Join-Path $root 'invalid.csv'
    @([pscustomobject][ordered]@{ businessId='biz-ABC'; 업소명='A' }) | Export-Csv -LiteralPath $invalid -NoTypeInformation -Encoding utf8
    Assert-Throws { & $scriptPath -InputCsv $invalid -OutputCsv (Join-Path $root 'invalid-output.csv') } 'Malformed existing IDs must fail'

    $duplicate = Join-Path $root 'duplicate.csv'
    @(
        [pscustomobject][ordered]@{ businessId='biz-00000000000000000000000000000004'; 업소명='A' },
        [pscustomobject][ordered]@{ businessId='biz-00000000000000000000000000000004'; 업소명='B' }
    ) | Export-Csv -LiteralPath $duplicate -NoTypeInformation -Encoding utf8
    Assert-Throws { & $scriptPath -InputCsv $duplicate -OutputCsv (Join-Path $root 'duplicate-output.csv') } 'Duplicate existing IDs must fail'

    Assert-Throws { & $scriptPath -InputCsv $input -OutputCsv $input } 'Input and output paths must be distinct'

    $inputBytesBefore = [IO.File]::ReadAllBytes($input)
    Assert-Throws { & $scriptPath -InputCsv $mixed -OutputCsv (Join-Path $root 'failed-output.csv') } 'Validation failure must throw'
    $inputBytesAfter = [IO.File]::ReadAllBytes($input)
    Assert-Equal ([Convert]::ToBase64String($inputBytesAfter)) ([Convert]::ToBase64String($inputBytesBefore)) 'A failed migration must not modify the original input'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'Canonical business ID migration tests passed.'

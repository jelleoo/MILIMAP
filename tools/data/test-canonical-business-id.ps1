$ErrorActionPreference = 'Stop'

$libraryPath = Join-Path $PSScriptRoot 'lib/identity/canonical-business-id.ps1'
. $libraryPath

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
function Assert-False {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { throw $Message }
}
function Assert-Throws {
    param([scriptblock]$Action, [string]$Message)
    $threw = $false
    try { & $Action } catch { $threw = $true }
    if (-not $threw) { throw $Message }
}

$valid = 'biz-0123456789abcdef0123456789abcdef'
Assert-True (Test-CanonicalBusinessId -Value $valid) 'Valid businessId must be accepted'
Assert-False (Test-CanonicalBusinessId -Value '') 'Blank businessId must be rejected'
Assert-False (Test-CanonicalBusinessId -Value 'biz-0123456789ABCDEF0123456789ABCDEF') 'Uppercase hex must be rejected'
Assert-False (Test-CanonicalBusinessId -Value 'business-0123456789abcdef0123456789abcdef') 'Wrong prefix must be rejected'
Assert-False (Test-CanonicalBusinessId -Value 'biz-0123456789abcdef') 'Wrong length must be rejected'
Assert-Throws { Assert-CanonicalBusinessId -Value '' } 'Assert-CanonicalBusinessId must reject blank values'

$rows = @(
    [pscustomobject]@{ businessId='biz-00000000000000000000000000000001' },
    [pscustomobject]@{ businessId='biz-00000000000000000000000000000001' }
)
Assert-Throws { Assert-CanonicalBusinessIds -Rows $rows } 'Duplicate business IDs must be rejected'

$id1 = New-CanonicalBusinessId
$id2 = New-CanonicalBusinessId
Assert-True ($id1 -cmatch '^biz-[0-9a-f]{32}$') 'Generated ID must match exact format'
Assert-True ($id2 -cmatch '^biz-[0-9a-f]{32}$') 'Second generated ID must match exact format'
Assert-True ($id1 -cne $id2) 'Two generated IDs must differ'

Write-Host 'Canonical business ID contract tests passed.'

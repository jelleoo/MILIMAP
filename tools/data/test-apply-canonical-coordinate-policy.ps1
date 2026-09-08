$ErrorActionPreference = 'Stop'

function Assert-Equal {
    param(
        [AllowNull()]$Actual,
        [AllowNull()]$Expected,
        [Parameter(Mandatory)][string]$Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message (expected: $Expected, actual: $Actual)"
    }
}

$fixtureRoot = Join-Path $PSScriptRoot 'testdata\canonical-coordinate-policy'
$outputPath = Join-Path ([IO.Path]::GetTempPath()) ('benefits-coordinate-policy-' + [guid]::NewGuid().ToString('N') + '.json')
$scriptPath = Join-Path $PSScriptRoot 'apply-canonical-coordinate-policy.ps1'

& $scriptPath `
    -CanonicalCsv (Join-Path $fixtureRoot 'canonical.csv') `
    -SourceJson (Join-Path $fixtureRoot 'benefits.seed.json') `
    -DestinationJson $outputPath

$items = @(Get-Content -Raw -Encoding utf8 $outputPath | ConvertFrom-Json)
Assert-Equal -Actual $items.Count -Expected 3 -Message '모든 시드 행을 보존해야 합니다'

$confirmed = @($items | Where-Object { $_.id -eq 'confirmed' })[0]
Assert-Equal -Actual $confirmed.latitude -Expected 37.5 -Message '확인 완료 좌표는 유지해야 합니다'
Assert-Equal -Actual $confirmed.longitude -Expected 127.0 -Message '확인 완료 좌표는 유지해야 합니다'

$recheck = @($items | Where-Object { $_.id -eq 'recheck' })[0]
Assert-Equal -Actual $recheck.latitude -Expected $null -Message '재확인 필요 좌표의 위도는 출시 시드에서 비워야 합니다'
Assert-Equal -Actual $recheck.longitude -Expected $null -Message '재확인 필요 좌표의 경도는 출시 시드에서 비워야 합니다'

$unverified = @($items | Where-Object { $_.id -eq 'unverified' })[0]
Assert-Equal -Actual $unverified.latitude -Expected $null -Message '미확인 좌표의 위도는 비워 둬야 합니다'
Assert-Equal -Actual $unverified.longitude -Expected $null -Message '미확인 좌표의 경도는 비워 둬야 합니다'

Remove-Item -LiteralPath $outputPath -Force
Write-Output 'PASS: canonical coordinate policy'

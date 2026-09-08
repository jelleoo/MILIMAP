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

function Get-SeedId {
    param([string]$Name, [string]$Address)

    $bytes = [Text.Encoding]::UTF8.GetBytes("$($Name.Trim())|$($Address.Trim())")
    $hash = [Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    $text = -join ($hash | ForEach-Object { $_.ToString('x2') })
    return "seed-$($text.Substring(0, 12))"
}

$fixtureRoot = Join-Path $PSScriptRoot 'testdata\canonical-source-seed'
$outputPath = Join-Path ([IO.Path]::GetTempPath()) ('canonical-source-seed-' + [guid]::NewGuid().ToString('N') + '.json')
$referencePath = Join-Path ([IO.Path]::GetTempPath()) ('canonical-source-reference-' + [guid]::NewGuid().ToString('N') + '.json')
$scriptPath = Join-Path $PSScriptRoot 'convert-benefits.ps1'
$foodId = Get-SeedId -Name '테스트 식당' -Address '서울특별시 마포구 테스트로 1'

@(
    [ordered]@{
        id = $foodId
        district = '서교동'
    }
) | ConvertTo-Json | Set-Content -LiteralPath $referencePath -Encoding utf8

& $scriptPath `
    -SourceCsv (Join-Path $fixtureRoot 'canonical.csv') `
    -DestinationJson $outputPath `
    -DistrictReferenceJson $referencePath

$items = @(Get-Content -Raw -Encoding utf8 $outputPath | ConvertFrom-Json)
Assert-Equal -Actual $items.Count -Expected 2 -Message '정본 행을 빠짐없이 중간 시드로 변환해야 합니다'

$food = @($items | Where-Object { $_.id -eq $foodId })[0]
Assert-Equal -Actual $food.name -Expected '테스트 식당' -Message '정본 업소명을 보존해야 합니다'
Assert-Equal -Actual $food.latitude -Expected 37.55 -Message '좌표 쌍은 숫자로 변환해야 합니다'
Assert-Equal -Actual $food.longitude -Expected 126.91 -Message '좌표 쌍은 숫자로 변환해야 합니다'
Assert-Equal -Actual $food.sourceType -Expected 'MMA_API' -Message '병무청 공공데이터는 MMA API 출처로 변환해야 합니다'
Assert-Equal -Actual $food.status -Expected 'ACTIVE' -Message '이용 가능 혜택은 활성 상태로 변환해야 합니다'
Assert-Equal -Actual $food.district -Expected '서교동' -Message '기존 출시 시드의 세부 지역은 안정적으로 보존해야 합니다'

$culture = @($items | Where-Object { $_.name -eq '테스트 문화공간' })[0]
Assert-Equal -Actual $culture.address -Expected '경기도 파주시 테스트리 2' -Message '도로명주소가 없으면 지번주소를 사용해야 합니다'
Assert-Equal -Actual $culture.category -Expected '문화·여가' -Message '허용 업종을 보존해야 합니다'
Assert-Equal -Actual $culture.sourceType -Expected 'PUBLIC_EVIDENCE' -Message '업체 공식 SNS는 공개 근거 출처로 변환해야 합니다'
Assert-Equal -Actual $culture.status -Expected 'NEEDS_VERIFICATION' -Message '확인 필요 혜택은 검토 상태로 변환해야 합니다'
Assert-Equal -Actual $culture.latitude -Expected $null -Message '좌표가 없으면 비워야 합니다'
Assert-Equal -Actual $culture.longitude -Expected $null -Message '좌표가 없으면 비워야 합니다'
Assert-Equal -Actual $culture.district -Expected '파주시' -Message '기존 세부 지역이 없으면 시군구를 사용해야 합니다'

Remove-Item -LiteralPath $outputPath, $referencePath -Force
Write-Output 'PASS: canonical benefit conversion'

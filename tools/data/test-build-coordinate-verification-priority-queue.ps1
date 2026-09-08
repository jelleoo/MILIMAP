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

$fixtureRoot = Join-Path $PSScriptRoot 'testdata\coordinate-priority'
$outputPath = Join-Path ([IO.Path]::GetTempPath()) ('coordinate-priority-' + [guid]::NewGuid().ToString('N') + '.csv')
$scriptPath = Join-Path $PSScriptRoot 'build-coordinate-verification-priority-queue.ps1'

& $scriptPath `
    -CanonicalCsv (Join-Path $fixtureRoot 'canonical.csv') `
    -CoordinateAuditCsv (Join-Path $fixtureRoot 'coordinate-audit.csv') `
    -BenefitReviewCsv @(
        (Join-Path $fixtureRoot 'benefit-review-a.csv'),
        (Join-Path $fixtureRoot 'benefit-review-b.csv')
    ) `
    -OutputCsv $outputPath

$rows = @(Import-Csv -LiteralPath $outputPath -Encoding utf8)
Assert-Equal -Actual $rows.Count -Expected 3 -Message '최신 공식 목록 일치 후보만 좌표 우선순위 큐에 포함해야 합니다'
Assert-Equal -Actual $rows[0].업소명 -Expected '확인 후보 업소' -Message '확인 후보 좌표를 최우선으로 정렬해야 합니다'
Assert-Equal -Actual $rows[0].우선순위 -Expected 'P1' -Message '확인 후보 좌표는 P1이어야 합니다'
Assert-Equal -Actual $rows[1].업소명 -Expected '재확인 업소' -Message '재확인 필요 좌표를 두 번째로 정렬해야 합니다'
Assert-Equal -Actual $rows[1].우선순위 -Expected 'P2' -Message '재확인 필요 좌표는 P2이어야 합니다'
Assert-Equal -Actual $rows[1].POI도로명주소 -Expected '경기도 테스트시 다른로 2' -Message '재확인 판단에 필요한 POI 주소를 함께 내보내야 합니다'
Assert-Equal -Actual $rows[1].POI조회어 -Expected '재확인 업소 경기도 테스트시 다른로 2' -Message '보조 검색으로 찾은 P2는 실제 POI 조회어를 함께 내보내야 합니다'
Assert-Equal -Actual $rows[1].POI조회방식 -Expected '도로명·건물번호 보조 검색' -Message 'P2 수동 대조에 사용한 POI 조회 방식을 함께 내보내야 합니다'
Assert-Equal -Actual $rows[2].업소명 -Expected '미확인 업소' -Message '두 번째 혜택 검토 보고서의 후보도 포함해야 합니다'
Assert-Equal -Actual $rows[2].우선순위 -Expected 'P3' -Message '미확인 좌표는 P3이어야 합니다'
Assert-Equal -Actual $rows[0].검토결정 -Expected '미검토' -Message '큐 생성은 사람 검토 결정을 자동으로 바꾸면 안 됩니다'
Assert-Equal -Actual $rows[0].정본반영여부 -Expected '아니오' -Message '큐 생성은 정본 반영을 제안하면 안 됩니다'

Write-Output 'PASS: coordinate verification priority rules'

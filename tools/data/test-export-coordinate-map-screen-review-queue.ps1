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

$fixturePath = Join-Path $PSScriptRoot 'testdata\coordinate-map-screen\priority-queue.csv'
$outputPath = Join-Path ([IO.Path]::GetTempPath()) ('coordinate-map-screen-' + [guid]::NewGuid().ToString('N') + '.csv')
$p3OutputPath = Join-Path ([IO.Path]::GetTempPath()) ('coordinate-map-screen-p3-' + [guid]::NewGuid().ToString('N') + '.csv')
$scriptPath = Join-Path $PSScriptRoot 'export-coordinate-map-screen-review-queue.ps1'

& $scriptPath -PriorityQueueCsv $fixturePath -OutputCsv $outputPath

$rows = @(Import-Csv -LiteralPath $outputPath -Encoding utf8)
Assert-Equal -Actual $rows.Count -Expected 1 -Message '지도 화면 검토 큐는 P2 행만 포함해야 합니다'
Assert-Equal -Actual $rows[0].업소명 -Expected '재확인 업소' -Message 'P2 업소명을 보존해야 합니다'
Assert-Equal -Actual $rows[0].참고POI상호 -Expected '재확인 업소' -Message '참고 POI 상호에서는 API 응답의 강조 태그를 제거해야 합니다'
Assert-Equal -Actual ([Uri]::UnescapeDataString($rows[0].원본주소지도검색URL)) -Expected 'https://map.naver.com/p/search/재확인 업소 경기도 테스트시 원본로 2 201호' -Message '원본 업소명과 주소로 지도 검색 URL을 만들어야 합니다'
Assert-Equal -Actual ([Uri]::UnescapeDataString($rows[0].참고POI지도검색URL)) -Expected 'https://map.naver.com/p/search/재확인 업소 경기도 테스트시 참고로 2 202호' -Message '참고 POI 상호와 주소로 별도 지도 검색 URL을 만들어야 합니다'
Assert-Equal -Actual ([Uri]::UnescapeDataString($rows[0].APIHUB조회어지도검색URL)) -Expected 'https://map.naver.com/p/search/재확인 업소 경기도 테스트시 검색로 2' -Message '실제 API HUB POI 조회어로도 별도 지도 검색 URL을 만들어야 합니다'
Assert-Equal -Actual $rows[0].POI조회방식 -Expected '도로명·건물번호 보조 검색' -Message '지도 검토자는 API HUB 조회 방식을 알 수 있어야 합니다'
Assert-Equal -Actual $rows[0].지도대조결과 -Expected '미검토' -Message '큐 생성은 지도 대조 결과를 자동으로 기록하면 안 됩니다'
Assert-Equal -Actual $rows[0].검토결정 -Expected '미검토' -Message '큐 생성은 사람 검토 결정을 자동으로 바꾸면 안 됩니다'
Assert-Equal -Actual $rows[0].정본반영여부 -Expected '아니오' -Message '큐 생성은 정본 반영을 제안하면 안 됩니다'
Assert-Equal -Actual $rows[0].감사제안위도 -Expected '' -Message 'P2 지도 검토 큐에 좌표를 새로 제안하면 안 됩니다'

& $scriptPath -PriorityQueueCsv $fixturePath -OutputCsv $p3OutputPath -QueuePriority P3

$p3Rows = @(Import-Csv -LiteralPath $p3OutputPath -Encoding utf8)
Assert-Equal -Actual $p3Rows.Count -Expected 1 -Message 'P3 지도 검토 큐는 P3 행만 포함해야 합니다'
Assert-Equal -Actual $p3Rows[0].업소명 -Expected '미확인 업소' -Message 'P3 업소명을 보존해야 합니다'
Assert-Equal -Actual ([Uri]::UnescapeDataString($p3Rows[0].원본주소지도검색URL)) -Expected 'https://map.naver.com/p/search/미확인 업소 경기도 테스트시 미확인로 3' -Message 'P3는 원본 업소명과 주소로 지도 검색 URL을 만들어야 합니다'
Assert-Equal -Actual $p3Rows[0].참고POI상호 -Expected '' -Message '미확인 P3에 없는 참고 POI를 만들면 안 됩니다'
Assert-Equal -Actual $p3Rows[0].검토결정 -Expected '미검토' -Message 'P3 큐 생성은 사람 검토 결정을 자동으로 바꾸면 안 됩니다'
Assert-Equal -Actual $p3Rows[0].정본반영여부 -Expected '아니오' -Message 'P3 큐 생성은 정본 반영을 제안하면 안 됩니다'
Assert-Equal -Actual $p3Rows[0].감사제안위도 -Expected '' -Message 'P3 지도 검토 큐에 좌표를 새로 제안하면 안 됩니다'

Write-Output 'PASS: coordinate map-screen review queue rules'

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

$fixtureRoot = Join-Path $PSScriptRoot 'testdata\release-readiness'
$outputPath = Join-Path ([IO.Path]::GetTempPath()) ('release-readiness-' + [guid]::NewGuid().ToString('N') + '.csv')
$scriptPath = Join-Path $PSScriptRoot 'build-release-readiness-report.ps1'

& $scriptPath `
    -CanonicalCsv (Join-Path $fixtureRoot 'canonical.csv') `
    -CoordinateReviewCsv (Join-Path $fixtureRoot 'coordinate-review.csv') `
    -BenefitReviewCsv @(
        (Join-Path $fixtureRoot 'benefit-review.csv'),
        (Join-Path $fixtureRoot 'benefit-review-secondary.csv'),
        (Join-Path $fixtureRoot 'benefit-comparison.csv')
    ) `
    -OutputCsv $outputPath

$rows = @(Import-Csv -LiteralPath $outputPath -Encoding utf8)
Assert-Equal -Actual $rows.Count -Expected 7 -Message '정본의 모든 업소를 출시 준비도 보고서에 포함해야 합니다'

$approved = @($rows | Where-Object { $_.업소명 -eq '승인 업소' })[0]
Assert-Equal -Actual $approved.좌표검토상태 -Expected '확인 완료' -Message '엄격 POI 좌표 감사 후보는 사람 승인 없이 확인 완료로 표시해야 합니다'
Assert-Equal -Actual $approved.혜택검토상태 -Expected '공식 최신 근거 확인' -Message '최신 공식 근거 후보는 사람 승인 없이 혜택 확인으로 표시해야 합니다'
Assert-Equal -Actual $approved.출시판정 -Expected '출시 검토 가능' -Message '엄격 POI 좌표와 공식 최신 근거가 있으면 출시 후보여야 합니다'
Assert-Equal -Actual $approved.지도표시정책 -Expected '좌표 마커 표시' -Message '엄격 POI 좌표 확인 완료 행만 지도 마커로 표시해야 합니다'

$coordinatePending = @($rows | Where-Object { $_.업소명 -eq '좌표 보류 업소' })[0]
Assert-Equal -Actual $coordinatePending.좌표검토상태 -Expected '위치 확인 필요' -Message '재확인 필요 좌표는 위치 확인 안내로 통일해야 합니다'
Assert-Equal -Actual $coordinatePending.지도표시정책 -Expected '지도 핀 미표시 · 주소 직접 확인' -Message '재확인 필요 좌표는 지도 핀을 표시하면 안 됩니다'
Assert-Equal -Actual $coordinatePending.출시판정 -Expected '출시 검토 가능' -Message '재확인 필요 좌표는 최신 혜택 근거가 있으면 목록과 상세 출시 후보가 될 수 있어야 합니다'

$benefitPending = @($rows | Where-Object { $_.업소명 -eq '혜택 보류 업소' })[0]
Assert-Equal -Actual $benefitPending.출시판정 -Expected '보류: 최신 공식 혜택 근거 없음' -Message '엄격 POI 좌표만으로 혜택을 출시 후보로 만들면 안 됩니다'

$duplicateApproval = @($rows | Where-Object { $_.업소명 -eq '복수 승인 업소' })[0]
Assert-Equal -Actual $duplicateApproval.좌표검토상태 -Expected '위치 확인 필요' -Message '같은 업소의 엄격 POI 좌표 후보가 여러 개면 지도 핀을 표시하면 안 됩니다'
Assert-Equal -Actual $duplicateApproval.지도표시정책 -Expected '지도 핀 미표시 · 주소 직접 확인' -Message '복수 좌표 후보는 위치 확인 안내로 전환해야 합니다'
Assert-Equal -Actual $duplicateApproval.출시판정 -Expected '출시 검토 가능' -Message '복수 좌표 후보여도 공식 혜택 근거가 있으면 목록과 상세 출시 후보가 될 수 있어야 합니다'

$secondaryReview = @($rows | Where-Object { $_.업소명 -eq '두번째 근거 업소' })[0]
Assert-Equal -Actual $secondaryReview.혜택검토상태 -Expected '공식 최신 근거 확인' -Message '두 번째 공식 근거 보고서도 출시 게이트에 반영해야 합니다'
Assert-Equal -Actual $secondaryReview.출시판정 -Expected '출시 검토 가능' -Message '각 지역의 분리된 공식 근거 보고서를 함께 읽어야 합니다'

$unverifiedCoordinate = @($rows | Where-Object { $_.업소명 -eq '좌표 미확인 업소' })[0]
Assert-Equal -Actual $unverifiedCoordinate.좌표검토상태 -Expected '위치 확인 필요' -Message '좌표 미확인 업소도 위치 확인 안내로 통일해야 합니다'
Assert-Equal -Actual $unverifiedCoordinate.지도표시정책 -Expected '지도 핀 미표시 · 주소 직접 확인' -Message '좌표 미확인 업소는 핀 대신 주소 확인 안내를 표시해야 합니다'
Assert-Equal -Actual $unverifiedCoordinate.출시판정 -Expected '출시 검토 가능' -Message '좌표가 비어 있어도 최신 공식 혜택 근거가 있으면 목록·상세 출시 후보가 될 수 있어야 합니다'

$comparisonEvidence = @($rows | Where-Object { $_.업소명 -eq '비교 결과 업소' })[0]
Assert-Equal -Actual $comparisonEvidence.혜택검토상태 -Expected '공식 최신 근거 확인' -Message '공식 비교 결과의 참여업소 일치 판정도 최신 공식 근거로 인식해야 합니다'
Assert-Equal -Actual $comparisonEvidence.출시판정 -Expected '출시 검토 가능' -Message '공식 비교 결과로 확인된 업소는 사람 승인 없이 출시 후보가 되어야 합니다'

Write-Output 'PASS: release readiness gate rules'

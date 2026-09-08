[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CanonicalCsv,
    [Parameter(Mandatory = $true)]
    [string]$OutputCsv
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$rows = @(Import-Csv -LiteralPath $CanonicalCsv -Encoding utf8)
$queue = foreach ($index in 0..($rows.Count - 1)) {
    $row = $rows[$index]
    if ($row.혜택상태 -ne '이용 가능') { continue }

    [pscustomobject][ordered]@{
        정본CSV행번호 = $index + 2
        우선순위 = 'P1'
        업소명 = $row.업소명
        시도 = $row.시도
        시군구 = $row.시군구
        소재지도로명주소 = $row.소재지도로명주소
        할인정보 = $row.할인정보
        적용대상 = $row.적용대상
        이용조건 = $row.이용조건
        인증방법 = $row.인증방법
        기존출처유형 = $row.출처유형
        기존출처URL = $row.출처URL
        기존최근확인일 = $row.최근확인일
        재확인기준 = '현재 공식 근거에서 혜택·적용대상·조건이 유지되는지 확인'
        검증결과 = '미검토'
        새출처유형 = ''
        새출처URL = ''
        새최근확인일 = ''
        제안혜택상태 = ''
        정본반영여부 = '아니오'
        검토메모 = ''
    }
}

$resolvedOutputCsv = [IO.Path]::GetFullPath($OutputCsv)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolvedOutputCsv) | Out-Null
$queue | Export-Csv -LiteralPath $resolvedOutputCsv -NoTypeInformation -Encoding utf8
Write-Output ("혜택 재확인 검토 큐 생성: {0}건" -f $queue.Count)

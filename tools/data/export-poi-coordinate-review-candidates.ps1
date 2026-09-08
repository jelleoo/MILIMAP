[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CanonicalCsv,
    [Parameter(Mandatory = $true)]
    [string]$AuditReportCsv,
    [Parameter(Mandatory = $true)]
    [string]$OutputCsv
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$toolRoot = $PSScriptRoot
$reviewOutputCsv = $OutputCsv
. (Join-Path $toolRoot 'verify-canonical-benefit-poi.ps1') -LibraryOnly

$canonicalRows = @(
    Import-Csv -LiteralPath $CanonicalCsv -Encoding utf8 |
        ForEach-Object -Begin { $index = 0 } -Process {
            $index += 1
            [pscustomobject]@{
                RowNumber = $index + 1
                Row = $_
            }
        }
)
$auditRows = @(Import-Csv -LiteralPath $AuditReportCsv -Encoding utf8 | Where-Object { $_.판정 -eq '확인 후보' })

$reviewRows = foreach ($auditRow in $auditRows) {
    $name = Normalize-PoiName $auditRow.업소명
    $address = Normalize-PoiAddress $auditRow.입력주소
    $matches = @(
        $canonicalRows | Where-Object {
            $canonicalName = Normalize-PoiName $_.Row.업소명
            $roadAddress = Normalize-PoiAddress $_.Row.소재지도로명주소
            $lotAddress = Normalize-PoiAddress $_.Row.소재지지번주소
            $canonicalName -eq $name -and ($roadAddress -eq $address -or $lotAddress -eq $address)
        }
    )
    if ($matches.Count -ne 1) {
        throw ("감사 후보와 정본 CSV의 1:1 대응을 확인할 수 없습니다: {0} / {1} (일치 {2}건)" -f $auditRow.업소명, $auditRow.입력주소, $matches.Count)
    }

    $canonical = $matches[0]
    [pscustomobject][ordered]@{
        정본CSV행번호 = $canonical.RowNumber
        감사정본행번호 = $auditRow.정본행번호
        업소명 = $canonical.Row.업소명
        소재지도로명주소 = $canonical.Row.소재지도로명주소
        소재지지번주소 = $canonical.Row.소재지지번주소
        현재위도 = $canonical.Row.위도
        현재경도 = $canonical.Row.경도
        현재좌표검증상태 = $canonical.Row.좌표검증상태
        감사제안위도 = $auditRow.제안위도
        감사제안경도 = $auditRow.제안경도
        POI상호 = $auditRow.POI상호
        POI도로명주소 = $auditRow.POI도로명주소
        POI지번주소 = $auditRow.POI지번주소
        좌표출처 = $auditRow.좌표출처
        좌표출처URL = $auditRow.좌표출처URL
        권장좌표검증상태 = $auditRow.권장좌표검증상태
        감사판정 = $auditRow.판정
        검토결정 = '미검토'
        정본반영여부 = '아니오'
        검토메모 = '감사 후보이며, 사람 검토 전 정본에 자동 반영하지 않음'
    }
}

$resolvedOutputCsv = [IO.Path]::GetFullPath($reviewOutputCsv)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolvedOutputCsv) | Out-Null
$reviewRows | Export-Csv -LiteralPath $resolvedOutputCsv -NoTypeInformation -Encoding utf8
Write-Output ("검토 후보 목록 생성: {0}건" -f $reviewRows.Count)

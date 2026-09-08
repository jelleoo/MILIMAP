[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PriorityQueueCsv,
    [Parameter(Mandatory = $true)]
    [string]$OutputCsv,
    [ValidateSet('P2', 'P3')]
    [string]$QueuePriority = 'P2'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-MapScreenValue {
    param($Row, [string]$Name)

    $property = $Row.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return '' }
    return ([string]$property.Value).Trim()
}

function ConvertTo-PlainMapScreenText {
    param([string]$Value)

    return (($Value -replace '<[^>]+>', '').Trim())
}

function New-NaverMapSearchUrl {
    param([string]$Name, [string]$Address)

    if ([string]::IsNullOrWhiteSpace($Name) -or [string]::IsNullOrWhiteSpace($Address)) { return '' }
    return New-NaverMapQueryUrl -Query "$Name $Address".Trim()
}

function New-NaverMapQueryUrl {
    param([string]$Query)

    if ([string]::IsNullOrWhiteSpace($Query)) { return '' }
    return 'https://map.naver.com/p/search/' + [Uri]::EscapeDataString($Query.Trim())
}

$reviewRows = @(
    Import-Csv -LiteralPath $PriorityQueueCsv -Encoding utf8 |
        Where-Object { (Get-MapScreenValue $_ '우선순위') -eq $QueuePriority } |
        ForEach-Object {
            $name = Get-MapScreenValue $_ '업소명'
            $roadAddress = Get-MapScreenValue $_ '소재지도로명주소'
            $lotAddress = Get-MapScreenValue $_ '소재지지번주소'
            $inputAddress = if ($roadAddress) { $roadAddress } else { $lotAddress }
            $poiName = ConvertTo-PlainMapScreenText (Get-MapScreenValue $_ 'POI상호')
            $poiRoadAddress = Get-MapScreenValue $_ 'POI도로명주소'
            $poiLotAddress = Get-MapScreenValue $_ 'POI지번주소'
            $poiAddress = if ($poiRoadAddress) { $poiRoadAddress } else { $poiLotAddress }
            $poiQuery = Get-MapScreenValue $_ 'POI조회어'
            $poiQueryStrategy = Get-MapScreenValue $_ 'POI조회방식'

            [pscustomobject][ordered]@{
                정본CSV행번호 = Get-MapScreenValue $_ '정본CSV행번호'
                업소명 = $name
                소재지도로명주소 = $roadAddress
                소재지지번주소 = $lotAddress
                참고POI상호 = $poiName
                참고POI도로명주소 = $poiRoadAddress
                참고POI지번주소 = $poiLotAddress
                원본주소지도검색URL = New-NaverMapSearchUrl -Name $name -Address $inputAddress
                참고POI지도검색URL = New-NaverMapSearchUrl -Name $poiName -Address $poiAddress
                POI조회어 = $poiQuery
                POI조회방식 = $poiQueryStrategy
                APIHUB조회어지도검색URL = New-NaverMapQueryUrl -Query $poiQuery
                지도대조결과 = '미검토'
                검토결정 = '미검토'
                정본반영여부 = '아니오'
                감사제안위도 = ''
                감사제안경도 = ''
                비고 = if ($QueuePriority -eq 'P3') {
                    'API 참고 POI가 없는 미확인군. 지도 POI 화면에서 상호와 도로명주소를 대조하고, 불확실하면 좌표를 비움'
                } else {
                    '지도 POI 화면에서 상호와 도로명주소를 대조하고, 불일치 또는 검색 불가면 재확인 필요로 남김'
                }
            }
        }
)

$reviewRows | Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -Encoding utf8BOM
Write-Output ("{0} 지도 화면 검토 큐 생성: {1}건" -f $QueuePriority, $reviewRows.Count)

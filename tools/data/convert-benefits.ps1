param(
    [Parameter(Mandatory = $true)]
    [string]$SourceCsv,
    [Parameter(Mandatory = $true)]
    [string]$DestinationJson
)

$rows = Import-Csv -LiteralPath $SourceCsv -Encoding utf8
$normalized = foreach ($row in $rows) {
    $rawCategory = $row.업종명.Trim()
    $category = switch -Regex ($rawCategory) {
        '음식' { '음식'; break }
        '카페' { '카페'; break }
        '미용' { '미용·뷰티'; break }
        '숙박' { '숙박'; break }
        '병원|의료|안경' { '병원'; break }
        default { '기타' }
    }
    $address = if ($row.소재지도로명주소) { $row.소재지도로명주소.Trim() } else { $row.소재지지번주소.Trim() }
    $identity = "$($row.업소명.Trim())|$address"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($identity)
    $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    $hashText = -join ($hash | ForEach-Object { $_.ToString('x2') })
    $sourceType = if ($row.출처유형 -match '병무청') { 'MMA_API' } elseif ($row.출처유형 -match '지자체') { 'LOCAL_GOV' } else { 'PUBLIC_EVIDENCE' }
    $status = if ($row.검증상태 -match '^A') { 'ACTIVE' } else { 'NEEDS_VERIFICATION' }

    [ordered]@{
        id = "seed-$($hashText.Substring(0, 12))"
        name = $row.업소명.Trim()
        address = $address
        latitude = if ($row.위도) { [double]::Parse($row.위도, [Globalization.CultureInfo]::InvariantCulture) } else { $null }
        longitude = if ($row.경도) { [double]::Parse($row.경도, [Globalization.CultureInfo]::InvariantCulture) } else { $null }
        category = $category
        benefitType = '할인·우대'
        benefitDescription = $row.할인정보.Trim()
        phone = if ($row.업소전화번호) { $row.업소전화번호.Trim() } else { $null }
        eligibleTarget = if ($row.혜택대상) { $row.혜택대상.Trim() } else { '군 장병·병역이행자' }
        usageCondition = if ($row.이용제한) { $row.이용제한.Trim() } elseif ($row.비고) { $row.비고.Trim() } else { $null }
        verificationMethod = if ($row.증빙자료) { $row.증빙자료.Trim() } else { '군인 신분 확인자료' }
        sourceType = $sourceType
        sourceLabel = if ($row.출처유형) { $row.출처유형.Trim() } else { '운영팀 직접 확인' }
        sourceUrl = if ($row.출처URL) { $row.출처URL.Trim() } else { $null }
        lastVerifiedAt = if ($row.데이터기준일자) { $row.데이터기준일자.Trim() } else { $row.수집일자.Trim() }
        status = $status
        district = $row.지역명.Trim()
    }
}

$json = $normalized | ConvertTo-Json -Depth 5
$parent = Split-Path -Parent $DestinationJson
[System.IO.Directory]::CreateDirectory($parent) | Out-Null
[System.IO.File]::WriteAllText($DestinationJson, $json, [System.Text.UTF8Encoding]::new($false))
Write-Output "Converted $($normalized.Count) rows to $DestinationJson"

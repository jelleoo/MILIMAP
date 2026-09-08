[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CanonicalCsv,
    [Parameter(Mandatory = $true)]
    [string]$DdcComparisonCsv,
    [Parameter(Mandatory = $true)]
    [string]$PajuComparisonCsv,
    [Parameter(Mandatory = $true)]
    [string]$YangjuComparisonCsv,
    [Parameter(Mandatory = $true)]
    [string]$OutputCsv,
    [string]$PajuProgramSourceUrl = 'https://www.paju.go.kr/www/www_02/health/health_03/health_03_09/health_03_09_01.jsp',
    [string]$YangjuSourceUrl = 'https://www.yangju.go.kr/health/selectBbsNttView.do?key=2716&bbsNo=81&nttNo=206761',
    [string]$VerifiedOn = '2026-09-06'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RowValue {
    param($Row, [string]$Name)

    $property = $Row.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return '' }
    return ([string]$property.Value).Trim()
}

function Get-RequiredRowValue {
    param($Row, [string]$Name)

    $value = Get-RowValue $Row $Name
    if ([string]::IsNullOrWhiteSpace($value)) { throw "$Name 값이 비어 있습니다." }
    return $value
}

function Normalize-Name {
    param([string]$Value)

    return (($Value -replace '[\s,().·&-]', '')).ToLowerInvariant()
}

function Normalize-Address {
    param([string]$Value)

    $normalized = $Value
    $normalized = $normalized -replace '서울특별시', '서울'
    $normalized = $normalized -replace '경기도', '경기'
    $normalized = $normalized -replace '인천광역시', '인천'
    return (($normalized -replace '[\s,().-]', '')).ToLowerInvariant()
}

function Test-SameBusiness {
    param($Canonical, $Comparison)

    $sameName = (Normalize-Name (Get-RowValue $Canonical '업소명')) -eq (Normalize-Name (Get-RowValue $Comparison '업소명'))
    $sameAddress = (Normalize-Address (Get-RowValue $Canonical '소재지도로명주소')) -eq (Normalize-Address (Get-RowValue $Comparison '소재지도로명주소'))
    return $sameName -and $sameAddress
}

function New-ReleaseCandidate {
    param(
        $Canonical,
        [int]$RowNumber,
        [string]$CopyType,
        [string]$Description,
        [string]$EligibleTarget,
        [string]$UsageCondition,
        [string]$VerificationMethod,
        [string]$SourceType,
        [string]$SourceUrl,
        [string]$DecisionReason
    )

    return [pscustomobject][ordered]@{
        정본CSV행번호 = $RowNumber
        업소명 = Get-RequiredRowValue $Canonical '업소명'
        소재지도로명주소 = Get-RequiredRowValue $Canonical '소재지도로명주소'
        혜택근거상태 = '공식 최신 근거 확인'
        혜택문구유형 = $CopyType
        출시할인정보 = $Description
        출시적용대상 = $EligibleTarget
        출시이용조건 = $UsageCondition
        출시인증방법 = $VerificationMethod
        출처유형 = $SourceType
        출처URL = $SourceUrl
        최근확인일 = $VerifiedOn
        결정근거 = $DecisionReason
    }
}

$canonicalEntries = @(
    Import-Csv -LiteralPath $CanonicalCsv -Encoding utf8 |
        ForEach-Object -Begin { $index = 0 } -Process {
            $index += 1
            [pscustomobject]@{ RowNumber = $index + 1; Row = $_ }
        }
)
$canonicalByRowNumber = @{}
foreach ($entry in $canonicalEntries) {
    $canonicalByRowNumber[$entry.RowNumber] = $entry.Row
}

function Resolve-Canonical {
    param($Comparison)

    $rowNumberText = Get-RequiredRowValue $Comparison '정본CSV행번호'
    $rowNumber = 0
    if (-not [int]::TryParse($rowNumberText, [ref]$rowNumber) -or -not $canonicalByRowNumber.ContainsKey($rowNumber)) {
        throw "정본CSV행번호 '$rowNumberText'에 대응하는 정본 행을 찾지 못했습니다."
    }
    $canonical = $canonicalByRowNumber[$rowNumber]
    if (-not (Test-SameBusiness $canonical $Comparison)) {
        throw "정본CSV행번호 $rowNumber의 업소명 또는 도로명주소가 비교 결과와 일치하지 않습니다."
    }
    return [pscustomobject]@{ RowNumber = $rowNumber; Row = $canonical }
}

$candidates = [System.Collections.Generic.List[object]]::new()
$candidateRowNumbers = [System.Collections.Generic.HashSet[int]]::new()
function Add-Candidate {
    param($Candidate)

    if (-not $candidateRowNumbers.Add([int]$Candidate.정본CSV행번호)) {
        throw "정본CSV행번호 $($Candidate.정본CSV행번호)가 여러 공식 근거 후보에 중복되었습니다."
    }
    $candidates.Add($Candidate)
}

$ddcRows = @(Import-Csv -LiteralPath $DdcComparisonCsv -Encoding utf8)
foreach ($comparison in $ddcRows | Where-Object {
    (Get-RowValue $_ '판정') -eq '현재 공식 목록 일치 후보' -and
    -not [string]::IsNullOrWhiteSpace((Get-RowValue $_ '공식할인정보'))
}) {
    $resolved = Resolve-Canonical $comparison
    $canonical = $resolved.Row
    Add-Candidate (New-ReleaseCandidate `
        -Canonical $canonical `
        -RowNumber $resolved.RowNumber `
        -CopyType '세부' `
        -Description (Get-RequiredRowValue $comparison '공식할인정보') `
        -EligibleTarget (Get-RowValue $canonical '적용대상') `
        -UsageCondition (Get-RowValue $canonical '이용조건') `
        -VerificationMethod '동두천시 공식 군장병 할인업소 목록' `
        -SourceType '지자체 공식 자료' `
        -SourceUrl (Get-RequiredRowValue $canonical '출처URL') `
        -DecisionReason '동두천시 공식 목록에서 상호·주소·전화·개별 할인 일치')
}

$pajuRows = @(Import-Csv -LiteralPath $PajuComparisonCsv -Encoding utf8)
foreach ($comparison in $pajuRows | Where-Object {
    (Get-RowValue $_ '판정') -eq '공식 참여업소 일치 후보' -and
    -not [string]::IsNullOrWhiteSpace((Get-RowValue $_ '공식출처URL'))
}) {
    $resolved = Resolve-Canonical $comparison
    Add-Candidate (New-ReleaseCandidate `
        -Canonical $resolved.Row `
        -RowNumber $resolved.RowNumber `
        -CopyType '공통' `
        -Description '군 장병·사회복무요원 대상 10% 이상 할인 또는 상응 서비스' `
        -EligibleTarget '관내 주둔 군 장병·사회복무요원' `
        -UsageCondition '업소별 적용 품목·조건은 방문 전 확인' `
        -VerificationMethod '파주시 공식 군장병 할인업소 목록 및 운영 안내' `
        -SourceType '지자체 공식 자료' `
        -SourceUrl "$PajuProgramSourceUrl | $(Get-RequiredRowValue $comparison '공식출처URL')" `
        -DecisionReason '파주시 공식 참여업소 목록 일치, 공식 공통 할인 정책 적용')
}

$yangjuRows = @(Import-Csv -LiteralPath $YangjuComparisonCsv -Encoding utf8)
foreach ($comparison in $yangjuRows | Where-Object {
    (Get-RowValue $_ '판정') -eq '현재 공식 목록 일치 후보' -and
    -not [string]::IsNullOrWhiteSpace((Get-RowValue $_ '공식메뉴')) -and
    -not [string]::IsNullOrWhiteSpace((Get-RowValue $_ '공식할인정보'))
}) {
    $resolved = Resolve-Canonical $comparison
    $canonical = $resolved.Row
    Add-Candidate (New-ReleaseCandidate `
        -Canonical $canonical `
        -RowNumber $resolved.RowNumber `
        -CopyType '세부' `
        -Description "$(Get-RequiredRowValue $comparison '공식메뉴'): $(Get-RequiredRowValue $comparison '공식할인정보')" `
        -EligibleTarget (Get-RowValue $canonical '적용대상') `
        -UsageCondition (Get-RowValue $canonical '이용조건') `
        -VerificationMethod '양주시 공식 군장병 할인·우대 업소 목록' `
        -SourceType '지자체 공식 자료' `
        -SourceUrl $YangjuSourceUrl `
        -DecisionReason '양주시 공식 목록에서 상호·주소·전화·메뉴·개별 할인 확인')
}

$resolvedOutput = [IO.Path]::GetFullPath($OutputCsv)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolvedOutput) | Out-Null
$candidates | Sort-Object 정본CSV행번호 | Export-Csv -LiteralPath $resolvedOutput -NoTypeInformation -Encoding utf8
Write-Output ("공식 혜택 출시 후보 생성: {0}건" -f $candidates.Count)

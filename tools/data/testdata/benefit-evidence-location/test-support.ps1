# Test-only helpers. Production libraries must never import this file.
$ErrorActionPreference = 'Stop'
$scopeDataRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
. (Join-Path $scopeDataRoot 'lib/benefit-verification-contracts.ps1')
. (Join-Path $scopeDataRoot 'lib/identity/normalize-business.ps1')
$script:ScopeTestFixturePath = Join-Path $PSScriptRoot 'synthetic.psd1'

function Assert-ScopeEqual {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -cne $Expected) { throw "$Message (expected: $Expected, actual: $Actual)" }
}
function Assert-ScopeTrue {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
function Assert-ScopeThrows {
    param([scriptblock]$Action, [string]$Message)
    $caught = $false
    try { & $Action } catch { $caught = $true }
    if (-not $caught) { throw $Message }
}
function Get-ScopeTestHtml {
    $fixture = Import-PowerShellDataFile -LiteralPath $script:ScopeTestFixturePath
    return [string]$fixture.Html
}
function New-ScopeTestDocument {
    param([int]$RowNumber=2, [string]$Html=(Get-ScopeTestHtml), [string]$Url='https://city.example.go.kr/list')
    return New-BenefitSourceDocument -SourceRowNumber $RowNumber -Url $Url -SourceFormat HTML -FetchStatus COMPLETE -Text $Html -ObservedAt '2026-09-24T00:00:00Z'
}
function New-ScopeTestRow {
    param([string]$Name='테스트가게 A', [string]$Building='12', [string]$Phone='02-0000-0012', [string]$Benefit='10% 할인')
    return [pscustomobject]@{
        업소명=$Name; 시도='서울특별시'; 시군구='마포구'
        소재지도로명주소="서울특별시 마포구 테스트로 $Building"; 소재지지번주소=''
        업소전화번호=$Phone; 할인정보=$Benefit; 적용대상=''; 이용조건=''; 인증방법=''
        출처유형='지자체 공식 자료'; 출처URL='https://city.example.go.kr/list'; 최근확인일='2026-09-24'
    }
}
function New-ScopeTestBusiness {
    param([int]$RowNumber=2, [string]$Name='테스트가게 A', [string]$Building='12')
    return ConvertTo-NormalizedBusiness -Row (New-ScopeTestRow -Name $Name -Building $Building) -SourceRowNumber $RowNumber
}

# Deliberately restricted fixture span builder, NOT the runtime HTML parser.
# Its input is the fixed two-row synthetic table above. It only constructs
# coordinates for testing contracts before the production parser exists.
function New-ScopeContractFixture {
    param([int]$RowNumber=2, [int]$UnitIndex=0)
    $document = New-ScopeTestDocument -RowNumber $RowNumber
    $snapshot = New-BenefitSourceSnapshot -SourceUrl $document.Url -SourceFormat HTML -Text $document.Text -ObservedAt $document.ObservedAt
    $headers = @([regex]::Matches($document.Text, '<th\b[^>]*>.*?</th>'))
    $rows = @([regex]::Matches($document.Text, '<tr\b[^>]*>.*?</tr>'))
    $keys = @('BusinessName','Address','Phone','BenefitDescription')
    $units = @()
    for ($rowIndex=1; $rowIndex -lt $rows.Count; $rowIndex++) {
        $row = $rows[$rowIndex]
        $cells = @([regex]::Matches($row.Value, '<td\b[^>]*>.*?</td>'))
        $fields = [ordered]@{}
        $references = [ordered]@{}
        $unitReference = 'HTML_TABLE_1_ROW_' + ($rowIndex + 1)
        for ($i=0; $i -lt $keys.Count; $i++) {
            $fields[$keys[$i]] = ConvertFrom-ScopeHtmlText -Text $cells[$i].Value
            $references[$keys[$i]] = [pscustomobject][ordered]@{
                HeaderStart=$headers[$i].Index; HeaderLength=$headers[$i].Length
                CellStart=($row.Index + $cells[$i].Index); CellLength=$cells[$i].Length
                OriginalHeader=(ConvertFrom-ScopeHtmlText -Text $headers[$i].Value)
                FieldReference=($unitReference + '/' + $keys[$i])
            }
        }
        $units += New-BenefitSourceContentUnit -Snapshot $snapshot -UnitReference $unitReference -TableStart 0 -TableLength $document.Text.Length -RawStart $row.Index -RawLength $row.Length -RawEvidenceText (ConvertFrom-ScopeHtmlText -Text $row.Value) -StructuredFields $fields -FieldReferences $references
    }
    $observation = New-BenefitSourceObservation -SourceRowNumber $RowNumber -Snapshot $snapshot -AdapterId HTML_GENERIC -AdapterVersion '1' -AdapterStatus COMPLETE -ContentUnits $units -Diagnostics @()
    $slice = New-RelevantBenefitEvidenceSlice -Observation $observation -Unit $units[$UnitIndex] -IdentityEvidence @('NAME_MATCH','FULL_ADDRESS_MATCH')
    return [pscustomobject]@{Document=$document;Snapshot=$snapshot;Units=$units;Observation=$observation;Slice=$slice}
}

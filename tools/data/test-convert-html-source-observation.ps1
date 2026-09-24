$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-location/test-support.ps1')
$parserPath = Join-Path $PSScriptRoot 'lib/benefit-evidence/convert-html-source-observation.ps1'
if (-not (Test-Path -LiteralPath $parserPath)) { throw 'Generic HTML observation parser is missing' }
. $parserPath

function Assert-ParserStatus {
    param($Result, [string]$Expected, [string]$Message)
    Assert-ScopeEqual $Result.AdapterStatus $Expected $Message
}

$document = New-ScopeTestDocument
$observation = ConvertTo-BenefitHtmlObservation -Document $document
Assert-ParserStatus $observation 'COMPLETE' 'A regular supported table must parse completely'
Assert-ScopeEqual @($observation.ContentUnits).Count 2 'Two physical business rows must remain two units'
Assert-ScopeEqual $observation.ContentUnits[0].UnitReference 'HTML_TABLE_1_ROW_2' 'First data row keeps its physical reference'
Assert-ScopeEqual $observation.ContentUnits[1].UnitReference 'HTML_TABLE_1_ROW_3' 'Second data row keeps its physical reference'
Assert-ScopeEqual $observation.ContentUnits[0].StructuredFields.BusinessName '테스트가게 A' 'Business name comes from its own cell'
Assert-ScopeEqual $observation.ContentUnits[1].StructuredFields.BenefitDescription '30% 할인' 'Benefit comes from its own cell'
Assert-ScopeTrue ($observation.ContentUnits[0].FieldReferences.BusinessName.FieldReference -eq 'HTML_TABLE_1_ROW_2/BusinessName') 'Field reference must preserve the physical row'

$csvDocument = New-BenefitSourceDocument -SourceRowNumber 2 -Url 'https://city.example.go.kr/list.csv' -SourceFormat CSV -FetchStatus COMPLETE -Text '업체명,주소' -ObservedAt '2026-09-24T00:00:00Z'
$csvObservation = ConvertTo-BenefitHtmlObservation -Document $csvDocument
Assert-ParserStatus $csvObservation 'UNSUPPORTED' 'The generic HTML parser must not parse another source format'
Assert-ScopeEqual @($csvObservation.ContentUnits).Count 0 'Unsupported formats cannot emit HTML evidence rows'

$twoTables = (Get-ScopeTestHtml) + '<table><tr><th>업체명</th><th>주소</th></tr><tr><td>세 번째 가게</td><td>서울특별시 마포구 테스트로 77</td></tr></table>'
$twoObservation = ConvertTo-BenefitHtmlObservation -Document (New-ScopeTestDocument -Html $twoTables)
Assert-ParserStatus $twoObservation 'COMPLETE' 'Multiple safe business tables are supported'
Assert-ScopeEqual @($twoObservation.ContentUnits).Count 3 'Rows from every safe candidate table are observed'
Assert-ScopeEqual $twoObservation.ContentUnits[2].UnitReference 'HTML_TABLE_2_ROW_2' 'Second physical table must not be renumbered'

$participationOnly = '<table><tr><th>사업장명</th><th>주소</th></tr><tr><td>참여 가게</td><td>서울특별시 마포구 테스트로 50</td></tr></table>'
$participationObservation = ConvertTo-BenefitHtmlObservation -Document (New-ScopeTestDocument -Html $participationOnly)
Assert-ParserStatus $participationObservation 'COMPLETE' 'A participation table does not need a benefit column'
Assert-ScopeEqual @($participationObservation.ContentUnits).Count 1 'Participation row remains eligible for later deterministic location'
Assert-ScopeTrue (-not $participationObservation.ContentUnits[0].StructuredFields.Contains('BenefitDescription')) 'Do not invent a missing benefit field'

$duplicateHeader = (Get-ScopeTestHtml) -replace '<th>주소</th>', '<th>업체명</th>'
$duplicateObservation = ConvertTo-BenefitHtmlObservation -Document (New-ScopeTestDocument -Html $duplicateHeader)
Assert-ParserStatus $duplicateObservation 'PARTIAL' 'Duplicate recognized business headers are unsafe'
Assert-ScopeEqual @($duplicateObservation.ContentUnits).Count 0 'Unsafe candidate rows must not be emitted'

$unequalCells = (Get-ScopeTestHtml) -replace '<td>30% 할인</td>', ''
$unequalObservation = ConvertTo-BenefitHtmlObservation -Document (New-ScopeTestDocument -Html $unequalCells)
Assert-ParserStatus $unequalObservation 'PARTIAL' 'Unequal header and data cell counts are unsafe'

foreach ($unsafeHtml in @(
    '<table><tr><th>업체명</th></tr><tr><td rowspan="2">가게</td></tr></table>',
    '<table><tr><th>업체명</th></tr><tr><td colspan="2">가게</td></tr></table>',
    '<table><tr><th>업체명</th></tr><tr><td><table><tr><td>nested</td></tr></table></td></tr></table>',
    '<table><tr><th>업체명</th></tr><tr><td>truncated'
)) {
    $unsafeObservation = ConvertTo-BenefitHtmlObservation -Document (New-ScopeTestDocument -Html $unsafeHtml)
    Assert-ScopeTrue ($unsafeObservation.AdapterStatus -in @('PARTIAL','FAILED')) 'Unsafe candidate structures must fail closed'
    Assert-ScopeEqual @($unsafeObservation.ContentUnits).Count 0 'Unsafe structures cannot yield source-backed rows'
}
foreach ($spacedSpan in @('rowspan=" 2"','colspan=" 2"')) {
    $spacedSpanHtml = '<table><tr><th>업체명</th><th>주소</th></tr><tr><td ' + $spacedSpan + '>가게</td><td>서울특별시 마포구 테스트로 1</td></tr></table>'
    $spacedSpanObservation = ConvertTo-BenefitHtmlObservation -Document (New-ScopeTestDocument -Html $spacedSpanHtml)
    Assert-ParserStatus $spacedSpanObservation 'PARTIAL' 'Whitespace cannot bypass unsupported merged-cell detection'
    Assert-ScopeEqual @($spacedSpanObservation.ContentUnits).Count 0 'Merged cells cannot emit an aligned evidence row'
}
$preHeaderData = '<table><tr><td>unlabelled preface</td></tr><tr><th>업체명</th><th>주소</th></tr><tr><td>가게</td><td>서울특별시 마포구 테스트로 1</td></tr></table>'
$preHeaderObservation = ConvertTo-BenefitHtmlObservation -Document (New-ScopeTestDocument -Html $preHeaderData)
Assert-ParserStatus $preHeaderObservation 'PARTIAL' 'A data row before the header is outside the supported deterministic subset'
Assert-ScopeEqual @($preHeaderObservation.ContentUnits).Count 0 'Pre-header data must not cause an exception or evidence output'
$nestedCandidate = '<table><tr><th>업체명</th></tr><tr><td><table><tr><th>업체명</th><th>주소</th></tr><tr><td>nested candidate</td><td>서울특별시 마포구 테스트로 1</td></tr></table></td></tr></table>'
$nestedCandidateObservation = ConvertTo-BenefitHtmlObservation -Document (New-ScopeTestDocument -Html $nestedCandidate)
Assert-ParserStatus $nestedCandidateObservation 'PARTIAL' 'A nested candidate table remains unsupported rather than independently parseable'
Assert-ScopeEqual @($nestedCandidateObservation.ContentUnits).Count 0 'Nested candidate rows cannot bypass the outer table safety boundary'

$encoded = '<table><tr><th>업체명</th><th>주소</th></tr><tr><td>가게 &amp; <b>카페</b></td><td>서울특별시<br>마포구 테스트로 8</td></tr></table>'
$encodedObservation = ConvertTo-BenefitHtmlObservation -Document (New-ScopeTestDocument -Html $encoded)
Assert-ParserStatus $encodedObservation 'COMPLETE' 'Safe inline markup and entities remain supported'
Assert-ScopeEqual $encodedObservation.ContentUnits[0].StructuredFields.BusinessName '가게 & 카페' 'Entities decode after inline markup is removed'
Assert-ScopeEqual $encodedObservation.ContentUnits[0].StructuredFields.Address '서울특별시 마포구 테스트로 8' 'Line-break markup becomes text spacing'

$opaquePrefix = @'
<!-- <table><tr><th>업체명</th></tr><tr><td>comment fake</td></tr></table> -->
<script>const fake = "<table><tr><th>업체명</th></tr><tr><td>script fake</td></tr></table>";</script>
<style>.x { content: "<table><tr><td>style fake</td></tr></table>"; }</style>
<textarea><table><tr><td>textarea fake</td></tr></table></textarea><title><table><tr><td>title fake</td></tr></table></title>
<div data-fake="<table><tr><td>attribute fake</td></tr></table>"></div>
'@
$opaqueObservation = ConvertTo-BenefitHtmlObservation -Document (New-ScopeTestDocument -Html ($opaquePrefix + (Get-ScopeTestHtml)))
Assert-ParserStatus $opaqueObservation 'COMPLETE' 'Opaque HTML-looking text must not manufacture tables'
Assert-ScopeEqual @($opaqueObservation.ContentUnits).Count 2 'Only real physical rows are observed'
Assert-ScopeEqual $opaqueObservation.ContentUnits[0].UnitReference 'HTML_TABLE_1_ROW_2' 'Fake tags cannot change physical table numbering'

$datedPage = (Get-ScopeTestHtml) + '<p>2026-12-31까지 안내</p>'
$datedObservation = ConvertTo-BenefitHtmlObservation -Document (New-ScopeTestDocument -Html $datedPage)
Assert-ScopeTrue (-not $datedObservation.ContentUnits[0].StructuredFields.Contains('ValidUntil')) 'Page dates cannot invent ValidUntil evidence'
Assert-ScopeTrue (-not $datedObservation.ContentUnits[0].StructuredFields.Contains('CurrentApplicability')) 'Page dates cannot invent currentness evidence'

Write-Host 'Generic HTML source observation parser tests passed.'

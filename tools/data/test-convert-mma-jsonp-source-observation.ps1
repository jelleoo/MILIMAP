$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-location/test-support.ps1')

function Assert-ScopeNoThrow {
    param([scriptblock]$Action, [string]$Message)
    try { & $Action } catch { throw "$Message ($($_.Exception.Message))" }
}

$parserPath = Join-Path $PSScriptRoot 'lib/benefit-evidence/convert-mma-jsonp-source-observation.ps1'
if (-not (Test-Path -LiteralPath $parserPath)) { throw 'MMA JSONP source observation parser is missing' }
. $parserPath

Assert-ScopeNoThrow { ConvertFrom-BenefitJsonpEnvelope -Text 'Cb({"success":true});' -ExpectedCallback 'Cb' } 'Valid JSONP envelope parses'
Assert-ScopeNoThrow { ConvertFrom-BenefitJsonpEnvelope -Text 'Cb({"success":true,"note":"brace } and quote \" retained"})' -ExpectedCallback 'Cb' } 'Escaped quote and brace remain JSON data'
foreach ($invalidEnvelope in @(
    @{Text='Wrong({"success":true})'; Callback='Cb'; Message='Callback mismatch fails'},
    @{Text='Cb({"success":true})alert(1)'; Callback='Cb'; Message='Executable suffix fails'},
    @{Text='Cb({"success":true}'; Callback='Cb'; Message='Missing close parenthesis fails'},
    @{Text='Cb([1,2,3])'; Callback='Cb'; Message='Non-object root fails'},
    @{Text='Cb({"success":false})'; Callback='Cb'; Message='Unsuccessful MMA response is unusable'},
    @{Text='Cb({not-json})'; Callback='Cb'; Message='Malformed JSON fails'}
)) {
    Assert-ScopeThrows { ConvertFrom-BenefitJsonpEnvelope -Text $invalidEnvelope.Text -ExpectedCallback $invalidEnvelope.Callback } $invalidEnvelope.Message
}

$fixtureRoot = Join-Path $PSScriptRoot 'testdata/benefit-evidence-mma'
$listText = Get-Content -Raw -LiteralPath (Join-Path $fixtureRoot 'mma-list.fixture.jsonp')
$detail2789Text = Get-Content -Raw -LiteralPath (Join-Path $fixtureRoot 'mma-detail-2789.fixture.jsonp')

# Raw keys were confirmed by the plan-authorized 2026-09-25 official MMA list probe:
# udgigwan_yhnm, addr, udgigwan_telno, udggeopjong_gbnm, udgigwan_cd.
$listDocument = New-BenefitSourceDocument -SourceRowNumber 2 -Url 'https://open.mma.go.kr/caisGGGS/mmanrsrListAjaxJsonCallNew.json?callback=MmaTestList' -SourceFormat JSONP -FetchStatus COMPLETE -ContentType 'application/json' -Text $listText -ObservedAt '2026-09-25T00:00:00Z'
$listObservation = ConvertTo-MmaJsonpListObservation -Document $listDocument -ExpectedCallback 'MmaTestList'
Assert-ScopeEqual $listObservation.AdapterStatus COMPLETE 'MMA list fixture parses completely'
Assert-ScopeEqual $listObservation.AdapterId MMA_JSONP_LIST 'MMA list adapter identity is explicit'
Assert-ScopeEqual $listObservation.Snapshot.Text $listText 'Raw JSONP list text is preserved without wrapper removal'
Assert-ScopeEqual @($listObservation.ContentUnits).Count 3 'One JSONP source unit is emitted per list object'
Assert-ScopeEqual $listObservation.ContentUnits[0].UnitReference JSONP_LIST_ITEM_1 'List reference keeps one-based physical index'
Assert-ScopeEqual $listObservation.ContentUnits[0].StructuredFields.BusinessName '(유)투투여행사' 'Observed MMA business name key is mapped'
Assert-ScopeEqual $listObservation.ContentUnits[0].StructuredFields.InstitutionCode 2789 'List institution code is preserved as linkage metadata'
Assert-ScopeEqual $listObservation.ContentUnits[0].FieldReferences.BusinessName.FieldReference 'JSONP_LIST_ITEM_1/udgigwan_yhnm' 'List field reference retains original raw property name'
Assert-ScopeEqual ($listText.Substring([int]$listObservation.ContentUnits[0].RawStart,[int]$listObservation.ContentUnits[0].RawLength)) $listObservation.ContentUnits[0].RawFragment 'List raw source span reconstructs selected JSON object'

$detailDocument = New-BenefitSourceDocument -SourceRowNumber 2 -Url 'https://open.mma.go.kr/caisGGGS/mmanrsrSangSeAjaxJsonCall.json?udgigwan_cd=2789&callback=MmaTestDetail' -SourceFormat JSONP -FetchStatus COMPLETE -ContentType 'application/json' -Text $detail2789Text -ObservedAt '2026-09-25T00:00:00Z'
$detailObservation = ConvertTo-MmaJsonpDetailObservation -Document $detailDocument -ExpectedCallback 'MmaTestDetail'
Assert-ScopeEqual $detailObservation.AdapterStatus COMPLETE 'MMA detail fixture parses completely'
Assert-ScopeEqual $detailObservation.AdapterId MMA_JSONP_DETAIL 'MMA detail adapter identity is explicit'
Assert-ScopeEqual @($detailObservation.ContentUnits).Count 1 'Detail response has one JSON object evidence unit'
Assert-ScopeEqual $detailObservation.ContentUnits[0].UnitReference JSONP_DETAIL_OBJECT 'Detail source unit has stable physical reference'
Assert-ScopeEqual $detailObservation.ContentUnits[0].StructuredFields.BenefitDescription '서비스 이용료 3% 할인' 'Benefit detail is mapped from its observed source property'
Assert-ScopeEqual $detailObservation.ContentUnits[0].StructuredFields.ValidUntilObserved '9999-12-31' 'Sentinel-like agreement end remains raw observed data'
Assert-ScopeEqual $detailObservation.ContentUnits[0].FieldReferences.BenefitDescription.FieldReference 'JSONP_DETAIL_OBJECT/udsangse_cn' 'Detail benefit reference retains original raw property name'
Assert-ScopeTrue ($detailObservation.ContentUnits[0].FieldReferences.BenefitDescription.ValueStart -ge $detailObservation.ContentUnits[0].RawStart) 'JSONP field value start is source-backed inside its selected object'
Assert-ScopeTrue ($detailObservation.ContentUnits[0].FieldReferences.BenefitDescription.ValueLength -gt 0) 'JSONP field value has a preserved raw span length'

$forgedOtherObject = Copy-ScopeContractData $listObservation.ContentUnits[0]
$forgedOtherObject.FieldReferences.BusinessName = Copy-ScopeContractData $listObservation.ContentUnits[1].FieldReferences.BusinessName
Assert-ScopeThrows { Assert-ScopeUnit $forgedOtherObject $listObservation.Snapshot } 'Another JSONP object field reference cannot be substituted'
$forgedProperty = Copy-ScopeContractData $detailObservation.ContentUnits[0]
$forgedProperty.FieldReferences.BenefitDescription.PropertyName = 'uddaesang_cn'
Assert-ScopeThrows { Assert-ScopeUnit $forgedProperty $detailObservation.Snapshot } 'A different JSONP property cannot back the claimed benefit field'
$forgedSpan = Copy-ScopeContractData $detailObservation.ContentUnits[0]
$forgedSpan.RawStart++
Assert-ScopeThrows { Assert-ScopeUnit $forgedSpan $detailObservation.Snapshot } 'Altered JSONP source span fails provenance validation'
$forgedValue = Copy-ScopeContractData $detailObservation.ContentUnits[0]
$forgedValue.StructuredFields.BenefitDescription = 'fabricated benefit'
Assert-ScopeThrows { Assert-ScopeUnit $forgedValue $detailObservation.Snapshot } 'Structured JSONP value must remain backed by selected raw property'
$forgedValueOffset = Copy-ScopeContractData $detailObservation.ContentUnits[0]
$forgedValueOffset.FieldReferences.BenefitDescription.ValueStart = $detailObservation.ContentUnits[0].FieldReferences.EligibleTarget.ValueStart
$forgedValueOffset.FieldReferences.BenefitDescription.ValueLength = $detailObservation.ContentUnits[0].FieldReferences.EligibleTarget.ValueLength
Assert-ScopeThrows { Assert-ScopeUnit $forgedValueOffset $detailObservation.Snapshot } 'Cross-property JSONP value offsets cannot back another semantic field'

Write-Host 'MMA JSONP source observation parser tests passed.'

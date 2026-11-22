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

$incompleteNeighborText = 'MmaTestList({"success":true,"list":[{"udgigwan_cd":"0000","udgigwan_yhnm":"","addr":"서울특별시 제외구","udgigwan_telno":"","udggeopjong_gbnm":"기타"},{"udgigwan_cd":"2789","udgigwan_yhnm":"(유)투투여행사","addr":"서울특별시 테스트구 여행로 2789","udgigwan_telno":"02-2789-0000","udggeopjong_gbnm":"여행사"}]});'
$incompleteNeighborDocument = New-BenefitSourceDocument -SourceRowNumber 2 -Url 'https://open.mma.go.kr/caisGGGS/mmanrsrListAjaxJsonCallNew.json?callback=MmaTestList' -SourceFormat JSONP -FetchStatus COMPLETE -ContentType 'application/json' -Text $incompleteNeighborText -ObservedAt '2026-09-25T00:00:00Z'
$incompleteNeighborObservation = ConvertTo-MmaJsonpListObservation -Document $incompleteNeighborDocument -ExpectedCallback 'MmaTestList'
Assert-ScopeEqual $incompleteNeighborObservation.AdapterStatus COMPLETE 'Unrelated empty-name MMA list record does not fail the whole observation'
Assert-ScopeEqual @($incompleteNeighborObservation.ContentUnits).Count 1 'Empty-name MMA list record is excluded from identity candidates'
Assert-ScopeEqual $incompleteNeighborObservation.ContentUnits[0].UnitReference JSONP_LIST_ITEM_2 'Skipping an unusable list record preserves physical source indexing'
Assert-ScopeEqual $incompleteNeighborObservation.ContentUnits[0].StructuredFields.BusinessName '(유)투투여행사' 'Usable neighboring MMA record remains source-backed'

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

$equalValueText = 'MmaTestDetail({"success":true,"udgigwanVO":{"benefit_a":"동일 값","benefit_b":"동일 값"}});'
$equalValueSnapshot = New-BenefitSourceSnapshot -SourceUrl 'https://open.mma.go.kr/caisGGGS/mmanrsrSangSeAjaxJsonCall.json?udgigwan_cd=equal&callback=MmaTestDetail' -SourceFormat JSONP -Text $equalValueText -ObservedAt '2026-09-25T00:00:00Z'
$equalValueObject = '{"benefit_a":"동일 값","benefit_b":"동일 값"}'
$equalValueStart = $equalValueText.IndexOf('"동일 값"')
$equalValueSecondStart = $equalValueText.IndexOf('"동일 값"', $equalValueStart + 1)
$equalValueUnit = New-BenefitJsonpSourceContentUnit -Snapshot $equalValueSnapshot -UnitReference 'JSONP_DETAIL_OBJECT' -RawStart $equalValueText.IndexOf($equalValueObject) -RawLength $equalValueObject.Length -RawEvidenceText '동일 값' -StructuredFields ([ordered]@{ BenefitDescription='동일 값'; EligibleTarget='동일 값' }) -FieldReferences ([ordered]@{
    BenefitDescription=[pscustomobject][ordered]@{ PropertyName='benefit_a'; FieldReference='JSONP_DETAIL_OBJECT/benefit_a'; ValueStart=$equalValueStart; ValueLength='"동일 값"'.Length }
    EligibleTarget=[pscustomobject][ordered]@{ PropertyName='benefit_b'; FieldReference='JSONP_DETAIL_OBJECT/benefit_b'; ValueStart=$equalValueSecondStart; ValueLength='"동일 값"'.Length }
})
$sameValueCrossPropertyForgery = Copy-ScopeContractData $equalValueUnit
$sameValueCrossPropertyForgery.FieldReferences.BenefitDescription.ValueStart = $equalValueUnit.FieldReferences.EligibleTarget.ValueStart
$sameValueCrossPropertyForgery.FieldReferences.BenefitDescription.ValueLength = $equalValueUnit.FieldReferences.EligibleTarget.ValueLength
Assert-ScopeThrows { Assert-ScopeUnit $sameValueCrossPropertyForgery $equalValueSnapshot } 'Equal JSON values from another property cannot satisfy the claimed property provenance'

$forgedObservationUnit = Copy-ScopeContractData $listObservation.ContentUnits[0]
$forgedObservationUnit.StructuredFields.BusinessName = 'forged business'
Assert-ScopeThrows {
    New-BenefitSourceObservation -SourceRowNumber 2 -Snapshot $listObservation.Snapshot -AdapterId MMA_JSONP_LIST -AdapterVersion '1' -AdapterStatus COMPLETE -ContentUnits @($forgedObservationUnit) -Diagnostics @()
} 'JSONP observation fast path still rejects forged unit provenance'

$dupPropJsonp = 'MmaTestDetail({"success":true,"udgigwanVO":{"udgigwan_cd":"2789","udgigwan_cd":"9999","udgigwan_yhnm":"dup"}});'
$dupPropSnap = New-BenefitSourceSnapshot -SourceUrl 'https://open.mma.go.kr/caisGGGS/mmanrsrSangSeAjaxJsonCall.json?udgigwan_cd=dup' -SourceFormat JSONP -Text $dupPropJsonp -ObservedAt '2026-09-25T00:00:00Z'
$dupObj = '{"udgigwan_cd":"2789","udgigwan_cd":"9999","udgigwan_yhnm":"dup"}'
$dupObjStart = $dupPropJsonp.IndexOf($dupObj)
$dupUnit = [pscustomobject][ordered]@{
    ContractType='SourceContentUnit'; ContractVersion=1; SnapshotId=$dupPropSnap.SnapshotId
    UnitType='JSON_OBJECT'; UnitReference='JSONP_DETAIL_OBJECT'; RawStart=$dupObjStart; RawLength=$dupObj.Length
    RawFragment=$dupObj; RawEvidenceText='2789'
    StructuredFields=[ordered]@{ InstitutionCode='2789' }
    FieldReferences=[ordered]@{ InstitutionCode=[pscustomobject][ordered]@{ PropertyName='udgigwan_cd'; FieldReference='JSONP_DETAIL_OBJECT/udgigwan_cd'; ValueStart=$dupPropJsonp.IndexOf('"2789"'); ValueLength='"2789"'.Length } }
}
Assert-ScopeThrows { Assert-ScopeJsonpUnitCore -Unit $dupUnit -Snapshot $dupPropSnap } 'Duplicate JSONP property key in raw object must be rejected'

$prefixFragUnit = Copy-ScopeContractData $detailObservation.ContentUnits[0]
$prefixFragUnit.RawFragment = $prefixFragUnit.RawFragment + ' '
Assert-ScopeThrows { Assert-ScopeJsonpUnitCore -Unit $prefixFragUnit -Snapshot $detailObservation.Snapshot } 'JSONP validation rejects RawFragment with trailing characters'

$mutSnap = New-BenefitSourceSnapshot -SourceUrl $detailObservation.Snapshot.SourceUrl -SourceFormat JSONP -Text $detail2789Text -ObservedAt $detailObservation.Snapshot.ObservedAt
$mutUnit = [pscustomobject][ordered]@{
    ContractType='SourceContentUnit'; ContractVersion=1; SnapshotId=$mutSnap.SnapshotId
    UnitType='JSON_OBJECT'; UnitReference=$detailObservation.ContentUnits[0].UnitReference
    RawStart=$detailObservation.ContentUnits[0].RawStart; RawLength=$detailObservation.ContentUnits[0].RawLength
    RawFragment=$detailObservation.ContentUnits[0].RawFragment; RawEvidenceText=$detailObservation.ContentUnits[0].RawEvidenceText
    StructuredFields=(Copy-ScopeContractData $detailObservation.ContentUnits[0].StructuredFields)
    FieldReferences=(Copy-ScopeContractData $detailObservation.ContentUnits[0].FieldReferences)
}
Assert-ScopeJsonpUnitCore -Unit $mutUnit -Snapshot $mutSnap
$mutSnap.Text = $mutSnap.Text.Replace('서비스 이용료 3% 할인', '서비스 이용료 9% 할인')
Assert-ScopeThrows { Assert-ScopeJsonpUnitCore -Unit $mutUnit -Snapshot $mutSnap } 'Mutating Snapshot.Text invalidates JSONP fast lookup and fails closed'

$scalarTypesText = 'MmaTestDetail({"s":" abc ","i":42,"bTrue":true,"bFalse":false,"n":null});'
$scalarTypesSnap = New-BenefitSourceSnapshot -SourceUrl 'https://open.mma.go.kr/caisGGGS/mmanrsrSangSeAjaxJsonCall.json?udgigwan_cd=types' -SourceFormat JSONP -Text $scalarTypesText -ObservedAt '2026-09-25T00:00:00Z'
$scalarObjText = '{"s":" abc ","i":42,"bTrue":true,"bFalse":false,"n":null}'
$scalarObjStart = $scalarTypesText.IndexOf($scalarObjText)
$scalarUnit = New-BenefitJsonpSourceContentUnit -Snapshot $scalarTypesSnap -UnitReference 'JSONP_DETAIL_OBJECT' -RawStart $scalarObjStart -RawLength $scalarObjText.Length -RawEvidenceText 'abc' `
    -StructuredFields ([ordered]@{ BusinessName='abc'; Code='42'; FlagT='True'; FlagF='False'; Empty='' }) `
    -FieldReferences ([ordered]@{
        BusinessName=[pscustomobject][ordered]@{ PropertyName='s'; FieldReference='JSONP_DETAIL_OBJECT/s'; ValueStart=$scalarTypesText.IndexOf('" abc "'); ValueLength='" abc "'.Length }
        Code=[pscustomobject][ordered]@{ PropertyName='i'; FieldReference='JSONP_DETAIL_OBJECT/i'; ValueStart=$scalarTypesText.IndexOf('42'); ValueLength='42'.Length }
        FlagT=[pscustomobject][ordered]@{ PropertyName='bTrue'; FieldReference='JSONP_DETAIL_OBJECT/bTrue'; ValueStart=$scalarTypesText.IndexOf('true'); ValueLength='true'.Length }
        FlagF=[pscustomobject][ordered]@{ PropertyName='bFalse'; FieldReference='JSONP_DETAIL_OBJECT/bFalse'; ValueStart=$scalarTypesText.IndexOf('false'); ValueLength='false'.Length }
        Empty=[pscustomobject][ordered]@{ PropertyName='n'; FieldReference='JSONP_DETAIL_OBJECT/n'; ValueStart=$scalarTypesText.IndexOf('null'); ValueLength='null'.Length }
    })
Assert-ScopeJsonpUnitCore -Unit $scalarUnit -Snapshot $scalarTypesSnap

$liveListText = 'MmaTestList({"success":true,"list":[{"udgigwan_cd":"0001","udgigwan_yhnm":"민간","udae_ggm":"","addr":"서울특별시 제외구","udgigwan_telno":"","udggeopjong_gbnm":"기타"},{"udgigwan_cd":"3348","udgigwan_yhnm":"민간","udae_ggm":"우동명가기리야마본진","addr":"서울특별시강남구강남대로84길23(역삼동, (한라클래식 지하1층))","udgigwan_telno":"02-567-0068","udggeopjong_gbnm":"음식점"}]});'
$liveListDocument = New-BenefitSourceDocument -SourceRowNumber 2 -Url 'https://open.mma.go.kr/caisGGGS/mmanrsrListAjaxJsonCallNew.json?callback=MmaTestList' -SourceFormat JSONP -FetchStatus COMPLETE -ContentType 'application/json' -Text $liveListText -ObservedAt '2026-11-22T00:00:00Z'
$liveListObservation = ConvertTo-MmaJsonpListObservation -Document $liveListDocument -ExpectedCallback 'MmaTestList'
Assert-ScopeEqual $liveListObservation.AdapterStatus COMPLETE 'Live MMA list schema with udae_ggm parses completely'
Assert-ScopeEqual @($liveListObservation.ContentUnits).Count 1 'Empty udae_ggm record is skipped even when udgigwan_yhnm contains category text'
Assert-ScopeEqual $liveListObservation.ContentUnits[0].UnitReference JSONP_LIST_ITEM_2 'Live MMA list preserves physical index after skipping empty udae_ggm'
Assert-ScopeEqual $liveListObservation.ContentUnits[0].StructuredFields.BusinessName '우동명가기리야마본진' 'Live MMA list maps BusinessName from udae_ggm over udgigwan_yhnm'
Assert-ScopeEqual $liveListObservation.ContentUnits[0].FieldReferences.BusinessName.FieldReference 'JSONP_LIST_ITEM_2/udae_ggm' 'Live MMA list field reference records udae_ggm provenance'

$liveDetailText = 'MmaTestDetail({"success":true,"udgigwanVO":{"udgigwan_cd":"3348","udgigwan_yhnm":"민간","udae_ggm":"우동명가기리야마본진","addr":"서울특별시강남구강남대로84길23(역삼동, (한라클래식 지하1층))","udgigwan_telno":"02-567-0068","udggeopjong_gbnm":"음식점","udsangse_cn":"서비스 이용료의 20% 할인","uddaesang_cn":"복무중인사람(현역병)","udjyjehan_cn":"없음","udjbjaryo_cn":"복무확인서","hyjeokyong_sjdt":"2024년 11월 12일","hyjeokyong_jrdt":"9999년 12월 31일"}});'
$liveDetailDocument = New-BenefitSourceDocument -SourceRowNumber 2 -Url 'https://open.mma.go.kr/caisGGGS/mmanrsrSangSeAjaxJsonCall.json?udgigwan_cd=3348&callback=MmaTestDetail' -SourceFormat JSONP -FetchStatus COMPLETE -ContentType 'application/json' -Text $liveDetailText -ObservedAt '2026-11-22T00:00:00Z'
$liveDetailObservation = ConvertTo-MmaJsonpDetailObservation -Document $liveDetailDocument -ExpectedCallback 'MmaTestDetail'
Assert-ScopeEqual $liveDetailObservation.AdapterStatus COMPLETE 'Live MMA detail schema with udae_ggm parses completely'
Assert-ScopeEqual $liveDetailObservation.ContentUnits[0].StructuredFields.BusinessName '우동명가기리야마본진' 'Live MMA detail maps BusinessName from udae_ggm over udgigwan_yhnm'
Assert-ScopeEqual $liveDetailObservation.ContentUnits[0].FieldReferences.BusinessName.FieldReference 'JSONP_DETAIL_OBJECT/udae_ggm' 'Live MMA detail field reference records udae_ggm provenance'
Assert-ScopeEqual $liveDetailObservation.ContentUnits[0].StructuredFields.ValidUntilObserved '9999년 12월 31일' 'Live MMA Korean open-ended expiry sentinel remains raw observed data'

Write-Host 'MMA JSONP source observation parser tests passed.'

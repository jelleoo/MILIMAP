Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'lib/benefit-evidence-location-contracts.ps1')
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-hwpx/test-support.ps1')
$adapter=Join-Path $PSScriptRoot 'lib/benefit-evidence/convert-hwpx-source-observation.ps1'
if(Test-Path $adapter){. $adapter}
$valid=Read-InternalBenefitHwpxPackage -Snapshot (New-HwpxTestSnapshot)
Assert-HwpxEqual $valid.Status COMPLETE 'Valid package resolves trusted section'
Assert-HwpxEqual $valid.Sections.Count 1 'One spine member parsed'
Assert-HwpxEqual $valid.Sections[0].EntryName 'Contents/section0.xml' 'Exact package member retained'
Assert-HwpxEqual $valid.Sections[0].SectionOrdinal 1 'Spine ordinal starts at one'
$root="<o:package xmlns:o='http://www.idpf.org/2007/opf'><o:manifest><o:item id='s' href='section0.xml'/></o:manifest><o:spine><o:itemref idref='s'/></o:spine></o:package>"
Assert-HwpxEqual (Read-InternalBenefitHwpxPackage -Snapshot (New-HwpxTestSnapshot -Bytes (New-HwpxTestBytes -RootXml $root))).Status COMPLETE 'Equivalent OPF prefixes accepted'
foreach($badRoot in @('<broken',($root.Replace('http://www.idpf.org/2007/opf','urn:wrong')),($root.Replace('section0.xml','../section0.xml')),($root.Replace('section0.xml','https://bad.example/section0.xml')),($root.Replace("<o:item id='s' href='section0.xml'/>","<o:item id='s' href='section0.xml'/><o:item id='s' href='section0.xml'/>")),($root.Replace("<o:itemref idref='s'/>","<o:itemref idref='s'/><o:itemref idref='s'/>")),($root.Replace('section0.xml','missing.xml')),($root.Replace("idref='s'","idref='missing'")),("<!DOCTYPE x [<!ENTITY ex SYSTEM 'file:///must-not-read'>]>"+$root))){
    Assert-HwpxEqual (Read-InternalBenefitHwpxPackage -Snapshot (New-HwpxTestSnapshot -Bytes (New-HwpxTestBytes -RootXml $badRoot))).Status FAILED 'Untrusted manifest/spine fails closed'
}
foreach($badSection in @('<broken',"<!DOCTYPE x [<!ENTITY ex SYSTEM 'https://must-not-fetch.example'>]><x/>",'<s:sec xmlns:s="urn:wrong"/>')){
    $partial=Read-InternalBenefitHwpxPackage -Snapshot (New-HwpxTestSnapshot -Bytes (New-HwpxTestBytes -Sections @('<hs:sec xmlns:hs="http://www.hancom.co.kr/hwpml/2011/section"/>',$badSection)))
    Assert-HwpxEqual $partial.Status PARTIAL 'Bad section is isolated'
    Assert-HwpxEqual $partial.Sections.Count 1 'Only safe section retained'
    Assert-HwpxEqual $partial.Diagnostics.Count 1 'Isolation diagnostic retained'
}
foreach($bytes in @((New-HwpxTestBytes -MissingRoot),(New-HwpxTestBytes -Mimetype wrong),(New-HwpxTestBytes -ExtraEntries @([pscustomobject]@{Name='../unsafe';Text='x'})),(New-HwpxTestBytes -ExtraEntries @([pscustomobject]@{Name='Contents/SECTION0.xml';Text='x'})),(New-HwpxTestBytes -ExtraEntries @(1..257|ForEach-Object{[pscustomobject]@{Name="extra/$_";Text='x'}})))){
    Assert-HwpxEqual (Read-InternalBenefitHwpxPackage -Snapshot (New-HwpxTestSnapshot -Bytes $bytes)).Status FAILED 'Unsafe or bounded-invalid ZIP rejected'
}
Write-Host 'HWPX package/XML tests passed.'
$document=New-HwpxTestDocument
$observation=ConvertTo-BenefitHwpxObservation -Document $document
Assert-HwpxEqual $observation.AdapterStatus COMPLETE 'Supported table parses completely'
Assert-HwpxEqual $observation.ContentUnits.Count 2 'Both independent business rows retained'
$unit=$observation.ContentUnits[0];$index=$observation.DocumentValidationIndex
Assert-HwpxEqual $unit.UnitReference HWPX_SECTION_1_TABLE_1_ROW_2 'Byte-derived physical row ordinal'
Assert-HwpxEqual $unit.StructuredFields.BusinessName '합성가게 A' 'Existing semantic map reused'
Assert-HwpxEqual $unit.FieldReferences.BenefitDescription.PhysicalReference 'section/1/table/1/row/2/cell/4' 'Exact physical cell retained'
Assert-HwpxEqual $unit.FieldReferences.BenefitDescription.SourceText '합성 A 혜택' 'Source text is from cell bytes'
Assert-HwpxEqual $index.AdapterId HWPX_GENERIC 'Fixed adapter metadata'
Assert-HwpxEqual $index.ExtractorId BUILTIN_HWPX_XML 'Native extractor metadata'
function Get-HwpxTestObservation {param([string]$Content);ConvertTo-BenefitHwpxObservation -Document (New-HwpxTestDocument -Bytes (New-HwpxTestBytes -Sections @((New-HwpxTestSection $Content))))}
$table=New-HwpxTestTable
$title=New-HwpxTestRow @((New-HwpxTestCell '합성 제목' -Span "<hp:cellSpan rowSpan='1' colSpan='4'/>"))
$decorated=$table.Replace('<hp:tbl>',"<hp:tbl>$title")
$decoratedObservation=Get-HwpxTestObservation $decorated
Assert-HwpxEqual $decoratedObservation.AdapterStatus COMPLETE 'Merged decorative title permitted'
Assert-HwpxEqual $decoratedObservation.ContentUnits[0].UnitReference HWPX_SECTION_1_TABLE_1_ROW_3 'Physical title row still counted'
foreach($content in @($table.Replace('업소명','이름미지원'),(New-HwpxTestTable -Rows @((New-HwpxTestRow @((New-HwpxTestCell '업소'),(New-HwpxTestCell '혜택'))),(New-HwpxTestRow @((New-HwpxTestCell '명'),(New-HwpxTestCell '정보'))))),'<hp:p><hp:run><hp:t>업소명 합성가게 A 혜택</hp:t></hp:run></hp:p>')){
    Assert-HwpxEqual (Get-HwpxTestObservation $content).AdapterStatus UNSUPPORTED 'No single supported BusinessName header; no paragraph/positional inference'
}
foreach($header in @(@('업소명','업체명','혜택'),@('업소명','혜택','할인정보'))){
    $duplicate=New-HwpxTestTable -Rows @((New-HwpxTestRow @($header|ForEach-Object{New-HwpxTestCell $_})))
    Assert-HwpxEqual (Get-HwpxTestObservation $duplicate).AdapterStatus PARTIAL 'Duplicate semantic header mapping fails closed'
}
foreach($badCell in @((New-HwpxTestCell '업소명' -Span "<hp:cellSpan rowSpan='1' colSpan='2'/>"),(New-HwpxTestCell '업소명' -Span ''),(New-HwpxTestCell '업소명' -Attributes "rowSpan='2' colSpan='1'"))){
    Assert-HwpxEqual (Get-HwpxTestObservation ($table.Replace((New-HwpxTestCell '업소명'),$badCell))).AdapterStatus PARTIAL 'Merged/unknown/conflicting semantic header span rejected'
}
foreach($badInner in @('<hp:p><hp:run><hp:pic/></hp:run></hp:p>','<hp:p><hp:run><hp:equation/></hp:run></hp:p>','<hp:p><hp:run><hp:footNote/></hp:run></hp:p>',(New-HwpxTestTable),'<hp:p><hp:run><hp:unknown/></hp:run></hp:p>')){
    $bad=Get-HwpxTestObservation ($table.Replace((New-HwpxTestCell '합성 A 혜택'),(New-HwpxTestCell -Inner $badInner)))
    Assert-HwpxEqual $bad.AdapterStatus PARTIAL 'Unsupported semantic inline content rejected'
    Assert-HwpxEqual $bad.ContentUnits.Count 1 'Bad row isolated; nested table never separately promoted'
}
$merged=Get-HwpxTestObservation ($table.Replace((New-HwpxTestCell '합성 A 혜택'),(New-HwpxTestCell '합성 A 혜택' -Span "<hp:cellSpan rowSpan='2' colSpan='1'/>")))
Assert-HwpxEqual $merged.AdapterStatus PARTIAL 'Merged mapped data rejected'
$textInner='<hp:p><hp:run><hp:t>  합</hp:t></hp:run><hp:run><hp:t>성</hp:t><hp:lineBreak/><hp:t>혜택</hp:t><hp:tab/><hp:t>A</hp:t></hp:run></hp:p><hp:p><hp:run><hp:t>다음  </hp:t></hp:run></hp:p>'
$textObservation=Get-HwpxTestObservation ($table.Replace((New-HwpxTestCell '합성 A 혜택'),(New-HwpxTestCell -Inner $textInner)))
Assert-HwpxEqual $textObservation.ContentUnits[0].StructuredFields.BenefitDescription "합성`n혜택`tA`n다음" 'Runs/paragraph/line/tab fidelity with outer trim only'
$multi=Get-HwpxTestObservation ($table+$table)
Assert-HwpxEqual $multi.ContentUnits.Count 4 'All independent tables processed'
Assert-HwpxEqual $multi.ContentUnits[2].UnitReference HWPX_SECTION_1_TABLE_2_ROW_2 'Top-level table ordinal is physical'
$renamed=(New-HwpxTestSection).Replace('xmlns:hp=','xmlns:q=').Replace('hp:','q:')
Assert-HwpxEqual (ConvertTo-BenefitHwpxObservation -Document (New-HwpxTestDocument -Bytes (New-HwpxTestBytes -Sections @($renamed)))).AdapterStatus COMPLETE 'Equivalent paragraph prefix accepted'
Assert-HwpxEqual (ConvertTo-BenefitHwpxObservation -Document (New-HwpxTestDocument -Bytes (New-HwpxTestBytes -Sections @((New-HwpxTestSection).Replace('http://www.hancom.co.kr/hwpml/2011/paragraph','urn:wrong'))))).AdapterStatus UNSUPPORTED 'Wrong paragraph namespace never trusted'
foreach($mutation in @({param($u)$u.PhysicalPath='section/2/table/1/row/2'},{param($u)$u.FieldReferences.BenefitDescription.PhysicalReference='section/1/table/1/row/3/cell/4'},{param($u)$u.FieldReferences.BenefitDescription.SourceText='forged'},{param($u)$u.StructuredFields.BenefitDescription='forged'},{param($u)$u.ExtractorVersion='2'},{param($u)$u.AdapterId='forged'},{param($u)$u.UnitReference='HWPX_SECTION_1_TABLE_1_ROW_99'})){
    $forged=Copy-ScopeContractData $unit;&$mutation $forged
    Assert-HwpxThrows {Assert-ScopeDocumentUnit -Unit $forged -Snapshot $observation.Snapshot -ValidationIndex $index} 'Parsed-byte unit tampering rejected'
}
$foreign=ConvertTo-BenefitHwpxObservation -Document (New-HwpxTestDocument -Url 'https://city.example.go.kr/other.hwpx')
Assert-HwpxThrows {Assert-ScopeDocumentUnit -Unit $unit -Snapshot $observation.Snapshot -ValidationIndex $foreign.DocumentValidationIndex} 'Cross-snapshot index rejected'
Write-Host 'HWPX table/text/provenance tests passed.'

# Whole-branch review regressions: exercise raw ZIP/XML, not parser doubles.
$reviewCases=@(
    @{Name='Whitespace-only semantic text run';Action={
        $inner='<hp:p><hp:run><hp:t>합성</hp:t></hp:run><hp:run><hp:t> </hp:t></hp:run><hp:run><hp:t>A 혜택</hp:t></hp:run></hp:p>'
        $actual=Get-HwpxTestObservation ($table.Replace((New-HwpxTestCell '합성 A 혜택'),(New-HwpxTestCell -Inner $inner)))
        Assert-HwpxEqual $actual.AdapterStatus COMPLETE 'Ordinary text-only run remains supported'
        Assert-HwpxEqual $actual.ContentUnits[0].StructuredFields.BenefitDescription '합성 A 혜택' 'Whitespace-only hp:t must preserve its source space'
        Assert-HwpxEqual $actual.ContentUnits[0].FieldReferences.BenefitDescription.SourceText '합성 A 혜택' 'Physical source text preserves run spacing'
    }},
    @{Name='Unsupported semantic header';Action={
        $header=New-HwpxTestRow @((New-HwpxTestCell '업소명'),(New-HwpxTestCell '주소'),(New-HwpxTestCell '혜택'),(New-HwpxTestCell -Inner '<hp:p><hp:run><hp:t>이용조건</hp:t><hp:pic/></hp:run></hp:p>'))
        $row=New-HwpxTestRow @('합성가게 A','서울특별시 마포구 테스트로 12','합성 A 혜택','평일 한정'|ForEach-Object{New-HwpxTestCell $_})
        $actual=Get-HwpxTestObservation (New-HwpxTestTable -Rows @($header,$row))
        Assert-HwpxEqual $actual.AdapterStatus PARTIAL 'Unsupported semantic header must not silently discard a condition'
        Assert-HwpxEqual $actual.ContentUnits.Count 0 'Unusable header exposes no business row'
    }},
    @{Name='Malformed row namespace';Action={
        $bRow=New-HwpxTestRow @('합성가게 B','서울특별시 마포구 테스트로 34','02-0000-0034','합성 B 혜택'|ForEach-Object{New-HwpxTestCell $_})
        $badRow=$bRow.Replace('<hp:tr>',"<wrong:tr xmlns:wrong='urn:wrong'>").Replace('</hp:tr>','</wrong:tr>')
        $actual=Get-HwpxTestObservation ($table.Replace($bRow,$badRow))
        Assert-HwpxEqual $actual.AdapterStatus PARTIAL 'Wrong-namespace row cannot silently become identity absence'
        $badCell=(New-HwpxTestCell '합성가게 B').Replace('<hp:tc ',"<wrong:tc xmlns:wrong='urn:wrong' ").Replace('</hp:tc>','</wrong:tc>')
        $actual=Get-HwpxTestObservation ($table.Replace((New-HwpxTestCell '합성가게 B'),$badCell))
        Assert-HwpxEqual $actual.AdapterStatus PARTIAL 'Wrong-namespace mapped cell is not trusted'
    }},
    @{Name='Unsupported separator children';Action={
        foreach($separator in @('lineBreak','tab')){
            $inner="<hp:p><hp:run><hp:t>합성</hp:t><hp:$separator><hp:pic/></hp:$separator><hp:t>A 혜택</hp:t></hp:run></hp:p>"
            $actual=Get-HwpxTestObservation ($table.Replace((New-HwpxTestCell '합성 A 혜택'),(New-HwpxTestCell -Inner $inner)))
            Assert-HwpxEqual $actual.AdapterStatus PARTIAL 'Unsupported child cannot hide inside a line/tab separator'
            Assert-HwpxEqual $actual.ContentUnits.Count 1 'Unsafe A row isolated while B physical row is retained'
        }
        $inner='<hp:p><hp:run><hp:t>합성</hp:t><hp:lineBreak>'+(New-HwpxTestTable)+'</hp:lineBreak><hp:t>A 혜택</hp:t></hp:run></hp:p>'
        $actual=Get-HwpxTestObservation ($table.Replace((New-HwpxTestCell '합성 A 혜택'),(New-HwpxTestCell -Inner $inner)))
        Assert-HwpxEqual $actual.AdapterStatus PARTIAL 'Nested table cannot hide inside a separator'
        Assert-HwpxEqual $actual.ContentUnits.Count 1 'Hidden nested table is not independent evidence'
    }}
)
$reviewFailures=[Collections.Generic.List[string]]::new()
foreach($case in $reviewCases){try{& $case.Action;Write-Host "PASS: $($case.Name)"}catch{$reviewFailures.Add("$($case.Name): $($_.Exception.Message)");Write-Host "FAIL: $($case.Name): $($_.Exception.Message)"}}
if($reviewFailures.Count){throw ($reviewFailures -join "`n")}

$decorativeHeader=New-HwpxTestRow @((New-HwpxTestCell '업소명'),(New-HwpxTestCell '주소'),(New-HwpxTestCell '혜택'),(New-HwpxTestCell -Inner '<hp:p><hp:run><hp:t>참고</hp:t><hp:pic/></hp:run></hp:p>'))
$decorativeData=New-HwpxTestRow @((New-HwpxTestCell '합성가게 A'),(New-HwpxTestCell '서울특별시 마포구 테스트로 12'),(New-HwpxTestCell '합성 A 혜택'),(New-HwpxTestCell -Inner '<hp:p><hp:run><hp:pic/></hp:run></hp:p>'))
Assert-HwpxEqual (Get-HwpxTestObservation (New-HwpxTestTable -Rows @($decorativeHeader,$decorativeData))).AdapterStatus COMPLETE 'Safely unmapped decorative complex column remains ignorable'

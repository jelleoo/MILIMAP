Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'lib/benefit-evidence-location-contracts.ps1')
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-pdf/test-support.ps1')
. (Join-Path $PSScriptRoot 'lib/benefit-evidence/convert-pdf-source-observation.ps1')
$document=New-PdfTestDocument
$o=ConvertTo-BenefitPdfObservation -Document $document
Assert-PdfEqual $o.AdapterStatus 'COMPLETE' 'Safe ruled business table'
Assert-PdfEqual $o.ContentUnits.Count 2 'Two independent business rows'
Assert-PdfEqual $o.ContentUnits[0].StructuredFields.BusinessName '합성가게 A' 'Korean native identity'
Assert-PdfEqual $o.ContentUnits[0].StructuredFields.BenefitDescription "합성 A 혜택`n합성 조건 A" 'Multiline physical cell text'
Assert-PdfEqual $o.ContentUnits[1].StructuredFields.BenefitDescription '합성 B 혜택' 'No cross-business mixing'
Assert-PdfEqual $o.ContentUnits[0].UnitReference 'PDF_PAGE_1_TABLE_1_ROW_2' 'Physical row reference'
Assert-PdfEqual $o.ContentUnits[0].FieldReferences.BenefitDescription.PhysicalReference 'page/1/table/1/row/2/cell/4' 'Exact physical cell'
Assert-PdfEqual $o.ContentUnits[0].ExtractorId 'PDFPIG' 'Native parser provenance'
Assert-PdfEqual $o.ContentUnits[0].ExtractorVersion '0.1.16' 'Exact version provenance'
foreach($case in @(@('decorative','COMPLETE',2),@('multi-table','COMPLETE',4),@('multi-page','COMPLETE',4),@('repeated','COMPLETE',4),@('native-no-grid','UNSUPPORTED',0),@('image-only','UNSUPPORTED',0),@('truncated','FAILED',0),@('encrypted','UNSUPPORTED',0),@('missing-name-header','UNSUPPORTED',0),@('duplicate-header','PARTIAL',0),@('ambiguous-header','PARTIAL',0),@('merged-header','PARTIAL',0),@('merged-value','PARTIAL',1),@('broken','PARTIAL',0),@('crossing','PARTIAL',1),@('overlap','PARTIAL',1),@('continuation','PARTIAL',1),@('empty-name','COMPLETE',1),@('rotation-90','COMPLETE',2),@('rotation-180','COMPLETE',2),@('rotation-270','COMPLETE',2))){
    $result=ConvertTo-BenefitPdfObservation -Document (New-PdfTestDocument $case[0])
    Assert-PdfEqual $result.AdapterStatus $case[1] "$($case[0]) operational boundary"
    Assert-PdfEqual $result.ContentUnits.Count $case[2] "$($case[0]) safe audit units"
}
foreach($property in @('UnitReference','PhysicalPath','RawEvidenceText','ExtractionConfigHash','ExtractorVersion')){
    $bad=Copy-ScopeContractData $o.ContentUnits[0];$bad.$property='forged'
    Assert-PdfThrows {Assert-ScopeUnit -Unit $bad -Snapshot $o.Snapshot -DocumentValidationIndex $o.DocumentValidationIndex} "Tampered $property"
}
foreach($property in @('FieldReference','PhysicalReference','SourceText')){
    $bad=Copy-ScopeContractData $o.ContentUnits[0];$bad.FieldReferences.BenefitDescription.$property='forged'
    Assert-PdfThrows {Assert-ScopeUnit -Unit $bad -Snapshot $o.Snapshot -DocumentValidationIndex $o.DocumentValidationIndex} "Tampered cell $property"
}
$bad=Copy-ScopeContractData $o.ContentUnits[0];$bad.StructuredFields.BenefitDescription='forged'
Assert-PdfThrows {Assert-ScopeUnit -Unit $bad -Snapshot $o.Snapshot -DocumentValidationIndex $o.DocumentValidationIndex} 'Tampered structured field'
$other=ConvertTo-BenefitPdfObservation -Document (New-PdfTestDocument 'repeated')
Assert-PdfThrows {Assert-ScopeUnit -Unit $o.ContentUnits[0] -Snapshot $o.Snapshot -DocumentValidationIndex $other.DocumentValidationIndex} 'Cross-snapshot index'
$forged=Copy-ScopeContractData $o.Snapshot;$forged.Bytes=(New-PdfTestDocument 'repeated').Bytes
Assert-PdfThrows {ConvertTo-BenefitPdfObservation -Document $document -Snapshot $forged} 'Forged old hash with replacement bytes'
$later=ConvertTo-BenefitPdfObservation -Document (New-PdfTestDocument 'malformed-later')
Assert-PdfEqual $later.AdapterStatus 'FAILED' 'Later-page parser trust failure'
Assert-PdfEqual $later.ContentUnits.Count 0 'Later-page failure clears earlier units'
Write-Host 'PDF source observation tests passed.'

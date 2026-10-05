Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'lib/benefit-evidence-location-contracts.ps1')
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-pdf/test-support.ps1')
. (Join-Path $PSScriptRoot 'lib/benefit-evidence/convert-pdf-source-observation.ps1')
$alias=ConvertTo-BenefitPdfObservation -Document (New-PdfTestDocument 'official-alias')
Assert-PdfEqual ($alias.ContentUnits[0].StructuredFields.Contains('Address')) $true 'Reviewed exact address header maps actual cell'
Assert-PdfEqual $alias.ContentUnits[0].StructuredFields.Address '서울특별시 마포구 테스트로 12' 'Reviewed address source text'
Assert-PdfEqual $alias.ContentUnits[0].StructuredFields.Phone '02-0000-0012' 'Reviewed exact phone header maps actual cell'
$nonexact=ConvertTo-BenefitPdfObservation -Document (New-PdfTestDocument 'nonexact-alias')
Assert-PdfEqual ($nonexact.ContentUnits[0].StructuredFields.Contains('Address')) $false 'No contains/fuzzy address mapping'
Assert-PdfEqual ($nonexact.ContentUnits[0].StructuredFields.Contains('Phone')) $false 'No contains/fuzzy phone mapping'
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
foreach($case in @(@('decorative','COMPLETE',2),@('multi-table','COMPLETE',4),@('multi-page','COMPLETE',4),@('repeated','COMPLETE',4),@('native-no-grid','UNSUPPORTED',0),@('image-only','UNSUPPORTED',0),@('truncated','FAILED',0),@('encrypted','UNSUPPORTED',0),@('missing-name-header','UNSUPPORTED',0),@('duplicate-header','PARTIAL',0),@('ambiguous-header','PARTIAL',0),@('merged-header','PARTIAL',0),@('merged-value','PARTIAL',1),@('broken','PARTIAL',0),@('crossing','PARTIAL',1),@('overlap','PARTIAL',1),@('continuation','PARTIAL',1),@('empty-name','PARTIAL',1),@('rotation-90','COMPLETE',2),@('rotation-180','COMPLETE',2),@('rotation-270','COMPLETE',2))){
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
$dense=Invoke-BenefitPdfNativeProjection -Bytes (New-PdfTestBytes -Content ('20 20 m 30 20 l S '*513))
Assert-PdfEqual $dense.Status COMPLETE 'Native parser permits bounded source below path quota'
Assert-PdfThrows {Get-InternalBenefitPdfPageGrids -Page $dense.Projection.Pages[0]} 'Grid segment quota precedes component quadratic work'
$glyphs='BT /F1 12 Tf 30 50 Td (a) Tj ET '*129
$grid='20 20 m 120 20 l S 20 120 m 120 120 l S 20 20 m 20 120 l S 120 20 m 120 120 l S '
$crowded=Invoke-BenefitPdfNativeProjection -Bytes (New-PdfTestBytes -Content ($grid+$glyphs))
Assert-PdfEqual $crowded.Status COMPLETE 'Native small crowded grid opens within native quotas'
Assert-PdfThrows {Get-InternalBenefitPdfPageGrids -Page $crowded.Projection.Pages[0]} 'Cell glyph quota must precede quadratic overlap work'
$wideGrid=@(foreach($n in 0..29){$v=10+$n*9;"$v 10 m $v 271 l S 10 $v m 271 $v l S"}) -join ' '
$scattered=@(foreach($n in 0..599){$x=14+($n%29)*9;$y=14+[Math]::Floor($n/29)*9;"BT /F1 2 Tf $x $y Td (a) Tj ET"}) -join ' '
$wideBytes=New-PdfTestBytes -Content ($wideGrid+' '+$scattered)
$wide=Invoke-BenefitPdfNativeProjection -Bytes $wideBytes
Assert-PdfEqual $wide.Status COMPLETE 'Native spread glyphs open within parser quotas'
try {$null=Get-InternalBenefitPdfPageGrids -Page $wide.Projection.Pages[0];throw 'Not rejected'}
catch {Assert-PdfEqual $_.Exception.Message 'PDF glyph/cell comparison quota exceeded' 'Intersection budget rejects before scanning glyphs against every cell'}
$budget=New-InternalBenefitPdfWorkBudget;$budget.CellChecks=0
Assert-PdfThrows {Get-InternalBenefitPdfPageGrids -Page $crowded.Projection.Pages[0] -WorkBudget $budget} 'Exhausted shared document work budget never resets per page'
$budget=New-InternalBenefitPdfWorkBudget;$budget.DeadlineMilliseconds=0;Start-Sleep -Milliseconds 10
try {$null=Get-InternalBenefitPdfPageGrids -Page $crowded.Projection.Pages[0] -WorkBudget $budget;throw 'Not rejected'}
catch {Assert-PdfEqual $_.Exception.Message 'PDF geometry deadline exceeded' 'Expired geometry deadline fails closed'}
$quotaDocument=New-BenefitSourceDocument -SourceRowNumber 2 -Url 'https://city.example.go.kr/quota.pdf' -SourceFormat PDF -FetchStatus COMPLETE -Text '' -Bytes $wideBytes -ObservedAt '2026-10-05T00:00:00Z'
$quotaObservation=ConvertTo-BenefitPdfObservation -Document $quotaDocument
Assert-PdfEqual $quotaObservation.AdapterStatus FAILED 'Geometry quota failure invalidates document evidence'
Assert-PdfEqual $quotaObservation.ContentUnits.Count 0 'Geometry quota never leaves partial semantic evidence'
Write-Host 'PDF final-review safety/work-budget tests passed.'
$hint=ConvertTo-BenefitPdfObservation -Document (New-PdfTestDocument 'uncovered-heading')
Assert-PdfEqual $hint.AdapterStatus PARTIAL 'Uncovered exact native identity header is rejection only'
Assert-PdfEqual $hint.ContentUnits.Count 2 'No evidence row is invented from uncovered heading'
Assert-PdfEqual $hint.ContentUnits[0].UnitReference 'PDF_PAGE_1_TABLE_1_ROW_2' 'Rejection hint must not change physical table ordinal'
$fourCells=@(foreach($v in @(20,70,120)){"$v 20 m $v 120 l S 20 $v m 120 $v l S"}) -join ' '
$construction=Invoke-BenefitPdfNativeProjection -Bytes (New-PdfTestBytes -Content $fourCells)
$deadlineBudget=New-InternalBenefitPdfWorkBudget;$deadlineBudget.Clock=[pscustomobject]@{ElapsedMilliseconds=0}
$coverageCalls=[pscustomobject]@{Count=0};$originalCoverage=${function:Test-InternalBenefitPdfCoverage}
Set-Item Function:Test-InternalBenefitPdfCoverage {param($Segments,$Coordinate,$Low,$High)$coverageCalls.Count++;$deadlineBudget.Clock.ElapsedMilliseconds=10001;& $originalCoverage @PSBoundParameters}
try {
    Assert-PdfThrows {Get-InternalBenefitPdfPageGrids -Page $construction.Projection.Pages[0] -WorkBudget $deadlineBudget} 'Deadline applies during grid construction, not only after it'
    Assert-PdfEqual ($coverageCalls.Count -le 4) $true 'Expired grid construction stops before another cell coverage scan'
} finally {Set-Item Function:Test-InternalBenefitPdfCoverage $originalCoverage}

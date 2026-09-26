$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-location/test-support.ps1')
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-xlsx/test-support.ps1')
$contracts = Join-Path $PSScriptRoot 'lib/benefit-evidence-location-contracts.ps1'
. $contracts
. (Join-Path $PSScriptRoot 'lib/benefit-evidence/convert-xlsx-source-observation.ps1')

Assert-ScopeTrue ($null -ne (Get-Command New-BenefitXlsxValidationIndex -ErrorAction SilentlyContinue)) 'XLSX validation index must be available'
$bytes = New-XlsxTestBytes
$snapshot = New-BenefitSourceSnapshot -SourceUrl 'https://city.example.go.kr/benefits.xlsx' -SourceFormat XLSX -Text '' -Bytes $bytes -ObservedAt '2026-09-26T00:00:00Z'
$index = New-BenefitXlsxValidationIndex -Snapshot $snapshot
Assert-ScopeEqual $index.Sheets[0].Name '음식점' 'Validation index resolves workbook sheet'
Assert-ScopeTrue ($null -ne (Get-Command ConvertTo-BenefitXlsxObservation -ErrorAction SilentlyContinue)) 'XLSX observation converter must be available'
$document=New-BenefitSourceDocument -SourceRowNumber 2 -Url 'https://city.example.go.kr/benefits.xlsx' -SourceFormat XLSX -FetchStatus COMPLETE -Text '' -Bytes $bytes -ObservedAt '2026-09-26T00:00:00Z'
$converted=ConvertTo-BenefitXlsxObservation -Document $document
Assert-ScopeEqual $converted.ContractType 'SourceObservation' 'Converter returns a source observation for XLSX rows'
Assert-ScopeEqual $converted.ContentUnits.Count 1 'Converter creates one deterministic data-row unit'
Assert-ScopeEqual $converted.ContentUnits[0].UnitReference 'XLSX_SHEET_1_ROW_22' 'Unit preserves physical sheet and row'
Assert-ScopeEqual $converted.ContentUnits[0].FieldReferences.BusinessName.CellReference 'B22' 'Business name points to exact cell'
Assert-ScopeEqual $converted.ContentUnits[0].UnitReference 'XLSX_SHEET_1_ROW_22' 'Observation retains the selected XLSX row'
Assert-ScopeObservation -Observation $converted -XlsxValidationIndex $converted.XlsxValidationIndex
$slice = New-RelevantBenefitEvidenceSlice -Observation $converted -Unit $converted.ContentUnits[0] -IdentityEvidence @('FULL_NAME_MATCH') -XlsxValidationIndex $converted.XlsxValidationIndex
Assert-ScopeEqual $slice.ScopeType 'XLSX_ROW' 'XLSX slices retain their format-specific scope type'
Assert-ScopeEqual $slice.FieldReferences.BusinessName.CellReference 'B22' 'XLSX slice retains the exact cell provenance'
Assert-RelevantBenefitEvidenceSlice -Slice $slice -Document $document -SourceRowNumber 2 -XlsxValidationIndex $converted.XlsxValidationIndex
$forgedSlice = Copy-ScopeContractData $slice
$forgedSlice | Add-Member -NotePropertyName RawStart -NotePropertyValue 0
Assert-ScopeThrows { Assert-RelevantBenefitEvidenceSlice -Slice $forgedSlice -Document $document -SourceRowNumber 2 -XlsxValidationIndex $converted.XlsxValidationIndex } 'XLSX slices must reject synthetic raw-span properties'
$otherDocument = New-BenefitSourceDocument -SourceRowNumber 2 -Url 'https://city.example.go.kr/other.xlsx' -SourceFormat XLSX -FetchStatus COMPLETE -Text '' -Bytes (New-XlsxTestBytes -Name '다른 가게') -ObservedAt '2026-09-26T00:00:00Z'
Assert-ScopeThrows { Assert-RelevantBenefitEvidenceSlice -Slice $slice -Document $otherDocument -SourceRowNumber 2 -XlsxValidationIndex $converted.XlsxValidationIndex } 'A slice cannot reuse a validated XLSX index from another snapshot'

$multiRowDocument = New-BenefitSourceDocument -SourceRowNumber 2 -Url 'https://city.example.go.kr/multi-row.xlsx' -SourceFormat XLSX -FetchStatus COMPLETE -Text '' -Bytes (New-XlsxTestBytes -DuplicateBusinessNameCell) -ObservedAt '2026-09-26T00:00:00Z'
$multiRowObservation = ConvertTo-BenefitXlsxObservation -Document $multiRowDocument
$script:byteHashCallCount = 0
$script:originalByteHash = (Get-Item Function:Get-BenefitEvidenceByteHash).ScriptBlock
function Get-BenefitEvidenceByteHash {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    $script:byteHashCallCount++
    return & $script:originalByteHash -Bytes $Bytes
}
try {
    Assert-ScopeUnit -Unit $multiRowObservation.ContentUnits[0] -Snapshot $multiRowObservation.Snapshot -XlsxValidationIndex $multiRowObservation.XlsxValidationIndex
    Assert-ScopeEqual $script:byteHashCallCount 1 'Standalone XLSX unit validation hashes its snapshot once'
    Write-Host "XLSX standalone-unit byte-hash calls: $script:byteHashCallCount"

    $script:byteHashCallCount = 0
    Assert-ScopeObservation -Observation $multiRowObservation -XlsxValidationIndex $multiRowObservation.XlsxValidationIndex
    Assert-ScopeEqual $script:byteHashCallCount 1 'Observation validation hashes an XLSX snapshot once regardless of ContentUnit count'
    Write-Host "XLSX observation byte-hash calls: $script:byteHashCallCount"
} finally {
    Set-Item Function:Get-BenefitEvidenceByteHash -Value $script:originalByteHash
    Remove-Variable -Scope Script -Name originalByteHash -ErrorAction SilentlyContinue
}

$formulaDocument = New-BenefitSourceDocument -SourceRowNumber 2 -Url 'https://city.example.go.kr/formula.xlsx' -SourceFormat XLSX -FetchStatus COMPLETE -Text '' -Bytes (New-XlsxTestBytes -FormulaBenefit) -ObservedAt '2026-09-26T00:00:00Z'
$formulaConverted = ConvertTo-BenefitXlsxObservation -Document $formulaDocument
Assert-ScopeEqual $formulaConverted.AdapterStatus PARTIAL 'A selected formula cell makes the affected XLSX row unusable'
Assert-ScopeEqual $formulaConverted.ContentUnits.Count 0 'A formula-backed semantic field cannot yield a candidate row'
Assert-ScopeTrue (@($formulaConverted.Diagnostics | Where-Object { $_.Code -eq 'XLSX_ROW_UNUSABLE' }).Count -eq 1) 'A selected formula row remains auditable as partial parsing'

foreach ($unsafeBusinessNameBytes in @((New-XlsxTestBytes -FormulaBusinessName), (New-XlsxTestBytes -UnsupportedBusinessName))) {
    $unsafeBusinessNameDocument = New-BenefitSourceDocument -SourceRowNumber 2 -Url 'https://city.example.go.kr/unsafe-business-name.xlsx' -SourceFormat XLSX -FetchStatus COMPLETE -Text '' -Bytes $unsafeBusinessNameBytes -ObservedAt '2026-09-26T00:00:00Z'
    $unsafeBusinessNameConverted = ConvertTo-BenefitXlsxObservation -Document $unsafeBusinessNameDocument
    Assert-ScopeEqual $unsafeBusinessNameConverted.AdapterStatus PARTIAL 'A physically present but unsafe BusinessName cell blocks the observation'
    Assert-ScopeEqual $unsafeBusinessNameConverted.ContentUnits.Count 0 'An unsafe BusinessName cell cannot yield a candidate unit'
    Assert-ScopeTrue (@($unsafeBusinessNameConverted.Diagnostics | Where-Object { $_.Code -eq 'XLSX_ROW_UNUSABLE' }).Count -eq 1) 'An unsafe BusinessName cell remains auditable as a blocking row'
}

foreach ($cellType in @('inlineStr','str','n')) {
    $typedDocument = New-BenefitSourceDocument -SourceRowNumber 2 -Url "https://city.example.go.kr/$cellType.xlsx" -SourceFormat XLSX -FetchStatus COMPLETE -Text '' -Bytes (New-XlsxTestBytes -BenefitCellType $cellType) -ObservedAt '2026-09-26T00:00:00Z'
    $typedObservation = ConvertTo-BenefitXlsxObservation -Document $typedDocument
    Assert-ScopeEqual $typedObservation.AdapterStatus COMPLETE "Approved XLSX cell type $cellType is accepted without conversion inference"
    Assert-ScopeEqual $typedObservation.ContentUnits[0].FieldReferences.BenefitDescription.CellType $cellType "Approved XLSX cell type $cellType is preserved in field provenance"
}
$unsupportedSelectedDocument = New-BenefitSourceDocument -SourceRowNumber 2 -Url 'https://city.example.go.kr/unsupported.xlsx' -SourceFormat XLSX -FetchStatus COMPLETE -Text '' -Bytes (New-XlsxTestBytes -BenefitCellType b) -ObservedAt '2026-09-26T00:00:00Z'
$unsupportedSelectedConverted = ConvertTo-BenefitXlsxObservation -Document $unsupportedSelectedDocument
Assert-ScopeEqual $unsupportedSelectedConverted.AdapterStatus PARTIAL 'An unsupported selected XLSX cell fails closed'
Assert-ScopeEqual $unsupportedSelectedConverted.ContentUnits.Count 0 'An unsupported selected XLSX cell cannot yield a candidate row'

$missingBenefitDocument = New-BenefitSourceDocument -SourceRowNumber 2 -Url 'https://city.example.go.kr/missing-benefit.xlsx' -SourceFormat XLSX -FetchStatus COMPLETE -Text '' -Bytes (New-XlsxTestBytes -MissingBenefitCell) -ObservedAt '2026-09-26T00:00:00Z'
$missingBenefitConverted = ConvertTo-BenefitXlsxObservation -Document $missingBenefitDocument
Assert-ScopeEqual $missingBenefitConverted.ContentUnits.Count 1 'An unclaimed missing XLSX cell does not invent a field'
$claimedMissingFields = Copy-ScopeContractData $missingBenefitConverted.ContentUnits[0].StructuredFields
$claimedMissingReferences = Copy-ScopeContractData $missingBenefitConverted.ContentUnits[0].FieldReferences
$claimedMissingFields['BenefitDescription'] = 'invented'
$claimedMissingReferences['BenefitDescription'] = [pscustomobject]@{ FieldReference='XLSX_SHEET_1_ROW_22/BenefitDescription'; HeaderCellReference='F2'; OriginalHeader='할인내용'; CellReference='F22'; CellType='s'; RawValue='7' }
Assert-ScopeThrows { New-BenefitXlsxSourceContentUnit -Snapshot $missingBenefitConverted.Snapshot -XlsxValidationIndex $missingBenefitConverted.XlsxValidationIndex -SheetName '음식점' -SheetIndex 1 -HeaderRowNumber 2 -RowNumber 22 -StructuredFields $claimedMissingFields -FieldReferences $claimedMissingReferences } 'A claimed missing XLSX cell must be rejected rather than invented'

$unrelatedUnsupportedDocument = New-BenefitSourceDocument -SourceRowNumber 2 -Url 'https://city.example.go.kr/unrelated.xlsx' -SourceFormat XLSX -FetchStatus COMPLETE -Text '' -Bytes (New-XlsxTestBytes -UnrelatedUnsupportedRow) -ObservedAt '2026-09-26T00:00:00Z'
$unrelatedUnsupportedConverted = ConvertTo-BenefitXlsxObservation -Document $unrelatedUnsupportedDocument
Assert-ScopeEqual $unrelatedUnsupportedConverted.AdapterStatus COMPLETE 'An unrelated unsupported XLSX row cannot poison a valid candidate observation'
Assert-ScopeEqual $unrelatedUnsupportedConverted.ContentUnits.Count 1 'An unrelated unusable row cannot erase a valid physical row'

$unmappedUnsupportedDocument = New-BenefitSourceDocument -SourceRowNumber 2 -Url 'https://city.example.go.kr/unmapped-unsupported.xlsx' -SourceFormat XLSX -FetchStatus COMPLETE -Text '' -Bytes (New-XlsxTestBytes -UnmappedUnsupportedCell) -ObservedAt '2026-09-26T00:00:00Z'
$unmappedUnsupportedConverted = ConvertTo-BenefitXlsxObservation -Document $unmappedUnsupportedDocument
Assert-ScopeEqual $unmappedUnsupportedConverted.AdapterStatus COMPLETE 'An unsupported unmapped cell in a valid business row does not poison the observation'
Assert-ScopeEqual $unmappedUnsupportedConverted.ContentUnits.Count 1 'An unsupported unmapped cell does not discard the valid XLSX row'

foreach ($nonCandidateBytes in @((New-XlsxTestBytes -NonCandidateFormulaBenefit), (New-XlsxTestBytes -NonCandidateUnsupportedBenefit))) {
    $nonCandidateDocument = New-BenefitSourceDocument -SourceRowNumber 2 -Url 'https://city.example.go.kr/non-candidate.xlsx' -SourceFormat XLSX -FetchStatus COMPLETE -Text '' -Bytes $nonCandidateBytes -ObservedAt '2026-09-26T00:00:00Z'
    $nonCandidateConverted = ConvertTo-BenefitXlsxObservation -Document $nonCandidateDocument
    Assert-ScopeEqual $nonCandidateConverted.AdapterStatus COMPLETE 'A non-candidate row with unsupported mapped benefit data cannot poison a valid observation'
    Assert-ScopeEqual $nonCandidateConverted.ContentUnits.Count 1 'A non-candidate row cannot discard the valid identity row'
}

$mergedHeaderDocument = New-BenefitSourceDocument -SourceRowNumber 2 -Url 'https://city.example.go.kr/merged-header.xlsx' -SourceFormat XLSX -FetchStatus COMPLETE -Text '' -Bytes (New-XlsxTestBytes -MergedBusinessHeader) -ObservedAt '2026-09-26T00:00:00Z'
$mergedHeaderConverted = ConvertTo-BenefitXlsxObservation -Document $mergedHeaderDocument
Assert-ScopeEqual $mergedHeaderConverted.AdapterStatus PARTIAL 'A mapped merged header fails closed'
Assert-ScopeEqual $mergedHeaderConverted.ContentUnits.Count 0 'A mapped merged header cannot yield candidate rows'

$duplicateHeaderDocument = New-BenefitSourceDocument -SourceRowNumber 2 -Url 'https://city.example.go.kr/duplicate-header.xlsx' -SourceFormat XLSX -FetchStatus COMPLETE -Text '' -Bytes (New-XlsxTestBytes -DuplicateBenefitHeader) -ObservedAt '2026-09-26T00:00:00Z'
$duplicateHeaderConverted = ConvertTo-BenefitXlsxObservation -Document $duplicateHeaderDocument
Assert-ScopeEqual $duplicateHeaderConverted.AdapterStatus PARTIAL 'Ambiguous XLSX headers cannot establish complete semantic mapping'
Assert-ScopeEqual $duplicateHeaderConverted.ContentUnits.Count 0 'Ambiguous XLSX headers cannot yield candidate rows'

$noIdentityHeaderDocument = New-BenefitSourceDocument -SourceRowNumber 2 -Url 'https://city.example.go.kr/no-identity-header.xlsx' -SourceFormat XLSX -FetchStatus COMPLETE -Text '' -Bytes (New-XlsxTestBytes -NoIdentityHeader) -ObservedAt '2026-09-26T00:00:00Z'
$noIdentityHeaderConverted = ConvertTo-BenefitXlsxObservation -Document $noIdentityHeaderDocument
Assert-ScopeEqual $noIdentityHeaderConverted.AdapterStatus UNSUPPORTED 'An XLSX sheet without a supported identity header cannot establish absence'
Assert-ScopeEqual $noIdentityHeaderConverted.ContentUnits.Count 0 'An unsupported XLSX table produces no candidate rows'

foreach ($unsafePackage in @(
    (New-XlsxTestBytes -DuplicateRelationshipId),
    (New-XlsxTestBytes -DuplicateWorksheetTarget),
    (New-XlsxTestBytes -ExternalRelationship),
    (New-XlsxTestBytes -WrongRelationshipType),
    (New-XlsxTestBytes -WorkbookDtd),
    (New-XlsxTestBytes -MalformedContentTypes),
    (New-XlsxTestBytes -ContentTypesDtd),
    (New-XlsxTestBytes -UnsafeArchivePath),
    (New-XlsxTestBytes -DuplicateWorkbookEntry),
    (New-XlsxTestBytes -DuplicateCell),
    (New-XlsxTestBytes -DuplicateRow),
    (New-XlsxTestBytes -MalformedCellRow),
    (New-XlsxTestBytes -ExtraEntryCount 252),
    (New-XlsxTestBytes -LargeEntryBytes 8388609),
    (New-XlsxTestBytes -TotalLargeEntryBytes 7000000)
)) {
    $unsafeSnapshot = New-BenefitSourceSnapshot -SourceUrl 'https://city.example.go.kr/unsafe.xlsx' -SourceFormat XLSX -Text '' -Bytes $unsafePackage -ObservedAt '2026-09-26T00:00:00Z'
    Assert-ScopeThrows { New-BenefitXlsxValidationIndex -Snapshot $unsafeSnapshot } 'Unsafe or ambiguous XLSX package structure must fail closed'
}

$unit = $converted.ContentUnits[0]
Assert-ScopeXlsxUnit -Unit $unit -Snapshot $converted.Snapshot -XlsxValidationIndex $converted.XlsxValidationIndex

foreach ($mutation in @(
    @{ Row=2; Cell='B2'; Property='IsSupported'; Value=$false; Message='An unsupported selected header must be rejected by provenance validation' },
    @{ Row=2; Cell='B2'; Property='HasFormula'; Value=$true; Message='A formula-backed selected header must be rejected by provenance validation' },
    @{ Row=22; Cell='B22'; Property='IsSupported'; Value=$false; Message='An unsupported selected value cell must be rejected by provenance validation' },
    @{ Row=22; Cell='B22'; Property='HasFormula'; Value=$true; Message='A formula-backed selected value cell must be rejected by provenance validation' }
)) {
    $forgedValidationIndex = Copy-ScopeContractData $converted.XlsxValidationIndex
    $forgedSheet = $forgedValidationIndex.Sheets[0]
    $forgedRow = @($forgedSheet.Rows | Where-Object { $_.Number -eq $mutation.Row })[0]
    $forgedRow.Cells[$mutation.Cell].$($mutation.Property) = $mutation.Value
    Assert-ScopeThrows { Assert-ScopeXlsxUnit -Unit $unit -Snapshot $converted.Snapshot -XlsxValidationIndex $forgedValidationIndex } $mutation.Message
}

function New-XlsxUnitForgery {
    param($Source)
    return Copy-ScopeContractData $Source
}

$forged = New-XlsxUnitForgery $unit
$forged.RowNumber = 23
$forged.UnitReference = 'XLSX_SHEET_1_ROW_23'
Assert-ScopeThrows { Assert-ScopeXlsxUnit -Unit $forged -Snapshot $converted.Snapshot -XlsxValidationIndex $converted.XlsxValidationIndex } 'A selected XLSX row must not be substituted with another row'

$sameDisplayDocument = New-BenefitSourceDocument -SourceRowNumber 2 -Url 'https://city.example.go.kr/benefits.xlsx' -SourceFormat XLSX -FetchStatus COMPLETE -Text '' -Bytes (New-XlsxTestBytes -DuplicateBusinessNameCell) -ObservedAt '2026-09-26T00:00:00Z'
$sameDisplayConverted = ConvertTo-BenefitXlsxObservation -Document $sameDisplayDocument
$forged = New-XlsxUnitForgery $sameDisplayConverted.ContentUnits[0]
$forged.FieldReferences.BusinessName.CellReference = 'B23'
Assert-ScopeThrows { Assert-ScopeXlsxUnit -Unit $forged -Snapshot $sameDisplayConverted.Snapshot -XlsxValidationIndex $sameDisplayConverted.XlsxValidationIndex } 'The same displayed business name in another physical cell must not be accepted'

$forged = New-XlsxUnitForgery $unit
$forged.SheetName = '다른 시트'
Assert-ScopeThrows { Assert-ScopeXlsxUnit -Unit $forged -Snapshot $converted.Snapshot -XlsxValidationIndex $converted.XlsxValidationIndex } 'A forged XLSX sheet name must be rejected'

$forged = New-XlsxUnitForgery $unit
$forged.SheetIndex = 2
$forged.UnitReference = 'XLSX_SHEET_2_ROW_22'
Assert-ScopeThrows { Assert-ScopeXlsxUnit -Unit $forged -Snapshot $converted.Snapshot -XlsxValidationIndex $converted.XlsxValidationIndex } 'A forged XLSX sheet index must be rejected'

$forged = New-XlsxUnitForgery $unit
$forged.FieldReferences.BusinessName.HeaderCellReference = 'C2'
Assert-ScopeThrows { Assert-ScopeXlsxUnit -Unit $forged -Snapshot $converted.Snapshot -XlsxValidationIndex $converted.XlsxValidationIndex } 'A forged XLSX header coordinate must be rejected'

$forged = New-XlsxUnitForgery $unit
$forged.FieldReferences.BusinessName.CellReference = 'C22'
Assert-ScopeThrows { Assert-ScopeXlsxUnit -Unit $forged -Snapshot $converted.Snapshot -XlsxValidationIndex $converted.XlsxValidationIndex } 'A forged XLSX value column must be rejected'

$forged = New-XlsxUnitForgery $unit
$forged.FieldReferences.BusinessName.RawValue = '999'
Assert-ScopeThrows { Assert-ScopeXlsxUnit -Unit $forged -Snapshot $converted.Snapshot -XlsxValidationIndex $converted.XlsxValidationIndex } 'A forged XLSX raw lexical value must be rejected'

$forged = New-XlsxUnitForgery $unit
$forged.FieldReferences.BusinessName.CellType = 'n'
Assert-ScopeThrows { Assert-ScopeXlsxUnit -Unit $forged -Snapshot $converted.Snapshot -XlsxValidationIndex $converted.XlsxValidationIndex } 'A forged XLSX cell type must be rejected'

$forged = New-XlsxUnitForgery $unit
$forged.StructuredFields.BusinessName = '위조 상호'
Assert-ScopeThrows { Assert-ScopeXlsxUnit -Unit $forged -Snapshot $converted.Snapshot -XlsxValidationIndex $converted.XlsxValidationIndex } 'A forged XLSX structured field must be rejected'

$otherSnapshot = New-BenefitSourceSnapshot -SourceUrl 'https://city.example.go.kr/other.xlsx' -SourceFormat XLSX -Text '' -Bytes (New-XlsxTestBytes -Name '다른 가게') -ObservedAt '2026-09-26T00:00:00Z'
$otherIndex = New-BenefitXlsxValidationIndex -Snapshot $otherSnapshot
Assert-ScopeThrows { Assert-ScopeXlsxUnit -Unit $unit -Snapshot $converted.Snapshot -XlsxValidationIndex $otherIndex } 'An XLSX index from another snapshot must be rejected'

$forged = New-XlsxUnitForgery $unit
$forged | Add-Member -NotePropertyName RawStart -NotePropertyValue 0
Assert-ScopeThrows { Assert-ScopeXlsxUnit -Unit $forged -Snapshot $converted.Snapshot -XlsxValidationIndex $converted.XlsxValidationIndex } 'XLSX units must reject invented raw-span properties'
Write-Host 'XLSX source observation tests passed.'

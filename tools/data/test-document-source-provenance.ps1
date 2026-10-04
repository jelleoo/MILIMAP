Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/benefit-evidence-location-contracts.ps1')
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-document/test-support.ps1')

function Assert-DocumentEqual($Actual,$Expected,[string]$Message) { if ($Actual -cne $Expected) { throw "$Message (expected=$Expected actual=$Actual)" } }
function Assert-DocumentThrows([scriptblock]$Action,[string]$Message) {
    $threw=$false; try { & $Action } catch { $threw=$true }
    if (-not $threw) { throw "$Message (no failure)" }
}

foreach ($format in @('PDF','HWPX')) {
    $x = New-DocumentTestFixture -Format $format
    $unit = $x.Units[0]
    Assert-DocumentEqual $unit.ContractType SourceContentUnit 'Document row uses the existing content-unit contract'
    Assert-DocumentEqual $unit.UnitType "${format}_ROW" 'Unit type preserves source format'
    Assert-DocumentEqual $unit.UnitReference $x.Index.Units[0].UnitReference 'Exact indexed reference is selected'
    Assert-DocumentEqual $unit.PhysicalPath $x.Index.Units[0].PhysicalPath 'Physical path is preserved'
    foreach ($key in @('AdapterId','AdapterVersion','ExtractionMethod','ExtractorId','ExtractorVersion','ExtractionConfigHash')) {
        Assert-DocumentEqual $unit.$key $x.Index.$key "Extraction metadata preserved: $key"
    }
    foreach ($key in $unit.StructuredFields.Keys) {
        Assert-DocumentEqual $unit.FieldReferences[$key].SourceText $unit.StructuredFields[$key] 'Field value preserves indexed source text'
    }
    Assert-ScopeDocumentUnit -Unit $unit -Snapshot $x.Snapshot -ValidationIndex $x.Index
    Assert-DocumentThrows { New-BenefitDocumentSourceContentUnit -Snapshot $x.Snapshot -ValidationIndex $x.Index -UnitReference "${format}_MISSING" } 'Missing unit reference must fail'
    $other = New-DocumentTestFixture -Format $format -ObservedAt '2026-10-05T00:00:01Z'
    Assert-DocumentThrows { Assert-ScopeDocumentUnit -Unit $unit -Snapshot $other.Snapshot -ValidationIndex $other.Index } 'Cross-snapshot unit must fail'
    Assert-DocumentThrows { Assert-BenefitDocumentValidationIndex -ValidationIndex $x.Index -Snapshot $other.Snapshot } 'Cross-snapshot index must fail'

    foreach ($mutation in @(
        @{Name='field value';Apply={param($u) $u.StructuredFields.BenefitDescription='invented'}},
        @{Name='field reference';Apply={param($u) $u.FieldReferences.BenefitDescription.FieldReference='another/BenefitDescription'}},
        @{Name='source text';Apply={param($u) $u.FieldReferences.BenefitDescription.SourceText='invented'}},
        @{Name='cross-row physical field';Apply={param($u) $u.FieldReferences.BenefitDescription.PhysicalReference='page/1/table/1/row/99/cell/4'}},
        @{Name='extraction method';Apply={param($u) $u.ExtractionMethod='OCR'}},
        @{Name='extractor version';Apply={param($u) $u.ExtractorVersion='2'}},
        @{Name='physical path';Apply={param($u) $u.PhysicalPath='invented'}},
        @{Name='raw evidence';Apply={param($u) $u.RawEvidenceText='invented'}},
        @{Name='fake byte span';Apply={param($u) $u | Add-Member RawStart 1}}
    )) {
        $forged = Copy-ScopeContractData $unit
        & $mutation.Apply $forged
        Assert-DocumentThrows { Assert-ScopeDocumentUnit -Unit $forged -Snapshot $x.Snapshot -ValidationIndex $x.Index } "Reject altered $($mutation.Name)"
    }
    foreach ($case in @('duplicate','invalid config','source text','cross-row physical','unknown field','fake field span','extra row metadata')) {
        $rows = @((New-DocumentTestRowRecord -Format $format))
        $config='a' * 64
        switch ($case) {
            duplicate { $rows += Copy-ScopeContractData $rows[0] }
            'invalid config' { $config='not-a-hash' }
            'source text' { $rows[0].FieldReferences.BenefitDescription.SourceText='invented' }
            'cross-row physical' { $rows[0].FieldReferences.BenefitDescription.PhysicalReference='page/1/table/1/row/99/cell/4' }
            'unknown field' { $rows[0].StructuredFields['Currentness']='CURRENT' }
            'fake field span' { $rows[0].FieldReferences.BenefitDescription | Add-Member RawStart 1 }
            'extra row metadata' { $rows[0] | Add-Member ExtractionMethod 'invented' }
        }
        Assert-DocumentThrows { New-BenefitDocumentValidationIndex -Snapshot $x.Snapshot -AdapterId SYNTHETIC -AdapterVersion '1' -ExtractionMethod SYNTHETIC_DOCUMENT_ROW -ExtractorId TEST_FIXTURE -ExtractorVersion '1' -ExtractionConfigHash $config -Units $rows } "Malformed index rejects $case"
    }
    $inputRow = New-DocumentTestRowRecord -Format $format
    $owned = New-DocumentTestFixture -Format $format -Rows @($inputRow)
    $inputRow.StructuredFields.BenefitDescription='mutated caller'
    $owned.Units[0].StructuredFields.BenefitDescription='mutated unit'
    Assert-DocumentEqual $owned.Index.Units[0].StructuredFields.BenefitDescription '합성 혜택 A' 'Index owns records and constructor copies selected unit'
}
$pdf = New-DocumentTestFixture -Format PDF
$hwpx = New-DocumentTestFixture -Format HWPX
Assert-DocumentThrows { Assert-ScopeDocumentUnit -Unit $pdf.Units[0] -Snapshot $hwpx.Snapshot -ValidationIndex $hwpx.Index } 'PDF unit cannot validate as HWPX'
Assert-DocumentThrows { Assert-ScopeDocumentUnit -Unit $hwpx.Units[0] -Snapshot $pdf.Snapshot -ValidationIndex $pdf.Index } 'HWPX unit cannot validate as PDF'
Write-Host 'Document source provenance tests passed (synthetic only).'

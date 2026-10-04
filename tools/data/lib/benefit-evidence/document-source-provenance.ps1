Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# This contract consumes adapter-produced rows. P4-0 does not extract real documents.
function Assert-InternalBenefitDocumentRow {
    param([Parameter(Mandatory)]$Row,[Parameter(Mandatory)][string]$SourceFormat)
    foreach ($property in @('UnitType','UnitReference','PhysicalPath','RawEvidenceText','StructuredFields','FieldReferences')) {
        if ($Row.PSObject.Properties.Name -notcontains $property) { throw "Document row is missing $property" }
    }
    foreach ($property in @('RawStart','RawLength','RawFragment','TableStart','TableLength')) {
        if ($Row.PSObject.Properties.Name -contains $property) { throw 'Document row must not fabricate raw-span provenance' }
    }
    if ($Row.UnitType -cne "${SourceFormat}_ROW") { throw 'Document row type/format mismatch' }
    Assert-ScopeText $Row.UnitReference 'UnitReference'
    Assert-ScopeText $Row.PhysicalPath 'PhysicalPath'
    Assert-ScopeText $Row.RawEvidenceText 'RawEvidenceText'
    $prefix = if ($SourceFormat -ceq 'PDF') { 'PDF_PAGE' } else { 'HWPX_SECTION' }
    if ($Row.UnitReference -cnotmatch "^${prefix}_([1-9]\d*)_TABLE_([1-9]\d*)_ROW_([1-9]\d*)$") { throw 'Invalid document row reference' }
    $root = if ($SourceFormat -ceq 'PDF') { 'page' } else { 'section' }
    $expectedPath = "$root/$($Matches[1])/table/$($Matches[2])/row/$($Matches[3])"
    if ($Row.PhysicalPath -cne $expectedPath) { throw 'Document row physical path mismatch' }
    if ($Row.StructuredFields -isnot [Collections.IDictionary] -or $Row.FieldReferences -isnot [Collections.IDictionary] -or $Row.StructuredFields.Count -eq 0 -or $Row.StructuredFields.Count -ne $Row.FieldReferences.Count) { throw 'Document row requires matching field dictionaries' }
    $allowedFields = @((Get-BenefitScopedHeaderMap).Values)
    $physicalReferences = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($key in $Row.StructuredFields.Keys) {
        if ($key -isnot [string] -or $allowedFields -cnotcontains $key -or -not $Row.FieldReferences.Contains($key) -or $Row.StructuredFields[$key] -isnot [string]) { throw 'Invalid document semantic field' }
        $reference = $Row.FieldReferences[$key]
        if ($reference -isnot [pscustomobject] -or @($reference.PSObject.Properties.Name).Count -ne 3) { throw 'Document field must use only physical reference and source text provenance' }
        foreach ($property in @('FieldReference','PhysicalReference','SourceText')) {
            if ($null -eq $reference -or $reference.PSObject.Properties.Name -notcontains $property -or $reference.$property -isnot [string]) { throw "Document field requires text $property" }
        }
        if ($reference.FieldReference -cne "$($Row.UnitReference)/$key" -or $reference.SourceText -cne $Row.StructuredFields[$key]) { throw 'Document field value/reference mismatch' }
        if ($reference.PhysicalReference -cnotmatch ('^' + [regex]::Escape($expectedPath) + '/cell/[1-9]\d*$') -or -not $physicalReferences.Add($reference.PhysicalReference)) { throw 'Document field must belong to one distinct cell of its row' }
    }
}

function Assert-InternalBenefitDocumentValidationIndex {
    param([Parameter(Mandatory)]$ValidationIndex,[Parameter(Mandatory)]$Snapshot)
    Assert-ScopeObject $ValidationIndex 'BenefitDocumentValidationIndex' @('SnapshotId','ContentHash','SourceFormat','AdapterId','AdapterVersion','ExtractionMethod','ExtractorId','ExtractorVersion','ExtractionConfigHash','Units','UnitsByReference')
    if ($Snapshot.SourceFormat -cnotin @('PDF','HWPX')) { throw 'Document index requires a PDF/HWPX byte snapshot' }
    foreach ($property in @('SnapshotId','ContentHash','SourceFormat')) {
        if ($ValidationIndex.$property -cne $Snapshot.$property) { throw 'Document index must belong to the exact source snapshot' }
    }
    foreach ($property in @('AdapterId','AdapterVersion','ExtractionMethod','ExtractorId','ExtractorVersion')) { Assert-ScopeText $ValidationIndex.$property $property }
    if ($ValidationIndex.ExtractionConfigHash -isnot [string] -or $ValidationIndex.ExtractionConfigHash -cnotmatch '^[a-f0-9]{64}$') { throw 'Invalid document extraction config hash' }
    if ($ValidationIndex.Units -isnot [array] -or $ValidationIndex.UnitsByReference -isnot [Collections.IDictionary] -or $ValidationIndex.UnitsByReference.Count -ne $ValidationIndex.Units.Count) { throw 'Invalid document index collections' }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($row in $ValidationIndex.Units) {
        if ($row -isnot [pscustomobject] -or @($row.PSObject.Properties.Name).Count -ne 6) { throw 'Document index row must use the exact common record shape' }
        Assert-InternalBenefitDocumentRow -Row $row -SourceFormat $Snapshot.SourceFormat
        if (-not $seen.Add($row.UnitReference)) { throw 'Duplicate document unit reference' }
        if (-not $ValidationIndex.UnitsByReference.Contains($row.UnitReference) -or -not [object]::ReferenceEquals($row,$ValidationIndex.UnitsByReference[$row.UnitReference])) { throw 'Document index lookup mismatch' }
    }
}

function New-BenefitDocumentValidationIndex {
    param([Parameter(Mandatory)]$Snapshot,[Parameter(Mandatory)][string]$AdapterId,[Parameter(Mandatory)][string]$AdapterVersion,
        [Parameter(Mandatory)][string]$ExtractionMethod,[Parameter(Mandatory)][string]$ExtractorId,[Parameter(Mandatory)][string]$ExtractorVersion,
        [Parameter(Mandatory)][string]$ExtractionConfigHash,[Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Units)
    Assert-ScopeSnapshot $Snapshot
    $records = Copy-ScopeContractData $Units
    $lookup = [ordered]@{}
    foreach ($row in $records) {
        Assert-InternalBenefitDocumentRow -Row $row -SourceFormat $Snapshot.SourceFormat
        if ($lookup.Contains($row.UnitReference)) { throw 'Duplicate document unit reference' }
        $lookup[$row.UnitReference] = $row
    }
    $index = [pscustomobject][ordered]@{
        ContractType='BenefitDocumentValidationIndex';ContractVersion=1
        SnapshotId=$Snapshot.SnapshotId;ContentHash=$Snapshot.ContentHash;SourceFormat=$Snapshot.SourceFormat
        AdapterId=$AdapterId;AdapterVersion=$AdapterVersion;ExtractionMethod=$ExtractionMethod
        ExtractorId=$ExtractorId;ExtractorVersion=$ExtractorVersion;ExtractionConfigHash=$ExtractionConfigHash
        Units=$records;UnitsByReference=$lookup
    }
    Assert-InternalBenefitDocumentValidationIndex -ValidationIndex $index -Snapshot $Snapshot
    return $index
}

function Assert-BenefitDocumentValidationIndex {
    param([Parameter(Mandatory)]$ValidationIndex,[Parameter(Mandatory)]$Snapshot)
    Assert-ScopeSnapshot $Snapshot
    Assert-InternalBenefitDocumentValidationIndex -ValidationIndex $ValidationIndex -Snapshot $Snapshot
}

function Assert-ScopeDocumentUnitCore {
    param([Parameter(Mandatory)]$Unit,[Parameter(Mandatory)]$Snapshot,[Parameter(Mandatory)]$ValidationIndex)
    Assert-ScopeObject $Unit 'SourceContentUnit' @('SnapshotId','UnitType','UnitReference','PhysicalPath','RawEvidenceText','StructuredFields','FieldReferences','AdapterId','AdapterVersion','ExtractionMethod','ExtractorId','ExtractorVersion','ExtractionConfigHash')
    if (@($Unit.PSObject.Properties.Name).Count -ne 15) { throw 'Document content unit must use the exact indexed shape' }
    Assert-InternalBenefitDocumentRow -Row $Unit -SourceFormat $Snapshot.SourceFormat
    if ($Unit.SnapshotId -cne $Snapshot.SnapshotId -or -not $ValidationIndex.UnitsByReference.Contains($Unit.UnitReference)) { throw 'Document unit must be an exact indexed snapshot member' }
    $record = $ValidationIndex.UnitsByReference[$Unit.UnitReference]
    foreach ($property in @('UnitType','UnitReference','PhysicalPath','RawEvidenceText')) {
        if ($Unit.$property -cne $record.$property) { throw "Document unit changed indexed $property" }
    }
    foreach ($property in @('AdapterId','AdapterVersion','ExtractionMethod','ExtractorId','ExtractorVersion','ExtractionConfigHash')) {
        if ($Unit.$property -cne $ValidationIndex.$property) { throw "Document unit changed indexed $property" }
    }
    if ($Unit.StructuredFields.Count -ne $record.StructuredFields.Count) { throw 'Document unit changed indexed fields' }
    foreach ($key in $record.StructuredFields.Keys) {
        if (-not $Unit.StructuredFields.Contains($key) -or $Unit.StructuredFields[$key] -cne $record.StructuredFields[$key]) { throw 'Document unit changed indexed field value' }
        foreach ($property in @('FieldReference','PhysicalReference','SourceText')) {
            if ($Unit.FieldReferences[$key].$property -cne $record.FieldReferences[$key].$property) { throw 'Document unit changed indexed field provenance' }
        }
    }
}

function Assert-ScopeDocumentUnit {
    param([Parameter(Mandatory)]$Unit,[Parameter(Mandatory)]$Snapshot,[Parameter(Mandatory)]$ValidationIndex)
    Assert-BenefitDocumentValidationIndex -ValidationIndex $ValidationIndex -Snapshot $Snapshot
    Assert-ScopeDocumentUnitCore -Unit $Unit -Snapshot $Snapshot -ValidationIndex $ValidationIndex
}

function New-BenefitDocumentSourceContentUnit {
    param([Parameter(Mandatory)]$Snapshot,[Parameter(Mandatory)]$ValidationIndex,[Parameter(Mandatory)][string]$UnitReference)
    Assert-BenefitDocumentValidationIndex -ValidationIndex $ValidationIndex -Snapshot $Snapshot
    if (-not $ValidationIndex.UnitsByReference.Contains($UnitReference)) { throw 'Missing document unit reference' }
    $unit = Copy-ScopeContractData $ValidationIndex.UnitsByReference[$UnitReference]
    $unit | Add-Member ContractType SourceContentUnit
    $unit | Add-Member ContractVersion 1
    $unit | Add-Member SnapshotId $Snapshot.SnapshotId
    foreach ($property in @('AdapterId','AdapterVersion','ExtractionMethod','ExtractorId','ExtractorVersion','ExtractionConfigHash')) { $unit | Add-Member -NotePropertyName $property -NotePropertyValue $ValidationIndex.$property }
    Assert-ScopeDocumentUnitCore -Unit $unit -Snapshot $Snapshot -ValidationIndex $ValidationIndex
    return $unit
}

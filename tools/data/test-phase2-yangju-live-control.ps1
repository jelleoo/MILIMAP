$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-location/test-support.ps1')

$artifactPath = Join-Path $PSScriptRoot 'testdata/benefit-evidence-xlsx/yangju-live-control.json'
if (-not (Test-Path -LiteralPath $artifactPath)) { throw 'Yangju live-control artifact is required' }
$artifact = Get-Content -Raw -LiteralPath $artifactPath | ConvertFrom-Json -Depth 10

foreach ($property in @('CheckedAt','SourceUrl','HttpStatus','ContentType','FinalUrl','WorkbookByteSize','SnapshotId','ContentHash','PositiveControl','AbsenceControl','Metrics','Timings','ProductionAction','ProtectedPathChanges')) {
    Assert-ScopeTrue ($artifact.PSObject.Properties.Name -contains $property) "Live-control artifact preserves $property"
}
Assert-ScopeTrue ($artifact.SourceUrl -match '^https://www\.yangju\.go\.kr/') 'Live-control artifact preserves the official Yangju attachment URL'
Assert-ScopeEqual $artifact.HttpStatus 200 'Live-control attachment fetch completes'
Assert-ScopeTrue ([int64]$artifact.WorkbookByteSize -gt 0) 'Live-control artifact preserves workbook byte size'
Assert-ScopeTrue (-not [string]::IsNullOrWhiteSpace([string]$artifact.SnapshotId)) 'Live-control artifact preserves snapshot identity'
Assert-ScopeTrue (-not [string]::IsNullOrWhiteSpace([string]$artifact.ContentHash)) 'Live-control artifact preserves content hash'

Assert-ScopeEqual $artifact.PositiveControl.FetchStatus COMPLETE 'Positive control fetch completes'
Assert-ScopeEqual $artifact.PositiveControl.SourceFormat XLSX 'Positive control is classified as XLSX'
Assert-ScopeEqual $artifact.PositiveControl.OfficialityStatus VERIFIED_OFFICIAL 'Positive control qualifies as official'
Assert-ScopeEqual $artifact.PositiveControl.ObservationStatus COMPLETE 'Positive control observation completes'
Assert-ScopeEqual $artifact.PositiveControl.LocationOperationalStatus COMPLETE 'Positive control locator is operationally complete'
Assert-ScopeEqual $artifact.PositiveControl.LocationStatus LOCATED 'Positive control is located'
Assert-ScopeEqual $artifact.PositiveControl.BindingStatus STRONG 'Positive control binding is strong'
Assert-ScopeEqual $artifact.PositiveControl.ExtractionMethod SCOPED_XLSX_CELL 'Positive control uses XLSX cell extraction'
Assert-ScopeEqual $artifact.PositiveControl.ValidationStatus VALIDATED 'Positive control claim is validated'
Assert-ScopeTrue (-not [string]::IsNullOrWhiteSpace([string]$artifact.PositiveControl.SheetName)) 'Positive control preserves sheet provenance'
Assert-ScopeTrue ([int]$artifact.PositiveControl.RowNumber -gt 0) 'Positive control preserves row provenance'
Assert-ScopeTrue (-not [string]::IsNullOrWhiteSpace([string]$artifact.PositiveControl.BenefitCellReference)) 'Positive control preserves benefit-cell provenance'

Assert-ScopeEqual $artifact.AbsenceControl.ObservationStatus COMPLETE 'Absence control is evaluated from a complete observation'
Assert-ScopeEqual $artifact.AbsenceControl.LocationOperationalStatus COMPLETE 'Absence locator is operationally complete'
Assert-ScopeEqual $artifact.AbsenceControl.LocationStatus NOT_FOUND 'Absence control is semantic identity absence only'
foreach ($forbidden in @('ENDED','VALID_UNTIL','EXPLICIT_DISCONTINUATION','CURRENT_APPLICABILITY_FALSE')) {
    Assert-ScopeTrue (@($artifact.AbsenceControl.ForbiddenInferences) -notcontains $forbidden) "Absence control does not infer $forbidden"
}
Assert-ScopeEqual $artifact.ProductionAction NONE 'Live controls retain no production action'
Assert-ScopeEqual @($artifact.ProtectedPathChanges).Count 0 'Live artifact records no protected-path mutation'

Assert-ScopeEqual $artifact.Metrics.ExternalFetchCount 1 'Live controls fetch the attachment once'
Assert-ScopeTrue ([int]$artifact.Metrics.FetchCacheHits -ge 1) 'Live controls reuse the fetched attachment'
Assert-ScopeEqual $artifact.Metrics.AdapterParseCount 1 'Live controls parse the attachment once'
Assert-ScopeTrue ([int]$artifact.Metrics.AdapterReuseCount -ge 1) 'Live controls reuse the parsed XLSX template'
Assert-ScopeEqual $artifact.Timings.SecondBusinessAdditionalWorkbookHashes 0 'Reused scoped path adds no workbook hash'

Write-Host 'Yangju live-control artifact tests passed.'

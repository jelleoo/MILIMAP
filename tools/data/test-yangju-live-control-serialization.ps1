$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-location/test-support.ps1')
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-xlsx/live-control-serialization.ps1')

Assert-ScopeTrue ($null -ne (Get-Command ConvertTo-YangjuLiveControlArtifact -ErrorAction SilentlyContinue)) 'Yangju live-control serializer must be available'

$transport = [pscustomobject]@{ StatusCode=200; ContentType='application/octer-stream'; FinalUrl='https://www.yangju.go.kr/health/downloadBbsFile.do?key=2716'; FetchMilliseconds=12.5; ByteSize=19032 }
$metrics = [pscustomobject]@{ ExternalFetchCount=1; FetchCacheHits=1; AdapterParseCount=1; AdapterReuseCount=1 }
$timings = [pscustomobject]@{ ParseIndexMilliseconds=25.5; FirstScopedMilliseconds=40.5; SecondScopedMilliseconds=2.5; FirstWorkbookHashes=2; SecondBusinessAdditionalWorkbookHashes=0 }
$emptyResult = [pscustomobject]@{
    Document=[pscustomobject]@{ FetchStatus='COMPLETE'; SourceFormat='XLSX' }
    Qualified=[pscustomobject]@{ OfficialityStatus='VERIFIED_OFFICIAL' }
    Observation=$null; LocationResult=$null; Bound=[pscustomobject]@{ BusinessBindingStatus='AMBIGUOUS' }
    Extraction=[pscustomobject]@{ Status='FAILED'; Claims=@() }; Validation=[pscustomobject]@{ Status='FAILED'; Claims=@() }; Slices=@(); ReasonCodes=@('EXTRACTION_FAILED')
}
$emptyArtifact = ConvertTo-YangjuLiveControlArtifact -CheckedAt '2026-09-26T00:00:00Z' -SourceUrl $transport.FinalUrl -Transport $transport -PositiveResult $emptyResult -AbsenceResult $emptyResult -Metrics $metrics -Timings $timings -ProtectedPathChanges @()
Assert-ScopeEqual $emptyArtifact.PositiveControl.BenefitValue '' 'Empty claims serialize without indexing failure'
Assert-ScopeEqual $emptyArtifact.PositiveControl.BenefitCellReference '' 'Missing slice serializes without property failure'
Assert-ScopeEqual $emptyArtifact.AbsenceControl.LocationStatus '' 'Null location serializes without invented semantic status'
Assert-ScopeTrue ($emptyArtifact.AbsenceControl.ForbiddenInferences.Count -eq 0) 'Empty claims do not invent lifecycle inferences'

$missingPropertyResult = [pscustomobject]@{
    Document=[pscustomobject]@{ FetchStatus='COMPLETE'; SourceFormat='XLSX' }
    Qualified=[pscustomobject]@{ OfficialityStatus='VERIFIED_OFFICIAL' }
    Observation=[pscustomobject]@{ AdapterStatus='COMPLETE'; SnapshotId='snapshot-1'; Snapshot=[pscustomobject]@{ ContentHash='hash-1' } }
    LocationResult=[pscustomobject]@{ OperationalStatus='COMPLETE'; Status='LOCATED' }
    Bound=[pscustomobject]@{ BusinessBindingStatus='STRONG' }
    Extraction=[pscustomobject]@{ Status='COMPLETE'; Claims=@([pscustomobject]@{ ClaimType='BENEFIT_DESCRIPTION'; EvidenceReference='XLSX_SHEET_1_ROW_22/BenefitDescription'; ExtractionMethod='SCOPED_XLSX_CELL' }) }
    Validation=[pscustomobject]@{ Status='COMPLETE'; Claims=@([pscustomobject]@{ ClaimType='BENEFIT_DESCRIPTION'; ValidationStatus='VALIDATED' }) }
    Slices=@([pscustomobject]@{ SheetName='음식점'; SheetIndex=1; RowNumber=22 }); ReasonCodes=@()
}
$missingPropertyArtifact = ConvertTo-YangjuLiveControlArtifact -CheckedAt '2026-09-26T00:00:00Z' -SourceUrl $transport.FinalUrl -Transport $transport -PositiveResult $missingPropertyResult -AbsenceResult $emptyResult -Metrics $metrics -Timings $timings -ProtectedPathChanges @()
Assert-ScopeEqual $missingPropertyArtifact.PositiveControl.BenefitValue '' 'Missing Value property serializes as empty rather than throwing'
Assert-ScopeEqual $missingPropertyArtifact.PositiveControl.BenefitCellReference XLSX_SHEET_1_ROW_22/BenefitDescription 'Existing exact reference is preserved'
Assert-ScopeEqual $missingPropertyArtifact.PositiveControl.ValidationStatus VALIDATED 'Existing validation status is preserved'

Write-Host 'Yangju live-control serialization tests passed.'

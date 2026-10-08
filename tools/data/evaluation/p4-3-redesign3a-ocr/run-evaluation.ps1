Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'crop-cells.ps1')
. (Join-Path $PSScriptRoot 'invoke-tesseract-batch.ps1')
# Reference-bound process-local authority: caller-authored hashes/metadata are not proof.
$script:P43R3aPreparedProofs=[Runtime.CompilerServices.ConditionalWeakTable[object,object]]::new()

function Prepare-P43R3aFixture {
    param([Parameter(Mandatory)][string]$PdfPath,[Parameter(Mandatory)][string]$ArtifactDirectory)
    $dll=Join-Path $PSScriptRoot '../p4-3a-ocr/bin/Release/net8.0/Milimap.P4_3A.OcrEval.dll'
    if(-not [IO.File]::Exists($dll)){throw 'HISTORICAL_HELPER_NOT_BUILT'}
    $pdfHash=(Get-FileHash -LiteralPath $PdfPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $sourceDirectory=Join-Path $ArtifactDirectory 'source'
    if([IO.Directory]::Exists($sourceDirectory)){throw 'PREPARATION_DIRECTORY_ALREADY_EXISTS'}
    $raw=& dotnet $dll inspect --input $PdfPath --artifact-dir $sourceDirectory
    $exitCode=$LASTEXITCODE
    $inspect=($raw -join "`n") | ConvertFrom-Json
    if($exitCode -ne 0 -or $inspect.SchemaVersion -ne 1 -or $inspect.ProbeId -cne 'MILIMAP_P4_3A_OCR_EVAL' -or $inspect.PdfPigVersion -cne '0.1.16' -or $inspect.Status -cne 'ELIGIBLE' -or $inspect.PdfSha256 -cne $pdfHash -or $inspect.Pages.Count -ne 1 -or $inspect.Images.Count -ne 1 -or $inspect.OpenCount -ne 1 -or $inspect.PageReadCount -ne 1 -or $inspect.ImageDecodeCount -ne 1){throw 'IMAGE_NOT_ELIGIBLE'}
    $image=$inspect.Images[0]
    if($image.PageNumber -ne 1 -or $image.ImageNumber -ne 1 -or $image.Components -notin @(1,3)){throw 'IMAGE_IDENTITY_INVALID'}
    $descriptor=Get-P43R3aPnmDescriptor -Path $image.ArtifactPath -ExpectedSha256 $image.PixelSha256
    if($descriptor.Width -ne $image.Width -or $descriptor.Height -ne $image.Height -or $descriptor.Components -ne $image.Components){throw 'IMAGE_IDENTITY_INVALID'}
    $metadata=Join-Path $sourceDirectory 'inspect.json'
    [IO.File]::WriteAllText($metadata,($raw -join "`n"),[Text.UTF8Encoding]::new($false))
    $gridRaw=& dotnet $dll grid --input $image.ArtifactPath --metadata $metadata --page 1 --image 1
    $exitCode=$LASTEXITCODE
    $grid=($gridRaw -join "`n") | ConvertFrom-Json
    if($exitCode -ne 0 -or $grid.Status -cne 'COMPLETE' -or $grid.GridBuildCount -ne 1 -or $grid.Cells.Count -ne 12 -or $grid.PixelSha256 -cne $image.PixelSha256 -or $grid.Config -cne 'EVAL_PIXEL_GRID_V1_BLACK32_H800_V400_FULL_BORDER_INSET3'){throw 'REQUIRED_GRID_NOT_COMPLETE'}
    $cells=@($grid.Cells | ForEach-Object {[pscustomobject]@{CellId=[string]$_.Id;Row=$_.Row;Column=$_.Column;X0=$_.X0;Y0=$_.Y0;X1=$_.X1;Y1=$_.Y1}})
    $set=New-P43R3aCellCropSet -ImagePath $image.ArtifactPath -ImageSha256 $image.PixelSha256 -Cells $cells -OutputDirectory (Join-Path $ArtifactDirectory 'crops')
    if($set.Status -cne 'COMPLETE'){throw $set.Code}
    $prepared=[pscustomobject]@{Status='COMPLETE';Policy=$set.Policy;PdfPath=[IO.Path]::GetFullPath($PdfPath);FixtureHash=$pdfHash;SourceImagePath=$image.ArtifactPath;SourcePixelSha256=$image.PixelSha256;PdfOpenCount=$inspect.OpenCount;PageReadCount=$inspect.PageReadCount;ImageDecodeCount=$inspect.ImageDecodeCount;GridBuildCount=$grid.GridBuildCount;CropBuildCount=$set.CropBuildCount;Cells=$cells;Crops=$set.Crops;ProductionAction='NONE'}
    # Snapshot the actual helper-derived preparation independently of mutable caller objects.
    $script:P43R3aPreparedProofs.Add($prepared,($prepared | ConvertTo-Json -Depth 10 | ConvertFrom-Json))
    return $prepared
}

function Invoke-P43R3aGateA {
    param([Parameter(Mandatory)][object]$PreparedFixture)
    try{
        [object]$proof=$null
        if(-not $script:P43R3aPreparedProofs.TryGetValue($PreparedFixture,[ref]$proof)){throw 'PREPARATION_AUTHORITY_MISSING'}
        foreach($field in @('Status','Policy','PdfPath','FixtureHash','SourceImagePath','SourcePixelSha256','PdfOpenCount','PageReadCount','ImageDecodeCount','GridBuildCount','CropBuildCount','ProductionAction')){
            if($PreparedFixture.$field -cne $proof.$field){throw 'PREPARATION_CHANGED'}
        }
        if($PreparedFixture.Cells.Count -ne 12 -or $PreparedFixture.Crops.Count -ne 12){throw 'CROP_COUNT_MISMATCH'}
        if((Get-FileHash -LiteralPath $proof.PdfPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $proof.FixtureHash){throw 'FIXTURE_HASH_MISMATCH'}
        $descriptor=Get-P43R3aPnmDescriptor -Path $proof.SourceImagePath -ExpectedSha256 $proof.SourcePixelSha256
        [byte[]]$source=[IO.File]::ReadAllBytes($proof.SourceImagePath)
        if([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($source)).ToLowerInvariant() -cne $proof.SourcePixelSha256){throw 'SOURCE_PIXEL_HASH_MISMATCH'}
        for($i=0;$i -lt 12;$i++){
            foreach($field in @('CellId','Row','Column','X0','Y0','X1','Y1')){
                if($PreparedFixture.Cells[$i].$field -cne $proof.Cells[$i].$field){throw 'PROVEN_CELL_CHANGED'}
            }
            $crop=$PreparedFixture.Crops[$i];$original=$proof.Crops[$i];$cell=$proof.Cells[$i]
            foreach($field in @('Ordinal','CellId','Row','Column','X0','Y0','X1','Y1','Width','Height','Components','ArtifactPath','CropSha256')){
                if($crop.$field -cne $original.$field){throw 'CROP_PROVENANCE_CHANGED'}
            }
            foreach($field in @('CellId','Row','Column','X0','Y0','X1','Y1')){
                if($crop.$field -cne $cell.$field){throw 'CROP_RECTANGLE_MISMATCH'}
            }
            [byte[]]$expected=Get-InternalP43R3aCropBytes -Source $source -Descriptor $descriptor -Cell $cell
            $expectedHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($expected)).ToLowerInvariant()
            if($expectedHash -cne $original.CropSha256 -or (Get-FileHash -LiteralPath $crop.ArtifactPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expectedHash){throw 'CROP_BYTES_MISMATCH'}
        }
        return 'GATE_A_CROP_PROVENANCE_PASS'
    }catch{return 'GATE_A_CROP_PROVENANCE_FAILED'}
}

function Invoke-P43R3aGateB {
    param([Parameter(Mandatory)][object]$PreparedFixture,[Parameter(Mandatory)][string]$Executable,[Parameter(Mandatory)][string]$ModelPath)
    $result=[pscustomobject]@{Status='GATE_B_BATCH_MAPPING_NOT_EVALUATED';Code=$null;Batches=@();ProductionAction='NONE'}
    if((Invoke-P43R3aGateA -PreparedFixture $PreparedFixture) -cne 'GATE_A_CROP_PROVENANCE_PASS'){$result.Code='GATE_A_CROP_PROVENANCE_FAILED';return $result}
    foreach($psm in @(6,11)){
        $batch=Invoke-P43R3aTesseractBatch -Executable $Executable -ModelPath $ModelPath -Crops $PreparedFixture.Crops -Psm $psm
        $result.Batches+= $batch
        if($batch.Status -cne 'COMPLETE' -and $batch.InvocationCount -eq 0){$result.Code=$batch.Code;return $result}
    }
    $result.Status='GATE_B_BATCH_MAPPING_FAILED'
    foreach($batch in $result.Batches){
        if($batch.Status -cne 'COMPLETE'){$result.Code=$batch.Code;return $result}
        if($batch.InvocationCount -ne 1 -or $batch.Pages.Count -ne 12){$result.Code='BATCH_PAGE_MAPPING_INVALID';return $result}
    }
    for($i=0;$i -lt 12;$i++){
        foreach($field in @('Page','CropOrdinal','CellId')){
            if($result.Batches[0].Pages[$i].$field -cne $result.Batches[1].Pages[$i].$field){$result.Code='BATCH_PAGE_MAPPING_INVALID';return $result}
        }
    }
    $result.Status='GATE_B_BATCH_MAPPING_PASS'
    return $result
}

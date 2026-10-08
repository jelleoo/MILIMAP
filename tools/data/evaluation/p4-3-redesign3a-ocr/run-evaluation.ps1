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

function Get-P43R3aOverlapClass {
    param([object]$A,[object]$B)
    if($A.CellId -cne $B.CellId -or $A.Page -ne $B.Page){return 'ORDERING_UNSAFE'}
    $sameBox=$A.Left -eq $B.Left -and $A.Top -eq $B.Top -and $A.Width -eq $B.Width -and $A.Height -eq $B.Height
    if(-not $sameBox -and $A.Left -eq $B.Left -and $A.Top -eq $B.Top){return 'ORDERING_UNSAFE'}
    $vertical=[Math]::Min($A.Top+$A.Height,$B.Top+$B.Height)-[Math]::Max($A.Top,$B.Top)
    if($vertical -gt 0 -and $A.Block -eq $B.Block -and $A.Paragraph -eq $B.Paragraph -and $A.Line -eq $B.Line){
        if($A.Word -eq $B.Word -and -not $sameBox){return 'ORDERING_UNSAFE'}
        if(($A.Left -lt $B.Left -and $A.Word -gt $B.Word) -or ($A.Left -gt $B.Left -and $A.Word -lt $B.Word)){return 'ORDERING_UNSAFE'}
    }
    $horizontal=[Math]::Min($A.Left+$A.Width,$B.Left+$B.Width)-[Math]::Max($A.Left,$B.Left)
    if($vertical -le 0 -or $horizontal -le 0){return 'NONE'}
    $ratio=([double]$horizontal*$vertical)/[Math]::Min(([double]$A.Width*$A.Height),([double]$B.Width*$B.Height))
    if($ratio -ge 0.25){if($A.Text -ceq $B.Text){return 'DUPLICATE'};return 'CONFLICTING'}
    return 'SAFE_ADJACENT'
}

function Resolve-P43R3aCropText {
    param([AllowEmptyCollection()][object[]]$PageWords,[string]$CellId)
    # Page/cell mapping and valid TSV geometry precede this crop-local reconstruction.
    # Confidence remains raw evidence; it never selects or rejects text.
    $items=@($PageWords | Sort-Object Top,Left,Word,Block,Paragraph,Line,Height,Width,Text,Confidence,Page,CropOrdinal,CellId)
    $diagnostics=[Collections.Generic.List[object]]::new()
    if($items.Count -eq 0){$diagnostics.Add([pscustomobject]@{Code='REQUIRED_COVERAGE_MISSING';CellId=$CellId})}
    foreach($word in $items){
        if($word.CellId -cne $CellId -or $word.Page -ne $items[0].Page -or $word.CropOrdinal -ne $items[0].CropOrdinal -or $word.Width -le 0 -or $word.Height -le 0 -or [string]::IsNullOrWhiteSpace($word.Text)){
            $diagnostics.Add([pscustomobject]@{Code='ORDERING_UNSAFE';CellId=$CellId;Record=$word})
        }
    }
    for($i=0;$i -lt $items.Count;$i++){
        for($j=$i+1;$j -lt $items.Count;$j++){
            $class=Get-P43R3aOverlapClass $items[$i] $items[$j]
            if($class -cne 'NONE'){$diagnostics.Add([pscustomobject]@{Code=$class;CellId=$CellId;A=$items[$i];B=$items[$j]})}
        }
    }
    # Retained physical vertical components: every component must be a clique.
    # A transitive bridge across separate lines cannot establish safe ordering.
    $remaining=[Collections.Generic.List[int]]::new();for($i=0;$i -lt $items.Count;$i++){$remaining.Add($i)}
    $lines=[Collections.Generic.List[string]]::new()
    while($remaining.Count -gt 0){
        $component=[Collections.Generic.List[int]]::new();$component.Add($remaining[0]);$remaining.RemoveAt(0)
        for($cursor=0;$cursor -lt $component.Count;$cursor++){
            $a=$items[$component[$cursor]]
            foreach($index in @($remaining.ToArray())){
                $b=$items[$index]
                if([Math]::Min($a.Top+$a.Height,$b.Top+$b.Height) -gt [Math]::Max($a.Top,$b.Top)){$component.Add($index);[void]$remaining.Remove($index)}
            }
        }
        for($i=0;$i -lt $component.Count;$i++){
            for($j=$i+1;$j -lt $component.Count;$j++){
                $a=$items[$component[$i]];$b=$items[$component[$j]]
                if([Math]::Min($a.Top+$a.Height,$b.Top+$b.Height) -le [Math]::Max($a.Top,$b.Top)){$diagnostics.Add([pscustomobject]@{Code='ORDERING_UNSAFE';CellId=$CellId;A=$a;B=$b})}
            }
        }
        $ordered=@($component | ForEach-Object {$items[$_]} | Sort-Object Left,Top,Word,Block,Paragraph,Line,Height,Width,Text,Confidence,Page,CropOrdinal,CellId)
        $lines.Add(($ordered.Text -join ' '))
    }
    return [pscustomobject]@{CellId=$CellId;Status=$(if(@($diagnostics | Where-Object Code -CNE 'SAFE_ADJACENT').Count -gt 0){'PARTIAL'}else{'COMPLETE'});
        Text=($lines -join "`n");Policy='SAME_CELL_OVERLAP_V1';SameRegionRatio=0.25;ConfidencePolicy='DIAGNOSTIC_ONLY_V1';
        Diagnostics=$diagnostics.ToArray();RawWordConfidences=@($items | ForEach-Object {$_.Confidence})}
}

function ConvertTo-P43R3aCellTexts {
    param([object]$BatchResult)
    if($BatchResult.Status -cne 'COMPLETE'){return}
    foreach($page in @($BatchResult.Pages | Sort-Object CropOrdinal)){
        $words=@($BatchResult.Words | Where-Object {$_.Page -eq $page.Page -and $_.CropOrdinal -eq $page.CropOrdinal -and $_.CellId -ceq $page.CellId})
        Resolve-P43R3aCropText -PageWords $words -CellId $page.CellId
    }
}

function Get-P43R3aFixtureGroundTruth {
    $root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
    $clear=Join-Path $PSScriptRoot '../p4-3a-ocr/fixtures'
    $a2=Join-Path $PSScriptRoot '../p4-3a2-ocr/fixtures'
    $generatorBlob='6231ed473349063ce3b0d12fc7b2cff0bef1d114'
    $manifestBlob='cde2a581ec2c4a1fb26481992908b5dcab2740ac'
    $a2ManifestBlob='ede9c602fbea2ae5a76e7dcfdc067f242c1929b7'
    foreach($authority in @(@{File=(Join-Path $clear 'generate-fixtures.py');Blob=$generatorBlob},@{File=(Join-Path $clear 'manifest.json');Blob=$manifestBlob},@{File=(Join-Path $a2 'manifest.json');Blob=$a2ManifestBlob})){
        $blob=& git -C $root hash-object -- $authority.File
        if($LASTEXITCODE -ne 0 -or $blob -cne $authority.Blob){throw 'GROUND_TRUTH_IDENTITY_MISMATCH'}
    }
    $hashes=@{
        'gray.pdf'='07182f75f5305bb4611458aeaea880aa57fa78d120030b0f9b6446bd56e5ec17'
        'rgb.pdf'='415645682f805899bdc0852feefec37ae596a3821b97a7ab344fc7d267c61c24'
        'degraded-gray.pdf'='ea26ae1430a7848d2bb6a4d82772fb416fabad9c6027bd05df94a8ee05c58476'
        'degraded-rgb.pdf'='8d04228cad7b37a3b573987d03c0f5b5a7681163b43702b4b7219abbf957a2bc'
        'mild-degraded-gray.pdf'='a8679aa5450789cb706b15670036db02101a40e88349d8a2f917d9a593401945'
    }
    foreach($name in $hashes.Keys){
        $directory=if($name -cin @('gray.pdf','rgb.pdf')){$clear}else{$a2}
        if((Get-FileHash -LiteralPath (Join-Path $directory $name) -Algorithm SHA256).Hash.ToLowerInvariant() -cne $hashes[$name]){throw 'GROUND_TRUTH_FIXTURE_MISMATCH'}
    }
    # Only now may the verified historical A2 manifest supply authored expectedRows.
    $a2Manifest=Get-Content -LiteralPath (Join-Path $a2 'manifest.json') -Raw | ConvertFrom-Json
    $clearText=@('업체명','주소','전화번호','혜택','가상 가람 식당','가상시 가람로 12','031-123-4567','시험 할인 10%','가상 누리 식당','가상시 누리로 23','031-234-5678',"시험 할인 20%`n방문 시 적용")
    $fixtureCells=@{}
    foreach($name in @('gray.pdf','rgb.pdf','degraded-gray.pdf','degraded-rgb.pdf','mild-degraded-gray.pdf')){
        $text=$clearText
        if($name -cnotin @('gray.pdf','rgb.pdf')){
            $fixture=@($a2Manifest.fixtures | Where-Object {$_.name+'.pdf' -ceq $name})
            if($fixture.Count -ne 1 -or $fixture[0].sha256 -cne $hashes[$name] -or $fixture[0].expectedRows.Count -ne 3 -or @($fixture[0].expectedRows | Where-Object Count -NE 4).Count -gt 0){throw 'GROUND_TRUTH_IDENTITY_MISMATCH'}
            $text=@($fixture[0].expectedRows | ForEach-Object {foreach($value in $_){$value}})
        }
        $fixtureCells[$name]=@(for($i=0;$i -lt 12;$i++){
            $row=[int][Math]::Floor($i/4)+1;$column=$i%4+1
            $role=if($row -eq 1){'HEADER'}elseif($column -eq 1){'BUSINESS_NAME'}elseif($column -eq 4){'BENEFIT'}else{'AUXILIARY'}
            [pscustomobject]@{CellId=[string]($i+1);Row=$row;Column=$column;FieldRole=$role;ExpectedText=$text[$i]}
        })
    }
    return [pscustomobject]@{Policy='TEXT_FIDELITY_GROUND_TRUTH_V1';GeneratorBlob=$generatorBlob;ManifestBlob=$manifestBlob;A2ManifestBlob=$a2ManifestBlob;FixtureHashes=$hashes;FixtureCells=$fixtureCells}
}

function Normalize-P43R3aFidelityText {
    param([AllowNull()][string]$Text)
    return [regex]::Replace($Text.Replace("`r`n","`n").Trim(),'[\p{Zs}\t]+',' ')
}

function Evaluate-P43R3aFidelity {
    param([string]$Fixture,[string]$FixtureHash,[ValidateSet(6,11)][int]$Psm,[AllowEmptyCollection()][object[]]$CellTexts)
    $cells=@();$trusted=$false;$code=$null
    try{
        $truth=Get-P43R3aFixtureGroundTruth
        if(-not $truth.FixtureHashes.ContainsKey($Fixture) -or $FixtureHash -cne $truth.FixtureHashes[$Fixture]){throw 'GROUND_TRUTH_FIXTURE_MISMATCH'}
        $cells=$truth.FixtureCells[$Fixture]
        $trusted=$CellTexts.Count -eq 12
        foreach($cell in $cells){if(@($CellTexts | Where-Object CellId -CEQ $cell.CellId).Count -ne 1){$trusted=$false}}
        if(-not $trusted){$code='CELL_MAPPING_INCOMPLETE'}
    }catch{$code=$_.Exception.Message}
    $evidence=@(foreach($cell in $cells){
        $actual=@($CellTexts | Where-Object CellId -CEQ $cell.CellId)
        $text=if($actual.Count -eq 1){$actual[0].Text}else{$null}
        $normalizedExpected=Normalize-P43R3aFidelityText $cell.ExpectedText
        $normalizedActual=Normalize-P43R3aFidelityText $text
        $state=if(-not $trusted -or $actual[0].Status -cne 'COMPLETE'){'FIDELITY_NOT_EVALUATED'}elseif([string]::Equals($normalizedExpected,$normalizedActual,[StringComparison]::Ordinal)){'FIDELITY_MATCH'}else{'FIDELITY_MISMATCH'}
        [pscustomobject]@{Fixture=$Fixture;Psm=$Psm;CellId=$cell.CellId;FieldRole=$cell.FieldRole;Status=$state;ExpectedText=$cell.ExpectedText;ReconstructedText=$text;
            NormalizedExpected=$normalizedExpected;NormalizedActual=$normalizedActual;RawWordConfidences=@(if($actual.Count -eq 1){$actual[0].RawWordConfidences})}
    })
    $mandatory=@($evidence | Where-Object FieldRole -CNE 'AUXILIARY')
    $status=if(@($mandatory | Where-Object Status -CEQ 'FIDELITY_MISMATCH').Count -gt 0){'FAILED'}elseif(-not $trusted -or @($mandatory | Where-Object Status -CEQ 'FIDELITY_NOT_EVALUATED').Count -gt 0){'NOT_EVALUATED'}else{'PASS'}
    return [pscustomobject]@{Fixture=$Fixture;Psm=$Psm;Status=$status;Code=$code;NormalizationPolicy='TEXT_FIDELITY_NORMALIZATION_V1';
        MandatoryMatchCount=@($mandatory | Where-Object Status -CEQ 'FIDELITY_MATCH').Count;MandatoryCellCount=8;AllCellMatchCount=@($evidence | Where-Object Status -CEQ 'FIDELITY_MATCH').Count;AllCellCount=12;Cells=$evidence;ProductionAction='NONE'}
}

function Invoke-P43R3aGateC {
    param([object]$GrayPrepared,[object]$RgbPrepared,[string]$Executable,[string]$ModelPath)
    $result=[pscustomobject]@{Status='GATE_C_CLEAR_FIDELITY_NOT_EVALUATED';Code=$null;Verdict='PRE_BUSINESS_TRUST_NOT_PROVEN';Runs=@();QualityInvocationCount=0;PreparationCounts=@();Determinism=@();Task4='BLOCKED';ProductionAction='NONE'}
    foreach($prepared in @($GrayPrepared,$RgbPrepared)){
        if((Invoke-P43R3aGateA $prepared) -cne 'GATE_A_CROP_PROVENANCE_PASS'){$result.Code='GATE_A_CROP_PROVENANCE_FAILED';return $result}
    }
    try{$truth=Get-P43R3aFixtureGroundTruth}catch{$result.Code=$_.Exception.Message;return $result}
    if($GrayPrepared.FixtureHash -cne $truth.FixtureHashes['gray.pdf'] -or $RgbPrepared.FixtureHash -cne $truth.FixtureHashes['rgb.pdf']){$result.Code='GROUND_TRUTH_FIXTURE_MISMATCH';return $result}
    foreach($pair in @(@{Name='gray.pdf';Prepared=$GrayPrepared},@{Name='rgb.pdf';Prepared=$RgbPrepared})){
        $prepared=$pair.Prepared
        $result.PreparationCounts+=[pscustomobject]@{Fixture=$pair.Name;PdfOpenCount=$prepared.PdfOpenCount;PageReadCount=$prepared.PageReadCount;ImageDecodeCount=$prepared.ImageDecodeCount;GridBuildCount=$prepared.GridBuildCount;CropBuildCount=$prepared.CropBuildCount}
        foreach($psm in @(6,11)){
            for($repeat=1;$repeat -le 2;$repeat++){
                # Retain the original crop objects; no preparation or quality retry here.
                $batch=Invoke-P43R3aTesseractBatch -Executable $Executable -ModelPath $ModelPath -Crops $prepared.Crops -Psm $psm
                $result.QualityInvocationCount+=$batch.InvocationCount
                if($batch.Status -cne 'COMPLETE' -and $batch.InvocationCount -eq 0){$result.Code=$batch.Code;return $result}
                $texts=@(ConvertTo-P43R3aCellTexts $batch)
                $fidelity=Evaluate-P43R3aFidelity $pair.Name $prepared.FixtureHash $psm $texts
                $result.Runs+=[pscustomobject]@{Fixture=$pair.Name;Psm=$psm;Repetition=$repeat;Batch=$batch;CellTexts=$texts;Fidelity=$fidelity}
            }
            $runs=@($result.Runs | Where-Object {$_.Fixture -ceq $pair.Name -and $_.Psm -eq $psm})
            $words=($runs[0].Batch.Words | ConvertTo-Json -Depth 12 -Compress) -ceq ($runs[1].Batch.Words | ConvertTo-Json -Depth 12 -Compress)
            $texts=($runs[0].CellTexts | Select-Object CellId,Status,Text | ConvertTo-Json -Depth 12 -Compress) -ceq ($runs[1].CellTexts | Select-Object CellId,Status,Text | ConvertTo-Json -Depth 12 -Compress)
            $fidelity=($runs[0].Fidelity | ConvertTo-Json -Depth 12 -Compress) -ceq ($runs[1].Fidelity | ConvertTo-Json -Depth 12 -Compress)
            $firstDiagnostics=@($runs[0].Batch.Diagnostics)+@($runs[0].CellTexts | ForEach-Object {$_.Diagnostics})
            $secondDiagnostics=@($runs[1].Batch.Diagnostics)+@($runs[1].CellTexts | ForEach-Object {$_.Diagnostics})
            $diagnostics=($firstDiagnostics | ConvertTo-Json -Depth 12 -Compress) -ceq ($secondDiagnostics | ConvertTo-Json -Depth 12 -Compress)
            $result.Determinism+=[pscustomobject]@{Fixture=$pair.Name;Psm=$psm;WordsIdentical=$words;TextsIdentical=$texts;FidelityIdentical=$fidelity;DiagnosticsIdentical=$diagnostics}
        }
    }
    if(@($result.Runs | Where-Object {$_.Batch.Status -cne 'COMPLETE' -or $_.Fidelity.Status -ceq 'FAILED' -or $_.Fidelity.MandatoryMatchCount -ne 8}).Count -gt 0 -or @($result.Determinism | Where-Object {-not $_.WordsIdentical -or -not $_.TextsIdentical -or -not $_.FidelityIdentical -or -not $_.DiagnosticsIdentical}).Count -gt 0){
        $result.Status='GATE_C_CLEAR_FIDELITY_FAILED';$result.Verdict='P4_3_REDESIGN3A_REJECTED'
    }elseif(@($result.Runs | Where-Object {$_.Fidelity.Status -cne 'PASS' -or $_.Fidelity.MandatoryMatchCount -ne 8}).Count -eq 0){
        $result.Status='GATE_C_CLEAR_FIDELITY_PASS';$result.Verdict='GATE_C_CLEAR_FIDELITY_PASS';$result.Task4='READY'
    }
    return $result
}

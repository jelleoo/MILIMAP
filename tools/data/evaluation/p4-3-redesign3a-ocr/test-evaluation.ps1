param([ValidateSet('CropProvenance','BatchMapping')][string]$Group='CropProvenance',
    [string]$Executable,[string]$ModelPath,[switch]$RunRealGateB)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Require($Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Reject([scriptblock]$Action,[string]$Code){
    try{& $Action | Out-Null}catch{Require ($_.Exception.Message -ceq $Code) "Expected $Code, got $($_.Exception.Message)";return}
    throw "Expected rejection: $Code"
}
$runner=Join-Path $PSScriptRoot 'run-evaluation.ps1'
Require (Test-Path -LiteralPath $runner) 'FAIL: Redesign 3A crop functions do not exist'
. $runner
if($Group -ceq 'BatchMapping'){
    foreach($name in @('ConvertFrom-P43R3aBatchTsv','Invoke-P43R3aTesseractBatch','Invoke-P43R3aGateB')){
        Require ($null -ne (Get-Command $name -ErrorAction SilentlyContinue)) "FAIL: Missing batch function: $name"
    }
    Require (-not (Get-Command Invoke-P43R3aTesseractBatch).Parameters.ContainsKey('ConfidenceThreshold')) 'No confidence threshold API'
    Require (-not (Get-Command Invoke-P43R3aTesseractBatch).Parameters.ContainsKey('Inputs')) 'No single-cell fallback API'
    function New-TestBatchTsv([int]$Count){
        $rows=[Collections.Generic.List[string]]::new()
        $rows.Add("level`tpage_num`tblock_num`tpar_num`tline_num`tword_num`tleft`ttop`twidth`theight`tconf`ttext")
        for($page=1;$page -le $Count;$page++){
            foreach($row in @("1`t$page`t0`t0`t0`t0`t0`t0`t2`t2`t-1`t","2`t$page`t1`t0`t0`t0`t0`t0`t2`t2`t-1`t","3`t$page`t1`t1`t0`t0`t0`t0`t2`t2`t-1`t","4`t$page`t1`t1`t1`t0`t0`t0`t2`t2`t-1`t","5`t$page`t1`t1`t1`t1`t0`t0`t1`t1`t0`t가","5`t$page`t1`t1`t1`t2`t1`t1`t1`t1`t100`t나")){$rows.Add($row)}
        }
        return $rows -join "`n"
    }
    $valid=New-TestBatchTsv 2
    $parsed=ConvertFrom-P43R3aBatchTsv -Text $valid -ExpectedPageCount 2
    Require ($parsed.Pages.Count -eq 2 -and $parsed.Words.Count -eq 4 -and ($parsed.Pages.Page -join ',') -ceq '1,2') 'Multiple words per page remain valid'
    $word=$parsed.Words[1]
    Require ($word.Page -eq 1 -and $word.Block -eq 1 -and $word.Paragraph -eq 1 -and $word.Line -eq 1 -and $word.Word -eq 2 -and $word.Left -eq 1 -and $word.Top -eq 1 -and $word.Width -eq 1 -and $word.Height -eq 1 -and $word.Confidence -eq 100 -and $word.Text -ceq '나') 'Preserve exact word fields'
    $pageRecord="1`t1`t0`t0`t0`t0`t0`t0`t2`t2`t-1`t"
    Reject {ConvertFrom-P43R3aBatchTsv -Text ($valid.Replace($pageRecord+"`n",'')) -ExpectedPageCount 2} 'BATCH_PAGE_MAPPING_INVALID'
    Reject {ConvertFrom-P43R3aBatchTsv -Text ($valid+"`n"+$pageRecord) -ExpectedPageCount 2} 'BATCH_PAGE_MAPPING_INVALID'
    Reject {ConvertFrom-P43R3aBatchTsv -Text $valid -ExpectedPageCount 1} 'BATCH_PAGE_MAPPING_INVALID'
    Reject {ConvertFrom-P43R3aBatchTsv -Text $valid -ExpectedPageCount 3} 'BATCH_PAGE_MAPPING_INVALID'
    foreach($bad in @($valid.Replace('level','wrong'),$valid.Replace("5`t1`t1`t1`t1`t1`t0`t0`t1`t1`t0`t가","5`t1`t1`t1`t1`t1`t0`t0`t0`t1`t0`t가"),$valid.Replace("`t100`t나","`tNaN`t나"),$valid.Replace("`t100`t나","`t101`t나"),$valid.Replace("`t0`t가","`t-1`t가"),$valid.Replace("5`t1`t1`t1`t1`t2`t1`t1","5`t1`t1`t1`t1`t2`t2`t1"),$valid.Replace("4`t1`t1`t1`t1`t0`t0`t0`t2`t2`t-1`t`n",''))){
        Reject {ConvertFrom-P43R3aBatchTsv -Text $bad -ExpectedPageCount 2} 'BATCH_TSV_INVALID'
    }
    $empty=($valid -split "`n" | Where-Object {$_ -cnotmatch '^5\t2\t'}) -join "`n"
    Reject {ConvertFrom-P43R3aBatchTsv -Text $empty -ExpectedPageCount 2} 'BATCH_REQUIRED_PAGE_EMPTY'
    $scratch=Join-Path ([IO.Path]::GetTempPath()) ('milimap-p43r3a-batch-test-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($scratch)
    try{
        if(-not $Executable -or -not $ModelPath){throw 'BatchMapping requires exact verified -Executable and -ModelPath'}
        $path=Join-Path $scratch 'source.pgm'
        [IO.File]::WriteAllBytes($path,[byte[]]([Text.Encoding]::ASCII.GetBytes("P5`n8 6`n255`n")+[byte[]](0..47)))
        $cells=@(for($id=1;$id -le 12;$id++){
            $row=[int][Math]::Floor(($id-1)/4)+1;$column=($id-1)%4+1
            [pscustomobject]@{CellId=[string]$id;Row=$row;Column=$column;X0=($column-1)*2;Y0=($row-1)*2;X1=$column*2;Y1=$row*2}
        })
        $crops=(New-P43R3aCellCropSet -ImagePath $path -ImageSha256 (Get-FileHash $path).Hash.ToLowerInvariant() -Cells $cells -OutputDirectory (Join-Path $scratch 'crops')).Crops
        $originalProcess=(Get-Item Function:Invoke-InternalP43R3aProcess).ScriptBlock
        $script:batchMode='valid';$script:batchCalls=0;$script:listPath=$null
        $script:expectedCropPaths=$crops.ArtifactPath -join ','
        function Invoke-InternalP43R3aProcess {
            param($Executable,$Arguments,$DeadlineMilliseconds)
            if($Arguments[0] -ceq '--version'){
                $version=if($script:batchMode -ceq 'version'){'tesseract 5.5.3'}else{'tesseract v5.5.3.20260724'}
                return [pscustomobject]@{ExitCode=0;Text=$version;ErrorText='';ElapsedMilliseconds=1}
            }
            $script:batchCalls++;$script:listPath=$Arguments[0]
            Require (([IO.File]::ReadAllLines($Arguments[0]) -join ',') -ceq $script:expectedCropPaths) 'Image list must use crop ordinal order'
            Require (($Arguments[1..($Arguments.Count-1)] -join '|') -ceq ('stdout|--tessdata-dir|'+[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($ModelPath))+'|-l|kor|--oem|1|--psm|6|--dpi|300|-c|tessedit_create_tsv=1')) 'Exact batch arguments'
            if($script:batchMode -ceq 'timeout'){throw 'BATCH_PROCESS_TIMEOUT'}
            $text=New-TestBatchTsv 12
            if($script:batchMode -ceq 'oversized'){$text='x'*1048577}
            if($script:batchMode -ceq 'missing'){$text=$text.Replace("1`t12`t0`t0`t0`t0`t0`t0`t2`t2`t-1`t`n",'')}
            if($script:batchMode -ceq 'empty'){$text=($text -split "`n" | Where-Object {$_ -cnotmatch '^5\t12\t'}) -join "`n"}
            return [pscustomobject]@{ExitCode=$(if($script:batchMode -ceq 'exit'){1}else{0});Text=$text;ErrorText='';ElapsedMilliseconds=1}
        }
        try{
            try{Invoke-P43R3aTesseractBatch -Executable $Executable -ModelPath $ModelPath -Crops $crops -Psm 3;throw 'Invalid PSM accepted'}catch{Require ($_.Exception.Message -like '*ValidateSet*' -or $_.Exception.Message -like '*6,11*') 'PSM 3 must reject at API boundary'}
            $result=Invoke-P43R3aTesseractBatch -Executable $Executable -ModelPath $ModelPath -Crops @($crops | Sort-Object Ordinal -Descending) -Psm 6
            Require ($result.Status -ceq 'COMPLETE' -and $result.InvocationCount -eq 1 -and $result.Pages.Count -eq 12 -and $result.Words.Count -eq 24 -and $script:batchCalls -eq 1 -and $result.ProductionAction -ceq 'NONE') "One exact batch publishes all 12 logical pages; code=$($result.Code)"
            Require (-not [IO.File]::Exists($script:listPath)) 'Success cleans list scratch'
            Require (($result.Pages.CropOrdinal -join ',') -ceq '1,2,3,4,5,6,7,8,9,10,11,12' -and ($result.Pages.CellId -join ',') -ceq '1,2,3,4,5,6,7,8,9,10,11,12' -and $result.Words[23].CropOrdinal -eq 12 -and $result.Words[23].CellId -ceq '12' -and $result.Words[0].Confidence -eq 0) 'Exact identity mapping; confidence zero retained'
            foreach($kind in @('ordinal','cell-id','crop-hash')){
                $badCrops=@($crops | ForEach-Object {$_.PSObject.Copy()})
                switch($kind){'ordinal'{$badCrops[0].Ordinal=2};'cell-id'{$badCrops[0].CellId='2'};'crop-hash'{$badCrops[0].CropSha256='0'*64}}
                $bad=Invoke-P43R3aTesseractBatch -Executable $Executable -ModelPath $ModelPath -Crops $badCrops -Psm 6
                Require ($bad.Status -ceq 'FAILED' -and $bad.InvocationCount -eq 0 -and $bad.Pages.Count -eq 0 -and $bad.Words.Count -eq 0) "$kind must reject before OCR"
            }
            $mismatch=Join-Path $scratch 'kor.traineddata';[IO.File]::WriteAllBytes($mismatch,[byte[]]@(1))
            foreach($case in @(@{Executable=$mismatch;ModelPath=$ModelPath;Code='ENGINE_HASH_MISMATCH'},@{Executable=$Executable;ModelPath=$mismatch;Code='MODEL_HASH_MISMATCH'})){
                $bad=Invoke-P43R3aTesseractBatch -Executable $case.Executable -ModelPath $case.ModelPath -Crops $crops -Psm 6
                Require ($bad.Code -ceq $case.Code -and $bad.InvocationCount -eq 0) 'Exact supply is mandatory'
            }
            foreach($case in @(@('version','ENGINE_VERSION_MISMATCH'),@('timeout','BATCH_PROCESS_TIMEOUT'),@('exit','BATCH_EXIT_FAILED'),@('oversized','BATCH_PROCESS_OUTPUT_LIMIT'),@('missing','BATCH_PAGE_MAPPING_INVALID'),@('empty','BATCH_REQUIRED_PAGE_EMPTY'))){
                $script:batchMode=$case[0]
                $bad=Invoke-P43R3aTesseractBatch -Executable $Executable -ModelPath $ModelPath -Crops $crops -Psm 6
                Require ($bad.Status -ceq 'FAILED' -and $bad.Code -ceq $case[1] -and $bad.Pages.Count -eq 0 -and $bad.Words.Count -eq 0 -and $bad.InvocationCount -eq $(if($case[0] -ceq 'version'){0}else{1})) "Fail closed: $($case[0]), got $($bad.Code)"
                Require (-not [IO.File]::Exists($script:listPath)) 'Failure cleans list scratch'
            }
            $forged=[pscustomobject]@{Crops=$crops}
            $blocked=Invoke-P43R3aGateB -PreparedFixture $forged -Executable $Executable -ModelPath $ModelPath
            Require ($blocked.Status -ceq 'GATE_B_BATCH_MAPPING_NOT_EVALUATED' -and $blocked.Batches.Count -eq 0) 'Gate A authority required before Gate B'
            Write-Host 'BatchMapping synthetic controls PASS; real OCR invocations=0 (process seam)'
        }finally{Set-Item Function:Invoke-InternalP43R3aProcess $originalProcess}
        if($RunRealGateB){
            $prepared=Prepare-P43R3aFixture -PdfPath (Join-Path $PSScriptRoot '../p4-3a-ocr/fixtures/gray.pdf') -ArtifactDirectory (Join-Path $scratch 'gray')
            $real=Invoke-P43R3aGateB -PreparedFixture $prepared -Executable $Executable -ModelPath $ModelPath
            Write-Host ("Real Gray: GateA={0}, GateB={1}, Code={2}; prepare counts={3}/{4}/{5}/{6}/{7}" -f (Invoke-P43R3aGateA $prepared),$real.Status,$real.Code,$prepared.PdfOpenCount,$prepared.PageReadCount,$prepared.ImageDecodeCount,$prepared.GridBuildCount,$prepared.CropBuildCount)
            foreach($batch in $real.Batches){
                Write-Host ("PSM{0}: Status={1}, Code={2}, invocations={3}, pages={4}, words={5}, elapsedMs={6}, page/ordinal/CellId={7}" -f $batch.Psm,$batch.Status,$batch.Code,$batch.InvocationCount,$batch.Pages.Count,$batch.Words.Count,$batch.ElapsedMilliseconds,(@($batch.Pages | ForEach-Object {"$($_.Page)/$($_.CropOrdinal)/$($_.CellId)"}) -join ','))
            }
            Require ($real.Status -ceq 'GATE_B_BATCH_MAPPING_PASS') "Real Gate B failed: $($real.Code)"
            Write-Host 'BatchMapping PASS: synthetic controls and actual exact-runtime Gray Gate B PASS'
        }else{Write-Host 'Real Gate B NOT_RUN in this invocation; synthetic PASS does not establish real mapping'}
    }finally{[IO.Directory]::Delete($scratch,$true)}
    return
}
foreach($name in @('Get-P43R3aPnmDescriptor','New-P43R3aCellCropSet','Prepare-P43R3aFixture','Invoke-P43R3aGateA')){
    Require ($null -ne (Get-Command $name -ErrorAction SilentlyContinue)) "Missing crop function: $name"
}
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('milimap-p43r3a-crop-test-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($scratch)
try{
    $cells=@(for($id=1;$id -le 12;$id++){
        $row=[int][Math]::Floor(($id-1)/4)+1;$column=($id-1)%4+1
        [pscustomobject]@{CellId=[string]$id;Row=$row;Column=$column;X0=($column-1)*2;Y0=($row-1)*2;X1=$column*2;Y1=$row*2;Text='must not affect filenames'}
    })
    foreach($magic in @('P5','P6')){
        $components=if($magic -ceq 'P5'){1}else{3}
        $path=Join-Path $scratch "$magic.pnm"
        [byte[]]$header=[Text.Encoding]::ASCII.GetBytes("$magic`n8 6`n255`n")
        [byte[]]$pixels=0..(48*$components-1)
        [IO.File]::WriteAllBytes($path,[byte[]]($header+$pixels))
        $hash=(Get-FileHash $path).Hash.ToLowerInvariant()
        $descriptor=Get-P43R3aPnmDescriptor -Path $path -ExpectedSha256 $hash
        Require ($descriptor.Magic -ceq $magic -and $descriptor.Width -eq 8 -and $descriptor.Height -eq 6 -and $descriptor.Components -eq $components -and $descriptor.HeaderLength -eq 11 -and $descriptor.PixelByteLength -eq 48*$components -and $descriptor.SourceSha256 -ceq $hash) "$magic exact descriptor"
        Reject {Get-P43R3aPnmDescriptor -Path $path -ExpectedSha256 ('0'*64)} 'SOURCE_PIXEL_HASH_MISMATCH'
        $first=New-P43R3aCellCropSet -ImagePath $path -ImageSha256 $hash -Cells @($cells | Sort-Object CellId -Descending) -OutputDirectory (Join-Path $scratch "$magic-first")
        $second=New-P43R3aCellCropSet -ImagePath $path -ImageSha256 $hash -Cells $cells -OutputDirectory (Join-Path $scratch "$magic-second")
        Require ($first.Status -ceq 'COMPLETE' -and $null -eq $first.Code -and $first.Policy -ceq 'PROVEN_CELL_CROP_V1' -and $first.CropBuildCount -eq 1 -and $first.Crops.Count -eq 12 -and $first.SourcePixelSha256 -ceq $hash) "$magic crop set"
        Require (($first.Crops.CropSha256 -join ',') -ceq ($second.Crops.CropSha256 -join ',')) "$magic repeat deterministic"
        $stringCells=@($cells | ForEach-Object {
            $copy=$_.PSObject.Copy()
            foreach($field in @('Row','Column','X0','Y0','X1','Y1')){$copy.$field=[string]$copy.$field}
            $copy
        })
        $stringSet=New-P43R3aCellCropSet -ImagePath $path -ImageSha256 $hash -Cells $stringCells -OutputDirectory (Join-Path $scratch "$magic-strings")
        Require ($stringSet.Status -ceq 'COMPLETE' -and ($stringSet.Crops.CropSha256 -join ',') -ceq ($first.Crops.CropSha256 -join ',')) 'Integer coordinate strings must retain numeric row arithmetic'
        $collisionDirectory=Join-Path $scratch "$magic-collision"
        [void][IO.Directory]::CreateDirectory($collisionDirectory)
        $collision=Join-Path $collisionDirectory ([IO.Path]::GetFileName($first.Crops[11].ArtifactPath))
        [IO.File]::WriteAllBytes($collision,[byte[]]@(7,8,9))
        $collided=New-P43R3aCellCropSet -ImagePath $path -ImageSha256 $hash -Cells $cells -OutputDirectory $collisionDirectory
        Require ($collided.Status -ceq 'FAILED' -and $collided.Code -ceq 'CROP_ARTIFACT_ALREADY_EXISTS' -and @(Get-ChildItem -LiteralPath $collisionDirectory -File).Count -eq 1 -and [Convert]::ToBase64String([IO.File]::ReadAllBytes($collision)) -ceq 'BwgJ') 'Existing crop collision must reject before any output writes and preserve bytes'
        $expected=if($components -eq 1){@(@(0,1,8,9),@(18,19,26,27),@(38,39,46,47))}else{@(@(0,1,2,3,4,5,24,25,26,27,28,29),@(54,55,56,57,58,59,78,79,80,81,82,83),@(114,115,116,117,118,119,138,139,140,141,142,143))}
        $ids=@(1,6,12)
        for($i=0;$i -lt 3;$i++){
            $crop=$first.Crops[$ids[$i]-1]
            [byte[]]$want=[byte[]]([Text.Encoding]::ASCII.GetBytes("$magic`n2 2`n255`n")+[byte[]]$expected[$i])
            Require ([Convert]::ToBase64String([IO.File]::ReadAllBytes($crop.ArtifactPath)) -ceq [Convert]::ToBase64String($want)) "$magic literal rectangle $($ids[$i]) exclusive ends/top origin"
        }
        foreach($crop in $first.Crops){
            Require ($crop.Ordinal -eq [int]$crop.CellId -and [IO.Path]::GetFileName($crop.ArtifactPath) -ceq ('crop-{0:D2}-cell-{1}.{2}' -f $crop.Ordinal,$crop.CellId,$(if($components -eq 1){'pgm'}else{'ppm'}))) 'Order/name must derive from proven ordinal/CellId'
        }
        foreach($mutation in @(@{X1=0},@{X0=-1},@{X1=9},@{Y1=7},@{Y1=-1},@{X0=0.5})){
            $invalid=@($cells | ForEach-Object {$copy=$_.PSObject.Copy();$copy})
            foreach($key in $mutation.Keys){$invalid[0].$key=$mutation[$key]}
            $bad=New-P43R3aCellCropSet -ImagePath $path -ImageSha256 $hash -Cells $invalid -OutputDirectory (Join-Path $scratch 'invalid')
            Require ($bad.Status -ceq 'FAILED' -and $bad.Crops.Count -eq 0 -and -not (Test-Path (Join-Path $scratch 'invalid'))) 'Invalid rectangle fails before writes'
        }
        foreach($kind in @('duplicate-id','duplicate-position','missing-id','missing-cell','extra-cell')){
            $invalid=@($cells | ForEach-Object {$_.PSObject.Copy()})
            switch($kind){
                'duplicate-id' {$invalid[1].CellId='1'}
                'duplicate-position' {$invalid[1].Column=1}
                'missing-id' {$invalid[11].CellId='13'}
                'missing-cell' {$invalid=$invalid[0..10]}
                'extra-cell' {$invalid+= $invalid[0].PSObject.Copy()}
            }
            $bad=New-P43R3aCellCropSet -ImagePath $path -ImageSha256 $hash -Cells $invalid -OutputDirectory (Join-Path $scratch 'invalid')
            Require ($bad.Status -ceq 'FAILED' -and $bad.Crops.Count -eq 0) "$kind must fail closed"
        }
        $bad=New-P43R3aCellCropSet -ImagePath $path -ImageSha256 ('0'*64) -Cells $cells -OutputDirectory (Join-Path $scratch 'invalid')
        Require ($bad.Status -ceq 'FAILED' -and $bad.Code -ceq 'SOURCE_PIXEL_HASH_MISMATCH' -and $bad.CropBuildCount -eq 0) 'Crop source SHA mismatch fails before build'
    }
    foreach($content in @("P5`n#comment`n8 6`n255`n","P5`r`n8 6`r`n255`r`n","P5`n8 6`n254`n","P5`n08 6`n255`n","P5`n8 6`n255`n")){
        $path=Join-Path $scratch 'malformed.pnm';[IO.File]::WriteAllBytes($path,[Text.Encoding]::ASCII.GetBytes($content))
        Reject {Get-P43R3aPnmDescriptor -Path $path -ExpectedSha256 (Get-FileHash $path).Hash.ToLowerInvariant()} 'PNM_INVALID'
    }
    $wide=Join-Path $scratch 'wide.pgm'
    [IO.File]::WriteAllBytes($wide,[byte[]]([Text.Encoding]::ASCII.GetBytes("P5`n16 6`n255`n")+[byte[]](0..95)))
    $wideCells=@($cells | ForEach-Object {
        [pscustomobject]@{CellId=$_.CellId;Row=[string]$_.Row;Column=[string]$_.Column;X0=[string]($_.X0*2);X1=[string]($_.X1*2);Y0=[string]$_.Y0;Y1=[string]$_.Y1}
    })
    $wideSet=New-P43R3aCellCropSet -ImagePath $wide -ImageSha256 (Get-FileHash $wide).Hash.ToLowerInvariant() -Cells $wideCells -OutputDirectory (Join-Path $scratch 'wide')
    Require ($wideSet.Status -ceq 'COMPLETE') 'Multi-digit integer strings must be compared numerically'
    [byte[]]$wideWant=[byte[]]([Text.Encoding]::ASCII.GetBytes("P5`n4 2`n255`n")+[byte[]]@(8,9,10,11,24,25,26,27))
    Require ([Convert]::ToBase64String([IO.File]::ReadAllBytes($wideSet.Crops[2].ArtifactPath)) -ceq [Convert]::ToBase64String($wideWant)) 'Multi-digit coordinate strings copy exact numeric rectangle'
    $manifest=Get-Content (Join-Path $PSScriptRoot '../p4-3a-ocr/fixtures/manifest.json') -Raw | ConvertFrom-Json
    foreach($name in @('gray','rgb')){
        $prepared=Prepare-P43R3aFixture -PdfPath (Join-Path $PSScriptRoot "../p4-3a-ocr/fixtures/$name.pdf") -ArtifactDirectory (Join-Path $scratch $name)
        $originalCrops=$prepared.Crops
        $authority=@($manifest.fixtures | Where-Object name -CEQ $name)[0]
        Require ($prepared.FixtureHash -ceq $authority.sha256 -and $prepared.SourcePixelSha256 -ceq $authority.expectedPixelHashes[0]) "$name retained authority"
        Require ($prepared.PdfOpenCount -eq 1 -and $prepared.PageReadCount -eq 1 -and $prepared.ImageDecodeCount -eq 1 -and $prepared.GridBuildCount -eq 1 -and $prepared.CropBuildCount -eq 1 -and $prepared.Cells.Count -eq 12 -and $prepared.Crops.Count -eq 12) "$name prepare once"
        Require ((Invoke-P43R3aGateA -PreparedFixture $prepared) -ceq 'GATE_A_CROP_PROVENANCE_PASS') "$name Gate A"
        $repeat=New-P43R3aCellCropSet -ImagePath $prepared.SourceImagePath -ImageSha256 $prepared.SourcePixelSha256 -Cells $prepared.Cells -OutputDirectory (Join-Path $scratch "$name-repeat")
        Require (($repeat.Crops.CropSha256 -join ',') -ceq ($prepared.Crops.CropSha256 -join ',')) "$name real crop deterministic"
        $forged=$prepared.PSObject.Copy()
        Require ((Invoke-P43R3aGateA -PreparedFixture $forged) -ceq 'GATE_A_CROP_PROVENANCE_FAILED') 'Cloned/self-authored prepared object is not helper authority'
        $prepared.Crops[0].X0++
        Require ((Invoke-P43R3aGateA -PreparedFixture $prepared) -ceq 'GATE_A_CROP_PROVENANCE_FAILED') 'Crop rectangle mutation rejects'
        $prepared.Crops[0].X0--
        $prepared.Cells[0].X0++
        Require ((Invoke-P43R3aGateA -PreparedFixture $prepared) -ceq 'GATE_A_CROP_PROVENANCE_FAILED') 'Proven cells cannot be re-authored'
        $prepared.Cells[0].X0--
        $prepared.CropBuildCount=2
        Require ((Invoke-P43R3aGateA -PreparedFixture $prepared) -ceq 'GATE_A_CROP_PROVENANCE_FAILED') 'Count mutation rejects'
        $prepared.CropBuildCount=1
        $prepared.Crops=$prepared.Crops[0..10]
        Require ((Invoke-P43R3aGateA -PreparedFixture $prepared) -ceq 'GATE_A_CROP_PROVENANCE_FAILED') 'Gate crop count mismatch rejects'
        $prepared.Crops=@($repeat.Crops)
        Require ((Invoke-P43R3aGateA -PreparedFixture $prepared) -ceq 'GATE_A_CROP_PROVENANCE_FAILED') 'Replacement artifacts lack original authority'
        $prepared.Crops=$originalCrops
        [IO.File]::WriteAllBytes($prepared.Crops[0].ArtifactPath,[byte[]]@(0))
        $prepared.Crops[0].CropSha256=(Get-FileHash $prepared.Crops[0].ArtifactPath).Hash.ToLowerInvariant()
        Require ((Invoke-P43R3aGateA -PreparedFixture $prepared) -ceq 'GATE_A_CROP_PROVENANCE_FAILED') 'Crop bytes plus self-authored SHA cannot replace authority'
        Write-Host "$name PASS: PDF open=$($prepared.PdfOpenCount), page read=$($prepared.PageReadCount), decode=$($prepared.ImageDecodeCount), grid=$($prepared.GridBuildCount), crop build=$($prepared.CropBuildCount), cells=12, crops=12"
    }
    foreach($name in @('multi-image','borderless','merged')){
        $code=if($name -ceq 'multi-image'){'IMAGE_NOT_ELIGIBLE'}else{'REQUIRED_GRID_NOT_COMPLETE'}
        Reject {Prepare-P43R3aFixture -PdfPath (Join-Path $PSScriptRoot "../p4-3a-ocr/fixtures/$name.pdf") -ArtifactDirectory (Join-Path $scratch "$name-rejected")} $code
        Require (-not (Test-Path (Join-Path $scratch "$name-rejected/crops"))) "$name preparation must not create crops"
    }
    $root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
    $protected=@('tools/data/evaluation/p4-3a-ocr','tools/data/evaluation/p4-3a2-ocr','tools/data/evaluation/p4-3-redesign2-ocr','tools/data/pdf-native','tools/data/lib','data/canonical','data/seed','apps')
    $diff=@(& git -C $root diff --name-only 625f888c703ed74541df2fd13420354dc67be736 -- @protected)
    Require ($LASTEXITCODE -eq 0 -and $diff.Count -eq 0) 'Historical/protected diff must remain zero'
    $untracked=@(& git -C $root ls-files --others --exclude-standard -- @protected)
    Require ($LASTEXITCODE -eq 0 -and $untracked.Count -eq 0) 'Historical/protected paths must have no untracked files'
    Write-Host 'CropProvenance PASS; historical/protected diff=0; OCR invocations=0'
}finally{[IO.Directory]::Delete($scratch,$true)}

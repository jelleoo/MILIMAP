param([ValidateSet('CropProvenance')][string]$Group='CropProvenance')
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

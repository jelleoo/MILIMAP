param([ValidateSet('ModelSupply','BestBatch')][string]$Group='ModelSupply',
    [Alias('TesseractExecutable')][string]$Executable,[Alias('KoreanModelPath')][string]$ModelPath)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Require($Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Reject([scriptblock]$Action,[string]$Code){
    try{& $Action | Out-Null}catch{Require ($_.Exception.Message -ceq $Code) "Expected $Code, got $($_.Exception.Message)";return}
    throw "Expected rejection: $Code"
}
$supply=Join-Path $PSScriptRoot 'model-supply.ps1'
Require (Test-Path -LiteralPath $supply) 'FAIL: Redesign 3B model supply functions do not exist'
. $supply
if($Group -ceq 'BestBatch'){
    $batch=Join-Path $PSScriptRoot 'invoke-tesseract-best-batch.ps1'
    Require (Test-Path -LiteralPath $batch) 'FAIL: Redesign 3B best-model batch boundary does not exist'
    . $batch
    $originalProcess=(Get-Command Invoke-InternalP43R3aProcess).ScriptBlock
    $scratch=Join-Path ([IO.Path]::GetTempPath()) ('milimap-p43r3b-batch-test-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($scratch)
    $script:bestCalls=0;$script:bestVersions=0;$script:bestMode='valid';$script:bestList=$null
    function New-BestTestTsv([int]$Count){
        $rows=[Collections.Generic.List[string]]::new()
        $rows.Add("level`tpage_num`tblock_num`tpar_num`tline_num`tword_num`tleft`ttop`twidth`theight`tconf`ttext")
        for($page=1;$page -le $Count;$page++){
            foreach($row in @("1`t$page`t0`t0`t0`t0`t0`t0`t2`t2`t-1`t","2`t$page`t1`t0`t0`t0`t0`t0`t2`t2`t-1`t","3`t$page`t1`t1`t0`t0`t0`t0`t2`t2`t-1`t","4`t$page`t1`t1`t1`t0`t0`t0`t2`t2`t-1`t","5`t$page`t1`t1`t1`t1`t0`t0`t1`t1`t0`t가","5`t$page`t1`t1`t1`t2`t1`t1`t1`t1`t100`t나")){$rows.Add($row)}
        }
        return $rows -join "`n"
    }
    function Assert-BestFailure($Result,[string]$Code,[int]$Calls){
        Require ($Result.Status -ceq 'FAILED' -and $Result.Code -ceq $Code -and $Result.InvocationCount -eq $Calls -and $Result.Pages.Count -eq 0 -and $Result.Words.Count -eq 0 -and $Result.ProductionAction -ceq 'NONE' -and $Result.Diagnostics.Count -eq 1 -and $Result.Diagnostics[0].Code -ceq $Code) "Best batch must fail closed: expected $Code/$Calls, got $($Result.Code)/$($Result.InvocationCount)"
    }
    # The real bounded process is delegated only for version probes. Quality OCR
    # is intercepted after real authority/model/runtime/crop validation.
    function Invoke-InternalP43R3aProcess {
        param([string]$Executable,[string[]]$Arguments,[int]$DeadlineMilliseconds)
        if($Arguments.Count -eq 1 -and $Arguments[0] -ceq '--version'){
            $script:bestVersions++
            return & $originalProcess -Executable $Executable -Arguments $Arguments -DeadlineMilliseconds $DeadlineMilliseconds
        }
        $script:bestCalls++;$script:bestList=$Arguments[0]
        Require ([IO.Path]::GetFullPath($Executable) -ceq $script:bestExecutable -and $DeadlineMilliseconds -eq 10000) 'Pinned engine and deadline are required'
        $images=[IO.File]::ReadAllLines($script:bestList)
        Require (($images -join '|') -ceq $script:bestPaths) 'Image list must contain only ordinal-ordered crop paths'
        Require (($Arguments[1..($Arguments.Count-1)] -join '|') -ceq ('stdout|--tessdata-dir|'+$script:bestModelDirectory+'|-l|kor|--oem|1|--psm|'+$script:bestPsm+'|--dpi|300|-c|tessedit_create_tsv=1')) 'Exact Korean OEM1 batch configuration required'
        Require (-not (($Arguments -join '|')+($images -join '|')).Contains('EXPECTED_TEXT_SECRET')) 'Expected text must never enter OCR inputs'
        if($script:bestMode -ceq 'timeout'){throw 'BATCH_PROCESS_TIMEOUT'}
        if($script:bestMode -ceq 'process-output-limit'){throw 'BATCH_PROCESS_OUTPUT_LIMIT'}
        $text=New-BestTestTsv $script:bestPageCount;$errorText=''
        switch($script:bestMode){
            'malformed' {$text=$text.Replace('level','invalid')}
            'missing' {$text=$text.Replace("1`t2`t0`t0`t0`t0`t0`t0`t2`t2`t-1`t`n",'')}
            'duplicate' {$text+="`n1`t1`t0`t0`t0`t0`t0`t0`t2`t2`t-1`t"}
            'extra' {$text=New-BestTestTsv ($script:bestPageCount+1)}
            'empty' {$text=($text -split "`n" | Where-Object {$_ -cnotmatch '^5\t2\t'}) -join "`n"}
            'dimensions' {$text=$text.Replace("1`t1`t0`t0`t0`t0`t0`t0`t2`t2`t-1`t","1`t1`t0`t0`t0`t0`t0`t0`t3`t2`t-1`t")}
            'stdout-limit' {$text='x'*1048577}
            'stderr-limit' {$errorText='x'*65537}
        }
        [pscustomobject]@{ExitCode=$(if($script:bestMode -ceq 'exit'){1}else{0});Text=$text;ErrorText=$errorText;ElapsedMilliseconds=7}
    }
    try{
        $unauthorized=[pscustomobject]@{Status='VERIFIED';Sha256='f888d4038348a0c3d25151e7f452bda0d74ca275b18cab146798bcbb94084fff'}
        foreach($psm in @(0,3,4,7,12)){
            try{Invoke-P43R3bTesseractBatch -Executable 'absent' -ModelDescriptor $unauthorized -Crops @() -Psm $psm | Out-Null;throw 'Invalid PSM accepted'}catch{Require ($_.Exception.Message -like '*ValidateSet*' -or $_.Exception.Message -like '*6,11*') "PSM $psm must reject at API boundary"}
        }
        Assert-BestFailure (Invoke-P43R3bTesseractBatch -Executable 'absent' -ModelDescriptor $unauthorized -Crops @() -Psm 6) 'MODEL_AUTHORITY_REQUIRED' 0
        Require ($script:bestCalls -eq 0 -and $script:bestVersions -eq 0) 'Invalid authority cannot probe or invoke OCR'
        if(-not $Executable -and -not $ModelPath){Write-Host 'BestBatch no-supply controls PASS; real authority/process-seam matrix=NOT_RUN_NO_SUPPLY; actual quality OCR calls=0';return}
        Require ($Executable -and $ModelPath) 'BestBatch authority matrix requires both executable and model paths'
        $localModelDirectory=Join-Path $scratch 'tessdata';[void][IO.Directory]::CreateDirectory($localModelDirectory)
        $localModel=Join-Path $localModelDirectory 'kor.traineddata';[IO.File]::Copy($ModelPath,$localModel)
        $gate=Invoke-P43R3bGateA -Executable $Executable -ModelPath $localModel
        Require ($gate.Status -ceq 'GATE_A_MODEL_SUPPLY_PASS' -and $gate.Descriptor.Sha256 -ceq 'f888d4038348a0c3d25151e7f452bda0d74ca275b18cab146798bcbb94084fff' -and $script:bestVersions -eq 1 -and $script:bestCalls -eq 0) 'Only real Gate A can authorize the unchanged best bytes'
        . $batch
        $script:bestExecutable=[IO.Path]::GetFullPath($Executable);$script:bestModelDirectory=$localModelDirectory
        $crops=@(for($id=1;$id -le 12;$id++){
            $path=Join-Path $scratch "crop-$id.pgm"
            [IO.File]::WriteAllBytes($path,[byte[]]([Text.Encoding]::ASCII.GetBytes("P5`n2 2`n255`n")+[byte[]]@(0,1,2,3)))
            [pscustomobject]@{Ordinal=$id;CellId="cell-$id";ArtifactPath=$path;CropSha256=(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant();Width=2;Height=2;ExpectedText='EXPECTED_TEXT_SECRET'}
        })
        foreach($count in @(1,2,12)){
            $subset=@($crops | Select-Object -First $count)
            $script:bestPaths=$subset.ArtifactPath -join '|';$script:bestPageCount=$count
            foreach($psm in @(6,11)){
                $script:bestPsm=$psm;$before=$script:bestCalls
                $result=Invoke-P43R3bTesseractBatch -Executable $Executable -ModelDescriptor $gate.Descriptor -Crops @($subset | Sort-Object Ordinal -Descending) -Psm $psm
                Require ($result.Status -ceq 'COMPLETE' -and $null -eq $result.Code -and $result.Psm -eq $psm -and $result.InvocationCount -eq 1 -and $result.Pages.Count -eq $count -and $result.Words.Count -eq 2*$count -and $script:bestCalls -eq $before+1 -and $result.Diagnostics.Count -eq 0 -and $result.ElapsedMilliseconds -eq 7 -and $result.ProductionAction -ceq 'NONE') "PSM$psm $count-page batch must publish one complete batch: $($result.Code)"
                Require ($result.EngineVersion -ceq '5.5.3' -and $result.EngineBuild -ceq 'tesseract v5.5.3.20260724' -and $result.ModelSha256 -ceq 'f888d4038348a0c3d25151e7f452bda0d74ca275b18cab146798bcbb94084fff') 'Best batch preserves verified engine/model identity'
                Require (($result.Pages.Page -join ',') -ceq ((1..$count) -join ',') -and ($result.Pages.CropOrdinal -join ',') -ceq ((1..$count) -join ',') -and ($result.Pages.CellId -join ',') -ceq ($subset.CellId -join ',') -and $result.Words[-1].CropOrdinal -eq $count -and $result.Words[-1].CellId -ceq "cell-$count" -and $result.Words[0].Text -ceq '가' -and $result.Words[0].Confidence -eq 0) 'Pages and words map exactly to 1..N without confidence filtering'
                for($page=1;$page -le $count;$page++){
                    $mappedWords=@($result.Words | Where-Object Page -EQ $page)
                    Require ($mappedWords.Count -eq 2 -and @($mappedWords | Where-Object {$_.CropOrdinal -ne $page -or $_.CellId -cne "cell-$page"}).Count -eq 0) 'Every word must retain its page/ordinal/CellId mapping'
                }
                Require (-not [IO.File]::Exists($script:bestList)) 'Success must clean image-list scratch'
            }
        }
        $script:bestPsm=6;$script:bestPageCount=2;$subset=@($crops[0..1]);$script:bestPaths=$subset.ArtifactPath -join '|'
        foreach($descriptor in @((Get-P43R3bModelDescriptor $localModel),($gate.Descriptor | ConvertTo-Json | ConvertFrom-Json),$unauthorized)){
            Assert-BestFailure (Invoke-P43R3bTesseractBatch -Executable $Executable -ModelDescriptor $descriptor -Crops $subset -Psm 6) 'MODEL_AUTHORITY_REQUIRED' 0
        }
        $sha=$gate.Descriptor.Sha256;$gate.Descriptor.Sha256='6b85e11d9bbf07863b97b3523b1b112844c43e713df8b66418a081fd1060b3b2'
        Assert-BestFailure (Invoke-P43R3bTesseractBatch -Executable $Executable -ModelDescriptor $gate.Descriptor -Crops $subset -Psm 6) 'MODEL_DESCRIPTOR_CHANGED' 0
        $gate.Descriptor.Sha256=$sha
        $frozen=$gate.Descriptor.FrozenAtUtc;$gate.Descriptor.FrozenAtUtc=$null
        Assert-BestFailure (Invoke-P43R3bTesseractBatch -Executable $Executable -ModelDescriptor $gate.Descriptor -Crops $subset -Psm 6) 'MODEL_DESCRIPTOR_CHANGED' 0
        $gate.Descriptor.FrozenAtUtc=$frozen
        Assert-BestFailure (Invoke-P43R3bTesseractBatch -Executable 'different-executable' -ModelDescriptor $gate.Descriptor -Crops $subset -Psm 6) 'MODEL_AUTHORITY_PATH_MISMATCH' 0
        foreach($kind in @('zero','extra','ordinal','gap','cell-id','blank-id','relative-path','newline-path','crop-hash','width','malformed-pnm')){
            $badCrops=@($crops | ForEach-Object {$_.PSObject.Copy()});$code='BATCH_CROP_IDENTITY_INVALID'
            switch($kind){
                'zero' {$badCrops=@()}
                'extra' {$badCrops+=$badCrops[0].PSObject.Copy()}
                'ordinal' {$badCrops[0].Ordinal=2}
                'gap' {$badCrops[11].Ordinal=13}
                'cell-id' {$badCrops[0].CellId='cell-2'}
                'blank-id' {$badCrops[0].CellId=' '}
                'relative-path' {$badCrops[0].ArtifactPath='relative.pgm'}
                'newline-path' {$badCrops[0].ArtifactPath+="`n"}
                'crop-hash' {$badCrops[0].CropSha256='0'*64;$code='SOURCE_PIXEL_HASH_MISMATCH'}
                'width' {$badCrops[0].Width=3}
                'malformed-pnm' {
                    $badPnm=Join-Path $scratch 'malformed.pgm';[IO.File]::WriteAllBytes($badPnm,[byte[]]@(1,2,3))
                    $badCrops[0].ArtifactPath=$badPnm;$badCrops[0].CropSha256=(Get-FileHash -LiteralPath $badPnm).Hash.ToLowerInvariant();$code='PNM_INVALID'
                }
            }
            Assert-BestFailure (Invoke-P43R3bTesseractBatch -Executable $Executable -ModelDescriptor $gate.Descriptor -Crops $badCrops -Psm 6) $code 0
        }
        foreach($case in @(@('timeout','BATCH_PROCESS_TIMEOUT'),@('process-output-limit','BATCH_PROCESS_OUTPUT_LIMIT'),@('exit','BATCH_EXIT_FAILED'),@('stdout-limit','BATCH_PROCESS_OUTPUT_LIMIT'),@('stderr-limit','BATCH_PROCESS_OUTPUT_LIMIT'),@('malformed','BATCH_TSV_INVALID'),@('missing','BATCH_PAGE_MAPPING_INVALID'),@('duplicate','BATCH_PAGE_MAPPING_INVALID'),@('extra','BATCH_PAGE_MAPPING_INVALID'),@('empty','BATCH_REQUIRED_PAGE_EMPTY'),@('dimensions','BATCH_PAGE_MAPPING_INVALID'))){
            $script:bestMode=$case[0];$before=$script:bestCalls
            Assert-BestFailure (Invoke-P43R3bTesseractBatch -Executable $Executable -ModelDescriptor $gate.Descriptor -Crops $subset -Psm 6) $case[1] 1
            Require ($script:bestCalls -eq $before+1 -and -not [IO.File]::Exists($script:bestList)) 'Failed batch cannot retry and must clean scratch'
        }
        $script:bestMode='valid';$before=$script:bestCalls
        # Mutate only a scratch copy during real crop validation, after the first
        # authority check. The immediately-before-process guard must catch it.
        $originalPnm=(Get-Command Get-P43R3aPnmDescriptor).ScriptBlock
        $script:bestMutated=$false
        function Get-P43R3aPnmDescriptor {
            param([string]$Path,[string]$ExpectedSha256)
            $descriptor=& $originalPnm -Path $Path -ExpectedSha256 $ExpectedSha256
            if(-not $script:bestMutated){
                $stream=[IO.File]::Open($localModel,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite)
                try{$value=$stream.ReadByte();$stream.Position=0;$stream.WriteByte($value -bxor 1)}finally{$stream.Dispose()}
                $script:bestMutated=$true
            }
            return $descriptor
        }
        try{
            Assert-BestFailure (Invoke-P43R3bTesseractBatch -Executable $Executable -ModelDescriptor $gate.Descriptor -Crops $subset -Psm 6) 'MODEL_BYTES_CHANGED' 0
            Require ($script:bestMutated -and $script:bestCalls -eq $before) 'Late model mutation must be rejected before the process seam'
        }finally{Set-Item Function:Get-P43R3aPnmDescriptor $originalPnm}
        # The next invocation must independently revalidate the already-changed bytes.
        Assert-BestFailure (Invoke-P43R3bTesseractBatch -Executable $Executable -ModelDescriptor $gate.Descriptor -Crops $subset -Psm 6) 'MODEL_BYTES_CHANGED' 0
        $badModel=Get-P43R3bModelDescriptor $localModel
        Require ($badModel.Code -ceq 'MODEL_BLOB_MISMATCH' -and $script:bestCalls -eq $before) 'Changed best bytes must fail pinned Git blob before quality invocation'
        [IO.File]::WriteAllBytes($localModel,[byte[]]@(1))
        Assert-BestFailure (Invoke-P43R3bTesseractBatch -Executable $Executable -ModelDescriptor $gate.Descriptor -Crops $subset -Psm 6) 'MODEL_BYTES_CHANGED' 0
        [IO.File]::Delete($localModel)
        Assert-BestFailure (Invoke-P43R3bTesseractBatch -Executable $Executable -ModelDescriptor $gate.Descriptor -Crops $subset -Psm 6) 'MODEL_BYTES_CHANGED' 0
        Require ($script:bestCalls -eq 17 -and $script:bestVersions -eq 1) 'Six success and eleven failure seams; no probes/retries/fallback outside Gate A'
        Write-Host 'BestBatch real-authority synthetic matrix PASS: success batches=6; fail-closed process batches=11; intercepted batch calls=17; version probes=1; actual quality OCR calls=0'
    }finally{Set-Item Function:Invoke-InternalP43R3aProcess $originalProcess;[IO.Directory]::Delete($scratch,$true)}
    return
}
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('milimap-p43r3b-supply-test-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($scratch)
try{
    $fixture=Join-Path $scratch 'fixture.bin'
    [IO.File]::WriteAllBytes($fixture,[Text.Encoding]::ASCII.GetBytes("hello`n"))
    Require ((Get-P43R3bGitBlobSha1 $fixture) -ceq 'ce013625030ba8dba906f756967f9e9ca394464a') 'Git blob must include the exact byte-length header and NUL'
    [IO.File]::WriteAllBytes($fixture,[byte[]]@())
    Require ((Get-P43R3bGitBlobSha1 $fixture) -ceq 'e69de29bb2d1d6434b8b29ae775ad8c2e48c5391') 'Empty Git blob identity must be exact'
    $candidate=Join-Path $scratch 'kor.traineddata'
    foreach($case in @(
        @{Path=$candidate;Code='MODEL_MISSING';Bytes=$null},
        @{Path=(Join-Path $scratch 'Kor.traineddata');Code='MODEL_FILENAME_MISMATCH';Bytes=[byte[]]@(1)},
        @{Path=$candidate;Code='MODEL_SIZE_MISMATCH';Bytes=[byte[]]@(1)},
        @{Path=$candidate;Code='MODEL_BLOB_MISMATCH';Bytes=[byte[]]::new(12528128)}
    )){
        if($null -ne $case.Bytes){[IO.File]::WriteAllBytes($case.Path,$case.Bytes)}
        $bad=Get-P43R3bModelDescriptor $case.Path
        Require ($bad.Status -ceq 'NOT_EVALUATED' -and $bad.Code -ceq $case.Code -and $null -eq $bad.Sha256 -and $null -eq $bad.FrozenAtUtc) "Invalid supply must stop before SHA256 freeze: $($case.Code)"
        $gate=Invoke-P43R3bGateA -Executable 'absent-executable' -ModelPath $case.Path
        Require ($gate.Status -ceq 'GATE_A_MODEL_SUPPLY_NOT_EVALUATED' -and $gate.Code -ceq $case.Code -and $gate.QualityInvocationCount -eq 0) 'Model identity must precede runtime or OCR'
    }
    Reject {Assert-P43R3bModelAuthority -Descriptor ([pscustomobject]@{Status='VERIFIED';Sha256='caller-authored'}) -Executable 'missing' -ModelPath $candidate} 'MODEL_AUTHORITY_REQUIRED'
    Write-Host 'ModelSupply synthetic controls PASS; quality OCR calls=0'
    if(-not $Executable -and -not $ModelPath){Write-Host 'Actual model/runtime authority=NOT_RUN_NO_SUPPLY';return}
    Require ($Executable -and $ModelPath) 'Real authority verification requires both executable and model paths'
    $descriptor=Get-P43R3bModelDescriptor $ModelPath
    Require ($descriptor.Status -ceq 'VERIFIED' -and $null -eq $descriptor.Code) 'The actual supplied candidate must prove independent blob identity'
    $expected=@{Filename='kor.traineddata';SizeBytes=12528128;GitBlobSha1='c82615b5228c9981c33a0985b32224d97b7fb43a';Sha256='f888d4038348a0c3d25151e7f452bda0d74ca275b18cab146798bcbb94084fff';SourceRepository='tesseract-ocr/tessdata_best';SourceTag='4.1.0';SourceTagObject='f0c187c74d3038e6d135fd080e30909af350eae0';SourceTagVerification='valid';SourceCommit='e2aad9b983032bb1beff9133104a67cdbb87ca4d';SourceTree='23d6207aa77e8f11abd8b300e12d2d94df300fb6';License='Apache-2.0'}
    foreach($field in $expected.Keys){Require ([string]$descriptor.$field -ceq [string]$expected[$field]) "Actual candidate descriptor mismatch: $field"}
    Require ($descriptor.Sha256 -cmatch '^[0-9a-f]{64}$' -and $descriptor.FrozenAtUtc -cmatch '^\d{4}-\d\d-\d\dT.*Z$') 'Successful blob validation must freeze lowercase SHA256 and UTC timestamp'
    Reject {Assert-P43R3bModelAuthority $descriptor $Executable $ModelPath} 'MODEL_AUTHORITY_REQUIRED'
    # Observe the real process boundary: only --version is allowed in this group.
    $originalProcess=(Get-Command Invoke-InternalP43R3aProcess).ScriptBlock
    $script:VersionCalls=0
    function Invoke-InternalP43R3aProcess {
        param([string]$Executable,[string[]]$Arguments,[int]$DeadlineMilliseconds)
        Require ($Arguments.Count -eq 1 -and $Arguments[0] -ceq '--version') 'Gate A attempted quality OCR'
        $script:VersionCalls++
        & $originalProcess -Executable $Executable -Arguments $Arguments -DeadlineMilliseconds $DeadlineMilliseconds
    }
    $gate=Invoke-P43R3bGateA $Executable $ModelPath
    Require ($gate.Status -ceq 'GATE_A_MODEL_SUPPLY_PASS' -and $null -eq $gate.Code -and $gate.QualityInvocationCount -eq 0 -and $script:VersionCalls -eq 1) 'Real Gate A must verify runtime without quality OCR'
    Require ($gate.Runtime.EngineVersion -ceq '5.5.3' -and $gate.Runtime.EngineBuild -ceq 'tesseract v5.5.3.20260724') 'Runtime version must remain the Redesign 3A identity'
    $hashes=@{'tesseract.exe'='c66f0f12ed76f6aa455dac97684bbc86756d6a732380bee09122454cfda3f420';'libtesseract-5.dll'='54d54528b453ce3a5ba79487687f8df43e7b194b9ea97beba74200453fe1fb46';'libleptonica-6.dll'='1869b44e3d46fd830620b042477e5d60a950779582f38f60291547efb27792f1'}
    foreach($name in $hashes.Keys){Require ($gate.Runtime.Hashes[$name] -ceq $hashes[$name]) "Runtime hash differs: $name"}
    Assert-P43R3bModelAuthority $gate.Descriptor $Executable $ModelPath | Out-Null
    Require (-not (Get-Command Assert-P43R3bModelAuthority).Parameters['ModelPath'].Attributes.Where({$_ -is [Management.Automation.ParameterAttribute]}).Mandatory) 'FAIL: authority cannot yet resolve the verified model path without caller input'
    $resolved=Assert-P43R3bModelAuthority -Descriptor $gate.Descriptor -Executable $Executable
    Require ($resolved.ModelPath -ceq [IO.Path]::GetFullPath($ModelPath) -and $resolved.Executable -ceq [IO.Path]::GetFullPath($Executable)) 'Authority must resolve its verified model path without caller path input'
    Reject {Assert-P43R3bModelAuthority $gate.Descriptor $Executable $candidate} 'MODEL_AUTHORITY_PATH_MISMATCH'
    $copy=$gate.Descriptor | ConvertTo-Json | ConvertFrom-Json
    Reject {Assert-P43R3bModelAuthority $copy $Executable $ModelPath} 'MODEL_AUTHORITY_REQUIRED'
    $authored=[pscustomobject]@{};foreach($property in $gate.Descriptor.PSObject.Properties){$authored | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value}
    Reject {Assert-P43R3bModelAuthority $authored $Executable $ModelPath} 'MODEL_AUTHORITY_REQUIRED'
    $originalTag=$gate.Descriptor.SourceTag;$gate.Descriptor.SourceTag='forged'
    Reject {Assert-P43R3bModelAuthority $gate.Descriptor $Executable $ModelPath} 'MODEL_DESCRIPTOR_CHANGED'
    $gate.Descriptor.SourceTag=$originalTag
    $gate.Descriptor | Add-Member -MemberType ScriptProperty -Name SourceTag -Value {'4.1.0'} -Force
    Reject {Assert-P43R3bModelAuthority $gate.Descriptor $Executable $ModelPath} 'MODEL_DESCRIPTOR_CHANGED'
    $gate.Descriptor | Add-Member -NotePropertyName SourceTag -NotePropertyValue $originalTag -Force
    $gate.Descriptor | Add-Member -NotePropertyName Properties -NotePropertyValue $authored
    Reject {Assert-P43R3bModelAuthority $gate.Descriptor $Executable $ModelPath} 'MODEL_DESCRIPTOR_CHANGED'
    $local=Join-Path $scratch 'local';[void][IO.Directory]::CreateDirectory($local)
    $localModel=Join-Path $local 'kor.traineddata';[IO.File]::Copy($ModelPath,$localModel)
    $localGate=Invoke-P43R3bGateA $Executable $localModel
    Require ($localGate.Status -ceq 'GATE_A_MODEL_SUPPLY_PASS') 'A real unchanged candidate copy must be verified through Gate A'
    $stream=[IO.File]::Open($localModel,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite)
    try{$value=$stream.ReadByte();$stream.Position=0;$stream.WriteByte($value -bxor 1)}finally{$stream.Dispose()}
    Reject {Assert-P43R3bModelAuthority $localGate.Descriptor $Executable $localModel} 'MODEL_BYTES_CHANGED'
    $missingRuntime=Invoke-P43R3bGateA 'missing-executable' $ModelPath
    Require ($missingRuntime.Status -ceq 'GATE_A_MODEL_SUPPLY_NOT_EVALUATED' -and $missingRuntime.Code -ceq 'EXECUTABLE_MISSING') 'Valid model with absent runtime must remain not evaluated'
    $fakeExe=Join-Path $local 'tesseract.exe';[IO.File]::WriteAllBytes($fakeExe,[byte[]]@(1))
    $badRuntime=Invoke-P43R3bGateA $fakeExe $ModelPath
    Require ($badRuntime.Status -ceq 'GATE_A_MODEL_SUPPLY_NOT_EVALUATED' -and $badRuntime.Code -ceq 'ENGINE_HASH_MISMATCH') 'Wrong runtime bytes must fail before version or OCR'
    $runtimeDir=Join-Path $scratch 'runtime';[void][IO.Directory]::CreateDirectory($runtimeDir)
    # Preserve the version probe's transitive DLL dependencies in scratch only.
    foreach($source in [IO.Directory]::GetFiles([IO.Path]::GetDirectoryName($Executable),'*.dll')){[IO.File]::Copy($source,(Join-Path $runtimeDir ([IO.Path]::GetFileName($source))))}
    [IO.File]::Copy($Executable,(Join-Path $runtimeDir 'tesseract.exe'))
    $localExe=Join-Path $runtimeDir 'tesseract.exe'
    $runtimeGate=Invoke-P43R3bGateA $localExe $ModelPath
    Require ($runtimeGate.Status -ceq 'GATE_A_MODEL_SUPPLY_PASS') 'Unchanged copied runtime must be verified through Gate A'
    foreach($name in $hashes.Keys){
        $path=Join-Path $runtimeDir $name;$stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite)
        try{$original=$stream.ReadByte();$stream.Position=0;$stream.WriteByte($original -bxor 1)}finally{$stream.Dispose()}
        try{
            Reject {Assert-P43R3bModelAuthority $runtimeGate.Descriptor $localExe $ModelPath} 'ENGINE_HASH_MISMATCH'
            $altered=Invoke-P43R3bGateA $localExe $ModelPath
            Require ($altered.Status -ceq 'GATE_A_MODEL_SUPPLY_NOT_EVALUATED' -and $altered.Code -ceq 'ENGINE_HASH_MISMATCH') "Altered runtime must fail before version: $name"
        }finally{$stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Write);try{$stream.WriteByte($original)}finally{$stream.Dispose()}}
    }
    Require ($script:VersionCalls -eq 3) 'Only the three successful real-supply gates may probe versions'
    Write-Host 'ModelSupply real authority PASS: exact model/runtime, copied/authored/spoofed/mutated descriptors, changed paths/model/runtime bytes rejected; version probes=3; quality OCR calls=0'
}finally{[IO.Directory]::Delete($scratch,$true)}

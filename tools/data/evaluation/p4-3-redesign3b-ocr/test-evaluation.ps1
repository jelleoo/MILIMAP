param([ValidateSet('ModelSupply')][string]$Group='ModelSupply',
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

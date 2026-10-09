Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# Historical process/parser definitions are reused read-only; its fast-model batch is never called.
. (Join-Path $PSScriptRoot '../p4-3-redesign3a-ocr/invoke-tesseract-batch.ps1')
Import-Module (New-Module -Name MilimapP43R3bModelSupply -ScriptBlock {
    # Only successful Gate A can register a reference. No registration function is exported.
    $proofs=[Runtime.CompilerServices.ConditionalWeakTable[object,object]]::new()
    $propertyAccessor=[Management.Automation.PSObject].GetProperty('Properties')
    function Get-BlobHash([IO.Stream]$Stream){
        $hash=[Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA1)
        try{
            $hash.AppendData([Text.Encoding]::ASCII.GetBytes("blob $($Stream.Length)`0"))
            $buffer=[byte[]]::new(65536)
            while(($count=$Stream.Read($buffer,0,$buffer.Length)) -gt 0){$hash.AppendData($buffer,0,$count)}
            [Convert]::ToHexString($hash.GetHashAndReset()).ToLowerInvariant()
        }finally{$hash.Dispose()}
    }
    function Get-P43R3bGitBlobSha1 {
        param([Parameter(Mandatory)][string]$Path)
        $stream=[IO.File]::OpenRead($Path)
        try{Get-BlobHash $stream}finally{$stream.Dispose()}
    }
    function Get-P43R3bModelDescriptor {
        param([Parameter(Mandatory)][string]$ModelPath)
        $descriptor=[pscustomobject]@{Status='NOT_EVALUATED';Code=$null;Filename=[IO.Path]::GetFileName($ModelPath);SizeBytes=$null;GitBlobSha1=$null;Sha256=$null;SourceRepository='tesseract-ocr/tessdata_best';SourceTag='4.1.0';SourceTagObject='f0c187c74d3038e6d135fd080e30909af350eae0';SourceTagVerification='valid';SourceCommit='e2aad9b983032bb1beff9133104a67cdbb87ca4d';SourceTree='23d6207aa77e8f11abd8b300e12d2d94df300fb6';License='Apache-2.0';FrozenAtUtc=$null}
        $stream=$null
        try{
            if(-not [IO.File]::Exists($ModelPath)){throw 'MODEL_MISSING'}
            if($descriptor.Filename -cne 'kor.traineddata'){throw 'MODEL_FILENAME_MISMATCH'}
            # One write-excluding handle proves blob and freezes SHA256 over the same bytes.
            $stream=[IO.File]::OpenRead($ModelPath)
            $descriptor.SizeBytes=$stream.Length
            if($descriptor.SizeBytes -ne 12528128){throw 'MODEL_SIZE_MISMATCH'}
            $descriptor.GitBlobSha1=Get-BlobHash $stream
            if($descriptor.GitBlobSha1 -cne 'c82615b5228c9981c33a0985b32224d97b7fb43a'){throw 'MODEL_BLOB_MISMATCH'}
            $stream.Position=0
            $descriptor.Sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream)).ToLowerInvariant()
            $descriptor.FrozenAtUtc=[DateTime]::UtcNow.ToString('o',[Globalization.CultureInfo]::InvariantCulture)
            $descriptor.Status='VERIFIED'
        }catch{$descriptor.Code=$_.Exception.Message}
        finally{if($null -ne $stream){$stream.Dispose()}}
        return $descriptor
    }
    function Get-Runtime([string]$Executable){
        if(-not [IO.File]::Exists($Executable)){throw 'EXECUTABLE_MISSING'}
        $runtime=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Executable))
        $expected=[ordered]@{'tesseract.exe'='c66f0f12ed76f6aa455dac97684bbc86756d6a732380bee09122454cfda3f420';'libtesseract-5.dll'='54d54528b453ce3a5ba79487687f8df43e7b194b9ea97beba74200453fe1fb46';'libleptonica-6.dll'='1869b44e3d46fd830620b042477e5d60a950779582f38f60291547efb27792f1'}
        $hashes=[ordered]@{}
        foreach($name in $expected.Keys){
            $path=if($name -ceq 'tesseract.exe'){[IO.Path]::GetFullPath($Executable)}else{Join-Path $runtime $name}
            if(-not [IO.File]::Exists($path)){throw 'ENGINE_HASH_MISMATCH'}
            $stream=[IO.File]::OpenRead($path)
            try{$hashes[$name]=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream)).ToLowerInvariant()}finally{$stream.Dispose()}
            if($hashes[$name] -cne $expected[$name]){throw 'ENGINE_HASH_MISMATCH'}
        }
        [pscustomobject]@{Executable=[IO.Path]::GetFullPath($Executable);Hashes=$hashes;EngineVersion='5.5.3';EngineBuild='tesseract v5.5.3.20260724'}
    }
    function Invoke-P43R3bGateA {
        param([Parameter(Mandatory)][string]$Executable,[Parameter(Mandatory)][string]$ModelPath)
        $result=[pscustomobject]@{Status='GATE_A_MODEL_SUPPLY_NOT_EVALUATED';Code=$null;Descriptor=$null;Runtime=$null;QualityInvocationCount=0;ProductionAction='NONE'}
        try{
            $descriptor=Get-P43R3bModelDescriptor $ModelPath
            $result.Descriptor=$descriptor
            if($descriptor.Status -cne 'VERIFIED'){throw $descriptor.Code}
            $runtime=Get-Runtime $Executable
            $identity=Invoke-InternalP43R3aProcess -Executable $Executable -Arguments @('--version') -DeadlineMilliseconds 3000
            if($identity.ExitCode -ne 0 -or $identity.Text -cnotmatch '^tesseract v5\.5\.3\.20260724(?:\r?\n|$)'){throw 'ENGINE_VERSION_MISMATCH'}
            if([Text.Encoding]::UTF8.GetByteCount($identity.Text) -gt 65536 -or [Text.Encoding]::UTF8.GetByteCount($identity.ErrorText) -gt 65536){throw 'BATCH_PROCESS_OUTPUT_LIMIT'}
            $snapshot=@{}
            foreach($property in $propertyAccessor.GetValue([Management.Automation.PSObject]::AsPSObject($descriptor))){$snapshot[$property.Name]=$property.Value}
            $proofs.Add($descriptor,[pscustomobject]@{Fields=$snapshot;ModelPath=[IO.Path]::GetFullPath($ModelPath);Executable=$runtime.Executable})
            $result.Runtime=$runtime;$result.Status='GATE_A_MODEL_SUPPLY_PASS'
        }catch{$result.Code=$_.Exception.Message}
        return $result
    }
    function Assert-P43R3bModelAuthority {
        param([Parameter(Mandatory)][object]$Descriptor,[Parameter(Mandatory)][string]$Executable,[Parameter(Mandatory)][string]$ModelPath)
        $proof=$null
        if(-not $proofs.TryGetValue($Descriptor,[ref]$proof)){throw 'MODEL_AUTHORITY_REQUIRED'}
        # Read CLR metadata directly instead of trusting caller-authored members.
        $properties=$propertyAccessor.GetValue([Management.Automation.PSObject]::AsPSObject($Descriptor))
        if(@($properties).Count -ne $proof.Fields.Count){throw 'MODEL_DESCRIPTOR_CHANGED'}
        foreach($name in $proof.Fields.Keys){
            $property=$properties.get_Item($name)
            if($null -eq $property -or $property.MemberType -ne [Management.Automation.PSMemberTypes]::NoteProperty -or -not [object]::Equals($property.Value,$proof.Fields[$name])){throw 'MODEL_DESCRIPTOR_CHANGED'}
        }
        if([IO.Path]::GetFullPath($ModelPath) -cne $proof.ModelPath -or [IO.Path]::GetFullPath($Executable) -cne $proof.Executable){throw 'MODEL_AUTHORITY_PATH_MISMATCH'}
        $current=Get-P43R3bModelDescriptor $proof.ModelPath
        if($current.Status -cne 'VERIFIED' -or $current.Sha256 -cne $proof.Fields['Sha256']){throw 'MODEL_BYTES_CHANGED'}
        Get-Runtime $proof.Executable
    }
    Export-ModuleMember -Function Get-P43R3bGitBlobSha1,Get-P43R3bModelDescriptor,Invoke-P43R3bGateA,Assert-P43R3bModelAuthority
}) -Force

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# Preserve an already-issued Gate A proof when loading the batch boundary.
if($null -eq (Get-Command Assert-P43R3bModelAuthority -ErrorAction SilentlyContinue)){
    . (Join-Path $PSScriptRoot 'model-supply.ps1')
}
. (Join-Path $PSScriptRoot '../p4-3-redesign3a-ocr/crop-cells.ps1')

function Invoke-P43R3bTesseractBatch {
    param([Parameter(Mandatory)][string]$Executable,[Parameter(Mandatory)][object]$ModelDescriptor,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Crops,[Parameter(Mandatory)][ValidateSet(6,11)][int]$Psm)
    $result=[pscustomobject]@{Status='FAILED';Code=$null;Psm=$Psm;InvocationCount=0;EngineVersion=$null;EngineBuild=$null;ModelSha256=$null;Pages=@();Words=@();Diagnostics=@();ElapsedMilliseconds=0;ProductionAction='NONE'}
    $scratch=$null
    try{
        # Only the supply module's exact reference proof can resolve model paths.
        $runtime=Assert-P43R3bModelAuthority -Descriptor $ModelDescriptor -Executable $Executable
        $result.ModelSha256=$ModelDescriptor.Sha256
        $result.EngineVersion=$runtime.EngineVersion;$result.EngineBuild=$runtime.EngineBuild
        if($Crops.Count -lt 1 -or $Crops.Count -gt 12){throw 'BATCH_CROP_IDENTITY_INVALID'}
        $ordered=@($Crops | Sort-Object {[int]$_.Ordinal})
        $ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        for($i=0;$i -lt $ordered.Count;$i++){
            $crop=$ordered[$i]
            if([string]$crop.Ordinal -cne [string]($i+1) -or [string]::IsNullOrWhiteSpace($crop.CellId) -or -not $ids.Add([string]$crop.CellId)){throw 'BATCH_CROP_IDENTITY_INVALID'}
            if(-not [IO.Path]::IsPathFullyQualified($crop.ArtifactPath) -or $crop.ArtifactPath.Contains("`n") -or $crop.ArtifactPath.Contains("`r")){throw 'BATCH_CROP_IDENTITY_INVALID'}
            $descriptor=Get-P43R3aPnmDescriptor -Path $crop.ArtifactPath -ExpectedSha256 $crop.CropSha256
            if($descriptor.Width -ne $crop.Width -or $descriptor.Height -ne $crop.Height){throw 'BATCH_CROP_IDENTITY_INVALID'}
        }
        $scratch=Join-Path ([IO.Path]::GetTempPath()) ('milimap-p43r3b-list-'+[guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($scratch)
        $list=Join-Path $scratch 'images.txt'
        [IO.File]::WriteAllLines($list,[string[]]$ordered.ArtifactPath,[Text.UTF8Encoding]::new($false))
        $arguments=@($list,'stdout','--tessdata-dir',[IO.Path]::GetDirectoryName($runtime.ModelPath),'-l','kor','--oem','1','--psm',[string]$Psm,'--dpi','300','-c','tessedit_create_tsv=1')
        # Revalidate the frozen SHA256, pinned Git blob and runtime immediately
        # before each quality invocation, after crop/list preparation.
        Assert-P43R3bModelAuthority -Descriptor $ModelDescriptor -Executable $Executable | Out-Null
        $result.InvocationCount=1
        $output=Invoke-InternalP43R3aProcess -Executable $Executable -Arguments $arguments -DeadlineMilliseconds 10000
        $result.ElapsedMilliseconds=$output.ElapsedMilliseconds
        if([Text.Encoding]::UTF8.GetByteCount($output.Text) -gt 1048576 -or [Text.Encoding]::UTF8.GetByteCount($output.ErrorText) -gt 65536){throw 'BATCH_PROCESS_OUTPUT_LIMIT'}
        if($output.ExitCode -ne 0){throw 'BATCH_EXIT_FAILED'}
        $parsed=ConvertFrom-P43R3aBatchTsv -Text $output.Text -ExpectedPageCount $ordered.Count
        foreach($page in $parsed.Pages){
            $crop=$ordered[$page.Page-1]
            if($page.Width -ne $crop.Width -or $page.Height -ne $crop.Height){throw 'BATCH_PAGE_MAPPING_INVALID'}
            $page | Add-Member -NotePropertyName CropOrdinal -NotePropertyValue $crop.Ordinal
            $page | Add-Member -NotePropertyName CellId -NotePropertyValue $crop.CellId
        }
        foreach($word in $parsed.Words){
            $crop=$ordered[$word.Page-1]
            $word | Add-Member -NotePropertyName CropOrdinal -NotePropertyValue $crop.Ordinal
            $word | Add-Member -NotePropertyName CellId -NotePropertyValue $crop.CellId
        }
        $result.Pages=$parsed.Pages;$result.Words=$parsed.Words;$result.Status='COMPLETE'
    }catch{$result.Code=$_.Exception.Message;$result.Diagnostics=@([pscustomobject]@{Code=$result.Code});$result.Pages=@();$result.Words=@()}
    finally{if($null -ne $scratch -and [IO.Directory]::Exists($scratch)){[IO.Directory]::Delete($scratch,$true)}}
    return $result
}

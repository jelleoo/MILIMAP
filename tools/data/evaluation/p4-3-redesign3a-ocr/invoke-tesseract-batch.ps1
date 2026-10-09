Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function ConvertFrom-P43R3aBatchTsv {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text,[Parameter(Mandatory)][ValidateRange(1,12)][int]$ExpectedPageCount)
    $lines=$Text.TrimEnd("`r","`n") -split '\r?\n'
    if([Text.Encoding]::UTF8.GetByteCount($Text) -gt 1048576 -or $lines.Count -lt 2 -or $lines.Count -gt 10000 -or $lines[0] -cne "level`tpage_num`tblock_num`tpar_num`tline_num`tword_num`tleft`ttop`twidth`theight`tconf`ttext"){throw 'BATCH_TSV_INVALID'}
    $pages=[Collections.Generic.List[object]]::new();$words=[Collections.Generic.List[object]]::new()
    $hierarchy=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $currentPage=0
    foreach($line in $lines | Select-Object -Skip 1){
        $parts=$line.Split("`t")
        if($parts.Count -ne 12){throw 'BATCH_TSV_INVALID'}
        $ints=[int[]]::new(10)
        for($i=0;$i -lt 10;$i++){
            $number=[int]0
            if($parts[$i] -cnotmatch '^(0|[1-9][0-9]*)$' -or -not [int]::TryParse($parts[$i],[ref]$number)){throw 'BATCH_TSV_INVALID'}
            $ints[$i]=$number
        }
        $confidence=[double]0
        if(-not [double]::TryParse($parts[10],[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$confidence) -or -not [double]::IsFinite($confidence) -or $confidence -lt -1 -or $confidence -gt 100 -or $ints[0] -lt 1 -or $ints[0] -gt 5){throw 'BATCH_TSV_INVALID'}
        $level=$ints[0];$page=$ints[1]
        if($page -lt 1 -or $page -gt $ExpectedPageCount){throw 'BATCH_PAGE_MAPPING_INVALID'}
        if($level -eq 1){
            if($page -ne $currentPage+1){throw 'BATCH_PAGE_MAPPING_INVALID'}
            if($ints[6] -ne 0 -or $ints[7] -ne 0){throw 'BATCH_TSV_INVALID'}
            $pages.Add([pscustomobject]@{Page=$page;Left=$ints[6];Top=$ints[7];Width=$ints[8];Height=$ints[9];WordCount=0})
            $currentPage=$page
        }elseif($page -ne $currentPage){throw 'BATCH_PAGE_MAPPING_INVALID'}
        if($ints[8] -le 0 -or $ints[9] -le 0){throw 'BATCH_TSV_INVALID'}
        # Each hierarchy level has positive ancestors and zero descendant counters.
        for($i=2;$i -le 5;$i++){
            if(($i -le $level -and $ints[$i] -le 0) -or ($i -gt $level -and $ints[$i] -ne 0)){throw 'BATCH_TSV_INVALID'}
        }
        if(($level -lt 5 -and ($confidence -ne -1 -or $parts[11] -cne '')) -or ($level -eq 5 -and $confidence -lt 0)){throw 'BATCH_TSV_INVALID'}
        $key=(@($level)+@($ints[1..5])) -join ':'
        if(-not $hierarchy.Add($key)){throw 'BATCH_TSV_INVALID'}
        if($level -gt 1){
            $parent=$ints.Clone();$parent[$level]=0
            $parentKey=(@($level-1)+@($parent[1..5])) -join ':'
            if(-not $hierarchy.Contains($parentKey)){throw 'BATCH_TSV_INVALID'}
        }
        $descriptor=$pages[$page-1]
        if([long]$ints[6]+$ints[8] -gt $descriptor.Width -or [long]$ints[7]+$ints[9] -gt $descriptor.Height){throw 'BATCH_TSV_INVALID'}
        if($level -eq 5 -and -not [string]::IsNullOrWhiteSpace($parts[11])){
            $words.Add([pscustomobject]@{Page=$page;Block=$ints[2];Paragraph=$ints[3];Line=$ints[4];Word=$ints[5];Left=$ints[6];Top=$ints[7];Width=$ints[8];Height=$ints[9];Confidence=$confidence;Text=$parts[11]})
            $descriptor.WordCount++
        }
    }
    if($pages.Count -ne $ExpectedPageCount){throw 'BATCH_PAGE_MAPPING_INVALID'}
    if(@($pages | Where-Object WordCount -eq 0).Count -gt 0){throw 'BATCH_REQUIRED_PAGE_EMPTY'}
    return [pscustomobject]@{Pages=$pages.ToArray();Words=$words.ToArray()}
}

function Invoke-InternalP43R3aProcess {
    param([string]$Executable,[string[]]$Arguments,[int]$DeadlineMilliseconds)
    $info=[Diagnostics.ProcessStartInfo]::new([IO.Path]::GetFullPath($Executable))
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $info.StandardOutputEncoding=[Text.UTF8Encoding]::new($false)
    $info.StandardErrorEncoding=[Text.UTF8Encoding]::new($false)
    foreach($argument in $Arguments){$info.ArgumentList.Add($argument)}
    $process=[Diagnostics.Process]::new();$process.StartInfo=$info;$started=$false
    $clock=[Diagnostics.Stopwatch]::StartNew()
    try{
        $started=$process.Start();if(-not $started){throw 'BATCH_PROCESS_START_FAILED'}
        $readers=@($process.StandardOutput,$process.StandardError)
        $buffers=@([char[]]::new(4096),[char[]]::new(4096))
        $builders=@([Text.StringBuilder]::new(),[Text.StringBuilder]::new())
        $tasks=@($readers[0].ReadAsync($buffers[0],0,4096),$readers[1].ReadAsync($buffers[1],0,4096))
        $closed=@($false,$false);$byteCounts=@(0,0);$limits=@(1048576,65536)
        while(-not ($closed[0] -and $closed[1] -and $process.HasExited)){
            if($clock.ElapsedMilliseconds -ge $DeadlineMilliseconds){throw 'BATCH_PROCESS_TIMEOUT'}
            for($i=0;$i -lt 2;$i++){
                if(-not $closed[$i] -and $tasks[$i].IsCompleted){
                    $count=$tasks[$i].GetAwaiter().GetResult()
                    if($count -eq 0){$closed[$i]=$true;continue}
                    $byteCounts[$i]+=[Text.Encoding]::UTF8.GetByteCount($buffers[$i],0,$count)
                    if($byteCounts[$i] -gt $limits[$i]){throw 'BATCH_PROCESS_OUTPUT_LIMIT'}
                    [void]$builders[$i].Append($buffers[$i],0,$count)
                    $tasks[$i]=$readers[$i].ReadAsync($buffers[$i],0,4096)
                }
            }
            [Threading.Thread]::Sleep(5)
        }
        return [pscustomobject]@{ExitCode=$process.ExitCode;Text=$builders[0].ToString();ErrorText=$builders[1].ToString();ElapsedMilliseconds=$clock.ElapsedMilliseconds}
    }finally{if($started -and -not $process.HasExited){$process.Kill($true);$process.WaitForExit()};$process.Dispose()}
}

function Invoke-P43R3aTesseractBatch {
    param([Parameter(Mandatory)][string]$Executable,[Parameter(Mandatory)][string]$ModelPath,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Crops,[Parameter(Mandatory)][ValidateSet(6,11)][int]$Psm)
    $result=[pscustomobject]@{Status='FAILED';Code=$null;Psm=$Psm;InvocationCount=0;EngineVersion=$null;EngineBuild=$null;ModelSha256=$null;Pages=@();Words=@();Diagnostics=@();ElapsedMilliseconds=0;ProductionAction='NONE'}
    $scratch=$null
    try{
        if(-not [IO.File]::Exists($Executable)){throw 'EXECUTABLE_MISSING'}
        $runtime=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Executable))
        $identities=@{
            ([IO.Path]::GetFullPath($Executable))='c66f0f12ed76f6aa455dac97684bbc86756d6a732380bee09122454cfda3f420'
            (Join-Path $runtime 'libtesseract-5.dll')='54d54528b453ce3a5ba79487687f8df43e7b194b9ea97beba74200453fe1fb46'
            (Join-Path $runtime 'libleptonica-6.dll')='1869b44e3d46fd830620b042477e5d60a950779582f38f60291547efb27792f1'
        }
        foreach($path in $identities.Keys){
            if(-not [IO.File]::Exists($path) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $identities[$path]){throw 'ENGINE_HASH_MISMATCH'}
        }
        if(-not [IO.File]::Exists($ModelPath)){throw 'MODEL_MISSING'}
        if([IO.Path]::GetFileName($ModelPath) -cne 'kor.traineddata'){throw 'MODEL_FILENAME_MISMATCH'}
        $result.ModelSha256=(Get-FileHash -LiteralPath $ModelPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if($result.ModelSha256 -cne '6b85e11d9bbf07863b97b3523b1b112844c43e713df8b66418a081fd1060b3b2'){throw 'MODEL_HASH_MISMATCH'}
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
        $identity=Invoke-InternalP43R3aProcess -Executable $Executable -Arguments @('--version') -DeadlineMilliseconds 3000
        if($identity.ExitCode -ne 0 -or $identity.Text -cnotmatch '^tesseract v5\.5\.3\.20260724(?:\r?\n|$)'){throw 'ENGINE_VERSION_MISMATCH'}
        if([Text.Encoding]::UTF8.GetByteCount($identity.Text) -gt 65536 -or [Text.Encoding]::UTF8.GetByteCount($identity.ErrorText) -gt 65536){throw 'BATCH_PROCESS_OUTPUT_LIMIT'}
        $result.EngineVersion='5.5.3';$result.EngineBuild=($identity.Text -split '\r?\n')[0]
        $scratch=Join-Path ([IO.Path]::GetTempPath()) ('milimap-p43r3a-list-'+[guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($scratch)
        $list=Join-Path $scratch 'images.txt'
        [IO.File]::WriteAllLines($list,[string[]]$ordered.ArtifactPath,[Text.UTF8Encoding]::new($false))
        $arguments=@($list,'stdout','--tessdata-dir',[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($ModelPath)),'-l','kor','--oem','1','--psm',[string]$Psm,'--dpi','300','-c','tessedit_create_tsv=1')
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

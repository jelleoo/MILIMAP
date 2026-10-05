Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Test-P43a2EngineVersion {
    param([Parameter(Mandatory)][string]$Text)
    return $Text -cmatch '^tesseract (?:5\.5\.3|v5\.5\.3\.20260724)(?:\r?\n|$)'
}

function ConvertFrom-P43a2Tsv {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $lines=$Text.TrimEnd("`r","`n") -split '\r?\n'
    if($lines.Count -lt 2 -or $lines.Count -gt 10000 -or $lines[0] -cne "level`tpage_num`tblock_num`tpar_num`tline_num`tword_num`tleft`ttop`twidth`theight`tconf`ttext"){throw 'P43A2_TSV_HEADER_OR_SIZE'}
    $words=[Collections.Generic.List[object]]::new()
    foreach($line in $lines | Select-Object -Skip 1){
        $parts=$line.Split("`t")
        if($parts.Count -ne 12){throw 'P43A2_TSV_COLUMNS'}
        $ints=[int[]]::new(10)
        for($i=0;$i -lt 10;$i++){
            $number=[int]0
            if(-not [int]::TryParse($parts[$i],[ref]$number) -or $number -lt 0){throw 'P43A2_TSV_INTEGER'}
            $ints[$i]=$number
        }
        $confidence=[double]0
        if(-not [double]::TryParse($parts[10],[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$confidence) -or -not [double]::IsFinite($confidence) -or $confidence -lt -1 -or $confidence -gt 100){throw 'P43A2_TSV_CONFIDENCE'}
        if($ints[0] -lt 1 -or $ints[0] -gt 5 -or $ints[1] -ne 1){throw 'P43A2_TSV_PAGE_OR_LEVEL'}
        if($ints[0] -eq 5){
            if($ints[2] -eq 0 -or $ints[3] -eq 0 -or $ints[4] -eq 0 -or $ints[5] -eq 0 -or $ints[8] -eq 0 -or $ints[9] -eq 0 -or $confidence -lt 0){throw 'P43A2_TSV_WORD_HIERARCHY_OR_VALUE'}
            # Tesseract reports ruled-line decoration as whitespace level-5 records.
            # They contain no text. All-whitespace output still fails EMPTY_WORD_OUTPUT.
            if([string]::IsNullOrWhiteSpace($parts[11])){continue}
            $words.Add([pscustomobject]@{Page=$ints[1];Block=$ints[2];Paragraph=$ints[3];Line=$ints[4];Word=$ints[5];Left=$ints[6];Top=$ints[7];Width=$ints[8];Height=$ints[9];Confidence=$confidence;Text=$parts[11]})
        }
    }
    if($words.Count -eq 0){throw 'P43A2_TSV_EMPTY_WORD_OUTPUT'}
    # Publish only after the whole TSV validates; later malformed records cannot leak a prefix.
    return $words.ToArray()
}

function Invoke-InternalP43a2Process {
    param([string]$Executable,[string[]]$Arguments,[int]$DeadlineMilliseconds)
    $info=[Diagnostics.ProcessStartInfo]::new([IO.Path]::GetFullPath($Executable))
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $info.StandardOutputEncoding=[Text.UTF8Encoding]::new($false)
    foreach($argument in $Arguments){$info.ArgumentList.Add($argument)}
    $process=[Diagnostics.Process]::new();$process.StartInfo=$info;$started=$false
    $clock=[Diagnostics.Stopwatch]::StartNew()
    try{
        $started=$process.Start()
        if(-not $started){throw 'P43A2_PROCESS_START_FAILED'}
        $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        if(-not $process.WaitForExit($DeadlineMilliseconds)){$process.Kill($true);$process.WaitForExit();throw 'P43A2_PROCESS_TIMEOUT'}
        $text=$stdout.GetAwaiter().GetResult();$errorText=$stderr.GetAwaiter().GetResult()
        if([Text.Encoding]::UTF8.GetByteCount($text) -gt 1048576 -or [Text.Encoding]::UTF8.GetByteCount($errorText) -gt 65536){throw 'P43A2_PROCESS_OUTPUT_LIMIT'}
        return [pscustomobject]@{ExitCode=$process.ExitCode;Text=$text;ElapsedMilliseconds=$clock.ElapsedMilliseconds}
    }finally{if($started -and -not $process.HasExited){$process.Kill($true)};$process.Dispose()}
}

function Invoke-P43a2TesseractEvaluation {
    param([Parameter(Mandatory)][string]$Executable,[Parameter(Mandatory)][string]$ModelPath,
        [AllowEmptyCollection()][string[]]$Inputs=@(),[ValidateSet(3,4,6,11)][int]$Psm=11)
    $result=[ordered]@{ProbeId='MILIMAP_P4_3A2_OCR_EVAL';SchemaVersion=1;OverlapPolicyCandidates=@(0.25,0.50,0.75);
        Status='FAILED';Code=$null;EngineVersion=$null;EngineBuild=$null;ModelSha256=$null;InvocationCount=0;ElapsedMilliseconds=0;Words=@();Diagnostics=@();ProductionAction='NONE'}
    try{
        if($Inputs.Count -ne 1){throw 'INPUT_UNSUPPORTED'}
        if(-not [IO.File]::Exists($Executable)){throw 'EXECUTABLE_MISSING'}
        if(-not [IO.File]::Exists($ModelPath)){throw 'MODEL_MISSING'}
        if([IO.Path]::GetFileName($ModelPath) -cne 'kor.traineddata'){throw 'MODEL_FILENAME_MISMATCH'}
        $result.ModelSha256=(Get-FileHash -LiteralPath $ModelPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if($result.ModelSha256 -cne '6b85e11d9bbf07863b97b3523b1b112844c43e713df8b66418a081fd1060b3b2'){throw 'MODEL_HASH_MISMATCH'}
        $identity=Invoke-InternalP43a2Process -Executable $Executable -Arguments @('--version') -DeadlineMilliseconds 3000
        if($identity.ExitCode -ne 0 -or -not (Test-P43a2EngineVersion -Text $identity.Text)){throw 'ENGINE_VERSION_MISMATCH'}
        $result.EngineVersion='5.5.3';$result.EngineBuild=($identity.Text -split '\r?\n')[0]
        if(-not [IO.File]::Exists($Inputs[0])){throw 'INPUT_UNSUPPORTED'}
        $arguments=@([IO.Path]::GetFullPath($Inputs[0]),'stdout','--tessdata-dir',[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($ModelPath)),'-l','kor','--oem','1','--psm',[string]$Psm,'--dpi','300','-c','tessedit_create_tsv=1')
        $result.InvocationCount=1
        $output=Invoke-InternalP43a2Process -Executable $Executable -Arguments $arguments -DeadlineMilliseconds 10000
        $result.ElapsedMilliseconds=$output.ElapsedMilliseconds
        if($output.ExitCode -ne 0){throw 'OCR_EXIT_FAILED'}
        $result.Words=@(ConvertFrom-P43a2Tsv -Text $output.Text)
        $result.Status='COMPLETE'
    }catch{
        $result.Code=$_.Exception.Message;$result.Diagnostics=@([pscustomobject]@{Code=$result.Code})
        $result.Words=@()
    }
    return [pscustomobject]$result
}

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Invoke-TesseractEvaluation {
    param([Parameter(Mandatory)][string]$Executable,[Parameter(Mandatory)][string]$ModelPath,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$ModelHash,
        [AllowEmptyCollection()][string[]]$Inputs=@(),[ValidateSet(3,4,6,11)][int]$Psm=6)
    $result=[ordered]@{Status='FAILED';Code=$null;EngineVersion=$null;ModelSha256=$null;InvocationCount=0;Words=@();ElapsedMilliseconds=0}
    if(-not [IO.File]::Exists($Executable)){$result.Code='EXECUTABLE_MISSING';return [pscustomobject]$result}
    if(-not [IO.File]::Exists($ModelPath)){$result.Code='MODEL_MISSING';return [pscustomobject]$result}
    $result.ModelSha256=(Get-FileHash -LiteralPath $ModelPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if($result.ModelSha256 -cne $ModelHash){$result.Code='MODEL_HASH_MISMATCH';return [pscustomobject]$result}
    $info=[Diagnostics.ProcessStartInfo]::new($Executable)
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $info.ArgumentList.Add('--version')
    $process=[Diagnostics.Process]::new();$process.StartInfo=$info
    try{
        [void]$process.Start()
        $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        if(-not $process.WaitForExit(3000)){$process.Kill($true);$result.Code='ENGINE_IDENTITY_TIMEOUT';return [pscustomobject]$result}
        $version=$stdout.GetAwaiter().GetResult()
        if($version.Length -gt 65536 -or $stderr.GetAwaiter().GetResult().Length -gt 65536 -or $process.ExitCode -ne 0 -or $version -cnotmatch '^tesseract (?:5\.5\.3|v5\.5\.3\.20260724)(?:\r?\n|$)'){
            $result.Code='ENGINE_VERSION_MISMATCH';return [pscustomobject]$result
        }
        $result.EngineVersion='5.5.3'
        if($Inputs.Count -ne 1 -or -not [IO.File]::Exists($Inputs[0])){$result.Code='INPUT_UNSUPPORTED';return [pscustomobject]$result}
        $process.Dispose()
        $info=[Diagnostics.ProcessStartInfo]::new([IO.Path]::GetFullPath($Executable))
        $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
        $info.StandardOutputEncoding=[Text.UTF8Encoding]::new($false)
        foreach($arg in @([IO.Path]::GetFullPath($Inputs[0]),'stdout','--tessdata-dir',[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($ModelPath)),'-l','kor','--oem','1','--psm',[string]$Psm,'--dpi','300','-c','tessedit_create_tsv=1')){$info.ArgumentList.Add($arg)}
        $process=[Diagnostics.Process]::new();$process.StartInfo=$info
        $clock=[Diagnostics.Stopwatch]::StartNew();[void]$process.Start();$result.InvocationCount=1
        $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        if(-not $process.WaitForExit(10000)){$process.Kill($true);$result.Code='OCR_TIMEOUT';return [pscustomobject]$result}
        $raw=$stdout.GetAwaiter().GetResult();$errorText=$stderr.GetAwaiter().GetResult();$result.ElapsedMilliseconds=$clock.ElapsedMilliseconds
        if($process.ExitCode -ne 0){$result.Code='OCR_EXIT_FAILED';return [pscustomobject]$result}
        if([Text.Encoding]::UTF8.GetByteCount($raw) -gt 1048576 -or $errorText.Length -gt 65536){$result.Code='OCR_OUTPUT_LIMIT';return [pscustomobject]$result}
        $result.Words=@(ConvertFrom-EvaluationTsv -Text $raw)
        $result.Status='COMPLETE';$result.Code=$null
        return [pscustomobject]$result
    }catch{$result.Code=if($result.InvocationCount -eq 1){'OCR_TSV_INVALID'}else{'ENGINE_IDENTITY_FAILED'};return [pscustomobject]$result}
    finally{if($process.Id -and -not $process.HasExited){$process.Kill($true)};$process.Dispose()}
}

function ConvertFrom-EvaluationTsv {
    param([Parameter(Mandatory)][string]$Text)
    $lines=$Text.TrimEnd("`r","`n") -split '\r?\n'
    if($lines.Count -lt 2 -or $lines.Count -gt 10000 -or $lines[0] -cne "level`tpage_num`tblock_num`tpar_num`tline_num`tword_num`tleft`ttop`twidth`theight`tconf`ttext"){throw 'Malformed TSV header/size'}
    foreach($line in $lines | Select-Object -Skip 1){
        $parts=$line.Split("`t")
        if($parts.Count -ne 12){throw 'Malformed TSV columns'}
        $ints=[int[]]::new(10)
        for($i=0;$i -lt 10;$i++){$parsed=[int]0;if(-not [int]::TryParse($parts[$i],[ref]$parsed) -or $parsed -lt 0){throw 'Malformed TSV integer'};$ints[$i]=$parsed}
        $confidence=[double]0
        if(-not [double]::TryParse($parts[10],[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$confidence) -or -not [double]::IsFinite($confidence) -or $confidence -lt -1 -or $confidence -gt 100){throw 'Malformed TSV confidence'}
        if($ints[0] -lt 1 -or $ints[0] -gt 5 -or $ints[1] -ne 1){throw 'Malformed TSV page/level'}
        if($ints[0] -eq 5 -and -not [string]::IsNullOrWhiteSpace($parts[11])){
            if($ints[8] -eq 0 -or $ints[9] -eq 0 -or $confidence -lt 0){throw 'Invalid word box/confidence'}
            [pscustomobject]@{Page=$ints[1];Left=$ints[6];Top=$ints[7];Width=$ints[8];Height=$ints[9];Confidence=$confidence;Text=$parts[11]}
        }
    }
}

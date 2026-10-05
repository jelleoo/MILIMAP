Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Invoke-TesseractEvaluation {
    param([Parameter(Mandatory)][string]$Executable,[Parameter(Mandatory)][string]$ModelPath,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$ModelHash,
        [AllowEmptyCollection()][string[]]$Inputs=@())
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
        if($version.Length -gt 65536 -or $stderr.GetAwaiter().GetResult().Length -gt 65536 -or $process.ExitCode -ne 0 -or $version -cnotmatch '^tesseract 5\.5\.3(?:\s|$)'){
            $result.Code='ENGINE_VERSION_MISMATCH';return [pscustomobject]$result
        }
        $result.EngineVersion='5.5.3'
        $result.Code='OCR_NOT_IMPLEMENTED'
        return [pscustomobject]$result
    }catch{$result.Code='ENGINE_IDENTITY_FAILED';return [pscustomobject]$result}
    finally{if($process.Id -and -not $process.HasExited){$process.Kill($true)};$process.Dispose()}
}

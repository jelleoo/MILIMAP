Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../benefit-evidence-location-contracts.ps1')

function Get-InternalBenefitPdfNativeCommand {
    param([Parameter(Mandatory)][string]$InputFile)
    $root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../pdf-native'))
    $dotnet=(Get-Command dotnet -ErrorAction Stop).Source
    $dll=Join-Path $root 'bin/Release/net8.0/Milimap.PdfNative.dll'
    if(-not (Test-Path -LiteralPath $dll)){
        $null=& $dotnet restore (Join-Path $root 'Milimap.PdfNative.csproj') --locked-mode
        if($LASTEXITCODE -ne 0){throw 'Locked native helper restore failed'}
        $null=& $dotnet build (Join-Path $root 'Milimap.PdfNative.csproj') -c Release --no-restore
        if($LASTEXITCODE -ne 0){throw 'Native helper build failed'}
    }
    [pscustomobject]@{FileName=$dotnet;Arguments=@($dll,'inspect','--input',$InputFile)}
}
function Invoke-BenefitPdfNativeProjection {
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes,
        [ValidateRange(1,120000)][int]$TimeoutMilliseconds=10000,
        [ValidateRange(1024,67108864)][int]$MaxOutputBytes=16777216)
    $scratch=Join-Path ([IO.Path]::GetTempPath()) ('milimap-pdf-native-'+[Guid]::NewGuid().ToString('N'))
    $process=$null;$started=$false;$projection=$null;$status='FAILED';$code='PDF_PROCESS_FAILED'
    $clock=[Diagnostics.Stopwatch]::StartNew();$peak=[long]0
    try {
        if($Bytes.Length -eq 0){throw 'Empty native PDF input'}
        if($Bytes.Length -gt 10485760){$code='PDF_SOURCE_LIMIT';throw 'Native PDF source exceeds byte quota'}
        $expectedHash=Get-BenefitEvidenceByteHash -Bytes $Bytes
        [void][IO.Directory]::CreateDirectory($scratch)
        $inputFile=Join-Path $scratch 'source.pdf';[IO.File]::WriteAllBytes($inputFile,$Bytes)
        $command=Get-InternalBenefitPdfNativeCommand -InputFile $inputFile
        $info=[Diagnostics.ProcessStartInfo]::new($command.FileName)
        $info.UseShellExecute=$false;$info.CreateNoWindow=$true
        $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
        $info.StandardOutputEncoding=[Text.UTF8Encoding]::new($false)
        $info.StandardErrorEncoding=[Text.UTF8Encoding]::new($false)
        foreach($argument in $command.Arguments){$info.ArgumentList.Add([string]$argument)}
        $process=[Diagnostics.Process]::new();$process.StartInfo=$info
        $started=$process.Start();if(-not $started){throw 'Native process did not start'}
        $clock.Restart()
        $stdout=[Text.StringBuilder]::new();$outputBytes=0;$errorBytes=0
        $outBuffer=[char[]]::new(4096);$errBuffer=[char[]]::new(4096)
        $outRead=$process.StandardOutput.ReadAsync($outBuffer,0,$outBuffer.Length)
        $errRead=$process.StandardError.ReadAsync($errBuffer,0,$errBuffer.Length)
        $outDone=$false;$errDone=$false
        while(-not ($process.HasExited -and $outDone -and $errDone)){
            if($clock.ElapsedMilliseconds -gt $TimeoutMilliseconds){$code='PDF_PROCESS_TIMEOUT';throw 'Native process wall deadline exceeded'}
            if(-not $outDone -and $outRead.IsCompleted){
                $count=$outRead.GetAwaiter().GetResult()
                if($count -eq 0){$outDone=$true}else{
                    $chunk=[string]::new($outBuffer,0,$count);$outputBytes += [Text.Encoding]::UTF8.GetByteCount($chunk)
                    if($outputBytes -gt $MaxOutputBytes){$code='PDF_OUTPUT_LIMIT';throw 'Native projection output exceeds quota'}
                    [void]$stdout.Append($chunk);$outRead=$process.StandardOutput.ReadAsync($outBuffer,0,$outBuffer.Length)
                }
            }
            if(-not $errDone -and $errRead.IsCompleted){
                $count=$errRead.GetAwaiter().GetResult()
                if($count -eq 0){$errDone=$true}else{
                    $errorBytes += [Text.Encoding]::UTF8.GetByteCount([string]::new($errBuffer,0,$count))
                    if($errorBytes -gt 65536){$code='PDF_OUTPUT_LIMIT';throw 'Native error output exceeds quota'}
                    $errRead=$process.StandardError.ReadAsync($errBuffer,0,$errBuffer.Length)
                }
            }
            if(-not $process.HasExited){$process.Refresh();$peak=[Math]::Max($peak,$process.WorkingSet64)}
            Start-Sleep -Milliseconds 5
        }
        if($process.ExitCode -notin @(0,1)){throw 'Native helper crashed'}
        $code='PDF_PROJECTION_INVALID'
        $parsed=ConvertFrom-Json -InputObject $stdout.ToString() -Depth 100 -NoEnumerate
        if($parsed -isnot [pscustomobject]){throw 'Projection must be an object'}
        foreach($name in @('SchemaVersion','ParserId','ParserVersion','FileSha256','OpenStatus','Encrypted','Pages','Diagnostics')){
            if($parsed.PSObject.Properties.Name -notcontains $name){throw 'Projection missing boundary metadata'}
        }
        if($parsed.SchemaVersion -ne 1 -or $parsed.ParserId -cne 'PDFPIG' -or $parsed.ParserVersion -cne '0.1.16' -or
            $parsed.FileSha256 -cne $expectedHash -or $parsed.Encrypted -isnot [bool] -or
            $parsed.Pages -isnot [array] -or $parsed.Diagnostics -isnot [array]){throw 'Invalid native projection identity/schema'}
        if($parsed.OpenStatus -ceq 'COMPLETE'){
            if($process.ExitCode -ne 0 -or $parsed.Encrypted -or $parsed.Pages.Count -lt 1){throw 'Inconsistent native success'}
            $projection=$parsed;$status='COMPLETE';$code=$null
        } elseif($parsed.OpenStatus -ceq 'UNSUPPORTED' -and $parsed.Encrypted -and $parsed.Pages.Count -eq 0 -and $process.ExitCode -eq 1){
            $status='UNSUPPORTED';$code='ENCRYPTED_PDF'
        } elseif($parsed.OpenStatus -ceq 'FAILED' -and $parsed.Pages.Count -eq 0 -and $process.ExitCode -eq 1){
            $code='PDF_PARSE_FAILED'
            foreach($diagnostic in $parsed.Diagnostics){
                if($diagnostic.Code -cin @('PDF_SOURCE_LIMIT','PDF_PAGE_LIMIT','PDF_LETTER_LIMIT','PDF_PATH_LIMIT','PDF_OUTPUT_LIMIT')){$code=$diagnostic.Code;break}
            }
        }
        else {throw 'Inconsistent native failure'}
    } catch { $projection=$null }
    finally {
        if($null -ne $process){
            try{if($started -and -not $process.HasExited){$process.Kill($true);[void]$process.WaitForExit(2000)}}finally{$process.Dispose()}
        }
        if([IO.Directory]::Exists($scratch)){[IO.Directory]::Delete($scratch,$true)}
        $clock.Stop()
    }
    $diagnostics=if($null -eq $code){@()}else{@([pscustomobject][ordered]@{Code=$code;Stage='PDF_NATIVE_RUNTIME';EvidenceReference='';Detail='Native processing did not yield a trusted projection'})}
    [pscustomobject][ordered]@{Status=$status;Projection=$projection;Diagnostics=$diagnostics;ElapsedMilliseconds=$clock.ElapsedMilliseconds;PeakWorkingSetBytes=$peak}
}

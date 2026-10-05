Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'invoke-tesseract-eval.ps1')

function Invoke-P43aGridProbe {
    param([Parameter(Mandatory)][string]$PdfPath)
    $scratch=Join-Path ([IO.Path]::GetTempPath()) ('milimap-p43a-grid-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($scratch)
    try{
        $dll=Join-Path $PSScriptRoot 'bin/Release/net8.0/Milimap.P4_3A.OcrEval.dll'
        $raw=& dotnet $dll inspect --input $PdfPath --artifact-dir $scratch
        $inspect=$raw | ConvertFrom-Json
        if($inspect.Status -ne 'ELIGIBLE'){return [pscustomobject]@{Status=$inspect.Status;Cells=@()}}
        $metadata=Join-Path $scratch 'inspect.json';[IO.File]::WriteAllText($metadata,$raw)
        & dotnet $dll grid --input $inspect.Images[0].ArtifactPath --metadata $metadata --page 1 --image 1 | ConvertFrom-Json
    }finally{[IO.Directory]::Delete($scratch,$true)}
}

function Resolve-EvaluationOcrCells {
    param([Parameter(Mandatory)][object[]]$Cells,[AllowEmptyCollection()][object[]]$Words,
        [Parameter(Mandatory)][ValidateRange(0,100)][double]$Threshold)
    $accepted=[Collections.Generic.List[object]]::new();$rejected=[Collections.Generic.List[object]]::new()
    foreach($word in $Words){
        $matches=@($Cells | Where-Object {$word.Left -ge $_.X0 -and $word.Top -ge $_.Y0 -and $word.Left+$word.Width -le $_.X1 -and $word.Top+$word.Height -le $_.Y1})
        if($word.Width -le 0 -or $word.Height -le 0 -or $word.Confidence -lt $Threshold -or $matches.Count -ne 1){$rejected.Add($word);continue}
        $accepted.Add([pscustomobject]@{CellId=$matches[0].Id;Left=$word.Left;Top=$word.Top;Width=$word.Width;Height=$word.Height;Text=$word.Text;Confidence=$word.Confidence})
    }
    for($i=0;$i -lt $accepted.Count;$i++){for($j=$i+1;$j -lt $accepted.Count;$j++){
        $a=$accepted[$i];$b=$accepted[$j]
        if($a.Left -lt $b.Left+$b.Width -and $b.Left -lt $a.Left+$a.Width -and $a.Top -lt $b.Top+$b.Height -and $b.Top -lt $a.Top+$a.Height){$rejected.Add($a);$rejected.Add($b)}
    }}
    if($rejected.Count -gt 0){return [pscustomobject]@{Status='PARTIAL';Accepted=@();Rejected=@($rejected.ToArray());CellText=@()}}
    $texts=@(foreach($cell in $Cells){
        $inside=@($accepted | Where-Object CellId -eq $cell.Id | Sort-Object Top,Left)
        $lines=[Collections.Generic.List[string]]::new();$lineWords=[Collections.Generic.List[string]]::new();$lineTop=-100000
        foreach($word in $inside){if($word.Top-$lineTop -gt 5){if($lineWords.Count){$lines.Add(($lineWords.ToArray() -join ' '));$lineWords.Clear()};$lineTop=$word.Top};$lineWords.Add($word.Text)}
        if($lineWords.Count){$lines.Add(($lineWords.ToArray() -join ' '))}
        [pscustomobject]@{CellId=$cell.Id;Text=($lines.ToArray() -join "`n")}
    })
    [pscustomobject]@{Status='COMPLETE';Accepted=@($accepted.ToArray());Rejected=@();CellText=$texts}
}

function Invoke-P43aOcrCalibration {
    param([Parameter(Mandatory)][string]$PdfPath,[Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string]$ModelPath,[ValidateSet(3,4,6,11)][int]$Psm)
    $scratch=Join-Path ([IO.Path]::GetTempPath()) ('milimap-p43a-calibration-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($scratch)
    try{
        $clock=[Diagnostics.Stopwatch]::StartNew()
        $dll=Join-Path $PSScriptRoot 'bin/Release/net8.0/Milimap.P4_3A.OcrEval.dll'
        $raw=& dotnet $dll inspect --input $PdfPath --artifact-dir $scratch
        $inspect=$raw | ConvertFrom-Json
        if($inspect.Status -ne 'ELIGIBLE' -or $inspect.Images.Count -ne 1){return [pscustomobject]@{Status=$inspect.Status;OpenCount=$inspect.OpenCount;OcrInvocationCount=0;GridBuildCount=0;Thresholds=@()}}
        $metadata=Join-Path $scratch 'inspect.json';[IO.File]::WriteAllText($metadata,$raw)
        $grid=& dotnet $dll grid --input $inspect.Images[0].ArtifactPath --metadata $metadata --page 1 --image 1 | ConvertFrom-Json
        if($grid.Status -ne 'COMPLETE'){return [pscustomobject]@{Status=$grid.Status;OpenCount=$inspect.OpenCount;OcrInvocationCount=0;GridBuildCount=1;Thresholds=@()}}
        $ocr=Invoke-TesseractEvaluation -Executable $Executable -ModelPath $ModelPath -ModelHash '6b85e11d9bbf07863b97b3523b1b112844c43e713df8b66418a081fd1060b3b2' -Inputs @($inspect.Images[0].ArtifactPath) -Psm $Psm
        if($ocr.Status -ne 'COMPLETE'){return [pscustomobject]@{Status='FAILED';Code=$ocr.Code;OpenCount=$inspect.OpenCount;OcrInvocationCount=$ocr.InvocationCount;GridBuildCount=1;Thresholds=@()}}
        $thresholds=@(foreach($threshold in @(0,50,80,90,95)){
            $resolved=Resolve-EvaluationOcrCells -Cells $grid.Cells -Words $ocr.Words -Threshold $threshold
            [pscustomobject]@{Threshold=$threshold;Status=$resolved.Status;AcceptedWordCount=$resolved.Accepted.Count;RejectedWordCount=$resolved.Rejected.Count;CellText=$resolved.CellText}
        })
        # Rejected words are audit diagnostics only. Never expose partial cell text as rows.
        $physicalFailures=@(foreach($word in $ocr.Words){
            $inside=@($grid.Cells | Where-Object {$word.Left -ge $_.X0 -and $word.Top -ge $_.Y0 -and $word.Left+$word.Width -le $_.X1 -and $word.Top+$word.Height -le $_.Y1})
            if($inside.Count -ne 1){[pscustomobject]@{Class='CONTAINMENT';Text=$word.Text;Confidence=$word.Confidence;Left=$word.Left;Top=$word.Top;Width=$word.Width;Height=$word.Height}}
        })
        [pscustomobject]@{Status='CALIBRATION_ONLY';Psm=$Psm;Oem=1;Dpi=300;OpenCount=$inspect.OpenCount;PageReadCount=$inspect.PageReadCount;
            ImageDecodeCount=$inspect.ImageDecodeCount;GridBuildCount=1;Cells=$grid.Cells.Count;OcrInvocationCount=$ocr.InvocationCount;
            WordCount=$ocr.Words.Count;ConfidenceMinimum=($ocr.Words | Measure-Object Confidence -Minimum).Minimum;
            ConfidenceMaximum=($ocr.Words | Measure-Object Confidence -Maximum).Maximum;OcrMilliseconds=$ocr.ElapsedMilliseconds;
            TotalMilliseconds=$clock.ElapsedMilliseconds;Thresholds=$thresholds;PhysicalFailures=$physicalFailures;Rows=@();ProductionAction='NONE'}
    }finally{[IO.Directory]::Delete($scratch,$true)}
}

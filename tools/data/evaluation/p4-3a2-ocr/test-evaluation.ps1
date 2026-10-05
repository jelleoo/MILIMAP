param([ValidateSet('Contract','OverlapPolicy','Acceptance','Safety','DeterminismContract','All')][string]$Group='Contract',
    [string]$TesseractExecutable,[string]$KoreanModelPath)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Require($Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Reject-Tsv([scriptblock]$Action){
    $rejected=$false
    try{& $Action | Out-Null}catch{if($_.Exception.Message -notlike 'P43A2_TSV_*'){throw};$rejected=$true}
    Require $rejected 'Unsafe TSV must fail closed'
}
if($Group -ne 'Contract'){throw 'A2_GROUP_NOT_IMPLEMENTED: only Task 1 Contract is available'}
$wrapper=Join-Path $PSScriptRoot 'invoke-tesseract-eval.ps1'
Require (Test-Path -LiteralPath $wrapper) 'Missing A2-only hierarchical TSV/runtime wrapper'
. $wrapper
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
$historical=Join-Path $PSScriptRoot '../p4-3a-ocr'
& dotnet restore (Join-Path $historical 'Milimap.P4_3A.OcrEval.csproj') --locked-mode | Out-Host
Require ($LASTEXITCODE -eq 0) 'Historical locked restore failed'
& dotnet build (Join-Path $historical 'Milimap.P4_3A.OcrEval.csproj') -c Release --no-restore | Out-Host
Require ($LASTEXITCODE -eq 0) 'Historical helper build failed'
$probe=& dotnet (Join-Path $historical 'bin/Release/net8.0/Milimap.P4_3A.OcrEval.dll') inspect --input (Join-Path $repo 'tools/data/testdata/benefit-evidence-pdf/two-business.pdf') --artifact-dir ([IO.Path]::GetTempPath()) | ConvertFrom-Json
Require ($probe.ProbeId -ceq 'MILIMAP_P4_3A_OCR_EVAL' -and $probe.OpenCount -eq 1 -and $probe.Status -ceq 'NATIVE_TEXT') 'Retained inspect identity/single-open changed'
Require (@(& git -C $repo diff origin/dev -- tools/data/evaluation/p4-3a-ocr).Count -eq 0) 'Historical P4-3A modified'
$header="level`tpage_num`tblock_num`tpar_num`tline_num`tword_num`tleft`ttop`twidth`theight`tconf`ttext"
$valid="$header`n5`t1`t4`t2`t3`t7`t10`t20`t30`t40`t92.5`t가상 식당"
$words=@(ConvertFrom-P43a2Tsv -Text $valid)
Require ($words.Count -eq 1) 'Valid TSV lost word'
$word=$words[0]
Require ($word.Page -eq 1 -and $word.Block -eq 4 -and $word.Paragraph -eq 2 -and $word.Line -eq 3 -and $word.Word -eq 7) 'TSV hierarchy renumbered/lost'
Require ($word.Left -eq 10 -and $word.Top -eq 20 -and $word.Width -eq 30 -and $word.Height -eq 40 -and $word.Confidence -eq 92.5 -and $word.Text -ceq '가상 식당') 'TSV physical/text values changed'
Require ((($word.PSObject.Properties.Name | Sort-Object) -join ',') -ceq 'Block,Confidence,Height,Left,Line,Page,Paragraph,Text,Top,Width,Word') 'Word contract fields differ'
foreach($bad in @(
    "$header`n5`t1`t0`t2`t3`t7`t10`t20`t30`t40`t92.5`tbad",
    "$header`n5`t1`t4`t0`t3`t7`t10`t20`t30`t40`t92.5`tbad",
    "$header`n5`t1`t4`t2`t0`t7`t10`t20`t30`t40`t92.5`tbad",
    "$header`n5`t1`t4`t2`t3`t0`t10`t20`t30`t40`t92.5`tbad",
    "$header`n5`t2`t4`t2`t3`t7`t10`t20`t30`t40`t92.5`tbad",
    "$header`n5`t1`t4`t2`t3`t7`t10`t20`t0`t40`t92.5`tbad",
    "$header`n5`t1`t4`t2`t3`t7`t10`t20`t30`t40`tNaN`tbad",
    "$header`n5`t1`t4`t2`t3`t7`t10`t20`t30`t40`t-1`tbad",
    "$header`n5`t1`t4`t2`t3`t7`t10`t20`t30`t40`t92.5`t   ",
    "$header`n1`t1`t0`t0`t0`t0`t0`t0`t1600`t900`t-1`t",$header,"$valid`nmalformed"
)){Reject-Tsv {ConvertFrom-P43a2Tsv -Text $bad}}
Require (Test-P43a2EngineVersion -Text "tesseract v5.5.3.20260724`n leptonica") 'Recorded Windows build rejected'
Require (Test-P43a2EngineVersion -Text "tesseract 5.5.3`n leptonica") 'Exact Ubuntu family rejected'
foreach($version in @('tesseract 5.5.2','tesseract 5.5.30','tesseract v5.5.3.unknown','PowerShell 7.5')){Require (-not (Test-P43a2EngineVersion -Text $version)) 'Wrong engine identity accepted'}
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('milimap-p43a2-contract-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($scratch)
try{
    $model=Join-Path $scratch 'kor.traineddata';[IO.File]::WriteAllBytes($model,[byte[]]@(1,2,3))
    $exe=(Get-Command pwsh).Source
    $missing=Invoke-P43a2TesseractEvaluation -Executable (Join-Path $scratch 'missing.exe') -ModelPath $model -Inputs @($model)
    Require ($missing.Status -eq 'FAILED' -and $missing.Code -eq 'EXECUTABLE_MISSING' -and $missing.InvocationCount -eq 0 -and $missing.Words.Count -eq 0) 'Missing engine must reject without OCR'
    Require ($missing.ProbeId -ceq 'MILIMAP_P4_3A2_OCR_EVAL' -and $missing.SchemaVersion -eq 1 -and ($missing.OverlapPolicyCandidates -join ',') -ceq '0.25,0.5,0.75') 'A2 identity/candidates changed'
    $absent=Invoke-P43a2TesseractEvaluation -Executable $exe -ModelPath (Join-Path $scratch 'missing-model') -Inputs @($model)
    Require ($absent.Code -eq 'MODEL_MISSING' -and $absent.InvocationCount -eq 0) 'Missing model accepted'
    $badModel=Invoke-P43a2TesseractEvaluation -Executable $exe -ModelPath $model -Inputs @($model)
    Require ($badModel.Code -eq 'MODEL_HASH_MISMATCH' -and $badModel.InvocationCount -eq 0 -and $badModel.Words.Count -eq 0) 'Wrong model accepted'
    $zero=Invoke-P43a2TesseractEvaluation -Executable $exe -ModelPath $model -Inputs @()
    $multi=Invoke-P43a2TesseractEvaluation -Executable $exe -ModelPath $model -Inputs @($model,$model)
    Require ($zero.Code -eq 'INPUT_UNSUPPORTED' -and $multi.Code -eq 'INPUT_UNSUPPORTED' -and $zero.InvocationCount -eq 0 -and $multi.InvocationCount -eq 0) 'Unsupported input count accepted'
    $wrongEngineText=& $exe --version
    Require (-not (Test-P43a2EngineVersion -Text ($wrongEngineText -join "`n"))) 'Real wrong engine identity accepted'
}finally{[IO.Directory]::Delete($scratch,$true)}
Write-Host 'A2 Contract PASS: hierarchy preserved; malformed/empty TSV and identity/input negatives rejected; historical diff 0'

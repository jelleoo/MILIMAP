param([ValidateSet('Contract','StructuralTrust','Isolation','Safety','DeterminismContract','All')][string]$Group='Contract',
    [string]$TesseractExecutable,[string]$KoreanModelPath)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Require($Condition,[string]$Message){if(-not $Condition){throw $Message}}
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
$base='7ae348b7d2e50c38ed79ab2639de7d6d6c5fd118'
function Assert-FrozenPaths {
    $diff=@(& git -C $repo diff $base -- tools/data/evaluation/p4-3a-ocr tools/data/evaluation/p4-3a2-ocr tools/data/pdf-native tools/data/lib data/canonical data/seed apps)
    Require ($LASTEXITCODE -eq 0 -and $diff.Count -eq 0) 'Historical/protected paths modified'
}
Assert-FrozenPaths
Require (Test-Path (Join-Path $PSScriptRoot 'invoke-tesseract-eval.ps1')) 'Missing Redesign 2 runtime boundary'
. (Join-Path $PSScriptRoot 'invoke-tesseract-eval.ps1')
if($Group -ne 'Contract'){throw 'REDESIGN2_GROUP_NOT_IMPLEMENTED'}
Require (-not (Get-Command Invoke-P43R2TesseractEvaluation).Parameters.ContainsKey('ConfidenceThreshold')) 'Threshold bypass exposed'
$header="level`tpage_num`tblock_num`tpar_num`tline_num`tword_num`tleft`ttop`twidth`theight`tconf`ttext"
$valid="$header`n5`t1`t4`t2`t3`t7`t10`t20`t30`t40`t1.25`t가상 식당"
Require (Test-P43a2EngineVersion 'tesseract v5.5.3.20260724') 'Exact engine rejected'
Require (-not (Test-P43a2EngineVersion 'tesseract 5.5.4')) 'Wrong engine accepted'
$parsed=@(ConvertFrom-P43a2Tsv $valid)
Require ($parsed[0].Confidence -eq 1.25 -and $parsed[0].Block -eq 4 -and $parsed[0].Word -eq 7) 'Raw confidence/hierarchy changed'
foreach($bad in @('',"$header`n1`t1`t0`t0`t0`t0`t0`t0`t10`t10`t-1`t", "$valid`nmalformed")){
    $thrown=$false;try { ConvertFrom-P43a2Tsv $bad | Out-Null } catch { $thrown=$true }
    Require $thrown 'Malformed/empty TSV accepted'
}
$missing=Invoke-P43R2TesseractEvaluation -Executable 'missing.exe' -ModelPath 'missing.model' -Inputs @('one')
Require ($missing.Status -eq 'FAILED' -and $missing.Code -eq 'EXECUTABLE_MISSING' -and $missing.Words.Count -eq 0) 'Missing executable not fail closed'
Require ((Invoke-P43R2TesseractEvaluation -Executable 'missing.exe' -ModelPath 'missing.model' -Inputs @('one','two')).Code -eq 'INPUT_UNSUPPORTED') 'Multiple input accepted'
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('milimap-p43r2-contract-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($scratch)
try {
    $exe=Join-Path $scratch 'not-executed.exe';[IO.File]::WriteAllText($exe,'test process seam')
    $image=Join-Path $scratch 'input.pgm';[IO.File]::WriteAllText($image,'test input')
    Require ((Invoke-P43R2TesseractEvaluation -Executable $exe -ModelPath 'missing.model' -Inputs @($image)).Code -eq 'MODEL_MISSING') 'Missing model accepted'
    $badModel=Join-Path $scratch 'kor.traineddata';[IO.File]::WriteAllText($badModel,'wrong bytes')
    Require ((Invoke-P43R2TesseractEvaluation -Executable $exe -ModelPath $badModel -Inputs @($image)).Code -eq 'MODEL_HASH_MISMATCH') 'Wrong model accepted'
    Require (Test-Path -LiteralPath $KoreanModelPath) 'Supply exact official model for runtime contract tests'
    # Only external process is doubled: actual model hash/identity/parser/mapping run.
    $originalProcess=(Get-Command Invoke-InternalP43a2Process).ScriptBlock
    $script:processIdentity="tesseract v5.5.3.20260724`n";$script:processTsv=$valid
    function Invoke-InternalP43a2Process {
        param($Executable,$Arguments,$DeadlineMilliseconds)
        if($Arguments[0] -eq '--version'){return [pscustomobject]@{ExitCode=0;Text=$script:processIdentity;ElapsedMilliseconds=0}}
        Require (($Arguments -join '|') -match '\|-l\|kor\|--oem\|1\|--psm\|11\|--dpi\|300\|') 'Material arguments changed'
        return [pscustomobject]@{ExitCode=0;Text=$script:processTsv;ElapsedMilliseconds=2}
    }
    $mapped=Invoke-P43R2TesseractEvaluation -Executable $exe -ModelPath $KoreanModelPath -Inputs @($image)
    Require ($mapped.Status -eq 'COMPLETE' -and $mapped.ProbeId -ceq 'MILIMAP_P4_3_REDESIGN2_OCR_EVAL' -and $mapped.SchemaVersion -eq 1 -and $mapped.TrustModelVersion -ceq 'STRUCTURAL_TRUST_V1' -and $mapped.ConfidencePolicy -ceq 'DIAGNOSTIC_ONLY_V1') 'Redesign2 identity/policy missing'
    Require (-not $mapped.PSObject.Properties['ConfidenceThreshold'] -and -not $mapped.PSObject.Properties['ConfidenceCandidates'] -and -not $mapped.PSObject.Properties['OverlapPolicyCandidates']) 'Candidate search leaked into contract'
    Require ($mapped.InvocationCount -eq 1 -and $mapped.ProductionAction -eq 'NONE') 'Work/safety identity lost'
    Require (($mapped.Words | ConvertTo-Json -Compress) -ceq ($parsed | ConvertTo-Json -Compress)) 'Raw word values changed'
    foreach($bad in @("$valid`nmalformed","$header`n1`t1`t0`t0`t0`t0`t0`t0`t10`t10`t-1`t")){
        $script:processTsv=$bad
        $result=Invoke-P43R2TesseractEvaluation -Executable $exe -ModelPath $KoreanModelPath -Inputs @($image)
        Require ($result.Status -eq 'FAILED' -and $result.Words.Count -eq 0) 'Malformed/empty output leaks words'
    }
    $script:processIdentity='tesseract 5.5.4'
    Require ((Invoke-P43R2TesseractEvaluation -Executable $exe -ModelPath $KoreanModelPath -Inputs @($image)).Code -eq 'ENGINE_VERSION_MISMATCH') 'Wrong runtime accepted'
} finally {
    if(Get-Variable originalProcess -ErrorAction SilentlyContinue){Set-Item Function:Invoke-InternalP43a2Process $originalProcess}
    [IO.Directory]::Delete($scratch,$true)
}
Assert-FrozenPaths
Write-Host 'Redesign2 Contract PASS: exact identity, raw confidence, fail-closed negatives; historical/protected diff 0'

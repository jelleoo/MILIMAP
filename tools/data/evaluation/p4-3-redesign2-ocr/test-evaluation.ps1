param([ValidateSet('Contract','StructuralTrust','TextFidelity','Isolation','Safety','DeterminismContract','All')][string]$Group='Contract',
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
if($Group -eq 'TextFidelity'){
    . (Join-Path $PSScriptRoot 'run-evaluation.ps1')
    $truth=Get-P43R2ClearFixtureGroundTruth
    Require ($truth.Policy -ceq 'TEXT_FIDELITY_GROUND_TRUTH_V1' -and $truth.Cells.Count -eq 12) 'Ground truth contract missing'
    Require ($truth.GeneratorBlob -ceq '6231ed473349063ce3b0d12fc7b2cff0bef1d114' -and $truth.ManifestBlob -ceq 'cde2a581ec2c4a1fb26481992908b5dcab2740ac') 'Historical authority changed'
    $literal=@('업체명','주소','전화번호','혜택','가상 가람 식당','가상시 가람로 12','031-123-4567','시험 할인 10%','가상 누리 식당','가상시 누리로 23','031-234-5678',"시험 할인 20%`n방문 시 적용")
    for($i=0;$i -lt 12;$i++){
        Require ($truth.Cells[$i].CellId -ceq "cell$($i+1)" -and $truth.Cells[$i].ExpectedText -ceq $literal[$i] -and $truth.Cells[$i].Row -eq ([Math]::Floor($i/4)+1) -and $truth.Cells[$i].Column -eq ($i%4+1)) 'Authored table changed'
    }
    foreach($role in @(@{Name='HEADER';Count=4},@{Name='BUSINESS_NAME';Count=2},@{Name='BENEFIT';Count=2},@{Name='AUXILIARY';Count=4})){
        Require (@($truth.Cells | Where-Object FieldRole -CEQ $role.Name).Count -eq $role.Count) 'Mandatory role coverage changed'
    }
    Require ((Normalize-P43R2FidelityText "  시험`t  할인 20%`r`n방문  시 적용  ") -ceq "시험 할인 20%`n방문 시 적용") 'Whitespace normalization incorrect'
    foreach($pair in @(@('업체명','업쳬명'),@('10%','10'),@('031-123-4567','031-123-4568'),@('가상','가샹'))){
        Require ((Normalize-P43R2FidelityText $pair[0]) -cne (Normalize-P43R2FidelityText $pair[1])) 'Material character silently repaired'
    }
    Require ((Get-Command Normalize-P43R2FidelityText).Parameters.Count -eq 1) 'Fuzzy normalization exposed'
    Require (-not (Get-Command Resolve-P43R2OcrCells).Parameters.ContainsKey('ExpectedText')) 'Ground truth leaked into resolver'
    Assert-FrozenPaths
    Write-Host 'Redesign2 TextFidelity contract PASS'
    return
}
if($Group -eq 'StructuralTrust'){
    Require (Test-Path (Join-Path $PSScriptRoot 'run-evaluation.ps1')) 'Missing Redesign 2 structural trust functions'
    . (Join-Path $PSScriptRoot 'run-evaluation.ps1')
    function W($Left,$Top,$Width,$Height,$Text,$Ordinal=1,$Confidence=99){
        [pscustomobject]@{Page=1;Block=1;Paragraph=1;Line=1;Word=$Ordinal;Left=$Left;Top=$Top;Width=$Width;Height=$Height;Confidence=$Confidence;Text=$Text}
    }
    $cell=[pscustomobject]@{Page=1;CellId='one';Left=0;Top=0;Width=100;Height=100}
    $other=[pscustomobject]@{Page=1;CellId='two';Left=100;Top=0;Width=100;Height=100}
    Require (-not (Get-Command Resolve-P43R2OcrCells).Parameters.ContainsKey('ConfidenceThreshold')) 'Resolver exposes threshold'
    $low=W 10 10 20 10 'low' 1 1
    $safe=Resolve-P43R2OcrCells -Cells @($cell) -Words @($low,(W 29 10 20 10 'b' 2)) -RequiredCellIds @('one')
    Require ($safe.Status -eq 'COMPLETE' -and $safe.CellText[0].Text -ceq 'low b' -and $safe.AcceptedWords[0].Record.Confidence -eq 1) 'Structurally valid low confidence rejected'
    Require (@($safe.Diagnostics | Where-Object Code -ne 'SAFE_ADJACENT').Count -eq 0) 'Low confidence creates blocking diagnostic'
    Require ((Get-P43R2OverlapClass -A $low -B $low) -eq 'ORDERING_UNSAFE') 'Unbound word trusted'
    foreach($case in @(
        @{Words=@((W 10 10 20 10 'same'),(W 11 10 20 10 'same' 2));Code='DUPLICATE'},
        @{Words=@((W 10 10 20 10 'a'),(W 11 10 20 10 'b' 2));Code='CONFLICTING'},
        @{Words=@((W 10 10 20 10 'a'),(W 10 10 10 10 'b' 2));Code='ORDERING_UNSAFE'},
        @{Words=@((W 10 10 20 10 'a' 2),(W 29 10 20 10 'b' 1));Code='ORDERING_UNSAFE'},
        @{Words=@((W 10 10 10 10 'a'),(W 25 18 10 14 'bridge' 2),(W 40 30 10 10 'b' 3));Code='ORDERING_UNSAFE'},
        @{Words=@((W 90 10 20 10 'cross'));Code='CELL_AMBIGUOUS'},
        @{Words=@((W 200 10 20 10 'outside'));Code='CELL_NONE'}
    )){
        $bad=Resolve-P43R2OcrCells -Cells @($cell,$other) -Words $case.Words -RequiredCellIds @('one')
        Require ($bad.Status -eq 'PARTIAL' -and $bad.AcceptedWords.Count -eq 0 -and $bad.CellText.Count -eq 0 -and @($bad.Diagnostics | Where-Object Code -eq $case.Code).Count -gt 0) "Unsafe $($case.Code) rescued"
    }
    Require ((Get-P43R2CellMembership -Cells @($cell,$cell) -Word $low).Status -eq 'AMBIGUOUS') 'Duplicate cell accepted'
    $missing=Resolve-P43R2OcrCells -Cells @($cell,$other) -Words @($low) -RequiredCellIds @('one','two')
    Require ($missing.Status -eq 'PARTIAL' -and @($missing.Diagnostics | Where-Object Code -eq 'REQUIRED_COVERAGE_MISSING').Count -eq 1) 'Missing required coverage accepted'
    $reverse=Resolve-P43R2OcrCells -Cells @($cell) -Words @((W 29 10 20 10 'b' 2),$low) -RequiredCellIds @('one')
    Require ($reverse.CellText[0].Text -ceq 'low b') 'Enumeration changes reconstruction'
    $failed=New-P43R2StructuralEvidence -Cells @($cell) -Ocr ([pscustomobject]@{Status='FAILED';Code='P43A2_TSV_EMPTY_WORD_OUTPUT';Words=@();Diagnostics=@([pscustomobject]@{Code='P43A2_TSV_EMPTY_WORD_OUTPUT'})}) -RequiredCellIds @('one')
    Require ($failed.OperationalStatus -eq 'FAILED' -and $failed.OperationalCode -eq 'EMPTY_WORD_OUTPUT' -and $failed.AcceptanceStatus -eq 'NOT_EVALUATED' -and $failed.AcceptedWords.Count -eq 0) 'Empty output becomes structural absence'
    $matrix=Invoke-P43R2GateAMatrix -Executable $TesseractExecutable -ModelPath $KoreanModelPath
    $matrix | ConvertTo-Json -Depth 16 | Write-Host
    Require ($matrix.Verdict -eq 'GATE_A_PASS' -and $matrix.RepetitionsIdentical -and $matrix.Runs.Count -eq 13) 'Gate A structural matrix failed'
    $clear=@($matrix.Runs | Where-Object {$_.Psm -eq 11 -and $_.Fixture -in @('gray.pdf','rgb.pdf')})
    foreach($run in $clear){Require ($run.WordCount -eq 40 -and $run.Status -eq 'COMPLETE' -and $run.UsableRows -eq 2 -and $run.AcceptedBelow50.Count -gt 0 -and $run.ExactMembership -and $run.RequiredCoverage) 'Clear physical/low-confidence positive failed'}
    $mild=@($matrix.Runs | Where-Object Fixture -eq 'mild-degraded-gray.pdf')[0]
    Require ($mild.WordCount -eq 39 -and $mild.Status -eq 'PARTIAL' -and @($mild.Diagnostics | Where-Object Code -eq 'CONFLICTING').Count -eq 2) 'Mild structural conflict lost'
    foreach($run in @($matrix.Runs | Where-Object Psm -ne 11)){
        $want=if($run.Psm -eq 3){5}else{2}
        Require ($run.Status -eq 'PARTIAL' -and @($run.Diagnostics | Where-Object {$_.Code -in @('CELL_NONE','CELL_AMBIGUOUS')}).Count -eq $want) 'PSM containment regression changed'
    }
    foreach($run in @($matrix.Runs | Where-Object {$_.Fixture -in @('degraded-gray.pdf','degraded-rgb.pdf')})){
        Require ($run.WordCount -eq 0 -and $run.OperationalStatus -eq 'FAILED' -and $run.OperationalCode -eq 'EMPTY_WORD_OUTPUT' -and $run.Status -eq 'NOT_EVALUATED' -and $run.UsableRows -eq 0) 'Old degraded failure rescued'
    }
    Assert-FrozenPaths
    Write-Host 'Redesign2 StructuralTrust PASS; GATE_A_PASS; HUMAN REVIEW STOP before Task3'
    return
}
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

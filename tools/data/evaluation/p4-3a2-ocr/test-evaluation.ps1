param([ValidateSet('Contract','OverlapPolicy','Acceptance','Safety','DeterminismContract','All')][string]$Group='Contract',
    [string]$TesseractExecutable,[string]$KoreanModelPath,[string]$FixturePythonExecutable)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Require($Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Reject-Tsv([scriptblock]$Action){
    $rejected=$false
    try{& $Action | Out-Null}catch{if($_.Exception.Message -notlike 'P43A2_TSV_*'){throw};$rejected=$true}
    Require $rejected 'Unsafe TSV must fail closed'
}
if($Group -eq 'OverlapPolicy'){
    $evaluation=Join-Path $PSScriptRoot 'run-evaluation.ps1'
    Require (Test-Path -LiteralPath $evaluation) 'Missing A2 unique-membership/overlap classifier'
    . $evaluation
    function New-Word($Left,$Top,$Width,$Height,$Text,$Ordinal=1){
        return [pscustomobject]@{Page=1;Block=1;Paragraph=1;Line=1;Word=$Ordinal;Left=$Left;Top=$Top;Width=$Width;Height=$Height;Confidence=99;Text=$Text}
    }
    $cell=[pscustomobject]@{Page=1;CellId='one';Left=0;Top=0;Width=100;Height=100}
    $other=[pscustomobject]@{Page=1;CellId='two';Left=100;Top=0;Width=100;Height=100}
    Require ((Get-P43a2CellMembership -Cells @($cell,$other) -Word (New-Word 10 10 20 10 'a')).Status -eq 'UNIQUE') 'Exact cell containment lost'
    Require ((Get-P43a2CellMembership -Cells @($cell,$other) -Word (New-Word 90 10 20 10 'cross')).Status -eq 'AMBIGUOUS') 'Cross-cell bbox accepted'
    Require ((Get-P43a2CellMembership -Cells @($cell) -Word (New-Word 200 10 20 10 'outside')).Status -eq 'NONE') 'Outside bbox accepted'
    Require ((Get-P43a2CellMembership -Cells @($cell,$cell) -Word (New-Word 10 10 20 10 'a')).Status -eq 'AMBIGUOUS') 'Ambiguous cell containment accepted'
    $passed=[Collections.Generic.List[double]]::new()
    foreach($ratio in @(0.25,0.50,0.75)){
        $a=New-Word 10 10 20 10 'a' 1;$b=New-Word 29 10 20 10 'b' 2
        $safe=Resolve-P43a2OcrCells -Cells @($cell) -Words @($a,$b) -ConfidenceThreshold 0 -SameRegionRatio $ratio
        Require ($safe.Status -eq 'COMPLETE' -and $safe.CellText[0].Text -ceq 'a b' -and @($safe.Diagnostics | Where-Object Code -eq 'SAFE_ADJACENT').Count -eq 1) 'One-pixel uniquely contained adjacency not safely classified'
        Require ((Get-P43a2OverlapClass -A $a -B $b -SameRegionRatio $ratio) -ne 'SAFE_ADJACENT') 'Unproven membership passed classifier'
        foreach($case in @(
            @{Words=@((New-Word 10 10 20 10 'same' 1),(New-Word 11 10 20 10 'same' 2));Code='DUPLICATE'},
            @{Words=@((New-Word 10 10 20 10 'a' 1),(New-Word 11 10 20 10 'b' 2));Code='CONFLICTING'},
            @{Words=@((New-Word 10 10 20 10 'a' 1),(New-Word 10 10 10 10 'b' 2));Code='ORDERING_UNSAFE'},
            @{Words=@((New-Word 10 10 20 10 'a' 2),(New-Word 29 10 20 10 'b' 1));Code='ORDERING_UNSAFE'},
            @{Words=@((New-Word 10 10 10 10 'a' 1),(New-Word 25 18 10 14 'bridge' 2),(New-Word 40 30 10 10 'b' 3));Code='ORDERING_UNSAFE'},
            @{Words=@((New-Word 90 10 20 10 'cross' 1));Code='CELL_AMBIGUOUS'},
            @{Words=@((New-Word 200 10 20 10 'outside' 1));Code='CELL_NONE'}
        )){
            foreach($threshold in @(0,95)){
                $bad=Resolve-P43a2OcrCells -Cells @($cell,$other) -Words $case.Words -ConfidenceThreshold $threshold -SameRegionRatio $ratio
                Require ($bad.Status -eq 'PARTIAL' -and $bad.AcceptedWords.Count -eq 0 -and $bad.CellText.Count -eq 0 -and @($bad.Diagnostics | Where-Object Code -eq $case.Code).Count -gt 0) "Unsafe $($case.Code) rescued at ratio $ratio / confidence $threshold"
            }
        }
        $reverse=Resolve-P43a2OcrCells -Cells @($cell) -Words @($b,$a) -ConfidenceThreshold 0 -SameRegionRatio $ratio
        Require ($reverse.CellText[0].Text -ceq $safe.CellText[0].Text) 'Input enumeration changes physical text order'
        $passed.Add($ratio)
        Write-Host "Overlap candidate $ratio PASS: adjacency + duplicate/conflict/order/bridge/cross-cell negatives"
    }
    Require ($passed.Count -eq 3 -and $passed[0] -eq 0.25) 'GATE_A_CLASSIFIER_REJECTED'
    Write-Host 'Selected SAME_CELL_OVERLAP_V1 ratio=0.25 (lowest passing fixed candidate); real Gate A NOT_RUN'
    return
}
if($Group -eq 'Acceptance'){
    . (Join-Path $PSScriptRoot 'run-evaluation.ps1')
    Require ([bool](Get-Command Invoke-P43a2AcceptanceMatrix -ErrorAction SilentlyContinue)) 'Missing A2 real acceptance matrix'
    Assert-P43a2FixtureSet -Directory (Join-Path $PSScriptRoot 'fixtures')
    Require (-not [string]::IsNullOrWhiteSpace($FixturePythonExecutable)) 'Supply existing fixture-authoring Python for byte-derived grid integrity check'
    & $FixturePythonExecutable (Join-Path $PSScriptRoot 'fixtures/generate-fixtures.py') --check | Out-Host
    Require ($LASTEXITCODE -eq 0) 'Actual PDF bytes/grid/one-mild fixture contract failed'
    $matrix=Invoke-P43a2AcceptanceMatrix -Executable $TesseractExecutable -ModelPath $KoreanModelPath -SameRegionRatio 0.25
    Require ($matrix.Runs.Count -eq 13) 'Bounded matrix must contain only 4 clear / 6 regression / 2 old degraded / 1 mild runs'
    $old=@($matrix.Runs | Where-Object Fixture -eq 'degraded-gray.pdf')[0]
    Require ($old.GridStatus -eq 'COMPLETE' -and $old.OperationalStatus -eq 'FAILED' -and $old.OperationalCode -eq 'EMPTY_WORD_OUTPUT' -and $old.AcceptanceStatus -eq 'NOT_EVALUATED' -and $old.ConfidenceEvidence -eq 'NOT_OBSERVED' -and $old.Thresholds.Count -eq 0) 'Old empty OCR misclassified as confidence evidence'
    $mild=@($matrix.Runs | Where-Object Fixture -eq 'mild-degraded-gray.pdf')[0]
    Require ($mild.GridStatus -eq 'COMPLETE' -and $mild.GridPixelsMatchClear) 'Mild grid must be exact clear-grid pixels'
    foreach($clear in @($matrix.Runs | Where-Object Psm -eq 11 | Where-Object {$_.Fixture -in @('gray.pdf','rgb.pdf')})){
        Require ($clear.WordCount -eq 40 -and $clear.Thresholds[0].Status -eq 'COMPLETE' -and $clear.Thresholds[0].UsableRows -eq 2) 'Clear threshold0 physical positive changed'
        Require (@($clear.Thresholds | Where-Object Threshold -gt 0 | Where-Object Status -ne 'PARTIAL').Count -eq 0) 'Clear fixed nonzero threshold result changed'
    }
    Require ($matrix.RepetitionsIdentical -and $matrix.RegressionSafe -and $matrix.RegressionUsableRows -eq 0) 'Clear repeat / PSM3/4/6 containment regression failed'
    if($mild.OperationalStatus -eq 'COMPLETE'){
        Require ($mild.WordCount -gt 0 -and ($mild.Thresholds.Threshold -join ',') -eq '0,50,80,90,95' -and $mild.ConfidenceEvidence -eq 'OBSERVED') 'Words require exact fixed confidence matrix'
    }else{
        Require ($mild.OperationalCode -eq 'EMPTY_WORD_OUTPUT' -and $mild.Thresholds.Count -eq 0 -and $matrix.Code -eq 'GATE_A_CONFIDENCE_NOT_OBSERVED') 'Mild empty output cannot be confidence rejection'
    }
    if($matrix.Status -eq 'COMPLETE'){
        Require ($matrix.SelectedConfidenceThreshold -in @(0,50,80,90,95) -and $matrix.Verdict -eq 'GATES_A_B_PASS') 'Unapproved selected threshold'
    }else{
        Require ($matrix.Status -eq 'REJECTED' -and $matrix.Verdict -eq 'P4_3A2_REJECTED' -and $null -eq $matrix.SelectedConfidenceThreshold -and $matrix.Code -in @('GATE_A_CONFIDENCE_NOT_OBSERVED','GATE_A_CONFIDENCE_REJECTED')) 'No qualifying threshold requires explicit bounded rejection'
    }
    $matrix | ConvertTo-Json -Depth 12 | Write-Host
    Write-Host "Acceptance assertions PASS; actual verdict=$($matrix.Verdict); Task4/5 STOP for human review"
    return
}
if($Group -ne 'Contract'){throw 'A2_GROUP_NOT_IMPLEMENTED: this group is not implemented'}
$wrapper=Join-Path $PSScriptRoot 'invoke-tesseract-eval.ps1'
Require (Test-Path -LiteralPath $wrapper) 'Missing A2-only hierarchical TSV/runtime wrapper'
. $wrapper
. (Join-Path $PSScriptRoot 'run-evaluation.ps1')
Require ([bool](Get-Command New-P43a2OcrAcceptanceEvidence -ErrorAction SilentlyContinue)) 'Missing distinct operational/acceptance evidence boundary'
$emptyOcr=[pscustomobject]@{Status='FAILED';Code='P43A2_TSV_EMPTY_WORD_OUTPUT';Words=@()}
$emptyEvidence=New-P43a2OcrAcceptanceEvidence -Cells @() -Ocr $emptyOcr -SameRegionRatio 0.25
Require ($emptyEvidence.OperationalStatus -eq 'FAILED' -and $emptyEvidence.OperationalCode -eq 'EMPTY_WORD_OUTPUT' -and $emptyEvidence.AcceptanceStatus -eq 'NOT_EVALUATED' -and $emptyEvidence.ConfidenceEvidence -eq 'NOT_OBSERVED' -and $emptyEvidence.Thresholds.Count -eq 0) 'EMPTY_WORD_OUTPUT must remain operational failure only'
$emptyGate=Get-P43a2ConfidenceDecision -Clear @() -Mild $emptyEvidence
Require ($emptyGate.Code -eq 'GATE_A_CONFIDENCE_NOT_OBSERVED' -and $emptyGate.Code -ne 'GATE_A_CONFIDENCE_REJECTED' -and $null -eq $emptyGate.SelectedConfidenceThreshold) 'Operational failure cannot masquerade as confidence rejection'
$calibrationCells=@(foreach($row in 1..3){foreach($col in 1..4){[pscustomobject]@{Page=1;CellId="$row-$col";Left=100*$col;Top=100*$row;Width=90;Height=90;Row=$row;Column=$col}}})
$calibrationWords=@($calibrationCells | ForEach-Object {[pscustomobject]@{Page=1;Block=1;Paragraph=1;Line=1;Word=1;Left=$_.Left+10;Top=$_.Top+10;Width=10;Height=10;Confidence=60;Text='synthetic'}})
$wordOcr=[pscustomobject]@{Status='COMPLETE';Code=$null;Words=$calibrationWords}
$wordEvidence=New-P43a2OcrAcceptanceEvidence -Cells $calibrationCells -Ocr $wordOcr -SameRegionRatio 0.25
Require ($wordEvidence.OperationalStatus -eq 'COMPLETE' -and $wordEvidence.ConfidenceEvidence -eq 'OBSERVED' -and ($wordEvidence.Thresholds.Threshold -join ',') -eq '0,50,80,90,95') 'Words must evaluate fixed confidence candidates'
$noSeparation=Get-P43a2ConfidenceDecision -Clear @($wordEvidence) -Mild $wordEvidence
Require ($noSeparation.Code -eq 'GATE_A_CONFIDENCE_REJECTED' -and $null -eq $noSeparation.SelectedConfidenceThreshold) 'No safe qualifying threshold must explicitly reject'
foreach($word in $calibrationWords){$word.Confidence=95}
$clearEvidence=New-P43a2OcrAcceptanceEvidence -Cells $calibrationCells -Ocr $wordOcr -SameRegionRatio 0.25
foreach($word in $calibrationWords){$word.Confidence=45}
$mildEvidence=New-P43a2OcrAcceptanceEvidence -Cells $calibrationCells -Ocr $wordOcr -SameRegionRatio 0.25
$separation=Get-P43a2ConfidenceDecision -Clear @($clearEvidence) -Mild $mildEvidence
Require ($null -eq $separation.Code -and $separation.SelectedConfidenceThreshold -eq 50) 'Select lowest approved threshold only when separation is confidence-only'
foreach($word in $calibrationWords){$word.Confidence=95}
# A data-row phone cell is not the required header/name/benefit separation control.
$calibrationWords[6].Confidence=45
$irrelevantLow=New-P43a2OcrAcceptanceEvidence -Cells $calibrationCells -Ocr $wordOcr -SameRegionRatio 0.25
$irrelevantDecision=Get-P43a2ConfidenceDecision -Clear @($clearEvidence) -Mild $irrelevantLow
Require ($irrelevantDecision.Code -eq 'GATE_A_CONFIDENCE_REJECTED' -and $null -eq $irrelevantDecision.SelectedConfidenceThreshold) 'Unrequired phone-word confidence must not prove required-text separation'
Assert-P43a2FixtureSet -Directory (Join-Path $PSScriptRoot 'fixtures')
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
$gridWhitespace="$valid`n5`t1`t5`t1`t1`t1`t48`t69`t1504`t3`t95.0`t "
Require (@(ConvertFrom-P43a2Tsv -Text $gridWhitespace).Count -eq 1) 'Tesseract whitespace-only grid decoration must not become a text word'
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
    $bounded=Join-Path $scratch 'bounded-fixtures';[void][IO.Directory]::CreateDirectory($bounded)
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'fixtures/manifest.json') -Destination $bounded
    foreach($name in @('degraded-gray','degraded-rgb','mild-degraded-gray')){Copy-Item -LiteralPath (Join-Path $PSScriptRoot "fixtures/$name.pdf") -Destination $bounded}
    Assert-P43a2FixtureSet -Directory $bounded
    Copy-Item -LiteralPath (Join-Path $bounded 'mild-degraded-gray.pdf') -Destination (Join-Path $bounded 'second-mild.pdf')
    $expandedRejected=$false
    try{Assert-P43a2FixtureSet -Directory $bounded}catch{if($_.Exception.Message -ne 'A2_FIXTURE_EXPANSION_FORBIDDEN'){throw};$expandedRejected=$true}
    Require $expandedRejected 'A second mild fixture must be rejected'
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

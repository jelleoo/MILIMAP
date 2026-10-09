param([ValidateSet('CropProvenance','BatchMapping','ClearFidelity','AllReached','ReachedReporting')][string]$Group='CropProvenance',
    [Alias('TesseractExecutable')][string]$Executable,[Alias('KoreanModelPath')][string]$ModelPath,[switch]$RunRealGateB,[switch]$RunRealGateC)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Require($Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Reject([scriptblock]$Action,[string]$Code){
    try{& $Action | Out-Null}catch{Require ($_.Exception.Message -ceq $Code) "Expected $Code, got $($_.Exception.Message)";return}
    throw "Expected rejection: $Code"
}
$runner=Join-Path $PSScriptRoot 'run-evaluation.ps1'
Require (Test-Path -LiteralPath $runner) 'FAIL: Redesign 3A crop functions do not exist'
. $runner
function Assert-P43R3aReachedVerification {
    param([object]$Reached)
    $gateB=if($null -eq $Reached.GateB){$Reached.GateD}else{$Reached.GateB.Status}
    $gateC=if($null -eq $Reached.GateC){$Reached.GateD}else{$Reached.GateC.Status}
    $code=if($null -eq $Reached.GateB){$null}else{$Reached.GateB.Code}
    Write-Host "Reached GateA=$($Reached.GateA); GateB=$gateB; Code=$code; GateC=$gateC"
    Require ($Reached.Verdict -cin @('P4_3_REDESIGN3A_EARLY_GATES_PASS','P4_3_REDESIGN3A_REJECTED','P4_3_REDESIGN3A_NOT_EVALUATED')) 'Final reached verdict must use the exact approved first-cycle vocabulary'
    Require ($Reached.SafetyInvocationCount -eq 0 -and $Reached.ProductionAction -ceq 'NONE') 'Reached verification cannot invoke safety or product actions'
    if($Reached.GateA -cne 'GATE_A_CROP_PROVENANCE_PASS'){
        Require ($null -eq $Reached.GateB -and $null -eq $Reached.GateC -and $Reached.GateD -ceq 'NOT_RUN_GATE_A_FAILED' -and $Reached.Verdict -ceq 'P4_3_REDESIGN3A_REJECTED') 'Failed A must leave B/C unrun and reject'
        Require ($Reached.MappingInvocationCount -eq 0 -and $Reached.QualityInvocationCount -eq 0 -and $Reached.TotalOcrInvocationCount -eq 0) 'Failed A must invoke no OCR'
    }else{
        Require ($null -ne $Reached.GateB) 'Passed A requires reached B evidence'
        foreach($batch in $Reached.GateB.Batches){Write-Host "Mapping PSM$($batch.Psm): status=$($batch.Status) calls=$($batch.InvocationCount) pages=$($batch.Pages.Count) words=$($batch.Words.Count) elapsedMs=$($batch.ElapsedMilliseconds) page/ordinal/CellId=$(@($batch.Pages | ForEach-Object {"$($_.Page)/$($_.CropOrdinal)/$($_.CellId)"}) -join ',')"}
        if($Reached.GateB.Status -cne 'GATE_B_BATCH_MAPPING_PASS'){
            Require ($Reached.GateB.Status -cin @('GATE_B_BATCH_MAPPING_FAILED','GATE_B_BATCH_MAPPING_NOT_EVALUATED') -and $null -eq $Reached.GateC -and $Reached.GateD -ceq 'NOT_RUN_GATE_B_FAILED') 'Blocked B must leave C/D unrun'
            $verdict=if($Reached.GateB.Status -ceq 'GATE_B_BATCH_MAPPING_NOT_EVALUATED'){'P4_3_REDESIGN3A_NOT_EVALUATED'}else{'P4_3_REDESIGN3A_REJECTED'}
            Require ($Reached.Verdict -ceq $verdict -and $Reached.QualityInvocationCount -eq 0 -and $Reached.TotalOcrInvocationCount -eq $Reached.MappingInvocationCount) 'Blocked B must preserve factual verdict and no clear OCR'
        }else{
            Require ($null -ne $Reached.GateC) 'Passed B requires reached C evidence'
            foreach($run in $Reached.GateC.Runs){
                Write-Host "Clear $($run.Fixture) PSM$($run.Psm) repeat$($run.Repetition): status=$($run.Batch.Status) mandatory=$($run.Fidelity.MandatoryMatchCount)/8 all=$($run.Fidelity.AllCellMatchCount)/12 words=$($run.Batch.Words.Count) elapsedMs=$($run.Batch.ElapsedMilliseconds)"
                foreach($cell in @($run.Fidelity.Cells | Where-Object Status -CNE 'FIDELITY_MATCH')){Write-Host ('Nonmatch: '+($cell | ConvertTo-Json -Depth 8 -Compress))}
            }
            Write-Host ('Preparation: '+($Reached.GateC.PreparationCounts | ConvertTo-Json -Compress))
            Write-Host ('Determinism: '+($Reached.GateC.Determinism | ConvertTo-Json -Compress))
            if($Reached.GateC.Status -ceq 'GATE_C_CLEAR_FIDELITY_FAILED'){
                Require ($Reached.GateD -ceq 'NOT_RUN_GATE_C_FAILED' -and $Reached.Verdict -ceq 'P4_3_REDESIGN3A_REJECTED') 'Reached rejection must remain factual and block D'
            }else{
                $blockedD=if($Reached.GateC.Status -ceq 'GATE_C_CLEAR_FIDELITY_NOT_EVALUATED'){'NOT_RUN_GATE_C_NOT_EVALUATED'}else{'NOT_RUN_TASK4_NOT_IMPLEMENTED'}
                Require ($Reached.GateC.Status -cin @('GATE_C_CLEAR_FIDELITY_NOT_EVALUATED','GATE_C_CLEAR_FIDELITY_PASS') -and $Reached.GateD -ceq $blockedD -and $Reached.Verdict -ceq 'P4_3_REDESIGN3A_NOT_EVALUATED') 'Unreached D cannot establish early-gates acceptance'
            }
            $observedCalls=0;foreach($run in $Reached.GateC.Runs){$observedCalls+=$run.Batch.InvocationCount}
            Require ($Reached.MappingInvocationCount -eq 2 -and $Reached.QualityInvocationCount -eq $observedCalls -and $Reached.TotalOcrInvocationCount -eq 2+$observedCalls) 'Reached C verification preserves exactly the observed mapping and clear calls'
            if($Reached.GateC.Runs.Count -eq 8){Require ($Reached.QualityInvocationCount -eq 8) 'Completed reached C matrix requires eight clear OCR calls'}else{
                Require ($null -ne $Reached.GateC.Code -and $Reached.GateC.Status -cin @('GATE_C_CLEAR_FIDELITY_FAILED','GATE_C_CLEAR_FIDELITY_NOT_EVALUATED') -and $Reached.GateC.Task4 -ceq 'BLOCKED') 'Incomplete reached C matrix must report its abort and block Task4'
            }
            foreach($counts in $Reached.GateC.PreparationCounts){Require ($counts.PdfOpenCount -eq 1 -and $counts.PageReadCount -eq 1 -and $counts.ImageDecodeCount -eq 1 -and $counts.GridBuildCount -eq 1 -and $counts.CropBuildCount -eq 1) 'Reached fixtures must reuse one preparation'}
            if($Reached.GateC.Runs.Count -eq 8 -or $Reached.GateC.Status -cne 'GATE_C_CLEAR_FIDELITY_FAILED'){foreach($repeat in $Reached.GateC.Determinism){Require ($repeat.WordsIdentical -and $repeat.TextsIdentical -and $repeat.FidelityIdentical -and $repeat.DiagnosticsIdentical) 'Completed or non-rejected reached repeated evidence must be identical'}}
        }
    }
    Write-Host "AllReached verification assertions PASS; actual acceptance=$($Reached.Verdict); GateD=$($Reached.GateD); mapping=$($Reached.MappingInvocationCount) clear=$($Reached.QualityInvocationCount) safety=$($Reached.SafetyInvocationCount) total=$($Reached.TotalOcrInvocationCount)"
}
if($Group -ceq 'ReachedReporting'){
    # Run the real public CLI with absent supply; helper preparation remains real.
    $missing=Join-Path ([IO.Path]::GetTempPath()) ('milimap-p43r3a-absent-'+[guid]::NewGuid().ToString('N'))
    Require (-not (Test-Path -LiteralPath $missing)) 'Absent-supply test must not acquire runtime/model'
    $cli=Invoke-InternalP43R3aProcess -Executable (Get-Command pwsh).Source -Arguments @('-NoProfile','-File',$PSCommandPath,'-Group','AllReached','-TesseractExecutable',(Join-Path $missing 'tesseract.exe'),'-KoreanModelPath',(Join-Path $missing 'kor.traineddata')) -DeadlineMilliseconds 10000
    Write-Host $cli.Text
    Write-Host $cli.ErrorText
    Require ($cli.ExitCode -eq 0) 'AllReached CLI must report unavailable B and null C without property errors'
    Require ($cli.Text.Contains('GateB=GATE_B_BATCH_MAPPING_NOT_EVALUATED') -and $cli.Text.Contains('Code=EXECUTABLE_MISSING') -and $cli.Text.Contains('GateC=NOT_RUN_GATE_B_FAILED') -and $cli.Text.Contains('actual acceptance=P4_3_REDESIGN3A_NOT_EVALUATED') -and $cli.Text.Contains('mapping=0 clear=0 safety=0 total=0')) 'CLI must report observed unavailable supply and downstream block, not fabricated acceptance'
    $blocked=Invoke-P43R3aAllReached ([pscustomobject]@{}) ([pscustomobject]@{}) 'absent-exe' 'absent-model'
    $rendered=@(Assert-P43R3aReachedVerification $blocked 6>&1) -join "`n"
    Write-Host $rendered
    Require ($rendered.Contains('GateB=NOT_RUN_GATE_A_FAILED') -and $rendered.Contains('GateC=NOT_RUN_GATE_A_FAILED') -and $rendered.Contains('actual acceptance=P4_3_REDESIGN3A_REJECTED') -and $rendered.Contains('mapping=0 clear=0 safety=0 total=0')) 'A boundary rendering must accept null B/C and explicitly block every downstream gate'
    Write-Host 'ReachedReporting PASS: real absent-supply CLI and unproven-preparation rendering; actual OCR calls=0'
    return
}
if($Group -ceq 'AllReached'){
    Require ($Executable -and $ModelPath) 'AllReached requires exact verified runtime and Korean model paths'
    $scratch=Join-Path ([IO.Path]::GetTempPath()) ('milimap-p43r3a-reached-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($scratch)
    try{
        $gray=Prepare-P43R3aFixture -PdfPath (Join-Path $PSScriptRoot '../p4-3a-ocr/fixtures/gray.pdf') -ArtifactDirectory (Join-Path $scratch 'gray')
        $rgb=Prepare-P43R3aFixture -PdfPath (Join-Path $PSScriptRoot '../p4-3a-ocr/fixtures/rgb.pdf') -ArtifactDirectory (Join-Path $scratch 'rgb')
        $reached=Invoke-P43R3aAllReached $gray $rgb $Executable $ModelPath
        Assert-P43R3aReachedVerification $reached
    }finally{[IO.Directory]::Delete($scratch,$true)}
    return
}
if($Group -ceq 'ClearFidelity'){
    foreach($name in @('Get-P43R3aOverlapClass','Resolve-P43R3aCropText','ConvertTo-P43R3aCellTexts','Get-P43R3aFixtureGroundTruth','Normalize-P43R3aFidelityText','Evaluate-P43R3aFidelity','Invoke-P43R3aGateC')){
        Require ($null -ne (Get-Command $name -ErrorAction SilentlyContinue)) "FAIL: Missing reconstruction/fidelity function: $name"
    }
    foreach($name in @('Resolve-P43R3aCropText','ConvertTo-P43R3aCellTexts','Get-P43R3aOverlapClass')){
        Require (-not (Get-Command $name).Parameters.ContainsKey('ExpectedText')) "$name must not consume expected text"
        Require (-not (Get-Command $name).Parameters.ContainsKey('OverlapRatio')) 'Overlap ratio is fixed, not a search parameter'
    }
    function New-TestWord([int]$Left,[int]$Top,[string]$Text,[int]$Word=1,[int]$Height=10,[int]$Width=20,[int]$Line=1,[double]$Confidence=1){
        [pscustomobject]@{Page=1;Block=1;Paragraph=1;Line=$Line;Word=$Word;Left=$Left;Top=$Top;Width=$Width;Height=$Height;Text=$Text;Confidence=$Confidence;CropOrdinal=1;CellId='1'}
    }
    $adjacent=@((New-TestWord 0 0 '가' 1),(New-TestWord 16 0 '나' 2))
    Require ((Get-P43R3aOverlapClass $adjacent[0] $adjacent[1]) -ceq 'SAFE_ADJACENT') '20 percent overlap is safe'
    $boundary=New-TestWord 15 0 '나' 2
    Require ((Get-P43R3aOverlapClass $adjacent[0] $boundary) -ceq 'CONFLICTING') 'Exactly 25 percent overlap is conflicting'
    $safe=Resolve-P43R3aCropText -PageWords $adjacent -CellId '1'
    $shuffled=Resolve-P43R3aCropText -PageWords @($adjacent[1],$adjacent[0]) -CellId '1'
    Require ($safe.Status -ceq 'COMPLETE' -and $safe.Text -ceq '가 나' -and ($safe.RawWordConfidences -join ',') -ceq '1,1') 'Safe adjacent words and confidence 1 remain usable'
    Require (($safe | ConvertTo-Json -Depth 12 -Compress) -ceq ($shuffled | ConvertTo-Json -Depth 12 -Compress)) 'Enumeration must not affect reconstructed evidence'
    foreach($case in @(
        @{Words=@((New-TestWord 0 0 '가'),(New-TestWord 0 0 '가'));Code='DUPLICATE'},
        @{Words=@((New-TestWord 0 0 '가'),(New-TestWord 0 0 '나'));Code='CONFLICTING'},
        @{Words=@((New-TestWord 0 0 '가' 2),(New-TestWord 30 0 '나' 1));Code='ORDERING_UNSAFE'},
        @{Words=@((New-TestWord 0 0 '가' 1),(New-TestWord 30 8 '나' 2),(New-TestWord 60 16 '다' 3));Code='ORDERING_UNSAFE'})){
        $resolved=Resolve-P43R3aCropText -PageWords $case.Words -CellId '1'
        Require ($resolved.Status -ceq 'PARTIAL' -and @($resolved.Diagnostics | Where-Object Code -CEQ $case.Code).Count -gt 0) "Unsafe geometry: $($case.Code)"
        $reverse=Resolve-P43R3aCropText -PageWords @($case.Words | Sort-Object Text -Descending) -CellId '1'
        Require (($resolved | ConvertTo-Json -Depth 12 -Compress) -ceq ($reverse | ConvertTo-Json -Depth 12 -Compress)) 'Unsafe diagnostics must also be deterministic'
    }
    $multiline=@((New-TestWord 30 30 '라' 2 10 20 2),(New-TestWord 0 0 '가' 1),(New-TestWord 0 30 '다' 1 10 20 2),(New-TestWord 30 0 '나' 2))
    $multi=Resolve-P43R3aCropText $multiline '1'
    Require ($multi.Status -ceq 'COMPLETE' -and $multi.Text -ceq "가 나`n다 라") 'Physical multiline reconstruction'
    $empty=Resolve-P43R3aCropText @() '1'
    Require ($empty.Status -ceq 'PARTIAL') 'Empty crop cannot be complete'
    $foreign=Resolve-P43R3aCropText @((New-TestWord 0 0 '가')) '2'
    Require ($foreign.Status -ceq 'PARTIAL') 'Foreign mapped CellId must fail closed'
    $batch=[pscustomobject]@{Status='COMPLETE';Pages=@([pscustomobject]@{Page=1;CropOrdinal=1;CellId='1'});Words=$adjacent}
    $converted=@(ConvertTo-P43R3aCellTexts $batch)
    Require ($converted.Count -eq 1 -and $converted[0].CellId -ceq '1' -and $converted[0].Text -ceq '가 나') 'One cell result per mapped crop'
    $truth=Get-P43R3aFixtureGroundTruth
    Require ($truth.GeneratorBlob -ceq '6231ed473349063ce3b0d12fc7b2cff0bef1d114' -and $truth.ManifestBlob -ceq 'cde2a581ec2c4a1fb26481992908b5dcab2740ac' -and $truth.A2ManifestBlob -ceq 'ede9c602fbea2ae5a76e7dcfdc067f242c1929b7') 'Historical authority identities'
    $authored=@('업체명','주소','전화번호','혜택','가상 가람 식당','가상시 가람로 12','031-123-4567','시험 할인 10%','가상 누리 식당','가상시 누리로 23','031-234-5678',"시험 할인 20%`n방문 시 적용")
    Require ($truth.FixtureHashes.Count -eq 5) 'Clear and all three A2 fixtures covered'
    foreach($fixture in @('gray.pdf','rgb.pdf','mild-degraded-gray.pdf','degraded-gray.pdf','degraded-rgb.pdf')){
        $cells=$truth.FixtureCells[$fixture]
        Require ($cells.Count -eq 12 -and ($cells.ExpectedText -join '|') -ceq ($authored -join '|')) "$fixture authored 3x4 table independent of OCR"
        Require (@($cells | Where-Object FieldRole -CEQ 'HEADER').Count -eq 4 -and @($cells | Where-Object FieldRole -CEQ 'BUSINESS_NAME').Count -eq 2 -and @($cells | Where-Object FieldRole -CEQ 'BENEFIT').Count -eq 2) 'Eight mandatory roles'
    }
    # Corrupt identity responses only: immutable historical files are never edited.
    $originalHash=${function:Get-FileHash}
    function Get-FileHash { param($LiteralPath,$Algorithm) if($LiteralPath -like '*p4-3a2-ocr*degraded-gray.pdf'){[pscustomobject]@{Hash=('0'*64)}}else{Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath -Algorithm SHA256} }
    try{Reject {Get-P43R3aFixtureGroundTruth} 'GROUND_TRUTH_FIXTURE_MISMATCH'}finally{
        if($null -eq $originalHash){Remove-Item Function:Get-FileHash}else{Set-Item Function:Get-FileHash $originalHash}
    }
    $originalGit=Get-Item Function:git -ErrorAction SilentlyContinue
    function git { if($args[-1] -like '*p4-3a2-ocr*manifest.json'){$global:LASTEXITCODE=0;'0000000000000000000000000000000000000000'}else{& git.exe @args} }
    try{Reject {Get-P43R3aFixtureGroundTruth} 'GROUND_TRUTH_IDENTITY_MISMATCH'}finally{
        if($null -eq $originalGit){Remove-Item Function:git}else{Set-Item Function:git $originalGit.ScriptBlock}
    }
    Require ((Normalize-P43R3aFidelityText " `t가상`u{00a0}  식당`r`n방문 `t") -ceq "가상 식당`n방문") 'Allowed horizontal whitespace, CRLF and outer trim only'
    foreach($different in @('각'.Normalize([Text.NormalizationForm]::FormD),'가상 식당 11%','가상 식당 10!','가상 식탕 10%')){
        $expected=if($different -ceq '각'.Normalize([Text.NormalizationForm]::FormD)){'각'}else{'가상 식당 10%'}
        Require (-not [string]::Equals((Normalize-P43R3aFidelityText $expected),(Normalize-P43R3aFidelityText $different),[StringComparison]::Ordinal)) 'Character, number, punctuation and Unicode decomposition remain unequal'
    }
    Require ((Normalize-P43R3aFidelityText "가`n 나") -ceq "가`n 나" -and (Normalize-P43R3aFidelityText "가`r나") -ceq "가`r나") 'Internal newline, line space and lone CR not repaired'
    $exact=@(for($i=0;$i -lt 12;$i++){[pscustomobject]@{CellId=[string]($i+1);Status='COMPLETE';Text=$authored[$i];Diagnostics=@();RawWordConfidences=@(1)}})
    $good=Evaluate-P43R3aFidelity 'gray.pdf' $truth.FixtureHashes['gray.pdf'] 6 $exact
    Require ($good.Status -ceq 'PASS' -and $good.MandatoryMatchCount -eq 8 -and $good.AllCellMatchCount -eq 12 -and $good.Cells[0].RawWordConfidences[0] -eq 1) 'Exact low confidence text passes'
    $wrong=@($exact | ForEach-Object {$_.PSObject.Copy()});$wrong[0].Text='업체';$wrong[0].RawWordConfidences=@(100)
    $bad=Evaluate-P43R3aFidelity 'gray.pdf' $truth.FixtureHashes['gray.pdf'] 11 $wrong
    Require ($bad.Status -ceq 'FAILED' -and $bad.MandatoryMatchCount -eq 7 -and $bad.AllCellMatchCount -eq 11 -and $bad.Cells[0].Status -ceq 'FIDELITY_MISMATCH') 'High confidence wrong mandatory text fails'
    $wrong[0].Status='PARTIAL'
    Require ((Evaluate-P43R3aFidelity 'gray.pdf' $truth.FixtureHashes['gray.pdf'] 6 $wrong).Status -ceq 'NOT_EVALUATED') 'Unsafe mandatory structure cannot pass fidelity'
    Require ((Evaluate-P43R3aFidelity 'gray.pdf' ('0'*64) 6 $exact).Status -ceq 'NOT_EVALUATED') 'Caller fixture hash mismatch cannot evaluate'
    Require ((Evaluate-P43R3aFidelity 'gray.pdf' $truth.FixtureHashes['gray.pdf'] 6 @($exact[0..10])).Status -ceq 'NOT_EVALUATED') 'Missing mapped cell cannot evaluate'
    $forged=[pscustomobject]@{Crops=@()}
    $blocked=Invoke-P43R3aGateC $forged $forged 'missing' 'missing'
    Require ($blocked.Status -ceq 'GATE_C_CLEAR_FIDELITY_NOT_EVALUATED' -and $blocked.Runs.Count -eq 0 -and $blocked.QualityInvocationCount -eq 0) 'Gate A failure prevents quality calls'
    # Matrix orchestration controls isolate the external OCR boundary. Reconstruction
    # and fidelity stay real; authored words are test-only, never OCR inputs.
    $originalGateA=${function:Invoke-P43R3aGateA};$originalBatch=${function:Invoke-P43R3aTesseractBatch}
    function New-TestPrepared([string]$Fixture){
        [pscustomobject]@{FixtureHash=$truth.FixtureHashes[$Fixture];Crops=@(for($i=1;$i -le 12;$i++){
            [pscustomobject]@{Ordinal=$i;CellId=[string]$i;Row=[int][Math]::Floor(($i-1)/4)+1;Column=($i-1)%4+1;X0=0;Y0=0;X1=400;Y1=150;Width=400;Height=150;Components=1;ArtifactPath="test-$Fixture-$i.pgm";CropSha256=('0'*64)}
        });PdfOpenCount=1;PageReadCount=1;ImageDecodeCount=1;GridBuildCount=1;CropBuildCount=1}
    }
    $script:testGray=New-TestPrepared 'gray.pdf';$script:testRgb=New-TestPrepared 'rgb.pdf'
    $script:reachedMapping=$false;$script:reachedMappingCalls=0
    function Invoke-P43R3aGateA { param($PreparedFixture) 'GATE_A_CROP_PROVENANCE_PASS' }
    function Invoke-P43R3aTesseractBatch {
        param($Executable,$ModelPath,$Crops,$Psm)
        Require ($Executable -ceq 'test-exe' -and $ModelPath -ceq 'test-model') 'Matrix forwards exact supply'
        $mapping=$script:reachedMapping -and $script:reachedMappingCalls -lt 2
        $expectedCrops=if($mapping -or $script:matrixCalls -lt 4){$script:testGray.Crops}else{$script:testRgb.Crops}
        Require (@($Crops).Count -eq 12) 'Every batch must retain all 12 prepared crops'
        for($i=0;$i -lt 12;$i++){Require ([object]::ReferenceEquals(@($Crops)[$i],$expectedCrops[$i])) 'Matrix retains every prepared crop object in order'}
        Require ($Psm -eq $(if($mapping){if($script:reachedMappingCalls -eq 0){6}else{11}}elseif($script:matrixCalls%4 -lt 2){6}else{11})) 'Fixed mapping pair then PSM6 twice and PSM11 twice'
        if($mapping){$script:reachedMappingCalls++}else{$script:matrixCalls++}
        $mappingFailed=$mapping -and ($script:matrixMode -ceq 'mapping-failed' -or ($script:matrixMode -ceq 'mapping-failed-then-unavailable' -and $script:reachedMappingCalls -eq 1))
        $qualityFailed=-not $mapping -and $script:matrixMode -ceq 'batch-failed-then-unavailable' -and $script:matrixCalls -eq 1
        if($mappingFailed -or $qualityFailed){
            return [pscustomobject]@{Status='FAILED';Code='BATCH_PAGE_MAPPING_INVALID';InvocationCount=1;Psm=$Psm;EngineVersion='5.5.3';EngineBuild='tesseract v5.5.3.20260724';ModelSha256='6b85e11d9bbf07863b97b3523b1b112844c43e713df8b66418a081fd1060b3b2';Pages=@();Words=@();Diagnostics=@([pscustomobject]@{Code='BATCH_PAGE_MAPPING_INVALID'});ElapsedMilliseconds=1;ProductionAction='NONE'}
        }
        $mappingUnavailable=$mapping -and $script:matrixMode -ceq 'mapping-failed-then-unavailable' -and $script:reachedMappingCalls -eq 2
        $qualityUnavailable=-not $mapping -and (($script:matrixMode -cin @('batch-failed-then-unavailable','mismatch-then-unavailable','partial-then-unavailable','exact-then-unavailable') -and $script:matrixCalls -eq 2) -or ($script:matrixMode -ceq 'nondeterministic-then-unavailable' -and $script:matrixCalls -eq 3))
        if($script:matrixMode -ceq 'unavailable-supply' -or $mappingUnavailable -or $qualityUnavailable){
            return [pscustomobject]@{Status='FAILED';Code='MODEL_MISSING';InvocationCount=0;Psm=$Psm;EngineVersion=$null;EngineBuild=$null;ModelSha256=$null;Pages=@();Words=@();Diagnostics=@([pscustomobject]@{Code='MODEL_MISSING'});ElapsedMilliseconds=0;ProductionAction='NONE'}
        }
        $words=@(for($i=0;$i -lt 12;$i++){
            $word=New-TestWord 0 0 $authored[$i]
            $word.Page=$i+1;$word.CropOrdinal=$i+1;$word.CellId=[string]($i+1)
            if($i -eq 0 -and $Psm -eq 11 -and $script:matrixMode -ceq 'mismatch'){$word.Text='업체'}
            if($i -eq 0 -and $script:matrixMode -ceq 'mismatch-then-unavailable'){$word.Text='업체'}
            if($i -eq 5 -and $script:matrixCalls -eq 2 -and $script:matrixMode -cin @('nondeterministic','nondeterministic-then-unavailable')){$word.Text='다른 주소'}
            $word
            if($i -eq 0 -and $script:matrixMode -cin @('mandatory-partial','partial-then-unavailable')){$duplicate=$word.PSObject.Copy();$duplicate.Word=2;$duplicate}
        })
        $pages=@(for($i=1;$i -le 12;$i++){[pscustomobject]@{Page=$i;CropOrdinal=$i;CellId=[string]$i;Left=0;Top=0;Width=400;Height=150;WordCount=1}})
        if($script:matrixMode -cin @('mandatory-partial','partial-then-unavailable')){$pages[0].WordCount=2}
        [pscustomobject]@{Status='COMPLETE';Code=$null;InvocationCount=1;Psm=$Psm;EngineVersion='5.5.3';EngineBuild='tesseract v5.5.3.20260724';ModelSha256='6b85e11d9bbf07863b97b3523b1b112844c43e713df8b66418a081fd1060b3b2';Pages=$pages;Words=$words;Diagnostics=@();ElapsedMilliseconds=$script:matrixCalls;ProductionAction='NONE'}
    }
    try{
        foreach($mode in @('exact','mismatch','nondeterministic','mandatory-partial')){
            $script:matrixMode=$mode;$script:matrixCalls=0
            $controlled=Invoke-P43R3aGateC $script:testGray $script:testRgb 'test-exe' 'test-model'
            Require ($controlled.Runs.Count -eq 8 -and $controlled.QualityInvocationCount -eq 8 -and $script:matrixCalls -eq 8) 'No retry or extra quality calls'
            if($mode -ceq 'exact'){
                Require ($controlled.Status -ceq 'GATE_C_CLEAR_FIDELITY_PASS' -and @($controlled.Runs | Where-Object {$_.Fidelity.MandatoryMatchCount -ne 8 -or $_.Fidelity.AllCellMatchCount -ne 12}).Count -eq 0) 'All independent PSM paths must match'
                Require (@($controlled.Determinism | Where-Object {-not $_.WordsIdentical -or -not $_.TextsIdentical -or -not $_.FidelityIdentical -or -not $_.DiagnosticsIdentical}).Count -eq 0) 'Elapsed time excluded from determinism'
            }elseif($mode -ceq 'mismatch'){
                Require ($controlled.Status -ceq 'GATE_C_CLEAR_FIDELITY_FAILED' -and $controlled.Verdict -ceq 'P4_3_REDESIGN3A_REJECTED' -and $controlled.Task4 -ceq 'BLOCKED') 'Exact PSM6 cannot rescue wrong PSM11'
                Require (@($controlled.Runs | Where-Object {$_.Psm -eq 6 -and $_.Fidelity.MandatoryMatchCount -eq 8}).Count -eq 4 -and @($controlled.Runs | Where-Object {$_.Psm -eq 11 -and $_.Fidelity.MandatoryMatchCount -eq 7}).Count -eq 4) 'Every repetition independently evaluated'
            }elseif($mode -ceq 'nondeterministic'){
                Require ($controlled.Status -ceq 'GATE_C_CLEAR_FIDELITY_FAILED' -and -not $controlled.Determinism[0].WordsIdentical -and -not $controlled.Determinism[0].TextsIdentical -and -not $controlled.Determinism[0].FidelityIdentical) 'Auxiliary-only repeat change still fails determinism'
            }else{
                Require (@($controlled.Runs | Where-Object {$_.Batch.Status -cne 'COMPLETE' -or $_.Fidelity.Status -cne 'NOT_EVALUATED' -or $_.Fidelity.MandatoryMatchCount -ne 7 -or $_.CellTexts[0].Status -cne 'PARTIAL'}).Count -eq 0) 'Observed mandatory incompleteness with eight complete batches'
                Require (@($controlled.Runs | ForEach-Object {$_.Fidelity.Cells} | Where-Object Status -CEQ 'FIDELITY_MISMATCH').Count -eq 0) 'Partial-only regression has no evaluated text mismatch'
                Require ($controlled.Status -ceq 'GATE_C_CLEAR_FIDELITY_FAILED' -and $controlled.Verdict -ceq 'P4_3_REDESIGN3A_REJECTED' -and $controlled.Task4 -ceq 'BLOCKED') 'Completed matrix with mandatory PARTIAL must reject candidate'
            }
        }
        # Supply loss must not overwrite earlier real orchestration evidence. The
        # seam replaces only external OCR; reconstruction, fidelity and gates run.
        $failures=[Collections.Generic.List[string]]::new()
        $script:matrixMode='mapping-failed-then-unavailable';$script:reachedMapping=$true;$script:reachedMappingCalls=0;$script:matrixCalls=0
        $mixed=Invoke-P43R3aAllReached $script:testGray $script:testRgb 'test-exe' 'test-model'
        if($mixed.GateB.Status -cne 'GATE_B_BATCH_MAPPING_FAILED' -or $mixed.GateB.Code -cne 'BATCH_PAGE_MAPPING_INVALID' -or $mixed.Verdict -cne 'P4_3_REDESIGN3A_REJECTED'){$failures.Add("B failed then unavailable: $($mixed.GateB.Status)/$($mixed.GateB.Code)/$($mixed.Verdict)")}
        Require ($mixed.MappingInvocationCount -eq 1 -and $mixed.TotalOcrInvocationCount -eq 1 -and $mixed.QualityInvocationCount -eq 0 -and $mixed.SafetyInvocationCount -eq 0 -and $null -eq $mixed.GateC -and $mixed.GateB.Batches.Count -eq 2 -and $script:reachedMappingCalls -eq 2 -and $script:matrixCalls -eq 0) 'Mixed B abort preserves both batches and one observed call, with no downstream OCR'
        Write-Host "Mixed B: status=$($mixed.GateB.Status) code=$($mixed.GateB.Code) verdict=$($mixed.Verdict) mapping=1 clear=0 safety=0 total=1 attempts=2"
        $script:reachedMapping=$false
        foreach($mode in @('batch-failed-then-unavailable','mismatch-then-unavailable','partial-then-unavailable','nondeterministic-then-unavailable','exact-then-unavailable')){
            $script:matrixMode=$mode;$script:matrixCalls=0
            $mixed=Invoke-P43R3aGateC $script:testGray $script:testRgb 'test-exe' 'test-model'
            $observed=if($mode -ceq 'nondeterministic-then-unavailable'){2}else{1}
            $status=if($mode -ceq 'exact-then-unavailable'){'GATE_C_CLEAR_FIDELITY_NOT_EVALUATED'}else{'GATE_C_CLEAR_FIDELITY_FAILED'}
            $verdict=if($mode -ceq 'exact-then-unavailable'){'P4_3_REDESIGN3A_NOT_EVALUATED'}else{'P4_3_REDESIGN3A_REJECTED'}
            if($mixed.Status -cne $status -or $mixed.Verdict -cne $verdict){$failures.Add("C $mode`: $($mixed.Status)/$($mixed.Verdict)")}
            Require ($mixed.Code -ceq 'MODEL_MISSING' -and $mixed.QualityInvocationCount -eq $observed -and $mixed.Runs.Count -eq $observed -and $script:matrixCalls -eq $observed+1 -and $mixed.PreparationCounts.Count -eq 1 -and $mixed.Task4 -ceq 'BLOCKED' -and $mixed.ProductionAction -ceq 'NONE') 'Mixed C abort retains prior runs and preparation counts without retry or downstream OCR'
            if($mode -ceq 'batch-failed-then-unavailable'){Require ($mixed.Runs[0].Batch.Status -ceq 'FAILED' -and $mixed.Runs[0].Batch.Code -ceq 'BATCH_PAGE_MAPPING_INVALID') 'Abort retains the original observed batch failure reason'}
            if($mode -ceq 'mismatch-then-unavailable'){Require ($mixed.Runs[0].Fidelity.Cells[0].Status -ceq 'FIDELITY_MISMATCH' -and $mixed.Runs[0].Fidelity.MandatoryMatchCount -eq 7) 'Abort retains observed mandatory mismatch'}
            if($mode -ceq 'partial-then-unavailable'){Require ($mixed.Runs[0].CellTexts[0].Status -ceq 'PARTIAL' -and $mixed.Runs[0].Fidelity.MandatoryMatchCount -eq 7) 'Abort retains observed mandatory incompleteness'}
            if($mode -ceq 'nondeterministic-then-unavailable'){Require ($mixed.Determinism.Count -eq 1 -and -not $mixed.Determinism[0].WordsIdentical -and -not $mixed.Determinism[0].TextsIdentical -and $mixed.Runs[0].Fidelity.MandatoryMatchCount -eq 8 -and $mixed.Runs[1].Fidelity.MandatoryMatchCount -eq 8) 'Abort retains observed auxiliary-only nondeterminism'}
            Write-Host "Mixed C $mode`: status=$($mixed.Status) code=$($mixed.Code) verdict=$($mixed.Verdict) clear=$observed runs=$observed attempts=$($script:matrixCalls) preparations=1 Task4=$($mixed.Task4)"
        }
        $script:matrixMode='exact';$script:matrixCalls=0;$script:reachedMapping=$true;$script:reachedMappingCalls=0
        $unreachedD=Invoke-P43R3aAllReached $script:testGray $script:testRgb 'test-exe' 'test-model'
        if($unreachedD.Verdict -cne 'P4_3_REDESIGN3A_NOT_EVALUATED'){$failures.Add("C pass with D unreached: $($unreachedD.Verdict)")}
        Require ($unreachedD.GateC.Status -ceq 'GATE_C_CLEAR_FIDELITY_PASS' -and $unreachedD.GateD -ceq 'NOT_RUN_TASK4_NOT_IMPLEMENTED' -and $unreachedD.MappingInvocationCount -eq 2 -and $unreachedD.QualityInvocationCount -eq 8 -and $unreachedD.TotalOcrInvocationCount -eq 10 -and $unreachedD.SafetyInvocationCount -eq 0) 'Intermediate C pass cannot fabricate D execution or first-cycle success'
        Write-Host "C pass/D unreached: verdict=$($unreachedD.Verdict) mapping=2 clear=8 safety=0 total=10"
        Require ($failures.Count -eq 0) ('Final result-contract regressions: '+($failures -join '; '))
        [void]@(Assert-P43R3aReachedVerification $unreachedD 6>&1)
        foreach($mode in @('mismatch-then-unavailable','exact-then-unavailable','nondeterministic-then-unavailable')){
            $script:matrixMode=$mode;$script:matrixCalls=0;$script:reachedMappingCalls=0
            $aborted=Invoke-P43R3aAllReached $script:testGray $script:testRgb 'test-exe' 'test-model'
            $rendered=@(Assert-P43R3aReachedVerification $aborted 6>&1) -join "`n"
            $calls=if($mode -ceq 'nondeterministic-then-unavailable'){2}else{1}
            Require ($aborted.MappingInvocationCount -eq 2 -and $aborted.QualityInvocationCount -eq $calls -and $aborted.TotalOcrInvocationCount -eq 2+$calls -and $script:matrixCalls -eq $calls+1 -and $rendered.Contains('AllReached verification assertions PASS')) 'Reached C supply abort preserves counters, approved final verdict and blocked D reporting'
        }
        Require ($null -ne (Get-Command Invoke-P43R3aAllReached -ErrorAction SilentlyContinue)) 'FAIL: reached pipeline verification wrapper is missing'
        $script:matrixMode='mandatory-partial';$script:matrixCalls=0
        $script:reachedMapping=$true;$script:reachedMappingCalls=0
        $reached=Invoke-P43R3aAllReached $script:testGray $script:testRgb 'test-exe' 'test-model'
        Require ($reached.GateA -ceq 'GATE_A_CROP_PROVENANCE_PASS' -and $reached.GateB.Status -ceq 'GATE_B_BATCH_MAPPING_PASS') 'Reached verification must actually validate A and B'
        Require ($reached.GateC.Status -ceq 'GATE_C_CLEAR_FIDELITY_FAILED' -and $reached.GateD -ceq 'NOT_RUN_GATE_C_FAILED' -and $reached.Verdict -ceq 'P4_3_REDESIGN3A_REJECTED') 'Reached mandatory PARTIAL must reject and block D'
        Require ($reached.MappingInvocationCount -eq 2 -and $reached.QualityInvocationCount -eq 8 -and $reached.TotalOcrInvocationCount -eq 10 -and $script:matrixCalls -eq 8) 'Reached mapping two plus clear eight, no extra quality or degraded calls'
        Require ($reached.SafetyInvocationCount -eq 0 -and $reached.ProductionAction -ceq 'NONE') 'Rejected reached path must not invoke safety or business OCR'
        $rendered=@(Assert-P43R3aReachedVerification $reached 6>&1) -join "`n"
        Require ($rendered.Contains('GateC=GATE_C_CLEAR_FIDELITY_FAILED') -and $rendered.Contains('actual acceptance=P4_3_REDESIGN3A_REJECTED') -and $rendered.Contains('mapping=2 clear=8 safety=0 total=10')) 'Reached-C reporting preserves the rejection and measured-matrix counters'
        Set-Item Function:Invoke-P43R3aGateA $originalGateA
        $blocked=Invoke-P43R3aAllReached $script:testGray $script:testRgb 'test-exe' 'test-model'
        Require ($blocked.GateA -ceq 'GATE_A_CROP_PROVENANCE_FAILED' -and $null -eq $blocked.GateB -and $null -eq $blocked.GateC -and $blocked.GateD -ceq 'NOT_RUN_GATE_A_FAILED' -and $blocked.TotalOcrInvocationCount -eq 0) 'Unproven preparation blocks every OCR invocation'
        function Invoke-P43R3aGateA { param($PreparedFixture) 'GATE_A_CROP_PROVENANCE_PASS' }
        $script:matrixMode='unavailable-supply';$script:reachedMappingCalls=0;$script:matrixCalls=0
        $blocked=Invoke-P43R3aAllReached $script:testGray $script:testRgb 'test-exe' 'test-model'
        Require ($blocked.GateB.Status -ceq 'GATE_B_BATCH_MAPPING_NOT_EVALUATED' -and $null -eq $blocked.GateC -and $blocked.GateD -ceq 'NOT_RUN_GATE_B_FAILED' -and $blocked.Verdict -ceq 'P4_3_REDESIGN3A_NOT_EVALUATED' -and $blocked.TotalOcrInvocationCount -eq 0) 'Unavailable supply cannot fabricate acceptance or run clear quality'
        $rendered=@(Assert-P43R3aReachedVerification $blocked 6>&1) -join "`n"
        Write-Host $rendered
        Require ($rendered.Contains('Code=MODEL_MISSING') -and $rendered.Contains('GateC=NOT_RUN_GATE_B_FAILED') -and $rendered.Contains('actual acceptance=P4_3_REDESIGN3A_NOT_EVALUATED') -and $rendered.Contains('mapping=0 clear=0 safety=0 total=0')) 'Unavailable model rendering must preserve unobserved evidence and null C'
        $script:matrixMode='mapping-failed';$script:reachedMappingCalls=0;$script:matrixCalls=0
        $blocked=Invoke-P43R3aAllReached $script:testGray $script:testRgb 'test-exe' 'test-model'
        $rendered=@(Assert-P43R3aReachedVerification $blocked 6>&1) -join "`n"
        Write-Host $rendered
        Require ($rendered.Contains('GateB=GATE_B_BATCH_MAPPING_FAILED') -and $rendered.Contains('Code=BATCH_PAGE_MAPPING_INVALID') -and $rendered.Contains('GateC=NOT_RUN_GATE_B_FAILED') -and $rendered.Contains('actual acceptance=P4_3_REDESIGN3A_REJECTED') -and $rendered.Contains('mapping=2 clear=0 safety=0 total=2') -and $script:matrixCalls -eq 0) 'Observed mapping failure rendering rejects with mapping-only counters and null C'
        $script:reachedMapping=$false
        $script:matrixMode='unavailable-supply';$script:matrixCalls=0
        $unavailable=Invoke-P43R3aGateC $script:testGray $script:testRgb 'test-exe' 'test-model'
        Require ($unavailable.Status -ceq 'GATE_C_CLEAR_FIDELITY_NOT_EVALUATED' -and $unavailable.Verdict -ceq 'P4_3_REDESIGN3A_NOT_EVALUATED' -and $unavailable.Code -ceq 'MODEL_MISSING' -and $unavailable.QualityInvocationCount -eq 0 -and $unavailable.Runs.Count -eq 0 -and $script:matrixCalls -eq 1) 'Unavailable supply without observed batch evidence remains NOT_EVALUATED'
    }finally{Set-Item Function:Invoke-P43R3aGateA $originalGateA;Set-Item Function:Invoke-P43R3aTesseractBatch $originalBatch}
    Write-Host 'ClearFidelity synthetic reconstruction/authority/fidelity assertions PASS; actual quality OCR calls=0'
    if($RunRealGateC){
        $scratch=Join-Path ([IO.Path]::GetTempPath()) ('milimap-p43r3a-clear-'+[guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($scratch)
        try{
            $gray=Prepare-P43R3aFixture -PdfPath (Join-Path $PSScriptRoot '../p4-3a-ocr/fixtures/gray.pdf') -ArtifactDirectory (Join-Path $scratch 'gray')
            $rgb=Prepare-P43R3aFixture -PdfPath (Join-Path $PSScriptRoot '../p4-3a-ocr/fixtures/rgb.pdf') -ArtifactDirectory (Join-Path $scratch 'rgb')
            $gate=Invoke-P43R3aGateC $gray $rgb $Executable $ModelPath
            foreach($run in $gate.Runs){
                Write-Host ("{0} PSM{1} repeat{2}: batch={3}/{4}; mandatory={5}/8 all={6}/12 fidelity={7}; words={8}; elapsedMs={9}" -f $run.Fixture,$run.Psm,$run.Repetition,$run.Batch.Status,$run.Batch.Code,$run.Fidelity.MandatoryMatchCount,$run.Fidelity.AllCellMatchCount,$run.Fidelity.Status,$run.Batch.Words.Count,$run.Batch.ElapsedMilliseconds)
                foreach($cell in @($run.Fidelity.Cells | Where-Object Status -CNE 'FIDELITY_MATCH')){Write-Host ("Mismatch: {0} PSM{1} repeat{2} cell={3} role={4} state={5} expected={6} actual={7} conf={8}" -f $run.Fixture,$run.Psm,$run.Repetition,$cell.CellId,$cell.FieldRole,$cell.Status,($cell.ExpectedText | ConvertTo-Json -Compress),($cell.ReconstructedText | ConvertTo-Json -Compress),($cell.RawWordConfidences -join ','))}
            }
            Write-Host ($gate.PreparationCounts | ConvertTo-Json -Compress)
            Write-Host ($gate.Determinism | ConvertTo-Json -Compress)
            Write-Host "Measured GateC=$($gate.Status); Code=$($gate.Code); Verdict=$($gate.Verdict); qualityCalls=$($gate.QualityInvocationCount); Task4=$($gate.Task4)"
            Require ($gate.QualityInvocationCount -eq 8 -and $gate.Runs.Count -eq 8) 'Fixed matrix must perform exactly eight quality calls'
            foreach($counts in $gate.PreparationCounts){Require ($counts.PdfOpenCount -eq 1 -and $counts.PageReadCount -eq 1 -and $counts.ImageDecodeCount -eq 1 -and $counts.GridBuildCount -eq 1 -and $counts.CropBuildCount -eq 1) 'Prepare each fixture once'}
            $pass=@($gate.Runs | Where-Object {$_.Fidelity.MandatoryMatchCount -ne 8 -or $_.Fidelity.Status -cne 'PASS'}).Count -eq 0 -and @($gate.Determinism | Where-Object {-not $_.WordsIdentical -or -not $_.TextsIdentical -or -not $_.FidelityIdentical -or -not $_.DiagnosticsIdentical}).Count -eq 0
            Require (($gate.Status -ceq 'GATE_C_CLEAR_FIDELITY_PASS') -eq $pass) 'Executable gate assertions must agree with measured mandatory evidence'
            if(-not $pass){Require ($gate.Verdict -ceq 'P4_3_REDESIGN3A_REJECTED' -and $gate.Task4 -ceq 'BLOCKED') 'Measured failure rejects candidate and stops Task4'}
            Write-Host "ClearFidelity executable assertions PASS; actual acceptance=$($gate.Status)"
        }finally{[IO.Directory]::Delete($scratch,$true)}
    }else{Write-Host 'Actual Gate C NOT_RUN; synthetic PASS is not measured fidelity acceptance'}
    return
}
if($Group -ceq 'BatchMapping'){
    foreach($name in @('ConvertFrom-P43R3aBatchTsv','Invoke-P43R3aTesseractBatch','Invoke-P43R3aGateB')){
        Require ($null -ne (Get-Command $name -ErrorAction SilentlyContinue)) "FAIL: Missing batch function: $name"
    }
    Require (-not (Get-Command Invoke-P43R3aTesseractBatch).Parameters.ContainsKey('ConfidenceThreshold')) 'No confidence threshold API'
    Require (-not (Get-Command Invoke-P43R3aTesseractBatch).Parameters.ContainsKey('Inputs')) 'No single-cell fallback API'
    function New-TestBatchTsv([int]$Count){
        $rows=[Collections.Generic.List[string]]::new()
        $rows.Add("level`tpage_num`tblock_num`tpar_num`tline_num`tword_num`tleft`ttop`twidth`theight`tconf`ttext")
        for($page=1;$page -le $Count;$page++){
            foreach($row in @("1`t$page`t0`t0`t0`t0`t0`t0`t2`t2`t-1`t","2`t$page`t1`t0`t0`t0`t0`t0`t2`t2`t-1`t","3`t$page`t1`t1`t0`t0`t0`t0`t2`t2`t-1`t","4`t$page`t1`t1`t1`t0`t0`t0`t2`t2`t-1`t","5`t$page`t1`t1`t1`t1`t0`t0`t1`t1`t0`t가","5`t$page`t1`t1`t1`t2`t1`t1`t1`t1`t100`t나")){$rows.Add($row)}
        }
        return $rows -join "`n"
    }
    $valid=New-TestBatchTsv 2
    $parsed=ConvertFrom-P43R3aBatchTsv -Text $valid -ExpectedPageCount 2
    Require ($parsed.Pages.Count -eq 2 -and $parsed.Words.Count -eq 4 -and ($parsed.Pages.Page -join ',') -ceq '1,2') 'Multiple words per page remain valid'
    $word=$parsed.Words[1]
    Require ($word.Page -eq 1 -and $word.Block -eq 1 -and $word.Paragraph -eq 1 -and $word.Line -eq 1 -and $word.Word -eq 2 -and $word.Left -eq 1 -and $word.Top -eq 1 -and $word.Width -eq 1 -and $word.Height -eq 1 -and $word.Confidence -eq 100 -and $word.Text -ceq '나') 'Preserve exact word fields'
    $pageRecord="1`t1`t0`t0`t0`t0`t0`t0`t2`t2`t-1`t"
    Reject {ConvertFrom-P43R3aBatchTsv -Text ($valid.Replace($pageRecord+"`n",'')) -ExpectedPageCount 2} 'BATCH_PAGE_MAPPING_INVALID'
    Reject {ConvertFrom-P43R3aBatchTsv -Text ($valid+"`n"+$pageRecord) -ExpectedPageCount 2} 'BATCH_PAGE_MAPPING_INVALID'
    Reject {ConvertFrom-P43R3aBatchTsv -Text $valid -ExpectedPageCount 1} 'BATCH_PAGE_MAPPING_INVALID'
    Reject {ConvertFrom-P43R3aBatchTsv -Text $valid -ExpectedPageCount 3} 'BATCH_PAGE_MAPPING_INVALID'
    foreach($bad in @($valid.Replace('level','wrong'),$valid.Replace("5`t1`t1`t1`t1`t1`t0`t0`t1`t1`t0`t가","5`t1`t1`t1`t1`t1`t0`t0`t0`t1`t0`t가"),$valid.Replace("`t100`t나","`tNaN`t나"),$valid.Replace("`t100`t나","`t101`t나"),$valid.Replace("`t0`t가","`t-1`t가"),$valid.Replace("5`t1`t1`t1`t1`t2`t1`t1","5`t1`t1`t1`t1`t2`t2`t1"),$valid.Replace("4`t1`t1`t1`t1`t0`t0`t0`t2`t2`t-1`t`n",''))){
        Reject {ConvertFrom-P43R3aBatchTsv -Text $bad -ExpectedPageCount 2} 'BATCH_TSV_INVALID'
    }
    $empty=($valid -split "`n" | Where-Object {$_ -cnotmatch '^5\t2\t'}) -join "`n"
    Reject {ConvertFrom-P43R3aBatchTsv -Text $empty -ExpectedPageCount 2} 'BATCH_REQUIRED_PAGE_EMPTY'
    $scratch=Join-Path ([IO.Path]::GetTempPath()) ('milimap-p43r3a-batch-test-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($scratch)
    try{
        if(-not $Executable -or -not $ModelPath){throw 'BatchMapping requires exact verified -Executable and -ModelPath'}
        $path=Join-Path $scratch 'source.pgm'
        [IO.File]::WriteAllBytes($path,[byte[]]([Text.Encoding]::ASCII.GetBytes("P5`n8 6`n255`n")+[byte[]](0..47)))
        $cells=@(for($id=1;$id -le 12;$id++){
            $row=[int][Math]::Floor(($id-1)/4)+1;$column=($id-1)%4+1
            [pscustomobject]@{CellId=[string]$id;Row=$row;Column=$column;X0=($column-1)*2;Y0=($row-1)*2;X1=$column*2;Y1=$row*2}
        })
        $crops=(New-P43R3aCellCropSet -ImagePath $path -ImageSha256 (Get-FileHash $path).Hash.ToLowerInvariant() -Cells $cells -OutputDirectory (Join-Path $scratch 'crops')).Crops
        $originalProcess=(Get-Item Function:Invoke-InternalP43R3aProcess).ScriptBlock
        $script:batchMode='valid';$script:batchCalls=0;$script:listPath=$null
        $script:expectedCropPaths=$crops.ArtifactPath -join ','
        function Invoke-InternalP43R3aProcess {
            param($Executable,$Arguments,$DeadlineMilliseconds)
            if($Arguments[0] -ceq '--version'){
                $version=if($script:batchMode -ceq 'version'){'tesseract 5.5.3'}else{'tesseract v5.5.3.20260724'}
                return [pscustomobject]@{ExitCode=0;Text=$version;ErrorText='';ElapsedMilliseconds=1}
            }
            $script:batchCalls++;$script:listPath=$Arguments[0]
            Require (([IO.File]::ReadAllLines($Arguments[0]) -join ',') -ceq $script:expectedCropPaths) 'Image list must use crop ordinal order'
            Require (($Arguments[1..($Arguments.Count-1)] -join '|') -ceq ('stdout|--tessdata-dir|'+[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($ModelPath))+'|-l|kor|--oem|1|--psm|6|--dpi|300|-c|tessedit_create_tsv=1')) 'Exact batch arguments'
            if($script:batchMode -ceq 'timeout'){throw 'BATCH_PROCESS_TIMEOUT'}
            $text=New-TestBatchTsv 12
            if($script:batchMode -ceq 'oversized'){$text='x'*1048577}
            if($script:batchMode -ceq 'missing'){$text=$text.Replace("1`t12`t0`t0`t0`t0`t0`t0`t2`t2`t-1`t`n",'')}
            if($script:batchMode -ceq 'empty'){$text=($text -split "`n" | Where-Object {$_ -cnotmatch '^5\t12\t'}) -join "`n"}
            return [pscustomobject]@{ExitCode=$(if($script:batchMode -ceq 'exit'){1}else{0});Text=$text;ErrorText='';ElapsedMilliseconds=1}
        }
        try{
            try{Invoke-P43R3aTesseractBatch -Executable $Executable -ModelPath $ModelPath -Crops $crops -Psm 3;throw 'Invalid PSM accepted'}catch{Require ($_.Exception.Message -like '*ValidateSet*' -or $_.Exception.Message -like '*6,11*') 'PSM 3 must reject at API boundary'}
            $result=Invoke-P43R3aTesseractBatch -Executable $Executable -ModelPath $ModelPath -Crops @($crops | Sort-Object Ordinal -Descending) -Psm 6
            Require ($result.Status -ceq 'COMPLETE' -and $result.InvocationCount -eq 1 -and $result.Pages.Count -eq 12 -and $result.Words.Count -eq 24 -and $script:batchCalls -eq 1 -and $result.ProductionAction -ceq 'NONE') "One exact batch publishes all 12 logical pages; code=$($result.Code)"
            Require (-not [IO.File]::Exists($script:listPath)) 'Success cleans list scratch'
            Require (($result.Pages.CropOrdinal -join ',') -ceq '1,2,3,4,5,6,7,8,9,10,11,12' -and ($result.Pages.CellId -join ',') -ceq '1,2,3,4,5,6,7,8,9,10,11,12' -and $result.Words[23].CropOrdinal -eq 12 -and $result.Words[23].CellId -ceq '12' -and $result.Words[0].Confidence -eq 0) 'Exact identity mapping; confidence zero retained'
            foreach($kind in @('ordinal','cell-id','crop-hash')){
                $badCrops=@($crops | ForEach-Object {$_.PSObject.Copy()})
                switch($kind){'ordinal'{$badCrops[0].Ordinal=2};'cell-id'{$badCrops[0].CellId='2'};'crop-hash'{$badCrops[0].CropSha256='0'*64}}
                $bad=Invoke-P43R3aTesseractBatch -Executable $Executable -ModelPath $ModelPath -Crops $badCrops -Psm 6
                Require ($bad.Status -ceq 'FAILED' -and $bad.InvocationCount -eq 0 -and $bad.Pages.Count -eq 0 -and $bad.Words.Count -eq 0) "$kind must reject before OCR"
            }
            $mismatch=Join-Path $scratch 'kor.traineddata';[IO.File]::WriteAllBytes($mismatch,[byte[]]@(1))
            foreach($case in @(@{Executable=$mismatch;ModelPath=$ModelPath;Code='ENGINE_HASH_MISMATCH'},@{Executable=$Executable;ModelPath=$mismatch;Code='MODEL_HASH_MISMATCH'})){
                $bad=Invoke-P43R3aTesseractBatch -Executable $case.Executable -ModelPath $case.ModelPath -Crops $crops -Psm 6
                Require ($bad.Code -ceq $case.Code -and $bad.InvocationCount -eq 0) 'Exact supply is mandatory'
            }
            foreach($case in @(@('version','ENGINE_VERSION_MISMATCH'),@('timeout','BATCH_PROCESS_TIMEOUT'),@('exit','BATCH_EXIT_FAILED'),@('oversized','BATCH_PROCESS_OUTPUT_LIMIT'),@('missing','BATCH_PAGE_MAPPING_INVALID'),@('empty','BATCH_REQUIRED_PAGE_EMPTY'))){
                $script:batchMode=$case[0]
                $bad=Invoke-P43R3aTesseractBatch -Executable $Executable -ModelPath $ModelPath -Crops $crops -Psm 6
                Require ($bad.Status -ceq 'FAILED' -and $bad.Code -ceq $case[1] -and $bad.Pages.Count -eq 0 -and $bad.Words.Count -eq 0 -and $bad.InvocationCount -eq $(if($case[0] -ceq 'version'){0}else{1})) "Fail closed: $($case[0]), got $($bad.Code)"
                Require (-not [IO.File]::Exists($script:listPath)) 'Failure cleans list scratch'
            }
            $forged=[pscustomobject]@{Crops=$crops}
            $blocked=Invoke-P43R3aGateB -PreparedFixture $forged -Executable $Executable -ModelPath $ModelPath
            Require ($blocked.Status -ceq 'GATE_B_BATCH_MAPPING_NOT_EVALUATED' -and $blocked.Batches.Count -eq 0) 'Gate A authority required before Gate B'
            Write-Host 'BatchMapping synthetic controls PASS; real OCR invocations=0 (process seam)'
        }finally{Set-Item Function:Invoke-InternalP43R3aProcess $originalProcess}
        if($RunRealGateB){
            $prepared=Prepare-P43R3aFixture -PdfPath (Join-Path $PSScriptRoot '../p4-3a-ocr/fixtures/gray.pdf') -ArtifactDirectory (Join-Path $scratch 'gray')
            $real=Invoke-P43R3aGateB -PreparedFixture $prepared -Executable $Executable -ModelPath $ModelPath
            Write-Host ("Real Gray: GateA={0}, GateB={1}, Code={2}; prepare counts={3}/{4}/{5}/{6}/{7}" -f (Invoke-P43R3aGateA $prepared),$real.Status,$real.Code,$prepared.PdfOpenCount,$prepared.PageReadCount,$prepared.ImageDecodeCount,$prepared.GridBuildCount,$prepared.CropBuildCount)
            foreach($batch in $real.Batches){
                Write-Host ("PSM{0}: Status={1}, Code={2}, invocations={3}, pages={4}, words={5}, elapsedMs={6}, page/ordinal/CellId={7}" -f $batch.Psm,$batch.Status,$batch.Code,$batch.InvocationCount,$batch.Pages.Count,$batch.Words.Count,$batch.ElapsedMilliseconds,(@($batch.Pages | ForEach-Object {"$($_.Page)/$($_.CropOrdinal)/$($_.CellId)"}) -join ','))
            }
            Require ($real.Status -ceq 'GATE_B_BATCH_MAPPING_PASS') "Real Gate B failed: $($real.Code)"
            Write-Host 'BatchMapping PASS: synthetic controls and actual exact-runtime Gray Gate B PASS'
        }else{Write-Host 'Real Gate B NOT_RUN in this invocation; synthetic PASS does not establish real mapping'}
    }finally{[IO.Directory]::Delete($scratch,$true)}
    return
}
foreach($name in @('Get-P43R3aPnmDescriptor','New-P43R3aCellCropSet','Prepare-P43R3aFixture','Invoke-P43R3aGateA')){
    Require ($null -ne (Get-Command $name -ErrorAction SilentlyContinue)) "Missing crop function: $name"
}
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('milimap-p43r3a-crop-test-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($scratch)
try{
    $cells=@(for($id=1;$id -le 12;$id++){
        $row=[int][Math]::Floor(($id-1)/4)+1;$column=($id-1)%4+1
        [pscustomobject]@{CellId=[string]$id;Row=$row;Column=$column;X0=($column-1)*2;Y0=($row-1)*2;X1=$column*2;Y1=$row*2;Text='must not affect filenames'}
    })
    foreach($magic in @('P5','P6')){
        $components=if($magic -ceq 'P5'){1}else{3}
        $path=Join-Path $scratch "$magic.pnm"
        [byte[]]$header=[Text.Encoding]::ASCII.GetBytes("$magic`n8 6`n255`n")
        [byte[]]$pixels=0..(48*$components-1)
        [IO.File]::WriteAllBytes($path,[byte[]]($header+$pixels))
        $hash=(Get-FileHash $path).Hash.ToLowerInvariant()
        $descriptor=Get-P43R3aPnmDescriptor -Path $path -ExpectedSha256 $hash
        Require ($descriptor.Magic -ceq $magic -and $descriptor.Width -eq 8 -and $descriptor.Height -eq 6 -and $descriptor.Components -eq $components -and $descriptor.HeaderLength -eq 11 -and $descriptor.PixelByteLength -eq 48*$components -and $descriptor.SourceSha256 -ceq $hash) "$magic exact descriptor"
        Reject {Get-P43R3aPnmDescriptor -Path $path -ExpectedSha256 ('0'*64)} 'SOURCE_PIXEL_HASH_MISMATCH'
        $first=New-P43R3aCellCropSet -ImagePath $path -ImageSha256 $hash -Cells @($cells | Sort-Object CellId -Descending) -OutputDirectory (Join-Path $scratch "$magic-first")
        $second=New-P43R3aCellCropSet -ImagePath $path -ImageSha256 $hash -Cells $cells -OutputDirectory (Join-Path $scratch "$magic-second")
        Require ($first.Status -ceq 'COMPLETE' -and $null -eq $first.Code -and $first.Policy -ceq 'PROVEN_CELL_CROP_V1' -and $first.CropBuildCount -eq 1 -and $first.Crops.Count -eq 12 -and $first.SourcePixelSha256 -ceq $hash) "$magic crop set"
        Require (($first.Crops.CropSha256 -join ',') -ceq ($second.Crops.CropSha256 -join ',')) "$magic repeat deterministic"
        $stringCells=@($cells | ForEach-Object {
            $copy=$_.PSObject.Copy()
            foreach($field in @('Row','Column','X0','Y0','X1','Y1')){$copy.$field=[string]$copy.$field}
            $copy
        })
        $stringSet=New-P43R3aCellCropSet -ImagePath $path -ImageSha256 $hash -Cells $stringCells -OutputDirectory (Join-Path $scratch "$magic-strings")
        Require ($stringSet.Status -ceq 'COMPLETE' -and ($stringSet.Crops.CropSha256 -join ',') -ceq ($first.Crops.CropSha256 -join ',')) 'Integer coordinate strings must retain numeric row arithmetic'
        $collisionDirectory=Join-Path $scratch "$magic-collision"
        [void][IO.Directory]::CreateDirectory($collisionDirectory)
        $collision=Join-Path $collisionDirectory ([IO.Path]::GetFileName($first.Crops[11].ArtifactPath))
        [IO.File]::WriteAllBytes($collision,[byte[]]@(7,8,9))
        $collided=New-P43R3aCellCropSet -ImagePath $path -ImageSha256 $hash -Cells $cells -OutputDirectory $collisionDirectory
        Require ($collided.Status -ceq 'FAILED' -and $collided.Code -ceq 'CROP_ARTIFACT_ALREADY_EXISTS' -and @(Get-ChildItem -LiteralPath $collisionDirectory -File).Count -eq 1 -and [Convert]::ToBase64String([IO.File]::ReadAllBytes($collision)) -ceq 'BwgJ') 'Existing crop collision must reject before any output writes and preserve bytes'
        $expected=if($components -eq 1){@(@(0,1,8,9),@(18,19,26,27),@(38,39,46,47))}else{@(@(0,1,2,3,4,5,24,25,26,27,28,29),@(54,55,56,57,58,59,78,79,80,81,82,83),@(114,115,116,117,118,119,138,139,140,141,142,143))}
        $ids=@(1,6,12)
        for($i=0;$i -lt 3;$i++){
            $crop=$first.Crops[$ids[$i]-1]
            [byte[]]$want=[byte[]]([Text.Encoding]::ASCII.GetBytes("$magic`n2 2`n255`n")+[byte[]]$expected[$i])
            Require ([Convert]::ToBase64String([IO.File]::ReadAllBytes($crop.ArtifactPath)) -ceq [Convert]::ToBase64String($want)) "$magic literal rectangle $($ids[$i]) exclusive ends/top origin"
        }
        foreach($crop in $first.Crops){
            Require ($crop.Ordinal -eq [int]$crop.CellId -and [IO.Path]::GetFileName($crop.ArtifactPath) -ceq ('crop-{0:D2}-cell-{1}.{2}' -f $crop.Ordinal,$crop.CellId,$(if($components -eq 1){'pgm'}else{'ppm'}))) 'Order/name must derive from proven ordinal/CellId'
        }
        foreach($mutation in @(@{X1=0},@{X0=-1},@{X1=9},@{Y1=7},@{Y1=-1},@{X0=0.5})){
            $invalid=@($cells | ForEach-Object {$copy=$_.PSObject.Copy();$copy})
            foreach($key in $mutation.Keys){$invalid[0].$key=$mutation[$key]}
            $bad=New-P43R3aCellCropSet -ImagePath $path -ImageSha256 $hash -Cells $invalid -OutputDirectory (Join-Path $scratch 'invalid')
            Require ($bad.Status -ceq 'FAILED' -and $bad.Crops.Count -eq 0 -and -not (Test-Path (Join-Path $scratch 'invalid'))) 'Invalid rectangle fails before writes'
        }
        foreach($kind in @('duplicate-id','duplicate-position','missing-id','missing-cell','extra-cell')){
            $invalid=@($cells | ForEach-Object {$_.PSObject.Copy()})
            switch($kind){
                'duplicate-id' {$invalid[1].CellId='1'}
                'duplicate-position' {$invalid[1].Column=1}
                'missing-id' {$invalid[11].CellId='13'}
                'missing-cell' {$invalid=$invalid[0..10]}
                'extra-cell' {$invalid+= $invalid[0].PSObject.Copy()}
            }
            $bad=New-P43R3aCellCropSet -ImagePath $path -ImageSha256 $hash -Cells $invalid -OutputDirectory (Join-Path $scratch 'invalid')
            Require ($bad.Status -ceq 'FAILED' -and $bad.Crops.Count -eq 0) "$kind must fail closed"
        }
        $bad=New-P43R3aCellCropSet -ImagePath $path -ImageSha256 ('0'*64) -Cells $cells -OutputDirectory (Join-Path $scratch 'invalid')
        Require ($bad.Status -ceq 'FAILED' -and $bad.Code -ceq 'SOURCE_PIXEL_HASH_MISMATCH' -and $bad.CropBuildCount -eq 0) 'Crop source SHA mismatch fails before build'
    }
    foreach($content in @("P5`n#comment`n8 6`n255`n","P5`r`n8 6`r`n255`r`n","P5`n8 6`n254`n","P5`n08 6`n255`n","P5`n8 6`n255`n")){
        $path=Join-Path $scratch 'malformed.pnm';[IO.File]::WriteAllBytes($path,[Text.Encoding]::ASCII.GetBytes($content))
        Reject {Get-P43R3aPnmDescriptor -Path $path -ExpectedSha256 (Get-FileHash $path).Hash.ToLowerInvariant()} 'PNM_INVALID'
    }
    $wide=Join-Path $scratch 'wide.pgm'
    [IO.File]::WriteAllBytes($wide,[byte[]]([Text.Encoding]::ASCII.GetBytes("P5`n16 6`n255`n")+[byte[]](0..95)))
    $wideCells=@($cells | ForEach-Object {
        [pscustomobject]@{CellId=$_.CellId;Row=[string]$_.Row;Column=[string]$_.Column;X0=[string]($_.X0*2);X1=[string]($_.X1*2);Y0=[string]$_.Y0;Y1=[string]$_.Y1}
    })
    $wideSet=New-P43R3aCellCropSet -ImagePath $wide -ImageSha256 (Get-FileHash $wide).Hash.ToLowerInvariant() -Cells $wideCells -OutputDirectory (Join-Path $scratch 'wide')
    Require ($wideSet.Status -ceq 'COMPLETE') 'Multi-digit integer strings must be compared numerically'
    [byte[]]$wideWant=[byte[]]([Text.Encoding]::ASCII.GetBytes("P5`n4 2`n255`n")+[byte[]]@(8,9,10,11,24,25,26,27))
    Require ([Convert]::ToBase64String([IO.File]::ReadAllBytes($wideSet.Crops[2].ArtifactPath)) -ceq [Convert]::ToBase64String($wideWant)) 'Multi-digit coordinate strings copy exact numeric rectangle'
    $manifest=Get-Content (Join-Path $PSScriptRoot '../p4-3a-ocr/fixtures/manifest.json') -Raw | ConvertFrom-Json
    foreach($name in @('gray','rgb')){
        $prepared=Prepare-P43R3aFixture -PdfPath (Join-Path $PSScriptRoot "../p4-3a-ocr/fixtures/$name.pdf") -ArtifactDirectory (Join-Path $scratch $name)
        $originalCrops=$prepared.Crops
        $authority=@($manifest.fixtures | Where-Object name -CEQ $name)[0]
        Require ($prepared.FixtureHash -ceq $authority.sha256 -and $prepared.SourcePixelSha256 -ceq $authority.expectedPixelHashes[0]) "$name retained authority"
        Require ($prepared.PdfOpenCount -eq 1 -and $prepared.PageReadCount -eq 1 -and $prepared.ImageDecodeCount -eq 1 -and $prepared.GridBuildCount -eq 1 -and $prepared.CropBuildCount -eq 1 -and $prepared.Cells.Count -eq 12 -and $prepared.Crops.Count -eq 12) "$name prepare once"
        Require ((Invoke-P43R3aGateA -PreparedFixture $prepared) -ceq 'GATE_A_CROP_PROVENANCE_PASS') "$name Gate A"
        $repeat=New-P43R3aCellCropSet -ImagePath $prepared.SourceImagePath -ImageSha256 $prepared.SourcePixelSha256 -Cells $prepared.Cells -OutputDirectory (Join-Path $scratch "$name-repeat")
        Require (($repeat.Crops.CropSha256 -join ',') -ceq ($prepared.Crops.CropSha256 -join ',')) "$name real crop deterministic"
        $forged=$prepared.PSObject.Copy()
        Require ((Invoke-P43R3aGateA -PreparedFixture $forged) -ceq 'GATE_A_CROP_PROVENANCE_FAILED') 'Cloned/self-authored prepared object is not helper authority'
        $prepared.Crops[0].X0++
        Require ((Invoke-P43R3aGateA -PreparedFixture $prepared) -ceq 'GATE_A_CROP_PROVENANCE_FAILED') 'Crop rectangle mutation rejects'
        $prepared.Crops[0].X0--
        $prepared.Cells[0].X0++
        Require ((Invoke-P43R3aGateA -PreparedFixture $prepared) -ceq 'GATE_A_CROP_PROVENANCE_FAILED') 'Proven cells cannot be re-authored'
        $prepared.Cells[0].X0--
        $prepared.CropBuildCount=2
        Require ((Invoke-P43R3aGateA -PreparedFixture $prepared) -ceq 'GATE_A_CROP_PROVENANCE_FAILED') 'Count mutation rejects'
        $prepared.CropBuildCount=1
        $prepared.Crops=$prepared.Crops[0..10]
        Require ((Invoke-P43R3aGateA -PreparedFixture $prepared) -ceq 'GATE_A_CROP_PROVENANCE_FAILED') 'Gate crop count mismatch rejects'
        $prepared.Crops=@($repeat.Crops)
        Require ((Invoke-P43R3aGateA -PreparedFixture $prepared) -ceq 'GATE_A_CROP_PROVENANCE_FAILED') 'Replacement artifacts lack original authority'
        $prepared.Crops=$originalCrops
        [IO.File]::WriteAllBytes($prepared.Crops[0].ArtifactPath,[byte[]]@(0))
        $prepared.Crops[0].CropSha256=(Get-FileHash $prepared.Crops[0].ArtifactPath).Hash.ToLowerInvariant()
        Require ((Invoke-P43R3aGateA -PreparedFixture $prepared) -ceq 'GATE_A_CROP_PROVENANCE_FAILED') 'Crop bytes plus self-authored SHA cannot replace authority'
        Write-Host "$name PASS: PDF open=$($prepared.PdfOpenCount), page read=$($prepared.PageReadCount), decode=$($prepared.ImageDecodeCount), grid=$($prepared.GridBuildCount), crop build=$($prepared.CropBuildCount), cells=12, crops=12"
    }
    foreach($name in @('multi-image','borderless','merged')){
        $code=if($name -ceq 'multi-image'){'IMAGE_NOT_ELIGIBLE'}else{'REQUIRED_GRID_NOT_COMPLETE'}
        Reject {Prepare-P43R3aFixture -PdfPath (Join-Path $PSScriptRoot "../p4-3a-ocr/fixtures/$name.pdf") -ArtifactDirectory (Join-Path $scratch "$name-rejected")} $code
        Require (-not (Test-Path (Join-Path $scratch "$name-rejected/crops"))) "$name preparation must not create crops"
    }
    $root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
    $protected=@('tools/data/evaluation/p4-3a-ocr','tools/data/evaluation/p4-3a2-ocr','tools/data/evaluation/p4-3-redesign2-ocr','tools/data/pdf-native','tools/data/lib','data/canonical','data/seed','apps')
    $diff=@(& git -C $root diff --name-only 625f888c703ed74541df2fd13420354dc67be736 -- @protected)
    Require ($LASTEXITCODE -eq 0 -and $diff.Count -eq 0) 'Historical/protected diff must remain zero'
    $untracked=@(& git -C $root ls-files --others --exclude-standard -- @protected)
    Require ($LASTEXITCODE -eq 0 -and $untracked.Count -eq 0) 'Historical/protected paths must have no untracked files'
    Write-Host 'CropProvenance PASS; historical/protected diff=0; OCR invocations=0'
}finally{[IO.Directory]::Delete($scratch,$true)}

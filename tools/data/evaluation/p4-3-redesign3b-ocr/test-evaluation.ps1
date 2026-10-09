param([ValidateSet('ModelSupply','BestBatch','GrayFidelity')][string]$Group='ModelSupply',
    [Alias('TesseractExecutable')][string]$Executable,[Alias('KoreanModelPath')][string]$ModelPath,
    [switch]$RunRealGateB1,[string]$ArtifactDirectory,[string]$ObservedResultPath)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Require($Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Reject([scriptblock]$Action,[string]$Code){
    try{& $Action | Out-Null}catch{Require ($_.Exception.Message -ceq $Code) "Expected $Code, got $($_.Exception.Message)";return}
    throw "Expected rejection: $Code"
}
$supply=Join-Path $PSScriptRoot 'model-supply.ps1'
Require (Test-Path -LiteralPath $supply) 'FAIL: Redesign 3B model supply functions do not exist'
. $supply
if($Group -ceq 'GrayFidelity'){
    $runner=Join-Path $PSScriptRoot 'run-evaluation.ps1'
    Require (Test-Path -LiteralPath $runner) 'FAIL: Redesign 3B Gray fidelity gate does not exist'
    . $runner
    function Assert-GrayEvidence($Cycle){
        Require ($Cycle.ProductionAction -ceq 'NONE' -and $Cycle.RgbInvocationCount -eq 0 -and $Cycle.ConsensusInvocationCount -eq 0 -and $Cycle.DegradedInvocationCount -eq 0) 'Task 3 cannot invoke any later gate'
        Require ($Cycle.GateB2 -like 'NOT_RUN_*' -and $Cycle.GateC -like 'NOT_RUN_*' -and $Cycle.GateD -like 'NOT_RUN_*') 'Later gates must remain blocked'
        if($null -eq $Cycle.GateB1){Require ($Cycle.QualityInvocationCount -eq 0 -and $Cycle.Verdict -ceq 'P4_3_REDESIGN3B_NOT_EVALUATED') 'Unavailable Gate A cannot fabricate Gray evidence';return}
        $gate=$Cycle.GateB1
        Require ($gate.QualityInvocationCount -eq $Cycle.QualityInvocationCount -and $gate.GrayPreparationCount -eq 1 -and $gate.PreparationCounts.Count -eq 1) 'One Gray preparation and accurate first-cycle counts'
        $counts=$gate.PreparationCounts[0]
        Require ($counts.PdfOpenCount -eq 1 -and $counts.PageReadCount -eq 1 -and $counts.ImageDecodeCount -eq 1 -and $counts.GridBuildCount -eq 1 -and $counts.CropBuildCount -eq 1 -and $counts.CropCount -eq 12) 'Gray preparation opens/reads/decodes/builds once and retains twelve crops'
        $complete=$gate.Runs.Count -eq 4 -and $gate.Determinism.Count -eq 2
        $failed=@($gate.Runs | Where-Object {$_.Batch.Status -cne 'COMPLETE' -or $_.Fidelity.Status -cne 'PASS' -or $_.Fidelity.MandatoryMatchCount -ne 8}).Count -gt 0 -or @($gate.Determinism | Where-Object {-not $_.WordsIdentical -or -not $_.TextsIdentical -or -not $_.FidelityIdentical -or -not $_.DiagnosticsIdentical}).Count -gt 0
        if($failed){Require ($gate.Status -ceq 'GATE_B1_CLEAR_GRAY_FIDELITY_FAILED' -and $Cycle.Verdict -ceq 'P4_3_REDESIGN3B_REJECTED') 'Observed Gray failure must reject even after supply loss'}
        elseif($complete){Require ($gate.Status -ceq 'GATE_B1_CLEAR_GRAY_FIDELITY_PASS' -and $Cycle.Verdict -ceq 'P4_3_REDESIGN3B_NOT_EVALUATED') 'Gray PASS alone cannot claim later-gate acceptance'}
        else{Require ($gate.Status -ceq 'GATE_B1_CLEAR_GRAY_FIDELITY_NOT_EVALUATED' -and $Cycle.Verdict -ceq 'P4_3_REDESIGN3B_NOT_EVALUATED') 'Incomplete unfailed matrix remains not evaluated'}
        if($complete){
            Require ($gate.QualityInvocationCount -eq 4) 'Completed Gray matrix uses exactly four quality batches'
            Require (($gate.Runs.Psm -join ',') -ceq '6,6,11,11' -and ($gate.Runs.Repetition -join ',') -ceq '1,2,1,2') 'Observed matrix retains the fixed order and repetitions'
        }
    }
    $originalBatch=${function:Invoke-P43R3bTesseractBatch};$originalPrepare=${function:Prepare-P43R3aFixture};$originalProvenance=${function:Invoke-P43R3aGateA}
    $originalAuthority=(Get-Command Assert-P43R3bModelAuthority).ScriptBlock;$originalGateA=(Get-Command Invoke-P43R3bGateA).ScriptBlock
    $truth=Get-P43R3aFixtureGroundTruth
    $authored=@('업체명','주소','전화번호','혜택','가상 가람 식당','가상시 가람로 12','031-123-4567','시험 할인 10%','가상 누리 식당','가상시 누리로 23','031-234-5678',"시험 할인 20%`n방문 시 적용")
    $prepared=[pscustomobject]@{FixtureHash=$truth.FixtureHashes['gray.pdf'];Crops=@(1..12 | ForEach-Object {[pscustomobject]@{Ordinal=$_;CellId=[string]$_}});PdfOpenCount=1;PageReadCount=1;ImageDecodeCount=1;GridBuildCount=1;CropBuildCount=1}
    $descriptor=[pscustomobject]@{Status='VERIFIED'}
    function Prepare-P43R3aFixture {param($PdfPath,$ArtifactDirectory) $script:grayPreparations++;return $prepared}
    function Invoke-P43R3aGateA {param($PreparedFixture) 'GATE_A_CROP_PROVENANCE_PASS'}
    function Assert-P43R3bModelAuthority {param($Descriptor,$Executable) Require ([object]::ReferenceEquals($Descriptor,$descriptor)) 'Exact issued descriptor forwarded'}
    function Invoke-P43R3bGateA {param($Executable,$ModelPath) [pscustomobject]@{Status=$(if($script:grayMode -ceq 'gate-a-unavailable'){'GATE_A_MODEL_SUPPLY_NOT_EVALUATED'}else{'GATE_A_MODEL_SUPPLY_PASS'});Code=$null;Descriptor=$descriptor;Runtime=$null;QualityInvocationCount=0;ProductionAction='NONE'}}
    # Only the external batch is controlled; real reconstruction, truth authority,
    # fidelity and orchestration decide every verdict below.
    function Invoke-P43R3bTesseractBatch {
        param($Executable,$ModelDescriptor,$Crops,$Psm)
        Require ($Executable -ceq 'test-exe' -and [object]::ReferenceEquals($ModelDescriptor,$descriptor)) 'Forward exact engine and model proof'
        Require ($Psm -eq $(if($script:grayCalls -lt 2){6}else{11}) -and $Crops.Count -eq 12) 'PSM6 twice then PSM11 twice; all Gray crops'
        for($i=0;$i -lt 12;$i++){Require ([object]::ReferenceEquals($Crops[$i],$prepared.Crops[$i])) 'Reuse original prepared crops'}
        $script:grayCalls++
        if($script:grayMode -like '*-then-exception' -and $script:grayCalls -eq $(if($script:grayMode -ceq 'nondeterministic-then-exception'){3}else{2})){throw [IO.IOException]::new('Synthetic batch cleanup failed')}
        $lost=$script:grayMode -ceq 'unavailable' -or ($script:grayMode -like '*-then-unavailable' -and $script:grayCalls -eq $(if($script:grayMode -ceq 'nondeterministic-then-unavailable'){3}else{2}))
        $batchFailed=$script:grayMode -cin @('batch-failed-then-unavailable','batch-failed-then-exception') -and $script:grayCalls -eq 1
        if($lost -or $batchFailed){return [pscustomobject]@{Status='FAILED';Code=$(if($lost){'MODEL_BYTES_CHANGED'}else{'BATCH_PAGE_MAPPING_INVALID'});Psm=$Psm;InvocationCount=$(if($lost){0}else{1});Pages=@();Words=@();Diagnostics=@();ElapsedMilliseconds=0;ProductionAction='NONE'}}
        $words=@(for($i=0;$i -lt 12;$i++){
            $text=$authored[$i]
            if($i -eq 0 -and (($script:grayMode -ceq 'psm6-mismatch' -and $Psm -eq 6) -or ($script:grayMode -ceq 'psm11-mismatch' -and $Psm -eq 11) -or $script:grayMode -cin @('mismatch-then-unavailable','mismatch-then-exception'))){$text='업체'}
            if($i -eq 5 -and $script:grayCalls -eq 2 -and $script:grayMode -like 'nondeterministic*'){$text='다른 주소'}
            $word=[pscustomobject]@{Page=$i+1;CropOrdinal=$i+1;CellId=[string]($i+1);Block=1;Paragraph=1;Line=1;Word=1;Left=0;Top=0;Width=20;Height=10;Text=$text;Confidence=1}
            $word
            if($i -eq 0 -and $script:grayMode -cin @('mandatory-partial','partial-then-unavailable','partial-then-exception')){$copy=$word.PSObject.Copy();$copy.Word=2;$copy}
        })
        [pscustomobject]@{Status='COMPLETE';Code=$null;Psm=$Psm;InvocationCount=1;Pages=@(1..12 | ForEach-Object {[pscustomobject]@{Page=$_;CropOrdinal=$_;CellId=[string]$_;Width=400;Height=150;WordCount=1}});Words=$words;Diagnostics=@();ElapsedMilliseconds=$script:grayCalls;ProductionAction='NONE'}
    }
    try{
        foreach($mode in @('batch-failed-then-exception','mismatch-then-exception','partial-then-exception','nondeterministic-then-exception','exact-then-exception')){
            foreach($entry in @('direct','first-cycle')){
                $script:grayMode=$mode;$script:grayCalls=0;$script:grayPreparations=0
                if($entry -ceq 'direct'){
                    try{$gate=Invoke-P43R3bGateB1 -GrayPrepared $prepared -Executable 'test-exe' -ModelDescriptor $descriptor}
                    catch{throw "Direct Gray boundary exception must preserve observations instead of escaping: $($_.Exception.Message)"}
                }else{
                    $cycle=Invoke-P43R3bFirstCycle -Executable 'test-exe' -ModelPath 'test-model' -ArtifactDirectory 'test-artifacts'
                    Require ($null -ne $cycle.GateB1) 'First-cycle boundary exception must retain evolving B1 evidence'
                    Assert-GrayEvidence $cycle
                    $gate=$cycle.GateB1
                    Require ($cycle.TotalOcrInvocationCount -eq $gate.QualityInvocationCount -and $script:grayPreparations -eq 1) 'Exception cannot erase first-cycle observed counts or reprepare'
                }
                $observed=if($mode -ceq 'nondeterministic-then-exception'){2}else{1}
                Require ($gate.Runs.Count -eq $observed -and $gate.QualityInvocationCount -eq $observed -and $script:grayCalls -eq $observed+1) 'Boundary exception retains earlier runs and counts without retries'
                Require ($gate.Code -ceq 'BATCH_BOUNDARY_EXCEPTION' -and $gate.AbortDiagnostic.ExceptionType -ceq 'System.IO.IOException' -and $gate.AbortDiagnostic.Message -ceq 'Synthetic batch cleanup failed' -and -not $gate.AbortDiagnostic.InvocationCountKnown) 'Unexpected boundary error remains explicit; throwing call count is not guessed'
                if($mode -ceq 'exact-then-exception'){Require ($gate.Status -ceq 'GATE_B1_CLEAR_GRAY_FIDELITY_NOT_EVALUATED' -and $gate.Verdict -ceq 'P4_3_REDESIGN3B_NOT_EVALUATED') 'One exact observation cannot pass an interrupted matrix'}
                else{Require ($gate.Status -ceq 'GATE_B1_CLEAR_GRAY_FIDELITY_FAILED' -and $gate.Verdict -ceq 'P4_3_REDESIGN3B_REJECTED' -and $null -ne $gate.FirstFailure) 'Earlier disqualifying observation and first failure remain rejected'}
                if($mode -ceq 'batch-failed-then-exception'){Require ($gate.FirstFailure.Code -ceq 'BATCH_PAGE_MAPPING_INVALID' -and $gate.Runs[0].Batch.Code -ceq 'BATCH_PAGE_MAPPING_INVALID') 'Later exception cannot erase the first batch failure'}
                if($mode -ceq 'mismatch-then-exception'){Require ($gate.Runs[0].Fidelity.MandatoryMatchCount -eq 7) 'Keep observed mandatory mismatch'}
                if($mode -ceq 'partial-then-exception'){Require ($gate.Runs[0].CellTexts[0].Status -ceq 'PARTIAL') 'Keep observed mandatory incompleteness'}
                if($mode -ceq 'nondeterministic-then-exception'){Require ($gate.Determinism.Count -eq 1 -and -not $gate.Determinism[0].WordsIdentical) 'Keep observed repeat nondeterminism'}
                Write-Host "Gray exception $mode $entry PASS: $($gate.Status), observedQuality=$observed, throwingCount=unknown, downstream=0"
            }
        }
        foreach($mode in @('exact','psm6-mismatch','psm11-mismatch','mandatory-partial','nondeterministic','unavailable','gate-a-unavailable','batch-failed-then-unavailable','mismatch-then-unavailable','partial-then-unavailable','nondeterministic-then-unavailable','exact-then-unavailable')){
            $script:grayMode=$mode;$script:grayCalls=0;$script:grayPreparations=0
            $cycle=Invoke-P43R3bFirstCycle -Executable 'test-exe' -ModelPath 'test-model' -ArtifactDirectory 'test-artifacts'
            Assert-GrayEvidence $cycle
            if($mode -ceq 'gate-a-unavailable'){Require ($script:grayPreparations -eq 0 -and $script:grayCalls -eq 0) 'Supply must precede preparation and quality';continue}
            Require ($script:grayPreparations -eq 1) 'Prepare Gray once only'
            if($mode -cin @('exact','psm6-mismatch','psm11-mismatch','mandatory-partial','nondeterministic')){Require ($cycle.GateB1.Runs.Count -eq 4 -and $script:grayCalls -eq 4) 'Four completed observations without retry'}
            if($mode -ceq 'exact'){Require ($cycle.GateB1.Status -ceq 'GATE_B1_CLEAR_GRAY_FIDELITY_PASS' -and @($cycle.GateB1.Runs | Where-Object {$_.Fidelity.MandatoryMatchCount -ne 8 -or $_.Fidelity.AllCellMatchCount -ne 12}).Count -eq 0) 'Both independent PSMs match 8 mandatory and 12 total cells'}
            if($mode -like 'psm*-mismatch'){Require ($cycle.GateB1.Status -ceq 'GATE_B1_CLEAR_GRAY_FIDELITY_FAILED' -and @($cycle.GateB1.Runs | Where-Object {$_.Fidelity.MandatoryMatchCount -eq 7}).Count -eq 2) 'Either independent PSM with 7/8 must reject'}
            if($mode -ceq 'mandatory-partial'){Require ($cycle.GateB1.Runs[0].Fidelity.Status -ceq 'NOT_EVALUATED' -and $cycle.GateB1.Runs[0].CellTexts[0].Status -ceq 'PARTIAL' -and $cycle.GateB1.Status -ceq 'GATE_B1_CLEAR_GRAY_FIDELITY_FAILED') 'Observed mandatory PARTIAL/NOT_EVALUATED rejects'}
            if($mode -like 'nondeterministic*'){Require (-not $cycle.GateB1.Determinism[0].WordsIdentical -and -not $cycle.GateB1.Determinism[0].TextsIdentical -and $cycle.GateB1.Status -ceq 'GATE_B1_CLEAR_GRAY_FIDELITY_FAILED') 'Auxiliary repeat difference rejects, including subsequent supply loss'}
            if($mode -ceq 'unavailable'){Require ($cycle.GateB1.Runs.Count -eq 0 -and $cycle.QualityInvocationCount -eq 0) 'No observed quality remains not evaluated'}
            if($mode -like '*-then-unavailable'){Require ($cycle.GateB1.Code -ceq 'MODEL_BYTES_CHANGED' -and $cycle.GateB1.Runs.Count -eq $(if($mode -ceq 'nondeterministic-then-unavailable'){2}else{1})) 'Supply abort preserves all prior observations'}
            Write-Host "Gray control $mode PASS: $($cycle.GateB1.Status), quality=$($cycle.QualityInvocationCount), downstream=0"
        }
        # Exercise the existing comparison independently on each evidence axis.
        # The baselines come from real historical reconstruction/fidelity once;
        # controlled stage outputs then prevent a changed axis from altering
        # the other three. All batch calls here are test-only, never processes.
        $script:grayMode='exact';$script:grayCalls=0
        $comparisonBatch=Invoke-P43R3bTesseractBatch -Executable 'test-exe' -ModelDescriptor $descriptor -Crops $prepared.Crops -Psm 6
        $comparisonTexts=@(ConvertTo-P43R3aCellTexts $comparisonBatch)
        $comparisonFidelity=Evaluate-P43R3aFidelity 'gray.pdf' $prepared.FixtureHash 6 $comparisonTexts
        $comparison3bBatch=${function:Invoke-P43R3bTesseractBatch};$comparison3aBatch=${function:Invoke-P43R3aTesseractBatch}
        $comparisonConvert=${function:ConvertTo-P43R3aCellTexts};$comparisonEvaluate=${function:Evaluate-P43R3aFidelity}
        $parityRgb=$prepared.PSObject.Copy();$parityRgb.FixtureHash=$truth.FixtureHashes['rgb.pdf']
        function New-ComparisonBatch([int]$Psm,[int]$Repetition){
            $batch=$comparisonBatch | ConvertTo-Json -Depth 12 | ConvertFrom-Json
            $batch.Psm=$Psm;$batch.ElapsedMilliseconds=7
            if($Repetition -eq 2 -and $script:comparisonMode -ceq 'words-only'){$batch.Words[0].Block=2}
            if($Repetition -eq 2 -and $script:comparisonMode -ceq 'elapsed-only'){$batch.ElapsedMilliseconds=11}
            $batch | Add-Member -NotePropertyName TestRepetition -NotePropertyValue $Repetition
            return $batch
        }
        function Invoke-P43R3bTesseractBatch {
            param($Executable,$ModelDescriptor,$Crops,$Psm)
            Require ($Executable -ceq 'test-exe' -and [object]::ReferenceEquals($ModelDescriptor,$descriptor) -and $Crops.Count -eq 12) 'Comparison-only 3B controlled boundary'
            $script:comparison3bCalls++;New-ComparisonBatch $Psm (($script:comparison3bCalls-1)%2+1)
        }
        function Invoke-P43R3aTesseractBatch {
            param($Executable,$ModelPath,$Crops,$Psm)
            Require ($Executable -ceq 'test-exe' -and $ModelPath -ceq 'test-model' -and $Crops.Count -eq 12) 'Historical parity uses only synthetic batch evidence'
            $script:comparison3aCalls++;New-ComparisonBatch $Psm (($script:comparison3aCalls-1)%2+1)
        }
        function ConvertTo-P43R3aCellTexts {
            param($BatchResult)
            $script:comparisonRepetition=$BatchResult.TestRepetition
            $texts=@($comparisonTexts | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
            if($script:comparisonRepetition -eq 2 -and $script:comparisonMode -ceq 'texts-only'){$texts[0].Text='업체명 '}
            if($script:comparisonRepetition -eq 2 -and $script:comparisonMode -ceq 'diagnostics-only'){$texts[0].Diagnostics=@([pscustomobject]@{Code='SAFE_ADJACENT';CellId='1'})}
            return $texts
        }
        function Evaluate-P43R3aFidelity {
            param($Fixture,$FixtureHash,$Psm,$CellTexts)
            $fidelity=$comparisonFidelity | ConvertTo-Json -Depth 12 | ConvertFrom-Json
            $fidelity.Fixture=$Fixture;$fidelity.Psm=$Psm
            foreach($cell in $fidelity.Cells){$cell.Fixture=$Fixture;$cell.Psm=$Psm}
            if($script:comparisonRepetition -eq 2 -and $script:comparisonMode -ceq 'fidelity-only'){$fidelity.Cells[0].NormalizedActual='independent fidelity change'}
            return $fidelity
        }
        try{
            foreach($case in @(
                @{Mode='all-same';Want=@($true,$true,$true,$true);Status='GATE_B1_CLEAR_GRAY_FIDELITY_PASS'},
                @{Mode='words-only';Want=@($false,$true,$true,$true);Status='GATE_B1_CLEAR_GRAY_FIDELITY_FAILED'},
                @{Mode='texts-only';Want=@($true,$false,$true,$true);Status='GATE_B1_CLEAR_GRAY_FIDELITY_FAILED'},
                @{Mode='fidelity-only';Want=@($true,$true,$false,$true);Status='GATE_B1_CLEAR_GRAY_FIDELITY_FAILED'},
                @{Mode='diagnostics-only';Want=@($true,$true,$true,$false);Status='GATE_B1_CLEAR_GRAY_FIDELITY_FAILED'},
                @{Mode='elapsed-only';Want=@($true,$true,$true,$true);Status='GATE_B1_CLEAR_GRAY_FIDELITY_PASS'}
            )){
                $script:comparisonMode=$case.Mode;$script:comparison3bCalls=0;$script:comparison3aCalls=0
                $gate=Invoke-P43R3bGateB1 -GrayPrepared $prepared -Executable 'test-exe' -ModelDescriptor $descriptor
                $historical=Invoke-P43R3aGateC -GrayPrepared $prepared -RgbPrepared $parityRgb -Executable 'test-exe' -ModelPath 'test-model'
                Require ($gate.Status -ceq $case.Status -and $gate.QualityInvocationCount -eq 4 -and $script:comparison3bCalls -eq 4 -and $script:comparison3aCalls -eq 8) 'Comparison contract decides each isolated axis with bounded synthetic batches'
                for($i=0;$i -lt 2;$i++){
                    $actual=$gate.Determinism[$i]
                    Require ($actual.WordsIdentical -eq $case.Want[0] -and $actual.TextsIdentical -eq $case.Want[1] -and $actual.FidelityIdentical -eq $case.Want[2] -and $actual.DiagnosticsIdentical -eq $case.Want[3]) "Independent comparison axis contract: $($case.Mode) PSM$($actual.Psm)"
                    $prior=@($historical.Determinism | Where-Object {$_.Fixture -ceq 'gray.pdf' -and $_.Psm -eq $actual.Psm})
                    Require ($prior.Count -eq 1 -and $prior[0].WordsIdentical -eq $actual.WordsIdentical -and $prior[0].TextsIdentical -eq $actual.TextsIdentical -and $prior[0].FidelityIdentical -eq $actual.FidelityIdentical -and $prior[0].DiagnosticsIdentical -eq $actual.DiagnosticsIdentical) 'Read-only historical comparison parity on the same synthetic evidence'
                }
                if($case.Mode -ceq 'elapsed-only'){Require ($gate.Runs[0].Batch.ElapsedMilliseconds -eq 7 -and $gate.Runs[1].Batch.ElapsedMilliseconds -eq 11) 'Elapsed difference really exists and remains outside the comparison'}
                Write-Host "Determinism contract $($case.Mode) PASS: words/texts/fidelity/diagnostics=$($case.Want -join '/'); both PSMs historical3A parity PASS; actual quality OCR calls=0"
            }
        }finally{
            Set-Item Function:Invoke-P43R3bTesseractBatch $comparison3bBatch;Set-Item Function:Invoke-P43R3aTesseractBatch $comparison3aBatch
            Set-Item Function:ConvertTo-P43R3aCellTexts $comparisonConvert;Set-Item Function:Evaluate-P43R3aFidelity $comparisonEvaluate
        }
    }finally{
        Set-Item Function:Invoke-P43R3bTesseractBatch $originalBatch;Set-Item Function:Prepare-P43R3aFixture $originalPrepare;Set-Item Function:Invoke-P43R3aGateA $originalProvenance
        Set-Item Function:Assert-P43R3bModelAuthority $originalAuthority;Set-Item Function:Invoke-P43R3bGateA $originalGateA
    }
    Require ($null -ne (Get-Command Invoke-P43R3bGateA -ErrorAction SilentlyContinue) -and $null -ne (Get-Command Assert-P43R3bModelAuthority -ErrorAction SilentlyContinue)) 'Real supply functions must survive synthetic seam restoration'
    Write-Host 'GrayFidelity synthetic assertions PASS; actual quality OCR calls=0'
    if($ObservedResultPath){$observed=Get-Content -LiteralPath $ObservedResultPath -Raw | ConvertFrom-Json;Assert-GrayEvidence $observed;Write-Host "GrayFidelity observed assertions PASS: $($observed.Verdict) / $($observed.GateB1.Status)"}
    if($RunRealGateB1){
        Require ($Executable -and $ModelPath -and $ArtifactDirectory -and -not $ObservedResultPath) 'Actual first measurement requires supplied engine/model and fresh external artifact directory'
        $repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))+[IO.Path]::DirectorySeparatorChar
        Require ([IO.Path]::IsPathFullyQualified($ArtifactDirectory) -and -not ([IO.Path]::GetFullPath($ArtifactDirectory)+[IO.Path]::DirectorySeparatorChar).StartsWith($repository,[StringComparison]::OrdinalIgnoreCase)) 'Actual crops and raw output must stay outside the repository'
        Require (-not (Test-Path -LiteralPath $ArtifactDirectory)) 'Actual measurement artifact directory already exists; replay is not authorized'
        [void][IO.Directory]::CreateDirectory($ArtifactDirectory)
        $originalProcess=${function:Invoke-InternalP43R3aProcess};$script:grayRawOrdinal=0;$script:grayPhysicalCalls=0;$script:grayVersionCalls=0
        function Invoke-InternalP43R3aProcess {
            param($Executable,$Arguments,$DeadlineMilliseconds)
            if($Arguments[0] -ceq '--version'){$script:grayVersionCalls++}
            else{$script:grayPhysicalCalls++;Require ($script:grayPhysicalCalls -le 4) 'Actual Gray quality budget exceeded'}
            $output=& $originalProcess -Executable $Executable -Arguments $Arguments -DeadlineMilliseconds $DeadlineMilliseconds
            if($Arguments[0] -cne '--version'){
                $script:grayRawOrdinal++
                [IO.File]::WriteAllText((Join-Path $ArtifactDirectory "batch-$script:grayRawOrdinal.tsv"),$output.Text,[Text.UTF8Encoding]::new($false))
                [IO.File]::WriteAllText((Join-Path $ArtifactDirectory "batch-$script:grayRawOrdinal.stderr.txt"),$output.ErrorText,[Text.UTF8Encoding]::new($false))
            }
            return $output
        }
        try{$actual=Invoke-P43R3bFirstCycle -Executable $Executable -ModelPath $ModelPath -ArtifactDirectory $ArtifactDirectory}
        finally{Set-Item Function:Invoke-InternalP43R3aProcess $originalProcess}
        $actual | Add-Member -NotePropertyName PhysicalQualityInvocationCount -NotePropertyValue $script:grayPhysicalCalls
        $actual | Add-Member -NotePropertyName VersionProbeCount -NotePropertyValue $script:grayVersionCalls
        $resultPath=Join-Path $ArtifactDirectory 'first-cycle.json'
        [IO.File]::WriteAllText($resultPath,($actual | ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
        Write-Host ('Frozen Gate A: '+($actual.GateA | ConvertTo-Json -Depth 8 -Compress))
        if($null -ne $actual.GateB1){foreach($run in @($actual.GateB1.Runs)){
            Write-Host "Gray PSM$($run.Psm) repeat$($run.Repetition): batch=$($run.Batch.Status) mandatory=$($run.Fidelity.MandatoryMatchCount)/8 all=$($run.Fidelity.AllCellMatchCount)/12 fidelity=$($run.Fidelity.Status) words=$($run.Batch.Words.Count) elapsedMs=$($run.Batch.ElapsedMilliseconds)"
            foreach($cell in @($run.Fidelity.Cells | Where-Object Status -CNE 'FIDELITY_MATCH')){Write-Host ('Nonmatch: '+($cell | ConvertTo-Json -Depth 8 -Compress))}
        }
        Write-Host ('Determinism: '+($actual.GateB1.Determinism | ConvertTo-Json -Compress))
        Write-Host ('Preparation: '+($actual.GateB1.PreparationCounts | ConvertTo-Json -Compress))
        Write-Host "Gate B1=$($actual.GateB1.Status)"}
        Write-Host "First cycle=$($actual.Verdict) returnedQuality=$($actual.QualityInvocationCount) physicalQuality=$script:grayPhysicalCalls versionProbes=$script:grayVersionCalls downstream=0"
        Require ($actual.QualityInvocationCount -eq $script:grayPhysicalCalls) 'Physical and reported quality counts must agree'
        Assert-GrayEvidence $actual
        Write-Host "GrayFidelity first measurement assertions PASS; result=$resultPath"
    }
    return
}
if($Group -ceq 'BestBatch'){
    $batch=Join-Path $PSScriptRoot 'invoke-tesseract-best-batch.ps1'
    Require (Test-Path -LiteralPath $batch) 'FAIL: Redesign 3B best-model batch boundary does not exist'
    . $batch
    $originalProcess=(Get-Command Invoke-InternalP43R3aProcess).ScriptBlock
    $scratch=Join-Path ([IO.Path]::GetTempPath()) ('milimap-p43r3b-batch-test-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($scratch)
    $script:bestCalls=0;$script:bestVersions=0;$script:bestMode='valid';$script:bestList=$null
    function New-BestTestTsv([int]$Count){
        $rows=[Collections.Generic.List[string]]::new()
        $rows.Add("level`tpage_num`tblock_num`tpar_num`tline_num`tword_num`tleft`ttop`twidth`theight`tconf`ttext")
        for($page=1;$page -le $Count;$page++){
            foreach($row in @("1`t$page`t0`t0`t0`t0`t0`t0`t2`t2`t-1`t","2`t$page`t1`t0`t0`t0`t0`t0`t2`t2`t-1`t","3`t$page`t1`t1`t0`t0`t0`t0`t2`t2`t-1`t","4`t$page`t1`t1`t1`t0`t0`t0`t2`t2`t-1`t","5`t$page`t1`t1`t1`t1`t0`t0`t1`t1`t0`t가","5`t$page`t1`t1`t1`t2`t1`t1`t1`t1`t100`t나")){$rows.Add($row)}
        }
        return $rows -join "`n"
    }
    function Assert-BestFailure($Result,[string]$Code,[int]$Calls){
        Require ($Result.Status -ceq 'FAILED' -and $Result.Code -ceq $Code -and $Result.InvocationCount -eq $Calls -and $Result.Pages.Count -eq 0 -and $Result.Words.Count -eq 0 -and $Result.ProductionAction -ceq 'NONE' -and $Result.Diagnostics.Count -eq 1 -and $Result.Diagnostics[0].Code -ceq $Code) "Best batch must fail closed: expected $Code/$Calls, got $($Result.Code)/$($Result.InvocationCount)"
    }
    # The real bounded process is delegated only for version probes. Quality OCR
    # is intercepted after real authority/model/runtime/crop validation.
    function Invoke-InternalP43R3aProcess {
        param([string]$Executable,[string[]]$Arguments,[int]$DeadlineMilliseconds)
        if($Arguments.Count -eq 1 -and $Arguments[0] -ceq '--version'){
            $script:bestVersions++
            return & $originalProcess -Executable $Executable -Arguments $Arguments -DeadlineMilliseconds $DeadlineMilliseconds
        }
        $script:bestCalls++;$script:bestList=$Arguments[0]
        Require ([IO.Path]::GetFullPath($Executable) -ceq $script:bestExecutable -and $DeadlineMilliseconds -eq 10000) 'Pinned engine and deadline are required'
        $images=[IO.File]::ReadAllLines($script:bestList)
        Require (($images -join '|') -ceq $script:bestPaths) 'Image list must contain only ordinal-ordered crop paths'
        Require (($Arguments[1..($Arguments.Count-1)] -join '|') -ceq ('stdout|--tessdata-dir|'+$script:bestModelDirectory+'|-l|kor|--oem|1|--psm|'+$script:bestPsm+'|--dpi|300|-c|tessedit_create_tsv=1')) 'Exact Korean OEM1 batch configuration required'
        Require (-not (($Arguments -join '|')+($images -join '|')).Contains('EXPECTED_TEXT_SECRET')) 'Expected text must never enter OCR inputs'
        if($script:bestMode -ceq 'timeout'){throw 'BATCH_PROCESS_TIMEOUT'}
        if($script:bestMode -ceq 'process-output-limit'){throw 'BATCH_PROCESS_OUTPUT_LIMIT'}
        $text=New-BestTestTsv $script:bestPageCount;$errorText=''
        switch($script:bestMode){
            'malformed' {$text=$text.Replace('level','invalid')}
            'missing' {$text=$text.Replace("1`t2`t0`t0`t0`t0`t0`t0`t2`t2`t-1`t`n",'')}
            'duplicate' {$text+="`n1`t1`t0`t0`t0`t0`t0`t0`t2`t2`t-1`t"}
            'extra' {$text=New-BestTestTsv ($script:bestPageCount+1)}
            'empty' {$text=($text -split "`n" | Where-Object {$_ -cnotmatch '^5\t2\t'}) -join "`n"}
            'dimensions' {$text=$text.Replace("1`t1`t0`t0`t0`t0`t0`t0`t2`t2`t-1`t","1`t1`t0`t0`t0`t0`t0`t0`t3`t2`t-1`t")}
            'stdout-limit' {$text='x'*1048577}
            'stderr-limit' {$errorText='x'*65537}
        }
        [pscustomobject]@{ExitCode=$(if($script:bestMode -ceq 'exit'){1}else{0});Text=$text;ErrorText=$errorText;ElapsedMilliseconds=7}
    }
    try{
        $unauthorized=[pscustomobject]@{Status='VERIFIED';Sha256='f888d4038348a0c3d25151e7f452bda0d74ca275b18cab146798bcbb94084fff'}
        foreach($psm in @(0,3,4,7,12)){
            try{Invoke-P43R3bTesseractBatch -Executable 'absent' -ModelDescriptor $unauthorized -Crops @() -Psm $psm | Out-Null;throw 'Invalid PSM accepted'}catch{Require ($_.Exception.Message -like '*ValidateSet*' -or $_.Exception.Message -like '*6,11*') "PSM $psm must reject at API boundary"}
        }
        Assert-BestFailure (Invoke-P43R3bTesseractBatch -Executable 'absent' -ModelDescriptor $unauthorized -Crops @() -Psm 6) 'MODEL_AUTHORITY_REQUIRED' 0
        Require ($script:bestCalls -eq 0 -and $script:bestVersions -eq 0) 'Invalid authority cannot probe or invoke OCR'
        if(-not $Executable -and -not $ModelPath){Write-Host 'BestBatch no-supply controls PASS; real authority/process-seam matrix=NOT_RUN_NO_SUPPLY; actual quality OCR calls=0';return}
        Require ($Executable -and $ModelPath) 'BestBatch authority matrix requires both executable and model paths'
        $localModelDirectory=Join-Path $scratch 'tessdata';[void][IO.Directory]::CreateDirectory($localModelDirectory)
        $localModel=Join-Path $localModelDirectory 'kor.traineddata';[IO.File]::Copy($ModelPath,$localModel)
        $gate=Invoke-P43R3bGateA -Executable $Executable -ModelPath $localModel
        Require ($gate.Status -ceq 'GATE_A_MODEL_SUPPLY_PASS' -and $gate.Descriptor.Sha256 -ceq 'f888d4038348a0c3d25151e7f452bda0d74ca275b18cab146798bcbb94084fff' -and $script:bestVersions -eq 1 -and $script:bestCalls -eq 0) 'Only real Gate A can authorize the unchanged best bytes'
        . $batch
        $script:bestExecutable=[IO.Path]::GetFullPath($Executable);$script:bestModelDirectory=$localModelDirectory
        $crops=@(for($id=1;$id -le 12;$id++){
            $path=Join-Path $scratch "crop-$id.pgm"
            [IO.File]::WriteAllBytes($path,[byte[]]([Text.Encoding]::ASCII.GetBytes("P5`n2 2`n255`n")+[byte[]]@(0,1,2,3)))
            [pscustomobject]@{Ordinal=$id;CellId="cell-$id";ArtifactPath=$path;CropSha256=(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant();Width=2;Height=2;ExpectedText='EXPECTED_TEXT_SECRET'}
        })
        foreach($count in @(1,2,12)){
            $subset=@($crops | Select-Object -First $count)
            $script:bestPaths=$subset.ArtifactPath -join '|';$script:bestPageCount=$count
            foreach($psm in @(6,11)){
                $script:bestPsm=$psm;$before=$script:bestCalls
                $result=Invoke-P43R3bTesseractBatch -Executable $Executable -ModelDescriptor $gate.Descriptor -Crops @($subset | Sort-Object Ordinal -Descending) -Psm $psm
                Require ($result.Status -ceq 'COMPLETE' -and $null -eq $result.Code -and $result.Psm -eq $psm -and $result.InvocationCount -eq 1 -and $result.Pages.Count -eq $count -and $result.Words.Count -eq 2*$count -and $script:bestCalls -eq $before+1 -and $result.Diagnostics.Count -eq 0 -and $result.ElapsedMilliseconds -eq 7 -and $result.ProductionAction -ceq 'NONE') "PSM$psm $count-page batch must publish one complete batch: $($result.Code)"
                Require ($result.EngineVersion -ceq '5.5.3' -and $result.EngineBuild -ceq 'tesseract v5.5.3.20260724' -and $result.ModelSha256 -ceq 'f888d4038348a0c3d25151e7f452bda0d74ca275b18cab146798bcbb94084fff') 'Best batch preserves verified engine/model identity'
                Require (($result.Pages.Page -join ',') -ceq ((1..$count) -join ',') -and ($result.Pages.CropOrdinal -join ',') -ceq ((1..$count) -join ',') -and ($result.Pages.CellId -join ',') -ceq ($subset.CellId -join ',') -and $result.Words[-1].CropOrdinal -eq $count -and $result.Words[-1].CellId -ceq "cell-$count" -and $result.Words[0].Text -ceq '가' -and $result.Words[0].Confidence -eq 0) 'Pages and words map exactly to 1..N without confidence filtering'
                for($page=1;$page -le $count;$page++){
                    $mappedWords=@($result.Words | Where-Object Page -EQ $page)
                    Require ($mappedWords.Count -eq 2 -and @($mappedWords | Where-Object {$_.CropOrdinal -ne $page -or $_.CellId -cne "cell-$page"}).Count -eq 0) 'Every word must retain its page/ordinal/CellId mapping'
                }
                Require (-not [IO.File]::Exists($script:bestList)) 'Success must clean image-list scratch'
            }
        }
        $script:bestPsm=6;$script:bestPageCount=2;$subset=@($crops[0..1]);$script:bestPaths=$subset.ArtifactPath -join '|'
        foreach($descriptor in @((Get-P43R3bModelDescriptor $localModel),($gate.Descriptor | ConvertTo-Json | ConvertFrom-Json),$unauthorized)){
            Assert-BestFailure (Invoke-P43R3bTesseractBatch -Executable $Executable -ModelDescriptor $descriptor -Crops $subset -Psm 6) 'MODEL_AUTHORITY_REQUIRED' 0
        }
        $sha=$gate.Descriptor.Sha256;$gate.Descriptor.Sha256='6b85e11d9bbf07863b97b3523b1b112844c43e713df8b66418a081fd1060b3b2'
        Assert-BestFailure (Invoke-P43R3bTesseractBatch -Executable $Executable -ModelDescriptor $gate.Descriptor -Crops $subset -Psm 6) 'MODEL_DESCRIPTOR_CHANGED' 0
        $gate.Descriptor.Sha256=$sha
        $frozen=$gate.Descriptor.FrozenAtUtc;$gate.Descriptor.FrozenAtUtc=$null
        Assert-BestFailure (Invoke-P43R3bTesseractBatch -Executable $Executable -ModelDescriptor $gate.Descriptor -Crops $subset -Psm 6) 'MODEL_DESCRIPTOR_CHANGED' 0
        $gate.Descriptor.FrozenAtUtc=$frozen
        Assert-BestFailure (Invoke-P43R3bTesseractBatch -Executable 'different-executable' -ModelDescriptor $gate.Descriptor -Crops $subset -Psm 6) 'MODEL_AUTHORITY_PATH_MISMATCH' 0
        foreach($kind in @('zero','extra','ordinal','gap','cell-id','blank-id','relative-path','newline-path','crop-hash','width','malformed-pnm')){
            $badCrops=@($crops | ForEach-Object {$_.PSObject.Copy()});$code='BATCH_CROP_IDENTITY_INVALID'
            switch($kind){
                'zero' {$badCrops=@()}
                'extra' {$badCrops+=$badCrops[0].PSObject.Copy()}
                'ordinal' {$badCrops[0].Ordinal=2}
                'gap' {$badCrops[11].Ordinal=13}
                'cell-id' {$badCrops[0].CellId='cell-2'}
                'blank-id' {$badCrops[0].CellId=' '}
                'relative-path' {$badCrops[0].ArtifactPath='relative.pgm'}
                'newline-path' {$badCrops[0].ArtifactPath+="`n"}
                'crop-hash' {$badCrops[0].CropSha256='0'*64;$code='SOURCE_PIXEL_HASH_MISMATCH'}
                'width' {$badCrops[0].Width=3}
                'malformed-pnm' {
                    $badPnm=Join-Path $scratch 'malformed.pgm';[IO.File]::WriteAllBytes($badPnm,[byte[]]@(1,2,3))
                    $badCrops[0].ArtifactPath=$badPnm;$badCrops[0].CropSha256=(Get-FileHash -LiteralPath $badPnm).Hash.ToLowerInvariant();$code='PNM_INVALID'
                }
            }
            Assert-BestFailure (Invoke-P43R3bTesseractBatch -Executable $Executable -ModelDescriptor $gate.Descriptor -Crops $badCrops -Psm 6) $code 0
        }
        foreach($case in @(@('timeout','BATCH_PROCESS_TIMEOUT'),@('process-output-limit','BATCH_PROCESS_OUTPUT_LIMIT'),@('exit','BATCH_EXIT_FAILED'),@('stdout-limit','BATCH_PROCESS_OUTPUT_LIMIT'),@('stderr-limit','BATCH_PROCESS_OUTPUT_LIMIT'),@('malformed','BATCH_TSV_INVALID'),@('missing','BATCH_PAGE_MAPPING_INVALID'),@('duplicate','BATCH_PAGE_MAPPING_INVALID'),@('extra','BATCH_PAGE_MAPPING_INVALID'),@('empty','BATCH_REQUIRED_PAGE_EMPTY'),@('dimensions','BATCH_PAGE_MAPPING_INVALID'))){
            $script:bestMode=$case[0];$before=$script:bestCalls
            Assert-BestFailure (Invoke-P43R3bTesseractBatch -Executable $Executable -ModelDescriptor $gate.Descriptor -Crops $subset -Psm 6) $case[1] 1
            Require ($script:bestCalls -eq $before+1 -and -not [IO.File]::Exists($script:bestList)) 'Failed batch cannot retry and must clean scratch'
        }
        $script:bestMode='valid';$before=$script:bestCalls
        # Mutate only a scratch copy during real crop validation, after the first
        # authority check. The immediately-before-process guard must catch it.
        $originalPnm=(Get-Command Get-P43R3aPnmDescriptor).ScriptBlock
        $script:bestMutated=$false
        function Get-P43R3aPnmDescriptor {
            param([string]$Path,[string]$ExpectedSha256)
            $descriptor=& $originalPnm -Path $Path -ExpectedSha256 $ExpectedSha256
            if(-not $script:bestMutated){
                $stream=[IO.File]::Open($localModel,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite)
                try{$value=$stream.ReadByte();$stream.Position=0;$stream.WriteByte($value -bxor 1)}finally{$stream.Dispose()}
                $script:bestMutated=$true
            }
            return $descriptor
        }
        try{
            Assert-BestFailure (Invoke-P43R3bTesseractBatch -Executable $Executable -ModelDescriptor $gate.Descriptor -Crops $subset -Psm 6) 'MODEL_BYTES_CHANGED' 0
            Require ($script:bestMutated -and $script:bestCalls -eq $before) 'Late model mutation must be rejected before the process seam'
        }finally{Set-Item Function:Get-P43R3aPnmDescriptor $originalPnm}
        # The next invocation must independently revalidate the already-changed bytes.
        Assert-BestFailure (Invoke-P43R3bTesseractBatch -Executable $Executable -ModelDescriptor $gate.Descriptor -Crops $subset -Psm 6) 'MODEL_BYTES_CHANGED' 0
        $badModel=Get-P43R3bModelDescriptor $localModel
        Require ($badModel.Code -ceq 'MODEL_BLOB_MISMATCH' -and $script:bestCalls -eq $before) 'Changed best bytes must fail pinned Git blob before quality invocation'
        [IO.File]::WriteAllBytes($localModel,[byte[]]@(1))
        Assert-BestFailure (Invoke-P43R3bTesseractBatch -Executable $Executable -ModelDescriptor $gate.Descriptor -Crops $subset -Psm 6) 'MODEL_BYTES_CHANGED' 0
        [IO.File]::Delete($localModel)
        Assert-BestFailure (Invoke-P43R3bTesseractBatch -Executable $Executable -ModelDescriptor $gate.Descriptor -Crops $subset -Psm 6) 'MODEL_BYTES_CHANGED' 0
        Require ($script:bestCalls -eq 17 -and $script:bestVersions -eq 1) 'Six success and eleven failure seams; no probes/retries/fallback outside Gate A'
        Write-Host 'BestBatch real-authority synthetic matrix PASS: success batches=6; fail-closed process batches=11; intercepted batch calls=17; version probes=1; actual quality OCR calls=0'
    }finally{Set-Item Function:Invoke-InternalP43R3aProcess $originalProcess;[IO.Directory]::Delete($scratch,$true)}
    return
}
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('milimap-p43r3b-supply-test-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($scratch)
try{
    $fixture=Join-Path $scratch 'fixture.bin'
    [IO.File]::WriteAllBytes($fixture,[Text.Encoding]::ASCII.GetBytes("hello`n"))
    Require ((Get-P43R3bGitBlobSha1 $fixture) -ceq 'ce013625030ba8dba906f756967f9e9ca394464a') 'Git blob must include the exact byte-length header and NUL'
    [IO.File]::WriteAllBytes($fixture,[byte[]]@())
    Require ((Get-P43R3bGitBlobSha1 $fixture) -ceq 'e69de29bb2d1d6434b8b29ae775ad8c2e48c5391') 'Empty Git blob identity must be exact'
    $candidate=Join-Path $scratch 'kor.traineddata'
    foreach($case in @(
        @{Path=$candidate;Code='MODEL_MISSING';Bytes=$null},
        @{Path=(Join-Path $scratch 'Kor.traineddata');Code='MODEL_FILENAME_MISMATCH';Bytes=[byte[]]@(1)},
        @{Path=$candidate;Code='MODEL_SIZE_MISMATCH';Bytes=[byte[]]@(1)},
        @{Path=$candidate;Code='MODEL_BLOB_MISMATCH';Bytes=[byte[]]::new(12528128)}
    )){
        if($null -ne $case.Bytes){[IO.File]::WriteAllBytes($case.Path,$case.Bytes)}
        $bad=Get-P43R3bModelDescriptor $case.Path
        Require ($bad.Status -ceq 'NOT_EVALUATED' -and $bad.Code -ceq $case.Code -and $null -eq $bad.Sha256 -and $null -eq $bad.FrozenAtUtc) "Invalid supply must stop before SHA256 freeze: $($case.Code)"
        $gate=Invoke-P43R3bGateA -Executable 'absent-executable' -ModelPath $case.Path
        Require ($gate.Status -ceq 'GATE_A_MODEL_SUPPLY_NOT_EVALUATED' -and $gate.Code -ceq $case.Code -and $gate.QualityInvocationCount -eq 0) 'Model identity must precede runtime or OCR'
    }
    Reject {Assert-P43R3bModelAuthority -Descriptor ([pscustomobject]@{Status='VERIFIED';Sha256='caller-authored'}) -Executable 'missing' -ModelPath $candidate} 'MODEL_AUTHORITY_REQUIRED'
    Write-Host 'ModelSupply synthetic controls PASS; quality OCR calls=0'
    if(-not $Executable -and -not $ModelPath){Write-Host 'Actual model/runtime authority=NOT_RUN_NO_SUPPLY';return}
    Require ($Executable -and $ModelPath) 'Real authority verification requires both executable and model paths'
    $descriptor=Get-P43R3bModelDescriptor $ModelPath
    Require ($descriptor.Status -ceq 'VERIFIED' -and $null -eq $descriptor.Code) 'The actual supplied candidate must prove independent blob identity'
    $expected=@{Filename='kor.traineddata';SizeBytes=12528128;GitBlobSha1='c82615b5228c9981c33a0985b32224d97b7fb43a';Sha256='f888d4038348a0c3d25151e7f452bda0d74ca275b18cab146798bcbb94084fff';SourceRepository='tesseract-ocr/tessdata_best';SourceTag='4.1.0';SourceTagObject='f0c187c74d3038e6d135fd080e30909af350eae0';SourceTagVerification='valid';SourceCommit='e2aad9b983032bb1beff9133104a67cdbb87ca4d';SourceTree='23d6207aa77e8f11abd8b300e12d2d94df300fb6';License='Apache-2.0'}
    foreach($field in $expected.Keys){Require ([string]$descriptor.$field -ceq [string]$expected[$field]) "Actual candidate descriptor mismatch: $field"}
    Require ($descriptor.Sha256 -cmatch '^[0-9a-f]{64}$' -and $descriptor.FrozenAtUtc -cmatch '^\d{4}-\d\d-\d\dT.*Z$') 'Successful blob validation must freeze lowercase SHA256 and UTC timestamp'
    Reject {Assert-P43R3bModelAuthority $descriptor $Executable $ModelPath} 'MODEL_AUTHORITY_REQUIRED'
    # Observe the real process boundary: only --version is allowed in this group.
    $originalProcess=(Get-Command Invoke-InternalP43R3aProcess).ScriptBlock
    $script:VersionCalls=0
    function Invoke-InternalP43R3aProcess {
        param([string]$Executable,[string[]]$Arguments,[int]$DeadlineMilliseconds)
        Require ($Arguments.Count -eq 1 -and $Arguments[0] -ceq '--version') 'Gate A attempted quality OCR'
        $script:VersionCalls++
        & $originalProcess -Executable $Executable -Arguments $Arguments -DeadlineMilliseconds $DeadlineMilliseconds
    }
    $gate=Invoke-P43R3bGateA $Executable $ModelPath
    Require ($gate.Status -ceq 'GATE_A_MODEL_SUPPLY_PASS' -and $null -eq $gate.Code -and $gate.QualityInvocationCount -eq 0 -and $script:VersionCalls -eq 1) 'Real Gate A must verify runtime without quality OCR'
    Require ($gate.Runtime.EngineVersion -ceq '5.5.3' -and $gate.Runtime.EngineBuild -ceq 'tesseract v5.5.3.20260724') 'Runtime version must remain the Redesign 3A identity'
    $hashes=@{'tesseract.exe'='c66f0f12ed76f6aa455dac97684bbc86756d6a732380bee09122454cfda3f420';'libtesseract-5.dll'='54d54528b453ce3a5ba79487687f8df43e7b194b9ea97beba74200453fe1fb46';'libleptonica-6.dll'='1869b44e3d46fd830620b042477e5d60a950779582f38f60291547efb27792f1'}
    foreach($name in $hashes.Keys){Require ($gate.Runtime.Hashes[$name] -ceq $hashes[$name]) "Runtime hash differs: $name"}
    Assert-P43R3bModelAuthority $gate.Descriptor $Executable $ModelPath | Out-Null
    Require (-not (Get-Command Assert-P43R3bModelAuthority).Parameters['ModelPath'].Attributes.Where({$_ -is [Management.Automation.ParameterAttribute]}).Mandatory) 'FAIL: authority cannot yet resolve the verified model path without caller input'
    $resolved=Assert-P43R3bModelAuthority -Descriptor $gate.Descriptor -Executable $Executable
    Require ($resolved.ModelPath -ceq [IO.Path]::GetFullPath($ModelPath) -and $resolved.Executable -ceq [IO.Path]::GetFullPath($Executable)) 'Authority must resolve its verified model path without caller path input'
    Reject {Assert-P43R3bModelAuthority $gate.Descriptor $Executable $candidate} 'MODEL_AUTHORITY_PATH_MISMATCH'
    $copy=$gate.Descriptor | ConvertTo-Json | ConvertFrom-Json
    Reject {Assert-P43R3bModelAuthority $copy $Executable $ModelPath} 'MODEL_AUTHORITY_REQUIRED'
    $authored=[pscustomobject]@{};foreach($property in $gate.Descriptor.PSObject.Properties){$authored | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value}
    Reject {Assert-P43R3bModelAuthority $authored $Executable $ModelPath} 'MODEL_AUTHORITY_REQUIRED'
    $originalTag=$gate.Descriptor.SourceTag;$gate.Descriptor.SourceTag='forged'
    Reject {Assert-P43R3bModelAuthority $gate.Descriptor $Executable $ModelPath} 'MODEL_DESCRIPTOR_CHANGED'
    $gate.Descriptor.SourceTag=$originalTag
    $gate.Descriptor | Add-Member -MemberType ScriptProperty -Name SourceTag -Value {'4.1.0'} -Force
    Reject {Assert-P43R3bModelAuthority $gate.Descriptor $Executable $ModelPath} 'MODEL_DESCRIPTOR_CHANGED'
    $gate.Descriptor | Add-Member -NotePropertyName SourceTag -NotePropertyValue $originalTag -Force
    $gate.Descriptor | Add-Member -NotePropertyName Properties -NotePropertyValue $authored
    Reject {Assert-P43R3bModelAuthority $gate.Descriptor $Executable $ModelPath} 'MODEL_DESCRIPTOR_CHANGED'
    $local=Join-Path $scratch 'local';[void][IO.Directory]::CreateDirectory($local)
    $localModel=Join-Path $local 'kor.traineddata';[IO.File]::Copy($ModelPath,$localModel)
    $localGate=Invoke-P43R3bGateA $Executable $localModel
    Require ($localGate.Status -ceq 'GATE_A_MODEL_SUPPLY_PASS') 'A real unchanged candidate copy must be verified through Gate A'
    $stream=[IO.File]::Open($localModel,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite)
    try{$value=$stream.ReadByte();$stream.Position=0;$stream.WriteByte($value -bxor 1)}finally{$stream.Dispose()}
    Reject {Assert-P43R3bModelAuthority $localGate.Descriptor $Executable $localModel} 'MODEL_BYTES_CHANGED'
    $missingRuntime=Invoke-P43R3bGateA 'missing-executable' $ModelPath
    Require ($missingRuntime.Status -ceq 'GATE_A_MODEL_SUPPLY_NOT_EVALUATED' -and $missingRuntime.Code -ceq 'EXECUTABLE_MISSING') 'Valid model with absent runtime must remain not evaluated'
    $fakeExe=Join-Path $local 'tesseract.exe';[IO.File]::WriteAllBytes($fakeExe,[byte[]]@(1))
    $badRuntime=Invoke-P43R3bGateA $fakeExe $ModelPath
    Require ($badRuntime.Status -ceq 'GATE_A_MODEL_SUPPLY_NOT_EVALUATED' -and $badRuntime.Code -ceq 'ENGINE_HASH_MISMATCH') 'Wrong runtime bytes must fail before version or OCR'
    $runtimeDir=Join-Path $scratch 'runtime';[void][IO.Directory]::CreateDirectory($runtimeDir)
    # Preserve the version probe's transitive DLL dependencies in scratch only.
    foreach($source in [IO.Directory]::GetFiles([IO.Path]::GetDirectoryName($Executable),'*.dll')){[IO.File]::Copy($source,(Join-Path $runtimeDir ([IO.Path]::GetFileName($source))))}
    [IO.File]::Copy($Executable,(Join-Path $runtimeDir 'tesseract.exe'))
    $localExe=Join-Path $runtimeDir 'tesseract.exe'
    $runtimeGate=Invoke-P43R3bGateA $localExe $ModelPath
    Require ($runtimeGate.Status -ceq 'GATE_A_MODEL_SUPPLY_PASS') 'Unchanged copied runtime must be verified through Gate A'
    foreach($name in $hashes.Keys){
        $path=Join-Path $runtimeDir $name;$stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite)
        try{$original=$stream.ReadByte();$stream.Position=0;$stream.WriteByte($original -bxor 1)}finally{$stream.Dispose()}
        try{
            Reject {Assert-P43R3bModelAuthority $runtimeGate.Descriptor $localExe $ModelPath} 'ENGINE_HASH_MISMATCH'
            $altered=Invoke-P43R3bGateA $localExe $ModelPath
            Require ($altered.Status -ceq 'GATE_A_MODEL_SUPPLY_NOT_EVALUATED' -and $altered.Code -ceq 'ENGINE_HASH_MISMATCH') "Altered runtime must fail before version: $name"
        }finally{$stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Write);try{$stream.WriteByte($original)}finally{$stream.Dispose()}}
    }
    Require ($script:VersionCalls -eq 3) 'Only the three successful real-supply gates may probe versions'
    Write-Host 'ModelSupply real authority PASS: exact model/runtime, copied/authored/spoofed/mutated descriptors, changed paths/model/runtime bytes rejected; version probes=3; quality OCR calls=0'
}finally{[IO.Directory]::Delete($scratch,$true)}

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../p4-3-redesign3a-ocr/run-evaluation.ps1')
. (Join-Path $PSScriptRoot 'invoke-tesseract-best-batch.ps1')

function Invoke-P43R3bGateB1 {
    param([Parameter(Mandatory)][object]$GrayPrepared,[Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][object]$ModelDescriptor)
    $result=[pscustomobject]@{Status='GATE_B1_CLEAR_GRAY_FIDELITY_NOT_EVALUATED';Code=$null;Verdict='P4_3_REDESIGN3B_NOT_EVALUATED';Runs=@();QualityInvocationCount=0;GrayPreparationCount=0;PreparationCounts=@();Determinism=@();FirstFailure=$null;AbortDiagnostic=$null;Task4='BLOCKED';ProductionAction='NONE'}
    if((Invoke-P43R3aGateA $GrayPrepared) -cne 'GATE_A_CROP_PROVENANCE_PASS'){$result.Code='GATE_A_CROP_PROVENANCE_FAILED';return $result}
    try{
        $truth=Get-P43R3aFixtureGroundTruth
        if($GrayPrepared.FixtureHash -cne $truth.FixtureHashes['gray.pdf']){throw 'GROUND_TRUTH_FIXTURE_MISMATCH'}
    }catch{$result.Code=$_.Exception.Message;return $result}
    $result.GrayPreparationCount=1
    $result.PreparationCounts=@([pscustomobject]@{Fixture='gray.pdf';PdfOpenCount=$GrayPrepared.PdfOpenCount;PageReadCount=$GrayPrepared.PageReadCount;ImageDecodeCount=$GrayPrepared.ImageDecodeCount;GridBuildCount=$GrayPrepared.GridBuildCount;CropBuildCount=$GrayPrepared.CropBuildCount;CropCount=$GrayPrepared.Crops.Count})
    try{Assert-P43R3bModelAuthority -Descriptor $ModelDescriptor -Executable $Executable | Out-Null}catch{$result.Code=$_.Exception.Message;return $result}
    foreach($psm in @(6,11)){
        for($repeat=1;$repeat -le 2;$repeat++){
            try{$batch=Invoke-P43R3bTesseractBatch -Executable $Executable -ModelDescriptor $ModelDescriptor -Crops $GrayPrepared.Crops -Psm $psm}
            catch{
                # A throwing boundary (including its cleanup) has not returned an
                # invocation count. Keep known observations; report the unknown
                # throwing call explicitly instead of inventing zero or one.
                $result.Code='BATCH_BOUNDARY_EXCEPTION'
                $result.AbortDiagnostic=[pscustomobject]@{Code=$result.Code;Psm=$psm;Repetition=$repeat;ExceptionType=$_.Exception.GetType().FullName;Message=$_.Exception.Message;InvocationCountKnown=$false}
                return $result
            }
            $result.QualityInvocationCount+=$batch.InvocationCount
            # Supply loss aborts the matrix, but never erases prior rejection.
            if($batch.Status -cne 'COMPLETE' -and $batch.InvocationCount -eq 0){$result.Code=$batch.Code;return $result}
            $texts=@(ConvertTo-P43R3aCellTexts $batch)
            $fidelity=Evaluate-P43R3aFidelity 'gray.pdf' $GrayPrepared.FixtureHash $psm $texts
            $result.Runs+=[pscustomobject]@{Fixture='gray.pdf';Psm=$psm;Repetition=$repeat;Batch=$batch;CellTexts=$texts;Fidelity=$fidelity}
            if($batch.Status -cne 'COMPLETE' -or $fidelity.Status -cne 'PASS' -or $fidelity.MandatoryMatchCount -ne 8){
                $result.Status='GATE_B1_CLEAR_GRAY_FIDELITY_FAILED';$result.Verdict='P4_3_REDESIGN3B_REJECTED'
                if($null -eq $result.FirstFailure){$result.FirstFailure=[pscustomobject]@{Psm=$psm;Repetition=$repeat;Code=$(if($batch.Status -cne 'COMPLETE'){$batch.Code}else{'MANDATORY_FIDELITY_FAILED'})}}
            }
        }
        $runs=@($result.Runs | Where-Object Psm -EQ $psm)
        $words=($runs[0].Batch.Words | ConvertTo-Json -Depth 12 -Compress) -ceq ($runs[1].Batch.Words | ConvertTo-Json -Depth 12 -Compress)
        $texts=($runs[0].CellTexts | Select-Object CellId,Status,Text | ConvertTo-Json -Depth 12 -Compress) -ceq ($runs[1].CellTexts | Select-Object CellId,Status,Text | ConvertTo-Json -Depth 12 -Compress)
        $fidelity=($runs[0].Fidelity | ConvertTo-Json -Depth 12 -Compress) -ceq ($runs[1].Fidelity | ConvertTo-Json -Depth 12 -Compress)
        $firstDiagnostics=@($runs[0].Batch.Diagnostics)+@($runs[0].CellTexts | ForEach-Object {$_.Diagnostics})
        $secondDiagnostics=@($runs[1].Batch.Diagnostics)+@($runs[1].CellTexts | ForEach-Object {$_.Diagnostics})
        $diagnostics=($firstDiagnostics | ConvertTo-Json -Depth 12 -Compress) -ceq ($secondDiagnostics | ConvertTo-Json -Depth 12 -Compress)
        $result.Determinism+=[pscustomobject]@{Fixture='gray.pdf';Psm=$psm;WordsIdentical=$words;TextsIdentical=$texts;FidelityIdentical=$fidelity;DiagnosticsIdentical=$diagnostics}
        if(-not $words -or -not $texts -or -not $fidelity -or -not $diagnostics){
            $result.Status='GATE_B1_CLEAR_GRAY_FIDELITY_FAILED';$result.Verdict='P4_3_REDESIGN3B_REJECTED'
            if($null -eq $result.FirstFailure){$result.FirstFailure=[pscustomobject]@{Psm=$psm;Repetition=2;Code='REPEAT_NONDETERMINISTIC'}}
        }
    }
    if($result.Status -cne 'GATE_B1_CLEAR_GRAY_FIDELITY_FAILED'){
        $result.Status='GATE_B1_CLEAR_GRAY_FIDELITY_PASS';$result.Verdict=$result.Status;$result.Task4='READY'
    }
    return $result
}

function Invoke-P43R3bFirstCycle {
    param([Parameter(Mandatory)][string]$Executable,[Parameter(Mandatory)][string]$ModelPath,
        [Parameter(Mandatory)][string]$ArtifactDirectory)
    $result=[pscustomobject]@{GateA=$null;CropProvenance=$null;GateB1=$null;GateB2='NOT_RUN_GATE_A_NOT_EVALUATED';GateC='NOT_RUN_GATE_A_NOT_EVALUATED';GateD='NOT_RUN_GATE_A_NOT_EVALUATED';Verdict='P4_3_REDESIGN3B_NOT_EVALUATED';Code=$null;QualityInvocationCount=0;RgbInvocationCount=0;ConsensusInvocationCount=0;DegradedInvocationCount=0;TotalOcrInvocationCount=0;ProductionAction='NONE'}
    # Acquire and freeze reference authority before preparing any quality input.
    $result.GateA=Invoke-P43R3bGateA -Executable $Executable -ModelPath $ModelPath
    if($result.GateA.Status -cne 'GATE_A_MODEL_SUPPLY_PASS'){$result.Code=$result.GateA.Code;return $result}
    try{
        $gray=Prepare-P43R3aFixture -PdfPath (Join-Path $PSScriptRoot '../p4-3a-ocr/fixtures/gray.pdf') -ArtifactDirectory (Join-Path $ArtifactDirectory 'gray')
    }catch{$result.Code=$_.Exception.Message;$result.GateB2=$result.GateC=$result.GateD='NOT_RUN_GRAY_PREPARATION_FAILED';return $result}
    $result.CropProvenance=Invoke-P43R3aGateA $gray
    $result.GateB1=Invoke-P43R3bGateB1 -GrayPrepared $gray -Executable $Executable -ModelDescriptor $result.GateA.Descriptor
    $result.QualityInvocationCount=$result.GateB1.QualityInvocationCount
    $result.TotalOcrInvocationCount=$result.QualityInvocationCount
    $result.Code=$result.GateB1.Code
    if($result.GateB1.Status -ceq 'GATE_B1_CLEAR_GRAY_FIDELITY_FAILED'){
        $result.Verdict='P4_3_REDESIGN3B_REJECTED';$blocked='NOT_RUN_GATE_B1_FAILED'
    }elseif($result.GateB1.Status -ceq 'GATE_B1_CLEAR_GRAY_FIDELITY_NOT_EVALUATED'){$blocked='NOT_RUN_GATE_B1_NOT_EVALUATED'}
    else{$blocked='NOT_RUN_TASK4_NOT_IMPLEMENTED'}
    $result.GateB2=$result.GateC=$result.GateD=$blocked
    return $result
}

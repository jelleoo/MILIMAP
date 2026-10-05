Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'invoke-tesseract-eval.ps1')

function Get-P43a2CellMembership {
    param([object[]]$Cells,[object]$Word)
    $contained=@();$intersected=@()
    foreach($cell in $Cells){
        if($cell.Page -ne $Word.Page){continue}
        if($Word.Left -lt ($cell.Left+$cell.Width) -and ($Word.Left+$Word.Width) -gt $cell.Left -and $Word.Top -lt ($cell.Top+$cell.Height) -and ($Word.Top+$Word.Height) -gt $cell.Top){$intersected+=,$cell}
        if($Word.Width -gt 0 -and $Word.Height -gt 0 -and $Word.Left -ge $cell.Left -and $Word.Top -ge $cell.Top -and ($Word.Left+$Word.Width) -le ($cell.Left+$cell.Width) -and ($Word.Top+$Word.Height) -le ($cell.Top+$cell.Height)){$contained+=,$cell}
    }
    if($contained.Count -eq 1 -and $intersected.Count -eq 1){return [pscustomobject]@{Status='UNIQUE';CellId=$contained[0].CellId}}
    if($intersected.Count -gt 1 -or $contained.Count -gt 1){return [pscustomobject]@{Status='AMBIGUOUS'}}
    return [pscustomobject]@{Status='NONE'}
}

function Invoke-InternalP43a2AcceptanceProbe {
    param([string]$PdfPath,[string]$Executable,[string]$ModelPath,[int]$Psm,[double]$SameRegionRatio)
    $scratch=Join-Path ([IO.Path]::GetTempPath()) ('milimap-p43a2-probe-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($scratch)
    try{
        $dll=Join-Path $PSScriptRoot '../p4-3a-ocr/bin/Release/net8.0/Milimap.P4_3A.OcrEval.dll'
        $raw=& dotnet $dll inspect --input $PdfPath --artifact-dir $scratch
        $inspect=$raw | ConvertFrom-Json
        if($LASTEXITCODE -ne 0 -or $inspect.Status -ne 'ELIGIBLE' -or $inspect.Images.Count -ne 1){throw 'A2_IMAGE_NOT_ELIGIBLE'}
        $metadata=Join-Path $scratch 'inspect.json';[IO.File]::WriteAllText($metadata,$raw)
        $grid=& dotnet $dll grid --input $inspect.Images[0].ArtifactPath --metadata $metadata --page 1 --image 1 | ConvertFrom-Json
        if($LASTEXITCODE -ne 0 -or $grid.Status -ne 'COMPLETE'){throw 'A2_GRID_NOT_COMPLETE'}
        $cells=@($grid.Cells | ForEach-Object {[pscustomobject]@{Page=1;CellId=[string]$_.Id;Left=$_.X0;Top=$_.Y0;Width=$_.X1-$_.X0;Height=$_.Y1-$_.Y0;Row=$_.Row;Column=$_.Column}})
        $ocr=Invoke-P43a2TesseractEvaluation -Executable $Executable -ModelPath $ModelPath -Inputs @($inspect.Images[0].ArtifactPath) -Psm $Psm
        $evidence=New-P43a2OcrAcceptanceEvidence -Cells $cells -Ocr $ocr -SameRegionRatio $SameRegionRatio
        return [pscustomobject]@{Fixture=[IO.Path]::GetFileName($PdfPath);FixtureHash=(Get-FileHash -LiteralPath $PdfPath).Hash.ToLowerInvariant();Psm=$Psm;GridStatus=$grid.Status;
            PdfOpenCount=$inspect.OpenCount;PageReadCount=$inspect.PageReadCount;ImageDecodeCount=$inspect.ImageDecodeCount;GridBuildCount=1;OcrInvocationCount=$ocr.InvocationCount;
            EngineBuild=$ocr.EngineBuild;ModelSha256=$ocr.ModelSha256;WordCount=$ocr.Words.Count;Words=$ocr.Words;Thresholds=$evidence.Thresholds;
            OperationalStatus=$evidence.OperationalStatus;OperationalCode=$evidence.OperationalCode;AcceptanceStatus=$evidence.AcceptanceStatus;ConfidenceEvidence=$evidence.ConfidenceEvidence;
            OcrMilliseconds=$ocr.ElapsedMilliseconds;ProductionAction='NONE'}
    }finally{[IO.Directory]::Delete($scratch,$true)}
}

function New-P43a2OcrAcceptanceEvidence {
    param([object[]]$Cells,[object]$Ocr,[ValidateSet(0.25,0.50,0.75)][double]$SameRegionRatio)
    if($Ocr.Status -ne 'COMPLETE'){
        $code=if($Ocr.Code -eq 'P43A2_TSV_EMPTY_WORD_OUTPUT'){'EMPTY_WORD_OUTPUT'}else{$Ocr.Code}
        return [pscustomobject]@{OperationalStatus='FAILED';OperationalCode=$code;AcceptanceStatus='NOT_EVALUATED';ConfidenceEvidence='NOT_OBSERVED';Thresholds=@()}
    }
    if($Ocr.Words.Count -eq 0){throw 'A2_INCONSISTENT_COMPLETE_WITHOUT_WORDS'}
    # Required columns are authored fixture metadata, never OCR-derived table
    # inference: header row, business-name column1 and benefit column4.
    $requiredCells=@($Cells | Where-Object {$_.Row -eq 1 -or $_.Column -in @(1,4)} | Select-Object -ExpandProperty CellId)
    $thresholds=@(foreach($threshold in @(0,50,80,90,95)){
        $resolved=Resolve-P43a2OcrCells -Cells $Cells -Words $Ocr.Words -ConfidenceThreshold $threshold -SameRegionRatio $SameRegionRatio
        $coverage=$resolved.Status -eq 'COMPLETE' -and $resolved.CellText.Count -eq 12 -and @($resolved.CellText | Where-Object {[string]::IsNullOrWhiteSpace($_.Text)}).Count -eq 0
        $codes=@($resolved.Diagnostics | Where-Object Code -ne 'SAFE_ADJACENT' | Select-Object -ExpandProperty Code)
        $requiredLow=@($resolved.Diagnostics | Where-Object {$_.Code -eq 'LOW_CONFIDENCE' -and $_.CellId -in $requiredCells}).Count
        [pscustomobject]@{Threshold=$threshold;Status=$resolved.Status;RequiredCoverage=$coverage;UsableRows=$(if($coverage){2}else{0});
            ConfidenceOnlyFailure=$resolved.Status -eq 'PARTIAL' -and $requiredLow -gt 0 -and @($codes | Where-Object {$_ -ne 'LOW_CONFIDENCE'}).Count -eq 0;
            Diagnostics=$resolved.Diagnostics;CellText=$resolved.CellText}
    })
    return [pscustomobject]@{OperationalStatus='COMPLETE';OperationalCode=$null;AcceptanceStatus='EVALUATED';ConfidenceEvidence='OBSERVED';Thresholds=$thresholds}
}

function Get-P43a2ConfidenceDecision {
    param([object[]]$Clear,[object]$Mild)
    # Only the new mild control may establish confidence evidence. Old operational
    # negatives never enter this gate, and no threshold evaluation occurs for them.
    if($Mild.OperationalStatus -ne 'COMPLETE'){
        $code=if($Mild.OperationalCode -eq 'EMPTY_WORD_OUTPUT'){'GATE_A_CONFIDENCE_NOT_OBSERVED'}else{'GATE_A_OPERATIONAL_FAILED'}
        return [pscustomobject]@{Code=$code;SelectedConfidenceThreshold=$null;Candidates=@()}
    }
    $candidates=@(foreach($threshold in @(0,50,80,90,95)){
        $clearPass=$Clear.Count -gt 0 -and @($Clear | Where-Object {
            $_.OperationalStatus -ne 'COMPLETE' -or @($_.Thresholds | Where-Object {$_.Threshold -eq $threshold -and $_.RequiredCoverage}).Count -ne 1
        }).Count -eq 0
        $base=@($Mild.Thresholds | Where-Object Threshold -eq 0)[0]
        $at=@($Mild.Thresholds | Where-Object Threshold -eq $threshold)[0]
        $mildPass=$base.Status -eq 'COMPLETE' -and $base.RequiredCoverage -and $at.ConfidenceOnlyFailure
        [pscustomobject]@{Threshold=$threshold;ClearRequiredUsable=$clearPass;MildConfidenceOnlyIncomplete=$mildPass;Qualifies=$clearPass -and $mildPass}
    })
    $qualified=@($candidates | Where-Object Qualifies)
    return [pscustomobject]@{Code=$(if($qualified.Count){$null}else{'GATE_A_CONFIDENCE_REJECTED'});SelectedConfidenceThreshold=$(if($qualified.Count){$qualified[0].Threshold}else{$null});Candidates=$candidates}
}

function Assert-P43a2FixtureSet {
    param([string]$Directory)
    $manifest=Get-Content -LiteralPath (Join-Path $Directory 'manifest.json') -Raw | ConvertFrom-Json
    $expected='degraded-gray,degraded-rgb,mild-degraded-gray'
    if((@($manifest.fixtures.name | Sort-Object) -join ',') -cne $expected -or (@(Get-ChildItem -LiteralPath $Directory -Filter '*.pdf' | ForEach-Object BaseName | Sort-Object) -join ',') -cne $expected){throw 'A2_FIXTURE_EXPANSION_FORBIDDEN'}
    foreach($fixture in $manifest.fixtures){
        if((Get-FileHash -LiteralPath (Join-Path $Directory ($fixture.name+'.pdf'))).Hash.ToLowerInvariant() -cne $fixture.sha256){throw 'A2_FIXTURE_HASH_MISMATCH'}
    }
    $mild=@($manifest.fixtures | Where-Object name -eq 'mild-degraded-gray')[0]
    if(-not $mild.degradation.textOnly -or $mild.degradation.operation -cne 'GaussianBlur' -or $mild.degradation.radius -ne 0.6 -or $mild.degradation.resize){throw 'A2_MILD_PARAMETER_CHANGED'}
}

function Invoke-P43a2AcceptanceMatrix {
    param([string]$Executable,[string]$ModelPath,[ValidateSet(0.25,0.50,0.75)][double]$SameRegionRatio)
    Assert-P43a2FixtureSet -Directory (Join-Path $PSScriptRoot 'fixtures')
    $clear=[Collections.Generic.List[object]]::new();$regression=[Collections.Generic.List[object]]::new();$degraded=[Collections.Generic.List[object]]::new()
    foreach($name in @('gray','rgb')){
        for($repeat=1;$repeat -le 2;$repeat++){$clear.Add((Invoke-InternalP43a2AcceptanceProbe -PdfPath (Join-Path $PSScriptRoot "../p4-3a-ocr/fixtures/$name.pdf") -Executable $Executable -ModelPath $ModelPath -Psm 11 -SameRegionRatio $SameRegionRatio))}
        foreach($psm in @(3,4,6)){$regression.Add((Invoke-InternalP43a2AcceptanceProbe -PdfPath (Join-Path $PSScriptRoot "../p4-3a-ocr/fixtures/$name.pdf") -Executable $Executable -ModelPath $ModelPath -Psm $psm -SameRegionRatio $SameRegionRatio))}
        $degraded.Add((Invoke-InternalP43a2AcceptanceProbe -PdfPath (Join-Path $PSScriptRoot "fixtures/degraded-$name.pdf") -Executable $Executable -ModelPath $ModelPath -Psm 11 -SameRegionRatio $SameRegionRatio))
    }
    $mild=Invoke-InternalP43a2AcceptanceProbe -PdfPath (Join-Path $PSScriptRoot 'fixtures/mild-degraded-gray.pdf') -Executable $Executable -ModelPath $ModelPath -Psm 11 -SameRegionRatio $SameRegionRatio
    # Byte-derived proof is independently checked by generate-fixtures.py --check
    # before Acceptance invokes OCR; its hashes are pinned by Assert-P43a2FixtureSet.
    $manifest=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures/manifest.json') -Raw | ConvertFrom-Json
    $proof=@($manifest.fixtures | Where-Object name -eq 'mild-degraded-gray')[0].gridProof
    $mild | Add-Member -NotePropertyName GridPixelsMatchClear -NotePropertyValue ($proof.gridPixelsSha256 -ceq $proof.clearGridPixelsSha256)
    $repetitions=$true
    foreach($offset in @(0,2)){
        $first=$clear[$offset];$second=$clear[$offset+1]
        # Same exact TSV word identity/bbox/confidence => same fixed membership/classification.
        if(($first.Words | ConvertTo-Json -Depth 8 -Compress) -cne ($second.Words | ConvertTo-Json -Depth 8 -Compress)){$repetitions=$false}
    }
    $decision=Get-P43a2ConfidenceDecision -Clear $clear.ToArray() -Mild $mild
    $selected=$decision.SelectedConfidenceThreshold
    $regressionSafe=@($regression | Where-Object {$_.OperationalStatus -ne 'COMPLETE' -or @($_.Thresholds | Where-Object Status -ne 'PARTIAL').Count -gt 0 -or @($_.Thresholds[0].Diagnostics | Where-Object {$_.Code -in @('CELL_NONE','CELL_AMBIGUOUS')}).Count -eq 0}).Count -eq 0
    $pass=$null -ne $selected -and $regressionSafe -and $repetitions
    $summarize={param($run) [pscustomobject]@{Fixture=$run.Fixture;FixtureHash=$run.FixtureHash;Psm=$run.Psm;EngineBuild=$run.EngineBuild;ModelSha256=$run.ModelSha256;WordCount=$run.WordCount;GridStatus=$run.GridStatus;
        GridPixelsMatchClear=$(if($run.PSObject.Properties['GridPixelsMatchClear']){$run.GridPixelsMatchClear}else{$null});
        PdfOpenCount=$run.PdfOpenCount;PageReadCount=$run.PageReadCount;ImageDecodeCount=$run.ImageDecodeCount;GridBuildCount=$run.GridBuildCount;OcrInvocationCount=$run.OcrInvocationCount;
        OperationalStatus=$run.OperationalStatus;OperationalCode=$run.OperationalCode;AcceptanceStatus=$run.AcceptanceStatus;ConfidenceEvidence=$run.ConfidenceEvidence;
        Thresholds=@($run.Thresholds | ForEach-Object {[pscustomobject]@{Threshold=$_.Threshold;Status=$_.Status;RequiredCoverage=$_.RequiredCoverage;UsableRows=$_.UsableRows;ConfidenceOnlyFailure=$_.ConfidenceOnlyFailure;
            Diagnostics=@($_.Diagnostics | Group-Object Code | Sort-Object Name | ForEach-Object {[pscustomobject]@{Code=$_.Name;Count=$_.Count}})}})}}
    return [pscustomobject]@{Status=$(if($pass){'COMPLETE'}else{'REJECTED'});Verdict=$(if($pass){'GATES_A_B_PASS'}else{'P4_3A2_REJECTED'});
        Code=$(if($pass){$null}elseif(-not $regressionSafe){'GATE_B_REGRESSION_REJECTED'}elseif(-not $repetitions){'GATE_A_REPETITION_REJECTED'}else{$decision.Code});
        SameRegionRatio=$SameRegionRatio;SelectedConfidenceThreshold=$selected;ConfidenceCandidates=$decision.Candidates;
        ClearUsableRows=($clear | ForEach-Object {$_.Thresholds[0].UsableRows} | Measure-Object -Sum).Sum;
        RegressionUsableRows=($regression | ForEach-Object {$_.Thresholds | Measure-Object UsableRows -Maximum | Select-Object -ExpandProperty Maximum} | Measure-Object -Sum).Sum;
        RepetitionsIdentical=$repetitions;RegressionSafe=$regressionSafe;DegradedGridComplete=@($degraded | Where-Object GridStatus -ne 'COMPLETE').Count -eq 0;
        Runs=@(@($clear.ToArray())+@($regression.ToArray())+@($degraded.ToArray())+@($mild) | ForEach-Object {& $summarize $_});ProductionAction='NONE'}
}

function Get-P43a2OverlapClass {
    param([object]$A,[object]$B,[ValidateSet(0.25,0.50,0.75)][double]$SameRegionRatio)
    # Inputs are evaluation-local membership wrappers, not raw TSV words.
    if(-not $A.PSObject.Properties['Membership'] -or -not $B.PSObject.Properties['Membership']){return 'ORDERING_UNSAFE'}
    if($A.Membership.Status -ne 'UNIQUE' -or $B.Membership.Status -ne 'UNIQUE' -or $A.Membership.CellId -cne $B.Membership.CellId -or $A.Record.Page -ne $B.Record.Page){return 'ORDERING_UNSAFE'}
    $aWord=$A.Record;$bWord=$B.Record
    $sameBox=$aWord.Left -eq $bWord.Left -and $aWord.Top -eq $bWord.Top -and $aWord.Width -eq $bWord.Width -and $aWord.Height -eq $bWord.Height
    if(-not $sameBox -and $aWord.Left -eq $bWord.Left -and $aWord.Top -eq $bWord.Top){return 'ORDERING_UNSAFE'}
    $vertical=[Math]::Min($aWord.Top+$aWord.Height,$bWord.Top+$bWord.Height)-[Math]::Max($aWord.Top,$bWord.Top)
    if($vertical -gt 0 -and $aWord.Block -eq $bWord.Block -and $aWord.Paragraph -eq $bWord.Paragraph -and $aWord.Line -eq $bWord.Line){
        if($aWord.Word -eq $bWord.Word -and -not $sameBox){return 'ORDERING_UNSAFE'}
        if(($aWord.Left -lt $bWord.Left -and $aWord.Word -gt $bWord.Word) -or ($aWord.Left -gt $bWord.Left -and $aWord.Word -lt $bWord.Word)){return 'ORDERING_UNSAFE'}
    }
    $horizontal=[Math]::Min($aWord.Left+$aWord.Width,$bWord.Left+$bWord.Width)-[Math]::Max($aWord.Left,$bWord.Left)
    if($vertical -le 0 -or $horizontal -le 0){return 'NONE'}
    $score=([double]$horizontal*$vertical)/[Math]::Min(([double]$aWord.Width*$aWord.Height),([double]$bWord.Width*$bWord.Height))
    if($score -ge $SameRegionRatio){if($aWord.Text -ceq $bWord.Text){return 'DUPLICATE'};return 'CONFLICTING'}
    return 'SAFE_ADJACENT'
}

function Resolve-P43a2OcrCells {
    param([object[]]$Cells,[object[]]$Words,[ValidateSet(0,50,80,90,95)][double]$ConfidenceThreshold,[ValidateSet(0.25,0.50,0.75)][double]$SameRegionRatio)
    $diagnostics=[Collections.Generic.List[object]]::new();$bound=[Collections.Generic.List[object]]::new()
    foreach($word in $Words){
        $membership=Get-P43a2CellMembership -Cells $Cells -Word $word
        if($membership.Status -ne 'UNIQUE'){$diagnostics.Add([pscustomobject]@{Code='CELL_'+$membership.Status});continue}
        $bound.Add([pscustomobject]@{Record=$word;Membership=$membership})
        if($word.Confidence -lt $ConfidenceThreshold){$diagnostics.Add([pscustomobject]@{Code='LOW_CONFIDENCE';CellId=$membership.CellId})}
    }
    if($Words.Count -eq 0){$diagnostics.Add([pscustomobject]@{Code='EMPTY_WORDS'})}
    $texts=[Collections.Generic.List[object]]::new()
    foreach($group in @($bound | Group-Object {$_.Membership.CellId})){
        $items=@($group.Group | Sort-Object {$_.Record.Top},{$_.Record.Left},{$_.Record.Word})
        for($i=0;$i -lt $items.Count;$i++){
            for($j=$i+1;$j -lt $items.Count;$j++){
                $class=Get-P43a2OverlapClass -A $items[$i] -B $items[$j] -SameRegionRatio $SameRegionRatio
                if($class -ne 'NONE'){$diagnostics.Add([pscustomobject]@{Code=$class;CellId=$group.Name})}
            }
        }
        # Build vertical-overlap connected components once. A non-clique component
        # bridges disjoint physical lines; never guess a line/order from that bridge.
        $remaining=[Collections.Generic.List[int]]::new();for($i=0;$i -lt $items.Count;$i++){$remaining.Add($i)}
        $lines=[Collections.Generic.List[string]]::new()
        while($remaining.Count -gt 0){
            $component=[Collections.Generic.List[int]]::new();$component.Add($remaining[0]);$remaining.RemoveAt(0)
            for($cursor=0;$cursor -lt $component.Count;$cursor++){
                $a=$items[$component[$cursor]].Record
                foreach($index in @($remaining.ToArray())){
                    $b=$items[$index].Record
                    if([Math]::Min($a.Top+$a.Height,$b.Top+$b.Height) -gt [Math]::Max($a.Top,$b.Top)){$component.Add($index);[void]$remaining.Remove($index)}
                }
            }
            for($i=0;$i -lt $component.Count;$i++){
                for($j=$i+1;$j -lt $component.Count;$j++){
                    $a=$items[$component[$i]].Record;$b=$items[$component[$j]].Record
                    if([Math]::Min($a.Top+$a.Height,$b.Top+$b.Height) -le [Math]::Max($a.Top,$b.Top)){$diagnostics.Add([pscustomobject]@{Code='ORDERING_UNSAFE';CellId=$group.Name})}
                }
            }
            $ordered=@($component | ForEach-Object {$items[$_].Record} | Sort-Object Left,Top)
            $lines.Add(($ordered.Text -join ' '))
        }
        $texts.Add([pscustomobject]@{CellId=$group.Name;Text=($lines -join "`n")})
    }
    $blocked=@($diagnostics | Where-Object Code -ne 'SAFE_ADJACENT').Count -gt 0
    return [pscustomobject]@{Status=$(if($blocked){'PARTIAL'}else{'COMPLETE'});Policy='SAME_CELL_OVERLAP_V1';SameRegionRatio=$SameRegionRatio;ConfidenceThreshold=$ConfidenceThreshold;
        AcceptedWords=@(if(-not $blocked){$bound.ToArray()});RejectedWords=@(if($blocked){$Words});Diagnostics=$diagnostics.ToArray();CellText=@(if(-not $blocked){$texts.ToArray()});ProductionAction='NONE'}
}

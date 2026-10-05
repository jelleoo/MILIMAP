Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'invoke-tesseract-eval.ps1')

function Get-P43R2CellMembership {
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

function Get-P43R2OverlapClass {
    param([object]$A,[object]$B)
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
    if($score -ge 0.25){if($aWord.Text -ceq $bWord.Text){return 'DUPLICATE'};return 'CONFLICTING'}
    return 'SAFE_ADJACENT'
}

function Resolve-P43R2OcrCells {
    param([object[]]$Cells,[object[]]$Words,[string[]]$RequiredCellIds)
    $diagnostics=[Collections.Generic.List[object]]::new();$bound=[Collections.Generic.List[object]]::new()
    foreach($word in $Words){
        $membership=Get-P43R2CellMembership -Cells $Cells -Word $word
        if($membership.Status -ne 'UNIQUE'){$diagnostics.Add([pscustomobject]@{Code='CELL_'+$membership.Status;Record=$word});continue}
        $bound.Add([pscustomobject]@{Record=$word;Membership=$membership})
    }
    $texts=[Collections.Generic.List[object]]::new()
    foreach($group in @($bound | Group-Object {$_.Membership.CellId} | Sort-Object Name)){
        $items=@($group.Group | Sort-Object {$_.Record.Top},{$_.Record.Left},{$_.Record.Word})
        for($i=0;$i -lt $items.Count;$i++){
            for($j=$i+1;$j -lt $items.Count;$j++){
                $class=Get-P43R2OverlapClass -A $items[$i] -B $items[$j]
                if($class -ne 'NONE'){$diagnostics.Add([pscustomobject]@{Code=$class;CellId=$group.Name;A=$items[$i].Record;B=$items[$j].Record})}
            }
        }
        # Retained A2 physical vertical components: non-clique bridge is unsafe.
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
    foreach($id in $RequiredCellIds){
        if(@($Cells | Where-Object CellId -CEQ $id).Count -ne 1 -or @($texts | Where-Object {$_.CellId -ceq $id -and -not [string]::IsNullOrWhiteSpace($_.Text)}).Count -ne 1){
            $diagnostics.Add([pscustomobject]@{Code='REQUIRED_COVERAGE_MISSING';CellId=$id})
        }
    }
    if($RequiredCellIds.Count -eq 0){$diagnostics.Add([pscustomobject]@{Code='REQUIRED_COVERAGE_MISSING'})}
    $blocked=@($diagnostics | Where-Object Code -ne 'SAFE_ADJACENT').Count -gt 0
    return [pscustomobject]@{Status=$(if($blocked){'PARTIAL'}else{'COMPLETE'});Policy='SAME_CELL_OVERLAP_V1';SameRegionRatio=0.25;ConfidencePolicy='DIAGNOSTIC_ONLY_V1';RequiredCoverage=(-not $blocked);
        AcceptedWords=@(if(-not $blocked){$bound.ToArray()});RejectedWords=@(if($blocked){$Words});Diagnostics=$diagnostics.ToArray();CellText=@(if(-not $blocked){$texts.ToArray()});ProductionAction='NONE'}
}

function New-P43R2StructuralEvidence {
    param([object[]]$Cells,[object]$Ocr,[string[]]$RequiredCellIds)
    if($Ocr.Status -ne 'COMPLETE' -or $Ocr.Words.Count -eq 0){
        $code=if($Ocr.Code -eq 'P43A2_TSV_EMPTY_WORD_OUTPUT' -or ($Ocr.Status -eq 'COMPLETE' -and $Ocr.Words.Count -eq 0)){'EMPTY_WORD_OUTPUT'}else{$Ocr.Code}
        return [pscustomobject]@{OperationalStatus='FAILED';OperationalCode=$code;AcceptanceStatus='NOT_EVALUATED';Status='NOT_EVALUATED';RequiredCoverage=$false;AcceptedWords=@();RejectedWords=@();CellText=@();Diagnostics=$Ocr.Diagnostics;ProductionAction='NONE'}
    }
    $resolved=Resolve-P43R2OcrCells -Cells $Cells -Words $Ocr.Words -RequiredCellIds $RequiredCellIds
    $resolved | Add-Member -NotePropertyName OperationalStatus -NotePropertyValue 'COMPLETE'
    $resolved | Add-Member -NotePropertyName OperationalCode -NotePropertyValue $null
    $resolved | Add-Member -NotePropertyName AcceptanceStatus -NotePropertyValue 'EVALUATED'
    return $resolved
}

function Invoke-InternalP43R2StructuralProbe {
    param([string]$PdfPath,[string]$Executable,[string]$ModelPath,[int]$Psm)
    $scratch=Join-Path ([IO.Path]::GetTempPath()) ('milimap-p43r2-probe-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($scratch)
    try{
        $dll=Join-Path $PSScriptRoot '../p4-3a-ocr/bin/Release/net8.0/Milimap.P4_3A.OcrEval.dll'
        $raw=& dotnet $dll inspect --input $PdfPath --artifact-dir $scratch
        $inspect=$raw | ConvertFrom-Json
        if($LASTEXITCODE -ne 0 -or $inspect.Status -ne 'ELIGIBLE' -or $inspect.Images.Count -ne 1){throw 'R2_IMAGE_NOT_ELIGIBLE'}
        $metadata=Join-Path $scratch 'inspect.json';[IO.File]::WriteAllText($metadata,$raw)
        $grid=& dotnet $dll grid --input $inspect.Images[0].ArtifactPath --metadata $metadata --page 1 --image 1 | ConvertFrom-Json
        if($LASTEXITCODE -ne 0 -or $grid.Status -ne 'COMPLETE' -or $grid.Cells.Count -ne 12){throw 'R2_REQUIRED_GRID_NOT_COMPLETE'}
        $cells=@($grid.Cells | ForEach-Object {[pscustomobject]@{Page=1;CellId=[string]$_.Id;Left=$_.X0;Top=$_.Y0;Width=$_.X1-$_.X0;Height=$_.Y1-$_.Y0;Row=$_.Row;Column=$_.Column}})
        # Entire proven 3x4 grid is required; topology never derived from OCR text.
        if(@($cells | Where-Object {$_.Row -notin 1..3 -or $_.Column -notin 1..4}).Count -gt 0){throw 'R2_GRID_TOPOLOGY_MISMATCH'}
        $ocr=Invoke-P43R2TesseractEvaluation -Executable $Executable -ModelPath $ModelPath -Inputs @($inspect.Images[0].ArtifactPath) -Psm $Psm
        $evidence=New-P43R2StructuralEvidence -Cells $cells -Ocr $ocr -RequiredCellIds $cells.CellId
        return [pscustomobject]@{Fixture=[IO.Path]::GetFileName($PdfPath);FixtureHash=(Get-FileHash $PdfPath).Hash.ToLowerInvariant();Psm=$Psm;Words=$ocr.Words;WordCount=$ocr.Words.Count;
            EngineBuild=$ocr.EngineBuild;ModelSha256=$ocr.ModelSha256;GridStatus=$grid.Status;Cells=$cells;CellText=$evidence.CellText;AcceptedWords=$evidence.AcceptedWords;
            RawConfidence=@($ocr.Words | Select-Object Page,Block,Paragraph,Line,Word,Text,Confidence);
            AcceptedBelow50=@($evidence.AcceptedWords | Where-Object {$_.Record.Confidence -lt 50} | ForEach-Object {[pscustomobject]@{CellId=$_.Membership.CellId;Record=$_.Record}});
            ExactMembership=($evidence.Status -eq 'COMPLETE' -and $evidence.AcceptedWords.Count -eq $ocr.Words.Count);RequiredCoverage=$evidence.RequiredCoverage;
            Status=$evidence.Status;OperationalStatus=$evidence.OperationalStatus;OperationalCode=$evidence.OperationalCode;
            UsableRows=$(if($evidence.Status -eq 'COMPLETE'){2}else{0});Diagnostics=$evidence.Diagnostics;
            PdfOpenCount=$inspect.OpenCount;ImageDecodeCount=$inspect.ImageDecodeCount;GridBuildCount=1;OcrInvocationCount=$ocr.InvocationCount;ProductionAction='NONE'}
    }finally{[IO.Directory]::Delete($scratch,$true)}
}

function Invoke-P43R2GateAMatrix {
    param([string]$Executable,[string]$ModelPath)
    $runs=[Collections.Generic.List[object]]::new()
    foreach($name in @('gray','rgb')){
        for($repeat=1;$repeat -le 2;$repeat++){$runs.Add((Invoke-InternalP43R2StructuralProbe -PdfPath (Join-Path $PSScriptRoot "../p4-3a-ocr/fixtures/$name.pdf") -Executable $Executable -ModelPath $ModelPath -Psm 11))}
        foreach($psm in @(3,4,6)){$runs.Add((Invoke-InternalP43R2StructuralProbe -PdfPath (Join-Path $PSScriptRoot "../p4-3a-ocr/fixtures/$name.pdf") -Executable $Executable -ModelPath $ModelPath -Psm $psm))}
        $runs.Add((Invoke-InternalP43R2StructuralProbe -PdfPath (Join-Path $PSScriptRoot "../p4-3a2-ocr/fixtures/degraded-$name.pdf") -Executable $Executable -ModelPath $ModelPath -Psm 11))
    }
    $runs.Add((Invoke-InternalP43R2StructuralProbe -PdfPath (Join-Path $PSScriptRoot '../p4-3a2-ocr/fixtures/mild-degraded-gray.pdf') -Executable $Executable -ModelPath $ModelPath -Psm 11))
    $clear=@($runs | Where-Object {$_.Psm -eq 11 -and $_.Fixture -in @('gray.pdf','rgb.pdf')})
    $repeat=$true
    foreach($offset in @(0,2)){
        foreach($field in @('Words','Cells','CellText','Diagnostics')){
            if(($clear[$offset].$field | ConvertTo-Json -Depth 12 -Compress) -cne ($clear[$offset+1].$field | ConvertTo-Json -Depth 12 -Compress)){$repeat=$false}
        }
    }
    $pass=$repeat -and @($clear | Where-Object {$_.Status -ne 'COMPLETE' -or $_.UsableRows -le 0 -or -not $_.RequiredCoverage -or -not $_.ExactMembership}).Count -eq 0
    $regression=@($runs | Where-Object Psm -ne 11)
    $pass=$pass -and @($regression | Where-Object {$_.Status -ne 'PARTIAL' -or @($_.Diagnostics | Where-Object {$_.Code -in @('CELL_NONE','CELL_AMBIGUOUS')}).Count -eq 0}).Count -eq 0
    $mild=$runs[$runs.Count-1]
    $pass=$pass -and $mild.Status -eq 'PARTIAL' -and @($mild.Diagnostics | Where-Object Code -eq 'CONFLICTING').Count -gt 0
    $old=@($runs | Where-Object {$_.Fixture -in @('degraded-gray.pdf','degraded-rgb.pdf')})
    $pass=$pass -and @($old | Where-Object {$_.OperationalStatus -ne 'FAILED' -or $_.OperationalCode -ne 'EMPTY_WORD_OUTPUT'}).Count -eq 0
    return [pscustomobject]@{ProbeId='MILIMAP_P4_3_REDESIGN2_OCR_EVAL';TrustModelVersion='STRUCTURAL_TRUST_V1';ConfidencePolicy='DIAGNOSTIC_ONLY_V1';SameRegionRatio=0.25;
        Verdict=$(if($pass){'GATE_A_PASS'}else{'P4_3_REDESIGN2_REJECTED'});RepetitionsIdentical=$repeat;Runs=$runs.ToArray();ProductionAction='NONE'}
}

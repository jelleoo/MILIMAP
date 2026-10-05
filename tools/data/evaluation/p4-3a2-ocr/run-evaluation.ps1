Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

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

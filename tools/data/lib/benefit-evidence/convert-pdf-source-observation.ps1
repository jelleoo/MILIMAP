Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'pdf-native-runtime.ps1')

function Get-InternalBenefitPdfGridConfiguration {
    # One material policy, shared by cache identity and indexed provenance.
    [ordered]@{Version='PDF_GRID_CONFIG_V1';Snap=0.5;ThinRectangle=0.75;Containment=0.01;Baseline=1.0;
        CoordinatePolicy='PDFPIG_INVERSE_ORTHOGONAL_V1';OverlapFraction=0.5;OverlapVisibleOnly=$true;MaxGridCoordinates=128;
        MaxGridCells=4096;AxisEpsilon=0.00000001;Parser='PDFPIG';ParserVersion='0.1.16';StackDepth=128;Strict=$true;ClipPaths=$true}
}
function Get-BenefitPdfExtractionConfigHash {
    $policy=Get-InternalBenefitPdfGridConfiguration
    $headers=Get-BenefitScopedHeaderMap
    $identity=($policy | ConvertTo-Json -Compress)+ '|' + (@($headers.Keys | Sort-Object -CaseSensitive | ForEach-Object {"$_=$($headers[$_])"}) -join '|')
    Get-BenefitEvidenceTextHash -Text $identity
}
function New-InternalBenefitPdfDiagnostic {
    param([string]$Code,[string]$Reference,[string]$Detail)
    [pscustomobject][ordered]@{Code=$Code;Stage='PDF_GRID';EvidenceReference=$Reference;Detail=$Detail}
}
function Convert-InternalBenefitPdfPoint {
    param([double]$X,[double]$Y,[Parameter(Mandatory)]$Page)
    if(-not [double]::IsFinite($X) -or -not [double]::IsFinite($Y)){throw 'Invalid native coordinate'}
    switch([int]$Page.RotationDegrees){
        0 {@($X,$Y)}
        90 {@(([double]$Page.Height-$Y),$X)}
        180 {@(([double]$Page.Width-$X),([double]$Page.Height-$Y))}
        270 {@($Y,([double]$Page.Width-$X))}
        default {throw 'Unsupported page rotation'}
    }
}
function Get-InternalBenefitPdfCoordinates {
    param([double[]]$Values)
    $snap=(Get-InternalBenefitPdfGridConfiguration).Snap
    $groups=[Collections.Generic.List[object]]::new()
    foreach($value in @($Values | Sort-Object -Unique)){
        if($groups.Count -gt 0 -and $value-$groups[$groups.Count-1][0] -le $snap){$groups[$groups.Count-1].Add($value)}
        else {$group=[Collections.Generic.List[double]]::new();$group.Add($value);$groups.Add($group)}
    }
    @($groups | ForEach-Object {($_ | Measure-Object -Average).Average})
}
function Test-InternalBenefitPdfCoverage {
    param([object[]]$Segments,[double]$Coordinate,[double]$Low,[double]$High)
    $snap=(Get-InternalBenefitPdfGridConfiguration).Snap
    $cursor=$Low
    foreach($segment in @($Segments | Where-Object {[Math]::Abs($_.C-$Coordinate) -le $snap} | Sort-Object Low,High)){
        if($segment.Low -gt $cursor+$snap){return $false}
        $cursor=[Math]::Max($cursor,$segment.High)
        if($cursor -ge $High-$snap){return $true}
    }
    return $false
}
function Get-InternalBenefitPdfPageGrids {
    param([Parameter(Mandatory)]$Page)
    $policy=Get-InternalBenefitPdfGridConfiguration
    $snap=$policy.Snap;$thin=$policy.ThinRectangle;$epsilon=$policy.Containment
    if($Page.Width -le 0 -or $Page.Height -le 0 -or -not [double]::IsFinite($Page.Width) -or -not [double]::IsFinite($Page.Height)){throw 'Invalid page box'}
    if($Page.RotationDegrees -notin @(0,90,180,270)){throw 'Unsupported page rotation'}
    $segments=[Collections.Generic.List[object]]::new();$letters=[Collections.Generic.List[object]]::new()
    foreach($letter in $Page.Letters){
        if($letter.Text -isnot [string] -or $letter.Text.Length -eq 0){throw 'Invalid native glyph text'}
        $points=@((Convert-InternalBenefitPdfPoint $letter.X0 $letter.Y0 $Page),(Convert-InternalBenefitPdfPoint $letter.X0 $letter.Y1 $Page),(Convert-InternalBenefitPdfPoint $letter.X1 $letter.Y0 $Page),(Convert-InternalBenefitPdfPoint $letter.X1 $letter.Y1 $Page))
        $baseline=Convert-InternalBenefitPdfPoint $letter.BaselineX $letter.BaselineY $Page
        $letters.Add([pscustomobject]@{Text=$letter.Text;Index=$letter.Index;X0=($points | ForEach-Object {$_[0]} | Measure-Object -Minimum).Minimum;X1=($points | ForEach-Object {$_[0]} | Measure-Object -Maximum).Maximum;Y0=($points | ForEach-Object {$_[1]} | Measure-Object -Minimum).Minimum;Y1=($points | ForEach-Object {$_[1]} | Measure-Object -Maximum).Maximum;Baseline=$baseline[1]})
    }
    foreach($path in $Page.Paths){foreach($subpath in $path.Subpaths){
        $lines=[Collections.Generic.List[object]]::new();$closed=$false;$straight=$true
        foreach($command in $subpath){
            if($command.Kind -ceq 'Close'){$closed=$true}
            elseif($command.Kind -ceq 'Line'){
                $a=Convert-InternalBenefitPdfPoint $command.Points.From.X $command.Points.From.Y $Page
                $b=Convert-InternalBenefitPdfPoint $command.Points.To.X $command.Points.To.Y $Page
                if([Math]::Abs($a[1]-$b[1]) -le $policy.AxisEpsilon){$lines.Add([pscustomobject]@{Axis='H';C=$a[1];Low=[Math]::Min($a[0],$b[0]);High=[Math]::Max($a[0],$b[0])})}
                elseif([Math]::Abs($a[0]-$b[0]) -le $policy.AxisEpsilon){$lines.Add([pscustomobject]@{Axis='V';C=$a[0];Low=[Math]::Min($a[1],$b[1]);High=[Math]::Max($a[1],$b[1])})}
                else {$straight=$false}
            } elseif($command.Kind -cne 'Move'){$straight=$false}
        }
        if($path.IsStroked){foreach($line in $lines){$segments.Add($line)}}
        if($path.IsFilled -and $straight -and $closed -and $lines.Count -eq 3){
            $h=@($lines | Where-Object Axis -CEQ 'H');$v=@($lines | Where-Object Axis -CEQ 'V')
            if($h.Count -gt 0 -and $v.Count -gt 0){
                $x0=($h.Low | Measure-Object -Minimum).Minimum;$x1=($h.High | Measure-Object -Maximum).Maximum
                $y0=($v.Low | Measure-Object -Minimum).Minimum;$y1=($v.High | Measure-Object -Maximum).Maximum
                if($x1-$x0 -gt 0 -and $x1-$x0 -le $thin -and $y1-$y0 -gt $thin){$segments.Add([pscustomobject]@{Axis='V';C=($x0+$x1)/2;Low=$y0;High=$y1})}
                if($y1-$y0 -gt 0 -and $y1-$y0 -le $thin -and $x1-$x0 -gt $thin){$segments.Add([pscustomobject]@{Axis='H';C=($y0+$y1)/2;Low=$x0;High=$x1})}
            }
        }
    }}
    # Connected vector components isolate tables before coordinate clustering.
    $remaining=[Collections.Generic.HashSet[int]]::new();for($i=0;$i -lt $segments.Count;$i++){[void]$remaining.Add($i)}
    $grids=[Collections.Generic.List[object]]::new()
    while($remaining.Count -gt 0){
        $seed=@($remaining)[0];[void]$remaining.Remove($seed);$todo=[Collections.Generic.Queue[int]]::new();$todo.Enqueue($seed);$members=[Collections.Generic.List[object]]::new()
        while($todo.Count -gt 0){
            $a=$segments[$todo.Dequeue()];$members.Add($a)
            foreach($i in @($remaining)){
                $b=$segments[$i];$connected=$false
                if($a.Axis -ceq $b.Axis){$connected=[Math]::Abs($a.C-$b.C) -le $snap -and [Math]::Min($a.High,$b.High) -ge [Math]::Max($a.Low,$b.Low)-$snap}
                else {$h=if($a.Axis -ceq 'H'){$a}else{$b};$v=if($a.Axis -ceq 'V'){$a}else{$b};$connected=$v.C -ge $h.Low-$snap -and $v.C -le $h.High+$snap -and $h.C -ge $v.Low-$snap -and $h.C -le $v.High+$snap}
                if($connected){[void]$remaining.Remove($i);$todo.Enqueue($i)}
            }
        }
        $horizontal=@($members | Where-Object Axis -CEQ 'H');$vertical=@($members | Where-Object Axis -CEQ 'V')
        if($horizontal.Count -lt 2 -or $vertical.Count -lt 2){continue}
        $xs=@(Get-InternalBenefitPdfCoordinates $vertical.C);$ys=@(Get-InternalBenefitPdfCoordinates $horizontal.C | Sort-Object -Descending)
        if($xs.Count -gt $policy.MaxGridCoordinates -or $ys.Count -gt $policy.MaxGridCoordinates -or ($xs.Count-1)*($ys.Count-1) -gt $policy.MaxGridCells){throw 'PDF grid exceeds geometry quota'}
        $rows=[Collections.Generic.List[object]]::new()
        for($r=0;$r -lt $ys.Count-1;$r++){
            $cells=[Collections.Generic.List[object]]::new()
            for($c=0;$c -lt $xs.Count-1;$c++){
                $safe=(Test-InternalBenefitPdfCoverage $horizontal $ys[$r] $xs[$c] $xs[$c+1]) -and (Test-InternalBenefitPdfCoverage $horizontal $ys[$r+1] $xs[$c] $xs[$c+1]) -and (Test-InternalBenefitPdfCoverage $vertical $xs[$c] $ys[$r+1] $ys[$r]) -and (Test-InternalBenefitPdfCoverage $vertical $xs[$c+1] $ys[$r+1] $ys[$r])
                $cells.Add([pscustomobject]@{X0=$xs[$c];X1=$xs[$c+1];Y0=$ys[$r+1];Y1=$ys[$r];Safe=$safe;Text='';Letters=[Collections.Generic.List[object]]::new()})
            }
            $rows.Add([pscustomobject]@{Cells=@($cells.ToArray())})
        }
        $allCells=@($rows | ForEach-Object {$_.Cells});$gridLetters=[Collections.Generic.List[object]]::new()
        foreach($letter in $letters){
            $intersections=@($allCells | Where-Object {$letter.X1 -gt $_.X0+$epsilon -and $letter.X0 -lt $_.X1-$epsilon -and $letter.Y1 -gt $_.Y0+$epsilon -and $letter.Y0 -lt $_.Y1-$epsilon})
            if($intersections.Count -eq 0){continue}
            $gridLetters.Add($letter)
            $owners=@($allCells | Where-Object {$_.Safe -and $letter.X0 -ge $_.X0-$epsilon -and $letter.X1 -le $_.X1+$epsilon -and $letter.Y0 -ge $_.Y0-$epsilon -and $letter.Y1 -le $_.Y1+$epsilon})
            if($owners.Count -ne 1){foreach($cell in $intersections){$cell.Safe=$false};continue}
            $owners[0].Letters.Add($letter)
        }
        foreach($cell in $allCells){
            for($i=0;$i -lt $cell.Letters.Count;$i++){
                $a=$cell.Letters[$i];if($a.Text.Contains([char]0xfffd)){$cell.Safe=$false}
                for($j=0;$j -lt $i;$j++){
                    $b=$cell.Letters[$j]
                    # CID space advance and font bbox width can differ. Whitespace
                    # remains fully contained/ordered, but has no visible ink to duplicate.
                    if([string]::IsNullOrWhiteSpace($a.Text) -or [string]::IsNullOrWhiteSpace($b.Text)){continue}
                    if([Math]::Min($a.X1,$b.X1)-[Math]::Max($a.X0,$b.X0) -gt $policy.OverlapFraction*[Math]::Min($a.X1-$a.X0,$b.X1-$b.X0) -and [Math]::Min($a.Y1,$b.Y1)-[Math]::Max($a.Y0,$b.Y0) -gt $policy.OverlapFraction*[Math]::Min($a.Y1-$a.Y0,$b.Y1-$b.Y0)){$cell.Safe=$false}
                }
            }
            $lines=[Collections.Generic.List[object]]::new()
            foreach($letter in @($cell.Letters | Sort-Object @{Expression='Baseline';Descending=$true},X0,Index)){
                if($lines.Count -gt 0 -and [Math]::Abs($lines[$lines.Count-1][0].Baseline-$letter.Baseline) -le $policy.Baseline){$lines[$lines.Count-1].Add($letter)}
                else {$line=[Collections.Generic.List[object]]::new();$line.Add($letter);$lines.Add($line)}
            }
            $cell.Text=(@($lines | ForEach-Object {(@($_ | Sort-Object X0,Index | ForEach-Object {$_.Text}) -join '')}) -join "`n").Trim()
        }
        $grids.Add([pscustomobject]@{Rows=@($rows.ToArray());Top=$ys[0];Left=$xs[0];HintText=(@($gridLetters | Sort-Object Index | ForEach-Object {$_.Text}) -join '')})
    }
    @($grids | Sort-Object @{Expression='Top';Descending=$true},Left)
}
function ConvertTo-BenefitPdfObservation {
    param([Parameter(Mandatory)]$Document,[AllowNull()]$Snapshot=$null)
    Assert-BenefitSourceDocument $Document
    if($Document.FetchStatus -cne 'COMPLETE' -or $Document.SourceFormat -cne 'PDF'){throw 'PDF conversion requires successful PDF bytes'}
    if($null -eq $Snapshot){$Snapshot=New-BenefitSourceSnapshot -SourceUrl $Document.Url -SourceFormat PDF -Text '' -Bytes $Document.Bytes -ObservedAt $Document.ObservedAt}
    Assert-ScopeSnapshot $Snapshot
    if($Snapshot.SourceFormat -cne 'PDF' -or $Snapshot.SourceUrl -cne $Document.Url -or $Snapshot.ObservedAt -cne $Document.ObservedAt -or -not [Linq.Enumerable]::SequenceEqual([byte[]]$Snapshot.Bytes,[byte[]]$Document.Bytes)){throw 'PDF snapshot/document byte identity mismatch'}
    $runtime=Invoke-BenefitPdfNativeProjection -Bytes $Snapshot.Bytes
    $diagnostics=[Collections.Generic.List[object]]::new();foreach($d in $runtime.Diagnostics){$diagnostics.Add($d)}
    $records=[Collections.Generic.List[object]]::new();$status=$runtime.Status;$hasHeader=$false;$partial=$false
    $map=Get-BenefitScopedHeaderMap
    if($status -ceq 'COMPLETE'){
        try {
            $pageNumber=0
            foreach($page in $runtime.Projection.Pages){
                $pageNumber++;if($page.PageNumber -ne $pageNumber){throw 'Non-sequential native page identity'}
                $grids=@(Get-InternalBenefitPdfPageGrids $page);$ordinal=0
                foreach($grid in $grids){
                    $ordinal++;$path="page/$pageNumber/table/$ordinal";$candidates=[Collections.Generic.List[object]]::new();$badHeader=$false
                    for($r=0;$r -lt $grid.Rows.Count;$r++){
                        $mapping=[ordered]@{};$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$name=$false;$safe=$true
                        for($c=0;$c -lt $grid.Rows[$r].Cells.Count;$c++){
                            $cell=$grid.Rows[$r].Cells[$c]
                            if($map.ContainsKey($cell.Text)){
                                $field=$map[$cell.Text];if($field -ceq 'BusinessName'){$name=$true}
                                if(-not $cell.Safe -or -not $seen.Add($field)){$safe=$false}
                                $mapping.Add($c,$field)
                            }
                        }
                        if($name){if($safe){$candidates.Add([pscustomobject]@{Row=$r;Mapping=$mapping})}else{$badHeader=$true}}
                    }
                    $hint=@($map.Keys | Where-Object {$map[$_] -ceq 'BusinessName' -and $grid.HintText.Contains($_)}).Count -gt 0
                    if($badHeader -or $candidates.Count -gt 1 -or ($candidates.Count -eq 0 -and $hint)){$partial=$true;$diagnostics.Add((New-InternalBenefitPdfDiagnostic 'PDF_HEADER_UNUSABLE' $path 'Ambiguous or unsafe semantic header'));continue}
                    if($candidates.Count -eq 0){continue}
                    $hasHeader=$true;$header=$candidates[0];$tableRecords=[Collections.Generic.List[object]]::new();$emptyEvidence=$false
                    for($r=$header.Row+1;$r -lt $grid.Rows.Count;$r++){
                        $fields=[ordered]@{};$refs=[ordered]@{};$texts=[Collections.Generic.List[string]]::new();$safe=$true
                        $reference="PDF_PAGE_${pageNumber}_TABLE_${ordinal}_ROW_$($r+1)";$rowPath="$path/row/$($r+1)"
                        foreach($c in $header.Mapping.Keys){
                            $cell=$grid.Rows[$r].Cells[$c];$field=$header.Mapping[[object]$c]
                            if(-not $cell.Safe){$safe=$false}
                            $fields[$field]=$cell.Text;$refs[$field]=[pscustomobject][ordered]@{FieldReference="$reference/$field";PhysicalReference="$rowPath/cell/$($c+1)";SourceText=$cell.Text}
                            if($cell.Text){$texts.Add($cell.Text)}
                        }
                        if(-not $safe){$partial=$true;$diagnostics.Add((New-InternalBenefitPdfDiagnostic 'PDF_ROW_UNUSABLE' $reference 'Unproven mapped cell boundaries or glyph containment'));continue}
                        if([string]::IsNullOrWhiteSpace($fields.BusinessName)){if($texts.Count){$emptyEvidence=$true};continue}
                        $tableRecords.Add([pscustomobject][ordered]@{UnitType='PDF_ROW';UnitReference=$reference;PhysicalPath=$rowPath;RawEvidenceText=($texts -join ' | ');StructuredFields=$fields;FieldReferences=$refs})
                    }
                    # A page-local table consisting only of identity-less evidence is not
                    # a complete absence proof (e.g. unsupported cross-page continuation).
                    if($tableRecords.Count -eq 0 -and $emptyEvidence){$partial=$true;$diagnostics.Add((New-InternalBenefitPdfDiagnostic 'PDF_ROW_UNUSABLE' $path 'Identity-less evidence cannot establish complete table coverage'))}
                    foreach($record in $tableRecords){$records.Add($record)}
                }
            }
            if($partial){$status='PARTIAL'}elseif(-not $hasHeader){$status='UNSUPPORTED';$code=if(@($runtime.Projection.Pages | Where-Object {$_.Letters.Count -gt 0}).Count -eq 0){'OCR_FALLBACK_CANDIDATE'}else{'PDF_GRID_UNSUPPORTED'};$diagnostics.Add((New-InternalBenefitPdfDiagnostic $code '' 'No safe native semantic ruled table'))}
        } catch {$status='FAILED';$records.Clear();$diagnostics.Add((New-InternalBenefitPdfDiagnostic 'PDF_GEOMETRY_UNUSABLE' '' 'Native geometry could not be safely interpreted'))}
    }
    $index=New-BenefitDocumentValidationIndex -Snapshot $Snapshot -AdapterId PDF_GRID -AdapterVersion 1 -ExtractionMethod STRUCTURED_PDF_ROW -ExtractorId PDFPIG -ExtractorVersion 0.1.16 -ExtractionConfigHash (Get-BenefitPdfExtractionConfigHash) -Units @($records.ToArray())
    $units=@(foreach($record in $records){New-BenefitDocumentSourceContentUnit -Snapshot $Snapshot -ValidationIndex $index -UnitReference $record.UnitReference})
    New-BenefitSourceObservation -SourceRowNumber $Document.SourceRowNumber -Snapshot $Snapshot -AdapterId PDF_GRID -AdapterVersion 1 -AdapterStatus $status -ContentUnits $units -Diagnostics @($diagnostics.ToArray()) -DocumentValidationIndex $index
}

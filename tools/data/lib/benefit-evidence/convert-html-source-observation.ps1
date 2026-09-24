Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '../benefit-evidence-location-contracts.ps1')

function New-A1HtmlDiagnostic {
    param([string]$Code, [string]$Detail, [string]$EvidenceReference='')
    return [pscustomobject][ordered]@{ Code=$Code; Stage='HTML_PARSER'; EvidenceReference=$EvidenceReference; Detail=$Detail }
}

function Get-A1HtmlPairs {
    param([object[]]$Tokens, [string]$Tag)
    $stack = [Collections.Generic.List[object]]::new()
    $pairs = [Collections.Generic.List[object]]::new()
    $malformed = $false
    foreach ($token in $Tokens) {
        if ($token.Tag -cne $Tag) { continue }
        if (-not $token.IsClosing) {
            $stack.Add($token)
            continue
        }
        if ($stack.Count -eq 0) { $malformed=$true; continue }
        $open = $stack[$stack.Count-1]
        $stack.RemoveAt($stack.Count-1)
        $pairs.Add([pscustomobject]@{ Start=$open.Index; OpenLength=$open.Length; End=($token.Index+$token.Length); CloseStart=$token.Index; CloseLength=$token.Length })
    }
    if ($stack.Count -gt 0) { $malformed=$true }
    return [pscustomobject]@{ Pairs=@($pairs | Sort-Object Start); Malformed=$malformed }
}

function Get-A1ContainedHtmlPairs {
    param([object[]]$Pairs, [long]$Start, [long]$End)
    return @($Pairs | Where-Object { $_.Start -gt $Start -and $_.End -lt $End } | Sort-Object Start)
}

function Test-A1HtmlCellSpanSafe {
    param([string]$OpenTag)
    $matches = [regex]::Matches($OpenTag, '\b(?:rowspan|colspan)\s*=\s*(?<value>"[^"]*"|''[^'']*''|[^\s>]+)', [Text.RegularExpressions.RegexOptions]::IgnoreCase, [TimeSpan]::FromSeconds(1))
    foreach ($match in $matches) {
        $value = $match.Groups['value'].Value.Trim().Trim('"', '''').Trim()
        $number = 0
        if (-not [int]::TryParse($value, [ref]$number) -or $number -ne 1) { return $false }
    }
    if ($OpenTag -match '\b(?:rowspan|colspan)\b' -and $matches.Count -eq 0) { return $false }
    return $true
}

function Get-A1HtmlTableTemplate {
    param([string]$Text, $Table, [int]$PhysicalTableIndex, [object[]]$RowPairs, [object[]]$HeaderPairs, [object[]]$CellPairs)
    $tableEnd = [long]$Table.End
    $rows = @(Get-A1ContainedHtmlPairs -Pairs $RowPairs -Start $Table.Start -End $tableEnd)
    if ($rows.Count -eq 0) { return [pscustomobject]@{ IsCandidate=$false; IsSafe=$true; Rows=@(); Diagnostic=$null } }

    $headerRows = @()
    foreach ($row in $rows) {
        $headers = @(Get-A1ContainedHtmlPairs -Pairs $HeaderPairs -Start $row.Start -End $row.End)
        $cells = @(Get-A1ContainedHtmlPairs -Pairs $CellPairs -Start $row.Start -End $row.End)
        if ($headers.Count -gt 0) { $headerRows += [pscustomobject]@{ Row=$row; Headers=$headers; Cells=$cells } }
    }
    if ($headerRows.Count -eq 0) { return [pscustomobject]@{ IsCandidate=$false; IsSafe=$true; Rows=@(); Diagnostic=$null } }
    $headerRow = $headerRows[0]
    $headerTexts = @($headerRow.Headers | ForEach-Object { ConvertFrom-ScopeHtmlText -Text $Text.Substring([int]$_.Start,[int]($_.End-$_.Start)) })
    $map = Get-BenefitScopedHeaderMap
    $recognized = [ordered]@{}
    for ($i=0; $i -lt $headerTexts.Count; $i++) {
        if (-not $map.ContainsKey($headerTexts[$i])) { continue }
        $field = $map[$headerTexts[$i]]
        if ($recognized.Contains($field)) {
            $candidate = ($recognized.Contains('BusinessName') -or $field -ceq 'BusinessName')
            return [pscustomobject]@{ IsCandidate=$candidate; IsSafe=$false; Rows=@(); Diagnostic=(New-A1HtmlDiagnostic 'HTML_TABLE_UNSAFE' 'Duplicate recognized header mapping' "HTML_TABLE_$PhysicalTableIndex") }
        }
        $recognized[$field] = $i
    }
    if (-not $recognized.Contains('BusinessName')) { return [pscustomobject]@{ IsCandidate=$false; IsSafe=$true; Rows=@(); Diagnostic=$null } }
    if ($headerRows.Count -ne 1 -or $headerRow.Cells.Count -ne 0) {
        return [pscustomobject]@{ IsCandidate=$true; IsSafe=$false; Rows=@(); Diagnostic=(New-A1HtmlDiagnostic 'HTML_TABLE_UNSAFE' 'A candidate table must have one unambiguous header row' "HTML_TABLE_$PhysicalTableIndex") }
    }
    if (@($rows | Where-Object { $_.Start -lt $headerRow.Row.Start }).Count -gt 0) {
        return [pscustomobject]@{ IsCandidate=$true; IsSafe=$false; Rows=@(); Diagnostic=(New-A1HtmlDiagnostic 'HTML_TABLE_UNSAFE' 'Data rows before the header are unsupported' "HTML_TABLE_$PhysicalTableIndex") }
    }
    foreach ($header in $headerRow.Headers) {
        if (-not (Test-A1HtmlCellSpanSafe -OpenTag $Text.Substring([int]$header.Start,[int]$header.OpenLength))) {
            return [pscustomobject]@{ IsCandidate=$true; IsSafe=$false; Rows=@(); Diagnostic=(New-A1HtmlDiagnostic 'HTML_TABLE_UNSAFE' 'Header spans are unsupported' "HTML_TABLE_$PhysicalTableIndex") }
        }
    }

    $data = @()
    foreach ($row in $rows) {
        if ($row.Start -eq $headerRow.Row.Start) { continue }
        $headers = @(Get-A1ContainedHtmlPairs -Pairs $HeaderPairs -Start $row.Start -End $row.End)
        $cells = @(Get-A1ContainedHtmlPairs -Pairs $CellPairs -Start $row.Start -End $row.End)
        if ($headers.Count -gt 0 -or $cells.Count -ne $headerRow.Headers.Count) {
            return [pscustomobject]@{ IsCandidate=$true; IsSafe=$false; Rows=@(); Diagnostic=(New-A1HtmlDiagnostic 'HTML_TABLE_UNSAFE' 'Data cells cannot be aligned with the header' "HTML_TABLE_$PhysicalTableIndex") }
        }
        foreach ($cell in $cells) {
            if (-not (Test-A1HtmlCellSpanSafe -OpenTag $Text.Substring([int]$cell.Start,[int]$cell.OpenLength))) {
                return [pscustomobject]@{ IsCandidate=$true; IsSafe=$false; Rows=@(); Diagnostic=(New-A1HtmlDiagnostic 'HTML_TABLE_UNSAFE' 'Data cell spans are unsupported' "HTML_TABLE_$PhysicalTableIndex") }
            }
        }
        $fields = [ordered]@{}
        $references = [ordered]@{}
        $physicalRowIndex = (@($rows | ForEach-Object { $_.Start }).IndexOf($row.Start) + 1)
        $unitReference = "HTML_TABLE_${PhysicalTableIndex}_ROW_${physicalRowIndex}"
        foreach ($field in $recognized.Keys) {
            $column = [int]$recognized[$field]
            $header = $headerRow.Headers[$column]
            $cell = $cells[$column]
            $headerLength = [int]($header.End-$header.Start)
            $cellLength = [int]($cell.End-$cell.Start)
            $fields[$field] = ConvertFrom-ScopeHtmlText -Text $Text.Substring([int]$cell.Start,$cellLength)
            $references[$field] = [pscustomobject][ordered]@{
                HeaderStart=[long]$header.Start; HeaderLength=[long]$headerLength
                CellStart=[long]$cell.Start; CellLength=[long]$cellLength
                OriginalHeader=$headerTexts[$column]; FieldReference="$unitReference/$field"
            }
        }
        $data += [pscustomobject]@{ UnitReference=$unitReference; TableStart=[long]$Table.Start; TableLength=[long]($Table.End-$Table.Start); RawStart=[long]$row.Start; RawLength=[long]($row.End-$row.Start); RawEvidenceText=(ConvertFrom-ScopeHtmlText -Text $Text.Substring([int]$row.Start,[int]($row.End-$row.Start))); StructuredFields=$fields; FieldReferences=$references }
    }
    return [pscustomobject]@{ IsCandidate=$true; IsSafe=$true; Rows=@($data); Diagnostic=$null }
}

function ConvertTo-BenefitHtmlTemplate {
    param([Parameter(Mandatory)]$Snapshot)
    Assert-ScopeSnapshot $Snapshot
    if ($Snapshot.SourceFormat -cne 'HTML') {
        return [pscustomobject]@{ AdapterStatus='UNSUPPORTED'; Rows=@(); Diagnostics=@(New-A1HtmlDiagnostic 'HTML_FORMAT_UNSUPPORTED' 'Only HTML snapshots are supported') }
    }
    $tokens = @(Get-ScopeHtmlTagTokens -Text $Snapshot.Text)
    $tables = Get-A1HtmlPairs -Tokens $tokens -Tag 'table'
    $rows = Get-A1HtmlPairs -Tokens $tokens -Tag 'tr'
    $headers = Get-A1HtmlPairs -Tokens $tokens -Tag 'th'
    $cells = Get-A1HtmlPairs -Tokens $tokens -Tag 'td'
    $diagnostics = @()
    $resultRows = @()
    $candidateSeen = $false
    $unsafeSeen = $false
    $tableOpens = @($tokens | Where-Object { $_.Tag -ceq 'table' -and -not $_.IsClosing } | Sort-Object Index)
    $tablePairs = @($tables.Pairs | Sort-Object Start)
    foreach ($table in $tablePairs) {
        $physicalIndex = (@($tableOpens | ForEach-Object { $_.Index }).IndexOf($table.Start) + 1)
        $parentTables = @($tablePairs | Where-Object { $_.Start -lt $table.Start -and $_.End -gt $table.End })
        if ($parentTables.Count -gt 0) {
            $unsafeSeen=$true; $candidateSeen=$true
            $diagnostics += New-A1HtmlDiagnostic 'HTML_TABLE_UNSAFE' 'Nested tables are unsupported' "HTML_TABLE_$physicalIndex"
            continue
        }
        $nested = @($tableOpens | Where-Object { $_.Index -gt $table.Start -and $_.Index -lt $table.End })
        if ($nested.Count -gt 0) {
            $unsafeSeen=$true; $candidateSeen=$true
            $diagnostics += New-A1HtmlDiagnostic 'HTML_TABLE_UNSAFE' 'Nested tables are unsupported' "HTML_TABLE_$physicalIndex"
            continue
        }
        $template = Get-A1HtmlTableTemplate -Text $Snapshot.Text -Table $table -PhysicalTableIndex $physicalIndex -RowPairs $rows.Pairs -HeaderPairs $headers.Pairs -CellPairs $cells.Pairs
        if ($template.IsCandidate) { $candidateSeen=$true }
        if (-not $template.IsSafe) { $unsafeSeen=$true; $diagnostics += $template.Diagnostic; continue }
        $resultRows += $template.Rows
    }
    if ($tables.Malformed -or $rows.Malformed -or $headers.Malformed -or $cells.Malformed) {
        if ($candidateSeen -or $Snapshot.Text -match '업소명|업체명|사업장명|상호') {
            $unsafeSeen=$true; $diagnostics += New-A1HtmlDiagnostic 'HTML_STRUCTURE_PARTIAL' 'Unbalanced candidate HTML structure'
        }
    }
    if ($unsafeSeen) { $status='PARTIAL' }
    elseif (-not $candidateSeen) { $status='UNSUPPORTED' }
    else { $status='COMPLETE' }
    return [pscustomobject]@{ AdapterStatus=$status; Rows=@($resultRows); Diagnostics=@($diagnostics) }
}

function ConvertTo-BenefitHtmlObservation {
    param([Parameter(Mandatory)]$Document)
    Assert-BenefitSourceDocument $Document
    if ($Document.FetchStatus -cne 'COMPLETE') { throw 'HTML observation requires a successfully fetched source document' }
    $snapshot = New-BenefitSourceSnapshot -SourceUrl $Document.Url -SourceFormat $Document.SourceFormat -Text $Document.Text -ObservedAt $Document.ObservedAt
    $template = ConvertTo-BenefitHtmlTemplate -Snapshot $snapshot
    $units = @()
    foreach ($row in $template.Rows) {
        $units += New-BenefitSourceContentUnit -Snapshot $snapshot -UnitReference $row.UnitReference -TableStart $row.TableStart -TableLength $row.TableLength -RawStart $row.RawStart -RawLength $row.RawLength -RawEvidenceText $row.RawEvidenceText -StructuredFields $row.StructuredFields -FieldReferences $row.FieldReferences
    }
    return New-BenefitSourceObservation -SourceRowNumber $Document.SourceRowNumber -Snapshot $snapshot -AdapterId 'HTML_GENERIC' -AdapterVersion '1' -AdapterStatus $template.AdapterStatus -ContentUnits $units -Diagnostics $template.Diagnostics
}

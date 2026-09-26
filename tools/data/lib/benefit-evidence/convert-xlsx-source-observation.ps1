Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '../benefit-evidence-location-contracts.ps1')

function ConvertTo-BenefitXlsxObservation {
    param([Parameter(Mandatory)]$Document)
    Assert-BenefitSourceDocument $Document
    if ($Document.FetchStatus -cne 'COMPLETE' -or $Document.SourceFormat -cne 'XLSX') { throw 'XLSX observation requires a successfully fetched XLSX document' }
    $snapshot=New-BenefitSourceSnapshot -SourceUrl $Document.Url -SourceFormat XLSX -Text '' -Bytes $Document.Bytes -ObservedAt $Document.ObservedAt
    $index=New-BenefitXlsxValidationIndex -Snapshot $snapshot
    $units = [Collections.Generic.List[object]]::new()
    $diagnostics = [Collections.Generic.List[object]]::new()
    $map = Get-BenefitScopedHeaderMap
    $identityHeaderSeen = $false
    foreach ($sheet in @($index.Sheets)) {
        foreach ($header in @($sheet.Rows)) {
            $headers = @{}
            $mappedFields = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            $headerIsUsable = $true
            foreach ($cell in @($header.Cells.Values)) {
                if ($map.ContainsKey($cell.Value)) {
                    if (-not $cell.IsSupported -or $cell.HasFormula -or -not $mappedFields.Add($map[$cell.Value])) {
                        $headerIsUsable = $false
                        break
                    }
                    $headers[$cell.Column] = [pscustomobject]@{
                        Cell = $cell
                        Field = $map[$cell.Value]
                    }
                }
            }
            if ($headers.Count -eq 0) { continue }
            if (@($headers.Values | Where-Object { $_.Field -ceq 'BusinessName' }).Count -gt 0) { $identityHeaderSeen = $true }
            if (-not $headerIsUsable) {
                $diagnostics.Add([pscustomobject][ordered]@{ Code='XLSX_ROW_UNUSABLE'; Stage='XLSX_PARSER'; EvidenceReference="XLSX_SHEET_$($sheet.Index)_ROW_$($header.Number)"; Detail='Ambiguous or unsupported semantic header mapping' })
                continue
            }

            foreach ($row in @($sheet.Rows | Where-Object { $_.Number -gt $header.Number })) {
                $fields = [ordered]@{}
                $references = [ordered]@{}
                $rowIsUsable = @($row.Cells.Values | Where-Object { -not $_.IsSupported -or $_.HasFormula }).Count -eq 0
                foreach ($column in @($headers.Keys)) {
                    $headerField = $headers[$column]
                    $valueCells = @($row.Cells.Values | Where-Object { $_.Column -ceq $column })
                    if ($valueCells.Count -eq 0) { continue }
                    if ($valueCells.Count -ne 1 -or $valueCells[0].HasFormula) {
                        $rowIsUsable = $false
                        break
                    }

                    $valueCell = $valueCells[0]
                    $fields[$headerField.Field] = $valueCell.Value
                    $references[$headerField.Field] = [pscustomobject][ordered]@{
                        FieldReference = "XLSX_SHEET_$($sheet.Index)_ROW_$($row.Number)/$($headerField.Field)"
                        HeaderCellReference = $headerField.Cell.Reference
                        OriginalHeader = $headerField.Cell.Value
                        CellReference = $valueCell.Reference
                        CellType = $valueCell.CellType
                        RawValue = $valueCell.RawValue
                    }
                }
                if (-not $rowIsUsable) {
                    $diagnostics.Add([pscustomobject][ordered]@{ Code='XLSX_ROW_UNUSABLE'; Stage='XLSX_PARSER'; EvidenceReference="XLSX_SHEET_$($sheet.Index)_ROW_$($row.Number)"; Detail='Unsupported or formula-backed source cell' })
                    continue
                }
                if ($rowIsUsable -and $fields.Contains('BusinessName')) {
                    $units.Add((New-BenefitXlsxSourceContentUnit -Snapshot $snapshot -XlsxValidationIndex $index -SheetName $sheet.Name -SheetIndex $sheet.Index -HeaderRowNumber $header.Number -RowNumber $row.Number -StructuredFields $fields -FieldReferences $references))
                }
            }
        }
    }
    $adapterStatus = if ($diagnostics.Count -gt 0) { 'PARTIAL' } elseif (-not $identityHeaderSeen) { 'UNSUPPORTED' } else { 'COMPLETE' }
    $observation = New-BenefitSourceObservation -SourceRowNumber $Document.SourceRowNumber -Snapshot $snapshot -AdapterId XLSX_GENERIC -AdapterVersion '1' -AdapterStatus $adapterStatus -ContentUnits @($units) -Diagnostics @($diagnostics) -XlsxValidationIndex $index
    $observation | Add-Member -NotePropertyName XlsxValidationIndex -NotePropertyValue $index
    return $observation
}

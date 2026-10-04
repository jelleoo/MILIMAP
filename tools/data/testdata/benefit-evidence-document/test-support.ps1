# Synthetic structure fixtures only; never real benefit truth.
function New-DocumentTestPdfBytes {
    param([string]$Marker='synthetic')
    return ,([Text.Encoding]::ASCII.GetBytes("%PDF-1.7`n% $Marker`n%%EOF`n"))
}

function New-DocumentTestHwpxBytes {
    param([switch]$MissingContent,[switch]$MissingSection,[switch]$WrongMimetype,[switch]$DuplicateMimetype,[switch]$UnsafePath)
    $stream = [IO.MemoryStream]::new()
    try {
        $archive = [IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
        try {
            $parts = [ordered]@{ mimetype=$(if ($WrongMimetype) { 'application/zip' } else { 'application/hwp+zip' }) }
            if (-not $MissingContent) { $parts['Contents/content.hpf'] = '<package/>' }
            if (-not $MissingSection) { $parts['Contents/section0.xml'] = '<section/>' }
            if ($UnsafePath) { $parts['Contents/../unsafe.xml'] = '<unsafe/>' }
            foreach ($part in $parts.GetEnumerator()) {
                $writer = [IO.StreamWriter]::new($archive.CreateEntry($part.Key).Open(),[Text.UTF8Encoding]::new($false))
                try { $writer.Write($part.Value) } finally { $writer.Dispose() }
            }
            if ($DuplicateMimetype) {
                $writer = [IO.StreamWriter]::new($archive.CreateEntry('mimetype').Open(),[Text.UTF8Encoding]::new($false))
                try { $writer.Write('application/hwp+zip') } finally { $writer.Dispose() }
            }
        } finally { $archive.Dispose() }
        return ,($stream.ToArray())
    } finally { $stream.Dispose() }
}

function New-DocumentTestRowRecord {
    param([ValidateSet('PDF','HWPX')][string]$Format='PDF',[int]$Row=2,
        [string]$Name='합성가게 A',[string]$Address='경기도 양주시 테스트로 23',[string]$Phone='031-000-0001',[string]$Benefit='합성 혜택 A')
    $reference = if ($Format -ceq 'PDF') { "PDF_PAGE_1_TABLE_1_ROW_$Row" } else { "HWPX_SECTION_1_TABLE_1_ROW_$Row" }
    $path = if ($Format -ceq 'PDF') { "page/1/table/1/row/$Row" } else { "section/1/table/1/row/$Row" }
    $fields = [ordered]@{BusinessName=$Name;Address=$Address;Phone=$Phone;BenefitDescription=$Benefit}
    $refs = [ordered]@{}; $cell=1
    foreach ($key in $fields.Keys) {
        $refs[$key] = [pscustomobject][ordered]@{FieldReference="$reference/$key";PhysicalReference="$path/cell/$cell";SourceText=$fields[$key]}
        $cell++
    }
    return [pscustomobject][ordered]@{UnitType="${Format}_ROW";UnitReference=$reference;PhysicalPath=$path;RawEvidenceText=($fields.Values -join ' | ');StructuredFields=$fields;FieldReferences=$refs}
}

function New-DocumentTestFixture {
    param([ValidateSet('PDF','HWPX')][string]$Format='PDF',[object[]]$Rows=@(),[string]$ObservedAt='2026-10-05T00:00:00Z')
    $bytes = if ($Format -ceq 'PDF') { New-DocumentTestPdfBytes } else { New-DocumentTestHwpxBytes }
    $url = "https://city.example.go.kr/synthetic.$($Format.ToLowerInvariant())"
    $snapshot = New-BenefitSourceSnapshot -SourceUrl $url -SourceFormat $Format -Text '' -Bytes $bytes -ObservedAt $ObservedAt
    if ($Rows.Count -eq 0) { $Rows = @((New-DocumentTestRowRecord -Format $Format)) }
    $index = New-BenefitDocumentValidationIndex -Snapshot $snapshot -AdapterId "${Format}_SYNTHETIC" -AdapterVersion '1' -ExtractionMethod SYNTHETIC_DOCUMENT_ROW -ExtractorId TEST_FIXTURE -ExtractorVersion '1' -ExtractionConfigHash ('a' * 64) -Units $Rows
    $units = @(foreach ($row in $Rows) { New-BenefitDocumentSourceContentUnit -Snapshot $snapshot -ValidationIndex $index -UnitReference $row.UnitReference })
    $document = New-BenefitSourceDocument -SourceRowNumber 2 -Url $url -SourceFormat $Format -FetchStatus COMPLETE -Text '' -Bytes $bytes -ObservedAt $ObservedAt
    return [pscustomobject]@{Snapshot=$snapshot;Index=$index;Units=$units;Document=$document}
}

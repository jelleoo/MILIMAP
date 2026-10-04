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

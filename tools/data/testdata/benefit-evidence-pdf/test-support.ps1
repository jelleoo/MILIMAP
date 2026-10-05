# Independently authored, parseable synthetic PDF controls. No real benefit truth.
function Assert-PdfEqual { param($Actual,$Expected,[string]$Message); if($Actual -cne $Expected){throw "$Message (expected $Expected, actual $Actual)"} }
function Assert-PdfThrows { param([scriptblock]$Action,[string]$Message); try{& $Action}catch{return}; throw "$Message (not rejected)" }
function New-PdfTestDocument {
    param([string]$Fixture='two-business',[int]$SourceRowNumber=2)
    $bytes=[IO.File]::ReadAllBytes((Join-Path $PSScriptRoot "$Fixture.pdf"))
    New-BenefitSourceDocument -SourceRowNumber $SourceRowNumber -Url 'https://city.example.go.kr/synthetic.pdf' -SourceFormat PDF -FetchStatus COMPLETE -Text '' -Bytes $bytes -ObservedAt '2026-10-05T00:00:00Z'
}
function New-PdfTestBytes {
    param([string]$Content='BT /F1 12 Tf 20 100 Td (Synthetic native control) Tj ET',[int]$PageCount=1)
    $objects=@('<< /Type /Catalog /Pages 2 0 R >>','<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 300] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
        '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',("<< /Length $([Text.Encoding]::ASCII.GetByteCount($Content)) >>`nstream`n$Content`nendstream"))
    if ($PageCount -gt 1) {
        $kids=@('3 0 R')
        for($page=2;$page -le $PageCount;$page++) {
            $kids+= "$($objects.Count+1) 0 R"
            $objects += $objects[2]
        }
        $objects[1]="<< /Type /Pages /Kids [$($kids -join ' ')] /Count $PageCount >>"
    }
    $text="%PDF-1.4`n"; $offsets=[Collections.Generic.List[int]]::new()
    for($i=0;$i -lt $objects.Count;$i++){$offsets.Add([Text.Encoding]::ASCII.GetByteCount($text));$text+="$($i+1) 0 obj`n$($objects[$i])`nendobj`n"}
    $xref=[Text.Encoding]::ASCII.GetByteCount($text);$text+="xref`n0 $($objects.Count+1)`n0000000000 65535 f `n"
    foreach($offset in $offsets){$text+=($offset.ToString('D10',[Globalization.CultureInfo]::InvariantCulture)+" 00000 n `n")}
    $text+="trailer`n<< /Size $($objects.Count+1) /Root 1 0 R >>`nstartxref`n$xref`n%%EOF`n"
    return ,([Text.Encoding]::ASCII.GetBytes($text))
}

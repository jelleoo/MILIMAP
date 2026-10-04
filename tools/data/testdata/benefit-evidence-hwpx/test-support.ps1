# Synthetic structural fixtures only; not real benefit truth.
function New-HwpxTestBytes {
    param([AllowNull()][string]$RootXml=$null,[string[]]$Sections=@('<hs:sec xmlns:hs="http://www.hancom.co.kr/hwpml/2011/section"/>'),[AllowNull()][object[]]$ExtraEntries=@(),[string]$Mimetype='application/hwp+zip',[switch]$MissingRoot)
    if ([string]::IsNullOrEmpty($RootXml)) {
        $items=''; $refs=''
        for($i=0;$i -lt $Sections.Count;$i++){ $items += "<opf:item id='s$i' href='section$i.xml'/>"; $refs += "<opf:itemref idref='s$i'/>" }
        $RootXml="<opf:package xmlns:opf='http://www.idpf.org/2007/opf'><opf:manifest>$items</opf:manifest><opf:spine>$refs</opf:spine></opf:package>"
    }
    $stream=[IO.MemoryStream]::new()
    try {
        $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
        try {
            $entries=@([pscustomobject]@{Name='mimetype';Text=$Mimetype})
            if(-not $MissingRoot){$entries+= [pscustomobject]@{Name='Contents/content.hpf';Text=$RootXml}}
            for($i=0;$i -lt $Sections.Count;$i++){$entries+= [pscustomobject]@{Name="Contents/section$i.xml";Text=$Sections[$i]}}
            $entries+=@($ExtraEntries)
            foreach($item in $entries){$entry=$zip.CreateEntry($item.Name);$writer=[IO.StreamWriter]::new($entry.Open(),[Text.UTF8Encoding]::new($false));try{$writer.Write($item.Text)}finally{$writer.Dispose()}}
        } finally {$zip.Dispose()}
        return ,([byte[]]$stream.ToArray())
    } finally {$stream.Dispose()}
}
function New-HwpxTestSnapshot {
    param([byte[]]$Bytes=(New-HwpxTestBytes),[string]$Url='https://city.example.go.kr/synthetic.hwpx')
    New-BenefitSourceSnapshot -SourceUrl $Url -SourceFormat HWPX -Text '' -Bytes $Bytes -ObservedAt '2026-10-05T00:00:00Z'
}
function Assert-HwpxEqual { param($Actual,$Expected,[string]$Message); if($Actual -cne $Expected){throw "$Message (expected $Expected, actual $Actual)"} }
function Assert-HwpxThrows { param([scriptblock]$Action,[string]$Message);try{&$Action}catch{return};throw "$Message (not rejected)" }

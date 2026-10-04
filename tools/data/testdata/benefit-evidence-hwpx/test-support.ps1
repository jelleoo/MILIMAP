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
function New-HwpxTestCell {
    param([string]$Text='', [AllowNull()][string]$Inner=$null,[string]$Span="<hp:cellSpan rowSpan='1' colSpan='1'/>",[string]$Attributes='')
    if($null -eq $Inner -or $Inner -eq ''){$Inner='<hp:p><hp:run><hp:t>'+[Security.SecurityElement]::Escape($Text)+'</hp:t></hp:run></hp:p>'}
    "<hp:tc $Attributes>$Span<hp:subList>$Inner</hp:subList></hp:tc>"
}
function New-HwpxTestRow {param([string[]]$Cells);'<hp:tr>'+($Cells -join '')+'</hp:tr>'}
function New-HwpxTestTable {
    param([AllowNull()][string[]]$Rows=$null)
    if($null -eq $Rows){$Rows=@((New-HwpxTestRow @('업소명','주소','전화번호','혜택'|ForEach-Object{New-HwpxTestCell $_})),(New-HwpxTestRow @('합성가게 A','서울특별시 마포구 테스트로 12','02-0000-0012','합성 A 혜택'|ForEach-Object{New-HwpxTestCell $_})),(New-HwpxTestRow @('합성가게 B','서울특별시 마포구 테스트로 34','02-0000-0034','합성 B 혜택'|ForEach-Object{New-HwpxTestCell $_})))}
    '<hp:tbl>'+($Rows -join '')+'</hp:tbl>'
}
function New-HwpxTestSection {param([string]$Content=(New-HwpxTestTable));"<hs:sec xmlns:hs='http://www.hancom.co.kr/hwpml/2011/section' xmlns:hp='http://www.hancom.co.kr/hwpml/2011/paragraph'><hp:p><hp:run>$Content</hp:run></hp:p></hs:sec>"}
function New-HwpxTestDocument {
    param([byte[]]$Bytes=(New-HwpxTestBytes -Sections @((New-HwpxTestSection))),[int]$SourceRowNumber=2,[string]$Url='https://city.example.go.kr/synthetic.hwpx')
    New-BenefitSourceDocument -SourceRowNumber $SourceRowNumber -Url $Url -SourceFormat HWPX -FetchStatus COMPLETE -Text '' -Bytes $Bytes -ObservedAt '2026-10-05T00:00:00Z'
}

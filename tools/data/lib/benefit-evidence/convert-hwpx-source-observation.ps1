Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../benefit-evidence-location-contracts.ps1')
. (Join-Path $PSScriptRoot '../benefit-source/discover-official-benefit-sources.ps1')

function New-InternalBenefitHwpxDiagnostic {
    param([string]$Code,[string]$Reference,[string]$Detail)
    [pscustomobject][ordered]@{Code=$Code;Stage='HWPX_PARSER';EvidenceReference=$Reference;Detail=$Detail}
}
function Read-InternalBenefitHwpxXml {
    param([Parameter(Mandatory)]$Entry)
    $settings=[Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver=$null
    $settings.MaxCharactersInDocument=16777216
    $stream=$Entry.Open()
    try {
        $reader=[Xml.XmlReader]::Create($stream,$settings)
        try {$xml=[Xml.XmlDocument]::new();$xml.XmlResolver=$null;$xml.PreserveWhitespace=$true;$xml.Load($reader);return ,$xml}
        finally {$reader.Dispose()}
    } finally {$stream.Dispose()}
}
function Read-InternalBenefitHwpxPackage {
    param([Parameter(Mandatory)]$Snapshot)
    Assert-ScopeSnapshot $Snapshot
    if($Snapshot.SourceFormat -cne 'HWPX'){throw 'HWPX reader requires an HWPX snapshot'}
    $sections=[Collections.Generic.List[object]]::new();$diagnostics=[Collections.Generic.List[object]]::new()
    $status='COMPLETE';$stream=$null;$zip=$null
    try {
        if(-not (Test-BenefitHwpxBinaryPackage -Bytes $Snapshot.Bytes)){throw 'Unsafe or invalid HWPX package'}
        $stream=[IO.MemoryStream]::new($Snapshot.Bytes,$false)
        $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Read,$false)
        $entries=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach($entry in $zip.Entries){if(-not $entries.TryAdd($entry.FullName,$entry)){throw 'Duplicate package entry'}}
        $root=Read-InternalBenefitHwpxXml $entries['Contents/content.hpf']
        $ns=[Xml.XmlNamespaceManager]::new($root.NameTable);$ns.AddNamespace('o','http://www.idpf.org/2007/opf')
        if($root.DocumentElement.LocalName -cne 'package' -or $root.DocumentElement.NamespaceURI -cne $ns.LookupNamespace('o')){throw 'Untrusted OPF root'}
        if($root.SelectNodes('/o:package/o:manifest',$ns).Count -ne 1 -or $root.SelectNodes('/o:package/o:spine',$ns).Count -ne 1){throw 'Ambiguous manifest/spine'}
        $manifest=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
        foreach($item in $root.SelectNodes('/o:package/o:manifest/*',$ns)){
            if($item.LocalName -cne 'item' -or $item.NamespaceURI -cne $ns.LookupNamespace('o')){throw 'Untrusted manifest item'}
            $id=$item.GetAttribute('id');if([string]::IsNullOrWhiteSpace($id) -or -not $manifest.TryAdd($id,$item)){throw 'Duplicate/missing manifest ID'}
        }
        $resolved=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $members=[Collections.Generic.List[object]]::new()
        foreach($ref in $root.SelectNodes('/o:package/o:spine/*',$ns)){
            if($ref.LocalName -cne 'itemref' -or $ref.NamespaceURI -cne $ns.LookupNamespace('o')){throw 'Untrusted spine reference'}
            $id=$ref.GetAttribute('idref');if(-not $manifest.ContainsKey($id)){throw 'Missing manifest target'}
            $href=$manifest[$id].GetAttribute('href')
            # Only these two package-local forms are supported; no URI decoding or traversal.
            if($href -cnotmatch '^(?:Contents/)?section[0-9]+\.xml$'){throw 'Unsafe/non-section href'}
            $name=if($href.StartsWith('Contents/',[StringComparison]::Ordinal)){$href}else{'Contents/'+$href}
            if(-not $entries.ContainsKey($name) -or $entries[$name].FullName -cne $name -or -not $resolved.Add($name)){throw 'Missing/ambiguous section target'}
            $members.Add([pscustomobject]@{Ordinal=$members.Count+1;Name=$name})
        }
        if($members.Count -eq 0){throw 'Empty spine'}
        foreach($member in $members){
            try {
                $xml=Read-InternalBenefitHwpxXml $entries[$member.Name]
                if($xml.DocumentElement.LocalName -cne 'sec' -or $xml.DocumentElement.NamespaceURI -cne 'http://www.hancom.co.kr/hwpml/2011/section'){throw 'Untrusted section namespace/root'}
                $sections.Add([pscustomobject][ordered]@{SectionOrdinal=$member.Ordinal;EntryName=$member.Name;Xml=$xml})
            } catch {$status='PARTIAL';$diagnostics.Add((New-InternalBenefitHwpxDiagnostic 'HWPX_SECTION_UNUSABLE' $member.Name $_.Exception.Message))}
        }
    } catch {$status='FAILED';$sections.Clear();$diagnostics.Add((New-InternalBenefitHwpxDiagnostic 'HWPX_PACKAGE_UNUSABLE' '' $_.Exception.Message))}
    finally {if($null -ne $zip){$zip.Dispose()};if($null -ne $stream){$stream.Dispose()}}
    [pscustomobject][ordered]@{Status=$status;Sections=@($sections.ToArray());Diagnostics=@($diagnostics.ToArray())}
}

function Read-InternalBenefitHwpxTextNode {
    param([Parameter(Mandatory)]$Node)
    if($Node.NodeType -in @([Xml.XmlNodeType]::Text,[Xml.XmlNodeType]::CDATA)){return [string]$Node.Value}
    if($Node.NodeType -in @([Xml.XmlNodeType]::Whitespace,[Xml.XmlNodeType]::SignificantWhitespace,[Xml.XmlNodeType]::Comment)){return ''}
    if($Node.NodeType -ne [Xml.XmlNodeType]::Element -or $Node.NamespaceURI -cne 'http://www.hancom.co.kr/hwpml/2011/paragraph'){throw 'Unsupported semantic text node'}
    if($Node.LocalName -ceq 'lineBreak'){return "`n"}
    if($Node.LocalName -ceq 'tab'){return "`t"}
    if($Node.LocalName -cnotin @('subList','p','run','t')){throw 'Unsupported semantic inline object'}
    if($Node.LocalName -ceq 'subList'){
        # Only direct paragraphs are valid; separators are physical paragraph boundaries.
        $paragraphs=@($Node.ChildNodes|Where-Object{$_.NodeType -eq [Xml.XmlNodeType]::Element})
        foreach($p in $paragraphs){if($p.LocalName -cne 'p'){throw 'Unsupported cell text container'}}
        return (@($paragraphs|ForEach-Object{Read-InternalBenefitHwpxTextNode $_}) -join "`n")
    }
    $parts=[Collections.Generic.List[string]]::new()
    foreach($child in $Node.ChildNodes){$parts.Add((Read-InternalBenefitHwpxTextNode $child))}
    return ($parts -join '')
}
function Read-InternalBenefitHwpxCell {
    param([Parameter(Mandatory)]$Cell,[Parameter(Mandatory)]$NamespaceManager)
    $lists=@($Cell.SelectNodes('./hp:subList',$NamespaceManager))
    if($lists.Count -ne 1){throw 'Cell must have one supported text container'}
    foreach($child in @($Cell.ChildNodes|Where-Object{$_.NodeType -eq [Xml.XmlNodeType]::Element})){
        if($child.NamespaceURI -cne $NamespaceManager.LookupNamespace('hp') -or $child.LocalName -cnotin @('subList','cellSpan','cellAddr','cellSz','cellMargin')){throw 'Unsupported cell structure'}
    }
    $text=(Read-InternalBenefitHwpxTextNode $lists[0]).Trim()
    $spanNodes=@($Cell.SelectNodes('./hp:cellSpan',$NamespaceManager))
    $spanValid=$spanNodes.Count -le 1
    $hasSpan=$false
    if($spanNodes.Count -eq 1){$hasSpan=$true;$spanValid=$spanValid -and $spanNodes[0].GetAttribute('rowSpan') -ceq '1' -and $spanNodes[0].GetAttribute('colSpan') -ceq '1'}
    if($Cell.HasAttribute('rowSpan') -or $Cell.HasAttribute('colSpan')){$hasSpan=$true;$spanValid=$spanValid -and $Cell.GetAttribute('rowSpan') -ceq '1' -and $Cell.GetAttribute('colSpan') -ceq '1'}
    [pscustomobject]@{Text=$text;Unmerged=([bool]($hasSpan -and $spanValid))}
}
function ConvertTo-InternalBenefitHwpxObservation {
    param([Parameter(Mandatory)]$Document,[Parameter(Mandatory)]$Snapshot)
    # Shared conversion core retains strict contracts; P4-1 adds no trust bypass.
    Assert-BenefitSourceDocument $Document
    Assert-ScopeSnapshot $Snapshot
    if($Document.FetchStatus -cne 'COMPLETE' -or $Document.SourceFormat -cne 'HWPX' -or $Snapshot.SourceFormat -cne 'HWPX' -or
        $Snapshot.SourceUrl -cne $Document.Url -or $Snapshot.ObservedAt -cne $Document.ObservedAt -or
        -not [Linq.Enumerable]::SequenceEqual([byte[]]$Snapshot.Bytes,[byte[]]$Document.Bytes)){throw 'HWPX snapshot must preserve the successful source document'}
    $package=Read-InternalBenefitHwpxPackage $Snapshot
    $diagnostics=[Collections.Generic.List[object]]::new();foreach($d in $package.Diagnostics){$diagnostics.Add($d)}
    $records=[Collections.Generic.List[object]]::new();$hasHeader=$false;$isolated=$false
    $headers=Get-BenefitScopedHeaderMap
    foreach($section in $package.Sections){
        $ns=[Xml.XmlNamespaceManager]::new($section.Xml.NameTable);$ns.AddNamespace('hp','http://www.hancom.co.kr/hwpml/2011/paragraph')
        $tables=@($section.Xml.SelectNodes('//hp:tbl[not(ancestor::hp:tbl)]',$ns));$tableOrdinal=0
        foreach($table in $tables){
            $tableOrdinal++;$path="section/$($section.SectionOrdinal)/table/$tableOrdinal"
            $rows=@($table.SelectNodes('./hp:tr',$ns));$headerCandidates=[Collections.Generic.List[object]]::new();$badHeader=$false
            for($r=0;$r -lt $rows.Count;$r++){
                $cells=@($rows[$r].SelectNodes('./hp:tc',$ns));$mapping=[ordered]@{};$semanticSeen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$safe=$true;$nameSeen=$false
                for($c=0;$c -lt $cells.Count;$c++){
                    try{$read=Read-InternalBenefitHwpxCell $cells[$c] $ns}catch{continue}
                    if($headers.ContainsKey($read.Text)){
                        $field=[string]$headers[$read.Text];if($field -ceq 'BusinessName'){$nameSeen=$true}
                        if(-not $read.Unmerged -or -not $semanticSeen.Add($field)){$safe=$false}
                        $mapping.Add($c,$field)
                    }
                }
                if($nameSeen){if(-not $safe){$badHeader=$true}else{$headerCandidates.Add([pscustomobject]@{Row=$r;Mapping=$mapping;CellCount=$cells.Count})}}
            }
            if($badHeader -or $headerCandidates.Count -gt 1){$isolated=$true;$diagnostics.Add((New-InternalBenefitHwpxDiagnostic 'HWPX_HEADER_UNUSABLE' $path 'Ambiguous or merged semantic header'));continue}
            if($headerCandidates.Count -eq 0){continue}
            $hasHeader=$true;$header=$headerCandidates[0]
            for($r=$header.Row+1;$r -lt $rows.Count;$r++){
                $cells=@($rows[$r].SelectNodes('./hp:tc',$ns));$fields=[ordered]@{};$refs=[ordered]@{};$texts=[Collections.Generic.List[string]]::new();$safe=$true
                $unitReference="HWPX_SECTION_$($section.SectionOrdinal)_TABLE_${tableOrdinal}_ROW_$($r+1)";$rowPath="$path/row/$($r+1)"
                foreach($column in $header.Mapping.Keys){
                    if($column -ge $cells.Count){$safe=$false;continue}
                    try{$read=Read-InternalBenefitHwpxCell $cells[$column] $ns;if(-not $read.Unmerged){throw 'Merged semantic value'}
                        $field=$header.Mapping[[object]$column];$fields[$field]=[string]$read.Text
                        $refs[$field]=[pscustomobject][ordered]@{FieldReference="$unitReference/$field";PhysicalReference="$rowPath/cell/$($column+1)";SourceText=[string]$read.Text}
                        if($read.Text){$texts.Add($read.Text)}
                    }catch{$safe=$false}
                }
                if(-not $safe -or $cells.Count -ne $header.CellCount){$isolated=$true;$diagnostics.Add((New-InternalBenefitHwpxDiagnostic 'HWPX_ROW_UNUSABLE' $unitReference 'Unsupported/malformed mapped cells'));continue}
                if(-not $fields.Contains('BusinessName') -or [string]::IsNullOrWhiteSpace($fields.BusinessName)){continue}
                $records.Add([pscustomobject][ordered]@{UnitType='HWPX_ROW';UnitReference=$unitReference;PhysicalPath=$rowPath;RawEvidenceText=($texts -join ' | ');StructuredFields=$fields;FieldReferences=$refs})
            }
        }
    }
    $config='HWPX_GENERIC|1|BUILTIN_HWPX_XML|1|table-only|unmerged|text-only|paragraph=LF|line=LF|tab=TAB|outer-trim|'+(@($headers.Keys|Sort-Object -CaseSensitive|ForEach-Object{"$_=$($headers[$_])"}) -join '|')
    $configHash=Get-BenefitEvidenceTextHash -Text $config
    $index=New-BenefitDocumentValidationIndex -Snapshot $Snapshot -AdapterId HWPX_GENERIC -AdapterVersion 1 -ExtractionMethod STRUCTURED_HWPX_ROW -ExtractorId BUILTIN_HWPX_XML -ExtractorVersion 1 -ExtractionConfigHash $configHash -Units @($records.ToArray())
    $units=@(foreach($record in $records){New-BenefitDocumentSourceContentUnit -Snapshot $Snapshot -ValidationIndex $index -UnitReference $record.UnitReference})
    $status=if($package.Status -ceq 'FAILED'){'FAILED'}elseif($package.Status -ceq 'PARTIAL' -or $isolated){'PARTIAL'}elseif(-not $hasHeader){'UNSUPPORTED'}else{'COMPLETE'}
    New-BenefitSourceObservation -SourceRowNumber $Document.SourceRowNumber -Snapshot $Snapshot -AdapterId HWPX_GENERIC -AdapterVersion 1 -AdapterStatus $status -ContentUnits $units -Diagnostics @($diagnostics.ToArray()) -DocumentValidationIndex $index
}
function ConvertTo-BenefitHwpxObservation {
    param([Parameter(Mandatory)]$Document,[AllowNull()]$Snapshot=$null)
    Assert-BenefitSourceDocument $Document
    if($Document.SourceFormat -cne 'HWPX' -or $Document.FetchStatus -cne 'COMPLETE'){throw 'HWPX conversion requires successfully fetched HWPX bytes'}
    if($null -eq $Snapshot){$Snapshot=New-BenefitSourceSnapshot -SourceUrl $Document.Url -SourceFormat HWPX -Text '' -Bytes $Document.Bytes -ObservedAt $Document.ObservedAt}
    ConvertTo-InternalBenefitHwpxObservation -Document $Document -Snapshot $Snapshot
}

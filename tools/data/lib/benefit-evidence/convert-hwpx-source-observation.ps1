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

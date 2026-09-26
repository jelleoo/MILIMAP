Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'benefit-verification-contracts.ps1')

# These contracts are deliberately separate from the existing core registry.
# They describe source preparation, never officiality or benefit lifecycle.
function Get-BenefitEvidenceTextHash {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Get-BenefitEvidenceByteHash {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
$script:XlsxValidationLimits = [pscustomobject]@{ MaxEntries=256; MaxEntryBytes=8MB; MaxTotalBytes=32MB }
function Read-BenefitXlsxXml {
    param([Parameter(Mandatory)]$Entry)
    $settings=[Xml.XmlReaderSettings]::new(); $settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit; $settings.XmlResolver=$null
    $reader=[Xml.XmlReader]::Create($Entry.Open(),$settings)
    try { $doc=[Xml.XmlDocument]::new(); $doc.XmlResolver=$null; $doc.Load($reader); return $doc } finally { $reader.Dispose() }
}
function Get-BenefitXlsxColumn {
    param([Parameter(Mandatory)][string]$Reference)
    if ($Reference -cnotmatch '^([A-Z]+)([1-9]\d*)$') { throw 'Invalid XLSX cell reference' }
    return $Matches[1]
}
function New-BenefitXlsxValidationIndex {
    param([Parameter(Mandatory)]$Snapshot)
    Assert-ScopeSnapshot $Snapshot
    if ($Snapshot.SourceFormat -cne 'XLSX' -or $Snapshot.Bytes -isnot [byte[]]) { throw 'XLSX validation index requires an XLSX byte snapshot' }
    $stream = [IO.MemoryStream]::new($Snapshot.Bytes, $false)
    try {
        $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Read, $false)
        try {
            if ($archive.Entries.Count -gt $script:XlsxValidationLimits.MaxEntries) { throw 'XLSX archive entry count exceeds limit' }
            $total=[long]0
            $entries=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
            foreach ($entry in $archive.Entries) {
                if ([string]::IsNullOrWhiteSpace($entry.FullName) -or $entry.FullName -match '(^|/)\.\.(/|$)' -or $entry.FullName.StartsWith('/')) { throw 'Unsafe XLSX archive path' }
                if (-not $entries.TryAdd($entry.FullName,$entry)) { throw 'Duplicate XLSX archive entry' }
                if ($entry.Length -gt $script:XlsxValidationLimits.MaxEntryBytes) { throw 'XLSX archive entry exceeds limit' }
                $total += $entry.Length
                if ($total -gt $script:XlsxValidationLimits.MaxTotalBytes) { throw 'XLSX archive total exceeds limit' }
            }
            foreach($required in @('[Content_Types].xml','xl/workbook.xml','xl/_rels/workbook.xml.rels')) { if(-not $entries.ContainsKey($required)){throw "Missing XLSX package part: $required"} }
            $settings=[Xml.XmlReaderSettings]::new(); $settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit; $settings.XmlResolver=$null
            $reader=[Xml.XmlReader]::Create($entries['xl/workbook.xml'].Open(),$settings)
            try { $doc=[Xml.XmlDocument]::new(); $doc.XmlResolver=$null; $doc.Load($reader) } finally { $reader.Dispose() }
            $nsm=[Xml.XmlNamespaceManager]::new($doc.NameTable); $nsm.AddNamespace('x','http://schemas.openxmlformats.org/spreadsheetml/2006/main')
            $sheets=[Collections.Generic.List[object]]::new(); $sheetNames=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$sheetRelationshipIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$i=0
            foreach($sheet in @($doc.SelectNodes('/x:workbook/x:sheets/x:sheet',$nsm))) {
                $i++;$sheetName=$sheet.GetAttribute('name');$relationshipId=$sheet.GetAttribute('id','http://schemas.openxmlformats.org/officeDocument/2006/relationships')
                if([string]::IsNullOrWhiteSpace($sheetName) -or [string]::IsNullOrWhiteSpace($relationshipId) -or -not $sheetNames.Add($sheetName) -or -not $sheetRelationshipIds.Add($relationshipId)){throw 'Duplicate or invalid XLSX worksheet identity'}
                $sheets.Add([pscustomobject]@{Name=$sheetName;Index=$i;RelationshipId=$relationshipId})
            }
            $rels=Read-BenefitXlsxXml $entries['xl/_rels/workbook.xml.rels']; $rn=[Xml.XmlNamespaceManager]::new($rels.NameTable); $rn.AddNamespace('r','http://schemas.openxmlformats.org/package/2006/relationships')
            $targets=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal);$worksheetTargets=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach($rel in @($rels.SelectNodes('/r:Relationships/r:Relationship',$rn))) {
                if($rel.GetAttribute('TargetMode') -ceq 'External'){throw 'External XLSX relationship'}
                $relationshipId=$rel.GetAttribute('Id');$target=$rel.GetAttribute('Target')
                if([string]::IsNullOrWhiteSpace($relationshipId) -or [string]::IsNullOrWhiteSpace($target) -or $target -match '(^|/|\\)\.\.(/|\\|$)' -or $target.StartsWith('/') -or $target.Contains('\\')){throw 'Unsafe XLSX relationship target'}
                $packageTarget='xl/'+$target
                if(-not $targets.TryAdd($relationshipId,$packageTarget)){throw 'Duplicate XLSX relationship identifier'}
                if($sheetRelationshipIds.Contains($relationshipId) -and -not $worksheetTargets.Add($packageTarget)){throw 'Duplicate selected XLSX worksheet part'}
            }
            $shared=@(); if($entries.ContainsKey('xl/sharedStrings.xml')) { $sd=Read-BenefitXlsxXml $entries['xl/sharedStrings.xml']; $sn=[Xml.XmlNamespaceManager]::new($sd.NameTable);$sn.AddNamespace('x','http://schemas.openxmlformats.org/spreadsheetml/2006/main');$shared=@($sd.SelectNodes('/x:sst/x:si',$sn)|ForEach-Object{ ($_.SelectNodes('.//x:t',$sn)|ForEach-Object{$_.InnerText}) -join '' }) }
            foreach($sheet in $sheets) {
                if(-not $targets.ContainsKey($sheet.RelationshipId) -or -not $entries.ContainsKey($targets[$sheet.RelationshipId])){throw 'Missing XLSX worksheet part'}
                $sheet | Add-Member -NotePropertyName Part -NotePropertyValue $targets[$sheet.RelationshipId]
                $wd=Read-BenefitXlsxXml $entries[$sheet.Part];$wn=[Xml.XmlNamespaceManager]::new($wd.NameTable);$wn.AddNamespace('x','http://schemas.openxmlformats.org/spreadsheetml/2006/main');$rows=[Collections.Generic.List[object]]::new();$rowNumbers=[Collections.Generic.HashSet[int]]::new()
                foreach($row in @($wd.SelectNodes('/x:worksheet/x:sheetData/x:row',$wn))) {
                    $cells=@{}; $number=[int]$row.GetAttribute('r')
                    if($number -lt 1 -or -not $rowNumbers.Add($number)){throw 'Invalid or duplicate XLSX row'}
                    foreach($cell in @($row.SelectNodes('x:c',$wn))){
                        $r=$cell.GetAttribute('r')
                        if($r -cnotmatch '^[A-Z]+([1-9]\d*)$' -or [int]$Matches[1] -ne $number -or $cells.ContainsKey($r)){throw 'Invalid or duplicate XLSX cell'}
                        $type=$cell.GetAttribute('t');if(-not $type){$type='n'}
                        $valueNode=$cell.SelectSingleNode('x:v',$wn)
                        $raw=if($type -ceq 'inlineStr'){($cell.SelectNodes('x:is//x:t',$wn)|ForEach-Object{$_.InnerText})-join ''}elseif($null -ne $valueNode){[string]$valueNode.InnerText}else{''}
                        $isSupported=$type -in @('s','inlineStr','str','n')
                        $value=$raw
                        if($type -ceq 's'){
                            $sharedIndex=0
                            if($raw -notmatch '^\d+$' -or -not [int]::TryParse($raw,[ref]$sharedIndex) -or $sharedIndex -ge $shared.Count){throw 'Invalid shared string'}
                            $value=$shared[$sharedIndex]
                        }
                        $cells[$r]=[pscustomobject]@{Reference=$r;Column=(Get-BenefitXlsxColumn $r);Row=$number;CellType=$type;RawValue=$raw;Value=(ConvertTo-BenefitText $value);HasFormula=($null -ne $cell.SelectSingleNode('x:f',$wn));IsSupported=$isSupported}
                    }
                    $rows.Add([pscustomobject]@{Number=$number;Cells=$cells})
                }
                $sheet | Add-Member -NotePropertyName Rows -NotePropertyValue @($rows)
            }
        } finally { $archive.Dispose() }
    } finally { $stream.Dispose() }
    return [pscustomobject][ordered]@{ SnapshotId=$Snapshot.SnapshotId; ContentHash=$Snapshot.ContentHash; Sheets=@($sheets) }
}
function ConvertFrom-ScopeHtmlText {
    param([AllowEmptyString()][string]$Text)
    $withoutTags = [regex]::Replace($Text, '<[^>]+>', ' ', [Text.RegularExpressions.RegexOptions]::None, [TimeSpan]::FromSeconds(1))
    return (([Net.WebUtility]::HtmlDecode($withoutTags)) -replace '\s+', ' ').Trim()
}
function Get-BenefitScopedHeaderMap {
    return @{
        '업소명'='BusinessName'; '업체명'='BusinessName'; '사업장명'='BusinessName'; '상호'='BusinessName'
        '주소'='Address'; '소재지'='Address'; '소재지도로명주소'='Address'
        '전화번호'='Phone'; '연락처'='Phone'; '전화'='Phone'; '지점'='Branch'; '지점명'='Branch'
        '할인'='BenefitDescription'; '할인정보'='BenefitDescription'; '할인내용'='BenefitDescription'; '혜택'='BenefitDescription'
        '적용대상'='EligibleTarget'; '이용조건'='UsageCondition'; '인증방법'='VerificationMethod'
    }
}
function Assert-ScopeText {
    param([AllowNull()]$Value, [string]$Name)
    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value)) { throw "$Name must be nonempty text" }
}
function Assert-ScopeObject {
    param([AllowNull()]$Object, [string]$Type, [string[]]$Properties)
    if ($null -eq $Object -or $Object -isnot [pscustomobject]) { throw "Expected $Type object" }
    foreach ($key in @('ContractType','ContractVersion') + $Properties) {
        if ($Object.PSObject.Properties.Name -notcontains $key) { throw "$Type is missing $key" }
    }
    if ($Object.ContractType -cne $Type -or $Object.ContractVersion -ne 1) { throw "Invalid $Type type/version" }
}
function Copy-ScopeContractData {
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [byte[]]) { return ,([byte[]]$Value.Clone()) }
    if ($Value -is [Collections.IDictionary]) {
        $copy = [ordered]@{}
        foreach ($key in $Value.Keys) { $copy[$key] = Copy-ScopeContractData $Value[$key] }
        return ,$copy
    }
    if ($Value -is [array]) {
        $copy = [object[]]::new($Value.Count)
        for ($i=0; $i -lt $Value.Count; $i++) { $copy[$i] = Copy-ScopeContractData $Value[$i] }
        return ,$copy
    }
    if ($Value -is [pscustomobject]) {
        $copy = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) { $copy[$property.Name] = Copy-ScopeContractData $property.Value }
        return [pscustomobject]$copy
    }
    return $Value
}
function Get-BenefitJsonStringEnd {
    param([Parameter(Mandatory)][string]$JsonText, [int]$Start)
    if ($Start -lt 0 -or $Start -ge $JsonText.Length -or $JsonText[$Start] -cne '"') { throw 'JSON string must start with a quote' }
    $escaped = $false
    for ($i=$Start+1; $i -lt $JsonText.Length; $i++) {
        $character = $JsonText[$i]
        if ($escaped) { $escaped=$false; continue }
        if ($character -ceq '\') { $escaped=$true; continue }
        if ($character -ceq '"') { return $i+1 }
    }
    throw 'Unterminated JSON string'
}
function Skip-BenefitJsonWhitespace {
    param([Parameter(Mandatory)][string]$JsonText, [int]$Start)
    $index=$Start
    while ($index -lt $JsonText.Length -and [char]::IsWhiteSpace($JsonText[$index])) { $index++ }
    return $index
}
function Get-BenefitJsonValueEnd {
    param([Parameter(Mandatory)][string]$JsonText, [int]$Start)
    $index = Skip-BenefitJsonWhitespace $JsonText $Start
    if ($index -ge $JsonText.Length) { throw 'Missing JSON value' }
    if ($JsonText[$index] -ceq '"') { return Get-BenefitJsonStringEnd $JsonText $index }
    if ($JsonText[$index] -notin @('{','[')) {
        $end=$index
        while ($end -lt $JsonText.Length -and $JsonText[$end] -notin @(',','}',']') -and -not [char]::IsWhiteSpace($JsonText[$end])) { $end++ }
        if ($end -eq $index) { throw 'Invalid JSON scalar value' }
        return $end
    }
    $open=$JsonText[$index]; $close=if ($open -ceq '{') { '}' } else { ']' }
    $depth=0; $inString=$false; $escaped=$false
    for ($i=$index; $i -lt $JsonText.Length; $i++) {
        $character=$JsonText[$i]
        if ($inString) {
            if ($escaped) { $escaped=$false; continue }
            if ($character -ceq '\') { $escaped=$true; continue }
            if ($character -ceq '"') { $inString=$false }
            continue
        }
        if ($character -ceq '"') { $inString=$true; continue }
        if ($character -ceq $open) { $depth++; continue }
        if ($character -ceq $close) {
            $depth--
            if ($depth -eq 0) { return $i+1 }
            if ($depth -lt 0) { break }
        }
    }
    throw 'Unterminated JSON container'
}
function Get-BenefitJsonTopLevelPropertySpanIndex {
    param([Parameter(Mandatory)][string]$JsonText)
    $rootStart=Skip-BenefitJsonWhitespace $JsonText 0
    if ($rootStart -ge $JsonText.Length -or $JsonText[$rootStart] -cne '{') { throw 'MMA JSONP root must start with an object' }
    $rootEnd=Get-BenefitJsonValueEnd $JsonText $rootStart
    if ((Skip-BenefitJsonWhitespace $JsonText $rootEnd) -ne $JsonText.Length) { throw 'JSONP root has trailing data' }
    $position=$rootStart+1
    $index=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    while ($true) {
        $position=Skip-BenefitJsonWhitespace $JsonText $position
        if ($position -ge $rootEnd) { throw 'Unterminated JSON root object' }
        if ($JsonText[$position] -ceq '}') { break }
        $keyStart=$position; $keyEnd=Get-BenefitJsonStringEnd $JsonText $keyStart
        try { $key=[string](('{"value":' + $JsonText.Substring($keyStart,$keyEnd-$keyStart) + '}') | ConvertFrom-Json -ErrorAction Stop | Select-Object -ExpandProperty value) }
        catch { throw 'JSONP property name cannot be decoded' }
        $position=Skip-BenefitJsonWhitespace $JsonText $keyEnd
        if ($position -ge $rootEnd -or $JsonText[$position] -cne ':') { throw 'JSONP property is missing a colon' }
        $valueStart=Skip-BenefitJsonWhitespace $JsonText ($position+1)
        $valueEnd=Get-BenefitJsonValueEnd $JsonText $valueStart
        $span=[pscustomobject][ordered]@{ Start=[long]$valueStart; Length=[long]($valueEnd-$valueStart); Fragment=$JsonText.Substring($valueStart,$valueEnd-$valueStart) }
        if (-not $index.ContainsKey($key)) { $index[$key]=[Collections.Generic.List[object]]::new() }
        ([Collections.Generic.List[object]]$index[$key]).Add($span)
        $position=Skip-BenefitJsonWhitespace $JsonText $valueEnd
        if ($position -ge $rootEnd) { throw 'Unterminated JSON root object' }
        if ($JsonText[$position] -ceq '}') { break }
        if ($JsonText[$position] -cne ',') { throw 'JSONP root has invalid property separator' }
        $position++
    }
    return $index
}
function Get-BenefitJsonTopLevelPropertySpan {
    param([Parameter(Mandatory)][string]$JsonText, [Parameter(Mandatory)][string]$PropertyName)
    $index=Get-BenefitJsonTopLevelPropertySpanIndex -JsonText $JsonText
    if (-not $index.ContainsKey($PropertyName) -or @($index[$PropertyName]).Count -ne 1) { throw "MMA JSONP must contain exactly one $PropertyName property" }
    return @($index[$PropertyName])[0]
}
function Assert-ScopeTimestamp {
    param([AllowNull()]$Value)
    Assert-ScopeText $Value 'ObservedAt'
    $time = [DateTimeOffset]::MinValue
    if ($Value -cnotmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+-]\d{2}:\d{2})$' -or
        -not [DateTimeOffset]::TryParse($Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$time)) {
        throw 'ObservedAt must be an ISO timestamp with an explicit offset'
    }
}
function Get-ScopeSnapshotId {
    param([string]$SourceUrl, [string]$SourceFormat, [string]$ObservedAt, [string]$ContentHash)
    $identity = ConvertTo-Json -InputObject @($SourceUrl,$SourceFormat,$ObservedAt,$ContentHash) -Compress
    return Get-BenefitEvidenceTextHash -Text $identity
}
function Assert-ScopeSnapshot {
    param([AllowNull()]$Snapshot)
    Assert-ScopeObject $Snapshot 'BenefitSourceSnapshot' @('SnapshotId','SourceUrl','SourceFormat','Text','ObservedAt','ContentHash')
    Assert-ScopeText $Snapshot.SourceUrl 'SourceUrl'
    $uri = $null
    if (-not [uri]::TryCreate($Snapshot.SourceUrl, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -notin @('https','http') -or $uri.UserInfo -or $Snapshot.SourceUrl -cne $Snapshot.SourceUrl.Trim()) {
        throw 'SourceUrl must be an absolute HTTP(S) URL without embedded credentials'
    }
    Assert-BenefitAllowedCode 'SourceFormat' $Snapshot.SourceFormat
    if ($Snapshot.SourceFormat -ceq 'XLSX') {
        if ($Snapshot.Text -cne '' -or $Snapshot.PSObject.Properties.Name -notcontains 'Bytes' -or $Snapshot.Bytes -isnot [byte[]] -or $Snapshot.Bytes.Length -eq 0) { throw 'XLSX snapshot requires empty Text and original Bytes' }
    } else { Assert-ScopeText $Snapshot.Text 'Snapshot.Text' }
    Assert-ScopeTimestamp $Snapshot.ObservedAt
    $hash = if ($Snapshot.SourceFormat -ceq 'XLSX') { Get-BenefitEvidenceByteHash -Bytes $Snapshot.Bytes } else { Get-BenefitEvidenceTextHash -Text $Snapshot.Text }
    if ($Snapshot.ContentHash -cne $hash -or
        $Snapshot.SnapshotId -cne (Get-ScopeSnapshotId $Snapshot.SourceUrl $Snapshot.SourceFormat $Snapshot.ObservedAt $hash)) {
        throw 'Snapshot content or identity mismatch'
    }
    if ($Snapshot.PSObject.Properties.Name -contains 'SourceRowNumber') { throw 'Shared snapshot must not contain a canonical row number' }
}
function New-BenefitSourceSnapshot {
    param([Parameter(Mandatory)][string]$SourceUrl, [Parameter(Mandatory)][string]$SourceFormat,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text, [AllowNull()][byte[]]$Bytes=$null, [Parameter(Mandatory)][string]$ObservedAt)
    $hash = if ($SourceFormat -ceq 'XLSX') { Get-BenefitEvidenceByteHash -Bytes $Bytes } else { Get-BenefitEvidenceTextHash -Text $Text }
    $result = [pscustomobject][ordered]@{
        ContractType='BenefitSourceSnapshot'; ContractVersion=1
        SnapshotId=(Get-ScopeSnapshotId $SourceUrl $SourceFormat $ObservedAt $hash)
        SourceUrl=$SourceUrl; SourceFormat=$SourceFormat; Text=$Text; ObservedAt=$ObservedAt; ContentHash=$hash
    }
    if ($SourceFormat -ceq 'XLSX') { $result | Add-Member -NotePropertyName Bytes -NotePropertyValue ([byte[]]$Bytes.Clone()) }
    Assert-ScopeSnapshot $result
    return $result
}
function Assert-ScopeSpan {
    param([long]$Start, [long]$Length, [long]$ContainerStart, [long]$ContainerLength)
    # Subtraction avoids overflow in user-supplied start + length.
    if ($Start -lt $ContainerStart -or $Length -le 0 -or $Length -gt $ContainerLength -or
        ($Start - $ContainerStart) -gt ($ContainerLength - $Length)) { throw 'Source span is outside its container' }
}
function Get-ScopeHtmlTagTokens {
    param([Parameter(Mandatory)][string]$Text)
    # Position-only tokenizer: comments/raw-text and quoted attribute values are
    # opaque. It neither constructs business rows nor repairs malformed HTML.
    $tail = '(?:[^''"<>]|"[^"]*"|''[^'']*'')*>'
    $pattern = '<!--.*?(?:-->|\z)|<(?<Raw>script|style|textarea|title|xmp)\b' + $tail + '.*?(?:</\k<Raw>\s*>|\z)|<![^>]*>|<(?<Close>/)?(?<Tag>[a-z][a-z0-9:-]*)\b' + $tail
    $options = [Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [Text.RegularExpressions.RegexOptions]::Singleline
    foreach ($match in [regex]::Matches($Text, $pattern, $options, [TimeSpan]::FromSeconds(1))) {
        if (-not $match.Groups['Tag'].Success) { continue }
        [pscustomobject]@{ Tag=$match.Groups['Tag'].Value.ToLowerInvariant(); IsClosing=$match.Groups['Close'].Success; Index=$match.Index; Length=$match.Length }
    }
}
function Assert-ScopePhysicalUnitReference {
    param(
        [Parameter(Mandatory)]$Unit,
        [Parameter(Mandatory)][string]$Text,
        [AllowNull()][object[]]$HtmlTokens=$null
    )
    $tokens = if ($null -eq $HtmlTokens) { @(Get-ScopeHtmlTagTokens -Text $Text) } else { @($HtmlTokens) }
    $tables = @($tokens | Where-Object { $_.Tag -ceq 'table' -and -not $_.IsClosing })
    $tableIndex = -1
    for ($i=0; $i -lt $tables.Count; $i++) { if ($tables[$i].Index -eq $Unit.TableStart) { $tableIndex=$i+1; break } }
    $rows = @($tokens | Where-Object { $_.Tag -ceq 'tr' -and -not $_.IsClosing -and $_.Index -gt $Unit.TableStart -and $_.Index -lt ($Unit.TableStart+$Unit.TableLength) })
    $rowIndex = -1
    for ($i=0; $i -lt $rows.Count; $i++) { if ($rows[$i].Index -eq $Unit.RawStart) { $rowIndex=$i+1; break } }
    $tableEnd = @($tokens | Where-Object { $_.Tag -ceq 'table' -and $_.IsClosing -and ($_.Index+$_.Length) -eq ($Unit.TableStart+$Unit.TableLength) })
    $rowEnd = @($tokens | Where-Object { $_.Tag -ceq 'tr' -and $_.IsClosing -and ($_.Index+$_.Length) -eq ($Unit.RawStart+$Unit.RawLength) })
    if ($tableIndex -lt 1 -or $rowIndex -lt 1 -or $tableEnd.Count -ne 1 -or $rowEnd.Count -ne 1 -or
        $Unit.UnitReference -cne "HTML_TABLE_${tableIndex}_ROW_${rowIndex}") {
        throw 'Physical reference does not match original table and row positions'
    }
}
function Get-ScopeHtmlPairs {
    param([Parameter(Mandatory)][object[]]$Tokens, [Parameter(Mandatory)][string]$Tag)
    $stack = [Collections.Generic.List[object]]::new()
    $pairs = [Collections.Generic.List[object]]::new()
    foreach ($token in $Tokens) {
        if ($token.Tag -cne $Tag) { continue }
        if (-not $token.IsClosing) { $stack.Add($token); continue }
        if ($stack.Count -eq 0) { throw "Unbalanced $Tag source element" }
        $open = $stack[$stack.Count-1]
        $stack.RemoveAt($stack.Count-1)
        $pairs.Add([pscustomobject]@{ Start=[long]$open.Index; OpenLength=[long]$open.Length; End=[long]($token.Index+$token.Length); CloseStart=[long]$token.Index; CloseLength=[long]$token.Length })
    }
    if ($stack.Count -ne 0) { throw "Unbalanced $Tag source element" }
    return @($pairs | Sort-Object Start)
}
function New-ScopeHtmlValidationIndex {
    param([Parameter(Mandatory)]$Snapshot, [AllowNull()][object[]]$HtmlTokens=$null)
    Assert-ScopeSnapshot $Snapshot
    if ($Snapshot.SourceFormat -cne 'HTML') { throw 'HTML validation index requires an HTML snapshot' }
    $tokens = if ($null -eq $HtmlTokens) { @(Get-ScopeHtmlTagTokens -Text $Snapshot.Text) } else { @($HtmlTokens) }
    foreach ($token in @($tokens | Where-Object { -not $_.IsClosing -and $_.Tag -in @('table','tr','th','td') })) {
        $rawToken = $Snapshot.Text.Substring([int]$token.Index,[int]$token.Length)
        if (@([regex]::Matches($rawToken, '<(?:table|tr|th|td)\b', [Text.RegularExpressions.RegexOptions]::IgnoreCase)).Count -ne 1) { return $null }
    }
    try {
        return [pscustomobject]@{
            SnapshotId=$Snapshot.SnapshotId; Tokens=$tokens
            Tables=@(Get-ScopeHtmlPairs -Tokens $tokens -Tag 'table')
            Rows=@(Get-ScopeHtmlPairs -Tokens $tokens -Tag 'tr')
            Headers=@(Get-ScopeHtmlPairs -Tokens $tokens -Tag 'th')
            Cells=@(Get-ScopeHtmlPairs -Tokens $tokens -Tag 'td')
        }
    } catch {
        # Preserve the parser's existing PARTIAL/UNSUPPORTED semantics for
        # malformed source structure.  Only a complete physical index may
        # accelerate provenance validation.
        return $null
    }
}
function Assert-ScopeHtmlValidationIndex {
    param([AllowNull()]$HtmlValidationIndex, [Parameter(Mandatory)]$Snapshot)
    if ($null -eq $HtmlValidationIndex) { throw 'HTML validation index is required' }
    foreach ($property in @('SnapshotId','Tokens','Tables','Rows','Headers','Cells')) {
        if ($HtmlValidationIndex.PSObject.Properties.Name -notcontains $property) { throw "HTML validation index is missing $property" }
    }
    if ($HtmlValidationIndex.SnapshotId -cne $Snapshot.SnapshotId) { throw 'HTML validation index must belong to the original snapshot' }
}
function Get-ScopeElementFragment {
    param([string]$Text, [long]$Start, [long]$Length, [ValidateSet('table','tr','th','td')][string]$Tag)
    Assert-ScopeSpan $Start $Length 0 $Text.Length
    $fragment = $Text.Substring([int]$Start, [int]$Length)
    $options = [Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [Text.RegularExpressions.RegexOptions]::Singleline
    $timeout = [TimeSpan]::FromSeconds(1)
    if (-not [regex]::IsMatch($fragment, '\A<' + $Tag + '\b[^>]*>.*</' + $Tag + '\s*>\z', $options, $timeout) -or
        [regex]::Matches($fragment, '<' + $Tag + '\b', $options, $timeout).Count -ne 1 -or
        [regex]::Matches($fragment, '</' + $Tag + '\s*>', $options, $timeout).Count -ne 1) {
        throw "Expected one complete non-nested $Tag source element"
    }
    return $fragment
}
function Assert-ScopeHtmlUnit {
    param([AllowNull()]$Unit, [Parameter(Mandatory)]$Snapshot, [AllowNull()][object[]]$HtmlTokens=$null, [AllowNull()]$HtmlValidationIndex=$null)
    if ($null -ne $HtmlValidationIndex) { Assert-ScopeHtmlValidationIndex -HtmlValidationIndex $HtmlValidationIndex -Snapshot $Snapshot }
    else { Assert-ScopeSnapshot $Snapshot }
    Assert-ScopeObject $Unit 'SourceContentUnit' @('SnapshotId','UnitType','UnitReference','TableStart','TableLength','RawStart','RawLength','RawFragment','RawEvidenceText','StructuredFields','FieldReferences')
    if ($Snapshot.SourceFormat -cne 'HTML' -or $Unit.UnitType -cne 'TABLE_ROW' -or $Unit.SnapshotId -cne $Snapshot.SnapshotId) { throw 'Unit source/type mismatch' }
    if ($Unit.UnitReference -cnotmatch '^HTML_TABLE_[1-9]\d*_ROW_[1-9]\d*$') { throw 'Invalid physical unit reference' }
    Assert-ScopeSpan $Unit.TableStart $Unit.TableLength 0 $Snapshot.Text.Length
    Assert-ScopeSpan $Unit.RawStart $Unit.RawLength $Unit.TableStart $Unit.TableLength
    if ($null -ne $HtmlValidationIndex -or $null -ne $HtmlTokens) {
        if ($null -ne $HtmlValidationIndex) {
            Assert-ScopeHtmlValidationIndex -HtmlValidationIndex $HtmlValidationIndex -Snapshot $Snapshot
            $HtmlTokens=@($HtmlValidationIndex.Tokens); $tables=@($HtmlValidationIndex.Tables); $rows=@($HtmlValidationIndex.Rows); $headers=@($HtmlValidationIndex.Headers); $cells=@($HtmlValidationIndex.Cells)
        } else {
            $tables = @(Get-ScopeHtmlPairs -Tokens $HtmlTokens -Tag 'table')
            $rows = @(Get-ScopeHtmlPairs -Tokens $HtmlTokens -Tag 'tr')
            $headers = @(Get-ScopeHtmlPairs -Tokens $HtmlTokens -Tag 'th')
            $cells = @(Get-ScopeHtmlPairs -Tokens $HtmlTokens -Tag 'td')
        }
        $table = @($tables | Where-Object { $_.Start -eq $Unit.TableStart -and $_.End -eq ($Unit.TableStart+$Unit.TableLength) })
        $row = @($rows | Where-Object { $_.Start -eq $Unit.RawStart -and $_.End -eq ($Unit.RawStart+$Unit.RawLength) })
        if ($table.Count -ne 1 -or $row.Count -ne 1) { throw 'Expected one complete non-nested source element' }
        $tableIndex = @($tables | ForEach-Object { $_.Start }).IndexOf([long]$Unit.TableStart) + 1
        $physicalRows = @($rows | Where-Object { $_.Start -gt $Unit.TableStart -and $_.End -lt ($Unit.TableStart+$Unit.TableLength) })
        $rowIndex = @($physicalRows | ForEach-Object { $_.Start }).IndexOf([long]$Unit.RawStart) + 1
        if ($tableIndex -lt 1 -or $rowIndex -lt 1 -or $Unit.UnitReference -cne "HTML_TABLE_${tableIndex}_ROW_${rowIndex}") { throw 'Physical reference does not match original table and row positions' }
        if ($Snapshot.Text.Substring([int]$Unit.RawStart,[int]$Unit.RawLength) -cne $Unit.RawFragment -or (ConvertFrom-ScopeHtmlText $Unit.RawFragment) -cne $Unit.RawEvidenceText) { throw 'Unit raw/decoded text mismatch' }
        Assert-ScopeText $Unit.RawEvidenceText 'RawEvidenceText'
        if ($Unit.StructuredFields -isnot [Collections.IDictionary] -or $Unit.FieldReferences -isnot [Collections.IDictionary] -or $Unit.StructuredFields.Count -ne $Unit.FieldReferences.Count) { throw 'Fields and references must be matching dictionaries' }
        $tableHeaders = @($headers | Where-Object { $_.Start -gt $Unit.TableStart -and $_.End -lt ($Unit.TableStart+$Unit.TableLength) })
        $rowCells = @($cells | Where-Object { $_.Start -gt $Unit.RawStart -and $_.End -lt ($Unit.RawStart+$Unit.RawLength) })
        if ($Unit.StructuredFields.Count -gt 0 -and $tableHeaders.Count -ne $rowCells.Count) { throw 'Header/cell columns cannot be aligned safely' }
        $map = Get-BenefitScopedHeaderMap
        $usedHeaders = [Collections.Generic.HashSet[long]]::new()
        $usedCells = [Collections.Generic.HashSet[long]]::new()
        foreach ($key in $Unit.StructuredFields.Keys) {
            if (-not $Unit.FieldReferences.Contains($key)) { throw 'Missing field reference' }
            $reference = $Unit.FieldReferences[$key]
            if ($null -eq $reference) { throw 'Null field reference' }
            foreach ($property in @('HeaderStart','HeaderLength','CellStart','CellLength','OriginalHeader','FieldReference')) { if ($reference.PSObject.Properties.Name -notcontains $property) { throw "Field reference is missing $property" } }
            Assert-ScopeSpan $reference.HeaderStart $reference.HeaderLength $Unit.TableStart $Unit.TableLength
            Assert-ScopeSpan $reference.CellStart $reference.CellLength $Unit.RawStart $Unit.RawLength
            if ($reference.HeaderStart -ge $Unit.RawStart) { throw 'Header must precede the selected data row' }
            $header = @($tableHeaders | Where-Object { $_.Start -eq $reference.HeaderStart -and $_.OpenLength -le $reference.HeaderLength -and $_.End -eq ($reference.HeaderStart+$reference.HeaderLength) })
            $cell = @($rowCells | Where-Object { $_.Start -eq $reference.CellStart -and $_.OpenLength -le $reference.CellLength -and $_.End -eq ($reference.CellStart+$reference.CellLength) })
            if ($header.Count -ne 1 -or $cell.Count -ne 1) { throw 'Field span must match an original source element' }
            $headerText = ConvertFrom-ScopeHtmlText -Text $Snapshot.Text.Substring([int]$reference.HeaderStart,[int]$reference.HeaderLength)
            $cellText = ConvertFrom-ScopeHtmlText -Text $Snapshot.Text.Substring([int]$reference.CellStart,[int]$reference.CellLength)
            if ($headerText -cne $reference.OriginalHeader -or -not $map.ContainsKey($headerText) -or $map[$headerText] -cne $key) { throw 'Original header does not support the claimed field' }
            if ($Unit.StructuredFields[$key] -isnot [string] -or $cellText -cne $Unit.StructuredFields[$key]) { throw 'Field value does not match original cell' }
            if ($reference.FieldReference -cne ($Unit.UnitReference + '/' + $key)) { throw 'Field reference must belong to its physical unit and field' }
            if (-not $usedHeaders.Add([long]$reference.HeaderStart) -or -not $usedCells.Add([long]$reference.CellStart)) { throw 'Duplicate field source span' }
            $headerIndex = @($tableHeaders | ForEach-Object { $_.Start }).IndexOf([long]$reference.HeaderStart)
            $cellIndex = @($rowCells | ForEach-Object { $_.Start }).IndexOf([long]$reference.CellStart)
            if ($headerIndex -lt 0 -or $cellIndex -ne $headerIndex) { throw 'Header and cell must use the same original column' }
        }
        return
    }
    $table = Get-ScopeElementFragment $Snapshot.Text $Unit.TableStart $Unit.TableLength 'table'
    $row = Get-ScopeElementFragment $Snapshot.Text $Unit.RawStart $Unit.RawLength 'tr'
    Assert-ScopePhysicalUnitReference -Unit $Unit -Text $Snapshot.Text -HtmlTokens $HtmlTokens
    if ($row -cne $Unit.RawFragment -or (ConvertFrom-ScopeHtmlText $row) -cne $Unit.RawEvidenceText) { throw 'Unit raw/decoded text mismatch' }
    Assert-ScopeText $Unit.RawEvidenceText 'RawEvidenceText'
    if ($Unit.StructuredFields -isnot [Collections.IDictionary] -or $Unit.FieldReferences -isnot [Collections.IDictionary] -or
        $Unit.StructuredFields.Count -ne $Unit.FieldReferences.Count) { throw 'Fields and references must be matching dictionaries' }

    $map = Get-BenefitScopedHeaderMap
    $options = [Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [Text.RegularExpressions.RegexOptions]::Singleline
    $timeout = [TimeSpan]::FromSeconds(1)
    $headers = @([regex]::Matches($table, '<th\b[^>]*>.*?</th\s*>', $options, $timeout))
    $cells = @([regex]::Matches($row, '<td\b[^>]*>.*?</td\s*>', $options, $timeout))
    if ($Unit.StructuredFields.Count -gt 0 -and $headers.Count -ne $cells.Count) { throw 'Header/cell columns cannot be aligned safely' }
    $usedHeaders = [Collections.Generic.HashSet[long]]::new()
    $usedCells = [Collections.Generic.HashSet[long]]::new()
    foreach ($key in $Unit.StructuredFields.Keys) {
        if (-not $Unit.FieldReferences.Contains($key)) { throw 'Missing field reference' }
        $reference = $Unit.FieldReferences[$key]
        if ($null -eq $reference) { throw 'Null field reference' }
        foreach ($property in @('HeaderStart','HeaderLength','CellStart','CellLength','OriginalHeader','FieldReference')) {
            if ($reference.PSObject.Properties.Name -notcontains $property) { throw "Field reference is missing $property" }
        }
        Assert-ScopeSpan $reference.HeaderStart $reference.HeaderLength $Unit.TableStart $Unit.TableLength
        Assert-ScopeSpan $reference.CellStart $reference.CellLength $Unit.RawStart $Unit.RawLength
        if ($reference.HeaderStart -ge $Unit.RawStart) { throw 'Header must precede the selected data row' }
        $header = Get-ScopeElementFragment $Snapshot.Text $reference.HeaderStart $reference.HeaderLength 'th'
        $cell = Get-ScopeElementFragment $Snapshot.Text $reference.CellStart $reference.CellLength 'td'
        $headerText = ConvertFrom-ScopeHtmlText $header
        if ($headerText -cne $reference.OriginalHeader -or -not $map.ContainsKey($headerText) -or $map[$headerText] -cne $key) { throw 'Original header does not support the claimed field' }
        if ($Unit.StructuredFields[$key] -isnot [string] -or (ConvertFrom-ScopeHtmlText $cell) -cne $Unit.StructuredFields[$key]) { throw 'Field value does not match original cell' }
        if ($reference.FieldReference -cne ($Unit.UnitReference + '/' + $key)) { throw 'Field reference must belong to its physical unit and field' }
        if (-not $usedHeaders.Add([long]$reference.HeaderStart) -or -not $usedCells.Add([long]$reference.CellStart)) { throw 'Duplicate field source span' }
        $headerIndex = -1; $cellIndex = -1
        for ($i=0; $i -lt $headers.Count; $i++) {
            if (($Unit.TableStart + $headers[$i].Index) -eq $reference.HeaderStart -and $headers[$i].Length -eq $reference.HeaderLength) { $headerIndex=$i }
        }
        for ($i=0; $i -lt $cells.Count; $i++) {
            if (($Unit.RawStart + $cells[$i].Index) -eq $reference.CellStart -and $cells[$i].Length -eq $reference.CellLength) { $cellIndex=$i }
        }
        if ($headerIndex -lt 0 -or $cellIndex -ne $headerIndex) { throw 'Header and cell must use the same original column' }
    }
}
function Assert-ScopeJsonpUnitCore {
    param([AllowNull()]$Unit, [Parameter(Mandatory)]$Snapshot)
    Assert-ScopeObject $Unit 'SourceContentUnit' @('SnapshotId','UnitType','UnitReference','RawStart','RawLength','RawFragment','RawEvidenceText','StructuredFields','FieldReferences')
    if ($Snapshot.SourceFormat -cne 'JSONP' -or $Unit.UnitType -cne 'JSON_OBJECT' -or $Unit.SnapshotId -cne $Snapshot.SnapshotId) { throw 'JSONP unit source/type mismatch' }
    if ($Unit.UnitReference -cnotmatch '^JSONP_(?:LIST_ITEM_[1-9]\d*|DETAIL_OBJECT)$') { throw 'Invalid JSONP unit reference' }
    Assert-ScopeSpan $Unit.RawStart $Unit.RawLength 0 $Snapshot.Text.Length
    if ($Snapshot.Text.Substring([int]$Unit.RawStart,[int]$Unit.RawLength) -cne $Unit.RawFragment) { throw 'JSONP raw fragment mismatch' }
    Assert-ScopeText $Unit.RawEvidenceText 'RawEvidenceText'
    if ($Unit.StructuredFields -isnot [Collections.IDictionary] -or $Unit.FieldReferences -isnot [Collections.IDictionary] -or
        $Unit.StructuredFields.Count -ne $Unit.FieldReferences.Count) { throw 'JSONP fields and references must be matching dictionaries' }
    try { $rawObject = $Unit.RawFragment | ConvertFrom-Json -ErrorAction Stop }
    catch { throw 'JSONP unit raw fragment must be a valid JSON object' }
    if ($null -eq $rawObject -or $rawObject -is [array]) { throw 'JSONP unit raw fragment must be a JSON object' }
    $propertySpans=Get-BenefitJsonTopLevelPropertySpanIndex -JsonText $Unit.RawFragment
    foreach ($key in $Unit.StructuredFields.Keys) {
        if (-not $Unit.FieldReferences.Contains($key)) { throw 'Missing JSONP field reference' }
        $reference = $Unit.FieldReferences[$key]
        if ($null -eq $reference) { throw 'Null JSONP field reference' }
        foreach ($property in @('PropertyName','FieldReference','ValueStart','ValueLength')) {
            if ($reference.PSObject.Properties.Name -notcontains $property) { throw "JSONP field reference is missing $property" }
        }
        Assert-ScopeText $reference.PropertyName 'JSONP PropertyName'
        if ($reference.FieldReference -cne ($Unit.UnitReference + '/' + $reference.PropertyName)) { throw 'JSONP field reference must belong to selected object' }
        if ($rawObject.PSObject.Properties.Name -notcontains $reference.PropertyName) { throw 'JSONP field reference property is absent from selected raw object' }
        Assert-ScopeSpan $reference.ValueStart $reference.ValueLength $Unit.RawStart $Unit.RawLength
        if (-not $propertySpans.ContainsKey([string]$reference.PropertyName) -or @($propertySpans[[string]$reference.PropertyName]).Count -ne 1) { throw 'JSONP field reference property must occur exactly once in selected raw object' }
        $propertySpan = @($propertySpans[[string]$reference.PropertyName])[0]
        if ($reference.ValueStart -ne ($Unit.RawStart + $propertySpan.Start) -or $reference.ValueLength -ne $propertySpan.Length) { throw 'JSONP field value span does not match the selected raw property span' }
        try { $rawValue=('{"value":' + $Snapshot.Text.Substring([int]$reference.ValueStart,[int]$reference.ValueLength) + '}') | ConvertFrom-Json -ErrorAction Stop | Select-Object -ExpandProperty value }
        catch { throw 'JSONP field value span is not valid source JSON' }
        if ((ConvertTo-BenefitText $rawValue) -cne (ConvertTo-BenefitText $Unit.StructuredFields[$key])) { throw 'JSONP field value span does not match semantic field' }
        if ((ConvertTo-BenefitText $rawObject.($reference.PropertyName)) -cne (ConvertTo-BenefitText $Unit.StructuredFields[$key])) { throw 'JSONP field value does not match selected raw property' }
    }
}
function Assert-ScopeJsonpUnit {
    param([AllowNull()]$Unit, [Parameter(Mandatory)]$Snapshot)
    Assert-ScopeSnapshot $Snapshot
    Assert-ScopeJsonpUnitCore -Unit $Unit -Snapshot $Snapshot
}
function Assert-ScopeXlsxUnit {
    param([Parameter(Mandatory)]$Unit,[Parameter(Mandatory)]$Snapshot,[Parameter(Mandatory)]$XlsxValidationIndex)
    Assert-ScopeObject $Unit 'SourceContentUnit' @('SnapshotId','UnitType','UnitReference','SheetName','SheetIndex','HeaderRowNumber','RowNumber','StructuredFields','FieldReferences')
    foreach ($forbiddenRawProperty in @('RawStart','RawLength','RawFragment','RawEvidenceText','TableStart','TableLength')) {
        if ($Unit.PSObject.Properties.Name -contains $forbiddenRawProperty) { throw 'XLSX units must not carry synthetic raw-span provenance' }
    }
    if($Snapshot.SourceFormat -cne 'XLSX' -or $Unit.UnitType -cne 'XLSX_ROW' -or $Unit.SnapshotId -cne $Snapshot.SnapshotId -or $XlsxValidationIndex.SnapshotId -cne $Snapshot.SnapshotId -or $XlsxValidationIndex.ContentHash -cne $Snapshot.ContentHash){throw 'XLSX unit snapshot mismatch'}
    if($Unit.UnitReference -cne "XLSX_SHEET_$($Unit.SheetIndex)_ROW_$($Unit.RowNumber)" -or [int]$Unit.SheetIndex -lt 1 -or [int]$Unit.HeaderRowNumber -lt 1 -or [int]$Unit.RowNumber -le [int]$Unit.HeaderRowNumber){throw 'Invalid XLSX physical reference'}
    $s=@($XlsxValidationIndex.Sheets|Where-Object{$_.Name -ceq $Unit.SheetName -and $_.Index -eq $Unit.SheetIndex});if($s.Count -ne 1){throw 'XLSX sheet identity mismatch'};$header=@($s[0].Rows|Where-Object{$_.Number -eq $Unit.HeaderRowNumber});$row=@($s[0].Rows|Where-Object{$_.Number -eq $Unit.RowNumber});if($header.Count -ne 1 -or $row.Count -ne 1){throw 'XLSX row missing'}
    if($Unit.StructuredFields -isnot [Collections.IDictionary] -or $Unit.FieldReferences -isnot [Collections.IDictionary] -or $Unit.StructuredFields.Count -ne $Unit.FieldReferences.Count){throw 'XLSX fields mismatch'};$map=Get-BenefitScopedHeaderMap
    foreach($key in $Unit.StructuredFields.Keys){if(-not $Unit.FieldReferences.Contains($key)){throw 'Missing XLSX field reference'};$f=$Unit.FieldReferences[$key];foreach($p in @('FieldReference','HeaderCellReference','OriginalHeader','CellReference','CellType','RawValue')){if($f.PSObject.Properties.Name -notcontains $p){throw 'Incomplete XLSX field reference'}};$hc=$header[0].Cells[$f.HeaderCellReference];$vc=$row[0].Cells[$f.CellReference];if($null -eq $hc -or $null -eq $vc -or $hc.Column -cne $vc.Column -or $vc.Row -ne $Unit.RowNumber -or $hc.Row -ne $Unit.HeaderRowNumber -or $vc.HasFormula -or $f.CellType -cne $vc.CellType -or $f.RawValue -cne $vc.RawValue -or $f.OriginalHeader -cne $hc.Value -or -not $map.ContainsKey($hc.Value) -or $map[$hc.Value] -cne $key -or $Unit.StructuredFields[$key] -cne $vc.Value -or $f.FieldReference -cne ($Unit.UnitReference+'/'+$key)){throw 'XLSX field provenance mismatch'}}
}
function New-BenefitXlsxSourceContentUnit {
    param([Parameter(Mandatory)]$Snapshot,[Parameter(Mandatory)]$XlsxValidationIndex,[string]$SheetName,[int]$SheetIndex,[int]$HeaderRowNumber,[int]$RowNumber,[Parameter(Mandatory)][Collections.IDictionary]$StructuredFields,[Parameter(Mandatory)][Collections.IDictionary]$FieldReferences)
    $unit=[pscustomobject][ordered]@{ContractType='SourceContentUnit';ContractVersion=1;SnapshotId=$Snapshot.SnapshotId;UnitType='XLSX_ROW';UnitReference="XLSX_SHEET_${SheetIndex}_ROW_${RowNumber}";SheetName=$SheetName;SheetIndex=$SheetIndex;HeaderRowNumber=$HeaderRowNumber;RowNumber=$RowNumber;StructuredFields=(Copy-ScopeContractData $StructuredFields);FieldReferences=(Copy-ScopeContractData $FieldReferences)}
    Assert-ScopeXlsxUnit -Unit $unit -Snapshot $Snapshot -XlsxValidationIndex $XlsxValidationIndex;return $unit
}
function Assert-ScopeUnit {
    param([AllowNull()]$Unit, [Parameter(Mandatory)]$Snapshot, [AllowNull()][object[]]$HtmlTokens=$null, [AllowNull()]$HtmlValidationIndex=$null,[AllowNull()]$XlsxValidationIndex=$null)
    if ($null -ne $HtmlValidationIndex) { Assert-ScopeHtmlValidationIndex -HtmlValidationIndex $HtmlValidationIndex -Snapshot $Snapshot }
    else { Assert-ScopeSnapshot $Snapshot }
    if ($Snapshot.SourceFormat -ceq 'HTML') { Assert-ScopeHtmlUnit -Unit $Unit -Snapshot $Snapshot -HtmlTokens $HtmlTokens -HtmlValidationIndex $HtmlValidationIndex; return }
    if ($Snapshot.SourceFormat -ceq 'JSONP') { Assert-ScopeJsonpUnit $Unit $Snapshot; return }
    if ($Snapshot.SourceFormat -ceq 'XLSX') { if($null -eq $XlsxValidationIndex){throw 'XLSX validation index is required'};Assert-ScopeXlsxUnit -Unit $Unit -Snapshot $Snapshot -XlsxValidationIndex $XlsxValidationIndex;return }
    throw 'Unsupported scoped source format'
}
function New-BenefitSourceContentUnit {
    param([Parameter(Mandatory)]$Snapshot, [Parameter(Mandatory)][string]$UnitReference,
        [long]$TableStart, [long]$TableLength, [long]$RawStart, [long]$RawLength,
        [Parameter(Mandatory)][string]$RawEvidenceText,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.IDictionary]$StructuredFields,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.IDictionary]$FieldReferences,
        [AllowNull()][object[]]$HtmlTokens=$null, [AllowNull()]$HtmlValidationIndex=$null)
    Assert-ScopeSnapshot $Snapshot
    Assert-ScopeSpan $RawStart $RawLength 0 $Snapshot.Text.Length
    $result = [pscustomobject][ordered]@{
        ContractType='SourceContentUnit'; ContractVersion=1; SnapshotId=$Snapshot.SnapshotId
        UnitType='TABLE_ROW'; UnitReference=$UnitReference; TableStart=$TableStart; TableLength=$TableLength
        RawStart=$RawStart; RawLength=$RawLength; RawFragment=$Snapshot.Text.Substring([int]$RawStart,[int]$RawLength)
        RawEvidenceText=$RawEvidenceText; StructuredFields=(Copy-ScopeContractData $StructuredFields); FieldReferences=(Copy-ScopeContractData $FieldReferences)
    }
    Assert-ScopeUnit -Unit $result -Snapshot $Snapshot -HtmlTokens $HtmlTokens -HtmlValidationIndex $HtmlValidationIndex
    return $result
}
function New-BenefitJsonpSourceContentUnit {
    param([Parameter(Mandatory)]$Snapshot, [Parameter(Mandatory)][string]$UnitReference,
        [long]$RawStart, [long]$RawLength, [Parameter(Mandatory)][string]$RawEvidenceText,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.IDictionary]$StructuredFields,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.IDictionary]$FieldReferences)
    Assert-ScopeSnapshot $Snapshot
    Assert-ScopeSpan $RawStart $RawLength 0 $Snapshot.Text.Length
    $result = [pscustomobject][ordered]@{
        ContractType='SourceContentUnit'; ContractVersion=1; SnapshotId=$Snapshot.SnapshotId
        UnitType='JSON_OBJECT'; UnitReference=$UnitReference; RawStart=$RawStart; RawLength=$RawLength
        RawFragment=$Snapshot.Text.Substring([int]$RawStart,[int]$RawLength); RawEvidenceText=$RawEvidenceText
        StructuredFields=(Copy-ScopeContractData $StructuredFields); FieldReferences=(Copy-ScopeContractData $FieldReferences)
    }
    Assert-ScopeUnit $result $Snapshot
    return $result
}
function Assert-ScopeDiagnostics {
    param([AllowEmptyCollection()][object[]]$Diagnostics)
    foreach ($diagnostic in $Diagnostics) {
        if ($null -eq $diagnostic) { throw 'Null diagnostic' }
        foreach ($key in @('Code','Stage','EvidenceReference','Detail')) {
            if ($diagnostic.PSObject.Properties.Name -notcontains $key -or $diagnostic.$key -isnot [string]) { throw "Diagnostic requires text property $key" }
        }
        Assert-ScopeText $diagnostic.Code 'Diagnostic.Code'
        Assert-ScopeText $diagnostic.Stage 'Diagnostic.Stage'
    }
}
function Assert-ScopeObservation {
    param([AllowNull()]$Observation, [AllowNull()][object[]]$HtmlTokens=$null, [AllowNull()]$HtmlValidationIndex=$null, [AllowNull()]$XlsxValidationIndex=$null)
    Assert-ScopeObject $Observation 'SourceObservation' @('SourceRowNumber','SnapshotId','SourceUrl','SourceFormat','ObservedAt','Snapshot','AdapterId','AdapterVersion','AdapterStatus','ContentUnits','Diagnostics')
    Assert-BenefitSourceRowNumber $Observation.SourceRowNumber
    Assert-ScopeSnapshot $Observation.Snapshot
    foreach ($key in @('SnapshotId','SourceUrl','SourceFormat','ObservedAt')) {
        if ($Observation.$key -cne $Observation.Snapshot.$key) { throw 'Observation must preserve snapshot identity' }
    }
    Assert-ScopeText $Observation.AdapterId 'AdapterId'
    Assert-ScopeText $Observation.AdapterVersion 'AdapterVersion'
    if ($Observation.AdapterStatus -cnotin @('COMPLETE','PARTIAL','FAILED','UNSUPPORTED')) { throw 'Invalid adapter status' }
    if ($Observation.ContentUnits -isnot [array] -or $Observation.Diagnostics -isnot [array]) { throw 'Observation collections must remain arrays' }
    if ($Observation.AdapterStatus -cin @('FAILED','UNSUPPORTED') -and $Observation.ContentUnits.Count -gt 0) { throw 'Failed adapter must not supply content units' }
    $references = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($unit in $Observation.ContentUnits) {
        if ($Observation.SourceFormat -ceq 'JSONP') {
            Assert-ScopeJsonpUnitCore -Unit $unit -Snapshot $Observation.Snapshot
        } else {
            Assert-ScopeUnit -Unit $unit -Snapshot $Observation.Snapshot -HtmlTokens $HtmlTokens -HtmlValidationIndex $HtmlValidationIndex -XlsxValidationIndex $XlsxValidationIndex
        }
        if (-not $references.Add([string]$unit.UnitReference)) { throw 'Duplicate content unit reference' }
    }
    Assert-ScopeDiagnostics $Observation.Diagnostics
}
function New-BenefitSourceObservation {
    param([int]$SourceRowNumber, [Parameter(Mandatory)]$Snapshot, [Parameter(Mandatory)][string]$AdapterId,
        [Parameter(Mandatory)][string]$AdapterVersion, [Parameter(Mandatory)][string]$AdapterStatus,
        [AllowEmptyCollection()][object[]]$ContentUnits=@(), [AllowEmptyCollection()][object[]]$Diagnostics=@(),
        [AllowNull()][object[]]$HtmlTokens=$null, [AllowNull()]$HtmlValidationIndex=$null, [AllowNull()]$XlsxValidationIndex=$null)
    Assert-ScopeSnapshot $Snapshot
    $result = [pscustomobject][ordered]@{
        ContractType='SourceObservation'; ContractVersion=1; SourceRowNumber=$SourceRowNumber
        SnapshotId=$Snapshot.SnapshotId; SourceUrl=$Snapshot.SourceUrl; SourceFormat=$Snapshot.SourceFormat; ObservedAt=$Snapshot.ObservedAt
        Snapshot=(Copy-ScopeContractData $Snapshot); AdapterId=$AdapterId; AdapterVersion=$AdapterVersion; AdapterStatus=$AdapterStatus
        ContentUnits=(Copy-ScopeContractData $ContentUnits); Diagnostics=(Copy-ScopeContractData $Diagnostics)
    }
    Assert-ScopeObservation -Observation $result -HtmlTokens $HtmlTokens -HtmlValidationIndex $HtmlValidationIndex -XlsxValidationIndex $XlsxValidationIndex
    return $result
}
function Assert-ScopeSliceShape {
    param([AllowNull()]$Slice, [int]$SourceRowNumber)
    Assert-ScopeObject $Slice 'RelevantEvidenceSlice' @('SourceRowNumber','SnapshotId','ContentHash','SourceUrl','SourceFormat','ObservedAt','LocatorMethod','ScopeType','EvidenceReference','StructuredFields','FieldReferences','IdentityEvidence')
    Assert-BenefitSourceRowNumber $SourceRowNumber
    if ($Slice.SourceRowNumber -ne $SourceRowNumber) { throw 'Slice source row mismatch' }
    if ($Slice.SourceFormat -ceq 'HTML') {
        Assert-ScopeObject $Slice 'RelevantEvidenceSlice' @('TableStart','TableLength','RawStart','RawLength','RawFragment','RawEvidenceText')
        if ($Slice.ScopeType -cne 'TABLE_ROW' -or $Slice.LocatorMethod -cne 'STRUCTURED_HTML_ROW' -or $Slice.EvidenceReference -cnotmatch '^HTML_TABLE_[1-9]\d*_ROW_[1-9]\d*$') { throw 'HTML slice scope mismatch' }
    } elseif ($Slice.SourceFormat -ceq 'JSONP') {
        Assert-ScopeObject $Slice 'RelevantEvidenceSlice' @('RawStart','RawLength','RawFragment','RawEvidenceText')
        if ($Slice.ScopeType -cne 'JSON_OBJECT' -or $Slice.LocatorMethod -cne 'STRUCTURED_JSONP_OBJECT' -or $Slice.EvidenceReference -cnotmatch '^JSONP_(?:LIST_ITEM_[1-9]\d*|DETAIL_OBJECT)$') { throw 'JSONP slice scope mismatch' }
    } elseif ($Slice.SourceFormat -ceq 'XLSX') {
        Assert-ScopeObject $Slice 'RelevantEvidenceSlice' @('SheetName','SheetIndex','HeaderRowNumber','RowNumber')
        foreach ($forbiddenRawProperty in @('RawStart','RawLength','RawFragment','RawEvidenceText','TableStart','TableLength')) {
            if ($Slice.PSObject.Properties.Name -contains $forbiddenRawProperty) { throw 'XLSX slices must not carry synthetic raw-span provenance' }
        }
        if ($Slice.ScopeType -cne 'XLSX_ROW' -or $Slice.LocatorMethod -cne 'STRUCTURED_XLSX_ROW' -or $Slice.EvidenceReference -cnotmatch '^XLSX_SHEET_[1-9]\d*_ROW_[1-9]\d*$') { throw 'XLSX slice scope mismatch' }
    } else { throw 'Unsupported slice source format' }
    if ($Slice.ContentHash -cnotmatch '^[0-9a-f]{64}$' -or $Slice.SnapshotId -cnotmatch '^[0-9a-f]{64}$') { throw 'Invalid slice hash' }
    Assert-ScopeText $Slice.SourceUrl 'Slice.SourceUrl'
    Assert-ScopeTimestamp $Slice.ObservedAt
    if ($Slice.IdentityEvidence -isnot [array]) { throw 'IdentityEvidence must remain an array' }
    foreach ($signal in $Slice.IdentityEvidence) { Assert-ScopeText $signal 'IdentityEvidence signal' }
}
function Assert-ScopeSliceAgainstSnapshot {
    param([AllowNull()]$Slice, [Parameter(Mandatory)]$Snapshot, [int]$SourceRowNumber, [AllowNull()][object[]]$HtmlTokens=$null, [AllowNull()]$HtmlValidationIndex=$null, [AllowNull()]$XlsxValidationIndex=$null)
    Assert-ScopeSliceShape $Slice $SourceRowNumber
    Assert-ScopeSnapshot $Snapshot
    foreach ($key in @('SnapshotId','ContentHash','SourceUrl','SourceFormat','ObservedAt')) {
        if ($Slice.$key -cne $Snapshot.$key) { throw 'Slice must preserve original source snapshot' }
    }
    $unit = if ($Snapshot.SourceFormat -ceq 'HTML') {
        [pscustomobject][ordered]@{
            ContractType='SourceContentUnit'; ContractVersion=1; SnapshotId=$Slice.SnapshotId; UnitType='TABLE_ROW'
            UnitReference=$Slice.EvidenceReference; TableStart=$Slice.TableStart; TableLength=$Slice.TableLength
            RawStart=$Slice.RawStart; RawLength=$Slice.RawLength; RawFragment=$Slice.RawFragment
            RawEvidenceText=$Slice.RawEvidenceText; StructuredFields=$Slice.StructuredFields; FieldReferences=$Slice.FieldReferences
        }
    } elseif ($Snapshot.SourceFormat -ceq 'JSONP') {
        [pscustomobject][ordered]@{
            ContractType='SourceContentUnit'; ContractVersion=1; SnapshotId=$Slice.SnapshotId; UnitType='JSON_OBJECT'
            UnitReference=$Slice.EvidenceReference; RawStart=$Slice.RawStart; RawLength=$Slice.RawLength; RawFragment=$Slice.RawFragment
            RawEvidenceText=$Slice.RawEvidenceText; StructuredFields=$Slice.StructuredFields; FieldReferences=$Slice.FieldReferences
        }
    } elseif ($Snapshot.SourceFormat -ceq 'XLSX') {
        [pscustomobject][ordered]@{
            ContractType='SourceContentUnit'; ContractVersion=1; SnapshotId=$Slice.SnapshotId; UnitType='XLSX_ROW'
            UnitReference=$Slice.EvidenceReference; SheetName=$Slice.SheetName; SheetIndex=$Slice.SheetIndex
            HeaderRowNumber=$Slice.HeaderRowNumber; RowNumber=$Slice.RowNumber
            StructuredFields=$Slice.StructuredFields; FieldReferences=$Slice.FieldReferences
        }
    } else { throw 'Unsupported slice source format' }
    Assert-ScopeUnit -Unit $unit -Snapshot $Snapshot -HtmlTokens $HtmlTokens -HtmlValidationIndex $HtmlValidationIndex -XlsxValidationIndex $XlsxValidationIndex
}
function New-RelevantBenefitEvidenceSlice {
    param([Parameter(Mandatory)]$Observation, [Parameter(Mandatory)]$Unit, [AllowEmptyCollection()][object[]]$IdentityEvidence=@(), [AllowNull()][object[]]$HtmlTokens=$null, [AllowNull()]$HtmlValidationIndex=$null, [AllowNull()]$XlsxValidationIndex=$null)
    Assert-ScopeObservation -Observation $Observation -HtmlTokens $HtmlTokens -HtmlValidationIndex $HtmlValidationIndex -XlsxValidationIndex $XlsxValidationIndex
    if ($Observation.AdapterStatus -cne 'COMPLETE') { throw 'Only a complete observation can yield a usable slice' }
    Assert-ScopeUnit -Unit $Unit -Snapshot $Observation.Snapshot -HtmlTokens $HtmlTokens -HtmlValidationIndex $HtmlValidationIndex -XlsxValidationIndex $XlsxValidationIndex
    $members = @($Observation.ContentUnits | Where-Object { $_.UnitReference -ceq $Unit.UnitReference })
    if ($members.Count -ne 1 -or
        (ConvertTo-Json -InputObject $members[0] -Depth 20 -Compress) -cne (ConvertTo-Json -InputObject $Unit -Depth 20 -Compress)) {
        throw 'Slice unit must be an exact member of its observation'
    }
    $result = if ($Observation.SourceFormat -ceq 'HTML') {
        [pscustomobject][ordered]@{
            ContractType='RelevantEvidenceSlice'; ContractVersion=1; SourceRowNumber=$Observation.SourceRowNumber
            SnapshotId=$Observation.SnapshotId; ContentHash=$Observation.Snapshot.ContentHash
            SourceUrl=$Observation.SourceUrl; SourceFormat=$Observation.SourceFormat; ObservedAt=$Observation.ObservedAt
            LocatorMethod='STRUCTURED_HTML_ROW'; ScopeType='TABLE_ROW'; EvidenceReference=$Unit.UnitReference
            TableStart=$Unit.TableStart; TableLength=$Unit.TableLength; RawStart=$Unit.RawStart; RawLength=$Unit.RawLength
            RawFragment=$Unit.RawFragment; RawEvidenceText=$Unit.RawEvidenceText
            StructuredFields=(Copy-ScopeContractData $Unit.StructuredFields); FieldReferences=(Copy-ScopeContractData $Unit.FieldReferences)
            IdentityEvidence=(Copy-ScopeContractData $IdentityEvidence)
        }
    } elseif ($Observation.SourceFormat -ceq 'JSONP') {
        [pscustomobject][ordered]@{
            ContractType='RelevantEvidenceSlice'; ContractVersion=1; SourceRowNumber=$Observation.SourceRowNumber
            SnapshotId=$Observation.SnapshotId; ContentHash=$Observation.Snapshot.ContentHash
            SourceUrl=$Observation.SourceUrl; SourceFormat=$Observation.SourceFormat; ObservedAt=$Observation.ObservedAt
            LocatorMethod='STRUCTURED_JSONP_OBJECT'; ScopeType='JSON_OBJECT'; EvidenceReference=$Unit.UnitReference
            RawStart=$Unit.RawStart; RawLength=$Unit.RawLength; RawFragment=$Unit.RawFragment; RawEvidenceText=$Unit.RawEvidenceText
            StructuredFields=(Copy-ScopeContractData $Unit.StructuredFields); FieldReferences=(Copy-ScopeContractData $Unit.FieldReferences)
            IdentityEvidence=(Copy-ScopeContractData $IdentityEvidence)
        }
    } elseif ($Observation.SourceFormat -ceq 'XLSX') {
        [pscustomobject][ordered]@{
            ContractType='RelevantEvidenceSlice'; ContractVersion=1; SourceRowNumber=$Observation.SourceRowNumber
            SnapshotId=$Observation.SnapshotId; ContentHash=$Observation.Snapshot.ContentHash
            SourceUrl=$Observation.SourceUrl; SourceFormat=$Observation.SourceFormat; ObservedAt=$Observation.ObservedAt
            LocatorMethod='STRUCTURED_XLSX_ROW'; ScopeType='XLSX_ROW'; EvidenceReference=$Unit.UnitReference
            SheetName=$Unit.SheetName; SheetIndex=$Unit.SheetIndex; HeaderRowNumber=$Unit.HeaderRowNumber; RowNumber=$Unit.RowNumber
            StructuredFields=(Copy-ScopeContractData $Unit.StructuredFields); FieldReferences=(Copy-ScopeContractData $Unit.FieldReferences)
            IdentityEvidence=(Copy-ScopeContractData $IdentityEvidence)
        }
    } else { throw 'Unsupported scoped source format' }
    Assert-ScopeSliceAgainstSnapshot -Slice $result -Snapshot $Observation.Snapshot -SourceRowNumber $Observation.SourceRowNumber -HtmlTokens $HtmlTokens -HtmlValidationIndex $HtmlValidationIndex -XlsxValidationIndex $XlsxValidationIndex
    return $result
}
function Assert-RelevantBenefitEvidenceSlice {
    param([AllowNull()]$Slice, [Parameter(Mandatory)]$Document, [int]$SourceRowNumber, [AllowNull()]$XlsxValidationIndex=$null)
    Assert-BenefitSourceDocument $Document
    if ($Document.SourceRowNumber -ne $SourceRowNumber -or $Document.FetchStatus -cne 'COMPLETE') { throw 'Slice requires the original successful source row document' }
    $snapshotParameters = @{ SourceUrl=$Document.Url; SourceFormat=$Document.SourceFormat; Text=$Document.Text; ObservedAt=$Document.ObservedAt }
    if ($Document.SourceFormat -ceq 'XLSX') { $snapshotParameters.Text = ''; $snapshotParameters.Bytes = $Document.Bytes }
    $snapshot = New-BenefitSourceSnapshot @snapshotParameters
    Assert-ScopeSliceAgainstSnapshot -Slice $Slice -Snapshot $snapshot -SourceRowNumber $SourceRowNumber -XlsxValidationIndex $XlsxValidationIndex
}
function New-BenefitEvidenceLocationResult {
    param([int]$SourceRowNumber, [Parameter(Mandatory)][string]$OperationalStatus, [AllowNull()]$Status=$null,
        [AllowEmptyCollection()][object[]]$Slices=@(), [AllowEmptyCollection()][string[]]$CandidateReferences=@(),
        [AllowEmptyCollection()][object[]]$Diagnostics=@())
    Assert-BenefitSourceRowNumber $SourceRowNumber
    if ($OperationalStatus -cnotin @('COMPLETE','PARTIAL','FAILED','UNSUPPORTED')) { throw 'Invalid location operational status' }
    if ($null -eq $Slices -or $null -eq $CandidateReferences -or $null -eq $Diagnostics) { throw 'Location arrays must not be null' }
    if ($OperationalStatus -ceq 'COMPLETE') {
        if ($Status -cnotin @('LOCATED','AMBIGUOUS','NOT_FOUND')) { throw 'Complete processing requires a location status' }
    } elseif ($null -ne $Status) { throw 'Incomplete processing cannot claim semantic location or absence' }
    if ($Status -ceq 'LOCATED') {
        if ($Slices.Count -ne 1) { throw 'A1 LOCATED requires exactly one usable slice' }
        Assert-ScopeSliceShape $Slices[0] $SourceRowNumber
    } elseif ($Slices.Count -ne 0) { throw 'Unresolved location cannot expose usable slices' }
    foreach ($reference in $CandidateReferences) { Assert-ScopeText $reference 'CandidateReference' }
    Assert-ScopeDiagnostics $Diagnostics
    return [pscustomobject][ordered]@{
        ContractType='EvidenceLocationResult'; ContractVersion=1; SourceRowNumber=$SourceRowNumber
        OperationalStatus=$OperationalStatus; Status=$Status; Slices=(Copy-ScopeContractData $Slices)
        CandidateReferences=(Copy-ScopeContractData $CandidateReferences); Diagnostics=(Copy-ScopeContractData $Diagnostics)
    }
}

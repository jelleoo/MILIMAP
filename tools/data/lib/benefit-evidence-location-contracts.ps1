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
    Assert-ScopeText $Snapshot.Text 'Snapshot.Text'
    Assert-ScopeTimestamp $Snapshot.ObservedAt
    $hash = Get-BenefitEvidenceTextHash -Text $Snapshot.Text
    if ($Snapshot.ContentHash -cne $hash -or
        $Snapshot.SnapshotId -cne (Get-ScopeSnapshotId $Snapshot.SourceUrl $Snapshot.SourceFormat $Snapshot.ObservedAt $hash)) {
        throw 'Snapshot content or identity mismatch'
    }
    if ($Snapshot.PSObject.Properties.Name -contains 'SourceRowNumber') { throw 'Shared snapshot must not contain a canonical row number' }
}
function New-BenefitSourceSnapshot {
    param([Parameter(Mandatory)][string]$SourceUrl, [Parameter(Mandatory)][string]$SourceFormat,
        [Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][string]$ObservedAt)
    $hash = Get-BenefitEvidenceTextHash -Text $Text
    $result = [pscustomobject][ordered]@{
        ContractType='BenefitSourceSnapshot'; ContractVersion=1
        SnapshotId=(Get-ScopeSnapshotId $SourceUrl $SourceFormat $ObservedAt $hash)
        SourceUrl=$SourceUrl; SourceFormat=$SourceFormat; Text=$Text; ObservedAt=$ObservedAt; ContentHash=$hash
    }
    Assert-ScopeSnapshot $result
    return $result
}
function Assert-ScopeSpan {
    param([long]$Start, [long]$Length, [long]$ContainerStart, [long]$ContainerLength)
    # Subtraction avoids overflow in user-supplied start + length.
    if ($Start -lt $ContainerStart -or $Length -le 0 -or $Length -gt $ContainerLength -or
        ($Start - $ContainerStart) -gt ($ContainerLength - $Length)) { throw 'Source span is outside its container' }
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
function Assert-ScopeUnit {
    param([AllowNull()]$Unit, [Parameter(Mandatory)]$Snapshot)
    Assert-ScopeSnapshot $Snapshot
    Assert-ScopeObject $Unit 'SourceContentUnit' @('SnapshotId','UnitType','UnitReference','TableStart','TableLength','RawStart','RawLength','RawFragment','RawEvidenceText','StructuredFields','FieldReferences')
    if ($Snapshot.SourceFormat -cne 'HTML' -or $Unit.UnitType -cne 'TABLE_ROW' -or $Unit.SnapshotId -cne $Snapshot.SnapshotId) { throw 'Unit source/type mismatch' }
    if ($Unit.UnitReference -cnotmatch '^HTML_TABLE_[1-9]\d*_ROW_[1-9]\d*$') { throw 'Invalid physical unit reference' }
    Assert-ScopeSpan $Unit.TableStart $Unit.TableLength 0 $Snapshot.Text.Length
    Assert-ScopeSpan $Unit.RawStart $Unit.RawLength $Unit.TableStart $Unit.TableLength
    $table = Get-ScopeElementFragment $Snapshot.Text $Unit.TableStart $Unit.TableLength 'table'
    $row = Get-ScopeElementFragment $Snapshot.Text $Unit.RawStart $Unit.RawLength 'tr'
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
function New-BenefitSourceContentUnit {
    param([Parameter(Mandatory)]$Snapshot, [Parameter(Mandatory)][string]$UnitReference,
        [long]$TableStart, [long]$TableLength, [long]$RawStart, [long]$RawLength,
        [Parameter(Mandatory)][string]$RawEvidenceText,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.IDictionary]$StructuredFields,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.IDictionary]$FieldReferences)
    Assert-ScopeSnapshot $Snapshot
    Assert-ScopeSpan $RawStart $RawLength 0 $Snapshot.Text.Length
    $result = [pscustomobject][ordered]@{
        ContractType='SourceContentUnit'; ContractVersion=1; SnapshotId=$Snapshot.SnapshotId
        UnitType='TABLE_ROW'; UnitReference=$UnitReference; TableStart=$TableStart; TableLength=$TableLength
        RawStart=$RawStart; RawLength=$RawLength; RawFragment=$Snapshot.Text.Substring([int]$RawStart,[int]$RawLength)
        RawEvidenceText=$RawEvidenceText; StructuredFields=(Copy-ScopeContractData $StructuredFields); FieldReferences=(Copy-ScopeContractData $FieldReferences)
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
    param([AllowNull()]$Observation)
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
        Assert-ScopeUnit $unit $Observation.Snapshot
        if (-not $references.Add([string]$unit.UnitReference)) { throw 'Duplicate content unit reference' }
    }
    Assert-ScopeDiagnostics $Observation.Diagnostics
}
function New-BenefitSourceObservation {
    param([int]$SourceRowNumber, [Parameter(Mandatory)]$Snapshot, [Parameter(Mandatory)][string]$AdapterId,
        [Parameter(Mandatory)][string]$AdapterVersion, [Parameter(Mandatory)][string]$AdapterStatus,
        [AllowEmptyCollection()][object[]]$ContentUnits=@(), [AllowEmptyCollection()][object[]]$Diagnostics=@())
    Assert-ScopeSnapshot $Snapshot
    $result = [pscustomobject][ordered]@{
        ContractType='SourceObservation'; ContractVersion=1; SourceRowNumber=$SourceRowNumber
        SnapshotId=$Snapshot.SnapshotId; SourceUrl=$Snapshot.SourceUrl; SourceFormat=$Snapshot.SourceFormat; ObservedAt=$Snapshot.ObservedAt
        Snapshot=(Copy-ScopeContractData $Snapshot); AdapterId=$AdapterId; AdapterVersion=$AdapterVersion; AdapterStatus=$AdapterStatus
        ContentUnits=(Copy-ScopeContractData $ContentUnits); Diagnostics=(Copy-ScopeContractData $Diagnostics)
    }
    Assert-ScopeObservation $result
    return $result
}
function Assert-ScopeSliceShape {
    param([AllowNull()]$Slice, [int]$SourceRowNumber)
    Assert-ScopeObject $Slice 'RelevantEvidenceSlice' @('SourceRowNumber','SnapshotId','ContentHash','SourceUrl','SourceFormat','ObservedAt','LocatorMethod','ScopeType','EvidenceReference','TableStart','TableLength','RawStart','RawLength','RawFragment','RawEvidenceText','StructuredFields','FieldReferences','IdentityEvidence')
    Assert-BenefitSourceRowNumber $SourceRowNumber
    if ($Slice.SourceRowNumber -ne $SourceRowNumber -or $Slice.ScopeType -cne 'TABLE_ROW' -or $Slice.LocatorMethod -cne 'STRUCTURED_HTML_ROW') { throw 'Slice row or scope mismatch' }
    if ($Slice.EvidenceReference -cnotmatch '^HTML_TABLE_[1-9]\d*_ROW_[1-9]\d*$' -or
        $Slice.ContentHash -cnotmatch '^[0-9a-f]{64}$' -or $Slice.SnapshotId -cnotmatch '^[0-9a-f]{64}$') { throw 'Invalid slice reference or hash' }
    Assert-ScopeText $Slice.SourceUrl 'Slice.SourceUrl'
    Assert-ScopeTimestamp $Slice.ObservedAt
    if ($Slice.IdentityEvidence -isnot [array]) { throw 'IdentityEvidence must remain an array' }
    foreach ($signal in $Slice.IdentityEvidence) { Assert-ScopeText $signal 'IdentityEvidence signal' }
}
function Assert-ScopeSliceAgainstSnapshot {
    param([AllowNull()]$Slice, [Parameter(Mandatory)]$Snapshot, [int]$SourceRowNumber)
    Assert-ScopeSliceShape $Slice $SourceRowNumber
    Assert-ScopeSnapshot $Snapshot
    foreach ($key in @('SnapshotId','ContentHash','SourceUrl','SourceFormat','ObservedAt')) {
        if ($Slice.$key -cne $Snapshot.$key) { throw 'Slice must preserve original source snapshot' }
    }
    $unit = [pscustomobject][ordered]@{
        ContractType='SourceContentUnit'; ContractVersion=1; SnapshotId=$Slice.SnapshotId; UnitType='TABLE_ROW'
        UnitReference=$Slice.EvidenceReference; TableStart=$Slice.TableStart; TableLength=$Slice.TableLength
        RawStart=$Slice.RawStart; RawLength=$Slice.RawLength; RawFragment=$Slice.RawFragment
        RawEvidenceText=$Slice.RawEvidenceText; StructuredFields=$Slice.StructuredFields; FieldReferences=$Slice.FieldReferences
    }
    Assert-ScopeUnit $unit $Snapshot
}
function New-RelevantBenefitEvidenceSlice {
    param([Parameter(Mandatory)]$Observation, [Parameter(Mandatory)]$Unit, [AllowEmptyCollection()][object[]]$IdentityEvidence=@())
    Assert-ScopeObservation $Observation
    if ($Observation.AdapterStatus -cne 'COMPLETE') { throw 'Only a complete observation can yield a usable slice' }
    Assert-ScopeUnit $Unit $Observation.Snapshot
    $members = @($Observation.ContentUnits | Where-Object { $_.UnitReference -ceq $Unit.UnitReference })
    if ($members.Count -ne 1 -or
        (ConvertTo-Json -InputObject $members[0] -Depth 20 -Compress) -cne (ConvertTo-Json -InputObject $Unit -Depth 20 -Compress)) {
        throw 'Slice unit must be an exact member of its observation'
    }
    $result = [pscustomobject][ordered]@{
        ContractType='RelevantEvidenceSlice'; ContractVersion=1; SourceRowNumber=$Observation.SourceRowNumber
        SnapshotId=$Observation.SnapshotId; ContentHash=$Observation.Snapshot.ContentHash
        SourceUrl=$Observation.SourceUrl; SourceFormat=$Observation.SourceFormat; ObservedAt=$Observation.ObservedAt
        LocatorMethod='STRUCTURED_HTML_ROW'; ScopeType='TABLE_ROW'; EvidenceReference=$Unit.UnitReference
        TableStart=$Unit.TableStart; TableLength=$Unit.TableLength; RawStart=$Unit.RawStart; RawLength=$Unit.RawLength
        RawFragment=$Unit.RawFragment; RawEvidenceText=$Unit.RawEvidenceText
        StructuredFields=(Copy-ScopeContractData $Unit.StructuredFields); FieldReferences=(Copy-ScopeContractData $Unit.FieldReferences)
        IdentityEvidence=(Copy-ScopeContractData $IdentityEvidence)
    }
    Assert-ScopeSliceAgainstSnapshot $result $Observation.Snapshot $Observation.SourceRowNumber
    return $result
}
function Assert-RelevantBenefitEvidenceSlice {
    param([AllowNull()]$Slice, [Parameter(Mandatory)]$Document, [int]$SourceRowNumber)
    Assert-BenefitSourceDocument $Document
    if ($Document.SourceRowNumber -ne $SourceRowNumber -or $Document.FetchStatus -cne 'COMPLETE') { throw 'Slice requires the original successful source row document' }
    $snapshot = New-BenefitSourceSnapshot -SourceUrl $Document.Url -SourceFormat $Document.SourceFormat -Text $Document.Text -ObservedAt $Document.ObservedAt
    Assert-ScopeSliceAgainstSnapshot $Slice $snapshot $SourceRowNumber
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

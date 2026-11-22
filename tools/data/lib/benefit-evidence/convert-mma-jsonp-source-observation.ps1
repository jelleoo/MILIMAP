Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '../benefit-evidence-location-contracts.ps1')

function New-MmaJsonpDiagnostic {
    param([string]$Code, [string]$Detail, [string]$EvidenceReference='')
    return [pscustomobject][ordered]@{ Code=$Code; Stage='MMA_JSONP_ADAPTER'; EvidenceReference=$EvidenceReference; Detail=$Detail }
}

function ConvertFrom-BenefitJsonpEnvelope {
    param([Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][string]$ExpectedCallback)
    if ($ExpectedCallback -cnotmatch '^[A-Za-z_$][A-Za-z0-9_$]*$') { throw 'Invalid expected JSONP callback' }
    $pattern = '\A\s*' + [regex]::Escape($ExpectedCallback) + '\s*\((?<json>.*)\)\s*;?\s*\z'
    $match = [regex]::Match($Text, $pattern, [Text.RegularExpressions.RegexOptions]::Singleline, [TimeSpan]::FromSeconds(1))
    if (-not $match.Success) { throw 'JSONP wrapper invalid or callback mismatch' }
    $jsonText = $match.Groups['json'].Value
    try { $value = $jsonText | ConvertFrom-Json -ErrorAction Stop }
    catch { throw 'JSONP payload parse failed' }
    if ($null -eq $value -or $value -is [array]) { throw 'MMA JSONP root must be an object' }
    if ($value.PSObject.Properties.Name -notcontains 'success' -or $value.success -isnot [bool] -or $value.success -ne $true) { throw 'MMA JSONP response is unsuccessful' }
    return [pscustomobject][ordered]@{ JsonText=$jsonText; JsonStart=[long]$match.Groups['json'].Index; Value=$value }
}

function Get-BenefitJsonObjectSpans {
    param([Parameter(Mandatory)][string]$JsonText)
    $stack=[Collections.Generic.List[long]]::new(); $spans=@(); $inString=$false; $escaped=$false
    for ($i=0; $i -lt $JsonText.Length; $i++) {
        $character=$JsonText[$i]
        if ($inString) {
            if ($escaped) { $escaped=$false; continue }
            if ($character -ceq '\') { $escaped=$true; continue }
            if ($character -ceq '"') { $inString=$false }
            continue
        }
        if ($character -ceq '"') { $inString=$true; continue }
        if ($character -ceq '{') { $stack.Add($i); continue }
        if ($character -ceq '}') {
            if ($stack.Count -eq 0) { throw 'Unexpected JSON object close' }
            $start=$stack[$stack.Count-1]; $stack.RemoveAt($stack.Count-1)
            $spans += [pscustomobject][ordered]@{ Start=[long]$start; Length=[long]($i-$start+1); Fragment=$JsonText.Substring($start,$i-$start+1) }
        }
    }
    if ($inString -or $stack.Count -ne 0) { throw 'Malformed JSON object spans' }
    return @($spans | Sort-Object Start)
}

function Get-BenefitJsonArrayObjectSpans {
    param([Parameter(Mandatory)][string]$JsonText, [Parameter(Mandatory)]$ArraySpan)
    if ($ArraySpan.Fragment.Length -lt 2 -or $ArraySpan.Fragment[0] -cne '[') { throw 'MMA JSONP list must be an array' }
    $arrayEnd = $ArraySpan.Start + $ArraySpan.Length
    $position = $ArraySpan.Start + 1
    $spans = [Collections.Generic.List[object]]::new()
    $quoteOrEsc = [char[]]@([char]'"', [char]'\')
    $objScan = [char[]]@([char]'"', [char]'{', [char]'}')
    while ($true) {
        while ($position -lt $arrayEnd -and [char]::IsWhiteSpace($JsonText[$position])) { $position++ }
        if ($position -ge $arrayEnd) { throw 'Unterminated JSONP list array' }
        if ($JsonText[$position] -ceq ']') { break }
        if ($JsonText[$position] -cne '{') { throw 'MMA JSONP list items must be objects' }
        $depth = 0
        $cPos = $position
        $end = -1
        while ($cPos -lt $arrayEnd) {
            $idx = $JsonText.IndexOfAny($objScan, $cPos)
            if ($idx -lt 0 -or $idx -ge $arrayEnd) { break }
            $c = $JsonText[$idx]
            if ($c -ceq '"') {
                $strPos = $idx + 1
                $strEnd = -1
                while ($strPos -lt $arrayEnd) {
                    $qIdx = $JsonText.IndexOfAny($quoteOrEsc, $strPos)
                    if ($qIdx -lt 0 -or $qIdx -ge $arrayEnd) { break }
                    if ($JsonText[$qIdx] -ceq '"') { $strEnd = $qIdx + 1; break }
                    $strPos = $qIdx + 2
                }
                if ($strEnd -lt 0) { throw 'Unterminated JSON string' }
                $cPos = $strEnd
                continue
            }
            if ($c -ceq '{') {
                $depth++
            } else {
                $depth--
                if ($depth -eq 0) { $end = $idx + 1; break }
                if ($depth -lt 0) { break }
            }
            $cPos = $idx + 1
        }
        if ($end -lt 0) { throw 'Unterminated JSON container' }
        $len = $end - $position
        $spans.Add([pscustomobject][ordered]@{ Start=[long]$position; Length=[long]$len; Fragment=$JsonText.Substring($position, $len) })
        $position = $end
        while ($position -lt $arrayEnd -and [char]::IsWhiteSpace($JsonText[$position])) { $position++ }
        if ($position -ge $arrayEnd) { throw 'Unterminated JSONP list array' }
        if ($JsonText[$position] -ceq ']') { break }
        if ($JsonText[$position] -cne ',') { throw 'JSONP list has invalid item separator' }
        $position++
    }
    return @($spans)
}

function Get-MmaJsonpStructuredData {
    param([Parameter(Mandatory)][string]$ObjectText, [Parameter(Mandatory)][string]$UnitReference, [Parameter(Mandatory)][hashtable]$FieldMap, [long]$ObjectStart, [bool]$RequireInstitutionCode=$true, [AllowNull()]$ParsedObject=$null, [AllowNull()]$FastLookup=$null)
    if ($null -ne $ParsedObject) {
        $object = $ParsedObject
    } else {
        try { $object=$ObjectText | ConvertFrom-Json -ErrorAction Stop }
        catch { throw 'MMA JSONP source object cannot be parsed' }
    }
    if ($null -eq $object -or $object -is [array]) { throw 'MMA JSONP source object must be an object' }
    $fields=[ordered]@{}; $references=[ordered]@{}
    $propertySpans=Get-BenefitJsonTopLevelPropertySpanIndex -JsonText $ObjectText
    $objProps = $object.PSObject.Properties
    $propMap = if ($null -ne $FastLookup) { [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal) } else { $null }
    if ($null -ne $propMap) {
        foreach ($p in $objProps) {
            $pName = $p.Name
            if (-not $propMap.ContainsKey($pName) -and $propertySpans.ContainsKey($pName)) {
                $pSpanList = [Collections.Generic.List[object]]$propertySpans[$pName]
                $pVal = $p.Value
                $bText = if ($pVal -is [string]) { $pVal.Trim() } elseif ($null -eq $pVal) { '' } else { ConvertTo-BenefitText $pVal }
                $propMap[$pName] = [pscustomobject]@{
                    SpanCount = $pSpanList.Count
                    Start = [long]$pSpanList[0].Start
                    Length = [long]$pSpanList[0].Length
                    BenefitText = $bText
                }
            }
        }
    }
    foreach ($semanticField in $FieldMap.Keys) {
        $rawProperty=$FieldMap[$semanticField]
        $rawPropObj = $objProps[$rawProperty]
        if ($null -eq $rawPropObj) { throw "MMA JSONP schema is missing $rawProperty" }
        if (-not $propertySpans.ContainsKey($rawProperty)) { throw "MMA JSONP must contain exactly one $rawProperty property" }
        $spanList = $propertySpans[$rawProperty]
        if ($spanList.Count -ne 1) { throw "MMA JSONP must contain exactly one $rawProperty property" }
        $span=$spanList[0]
        $rawVal = $rawPropObj.Value
        $fields[$semanticField] = if ($rawVal -is [string]) { $rawVal.Trim() } elseif ($null -eq $rawVal) { '' } else { ConvertTo-BenefitText $rawVal }
        $references[$semanticField]=[pscustomobject][ordered]@{ PropertyName=$rawProperty; FieldReference="$UnitReference/$rawProperty"; ValueStart=[long]($ObjectStart+$span.Start); ValueLength=[long]$span.Length }
    }
    Assert-ScopeText $fields.BusinessName 'MMA JSONP BusinessName'
    if ($RequireInstitutionCode) { Assert-ScopeText $fields.InstitutionCode 'MMA JSONP InstitutionCode' }
    if ($null -ne $FastLookup -and $null -ne $propMap) {
        $spanKey = "$ObjectStart|$($ObjectText.Length)"
        $FastLookup.ObjectsBySpan[$spanKey] = [pscustomobject]@{ PropMap = $propMap }
    }
    return [pscustomobject][ordered]@{ StructuredFields=$fields; FieldReferences=$references }
}

function ConvertTo-MmaJsonpListTemplate {
    param([Parameter(Mandatory)]$Snapshot, [Parameter(Mandatory)][string]$ExpectedCallback, [switch]$SkipSnapshotValidation)
    if (-not $SkipSnapshotValidation) { Assert-ScopeSnapshot $Snapshot }
    if ($Snapshot.SourceFormat -cne 'JSONP') { throw 'MMA JSONP adapter requires JSONP source format' }
    $envelope=ConvertFrom-BenefitJsonpEnvelope -Text $Snapshot.Text -ExpectedCallback $ExpectedCallback
    $listProp = $envelope.Value.PSObject.Properties['list']
    if ($null -eq $listProp -or $listProp.Value -isnot [array]) { throw 'MMA JSONP list schema is unsupported' }
    $arraySpan=Get-BenefitJsonTopLevelPropertySpan -JsonText $envelope.JsonText -PropertyName 'list'
    $objectSpans=Get-BenefitJsonArrayObjectSpans -JsonText $envelope.JsonText -ArraySpan $arraySpan
    $parsedItems=@($listProp.Value)
    if ($objectSpans.Count -ne $parsedItems.Count) { throw 'MMA JSONP list item spans do not match parsed list' }
    $fastLookup = Get-InternalScopeJsonpFastLookup -Snapshot $Snapshot
    $rows=[Collections.Generic.List[object]]::new($objectSpans.Count)
    $legacyFieldMap=@{ BusinessName='udgigwan_yhnm'; Address='addr'; Phone='udgigwan_telno'; Category='udggeopjong_gbnm'; InstitutionCode='udgigwan_cd' }
    $liveFieldMap=@{ BusinessName='udae_ggm'; Address='addr'; Phone='udgigwan_telno'; Category='udggeopjong_gbnm'; InstitutionCode='udgigwan_cd' }
    for ($i=0; $i -lt $objectSpans.Count; $i++) {
        $span=$objectSpans[$i]; $reference='JSONP_LIST_ITEM_' + ($i+1); $parsedItem=$parsedItems[$i]
        $hasLiveNameProp = ($null -ne $parsedItem.PSObject.Properties['udae_ggm'])
        $nameKey = if ($hasLiveNameProp) { 'udae_ggm' } else { 'udgigwan_yhnm' }
        $fieldMap = if ($hasLiveNameProp) { $liveFieldMap } else { $legacyFieldMap }
        $nameProp = $parsedItem.PSObject.Properties[$nameKey]
        if ($null -eq $nameProp -or [string]::IsNullOrWhiteSpace((ConvertTo-BenefitText $nameProp.Value))) {
            continue
        }
        $data=Get-MmaJsonpStructuredData -ObjectText $span.Fragment -UnitReference $reference -FieldMap $fieldMap -ObjectStart ($envelope.JsonStart+$span.Start) -RequireInstitutionCode:$false -ParsedObject $parsedItem -FastLookup $fastLookup
        $rows.Add([pscustomobject][ordered]@{ UnitReference=$reference; RawStart=[long]($envelope.JsonStart+$span.Start); RawLength=$span.Length; RawEvidenceText=$data.StructuredFields.BusinessName; StructuredFields=$data.StructuredFields; FieldReferences=$data.FieldReferences })
    }
    return [pscustomobject][ordered]@{ Rows=@($rows) }
}

function ConvertTo-MmaJsonpDetailTemplate {
    param([Parameter(Mandatory)]$Snapshot, [Parameter(Mandatory)][string]$ExpectedCallback, [switch]$SkipSnapshotValidation)
    if (-not $SkipSnapshotValidation) { Assert-ScopeSnapshot $Snapshot }
    if ($Snapshot.SourceFormat -cne 'JSONP') { throw 'MMA JSONP adapter requires JSONP source format' }
    $envelope=ConvertFrom-BenefitJsonpEnvelope -Text $Snapshot.Text -ExpectedCallback $ExpectedCallback
    $voProp = $envelope.Value.PSObject.Properties['udgigwanVO']
    if ($null -eq $voProp -or $null -eq $voProp.Value -or $voProp.Value -is [array]) { throw 'MMA JSONP detail schema is unsupported' }
    $span=Get-BenefitJsonTopLevelPropertySpan -JsonText $envelope.JsonText -PropertyName 'udgigwanVO'
    if ($span.Fragment[0] -cne '{') { throw 'MMA JSONP detail must be an object' }
    $fastLookup = Get-InternalScopeJsonpFastLookup -Snapshot $Snapshot
    $detailNameKey = if ($null -ne $voProp.Value.PSObject.Properties['udae_ggm']) { 'udae_ggm' } else { 'udgigwan_yhnm' }
    $fieldMap=@{ BusinessName=$detailNameKey; Address='addr'; Phone='udgigwan_telno'; Category='udggeopjong_gbnm'; InstitutionCode='udgigwan_cd'; BenefitDescription='udsangse_cn'; EligibleTarget='uddaesang_cn'; UsageCondition='udjyjehan_cn'; VerificationMethod='udjbjaryo_cn'; ValidFrom='hyjeokyong_sjdt'; ValidUntilObserved='hyjeokyong_jrdt' }
    $data=Get-MmaJsonpStructuredData -ObjectText $span.Fragment -UnitReference 'JSONP_DETAIL_OBJECT' -FieldMap $fieldMap -ObjectStart ($envelope.JsonStart+$span.Start) -ParsedObject $voProp.Value -FastLookup $fastLookup
    return [pscustomobject][ordered]@{ Rows=@([pscustomobject][ordered]@{ UnitReference='JSONP_DETAIL_OBJECT'; RawStart=[long]($envelope.JsonStart+$span.Start); RawLength=$span.Length; RawEvidenceText=$data.StructuredFields.BenefitDescription; StructuredFields=$data.StructuredFields; FieldReferences=$data.FieldReferences }) }
}

function ConvertTo-MmaJsonpObservation {
    param([Parameter(Mandatory)]$Document, [Parameter(Mandatory)][string]$ExpectedCallback, [Parameter(Mandatory)][ValidateSet('LIST','DETAIL')][string]$Role, [AllowNull()]$Snapshot=$null)
    Assert-BenefitSourceDocument $Document
    if ($Document.FetchStatus -cne 'COMPLETE') { throw 'MMA JSONP observation requires a successfully fetched source document' }
    if ($null -eq $Snapshot) {
        $Snapshot = New-BenefitSourceSnapshot -SourceUrl $Document.Url -SourceFormat $Document.SourceFormat -Text $Document.Text -ObservedAt $Document.ObservedAt
        Set-InternalBenefitJsonpRunContextSnapshotTrust -Snapshot $Snapshot
    } elseif (-not (Test-InternalBenefitJsonpRunContextSnapshotTrust -Snapshot $Snapshot)) {
        $Snapshot = New-BenefitSourceSnapshot -SourceUrl $Document.Url -SourceFormat $Document.SourceFormat -Text $Document.Text -ObservedAt $Document.ObservedAt
        Set-InternalBenefitJsonpRunContextSnapshotTrust -Snapshot $Snapshot
    }
    try {
        $template=if ($Role -ceq 'LIST') { ConvertTo-MmaJsonpListTemplate -Snapshot $Snapshot -ExpectedCallback $ExpectedCallback -SkipSnapshotValidation } else { ConvertTo-MmaJsonpDetailTemplate -Snapshot $Snapshot -ExpectedCallback $ExpectedCallback -SkipSnapshotValidation }
        $units=[Collections.Generic.List[object]]::new($template.Rows.Count)
        foreach ($row in @($template.Rows)) {
            $units.Add((Copy-InternalJsonpSourceContentUnit -Snapshot $Snapshot -Unit $row))
        }
        if ($Role -ceq 'DETAIL' -and $units.Count -ne 1) { throw 'MMA JSONP detail must produce exactly one object' }
        return New-InternalBenefitJsonpSourceObservation -SourceRowNumber $Document.SourceRowNumber -Snapshot $Snapshot -AdapterId ("MMA_JSONP_$Role") -AdapterVersion '1' -AdapterStatus COMPLETE -ContentUnits @($units.ToArray()) -Diagnostics @()
    } catch {
        return New-InternalBenefitJsonpSourceObservation -SourceRowNumber $Document.SourceRowNumber -Snapshot $Snapshot -AdapterId ("MMA_JSONP_$Role") -AdapterVersion '1' -AdapterStatus FAILED -ContentUnits @() -Diagnostics @(New-MmaJsonpDiagnostic 'JSONP_ADAPTER_FAILED' $_.Exception.Message)
    }
}

function ConvertTo-MmaJsonpListObservation {
    param([Parameter(Mandatory)]$Document, [Parameter(Mandatory)][string]$ExpectedCallback)
    return ConvertTo-MmaJsonpObservation -Document $Document -ExpectedCallback $ExpectedCallback -Role LIST
}

function ConvertTo-MmaJsonpDetailObservation {
    param([Parameter(Mandatory)]$Document, [Parameter(Mandatory)][string]$ExpectedCallback)
    return ConvertTo-MmaJsonpObservation -Document $Document -ExpectedCallback $ExpectedCallback -Role DETAIL
}

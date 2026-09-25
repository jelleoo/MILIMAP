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

function Get-BenefitJsonTopLevelPropertySpan {
    param([Parameter(Mandatory)][string]$JsonText, [Parameter(Mandatory)][string]$PropertyName)
    $rootStart=Skip-BenefitJsonWhitespace $JsonText 0
    if ($rootStart -ge $JsonText.Length -or $JsonText[$rootStart] -cne '{') { throw 'MMA JSONP root must start with an object' }
    $rootEnd=Get-BenefitJsonValueEnd $JsonText $rootStart
    if ((Skip-BenefitJsonWhitespace $JsonText $rootEnd) -ne $JsonText.Length) { throw 'JSONP root has trailing data' }
    $position=$rootStart+1; $found=@()
    while ($true) {
        $position=Skip-BenefitJsonWhitespace $JsonText $position
        if ($position -ge $rootEnd) { throw 'Unterminated JSON root object' }
        if ($JsonText[$position] -ceq '}') { break }
        $keyStart=$position; $keyEnd=Get-BenefitJsonStringEnd $JsonText $keyStart
        try { $key=('{"value":' + $JsonText.Substring($keyStart,$keyEnd-$keyStart) + '}') | ConvertFrom-Json -ErrorAction Stop | Select-Object -ExpandProperty value }
        catch { throw 'JSONP property name cannot be decoded' }
        $position=Skip-BenefitJsonWhitespace $JsonText $keyEnd
        if ($position -ge $rootEnd -or $JsonText[$position] -cne ':') { throw 'JSONP property is missing a colon' }
        $valueStart=Skip-BenefitJsonWhitespace $JsonText ($position+1)
        $valueEnd=Get-BenefitJsonValueEnd $JsonText $valueStart
        if ($key -ceq $PropertyName) { $found += [pscustomobject][ordered]@{ Start=[long]$valueStart; Length=[long]($valueEnd-$valueStart); Fragment=$JsonText.Substring($valueStart,$valueEnd-$valueStart) } }
        $position=Skip-BenefitJsonWhitespace $JsonText $valueEnd
        if ($position -ge $rootEnd) { throw 'Unterminated JSON root object' }
        if ($JsonText[$position] -ceq '}') { break }
        if ($JsonText[$position] -cne ',') { throw 'JSONP root has invalid property separator' }
        $position++
    }
    if ($found.Count -ne 1) { throw "MMA JSONP must contain exactly one $PropertyName property" }
    return $found[0]
}

function Get-BenefitJsonArrayObjectSpans {
    param([Parameter(Mandatory)][string]$JsonText, [Parameter(Mandatory)]$ArraySpan)
    if ($ArraySpan.Fragment.Length -lt 2 -or $ArraySpan.Fragment[0] -cne '[') { throw 'MMA JSONP list must be an array' }
    $arrayEnd=$ArraySpan.Start+$ArraySpan.Length; $position=$ArraySpan.Start+1; $spans=@()
    while ($true) {
        $position=Skip-BenefitJsonWhitespace $JsonText $position
        if ($position -ge $arrayEnd) { throw 'Unterminated JSONP list array' }
        if ($JsonText[$position] -ceq ']') { break }
        if ($JsonText[$position] -cne '{') { throw 'MMA JSONP list items must be objects' }
        $end=Get-BenefitJsonValueEnd $JsonText $position
        $spans += [pscustomobject][ordered]@{ Start=[long]$position; Length=[long]($end-$position); Fragment=$JsonText.Substring($position,$end-$position) }
        $position=Skip-BenefitJsonWhitespace $JsonText $end
        if ($position -ge $arrayEnd) { throw 'Unterminated JSONP list array' }
        if ($JsonText[$position] -ceq ']') { break }
        if ($JsonText[$position] -cne ',') { throw 'JSONP list has invalid item separator' }
        $position++
    }
    return @($spans)
}

function Get-MmaJsonpStructuredData {
    param([Parameter(Mandatory)][string]$ObjectText, [Parameter(Mandatory)][string]$UnitReference, [Parameter(Mandatory)][hashtable]$FieldMap, [long]$ObjectStart, [bool]$RequireInstitutionCode=$true)
    try { $object=$ObjectText | ConvertFrom-Json -ErrorAction Stop }
    catch { throw 'MMA JSONP source object cannot be parsed' }
    if ($null -eq $object -or $object -is [array]) { throw 'MMA JSONP source object must be an object' }
    $fields=[ordered]@{}; $references=[ordered]@{}
    foreach ($semanticField in $FieldMap.Keys) {
        $rawProperty=$FieldMap[$semanticField]
        if ($object.PSObject.Properties.Name -notcontains $rawProperty) { throw "MMA JSONP schema is missing $rawProperty" }
        $span=Get-BenefitJsonTopLevelPropertySpan -JsonText $ObjectText -PropertyName $rawProperty
        $fields[$semanticField]=ConvertTo-BenefitText $object.($rawProperty)
        $references[$semanticField]=[pscustomobject][ordered]@{ PropertyName=$rawProperty; FieldReference="$UnitReference/$rawProperty"; ValueStart=[long]($ObjectStart+$span.Start); ValueLength=[long]$span.Length }
    }
    Assert-ScopeText $fields.BusinessName 'MMA JSONP BusinessName'
    if ($RequireInstitutionCode) { Assert-ScopeText $fields.InstitutionCode 'MMA JSONP InstitutionCode' }
    return [pscustomobject][ordered]@{ StructuredFields=$fields; FieldReferences=$references }
}

function ConvertTo-MmaJsonpListTemplate {
    param([Parameter(Mandatory)]$Snapshot, [Parameter(Mandatory)][string]$ExpectedCallback)
    Assert-ScopeSnapshot $Snapshot
    if ($Snapshot.SourceFormat -cne 'JSONP') { throw 'MMA JSONP adapter requires JSONP source format' }
    $envelope=ConvertFrom-BenefitJsonpEnvelope -Text $Snapshot.Text -ExpectedCallback $ExpectedCallback
    if ($envelope.Value.PSObject.Properties.Name -notcontains 'list' -or $envelope.Value.list -isnot [array]) { throw 'MMA JSONP list schema is unsupported' }
    $arraySpan=Get-BenefitJsonTopLevelPropertySpan -JsonText $envelope.JsonText -PropertyName 'list'
    $objectSpans=Get-BenefitJsonArrayObjectSpans -JsonText $envelope.JsonText -ArraySpan $arraySpan
    if ($objectSpans.Count -ne @($envelope.Value.list).Count) { throw 'MMA JSONP list item spans do not match parsed list' }
    $rows=@(); $fieldMap=@{ BusinessName='udgigwan_yhnm'; Address='addr'; Phone='udgigwan_telno'; Category='udggeopjong_gbnm'; InstitutionCode='udgigwan_cd' }
    for ($i=0; $i -lt $objectSpans.Count; $i++) {
        $span=$objectSpans[$i]; $reference='JSONP_LIST_ITEM_' + ($i+1)
        $data=Get-MmaJsonpStructuredData -ObjectText $span.Fragment -UnitReference $reference -FieldMap $fieldMap -ObjectStart ($envelope.JsonStart+$span.Start) -RequireInstitutionCode:$false
        $rows += [pscustomobject][ordered]@{ UnitReference=$reference; RawStart=[long]($envelope.JsonStart+$span.Start); RawLength=$span.Length; RawEvidenceText=$data.StructuredFields.BusinessName; StructuredFields=$data.StructuredFields; FieldReferences=$data.FieldReferences }
    }
    return [pscustomobject][ordered]@{ Rows=@($rows) }
}

function ConvertTo-MmaJsonpDetailTemplate {
    param([Parameter(Mandatory)]$Snapshot, [Parameter(Mandatory)][string]$ExpectedCallback)
    Assert-ScopeSnapshot $Snapshot
    if ($Snapshot.SourceFormat -cne 'JSONP') { throw 'MMA JSONP adapter requires JSONP source format' }
    $envelope=ConvertFrom-BenefitJsonpEnvelope -Text $Snapshot.Text -ExpectedCallback $ExpectedCallback
    if ($envelope.Value.PSObject.Properties.Name -notcontains 'udgigwanVO' -or $null -eq $envelope.Value.udgigwanVO -or $envelope.Value.udgigwanVO -is [array]) { throw 'MMA JSONP detail schema is unsupported' }
    $span=Get-BenefitJsonTopLevelPropertySpan -JsonText $envelope.JsonText -PropertyName 'udgigwanVO'
    if ($span.Fragment[0] -cne '{') { throw 'MMA JSONP detail must be an object' }
    $fieldMap=@{ BusinessName='udgigwan_yhnm'; Address='addr'; Phone='udgigwan_telno'; Category='udggeopjong_gbnm'; InstitutionCode='udgigwan_cd'; BenefitDescription='udsangse_cn'; EligibleTarget='uddaesang_cn'; UsageCondition='udjyjehan_cn'; VerificationMethod='udjbjaryo_cn'; ValidFrom='hyjeokyong_sjdt'; ValidUntilObserved='hyjeokyong_jrdt' }
    $data=Get-MmaJsonpStructuredData -ObjectText $span.Fragment -UnitReference 'JSONP_DETAIL_OBJECT' -FieldMap $fieldMap -ObjectStart ($envelope.JsonStart+$span.Start)
    return [pscustomobject][ordered]@{ Rows=@([pscustomobject][ordered]@{ UnitReference='JSONP_DETAIL_OBJECT'; RawStart=[long]($envelope.JsonStart+$span.Start); RawLength=$span.Length; RawEvidenceText=$data.StructuredFields.BenefitDescription; StructuredFields=$data.StructuredFields; FieldReferences=$data.FieldReferences }) }
}

function ConvertTo-MmaJsonpObservation {
    param([Parameter(Mandatory)]$Document, [Parameter(Mandatory)][string]$ExpectedCallback, [Parameter(Mandatory)][ValidateSet('LIST','DETAIL')][string]$Role)
    Assert-BenefitSourceDocument $Document
    if ($Document.FetchStatus -cne 'COMPLETE') { throw 'MMA JSONP observation requires a successfully fetched source document' }
    $snapshot=New-BenefitSourceSnapshot -SourceUrl $Document.Url -SourceFormat $Document.SourceFormat -Text $Document.Text -ObservedAt $Document.ObservedAt
    try {
        $template=if ($Role -ceq 'LIST') { ConvertTo-MmaJsonpListTemplate -Snapshot $snapshot -ExpectedCallback $ExpectedCallback } else { ConvertTo-MmaJsonpDetailTemplate -Snapshot $snapshot -ExpectedCallback $ExpectedCallback }
        $units=@()
        foreach ($row in @($template.Rows)) {
            $units += New-BenefitJsonpSourceContentUnit -Snapshot $snapshot -UnitReference $row.UnitReference -RawStart $row.RawStart -RawLength $row.RawLength -RawEvidenceText $row.RawEvidenceText -StructuredFields $row.StructuredFields -FieldReferences $row.FieldReferences
        }
        if ($Role -ceq 'DETAIL' -and $units.Count -ne 1) { throw 'MMA JSONP detail must produce exactly one object' }
        return New-BenefitSourceObservation -SourceRowNumber $Document.SourceRowNumber -Snapshot $snapshot -AdapterId ("MMA_JSONP_$Role") -AdapterVersion '1' -AdapterStatus COMPLETE -ContentUnits $units -Diagnostics @()
    } catch {
        return New-BenefitSourceObservation -SourceRowNumber $Document.SourceRowNumber -Snapshot $snapshot -AdapterId ("MMA_JSONP_$Role") -AdapterVersion '1' -AdapterStatus FAILED -ContentUnits @() -Diagnostics @(New-MmaJsonpDiagnostic 'JSONP_ADAPTER_FAILED' $_.Exception.Message)
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

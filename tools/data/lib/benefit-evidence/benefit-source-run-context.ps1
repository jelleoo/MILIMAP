Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '../benefit-source/discover-official-benefit-sources.ps1')
. (Join-Path $PSScriptRoot 'convert-html-source-observation.ps1')
. (Join-Path $PSScriptRoot 'convert-mma-jsonp-source-observation.ps1')
. (Join-Path $PSScriptRoot 'convert-xlsx-source-observation.ps1')

function New-BenefitSourceRunContext {
    $payloadCache = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $templateCache = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $attempts = [Collections.Generic.List[object]]::new()
    $metrics = [pscustomobject][ordered]@{
        ExternalFetchCount=0
        FetchCacheHits=0
        AdapterParseCount=0
        AdapterReuseCount=0
        UniqueRequestKeys=0
        SourceFetchFailures=0
    }
    return [pscustomobject][ordered]@{
        ContextType='BenefitSourceRunContext'
        ContextVersion=1
        PayloadCache=$payloadCache
        TemplateCache=$templateCache
        Metrics=$metrics
        Attempts=$attempts
        RequestInvokerBound=$false
        RequestInvokerProfile=$null
    }
}

function Assert-BenefitSourceRunContext {
    param([Parameter(Mandatory)]$Context)
    foreach ($property in @('ContextType','ContextVersion','PayloadCache','TemplateCache','Metrics','Attempts','RequestInvokerBound','RequestInvokerProfile')) {
        if ($Context.PSObject.Properties.Name -notcontains $property) { throw "Run context is missing $property" }
    }
    if ($Context.ContextType -cne 'BenefitSourceRunContext' -or [int]$Context.ContextVersion -ne 1) { throw 'Invalid benefit source run context' }
    if ($Context.PayloadCache -isnot [Collections.Generic.Dictionary[string,object]] -or
        $Context.TemplateCache -isnot [Collections.Generic.Dictionary[string,object]]) { throw 'Run context caches must be ordinal dictionaries' }
    foreach ($metric in @('ExternalFetchCount','FetchCacheHits','AdapterParseCount','AdapterReuseCount','UniqueRequestKeys','SourceFetchFailures')) {
        if ($Context.Metrics.PSObject.Properties.Name -notcontains $metric) { throw "Run context metrics are missing $metric" }
    }
}

function Copy-BenefitRunBytes {
    param([AllowNull()][byte[]]$Bytes)
    if ($null -eq $Bytes) { return $null }
    return [byte[]]$Bytes.Clone()
}

function New-BenefitRunDocumentFromPayload {
    param([Parameter(Mandatory)]$Candidate, [Parameter(Mandatory)]$Payload)
    return New-BenefitSourceDocument -SourceRowNumber $Candidate.SourceRowNumber -Url $Payload.Url -SourceFormat $Payload.SourceFormat -FetchStatus $Payload.FetchStatus -ContentType $Payload.ContentType -Text $Payload.Text -Bytes (Copy-BenefitRunBytes $Payload.Bytes) -ObservedAt $Payload.ObservedAt -ReasonCodes @($Payload.ReasonCodes)
}

function Assert-BenefitRunRequestInvokerProfile {
    param([Parameter(Mandatory)]$Context, [AllowNull()][scriptblock]$RequestInvoker)
    if ($null -eq $RequestInvoker) { return }
    if (-not [bool]$Context.RequestInvokerBound) {
        $Context.RequestInvokerProfile = $RequestInvoker
        $Context.RequestInvokerBound = $true
        return
    }
    if (-not [object]::ReferenceEquals($Context.RequestInvokerProfile, $RequestInvoker)) {
        throw 'Cannot change RequestInvoker profile in an existing run context'
    }
}

function Get-BenefitRunSourceDocument {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$Candidate,
        [AllowNull()][scriptblock]$RequestInvoker=$null
    )
    Assert-BenefitSourceRunContext $Context
    Assert-BenefitSourceCandidate $Candidate
    Assert-BenefitRunRequestInvokerProfile -Context $Context -RequestInvoker $RequestInvoker

    $key = [string]$Candidate.Url
    if ($Context.PayloadCache.ContainsKey($key)) {
        $Context.Metrics.FetchCacheHits++
        $payload = $Context.PayloadCache[$key]
        [void]$Context.Attempts.Add([pscustomobject][ordered]@{Stage='FETCH';Key=$key;CacheHit=$true;Status=$payload.FetchStatus})
        return New-BenefitRunDocumentFromPayload -Candidate $Candidate -Payload $payload
    }

    $countingRequest = $null
    if ($null -ne $RequestInvoker) {
        $innerRequest = $RequestInvoker
        $metrics = $Context.Metrics
        $countingRequest = {
            param($Uri)
            $metrics.ExternalFetchCount++
            & $innerRequest $Uri
        }.GetNewClosure()
    }

    $document = Get-BenefitSourceDocument -Candidate $Candidate -RequestInvoker $countingRequest
    $payload = [pscustomobject][ordered]@{
        Url=[string]$document.Url
        SourceFormat=[string]$document.SourceFormat
        FetchStatus=[string]$document.FetchStatus
        ContentType=[string]$document.ContentType
        Text=[string]$document.Text
        Bytes=(Copy-BenefitRunBytes $document.Bytes)
        ObservedAt=[string]$document.ObservedAt
        ReasonCodes=@($document.ReasonCodes)
    }
    $Context.PayloadCache.Add($key, $payload)
    $Context.Metrics.UniqueRequestKeys = $Context.PayloadCache.Count
    if ($document.FetchStatus -ceq 'FAILED') { $Context.Metrics.SourceFetchFailures++ }
    [void]$Context.Attempts.Add([pscustomobject][ordered]@{Stage='FETCH';Key=$key;CacheHit=$false;Status=$document.FetchStatus})
    return New-BenefitRunDocumentFromPayload -Candidate $Candidate -Payload $payload
}

function Get-BenefitRunExplicitDocument {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)]$Candidate, [Parameter(Mandatory)][ValidateSet('JSONP')][string]$SourceFormat, [AllowNull()][scriptblock]$RequestInvoker=$null)
    Assert-BenefitSourceRunContext $Context
    Assert-BenefitSourceCandidate $Candidate
    Assert-BenefitRunRequestInvokerProfile -Context $Context -RequestInvoker $RequestInvoker
    $key = "EXPLICIT_$SourceFormat|$($Candidate.Url)"
    if ($Context.PayloadCache.ContainsKey($key)) {
        $Context.Metrics.FetchCacheHits++
        $payload=$Context.PayloadCache[$key]
        [void]$Context.Attempts.Add([pscustomobject][ordered]@{Stage='FETCH';Key=$key;CacheHit=$true;Status=$payload.FetchStatus})
        return New-BenefitRunDocumentFromPayload -Candidate $Candidate -Payload $payload
    }
    $countingRequest=$null
    if ($null -ne $RequestInvoker) {
        $inner=$RequestInvoker; $metrics=$Context.Metrics
        $countingRequest={ param($Uri) $metrics.ExternalFetchCount++; & $inner $Uri }.GetNewClosure()
    }
    $fetched=Get-BenefitSourceDocument -Candidate $Candidate -RequestInvoker $countingRequest
    $document=New-BenefitSourceDocument -SourceRowNumber $Candidate.SourceRowNumber -Url $fetched.Url -SourceFormat $SourceFormat -FetchStatus $fetched.FetchStatus -ContentType $fetched.ContentType -Text $fetched.Text -Bytes (Copy-BenefitRunBytes $fetched.Bytes) -ObservedAt $fetched.ObservedAt -ReasonCodes $fetched.ReasonCodes
    $payload=[pscustomobject][ordered]@{Url=$document.Url;SourceFormat=$document.SourceFormat;FetchStatus=$document.FetchStatus;ContentType=$document.ContentType;Text=$document.Text;Bytes=(Copy-BenefitRunBytes $document.Bytes);ObservedAt=$document.ObservedAt;ReasonCodes=@($document.ReasonCodes)}
    $Context.PayloadCache.Add($key,$payload); $Context.Metrics.UniqueRequestKeys=$Context.PayloadCache.Count
    if ($document.FetchStatus -ceq 'FAILED') {$Context.Metrics.SourceFetchFailures++}
    [void]$Context.Attempts.Add([pscustomobject][ordered]@{Stage='FETCH';Key=$key;CacheHit=$false;Status=$document.FetchStatus})
    return New-BenefitRunDocumentFromPayload -Candidate $Candidate -Payload $payload
}

function Get-BenefitRunMmaJsonpObservation {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)]$Document, [Parameter(Mandatory)][ValidateSet('LIST','DETAIL')][string]$Role, [Parameter(Mandatory)][string]$ExpectedCallback)
    Assert-BenefitSourceRunContext $Context; Assert-BenefitSourceDocument $Document
    if ($Document.FetchStatus -cne 'COMPLETE' -or $Document.SourceFormat -cne 'JSONP') { throw 'MMA JSONP observation requires a successful JSONP document' }
    $snapshot=New-BenefitSourceSnapshot -SourceUrl $Document.Url -SourceFormat JSONP -Text $Document.Text -ObservedAt $Document.ObservedAt
    $adapterId="MMA_JSONP_$Role"; $key="$($snapshot.SnapshotId)|$adapterId|1"
    if ($Context.TemplateCache.ContainsKey($key)) { $Context.Metrics.AdapterReuseCount++; $template=$Context.TemplateCache[$key]; $cacheHit=$true }
    else {
        $template=if ($Role -ceq 'LIST') { ConvertTo-MmaJsonpListObservation -Document $Document -ExpectedCallback $ExpectedCallback } else { ConvertTo-MmaJsonpDetailObservation -Document $Document -ExpectedCallback $ExpectedCallback }
        $Context.TemplateCache.Add($key,$template); $Context.Metrics.AdapterParseCount++; $cacheHit=$false
    }
    [void]$Context.Attempts.Add([pscustomobject][ordered]@{Stage='PARSE';Key=$key;CacheHit=$cacheHit;Status=$template.AdapterStatus})
    return New-BenefitSourceObservation -SourceRowNumber $Document.SourceRowNumber -Snapshot $snapshot -AdapterId $template.AdapterId -AdapterVersion $template.AdapterVersion -AdapterStatus $template.AdapterStatus -ContentUnits $template.ContentUnits -Diagnostics $template.Diagnostics
}

function Get-BenefitRunHtmlObservation {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)]$Document)
    Assert-BenefitSourceRunContext $Context
    Assert-BenefitSourceDocument $Document
    if ($Document.FetchStatus -cne 'COMPLETE') { throw 'HTML observation requires a successfully fetched source document' }

    $snapshot = New-BenefitSourceSnapshot -SourceUrl $Document.Url -SourceFormat $Document.SourceFormat -Text $Document.Text -ObservedAt $Document.ObservedAt
    $adapterId = 'HTML_GENERIC'
    $adapterVersion = '1'
    $key = "$($snapshot.SnapshotId)|$adapterId|$adapterVersion"

    if ($Context.TemplateCache.ContainsKey($key)) {
        $Context.Metrics.AdapterReuseCount++
        $template = $Context.TemplateCache[$key]
        $cacheHit = $true
    } else {
        $template = ConvertTo-BenefitHtmlTemplate -Snapshot $snapshot
        $Context.TemplateCache.Add($key, $template)
        $Context.Metrics.AdapterParseCount++
        $cacheHit = $false
    }

    $htmlValidationIndex = $template.HtmlValidationIndex
    $htmlTokens = if ($null -eq $htmlValidationIndex) { $null } else { @($htmlValidationIndex.Tokens) }
    $units = @()
    foreach ($row in @($template.Rows)) {
        $units += New-BenefitSourceContentUnit -Snapshot $snapshot -UnitReference $row.UnitReference -TableStart $row.TableStart -TableLength $row.TableLength -RawStart $row.RawStart -RawLength $row.RawLength -RawEvidenceText $row.RawEvidenceText -StructuredFields $row.StructuredFields -FieldReferences $row.FieldReferences -HtmlTokens $htmlTokens -HtmlValidationIndex $htmlValidationIndex
    }
    [void]$Context.Attempts.Add([pscustomobject][ordered]@{Stage='PARSE';Key=$key;CacheHit=$cacheHit;Status=$template.AdapterStatus})
    return New-BenefitSourceObservation -SourceRowNumber $Document.SourceRowNumber -Snapshot $snapshot -AdapterId $adapterId -AdapterVersion $adapterVersion -AdapterStatus $template.AdapterStatus -ContentUnits $units -Diagnostics @($template.Diagnostics) -HtmlTokens $htmlTokens -HtmlValidationIndex $htmlValidationIndex
}

function Get-BenefitRunXlsxObservation {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)]$Document)
    Assert-BenefitSourceRunContext $Context; Assert-BenefitSourceDocument $Document
    if ($Document.FetchStatus -cne 'COMPLETE' -or $Document.SourceFormat -cne 'XLSX') { throw 'XLSX observation requires a successful XLSX document' }
    $payload = $Context.PayloadCache[[string]$Document.Url]
    if ($null -eq $payload) { throw 'XLSX observation requires a run-context payload' }
    if ($payload.PSObject.Properties.Name -notcontains 'XlsxSnapshot') {
        $payload | Add-Member -NotePropertyName XlsxSnapshot -NotePropertyValue (New-BenefitSourceSnapshot -SourceUrl $Document.Url -SourceFormat XLSX -Text '' -Bytes $Document.Bytes -ObservedAt $Document.ObservedAt)
    }
    $snapshot=$payload.XlsxSnapshot; $adapterId='XLSX_GENERIC'; $key="$($snapshot.SnapshotId)|$adapterId|1"
    # Use the exact byte array which was validated to create the cached
    # snapshot.  Later scoped stages can prove this identity by reference and
    # reuse its index without rehashing a copied workbook.
    $Document.Bytes = $snapshot.Bytes
    if ($Document.PSObject.Properties.Name -notcontains 'ValidatedXlsxSnapshot') {
        $Document | Add-Member -NotePropertyName ValidatedXlsxSnapshot -NotePropertyValue $snapshot
    }
    if ($Context.TemplateCache.ContainsKey($key)) { $Context.Metrics.AdapterReuseCount++; $template=$Context.TemplateCache[$key]; $cacheHit=$true }
    else { $template=ConvertTo-BenefitXlsxObservation -Document $Document -Snapshot $snapshot; $Context.TemplateCache.Add($key,$template); $Context.Metrics.AdapterParseCount++; $cacheHit=$false }
    [void]$Context.Attempts.Add([pscustomobject][ordered]@{Stage='PARSE';Key=$key;CacheHit=$cacheHit;Status=$template.AdapterStatus})
    $observation=New-BenefitSourceObservation -SourceRowNumber $Document.SourceRowNumber -Snapshot $snapshot -AdapterId $template.AdapterId -AdapterVersion $template.AdapterVersion -AdapterStatus $template.AdapterStatus -ContentUnits $template.ContentUnits -Diagnostics $template.Diagnostics -XlsxValidationIndex $template.XlsxValidationIndex -SnapshotAlreadyValidated
    $observation | Add-Member -NotePropertyName XlsxValidationIndex -NotePropertyValue $template.XlsxValidationIndex
    return $observation
}

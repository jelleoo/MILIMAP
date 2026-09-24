Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'benefit-verification-contracts.ps1')
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'benefit-evidence-location-contracts.ps1')

$script:BenefitStructuredHeaders = @('할인','할인정보','할인내용','혜택','서비스')
$script:BenefitStructuredContextHeaders = @('업소명','업체명','상호','주소','소재지','소재지도로명주소','전화번호','연락처')

function ConvertTo-BenefitEvidenceText {
    param([AllowNull()]$Value)
    $text = [Net.WebUtility]::HtmlDecode([string]$Value)
    $text = $text -replace '<[^>]+>', ' '
    return (($text -replace '\s+', ' ').Trim())
}

function New-BenefitEvidenceExtractionResult {
    param([Parameter(Mandatory)]$Source, [Parameter(Mandatory)][string]$Status, [AllowNull()][object[]]$Claims=@(), [AllowNull()][object[]]$ReasonCodes=@(), [AllowNull()][string]$SourceRepresentation='')
    Assert-BenefitAllowedCode 'ExtractionStatus' $Status
    Assert-BenefitReasonCodes $ReasonCodes
    [pscustomobject][ordered]@{ SourceRowNumber=[int]$Source.SourceRowNumber; Status=$Status; Claims=@($Claims | Where-Object { $null -ne $_ }); ReasonCodes=@($ReasonCodes | Where-Object { $null -ne $_ }); SourceRepresentation=$SourceRepresentation }
}

function Assert-BenefitEvidenceSourceDocument {
    param([Parameter(Mandatory)]$Source, [Parameter(Mandatory)]$Document)
    Assert-BoundBenefitSource $Source
    Assert-BenefitSourceDocument $Document
    $carriedDocument = $Source.QualifiedSource.Document
    if ([int]$Source.SourceRowNumber -ne [int]$Document.SourceRowNumber -or [int]$carriedDocument.SourceRowNumber -ne [int]$Document.SourceRowNumber) { throw 'Evidence extraction inputs must preserve one SourceRowNumber' }
    if ([string]$carriedDocument.Url -cne [string]$Document.Url) { throw 'Evidence extraction document must match bound source provenance' }
}

function Get-BenefitStructuredEvidenceText {
    param([Parameter(Mandatory)]$Row, [Parameter(Mandatory)][string]$BenefitHeader)
    $parts=@()
    foreach($property in @($Row.PSObject.Properties)){
        $header=ConvertTo-BenefitEvidenceText $property.Name
        if($header -ne $BenefitHeader -and $script:BenefitStructuredContextHeaders -notcontains $header){continue}
        $value=ConvertTo-BenefitEvidenceText $property.Value
        if($value){$parts += ('{0}: {1}' -f $header,$value)}
    }
    return ($parts -join ' | ')
}

function Get-BenefitStructuredSourceRepresentation {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rows)
    $evidence=@()
    foreach($row in $Rows){
        foreach($property in @($row.PSObject.Properties)){
            $header=ConvertTo-BenefitEvidenceText $property.Name
            if($script:BenefitStructuredHeaders -notcontains $header){continue}
            $text=Get-BenefitStructuredEvidenceText -Row $row -BenefitHeader $header
            if($text){$evidence += $text}
        }
    }
    return ($evidence -join "`n")
}

function Get-BenefitStructuredClaims {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rows, [Parameter(Mandatory)]$Document, [Parameter(Mandatory)][string]$Method, [Parameter(Mandatory)][string]$ReferencePrefix)
    $claims=@(); $rowNumber=0
    foreach ($row in $Rows) {
        $rowNumber++
        foreach ($property in @($row.PSObject.Properties)) {
            $header=ConvertTo-BenefitEvidenceText $property.Name
            if ($script:BenefitStructuredHeaders -notcontains $header) { continue }
            $value=ConvertTo-BenefitEvidenceText $property.Value
            if (-not $value) { continue }
            $evidenceText=Get-BenefitStructuredEvidenceText -Row $row -BenefitHeader $header
            $claim=New-ExtractedBenefitClaim -ClaimType 'BENEFIT_DESCRIPTION' -Value $value -EvidenceText $evidenceText -EvidenceReference ("{0}_ROW_{1}_{2}" -f $ReferencePrefix,$rowNumber,$header) -SourceUrl $Document.Url -ExtractionMethod $Method
            Assert-ExtractedBenefitClaim $claim
            $claims += $claim
        }
    }
    return @($claims)
}

function Get-BenefitHtmlStructuredRows {
    param([Parameter(Mandatory)][string]$Html)
    foreach($table in @([regex]::Matches($Html,'(?is)<table\b[^>]*>(?<content>.*?)</table>'))){
        $rows=@([regex]::Matches($table.Groups['content'].Value,'(?is)<tr\b[^>]*>(?<content>.*?)</tr>'))
        if($rows.Count -lt 2){continue}
        $headerMatches=@([regex]::Matches($rows[0].Groups['content'].Value,'(?is)<th\b[^>]*>(?<content>.*?)</th>'))
        if($headerMatches.Count -eq 0){continue}
        $headers=@($headerMatches|ForEach-Object{ConvertTo-BenefitEvidenceText $_.Groups['content'].Value})
        if(@($headers | Where-Object { $script:BenefitStructuredHeaders -contains $_ }).Count -eq 0){continue}
        $out=@()
        for($index=1;$index -lt $rows.Count;$index++){
            $cells=@([regex]::Matches($rows[$index].Groups['content'].Value,'(?is)<td\b[^>]*>(?<content>.*?)</td>'))
            if($cells.Count -ne $headers.Count){continue}
            $row=[ordered]@{}
            for($cellIndex=0;$cellIndex -lt $headers.Count;$cellIndex++){$row[$headers[$cellIndex]]=ConvertTo-BenefitEvidenceText $cells[$cellIndex].Groups['content'].Value}
            $out += [pscustomobject]$row
        }
        return @($out)
    }
    return $null
}

function ConvertTo-BenefitExtractorClaims {
    param([Parameter(Mandatory)]$Candidates, [Parameter(Mandatory)]$Document, [Parameter(Mandatory)][string]$Method)
    $claims=@()
    foreach($candidate in @($Candidates)){
        try{
            foreach($property in @('ClaimType','Value','EvidenceText')){if($candidate.PSObject.Properties.Name -notcontains $property){throw "Missing extractor property: $property"}}
            $reference=if($candidate.PSObject.Properties.Name -contains 'EvidenceReference'){[string]$candidate.EvidenceReference}else{''}
            $claim=New-ExtractedBenefitClaim -ClaimType ([string]$candidate.ClaimType) -Value ([string]$candidate.Value) -EvidenceText ([string]$candidate.EvidenceText) -EvidenceReference $reference -SourceUrl $Document.Url -ExtractionMethod $Method
            Assert-ExtractedBenefitClaim $claim;$claims += $claim
        }catch{throw 'Invalid extractor claim candidate'}
    }
    return @($claims)
}

function Invoke-BenefitEvidenceExtraction {
    param([Parameter(Mandatory)]$Source,[Parameter(Mandatory)]$Document,[AllowNull()][scriptblock]$UnstructuredExtractor=$null,[AllowNull()][scriptblock]$SpreadsheetExtractor=$null,[AllowNull()][scriptblock]$PdfTextExtractor=$null,[AllowNull()]$EvidenceSlice=$null)
    Assert-BenefitEvidenceSourceDocument -Source $Source -Document $Document
    if ($PSBoundParameters.ContainsKey('EvidenceSlice')) {
        if ($null -eq $EvidenceSlice) { throw 'Explicit scoped evidence cannot be null' }
        Assert-RelevantBenefitEvidenceSlice -Slice $EvidenceSlice -Document $Document -SourceRowNumber $Document.SourceRowNumber
        $detailMap = [ordered]@{ BenefitDescription='BENEFIT_DESCRIPTION'; EligibleTarget='ELIGIBLE_TARGET'; UsageCondition='USAGE_CONDITION'; VerificationMethod='VERIFICATION_METHOD' }
        $claims = @()
        foreach ($field in $detailMap.Keys) {
            if (-not $EvidenceSlice.StructuredFields.Contains($field) -or -not $EvidenceSlice.FieldReferences.Contains($field)) { continue }
            $value = [string]$EvidenceSlice.StructuredFields[$field]
            if ([string]::IsNullOrWhiteSpace($value)) { continue }
            $reference = $EvidenceSlice.FieldReferences[$field]
            if ($null -eq $reference -or [string]::IsNullOrWhiteSpace([string]$reference.FieldReference)) { continue }
            $claim = New-ExtractedBenefitClaim -ClaimType $detailMap[$field] -Value $value -EvidenceText $value -EvidenceReference $reference.FieldReference -SourceUrl $Document.Url -ExtractionMethod 'SCOPED_HTML_CELL'
            Assert-ExtractedBenefitClaim $claim
            $claims += $claim
        }
        return New-BenefitEvidenceExtractionResult -Source $Source -Status 'COMPLETE' -Claims $claims
    }
    if([string]$Document.FetchStatus -ne 'COMPLETE'){return New-BenefitEvidenceExtractionResult -Source $Source -Status 'FAILED' -ReasonCodes @($Document.ReasonCodes)}
    if([string]$Document.SourceFormat -eq 'UNSUPPORTED'){return New-BenefitEvidenceExtractionResult -Source $Source -Status 'FAILED' -ReasonCodes @('SOURCE_UNSUPPORTED')}
    try{
        switch([string]$Document.SourceFormat){
            'HTML' {
                $rows=Get-BenefitHtmlStructuredRows -Html $Document.Text
                if($null -ne $rows){return New-BenefitEvidenceExtractionResult -Source $Source -Status 'COMPLETE' -Claims (Get-BenefitStructuredClaims -Rows $rows -Document $Document -Method 'STRUCTURED_HTML_TABLE' -ReferencePrefix 'HTML_TABLE') -SourceRepresentation (Get-BenefitStructuredSourceRepresentation -Rows $rows)}
                if($null -eq $UnstructuredExtractor){return New-BenefitEvidenceExtractionResult -Source $Source -Status 'FAILED' -ReasonCodes @('EXTRACTION_PROVIDER_NOT_CONFIGURED')}
                return New-BenefitEvidenceExtractionResult -Source $Source -Status 'COMPLETE' -Claims (ConvertTo-BenefitExtractorClaims -Candidates (& $UnstructuredExtractor $Document.Text $Document $Source) -Document $Document -Method 'UNSTRUCTURED_EXTRACTOR') -SourceRepresentation $Document.Text
            }
            'CSV' {$rows=@($Document.Text|ConvertFrom-Csv);return New-BenefitEvidenceExtractionResult -Source $Source -Status 'COMPLETE' -Claims (Get-BenefitStructuredClaims -Rows $rows -Document $Document -Method 'CSV' -ReferencePrefix 'CSV') -SourceRepresentation (Get-BenefitStructuredSourceRepresentation -Rows $rows)}
            'XLSX' {
                if($null -eq $SpreadsheetExtractor){return New-BenefitEvidenceExtractionResult -Source $Source -Status 'FAILED' -ReasonCodes @('EXTRACTION_PROVIDER_NOT_CONFIGURED')}
                $rows=@(& $SpreadsheetExtractor $Document.Bytes $Document $Source)
                return New-BenefitEvidenceExtractionResult -Source $Source -Status 'COMPLETE' -Claims (Get-BenefitStructuredClaims -Rows $rows -Document $Document -Method 'SPREADSHEET_EXTRACTOR' -ReferencePrefix 'XLSX') -SourceRepresentation (Get-BenefitStructuredSourceRepresentation -Rows $rows)
            }
            'PDF' {
                if($null -eq $PdfTextExtractor){return New-BenefitEvidenceExtractionResult -Source $Source -Status 'FAILED' -ReasonCodes @('EXTRACTION_PROVIDER_NOT_CONFIGURED')}
                $pdfText=[string](& $PdfTextExtractor $Document.Bytes $Document $Source)
                if(-not (ConvertTo-BenefitEvidenceText $pdfText)){return New-BenefitEvidenceExtractionResult -Source $Source -Status 'FAILED' -ReasonCodes @('EXTRACTION_FAILED')}
                if($null -eq $UnstructuredExtractor){return New-BenefitEvidenceExtractionResult -Source $Source -Status 'FAILED' -ReasonCodes @('EXTRACTION_PROVIDER_NOT_CONFIGURED')}
                return New-BenefitEvidenceExtractionResult -Source $Source -Status 'COMPLETE' -Claims (ConvertTo-BenefitExtractorClaims -Candidates (& $UnstructuredExtractor $pdfText $Document $Source) -Document $Document -Method 'PDF_TEXT_UNSTRUCTURED_EXTRACTOR') -SourceRepresentation $pdfText
            }
            default {return New-BenefitEvidenceExtractionResult -Source $Source -Status 'FAILED' -ReasonCodes @('SOURCE_UNSUPPORTED')}
        }
    }catch{
        if($_.Exception.Message -eq 'Invalid extractor claim candidate'){return New-BenefitEvidenceExtractionResult -Source $Source -Status 'FAILED' -ReasonCodes @('EXTRACTION_SOURCE_MISMATCH')}
        return New-BenefitEvidenceExtractionResult -Source $Source -Status 'FAILED' -ReasonCodes @('EXTRACTION_FAILED')
    }
}

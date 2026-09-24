Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'benefit-verification-contracts.ps1')

$script:BenefitStructuredHeaders = @('할인','할인정보','할인내용','혜택','서비스')

function ConvertTo-BenefitEvidenceText {
    param([AllowNull()]$Value)
    $text = [Net.WebUtility]::HtmlDecode([string]$Value)
    $text = $text -replace '<[^>]+>', ' '
    return (($text -replace '\s+', ' ').Trim())
}

function New-BenefitEvidenceExtractionResult {
    param([Parameter(Mandatory)]$Source, [Parameter(Mandatory)][string]$Status, [AllowNull()][object[]]$Claims=@(), [AllowNull()][object[]]$ReasonCodes=@())
    Assert-BenefitAllowedCode 'ExtractionStatus' $Status
    Assert-BenefitReasonCodes $ReasonCodes
    [pscustomobject][ordered]@{ SourceRowNumber=[int]$Source.SourceRowNumber; Status=$Status; Claims=@($Claims | Where-Object { $null -ne $_ }); ReasonCodes=@($ReasonCodes | Where-Object { $null -ne $_ }) }
}

function Assert-BenefitEvidenceSourceDocument {
    param([Parameter(Mandatory)]$Source, [Parameter(Mandatory)]$Document)
    Assert-BoundBenefitSource $Source
    Assert-BenefitSourceDocument $Document
    $carriedDocument = $Source.QualifiedSource.Document
    if ([int]$Source.SourceRowNumber -ne [int]$Document.SourceRowNumber -or [int]$carriedDocument.SourceRowNumber -ne [int]$Document.SourceRowNumber) { throw 'Evidence extraction inputs must preserve one SourceRowNumber' }
    if ([string]$carriedDocument.Url -cne [string]$Document.Url) { throw 'Evidence extraction document must match bound source provenance' }
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
            $claim=New-ExtractedBenefitClaim -ClaimType 'BENEFIT_DESCRIPTION' -Value $value -EvidenceText $value -EvidenceReference ("{0}_ROW_{1}_{2}" -f $ReferencePrefix,$rowNumber,$header) -SourceUrl $Document.Url -ExtractionMethod $Method
            Assert-ExtractedBenefitClaim $claim
            $claims += $claim
        }
    }
    return @($claims)
}

function Get-BenefitHtmlStructuredRows {
    param([Parameter(Mandatory)][string]$Html)
    $table=[regex]::Match($Html,'(?is)<table\b[^>]*>(?<content>.*?)</table>')
    if(-not $table.Success){return $null}
    $rows=@([regex]::Matches($table.Groups['content'].Value,'(?is)<tr\b[^>]*>(?<content>.*?)</tr>'))
    if($rows.Count -lt 2){return $null}
    $headerMatches=@([regex]::Matches($rows[0].Groups['content'].Value,'(?is)<th\b[^>]*>(?<content>.*?)</th>'))
    if($headerMatches.Count -eq 0){return $null}
    $headers=@($headerMatches|ForEach-Object{ConvertTo-BenefitEvidenceText $_.Groups['content'].Value});$out=@()
    for($index=1;$index -lt $rows.Count;$index++){
        $cells=@([regex]::Matches($rows[$index].Groups['content'].Value,'(?is)<td\b[^>]*>(?<content>.*?)</td>'))
        if($cells.Count -ne $headers.Count){continue}
        $row=[ordered]@{}
        for($cellIndex=0;$cellIndex -lt $headers.Count;$cellIndex++){$row[$headers[$cellIndex]]=ConvertTo-BenefitEvidenceText $cells[$cellIndex].Groups['content'].Value}
        $out += [pscustomobject]$row
    }
    return @($out)
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
    param([Parameter(Mandatory)]$Source,[Parameter(Mandatory)]$Document,[AllowNull()][scriptblock]$UnstructuredExtractor=$null,[AllowNull()][scriptblock]$SpreadsheetExtractor=$null,[AllowNull()][scriptblock]$PdfTextExtractor=$null)
    Assert-BenefitEvidenceSourceDocument -Source $Source -Document $Document
    if([string]$Document.FetchStatus -ne 'COMPLETE'){return New-BenefitEvidenceExtractionResult -Source $Source -Status 'FAILED' -ReasonCodes @($Document.ReasonCodes)}
    if([string]$Document.SourceFormat -eq 'UNSUPPORTED'){return New-BenefitEvidenceExtractionResult -Source $Source -Status 'FAILED' -ReasonCodes @('SOURCE_UNSUPPORTED')}
    try{
        switch([string]$Document.SourceFormat){
            'HTML' {
                $rows=Get-BenefitHtmlStructuredRows -Html $Document.Text
                if($null -ne $rows){return New-BenefitEvidenceExtractionResult -Source $Source -Status 'COMPLETE' -Claims (Get-BenefitStructuredClaims -Rows $rows -Document $Document -Method 'STRUCTURED_HTML_TABLE' -ReferencePrefix 'HTML_TABLE')}
                if($null -eq $UnstructuredExtractor){return New-BenefitEvidenceExtractionResult -Source $Source -Status 'FAILED' -ReasonCodes @('EXTRACTION_PROVIDER_NOT_CONFIGURED')}
                return New-BenefitEvidenceExtractionResult -Source $Source -Status 'COMPLETE' -Claims (ConvertTo-BenefitExtractorClaims -Candidates (& $UnstructuredExtractor $Document.Text $Document $Source) -Document $Document -Method 'UNSTRUCTURED_EXTRACTOR')
            }
            'CSV' {return New-BenefitEvidenceExtractionResult -Source $Source -Status 'COMPLETE' -Claims (Get-BenefitStructuredClaims -Rows @($Document.Text|ConvertFrom-Csv) -Document $Document -Method 'CSV' -ReferencePrefix 'CSV')}
            'XLSX' {
                if($null -eq $SpreadsheetExtractor){return New-BenefitEvidenceExtractionResult -Source $Source -Status 'FAILED' -ReasonCodes @('EXTRACTION_PROVIDER_NOT_CONFIGURED')}
                return New-BenefitEvidenceExtractionResult -Source $Source -Status 'COMPLETE' -Claims (Get-BenefitStructuredClaims -Rows @(& $SpreadsheetExtractor $Document.Bytes $Document $Source) -Document $Document -Method 'SPREADSHEET_EXTRACTOR' -ReferencePrefix 'XLSX')
            }
            'PDF' {
                if($null -eq $PdfTextExtractor){return New-BenefitEvidenceExtractionResult -Source $Source -Status 'FAILED' -ReasonCodes @('EXTRACTION_PROVIDER_NOT_CONFIGURED')}
                $pdfText=[string](& $PdfTextExtractor $Document.Bytes $Document $Source)
                if(-not (ConvertTo-BenefitEvidenceText $pdfText)){return New-BenefitEvidenceExtractionResult -Source $Source -Status 'FAILED' -ReasonCodes @('EXTRACTION_FAILED')}
                if($null -eq $UnstructuredExtractor){return New-BenefitEvidenceExtractionResult -Source $Source -Status 'FAILED' -ReasonCodes @('EXTRACTION_PROVIDER_NOT_CONFIGURED')}
                return New-BenefitEvidenceExtractionResult -Source $Source -Status 'COMPLETE' -Claims (ConvertTo-BenefitExtractorClaims -Candidates (& $UnstructuredExtractor $pdfText $Document $Source) -Document $Document -Method 'PDF_TEXT_UNSTRUCTURED_EXTRACTOR')
            }
            default {return New-BenefitEvidenceExtractionResult -Source $Source -Status 'FAILED' -ReasonCodes @('SOURCE_UNSUPPORTED')}
        }
    }catch{
        if($_.Exception.Message -eq 'Invalid extractor claim candidate'){return New-BenefitEvidenceExtractionResult -Source $Source -Status 'FAILED' -ReasonCodes @('EXTRACTION_SOURCE_MISMATCH')}
        return New-BenefitEvidenceExtractionResult -Source $Source -Status 'FAILED' -ReasonCodes @('EXTRACTION_FAILED')
    }
}

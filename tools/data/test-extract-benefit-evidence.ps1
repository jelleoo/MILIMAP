$ErrorActionPreference = 'Stop'

$contractPath = Join-Path $PSScriptRoot 'lib/benefit-verification-contracts.ps1'
$extractionPath = Join-Path $PSScriptRoot 'lib/benefit-evidence/extract-benefit-evidence.ps1'
. $contractPath
if (Test-Path -LiteralPath $extractionPath) { . $extractionPath }

function Assert-Equal {
    param([AllowNull()]$Actual, [AllowNull()]$Expected, [Parameter(Mandatory)][string]$Message)
    if ($Actual -cne $Expected) { throw "$Message (expected: $Expected, actual: $Actual)" }
}

function Assert-True {
    param([bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Throws {
    param([Parameter(Mandatory)][scriptblock]$Action, [Parameter(Mandatory)][string]$Message)
    $threw = $false
    try { & $Action } catch { $threw = $true }
    if (-not $threw) { throw $Message }
}

function New-TestDocument {
    param([string]$Url, [string]$SourceFormat='HTML', [string]$FetchStatus='COMPLETE', [string]$Text='', [int]$SourceRowNumber=2, [AllowNull()][byte[]]$Bytes=$null)
    return New-BenefitSourceDocument -SourceRowNumber $SourceRowNumber -Url $Url -SourceFormat $SourceFormat -FetchStatus $FetchStatus -ContentType 'fixture' -Text $Text -Bytes $Bytes -ObservedAt '2026-09-24T00:00:00Z'
}

function New-TestBoundSource {
    param([Parameter(Mandatory)]$Document, [int]$SourceRowNumber=2)
    $candidate = New-BenefitSourceCandidate -SourceRowNumber $SourceRowNumber -Url $Document.Url -SourceKind 'PUBLIC_OFFICIAL' -SourceLabel 'fixture' -DiscoveryMethod 'TEST' -ObservedAt '2026-09-24T00:00:00Z'
    $qualified = New-QualifiedBenefitSource -Candidate $candidate -Document $Document -OfficialityStatus 'VERIFIED_OFFICIAL' -CurrentnessStatus 'UNKNOWN'
    return New-BoundBenefitSource -QualifiedSource $qualified -BusinessBindingStatus 'STRONG' -BindingEvidence @('fixture')
}

$html = '<table><tr><th>업소명</th><th>주소</th><th>할인</th></tr><tr><td>테스트 식당</td><td>서울 마포구 테스트로 12</td><td>10% 할인</td></tr></table>'
$htmlDocument = New-TestDocument -Url 'https://city.example.go.kr/list' -Text $html
$htmlExtraction = Invoke-BenefitEvidenceExtraction -Source (New-TestBoundSource -Document $htmlDocument) -Document $htmlDocument
Assert-Equal $htmlExtraction.Status 'COMPLETE' 'Recognized structured HTML table must complete deterministically'
Assert-Equal $htmlExtraction.SourceRowNumber 2 'Extraction must preserve source row'
$htmlClaim = @($htmlExtraction.Claims | Where-Object { $_.ClaimType -eq 'BENEFIT_DESCRIPTION' -and $_.Value -eq '10% 할인' })
Assert-Equal $htmlClaim.Count 1 'Recognized HTML benefit cell must produce exactly one benefit-description claim'
Assert-ExtractedBenefitClaim $htmlClaim[0]
Assert-Equal $htmlClaim[0].SourceUrl $htmlDocument.Url 'Structured HTML claim must preserve document URL'
Assert-True ($htmlClaim[0].EvidenceText -like '*10% 할인*') 'Structured HTML claim evidence must preserve source-supported benefit text'

$unknownHtml = '<table><tr><th>업소명</th><th>비고</th></tr><tr><td>테스트 식당</td><td>10% 할인</td></tr></table>'
$unknownDocument = New-TestDocument -Url 'https://city.example.go.kr/unknown' -Text $unknownHtml
$unknownExtraction = Invoke-BenefitEvidenceExtraction -Source (New-TestBoundSource -Document $unknownDocument) -Document $unknownDocument
Assert-Equal @($unknownExtraction.Claims).Count 0 'Unknown structured columns must not create claims'

$csvDocument = New-TestDocument -Url 'https://city.example.go.kr/list.csv' -SourceFormat 'CSV' -Text "업소명,할인`n테스트 식당,10% 할인"
$csvExtraction = Invoke-BenefitEvidenceExtraction -Source (New-TestBoundSource -Document $csvDocument) -Document $csvDocument
Assert-Equal $csvExtraction.Status 'COMPLETE' 'Recognized CSV extraction must complete deterministically'
Assert-Equal @($csvExtraction.Claims | Where-Object { $_.ClaimType -eq 'BENEFIT_DESCRIPTION' -and $_.Value -eq '10% 할인' }).Count 1 'Recognized CSV benefit field must produce a benefit-description claim'

$freeDocument = New-TestDocument -Url 'https://city.example.go.kr/notice' -Text '<p>현역 장병 혜택 안내</p>'
$noExtractor = Invoke-BenefitEvidenceExtraction -Source (New-TestBoundSource -Document $freeDocument) -Document $freeDocument
Assert-Equal $noExtractor.Status 'FAILED' 'Free-form HTML without extractor must fail operationally'
Assert-True ($noExtractor.ReasonCodes -contains 'EXTRACTION_PROVIDER_NOT_CONFIGURED') 'Missing free-form extractor must preserve provider reason'

$injected = Invoke-BenefitEvidenceExtraction -Source (New-TestBoundSource -Document $freeDocument) -Document $freeDocument -UnstructuredExtractor {
    param($Text, $ExtractorDocument, $ExtractorSource)
    [pscustomobject]@{ ClaimType='BENEFIT_DESCRIPTION'; Value='20% 할인'; EvidenceText='현역 장병 20% 할인'; EvidenceReference='extractor:1' }
}
Assert-Equal $injected.Status 'COMPLETE' 'Injected free-form extractor must complete operationally'
Assert-Equal @($injected.Claims).Count 1 'Injected candidate must produce one extracted claim'
Assert-Equal $injected.Claims[0].ClaimType 'BENEFIT_DESCRIPTION' 'Injected claim type must be preserved'
Assert-Equal $injected.Claims[0].Value '20% 할인' 'Injected value must be preserved'
Assert-Equal $injected.Claims[0].EvidenceText '현역 장병 20% 할인' 'Injected evidence text must be preserved'
Assert-Equal $injected.Claims[0].SourceUrl $freeDocument.Url 'Injected claim must preserve document URL'
Assert-True (-not [string]::IsNullOrWhiteSpace($injected.Claims[0].ExtractionMethod)) 'Injected claim must preserve extraction provenance'

$invalidInjected = Invoke-BenefitEvidenceExtraction -Source (New-TestBoundSource -Document $freeDocument) -Document $freeDocument -UnstructuredExtractor {
    param($Text, $ExtractorDocument, $ExtractorSource)
    [pscustomobject]@{ ClaimType='INVENTED_TYPE'; Value='20% 할인'; EvidenceText='현역 장병 20% 할인'; EvidenceReference='extractor:1' }
}
Assert-Equal $invalidInjected.Status 'FAILED' 'Invalid extractor claim type must fail closed'
Assert-Equal @($invalidInjected.Claims).Count 0 'Invalid extractor claim must not become usable evidence'
Assert-True ($invalidInjected.ReasonCodes -contains 'EXTRACTION_SOURCE_MISMATCH') 'Invalid extractor output preserves mismatch reason'

$pdfDocument = New-TestDocument -Url 'https://city.example.go.kr/a.pdf' -SourceFormat 'PDF' -Bytes ([byte[]](1,2,3))
$noPdfExtractor = Invoke-BenefitEvidenceExtraction -Source (New-TestBoundSource -Document $pdfDocument) -Document $pdfDocument
Assert-Equal $noPdfExtractor.Status 'FAILED' 'PDF without injected text extractor must fail operationally'
Assert-True ($noPdfExtractor.ReasonCodes -contains 'EXTRACTION_PROVIDER_NOT_CONFIGURED') 'Missing PDF extractor preserves provider reason'

$pdfWithoutUnstructured = Invoke-BenefitEvidenceExtraction -Source (New-TestBoundSource -Document $pdfDocument) -Document $pdfDocument -PdfTextExtractor { param($Bytes, $ExtractorDocument, $ExtractorSource) '현역 장병 혜택 안내' }
Assert-Equal $pdfWithoutUnstructured.Status 'FAILED' 'PDF free text without unstructured extractor must fail closed'
Assert-True ($pdfWithoutUnstructured.ReasonCodes -contains 'EXTRACTION_PROVIDER_NOT_CONFIGURED') 'PDF free text preserves missing unstructured extractor reason'

$xlsxDocument = New-TestDocument -Url 'https://city.example.go.kr/list.xlsx' -SourceFormat 'XLSX' -Bytes ([byte[]](1,2,3))
$noSpreadsheetExtractor = Invoke-BenefitEvidenceExtraction -Source (New-TestBoundSource -Document $xlsxDocument) -Document $xlsxDocument
Assert-Equal $noSpreadsheetExtractor.Status 'FAILED' 'XLSX without injected spreadsheet extractor must fail operationally'
Assert-True ($noSpreadsheetExtractor.ReasonCodes -contains 'EXTRACTION_PROVIDER_NOT_CONFIGURED') 'Missing spreadsheet extractor preserves provider reason'

$xlsxExtraction = Invoke-BenefitEvidenceExtraction -Source (New-TestBoundSource -Document $xlsxDocument) -Document $xlsxDocument -SpreadsheetExtractor {
    param($Bytes, $ExtractorDocument, $ExtractorSource)
    @([pscustomobject]@{ 업소명='테스트 식당'; 할인='15% 할인' })
}
Assert-Equal $xlsxExtraction.Status 'COMPLETE' 'Injected XLSX structured representation must complete'
Assert-Equal @($xlsxExtraction.Claims | Where-Object { $_.ClaimType -eq 'BENEFIT_DESCRIPTION' -and $_.Value -eq '15% 할인' }).Count 1 'Injected XLSX recognized benefit field must produce a claim'

$unsupportedDocument = New-TestDocument -Url 'https://city.example.go.kr/archive.bin' -SourceFormat 'UNSUPPORTED'
$unsupported = Invoke-BenefitEvidenceExtraction -Source (New-TestBoundSource -Document $unsupportedDocument) -Document $unsupportedDocument
Assert-Equal $unsupported.Status 'FAILED' 'Unsupported source format must fail operationally'
Assert-True ($unsupported.ReasonCodes -contains 'SOURCE_UNSUPPORTED') 'Unsupported source format preserves source reason'

$failedDocument = New-TestDocument -Url 'https://city.example.go.kr/failed' -FetchStatus 'FAILED'
$failed = Invoke-BenefitEvidenceExtraction -Source (New-TestBoundSource -Document $failedDocument) -Document $failedDocument
Assert-Equal $failed.Status 'FAILED' 'Failed fetch must not extract claims'
Assert-Equal @($failed.Claims).Count 0 'Failed fetch must preserve no claims'

$sourceDocument = New-TestDocument -Url 'https://city.example.go.kr/provenance' -Text $html
$mismatchedDocument = New-TestDocument -Url $sourceDocument.Url -Text $html -SourceRowNumber 3
Assert-Throws { Invoke-BenefitEvidenceExtraction -Source (New-TestBoundSource -Document $sourceDocument) -Document $mismatchedDocument } 'Extraction must fail closed on source-row mismatch'

$unrelatedDocument = New-TestDocument -Url 'https://unrelated.example.com/provenance' -Text $html
Assert-Throws { Invoke-BenefitEvidenceExtraction -Source (New-TestBoundSource -Document $sourceDocument) -Document $unrelatedDocument } 'Extraction must fail closed on document provenance mismatch'

Write-Host 'Benefit evidence extraction tests passed.'

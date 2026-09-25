Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'benefit-source-run-context.ps1')
. (Join-Path $PSScriptRoot 'find-business-evidence-slice.ps1')
. (Join-Path $PSScriptRoot '../benefit-source/qualify-official-benefit-source.ps1')
. (Join-Path $PSScriptRoot '../benefit-source/bind-benefit-source.ps1')
. (Join-Path $PSScriptRoot 'extract-benefit-evidence.ps1')
. (Join-Path $PSScriptRoot 'validate-benefit-evidence.ps1')

$script:MmaEntryUrl='https://www.mma.go.kr/about/udgg/list.do?mc=mma0003357'
$script:MmaListUrl='https://open.mma.go.kr/caisGGGS/mmanrsrListAjaxJsonCallNew.json?jbc_cd=&udggeopjong_gbcd=&callback=MmaBenefitList'
$script:MmaDetailBaseUrl='https://open.mma.go.kr/caisGGGS/mmanrsrSangSeAjaxJsonCall.json'

function Test-MmaBenefitEntryUrl { param([string]$Url) return [string]$Url -ceq $script:MmaEntryUrl }
function New-MmaJsonpDiagnostic { param([string]$Code,[string]$Detail,[string]$EvidenceReference=''); [pscustomobject][ordered]@{Code=$Code;Stage='MMA_JSONP_LINKAGE';EvidenceReference=$EvidenceReference;Detail=$Detail} }
function New-MmaJsonpPlaceholderBound {
    param($Qualified,[bool]$Conflict=$false)
    $status=if($Conflict){'CONFLICT'}else{'AMBIGUOUS'}; $reasons=if($Conflict){@('BUSINESS_BINDING_CONFLICT')}else{@('BUSINESS_BINDING_AMBIGUOUS')}
    return New-BoundBenefitSource -QualifiedSource $Qualified -BusinessBindingStatus $status -BindingEvidence @() -ReasonCodes $reasons
}
function New-MmaJsonpEmptyExtraction { param($Bound,[object[]]$ReasonCodes=@('EXTRACTION_FAILED')); return New-BenefitEvidenceExtractionResult -Source $Bound -Status FAILED -Claims @() -ReasonCodes $ReasonCodes }
function New-MmaJsonpEmptyValidation { param($Extraction); return [pscustomobject][ordered]@{SourceRowNumber=[int]$Extraction.SourceRowNumber;Status='FAILED';Claims=@();ReasonCodes=@($Extraction.ReasonCodes)} }
function New-MmaJsonpSourceRecord {
    param($Candidate,$Document,$Qualified,$Bound,$Extraction,$Validation,$Observation,$LocationResult,[object[]]$Slices=@(),[object[]]$PreparationDiagnostics=@(),$LinkageObservation=$null)
    $reasons=[Collections.Generic.List[string]]::new()
    foreach($source in @($Candidate,$Document,$Qualified,$Bound,$Extraction,$Validation)) { if($null -ne $source -and $source.PSObject.Properties.Name -contains 'ReasonCodes') { foreach($reason in @($source.ReasonCodes)) { if($reason -and $reasons -notcontains $reason){$reasons.Add([string]$reason)} } } }
    return [pscustomobject][ordered]@{SourceRowNumber=$Candidate.SourceRowNumber;Candidate=$Candidate;Document=$Document;Qualified=$Qualified;Bound=$Bound;Extraction=$Extraction;Validation=$Validation;Observation=$Observation;LocationResult=$LocationResult;Slices=@($Slices);PreparationDiagnostics=@($PreparationDiagnostics);LinkageObservation=$LinkageObservation;DiscoveryExecution='NOT_REQUESTED';ReasonCodes=@($reasons)}
}

function Invoke-MmaJsonpBenefitSourceCandidate {
    param([Parameter(Mandatory)]$Candidate,[Parameter(Mandatory)]$Business,[string]$CanonicalPhone='',[Parameter(Mandatory)]$RunContext,[AllowNull()][scriptblock]$RequestInvoker=$null)
    Assert-BenefitSourceCandidate $Candidate; Assert-NormalizedBusiness $Business; Assert-BenefitSourceRunContext $RunContext
    if ([int]$Candidate.SourceRowNumber -ne [int]$Business.SourceRowNumber) { throw 'MMA source and business must preserve one SourceRowNumber' }
    if (-not (Test-MmaBenefitEntryUrl $Candidate.Url)) { throw 'Only the approved MMA entry URL may trigger the JSONP adapter' }
    $diagnostics=@()
    $listCandidate=New-BenefitSourceCandidate -SourceRowNumber $Candidate.SourceRowNumber -Url $script:MmaListUrl -SourceKind PUBLIC_OFFICIAL -SourceLabel 'MMA official benefit list JSONP' -DiscoveryMethod MMA_JSONP_LIST -ObservedAt $Candidate.ObservedAt
    $listDocument=Get-BenefitRunExplicitDocument -Context $RunContext -Candidate $listCandidate -SourceFormat JSONP -RequestInvoker $RequestInvoker
    $listQualified=Get-QualifiedBenefitSource -Candidate $listCandidate -Document $listDocument -Business $Business
    $listObservation=$null; $location=$null
    if ($listDocument.FetchStatus -ne 'COMPLETE' -or $listQualified.OfficialityStatus -ne 'VERIFIED_OFFICIAL') {
        $diagnostics += New-MmaJsonpDiagnostic MMA_LIST_UNUSABLE 'The official MMA list document is unavailable or unqualified'
        $bound=New-MmaJsonpPlaceholderBound $listQualified; $extraction=New-MmaJsonpEmptyExtraction $bound @('EXTRACTION_FAILED'); $validation=New-MmaJsonpEmptyValidation $extraction
        return New-MmaJsonpSourceRecord $Candidate $listDocument $listQualified $bound $extraction $validation $null $null @() $diagnostics $null
    }
    try { $listObservation=Get-BenefitRunMmaJsonpObservation -Context $RunContext -Document $listDocument -Role LIST -ExpectedCallback MmaBenefitList }
    catch { $diagnostics += New-MmaJsonpDiagnostic MMA_LIST_UNUSABLE 'The MMA list parser could not construct an observation'; $bound=New-MmaJsonpPlaceholderBound $listQualified; $extraction=New-MmaJsonpEmptyExtraction $bound; $validation=New-MmaJsonpEmptyValidation $extraction; return New-MmaJsonpSourceRecord $Candidate $listDocument $listQualified $bound $extraction $validation $null $null @() $diagnostics $null }
    $diagnostics += @($listObservation.Diagnostics)
    $location=Find-BenefitBusinessEvidence -Observation $listObservation -Business $Business -CanonicalPhone $CanonicalPhone
    $diagnostics += @($location.Diagnostics)
    if ($location.OperationalStatus -ne 'COMPLETE' -or $location.Status -ne 'LOCATED') {
        $diagnostics += New-MmaJsonpDiagnostic MMA_LIST_UNUSABLE 'MMA list identity did not produce one safe selected business'
        $bound=New-MmaJsonpPlaceholderBound $listQualified; $reason=if($location.Status -eq 'NOT_FOUND'){'SOURCE_NOT_FOUND'}else{'BUSINESS_BINDING_AMBIGUOUS'}; $extraction=New-MmaJsonpEmptyExtraction $bound @($reason); $validation=New-MmaJsonpEmptyValidation $extraction
        return New-MmaJsonpSourceRecord $Candidate $listDocument $listQualified $bound $extraction $validation $listObservation $location @() $diagnostics $listObservation
    }
    $listSlice=$location.Slices[0]; $institutionCode=[string]$listSlice.StructuredFields.InstitutionCode
    if ([string]::IsNullOrWhiteSpace($institutionCode) -or $institutionCode -cnotmatch '^\d+$') {
        $diagnostics += New-MmaJsonpDiagnostic MMA_INSTITUTION_CODE_MISSING 'Selected MMA list record has no valid institution code' $listSlice.EvidenceReference
        $bound=New-MmaJsonpPlaceholderBound $listQualified; $extraction=New-MmaJsonpEmptyExtraction $bound; $validation=New-MmaJsonpEmptyValidation $extraction
        return New-MmaJsonpSourceRecord $Candidate $listDocument $listQualified $bound $extraction $validation $listObservation $location @() $diagnostics $listObservation
    }
    $detailUrl=$script:MmaDetailBaseUrl + '?udgigwan_cd=' + [Uri]::EscapeDataString($institutionCode) + '&callback=MmaBenefitDetail'
    $detailCandidate=New-BenefitSourceCandidate -SourceRowNumber $Candidate.SourceRowNumber -Url $detailUrl -SourceKind PUBLIC_OFFICIAL -SourceLabel 'MMA official benefit detail JSONP' -DiscoveryMethod MMA_JSONP_DETAIL -ObservedAt $Candidate.ObservedAt
    $detailDocument=Get-BenefitRunExplicitDocument -Context $RunContext -Candidate $detailCandidate -SourceFormat JSONP -RequestInvoker $RequestInvoker
    $detailQualified=Get-QualifiedBenefitSource -Candidate $detailCandidate -Document $detailDocument -Business $Business
    if ($detailDocument.FetchStatus -ne 'COMPLETE' -or $detailQualified.OfficialityStatus -ne 'VERIFIED_OFFICIAL') {
        $diagnostics += New-MmaJsonpDiagnostic MMA_DETAIL_UNAVAILABLE 'The selected MMA detail document is unavailable or unqualified'
        $bound=New-MmaJsonpPlaceholderBound $detailQualified; $extraction=New-MmaJsonpEmptyExtraction $bound; $validation=New-MmaJsonpEmptyValidation $extraction
        return New-MmaJsonpSourceRecord $Candidate $detailDocument $detailQualified $bound $extraction $validation $null $location @() $diagnostics $listObservation
    }
    $detailObservation=Get-BenefitRunMmaJsonpObservation -Context $RunContext -Document $detailDocument -Role DETAIL -ExpectedCallback MmaBenefitDetail
    $diagnostics += @($detailObservation.Diagnostics)
    if ($detailObservation.AdapterStatus -ne 'COMPLETE' -or @($detailObservation.ContentUnits).Count -ne 1) {
        $diagnostics += New-MmaJsonpDiagnostic MMA_DETAIL_UNAVAILABLE 'The selected MMA detail payload is unusable'
        $bound=New-MmaJsonpPlaceholderBound $detailQualified; $extraction=New-MmaJsonpEmptyExtraction $bound; $validation=New-MmaJsonpEmptyValidation $extraction
        return New-MmaJsonpSourceRecord $Candidate $detailDocument $detailQualified $bound $extraction $validation $detailObservation $location @() $diagnostics $listObservation
    }
    $detailUnit=$detailObservation.ContentUnits[0]
    if ([string]$detailUnit.StructuredFields.InstitutionCode -cne $institutionCode) {
        $diagnostics += New-MmaJsonpDiagnostic MMA_INSTITUTION_CODE_MISMATCH 'MMA detail institution code differs from the safely selected list code' $detailUnit.UnitReference
        $bound=New-MmaJsonpPlaceholderBound $detailQualified -Conflict:$true; $extraction=New-MmaJsonpEmptyExtraction $bound; $validation=New-MmaJsonpEmptyValidation $extraction
        return New-MmaJsonpSourceRecord $Candidate $detailDocument $detailQualified $bound $extraction $validation $detailObservation $location @() $diagnostics $listObservation
    }
    $detailSlice=New-RelevantBenefitEvidenceSlice -Observation $detailObservation -Unit $detailUnit -IdentityEvidence @('MMA_LIST_LINKAGE')
    $bound=Get-BenefitBusinessBinding -Source $detailQualified -Business $Business -CanonicalPhone $CanonicalPhone -EvidenceSlice $detailSlice
    if ($bound.BusinessBindingStatus -ne 'STRONG') { $extraction=New-MmaJsonpEmptyExtraction $bound; $validation=New-MmaJsonpEmptyValidation $extraction }
    else { $extraction=Invoke-BenefitEvidenceExtraction -Source $bound -Document $detailDocument -EvidenceSlice $detailSlice; $validation=ConvertTo-ValidatedBenefitEvidence -Extraction $extraction -Document $detailDocument -EvidenceSlice $detailSlice }
    return New-MmaJsonpSourceRecord $Candidate $detailDocument $detailQualified $bound $extraction $validation $detailObservation $location @($detailSlice) $diagnostics $listObservation
}

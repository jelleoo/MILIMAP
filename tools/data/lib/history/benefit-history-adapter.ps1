Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$historyRoot = $PSScriptRoot
$dataLibRoot = Split-Path -Parent $historyRoot

. (Join-Path $dataLibRoot 'benefit-verification-contracts.ps1')
. (Join-Path $dataLibRoot 'benefit-verification/compare-benefit-claims.ps1')
. (Join-Path $historyRoot 'history-contracts.ps1')
. (Join-Path $historyRoot 'history-fingerprints.ps1')
. (Join-Path $historyRoot 'history-store.ps1')
. (Join-Path $historyRoot 'compare-history-observations.ps1')

$script:BenefitHistoryAdapterVersion = 1
$script:BenefitHistoryMaterialReasonCodes = @(
    'MATERIAL_CHANGE',
    'EXPLICIT_VALIDITY_END',
    'EXPLICIT_DISCONTINUATION',
    'SOURCE_CONFLICT',
    'CURRENTNESS_INSUFFICIENT',
    'DETAIL_INCOMPLETE',
    'BUSINESS_BINDING_CONFLICT',
    'BUSINESS_BINDING_AMBIGUOUS',
    'SOURCE_OFFICIALITY_UNRESOLVED'
)

function Get-BenefitHistoryProperty {
    param([AllowNull()]$Object,[Parameter(Mandatory)][string]$Name,[AllowNull()]$Default='')
    if($null -eq $Object -or $Object.PSObject.Properties.Name -notcontains $Name){ return $Default }
    return $Object.$Name
}

function Get-BenefitHistorySemanticValue {
    param([Parameter(Mandatory)]$Claim)

    Assert-BenefitClaimVerification $Claim
    if([string]$Claim.ClaimType -in @('BENEFIT_EXISTENCE','CURRENT_APPLICABILITY') -and [string]$Claim.Result -in @('CONFIRMED','ENDED')){
        return [string]$Claim.Result
    }

    $text=ConvertTo-BenefitComparisonText ([string]$Claim.EvidenceValue)
    switch([string]$Claim.ClaimType){
        'BENEFIT_DESCRIPTION' {
            return (($text -replace '^(이용\s*금액|결제\s*금액의?)\s*','').Trim())
        }
        'VALID_FROM' {
            $date=Get-BenefitComparisonDateToken $text
            return $(if($date){$date}else{$text})
        }
        'VALID_UNTIL' {
            $date=Get-BenefitComparisonDateToken $text
            return $(if($date){$date}else{$text})
        }
        'VERIFICATION_METHOD' {
            if($text -match '군인\s*신분증'){ return 'MILITARY_ID' }
            if($text -match '나라사랑카드'){ return 'NARASARANG_CARD' }
            return $text
        }
        default { return $text }
    }
}

function ConvertTo-BenefitHistoryInputProjection {
    param(
        [Parameter(Mandatory)][string]$BusinessId,
        [Parameter(Mandatory)]$Benefit,
        [Parameter(Mandatory)]$BusinessIdentity,
        [string]$CanonicalPhone=''
    )

    Assert-HistoryBusinessId -Value $BusinessId
    Assert-CanonicalBenefitRecord $Benefit
    Assert-NormalizedBusiness $BusinessIdentity
    if([int]$Benefit.SourceRowNumber -ne [int]$BusinessIdentity.SourceRowNumber){ throw 'Benefit and BusinessIdentity SourceRowNumber must match' }

    return [pscustomobject][ordered]@{
        ProjectionType='BenefitHistoryInput'
        ProjectionVersion=1
        BusinessId=$BusinessId
        BusinessIdentity=[pscustomobject][ordered]@{
            OriginalName=[string]$BusinessIdentity.OriginalName
            NormalizedName=[string]$BusinessIdentity.NormalizedName
            BaseName=[string]$BusinessIdentity.BaseName
            BranchName=[string]$BusinessIdentity.BranchName
            OriginalRoadAddress=[string]$BusinessIdentity.OriginalRoadAddress
            OriginalLotAddress=[string]$BusinessIdentity.OriginalLotAddress
            PreferredAddress=[string]$BusinessIdentity.PreferredAddress
            Province=[string]$BusinessIdentity.Province
            City=[string]$BusinessIdentity.City
            District=[string]$BusinessIdentity.District
            Dong=[string]$BusinessIdentity.Dong
            RoadName=[string]$BusinessIdentity.RoadName
            BuildingMain=[string]$BusinessIdentity.BuildingMain
            BuildingSub=[string]$BusinessIdentity.BuildingSub
            Floor=[string]$BusinessIdentity.Floor
            Unit=[string]$BusinessIdentity.Unit
            AddressParseStatus=[string]$BusinessIdentity.AddressParseStatus
            Phone=ConvertTo-BenefitComparisonText $CanonicalPhone
        }
        Benefit=[pscustomobject][ordered]@{
            BenefitDescription=ConvertTo-BenefitComparisonText ([string]$Benefit.BenefitDescription)
            EligibleTarget=ConvertTo-BenefitComparisonText ([string]$Benefit.EligibleTarget)
            UsageCondition=ConvertTo-BenefitComparisonText ([string]$Benefit.UsageCondition)
            VerificationMethod=ConvertTo-BenefitComparisonText ([string]$Benefit.VerificationMethod)
            ExistingSourceType=ConvertTo-BenefitComparisonText ([string]$Benefit.ExistingSourceType)
            ExistingSourceUrl=[string]$Benefit.ExistingSourceUrl
        }
    }
}

function ConvertTo-BenefitHistoryEvidenceProjection {
    param([AllowNull()][object[]]$EvidenceDiagnostics=@())

    $sources=[Collections.Generic.List[object]]::new()
    foreach($diagnostic in @($EvidenceDiagnostics | Where-Object { $null -ne $_ })){
        $candidateReferences=@(Get-BenefitHistoryProperty -Object $diagnostic -Name 'CandidateReferences' -Default @())
        $sources.Add([pscustomobject][ordered]@{
            SourceUrl=[string](Get-BenefitHistoryProperty -Object $diagnostic -Name 'Url')
            SourceFormat=[string](Get-BenefitHistoryProperty -Object $diagnostic -Name 'SourceFormat')
            ContentHash=[string](Get-BenefitHistoryProperty -Object $diagnostic -Name 'ContentHash')
            AdapterId=[string](Get-BenefitHistoryProperty -Object $diagnostic -Name 'AdapterId')
            AdapterVersion=[string](Get-BenefitHistoryProperty -Object $diagnostic -Name 'AdapterVersion')
            LocationOperationalStatus=[string](Get-BenefitHistoryProperty -Object $diagnostic -Name 'LocationOperationalStatus')
            LocationStatus=[string](Get-BenefitHistoryProperty -Object $diagnostic -Name 'LocationStatus')
            CandidateReferences=@($candidateReferences | ForEach-Object { [string]$_ })
        })
    }

    return [pscustomobject][ordered]@{
        ProjectionType='BenefitHistoryEvidence'
        ProjectionVersion=1
        Sources=@($sources)
    }
}

function Test-BenefitHistoryAbsenceEligible {
    param([AllowNull()][object[]]$EvidenceDiagnostics=@())

    $diagnostics=@($EvidenceDiagnostics | Where-Object { $null -ne $_ })
    if($diagnostics.Count -eq 0){ return $false }

    foreach($diagnostic in $diagnostics){
        if([string](Get-BenefitHistoryProperty $diagnostic 'FetchStatus') -cne 'COMPLETE'){ return $false }
        if([string](Get-BenefitHistoryProperty $diagnostic 'OfficialityStatus') -cne 'VERIFIED_OFFICIAL'){ return $false }
        if([string](Get-BenefitHistoryProperty $diagnostic 'AdapterStatus') -cne 'COMPLETE'){ return $false }
        if([string](Get-BenefitHistoryProperty $diagnostic 'LocationOperationalStatus') -cne 'COMPLETE'){ return $false }
        if([string](Get-BenefitHistoryProperty $diagnostic 'LocationStatus') -cne 'NOT_FOUND'){ return $false }
    }
    return $true
}

function Get-BenefitHistoryBusinessPresence {
    param([AllowNull()][object[]]$EvidenceDiagnostics=@())

    if(Test-BenefitHistoryAbsenceEligible -EvidenceDiagnostics $EvidenceDiagnostics){ return 'ABSENT' }

    foreach($diagnostic in @($EvidenceDiagnostics | Where-Object { $null -ne $_ })){
        if([string](Get-BenefitHistoryProperty $diagnostic 'FetchStatus') -cne 'COMPLETE'){ continue }
        if([string](Get-BenefitHistoryProperty $diagnostic 'OfficialityStatus') -cne 'VERIFIED_OFFICIAL'){ continue }
        if([string](Get-BenefitHistoryProperty $diagnostic 'AdapterStatus') -cne 'COMPLETE'){ continue }
        if([string](Get-BenefitHistoryProperty $diagnostic 'LocationOperationalStatus') -cne 'COMPLETE'){ continue }
        if([string](Get-BenefitHistoryProperty $diagnostic 'LocationStatus') -cne 'LOCATED'){ continue }
        if([string](Get-BenefitHistoryProperty $diagnostic 'BusinessBindingStatus') -cne 'STRONG'){ continue }
        return 'PRESENT'
    }
    return 'UNKNOWN'
}

function ConvertTo-BenefitHistorySemanticProjection {
    param(
        [Parameter(Mandatory)]$Result,
        [AllowNull()][object[]]$EvidenceDiagnostics=@()
    )

    Assert-BenefitVerificationResult $Result
    $claims=[Collections.Generic.List[object]]::new()
    foreach($claim in @($Result.ClaimResults)){
        Assert-BenefitClaimVerification $claim
        $validationStatus=''
        if($null -ne $claim.ValidatedClaim){ $validationStatus=[string]$claim.ValidatedClaim.ValidationStatus }
        $materialReasons=@($claim.ReasonCodes | Where-Object { $script:BenefitHistoryMaterialReasonCodes -contains [string]$_ } | Sort-Object -CaseSensitive -Unique)
        $claims.Add([pscustomobject][ordered]@{
            ClaimType=[string]$claim.ClaimType
            SemanticValue=Get-BenefitHistorySemanticValue -Claim $claim
            ClaimResult=[string]$claim.Result
            ValidationStatus=$validationStatus
            MaterialReasonCodes=@($materialReasons)
        })
    }

    $resultReasons=@($Result.ReasonCodes | Where-Object { $script:BenefitHistoryMaterialReasonCodes -contains [string]$_ } | Sort-Object -CaseSensitive -Unique)
    return [pscustomobject][ordered]@{
        ProjectionType='BenefitHistorySemantic'
        ProjectionVersion=1
        BenefitState=[string]$Result.BenefitState
        ReviewClass=[string]$Result.ReviewClass
        BusinessPresence=Get-BenefitHistoryBusinessPresence -EvidenceDiagnostics $EvidenceDiagnostics
        AbsenceEligible=[bool](Test-BenefitHistoryAbsenceEligible -EvidenceDiagnostics $EvidenceDiagnostics)
        Claims=@($claims)
        MaterialReasonCodes=@($resultReasons)
    }
}

function ConvertTo-BenefitHistoryExecutionProjection {
    param(
        [Parameter(Mandatory)][string]$RepositoryRevision,
        [AllowNull()]$ExecutionConfiguration=$null
    )

    if($RepositoryRevision -cnotmatch '^[0-9a-f]{40}$'){ throw 'RepositoryRevision must be a lowercase 40-character commit SHA' }
    $benefitContract=(Get-BenefitVerificationContractDefinition).ContractVersion
    return [pscustomobject][ordered]@{
        ProjectionType='BenefitHistoryExecution'
        ProjectionVersion=1
        RepositoryRevision=$RepositoryRevision
        BenefitHistoryAdapterVersion=$script:BenefitHistoryAdapterVersion
        BenefitContractVersion=[int]$benefitContract
        HistoryContractVersion=[int]$script:HistoryContractVersion
        FingerprintSchemaVersion=[int]$script:FingerprintSchemaVersion
        ComparatorVersion=[int]$script:ComparatorVersion
        Configuration=$ExecutionConfiguration
    }
}

function Get-BenefitHistoryOperationalAssessment {
    param(
        [Parameter(Mandatory)]$OperationalStatus,
        [AllowNull()][object[]]$EvidenceDiagnostics=@()
    )

    $reasons=[Collections.Generic.List[string]]::new()
    $diagnostics=@($EvidenceDiagnostics | Where-Object { $null -ne $_ })
    $discovery=[string](Get-BenefitHistoryProperty -Object $OperationalStatus -Name 'DiscoveryStatus')
    $extraction=[string](Get-BenefitHistoryProperty -Object $OperationalStatus -Name 'ExtractionStatus')
    $absenceEligible=Test-BenefitHistoryAbsenceEligible -EvidenceDiagnostics $diagnostics

    if($discovery -cne 'COMPLETE'){ $reasons.Add('DISCOVERY_NOT_COMPLETE') }
    if($diagnostics.Count -eq 0){ $reasons.Add('SOURCE_EVIDENCE_MISSING') }

    foreach($diagnostic in $diagnostics){
        if([string](Get-BenefitHistoryProperty $diagnostic 'FetchStatus') -cne 'COMPLETE'){
            if($reasons -notcontains 'SOURCE_FETCH_NOT_COMPLETE'){ $reasons.Add('SOURCE_FETCH_NOT_COMPLETE') }
        }
        $hash=[string](Get-BenefitHistoryProperty $diagnostic 'ContentHash')
        if($hash -cnotmatch '^[0-9a-f]{64}$'){
            if($reasons -notcontains 'SOURCE_CONTENT_HASH_MISSING'){ $reasons.Add('SOURCE_CONTENT_HASH_MISSING') }
        }
        $locationOperational=[string](Get-BenefitHistoryProperty $diagnostic 'LocationOperationalStatus')
        if(-not [string]::IsNullOrWhiteSpace($locationOperational) -and $locationOperational -cne 'COMPLETE'){
            if($reasons -notcontains 'SOURCE_LOCATION_NOT_COMPLETE'){ $reasons.Add('SOURCE_LOCATION_NOT_COMPLETE') }
        }
    }

    if(-not $absenceEligible -and $extraction -cne 'COMPLETE'){ $reasons.Add('EXTRACTION_NOT_COMPLETE') }

    $pipelineStatus='COMPLETE'
    if($discovery -eq 'FAILED' -or (-not $absenceEligible -and $extraction -eq 'FAILED')){
        $pipelineStatus='FAILED'
    } elseif($discovery -ne 'COMPLETE' -or (-not $absenceEligible -and $extraction -ne 'COMPLETE')){
        $pipelineStatus='PARTIAL'
    }

    $comparable=($pipelineStatus -ceq 'COMPLETE' -and $reasons.Count -eq 0)
    return [pscustomobject][ordered]@{
        OperationalStatus=$pipelineStatus
        Comparable=$comparable
        NonComparableReasons=@($reasons | Sort-Object -CaseSensitive -Unique)
        AbsenceEligible=$absenceEligible
    }
}

function New-BenefitHistoryProjectionArtifact {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)]$Projection
    )

    $json=ConvertTo-HistoryCanonicalJson -Value $Projection
    $hash=Get-HistorySha256 -Text $json
    $path=Get-HistoryArtifactPath -Store $Store -ContentHash $hash -Extension 'json'
    $relative=Get-HistoryRelativePath -Store $Store -FullPath $path
    $reference=New-HistoryArtifactReference -Kind $Kind -ContentHash $hash -RelativePath $relative
    return [pscustomobject][ordered]@{
        Reference=$reference
        PreparedArtifact=[pscustomobject][ordered]@{
            ContentHash=$hash
            Extension='json'
            Kind=$Kind
            Text=$json
        }
    }
}

function New-BenefitHistoryObservationPackage {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$BusinessId,
        [Parameter(Mandatory)][string]$ObservedAt,
        [Parameter(Mandatory)][string]$RepositoryRevision,
        [Parameter(Mandatory)]$Benefit,
        [Parameter(Mandatory)]$BusinessIdentity,
        [string]$CanonicalPhone='',
        [Parameter(Mandatory)]$Result,
        [AllowNull()][object[]]$EvidenceDiagnostics=@(),
        [Parameter(Mandatory)]$OperationalStatus,
        [AllowNull()]$ExecutionConfiguration=$null
    )

    Assert-HistoryToken -Value $RunId -Name 'run id'
    Assert-HistoryBusinessId -Value $BusinessId
    Assert-HistoryTimestamp -Value $ObservedAt -Name 'ObservedAt'
    Assert-BenefitVerificationResult $Result
    if([int]$Result.SourceRowNumber -ne [int]$Benefit.SourceRowNumber -or [int]$Result.SourceRowNumber -ne [int]$BusinessIdentity.SourceRowNumber){
        throw 'Benefit history adapter inputs must preserve one SourceRowNumber'
    }

    $input=ConvertTo-BenefitHistoryInputProjection -BusinessId $BusinessId -Benefit $Benefit -BusinessIdentity $BusinessIdentity -CanonicalPhone $CanonicalPhone
    $evidence=ConvertTo-BenefitHistoryEvidenceProjection -EvidenceDiagnostics $EvidenceDiagnostics
    $semantic=ConvertTo-BenefitHistorySemanticProjection -Result $Result -EvidenceDiagnostics $EvidenceDiagnostics
    $execution=ConvertTo-BenefitHistoryExecutionProjection -RepositoryRevision $RepositoryRevision -ExecutionConfiguration $ExecutionConfiguration

    $fingerprints=New-HistoryFingerprintSet -InputProjection $input -EvidenceProjection $evidence -SemanticProjection $semantic -ExecutionProjection $execution -SchemaVersion $script:FingerprintSchemaVersion -EvidenceOrderInsensitivePaths @('Sources','Sources[].CandidateReferences') -SemanticOrderInsensitivePaths @('Claims','Claims[].MaterialReasonCodes','MaterialReasonCodes')
    $assessment=Get-BenefitHistoryOperationalAssessment -OperationalStatus $OperationalStatus -EvidenceDiagnostics $EvidenceDiagnostics

    $evidenceArtifact=New-BenefitHistoryProjectionArtifact -Store $Store -Kind 'BENEFIT_EVIDENCE_PROJECTION' -Projection $evidence
    $semanticArtifact=New-BenefitHistoryProjectionArtifact -Store $Store -Kind 'BENEFIT_SEMANTIC_PROJECTION' -Projection $semantic

    $identityMaterial=$RunId + '|' + $BusinessId + '|BENEFIT|' + $fingerprints.InputFingerprint + '|' + $fingerprints.EvidenceFingerprint + '|' + $fingerprints.SemanticFingerprint + '|' + $fingerprints.ExecutionFingerprint
    $observationId='obs-' + (Get-HistorySha256 -Text $identityMaterial).Substring(0,32)

    $observation=New-HistoryObservation -ObservationId $observationId -RunId $RunId -BusinessId $BusinessId -Domain 'BENEFIT' -ObservedAt $ObservedAt -OperationalStatus $assessment.OperationalStatus -Comparable ([bool]$assessment.Comparable) -InputFingerprint $fingerprints.InputFingerprint -EvidenceFingerprint $fingerprints.EvidenceFingerprint -SemanticFingerprint $fingerprints.SemanticFingerprint -ExecutionFingerprint $fingerprints.ExecutionFingerprint -ArtifactReferences @($evidenceArtifact.Reference,$semanticArtifact.Reference) -SemanticResultReference ([string]$semanticArtifact.Reference.RelativePath) -NonComparableReasons @($assessment.NonComparableReasons)

    return [pscustomobject][ordered]@{
        Observation=$observation
        PreparedArtifacts=@($evidenceArtifact.PreparedArtifact,$semanticArtifact.PreparedArtifact)
        InputProjection=$input
        EvidenceProjection=$evidence
        SemanticProjection=$semantic
        ExecutionProjection=$execution
    }
}


function Read-BenefitHistorySemanticProjection {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)]$Observation
    )

    Assert-HistoryObservation $Observation
    if([string]$Observation.Domain -cne 'BENEFIT'){ throw 'Benefit semantic projection requires BENEFIT observation' }

    $references=@($Observation.ArtifactReferences | Where-Object { [string]$_.Kind -ceq 'BENEFIT_SEMANTIC_PROJECTION' })
    if($references.Count -ne 1){ throw 'Benefit observation requires exactly one semantic projection artifact' }
    $reference=$references[0]
    if([string]$Observation.SemanticResultReference -cne [string]$reference.RelativePath){
        throw 'Benefit semantic result reference does not match semantic artifact'
    }

    Assert-HistoryArtifactReferenceExists -Store $Store -Reference $reference
    $path=Assert-HistoryStorePathWithinRoot -Store $Store -Path (Join-Path $Store.Root ([string]$reference.RelativePath))
    $projection=Read-HistoryJsonFile -Store $Store -Path $path -Kind 'benefit semantic projection'
    if($null -eq $projection){ throw 'Benefit semantic projection artifact is missing' }
    if([string]$projection.ProjectionType -cne 'BenefitHistorySemantic' -or [int]$projection.ProjectionVersion -ne 1){
        throw 'Unsupported benefit semantic projection'
    }

    $fingerprint=Get-HistoryFingerprint -Projection $projection -SchemaVersion $script:FingerprintSchemaVersion -OrderInsensitivePaths @('Claims','Claims[].MaterialReasonCodes','MaterialReasonCodes')
    if($fingerprint -cne [string]$Observation.SemanticFingerprint){
        throw 'Benefit semantic projection fingerprint mismatch'
    }
    return $projection
}

function Get-BenefitHistoryComparableClaimsByType {
    param([Parameter(Mandatory)]$Projection)

    $result=@{}
    foreach($claim in @($Projection.Claims)){
        if([string]$claim.ValidationStatus -cne 'VALIDATED'){ continue }
        $type=[string]$claim.ClaimType
        if([string]::IsNullOrWhiteSpace($type)){ continue }
        if(-not $result.ContainsKey($type)){ $result[$type]=[Collections.Generic.List[object]]::new() }
        $result[$type].Add($claim)
    }
    return $result
}

function Test-BenefitHistoryMaterialClaimDelta {
    param(
        [Parameter(Mandatory)]$PreviousProjection,
        [Parameter(Mandatory)]$CurrentProjection
    )

    $previousByType=Get-BenefitHistoryComparableClaimsByType -Projection $PreviousProjection
    $currentByType=Get-BenefitHistoryComparableClaimsByType -Projection $CurrentProjection
    foreach($claimType in @($previousByType.Keys | Where-Object { $currentByType.ContainsKey($_) } | Sort-Object -CaseSensitive)){
        $previousClaims=@($previousByType[$claimType])
        $currentClaims=@($currentByType[$claimType])
        if($previousClaims.Count -ne 1 -or $currentClaims.Count -ne 1){ continue }

        $previous=$previousClaims[0]
        $current=$currentClaims[0]
        if($claimType -in @('BENEFIT_EXISTENCE','CURRENT_APPLICABILITY')){
            $previousResult=[string]$previous.ClaimResult
            $currentResult=[string]$current.ClaimResult
            if($previousResult -in @('CONFIRMED','ENDED') -and $currentResult -in @('CONFIRMED','ENDED') -and $previousResult -cne $currentResult){
                return $true
            }
            continue
        }

        $comparison=Compare-BenefitClaim -ClaimType $claimType -CanonicalValue ([string]$previous.SemanticValue) -EvidenceValue ([string]$current.SemanticValue)
        if([string]$comparison.Result -ceq 'CHANGED'){ return $true }
    }
    return $false
}

function Resolve-BenefitHistoryDomainChange {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)]$Previous,
        [Parameter(Mandatory)]$Current
    )

    $previousProjection=Read-BenefitHistorySemanticProjection -Store $Store -Observation $Previous
    $currentProjection=Read-BenefitHistorySemanticProjection -Store $Store -Observation $Current

    $previousPresence=[string]$previousProjection.BusinessPresence
    $currentAbsent=[bool]$currentProjection.AbsenceEligible
    if($currentAbsent -and $previousPresence -ceq 'PRESENT'){
        return [pscustomobject][ordered]@{
            ChangeCandidates=@('BENEFIT_ABSENCE_SUSPECTED')
            ReasonCodes=@('COMPLETE_BUSINESS_NOT_FOUND')
        }
    }

    if(Test-BenefitHistoryMaterialClaimDelta -PreviousProjection $previousProjection -CurrentProjection $currentProjection){
        return [pscustomobject][ordered]@{
            ChangeCandidates=@('BENEFIT_CHANGE_SUSPECTED')
            ReasonCodes=@('MATERIAL_BENEFIT_SEMANTIC_DELTA')
        }
    }

    return [pscustomobject][ordered]@{
        ChangeCandidates=@()
        ReasonCodes=@('BENEFIT_SEMANTIC_DELTA_NOT_MATERIAL')
    }
}

function Compare-BenefitHistoryObservations {
    param(
        [Parameter(Mandatory)]$Store,
        [AllowNull()]$Previous,
        [Parameter(Mandatory)]$Current
    )

    Assert-HistoryObservation $Current
    if([string]$Current.Domain -cne 'BENEFIT'){ throw 'Benefit history comparison requires BENEFIT current observation' }
    if($null -ne $Previous){
        Assert-HistoryObservation $Previous
        if([string]$Previous.Domain -cne 'BENEFIT'){ throw 'Benefit history comparison requires BENEFIT previous observation' }
    }

    $gateResolver={
        param($PreviousObservation,$CurrentObservation)
        [pscustomobject][ordered]@{
            ChangeCandidates=@('BENEFIT_DOMAIN_RESOLUTION_REQUIRED')
            ReasonCodes=@('BENEFIT_DOMAIN_RESOLUTION_REQUIRED')
        }
    }
    $gate=Compare-HistoryObservations -Previous $Previous -Current $Current -DomainChangeResolver $gateResolver
    if(@($gate.ChangeCandidates) -notcontains 'BENEFIT_DOMAIN_RESOLUTION_REQUIRED'){
        return $gate
    }

    $resolved=Resolve-BenefitHistoryDomainChange -Store $Store -Previous $Previous -Current $Current
    $gate.ChangeCandidates=@($resolved.ChangeCandidates | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $gate.ReasonCodes=@($resolved.ReasonCodes | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    Assert-ObservationComparison $gate
    return $gate
}

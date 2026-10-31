# Inactive C-Lite contracts. Loading defines validators only; no store, network or writer is opened.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'benefit-history-adapter.ps1')
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'benefit-evidence/validate-benefit-evidence.ps1')
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'benefit-evidence/find-business-evidence-slice.ps1')

function Assert-InternalScopedObject($Value,[string[]]$Properties){
    if($Value -isnot [pscustomobject]){throw 'C_LITE_OBJECT_TYPE'}
    $actual=@($Value.PSObject.Properties)
    if($actual.Count -ne $Properties.Count){throw 'C_LITE_PROPERTY_SET'}
    foreach($p in $actual){if($p.MemberType -ne 'NoteProperty' -or $p.Name -cnotin $Properties){throw 'C_LITE_PROPERTY_SET'}}
}
function Assert-InternalScopedString($Value,[int]$MaxBytes,[string]$Pattern='',[switch]$Empty){
    if($Value -isnot [string] -or [Text.Encoding]::UTF8.GetByteCount($Value) -gt $MaxBytes -or
       (-not $Empty -and [string]::IsNullOrWhiteSpace($Value)) -or ($Pattern -and $Value -cnotmatch $Pattern)){throw 'C_LITE_STRING'}
}
function Assert-InternalScopedInteger($Value,[long]$Min=0,[long]$Max=[int]::MaxValue){
    if(($Value -isnot [int] -and $Value -isnot [long]) -or $Value -lt $Min -or $Value -gt $Max){throw 'C_LITE_INTEGER'}
}
function Assert-InternalScopedCode($Value,[string[]]$Allowed,[switch]$Nullable){
    if($Nullable -and $null -eq $Value){return}
    Assert-InternalScopedString $Value 64
    if($Value -cnotin $Allowed){throw 'C_LITE_CODE'}
}
function Assert-InternalScopedArray($Value,[int]$Max){
    if($Value -isnot [array] -or $Value.Rank -ne 1 -or $Value.Count -gt $Max){throw 'C_LITE_ARRAY'}
}
function Assert-InternalScopedTimestamp($Value){
    Assert-InternalScopedString $Value 64
    Assert-ScopeTimestamp $Value
}
function Assert-InternalScopedJsonNode($Node){
    switch($Node.ValueKind.ToString()){
        'Object' {
            $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach($property in $Node.EnumerateObject()){
                if(-not $seen.Add($property.Name)){throw 'C_LITE_DUPLICATE_JSON_PROPERTY'}
                Assert-InternalScopedJsonNode $property.Value
            }
        }
        'Array' {foreach($child in $Node.EnumerateArray()){Assert-InternalScopedJsonNode $child}}
    }
}
function ConvertFrom-BenefitScopedEvidenceJson {
    param([Parameter(Mandatory)]$Json,[int]$MaxBytes=65536)
    Assert-InternalScopedString $Json $MaxBytes
    $document=[System.Text.Json.JsonDocument]::Parse([string]$Json)
    try{Assert-InternalScopedJsonNode $document.RootElement}finally{$document.Dispose()}
    # DateKind String preserves source timestamp identity, including offset and fractional digits.
    return ConvertFrom-Json -InputObject $Json -Depth 64 -DateKind String -NoEnumerate
}
function Get-BenefitRetentionProfileCandidate {
    param([Parameter(Mandatory)]$ExecutionFingerprint,[Parameter(Mandatory)]$RepositoryRevision)
    Assert-InternalScopedString $ExecutionFingerprint 64 '^[0-9a-f]{64}$'
    Assert-InternalScopedString $RepositoryRevision 40 '^[0-9a-f]{40}$'
    $matches=@(foreach($profile in @('LEGACY','C_LITE_V1')){
        # Frozen v1 descriptors: never reconstruct old fingerprints from mutable version globals.
        $configuration=if($profile -ceq 'LEGACY'){$null}else{[pscustomobject]@{HtmlEvidenceRetentionProfile='C_LITE_V1'}}
        $projection=[pscustomobject][ordered]@{
            ProjectionType='BenefitHistoryExecution';ProjectionVersion=1;RepositoryRevision=$RepositoryRevision
            BenefitHistoryAdapterVersion=1;BenefitContractVersion=1;HistoryContractVersion=1
            FingerprintSchemaVersion=1;ComparatorVersion=1;Configuration=$configuration
        }
        if((Get-HistoryFingerprint -Projection $projection -SchemaVersion 1) -ceq $ExecutionFingerprint){$profile}
    })
    if($matches.Count -eq 1){return $matches[0]}
    return 'PROFILE_UNKNOWN'
}

function Assert-InternalScopedReference($Value,[string]$Kind){
    Assert-InternalScopedObject $Value @('ContractType','ContractVersion','Kind','ContentHash','RelativePath')
    Assert-InternalScopedCode $Value.ContractType @('HistoryArtifactReference')
    Assert-InternalScopedInteger $Value.ContractVersion 1 1
    Assert-InternalScopedCode $Value.Kind @($Kind)
    Assert-InternalScopedString $Value.ContentHash 64 '^[0-9a-f]{64}$'
    Assert-InternalScopedString $Value.RelativePath 128
    if($Value.RelativePath -cne ('artifacts/sha256/'+$Value.ContentHash+'.json')){throw 'C_LITE_ARTIFACT_PATH'}
}
function Assert-InternalScopedSpan($Start,$Length,$ParentStart,$ParentLength){
    Assert-InternalScopedInteger $Start
    Assert-InternalScopedInteger $Length 1
    if($Start -lt $ParentStart -or $Start -gt ($ParentStart+$ParentLength) -or $Length -gt (($ParentStart+$ParentLength)-$Start)){throw 'C_LITE_SPAN'}
}
function Get-InternalScopedClaimFields {
    return @{BENEFIT_DESCRIPTION='BenefitDescription';ELIGIBLE_TARGET='EligibleTarget';USAGE_CONDITION='UsageCondition';VERIFICATION_METHOD='VerificationMethod';VALID_FROM='ValidFrom';VALID_UNTIL='ValidUntilObserved'}
}
function Get-InternalScopedRetainedKeys($IdentityCodes,$Claims){
    $keys=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    [void]$keys.Add('BusinessName')
    $identityMap=@{NAME_MATCH='BusinessName';FULL_NAME_MATCH='BusinessName';FULL_ADDRESS_MATCH='Address';BRANCH_MATCH='Branch';PHONE_MATCH='Phone'}
    foreach($code in $IdentityCodes){if(-not $identityMap.ContainsKey($code)){throw 'C_LITE_IDENTITY_CODE'};[void]$keys.Add($identityMap[$code])}
    $claimMap=Get-InternalScopedClaimFields
    foreach($claim in $Claims){if(-not $claimMap.ContainsKey($claim.ClaimType)){throw 'C_LITE_CLAIM_LINK'};[void]$keys.Add($claimMap[$claim.ClaimType])}
    return @($keys)
}
function Test-InternalScopedCompletePositive($Outcome){
    foreach($key in @('ObservationOperationalStatus','FetchStatus','AdapterStatus','LocationOperationalStatus','ExtractionStatus','ValidationStatus')){if($Outcome.$key -cne 'COMPLETE'){return $false}}
    return ($Outcome.Comparable -and $Outcome.OfficialityStatus -ceq 'VERIFIED_OFFICIAL' -and $Outcome.LocationStatus -ceq 'LOCATED' -and $Outcome.BindingStatus -ceq 'STRONG')
}
function Assert-BenefitScopedEvidence {
    param([Parameter(Mandatory)]$Evidence)
    $a=$Evidence
    Assert-InternalScopedObject $a @('ContractType','ContractVersion','RetentionProfile','Mode','BusinessId','Capture','Links','Source','Adapter','Outcome','Scope','Fields','Claims')
    Assert-InternalScopedCode $a.ContractType @('BenefitScopedEvidence')
    Assert-InternalScopedInteger $a.ContractVersion 1 1
    Assert-InternalScopedCode $a.RetentionProfile @('C_LITE_V1')
    Assert-InternalScopedCode $a.Mode @('LOCATED_FIELDS','OUTCOME_ONLY')
    Assert-InternalScopedString $a.BusinessId 128 '^biz-[0-9a-f]{32}$'
    Assert-InternalScopedObject $a.Capture @('ObservationId','RunId','ObservedAt','SourceRowNumber')
    foreach($key in @('ObservationId','RunId')){Assert-InternalScopedString $a.Capture.$key 128 '^[A-Za-z0-9._:/-]+$'}
    Assert-InternalScopedTimestamp $a.Capture.ObservedAt
    Assert-InternalScopedInteger $a.Capture.SourceRowNumber 2
    Assert-InternalScopedObject $a.Links @('InputFingerprint','EvidenceFingerprint','SemanticFingerprint','ExecutionFingerprint','EvidenceArtifactReference','SemanticArtifactReference')
    foreach($key in @('InputFingerprint','EvidenceFingerprint','SemanticFingerprint','ExecutionFingerprint')){Assert-InternalScopedString $a.Links.$key 64 '^[0-9a-f]{64}$'}
    Assert-InternalScopedReference $a.Links.EvidenceArtifactReference 'BENEFIT_EVIDENCE_PROJECTION'
    Assert-InternalScopedReference $a.Links.SemanticArtifactReference 'BENEFIT_SEMANTIC_PROJECTION'
    Assert-InternalScopedObject $a.Source @('Url','Format','ContentHash','HashKind','SnapshotId','ObservedAt','TextLengthUtf16')
    Assert-InternalScopedString $a.Source.Url 2048
    $uri=$null
    if(-not [uri]::TryCreate($a.Source.Url,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -notin @('http','https') -or $uri.UserInfo -or $a.Source.Url -cne $a.Source.Url.Trim()){throw 'C_LITE_SOURCE_URL'}
    Assert-InternalScopedCode $a.Source.Format @('HTML')
    Assert-InternalScopedCode $a.Source.HashKind @('HTML_TEXT_UTF8_SHA256')
    foreach($key in @('ContentHash','SnapshotId')){Assert-InternalScopedString $a.Source.$key 64 '^[0-9a-f]{64}$'}
    Assert-InternalScopedTimestamp $a.Source.ObservedAt
    Assert-InternalScopedInteger $a.Source.TextLengthUtf16 1
    if($a.Source.SnapshotId -cne (Get-ScopeSnapshotId $a.Source.Url 'HTML' $a.Source.ObservedAt $a.Source.ContentHash)){throw 'C_LITE_SNAPSHOT_ID'}
    Assert-InternalScopedObject $a.Adapter @('Id','Version')
    if($null -ne $a.Adapter.Id -or $null -ne $a.Adapter.Version){
        Assert-InternalScopedCode $a.Adapter.Id @('HTML_GENERIC')
        Assert-InternalScopedCode $a.Adapter.Version @('1')
    }
    $o=$a.Outcome
    Assert-InternalScopedObject $o @('ObservationOperationalStatus','Comparable','FetchStatus','OfficialityStatus','AdapterStatus','LocationOperationalStatus','LocationStatus','BindingStatus','ExtractionStatus','ValidationStatus','CoverageKind','ContentUnitCount','CandidateReferences','CandidateReferenceCount','IdentityEvidenceCodes','ReasonCodes','ClaimValidationCounts')
    Assert-InternalScopedCode $o.ObservationOperationalStatus @('COMPLETE','PARTIAL','FAILED')
    if($o.Comparable -isnot [bool]){throw 'C_LITE_BOOLEAN'}
    if($o.Comparable -and $o.ObservationOperationalStatus -cne 'COMPLETE'){throw 'C_LITE_COMPARABILITY'}
    # A receipt is possible only after successful capture. A failed fetch has no source snapshot.
    Assert-InternalScopedCode $o.FetchStatus @('COMPLETE')
    Assert-InternalScopedCode $o.OfficialityStatus @('VERIFIED_OFFICIAL','UNVERIFIED','REJECTED') -Nullable
    Assert-InternalScopedCode $o.AdapterStatus @('COMPLETE','PARTIAL','FAILED','UNSUPPORTED') -Nullable
    Assert-InternalScopedCode $o.LocationOperationalStatus @('COMPLETE','PARTIAL','FAILED','UNSUPPORTED') -Nullable
    Assert-InternalScopedCode $o.LocationStatus @('LOCATED','AMBIGUOUS','NOT_FOUND') -Nullable
    Assert-InternalScopedCode $o.BindingStatus @('STRONG','PLAUSIBLE','AMBIGUOUS','CONFLICT') -Nullable
    foreach($key in @('ExtractionStatus','ValidationStatus')){Assert-InternalScopedCode $o.$key @('COMPLETE','PARTIAL','FAILED') -Nullable}
    Assert-InternalScopedCode $o.CoverageKind @('ADAPTER_SUPPORTED_TABLE_ROWS')
    if(($null -ne $o.LocationStatus -and $o.LocationOperationalStatus -cne 'COMPLETE') -or ($o.LocationOperationalStatus -ceq 'COMPLETE' -and ($o.AdapterStatus -cne 'COMPLETE' -or $null -eq $o.LocationStatus))){throw 'C_LITE_LOCATION_STATUS'}
    if($null -eq $o.AdapterStatus){
        if($null -ne $a.Adapter.Id -or $null -ne $o.ContentUnitCount -or $null -ne $o.LocationOperationalStatus){throw 'C_LITE_UNOBSERVED_ADAPTER'}
    } elseif($null -eq $a.Adapter.Id){throw 'C_LITE_ADAPTER_IDENTITY'}
    if($null -ne $o.ContentUnitCount){Assert-InternalScopedInteger $o.ContentUnitCount}
    Assert-InternalScopedArray $o.CandidateReferences 16
    if($null -eq $o.CandidateReferenceCount){if($o.CandidateReferences.Count -ne 0){throw 'C_LITE_UNKNOWN_COUNT'}}else{
        Assert-InternalScopedInteger $o.CandidateReferenceCount 0 16
        if($o.CandidateReferenceCount -ne $o.CandidateReferences.Count){throw 'C_LITE_COUNT'}
    }
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($ref in $o.CandidateReferences){Assert-InternalScopedString $ref 128 '^HTML_TABLE_[1-9][0-9]*_ROW_[1-9][0-9]*$';if(-not $seen.Add($ref)){throw 'C_LITE_DUPLICATE_REFERENCE'}}
    foreach($entry in @(@{Key='IdentityEvidenceCodes';Max=8;Allowed=@('NAME_MATCH','FULL_NAME_MATCH','FULL_ADDRESS_MATCH','BRANCH_MATCH','PHONE_MATCH')},@{Key='ReasonCodes';Max=32;Allowed=@((Get-BenefitVerificationContractDefinition).ReasonCode)})){
        Assert-InternalScopedArray $o.($entry.Key) $entry.Max
        $seen.Clear()
        foreach($code in $o.($entry.Key)){Assert-InternalScopedCode $code $entry.Allowed;if(-not $seen.Add($code)){throw 'C_LITE_DUPLICATE_CODE'}}
    }
    if($null -ne $o.ClaimValidationCounts){
        Assert-InternalScopedObject $o.ClaimValidationCounts @('Total','Validated','Invalid','Conflict','Unknown')
        foreach($key in @('Total','Validated','Invalid','Conflict','Unknown')){Assert-InternalScopedInteger $o.ClaimValidationCounts.$key 0 6}
        $counts=$o.ClaimValidationCounts
        if($counts.Total -ne ($counts.Validated+$counts.Invalid+$counts.Conflict+$counts.Unknown)){throw 'C_LITE_CLAIM_COUNTS'}
    }
    Assert-InternalScopedArray $a.Fields 10
    Assert-InternalScopedArray $a.Claims 6
    if($a.Mode -ceq 'OUTCOME_ONLY'){
        if(Test-InternalScopedCompletePositive $o){throw 'C_LITE_POSITIVE_DOWNGRADE'}
        if($null -ne $a.Scope -or $a.Fields.Count -ne 0 -or $a.Claims.Count -ne 0){throw 'C_LITE_OUTCOME_HAS_FIELDS'}
    }else{
        foreach($key in @('ObservationOperationalStatus','FetchStatus','AdapterStatus','LocationOperationalStatus','ExtractionStatus','ValidationStatus')){if($o.$key -cne 'COMPLETE'){throw 'C_LITE_INCOMPLETE_SCOPED'}}
        if(-not $o.Comparable -or $o.OfficialityStatus -cne 'VERIFIED_OFFICIAL' -or $o.LocationStatus -cne 'LOCATED' -or $o.BindingStatus -cne 'STRONG' -or $null -eq $o.ClaimValidationCounts -or $null -eq $o.ContentUnitCount -or $o.ContentUnitCount -lt 1 -or $o.CandidateReferenceCount -ne 1){throw 'C_LITE_INCOMPLETE_SCOPED'}
        $counts=$o.ClaimValidationCounts
        if($counts.Invalid+$counts.Conflict+$counts.Unknown -ne 0 -or $counts.Total -ne $a.Claims.Count){throw 'C_LITE_INCOMPLETE_CLAIMS'}
        Assert-InternalScopedObject $a.Scope @('Type','Reference','TableStart','TableLength','RowStart','RowLength')
        Assert-InternalScopedCode $a.Scope.Type @('TABLE_ROW')
        Assert-InternalScopedString $a.Scope.Reference 128 '^HTML_TABLE_[1-9][0-9]*_ROW_[1-9][0-9]*$'
        if($o.CandidateReferences[0] -cne $a.Scope.Reference){throw 'C_LITE_SCOPE_REFERENCE'}
        Assert-InternalScopedSpan $a.Scope.TableStart $a.Scope.TableLength 0 $a.Source.TextLengthUtf16
        Assert-InternalScopedSpan $a.Scope.RowStart $a.Scope.RowLength $a.Scope.TableStart $a.Scope.TableLength
        $keys=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $references=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $totalBytes=0
        foreach($field in $a.Fields){
            Assert-InternalScopedObject $field @('Key','HeaderText','DecodedValue','HeaderStart','HeaderLength','CellStart','CellLength','FieldReference')
            Assert-InternalScopedCode $field.Key @('BusinessName','Address','Phone','Branch','BenefitDescription','EligibleTarget','UsageCondition','VerificationMethod','ValidFrom','ValidUntilObserved')
            if(-not $keys.Add($field.Key)){throw 'C_LITE_DUPLICATE_FIELD'}
            Assert-InternalScopedString $field.HeaderText 256
            $headerMap=Get-BenefitScopedHeaderMap
            if(-not $headerMap.ContainsKey($field.HeaderText) -or $headerMap[$field.HeaderText] -cne $field.Key){throw 'C_LITE_HEADER_FIELD'}
            Assert-InternalScopedString $field.DecodedValue 4096
            $totalBytes += [Text.Encoding]::UTF8.GetByteCount($field.HeaderText)+[Text.Encoding]::UTF8.GetByteCount($field.DecodedValue)
            Assert-InternalScopedString $field.FieldReference 128
            if($field.FieldReference -cne ($a.Scope.Reference+'/'+$field.Key) -or -not $references.Add($field.FieldReference)){throw 'C_LITE_FIELD_REFERENCE'}
            Assert-InternalScopedSpan $field.HeaderStart $field.HeaderLength $a.Scope.TableStart $a.Scope.TableLength
            Assert-InternalScopedSpan $field.CellStart $field.CellLength $a.Scope.RowStart $a.Scope.RowLength
            if($field.HeaderStart+$field.HeaderLength -gt $a.Scope.RowStart){throw 'C_LITE_HEADER_ORDER'}
        }
        $requiredKeys=@(Get-InternalScopedRetainedKeys $o.IdentityEvidenceCodes $a.Claims)
        if($keys.Count -ne $requiredKeys.Count -or @($requiredKeys|Where-Object {-not $keys.Contains($_)}).Count -ne 0){throw 'C_LITE_RETAINED_FIELD_SET'}
        if(-not $keys.Contains('BusinessName') -or $totalBytes -gt 16384){throw 'C_LITE_FIELD_COVERAGE_OR_SIZE'}
        for($i=0;$i -lt $a.Fields.Count;$i++){
            for($j=$i+1;$j -lt $a.Fields.Count;$j++){
                foreach($part in @('Header','Cell')){
                    $left=$a.Fields[$i];$right=$a.Fields[$j];$s=$part+'Start';$l=$part+'Length'
                    if($left.$s -lt $right.$s+$right.$l -and $right.$s -lt $left.$s+$left.$l){throw 'C_LITE_FIELD_OVERLAP'}
                }
            }
        }
        $ordinals=[Collections.Generic.HashSet[long]]::new();$claimKeys=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $map=Get-InternalScopedClaimFields
        foreach($claim in $a.Claims){
            Assert-InternalScopedObject $claim @('ClaimType','FieldKey','EvidenceReference','ExtractionMethod','ValidationStatus','SemanticClaimOrdinal')
            Assert-InternalScopedCode $claim.ClaimType @($map.Keys)
            Assert-InternalScopedCode $claim.FieldKey @($map.Values)
            Assert-InternalScopedCode $claim.ExtractionMethod @('SCOPED_HTML_CELL')
            Assert-InternalScopedCode $claim.ValidationStatus @('VALIDATED')
            Assert-InternalScopedInteger $claim.SemanticClaimOrdinal 0 5
            Assert-InternalScopedString $claim.EvidenceReference 128
            if($claim.FieldKey -cne $map[$claim.ClaimType] -or -not $keys.Contains($claim.FieldKey) -or $claim.EvidenceReference -cne ($a.Scope.Reference+'/'+$claim.FieldKey) -or -not $ordinals.Add($claim.SemanticClaimOrdinal) -or -not $claimKeys.Add($claim.ClaimType)){throw 'C_LITE_CLAIM_LINK'}
        }
    }
    if([Text.Encoding]::UTF8.GetByteCount((ConvertTo-HistoryCanonicalJson $a)) -gt 65536){throw 'C_LITE_ARTIFACT_SIZE'}
}
function Test-BenefitScopedEvidenceReuseEligible {
    param([Parameter(Mandatory)]$Evidence)
    Assert-BenefitScopedEvidence $Evidence
    return ($Evidence.Mode -ceq 'LOCATED_FIELDS' -and $Evidence.Claims.Count -gt 0)
}

function Assert-InternalScopedObservation($Observation,$Manifest){
    Assert-InternalScopedObject $Observation @('ContractType','HistoryContractVersion','ObservationId','RunId','BusinessId','Domain','ObservedAt','OperationalStatus','Comparable','NonComparableReasons','InputFingerprint','EvidenceFingerprint','SemanticFingerprint','ExecutionFingerprint','ArtifactReferences','SemanticResultReference')
    Assert-InternalScopedCode $Observation.ContractType @('HistoryObservation')
    Assert-InternalScopedCode $Observation.OperationalStatus @('COMPLETE','PARTIAL','FAILED')
    Assert-InternalScopedString $Observation.BusinessId 128 '^biz-[0-9a-f]{32}$'
    foreach($key in @('InputFingerprint','EvidenceFingerprint','SemanticFingerprint','ExecutionFingerprint')){Assert-InternalScopedString $Observation.$key 64 '^[0-9a-f]{64}$'}
    Assert-InternalScopedString $Observation.SemanticResultReference 128
    Assert-InternalScopedArray $Observation.NonComparableReasons 32
    foreach($reason in $Observation.NonComparableReasons){Assert-InternalScopedString $reason 64 '^[A-Z0-9_]+$'}
    Assert-HistoryObservation $Observation
    foreach($key in @('ObservationId','RunId')){Assert-InternalScopedString $Observation.$key 128 '^[A-Za-z0-9._:/-]+$'}
    Assert-InternalScopedInteger $Observation.HistoryContractVersion 1 1
    Assert-InternalScopedCode $Observation.Domain @('BENEFIT')
    Assert-InternalScopedTimestamp $Observation.ObservedAt
    if($Observation.Comparable -isnot [bool]){throw 'C_LITE_BOOLEAN'}
    Assert-InternalScopedArray $Observation.ArtifactReferences 64
    foreach($ref in $Observation.ArtifactReferences){
        Assert-InternalScopedObject $ref @('ContractType','ContractVersion','Kind','ContentHash','RelativePath')
        Assert-InternalScopedCode $ref.ContractType @('HistoryArtifactReference')
        Assert-InternalScopedInteger $ref.ContractVersion 1 1
        Assert-InternalScopedString $ref.Kind 64 '^[A-Za-z0-9._:/-]+$'
        Assert-InternalScopedString $ref.ContentHash 64 '^[0-9a-f]{64}$'
        Assert-InternalScopedString $ref.RelativePath 128
        if($ref.RelativePath -cnotmatch ('^artifacts/sha256/'+$ref.ContentHash+'\.[a-z0-9]{1,16}$')){throw 'C_LITE_ARTIFACT_PATH'}
    }
    Assert-InternalScopedObject $Manifest @('ContractType','RunId','StartedAt','CompletedAt','RepositoryRevision','HistoryContractVersion','FingerprintSchemaVersion','RequestedBusinessIds','CompletedBusinessIds','FailedBusinessIds','ExecutionStatus','RunCommitStatus')
    Assert-InternalScopedCode $Manifest.ContractType @('HistoryRunManifest')
    Assert-InternalScopedString $Manifest.RunId 128 '^[A-Za-z0-9._:/-]+$'
    Assert-InternalScopedTimestamp $Manifest.StartedAt
    Assert-InternalScopedTimestamp $Manifest.CompletedAt
    Assert-InternalScopedString $Manifest.RepositoryRevision 40 '^[0-9a-f]{40}$'
    Assert-InternalScopedCode $Manifest.ExecutionStatus @('COMPLETE','PARTIAL','FAILED')
    Assert-InternalScopedCode $Manifest.RunCommitStatus @('COMMITTED')
    foreach($key in @('RequestedBusinessIds','CompletedBusinessIds','FailedBusinessIds')){
        Assert-InternalScopedArray $Manifest.$key 100000
        foreach($id in $Manifest.$key){Assert-InternalScopedString $id 128 '^biz-[0-9a-f]{32}$'}
    }
    Assert-HistoryRunManifest $Manifest
    Assert-InternalScopedInteger $Manifest.HistoryContractVersion 1 1
    Assert-InternalScopedInteger $Manifest.FingerprintSchemaVersion 1 1
    if($Manifest.RunId -cne $Observation.RunId -or $Manifest.RunCommitStatus -cne 'COMMITTED'){throw 'C_LITE_MANIFEST_OWNER'}
    foreach($key in @('RequestedBusinessIds','CompletedBusinessIds','FailedBusinessIds')){Assert-InternalScopedArray $Manifest.$key 100000}
    if($Observation.BusinessId -cnotin $Manifest.RequestedBusinessIds -or $Observation.BusinessId -cnotin $Manifest.CompletedBusinessIds -or $Observation.BusinessId -cin $Manifest.FailedBusinessIds){throw 'C_LITE_MANIFEST_MEMBERSHIP'}
}
function Assert-InternalScopedProjectionLinks($Observation,$EvidenceProjection,$SemanticProjection){
    Assert-InternalScopedObject $EvidenceProjection @('ProjectionType','ProjectionVersion','Sources')
    Assert-InternalScopedCode $EvidenceProjection.ProjectionType @('BenefitHistoryEvidence')
    Assert-InternalScopedInteger $EvidenceProjection.ProjectionVersion 1 1
    Assert-InternalScopedArray $EvidenceProjection.Sources 1
    foreach($source in $EvidenceProjection.Sources){
        Assert-InternalScopedObject $source @('SourceUrl','SourceFormat','ContentHash','AdapterId','AdapterVersion','LocationOperationalStatus','LocationStatus','CandidateReferences')
        foreach($key in @('SourceUrl','SourceFormat','ContentHash','AdapterId','AdapterVersion','LocationOperationalStatus','LocationStatus')){Assert-InternalScopedString $source.$key $(if($key -ceq 'SourceUrl'){2048}else{128}) -Empty}
        Assert-InternalScopedArray $source.CandidateReferences 16
        foreach($r in $source.CandidateReferences){Assert-InternalScopedString $r 128}
    }
    Assert-InternalScopedObject $SemanticProjection @('ProjectionType','ProjectionVersion','BenefitState','ReviewClass','BusinessPresence','AbsenceEligible','Claims','MaterialReasonCodes')
    Assert-InternalScopedCode $SemanticProjection.ProjectionType @('BenefitHistorySemantic')
    Assert-InternalScopedInteger $SemanticProjection.ProjectionVersion 1 1
    Assert-InternalScopedCode $SemanticProjection.BenefitState @('ACTIVE','CHANGED','ENDED','NEEDS_VERIFICATION')
    Assert-InternalScopedCode $SemanticProjection.ReviewClass @('GREEN','YELLOW','RED')
    Assert-InternalScopedCode $SemanticProjection.BusinessPresence @('PRESENT','ABSENT','UNKNOWN')
    if($SemanticProjection.AbsenceEligible -isnot [bool]){throw 'C_LITE_BOOLEAN'}
    Assert-InternalScopedArray $SemanticProjection.Claims 8
    foreach($claim in $SemanticProjection.Claims){
        Assert-InternalScopedObject $claim @('ClaimType','SemanticValue','ClaimResult','ValidationStatus','BusinessBound','MaterialReasonCodes')
        Assert-InternalScopedCode $claim.ClaimType @((Get-BenefitVerificationContractDefinition).ClaimType)
        Assert-InternalScopedString $claim.SemanticValue 4096 -Empty
        Assert-InternalScopedCode $claim.ClaimResult @((Get-BenefitVerificationContractDefinition).ClaimResult)
        if($claim.ValidationStatus -isnot [string] -or ($claim.ValidationStatus -cne '' -and $claim.ValidationStatus -cnotin @('VALIDATED','INVALID','CONFLICT','UNKNOWN'))){throw 'C_LITE_VALIDATION_CODE'}
        if($claim.BusinessBound -isnot [bool]){throw 'C_LITE_BOOLEAN'}
        Assert-InternalScopedArray $claim.MaterialReasonCodes 32
        foreach($reason in $claim.MaterialReasonCodes){Assert-InternalScopedCode $reason $script:BenefitHistoryMaterialReasonCodes}
    }
    Assert-InternalScopedArray $SemanticProjection.MaterialReasonCodes 32
    foreach($reason in $SemanticProjection.MaterialReasonCodes){Assert-InternalScopedCode $reason $script:BenefitHistoryMaterialReasonCodes}
    $pairs=@(
        @{Kind='BENEFIT_EVIDENCE_PROJECTION';Projection=$EvidenceProjection;Fingerprint='EvidenceFingerprint';Paths=@('Sources','Sources[].CandidateReferences')},
        @{Kind='BENEFIT_SEMANTIC_PROJECTION';Projection=$SemanticProjection;Fingerprint='SemanticFingerprint';Paths=@('Claims','Claims[].MaterialReasonCodes','MaterialReasonCodes')}
    )
    foreach($p in $pairs){
        $refs=@($Observation.ArtifactReferences|Where-Object Kind -CEQ $p.Kind)
        if($refs.Count -ne 1){throw 'C_LITE_PROJECTION_REFERENCE'}
        $json=ConvertTo-HistoryCanonicalJson -Value $p.Projection -OrderInsensitivePaths $p.Paths
        if([Text.Encoding]::UTF8.GetByteCount($json) -gt 65536 -or (Get-HistorySha256 $json) -cne $refs[0].ContentHash -or (Get-HistoryFingerprint $p.Projection -SchemaVersion 1 -OrderInsensitivePaths $p.Paths) -cne $Observation.($p.Fingerprint)){throw 'C_LITE_PROJECTION_INTEGRITY'}
        if($p.Kind -ceq 'BENEFIT_SEMANTIC_PROJECTION' -and $Observation.SemanticResultReference -cne $refs[0].RelativePath){throw 'C_LITE_SEMANTIC_REFERENCE'}
    }
}
function Assert-BenefitRetentionArtifactRequirements {
    param([Parameter(Mandatory)]$Observation,[Parameter(Mandatory)]$RunManifest,[Parameter(Mandatory)]$EvidenceProjection,[Parameter(Mandatory)]$SemanticProjection)
    Assert-InternalScopedObservation $Observation $RunManifest
    $profile=Get-BenefitRetentionProfileCandidate -ExecutionFingerprint $Observation.ExecutionFingerprint -RepositoryRevision $RunManifest.RepositoryRevision
    if($profile -ceq 'PROFILE_UNKNOWN'){throw 'C_LITE_PROFILE_UNKNOWN'}
    if($profile -ceq 'LEGACY'){return $profile} # Basic legacy readability does not qualify it for C-Lite reuse.
    Assert-InternalScopedProjectionLinks $Observation $EvidenceProjection $SemanticProjection
    foreach($r in $Observation.ArtifactReferences){if($r.Kind -cnotin @('BENEFIT_EVIDENCE_PROJECTION','BENEFIT_SEMANTIC_PROJECTION','BENEFIT_SCOPED_EVIDENCE','BENEFIT_REUSE_DECISION')){throw 'C_LITE_FORBIDDEN_ARTIFACT'}}
    $refs=@($Observation.ArtifactReferences|Where-Object Kind -CEQ 'BENEFIT_SCOPED_EVIDENCE')
    if($refs.Count -gt 1){throw 'C_LITE_SCOPED_REFERENCE'}
    if($refs.Count -eq 0){
        # The only no-artifact exception: no captured supported payload, no absence or comparable result.
        if($Observation.Comparable -or $Observation.OperationalStatus -ceq 'COMPLETE' -or 'SOURCE_FETCH_NOT_COMPLETE' -cnotin $Observation.NonComparableReasons -or $SemanticProjection.BusinessPresence -cne 'UNKNOWN' -or $SemanticProjection.AbsenceEligible){throw 'C_LITE_REQUIRED_SCOPED_REFERENCE'}
        foreach($source in $EvidenceProjection.Sources){if($source.ContentHash -cne '' -or $source.SourceFormat -cnotin @('','UNSUPPORTED')){throw 'C_LITE_REQUIRED_SCOPED_REFERENCE'}}
    }
    return $profile
}
function Get-InternalScopedPresenceDiagnostic($Evidence){
    return [pscustomobject]@{Url=$Evidence.Source.Url;FetchStatus=$Evidence.Outcome.FetchStatus;OfficialityStatus=$Evidence.Outcome.OfficialityStatus;AdapterStatus=$Evidence.Outcome.AdapterStatus;LocationOperationalStatus=$Evidence.Outcome.LocationOperationalStatus;LocationStatus=$Evidence.Outcome.LocationStatus;BusinessBindingStatus=$Evidence.Outcome.BindingStatus}
}
function Assert-BenefitScopedEvidenceRelationship {
    param([Parameter(Mandatory)]$Evidence,[Parameter(Mandatory)]$Observation,[Parameter(Mandatory)]$RunManifest,[Parameter(Mandatory)]$EvidenceProjection,[Parameter(Mandatory)]$SemanticProjection)
    Assert-BenefitScopedEvidence $Evidence
    $profile=Assert-BenefitRetentionArtifactRequirements -Observation $Observation -RunManifest $RunManifest -EvidenceProjection $EvidenceProjection -SemanticProjection $SemanticProjection
    if($profile -cne 'C_LITE_V1'){throw 'C_LITE_CAPTURE_PROFILE'}
    if($Evidence.BusinessId -cne $Observation.BusinessId -or $Evidence.Capture.ObservationId -cne $Observation.ObservationId -or $Evidence.Capture.RunId -cne $Observation.RunId -or $Evidence.Capture.ObservedAt -cne $Observation.ObservedAt -or $Evidence.Outcome.ObservationOperationalStatus -cne $Observation.OperationalStatus -or $Evidence.Outcome.Comparable -ne $Observation.Comparable){throw 'C_LITE_CAPTURE_OWNER'}
    $identity=$Observation.RunId+'|'+$Observation.BusinessId+'|BENEFIT|'+$Observation.InputFingerprint+'|'+$Observation.EvidenceFingerprint+'|'+$Observation.SemanticFingerprint+'|'+$Observation.ExecutionFingerprint
    if($Observation.ObservationId -cne ('obs-'+(Get-HistorySha256 $identity).Substring(0,32))){throw 'C_LITE_CAPTURE_OBSERVATION_ID'}
    foreach($key in @('InputFingerprint','EvidenceFingerprint','SemanticFingerprint','ExecutionFingerprint')){if($Evidence.Links.$key -cne $Observation.$key){throw 'C_LITE_CAPTURE_FINGERPRINT'}}
    foreach($p in @(@{Key='EvidenceArtifactReference';Kind='BENEFIT_EVIDENCE_PROJECTION'},@{Key='SemanticArtifactReference';Kind='BENEFIT_SEMANTIC_PROJECTION'})){
        $ref=@($Observation.ArtifactReferences|Where-Object Kind -CEQ $p.Kind)[0]
        if((ConvertTo-HistoryCanonicalJson $ref) -cne (ConvertTo-HistoryCanonicalJson $Evidence.Links.($p.Key))){throw 'C_LITE_CAPTURE_REFERENCE'}
    }
    $refs=@($Observation.ArtifactReferences|Where-Object Kind -CEQ 'BENEFIT_SCOPED_EVIDENCE')
    if($refs.Count -ne 1 -or $refs[0].ContentHash -cne (Get-HistorySha256 (ConvertTo-HistoryCanonicalJson $Evidence))){throw 'C_LITE_SCOPED_HASH'}
    if($EvidenceProjection.Sources.Count -ne 1){throw 'C_LITE_SOURCE_COUNT'}
    $s=$EvidenceProjection.Sources[0]
    foreach($p in @(@('SourceUrl','Url'),@('SourceFormat','Format'),@('ContentHash','ContentHash'))){if($s.($p[0]) -cne $Evidence.Source.($p[1])){throw 'C_LITE_SOURCE_LINK'}}
    foreach($p in @(@('AdapterId','Id'),@('AdapterVersion','Version'))){if($s.($p[0]) -cne $(if($null -eq $Evidence.Adapter.($p[1])){''}else{$Evidence.Adapter.($p[1])})){throw 'C_LITE_ADAPTER_LINK'}}
    foreach($p in @(@('LocationOperationalStatus','LocationOperationalStatus'),@('LocationStatus','LocationStatus'))){if($s.($p[0]) -cne $(if($null -eq $Evidence.Outcome.($p[1])){''}else{$Evidence.Outcome.($p[1])})){throw 'C_LITE_OUTCOME_LINK'}}
    if((ConvertTo-HistoryCanonicalJson @($s.CandidateReferences|Sort-Object -CaseSensitive)) -cne (ConvertTo-HistoryCanonicalJson @($Evidence.Outcome.CandidateReferences|Sort-Object -CaseSensitive))){throw 'C_LITE_CANDIDATE_LINK'}
    $diagnostic=Get-InternalScopedPresenceDiagnostic $Evidence
    if($SemanticProjection.BusinessPresence -cne (Get-BenefitHistoryBusinessPresence @($diagnostic)) -or $SemanticProjection.AbsenceEligible -ne (Test-BenefitHistoryAbsenceEligible @($diagnostic))){throw 'C_LITE_PRESENCE_LINK'}
    $canonicalSemantic=ConvertFrom-BenefitScopedEvidenceJson (ConvertTo-HistoryCanonicalJson $SemanticProjection -OrderInsensitivePaths @('Claims','Claims[].MaterialReasonCodes','MaterialReasonCodes'))
    if($Evidence.Mode -ceq 'LOCATED_FIELDS' -and $canonicalSemantic.Claims.Count -ne $Evidence.Claims.Count){throw 'C_LITE_INCOMPLETE_SEMANTIC_COVERAGE'}
    foreach($claim in $Evidence.Claims){
        if($claim.SemanticClaimOrdinal -ge $canonicalSemantic.Claims.Count){throw 'C_LITE_SEMANTIC_ORDINAL'}
        $semantic=$canonicalSemantic.Claims[$claim.SemanticClaimOrdinal]
        $field=@($Evidence.Fields|Where-Object Key -CEQ $claim.FieldKey)[0]
        $validated=New-ValidatedBenefitClaim -ClaimType $claim.ClaimType -Value $field.DecodedValue -ValidationStatus VALIDATED -EvidenceText $field.DecodedValue -EvidenceReference $claim.EvidenceReference -SourceUrl $Evidence.Source.Url
        $verification=New-BenefitClaimVerification -ClaimType $claim.ClaimType -EvidenceValue $field.DecodedValue -Result $semantic.ClaimResult -ValidatedClaim $validated
        if($semantic.ClaimType -cne $claim.ClaimType -or $semantic.ValidationStatus -cne 'VALIDATED' -or -not $semantic.BusinessBound -or $semantic.SemanticValue -cne (Get-BenefitHistorySemanticValue $verification)){throw 'C_LITE_SEMANTIC_LINK'}
    }
}
function Assert-BenefitScopedEvidenceCapture {
    param([Parameter(Mandatory)]$Evidence,[Parameter(Mandatory)]$Document,[AllowNull()]$EvidenceSlice,[Parameter(Mandatory)]$Extraction,[Parameter(Mandatory)]$Validation,[Parameter(Mandatory)]$Result,[Parameter(Mandatory)][AllowNull()]$SourceObservation,[Parameter(Mandatory)]$Business,[Parameter(Mandatory)]$QualifiedSource,[string]$CanonicalPhone=$null)
    Assert-BenefitScopedEvidence $Evidence
    Assert-BenefitSourceDocument $Document
    if($Document.FetchStatus -cne 'COMPLETE' -or $Document.SourceFormat -cne 'HTML' -or $Document.Url -cne $Evidence.Source.Url -or $Document.ObservedAt -cne $Evidence.Source.ObservedAt -or $Document.Text.Length -ne $Evidence.Source.TextLengthUtf16 -or (Get-BenefitEvidenceTextHash $Document.Text) -cne $Evidence.Source.ContentHash){throw 'C_LITE_CAPTURE_DOCUMENT'}
    foreach($stage in @($Document,$Extraction,$Validation,$Result)){if($stage.SourceRowNumber -ne $Evidence.Capture.SourceRowNumber){throw 'C_LITE_CAPTURE_ROW'}}
    if($Extraction.Status -cne $Evidence.Outcome.ExtractionStatus -or $Validation.Status -cne $Evidence.Outcome.ValidationStatus){throw 'C_LITE_CAPTURE_STAGE_STATUS'}
    Assert-InternalScopedArray $Extraction.Claims 6
    Assert-InternalScopedArray $Validation.Claims 6
    $counts=[ordered]@{Total=$Validation.Claims.Count;Validated=0;Invalid=0;Conflict=0;Unknown=0}
    foreach($v in $Validation.Claims){
        Assert-ValidatedBenefitClaim $v
        switch -CaseSensitive ($v.ValidationStatus){'VALIDATED'{$counts.Validated++};'INVALID'{$counts.Invalid++};'CONFLICT'{$counts.Conflict++};'UNKNOWN'{$counts.Unknown++};default{throw 'C_LITE_VALIDATION_CODE'}}
    }
    if((ConvertTo-HistoryCanonicalJson ([pscustomobject]$counts)) -cne (ConvertTo-HistoryCanonicalJson $Evidence.Outcome.ClaimValidationCounts)){throw 'C_LITE_CAPTURE_COUNTS'}
    # Ownership applies to receipts as well as positive field captures.
    Assert-NormalizedBusiness $Business
    Assert-BenefitVerificationResult $Result
    Assert-QualifiedBenefitSource $QualifiedSource
    foreach($trustedInput in @($Business,$QualifiedSource,$QualifiedSource.Candidate,$QualifiedSource.Document)){
        Assert-InternalScopedInteger $trustedInput.SourceRowNumber 2
        if($trustedInput.SourceRowNumber -ne $Evidence.Capture.SourceRowNumber){throw 'C_LITE_TRUSTED_ROW'}
    }
    if((ConvertTo-HistoryCanonicalJson $Business) -cne (ConvertTo-HistoryCanonicalJson $Result.BusinessIdentity)){throw 'C_LITE_TRUSTED_BUSINESS'}
    if($QualifiedSource.Document.Text -cne $Document.Text -or $QualifiedSource.Document.Url -cne $Document.Url -or $QualifiedSource.Candidate.Url -cne $Document.Url -or $QualifiedSource.Document.ObservedAt -cne $Document.ObservedAt -or $QualifiedSource.Document.SourceFormat -cne $Document.SourceFormat -or $QualifiedSource.Document.FetchStatus -cne $Document.FetchStatus -or ($null -ne $Evidence.Outcome.OfficialityStatus -and $QualifiedSource.OfficialityStatus -cne $Evidence.Outcome.OfficialityStatus)){throw 'C_LITE_TRUSTED_QUALIFICATION'}
    $located=$null
    if($null -eq $SourceObservation){
        if($null -ne $Evidence.Adapter.Id -or $null -ne $Evidence.Outcome.AdapterStatus -or $null -ne $Evidence.Outcome.ContentUnitCount -or $null -ne $Evidence.Outcome.LocationOperationalStatus -or $null -ne $Evidence.Outcome.LocationStatus){throw 'C_LITE_UNOBSERVED_ADAPTER'}
    }else{
        Assert-InternalScopedInteger $SourceObservation.SourceRowNumber 2
        if($SourceObservation.SourceRowNumber -ne $Evidence.Capture.SourceRowNumber){throw 'C_LITE_TRUSTED_ROW'}
        if($SourceObservation.Snapshot.Text -cne $Document.Text -or $SourceObservation.SourceUrl -cne $Document.Url -or $SourceObservation.ObservedAt -cne $Document.ObservedAt -or $SourceObservation.SourceFormat -cne 'HTML'){throw 'C_LITE_TRUSTED_SOURCE'}
        if($Evidence.Adapter.Id -cne $SourceObservation.AdapterId -or $Evidence.Adapter.Version -cne $SourceObservation.AdapterVersion -or $Evidence.Outcome.AdapterStatus -cne $SourceObservation.AdapterStatus -or ($null -ne $Evidence.Outcome.ContentUnitCount -and $Evidence.Outcome.ContentUnitCount -ne $SourceObservation.ContentUnits.Count)){throw 'C_LITE_TRUSTED_ADAPTER'}
        if($SourceObservation.AdapterStatus -ceq 'COMPLETE'){
            $located=Find-BenefitBusinessEvidence -Observation $SourceObservation -Business $Business -CanonicalPhone $CanonicalPhone
            if($located.OperationalStatus -cne $Evidence.Outcome.LocationOperationalStatus -or $located.Status -cne $Evidence.Outcome.LocationStatus){throw 'C_LITE_TRUSTED_LOCATION'}
            if($null -eq $Evidence.Outcome.CandidateReferenceCount -or $Evidence.Outcome.CandidateReferenceCount -ne @($located.CandidateReferences).Count -or (ConvertTo-HistoryCanonicalJson @($located.CandidateReferences|Sort-Object -CaseSensitive)) -cne (ConvertTo-HistoryCanonicalJson @($Evidence.Outcome.CandidateReferences|Sort-Object -CaseSensitive))){throw 'C_LITE_CANDIDATE_LINK'}
        }else{
            # Validate available observation integrity, without requiring successful parsing/location.
            Assert-ScopeObservation -Observation $SourceObservation
        }
    }
    if($Evidence.Mode -ceq 'OUTCOME_ONLY'){return}
    Assert-RelevantBenefitEvidenceSlice -Slice $EvidenceSlice -Document $Document -SourceRowNumber $Document.SourceRowNumber
    foreach($p in @(@('Type','ScopeType'),@('Reference','EvidenceReference'),@('TableStart','TableStart'),@('TableLength','TableLength'),@('RowStart','RawStart'),@('RowLength','RawLength'))){if($Evidence.Scope.($p[0]) -cne $EvidenceSlice.($p[1])){throw 'C_LITE_CAPTURE_SCOPE'}}
    if($located.OperationalStatus -cne 'COMPLETE' -or $located.Status -cne 'LOCATED' -or $located.Slices.Count -ne 1 -or $located.Slices[0].EvidenceReference -cne $EvidenceSlice.EvidenceReference){throw 'C_LITE_TRUSTED_LOCATION'}
    $trustedSlice=$located.Slices[0]
    $binding=Get-BenefitBusinessBinding -Source $QualifiedSource -Business $Business -CanonicalPhone $CanonicalPhone -EvidenceSlice $trustedSlice
    if($binding.BusinessBindingStatus -cne 'STRONG'){throw 'C_LITE_TRUSTED_BINDING'}
    $trustedCodes=@($trustedSlice.IdentityEvidence|Sort-Object -CaseSensitive)
    foreach($codes in @(@{Values=$Evidence.Outcome.IdentityEvidenceCodes},@{Values=$EvidenceSlice.IdentityEvidence})){
        if((ConvertTo-HistoryCanonicalJson @($codes.Values|Sort-Object -CaseSensitive)) -cne (ConvertTo-HistoryCanonicalJson $trustedCodes)){throw 'C_LITE_TRUSTED_IDENTITY'}
    }
    if($Evidence.Outcome.ContentUnitCount -ne $SourceObservation.ContentUnits.Count -or $Evidence.Adapter.Id -cne $SourceObservation.AdapterId -or $Evidence.Adapter.Version -cne $SourceObservation.AdapterVersion){throw 'C_LITE_TRUSTED_ADAPTER'}
    $nonemptyKeys=@(Get-InternalScopedRetainedKeys $trustedSlice.IdentityEvidence $Evidence.Claims)
    if($Evidence.Fields.Count -ne $nonemptyKeys.Count -or $Evidence.Claims.Count -ne $Extraction.Claims.Count -or $Extraction.Claims.Count -ne $Validation.Claims.Count){throw 'C_LITE_CAPTURE_CARDINALITY'}
    foreach($field in $Evidence.Fields){
        if($field.Key -cnotin $nonemptyKeys -or $field.DecodedValue -cne $EvidenceSlice.StructuredFields[$field.Key]){throw 'C_LITE_CAPTURE_FIELD'}
        $ref=$EvidenceSlice.FieldReferences[$field.Key]
        foreach($p in @(@('HeaderText','OriginalHeader'),@('HeaderStart','HeaderStart'),@('HeaderLength','HeaderLength'),@('CellStart','CellStart'),@('CellLength','CellLength'),@('FieldReference','FieldReference'))){if($field.($p[0]) -cne $ref.($p[1])){throw 'C_LITE_CAPTURE_FIELD_REFERENCE'}}
    }
    if($Result.ClaimResults.Count -ne $Evidence.Claims.Count){throw 'C_LITE_INCOMPLETE_SEMANTIC_COVERAGE'}
    $diagnostic=Get-InternalScopedPresenceDiagnostic $Evidence
    $semantic=ConvertTo-BenefitHistorySemanticProjection -Result $Result -EvidenceDiagnostics @($diagnostic)
    $canonical=ConvertTo-HistoryCanonicalJson $semantic -OrderInsensitivePaths @('Claims','Claims[].MaterialReasonCodes','MaterialReasonCodes')
    if([Text.Encoding]::UTF8.GetByteCount($canonical) -gt 65536 -or (Get-HistorySha256 $canonical) -cne $Evidence.Links.SemanticArtifactReference.ContentHash -or (Get-HistoryFingerprint $semantic -OrderInsensitivePaths @('Claims','Claims[].MaterialReasonCodes','MaterialReasonCodes')) -cne $Evidence.Links.SemanticFingerprint){throw 'C_LITE_CAPTURE_SEMANTIC'}
    $stored=ConvertFrom-BenefitScopedEvidenceJson $canonical
    foreach($link in $Evidence.Claims){
        $x=@($Extraction.Claims|Where-Object {$_.ClaimType -ceq $link.ClaimType -and $_.EvidenceReference -ceq $link.EvidenceReference})
        $v=@($Validation.Claims|Where-Object {$_.ClaimType -ceq $link.ClaimType -and $_.EvidenceReference -ceq $link.EvidenceReference})
        $results=@($Result.ClaimResults|Where-Object {$_.ClaimType -ceq $link.ClaimType -and $null -ne $_.ValidatedClaim -and $_.ValidatedClaim.EvidenceReference -ceq $link.EvidenceReference})
        if($x.Count -ne 1 -or $v.Count -ne 1 -or $results.Count -ne 1){throw 'C_LITE_AMBIGUOUS_CLAIM'}
        Assert-ExtractedBenefitClaim $x[0]
        Assert-InternalScopedCode $x[0].ExtractionMethod @('SCOPED_HTML_CELL')
        foreach($validated in @($v[0],$results[0].ValidatedClaim)){
            Assert-InternalScopedCode $validated.ValidationStatus @('VALIDATED')
            if($validated.PSObject.Properties.Name -ccontains 'ExtractionMethod'){Assert-InternalScopedCode $validated.ExtractionMethod @('SCOPED_HTML_CELL')}
        }
        if($v[0].PSObject.Properties.Name -ccontains 'ExtractionMethod' -and $v[0].ExtractionMethod -cne $x[0].ExtractionMethod){throw 'C_LITE_CLAIM_METHOD'}
        foreach($claim in @($x[0],$v[0],$results[0].ValidatedClaim)){
            foreach($key in @('ClaimType','Value','EvidenceText','EvidenceReference','SourceUrl')){if($claim.$key -isnot [string]){throw 'C_LITE_CLAIM_TYPE'}}
            $value=$EvidenceSlice.StructuredFields[$link.FieldKey]
            if($claim.ClaimType -cne $link.ClaimType -or $claim.EvidenceReference -cne $link.EvidenceReference -or $claim.SourceUrl -cne $Document.Url -or (ConvertTo-BenefitScopedValidationText $claim.Value) -cne (ConvertTo-BenefitScopedValidationText $value) -or (ConvertTo-BenefitScopedValidationText $claim.EvidenceText) -cne (ConvertTo-BenefitScopedValidationText $value)){throw 'C_LITE_CLAIM_VALUE'}
        }
        $single=ConvertTo-BenefitHistorySemanticProjection -Result (New-BenefitVerificationResult -SourceRowNumber $Result.SourceRowNumber -BusinessIdentity $Result.BusinessIdentity -BenefitState $Result.BenefitState -ReviewClass $Result.ReviewClass -ClaimResults @($results[0]) -ProductionAction NONE) -EvidenceDiagnostics @($diagnostic)
        if($link.SemanticClaimOrdinal -ge $stored.Claims.Count -or (ConvertTo-HistoryCanonicalJson $single.Claims[0] -OrderInsensitivePaths @('MaterialReasonCodes')) -cne (ConvertTo-HistoryCanonicalJson $stored.Claims[$link.SemanticClaimOrdinal] -OrderInsensitivePaths @('MaterialReasonCodes'))){throw 'C_LITE_CANONICAL_CLAIM_ORDINAL'}
    }
}

function Assert-BenefitReuseDecisionV2 {
    param([Parameter(Mandatory)]$Decision)
    $d=$Decision
    Assert-InternalScopedObject $d @('ContractType','ContractVersion','ProcessingMode','ReusedFromObservationId','Capability','PreviousPayloadCheckpoint','CurrentPayloadCheckpoint','InputMatch','ExecutionMatch','PayloadMatch','RepositoryClean','PreviousComparable','ReuseApplied','ReasonCodes','OwnerObservationId','OwnerRunId','BusinessId','ScopedEvidenceReference')
    Assert-InternalScopedCode $d.ContractType @('BenefitReuseDecision')
    Assert-InternalScopedInteger $d.ContractVersion 2 2
    Assert-InternalScopedCode $d.ProcessingMode @('REUSED_IDENTICAL_EVIDENCE')
    Assert-InternalScopedCode $d.Capability @('POST_FETCH')
    foreach($key in @('InputMatch','ExecutionMatch','PayloadMatch','RepositoryClean','PreviousComparable','ReuseApplied')){if($d.$key -isnot [bool] -or -not $d.$key){throw 'C_LITE_REUSE_FLAG'}}
    foreach($key in @('OwnerObservationId','OwnerRunId','ReusedFromObservationId')){Assert-InternalScopedString $d.$key 128 '^[A-Za-z0-9._:/-]+$'}
    Assert-InternalScopedString $d.BusinessId 128 '^biz-[0-9a-f]{32}$'
    Assert-InternalScopedReference $d.ScopedEvidenceReference 'BENEFIT_SCOPED_EVIDENCE'
    Assert-InternalScopedArray $d.ReasonCodes 1
    if($d.ReasonCodes.Count -ne 1){throw 'C_LITE_REUSE_REASON'}
    Assert-InternalScopedCode $d.ReasonCodes[0] @('REUSE_ELIGIBLE')
    foreach($checkpoint in @($d.PreviousPayloadCheckpoint,$d.CurrentPayloadCheckpoint)){
        Assert-InternalScopedObject $checkpoint @('ContractType','ContractVersion','SourceUrl','SourceFormat','ContentHash')
        Assert-InternalScopedCode $checkpoint.ContractType @('BenefitIncrementalPayloadCheckpoint')
        Assert-InternalScopedInteger $checkpoint.ContractVersion 1 1
        Assert-InternalScopedCode $checkpoint.SourceFormat @('HTML')
        Assert-InternalScopedString $checkpoint.SourceUrl 2048
        Assert-InternalScopedString $checkpoint.ContentHash 64 '^[0-9a-f]{64}$'
    }
    if((ConvertTo-HistoryCanonicalJson $d.PreviousPayloadCheckpoint) -cne (ConvertTo-HistoryCanonicalJson $d.CurrentPayloadCheckpoint)){throw 'C_LITE_REUSE_PAYLOAD'}
    if([Text.Encoding]::UTF8.GetByteCount((ConvertTo-HistoryCanonicalJson $d)) -gt 16384){throw 'C_LITE_REUSE_SIZE'}
}
function Assert-InternalScopedReuseOwner($Decision,$Observation,$Evidence){
    Assert-BenefitReuseDecisionV2 $Decision
    if($Decision.OwnerObservationId -cne $Observation.ObservationId -or $Decision.OwnerRunId -cne $Observation.RunId -or $Decision.BusinessId -cne $Observation.BusinessId){throw 'C_LITE_REUSE_OWNER'}
    $identity=$Observation.RunId+'|'+$Observation.BusinessId+'|BENEFIT|REUSED|'+$Decision.ReusedFromObservationId+'|'+$Observation.ObservedAt
    if($Observation.ObservationId -cne ('obs-'+(Get-HistorySha256 $identity).Substring(0,32))){throw 'C_LITE_REUSE_OBSERVATION_ID'}
    $refs=@($Observation.ArtifactReferences|Where-Object Kind -CEQ 'BENEFIT_REUSE_DECISION')
    if($refs.Count -ne 1 -or $refs[0].ContentHash -cne (Get-HistorySha256 (ConvertTo-HistoryCanonicalJson $Decision))){throw 'C_LITE_REUSE_HASH'}
    $scoped=@($Observation.ArtifactReferences|Where-Object Kind -CEQ 'BENEFIT_SCOPED_EVIDENCE')
    if($scoped.Count -ne 1 -or (ConvertTo-HistoryCanonicalJson $scoped[0]) -cne (ConvertTo-HistoryCanonicalJson $Decision.ScopedEvidenceReference)){throw 'C_LITE_REUSE_SCOPED_REFERENCE'}
    foreach($checkpoint in @($Decision.PreviousPayloadCheckpoint,$Decision.CurrentPayloadCheckpoint)){
        if($checkpoint.SourceUrl -cne $Evidence.Source.Url -or $checkpoint.SourceFormat -cne $Evidence.Source.Format -or $checkpoint.ContentHash -cne $Evidence.Source.ContentHash){throw 'C_LITE_REUSE_CAPTURE_PAYLOAD'}
    }
}
function Assert-BenefitScopedReuseRelationship {
    param([Parameter(Mandatory)]$Decision,[Parameter(Mandatory)]$Current,[Parameter(Mandatory)]$CurrentManifest,
        [Parameter(Mandatory)]$Previous,[Parameter(Mandatory)]$PreviousManifest,[Parameter(Mandatory)]$CaptureObservation,[Parameter(Mandatory)]$CaptureManifest,
        [Parameter(Mandatory)]$Evidence,[Parameter(Mandatory)]$EvidenceProjection,[Parameter(Mandatory)]$SemanticProjection,[Parameter(Mandatory)]$Comparison,[AllowNull()]$PreviousReuseDecision=$null)
    Assert-BenefitScopedEvidenceRelationship -Evidence $Evidence -Observation $CaptureObservation -RunManifest $CaptureManifest -EvidenceProjection $EvidenceProjection -SemanticProjection $SemanticProjection
    if(-not (Test-BenefitScopedEvidenceReuseEligible $Evidence)){throw 'C_LITE_REUSE_NOT_QUALIFIED'}
    foreach($pair in @(@{Observation=$Current;Manifest=$CurrentManifest},@{Observation=$Previous;Manifest=$PreviousManifest})){
        $o=$pair.Observation
        $profile=Assert-BenefitRetentionArtifactRequirements -Observation $o -RunManifest $pair.Manifest -EvidenceProjection $EvidenceProjection -SemanticProjection $SemanticProjection
        if($profile -cne 'C_LITE_V1' -or -not $o.Comparable -or $o.OperationalStatus -cne 'COMPLETE' -or $o.BusinessId -cne $CaptureObservation.BusinessId){throw 'C_LITE_REUSE_OBSERVATION'}
        foreach($key in @('InputFingerprint','EvidenceFingerprint','SemanticFingerprint','ExecutionFingerprint')){if($o.$key -cne $CaptureObservation.$key){throw 'C_LITE_REUSE_FINGERPRINT'}}
        $a=@($o.ArtifactReferences|Where-Object Kind -CEQ 'BENEFIT_SCOPED_EVIDENCE')
        if($a.Count -ne 1 -or $a[0].ContentHash -cne (Get-HistorySha256 (ConvertTo-HistoryCanonicalJson $Evidence))){throw 'C_LITE_REUSE_CAPTURE_HASH'}
    }
    if($Current.ObservationId -ceq $Previous.ObservationId -or $Current.RunId -ceq $Previous.RunId -or $Current.ObservedAt -ceq $Previous.ObservedAt -or $Decision.ReusedFromObservationId -cne $Previous.ObservationId){throw 'C_LITE_REUSE_FRESH_IDENTITY'}
    Assert-InternalScopedReuseOwner $Decision $Current $Evidence
    if($Previous.ObservationId -cne $CaptureObservation.ObservationId){
        if($null -eq $PreviousReuseDecision){throw 'C_LITE_PREVIOUS_REUSE_PROOF_REQUIRED'}
        Assert-InternalScopedReuseOwner $PreviousReuseDecision $Previous $Evidence
    }elseif($null -ne $PreviousReuseDecision -or @($Previous.ArtifactReferences|Where-Object Kind -CEQ 'BENEFIT_REUSE_DECISION').Count -ne 0){throw 'C_LITE_CAPTURE_IS_NOT_REUSE'}
    Assert-InternalScopedObject $Comparison @('ContractType','HistoryContractVersion','ComparatorVersion','ComparisonId','RunId','BusinessId','Domain','PreviousObservationId','CurrentObservationId','ComparisonStatus','DeltaDimensions','ChangeCandidates','ReasonCodes')
    Assert-InternalScopedCode $Comparison.ContractType @('ObservationComparison')
    foreach($key in @('ComparisonId','RunId','PreviousObservationId','CurrentObservationId')){Assert-InternalScopedString $Comparison.$key 128 '^[A-Za-z0-9._:/-]+$'}
    Assert-InternalScopedString $Comparison.BusinessId 128 '^biz-[0-9a-f]{32}$'
    Assert-InternalScopedCode $Comparison.Domain @('BENEFIT')
    Assert-InternalScopedCode $Comparison.ComparisonStatus @('COMPLETE')
    Assert-ObservationComparison $Comparison
    Assert-InternalScopedInteger $Comparison.HistoryContractVersion 1 1
    Assert-InternalScopedInteger $Comparison.ComparatorVersion 1 1
    foreach($key in @('DeltaDimensions','ChangeCandidates','ReasonCodes')){Assert-InternalScopedArray $Comparison.$key 0}
    if($Comparison.RunId -cne $Current.RunId -or $Comparison.BusinessId -cne $Current.BusinessId -or $Comparison.Domain -cne 'BENEFIT' -or $Comparison.ComparisonStatus -cne 'COMPLETE' -or $Comparison.PreviousObservationId -cne $Previous.ObservationId -or $Comparison.CurrentObservationId -cne $Current.ObservationId){throw 'C_LITE_REUSE_COMPARISON'}
}
function Assert-BenefitScopedEvidenceBundleSize {
    param([Parameter(Mandatory)]$ScopedJson,[Parameter(Mandatory)]$EvidenceJson,[Parameter(Mandatory)]$SemanticJson,[AllowNull()]$ReuseDecisionJson=$null)
    $total=0
    foreach($json in @($ScopedJson,$EvidenceJson,$SemanticJson)){
        Assert-InternalScopedString $json 65536 -Empty
        $total += [Text.Encoding]::UTF8.GetByteCount($json)
    }
    if($null -ne $ReuseDecisionJson){Assert-InternalScopedString $ReuseDecisionJson 16384 -Empty;$total += [Text.Encoding]::UTF8.GetByteCount($ReuseDecisionJson)}
    if($total -gt 196608){throw 'C_LITE_PREPARED_BUNDLE_SIZE'}
}

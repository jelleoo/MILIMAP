# Inactive composition only. No runner imports this file and no Store is opened.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'benefit-scoped-evidence.ps1')
. (Join-Path $PSScriptRoot '../benefit-evidence/benefit-source-run-context.ps1')
. (Join-Path $PSScriptRoot '../benefit-source/bind-benefit-source.ps1')

function Assert-InternalScopedHtmlCandidate {
    param($Candidate,$Evidence,$InputProjection,$EvidenceProjection,$SemanticProjection,$ExecutionProjection,$Assessment)
    Assert-InternalScopedObject $Candidate @('Observation','Artifacts')
    $o=$Candidate.Observation
    Assert-InternalScopedObject $o @('ContractType','HistoryContractVersion','ObservationId','RunId','BusinessId','Domain','ObservedAt','OperationalStatus','Comparable','NonComparableReasons','InputFingerprint','EvidenceFingerprint','SemanticFingerprint','ExecutionFingerprint','ArtifactReferences','SemanticResultReference')
    Assert-BenefitScopedEvidence $Evidence
    Assert-InternalScopedCode $o.ContractType @('HistoryObservation')
    Assert-InternalScopedInteger $o.HistoryContractVersion 1 1
    Assert-InternalScopedCode $o.Domain @('BENEFIT')
    Assert-InternalScopedCode $o.OperationalStatus @('COMPLETE','PARTIAL','FAILED')
    if($o.Comparable -isnot [bool]){throw 'C_LITE_CANDIDATE_BOOLEAN'}
    Assert-InternalScopedTimestamp $o.ObservedAt
    foreach($key in @('ObservationId','RunId')){Assert-InternalScopedString $o.$key 128 '^[A-Za-z0-9._:/-]+$'}
    Assert-InternalScopedString $o.BusinessId 128 '^biz-[0-9a-f]{32}$'
    foreach($key in @('InputFingerprint','EvidenceFingerprint','SemanticFingerprint','ExecutionFingerprint')){Assert-InternalScopedString $o.$key 64 '^[0-9a-f]{64}$'}
    Assert-InternalScopedArray $o.ArtifactReferences 3
    Assert-InternalScopedArray $o.NonComparableReasons 32
    foreach($reason in $o.NonComparableReasons){Assert-InternalScopedString $reason 64 '^[A-Z0-9_]+$'}
    if($o.OperationalStatus -cne $Assessment.OperationalStatus -or $o.Comparable -ne $Assessment.Comparable -or
        (ConvertTo-HistoryCanonicalJson @($o.NonComparableReasons)) -cne (ConvertTo-HistoryCanonicalJson @($Assessment.NonComparableReasons))){throw 'C_LITE_CANDIDATE_ASSESSMENT'}
    Assert-HistoryObservation $o
    Assert-InternalScopedArray $Candidate.Artifacts 3
    if($Candidate.Artifacts.Count -ne 3 -or $o.ArtifactReferences.Count -ne 3){throw 'C_LITE_CANDIDATE_ARTIFACTS'}
    $kinds=@('BENEFIT_EVIDENCE_PROJECTION','BENEFIT_SEMANTIC_PROJECTION','BENEFIT_SCOPED_EVIDENCE')
    foreach($kind in $kinds){
        $items=@($Candidate.Artifacts|Where-Object {$_.Reference.Kind -ceq $kind})
        $refs=@($o.ArtifactReferences|Where-Object Kind -CEQ $kind)
        if($items.Count -ne 1 -or $refs.Count -ne 1){throw 'C_LITE_CANDIDATE_ARTIFACTS'}
        Assert-InternalScopedObject $items[0] @('Reference','Text')
        Assert-InternalScopedReference $items[0].Reference $kind
        Assert-InternalScopedString $items[0].Text 65536
        if((Get-HistorySha256 $items[0].Text) -cne $refs[0].ContentHash -or
            (ConvertTo-HistoryCanonicalJson $items[0].Reference) -cne (ConvertTo-HistoryCanonicalJson $refs[0])){throw 'C_LITE_CANDIDATE_HASH'}
    }
    Assert-InternalScopedProjectionLinks $o $EvidenceProjection $SemanticProjection
    if((Get-HistoryFingerprint $InputProjection) -cne $o.InputFingerprint -or
        (Get-HistoryFingerprint $ExecutionProjection) -cne $o.ExecutionFingerprint -or
        (Get-BenefitRetentionProfileCandidate $o.ExecutionFingerprint $ExecutionProjection.RepositoryRevision) -cne 'C_LITE_V1'){throw 'C_LITE_CANDIDATE_FINGERPRINT'}
    $identity=$o.RunId+'|'+$o.BusinessId+'|BENEFIT|'+$o.InputFingerprint+'|'+$o.EvidenceFingerprint+'|'+$o.SemanticFingerprint+'|'+$o.ExecutionFingerprint
    if($o.ObservationId -cne ('obs-'+(Get-HistorySha256 $identity).Substring(0,32))){throw 'C_LITE_CANDIDATE_ID'}
    if($Evidence.BusinessId -cne $o.BusinessId -or $Evidence.Capture.ObservationId -cne $o.ObservationId -or
        $Evidence.Capture.RunId -cne $o.RunId -or $Evidence.Capture.ObservedAt -cne $o.ObservedAt -or
        $Evidence.Outcome.ObservationOperationalStatus -cne $o.OperationalStatus -or $Evidence.Outcome.Comparable -ne $o.Comparable){throw 'C_LITE_CANDIDATE_OWNER'}
    foreach($key in @('InputFingerprint','EvidenceFingerprint','SemanticFingerprint','ExecutionFingerprint')){
        if($Evidence.Links.$key -cne $o.$key){throw 'C_LITE_CANDIDATE_FINGERPRINT'}
    }
    $er=@($o.ArtifactReferences|Where-Object Kind -CEQ 'BENEFIT_EVIDENCE_PROJECTION')[0]
    $sr=@($o.ArtifactReferences|Where-Object Kind -CEQ 'BENEFIT_SEMANTIC_PROJECTION')[0]
    $ar=@($o.ArtifactReferences|Where-Object Kind -CEQ 'BENEFIT_SCOPED_EVIDENCE')[0]
    if((ConvertTo-HistoryCanonicalJson $er) -cne (ConvertTo-HistoryCanonicalJson $Evidence.Links.EvidenceArtifactReference) -or
        (ConvertTo-HistoryCanonicalJson $sr) -cne (ConvertTo-HistoryCanonicalJson $Evidence.Links.SemanticArtifactReference) -or
        (Get-HistorySha256 (ConvertTo-HistoryCanonicalJson $Evidence)) -cne $ar.ContentHash){throw 'C_LITE_CANDIDATE_LINK'}
    $presence=Get-InternalScopedPresenceDiagnostic $Evidence
    if($SemanticProjection.BusinessPresence -cne (Get-BenefitHistoryBusinessPresence @($presence)) -or
        $SemanticProjection.AbsenceEligible -ne (Test-BenefitHistoryAbsenceEligible @($presence))){throw 'C_LITE_CANDIDATE_PRESENCE'}
    $ej=@($Candidate.Artifacts|Where-Object {$_.Reference.Kind -ceq 'BENEFIT_EVIDENCE_PROJECTION'})[0].Text
    $sj=@($Candidate.Artifacts|Where-Object {$_.Reference.Kind -ceq 'BENEFIT_SEMANTIC_PROJECTION'})[0].Text
    $aj=@($Candidate.Artifacts|Where-Object {$_.Reference.Kind -ceq 'BENEFIT_SCOPED_EVIDENCE'})[0].Text
    Assert-BenefitScopedEvidenceBundleSize -ScopedJson $aj -EvidenceJson $ej -SemanticJson $sj
}

function New-BenefitScopedHtmlCaptureCandidate {
    # Untyped boundary parameters allow contract failures to be caught here instead
    # of exposing source values in PowerShell's parameter-binding error messages.
    param($RunContext,$SourceRecord,$Benefit,$BusinessId,$BusinessIdentity,$CanonicalPhone='',
        $Result,$OperationalStatus,$RunId,$ObservedAt,$RepositoryRevision)
    $ErrorActionPreference='Stop'
    try {
        # Capture all redirectable streams. A helper emitting anything beyond the
        # single completed DTO causes rejection; raw diagnostics never escape.
        $emitted=@(& {
            Assert-BenefitSourceRunContext $RunContext
            Assert-HistoryBusinessId $BusinessId
            Assert-HistoryToken $RunId 'run id'
            Assert-HistoryTimestamp $ObservedAt 'ObservedAt'
            Assert-InternalScopedString $RepositoryRevision 40 '^[0-9a-f]{40}$'
            if($CanonicalPhone -isnot [string]){throw 'C_LITE_PHONE_TYPE'}
            Assert-CanonicalBenefitRecord $Benefit
            Assert-NormalizedBusiness $BusinessIdentity
            Assert-BenefitVerificationResult $Result
            $d=$SourceRecord.Document;$obs=$SourceRecord.Observation
            Assert-BenefitSourceDocument $d
            if($d.SourceFormat -cne 'HTML' -or $d.FetchStatus -cne 'COMPLETE'){
                return [pscustomobject]@{Status='NOT_APPLICABLE';ReasonCode='C_LITE_NO_CAPTURED_HTML';Candidate=$null}
            }
            $row=$Benefit.SourceRowNumber
            foreach($item in @($BusinessIdentity,$Result,$SourceRecord,$SourceRecord.Candidate,$d)){
                Assert-InternalScopedInteger $item.SourceRowNumber 2
                if($item.SourceRowNumber -ne $row){throw 'C_LITE_INPUT_ROW'}
            }
            if($Benefit.ExistingSourceUrl -cne $d.Url -or $SourceRecord.Candidate.Url -cne $d.Url -or
                (ConvertTo-HistoryCanonicalJson $BusinessIdentity) -cne (ConvertTo-HistoryCanonicalJson $Result.BusinessIdentity)){throw 'C_LITE_INPUT_OWNER'}
            # Inspect existing cache only. Never call the lazy snapshot getter.
            if(-not $RunContext.PayloadCache.ContainsKey($d.Url)){throw 'C_LITE_PAYLOAD_MISSING'}
            $payload=$RunContext.PayloadCache[$d.Url]
            if($d.PSObject.Properties.Name -cnotcontains 'RunContextPayload' -or
                -not [object]::ReferenceEquals($d.RunContextPayload,$payload) -or
                $payload.PSObject.Properties.Name -cnotcontains 'SourceSnapshot'){throw 'C_LITE_PAYLOAD_TRUST'}
            $snapshot=$payload.SourceSnapshot
            if(-not (Test-InternalBenefitHtmlRunContextSnapshotTrust $snapshot)){throw 'C_LITE_SNAPSHOT_TRUST'}
            Assert-ScopeSnapshot $snapshot
            if($snapshot.SourceUrl -cne $d.Url -or $snapshot.ObservedAt -cne $d.ObservedAt -or $snapshot.Text -cne $d.Text -or
                $payload.Url -cne $d.Url -or $payload.ObservedAt -cne $d.ObservedAt -or $payload.Text -cne $d.Text -or
                $payload.SourceFormat -cne 'HTML' -or $payload.FetchStatus -cne 'COMPLETE'){throw 'C_LITE_PAYLOAD_OWNER'}
            $located=$null;$slice=$null
            $templateKey=$snapshot.SnapshotId+'|HTML_GENERIC|1'
            if($null -ne $obs){
                # Index-less failed/unsupported observations are strict copies in
                # the existing constructor. Their original cached Snapshot must
                # still be trusted; strict capture verifies the copied contents.
                if(($obs.AdapterStatus -ceq 'COMPLETE' -or $obs.ContentUnits.Count -gt 0) -and
                    -not [object]::ReferenceEquals($obs.Snapshot,$snapshot)){throw 'C_LITE_OBSERVATION_SNAPSHOT'}
                $index=Get-BenefitHistoryProperty $obs 'HtmlValidationIndex' $null
                $trusted=Test-InternalBenefitHtmlRunContextTrust -Snapshot $snapshot -HtmlValidationIndex $index
                if(-not $RunContext.TemplateCache.ContainsKey($templateKey)){throw 'C_LITE_TEMPLATE_MISSING'}
                $template=$RunContext.TemplateCache[$templateKey]
                if($obs.AdapterStatus -cne $template.AdapterStatus -or $obs.ContentUnits.Count -ne $template.Rows.Count){throw 'C_LITE_TEMPLATE_OUTCOME'}
                foreach($unit in $obs.ContentUnits){
                    $rows=@($template.Rows|Where-Object UnitReference -CEQ $unit.UnitReference)
                    if($rows.Count -ne 1){throw 'C_LITE_TEMPLATE_UNIT'}
                    foreach($key in @('TableStart','TableLength','RawStart','RawLength','RawEvidenceText')){
                        if($unit.$key -cne $rows[0].$key){throw 'C_LITE_TEMPLATE_UNIT'}
                    }
                    foreach($key in @('StructuredFields','FieldReferences')){
                        if((ConvertTo-HistoryCanonicalJson $unit.$key) -cne (ConvertTo-HistoryCanonicalJson $rows[0].$key)){throw 'C_LITE_TEMPLATE_UNIT'}
                    }
                }
                if($obs.AdapterStatus -ceq 'COMPLETE' -or ($obs.AdapterStatus -ceq 'PARTIAL' -and $obs.ContentUnits.Count -gt 0)){
                    if(-not $trusted){throw 'C_LITE_INDEX_REQUIRED'}
                }
                if($obs.AdapterStatus -ceq 'COMPLETE'){
                    # The existing slice/binder validator reads trust from the
                    # Document, independently of the Observation's trusted index.
                    # Guard both documents before any strict fallback can parse.
                    foreach($sourceDocument in @($d,$SourceRecord.Qualified.Document)){
                        if($sourceDocument.PSObject.Properties.Name -cnotcontains 'ValidatedHtmlSnapshot' -or
                            $sourceDocument.PSObject.Properties.Name -cnotcontains 'HtmlValidationIndex' -or
                            -not [object]::ReferenceEquals($sourceDocument.ValidatedHtmlSnapshot,$snapshot) -or
                            -not [object]::ReferenceEquals($sourceDocument.HtmlValidationIndex,$index) -or
                            -not [object]::ReferenceEquals($sourceDocument.Text,$snapshot.Text) -or
                            $sourceDocument.Url -cne $snapshot.SourceUrl -or $sourceDocument.ObservedAt -cne $snapshot.ObservedAt -or
                            $sourceDocument.SourceFormat -cne 'HTML' -or $sourceDocument.FetchStatus -cne 'COMPLETE' -or
                            $sourceDocument.SourceRowNumber -ne $row){throw 'C_LITE_DOCUMENT_INDEX_REQUIRED'}
                    }
                }
                Assert-ScopeObservation -Observation $obs -HtmlValidationIndex $(if($trusted){$index}else{$null})
                if($obs.AdapterStatus -ceq 'COMPLETE'){
                    $located=Find-BenefitBusinessEvidence -Observation $obs -Business $BusinessIdentity -CanonicalPhone $CanonicalPhone
                    $supplied=$SourceRecord.LocationResult
                    if($null -eq $supplied -or $supplied.Status -cne $located.Status -or $supplied.OperationalStatus -cne $located.OperationalStatus -or
                        (ConvertTo-HistoryCanonicalJson @($supplied.CandidateReferences|Sort-Object -CaseSensitive)) -cne (ConvertTo-HistoryCanonicalJson @($located.CandidateReferences|Sort-Object -CaseSensitive))){throw 'C_LITE_LOCATION_MISMATCH'}
                    if($located.Status -ceq 'LOCATED'){
                        if($SourceRecord.Slices.Count -ne 1){throw 'C_LITE_SLICE_COUNT'}
                        $slice=$SourceRecord.Slices[0]
                        if($slice.EvidenceReference -cne $located.Slices[0].EvidenceReference -or
                            (ConvertTo-HistoryCanonicalJson @($slice.IdentityEvidence|Sort-Object -CaseSensitive)) -cne
                            (ConvertTo-HistoryCanonicalJson @($located.Slices[0].IdentityEvidence|Sort-Object -CaseSensitive))){throw 'C_LITE_SLICE_IDENTITY'}
                        $binding=Get-BenefitBusinessBinding -Source $SourceRecord.Qualified -Business $BusinessIdentity -CanonicalPhone $CanonicalPhone -EvidenceSlice $located.Slices[0]
                        if($binding.BusinessBindingStatus -cne $SourceRecord.Bound.BusinessBindingStatus){throw 'C_LITE_BINDING_MISMATCH'}
                    }elseif($SourceRecord.Slices.Count -ne 0){throw 'C_LITE_UNLOCATED_SLICE'}
                }else{
                    $supplied=$SourceRecord.LocationResult
                    if($null -eq $supplied -or $supplied.OperationalStatus -cne $obs.AdapterStatus -or $null -ne $supplied.Status -or
                        $supplied.CandidateReferences.Count -ne 0 -or $SourceRecord.Slices.Count -ne 0){throw 'C_LITE_INCOMPLETE_LOCATION'}
                }
            }elseif($RunContext.TemplateCache.ContainsKey($templateKey) -or $null -ne $SourceRecord.LocationResult -or $SourceRecord.Slices.Count -ne 0 -or $SourceRecord.Extraction.Status -cne 'FAILED'){
                # A cached template cannot attest whether observation construction
                # failed or the caller removed an existing observation. Reject
                # this ambiguous post-template state; do not invent failure trust.
                throw 'C_LITE_PARSER_FAILURE_STATE'
            }
            $qualified=$SourceRecord.Qualified
            Assert-QualifiedBenefitSource $qualified
            Assert-BoundBenefitSource $SourceRecord.Bound
            # Receipts also carry semantic projections. Validate every supplied
            # claim chain before projecting it; Capture's receipt early return
            # deliberately does not perform the positive-only claim checks.
            Assert-InternalScopedArray $SourceRecord.Extraction.Claims 6
            Assert-InternalScopedArray $SourceRecord.Validation.Claims 6
            Assert-InternalScopedArray $Result.ClaimResults 6
            if($SourceRecord.Extraction.Claims.Count -ne $SourceRecord.Validation.Claims.Count -or
                $Result.ClaimResults.Count -ne $SourceRecord.Validation.Claims.Count){throw 'C_LITE_STAGE_CLAIM_COUNT'}
            if($SourceRecord.Extraction.Claims.Count -gt 0){
                if($null -eq $slice -or $SourceRecord.Bound.BusinessBindingStatus -cne 'STRONG' -or
                    $qualified.OfficialityStatus -cne 'VERIFIED_OFFICIAL'){throw 'C_LITE_UNBOUND_CLAIMS'}
                Assert-RelevantBenefitEvidenceSlice -Slice $slice -Document $d -SourceRowNumber $row
            }
            $seenClaims=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach($x in $SourceRecord.Extraction.Claims){
                Assert-ExtractedBenefitClaim $x
                $claimMap=Get-InternalScopedClaimFields
                if(-not $claimMap.ContainsKey($x.ClaimType) -or -not $seenClaims.Add($x.ClaimType)){throw 'C_LITE_CLAIM_TYPE'}
                $fieldKey=$claimMap[$x.ClaimType]
                if($x.ExtractionMethod -cne 'SCOPED_HTML_CELL' -or $x.EvidenceReference -cne $slice.FieldReferences[$fieldKey].FieldReference -or
                    $x.SourceUrl -cne $d.Url -or
                    (ConvertTo-BenefitScopedValidationText $x.Value) -cne (ConvertTo-BenefitScopedValidationText $slice.StructuredFields[$fieldKey]) -or
                    (ConvertTo-BenefitScopedValidationText $x.EvidenceText) -cne (ConvertTo-BenefitScopedValidationText $slice.StructuredFields[$fieldKey])){throw 'C_LITE_EXTRACTION_LINK'}
                $validations=@($SourceRecord.Validation.Claims|Where-Object {$_.ClaimType -ceq $x.ClaimType -and $_.EvidenceReference -ceq $x.EvidenceReference})
                $verifications=@($Result.ClaimResults|Where-Object {$_.ClaimType -ceq $x.ClaimType -and $null -ne $_.ValidatedClaim -and $_.ValidatedClaim.EvidenceReference -ceq $x.EvidenceReference})
                if($validations.Count -ne 1 -or $verifications.Count -ne 1){throw 'C_LITE_VALIDATION_LINK'}
                $v=$validations[0];$verification=$verifications[0]
                Assert-ValidatedBenefitClaim $v
                foreach($key in @('ClaimType','Value','EvidenceText','EvidenceReference','SourceUrl')){
                    if($v.$key -cne $x.$key -or $verification.ValidatedClaim.$key -cne $v.$key){throw 'C_LITE_VALIDATION_LINK'}
                }
                if($verification.ValidatedClaim.ValidationStatus -cne $v.ValidationStatus -or $verification.EvidenceValue -cne $v.Value){throw 'C_LITE_RESULT_LINK'}
            }
            $diag=[pscustomobject]@{
                Url=$d.Url;SourceFormat='HTML';FetchStatus=$d.FetchStatus;ContentHash=$snapshot.ContentHash
                OfficialityStatus=$qualified.OfficialityStatus;BusinessBindingStatus=$SourceRecord.Bound.BusinessBindingStatus
                AdapterId=$(if($null -eq $obs){''}else{$obs.AdapterId});AdapterVersion=$(if($null -eq $obs){''}else{$obs.AdapterVersion})
                AdapterStatus=$(if($null -eq $obs){''}else{$obs.AdapterStatus})
                LocationOperationalStatus=$(if($null -eq $SourceRecord.LocationResult){''}else{$SourceRecord.LocationResult.OperationalStatus})
                LocationStatus=$(if($null -eq $SourceRecord.LocationResult -or $null -eq $SourceRecord.LocationResult.Status){''}else{$SourceRecord.LocationResult.Status})
                CandidateReferences=@(if($null -ne $located){$located.CandidateReferences})
            }
            $input=ConvertTo-BenefitHistoryInputProjection -BusinessId $BusinessId -Benefit $Benefit -BusinessIdentity $BusinessIdentity -CanonicalPhone $CanonicalPhone
            $ep=ConvertTo-BenefitHistoryEvidenceProjection @($diag)
            $sp=ConvertTo-BenefitHistorySemanticProjection -Result $Result -EvidenceDiagnostics @($diag)
            $xp=ConvertTo-BenefitHistoryExecutionProjection -RepositoryRevision $RepositoryRevision -ExecutionConfiguration ([pscustomobject]@{HtmlEvidenceRetentionProfile='C_LITE_V1'})
            $fps=New-HistoryFingerprintSet -InputProjection $input -EvidenceProjection $ep -SemanticProjection $sp -ExecutionProjection $xp -EvidenceOrderInsensitivePaths @('Sources','Sources[].CandidateReferences') -SemanticOrderInsensitivePaths @('Claims','Claims[].MaterialReasonCodes','MaterialReasonCodes')
            $assessment=Get-BenefitHistoryOperationalAssessment -OperationalStatus $OperationalStatus -EvidenceDiagnostics @($diag)
            if($null -eq $obs -and $assessment.Comparable){throw 'C_LITE_PARSER_COMPARABLE'}
            $identity=$RunId+'|'+$BusinessId+'|BENEFIT|'+$fps.InputFingerprint+'|'+$fps.EvidenceFingerprint+'|'+$fps.SemanticFingerprint+'|'+$fps.ExecutionFingerprint
            $oid='obs-'+(Get-HistorySha256 $identity).Substring(0,32)
            $ej=ConvertTo-HistoryCanonicalJson $ep -OrderInsensitivePaths @('Sources','Sources[].CandidateReferences')
            $sj=ConvertTo-HistoryCanonicalJson $sp -OrderInsensitivePaths @('Claims','Claims[].MaterialReasonCodes','MaterialReasonCodes')
            $erHash=Get-HistorySha256 $ej;$srHash=Get-HistorySha256 $sj
            $er=New-HistoryArtifactReference -Kind BENEFIT_EVIDENCE_PROJECTION -ContentHash $erHash -RelativePath ('artifacts/sha256/'+$erHash+'.json')
            $sr=New-HistoryArtifactReference -Kind BENEFIT_SEMANTIC_PROJECTION -ContentHash $srHash -RelativePath ('artifacts/sha256/'+$srHash+'.json')
            $counts=[pscustomobject]@{Total=$SourceRecord.Validation.Claims.Count;Validated=0;Invalid=0;Conflict=0;Unknown=0}
            foreach($v in $SourceRecord.Validation.Claims){
                Assert-ValidatedBenefitClaim $v
                switch -CaseSensitive ($v.ValidationStatus){VALIDATED{$counts.Validated++};INVALID{$counts.Invalid++};CONFLICT{$counts.Conflict++};UNKNOWN{$counts.Unknown++}}
            }
            $outcome=[pscustomobject]@{
                ObservationOperationalStatus=$assessment.OperationalStatus;Comparable=$assessment.Comparable;FetchStatus='COMPLETE'
                OfficialityStatus=$qualified.OfficialityStatus;AdapterStatus=$(if($null -eq $obs){$null}else{$obs.AdapterStatus})
                LocationOperationalStatus=$(if($null -eq $SourceRecord.LocationResult){$null}else{$SourceRecord.LocationResult.OperationalStatus})
                LocationStatus=$(if($null -eq $SourceRecord.LocationResult){$null}else{$SourceRecord.LocationResult.Status})
                BindingStatus=$SourceRecord.Bound.BusinessBindingStatus;ExtractionStatus=$SourceRecord.Extraction.Status;ValidationStatus=$SourceRecord.Validation.Status
                CoverageKind='ADAPTER_SUPPORTED_TABLE_ROWS';ContentUnitCount=$(if($null -eq $obs){$null}else{$obs.ContentUnits.Count})
                CandidateReferences=@($diag.CandidateReferences);CandidateReferenceCount=$(if($null -eq $located){$null}else{$located.CandidateReferences.Count})
                IdentityEvidenceCodes=@(if($null -ne $slice){$slice.IdentityEvidence});ReasonCodes=@($SourceRecord.ReasonCodes);ClaimValidationCounts=$counts
            }
            $mode=if(Test-InternalScopedCompletePositive $outcome){'LOCATED_FIELDS'}else{'OUTCOME_ONLY'}
            $fields=@();$claims=@();$scope=$null
            if($mode -ceq 'LOCATED_FIELDS'){
                $canonicalSemantic=ConvertFrom-BenefitScopedEvidenceJson $sj
                foreach($x in $SourceRecord.Extraction.Claims){
                    $matches=@($Result.ClaimResults|Where-Object {$_.ClaimType -ceq $x.ClaimType -and $null -ne $_.ValidatedClaim -and $_.ValidatedClaim.EvidenceReference -ceq $x.EvidenceReference})
                    if($matches.Count -ne 1){throw 'C_LITE_CLAIM_RESULT'}
                    $one=New-BenefitVerificationResult -SourceRowNumber $row -BusinessIdentity $BusinessIdentity -BenefitState $Result.BenefitState -ReviewClass $Result.ReviewClass -ClaimResults @($matches[0]) -ProductionAction NONE
                    $single=ConvertTo-BenefitHistorySemanticProjection -Result $one -EvidenceDiagnostics @($diag)
                    $key=ConvertTo-HistoryCanonicalJson $single.Claims[0] -OrderInsensitivePaths @('MaterialReasonCodes')
                    $ordinals=@(for($i=0;$i -lt $canonicalSemantic.Claims.Count;$i++){
                        if((ConvertTo-HistoryCanonicalJson $canonicalSemantic.Claims[$i] -OrderInsensitivePaths @('MaterialReasonCodes')) -ceq $key){$i}
                    })
                    if($ordinals.Count -ne 1){throw 'C_LITE_CLAIM_ORDINAL'}
                    $map=Get-InternalScopedClaimFields
                    $claims+=@([pscustomobject]@{ClaimType=$x.ClaimType;FieldKey=$map[$x.ClaimType];EvidenceReference=$x.EvidenceReference;ExtractionMethod=$x.ExtractionMethod;ValidationStatus='VALIDATED';SemanticClaimOrdinal=$ordinals[0]})
                }
                foreach($key in @(Get-InternalScopedRetainedKeys $slice.IdentityEvidence $claims|Sort-Object -CaseSensitive)){
                    $r=$slice.FieldReferences[$key]
                    $fields+=@([pscustomobject]@{Key=$key;HeaderText=$r.OriginalHeader;DecodedValue=$slice.StructuredFields[$key];HeaderStart=$r.HeaderStart;HeaderLength=$r.HeaderLength;CellStart=$r.CellStart;CellLength=$r.CellLength;FieldReference=$r.FieldReference})
                }
                $scope=[pscustomobject]@{Type=$slice.ScopeType;Reference=$slice.EvidenceReference;TableStart=$slice.TableStart;TableLength=$slice.TableLength;RowStart=$slice.RawStart;RowLength=$slice.RawLength}
            }
            $evidence=[pscustomobject]@{
                ContractType='BenefitScopedEvidence';ContractVersion=1;RetentionProfile='C_LITE_V1';Mode=$mode;BusinessId=$BusinessId
                Capture=[pscustomobject]@{ObservationId=$oid;RunId=$RunId;ObservedAt=$ObservedAt;SourceRowNumber=$row}
                Links=[pscustomobject]@{InputFingerprint=$fps.InputFingerprint;EvidenceFingerprint=$fps.EvidenceFingerprint;SemanticFingerprint=$fps.SemanticFingerprint;ExecutionFingerprint=$fps.ExecutionFingerprint;EvidenceArtifactReference=$er;SemanticArtifactReference=$sr}
                Source=[pscustomobject]@{Url=$d.Url;Format='HTML';ContentHash=$snapshot.ContentHash;HashKind='HTML_TEXT_UTF8_SHA256';SnapshotId=$snapshot.SnapshotId;ObservedAt=$snapshot.ObservedAt;TextLengthUtf16=$snapshot.Text.Length}
                Adapter=[pscustomobject]@{Id=$(if($null -eq $obs){$null}else{$obs.AdapterId});Version=$(if($null -eq $obs){$null}else{$obs.AdapterVersion})}
                Outcome=$outcome;Scope=$scope;Fields=@($fields);Claims=@($claims)
            }
            Assert-BenefitScopedEvidenceCapture -Evidence $evidence -Document $d -EvidenceSlice $slice -Extraction $SourceRecord.Extraction -Validation $SourceRecord.Validation -Result $Result -SourceObservation $obs -Business $BusinessIdentity -QualifiedSource $qualified -CanonicalPhone $CanonicalPhone
            $aj=ConvertTo-HistoryCanonicalJson $evidence;$arHash=Get-HistorySha256 $aj
            $ar=New-HistoryArtifactReference -Kind BENEFIT_SCOPED_EVIDENCE -ContentHash $arHash -RelativePath ('artifacts/sha256/'+$arHash+'.json')
            $o=New-HistoryObservation -ObservationId $oid -RunId $RunId -BusinessId $BusinessId -Domain BENEFIT -ObservedAt $ObservedAt -OperationalStatus $assessment.OperationalStatus -Comparable $assessment.Comparable -InputFingerprint $fps.InputFingerprint -EvidenceFingerprint $fps.EvidenceFingerprint -SemanticFingerprint $fps.SemanticFingerprint -ExecutionFingerprint $fps.ExecutionFingerprint -ArtifactReferences @($er,$sr,$ar) -SemanticResultReference $sr.RelativePath -NonComparableReasons @($assessment.NonComparableReasons)
            $candidate=[pscustomobject]@{Observation=$o;Artifacts=@([pscustomobject]@{Reference=$er;Text=$ej},[pscustomobject]@{Reference=$sr;Text=$sj},[pscustomobject]@{Reference=$ar;Text=$aj})}
            Assert-InternalScopedHtmlCandidate -Candidate $candidate -Evidence $evidence -InputProjection $input -EvidenceProjection $ep -SemanticProjection $sp -ExecutionProjection $xp -Assessment $assessment
            return [pscustomobject]@{Status='READY';ReasonCode='C_LITE_CANDIDATE_READY';Candidate=$candidate}
        } *>&1)
        if($emitted.Count -ne 1 -or $emitted[0] -isnot [pscustomobject]){throw 'C_LITE_UNEXPECTED_OUTPUT'}
        return $emitted[0]
    } catch {
        return [pscustomobject]@{Status='REJECTED';ReasonCode='C_LITE_CANDIDATE_REJECTED';Candidate=$null}
    }
}

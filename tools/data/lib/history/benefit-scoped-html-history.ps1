# Inactive C-Lite persistence boundary. Definitions only; no writer/runner activation.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'benefit-scoped-html-capture-builder.ps1')
. (Join-Path $PSScriptRoot 'commit-history-run.ps1')

function Assert-InternalScopedHistoryFileToken {
    param($Value)
    Assert-InternalScopedString $Value 128 '^[A-Za-z0-9_-][A-Za-z0-9._-]*$'
    if($Value.Contains('..')){throw 'C_LITE_HISTORY_PATH_TOKEN'}
}

function ConvertFrom-InternalScopedHtmlArtifacts {
    param($Observation,$Artifacts,[switch]$IncludeReuse)
    $expectedCount=if($IncludeReuse){4}else{3}
    Assert-InternalScopedArray $Observation.ArtifactReferences $expectedCount
    Assert-InternalScopedArray $Artifacts $expectedCount
    if($Artifacts.Count -ne $expectedCount -or $Observation.ArtifactReferences.Count -ne $expectedCount){throw 'C_LITE_HISTORY_ARTIFACT_COUNT'}
    $specs=@(
        @{Kind='BENEFIT_EVIDENCE_PROJECTION';Key='EvidenceProjection';Paths=@('Sources','Sources[].CandidateReferences');MaxBytes=65536},
        @{Kind='BENEFIT_SEMANTIC_PROJECTION';Key='SemanticProjection';Paths=@('Claims','Claims[].MaterialReasonCodes','MaterialReasonCodes');MaxBytes=65536},
        @{Kind='BENEFIT_SCOPED_EVIDENCE';Key='Evidence';Paths=@();MaxBytes=65536}
    )
    if($IncludeReuse){
        $specs+=@(@{Kind='BENEFIT_REUSE_DECISION';Key='ReuseDecision';Paths=@();MaxBytes=16384})
    }
    $nodes=[ordered]@{Evidence=$null;EvidenceProjection=$null;SemanticProjection=$null}
    if($IncludeReuse){$nodes.ReuseDecision=$null}
    $texts=[ordered]@{}
    foreach($pair in $specs){
        $items=@($Artifacts|Where-Object {$_.Reference.Kind -ceq $pair.Kind})
        $refs=@($Observation.ArtifactReferences|Where-Object Kind -CEQ $pair.Kind)
        if($items.Count -ne 1 -or $refs.Count -ne 1){throw 'C_LITE_HISTORY_ARTIFACT_KIND'}
        $item=$items[0]
        Assert-InternalScopedObject $item @('Reference','Text')
        Assert-InternalScopedReference $item.Reference $pair.Kind
        Assert-InternalScopedReference $refs[0] $pair.Kind
        if((ConvertTo-HistoryCanonicalJson $item.Reference) -cne (ConvertTo-HistoryCanonicalJson $refs[0])){throw 'C_LITE_HISTORY_REFERENCE'}
        Assert-InternalScopedString $item.Text $pair.MaxBytes
        $bytes=[Text.UTF8Encoding]::new($false,$true).GetBytes($item.Text)
        if((Get-BenefitEvidenceByteHash $bytes) -cne $item.Reference.ContentHash){throw 'C_LITE_HISTORY_HASH'}
        $node=ConvertFrom-BenefitScopedEvidenceJson $item.Text -MaxBytes $pair.MaxBytes
        if((ConvertTo-HistoryCanonicalJson $node -OrderInsensitivePaths $pair.Paths) -cne $item.Text){throw 'C_LITE_HISTORY_CANONICAL'}
        $nodes[$pair.Key]=$node
        $texts[$pair.Kind]=$item.Text
    }
    Assert-BenefitScopedEvidence $nodes.Evidence
    if($IncludeReuse){
        Assert-BenefitReuseDecisionV2 $nodes.ReuseDecision
    }
    Assert-InternalScopedProjectionLinks $Observation $nodes.EvidenceProjection $nodes.SemanticProjection
    $reuseText=if($IncludeReuse){$texts['BENEFIT_REUSE_DECISION']}else{$null}
    Assert-BenefitScopedEvidenceBundleSize -ScopedJson $texts['BENEFIT_SCOPED_EVIDENCE'] -EvidenceJson $texts['BENEFIT_EVIDENCE_PROJECTION'] -SemanticJson $texts['BENEFIT_SEMANTIC_PROJECTION'] -ReuseDecisionJson $reuseText
    return [pscustomobject]$nodes
}

function New-BenefitScopedHtmlHistoryPackage {
    param($RunContext,$SourceRecord,$Benefit,$BusinessId,$BusinessIdentity,$CanonicalPhone='',
        $Result,$OperationalStatus,$RunId,$ObservedAt,$RepositoryRevision)
    $ErrorActionPreference='Stop'
    $inputs=@{RunContext=$RunContext;SourceRecord=$SourceRecord;Benefit=$Benefit;BusinessId=$BusinessId;BusinessIdentity=$BusinessIdentity;CanonicalPhone=$CanonicalPhone;Result=$Result;OperationalStatus=$OperationalStatus;RunId=$RunId;ObservedAt=$ObservedAt;RepositoryRevision=$RepositoryRevision}
    try{
        $output=@(& {
            $built=New-BenefitScopedHtmlCaptureCandidate @inputs
            Assert-InternalScopedObject $built @('Status','ReasonCode','Candidate')
            if($built.Status -cne 'READY' -or $built.ReasonCode -cne 'C_LITE_CANDIDATE_READY'){throw 'C_LITE_HISTORY_NOT_READY'}
            Assert-InternalScopedHistoryFileToken $RunId
            $candidate=$built.Candidate
            Assert-InternalScopedObject $candidate @('Observation','Artifacts')
            $o=$candidate.Observation
            if($o.RunId -cne $RunId -or $o.BusinessId -cne $BusinessId -or $o.ObservedAt -cne $ObservedAt){throw 'C_LITE_HISTORY_OWNER'}
            $nodes=ConvertFrom-InternalScopedHtmlArtifacts -Observation $o -Artifacts $candidate.Artifacts
            $e=$nodes.Evidence
            if($e.Outcome.BindingStatus -cne $SourceRecord.Bound.BusinessBindingStatus -or $e.Outcome.OfficialityStatus -cne $SourceRecord.Qualified.OfficialityStatus){throw 'C_LITE_HISTORY_SOURCE_OWNER'}
            $diag=Get-InternalScopedPresenceDiagnostic $e
            $diag|Add-Member SourceFormat 'HTML'
            $diag|Add-Member ContentHash $e.Source.ContentHash
            $diag|Add-Member AdapterId $(if($null -eq $e.Adapter.Id){''}else{$e.Adapter.Id})
            $diag|Add-Member AdapterVersion $(if($null -eq $e.Adapter.Version){''}else{$e.Adapter.Version})
            $diag|Add-Member CandidateReferences @($e.Outcome.CandidateReferences)
            $ip=ConvertTo-BenefitHistoryInputProjection -BusinessId $BusinessId -Benefit $Benefit -BusinessIdentity $BusinessIdentity -CanonicalPhone $CanonicalPhone
            $ep=ConvertTo-BenefitHistoryEvidenceProjection @($diag)
            $sp=ConvertTo-BenefitHistorySemanticProjection -Result $Result -EvidenceDiagnostics @($diag)
            $xp=ConvertTo-BenefitHistoryExecutionProjection -RepositoryRevision $RepositoryRevision -ExecutionConfiguration ([pscustomobject]@{HtmlEvidenceRetentionProfile='C_LITE_V1'})
            $assessment=Get-BenefitHistoryOperationalAssessment -OperationalStatus $OperationalStatus -EvidenceDiagnostics @($diag)
            Assert-InternalScopedHtmlCandidate -Candidate $candidate -Evidence $e -InputProjection $ip -EvidenceProjection $ep -SemanticProjection $sp -ExecutionProjection $xp -Assessment $assessment
            if($null -ne $SourceRecord.Observation -and $SourceRecord.Observation.AdapterStatus -ceq 'COMPLETE'){
                $snapshot=$SourceRecord.Observation.Snapshot;$index=$SourceRecord.Observation.HtmlValidationIndex
                if(-not (Test-InternalBenefitHtmlRunContextTrust -Snapshot $snapshot -HtmlValidationIndex $index)){throw 'C_LITE_HISTORY_INDEX'}
                foreach($document in @($SourceRecord.Document,$SourceRecord.Qualified.Document)){
                    if(-not [object]::ReferenceEquals($document.ValidatedHtmlSnapshot,$snapshot) -or
                        -not [object]::ReferenceEquals($document.HtmlValidationIndex,$index) -or
                        -not [object]::ReferenceEquals($document.Text,$snapshot.Text)){throw 'C_LITE_HISTORY_DOCUMENT_INDEX'}
                }
            }
            $slice=if($SourceRecord.Slices.Count -eq 1){$SourceRecord.Slices[0]}else{$null}
            Assert-BenefitScopedEvidenceCapture -Evidence $e -Document $SourceRecord.Document -EvidenceSlice $slice -Extraction $SourceRecord.Extraction -Validation $SourceRecord.Validation -Result $Result -SourceObservation $SourceRecord.Observation -Business $BusinessIdentity -QualifiedSource $SourceRecord.Qualified -CanonicalPhone $CanonicalPhone
            $prepared=@(foreach($item in $candidate.Artifacts){
                [pscustomobject]@{ContentHash=$item.Reference.ContentHash;Extension='json';Kind=$item.Reference.Kind;Text=$item.Text}
            })
            return [pscustomobject]@{Status='READY';ReasonCode='C_LITE_HISTORY_PACKAGE_READY';Package=[pscustomobject]@{Observation=$o;PreparedArtifacts=$prepared}}
        } *>&1)
        if($output.Count -ne 1 -or $output[0] -isnot [pscustomobject]){throw 'C_LITE_HISTORY_OUTPUT'}
        return $output[0]
    }catch{return [pscustomobject]@{Status='REJECTED';ReasonCode='C_LITE_HISTORY_PACKAGE_REJECTED';Package=$null}}
}

function Assert-InternalScopedHistoryStore {
    param($Store)
    Assert-InternalScopedObject $Store @('Root','RunsRoot','ObservationsRoot','ComparisonsRoot','ArtifactsRoot','IndexesRoot','TempRoot')
    if($Store.Root -isnot [string] -or -not [IO.Path]::IsPathRooted($Store.Root) -or -not [IO.Directory]::Exists($Store.Root)){throw 'C_LITE_HISTORY_STORE'}
    foreach($pair in @(@('RunsRoot','runs'),@('ObservationsRoot','observations'),@('ComparisonsRoot','comparisons'),@('ArtifactsRoot','artifacts/sha256'),@('IndexesRoot','indexes'),@('TempRoot','tmp'))){
        if($Store.($pair[0]) -isnot [string] -or [IO.Path]::GetFullPath($Store.($pair[0])) -cne [IO.Path]::GetFullPath((Join-Path $Store.Root $pair[1]))){throw 'C_LITE_HISTORY_LAYOUT'}
    }
}

function Read-InternalScopedHistoryFile {
    param($Store,[string]$Path,[int]$MaxBytes)
    $safe=Assert-HistoryStorePathWithinRoot -Store $Store -Path $Path
    # Core helpers enforce lexical containment. Reject filesystem indirections as
    # well, including in ancestors; never create/rebuild any Store paths here.
    $cursor=$safe
    while($null -ne $cursor){
        if(([IO.File]::GetAttributes($cursor) -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'C_LITE_HISTORY_REPARSE'}
        $parent=[IO.Directory]::GetParent($cursor)
        $cursor=if($null -eq $parent){$null}else{$parent.FullName}
    }
    $stream=[IO.File]::Open($safe,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try{
        if($stream.Length -lt 1 -or $stream.Length -gt $MaxBytes){throw 'C_LITE_HISTORY_FILE_SIZE'}
        $bytes=[byte[]]::new([int]$stream.Length)
        $stream.ReadExactly($bytes,0,$bytes.Length)
        $text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)
        # Strict parse runs on original bytes/text, before any Core reader can
        # normalize timestamp strings or discard duplicate/case-colliding keys.
        $value=ConvertFrom-BenefitScopedEvidenceJson -Json $text -MaxBytes $MaxBytes
        return [pscustomobject]@{Text=$text;Bytes=$bytes;Value=$value}
    }finally{$stream.Dispose()}
}

function Read-InternalScopedCommittedRecord {
    param($Store,[string]$ObservationId,[int]$ExpectedArtifactCount=0)
    Assert-InternalScopedHistoryFileToken $ObservationId
    $observationPath=Get-HistoryObservationPath -Store $Store -ObservationId $ObservationId
    $observationFile=Read-InternalScopedHistoryFile -Store $Store -Path $observationPath -MaxBytes 65536
    $o=$observationFile.Value
    if($o.ObservationId -cne $ObservationId){throw 'C_LITE_HISTORY_OBSERVATION_OWNER'}
    Assert-InternalScopedHistoryFileToken $o.RunId
    $manifestPath=Get-HistoryRunManifestPath -Store $Store -RunId $o.RunId
    $manifestFile=Read-InternalScopedHistoryFile -Store $Store -Path $manifestPath -MaxBytes 16777216
    $manifest=$manifestFile.Value
    Assert-InternalScopedObservation $o $manifest
    if($ExpectedArtifactCount -gt 0 -and $o.ArtifactReferences.Count -ne $ExpectedArtifactCount){throw 'C_LITE_HISTORY_ARTIFACT_COUNT'}
    return [pscustomobject]@{
        Observation=$o;Manifest=$manifest
        ObservationPath=$observationPath;ObservationText=$observationFile.Text
        ManifestPath=$manifestPath;ManifestText=$manifestFile.Text
    }
}

function Read-InternalScopedArtifactItem {
    param($Store,$Ref,[int]$MaxBytes=65536)
    Assert-InternalScopedReference $Ref $Ref.Kind
    $path=Get-HistoryArtifactPath -Store $Store -ContentHash $Ref.ContentHash -Extension 'json'
    if((Get-HistoryRelativePath -Store $Store -FullPath $path) -cne $Ref.RelativePath){throw 'C_LITE_HISTORY_REFERENCE'}
    $file=Read-InternalScopedHistoryFile -Store $Store -Path $path -MaxBytes $MaxBytes
    if((Get-BenefitEvidenceByteHash $file.Bytes) -cne $Ref.ContentHash){throw 'C_LITE_HISTORY_HASH'}
    return [pscustomobject]@{Reference=$Ref;Text=$file.Text;Value=$file.Value}
}

function Assert-InternalScopedFilesUnchanged {
    param($Store,[object[]]$Entries)
    foreach($entry in $Entries){
        $again=Read-InternalScopedHistoryFile -Store $Store -Path $entry.Path -MaxBytes $entry.MaxBytes
        if($again.Text -cne $entry.Text){throw 'C_LITE_HISTORY_CHANGED_DURING_READ'}
    }
}

function Read-BenefitScopedHtmlCommittedCapture {
    param($Store,$ObservationId)
    $ErrorActionPreference='Stop'
    try{
        $output=@(& {
            Assert-InternalScopedHistoryStore $Store
            $record=Read-InternalScopedCommittedRecord -Store $Store -ObservationId $ObservationId -ExpectedArtifactCount 3
            $o=$record.Observation;$manifest=$record.Manifest
            $artifacts=@(foreach($ref in $o.ArtifactReferences){
                if($ref.Kind -cnotin @('BENEFIT_EVIDENCE_PROJECTION','BENEFIT_SEMANTIC_PROJECTION','BENEFIT_SCOPED_EVIDENCE')){throw 'C_LITE_HISTORY_ARTIFACT_KIND'}
                $item=Read-InternalScopedArtifactItem -Store $Store -Ref $ref -MaxBytes 65536
                [pscustomobject]@{Reference=$item.Reference;Text=$item.Text}
            })
            $nodes=ConvertFrom-InternalScopedHtmlArtifacts -Observation $o -Artifacts $artifacts
            Assert-BenefitScopedEvidenceRelationship -Evidence $nodes.Evidence -Observation $o -RunManifest $manifest -EvidenceProjection $nodes.EvidenceProjection -SemanticProjection $nodes.SemanticProjection
            # Immutable records must still be the same at the end of this scan;
            # a mismatch rejects this attempt rather than triggering a retry.
            Assert-InternalScopedFilesUnchanged -Store $Store -Entries @(
                @{Path=$record.ObservationPath;MaxBytes=65536;Text=$record.ObservationText},
                @{Path=$record.ManifestPath;MaxBytes=16777216;Text=$record.ManifestText}
            )
            return [pscustomobject]@{Status='VERIFIED';ReasonCode='C_LITE_COMMITTED_VERIFIED';Capture=[pscustomobject]@{Observation=$o;Artifacts=$artifacts}}
        } *>&1)
        if($output.Count -ne 1 -or $output[0] -isnot [pscustomobject]){throw 'C_LITE_HISTORY_OUTPUT'}
        return $output[0]
    }catch{return [pscustomobject]@{Status='REJECTED';ReasonCode='C_LITE_COMMITTED_REJECTED';Capture=$null}}
}

function New-BenefitScopedHtmlReusePackage {
    param($Store,$PreviousObservationId,$RunContext,$Candidate,$Document,$Benefit,$BusinessId,$BusinessIdentity,$CanonicalPhone='',
        $RunId,$ObservedAt,$RepositoryRevision,$RepositoryClean=$true)
    $ErrorActionPreference='Stop'
    try{
        $output=@(& {
            Assert-InternalScopedHistoryStore $Store
            Assert-InternalScopedHistoryFileToken $PreviousObservationId
            Assert-InternalScopedHistoryFileToken $RunId
            Assert-HistoryBusinessId $BusinessId
            Assert-HistoryTimestamp $ObservedAt 'ObservedAt'
            Assert-InternalScopedString $RepositoryRevision 40 '^[0-9a-f]{40}$'
            if($CanonicalPhone -isnot [string]){throw 'C_LITE_REUSE_PHONE_TYPE'}
            if($RepositoryClean -isnot [bool] -or -not $RepositoryClean){throw 'C_LITE_REUSE_DIRTY_REPOSITORY'}
            Assert-BenefitSourceRunContext $RunContext
            Assert-CanonicalBenefitRecord $Benefit
            Assert-NormalizedBusiness $BusinessIdentity
            Assert-BenefitSourceCandidate $Candidate
            Assert-BenefitSourceDocument $Document
            if($Candidate.SourceKind -cne 'PUBLIC_OFFICIAL' -or $Document.SourceFormat -cne 'HTML' -or $Document.FetchStatus -cne 'COMPLETE'){throw 'C_LITE_REUSE_UNSUPPORTED_SOURCE'}
            $row=$Benefit.SourceRowNumber
            foreach($item in @($BusinessIdentity,$Candidate,$Document)){
                Assert-InternalScopedInteger $item.SourceRowNumber 2
                if($item.SourceRowNumber -ne $row){throw 'C_LITE_REUSE_ROW'}
            }
            if($Candidate.Url -cne $Document.Url){throw 'C_LITE_REUSE_URL'}
            if(-not $RunContext.PayloadCache.ContainsKey($Document.Url)){throw 'C_LITE_REUSE_PAYLOAD_MISSING'}
            $payload=$RunContext.PayloadCache[$Document.Url]
            if($Document.PSObject.Properties.Name -cnotcontains 'RunContextPayload' -or
                -not [object]::ReferenceEquals($Document.RunContextPayload,$payload) -or
                $payload.PSObject.Properties.Name -cnotcontains 'SourceSnapshot'){throw 'C_LITE_REUSE_PAYLOAD_TRUST'}
            $snapshot=$payload.SourceSnapshot
            if(-not (Test-InternalBenefitHtmlRunContextSnapshotTrust -Snapshot $snapshot)){throw 'C_LITE_REUSE_SNAPSHOT_TRUST'}
            Assert-ScopeSnapshot $snapshot
            if($snapshot.SourceUrl -cne $Document.Url -or $snapshot.ObservedAt -cne $Document.ObservedAt -or
                -not [object]::ReferenceEquals($snapshot.Text,$Document.Text) -or
                $payload.Url -cne $Document.Url -or $payload.ObservedAt -cne $Document.ObservedAt -or
                -not [object]::ReferenceEquals($payload.Text,$Document.Text) -or
                $payload.SourceFormat -cne 'HTML' -or $payload.FetchStatus -cne 'COMPLETE'){throw 'C_LITE_REUSE_PAYLOAD_OWNER'}

            $prevRecord=Read-InternalScopedCommittedRecord -Store $Store -ObservationId $PreviousObservationId
            $prevCount=$prevRecord.Observation.ArtifactReferences.Count
            if($prevCount -eq 3){
                $verified=Read-BenefitScopedHtmlCommittedCapture -Store $Store -ObservationId $PreviousObservationId
                if($verified.Status -cne 'VERIFIED' -or $null -eq $verified.Capture){throw 'C_LITE_REUSE_BASELINE_CAPTURE'}
                $prev=$verified.Capture.Observation
                $baseArtifacts=$verified.Capture.Artifacts
            }elseif($prevCount -eq 4){
                $verified=Read-BenefitScopedHtmlCommittedReuse -Store $Store -ObservationId $PreviousObservationId
                if($verified.Status -cne 'VERIFIED' -or $null -eq $verified.Reuse){throw 'C_LITE_REUSE_BASELINE_REUSE'}
                $prev=$verified.Reuse.Observation
                $baseArtifacts=@($verified.Reuse.Artifacts|Where-Object {$_.Reference.Kind -cne 'BENEFIT_REUSE_DECISION'})
            }else{
                throw 'C_LITE_REUSE_BASELINE_KIND'
            }
            if($prevRecord.Manifest.RepositoryRevision -cne $RepositoryRevision){throw 'C_LITE_REUSE_REVISION'}
            if($prev.BusinessId -cne $BusinessId -or $prev.OperationalStatus -cne 'COMPLETE' -or -not $prev.Comparable){throw 'C_LITE_REUSE_BASELINE_STATUS'}
            if($prev.RunId -ceq $RunId -or $prev.ObservedAt -ceq $ObservedAt){throw 'C_LITE_REUSE_FRESH_IDENTITY'}

            $baseObservation=[pscustomobject]@{
                ContractType=$prev.ContractType;HistoryContractVersion=$prev.HistoryContractVersion;ObservationId=$prev.ObservationId;RunId=$prev.RunId;BusinessId=$prev.BusinessId;Domain=$prev.Domain;ObservedAt=$prev.ObservedAt;OperationalStatus=$prev.OperationalStatus;Comparable=$prev.Comparable;NonComparableReasons=$prev.NonComparableReasons;InputFingerprint=$prev.InputFingerprint;EvidenceFingerprint=$prev.EvidenceFingerprint;SemanticFingerprint=$prev.SemanticFingerprint;ExecutionFingerprint=$prev.ExecutionFingerprint;ArtifactReferences=@($baseArtifacts|ForEach-Object {$_.Reference});SemanticResultReference=$prev.SemanticResultReference
            }
            $nodes=ConvertFrom-InternalScopedHtmlArtifacts -Observation $baseObservation -Artifacts $baseArtifacts
            $evidence=$nodes.Evidence;$ep=$nodes.EvidenceProjection;$sp=$nodes.SemanticProjection
            if(-not (Test-BenefitScopedEvidenceReuseEligible $evidence)){throw 'C_LITE_REUSE_NOT_ELIGIBLE'}
            if($evidence.Capture.RunId -ceq $RunId -or $evidence.Capture.ObservedAt -ceq $ObservedAt){throw 'C_LITE_REUSE_CAPTURE_IDENTITY'}

            $ip=ConvertTo-BenefitHistoryInputProjection -BusinessId $BusinessId -Benefit $Benefit -BusinessIdentity $BusinessIdentity -CanonicalPhone $CanonicalPhone
            $xp=ConvertTo-BenefitHistoryExecutionProjection -RepositoryRevision $RepositoryRevision -ExecutionConfiguration ([pscustomobject]@{HtmlEvidenceRetentionProfile='C_LITE_V1'})
            if((Get-HistoryFingerprint $ip) -cne $prev.InputFingerprint -or (Get-HistoryFingerprint $xp) -cne $prev.ExecutionFingerprint){throw 'C_LITE_REUSE_FINGERPRINT'}
            if($evidence.Source.Url -cne $Document.Url -or $evidence.Source.Format -cne 'HTML' -or $evidence.Source.ContentHash -cne $snapshot.ContentHash -or
                $ep.Sources.Count -ne 1 -or $ep.Sources[0].SourceUrl -cne $Document.Url -or $ep.Sources[0].SourceFormat -cne 'HTML' -or $ep.Sources[0].ContentHash -cne $snapshot.ContentHash){throw 'C_LITE_REUSE_PAYLOAD_MISMATCH'}

            $er=@($baseArtifacts|Where-Object {$_.Reference.Kind -ceq 'BENEFIT_EVIDENCE_PROJECTION'})[0]
            $sr=@($baseArtifacts|Where-Object {$_.Reference.Kind -ceq 'BENEFIT_SEMANTIC_PROJECTION'})[0]
            $ar=@($baseArtifacts|Where-Object {$_.Reference.Kind -ceq 'BENEFIT_SCOPED_EVIDENCE'})[0]

            $identity=$RunId+'|'+$BusinessId+'|BENEFIT|REUSED|'+$prev.ObservationId+'|'+$ObservedAt
            $oid='obs-'+(Get-HistorySha256 $identity).Substring(0,32)
            if($oid -ceq $prev.ObservationId -or $oid -ceq $evidence.Capture.ObservationId){throw 'C_LITE_REUSE_OBSERVATION_ID'}

            $prevCheckpoint=[pscustomobject][ordered]@{ContractType='BenefitIncrementalPayloadCheckpoint';ContractVersion=1;SourceUrl=$evidence.Source.Url;SourceFormat='HTML';ContentHash=$evidence.Source.ContentHash}
            $currCheckpoint=[pscustomobject][ordered]@{ContractType='BenefitIncrementalPayloadCheckpoint';ContractVersion=1;SourceUrl=$Document.Url;SourceFormat='HTML';ContentHash=$snapshot.ContentHash}
            $decision=[pscustomobject][ordered]@{
                ContractType='BenefitReuseDecision';ContractVersion=2;ProcessingMode='REUSED_IDENTICAL_EVIDENCE'
                ReusedFromObservationId=$prev.ObservationId;Capability='POST_FETCH'
                PreviousPayloadCheckpoint=$prevCheckpoint;CurrentPayloadCheckpoint=$currCheckpoint
                InputMatch=$true;ExecutionMatch=$true;PayloadMatch=$true;RepositoryClean=$true;PreviousComparable=$true;ReuseApplied=$true
                ReasonCodes=@('REUSE_ELIGIBLE')
                OwnerObservationId=$oid;OwnerRunId=$RunId;BusinessId=$BusinessId;ScopedEvidenceReference=$ar.Reference
            }
            Assert-BenefitReuseDecisionV2 $decision
            $dj=ConvertTo-HistoryCanonicalJson $decision
            Assert-BenefitScopedEvidenceBundleSize -ScopedJson $ar.Text -EvidenceJson $er.Text -SemanticJson $sr.Text -ReuseDecisionJson $dj
            $drHash=Get-HistorySha256 $dj
            $dr=New-HistoryArtifactReference -Kind 'BENEFIT_REUSE_DECISION' -ContentHash $drHash -RelativePath ('artifacts/sha256/'+$drHash+'.json')
            $preparedDecision=[pscustomobject]@{ContentHash=$drHash;Extension='json';Kind='BENEFIT_REUSE_DECISION';Text=$dj}

            $o=New-HistoryObservation -ObservationId $oid -RunId $RunId -BusinessId $BusinessId -Domain 'BENEFIT' -ObservedAt $ObservedAt -OperationalStatus 'COMPLETE' -Comparable $true -InputFingerprint $prev.InputFingerprint -EvidenceFingerprint $prev.EvidenceFingerprint -SemanticFingerprint $prev.SemanticFingerprint -ExecutionFingerprint $prev.ExecutionFingerprint -ArtifactReferences @($er.Reference,$sr.Reference,$ar.Reference,$dr) -SemanticResultReference $sr.Reference.RelativePath -NonComparableReasons @()
            $comparison=Compare-BenefitHistoryObservations -Store $Store -Previous $prev -Current $o -StagedCurrentSemanticProjection $sp
            if($comparison.ComparisonStatus -cne 'COMPLETE' -or $comparison.DeltaDimensions.Count -ne 0 -or $comparison.ChangeCandidates.Count -ne 0 -or $comparison.ReasonCodes.Count -ne 0){throw 'C_LITE_REUSE_COMPARISON'}
            Assert-ObservationComparison $comparison
            Assert-InternalScopedReuseOwner $decision $o $evidence

            Assert-InternalScopedFilesUnchanged -Store $Store -Entries @(
                @{Path=$prevRecord.ObservationPath;MaxBytes=65536;Text=$prevRecord.ObservationText},
                @{Path=$prevRecord.ManifestPath;MaxBytes=16777216;Text=$prevRecord.ManifestText}
            )
            return [pscustomobject]@{Status='READY';ReasonCode='C_LITE_REUSE_PACKAGE_READY';Package=[pscustomobject]@{Observation=$o;PreparedArtifacts=@($preparedDecision);Comparison=$comparison;ReuseDecision=$decision}}
        } *>&1)
        if($output.Count -ne 1 -or $output[0] -isnot [pscustomobject]){throw 'C_LITE_HISTORY_OUTPUT'}
        return $output[0]
    }catch{return [pscustomobject]@{Status='REJECTED';ReasonCode='C_LITE_REUSE_PACKAGE_REJECTED';Package=$null}}
}

function Read-BenefitScopedHtmlCommittedReuse {
    param($Store,$ObservationId)
    $ErrorActionPreference='Stop'
    try{
        $output=@(& {
            Assert-InternalScopedHistoryStore $Store
            $curr=Read-InternalScopedCommittedRecord -Store $Store -ObservationId $ObservationId -ExpectedArtifactCount 4
            $o=$curr.Observation;$manifest=$curr.Manifest
            $artifacts=@(foreach($ref in $o.ArtifactReferences){
                if($ref.Kind -cnotin @('BENEFIT_EVIDENCE_PROJECTION','BENEFIT_SEMANTIC_PROJECTION','BENEFIT_SCOPED_EVIDENCE','BENEFIT_REUSE_DECISION')){throw 'C_LITE_HISTORY_ARTIFACT_KIND'}
                $max=if($ref.Kind -ceq 'BENEFIT_REUSE_DECISION'){16384}else{65536}
                $item=Read-InternalScopedArtifactItem -Store $Store -Ref $ref -MaxBytes $max
                [pscustomobject]@{Reference=$item.Reference;Text=$item.Text}
            })
            $nodes=ConvertFrom-InternalScopedHtmlArtifacts -Observation $o -Artifacts $artifacts -IncludeReuse
            $captureId=$nodes.Evidence.Capture.ObservationId
            if($captureId -ceq $o.ObservationId){throw 'C_LITE_REUSE_SELF_CAPTURE'}
            $cap=Read-InternalScopedCommittedRecord -Store $Store -ObservationId $captureId -ExpectedArtifactCount 3
            foreach($kind in @('BENEFIT_EVIDENCE_PROJECTION','BENEFIT_SEMANTIC_PROJECTION','BENEFIT_SCOPED_EVIDENCE')){
                $capRef=@($cap.Observation.ArtifactReferences|Where-Object Kind -CEQ $kind)
                $curRef=@($o.ArtifactReferences|Where-Object Kind -CEQ $kind)
                if($capRef.Count -ne 1 -or $curRef.Count -ne 1 -or (ConvertTo-HistoryCanonicalJson $capRef[0]) -cne (ConvertTo-HistoryCanonicalJson $curRef[0])){throw 'C_LITE_REUSE_CAPTURE_REF_MISMATCH'}
            }
            $prevId=$nodes.ReuseDecision.ReusedFromObservationId
            if($prevId -ceq $o.ObservationId){throw 'C_LITE_REUSE_SELF_PREVIOUS'}
            $prevReuseDecision=$null
            if($prevId -ceq $captureId){
                $prev=$cap
            }else{
                $prev=Read-InternalScopedCommittedRecord -Store $Store -ObservationId $prevId -ExpectedArtifactCount 4
                foreach($kind in @('BENEFIT_EVIDENCE_PROJECTION','BENEFIT_SEMANTIC_PROJECTION','BENEFIT_SCOPED_EVIDENCE')){
                    $capRef=@($cap.Observation.ArtifactReferences|Where-Object Kind -CEQ $kind)
                    $prevRef=@($prev.Observation.ArtifactReferences|Where-Object Kind -CEQ $kind)
                    if($capRef.Count -ne 1 -or $prevRef.Count -ne 1 -or (ConvertTo-HistoryCanonicalJson $capRef[0]) -cne (ConvertTo-HistoryCanonicalJson $prevRef[0])){throw 'C_LITE_REUSE_PREV_REF_MISMATCH'}
                }
                $prevDecRefs=@($prev.Observation.ArtifactReferences|Where-Object Kind -CEQ 'BENEFIT_REUSE_DECISION')
                if($prevDecRefs.Count -ne 1){throw 'C_LITE_REUSE_PREV_DECISION'}
                $prevDecItem=Read-InternalScopedArtifactItem -Store $Store -Ref $prevDecRefs[0] -MaxBytes 16384
                $prevReuseDecision=$prevDecItem.Value
                Assert-BenefitReuseDecisionV2 $prevReuseDecision
                if((ConvertTo-HistoryCanonicalJson $prevReuseDecision) -cne $prevDecItem.Text){throw 'C_LITE_HISTORY_CANONICAL'}
            }
            if($manifest.RepositoryRevision -cne $cap.Manifest.RepositoryRevision -or $prev.Manifest.RepositoryRevision -cne $cap.Manifest.RepositoryRevision){throw 'C_LITE_REUSE_REVISION'}
            $comparisonId=New-HistoryComparisonId -RunId $o.RunId -BusinessId $o.BusinessId -Domain 'BENEFIT' -PreviousObservationId $prev.Observation.ObservationId -CurrentObservationId $o.ObservationId
            Assert-InternalScopedHistoryFileToken $comparisonId
            $comparisonPath=Get-HistoryComparisonPath -Store $Store -ComparisonId $comparisonId
            $comparisonFile=Read-InternalScopedHistoryFile -Store $Store -Path $comparisonPath -MaxBytes 65536
            $comparison=$comparisonFile.Value
            if($comparison.ComparisonId -cne $comparisonId){throw 'C_LITE_REUSE_COMPARISON_ID'}
            Assert-BenefitScopedReuseRelationship -Decision $nodes.ReuseDecision -Current $o -CurrentManifest $manifest -Previous $prev.Observation -PreviousManifest $prev.Manifest -CaptureObservation $cap.Observation -CaptureManifest $cap.Manifest -Evidence $nodes.Evidence -EvidenceProjection $nodes.EvidenceProjection -SemanticProjection $nodes.SemanticProjection -Comparison $comparison -PreviousReuseDecision $prevReuseDecision
            $checkEntries=@(
                @{Path=$curr.ObservationPath;MaxBytes=65536;Text=$curr.ObservationText},
                @{Path=$curr.ManifestPath;MaxBytes=16777216;Text=$curr.ManifestText},
                @{Path=$cap.ObservationPath;MaxBytes=65536;Text=$cap.ObservationText},
                @{Path=$cap.ManifestPath;MaxBytes=16777216;Text=$cap.ManifestText},
                @{Path=$comparisonPath;MaxBytes=65536;Text=$comparisonFile.Text}
            )
            if($prevId -cne $captureId){
                $checkEntries+=@(
                    @{Path=$prev.ObservationPath;MaxBytes=65536;Text=$prev.ObservationText},
                    @{Path=$prev.ManifestPath;MaxBytes=16777216;Text=$prev.ManifestText}
                )
            }
            Assert-InternalScopedFilesUnchanged -Store $Store -Entries $checkEntries
            return [pscustomobject]@{Status='VERIFIED';ReasonCode='C_LITE_COMMITTED_REUSE_VERIFIED';Reuse=[pscustomobject]@{Observation=$o;Artifacts=$artifacts;Comparison=$comparison;ReuseDecision=$nodes.ReuseDecision;OwnerObservationId=$cap.Observation.ObservationId}}
        } *>&1)
        if($output.Count -ne 1 -or $output[0] -isnot [pscustomobject]){throw 'C_LITE_HISTORY_OUTPUT'}
        return $output[0]
    }catch{return [pscustomobject]@{Status='REJECTED';ReasonCode='C_LITE_COMMITTED_REUSE_REJECTED';Reuse=$null}}
}

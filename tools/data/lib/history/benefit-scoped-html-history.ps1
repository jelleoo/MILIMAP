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
    param($Observation,$Artifacts)
    Assert-InternalScopedArray $Observation.ArtifactReferences 3
    Assert-InternalScopedArray $Artifacts 3
    if($Artifacts.Count -ne 3 -or $Observation.ArtifactReferences.Count -ne 3){throw 'C_LITE_HISTORY_ARTIFACT_COUNT'}
    $nodes=[ordered]@{Evidence=$null;EvidenceProjection=$null;SemanticProjection=$null}
    foreach($pair in @(
        @{Kind='BENEFIT_EVIDENCE_PROJECTION';Key='EvidenceProjection';Paths=@('Sources','Sources[].CandidateReferences')},
        @{Kind='BENEFIT_SEMANTIC_PROJECTION';Key='SemanticProjection';Paths=@('Claims','Claims[].MaterialReasonCodes','MaterialReasonCodes')},
        @{Kind='BENEFIT_SCOPED_EVIDENCE';Key='Evidence';Paths=@()}
    )){
        $items=@($Artifacts|Where-Object {$_.Reference.Kind -ceq $pair.Kind})
        $refs=@($Observation.ArtifactReferences|Where-Object Kind -CEQ $pair.Kind)
        if($items.Count -ne 1 -or $refs.Count -ne 1){throw 'C_LITE_HISTORY_ARTIFACT_KIND'}
        $item=$items[0]
        Assert-InternalScopedObject $item @('Reference','Text')
        Assert-InternalScopedReference $item.Reference $pair.Kind
        Assert-InternalScopedReference $refs[0] $pair.Kind
        if((ConvertTo-HistoryCanonicalJson $item.Reference) -cne (ConvertTo-HistoryCanonicalJson $refs[0])){throw 'C_LITE_HISTORY_REFERENCE'}
        Assert-InternalScopedString $item.Text 65536
        $bytes=[Text.UTF8Encoding]::new($false,$true).GetBytes($item.Text)
        if((Get-BenefitEvidenceByteHash $bytes) -cne $item.Reference.ContentHash){throw 'C_LITE_HISTORY_HASH'}
        $node=ConvertFrom-BenefitScopedEvidenceJson $item.Text
        if((ConvertTo-HistoryCanonicalJson $node -OrderInsensitivePaths $pair.Paths) -cne $item.Text){throw 'C_LITE_HISTORY_CANONICAL'}
        $nodes[$pair.Key]=$node
    }
    Assert-BenefitScopedEvidence $nodes.Evidence
    Assert-InternalScopedProjectionLinks $Observation $nodes.EvidenceProjection $nodes.SemanticProjection
    $aj=@($Artifacts|Where-Object {$_.Reference.Kind -ceq 'BENEFIT_SCOPED_EVIDENCE'})[0].Text
    $ej=@($Artifacts|Where-Object {$_.Reference.Kind -ceq 'BENEFIT_EVIDENCE_PROJECTION'})[0].Text
    $sj=@($Artifacts|Where-Object {$_.Reference.Kind -ceq 'BENEFIT_SEMANTIC_PROJECTION'})[0].Text
    Assert-BenefitScopedEvidenceBundleSize -ScopedJson $aj -EvidenceJson $ej -SemanticJson $sj
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

function Read-BenefitScopedHtmlCommittedCapture {
    param($Store,$ObservationId)
    $ErrorActionPreference='Stop'
    try{
        $output=@(& {
            Assert-InternalScopedHistoryStore $Store
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
            if($o.ArtifactReferences.Count -ne 3){throw 'C_LITE_HISTORY_ARTIFACT_COUNT'}
            $artifacts=@(foreach($ref in $o.ArtifactReferences){
                if($ref.Kind -cnotin @('BENEFIT_EVIDENCE_PROJECTION','BENEFIT_SEMANTIC_PROJECTION','BENEFIT_SCOPED_EVIDENCE')){throw 'C_LITE_HISTORY_ARTIFACT_KIND'}
                Assert-InternalScopedReference $ref $ref.Kind
                $path=Get-HistoryArtifactPath -Store $Store -ContentHash $ref.ContentHash -Extension 'json'
                if((Get-HistoryRelativePath -Store $Store -FullPath $path) -cne $ref.RelativePath){throw 'C_LITE_HISTORY_REFERENCE'}
                $file=Read-InternalScopedHistoryFile -Store $Store -Path $path -MaxBytes 65536
                if((Get-BenefitEvidenceByteHash $file.Bytes) -cne $ref.ContentHash){throw 'C_LITE_HISTORY_HASH'}
                [pscustomobject]@{Reference=$ref;Text=$file.Text}
            })
            $nodes=ConvertFrom-InternalScopedHtmlArtifacts -Observation $o -Artifacts $artifacts
            Assert-BenefitScopedEvidenceRelationship -Evidence $nodes.Evidence -Observation $o -RunManifest $manifest -EvidenceProjection $nodes.EvidenceProjection -SemanticProjection $nodes.SemanticProjection
            # Immutable records must still be the same at the end of this scan;
            # a mismatch rejects this attempt rather than triggering a retry.
            $againObservation=Read-InternalScopedHistoryFile -Store $Store -Path $observationPath -MaxBytes 65536
            $againManifest=Read-InternalScopedHistoryFile -Store $Store -Path $manifestPath -MaxBytes 16777216
            if($againObservation.Text -cne $observationFile.Text -or $againManifest.Text -cne $manifestFile.Text){throw 'C_LITE_HISTORY_CHANGED_DURING_READ'}
            return [pscustomobject]@{Status='VERIFIED';ReasonCode='C_LITE_COMMITTED_VERIFIED';Capture=[pscustomobject]@{Observation=$o;Artifacts=$artifacts}}
        } *>&1)
        if($output.Count -ne 1 -or $output[0] -isnot [pscustomobject]){throw 'C_LITE_HISTORY_OUTPUT'}
        return $output[0]
    }catch{return [pscustomobject]@{Status='REJECTED';ReasonCode='C_LITE_COMMITTED_REJECTED';Capture=$null}}
}

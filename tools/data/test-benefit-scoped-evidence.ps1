$ErrorActionPreference='Stop'
$module=Join-Path $PSScriptRoot 'lib/history/benefit-scoped-evidence.ps1'
if(-not (Test-Path -LiteralPath $module)){ throw 'RED: inactive C-Lite contract module is missing' }
. $module
$script:checks=0
function Check($Condition,$Name){ if(-not $Condition){throw "FAIL: $Name"}; $script:checks++ }
function Reject([scriptblock]$Action,$Name){$caught=$false;try{& $Action | Out-Null}catch{$caught=$true};Check $caught $Name}
function Copy-Case($Value){ConvertFrom-Json ($Value|ConvertTo-Json -Depth 60 -Compress) -Depth 60 -DateKind String}
$revision='ef2a2b6e50f884778c92d64e93337e3e0b838cda'
$legacy=ConvertTo-BenefitHistoryExecutionProjection -RepositoryRevision $revision
$lite=ConvertTo-BenefitHistoryExecutionProjection -RepositoryRevision $revision -ExecutionConfiguration ([pscustomobject]@{HtmlEvidenceRetentionProfile='C_LITE_V1'})
Check ((Get-BenefitRetentionProfileCandidate -ExecutionFingerprint (Get-HistoryFingerprint $legacy) -RepositoryRevision $revision) -ceq 'LEGACY') 'known exact Legacy descriptor'
Check ((Get-BenefitRetentionProfileCandidate -ExecutionFingerprint (Get-HistoryFingerprint $lite) -RepositoryRevision $revision) -ceq 'C_LITE_V1') 'known exact C-Lite descriptor'
Check ((Get-BenefitRetentionProfileCandidate -ExecutionFingerprint ('f'*64) -RepositoryRevision $revision) -ceq 'PROFILE_UNKNOWN') 'unknown descriptor never defaults Legacy'
$other=Copy-Case $lite;$other.Configuration | Add-Member Unknown 1
Check ((Get-BenefitRetentionProfileCandidate -ExecutionFingerprint (Get-HistoryFingerprint $other) -RepositoryRevision $revision) -ceq 'PROFILE_UNKNOWN') 'unsupported execution configuration'
Check ((Get-BenefitRetentionProfileCandidate -ExecutionFingerprint (Get-HistoryFingerprint $lite) -RepositoryRevision ('a'*40)) -ceq 'PROFILE_UNKNOWN') 'mismatched manifest revision'
Reject {ConvertFrom-BenefitScopedEvidenceJson '{"ContractType":"x","ContractType":"y"}'} 'duplicate property rejected before deserialization'
Reject {ConvertFrom-BenefitScopedEvidenceJson '{"x":{"a":1,"a":2}}'} 'nested duplicate property rejected'
Reject {ConvertFrom-BenefitScopedEvidenceJson '{"x":1,"X":2}'} 'case-colliding property rejected'
Reject {ConvertFrom-BenefitScopedEvidenceJson '{"x":1,}'} 'malformed JSON rejected'
$parsed=ConvertFrom-BenefitScopedEvidenceJson '{"ObservedAt":"2026-10-27T08:00:00.000+09:00","empty":[],"nil":null}'
Check ($parsed.ObservedAt -is [string] -and $parsed.ObservedAt -ceq '2026-10-27T08:00:00.000+09:00') 'timestamp lexical identity preserved'
Check ($parsed.empty -is [array] -and $parsed.empty.Count -eq 0 -and $null -eq $parsed.nil) 'empty array differs from null'
Write-Host "PASS: C-Lite contracts ($script:checks checks)"

# Fictional physical HTML fixture; no live source, store preparation or History publication.
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-location/test-support.ps1')
function Ref($Kind,$Projection,[string[]]$Paths=@()){
    $hash=Get-HistorySha256 (ConvertTo-HistoryCanonicalJson -Value $Projection -OrderInsensitivePaths $Paths)
    New-HistoryArtifactReference -Kind $Kind -ContentHash $hash -RelativePath "artifacts/sha256/$hash.json"
}
. (Join-Path $PSScriptRoot 'lib/benefit-evidence/find-business-evidence-slice.ps1')
function New-TestQualified {
    $doc=New-ScopeTestDocument
    $candidate=New-BenefitSourceCandidate -SourceRowNumber 2 -Url $doc.Url -SourceKind PUBLIC_OFFICIAL
    New-QualifiedBenefitSource -Candidate $candidate -Document $doc -OfficialityStatus VERIFIED_OFFICIAL
}
function New-Case {
    $f=New-ScopeContractFixture;$f.Slice=(Find-BenefitBusinessEvidence -Observation $f.Observation -Business (New-ScopeTestBusiness)).Slices[0]
    $x=New-ExtractedBenefitClaim -ClaimType BENEFIT_DESCRIPTION -Value $f.Slice.StructuredFields.BenefitDescription -EvidenceText $f.Slice.StructuredFields.BenefitDescription -EvidenceReference $f.Slice.FieldReferences.BenefitDescription.FieldReference -SourceUrl $f.Document.Url -ExtractionMethod SCOPED_HTML_CELL
    $v=Test-ScopedBenefitExtractedClaim -Claim $x -Document $f.Document -EvidenceSlice $f.Slice
    $verification=New-BenefitClaimVerification -ClaimType BENEFIT_DESCRIPTION -EvidenceValue $v.Value -Result CONFIRMED -ValidatedClaim $v
    $result=New-BenefitVerificationResult -SourceRowNumber 2 -BusinessIdentity (New-ScopeTestBusiness) -BenefitState NEEDS_VERIFICATION -ReviewClass YELLOW -ClaimResults @($verification) -ProductionAction NONE
    $diag=[pscustomobject]@{Url=$f.Document.Url;FetchStatus='COMPLETE';AdapterStatus='COMPLETE';SourceFormat='HTML';ContentHash=$f.Snapshot.ContentHash;AdapterId='HTML_GENERIC';AdapterVersion='1';LocationOperationalStatus='COMPLETE';LocationStatus='LOCATED';CandidateReferences=@($f.Slice.EvidenceReference);OfficialityStatus='VERIFIED_OFFICIAL';BusinessBindingStatus='STRONG'}
    $ep=ConvertTo-BenefitHistoryEvidenceProjection @($diag)
    $sp=ConvertTo-BenefitHistorySemanticProjection -Result $result -EvidenceDiagnostics @($diag)
    $er=Ref BENEFIT_EVIDENCE_PROJECTION $ep @('Sources','Sources[].CandidateReferences')
    $sr=Ref BENEFIT_SEMANTIC_PROJECTION $sp @('Claims','Claims[].MaterialReasonCodes','MaterialReasonCodes')
    $efp=Get-HistoryFingerprint $ep -OrderInsensitivePaths @('Sources','Sources[].CandidateReferences')
    $sfp=Get-HistoryFingerprint $sp -OrderInsensitivePaths @('Claims','Claims[].MaterialReasonCodes','MaterialReasonCodes')
    $xfp=Get-HistoryFingerprint $lite
    $biz='biz-0123456789abcdef0123456789abcdef';$run='run-capture'
    $ifp='a'*64
    $oid='obs-'+(Get-HistorySha256 ($run+'|'+$biz+'|BENEFIT|'+$ifp+'|'+$efp+'|'+$sfp+'|'+$xfp)).Substring(0,32)
    $o=New-HistoryObservation -ObservationId $oid -RunId $run -BusinessId $biz -Domain BENEFIT -ObservedAt '2026-10-27T08:00:00.000+09:00' -OperationalStatus COMPLETE -Comparable $true -InputFingerprint $ifp -EvidenceFingerprint $efp -SemanticFingerprint $sfp -ExecutionFingerprint $xfp -ArtifactReferences @($er,$sr) -SemanticResultReference $sr.RelativePath
    $manifest=New-HistoryRunManifest -RunId $run -StartedAt $o.ObservedAt -CompletedAt $o.ObservedAt -RepositoryRevision $revision -RequestedBusinessIds @($biz) -CompletedBusinessIds @($biz) -ExecutionStatus COMPLETE -RunCommitStatus COMMITTED
    $fields=@(foreach($key in @('BusinessName','Address','BenefitDescription')){
        $r=$f.Slice.FieldReferences[$key]
        [pscustomobject]@{Key=$key;HeaderText=$r.OriginalHeader;DecodedValue=$f.Slice.StructuredFields[$key];HeaderStart=$r.HeaderStart;HeaderLength=$r.HeaderLength;CellStart=$r.CellStart;CellLength=$r.CellLength;FieldReference=$r.FieldReference}
    })
    $a=[pscustomobject]@{
        ContractType='BenefitScopedEvidence';ContractVersion=1;RetentionProfile='C_LITE_V1';Mode='LOCATED_FIELDS';BusinessId=$biz
        Capture=[pscustomobject]@{ObservationId=$oid;RunId=$run;ObservedAt=$o.ObservedAt;SourceRowNumber=2}
        Links=[pscustomobject]@{InputFingerprint=$ifp;EvidenceFingerprint=$efp;SemanticFingerprint=$sfp;ExecutionFingerprint=$xfp;EvidenceArtifactReference=$er;SemanticArtifactReference=$sr}
        Source=[pscustomobject]@{Url=$f.Snapshot.SourceUrl;Format='HTML';ContentHash=$f.Snapshot.ContentHash;HashKind='HTML_TEXT_UTF8_SHA256';SnapshotId=$f.Snapshot.SnapshotId;ObservedAt=$f.Snapshot.ObservedAt;TextLengthUtf16=$f.Snapshot.Text.Length}
        Adapter=[pscustomobject]@{Id='HTML_GENERIC';Version='1'}
        Outcome=[pscustomobject]@{ObservationOperationalStatus='COMPLETE';Comparable=$true;FetchStatus='COMPLETE';OfficialityStatus='VERIFIED_OFFICIAL';AdapterStatus='COMPLETE';LocationOperationalStatus='COMPLETE';LocationStatus='LOCATED';BindingStatus='STRONG';ExtractionStatus='COMPLETE';ValidationStatus='COMPLETE';CoverageKind='ADAPTER_SUPPORTED_TABLE_ROWS';ContentUnitCount=2;CandidateReferences=@($f.Slice.EvidenceReference);CandidateReferenceCount=1;IdentityEvidenceCodes=@($f.Slice.IdentityEvidence);ReasonCodes=@();ClaimValidationCounts=[pscustomobject]@{Total=1;Validated=1;Invalid=0;Conflict=0;Unknown=0}}
        Scope=[pscustomobject]@{Type='TABLE_ROW';Reference=$f.Slice.EvidenceReference;TableStart=$f.Slice.TableStart;TableLength=$f.Slice.TableLength;RowStart=$f.Slice.RawStart;RowLength=$f.Slice.RawLength}
        Fields=$fields
        Claims=@([pscustomobject]@{ClaimType='BENEFIT_DESCRIPTION';FieldKey='BenefitDescription';EvidenceReference=$v.EvidenceReference;ExtractionMethod='SCOPED_HTML_CELL';ValidationStatus='VALIDATED';SemanticClaimOrdinal=0})
    }
    $ar=Ref BENEFIT_SCOPED_EVIDENCE $a;$o.ArtifactReferences+=@($ar)
    [pscustomobject]@{Artifact=$a;Reference=$ar;Observation=$o;Manifest=$manifest;EvidenceProjection=$ep;SemanticProjection=$sp;Fixture=$f;Extracted=@($x);Validated=@($v);Result=$result}
}
$c=New-Case
Assert-BenefitScopedEvidence $c.Artifact
Check (Test-BenefitScopedEvidenceReuseEligible $c.Artifact) 'complete validated scoped evidence eligible'
foreach($mutation in @(
    {param($a)$a.ContractVersion='1'}, {param($a)$a.ContractVersion=1.0}, {param($a)$a.ContractVersion=$true},
    {param($a)$a.Outcome.Comparable='true'}, {param($a)$a.Source.ObservedAt=[datetime]::Now},
    {param($a)$a.Capture.SourceRowNumber=1}, {param($a)$a.Source.Format='XLSX'},
    {param($a)$a.Source.SnapshotId='f'*64}, {param($a)$a.Source.HashKind='WIRE_BYTES'},
    {param($a)$a|Add-Member RawFragment '<html>forbidden</html>'},
    {param($a)$a.Fields[0]|Add-Member Bytes @(1,2)},
    {param($a)$a.Fields=$null}, {param($a)$a.Claims=$a.Claims[0]},
    {param($a)$a.Outcome.CandidateReferenceCount=0},
    {param($a)$a.Outcome.ContentUnitCount='2'},
    {param($a)$a.Outcome.ClaimValidationCounts.Total=2},
    {param($a)$a.Claims+=@($a.Claims[0])}, {param($a)$a.Fields+=@($a.Fields[0])},
    {param($a)$a.Claims[0].FieldKey='Address'},
    {param($a)$a.Fields[0].HeaderLength=[long]::MaxValue},
    {param($a)$a.Fields[0].CellStart=$a.Scope.RowStart-1},
    {param($a)$a.Fields[0].FieldReference='OTHER/BusinessName'},
    {param($a)$a.Outcome.LocationOperationalStatus='PARTIAL'},
    {param($a)$a.Outcome.ValidationStatus='PARTIAL'},
    {param($a)$a.Outcome.ClaimValidationCounts.Invalid=1},
    {param($a)$a.Source.Url='https://user:pass@example.invalid/'},
    {param($a)$a.Outcome.ReasonCodes=@('<html>raw error</html>')}
)){
    $a=Copy-Case $c.Artifact;& $mutation $a
    Reject {Assert-BenefitScopedEvidence $a} ('strict evidence mutation '+$mutation.ToString())
}
foreach($status in @('PARTIAL','FAILED')){
    $a=Copy-Case $c.Artifact;$a.Mode='OUTCOME_ONLY';$a.Scope=$null;$a.Fields=@();$a.Claims=@();$a.Outcome.ValidationStatus=$status
    $a.Outcome.ClaimValidationCounts=[pscustomobject]@{Total=2;Validated=1;Invalid=1;Conflict=0;Unknown=0}
    Assert-BenefitScopedEvidence $a
    Check (-not (Test-BenefitScopedEvidenceReuseEligible $a)) 'mixed validation may remain History comparable but cannot reuse'
}
$a=Copy-Case $c.Artifact;$a.Mode='OUTCOME_ONLY';$a.Scope=$null;$a.Fields=@();$a.Claims=@();$a.Outcome.LocationStatus='NOT_FOUND';$a.Outcome.BindingStatus='AMBIGUOUS';$a.Outcome.ExtractionStatus='FAILED';$a.Outcome.ValidationStatus='FAILED';$a.Outcome.ClaimValidationCounts=[pscustomobject]@{Total=0;Validated=0;Invalid=0;Conflict=0;Unknown=0}
Assert-BenefitScopedEvidence $a
Check (-not (Test-BenefitScopedEvidenceReuseEligible $a)) 'absence receipt never shortcut eligible'
$a.Outcome.ContentUnitCount=$null;$a.Outcome.CandidateReferenceCount=$null;$a.Outcome.CandidateReferences=@();$a.Outcome.ClaimValidationCounts=$null
Assert-BenefitScopedEvidence $a
Check ($null -eq $a.Outcome.ContentUnitCount) 'unobserved count remains null'
Write-Host "PASS: C-Lite evidence shapes ($script:checks checks)"

Assert-BenefitScopedEvidenceRelationship -Evidence $c.Artifact -Observation $c.Observation -RunManifest $c.Manifest -EvidenceProjection $c.EvidenceProjection -SemanticProjection $c.SemanticProjection
$cap=@{Evidence=$c.Artifact;Document=$c.Fixture.Document;EvidenceSlice=$c.Fixture.Slice;Extraction=[pscustomobject]@{Status='COMPLETE';SourceRowNumber=2;Claims=$c.Extracted};Validation=[pscustomobject]@{Status='COMPLETE';SourceRowNumber=2;Claims=$c.Validated};Result=$c.Result}
Assert-BenefitScopedEvidenceCapture -SourceObservation $c.Fixture.Observation -Business (New-ScopeTestBusiness) -QualifiedSource (New-TestQualified) @cap
foreach($mutation in @(
    {param($k)$k.Evidence.Fields[0].DecodedValue='another business'},
    {param($k)$k.Extraction.Claims+=@($k.Extraction.Claims[0])},
    {param($k)$k.Validation.Claims+=@($k.Validation.Claims[0])},
    {param($k)$k.Validation.Claims[0].EvidenceReference='other/cell'},
    {param($k)$k.Validation.Claims[0].Value='wrong value'},
    {param($k)$k.Validation.Claims[0].ExtractionMethod='SCOPED_XLSX_CELL'},
    {param($k)$k.Result.ClaimResults[0].EvidenceValue='wrong value'},
    {param($k)$k.Result.ClaimResults+=@($k.Result.ClaimResults[0])},
    {param($k)$k.Evidence.Claims[0].SemanticClaimOrdinal=1},
    {param($k)$k.Evidence.Source.ContentHash='b'*64},
    {param($k)$k.Document.SourceRowNumber=3}
)){
    $k=Copy-Case ([pscustomobject]$cap);$k.EvidenceSlice=$c.Fixture.Slice;$baselineArgs=@{};foreach($p in $k.PSObject.Properties){$baselineArgs[$p.Name]=$p.Value};Assert-BenefitScopedEvidenceCapture -SourceObservation $c.Fixture.Observation -Business (New-ScopeTestBusiness) -QualifiedSource (New-TestQualified) @baselineArgs;& $mutation $k
    $callParameters=@{};foreach($p in $k.PSObject.Properties){$callParameters[$p.Name]=$p.Value}
    Reject {Assert-BenefitScopedEvidenceCapture -SourceObservation $c.Fixture.Observation -Business (New-ScopeTestBusiness) -QualifiedSource (New-TestQualified) @callParameters} 'claim/source tamper rejected'
}
# A persisted artifact alone cannot prove that an excerpt was in a deleted original HTML.
# Relationships are checked against supplied immutable E/S records, never by fabricating an HTML document.
foreach($target in @('BusinessId','ObservationId','RunId','ObservedAt','InputFingerprint','ExecutionFingerprint','SemanticResultReference')){
    $o=Copy-Case $c.Observation
    switch($target){
        'BusinessId' {$o.BusinessId='biz-'+('f'*32)}
        'ObservedAt' {$o.ObservedAt='2026-10-28T00:00:00Z'}
        {$_ -in @('InputFingerprint','ExecutionFingerprint')} {$o.$target='f'*64}
        default {$o.$target='changed'}
    }
    Reject {Assert-BenefitScopedEvidenceRelationship -Evidence $c.Artifact -Observation $o -RunManifest $c.Manifest -EvidenceProjection $c.EvidenceProjection -SemanticProjection $c.SemanticProjection} "capture relationship $target"
}
foreach($mutation in @(
    {param($m)$m.RunId='other-run'}, {param($m)$m.RepositoryRevision='f'*40},
    {param($m)$m.RunCommitStatus='PREPARED'}, {param($m)$m.CompletedBusinessIds=@()},
    {param($m)$m.RequestedBusinessIds=@()}, {param($m)$m.FingerprintSchemaVersion=2}
)){
    $m=Copy-Case $c.Manifest;& $mutation $m
    Reject {Assert-BenefitScopedEvidenceRelationship -Evidence $c.Artifact -Observation $c.Observation -RunManifest $m -EvidenceProjection $c.EvidenceProjection -SemanticProjection $c.SemanticProjection} 'manifest tamper rejected'
}
$o=Copy-Case $c.Observation;$o.ArtifactReferences=@($o.ArtifactReferences|Where-Object Kind -cne BENEFIT_SCOPED_EVIDENCE)
Reject {Assert-BenefitRetentionArtifactRequirements -Observation $o -RunManifest $c.Manifest -EvidenceProjection $c.EvidenceProjection -SemanticProjection $c.SemanticProjection} 'deleting mandatory scoped ref cannot downgrade profile'
$o.ExecutionFingerprint=Get-HistoryFingerprint $legacy
Check ((Assert-BenefitRetentionArtifactRequirements -Observation $o -RunManifest $c.Manifest -EvidenceProjection $c.EvidenceProjection -SemanticProjection $c.SemanticProjection) -ceq 'LEGACY') 'Legacy remains readable without new reference'
$o.ExecutionFingerprint='f'*64
Reject {Assert-BenefitRetentionArtifactRequirements -Observation $o -RunManifest $c.Manifest -EvidenceProjection $c.EvidenceProjection -SemanticProjection $c.SemanticProjection} 'unknown profile not eligible for trusted artifact handling'
# Frozen descriptor is independent of future mutable script version constants.
$oldVersion=$script:BenefitHistoryAdapterVersion
try{$script:BenefitHistoryAdapterVersion=99;Check ((Get-BenefitRetentionProfileCandidate -ExecutionFingerprint (Get-HistoryFingerprint $lite) -RepositoryRevision $revision) -ceq 'C_LITE_V1') 'historical descriptor never uses current version globals'}finally{$script:BenefitHistoryAdapterVersion=$oldVersion}
Write-Host "PASS: C-Lite capture links ($script:checks checks)"

function New-ReuseCase($Capture){
    $current=Copy-Case $Capture.Observation;$current.RunId='run-reuse';$current.ObservedAt='2026-10-27T09:00:00+09:00'
    $current.ObservationId='obs-'+(Get-HistorySha256 ($current.RunId+'|'+$current.BusinessId+'|BENEFIT|REUSED|'+$Capture.Observation.ObservationId+'|'+$current.ObservedAt)).Substring(0,32)
    $checkpoint=[pscustomobject]@{ContractType='BenefitIncrementalPayloadCheckpoint';ContractVersion=1;SourceUrl=$Capture.Artifact.Source.Url;SourceFormat='HTML';ContentHash=$Capture.Artifact.Source.ContentHash}
    $d=[pscustomobject]@{
        ContractType='BenefitReuseDecision';ContractVersion=2;ProcessingMode='REUSED_IDENTICAL_EVIDENCE';ReusedFromObservationId=$Capture.Observation.ObservationId
        Capability='POST_FETCH';PreviousPayloadCheckpoint=$checkpoint;CurrentPayloadCheckpoint=(Copy-Case $checkpoint)
        InputMatch=$true;ExecutionMatch=$true;PayloadMatch=$true;RepositoryClean=$true;PreviousComparable=$true;ReuseApplied=$true;ReasonCodes=@('REUSE_ELIGIBLE')
        OwnerObservationId=$current.ObservationId;OwnerRunId=$current.RunId;BusinessId=$current.BusinessId;ScopedEvidenceReference=$Capture.Reference
    }
    $current.ArtifactReferences+=@(Ref BENEFIT_REUSE_DECISION $d)
    $manifest=Copy-Case $Capture.Manifest;$manifest.RunId=$current.RunId;$manifest.StartedAt=$current.ObservedAt;$manifest.CompletedAt=$current.ObservedAt
    $comparison=New-ObservationComparison -ComparisonId comparison-reuse -RunId $current.RunId -BusinessId $current.BusinessId -Domain BENEFIT -PreviousObservationId $Capture.Observation.ObservationId -CurrentObservationId $current.ObservationId -ComparisonStatus COMPLETE
    [pscustomobject]@{Decision=$d;Current=$current;CurrentManifest=$manifest;Previous=$Capture.Observation;PreviousManifest=$Capture.Manifest;CaptureObservation=$Capture.Observation;CaptureManifest=$Capture.Manifest;Evidence=$Capture.Artifact;EvidenceProjection=$Capture.EvidenceProjection;SemanticProjection=$Capture.SemanticProjection;Comparison=$comparison}
}
$r=New-ReuseCase $c
function Reuse-Args($Object){$splat=@{};foreach($p in $Object.PSObject.Properties){$splat[$p.Name]=$p.Value};return $splat}
$callParameters=Reuse-Args $r
Assert-BenefitScopedReuseRelationship @callParameters
foreach($mutation in @(
    {param($r)$r.Decision.ContractVersion=1}, {param($r)$r.Decision.ReuseApplied='true'},
    {param($r)$r.Decision.PayloadMatch=$false}, {param($r)$r.Decision.OwnerObservationId='other'},
    {param($r)$r.Decision.OwnerRunId='other'}, {param($r)$r.Decision.BusinessId='biz-'+('f'*32)},
    {param($r)$r.Decision.ScopedEvidenceReference.ContentHash='f'*64},
    {param($r)$r.Decision.CurrentPayloadCheckpoint.ContentHash='f'*64},
    {param($r)$r.Decision.PreviousPayloadCheckpoint.SourceUrl='https://other.invalid/'},
    {param($r)$r.Decision.ReusedFromObservationId='other'},
    {param($r)$r.Previous.Comparable=$false}, {param($r)$r.Current.InputFingerprint='f'*64},
    {param($r)$r.Current.ObservedAt=$r.Previous.ObservedAt;$r.Current.RunId=$r.Previous.RunId},
    {param($r)$r.Comparison.PreviousObservationId='other'},
    {param($r)$r.Comparison.ChangeCandidates=@('BENEFIT_DETAIL_CHANGED')},
    {param($r)$r.Comparison.DeltaDimensions=@('SEMANTIC')},
    {param($r)$r.Current.ArtifactReferences+=@($r.Current.ArtifactReferences[-1])},
    {param($r)$r.Decision|Add-Member RawSource 'forbidden'},
    {param($r)$r.CaptureManifest.RepositoryRevision='f'*40}
)){
    $m=Copy-Case $r;& $mutation $m;$callParameters=Reuse-Args $m
    Reject {Assert-BenefitScopedReuseRelationship @callParameters} 'reuse ownership/tamper rejected'
}
# Type-specific limits are checked on the canonical artifacts as well as raw JSON input.
Assert-InternalScopedString ('x'*256) 256
Reject {Assert-InternalScopedString ('x'*257) 256} 'header UTF8 size ceiling independent of alias eligibility'
foreach($case in @(@{Property='DecodedValue';Limit=4096})){
    $a=Copy-Case $c.Artifact;$a.Fields[0].($case.Property)='x'*$case.Limit
    Assert-BenefitScopedEvidence $a
    $a.Fields[0].($case.Property)+='x'
    Reject {Assert-BenefitScopedEvidence $a} 'per-field UTF8 exact boundary'
}
$a=Copy-Case $c.Artifact;$a.Fields[0].DecodedValue='한'*1365
Assert-BenefitScopedEvidence $a
$a.Fields[0].DecodedValue+='한';Reject {Assert-BenefitScopedEvidence $a} 'UTF8 bytes not character count'
$exact='{"x":"'+('a'*(65536-8))+'"}'
Check ([Text.Encoding]::UTF8.GetByteCount($exact) -eq 65536) 'JSON boundary fixture exact size'
$null=ConvertFrom-BenefitScopedEvidenceJson $exact
Reject {ConvertFrom-BenefitScopedEvidenceJson ($exact+' ')} 'JSON bytes bound plus one'
Assert-BenefitScopedEvidenceBundleSize -ScopedJson (' ' * 65536) -EvidenceJson (' ' * 65536) -SemanticJson (' ' * 65536)
Reject {Assert-BenefitScopedEvidenceBundleSize -ScopedJson (' '*65536) -EvidenceJson (' '*65536) -SemanticJson (' '*65536) -ReuseDecisionJson 'x'} 'prepared aggregate 192KiB bound'
Reject {Assert-BenefitScopedEvidenceBundleSize -ScopedJson '{}' -EvidenceJson '{}' -SemanticJson '{}' -ReuseDecisionJson (' '*16385)} 'reuse audit 16KiB bound'
Write-Host "PASS: C-Lite reuse and sizes ($script:checks checks)"

# Consistent edits to both owner and receipt must still respect the existing observation-id formula.
$m=New-Case;$m.Observation.ObservationId='obs-'+('f'*32);$m.Artifact.Capture.ObservationId=$m.Observation.ObservationId
$m.Observation.ArtifactReferences[-1]=Ref BENEFIT_SCOPED_EVIDENCE $m.Artifact
Reject {Assert-BenefitScopedEvidenceRelationship -Evidence $m.Artifact -Observation $m.Observation -RunManifest $m.Manifest -EvidenceProjection $m.EvidenceProjection -SemanticProjection $m.SemanticProjection} 'self-consistent forged capture identity'
# Reuse stored canonical claim ordinals, never the incoming in-memory iteration order.
$m=New-Case;$m.Artifact.Fields[0].HeaderText='혜택';$m.Observation.ArtifactReferences[-1]=Ref BENEFIT_SCOPED_EVIDENCE $m.Artifact
Reject {Assert-BenefitScopedEvidence $m.Artifact} 'header/key substitution uses existing map'

$legacyObservation=Copy-Case $c.Observation;$legacyObservation.ExecutionFingerprint=Get-HistoryFingerprint $legacy
$legacyObservation.ArtifactReferences=@($legacyObservation.ArtifactReferences|Where-Object Kind -cne BENEFIT_SCOPED_EVIDENCE)
$legacyObservation.ArtifactReferences+=@(New-HistoryArtifactReference -Kind RAW_SOURCE_PAYLOAD -ContentHash ('a'*64) -RelativePath ('artifacts/sha256/'+('a'*64)+'.html'))
Check ((Assert-BenefitRetentionArtifactRequirements -Observation $legacyObservation -RunManifest $c.Manifest -EvidenceProjection $c.EvidenceProjection -SemanticProjection $c.SemanticProjection) -ceq 'LEGACY') 'existing Legacy RAW html reference remains readable'

# Additional outcome, unknown-count, JSON, and cardinality controls.
Reject {ConvertFrom-BenefitScopedEvidenceJson '{"Mode":1,"\u004dode":2}'} 'escaped duplicate JSON property'
Reject {ConvertFrom-BenefitScopedEvidenceJson '{"a":NaN}'} 'non-JSON number rejected'
$a=Copy-Case $c.Artifact;$a.PSObject.Properties.Remove('Mode');$a|Add-Member mode LOCATED_FIELDS
Reject {Assert-BenefitScopedEvidence $a} 'exact property casing'
$a=Copy-Case $c.Artifact;$a.Outcome.ClaimValidationCounts=[pscustomobject]@{Total=0;Validated=0;Invalid=0;Conflict=0;Unknown=0};$a.Claims=@();$a.Fields=@($a.Fields|Where-Object Key -cne BenefitDescription)
Assert-BenefitScopedEvidence $a
Check (-not (Test-BenefitScopedEvidenceReuseEligible $a)) 'identity-only scoped evidence not initially reuse eligible'
foreach($state in @('AMBIGUOUS','PARTIAL','UNSUPPORTED','FAILED')){
    $a=Copy-Case $c.Artifact;$a.Mode='OUTCOME_ONLY';$a.Scope=$null;$a.Fields=@();$a.Claims=@()
    if($state -ceq 'AMBIGUOUS'){$a.Outcome.LocationStatus=$state;$a.Outcome.BindingStatus='AMBIGUOUS'}else{$a.Outcome.LocationOperationalStatus=$state;$a.Outcome.LocationStatus=$null;$a.Outcome.AdapterStatus=$state;$a.Outcome.ObservationOperationalStatus=$(if($state -ceq 'FAILED'){'FAILED'}else{'PARTIAL'});$a.Outcome.Comparable=$false}
    $a.Outcome.ExtractionStatus='FAILED';$a.Outcome.ValidationStatus='FAILED';$a.Outcome.ClaimValidationCounts=[pscustomobject]@{Total=0;Validated=0;Invalid=0;Conflict=0;Unknown=0}
    Assert-BenefitScopedEvidence $a
    Check (-not (Test-BenefitScopedEvidenceReuseEligible $a)) "outcome $state cannot reuse or imply absence"
}
$a.Outcome.CandidateReferences=@(1..16|ForEach-Object {"HTML_TABLE_1_ROW_$_"});$a.Outcome.CandidateReferenceCount=16
Assert-BenefitScopedEvidence $a
$a.Outcome.CandidateReferences+=@('HTML_TABLE_1_ROW_17');$a.Outcome.CandidateReferenceCount=17
Reject {Assert-BenefitScopedEvidence $a} 'candidate bound cannot truncate'
# Fetch failure has no source snapshot; rebind real E/S fingerprint and artifact hashes, not fake counts.
$failed=Copy-Case $c
$failed.Observation.OperationalStatus='FAILED';$failed.Observation.Comparable=$false;$failed.Observation.NonComparableReasons=@('SOURCE_FETCH_NOT_COMPLETE','SOURCE_CONTENT_HASH_MISSING')
$failed.EvidenceProjection.Sources[0].ContentHash='';$failed.EvidenceProjection.Sources[0].SourceFormat='UNSUPPORTED'
$failed.SemanticProjection.BusinessPresence='UNKNOWN';$failed.SemanticProjection.AbsenceEligible=$false;$failed.SemanticProjection.Claims=@()
$failed.Observation.EvidenceFingerprint=Get-HistoryFingerprint $failed.EvidenceProjection -OrderInsensitivePaths @('Sources','Sources[].CandidateReferences')
$failed.Observation.SemanticFingerprint=Get-HistoryFingerprint $failed.SemanticProjection -OrderInsensitivePaths @('Claims','Claims[].MaterialReasonCodes','MaterialReasonCodes')
$failed.Observation.ArtifactReferences=@((Ref BENEFIT_EVIDENCE_PROJECTION $failed.EvidenceProjection @('Sources','Sources[].CandidateReferences')),(Ref BENEFIT_SEMANTIC_PROJECTION $failed.SemanticProjection @('Claims','Claims[].MaterialReasonCodes','MaterialReasonCodes')))
$failed.Observation.SemanticResultReference=$failed.Observation.ArtifactReferences[1].RelativePath
Check ((Assert-BenefitRetentionArtifactRequirements -Observation $failed.Observation -RunManifest $failed.Manifest -EvidenceProjection $failed.EvidenceProjection -SemanticProjection $failed.SemanticProjection) -ceq 'C_LITE_V1') 'failed fetch no-receipt exception remains C-Lite'
$failed.Observation.Comparable=$true
Reject {Assert-BenefitRetentionArtifactRequirements -Observation $failed.Observation -RunManifest $failed.Manifest -EvidenceProjection $failed.EvidenceProjection -SemanticProjection $failed.SemanticProjection} 'no artifact fetch failure cannot be comparable'
# Profile recognition is not execution qualification: unknown revisions are not reversed from a hash.
$unknown=ConvertTo-BenefitHistoryExecutionProjection -RepositoryRevision ('1'*40) -ExecutionConfiguration ([pscustomobject]@{HtmlEvidenceRetentionProfile='C_LITE_V1'})
Check ((Get-BenefitRetentionProfileCandidate -ExecutionFingerprint (Get-HistoryFingerprint $unknown) -RepositoryRevision ('1'*40)) -ceq 'C_LITE_V1') 'known descriptor shape on unknown revision is only a candidate'
$unknown.Configuration=[pscustomobject]@{Future=1}
Check ((Get-BenefitRetentionProfileCandidate -ExecutionFingerprint (Get-HistoryFingerprint $unknown) -RepositoryRevision ('1'*40)) -ceq 'PROFILE_UNKNOWN') 'unknown historical descriptor is not Legacy'
# Module load must never activate existing production paths; fail immediately if a writer/transport is called.
$called=0
function Write-HistoryArtifact {$script:called++;throw 'no I/O allowed'}
function Prepare-HistoryRun {$script:called++;throw 'no I/O allowed'}
function Commit-HistoryRun {$script:called++;throw 'no I/O allowed'}
function Invoke-WebRequest {$script:called++;throw 'no I/O allowed'}
. $module
Check ($called -eq 0) 'inactive load invokes no transport or History writer'
Write-Host "PASS: outcome controls ($script:checks assertions; operational HTTP=0; History publications=0)"

# Complete scoped evidence cannot cherry-pick the one valid claim from a mixed semantic projection.
$unlinked=New-Case
$extra=New-BenefitClaimVerification -ClaimType ELIGIBLE_TARGET -EvidenceValue 'fictional unvalidated target' -Result UNKNOWN
$unlinked.Result.ClaimResults+=@($extra)
$diagnostic=[pscustomobject]@{Url=$unlinked.Artifact.Source.Url;FetchStatus='COMPLETE';OfficialityStatus='VERIFIED_OFFICIAL';AdapterStatus='COMPLETE';LocationOperationalStatus='COMPLETE';LocationStatus='LOCATED';BusinessBindingStatus='STRONG'}
$unlinked.SemanticProjection=ConvertTo-BenefitHistorySemanticProjection -Result $unlinked.Result -EvidenceDiagnostics @($diagnostic)
$sr=Ref BENEFIT_SEMANTIC_PROJECTION $unlinked.SemanticProjection @('Claims','Claims[].MaterialReasonCodes','MaterialReasonCodes')
$unlinked.Observation.ArtifactReferences[1]=$sr;$unlinked.Observation.SemanticResultReference=$sr.RelativePath
$unlinked.Observation.SemanticFingerprint=Get-HistoryFingerprint $unlinked.SemanticProjection -OrderInsensitivePaths @('Claims','Claims[].MaterialReasonCodes','MaterialReasonCodes')
$unlinked.Artifact.Links.SemanticFingerprint=$unlinked.Observation.SemanticFingerprint;$unlinked.Artifact.Links.SemanticArtifactReference=$sr
$o=$unlinked.Observation;$o.ObservationId='obs-'+(Get-HistorySha256 ($o.RunId+'|'+$o.BusinessId+'|BENEFIT|'+$o.InputFingerprint+'|'+$o.EvidenceFingerprint+'|'+$o.SemanticFingerprint+'|'+$o.ExecutionFingerprint)).Substring(0,32)
$unlinked.Artifact.Capture.ObservationId=$o.ObservationId
$canonical=ConvertFrom-BenefitScopedEvidenceJson (ConvertTo-HistoryCanonicalJson $unlinked.SemanticProjection -OrderInsensitivePaths @('Claims','Claims[].MaterialReasonCodes','MaterialReasonCodes'))
$unlinked.Artifact.Claims[0].SemanticClaimOrdinal=@(for($i=0;$i -lt $canonical.Claims.Count;$i++){if($canonical.Claims[$i].ClaimType -ceq 'BENEFIT_DESCRIPTION'){$i}})[0]
$unlinked.Reference=Ref BENEFIT_SCOPED_EVIDENCE $unlinked.Artifact;$o.ArtifactReferences[2]=$unlinked.Reference
$badCap=@{Evidence=$unlinked.Artifact;Document=$unlinked.Fixture.Document;EvidenceSlice=$unlinked.Fixture.Slice;Extraction=[pscustomobject]@{Status='COMPLETE';SourceRowNumber=2;Claims=$unlinked.Extracted};Validation=[pscustomobject]@{Status='COMPLETE';SourceRowNumber=2;Claims=$unlinked.Validated};Result=$unlinked.Result}
Reject {Assert-BenefitScopedEvidenceCapture -SourceObservation $c.Fixture.Observation -Business (New-ScopeTestBusiness) -QualifiedSource (New-TestQualified) @badCap} 'unlinked semantic claim cannot be hidden behind valid subset at capture'
Reject {Assert-BenefitScopedEvidenceRelationship -Evidence $unlinked.Artifact -Observation $unlinked.Observation -RunManifest $unlinked.Manifest -EvidenceProjection $unlinked.EvidenceProjection -SemanticProjection $unlinked.SemanticProjection} 'unlinked semantic claim cannot qualify persisted receipt'
$badReuse=Reuse-Args (New-ReuseCase $unlinked)
Reject {Assert-BenefitScopedReuseRelationship @badReuse} 'mixed semantic projection cannot reuse'

foreach($mutation in @(
    {param($m)$m.RunId=@($m.RunId)}, {param($m)$m.StartedAt=[datetime]'2026-10-27'},
    {param($m)$m.CompletedAt=[datetime]'2026-10-27'}, {param($m)$m.ExecutionStatus=@('COMPLETE')}
)){
    $m=Copy-Case $c.Manifest;& $mutation $m
    Reject {Assert-BenefitScopedEvidenceRelationship -Evidence $c.Artifact -Observation $c.Observation -RunManifest $m -EvidenceProjection $c.EvidenceProjection -SemanticProjection $c.SemanticProjection} 'manifest scalar types never coerced'
}
$m=New-ReuseCase $c;$m.Comparison.ComparisonId=@('comparison-reuse');$callParameters=Reuse-Args $m
Reject {Assert-BenefitScopedReuseRelationship @callParameters} 'comparison scalar ID never coerced'


$m=Copy-Case (New-Case)
$m.Result.ClaimResults[0].Result='UNKNOWN';$m.Result.ClaimResults[0].ValidatedClaim.ValidationStatus='UNKNOWN'
$sp=ConvertTo-BenefitHistorySemanticProjection -Result $m.Result -EvidenceDiagnostics @($diagnostic)
$m.Artifact.Links.SemanticFingerprint=Get-HistoryFingerprint $sp -OrderInsensitivePaths @('Claims','Claims[].MaterialReasonCodes','MaterialReasonCodes')
$m.Artifact.Links.SemanticArtifactReference=Ref BENEFIT_SEMANTIC_PROJECTION $sp @('Claims','Claims[].MaterialReasonCodes','MaterialReasonCodes')
$badCap=@{Evidence=$m.Artifact;Document=$m.Fixture.Document;EvidenceSlice=$c.Fixture.Slice;Extraction=[pscustomobject]@{Status='COMPLETE';SourceRowNumber=2;Claims=$m.Extracted};Validation=[pscustomobject]@{Status='COMPLETE';SourceRowNumber=2;Claims=$m.Validated};Result=$m.Result}
Reject {Assert-BenefitScopedEvidenceCapture -SourceObservation $c.Fixture.Observation -Business (New-ScopeTestBusiness) -QualifiedSource (New-TestQualified) @badCap} 'Result embedded UNKNOWN validation cannot inherit validated stage status'



# Even content-bound records must agree on existing domain presence/absence semantics.
$m=New-Case;$m.SemanticProjection.BusinessPresence='ABSENT';$m.SemanticProjection.AbsenceEligible=$true
$sr=Ref BENEFIT_SEMANTIC_PROJECTION $m.SemanticProjection @('Claims','Claims[].MaterialReasonCodes','MaterialReasonCodes')
$m.Observation.ArtifactReferences[1]=$sr;$m.Observation.SemanticResultReference=$sr.RelativePath
$m.Observation.SemanticFingerprint=Get-HistoryFingerprint $m.SemanticProjection -OrderInsensitivePaths @('Claims','Claims[].MaterialReasonCodes','MaterialReasonCodes')
$m.Artifact.Links.SemanticArtifactReference=$sr;$m.Artifact.Links.SemanticFingerprint=$m.Observation.SemanticFingerprint
$o=$m.Observation;$o.ObservationId='obs-'+(Get-HistorySha256 ($o.RunId+'|'+$o.BusinessId+'|BENEFIT|'+$o.InputFingerprint+'|'+$o.EvidenceFingerprint+'|'+$o.SemanticFingerprint+'|'+$o.ExecutionFingerprint)).Substring(0,32)
$m.Artifact.Capture.ObservationId=$o.ObservationId;$o.ArtifactReferences[2]=Ref BENEFIT_SCOPED_EVIDENCE $m.Artifact
Reject {Assert-BenefitScopedEvidenceRelationship -Evidence $m.Artifact -Observation $m.Observation -RunManifest $m.Manifest -EvidenceProjection $m.EvidenceProjection -SemanticProjection $m.SemanticProjection} 'LOCATED strong evidence cannot assert semantic absence'

Write-Host "PASS: final C-Lite contract assertions=$script:checks"

# A third observation reuses the same immutable capture without a recursive history walk.
$third=New-ReuseCase $c
$third.Previous=$r.Current;$third.PreviousManifest=$r.CurrentManifest
$third.Current.RunId='run-third';$third.Current.ObservedAt='2026-10-27T10:00:00+09:00'
$third.Decision.ReusedFromObservationId=$third.Previous.ObservationId
$third.Current.ObservationId='obs-'+(Get-HistorySha256 ($third.Current.RunId+'|'+$third.Current.BusinessId+'|BENEFIT|REUSED|'+$third.Previous.ObservationId+'|'+$third.Current.ObservedAt)).Substring(0,32)
$third.Decision.OwnerObservationId=$third.Current.ObservationId;$third.Decision.OwnerRunId=$third.Current.RunId
$third.Current.ArtifactReferences=@($third.Current.ArtifactReferences|Where-Object Kind -cne BENEFIT_REUSE_DECISION)+@(Ref BENEFIT_REUSE_DECISION $third.Decision)
$third.CurrentManifest.RunId=$third.Current.RunId;$third.CurrentManifest.StartedAt=$third.Current.ObservedAt;$third.CurrentManifest.CompletedAt=$third.Current.ObservedAt
$third.Comparison.RunId=$third.Current.RunId;$third.Comparison.PreviousObservationId=$third.Previous.ObservationId;$third.Comparison.CurrentObservationId=$third.Current.ObservationId
$callParameters=Reuse-Args $third
Reject {Assert-BenefitScopedReuseRelationship @callParameters} 'later reuse requires owned previous v2 proof'
$callParameters.PreviousReuseDecision=$r.Decision
Assert-BenefitScopedReuseRelationship @callParameters
Check ($third.Evidence.Capture.RunId -ceq $c.Observation.RunId) 'later reuse preserves original capture ownership'
Write-Host "PASS: final C-Lite contract assertions=$script:checks"

# Approved correction: complete positives cannot discard physical evidence.
$d=New-Case;$d.Artifact.Mode='OUTCOME_ONLY';$d.Artifact.Scope=$null;$d.Artifact.Fields=@();$d.Artifact.Claims=@()
$d.Observation.ArtifactReferences[2]=Ref BENEFIT_SCOPED_EVIDENCE $d.Artifact
Reject {Assert-BenefitScopedEvidence $d.Artifact} 'complete-positive downgrade rejected at shape'
Reject {Assert-BenefitScopedEvidenceCapture -SourceObservation $c.Fixture.Observation -Business (New-ScopeTestBusiness) -QualifiedSource (New-TestQualified) -Evidence $d.Artifact -Document $d.Fixture.Document -EvidenceSlice $d.Fixture.Slice -Extraction ([pscustomobject]@{Status='COMPLETE';SourceRowNumber=2;Claims=$d.Extracted}) -Validation ([pscustomobject]@{Status='COMPLETE';SourceRowNumber=2;Claims=$d.Validated}) -Result $d.Result} 'complete-positive downgrade rejected at capture'
Reject {Assert-BenefitScopedEvidenceRelationship -Evidence $d.Artifact -Observation $d.Observation -RunManifest $d.Manifest -EvidenceProjection $d.EvidenceProjection -SemanticProjection $d.SemanticProjection} 'rehashed downgrade rejected at relationship'

# Minimal retained fields are verified against a re-derived full-source locator result.
function Capture-Args($case,$phone='',$business=(New-ScopeTestBusiness)){
    @{Evidence=$case.Artifact;Document=$case.Fixture.Document;EvidenceSlice=$case.Fixture.Slice;Extraction=[pscustomobject]@{Status='COMPLETE';SourceRowNumber=2;Claims=$case.Extracted};Validation=[pscustomobject]@{Status='COMPLETE';SourceRowNumber=2;Claims=$case.Validated};Result=$case.Result;SourceObservation=$case.Fixture.Observation;Business=$business;QualifiedSource=(New-TestQualified);CanonicalPhone=$phone}
}
$m=New-Case;$callParameters=Capture-Args $m
Assert-BenefitScopedEvidenceCapture @callParameters
Check ($m.Artifact.Fields.Key -cnotcontains 'Phone') 'unused source Phone omitted from valid capture'
foreach($key in @('BusinessName','Address','BenefitDescription')){
 $a=Copy-Case $m.Artifact;$a.Fields=@($a.Fields|Where-Object Key -cne $key)
 Reject {Assert-BenefitScopedEvidence $a} "required retained field $key"
}
$extra=New-ScopeContractFixture
$phoneRef=$extra.Slice.FieldReferences.Phone
$phoneField=[pscustomobject]@{Key='Phone';HeaderText=$phoneRef.OriginalHeader;DecodedValue=$extra.Slice.StructuredFields.Phone;HeaderStart=$phoneRef.HeaderStart;HeaderLength=$phoneRef.HeaderLength;CellStart=$phoneRef.CellStart;CellLength=$phoneRef.CellLength;FieldReference=$phoneRef.FieldReference}
$m.Artifact.Fields+=@($phoneField)
Reject {Assert-BenefitScopedEvidence $m.Artifact} 'arbitrary extra Phone without identity or claim forbidden'
$m.Artifact.Outcome.IdentityEvidenceCodes+=@('PHONE_MATCH')
$m.Fixture.Slice=(Find-BenefitBusinessEvidence -Observation $m.Fixture.Observation -Business (New-ScopeTestBusiness) -CanonicalPhone '02-0000-0012').Slices[0]
$callParameters=Capture-Args $m '02-0000-0012'
Assert-BenefitScopedEvidenceCapture @callParameters
Check $true 'actual PHONE_MATCH retains Phone and captures'
$a=Copy-Case $m.Artifact;$a.Fields=@($a.Fields|Where-Object Key -cne Phone)
Reject {Assert-BenefitScopedEvidence $a} 'PHONE_MATCH requires Phone'
$callParameters.CanonicalPhone='02-0000-9999'
Reject {Assert-BenefitScopedEvidenceCapture @callParameters} 'omitted fields cannot hide full-source phone conflict'
$callParameters=Capture-Args $m ''
Reject {Assert-BenefitScopedEvidenceCapture @callParameters} 'forged PHONE_MATCH not established by trusted canonical input'
$m=New-Case;$m.Artifact.Outcome.IdentityEvidenceCodes=@('FULL_NAME_MATCH');$m.Artifact.Fields=@($m.Artifact.Fields|Where-Object Key -cne Address)
$callParameters=Capture-Args $m
Reject {Assert-BenefitScopedEvidenceCapture @callParameters} 'omitted identity code rejected against trusted locator'
$m=New-Case;$m.Artifact.Outcome.IdentityEvidenceCodes+=@('BRANCH_MATCH')
Reject {Assert-BenefitScopedEvidence $m.Artifact} 'BRANCH_MATCH requires Branch'
Write-Host "PASS: approved correction assertions=$script:checks"

# Zero-claim complete identity evidence still needs its physical identity fields, never reuse.
$z=New-Case;$z.Artifact.Claims=@();$z.Artifact.Fields=@($z.Artifact.Fields|Where-Object Key -cne BenefitDescription)
$z.Artifact.Outcome.ClaimValidationCounts=[pscustomobject]@{Total=0;Validated=0;Invalid=0;Conflict=0;Unknown=0};$z.Result.ClaimResults=@()
$diag=Get-InternalScopedPresenceDiagnostic $z.Artifact
$sp=ConvertTo-BenefitHistorySemanticProjection -Result $z.Result -EvidenceDiagnostics @($diag)
$z.Artifact.Links.SemanticFingerprint=Get-HistoryFingerprint $sp -OrderInsensitivePaths @('Claims','Claims[].MaterialReasonCodes','MaterialReasonCodes')
$z.Artifact.Links.SemanticArtifactReference=Ref BENEFIT_SEMANTIC_PROJECTION $sp @('Claims','Claims[].MaterialReasonCodes','MaterialReasonCodes')
$callParameters=Capture-Args $z;$callParameters.Extraction.Claims=@();$callParameters.Validation.Claims=@()
Assert-BenefitScopedEvidenceCapture @callParameters
Check (-not (Test-BenefitScopedEvidenceReuseEligible $z.Artifact)) 'complete zero-claim identity capture not reuse eligible'
$z.Artifact.Mode='OUTCOME_ONLY';$z.Artifact.Scope=$null;$z.Artifact.Fields=@()
Reject {Assert-BenefitScopedEvidence $z.Artifact} 'zero-claim complete positive cannot downgrade'
# Actual branch identity uses the existing parser/locator/binding, with no new fixture file.
. (Join-Path $PSScriptRoot 'lib/benefit-evidence/convert-html-source-observation.ps1')
$b=New-Case;$business=New-ScopeTestBusiness;$business.BranchName='테스트점';$b.Result.BusinessIdentity=Copy-Case $business
$html=(Get-ScopeTestHtml).Replace('<th>할인</th>','<th>할인</th><th>지점</th>').Replace('<td>10% 할인</td>','<td>10% 할인</td><td>테스트점</td>').Replace('<td>30% 할인</td>','<td>30% 할인</td><td>다른점</td>')
$doc=New-ScopeTestDocument -Html $html;$obs=ConvertTo-BenefitHtmlObservation -Document $doc
$slice=(Find-BenefitBusinessEvidence -Observation $obs -Business $business).Slices[0]
$b.Fixture.Document=$doc;$b.Fixture.Observation=$obs;$b.Fixture.Slice=$slice
$b.Artifact.Source.ContentHash=$obs.Snapshot.ContentHash;$b.Artifact.Source.SnapshotId=$obs.SnapshotId;$b.Artifact.Source.TextLengthUtf16=$html.Length
$b.Artifact.Outcome.IdentityEvidenceCodes=@($slice.IdentityEvidence)
$b.Artifact.Scope=[pscustomobject]@{Type='TABLE_ROW';Reference=$slice.EvidenceReference;TableStart=$slice.TableStart;TableLength=$slice.TableLength;RowStart=$slice.RawStart;RowLength=$slice.RawLength}
$b.Artifact.Fields=@(foreach($key in @('BusinessName','Address','Branch','BenefitDescription')){$ref=$slice.FieldReferences[$key];[pscustomobject]@{Key=$key;HeaderText=$ref.OriginalHeader;DecodedValue=$slice.StructuredFields[$key];HeaderStart=$ref.HeaderStart;HeaderLength=$ref.HeaderLength;CellStart=$ref.CellStart;CellLength=$ref.CellLength;FieldReference=$ref.FieldReference}})
$callParameters=Capture-Args $b '' $business
$candidate=New-BenefitSourceCandidate -SourceRowNumber 2 -Url $doc.Url -SourceKind PUBLIC_OFFICIAL
$callParameters.QualifiedSource=New-QualifiedBenefitSource -Candidate $candidate -Document $doc -OfficialityStatus VERIFIED_OFFICIAL
Assert-BenefitScopedEvidenceCapture @callParameters
Check ($slice.IdentityEvidence -ccontains 'BRANCH_MATCH') 'actual BRANCH_MATCH capture includes required Branch'
$business.BranchName='잘못된점';$b.Result.BusinessIdentity=Copy-Case $business
try{Assert-BenefitScopedEvidenceCapture @callParameters;throw 'EXPECTED_BRANCH_CONFLICT'}catch{Check ($_.Exception.Message -ceq 'C_LITE_TRUSTED_LOCATION') 'full source branch conflict reaches existing locator gate'}
Write-Host "PASS: final corrected C-Lite assertions=$script:checks"

$m=New-Case;$callParameters=Capture-Args $m
$callParameters.SourceObservation.SourceRowNumber=3;$callParameters.Business=New-ScopeTestBusiness -RowNumber 3
$callParameters.QualifiedSource.SourceRowNumber=3;$callParameters.QualifiedSource.Candidate.SourceRowNumber=3;$callParameters.QualifiedSource.Document.SourceRowNumber=3
Reject {Assert-BenefitScopedEvidenceCapture @callParameters} 'trusted locator inputs cannot switch physical canonical row'
$m=New-Case;$callParameters=Capture-Args $m;$callParameters.Result.BusinessIdentity=New-ScopeTestBusiness -Name '다른 합성 업소' -Building 99
Reject {Assert-BenefitScopedEvidenceCapture @callParameters} 'Result identity must equal the actual locator business'

Write-Host "PASS: complete corrected contract suite assertions=$script:checks"

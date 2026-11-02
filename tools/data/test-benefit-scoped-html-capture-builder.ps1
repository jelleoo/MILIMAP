$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-location/test-support.ps1')
. (Join-Path $PSScriptRoot 'lib/benefit-evidence/invoke-scoped-benefit-source.ps1')
$builderPath=Join-Path $PSScriptRoot 'lib/history/benefit-scoped-html-capture-builder.ps1'
if(Test-Path -LiteralPath $builderPath){. $builderPath}
$script:BuilderChecks=0
function Check-Builder([bool]$Condition,[string]$Label){
    if(-not $Condition){throw "FAIL: $Label"};$script:BuilderChecks++
}
function New-BuilderFixture([string]$Html=(Get-ScopeTestHtml),[string]$Name='테스트가게 A',[string]$Building='12'){
    $context=New-BenefitSourceRunContext
    $business=New-ScopeTestBusiness -Name $Name -Building $Building
    $candidate=New-BenefitSourceCandidate -SourceRowNumber 2 -Url 'https://city.example.go.kr/list' -SourceKind PUBLIC_OFFICIAL
    $request={param($Uri)[pscustomobject]@{StatusCode=200;ContentType='text/html';Text=$Html;Bytes=$null}}.GetNewClosure()
    $record=Invoke-ScopedPhase2BenefitSourceCandidate -Candidate $candidate -Business $business -RunContext $context -RequestInvoker $request
    $claims=@(foreach($validated in $record.Validation.Claims){
        New-BenefitClaimVerification -ClaimType $validated.ClaimType -EvidenceValue $validated.Value -Result UNKNOWN -ValidatedClaim $validated
    })
    $result=New-BenefitVerificationResult -SourceRowNumber 2 -BusinessIdentity $business -BenefitState NEEDS_VERIFICATION -ReviewClass YELLOW -ClaimResults $claims -ProductionAction NONE
    $benefit=New-CanonicalBenefitRecord -SourceRowNumber 2 -BusinessName $Name -BenefitDescription '10% 할인' -ExistingSourceType '지자체 공식 자료' -ExistingSourceUrl $candidate.Url
    return @{
        RunContext=$context;SourceRecord=$record;Benefit=$benefit;BusinessId='biz-0123456789abcdef0123456789abcdef'
        BusinessIdentity=$business;CanonicalPhone='';Result=$result
        OperationalStatus=[pscustomobject]@{DiscoveryStatus='COMPLETE';ExtractionStatus=$record.Extraction.Status}
        RunId='run-clite-builder';ObservedAt='2026-11-01T09:00:00.000+09:00';RepositoryRevision=('a'*40)
    }
}

function Get-BuilderEvidence($Built){
    ConvertFrom-BenefitScopedEvidenceJson (@($Built.Candidate.Artifacts|Where-Object {$_.Reference.Kind -ceq 'BENEFIT_SCOPED_EVIDENCE'})[0].Text)
}
function Expect-BuilderRejected($Parameters,[string]$Label){
    $output=@(New-BenefitScopedHtmlCaptureCandidate @Parameters *>&1)
    Check-Builder ($output.Count -eq 1 -and $output[0].Status -ceq 'REJECTED' -and $null -eq $output[0].Candidate) $Label
    Check-Builder ($output[0].ReasonCode -cmatch '^[A-Z0-9_]{1,64}$') "$Label bounded reason"
}

# AC01: a missing builder (or one returning an empty/default receipt) must fail.
$fixture=New-BuilderFixture
Check-Builder ([bool](Get-Command New-BenefitScopedHtmlCaptureCandidate -ErrorAction SilentlyContinue)) 'AC01 builder public function exists'
$built=New-BenefitScopedHtmlCaptureCandidate @fixture
Check-Builder ($built.Status -ceq 'READY' -and $null -ne $built.Candidate) 'AC01 complete real pipeline produces READY'
$scoped=Get-BuilderEvidence $built
Check-Builder ($scoped.Mode -ceq 'LOCATED_FIELDS' -and $scoped.Fields.Count -eq 3 -and $scoped.Claims.Count -eq 1) 'AC01 exact minimal positive fields'

# AC02: complete identity-only must never be downgraded to a receipt.
$identity=New-BuilderFixture -Html ((Get-ScopeTestHtml).Replace('10% 할인','').Replace('30% 할인',''))
$value=New-BenefitScopedHtmlCaptureCandidate @identity
Check-Builder ($value.Status -ceq 'READY') 'AC02 identity-only READY'
$e=Get-BuilderEvidence $value
Check-Builder ($e.Mode -ceq 'LOCATED_FIELDS' -and $e.Claims.Count -eq 0 -and -not (Test-BenefitScopedEvidenceReuseEligible $e)) 'AC02 zero-claim is not reusable'

# AC03/04: validation failures remain receipts; never publish the valid subset.
foreach($status in @('UNKNOWN','INVALID','CONFLICT')){
    $p=New-BuilderFixture
    $p.SourceRecord.Validation.Status='PARTIAL';$p.SourceRecord.Validation.Claims[0].ValidationStatus=$status
    $p.Result.ClaimResults[0].ValidatedClaim.ValidationStatus=$status
    $b=New-BenefitScopedHtmlCaptureCandidate @p
    Check-Builder ($b.Status -ceq 'READY' -and (Get-BuilderEvidence $b).Mode -ceq 'OUTCOME_ONLY') "AC03/04 $status receipt"
}

# AC04/14: two actual fields, canonical ordinals independent of Result order.
$multiHtml=(Get-ScopeTestHtml).Replace('<th>할인</th>','<th>할인</th><th>적용대상</th>').Replace('<td>10% 할인</td>','<td>10% 할인</td><td>현역 장병</td>').Replace('<td>30% 할인</td>','<td>30% 할인</td><td>다른 합성 대상</td>')
$p=New-BuilderFixture -Html $multiHtml
$p.Result.ClaimResults=@($p.Result.ClaimResults|Sort-Object ClaimType -Descending)
$multi=New-BenefitScopedHtmlCaptureCandidate @p
Check-Builder ($multi.Status -ceq 'READY') 'AC14 multi-claim positive ready'
$me=Get-BuilderEvidence $multi
$ms=ConvertFrom-BenefitScopedEvidenceJson (@($multi.Candidate.Artifacts|Where-Object {$_.Reference.Kind -ceq 'BENEFIT_SEMANTIC_PROJECTION'})[0].Text)
Check-Builder ($me.Claims.Count -eq 2 -and $me.Fields.Count -eq 4) 'AC14 two claim minimum union'
foreach($claim in $me.Claims){Check-Builder ($ms.Claims[$claim.SemanticClaimOrdinal].ClaimType -ceq $claim.ClaimType) 'AC14 actual canonical ordinal'}
$p.SourceRecord.Validation.Status='PARTIAL'
$p.SourceRecord.Validation.Claims[0].ValidationStatus='CONFLICT'
$p.Result.ClaimResults|Where-Object ClaimType -CEQ $p.SourceRecord.Validation.Claims[0].ClaimType|ForEach-Object {$_.ValidatedClaim.ValidationStatus='CONFLICT'}
$mixed=New-BenefitScopedHtmlCaptureCandidate @p
Check-Builder ($mixed.Status -ceq 'READY' -and (Get-BuilderEvidence $mixed).Mode -ceq 'OUTCOME_ONLY' -and (Get-BuilderEvidence $mixed).Claims.Count -eq 0) 'AC04 mixed valid/conflict retains no subset'

# AC06/07: measured absence/ambiguity uses the actual locator and exact references.
foreach($kind in @('NOT_FOUND','AMBIGUOUS')){
    $html=Get-ScopeTestHtml
    if($kind -ceq 'NOT_FOUND'){$p=New-BuilderFixture -Name '없는 합성 업소' -Building '500'}
    else{$p=New-BuilderFixture -Html ($html.Replace('테스트가게 B','테스트가게 A').Replace('테스트로 99','테스트로 12').Replace('02-0000-0099','02-0000-0012'))}
    $b=New-BenefitScopedHtmlCaptureCandidate @p
    Check-Builder ($b.Status -ceq 'READY') "AC06/07 $kind ready"
    $e=Get-BuilderEvidence $b
    Check-Builder ($e.Mode -ceq 'OUTCOME_ONLY' -and $e.Outcome.LocationStatus -ceq $kind -and $e.Outcome.CandidateReferenceCount -eq $(if($kind -ceq 'NOT_FOUND'){0}else{2})) "AC06/07 $kind exact count"
}

# AC09..17: mutations must not be repaired, silently ignored or published.
$mutations=[ordered]@{
    'AC09 business'={param($p)$p.Result.BusinessIdentity=New-ScopeTestBusiness -Name 'other'}
    'AC09 row'={param($p)$p.SourceRecord.Document.SourceRowNumber=3}
    'AC09 URL'={param($p)$p.SourceRecord.Candidate.Url='https://other.example.invalid/'}
    'AC09 time'={param($p)$p.SourceRecord.Document.ObservedAt='2026-10-01T00:00:00Z'}
    'AC10 phone conflict'={param($p)$p.CanonicalPhone='02-9999-9999'}
    'AC11 missing'={param($p)$p.SourceRecord.Observation.PSObject.Properties.Remove('HtmlValidationIndex')}
    'AC11 copied'={param($p)$p.SourceRecord.Observation.HtmlValidationIndex=($p.SourceRecord.Observation.HtmlValidationIndex|ConvertTo-Json -Depth 64 -Compress|ConvertFrom-Json -Depth 64)}
    'AC11 forged'={param($p)$p.SourceRecord.Observation.HtmlValidationIndex=[pscustomobject]@{SnapshotId=$p.SourceRecord.Observation.SnapshotId;Trusted=$true}}
    'AC11 foreign'={param($p)$other=New-BuilderFixture;$p.SourceRecord.Observation.HtmlValidationIndex=$other.SourceRecord.Observation.HtmlValidationIndex}
    'AC11 document index'={param($p)$p.SourceRecord.Document.PSObject.Properties.Remove('HtmlValidationIndex')}
    'AC11 document snapshot'={param($p)$p.SourceRecord.Document.PSObject.Properties.Remove('ValidatedHtmlSnapshot')}
    'AC11 qualified document copy'={param($p)$p.SourceRecord.Qualified.Document=($p.SourceRecord.Document|ConvertTo-Json -Depth 64 -Compress|ConvertFrom-Json -Depth 64)}
    'AC11 unrelated snapshot'={param($p)$other=New-BuilderFixture;$p.SourceRecord.Observation.Snapshot=$other.SourceRecord.Observation.Snapshot}
    'AC12 cell'={param($p)$p.SourceRecord.Slices[0].FieldReferences.BenefitDescription.CellStart++}
    'AC12 header'={param($p)$p.SourceRecord.Slices[0].FieldReferences.BenefitDescription.OriginalHeader='주소'}
    'AC12 reference'={param($p)$p.SourceRecord.Slices[0].FieldReferences.BenefitDescription.FieldReference='HTML_TABLE_1_ROW_3/BenefitDescription'}
    'AC14 duplicate'={param($p)$p.SourceRecord.Extraction.Claims+=@($p.SourceRecord.Extraction.Claims[0])}
    'AC15 null count'={param($p)$p.SourceRecord.LocationResult.CandidateReferences=@()}
    'AC16 references'={param($p)$p.SourceRecord.LocationResult.CandidateReferences=@('HTML_TABLE_1_ROW_3')}
    'AC17 hash'={param($p)$p.SourceRecord.Observation.Snapshot.ContentHash='f'*64}
    'AC17 snapshot'={param($p)$p.SourceRecord.Observation.Snapshot.SnapshotId='f'*64}
}
foreach($entry in $mutations.GetEnumerator()){
    $p=New-BuilderFixture;& $entry.Value $p
    $script:BuilderMutationTokens=0
    $script:BuilderOriginalMutationTokenizer=(Get-Item Function:Get-ScopeHtmlTagTokens).ScriptBlock
    try{
        Set-Item Function:Get-ScopeHtmlTagTokens -Value {param($Text)$script:BuilderMutationTokens++;& $script:BuilderOriginalMutationTokenizer -Text $Text}
        Expect-BuilderRejected $p $entry.Key
        Check-Builder ($script:BuilderMutationTokens -eq 0) "$($entry.Key) rejects before tokenizer fallback"
    }finally{Set-Item Function:Get-ScopeHtmlTagTokens -Value $script:BuilderOriginalMutationTokenizer}
}

# AC19/21/22: exact public shape, no other-business or raw source leakage.
Check-Builder ((@($built.PSObject.Properties.Name|Sort-Object) -join ',') -ceq 'Candidate,ReasonCode,Status') 'AC19 wrapper property set'
Check-Builder ((@($built.Candidate.PSObject.Properties.Name|Sort-Object) -join ',') -ceq 'Artifacts,Observation') 'AC19 candidate property set'
$publicJson=ConvertTo-HistoryCanonicalJson $built
Check-Builder (-not $publicJson.Contains('테스트가게 B') -and -not $publicJson.Contains('<table>') -and -not $publicJson.Contains('RawFragment') -and -not $publicJson.Contains('HtmlValidationIndex')) 'AC22 minimized output'

foreach($notApplicable in @('format','fetch')){
    $p=New-BuilderFixture
    if($notApplicable -ceq 'format'){$p.SourceRecord.Document.SourceFormat='UNSUPPORTED'}else{$p.SourceRecord.Document.FetchStatus='FAILED'}
    $b=New-BenefitScopedHtmlCaptureCandidate @p
    Check-Builder ($b.Status -ceq 'NOT_APPLICABLE' -and $null -eq $b.Candidate) "non-applicable $notApplicable"
}

# AC05/08: controlled adapter faults occur during fixture setup, never in builder.
foreach($adapterMode in @('FAILED','UNSUPPORTED','THROW')){
    $originalTemplate=(Get-Item Function:ConvertTo-InternalBenefitHtmlTemplate).ScriptBlock
    try{
        $script:BuilderAdapterMode=$adapterMode
        Set-Item Function:ConvertTo-InternalBenefitHtmlTemplate -Value {
            param($Snapshot)
            if($script:BuilderAdapterMode -ceq 'THROW'){throw 'SYNTHETIC_PRIVATE_PARSER_MARKER'}
            [pscustomobject]@{AdapterStatus=$script:BuilderAdapterMode;Rows=@();Diagnostics=@();HtmlValidationIndex=$null}
        }
        $p=New-BuilderFixture
    }finally{Set-Item Function:ConvertTo-InternalBenefitHtmlTemplate -Value $originalTemplate}
    $b=New-BenefitScopedHtmlCaptureCandidate @p
    Check-Builder ($b.Status -ceq 'READY') "AC05/08 $adapterMode READY"
    $e=Get-BuilderEvidence $b
    Check-Builder ($e.Mode -ceq 'OUTCOME_ONLY' -and -not $b.Candidate.Observation.Comparable -and $null -eq $e.Outcome.LocationStatus) "AC05/08 $adapterMode noncomparable receipt"
    if($adapterMode -ceq 'THROW'){
        Check-Builder ($e.Source.ContentHash -ceq $p.RunContext.PayloadCache[$p.SourceRecord.Document.Url].SourceSnapshot.ContentHash) 'AC08 actual cached parser-failure hash'
        $p.RunContext.PayloadCache[$p.SourceRecord.Document.Url].PSObject.Properties.Remove('SourceSnapshot')
        Expect-BuilderRejected $p 'AC08 no lazy snapshot creation'
        Check-Builder ($p.RunContext.PayloadCache[$p.SourceRecord.Document.Url].PSObject.Properties.Name -cnotcontains 'SourceSnapshot') 'AC08 rejection preserves absent cache'
    }
}

# AC23/24/25: after fixture setup, count or forbid every additional side-effect path.
$partialHtml=(Get-ScopeTestHtml)+'<table><tr><th>업소명</th><th>할인</th></tr><tr><td colspan="2">합성 unsupported</td></tr></table>'
$zeroHtml='<table><tr><th>업소명</th><th>할인</th></tr><tr><td colspan="2">합성 unsupported</td></tr></table>'
foreach($kind in @('COMPLETE','PARTIAL','ZERO_PARTIAL')){
    $p=New-BuilderFixture -Html $(if($kind -ceq 'PARTIAL'){$partialHtml}elseif($kind -ceq 'ZERO_PARTIAL'){$zeroHtml}else{Get-ScopeTestHtml})
    if($kind -ceq 'ZERO_PARTIAL'){
        Check-Builder ($p.SourceRecord.Observation.AdapterStatus -ceq 'PARTIAL' -and $p.SourceRecord.Observation.ContentUnits.Count -eq 0) 'AC24 genuine zero-unit PARTIAL'
        $p.SourceRecord.Observation.PSObject.Properties.Remove('HtmlValidationIndex')
    }
    $before=ConvertTo-HistoryCanonicalJson ([pscustomobject]@{SourceRecord=$p.SourceRecord;Result=$p.Result;Metrics=$p.RunContext.Metrics;Attempts=@($p.RunContext.Attempts)})
    $payload=$p.RunContext.PayloadCache[$p.SourceRecord.Document.Url];$snap=$payload.SourceSnapshot
    $originals=@{}
    $script:BuilderForbiddenCalls=0
    $script:BuilderOriginalCopy=(Get-Item Function:Copy-ScopeContractData).ScriptBlock
    $script:BuilderLargeRoots=@($p.RunContext,$p.SourceRecord,$p.SourceRecord.Document,$p.Result,$snap)
    $forbidden=@('Get-ScopeHtmlTagTokens','New-ScopeHtmlValidationIndex','New-InternalScopeHtmlValidationIndex','ConvertTo-InternalBenefitHtmlTemplate','Get-BenefitRunSourceDocument','Get-BenefitRunSourceSnapshot','New-BenefitHistoryObservationPackage','New-HistoryStoreLayout')
    try{
        Set-Item Function:Copy-ScopeContractData -Value {
            param($Value)
            foreach($root in $script:BuilderLargeRoots){if([object]::ReferenceEquals($root,$Value)){$script:BuilderForbiddenCalls++;throw 'FORBIDDEN_FULL_GRAPH_COPY'}}
            & $script:BuilderOriginalCopy $Value
        }
        foreach($functionName in $forbidden){
            $originals[$functionName]=(Get-Item "Function:$functionName").ScriptBlock
            Set-Item "Function:$functionName" -Value {$script:BuilderForbiddenCalls++;throw 'FORBIDDEN_ADDITIONAL_WORK'}
        }
        $b=New-BenefitScopedHtmlCaptureCandidate @p
    }finally{foreach($functionName in $forbidden){Set-Item "Function:$functionName" -Value $originals[$functionName]};Set-Item Function:Copy-ScopeContractData -Value $script:BuilderOriginalCopy}
    Check-Builder ($b.Status -ceq 'READY' -and $script:BuilderForbiddenCalls -eq 0) "AC23/24/25 $kind zero additional work"
    $after=ConvertTo-HistoryCanonicalJson ([pscustomobject]@{SourceRecord=$p.SourceRecord;Result=$p.Result;Metrics=$p.RunContext.Metrics;Attempts=@($p.RunContext.Attempts)})
    Check-Builder ($before -ceq $after -and [object]::ReferenceEquals($snap,$payload.SourceSnapshot)) "AC25 $kind inputs/cache unchanged"
    if($kind -ceq 'ZERO_PARTIAL'){Write-Host 'PR2B zero-unit PARTIAL: additional HTTP/tokenizer/parser/index/full-graph-copy calls=0'}
}

# AC13/14/17/18/20/21/22: inject at real composition/validation seams.
# Review counterexamples must fail before correction: receipt linkage, closed
# observation output and actual cached adapter truth cannot be bypassed.
$p=New-BuilderFixture
$p.SourceRecord.Validation.Status='PARTIAL'
$p.Result.ClaimResults[0].ValidatedClaim=New-ValidatedBenefitClaim -ClaimType BENEFIT_DESCRIPTION -Value 'UNRELATED_BUSINESS_SECRET' -ValidationStatus VALIDATED -EvidenceText 'UNRELATED_BUSINESS_SECRET' -EvidenceReference 'HTML_TABLE_1_ROW_3/BenefitDescription' -SourceUrl $p.SourceRecord.Document.Url
$p.Result.ClaimResults[0].EvidenceValue='UNRELATED_BUSINESS_SECRET'
Expect-BuilderRejected $p 'AC04/22 receipt rejects unrelated Result claim'
$p=New-BuilderFixture
$p.SourceRecord.Observation.AdapterStatus='FAILED';$p.SourceRecord.Observation.ContentUnits=@()
$p.SourceRecord.LocationResult.OperationalStatus='FAILED';$p.SourceRecord.LocationResult.Status=$null;$p.SourceRecord.LocationResult.CandidateReferences=@()
$p.SourceRecord.Slices=@();$p.SourceRecord.Extraction.Status='FAILED';$p.SourceRecord.Extraction.Claims=@();$p.SourceRecord.Validation.Status='FAILED';$p.SourceRecord.Validation.Claims=@();$p.Result.ClaimResults=@();$p.OperationalStatus.ExtractionStatus='FAILED'
Expect-BuilderRejected $p 'AC05 cached COMPLETE cannot be rewritten FAILED'
$p=New-BuilderFixture
$p.SourceRecord.Observation=$null;$p.SourceRecord.LocationResult=$null;$p.SourceRecord.Slices=@()
$p.SourceRecord.Extraction.Status='FAILED';$p.SourceRecord.Extraction.Claims=@();$p.SourceRecord.Validation.Status='FAILED';$p.SourceRecord.Validation.Claims=@();$p.Result.ClaimResults=@();$p.OperationalStatus.ExtractionStatus='FAILED'
Expect-BuilderRejected $p 'AC08 existing template cannot attest a missing observation failure'
$originalObservation=(Get-Item Function:New-HistoryObservation).ScriptBlock
$script:BuilderOriginalObservation=$originalObservation
try{
    Set-Item Function:New-HistoryObservation -Value {
        param($ObservationId,$RunId,$BusinessId,$Domain,$ObservedAt,$OperationalStatus,$Comparable,$InputFingerprint,$EvidenceFingerprint,$SemanticFingerprint,$ExecutionFingerprint,$ArtifactReferences,$SemanticResultReference,$NonComparableReasons)
        $o=& $script:BuilderOriginalObservation @PSBoundParameters
        $o|Add-Member RawSource 'UNRELATED_BUSINESS_SECRET';$o
    }
    $p=New-BuilderFixture
    Expect-BuilderRejected $p 'AC19 closed observation rejects raw property'
}finally{Set-Item Function:New-HistoryObservation -Value $originalObservation}

$p=New-BuilderFixture
$p.SourceRecord.Validation.Status='PARTIAL'
$other=$p.SourceRecord.Observation.ContentUnits[1]
$p.SourceRecord.Slices[0]=New-RelevantBenefitEvidenceSlice -Observation $p.SourceRecord.Observation -Unit $other -IdentityEvidence @('NAME_MATCH','FULL_ADDRESS_MATCH')
$p.SourceRecord.Extraction.Claims[0].EvidenceReference='HTML_TABLE_1_ROW_3/BenefitDescription'
$p.SourceRecord.Extraction.Claims[0].Value='30% 할인';$p.SourceRecord.Extraction.Claims[0].EvidenceText='30% 할인'
$p.SourceRecord.Validation.Claims[0].EvidenceReference='HTML_TABLE_1_ROW_3/BenefitDescription';$p.SourceRecord.Validation.Claims[0].Value='30% 할인';$p.SourceRecord.Validation.Claims[0].EvidenceText='30% 할인'
$p.Result.ClaimResults[0].EvidenceValue='30% 할인';$p.Result.ClaimResults[0].ValidatedClaim=$p.SourceRecord.Validation.Claims[0]
Expect-BuilderRejected $p 'AC10/22 receipt cannot substitute another source row'
foreach($fault in @('missing-field','extra-field','bad-ordinal','fingerprint','artifact-reference','oversize','domain','boolean','reasons','serializer-throw','validator-throw','validator-output','validator-error','validator-info','validator-verbose','validator-debug','validator-host','validator-success')){
    $p=New-BuilderFixture
    $functionName=switch($fault){
        'serializer-throw' {'ConvertTo-HistoryCanonicalJson'}
        default {'Assert-InternalScopedHtmlCandidate'}
    }
    $script:BuilderFault=$fault
    $script:BuilderOriginalSeam=(Get-Item "Function:$functionName").ScriptBlock
    try{
        switch($fault){
            'serializer-throw' {Set-Item "Function:$functionName" -Value {throw 'SYNTHETIC_PRIVATE_FAILURE_MARKER'}}
            default {
                Set-Item "Function:$functionName" -Value {
                    param($Candidate,$Evidence,$InputProjection,$EvidenceProjection,$SemanticProjection,$ExecutionProjection,$Assessment)
                    switch($script:BuilderFault){
                        'missing-field' {$Evidence.Fields=@($Evidence.Fields|Where-Object Key -CNE 'BusinessName')}
                        'extra-field' {$Evidence.Fields+=@($Evidence.Fields[0])}
                        'bad-ordinal' {$Evidence.Claims[0].SemanticClaimOrdinal=5}
                        'fingerprint' {$Candidate.Observation.InputFingerprint='f'*64}
                        'artifact-reference' {$Candidate.Artifacts[0].Reference.RelativePath='artifacts/sha256/wrong.json'}
                        'oversize' {$Candidate.Artifacts[0].Text='x'*65537}
                        'domain' {$Candidate.Observation.Domain='LOCATION'}
                        'boolean' {$Candidate.Observation.Comparable='true'}
                        'reasons' {$Candidate.Observation.NonComparableReasons=@('UNRELATED_BUSINESS_SECRET')}
                        'validator-throw' {throw 'SYNTHETIC_PRIVATE_FAILURE_MARKER'}
                        'validator-output' {Write-Warning 'SYNTHETIC_PRIVATE_FAILURE_MARKER';return}
                        'validator-error' {Write-Error 'SYNTHETIC_PRIVATE_FAILURE_MARKER';return}
                        'validator-info' {Write-Information 'SYNTHETIC_PRIVATE_FAILURE_MARKER' -InformationAction Continue;return}
                        'validator-verbose' {Write-Verbose 'SYNTHETIC_PRIVATE_FAILURE_MARKER' -Verbose;return}
                        'validator-debug' {Write-Debug 'SYNTHETIC_PRIVATE_FAILURE_MARKER' -Debug;return}
                        'validator-host' {Write-Host 'SYNTHETIC_PRIVATE_FAILURE_MARKER';return}
                        'validator-success' {'SYNTHETIC_PRIVATE_FAILURE_MARKER';return}
                    }
                    & $script:BuilderOriginalSeam @PSBoundParameters
                }
            }
        }
        Expect-BuilderRejected $p "AC13/14/17/18/20/21/22 $fault"
    }finally{Set-Item "Function:$functionName" -Value $script:BuilderOriginalSeam}
}

# AC26: existing package oracle, test-only temporary Store. No Prepare/Commit.
$p=New-BuilderFixture
$diag=[pscustomobject]@{Url=$p.SourceRecord.Document.Url;SourceFormat='HTML';FetchStatus='COMPLETE';ContentHash=$p.SourceRecord.Observation.Snapshot.ContentHash;AdapterId='HTML_GENERIC';AdapterVersion='1';AdapterStatus='COMPLETE';LocationOperationalStatus='COMPLETE';LocationStatus='LOCATED';CandidateReferences=@('HTML_TABLE_1_ROW_2');OfficialityStatus='VERIFIED_OFFICIAL';BusinessBindingStatus='STRONG'}
$oracleRoot=Join-Path ([IO.Path]::GetTempPath()) ('milimap-pr2b-oracle-'+[guid]::NewGuid().ToString('N'))
$store=New-HistoryStoreLayout -Root $oracleRoot
try{
    $oracleParameters=@{};foreach($key in @('Benefit','BusinessId','BusinessIdentity','CanonicalPhone','Result','OperationalStatus','RunId','ObservedAt','RepositoryRevision')){$oracleParameters[$key]=$p[$key]}
    $oracle=New-BenefitHistoryObservationPackage -Store $store -EvidenceDiagnostics @($diag) -ExecutionConfiguration ([pscustomobject]@{HtmlEvidenceRetentionProfile='C_LITE_V1'}) @oracleParameters
    $b=New-BenefitScopedHtmlCaptureCandidate @p
    Check-Builder ($b.Status -ceq 'READY') 'AC26 oracle candidate ready'
    foreach($key in @('InputFingerprint','EvidenceFingerprint','SemanticFingerprint','ExecutionFingerprint','ObservationId','SemanticResultReference','OperationalStatus','Comparable')){
        Check-Builder ($b.Candidate.Observation.$key -ceq $oracle.Observation.$key) "AC26 oracle $key parity"
    }
    foreach($a in $oracle.PreparedArtifacts){
        $actual=@($b.Candidate.Artifacts|Where-Object {$_.Reference.Kind -ceq $a.Kind})[0]
        Check-Builder ($actual.Text -ceq $a.Text -and $actual.Reference.ContentHash -ceq $a.ContentHash -and $actual.Reference.RelativePath -ceq "artifacts/sha256/$($a.ContentHash).json") "AC26 canonical $($a.Kind) bytes/hash/path"
    }
    Check-Builder ((ConvertTo-HistoryCanonicalJson $b) -ceq (ConvertTo-HistoryCanonicalJson (New-BenefitScopedHtmlCaptureCandidate @p))) 'AC26 repeated input deterministic'
    Check-Builder (@(Get-ChildItem -LiteralPath $oracleRoot -Recurse -File).Count -eq 0) 'AC26 oracle creates no persisted records'
}finally{
    $resolved=[IO.Path]::GetFullPath($oracleRoot)
    $tempPrefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if(-not $resolved.StartsWith($tempPrefix,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -cnotmatch '^milimap-pr2b-oracle-[0-9a-f]{32}$'){throw 'Unsafe oracle cleanup path'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Host "PASS: C-Lite builder assertions=$script:BuilderChecks"

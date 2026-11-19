$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-location/test-support.ps1')
. (Join-Path $PSScriptRoot 'lib/benefit-evidence/invoke-scoped-benefit-source.ps1')
. (Join-Path $PSScriptRoot 'lib/benefit-verification/evaluate-benefit-state.ps1')
. (Join-Path $PSScriptRoot 'lib/history/benefit-scoped-html-capture-builder.ps1')
. (Join-Path $PSScriptRoot 'lib/history/commit-history-run.ps1')
$historyLibrary=Join-Path $PSScriptRoot 'lib/history/benefit-scoped-html-history.ps1'
if(Test-Path -LiteralPath $historyLibrary){. $historyLibrary}
$script:BridgeChecks=0
function Check-Bridge([bool]$Condition,[string]$Label){if(-not $Condition){throw "FAIL: $Label"};$script:BridgeChecks++}
function New-BridgeFixture([string]$Kind='LOCATED_FIELDS'){
    $html=(Get-ScopeTestHtml)+'<!--RAW_SOURCE_SENTINEL-->'
    if($Kind -ceq 'UNSUPPORTED'){$html='<p>SYNTHETIC_UNSUPPORTED_SENTINEL</p>'}
    if($Kind -ceq 'PARTIAL'){$html+='<table><tr><th>업소명</th><th>할인</th></tr><tr><td colspan="2">합성 unsupported</td></tr></table>'}
    if($Kind -ceq 'ZERO_CLAIM'){$html=$html.Replace('10% 할인','').Replace('30% 할인','')}
    $context=New-BenefitSourceRunContext
    $business=New-ScopeTestBusiness
    $candidate=New-BenefitSourceCandidate -SourceRowNumber 2 -Url 'https://city.example.go.kr/list' -SourceKind PUBLIC_OFFICIAL
    $request={param($Uri)[pscustomobject]@{StatusCode=200;ContentType='text/html';Text=$html;Bytes=$null}}.GetNewClosure()
    $record=Invoke-ScopedPhase2BenefitSourceCandidate -Candidate $candidate -Business $business -RunContext $context -RequestInvoker $request
    if($Kind -ceq 'OUTCOME_ONLY'){$record.Validation.Status='PARTIAL';$record.Validation.Claims[0].ValidationStatus='INVALID'}
    $claims=@(foreach($v in $record.Validation.Claims){New-BenefitClaimVerification -ClaimType $v.ClaimType -EvidenceValue $v.Value -Result UNKNOWN -ValidatedClaim $v})
    $result=New-BenefitVerificationResult -SourceRowNumber 2 -BusinessIdentity $business -BenefitState NEEDS_VERIFICATION -ReviewClass YELLOW -ClaimResults $claims -ProductionAction NONE
    @{
        RunContext=$context;SourceRecord=$record;Benefit=(New-CanonicalBenefitRecord -SourceRowNumber 2 -BusinessName $business.OriginalName -BenefitDescription '10% 할인' -ExistingSourceType '지자체 공식 자료' -ExistingSourceUrl $candidate.Url)
        BusinessId='biz-0123456789abcdef0123456789abcdef';BusinessIdentity=$business;CanonicalPhone='';Result=$result
        OperationalStatus=[pscustomobject]@{DiscoveryStatus='COMPLETE';ExtractionStatus=$record.Extraction.Status}
        RunId=('run-pr2c-'+[guid]::NewGuid().ToString('N'));ObservedAt='2026-11-19T12:34:56.000+09:00';RepositoryRevision=('a'*40)
    }
}
function Copy-BridgeData($Value){ConvertFrom-BenefitScopedEvidenceJson (ConvertTo-HistoryCanonicalJson $Value) -MaxBytes 1048576}
function New-BridgeManifest($Parameters,$Observation){
    New-HistoryRunManifest -RunId $Parameters.RunId -StartedAt $Parameters.ObservedAt -CompletedAt '' -RepositoryRevision $Parameters.RepositoryRevision -RequestedBusinessIds @($Parameters.BusinessId) -CompletedBusinessIds @($Parameters.BusinessId) -FailedBusinessIds @() -ExecutionStatus $Observation.OperationalStatus -RunCommitStatus PREPARED
}
function New-BridgeTestStore {
    $root=Join-Path ([IO.Path]::GetTempPath()) ('milimap-pr2c-'+[guid]::NewGuid().ToString('N'))
    $script:BridgeTestRoots.Add($root)
    New-HistoryStoreLayout -Root $root
}
function Bridge-Inventory($Store){
    @(Get-ChildItem -LiteralPath $Store.Root -Recurse -File | Sort-Object FullName | ForEach-Object { $_.FullName+'|'+(Get-FileHash -LiteralPath $_.FullName).Hash }) -join "`n"
}
function Commit-BridgePackage($Store,$Parameters,$Package,[hashtable]$ExpectedBaselines,[scriptblock]$FaultInjector=$null){
    $prepared=Prepare-HistoryRun -Store $Store -RunManifest (New-BridgeManifest $Parameters $Package.Observation) -Artifacts $Package.PreparedArtifacts -Observations @($Package.Observation)
    Commit-HistoryRun -Store $Store -PreparedRun $prepared -ExpectedBaselines $ExpectedBaselines -FaultInjector $FaultInjector
}
function Reject-BridgePackage($Parameters,[string]$Label){
    $values=@(New-BenefitScopedHtmlHistoryPackage @Parameters *>&1)
    Check-Bridge ($values.Count -eq 1 -and $values[0].Status -ceq 'REJECTED' -and $null -eq $values[0].Package -and $values[0].ReasonCode -ceq 'C_LITE_HISTORY_PACKAGE_REJECTED') $Label
}
function Reject-BridgeRead($Store,$Id,[string]$Label){
    $values=@(Read-BenefitScopedHtmlCommittedCapture -Store $Store -ObservationId $Id *>&1)
    Check-Bridge ($values.Count -eq 1 -and $values[0].Status -ceq 'REJECTED' -and $null -eq $values[0].Capture -and $values[0].ReasonCode -ceq 'C_LITE_COMMITTED_REJECTED') $Label
}
function Rewrite-BridgeEvidence($Built,[scriptblock]$Change){
    $artifact=@($Built.Candidate.Artifacts|Where-Object {$_.Reference.Kind -ceq 'BENEFIT_SCOPED_EVIDENCE'})[0]
    $e=ConvertFrom-BenefitScopedEvidenceJson $artifact.Text
    & $Change $e
    $artifact.Text=ConvertTo-HistoryCanonicalJson $e
    $artifact.Reference.ContentHash=Get-HistorySha256 $artifact.Text
    $artifact.Reference.RelativePath='artifacts/sha256/'+$artifact.Reference.ContentHash+'.json'
}
$script:BridgeTestRoots=[Collections.Generic.List[string]]::new()
try{
    Check-Bridge ([bool](Get-Command New-BenefitScopedHtmlHistoryPackage -ErrorAction SilentlyContinue)) 'persistence bridge function exists'
    Check-Bridge ([bool](Get-Command Read-BenefitScopedHtmlCommittedCapture -ErrorAction SilentlyContinue)) 'committed verifier function exists'
    foreach($kind in @('LOCATED_FIELDS','OUTCOME_ONLY','ZERO_CLAIM','PARTIAL','UNSUPPORTED','PARSER_FAILURE')){
        if($kind -ceq 'PARSER_FAILURE'){
            $originalTemplate=(Get-Item Function:ConvertTo-InternalBenefitHtmlTemplate).ScriptBlock
            try{Set-Item Function:ConvertTo-InternalBenefitHtmlTemplate -Value {param($Snapshot)throw 'PRIVATE_PARSER_SENTINEL'};$p=New-BridgeFixture}
            finally{Set-Item Function:ConvertTo-InternalBenefitHtmlTemplate -Value $originalTemplate}
            Check-Bridge ($null -eq $p.SourceRecord.Observation -and $p.RunContext.TemplateCache.Count -eq 0) 'real pre-template parser failure fixture'
        }else{$p=New-BridgeFixture $kind}
        $expected=New-BenefitScopedHtmlCaptureCandidate @p
        $before=ConvertTo-HistoryCanonicalJson ([pscustomobject]@{Record=$p.SourceRecord;Result=$p.Result;Metrics=$p.RunContext.Metrics;Attempts=@($p.RunContext.Attempts)})
        $script:BridgeBuilderCalls=0;$script:BridgeOriginalBuilder=(Get-Item Function:New-BenefitScopedHtmlCaptureCandidate).ScriptBlock
        $script:BridgeForbiddenCalls=0;$guardSaved=@{}
        try{
            foreach($name in @('Prepare-HistoryRun','Commit-HistoryRun','Get-BenefitRunSourceDocument','Get-BenefitRunSourceSnapshot','Get-ScopeHtmlTagTokens','New-ScopeHtmlValidationIndex','New-InternalScopeHtmlValidationIndex','ConvertTo-InternalBenefitHtmlTemplate','Invoke-BenefitEvidenceExtraction','ConvertTo-ValidatedBenefitEvidence','Compare-BenefitClaims','Invoke-BenefitStateEvaluation')){
                $guardSaved[$name]=(Get-Item "Function:$name").ScriptBlock
                Set-Item "Function:$name" -Value {$script:BridgeForbiddenCalls++;throw 'FORBIDDEN_BRIDGE_WORK'}
            }
            Set-Item Function:New-BenefitScopedHtmlCaptureCandidate -Value {
                param($RunContext,$SourceRecord,$Benefit,$BusinessId,$BusinessIdentity,$CanonicalPhone='',$Result,$OperationalStatus,$RunId,$ObservedAt,$RepositoryRevision)
                $script:BridgeBuilderCalls++;& $script:BridgeOriginalBuilder @PSBoundParameters
            }
            $built=New-BenefitScopedHtmlHistoryPackage @p
        }finally{
            Set-Item Function:New-BenefitScopedHtmlCaptureCandidate -Value $script:BridgeOriginalBuilder
            foreach($name in $guardSaved.Keys){Set-Item "Function:$name" -Value $guardSaved[$name]}
        }
        Check-Bridge ($built.Status -ceq 'READY' -and $script:BridgeBuilderCalls -eq 1) "$kind builder exactly once"
        Check-Bridge ($script:BridgeForbiddenCalls -eq 0) "$kind no writer/HTTP/source parse/index/extract/compare work"
        Check-Bridge ($built.Package.PreparedArtifacts.Count -eq 3 -and $built.Package.Observation.ArtifactReferences.Count -eq 3) "$kind exactly three artifacts"
        foreach($a in $expected.Candidate.Artifacts){
            $prepared=@($built.Package.PreparedArtifacts|Where-Object Kind -CEQ $a.Reference.Kind)[0]
            Check-Bridge ($prepared.ContentHash -ceq $a.Reference.ContentHash -and $prepared.Extension -ceq 'json' -and $prepared.Text -ceq $a.Text) "$kind prepared identity"
            Check-Bridge ((Get-BenefitEvidenceByteHash (Get-PreparedArtifactPayload $prepared)) -ceq $a.Reference.ContentHash) "$kind exact UTF8 bytes"
        }
        Check-Bridge ($before -ceq (ConvertTo-HistoryCanonicalJson ([pscustomobject]@{Record=$p.SourceRecord;Result=$p.Result;Metrics=$p.RunContext.Metrics;Attempts=@($p.RunContext.Attempts)}))) "$kind inputs unchanged"
        $store=New-BridgeTestStore
        $committed=Commit-BridgePackage $store $p $built.Package @{($p.BusinessId+'|BENEFIT')=''}
        Check-Bridge ($committed.Code -ceq 'COMMITTED') "$kind real commit"
        $inventory=Bridge-Inventory $store
        $read=Read-BenefitScopedHtmlCommittedCapture -Store $store -ObservationId $built.Package.Observation.ObservationId
        Check-Bridge ($read.Status -ceq 'VERIFIED') "$kind committed verified"
        Check-Bridge ((ConvertTo-HistoryCanonicalJson $read.Capture) -ceq (ConvertTo-HistoryCanonicalJson $expected.Candidate)) "$kind exact round trip"
        Check-Bridge ($inventory -ceq (Bridge-Inventory $store)) "$kind reader is read-only"
        Check-Bridge ((ConvertTo-HistoryCanonicalJson $read) -cnotmatch 'RAW_SOURCE_SENTINEL|테스트가게 B|SYNTHETIC_UNSUPPORTED_SENTINEL') "$kind no raw/cross-business output"
        $scoped=ConvertFrom-BenefitScopedEvidenceJson (@($read.Capture.Artifacts|Where-Object {$_.Reference.Kind -ceq 'BENEFIT_SCOPED_EVIDENCE'})[0].Text)
        if($kind -cin @('OUTCOME_ONLY','PARTIAL','UNSUPPORTED','PARSER_FAILURE')){
            Check-Bridge ($scoped.Mode -ceq 'OUTCOME_ONLY' -and -not (Test-BenefitScopedEvidenceReuseEligible $scoped)) "$kind receipt never reuse eligible"
        }
        if($kind -ceq 'PARSER_FAILURE'){
            Check-Bridge (-not $read.Capture.Observation.Comparable -and $null -eq $scoped.Outcome.LocationStatus -and $scoped.Source.ContentHash -ceq $p.RunContext.PayloadCache[$p.SourceRecord.Document.Url].SourceSnapshot.ContentHash) 'parser-failure trusted hash/noncomparable semantics preserved'
        }
    }
    # Non-ready/forged builder outputs must be rejected before any Prepare/write.
    $faults=[ordered]@{
        rejected={param($b)$b.Status='REJECTED';$b.Candidate=$null}
        notApplicable={param($b)$b.Status='NOT_APPLICABLE';$b.Candidate=$null}
        wrapper={param($b)$b|Add-Member RawSource 'PRIVATE_FAULT_SENTINEL'}
        owner={param($b)$b.Candidate.Observation.BusinessId='biz-'+('f'*32)}
        time={param($b)$b.Candidate.Observation.ObservedAt='2026-11-19T03:34:56Z'}
        inputFingerprint={param($b)$b.Candidate.Observation.InputFingerprint='f'*64}
        scope={param($b)Rewrite-BridgeEvidence $b {param($e)$e.Scope.RowStart++}}
        extraField={param($b)Rewrite-BridgeEvidence $b {param($e)$e.Fields+=@($e.Fields[0])}}
        raw={param($b)$b.Candidate.Observation.ArtifactReferences[0].Kind='RAW_SOURCE_PAYLOAD'}
        extraArtifact={param($b)$b.Candidate.Artifacts+=@($b.Candidate.Artifacts[0])}
        missingScoped={param($b)$b.Candidate.Artifacts=@($b.Candidate.Artifacts|Where-Object {$_.Reference.Kind -cne 'BENEFIT_SCOPED_EVIDENCE'});$b.Candidate.Observation.ArtifactReferences=@($b.Candidate.Observation.ArtifactReferences|Where-Object Kind -CNE 'BENEFIT_SCOPED_EVIDENCE')}
        oversized={param($b)$b.Candidate.Artifacts[0].Text='x'*65537}
        modifiedJson={param($b)$b.Candidate.Artifacts[0].Text+=' '}
        emitted={param($b)Write-Warning 'PRIVATE_FAULT_SENTINEL'}
        thrown={param($b)throw 'PRIVATE_FAULT_SENTINEL'}
    }
    foreach($fault in $faults.GetEnumerator()){
        $p=New-BridgeFixture
        $store=New-BridgeTestStore;$before=Bridge-Inventory $store
        $script:BridgeOriginalBuilder=(Get-Item Function:New-BenefitScopedHtmlCaptureCandidate).ScriptBlock
        $script:BridgeFault=$fault.Value;$script:BridgeBuilderCalls=0;$script:BridgeForbiddenCalls=0
        $saved=@{}
        try{
            foreach($name in @('Prepare-HistoryRun','Commit-HistoryRun','Get-BenefitRunSourceDocument','Get-ScopeHtmlTagTokens','ConvertTo-InternalBenefitHtmlTemplate','Invoke-BenefitEvidenceExtraction','ConvertTo-ValidatedBenefitEvidence','Compare-BenefitClaims')){
                $saved[$name]=(Get-Item "Function:$name").ScriptBlock
                Set-Item "Function:$name" -Value {$script:BridgeForbiddenCalls++;throw 'FORBIDDEN_EXTRA_WORK'}
            }
            Set-Item Function:New-BenefitScopedHtmlCaptureCandidate -Value {
                param($RunContext,$SourceRecord,$Benefit,$BusinessId,$BusinessIdentity,$CanonicalPhone='',$Result,$OperationalStatus,$RunId,$ObservedAt,$RepositoryRevision)
                $script:BridgeBuilderCalls++
                $b=& $script:BridgeOriginalBuilder @PSBoundParameters
                & $script:BridgeFault $b
                $b
            }
            Reject-BridgePackage $p ("pre-Prepare fault: "+$fault.Key)
            Check-Bridge ($script:BridgeBuilderCalls -eq 1 -and $script:BridgeForbiddenCalls -eq 0) ("single builder / no extra work: "+$fault.Key)
        }finally{
            Set-Item Function:New-BenefitScopedHtmlCaptureCandidate -Value $script:BridgeOriginalBuilder
            foreach($name in $saved.Keys){Set-Item "Function:$name" -Value $saved[$name]}
        }
        Check-Bridge ($before -ceq (Bridge-Inventory $store) -and @(Get-ChildItem -LiteralPath $store.TempRoot -Force).Count -eq 0) ("no staging: "+$fault.Key)
    }
    foreach($unsafeRun in @('run/../escape','../escape','run:alternate-stream')){
        $p=New-BridgeFixture;$p.RunId=$unsafeRun
        Reject-BridgePackage $p 'file-store-unsafe RunId rejected before Prepare'
    }

    # Real persisted-read boundary mutations. Restore original bytes after each.
    $p=New-BridgeFixture;$built=New-BenefitScopedHtmlHistoryPackage @p;$store=New-BridgeTestStore
    $key=$p.BusinessId+'|BENEFIT'
    $commit=Commit-BridgePackage $store $p $built.Package @{$key=''}
    Check-Bridge ($commit.Code -ceq 'COMMITTED') 'read attacks start with real COMMITTED Store'
    $id=$built.Package.Observation.ObservationId
    $observationPath=Get-HistoryObservationPath $store $id
    $manifestPath=Get-HistoryRunManifestPath $store $p.RunId
    $originalObservation=[IO.File]::ReadAllBytes($observationPath)
    $originalManifest=[IO.File]::ReadAllBytes($manifestPath)
    $observationText=[Text.Encoding]::UTF8.GetString($originalObservation)
    foreach($injectedKey in @('RunId','runid','\u0052unId')){
        try{
            [IO.File]::WriteAllText($observationPath,('{"'+$injectedKey+'":"PRIVATE_FAULT_SENTINEL",'+$observationText.Substring(1)),[Text.UTF8Encoding]::new($false))
            Reject-BridgeRead $store $id ("duplicate/colliding record key: "+$injectedKey)
        }finally{[IO.File]::WriteAllBytes($observationPath,$originalObservation)}
    }
    foreach($mutation in @(
        {param($o)$o.ObservedAt='2026-11-19T03:34:56Z'},
        {param($o)$o.BusinessId='biz-'+('f'*32)},
        {param($o)$o.HistoryContractVersion='1'},
        {param($o)$o.Comparable='true'},
        {param($o)$o.Domain='benefit'},
        {param($o)$o.InputFingerprint='f'*64},
        {param($o)$o.EvidenceFingerprint='f'*64},
        {param($o)$o.SemanticFingerprint='f'*64},
        {param($o)$o.ExecutionFingerprint='f'*64},
        {param($o)$o.ArtifactReferences=@($o.ArtifactReferences|Where-Object Kind -CNE 'BENEFIT_SCOPED_EVIDENCE')},
        {param($o)$o.ArtifactReferences[0].RelativePath='../PRIVATE_FAULT_SENTINEL.json'},
        {param($o)$o|Add-Member RawSource 'PRIVATE_FAULT_SENTINEL'}
    )){
        try{
            $o=ConvertFrom-BenefitScopedEvidenceJson $observationText;& $mutation $o
            [IO.File]::WriteAllText($observationPath,(ConvertTo-HistoryCanonicalJson $o),[Text.UTF8Encoding]::new($false))
            Reject-BridgeRead $store $id 'typed/owner/fingerprint/ref observation mutation'
        }finally{[IO.File]::WriteAllBytes($observationPath,$originalObservation)}
    }
    foreach($mutation in @(
        {param($m)$m.RunCommitStatus='PREPARED'}, {param($m)$m.RunCommitStatus='ABORTED'},
        {param($m)$m.RepositoryRevision='b'*40}, {param($m)$m.CompletedBusinessIds=@()},
        {param($m)$m.FailedBusinessIds=@($m.RequestedBusinessIds)},
        {param($m)$m.FingerprintSchemaVersion='1'}
    )){
        try{
            $m=ConvertFrom-BenefitScopedEvidenceJson ([Text.Encoding]::UTF8.GetString($originalManifest));& $mutation $m
            [IO.File]::WriteAllText($manifestPath,(ConvertTo-HistoryCanonicalJson $m),[Text.UTF8Encoding]::new($false))
            Reject-BridgeRead $store $id 'real manifest terminal/revision/membership mutation'
        }finally{[IO.File]::WriteAllBytes($manifestPath,$originalManifest)}
    }
    foreach($artifact in $built.Package.PreparedArtifacts){
        $artifactPath=Get-HistoryArtifactPath $store $artifact.ContentHash json
        $originalBytes=[IO.File]::ReadAllBytes($artifactPath)
        try{
            [IO.File]::WriteAllText($artifactPath,'PRIVATE_FAULT_SENTINEL',[Text.UTF8Encoding]::new($false))
            Reject-BridgeRead $store $id 'actual artifact bytes must match hash'
        }finally{[IO.File]::WriteAllBytes($artifactPath,$originalBytes)}
        try{
            Remove-Item -LiteralPath $artifactPath -Force
            Reject-BridgeRead $store $id 'missing actual artifact'
        }finally{[IO.File]::WriteAllBytes($artifactPath,$originalBytes)}
        $held=[IO.File]::Open($artifactPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
        try{Reject-BridgeRead $store $id 'unreadable artifact fails closed'}finally{$held.Dispose()}
    }
    # Even self-consistent new content addresses cannot hide JSON ambiguity or
    # lexical source/capture timestamp changes behind hashes.
    foreach($kind in @('BENEFIT_EVIDENCE_PROJECTION','BENEFIT_SEMANTIC_PROJECTION','BENEFIT_SCOPED_EVIDENCE')){
        $originalArtifact=@($built.Package.PreparedArtifacts|Where-Object Kind -CEQ $kind)[0]
        foreach($attack in @('duplicate','case-collision','escaped-collision','timestamp')){
            if($attack -ceq 'timestamp' -and $kind -cne 'BENEFIT_SCOPED_EVIDENCE'){continue}
            $newPath=$null
            try{
                $text=$originalArtifact.Text
                if($attack -ceq 'timestamp'){
                    $node=ConvertFrom-BenefitScopedEvidenceJson $text
                    $node.Capture.ObservedAt='2026-11-19T03:34:56Z'
                    $text=ConvertTo-HistoryCanonicalJson $node
                }else{
                    $property=if($kind -ceq 'BENEFIT_SCOPED_EVIDENCE'){'ContractType'}else{'ProjectionType'}
                    if($attack -ceq 'case-collision'){$property=$property.ToLowerInvariant()}
                    if($attack -ceq 'escaped-collision'){$property='\u'+([int][char]$property[0]).ToString('x4')+$property.Substring(1)}
                    $text='{"'+$property+'":"PRIVATE_FAULT_SENTINEL",'+$text.Substring(1)
                }
                $hash=Get-HistorySha256 $text
                $newPath=Get-HistoryArtifactPath $store $hash json
                [IO.File]::WriteAllText($newPath,$text,[Text.UTF8Encoding]::new($false))
                $o=ConvertFrom-BenefitScopedEvidenceJson $observationText
                $ref=@($o.ArtifactReferences|Where-Object Kind -CEQ $kind)[0]
                $ref.ContentHash=$hash;$ref.RelativePath='artifacts/sha256/'+$hash+'.json'
                [IO.File]::WriteAllText($observationPath,(ConvertTo-HistoryCanonicalJson $o),[Text.UTF8Encoding]::new($false))
                Reject-BridgeRead $store $id ("rehashed artifact attack: $kind / $attack")
            }finally{
                [IO.File]::WriteAllBytes($observationPath,$originalObservation)
                if($null -ne $newPath -and (Test-Path -LiteralPath $newPath)){Remove-Item -LiteralPath $newPath -Force}
            }
        }
    }
    $scopedArtifact=@($built.Package.PreparedArtifacts|Where-Object Kind -CEQ 'BENEFIT_SCOPED_EVIDENCE')[0]
    $scopedPath=Get-HistoryArtifactPath $store $scopedArtifact.ContentHash json
    foreach($badBytes in @([byte[]]@(0xff,0xfe,0x7b),[Text.Encoding]::UTF8.GetBytes((' '*65537)))){
        try{[IO.File]::WriteAllBytes($scopedPath,$badBytes);Reject-BridgeRead $store $id 'invalid UTF8 / oversized physical artifact'}
        finally{[IO.File]::WriteAllText($scopedPath,$scopedArtifact.Text,[Text.UTF8Encoding]::new($false))}
    }
    $outside=New-BridgeTestStore
    $movedPath=Assert-HistoryStorePathWithinRoot $outside (Join-Path $outside.Root 'moved-artifacts')
    $linkPath=Assert-HistoryStorePathWithinRoot $store $store.ArtifactsRoot
    [IO.Directory]::Move($linkPath,$movedPath)
    try{
        $linkType=if([OperatingSystem]::IsWindows()){'Junction'}else{'SymbolicLink'}
        $null=New-Item -ItemType $linkType -Path $linkPath -Target $movedPath
        Reject-BridgeRead $store $id 'filesystem junction/symlink cannot redirect artifact reads'
    }finally{
        if([IO.Directory]::Exists($linkPath)){
            if(([IO.File]::GetAttributes($linkPath) -band [IO.FileAttributes]::ReparsePoint) -eq 0){throw 'Expected test-only reparse link'}
            [IO.Directory]::Delete($linkPath)
        }
        [IO.Directory]::Move($movedPath,$linkPath)
    }
    $fakeLayout=Copy-BridgeData $store;$fakeLayout.ArtifactsRoot=[IO.Path]::GetTempPath()
    Reject-BridgeRead $fakeLayout $id 'caller Store layout cannot redirect artifact reads'
    Reject-BridgeRead $store '../escape' 'observation path traversal'
    $inventory=Bridge-Inventory $store
    $saved=@{};$script:BridgeForbiddenCalls=0
    try{
        foreach($name in @('Prepare-HistoryRun','Commit-HistoryRun','Read-HistoryJsonFile','Read-HistoryObservation','Get-HistoryLatestEntry','Rebuild-HistoryIndexes','Get-BenefitRunSourceDocument','Get-ScopeHtmlTagTokens','Invoke-BenefitEvidenceExtraction','Compare-BenefitClaims')){
            $saved[$name]=(Get-Item "Function:$name").ScriptBlock
            Set-Item "Function:$name" -Value {$script:BridgeForbiddenCalls++;throw 'FORBIDDEN_READER_WORK'}
        }
        $verified=Read-BenefitScopedHtmlCommittedCapture $store $id
        Check-Bridge ($verified.Status -ceq 'VERIFIED' -and $script:BridgeForbiddenCalls -eq 0) 'strict reader performs no writer/lossy-reader/network/source processing'
    }finally{foreach($name in $saved.Keys){Set-Item "Function:$name" -Value $saved[$name]}}
    Check-Bridge ($inventory -ceq (Bridge-Inventory $store)) 'reader does not repair indexes or mutate immutable records'

    # Reader faults must produce one bounded rejection, with no partial capture
    # or diagnostic from any redirectable PowerShell stream.
    foreach($channel in @('Success','Warning','Information','Verbose','Debug','Host','Error','Throw')){
        $script:BridgeReadChannel=$channel
        $originalRead=(Get-Item Function:Read-InternalScopedHistoryFile).ScriptBlock
        try{
            Set-Item Function:Read-InternalScopedHistoryFile -Value {
                param($Store,$Path,$MaxBytes)
                switch($script:BridgeReadChannel){
                    Success {'PRIVATE_FAULT_SENTINEL'}
                    Warning {Write-Warning 'PRIVATE_FAULT_SENTINEL'}
                    Information {Write-Information 'PRIVATE_FAULT_SENTINEL' -InformationAction Continue}
                    Verbose {Write-Verbose 'PRIVATE_FAULT_SENTINEL' -Verbose}
                    Debug {Write-Debug 'PRIVATE_FAULT_SENTINEL' -Debug}
                    Host {Write-Host 'PRIVATE_FAULT_SENTINEL'}
                    Error {Write-Error 'PRIVATE_FAULT_SENTINEL'}
                    Throw {throw 'PRIVATE_FAULT_SENTINEL'}
                }
            }
            Reject-BridgeRead $store $id ("non-leaking reader failure: "+$channel)
        }finally{Set-Item Function:Read-InternalScopedHistoryFile -Value $originalRead}
    }

    # Existing staged comparison/CAS/lock semantics with real bridge packages.
    $p2=New-BridgeFixture;$p2.ObservedAt='2026-11-19T12:35:56.000+09:00'
    $b2=New-BenefitScopedHtmlHistoryPackage @p2
    $semantic=ConvertFrom-BenefitScopedEvidenceJson (@($b2.Package.PreparedArtifacts|Where-Object Kind -CEQ 'BENEFIT_SEMANTIC_PROJECTION')[0].Text)
    $comparison=Compare-BenefitHistoryObservations -Store $store -Previous $verified.Capture.Observation -Current $b2.Package.Observation -StagedCurrentSemanticProjection $semantic
    Check-Bridge ($comparison.ComparisonStatus -ceq 'COMPLETE' -and $comparison.ChangeCandidates.Count -eq 0) 'staged identical-evidence comparator parity'
    $prepared=Prepare-HistoryRun -Store $store -RunManifest (New-BridgeManifest $p2 $b2.Package.Observation) -Artifacts $b2.Package.PreparedArtifacts -Observations @($b2.Package.Observation) -Comparisons @($comparison)
    $commit2=Commit-HistoryRun -Store $store -PreparedRun $prepared -ExpectedBaselines @{$key=$id}
    Check-Bridge ($commit2.Code -ceq 'COMMITTED') 'second comparable baseline commits'
    $staleP=New-BridgeFixture;$staleP.ObservedAt='2026-11-19T12:36:56.000+09:00';$staleB=New-BenefitScopedHtmlHistoryPackage @staleP
    $stale=Commit-BridgePackage $store $staleP $staleB.Package @{$key=$id}
    Check-Bridge ($stale.Code -ceq 'BASELINE_MOVED') 'Core CAS conflict remains BASELINE_MOVED'
    Check-Bridge ((Get-HistoryLatestEntry $store $p.BusinessId BENEFIT -ComparableOnly).LatestComparableObservationId -ceq $b2.Package.Observation.ObservationId) 'stale attempt did not publish'
    $lockP=New-BridgeFixture;$lockB=New-BenefitScopedHtmlHistoryPackage @lockP
    $lock=[IO.File]::Open((Join-Path $store.Root '.writer-lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try{$locked=Commit-BridgePackage $store $lockP $lockB.Package @{$key=$b2.Package.Observation.ObservationId};Check-Bridge ($locked.Code -ceq 'WRITER_LOCKED') 'Core writer lock remains WRITER_LOCKED'}finally{$lock.Dispose()}
    $repairP=New-BridgeFixture;$repairP.ObservedAt='2026-11-19T12:37:56.000+09:00';$repairB=New-BenefitScopedHtmlHistoryPackage @repairP
    $postFault={param($Name)if($Name -ceq 'AFTER_MANIFEST_COMMIT'){throw 'SYNTHETIC_INDEX_REPAIR_FAULT'}}
    $repair=Commit-BridgePackage $store $repairP $repairB.Package @{$key=$b2.Package.Observation.ObservationId} $postFault
    Check-Bridge ($repair.Code -ceq 'COMMITTED' -and $repair.IndexRepairRequired) 'post-commit index fault remains terminal COMMITTED'
    $before=Bridge-Inventory $store
    $repairRead=Read-BenefitScopedHtmlCommittedCapture $store $repairB.Package.Observation.ObservationId
    Check-Bridge ($repairRead.Status -ceq 'VERIFIED' -and $before -ceq (Bridge-Inventory $store)) 'committed reader verifies without index repair/retry'
    Write-Host "PASS: C-Lite History bridge assertions=$script:BridgeChecks"
}finally{
    foreach($root in $script:BridgeTestRoots){
        $resolved=[IO.Path]::GetFullPath($root)
        $prefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
        if(-not $resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -cnotmatch '^milimap-pr2c-[0-9a-f]{32}$'){throw 'Unsafe test Store cleanup'}
        if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
    }
}

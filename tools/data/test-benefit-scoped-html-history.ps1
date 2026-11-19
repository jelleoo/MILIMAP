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

    # PR 2D (Issue #145): inactive ReuseDecision v2 persistence bridge and committed reuse verifier.
    Check-Bridge ([bool](Get-Command New-BenefitScopedHtmlReusePackage -ErrorAction SilentlyContinue)) 'reuse persistence bridge function exists'
    Check-Bridge ([bool](Get-Command Read-BenefitScopedHtmlCommittedReuse -ErrorAction SilentlyContinue)) 'committed reuse verifier function exists'

    function New-ReuseBridgeInput {
        param([string]$RunId=('run-pr2d-'+[guid]::NewGuid().ToString('N')),[string]$ObservedAt='2026-11-19T13:00:00.000+09:00',[string]$Html=((Get-ScopeTestHtml)+'<!--RAW_SOURCE_SENTINEL-->'),[string]$Url='https://city.example.go.kr/list')
        $ctx=New-BenefitSourceRunContext
        $biz=New-ScopeTestBusiness
        $cand=New-BenefitSourceCandidate -SourceRowNumber 2 -Url $Url -SourceKind PUBLIC_OFFICIAL
        $req={param($Uri)[pscustomobject]@{StatusCode=200;ContentType='text/html';Text=$Html;Bytes=$null}}.GetNewClosure()
        $doc=Get-BenefitRunSourceDocument -Context $ctx -Candidate $cand -RequestInvoker $req
        $snap=Get-BenefitRunSourceSnapshot -Context $ctx -Document $doc
        @{
            RunContext=$ctx;Candidate=$cand;Document=$doc;Snapshot=$snap
            Benefit=(New-CanonicalBenefitRecord -SourceRowNumber 2 -BusinessName $biz.OriginalName -BenefitDescription '10% 할인' -ExistingSourceType '지자체 공식 자료' -ExistingSourceUrl $Url)
            BusinessId='biz-0123456789abcdef0123456789abcdef';BusinessIdentity=$biz;CanonicalPhone=''
            RunId=$RunId;ObservedAt=$ObservedAt;RepositoryRevision=('a'*40);RepositoryClean=$true
        }
    }
    function Commit-ReuseBridgePackage($Store,$ReuseInput,$Package,[hashtable]$ExpectedBaselines,[scriptblock]$FaultInjector=$null){
        $manifest=New-HistoryRunManifest -RunId $ReuseInput.RunId -StartedAt $ReuseInput.ObservedAt -CompletedAt '' -RepositoryRevision $ReuseInput.RepositoryRevision -RequestedBusinessIds @($ReuseInput.BusinessId) -CompletedBusinessIds @($ReuseInput.BusinessId) -FailedBusinessIds @() -ExecutionStatus 'COMPLETE' -RunCommitStatus 'PREPARED'
        $prepared=Prepare-HistoryRun -Store $Store -RunManifest $manifest -Artifacts $Package.PreparedArtifacts -Observations @($Package.Observation) -Comparisons @($Package.Comparison)
        Commit-HistoryRun -Store $Store -PreparedRun $prepared -ExpectedBaselines $ExpectedBaselines -FaultInjector $FaultInjector
    }
    function Reject-ReusePackage($Parameters,[string]$Label){
        $values=@(New-BenefitScopedHtmlReusePackage @Parameters *>&1)
        Check-Bridge ($values.Count -eq 1 -and $values[0].Status -ceq 'REJECTED' -and $null -eq $values[0].Package -and $values[0].ReasonCode -ceq 'C_LITE_REUSE_PACKAGE_REJECTED') $Label
    }
    function Reject-ReuseRead($Store,$Id,[string]$Label){
        $values=@(Read-BenefitScopedHtmlCommittedReuse -Store $Store -ObservationId $Id *>&1)
        Check-Bridge ($values.Count -eq 1 -and $values[0].Status -ceq 'REJECTED' -and $null -eq $values[0].Reuse -and $values[0].ReasonCode -ceq 'C_LITE_COMMITTED_REUSE_REJECTED') $Label
    }

    $reuseStore=New-BridgeTestStore
    $capInput=New-BridgeFixture 'LOCATED_FIELDS'
    $capBuilt=New-BenefitScopedHtmlHistoryPackage @capInput
    $capCommit=Commit-BridgePackage $reuseStore $capInput $capBuilt.Package @{($capInput.BusinessId+'|BENEFIT')=''}
    Check-Bridge ($capCommit.Code -ceq 'COMMITTED') 'PR2D capture baseline commits'
    $capId=$capBuilt.Package.Observation.ObservationId

    # 1st-hop reuse from committed capture baseline; ensure zero parse/extract/eval/index-lookup/writer calls.
    $hop1In=New-ReuseBridgeInput -ObservedAt '2026-11-19T13:10:00.000+09:00'
    $hop1Args=@{Store=$reuseStore;PreviousObservationId=$capId;RunContext=$hop1In.RunContext;Candidate=$hop1In.Candidate;Document=$hop1In.Document;Benefit=$hop1In.Benefit;BusinessId=$hop1In.BusinessId;BusinessIdentity=$hop1In.BusinessIdentity;CanonicalPhone=$hop1In.CanonicalPhone;RunId=$hop1In.RunId;ObservedAt=$hop1In.ObservedAt;RepositoryRevision=$hop1In.RepositoryRevision;RepositoryClean=$hop1In.RepositoryClean}
    $script:BridgeForbiddenCalls=0;$guardSaved=@{};$invBefore=Bridge-Inventory $reuseStore
    try{
        foreach($name in @('Prepare-HistoryRun','Commit-HistoryRun','Get-HistoryLatestEntry','Rebuild-HistoryIndexes','ConvertTo-InternalBenefitHtmlTemplate','Get-ScopeHtmlTagTokens','New-ScopeHtmlValidationIndex','New-InternalScopeHtmlValidationIndex','Invoke-BenefitEvidenceExtraction','ConvertTo-ValidatedBenefitEvidence','Invoke-BenefitStateEvaluation')){
            $guardSaved[$name]=(Get-Item "Function:$name").ScriptBlock
            Set-Item "Function:$name" -Value {$script:BridgeForbiddenCalls++;throw 'FORBIDDEN_REUSE_BRIDGE_WORK'}
        }
        $hop1Pkg=New-BenefitScopedHtmlReusePackage @hop1Args
    }finally{foreach($name in $guardSaved.Keys){Set-Item "Function:$name" -Value $guardSaved[$name]}}
    Check-Bridge ($hop1Pkg.Status -ceq 'READY' -and $hop1Pkg.ReasonCode -ceq 'C_LITE_REUSE_PACKAGE_READY') '1st-hop reuse package READY'
    Check-Bridge ($script:BridgeForbiddenCalls -eq 0 -and $invBefore -ceq (Bridge-Inventory $reuseStore)) '1st-hop reuse build performs no forbidden parse/eval/write/index work'
    Check-Bridge ($hop1Pkg.Package.PreparedArtifacts.Count -eq 1 -and $hop1Pkg.Package.PreparedArtifacts[0].Kind -ceq 'BENEFIT_REUSE_DECISION') 'reuse prepares only single BenefitReuseDecision artifact'
    Check-Bridge ($hop1Pkg.Package.Observation.ArtifactReferences.Count -eq 4 -and @($hop1Pkg.Package.Observation.ArtifactReferences|Where-Object Kind -CEQ 'RAW_SOURCE_PAYLOAD').Count -eq 0) 'reuse observation has 4 refs and 0 RAW'
    Check-Bridge ($hop1Pkg.Package.Comparison.ComparisonStatus -ceq 'COMPLETE' -and $hop1Pkg.Package.Comparison.DeltaDimensions.Count -eq 0 -and $hop1Pkg.Package.Comparison.ChangeCandidates.Count -eq 0 -and $hop1Pkg.Package.Comparison.ReasonCodes.Count -eq 0) 'reuse comparison is empty-delta COMPLETE'
    $hop1Commit=Commit-ReuseBridgePackage $reuseStore $hop1In $hop1Pkg.Package @{($hop1In.BusinessId+'|BENEFIT')=$capId}
    Check-Bridge ($hop1Commit.Code -ceq 'COMMITTED') '1st-hop reuse commits'
    $hop1Id=$hop1Pkg.Package.Observation.ObservationId
    $invAfterHop1=Bridge-Inventory $reuseStore
    $hop1Read=Read-BenefitScopedHtmlCommittedReuse -Store $reuseStore -ObservationId $hop1Id
    Check-Bridge ($hop1Read.Status -ceq 'VERIFIED' -and $hop1Read.ReasonCode -ceq 'C_LITE_COMMITTED_REUSE_VERIFIED') '1st-hop committed reuse verifies'
    Check-Bridge ($hop1Read.Reuse.OwnerObservationId -ceq $capId -and $hop1Read.Reuse.ReuseDecision.ReusedFromObservationId -ceq $capId -and $hop1Read.Reuse.Artifacts.Count -eq 4) '1st-hop reuse preserves capture owner and 4 artifacts'
    Check-Bridge ($invAfterHop1 -ceq (Bridge-Inventory $reuseStore)) 'reuse reader is strictly read-only'
    Check-Bridge ((ConvertTo-HistoryCanonicalJson $hop1Read) -cnotmatch 'RAW_SOURCE_SENTINEL|테스트가게 B') 'no raw/cross-business leakage in reuse read'

    # Multi-hop (hop2 and hop3) + O(1) non-recursive verification (hop3 never opens hop1).
    $hop2In=New-ReuseBridgeInput -ObservedAt '2026-11-19T13:20:00.000+09:00'
    $hop2Pkg=New-BenefitScopedHtmlReusePackage -Store $reuseStore -PreviousObservationId $hop1Id -RunContext $hop2In.RunContext -Candidate $hop2In.Candidate -Document $hop2In.Document -Benefit $hop2In.Benefit -BusinessId $hop2In.BusinessId -BusinessIdentity $hop2In.BusinessIdentity -CanonicalPhone $hop2In.CanonicalPhone -RunId $hop2In.RunId -ObservedAt $hop2In.ObservedAt -RepositoryRevision $hop2In.RepositoryRevision -RepositoryClean $true
    Check-Bridge ($hop2Pkg.Status -ceq 'READY' -and $hop2Pkg.Package.Observation.ArtifactReferences.Count -eq 4 -and $hop2Pkg.Package.ReuseDecision.ReusedFromObservationId -ceq $hop1Id) '2nd-hop reuse keeps exactly 4 refs'
    $hop2Commit=Commit-ReuseBridgePackage $reuseStore $hop2In $hop2Pkg.Package @{($hop2In.BusinessId+'|BENEFIT')=$hop1Id}
    Check-Bridge ($hop2Commit.Code -ceq 'COMMITTED') '2nd-hop reuse commits'
    $hop2Id=$hop2Pkg.Package.Observation.ObservationId

    $hop3In=New-ReuseBridgeInput -ObservedAt '2026-11-19T13:30:00.000+09:00'
    $hop3Pkg=New-BenefitScopedHtmlReusePackage -Store $reuseStore -PreviousObservationId $hop2Id -RunContext $hop3In.RunContext -Candidate $hop3In.Candidate -Document $hop3In.Document -Benefit $hop3In.Benefit -BusinessId $hop3In.BusinessId -BusinessIdentity $hop3In.BusinessIdentity -CanonicalPhone $hop3In.CanonicalPhone -RunId $hop3In.RunId -ObservedAt $hop3In.ObservedAt -RepositoryRevision $hop3In.RepositoryRevision -RepositoryClean $true
    $hop3Commit=Commit-ReuseBridgePackage $reuseStore $hop3In $hop3Pkg.Package @{($hop3In.BusinessId+'|BENEFIT')=$hop2Id}
    Check-Bridge ($hop3Commit.Code -ceq 'COMMITTED') '3rd-hop reuse commits'
    $hop3Id=$hop3Pkg.Package.Observation.ObservationId

    $script:BridgeReadPaths=[Collections.Generic.List[string]]::new()
    $origReadFile=(Get-Item Function:Read-InternalScopedHistoryFile).ScriptBlock
    try{
        Set-Item Function:Read-InternalScopedHistoryFile -Value {
            param($Store,[string]$Path,[int]$MaxBytes)
            $script:BridgeReadPaths.Add([IO.Path]::GetFullPath($Path))
            & $origReadFile $Store $Path $MaxBytes
        }
        $hop3Read=Read-BenefitScopedHtmlCommittedReuse -Store $reuseStore -ObservationId $hop3Id
    }finally{Set-Item Function:Read-InternalScopedHistoryFile -Value $origReadFile}
    Check-Bridge ($hop3Read.Status -ceq 'VERIFIED' -and $hop3Read.Reuse.OwnerObservationId -ceq $capId -and $hop3Read.Reuse.ReuseDecision.ReusedFromObservationId -ceq $hop2Id) '3rd-hop committed reuse verifies'
    $hop1ObsFull=[IO.Path]::GetFullPath((Get-HistoryObservationPath $reuseStore $hop1Id))
    $hop1ManFull=[IO.Path]::GetFullPath((Get-HistoryRunManifestPath $reuseStore $hop1In.RunId))
    Check-Bridge (($script:BridgeReadPaths -cnotcontains $hop1ObsFull) -and ($script:BridgeReadPaths -cnotcontains $hop1ManFull)) 'O(1) non-recursive reuse reader never walks hop1'

    # Pre-Prepare reuse rejection matrix.
    foreach($nonEligibleKind in @('OUTCOME_ONLY','ZERO_CLAIM','PARTIAL','UNSUPPORTED','PARSER_FAILURE')){
        $neStore=New-BridgeTestStore
        if($nonEligibleKind -ceq 'PARSER_FAILURE'){
            $origT=(Get-Item Function:ConvertTo-InternalBenefitHtmlTemplate).ScriptBlock
            try{Set-Item Function:ConvertTo-InternalBenefitHtmlTemplate -Value {param($Snapshot)throw 'PRIVATE_PARSER_SENTINEL'};$np=New-BridgeFixture}
            finally{Set-Item Function:ConvertTo-InternalBenefitHtmlTemplate -Value $origT}
        }else{$np=New-BridgeFixture $nonEligibleKind}
        $nb=New-BenefitScopedHtmlHistoryPackage @np
        $nc=Commit-BridgePackage $neStore $np $nb.Package @{($np.BusinessId+'|BENEFIT')=''}
        Check-Bridge ($nc.Code -ceq 'COMMITTED') "$nonEligibleKind non-eligible fixture committed"
        $rIn=New-ReuseBridgeInput -ObservedAt '2026-11-19T13:40:00.000+09:00'
        $rArgs=@{Store=$neStore;PreviousObservationId=$nb.Package.Observation.ObservationId;RunContext=$rIn.RunContext;Candidate=$rIn.Candidate;Document=$rIn.Document;Benefit=$rIn.Benefit;BusinessId=$rIn.BusinessId;BusinessIdentity=$rIn.BusinessIdentity;CanonicalPhone=$rIn.CanonicalPhone;RunId=$rIn.RunId;ObservedAt=$rIn.ObservedAt;RepositoryRevision=$rIn.RepositoryRevision;RepositoryClean=$true}
        Reject-ReusePackage $rArgs "non-eligible baseline rejected: $nonEligibleKind"
    }
    # Reset latest comparable baseline back to a fresh store for tamper/legacy/eligibility tests.
    $legacyStore=New-BridgeTestStore
    $lCapIn=New-BridgeFixture 'LOCATED_FIELDS'
    $lCapBuilt=New-BenefitScopedHtmlHistoryPackage @lCapIn
    $null=Commit-BridgePackage $legacyStore $lCapIn $lCapBuilt.Package @{($lCapIn.BusinessId+'|BENEFIT')=''}
    $lCapId=$lCapBuilt.Package.Observation.ObservationId
    $lBad=$lCapIn.RunContext;$lCapPkg=$lCapBuilt.Package

    # Legacy baseline (LEGACY execution fingerprint + no scoped ref) rejected for C-Lite reuse.
    $legacyPkg=New-BenefitHistoryObservationPackage -Store $legacyStore -RunId ('run-leg-'+[guid]::NewGuid().ToString('N')) -BusinessId $lCapIn.BusinessId -ObservedAt '2026-11-19T12:00:00.000+09:00' -RepositoryRevision $lCapIn.RepositoryRevision -Benefit $lCapIn.Benefit -BusinessIdentity $lCapIn.BusinessIdentity -Result $lCapIn.Result -EvidenceDiagnostics @([pscustomobject]@{Url='https://city.example.go.kr/list';SourceFormat='HTML';FetchStatus='COMPLETE';ContentHash=$lCapIn.RunContext.PayloadCache['https://city.example.go.kr/list'].SourceSnapshot.ContentHash;AdapterId='HTML_GENERIC';AdapterVersion='1';AdapterStatus='COMPLETE';LocationOperationalStatus='COMPLETE';LocationStatus='LOCATED';CandidateReferences=@('HTML_TABLE_1_ROW_2');OfficialityStatus='VERIFIED_OFFICIAL';BusinessBindingStatus='STRONG';ExtractionStatus='COMPLETE'}) -OperationalStatus $lCapIn.OperationalStatus
    $legManifest=New-HistoryRunManifest -RunId $legacyPkg.Observation.RunId -StartedAt $legacyPkg.Observation.ObservedAt -CompletedAt '' -RepositoryRevision $lCapIn.RepositoryRevision -RequestedBusinessIds @($lCapIn.BusinessId) -CompletedBusinessIds @($lCapIn.BusinessId) -FailedBusinessIds @() -ExecutionStatus 'COMPLETE' -RunCommitStatus 'PREPARED'
    $legPrep=Prepare-HistoryRun -Store $legacyStore -RunManifest $legManifest -Artifacts $legacyPkg.PreparedArtifacts -Observations @($legacyPkg.Observation) -Comparisons @()
    $legCommit=Commit-HistoryRun -Store $legacyStore -PreparedRun $legPrep -ExpectedBaselines @{($lCapIn.BusinessId+'|BENEFIT')=$lCapId}
    Check-Bridge ($legCommit.Code -ceq 'COMMITTED') 'Legacy baseline committed for rejection test'

    $baseReuseIn=New-ReuseBridgeInput -ObservedAt '2026-11-19T14:00:00.000+09:00'
    $baseReuseArgs=@{Store=$legacyStore;PreviousObservationId=$lCapId;RunContext=$baseReuseIn.RunContext;Candidate=$baseReuseIn.Candidate;Document=$baseReuseIn.Document;Benefit=$baseReuseIn.Benefit;BusinessId=$baseReuseIn.BusinessId;BusinessIdentity=$baseReuseIn.BusinessIdentity;CanonicalPhone=$baseReuseIn.CanonicalPhone;RunId=$baseReuseIn.RunId;ObservedAt=$baseReuseIn.ObservedAt;RepositoryRevision=$baseReuseIn.RepositoryRevision;RepositoryClean=$true}
    foreach($case in @(
        @{Name='legacyBaseline';Setup={param($a)$a.PreviousObservationId=$legacyPkg.Observation.ObservationId}},
        @{Name='missingBaseline';Setup={param($a)$a.PreviousObservationId='obs-'+('e'*32)}},
        @{Name='dirtyRepo';Setup={param($a)$a.RepositoryClean=$false}},
        @{Name='inputBenefitChanged';Setup={param($a)$a.Benefit.BenefitDescription='20% 할인'}},
        @{Name='inputPhoneChanged';Setup={param($a)$a.CanonicalPhone='02-9999-9999'}},
        @{Name='executionRevisionChanged';Setup={param($a)$a.RepositoryRevision=('b'*40)}},
        @{Name='payloadChanged';Setup={param($a)$ri=New-ReuseBridgeInput -ObservedAt '2026-11-19T14:01:00.000+09:00' -Html ((Get-ScopeTestHtml).Replace('10% 할인','20% 할인'));$a.RunContext=$ri.RunContext;$a.Candidate=$ri.Candidate;$a.Document=$ri.Document}},
        @{Name='urlChanged';Setup={param($a)$ri=New-ReuseBridgeInput -ObservedAt '2026-11-19T14:02:00.000+09:00' -Url 'https://city.example.go.kr/other';$a.RunContext=$ri.RunContext;$a.Candidate=$ri.Candidate;$a.Document=$ri.Document}},
        @{Name='copiedDocumentText';Setup={param($a)$a.Document=Copy-BridgeData $a.Document}},
        @{Name='nonOfficialCandidate';Setup={param($a)$a.Candidate.SourceKind='UNOFFICIAL_DISCOVERY'}},
        @{Name='failedDocument';Setup={param($a)$a.Document.FetchStatus='FAILED'}},
        @{Name='nonHtmlDocument';Setup={param($a)$a.Document.SourceFormat='XLSX'}},
        @{Name='sameRunIdAsCapture';Setup={param($a)$a.RunId=$lCapIn.RunId}},
        @{Name='sameObservedAtAsCapture';Setup={param($a)$a.ObservedAt=$lCapIn.ObservedAt}},
        @{Name='unsafeRunId';Setup={param($a)$a.RunId='../escape'}},
        @{Name='unsafePrevId';Setup={param($a)$a.PreviousObservationId='../escape'}}
    )){
        $ri=New-ReuseBridgeInput -ObservedAt '2026-11-19T14:00:00.000+09:00'
        $a=@{Store=$legacyStore;PreviousObservationId=$lCapId;RunContext=$ri.RunContext;Candidate=$ri.Candidate;Document=$ri.Document;Benefit=$ri.Benefit;BusinessId=$ri.BusinessId;BusinessIdentity=$ri.BusinessIdentity;CanonicalPhone=$ri.CanonicalPhone;RunId=$ri.RunId;ObservedAt=$ri.ObservedAt;RepositoryRevision=$ri.RepositoryRevision;RepositoryClean=$true}
        & $case.Setup $a
        Reject-ReusePackage $a ("reuse package rejection: "+$case.Name)
    }

    # Committed reuse read boundary attacks on real hop2 in dedicated store.
    $atkStore=New-BridgeTestStore
    $aCapIn=New-BridgeFixture 'LOCATED_FIELDS'
    $aCapBuilt=New-BenefitScopedHtmlHistoryPackage @aCapIn
    $null=Commit-BridgePackage $atkStore $aCapIn $aCapBuilt.Package @{($aCapIn.BusinessId+'|BENEFIT')=''}
    $aCapId=$aCapBuilt.Package.Observation.ObservationId
    $aHop1In=New-ReuseBridgeInput -ObservedAt '2026-11-19T15:00:00.000+09:00'
    $aHop1Pkg=New-BenefitScopedHtmlReusePackage -Store $atkStore -PreviousObservationId $aCapId -RunContext $aHop1In.RunContext -Candidate $aHop1In.Candidate -Document $aHop1In.Document -Benefit $aHop1In.Benefit -BusinessId $aHop1In.BusinessId -BusinessIdentity $aHop1In.BusinessIdentity -CanonicalPhone $aHop1In.CanonicalPhone -RunId $aHop1In.RunId -ObservedAt $aHop1In.ObservedAt -RepositoryRevision $aHop1In.RepositoryRevision -RepositoryClean $true
    $null=Commit-ReuseBridgePackage $atkStore $aHop1In $aHop1Pkg.Package @{($aHop1In.BusinessId+'|BENEFIT')=$aCapId}
    $aHop1Id=$aHop1Pkg.Package.Observation.ObservationId
    $aHop2In=New-ReuseBridgeInput -ObservedAt '2026-11-19T15:10:00.000+09:00'
    $aHop2Pkg=New-BenefitScopedHtmlReusePackage -Store $atkStore -PreviousObservationId $aHop1Id -RunContext $aHop2In.RunContext -Candidate $aHop2In.Candidate -Document $aHop2In.Document -Benefit $aHop2In.Benefit -BusinessId $aHop2In.BusinessId -BusinessIdentity $aHop2In.BusinessIdentity -CanonicalPhone $aHop2In.CanonicalPhone -RunId $aHop2In.RunId -ObservedAt $aHop2In.ObservedAt -RepositoryRevision $aHop2In.RepositoryRevision -RepositoryClean $true
    $null=Commit-ReuseBridgePackage $atkStore $aHop2In $aHop2Pkg.Package @{($aHop2In.BusinessId+'|BENEFIT')=$aHop1Id}
    $aHop2Id=$aHop2Pkg.Package.Observation.ObservationId

    $aHop2ObsPath=Get-HistoryObservationPath $atkStore $aHop2Id
    $aHop2ManPath=Get-HistoryRunManifestPath $atkStore $aHop2In.RunId
    $aHop2CmpId=New-HistoryComparisonId -RunId $aHop2In.RunId -BusinessId $aHop2In.BusinessId -Domain BENEFIT -PreviousObservationId $aHop1Id -CurrentObservationId $aHop2Id
    $aHop2CmpPath=Get-HistoryComparisonPath $atkStore $aHop2CmpId
    $aHop2DecRef=@($aHop2Pkg.Package.Observation.ArtifactReferences|Where-Object Kind -CEQ 'BENEFIT_REUSE_DECISION')[0]
    $aHop2DecPath=Get-HistoryArtifactPath $atkStore $aHop2DecRef.ContentHash json
    $aHop1ManPath=Get-HistoryRunManifestPath $atkStore $aHop1In.RunId
    $aHop1DecRef=@($aHop1Pkg.Package.Observation.ArtifactReferences|Where-Object Kind -CEQ 'BENEFIT_REUSE_DECISION')[0]
    $aHop1DecPath=Get-HistoryArtifactPath $atkStore $aHop1DecRef.ContentHash json

    $origHop2Obs=[IO.File]::ReadAllBytes($aHop2ObsPath)
    $origHop2Man=[IO.File]::ReadAllBytes($aHop2ManPath)
    $origHop2Cmp=[IO.File]::ReadAllBytes($aHop2CmpPath)
    $origHop2Dec=[IO.File]::ReadAllBytes($aHop2DecPath)
    $origHop1Man=[IO.File]::ReadAllBytes($aHop1ManPath)
    $origHop1Dec=[IO.File]::ReadAllBytes($aHop1DecPath)

    try{
        [IO.File]::WriteAllText($aHop2DecPath,'PRIVATE_FAULT_SENTINEL',[Text.UTF8Encoding]::new($false))
        Reject-ReuseRead $atkStore $aHop2Id 'corrupted reuse decision bytes rejected'
    }finally{[IO.File]::WriteAllBytes($aHop2DecPath,$origHop2Dec)}
    try{
        Remove-Item -LiteralPath $aHop2CmpPath -Force
        Reject-ReuseRead $atkStore $aHop2Id 'missing comparison rejected'
    }finally{[IO.File]::WriteAllBytes($aHop2CmpPath,$origHop2Cmp)}
    try{
        $cmpObj=ConvertFrom-BenefitScopedEvidenceJson ([Text.Encoding]::UTF8.GetString($origHop2Cmp))
        $cmpObj.DeltaDimensions=@('SEMANTIC');$cmpObj.ChangeCandidates=@('BENEFIT_CHANGE_SUSPECTED')
        [IO.File]::WriteAllText($aHop2CmpPath,(ConvertTo-HistoryCanonicalJson $cmpObj),[Text.UTF8Encoding]::new($false))
        Reject-ReuseRead $atkStore $aHop2Id 'non-empty delta comparison rejected'
    }finally{[IO.File]::WriteAllBytes($aHop2CmpPath,$origHop2Cmp)}
    try{
        $manObj=ConvertFrom-BenefitScopedEvidenceJson ([Text.Encoding]::UTF8.GetString($origHop1Man))
        $manObj.RunCommitStatus='PREPARED'
        [IO.File]::WriteAllText($aHop1ManPath,(ConvertTo-HistoryCanonicalJson $manObj),[Text.UTF8Encoding]::new($false))
        Reject-ReuseRead $atkStore $aHop2Id 'non-committed predecessor manifest rejected'
    }finally{[IO.File]::WriteAllBytes($aHop1ManPath,$origHop1Man)}
    try{
        Remove-Item -LiteralPath $aHop1DecPath -Force
        Reject-ReuseRead $atkStore $aHop2Id 'missing predecessor v2 decision rejected'
    }finally{[IO.File]::WriteAllBytes($aHop1DecPath,$origHop1Dec)}
    try{
        $obsObj=ConvertFrom-BenefitScopedEvidenceJson ([Text.Encoding]::UTF8.GetString($origHop2Obs))
        $obsObj.ObservedAt='2026-11-19T06:10:00Z'
        [IO.File]::WriteAllText($aHop2ObsPath,(ConvertTo-HistoryCanonicalJson $obsObj),[Text.UTF8Encoding]::new($false))
        Reject-ReuseRead $atkStore $aHop2Id 'lexical timestamp tampering on reuse obs rejected'
    }finally{[IO.File]::WriteAllBytes($aHop2ObsPath,$origHop2Obs)}
    $badPath=$null
    try{
        $decText=[Text.Encoding]::UTF8.GetString($origHop2Dec)
        $badDec='{"ContractVersion":2,'+$decText.Substring(1)
        $badHash=Get-HistorySha256 $badDec
        $badPath=Get-HistoryArtifactPath $atkStore $badHash json
        [IO.File]::WriteAllText($badPath,$badDec,[Text.UTF8Encoding]::new($false))
        $obsObj=ConvertFrom-BenefitScopedEvidenceJson ([Text.Encoding]::UTF8.GetString($origHop2Obs))
        $obsObj.ArtifactReferences[3].ContentHash=$badHash;$obsObj.ArtifactReferences[3].RelativePath='artifacts/sha256/'+$badHash+'.json'
        [IO.File]::WriteAllText($aHop2ObsPath,(ConvertTo-HistoryCanonicalJson $obsObj),[Text.UTF8Encoding]::new($false))
        Reject-ReuseRead $atkStore $aHop2Id 'rehashed duplicate-key reuse decision rejected'
    }finally{
        [IO.File]::WriteAllBytes($aHop2ObsPath,$origHop2Obs)
        if($badPath -and (Test-Path -LiteralPath $badPath)){Remove-Item -LiteralPath $badPath -Force}
    }
    try{
        $obsObj=ConvertFrom-BenefitScopedEvidenceJson ([Text.Encoding]::UTF8.GetString($origHop2Obs))
        $obsObj.ExecutionFingerprint='f'*64
        [IO.File]::WriteAllText($aHop2ObsPath,(ConvertTo-HistoryCanonicalJson $obsObj),[Text.UTF8Encoding]::new($false))
        Reject-ReuseRead $atkStore $aHop2Id 'PROFILE_UNKNOWN reuse observation rejected'
    }finally{[IO.File]::WriteAllBytes($aHop2ObsPath,$origHop2Obs)}

    # Concurrent change detected on comparison re-read during scan rejects without retry.
    $script:BridgeCmpReadCount=0
    $origReadScan=(Get-Item Function:Read-InternalScopedHistoryFile).ScriptBlock
    try{
        Set-Item Function:Read-InternalScopedHistoryFile -Value {
            param($Store,[string]$Path,[int]$MaxBytes)
            $res=& $origReadScan $Store $Path $MaxBytes
            if([IO.Path]::GetFullPath($Path) -ceq [IO.Path]::GetFullPath($aHop2CmpPath)){
                $script:BridgeCmpReadCount++
                if($script:BridgeCmpReadCount -ge 2){$res.Text=$res.Text+' '}
            }
            return $res
        }
        Reject-ReuseRead $atkStore $aHop2Id 'concurrent comparison modification during scan rejected'
    }finally{Set-Item Function:Read-InternalScopedHistoryFile -Value $origReadScan}

    # Reparse point / junction on ComparisonsRoot rejected.
    $cmpOutside=New-BridgeTestStore
    $movedCmp=Assert-HistoryStorePathWithinRoot $cmpOutside (Join-Path $cmpOutside.Root 'moved-comparisons')
    $linkCmp=Assert-HistoryStorePathWithinRoot $atkStore $atkStore.ComparisonsRoot
    [IO.Directory]::Move($linkCmp,$movedCmp)
    try{
        $linkType=if([OperatingSystem]::IsWindows()){'Junction'}else{'SymbolicLink'}
        $null=New-Item -ItemType $linkType -Path $linkCmp -Target $movedCmp
        Reject-ReuseRead $atkStore $aHop2Id 'filesystem junction/symlink cannot redirect comparison reads'
    }finally{
        if([IO.Directory]::Exists($linkCmp)){
            if(([IO.File]::GetAttributes($linkCmp) -band [IO.FileAttributes]::ReparsePoint) -eq 0){throw 'Expected test-only comparison reparse link'}
            [IO.Directory]::Delete($linkCmp)
        }
        [IO.Directory]::Move($movedCmp,$linkCmp)
    }

    # Stream non-leakage on reuse reader fault.
    foreach($channel in @('Success','Warning','Error','Throw')){
        $script:BridgeReadChannel=$channel
        $origR=(Get-Item Function:Read-InternalScopedHistoryFile).ScriptBlock
        try{
            Set-Item Function:Read-InternalScopedHistoryFile -Value {
                param($Store,$Path,[int]$MaxBytes)
                switch($script:BridgeReadChannel){
                    Success {'PRIVATE_FAULT_SENTINEL'}
                    Warning {Write-Warning 'PRIVATE_FAULT_SENTINEL'}
                    Error {Write-Error 'PRIVATE_FAULT_SENTINEL'}
                    Throw {throw 'PRIVATE_FAULT_SENTINEL'}
                }
            }
            Reject-ReuseRead $atkStore $aHop2Id ("non-leaking reuse reader failure: "+$channel)
        }finally{Set-Item Function:Read-InternalScopedHistoryFile -Value $origR}
    }
    Reject-ReuseRead $atkStore '../escape' 'reuse observation path traversal rejected'

    # CAS / lock / terminal COMMITTED + IndexRepairRequired on reuse packages.
    $staleReuseIn=New-ReuseBridgeInput -ObservedAt '2026-11-19T15:20:00.000+09:00'
    $staleReusePkg=New-BenefitScopedHtmlReusePackage -Store $atkStore -PreviousObservationId $aHop2Id -RunContext $staleReuseIn.RunContext -Candidate $staleReuseIn.Candidate -Document $staleReuseIn.Document -Benefit $staleReuseIn.Benefit -BusinessId $staleReuseIn.BusinessId -BusinessIdentity $staleReuseIn.BusinessIdentity -CanonicalPhone $staleReuseIn.CanonicalPhone -RunId $staleReuseIn.RunId -ObservedAt $staleReuseIn.ObservedAt -RepositoryRevision $staleReuseIn.RepositoryRevision -RepositoryClean $true
    $moverReuseIn=New-ReuseBridgeInput -ObservedAt '2026-11-19T15:21:00.000+09:00'
    $moverReusePkg=New-BenefitScopedHtmlReusePackage -Store $atkStore -PreviousObservationId $aHop2Id -RunContext $moverReuseIn.RunContext -Candidate $moverReuseIn.Candidate -Document $moverReuseIn.Document -Benefit $moverReuseIn.Benefit -BusinessId $moverReuseIn.BusinessId -BusinessIdentity $moverReuseIn.BusinessIdentity -CanonicalPhone $moverReuseIn.CanonicalPhone -RunId $moverReuseIn.RunId -ObservedAt $moverReuseIn.ObservedAt -RepositoryRevision $moverReuseIn.RepositoryRevision -RepositoryClean $true
    $moverCommit=Commit-ReuseBridgePackage $atkStore $moverReuseIn $moverReusePkg.Package @{($moverReuseIn.BusinessId+'|BENEFIT')=$aHop2Id}
    Check-Bridge ($moverCommit.Code -ceq 'COMMITTED') 'concurrent reuse moves baseline'
    $moverId=$moverReusePkg.Package.Observation.ObservationId
    $staleCommit=Commit-ReuseBridgePackage $atkStore $staleReuseIn $staleReusePkg.Package @{($staleReuseIn.BusinessId+'|BENEFIT')=$aHop2Id}
    Check-Bridge ($staleCommit.Code -ceq 'BASELINE_MOVED') 'reuse CAS conflict remains BASELINE_MOVED'
    $lockReuseIn=New-ReuseBridgeInput -ObservedAt '2026-11-19T15:22:00.000+09:00'
    $lockReusePkg=New-BenefitScopedHtmlReusePackage -Store $atkStore -PreviousObservationId $moverId -RunContext $lockReuseIn.RunContext -Candidate $lockReuseIn.Candidate -Document $lockReuseIn.Document -Benefit $lockReuseIn.Benefit -BusinessId $lockReuseIn.BusinessId -BusinessIdentity $lockReuseIn.BusinessIdentity -CanonicalPhone $lockReuseIn.CanonicalPhone -RunId $lockReuseIn.RunId -ObservedAt $lockReuseIn.ObservedAt -RepositoryRevision $lockReuseIn.RepositoryRevision -RepositoryClean $true
    $reuseLock=[IO.File]::Open((Join-Path $atkStore.Root '.writer-lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try{$lockedReuse=Commit-ReuseBridgePackage $atkStore $lockReuseIn $lockReusePkg.Package @{($lockReuseIn.BusinessId+'|BENEFIT')=$moverId};Check-Bridge ($lockedReuse.Code -ceq 'WRITER_LOCKED') 'reuse writer lock remains WRITER_LOCKED'}finally{$reuseLock.Dispose()}
    $repairReuseIn=New-ReuseBridgeInput -ObservedAt '2026-11-19T15:23:00.000+09:00'
    $repairReusePkg=New-BenefitScopedHtmlReusePackage -Store $atkStore -PreviousObservationId $moverId -RunContext $repairReuseIn.RunContext -Candidate $repairReuseIn.Candidate -Document $repairReuseIn.Document -Benefit $repairReuseIn.Benefit -BusinessId $repairReuseIn.BusinessId -BusinessIdentity $repairReuseIn.BusinessIdentity -CanonicalPhone $repairReuseIn.CanonicalPhone -RunId $repairReuseIn.RunId -ObservedAt $repairReuseIn.ObservedAt -RepositoryRevision $repairReuseIn.RepositoryRevision -RepositoryClean $true
    $repairReuseCommit=Commit-ReuseBridgePackage $atkStore $repairReuseIn $repairReusePkg.Package @{($repairReuseIn.BusinessId+'|BENEFIT')=$moverId} $postFault
    Check-Bridge ($repairReuseCommit.Code -ceq 'COMMITTED' -and $repairReuseCommit.IndexRepairRequired) 'reuse post-commit index fault remains terminal COMMITTED'
    $invAtk=Bridge-Inventory $atkStore
    $repairReuseRead=Read-BenefitScopedHtmlCommittedReuse -Store $atkStore -ObservationId $repairReusePkg.Package.Observation.ObservationId
    Check-Bridge ($repairReuseRead.Status -ceq 'VERIFIED' -and $invAtk -ceq (Bridge-Inventory $atkStore)) 'committed reuse reader verifies after IndexRepairRequired without repair/retry'

    Write-Host "PASS: C-Lite History bridge assertions=$script:BridgeChecks"
}finally{
    foreach($root in $script:BridgeTestRoots){
        $resolved=[IO.Path]::GetFullPath($root)
        $prefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
        if(-not $resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -cnotmatch '^milimap-pr2c-[0-9a-f]{32}$'){throw 'Unsafe test Store cleanup'}
        if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
    }
}

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'invoke-phase2-benefit-shadow-mode.ps1')
. (Join-Path $PSScriptRoot 'lib/identity/canonical-business-id.ps1')
. (Join-Path $PSScriptRoot 'lib/history/benefit-incremental-reuse.ps1')
. (Join-Path $PSScriptRoot 'invoke-phase3-review-audit.ps1')

function Get-Phase5BenefitRepositoryRoots {
    $worktree=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $common=& git -C $worktree rev-parse --path-format=absolute --git-common-dir
    if($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($common)){throw 'P5_REPOSITORY_ROOT_UNAVAILABLE'}
    return @($worktree,(Split-Path -Parent $common))
}

function Assert-Phase5BenefitExternalPath {
    param([Parameter(Mandatory)][string]$Path,[string[]]$RepositoryRoots=@())
    $full=[IO.Path]::GetFullPath($Path)
    if($RepositoryRoots.Count -eq 0){$RepositoryRoots=Get-Phase5BenefitRepositoryRoots}
    foreach($root in $RepositoryRoots){
        $repository=[IO.Path]::GetFullPath($root).TrimEnd([IO.Path]::DirectorySeparatorChar)
        if($full.Equals($repository,[StringComparison]::OrdinalIgnoreCase) -or $full.StartsWith($repository+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'P5_OUTPUT_MUST_BE_OUTSIDE_REPOSITORY'}
    }
    $ancestor=$full
    while(-not [string]::IsNullOrEmpty($ancestor)){
        if(Test-Path -LiteralPath $ancestor){
            if((Get-Item -LiteralPath $ancestor -Force).Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)){throw 'P5_OUTPUT_REPARSE_POINT'}
        }
        $ancestor=[IO.Path]::GetDirectoryName($ancestor)
    }
    return $full
}

function Write-Phase5BenefitCycleOutput {
    param([Parameter(Mandatory)]$Result,[Parameter(Mandatory)][string]$Directory)
    [void][IO.Directory]::CreateDirectory($Directory)
    $path=Join-Path $Directory ($Result.RunId+'.json')
    if([IO.File]::Exists($path)){
        $existing=Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json
        if([DateTimeOffset]$existing.ObservedAt -ne [DateTimeOffset]::Parse($Result.ObservedAt,[Globalization.CultureInfo]::InvariantCulture)){throw 'P5_OUTPUT_VIEW_CONFLICT'}
        $existing.ObservedAt=$Result.ObservedAt
        if($null -ne $existing.Review){
            if([DateTimeOffset]$existing.Review.ObservedAt -ne [DateTimeOffset]::Parse($Result.ObservedAt,[Globalization.CultureInfo]::InvariantCulture)){throw 'P5_OUTPUT_VIEW_CONFLICT'}
            $existing.Review.ObservedAt=$Result.ObservedAt
        }
        foreach($field in @('RunId','BusinessId','ObservedAt','RepositoryRevision','CommitCode','OperationalStatus','ObservationId','BenefitState','ReviewClass','Comparison','Review','ProductionAction')){
            if((ConvertTo-Json -InputObject $existing.$field -Depth 20 -Compress) -cne (ConvertTo-Json -InputObject $Result.$field -Depth 20 -Compress)){throw 'P5_OUTPUT_VIEW_CONFLICT'}
        }
        $Result.OutputStatus='PRESERVED'
        return
    }
    $temporary=Join-Path $Directory ('.p5-'+[guid]::NewGuid().ToString('N')+'.tmp')
    try{
        $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Result | ConvertTo-Json -Depth 25))
        $stream=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try{$stream.Write($bytes)}finally{$stream.Dispose()}
        [IO.File]::Move($temporary,$path,$false)
    }finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
}

function Set-Phase5BenefitCommittedView {
    param($Result,$Store,$Observation,$Comparison)
    Assert-HistoryObservationIsCommitted -Store $Store -Observation $Observation
    $semantic=Read-BenefitHistorySemanticProjection -Store $Store -Observation $Observation
    $Result.ObservationId=[string]$Observation.ObservationId
    $Result.OperationalStatus=[string]$Observation.OperationalStatus
    $Result.BenefitState=[string]$semantic.BenefitState
    $Result.ReviewClass=[string]$semantic.ReviewClass
    $Result.Comparison=$Comparison
    $reviewObservation=$Observation | Select-Object *
    $reviewObservation.ObservedAt=$Result.ObservedAt
    $Result.Review=New-Phase3ReviewItem -Observation $reviewObservation -Comparison $Comparison
    $Result.Reasons=@($Observation.NonComparableReasons)
    $Result.Status=if($Observation.OperationalStatus -ceq 'COMPLETE'){'COMPLETE'}else{[string]$Observation.OperationalStatus}
}

function Invoke-Phase5BenefitCycle {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rows,
        [Parameter(Mandatory)][string]$BusinessId,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$ObservedAt,
        [Parameter(Mandatory)][string]$RepositoryRevision,
        [Parameter(Mandatory)][string]$OutputDirectory,
        [Parameter(Mandatory)][scriptblock]$RepositoryStateProvider,
        [int]$SourceRowNumberOffset=1,
        [AllowNull()][scriptblock]$RequestInvoker=$null
    )
    $view=[pscustomobject][ordered]@{
        RunId=$RunId;BusinessId=$BusinessId;SourceRowNumber=$null;ObservedAt=$ObservedAt;RepositoryRevision=$RepositoryRevision
        Status='BLOCKED';Code=$null;CommitCode=$null;RetryRequired=$false;Recovered=$false
        OperationalStatus=$null;ObservationId=$null;BenefitState=$null;ReviewClass=$null
        Comparison=$null;Review=$null;Metrics=$null;Reasons=@();OutputStatus='NOT_WRITTEN';ProductionAction='NONE'
    }
    $started=$false
    $launchClaim=$null;$claimPath=$null;$clearClaim=$false
    try{
        if($RunId -cnotmatch '^[a-z0-9][a-z0-9._-]{0,127}$' -or $RunId.Contains('..')){throw 'P5_RUN_ID_INVALID'}
        Assert-HistoryTimestamp -Value $ObservedAt
        if($RepositoryRevision -cnotmatch '^[0-9a-f]{40}$'){throw 'P5_REVISION_INVALID'}
        Assert-CanonicalBusinessId $BusinessId
        Assert-CanonicalBusinessIds -Rows $Rows
        $selected=@(for($i=0;$i -lt $Rows.Count;$i++){if([string]$Rows[$i].businessId -ceq $BusinessId){$i}})
        if($selected.Count -ne 1 -or $SourceRowNumberOffset -lt 1){throw 'P5_BUSINESS_SELECTION_INVALID'}
        $row=$Rows[$selected[0]]
        $view.SourceRowNumber=$selected[0]+$SourceRowNumberOffset
        $business=ConvertTo-NormalizedBusiness -Row $row -SourceRowNumber $view.SourceRowNumber
        $benefit=ConvertTo-Phase2CanonicalBenefitRecord -Row $row -SourceRowNumber $view.SourceRowNumber
        $candidate=Get-ExistingBenefitSourceCandidate -Benefit $benefit
        if($null -eq $candidate -or $candidate.SourceKind -cne 'PUBLIC_OFFICIAL'){throw 'P5_OFFICIAL_SOURCE_REQUIRED'}
        if(-not (Test-BenefitSafeHttpUri $candidate.Url)){throw 'P5_SOURCE_URL_UNSAFE'}
        $extension=[IO.Path]::GetExtension(([Uri]$candidate.Url).AbsolutePath).ToLowerInvariant()
        if($extension -notin @('','.html','.htm','.do','.php','.aspx','.asp','.jsp','.xlsx','.hwpx','.pdf')){throw 'P5_SOURCE_FORMAT_UNSUPPORTED'}
        $candidate.ObservedAt=$ObservedAt
        $phone=Get-Phase2BenefitRowValue -Row $row -Name '업소전화번호'
        $repositoryRoots=Get-Phase5BenefitRepositoryRoots
        foreach($property in @('Root','RunsRoot','ObservationsRoot','ComparisonsRoot','ArtifactsRoot','IndexesRoot','TempRoot')){
            [void](Assert-Phase5BenefitExternalPath ([string]$Store.$property) $repositoryRoots)
            if($property -cne 'Root'){[void](Assert-HistoryStorePathWithinRoot -Store $Store -Path $Store.$property)}
        }
        $output=Assert-Phase5BenefitExternalPath $OutputDirectory $repositoryRoots
        $historyRoot=[IO.Path]::GetFullPath([string]$Store.Root).TrimEnd([IO.Path]::DirectorySeparatorChar)
        if($output.Equals($historyRoot,[StringComparison]::OrdinalIgnoreCase) -or $output.StartsWith($historyRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'P5_REPORT_MUST_BE_OUTSIDE_HISTORY'}
        $terminal=Read-HistoryJsonFile -Store $Store -Path (Get-HistoryRunManifestPath -Store $Store -RunId $RunId) -Kind 'run manifest'
        if($null -ne $terminal){
            Assert-HistoryRunManifest $terminal
            if($terminal.RunId -cne $RunId -or $terminal.RepositoryRevision -cne $RepositoryRevision -or [DateTimeOffset]$terminal.StartedAt -ne [DateTimeOffset]::Parse($ObservedAt,[Globalization.CultureInfo]::InvariantCulture) -or @($terminal.RequestedBusinessIds).Count -ne 1 -or $terminal.RequestedBusinessIds[0] -cne $BusinessId){throw 'P5_RUN_IDENTITY_MISMATCH'}
            $view.CommitCode=[string]$terminal.RunCommitStatus
            if($view.CommitCode -cne 'COMMITTED'){throw ('P5_TERMINAL_'+$view.CommitCode)}
            # Recovery only: use the existing read-only committed-history scanner
            # once; latest indexes may already point to a newer run.
            $audit=Invoke-Phase3ReviewAudit -Store $Store
            $items=@($audit.Items | Where-Object { $_.RunId -ceq $RunId })
            if($items.Count -ne 1 -or $items[0].BusinessId -cne $BusinessId -or $items[0].Domain -cne 'BENEFIT'){throw 'P5_COMMITTED_RECORDS_AMBIGUOUS'}
            $observation=Read-HistoryObservation -Store $Store -ObservationId $items[0].CurrentObservationId
            $input=ConvertTo-BenefitHistoryInputProjection -BusinessId $BusinessId -Benefit $benefit -BusinessIdentity $business -CanonicalPhone $phone
            $execution=ConvertTo-BenefitHistoryExecutionProjection -RepositoryRevision $RepositoryRevision
            if([DateTimeOffset]$observation.ObservedAt -ne [DateTimeOffset]::Parse($ObservedAt,[Globalization.CultureInfo]::InvariantCulture) -or $observation.InputFingerprint -cne (Get-HistoryFingerprint -Projection $input -SchemaVersion $script:FingerprintSchemaVersion) -or $observation.ExecutionFingerprint -cne (Get-HistoryFingerprint -Projection $execution -SchemaVersion $script:FingerprintSchemaVersion)){throw 'P5_COMMITTED_INPUT_MISMATCH'}
            $comparison=if($items[0].ComparisonId){Read-HistoryJsonFile -Store $Store -Path (Get-HistoryComparisonPath -Store $Store -ComparisonId $items[0].ComparisonId) -Kind 'comparison'}else{$null}
            Set-Phase5BenefitCommittedView -Result $view -Store $Store -Observation $observation -Comparison $comparison
            $view.Code='COMMITTED';$view.Recovered=$true
            try{$view.OutputStatus='WRITTEN';Write-Phase5BenefitCycleOutput $view $output}catch{$view.OutputStatus='FAILED';$view.Code='OUTPUT_FAILED';$view.Reasons+=@($_.Exception.Message)}
            return $view
        }
        $terminalDirectory=Split-Path -Parent (Get-HistoryRunManifestPath -Store $Store -RunId $RunId)
        if(Test-Path -LiteralPath $terminalDirectory){throw 'P5_TERMINAL_STATE_AMBIGUOUS'}
        $claimPath=Assert-HistoryStorePathWithinRoot -Store $Store -Path (Join-Path $Store.TempRoot ('.p5-'+$RunId+'.claim'))
        if(Test-Path -LiteralPath $claimPath){
            try{
                if((Get-Item -LiteralPath $claimPath).Length -gt 128){throw 'P5_CLAIM_INVALID'}
                $prior=[IO.File]::ReadAllText($claimPath)
            }catch [IO.IOException]{$view.Code='P5_RUN_ACTIVE';$view.Reasons=@('P5_RUN_ACTIVE');return $view}
            if($prior -cin @('BASELINE_MOVED','WRITER_LOCKED','ABORTED')){$view.CommitCode=$prior;$view.RetryRequired=$prior -ceq 'BASELINE_MOVED'}
            $view.Code='P5_PREVIOUS_ATTEMPT';$view.Reasons=@('P5_STALE_CLAIM_REQUIRES_REVIEW');return $view
        }
        $stagePath=Assert-HistoryStorePathWithinRoot -Store $Store -Path (Join-Path $Store.TempRoot $RunId)
        if(Test-Path -LiteralPath $stagePath){throw 'P5_STAGING_AMBIGUOUS'}
        try{$launchClaim=[IO.File]::Open($claimPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}
        catch [IO.IOException]{$view.Code='P5_RUN_ACTIVE';$view.Reasons=@('P5_RUN_ACTIVE');return $view}
        # This launch claim is not the History writer lock. It serializes only
        # the same RunId, including the pre-fetch window. Never steal stale claims.
        if((Test-Path -LiteralPath $stagePath) -or (Test-Path -LiteralPath $terminalDirectory)){throw 'P5_STATE_CHANGED_BEFORE_FETCH'}
        $started=$true
        $context=New-BenefitSourceRunContext
        $run=Invoke-BenefitIncrementalPostFetch -Store $Store -RunId $RunId -ObservedAt $ObservedAt -RepositoryRevision $RepositoryRevision -BusinessId $BusinessId -Benefit $benefit -BusinessIdentity $business -CanonicalPhone $phone -Candidate $candidate -RunContext $context -RequestInvoker $RequestInvoker -RepositoryStateProvider $RepositoryStateProvider
        $view.CommitCode=[string]$run.Commit.Code;$view.Code=$view.CommitCode;$view.RetryRequired=[bool]$run.Commit.RetryRequired
        $clearClaim=$view.CommitCode -ceq 'COMMITTED'
        $view.OperationalStatus=[string]$run.Observation.OperationalStatus
        $view.Metrics=$run.Metrics | Select-Object *
        $view.Metrics | Add-Member NoteProperty FetchCacheHits $context.Metrics.FetchCacheHits
        $view.Metrics | Add-Member NoteProperty AdapterReuseCount $context.Metrics.AdapterReuseCount
        if($view.CommitCode -ceq 'COMMITTED'){
            Set-Phase5BenefitCommittedView -Result $view -Store $Store -Observation $run.Observation -Comparison $run.Comparison
        }else{
            $view.Status='FAILED';$view.Reasons=@([string]$run.Commit.Reason)
        }
        try{$view.OutputStatus='WRITTEN';Write-Phase5BenefitCycleOutput $view $output}catch{$view.OutputStatus='FAILED';$view.Code='OUTPUT_FAILED';$view.Reasons+=@($_.Exception.Message)}
    }catch{
        $view.Status=if($started){'FAILED'}else{'BLOCKED'}
        $view.Code=if($started){'P5_CYCLE_FAILED'}else{'P5_PREFLIGHT_REJECTED'}
        $view.Reasons=@($_.Exception.Message)
    }finally{
        if($null -ne $launchClaim){
            try{
                if(-not $clearClaim){
                    $outcome=if($view.CommitCode){$view.CommitCode}else{'P5_INTERRUPTED'}
                    $bytes=[Text.Encoding]::ASCII.GetBytes($outcome)
                    $launchClaim.SetLength(0);$launchClaim.Write($bytes);$launchClaim.Flush()
                }
            }catch{$view.Reasons+=@('P5_CLAIM_OUTCOME_NOT_RECORDED')}
            finally{$launchClaim.Dispose()}
            if($clearClaim){try{[IO.File]::Delete($claimPath)}catch{$view.Reasons+=@('P5_COMMITTED_CLAIM_CLEANUP_FAILED')}}
        }
    }
    return $view
}

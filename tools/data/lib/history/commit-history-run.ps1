Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'history-contracts.ps1')
. (Join-Path $PSScriptRoot 'history-fingerprints.ps1')
. (Join-Path $PSScriptRoot 'history-store.ps1')

function New-HistoryRunId {
    return 'run-' + [Guid]::NewGuid().ToString('N')
}

function Get-HistoryComparisonPath {
    param([Parameter(Mandatory)]$Store,[Parameter(Mandatory)][string]$ComparisonId)
    Assert-HistoryToken -Value $ComparisonId -Name 'comparison id'
    if ($ComparisonId.Contains('/') -or $ComparisonId.Contains('\') -or $ComparisonId.Contains('..')) {
        throw 'Comparison id cannot contain path separators or traversal'
    }
    return Assert-HistoryStorePathWithinRoot -Store $Store -Path (Join-Path $Store.ComparisonsRoot ($ComparisonId + '.json'))
}

function Write-HistoryPreparedJson {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Value
    )
    $safePath=Assert-HistoryStorePathWithinRoot -Store $Store -Path $Path
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $safePath) | Out-Null
    $Value | ConvertTo-Json -Depth 30 -Compress | Set-Content -LiteralPath $safePath -Encoding utf8 -NoNewline
}

function Get-PreparedArtifactPayload {
    param([Parameter(Mandatory)]$Artifact)
    $hasBytes=$Artifact.PSObject.Properties.Name -contains 'Bytes'
    $hasText=$Artifact.PSObject.Properties.Name -contains 'Text'
    if($hasBytes -eq $hasText){ throw 'Prepared artifact requires exactly one of Bytes or Text' }
    if($hasBytes){ return [byte[]]$Artifact.Bytes }
    return [Text.Encoding]::UTF8.GetBytes([string]$Artifact.Text)
}

function Get-PreparedArtifactReferenceKeys {
    param(
        [Parameter(Mandatory)]$Store,
        [object[]]$Artifacts=@()
    )

    $keys=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($artifact in @($Artifacts)){
        if($null -eq $artifact){ throw 'Prepared artifact cannot be null' }

        $hash=[string]$artifact.ContentHash
        $extension=[string]$artifact.Extension
        Assert-HistoryHash -Value $hash -Name 'content hash'
        if($extension -cnotmatch '^[a-z0-9]{1,16}$'){ throw 'Invalid artifact extension' }

        $path=Get-HistoryArtifactPath -Store $Store -ContentHash $hash -Extension $extension
        $relative=Get-HistoryRelativePath -Store $Store -FullPath $path
        [void]$keys.Add($hash + '|' + $relative)
    }
    return $keys
}

function Assert-PreparedObservationReferences {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)][object[]]$Observations,
        [Parameter(Mandatory)]$PreparedArtifactKeys
    )

    foreach($observation in @($Observations)){
        foreach($reference in @($observation.ArtifactReferences)){
            Assert-HistoryArtifactReference $reference
            $key=([string]$reference.ContentHash) + '|' + ([string]$reference.RelativePath)
            if($PreparedArtifactKeys.Contains($key)){ continue }
            Assert-HistoryArtifactReferenceExists -Store $Store -Reference $reference
        }
    }
}

function Assert-HistoryObservationIsCommitted {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)]$Observation
    )

    $manifestPath=Get-HistoryRunManifestPath -Store $Store -RunId ([string]$Observation.RunId)
    $manifest=Read-HistoryJsonFile -Store $Store -Path $manifestPath -Kind 'run manifest'
    if($null -eq $manifest){ throw "Previous observation run is not committed: $($Observation.ObservationId)" }

    Assert-HistoryRunManifest $manifest
    if([string]$manifest.RunCommitStatus -cne 'COMMITTED'){
        throw "Previous observation run is not committed: $($Observation.ObservationId)"
    }
}

function Assert-PreparedComparisonReferences {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)][object[]]$Observations,
        [Parameter(Mandatory)][object[]]$Comparisons
    )

    $currentById=@{}
    foreach($observation in @($Observations)){
        $observationId=[string]$observation.ObservationId
        $currentById[$observationId]=$observation
    }

    foreach($comparison in @($Comparisons)){
        $currentId=[string]$comparison.CurrentObservationId
        if(-not $currentById.ContainsKey($currentId)){
            throw "Comparison current observation is not part of prepared run: $currentId"
        }

        $current=$currentById[$currentId]
        if([string]$current.BusinessId -cne [string]$comparison.BusinessId -or [string]$current.Domain -cne [string]$comparison.Domain){
            throw 'Comparison current observation identity/domain mismatch'
        }

        $previousId=[string]$comparison.PreviousObservationId
        if([string]::IsNullOrWhiteSpace($previousId)){ continue }

        $previous=Read-HistoryObservation -Store $Store -ObservationId $previousId
        if($null -eq $previous){ throw "Comparison previous observation does not exist: $previousId" }
        if([string]$previous.BusinessId -cne [string]$comparison.BusinessId -or [string]$previous.Domain -cne [string]$comparison.Domain){
            throw 'Comparison previous observation identity/domain mismatch'
        }

        Assert-HistoryObservationIsCommitted -Store $Store -Observation $previous
    }
}

function Prepare-HistoryRun {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)]$RunManifest,
        [object[]]$Artifacts=@(),
        [object[]]$Observations=@(),
        [object[]]$Comparisons=@()
    )

    Assert-HistoryRunManifest $RunManifest
    if([string]$RunManifest.RunCommitStatus -cne 'PREPARED'){ throw 'Prepare-HistoryRun requires PREPARED manifest' }
    if(-not [string]::IsNullOrWhiteSpace([string]$RunManifest.CompletedAt)){ throw 'PREPARED manifest cannot have CompletedAt' }

    $runId=[string]$RunManifest.RunId
    Assert-HistoryToken -Value $runId -Name 'run id'
    if($runId.Contains('/') -or $runId.Contains('\') -or $runId.Contains('..')){ throw 'Run id cannot contain path traversal' }

    $terminalRunDirectory=Assert-HistoryStorePathWithinRoot -Store $Store -Path (Join-Path $Store.RunsRoot $runId)
    if(Test-Path -LiteralPath $terminalRunDirectory){ throw "History RunId already has terminal state: $runId" }

    $stageRoot=Assert-HistoryStorePathWithinRoot -Store $Store -Path (Join-Path $Store.TempRoot $runId)
    if(Test-Path -LiteralPath $stageRoot){ throw "Prepared run staging already exists: $runId" }

    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($observation in @($Observations)){
        Assert-HistoryObservation $observation
        if([string]$observation.RunId -cne $runId){ throw 'Observation RunId does not match prepared run' }
        $key=([string]$observation.BusinessId) + '|' + ([string]$observation.Domain
)
        if(-not $seen.Add($key)){ throw "Duplicate businessId+domain in prepared run: $key" }
    }
    foreach($comparison in @($Comparisons)){
        Assert-ObservationComparison $comparison
        if([string]$comparison.RunId -cne $runId){ throw 'Comparison RunId does not match prepared run' }
    }

    $preparedArtifactKeys=Get-PreparedArtifactReferenceKeys -Store $Store -Artifacts @($Artifacts)
    Assert-PreparedObservationReferences -Store $Store -Observations @($Observations) -PreparedArtifactKeys $preparedArtifactKeys
    Assert-PreparedComparisonReferences -Store $Store -Observations @($Observations) -Comparisons @($Comparisons)

    $artifactEntries=[Collections.Generic.List[object]]::new()
    try {
        New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null
        $artifactStageRoot=Join-Path $stageRoot 'artifacts'
        $observationStageRoot=Join-Path $stageRoot 'observations'
        $comparisonStageRoot=Join-Path $stageRoot 'comparisons'
        New-Item -ItemType Directory -Force -Path $artifactStageRoot,$observationStageRoot,$comparisonStageRoot | Out-Null

        foreach($artifact in @($Artifacts)){
            if($null -eq $artifact){ throw 'Prepared artifact cannot be null' }
            $hash=[string]$artifact.ContentHash
            $extension=[string]$artifact.Extension
            Assert-HistoryHash -Value $hash -Name 'content hash'
            if($extension -cnotmatch '^[a-z0-9]{1,16}$'){ throw 'Invalid artifact extension' }
            $payload=Get-PreparedArtifactPayload -Artifact $artifact
            $sha=[Security.Cryptography.SHA256]::Create()
            try {
                $actual=([BitConverter]::ToString($sha.ComputeHash($payload)) -replace '-','').ToLowerInvariant()
            } finally {
                $sha.Dispose()
            }
            if($actual -cne $hash){ throw 'Prepared artifact hash mismatch' }
            $stagePath=Assert-HistoryStorePathWithinRoot -Store $Store -Path (Join-Path $artifactStageRoot ($hash + '.' + $extension))
            [IO.File]::WriteAllBytes($stagePath,$payload)
            $artifactEntries.Add([pscustomobject][ordered]@{
                ContentHash=$hash
                Extension=$extension
                Kind=$(if($artifact.PSObject.Properties.Name -contains 'Kind' -and -not [string]::IsNullOrWhiteSpace([string]$artifact.Kind)){[string]$artifact.Kind}else{'HISTORY_ARTIFACT'})
                StagePath=$stagePath
            })
        }

        foreach($observation in @($Observations)){
            $stagePath=Assert-HistoryStorePathWithinRoot -Store $Store -Path (Join-Path $observationStageRoot ($observation.ObservationId + '.json'))
            Write-HistoryPreparedJson -Store $Store -Path $stagePath -Value $observation
        }
        foreach($comparison in @($Comparisons)){
            $stagePath=Assert-HistoryStorePathWithinRoot -Store $Store -Path (Join-Path $comparisonStageRoot ($comparison.ComparisonId + '.json'))
            Write-HistoryPreparedJson -Store $Store -Path $stagePath -Value $comparison
        }
        Write-HistoryPreparedJson -Store $Store -Path (Join-Path $stageRoot 'manifest.prepared.json') -Value $RunManifest
    } catch {
        if(Test-Path -LiteralPath $stageRoot){ Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction SilentlyContinue }
        throw
    }

    return [pscustomobject][ordered]@{
        StoreRoot=[string]$Store.Root
        StageRoot=$stageRoot
        RunManifest=$RunManifest
        Artifacts=@($artifactEntries)
        Observations=@($Observations)
        Comparisons=@($Comparisons)
    }
}

function Invoke-HistoryFaultCheckpoint {
    param([AllowNull()][scriptblock]$FaultInjector,[Parameter(Mandatory)][string]$Name)
    if($null -ne $FaultInjector){ & $FaultInjector $Name }
}

function New-HistoryCommitResult {
    param(
        [Parameter(Mandatory)][string]$Code,
        [bool]$RetryRequired=$false,
        [bool]$IndexRepairRequired=$false,
        [string]$RunId='',
        [string]$Reason=''
    )
    return [pscustomobject][ordered]@{
        Code=$Code
        RunId=$RunId
        RetryRequired=$RetryRequired
        IndexRepairRequired=$IndexRepairRequired
        Reason=$Reason
    }
}

function Write-HistoryTerminalManifest {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)]$PreparedRun,
        [Parameter(Mandatory)][ValidateSet('COMMITTED','ABORTED')][string]$CommitStatus
    )
    $source=$PreparedRun.RunManifest
    $manifest=New-HistoryRunManifest -RunId $source.RunId -StartedAt $source.StartedAt -CompletedAt ([DateTimeOffset]::UtcNow.ToString('o')) -RepositoryRevision $source.RepositoryRevision -HistoryContractVersion $source.HistoryContractVersion -FingerprintSchemaVersion $source.FingerprintSchemaVersion -RequestedBusinessIds @($source.RequestedBusinessIds) -CompletedBusinessIds @($source.CompletedBusinessIds) -FailedBusinessIds @($source.FailedBusinessIds) -ExecutionStatus $source.ExecutionStatus -RunCommitStatus $CommitStatus

    $runDirectory=Assert-HistoryStorePathWithinRoot -Store $Store -Path (Join-Path $Store.RunsRoot ([string]$source.RunId))
    New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null
    $finalPath=Get-HistoryRunManifestPath -Store $Store -RunId ([string]$source.RunId)
    $tempPath=Assert-HistoryStorePathWithinRoot -Store $Store -Path (Join-Path $Store.TempRoot ('manifest-' + [Guid]::NewGuid().ToString('N') + '.tmp'))
    Write-HistoryPreparedJson -Store $Store -Path $tempPath -Value $manifest
    try {
        [IO.File]::Move($tempPath,$finalPath,$false)
    } finally {
        if(Test-Path -LiteralPath $tempPath){ Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue }
    }
    return $manifest
}

function Publish-HistoryPreparedArtifacts {
    param([Parameter(Mandatory)]$Store,[Parameter(Mandatory)]$PreparedRun)
    foreach($entry in @($PreparedRun.Artifacts)){
        $bytes=[IO.File]::ReadAllBytes([string]$entry.StagePath)
        [void](Write-HistoryArtifact -Store $Store -ContentHash $entry.ContentHash -Extension $entry.Extension -Bytes $bytes)
    }
}

function Publish-HistoryPreparedRecords {
    param([Parameter(Mandatory)]$Store,[Parameter(Mandatory)]$PreparedRun)
    foreach($observation in @($PreparedRun.Observations)){
        $source=Assert-HistoryStorePathWithinRoot -Store $Store -Path (Join-Path (Join-Path $PreparedRun.StageRoot 'observations') ($observation.ObservationId + '.json'))
        $destination=Get-HistoryObservationPath -Store $Store -ObservationId ([string]$observation.ObservationId)
        if(Test-Path -LiteralPath $destination){ throw "Observation already exists: $($observation.ObservationId)" }
        [IO.File]::Move($source,$destination,$false)
    }
    foreach($comparison in @($PreparedRun.Comparisons)){
        $source=Assert-HistoryStorePathWithinRoot -Store $Store -Path (Join-Path (Join-Path $PreparedRun.StageRoot 'comparisons') ($comparison.ComparisonId + '.json'))
        $destination=Get-HistoryComparisonPath -Store $Store -ComparisonId ([string]$comparison.ComparisonId)
        if(Test-Path -LiteralPath $destination){ throw "Comparison already exists: $($comparison.ComparisonId)" }
        [IO.File]::Move($source,$destination,$false)
    }
}

function Ensure-HistoryIndexesAvailableForCas {
    param([Parameter(Mandatory)]$Store,[Parameter(Mandatory)][object[]]$Observations)
    $missing=$false
    foreach($observation in @($Observations)){
        $path=Get-HistoryIndexPath -Store $Store -BusinessId $observation.BusinessId -Domain $observation.Domain
        if(-not (Test-Path -LiteralPath $path -PathType Leaf)){ $missing=$true; break }
    }
    if($missing){ [void](Rebuild-HistoryIndexes -Store $Store) }
}

function Test-HistoryExpectedBaselines {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)][object[]]$Observations,
        [Parameter(Mandatory)][hashtable]$ExpectedBaselines
    )
    Ensure-HistoryIndexesAvailableForCas -Store $Store -Observations $Observations
    foreach($observation in @($Observations)){
        $key=([string]$observation.BusinessId) + '|' + ([string]$observation.Domain
)
        if(-not $ExpectedBaselines.ContainsKey($key)){ throw "Missing expected baseline for $key" }
        $expected=if($null -eq $ExpectedBaselines[$key]){''}else{[string]$ExpectedBaselines[$key]}
        $entry=Get-HistoryLatestEntry -Store $Store -BusinessId $observation.BusinessId -Domain $observation.Domain -ComparableOnly
        $actual=if($null -eq $entry){''}else{[string]$entry.LatestComparableObservationId}
        if($actual -cne $expected){
            return [pscustomobject][ordered]@{ Matches=$false; Key=$key; Expected=$expected; Actual=$actual }
        }
    }
    return [pscustomobject][ordered]@{ Matches=$true; Key=''; Expected=''; Actual='' }
}

function Update-HistoryIndexesAfterCommit {
    param([Parameter(Mandatory)]$Store,[Parameter(Mandatory)][object[]]$Observations)
    foreach($observation in @($Observations)){
        $prior=Get-HistoryLatestEntry -Store $Store -BusinessId $observation.BusinessId -Domain $observation.Domain
        $priorComparable=if($null -eq $prior){''}else{[string]$prior.LatestComparableObservationId}
        $latestComparable=if([bool]$observation.Comparable -and [string]$observation.OperationalStatus -ceq 'COMPLETE'){[string]$observation.ObservationId}else{$priorComparable}
        $entry=New-HistoryIndexEntry -BusinessId $observation.BusinessId -Domain $observation.Domain -LatestObservationId $observation.ObservationId -LatestComparableObservationId $latestComparable
        Write-HistoryIndexEntry -Store $Store -Entry $entry
    }
}

function Commit-HistoryRun {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)]$PreparedRun,
        [Parameter(Mandatory)][hashtable]$ExpectedBaselines,
        [AllowNull()][scriptblock]$FaultInjector=$null
    )

    if([IO.Path]::GetFullPath([string]$PreparedRun.StoreRoot) -cne [IO.Path]::GetFullPath([string]$Store.Root)){ throw 'Prepared run belongs to a different history store' }
    if(-not (Test-Path -LiteralPath $PreparedRun.StageRoot -PathType Container)){ throw 'Prepared run staging directory does not exist' }

    foreach($observation in @($PreparedRun.Observations)){
        $key=([string]$observation.BusinessId) + '|' + ([string]$observation.Domain
)
        if(-not $ExpectedBaselines.ContainsKey($key)){ throw "Missing expected baseline for $key" }
    }

    $lockPath=Join-Path $Store.Root '.writer-lock'
    $lock=$null
    try {
        $lock=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    } catch [IO.IOException] {
        return New-HistoryCommitResult -Code 'WRITER_LOCKED' -RunId $PreparedRun.RunManifest.RunId -Reason 'Exclusive history writer lock is already held'
    }

    $manifestCommitted=$false
    try {
        $cas=Test-HistoryExpectedBaselines -Store $Store -Observations @($PreparedRun.Observations) -ExpectedBaselines $ExpectedBaselines
        if(-not [bool]$cas.Matches){
            if(Test-Path -LiteralPath $PreparedRun.StageRoot){ Remove-Item -LiteralPath $PreparedRun.StageRoot -Recurse -Force -ErrorAction SilentlyContinue }
            return New-HistoryCommitResult -Code 'BASELINE_MOVED' -RunId $PreparedRun.RunManifest.RunId -RetryRequired $true -Reason ("Baseline moved for " + $cas.Key)
        }

        Publish-HistoryPreparedArtifacts -Store $Store -PreparedRun $PreparedRun
        Invoke-HistoryFaultCheckpoint -FaultInjector $FaultInjector -Name 'AFTER_ARTIFACTS'

        Publish-HistoryPreparedRecords -Store $Store -PreparedRun $PreparedRun
        Invoke-HistoryFaultCheckpoint -FaultInjector $FaultInjector -Name 'AFTER_OBSERVATIONS'
        Invoke-HistoryFaultCheckpoint -FaultInjector $FaultInjector -Name 'BEFORE_MANIFEST_COMMIT'

        [void](Write-HistoryTerminalManifest -Store $Store -PreparedRun $PreparedRun -CommitStatus 'COMMITTED')
        $manifestCommitted=$true

        Invoke-HistoryFaultCheckpoint -FaultInjector $FaultInjector -Name 'AFTER_MANIFEST_COMMIT'

        Update-HistoryIndexesAfterCommit -Store $Store -Observations @($PreparedRun.Observations)
        Invoke-HistoryFaultCheckpoint -FaultInjector $FaultInjector -Name 'AFTER_INDEX_UPDATE'

        if(Test-Path -LiteralPath $PreparedRun.StageRoot){ Remove-Item -LiteralPath $PreparedRun.StageRoot -Recurse -Force -ErrorAction SilentlyContinue }
        return New-HistoryCommitResult -Code 'COMMITTED' -RunId $PreparedRun.RunManifest.RunId
    } catch {
        $reason=$_.Exception.Message
        if($manifestCommitted){
            return New-HistoryCommitResult -Code 'COMMITTED' -RunId $PreparedRun.RunManifest.RunId -IndexRepairRequired $true -Reason $reason
        }

        try {
            [void](Write-HistoryTerminalManifest -Store $Store -PreparedRun $PreparedRun -CommitStatus 'ABORTED')
        } catch {
        }
        if(Test-Path -LiteralPath $PreparedRun.StageRoot){ Remove-Item -LiteralPath $PreparedRun.StageRoot -Recurse -Force -ErrorAction SilentlyContinue }
        return New-HistoryCommitResult -Code 'ABORTED' -RunId $PreparedRun.RunManifest.RunId -Reason $reason
    } finally {
        if($null -ne $lock){ $lock.Dispose() }
    }
}
){ throw 'Invalid artifact extension' }
        $path=Get-HistoryArtifactPath -Store $Store -ContentHash $hash -Extension $extension
        $relative=Get-HistoryRelativePath -Store $Store -FullPath $path
        [void]$keys.Add($hash + '|' + $relative)
    }
    return $keys
}

function Assert-PreparedObservationReferences {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)][object[]]$Observations,
        [Parameter(Mandatory)][Collections.Generic.HashSet[string]]$PreparedArtifactKeys
    )
    foreach($observation in @($Observations)){
        foreach($reference in @($observation.ArtifactReferences)){
            Assert-HistoryArtifactReference $reference
            $key=([string]$reference.ContentHash) + '|' + ([string]$reference.RelativePath)
            if($PreparedArtifactKeys.Contains($key)){ continue }
            Assert-HistoryArtifactReferenceExists -Store $Store -Reference $reference
        }
    }
}

function Assert-HistoryObservationIsCommitted {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)]$Observation
    )
    $manifestPath=Get-HistoryRunManifestPath -Store $Store -RunId ([string]$Observation.RunId)
    $manifest=Read-HistoryJsonFile -Store $Store -Path $manifestPath -Kind 'run manifest'
    if($null -eq $manifest){ throw "Previous observation run is not committed: $($Observation.ObservationId)" }
    Assert-HistoryRunManifest $manifest
    if([string]$manifest.RunCommitStatus -cne 'COMMITTED'){ throw "Previous observation run is not committed: $($Observation.ObservationId)" }
}

function Assert-PreparedComparisonReferences {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)][object[]]$Observations,
        [Parameter(Mandatory)][object[]]$Comparisons
    )
    $currentById=@{}
    foreach($observation in @($Observations)){
        $currentById[[string]$observation.ObservationId]=$observation
    }

    foreach($comparison in @($Comparisons)){
        $currentId=[string]$comparison.CurrentObservationId
        if(-not $currentById.ContainsKey($currentId)){ throw "Comparison current observation is not part of prepared run: $currentId" }
        $current=$currentById[$currentId]
        if([string]$current.BusinessId -cne [string]$comparison.BusinessId -or [string]$current.Domain -cne [string]$comparison.Domain){
            throw 'Comparison current observation identity/domain mismatch'
        }

        $previousId=[string]$comparison.PreviousObservationId
        if([string]::IsNullOrWhiteSpace($previousId)){ continue }
        $previous=Read-HistoryObservation -Store $Store -ObservationId $previousId
        if($null -eq $previous){ throw "Comparison previous observation does not exist: $previousId" }
        if([string]$previous.BusinessId -cne [string]$comparison.BusinessId -or [string]$previous.Domain -cne [string]$comparison.Domain){
            throw 'Comparison previous observation identity/domain mismatch'
        }
        Assert-HistoryObservationIsCommitted -Store $Store -Observation $previous
    }
}

function Prepare-HistoryRun {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)]$RunManifest,
        [object[]]$Artifacts=@(),
        [object[]]$Observations=@(),
        [object[]]$Comparisons=@()
    )

    Assert-HistoryRunManifest $RunManifest
    if([string]$RunManifest.RunCommitStatus -cne 'PREPARED'){ throw 'Prepare-HistoryRun requires PREPARED manifest' }
    if(-not [string]::IsNullOrWhiteSpace([string]$RunManifest.CompletedAt)){ throw 'PREPARED manifest cannot have CompletedAt' }

    $runId=[string]$RunManifest.RunId
    Assert-HistoryToken -Value $runId -Name 'run id'
    if($runId.Contains('/') -or $runId.Contains('\') -or $runId.Contains('..')){ throw 'Run id cannot contain path traversal' }

    $terminalRunDirectory=Assert-HistoryStorePathWithinRoot -Store $Store -Path (Join-Path $Store.RunsRoot $runId)
    if(Test-Path -LiteralPath $terminalRunDirectory){ throw "History RunId already has terminal state: $runId" }

    $stageRoot=Assert-HistoryStorePathWithinRoot -Store $Store -Path (Join-Path $Store.TempRoot $runId)
    if(Test-Path -LiteralPath $stageRoot){ throw "Prepared run staging already exists: $runId" }

    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($observation in @($Observations)){
        Assert-HistoryObservation $observation
        if([string]$observation.RunId -cne $runId){ throw 'Observation RunId does not match prepared run' }
        $key=([string]$observation.BusinessId) + '|' + ([string]$observation.Domain
)
        if(-not $seen.Add($key)){ throw "Duplicate businessId+domain in prepared run: $key" }
    }
    foreach($comparison in @($Comparisons)){
        Assert-ObservationComparison $comparison
        if([string]$comparison.RunId -cne $runId){ throw 'Comparison RunId does not match prepared run' }
    }

    $artifactEntries=[Collections.Generic.List[object]]::new()
    try {
        New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null
        $artifactStageRoot=Join-Path $stageRoot 'artifacts'
        $observationStageRoot=Join-Path $stageRoot 'observations'
        $comparisonStageRoot=Join-Path $stageRoot 'comparisons'
        New-Item -ItemType Directory -Force -Path $artifactStageRoot,$observationStageRoot,$comparisonStageRoot | Out-Null

        foreach($artifact in @($Artifacts)){
            if($null -eq $artifact){ throw 'Prepared artifact cannot be null' }
            $hash=[string]$artifact.ContentHash
            $extension=[string]$artifact.Extension
            Assert-HistoryHash -Value $hash -Name 'content hash'
            if($extension -cnotmatch '^[a-z0-9]{1,16}$'){ throw 'Invalid artifact extension' }
            $payload=Get-PreparedArtifactPayload -Artifact $artifact
            $sha=[Security.Cryptography.SHA256]::Create()
            try {
                $actual=([BitConverter]::ToString($sha.ComputeHash($payload)) -replace '-','').ToLowerInvariant()
            } finally {
                $sha.Dispose()
            }
            if($actual -cne $hash){ throw 'Prepared artifact hash mismatch' }
            $stagePath=Assert-HistoryStorePathWithinRoot -Store $Store -Path (Join-Path $artifactStageRoot ($hash + '.' + $extension))
            [IO.File]::WriteAllBytes($stagePath,$payload)
            $artifactEntries.Add([pscustomobject][ordered]@{
                ContentHash=$hash
                Extension=$extension
                Kind=$(if($artifact.PSObject.Properties.Name -contains 'Kind' -and -not [string]::IsNullOrWhiteSpace([string]$artifact.Kind)){[string]$artifact.Kind}else{'HISTORY_ARTIFACT'})
                StagePath=$stagePath
            })
        }

        foreach($observation in @($Observations)){
            $stagePath=Assert-HistoryStorePathWithinRoot -Store $Store -Path (Join-Path $observationStageRoot ($observation.ObservationId + '.json'))
            Write-HistoryPreparedJson -Store $Store -Path $stagePath -Value $observation
        }
        foreach($comparison in @($Comparisons)){
            $stagePath=Assert-HistoryStorePathWithinRoot -Store $Store -Path (Join-Path $comparisonStageRoot ($comparison.ComparisonId + '.json'))
            Write-HistoryPreparedJson -Store $Store -Path $stagePath -Value $comparison
        }
        Write-HistoryPreparedJson -Store $Store -Path (Join-Path $stageRoot 'manifest.prepared.json') -Value $RunManifest
    } catch {
        if(Test-Path -LiteralPath $stageRoot){ Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction SilentlyContinue }
        throw
    }

    return [pscustomobject][ordered]@{
        StoreRoot=[string]$Store.Root
        StageRoot=$stageRoot
        RunManifest=$RunManifest
        Artifacts=@($artifactEntries)
        Observations=@($Observations)
        Comparisons=@($Comparisons)
    }
}

function Invoke-HistoryFaultCheckpoint {
    param([AllowNull()][scriptblock]$FaultInjector,[Parameter(Mandatory)][string]$Name)
    if($null -ne $FaultInjector){ & $FaultInjector $Name }
}

function New-HistoryCommitResult {
    param(
        [Parameter(Mandatory)][string]$Code,
        [bool]$RetryRequired=$false,
        [bool]$IndexRepairRequired=$false,
        [string]$RunId='',
        [string]$Reason=''
    )
    return [pscustomobject][ordered]@{
        Code=$Code
        RunId=$RunId
        RetryRequired=$RetryRequired
        IndexRepairRequired=$IndexRepairRequired
        Reason=$Reason
    }
}

function Write-HistoryTerminalManifest {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)]$PreparedRun,
        [Parameter(Mandatory)][ValidateSet('COMMITTED','ABORTED')][string]$CommitStatus
    )
    $source=$PreparedRun.RunManifest
    $manifest=New-HistoryRunManifest -RunId $source.RunId -StartedAt $source.StartedAt -CompletedAt ([DateTimeOffset]::UtcNow.ToString('o')) -RepositoryRevision $source.RepositoryRevision -HistoryContractVersion $source.HistoryContractVersion -FingerprintSchemaVersion $source.FingerprintSchemaVersion -RequestedBusinessIds @($source.RequestedBusinessIds) -CompletedBusinessIds @($source.CompletedBusinessIds) -FailedBusinessIds @($source.FailedBusinessIds) -ExecutionStatus $source.ExecutionStatus -RunCommitStatus $CommitStatus

    $runDirectory=Assert-HistoryStorePathWithinRoot -Store $Store -Path (Join-Path $Store.RunsRoot ([string]$source.RunId))
    New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null
    $finalPath=Get-HistoryRunManifestPath -Store $Store -RunId ([string]$source.RunId)
    $tempPath=Assert-HistoryStorePathWithinRoot -Store $Store -Path (Join-Path $Store.TempRoot ('manifest-' + [Guid]::NewGuid().ToString('N') + '.tmp'))
    Write-HistoryPreparedJson -Store $Store -Path $tempPath -Value $manifest
    try {
        [IO.File]::Move($tempPath,$finalPath,$false)
    } finally {
        if(Test-Path -LiteralPath $tempPath){ Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue }
    }
    return $manifest
}

function Publish-HistoryPreparedArtifacts {
    param([Parameter(Mandatory)]$Store,[Parameter(Mandatory)]$PreparedRun)
    foreach($entry in @($PreparedRun.Artifacts)){
        $bytes=[IO.File]::ReadAllBytes([string]$entry.StagePath)
        [void](Write-HistoryArtifact -Store $Store -ContentHash $entry.ContentHash -Extension $entry.Extension -Bytes $bytes)
    }
}

function Publish-HistoryPreparedRecords {
    param([Parameter(Mandatory)]$Store,[Parameter(Mandatory)]$PreparedRun)
    foreach($observation in @($PreparedRun.Observations)){
        $source=Assert-HistoryStorePathWithinRoot -Store $Store -Path (Join-Path (Join-Path $PreparedRun.StageRoot 'observations') ($observation.ObservationId + '.json'))
        $destination=Get-HistoryObservationPath -Store $Store -ObservationId ([string]$observation.ObservationId)
        if(Test-Path -LiteralPath $destination){ throw "Observation already exists: $($observation.ObservationId)" }
        [IO.File]::Move($source,$destination,$false)
    }
    foreach($comparison in @($PreparedRun.Comparisons)){
        $source=Assert-HistoryStorePathWithinRoot -Store $Store -Path (Join-Path (Join-Path $PreparedRun.StageRoot 'comparisons') ($comparison.ComparisonId + '.json'))
        $destination=Get-HistoryComparisonPath -Store $Store -ComparisonId ([string]$comparison.ComparisonId)
        if(Test-Path -LiteralPath $destination){ throw "Comparison already exists: $($comparison.ComparisonId)" }
        [IO.File]::Move($source,$destination,$false)
    }
}

function Ensure-HistoryIndexesAvailableForCas {
    param([Parameter(Mandatory)]$Store,[Parameter(Mandatory)][object[]]$Observations)
    $missing=$false
    foreach($observation in @($Observations)){
        $path=Get-HistoryIndexPath -Store $Store -BusinessId $observation.BusinessId -Domain $observation.Domain
        if(-not (Test-Path -LiteralPath $path -PathType Leaf)){ $missing=$true; break }
    }
    if($missing){ [void](Rebuild-HistoryIndexes -Store $Store) }
}

function Test-HistoryExpectedBaselines {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)][object[]]$Observations,
        [Parameter(Mandatory)][hashtable]$ExpectedBaselines
    )
    Ensure-HistoryIndexesAvailableForCas -Store $Store -Observations $Observations
    foreach($observation in @($Observations)){
        $key=([string]$observation.BusinessId) + '|' + ([string]$observation.Domain
)
        if(-not $ExpectedBaselines.ContainsKey($key)){ throw "Missing expected baseline for $key" }
        $expected=if($null -eq $ExpectedBaselines[$key]){''}else{[string]$ExpectedBaselines[$key]}
        $entry=Get-HistoryLatestEntry -Store $Store -BusinessId $observation.BusinessId -Domain $observation.Domain -ComparableOnly
        $actual=if($null -eq $entry){''}else{[string]$entry.LatestComparableObservationId}
        if($actual -cne $expected){
            return [pscustomobject][ordered]@{ Matches=$false; Key=$key; Expected=$expected; Actual=$actual }
        }
    }
    return [pscustomobject][ordered]@{ Matches=$true; Key=''; Expected=''; Actual='' }
}

function Update-HistoryIndexesAfterCommit {
    param([Parameter(Mandatory)]$Store,[Parameter(Mandatory)][object[]]$Observations)
    foreach($observation in @($Observations)){
        $prior=Get-HistoryLatestEntry -Store $Store -BusinessId $observation.BusinessId -Domain $observation.Domain
        $priorComparable=if($null -eq $prior){''}else{[string]$prior.LatestComparableObservationId}
        $latestComparable=if([bool]$observation.Comparable -and [string]$observation.OperationalStatus -ceq 'COMPLETE'){[string]$observation.ObservationId}else{$priorComparable}
        $entry=New-HistoryIndexEntry -BusinessId $observation.BusinessId -Domain $observation.Domain -LatestObservationId $observation.ObservationId -LatestComparableObservationId $latestComparable
        Write-HistoryIndexEntry -Store $Store -Entry $entry
    }
}

function Commit-HistoryRun {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)]$PreparedRun,
        [Parameter(Mandatory)][hashtable]$ExpectedBaselines,
        [AllowNull()][scriptblock]$FaultInjector=$null
    )

    if([IO.Path]::GetFullPath([string]$PreparedRun.StoreRoot) -cne [IO.Path]::GetFullPath([string]$Store.Root)){ throw 'Prepared run belongs to a different history store' }
    if(-not (Test-Path -LiteralPath $PreparedRun.StageRoot -PathType Container)){ throw 'Prepared run staging directory does not exist' }

    foreach($observation in @($PreparedRun.Observations)){
        $key=([string]$observation.BusinessId) + '|' + ([string]$observation.Domain
)
        if(-not $ExpectedBaselines.ContainsKey($key)){ throw "Missing expected baseline for $key" }
    }

    $lockPath=Join-Path $Store.Root '.writer-lock'
    $lock=$null
    try {
        $lock=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    } catch [IO.IOException] {
        return New-HistoryCommitResult -Code 'WRITER_LOCKED' -RunId $PreparedRun.RunManifest.RunId -Reason 'Exclusive history writer lock is already held'
    }

    $manifestCommitted=$false
    try {
        $cas=Test-HistoryExpectedBaselines -Store $Store -Observations @($PreparedRun.Observations) -ExpectedBaselines $ExpectedBaselines
        if(-not [bool]$cas.Matches){
            if(Test-Path -LiteralPath $PreparedRun.StageRoot){ Remove-Item -LiteralPath $PreparedRun.StageRoot -Recurse -Force -ErrorAction SilentlyContinue }
            return New-HistoryCommitResult -Code 'BASELINE_MOVED' -RunId $PreparedRun.RunManifest.RunId -RetryRequired $true -Reason ("Baseline moved for " + $cas.Key)
        }

        Publish-HistoryPreparedArtifacts -Store $Store -PreparedRun $PreparedRun
        Invoke-HistoryFaultCheckpoint -FaultInjector $FaultInjector -Name 'AFTER_ARTIFACTS'

        Publish-HistoryPreparedRecords -Store $Store -PreparedRun $PreparedRun
        Invoke-HistoryFaultCheckpoint -FaultInjector $FaultInjector -Name 'AFTER_OBSERVATIONS'
        Invoke-HistoryFaultCheckpoint -FaultInjector $FaultInjector -Name 'BEFORE_MANIFEST_COMMIT'

        [void](Write-HistoryTerminalManifest -Store $Store -PreparedRun $PreparedRun -CommitStatus 'COMMITTED')
        $manifestCommitted=$true

        Invoke-HistoryFaultCheckpoint -FaultInjector $FaultInjector -Name 'AFTER_MANIFEST_COMMIT'

        Update-HistoryIndexesAfterCommit -Store $Store -Observations @($PreparedRun.Observations)
        Invoke-HistoryFaultCheckpoint -FaultInjector $FaultInjector -Name 'AFTER_INDEX_UPDATE'

        if(Test-Path -LiteralPath $PreparedRun.StageRoot){ Remove-Item -LiteralPath $PreparedRun.StageRoot -Recurse -Force -ErrorAction SilentlyContinue }
        return New-HistoryCommitResult -Code 'COMMITTED' -RunId $PreparedRun.RunManifest.RunId
    } catch {
        $reason=$_.Exception.Message
        if($manifestCommitted){
            return New-HistoryCommitResult -Code 'COMMITTED' -RunId $PreparedRun.RunManifest.RunId -IndexRepairRequired $true -Reason $reason
        }

        try {
            [void](Write-HistoryTerminalManifest -Store $Store -PreparedRun $PreparedRun -CommitStatus 'ABORTED')
        } catch {
        }
        if(Test-Path -LiteralPath $PreparedRun.StageRoot){ Remove-Item -LiteralPath $PreparedRun.StageRoot -Recurse -Force -ErrorAction SilentlyContinue }
        return New-HistoryCommitResult -Code 'ABORTED' -RunId $PreparedRun.RunManifest.RunId -Reason $reason
    } finally {
        if($null -ne $lock){ $lock.Dispose() }
    }
}

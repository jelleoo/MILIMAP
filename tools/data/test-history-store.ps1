$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/history/history-contracts.ps1')
. (Join-Path $PSScriptRoot 'lib/history/history-fingerprints.ps1')
. (Join-Path $PSScriptRoot 'lib/history/history-store.ps1')

function Assert-True { param([bool]$Condition,[string]$Message); if(-not $Condition){throw $Message} }
function Assert-Equal { param($Actual,$Expected,[string]$Message); if($Actual -ne $Expected){throw "$Message (expected: $Expected, actual: $Actual)"} }
function Assert-Throws { param([scriptblock]$Action,[string]$Message); $threw=$false; try{& $Action}catch{$threw=$true}; if(-not $threw){throw $Message} }

function Write-TestJson {
    param([string]$Path,$Value)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding utf8
}

function Write-TestManifest {
    param($Store,[string]$RunId,[string]$CommitStatus,[string]$ExecutionStatus='COMPLETE',[string[]]$Completed=@())
    $manifest = New-HistoryRunManifest -RunId $RunId -StartedAt '2026-09-26T00:00:00Z' -CompletedAt $(if($CommitStatus -eq 'COMMITTED'){'2026-09-26T00:10:00Z'}else{''}) -RepositoryRevision ('a'*40) -HistoryContractVersion 1 -FingerprintSchemaVersion 1 -RequestedBusinessIds @('biz-0123456789abcdef0123456789abcdef') -CompletedBusinessIds $Completed -FailedBusinessIds @() -ExecutionStatus $ExecutionStatus -RunCommitStatus $CommitStatus
    Write-TestJson -Path (Join-Path (Join-Path $Store.RunsRoot $RunId) 'manifest.json') -Value $manifest
}

function Write-TestObservation {
    param($Store,[string]$Id,[string]$RunId,[string]$ObservedAt,[string]$Status='COMPLETE',[bool]$Comparable=$true,[object[]]$Artifacts=@())
    $obs = New-HistoryObservation -ObservationId $Id -RunId $RunId -BusinessId 'biz-0123456789abcdef0123456789abcdef' -Domain 'BENEFIT' -ObservedAt $ObservedAt -OperationalStatus $Status -Comparable $Comparable -InputFingerprint ('1'*64) -EvidenceFingerprint ('2'*64) -SemanticFingerprint ('3'*64) -ExecutionFingerprint ('4'*64) -ArtifactReferences $Artifacts
    Write-TestJson -Path (Join-Path $Store.ObservationsRoot ($Id + '.json')) -Value $obs
    return $obs
}

$root = Join-Path ([IO.Path]::GetTempPath()) ('milimap-history-store-' + [Guid]::NewGuid().ToString('N'))
try {
    $store = New-HistoryStoreLayout -Root $root
    foreach($path in @($store.RunsRoot,$store.ObservationsRoot,$store.ComparisonsRoot,$store.ArtifactsRoot,$store.IndexesRoot,$store.TempRoot)){
        Assert-True ($path.StartsWith([IO.Path]::GetFullPath($root),[StringComparison]::Ordinal)) 'Every store path must remain below root'
    }
    Assert-Throws { Read-HistoryObservation -Store $store -ObservationId '../escape' } 'Observation path traversal must be rejected'

    $hashA = Get-HistorySha256 -Text 'content-A'
    $hashB = Get-HistorySha256 -Text 'content-B'
    $a1 = Write-HistoryArtifact -Store $store -ContentHash $hashA -Extension 'html' -Text 'content-A'
    $a2 = Write-HistoryArtifact -Store $store -ContentHash $hashA -Extension 'html' -Text 'content-A'
    $b1 = Write-HistoryArtifact -Store $store -ContentHash $hashB -Extension 'html' -Text 'content-B'
    Assert-Equal $a1.RelativePath $a2.RelativePath 'Same content hash must resolve to same physical artifact'
    Assert-True ($a1.RelativePath -ne $b1.RelativePath) 'Different content hash must resolve to a different artifact'
    Assert-Throws { Write-HistoryArtifact -Store $store -ContentHash ('0'*64) -Extension 'html' -Text 'content-A' } 'Supplied hash must match artifact content'

    $artifactFiles = @(Get-ChildItem -LiteralPath $store.ArtifactsRoot -File -Recurse)
    Assert-Equal $artifactFiles.Count 2 'A/A/B content must create exactly two physical artifacts'

    $obs1 = Write-TestObservation -Store $store -Id 'obs-0001' -RunId 'run-0001' -ObservedAt '2026-09-26T00:01:00Z' -Artifacts @($a1)
    Write-TestManifest -Store $store -RunId 'run-0001' -CommitStatus 'COMMITTED' -Completed @($obs1.BusinessId)

    $obs2 = Write-TestObservation -Store $store -Id 'obs-0002' -RunId 'run-0002' -ObservedAt '2026-09-26T00:02:00Z' -Artifacts @($a2)
    Write-TestManifest -Store $store -RunId 'run-0002' -CommitStatus 'COMMITTED' -Completed @($obs2.BusinessId)

    $obs3 = Write-TestObservation -Store $store -Id 'obs-0003' -RunId 'run-0003' -ObservedAt '2026-09-26T00:03:00Z' -Artifacts @($b1)
    Write-TestManifest -Store $store -RunId 'run-0003' -CommitStatus 'COMMITTED' -Completed @($obs3.BusinessId)

    $failed = Write-TestObservation -Store $store -Id 'obs-0004' -RunId 'run-0004' -ObservedAt '2026-09-26T00:04:00Z' -Status 'FAILED' -Comparable $false
    Write-TestManifest -Store $store -RunId 'run-0004' -CommitStatus 'COMMITTED' -ExecutionStatus 'PARTIAL'

    $prepared = Write-TestObservation -Store $store -Id 'obs-0005' -RunId 'run-0005' -ObservedAt '2026-09-26T00:05:00Z'
    Write-TestManifest -Store $store -RunId 'run-0005' -CommitStatus 'PREPARED'

    $aborted = Write-TestObservation -Store $store -Id 'obs-0006' -RunId 'run-0006' -ObservedAt '2026-09-26T00:06:00Z'
    Write-TestManifest -Store $store -RunId 'run-0006' -CommitStatus 'ABORTED'

    $summary = Rebuild-HistoryIndexes -Store $store
    Assert-Equal $summary.CommittedObservationCount 4 'Only observations from COMMITTED runs participate in indexes'
    Assert-Equal $summary.IndexEntryCount 1 'One business/domain pair produces one index entry'

    $latest = Get-HistoryLatestEntry -Store $store -BusinessId $obs1.BusinessId -Domain 'BENEFIT'
    $latestComparable = Get-HistoryLatestEntry -Store $store -BusinessId $obs1.BusinessId -Domain 'BENEFIT' -ComparableOnly
    Assert-Equal $latest.ObservationId 'obs-0004' 'Latest observation includes committed FAILED observation'
    Assert-Equal $latestComparable.ObservationId 'obs-0003' 'Latest comparable must ignore committed FAILED observation'
    Assert-True ($latest.ObservationId -ne 'obs-0005' -and $latest.ObservationId -ne 'obs-0006') 'PREPARED/ABORTED observations never become baseline'

    $read = Read-HistoryObservation -Store $store -ObservationId 'obs-0003'
    Assert-Equal $read.ObservationId 'obs-0003' 'Observation must be directly readable by id'

    $indexPath = Get-HistoryIndexPath -Store $store -BusinessId $obs1.BusinessId -Domain 'BENEFIT'
    $indexBefore = Get-Content -LiteralPath $indexPath -Raw -Encoding utf8
    Remove-Item -LiteralPath $indexPath -Force
    Assert-Equal (Get-HistoryLatestEntry -Store $store -BusinessId $obs1.BusinessId -Domain 'BENEFIT') $null 'Missing derived index must not invent a baseline'
    [void](Rebuild-HistoryIndexes -Store $store)
    $indexAfter = Get-Content -LiteralPath $indexPath -Raw -Encoding utf8
    Assert-Equal $indexAfter $indexBefore 'Index rebuild must be deterministic'

    Set-Content -LiteralPath $indexPath -Value '{not-json' -Encoding utf8
    Assert-Throws { Get-HistoryLatestEntry -Store $store -BusinessId $obs1.BusinessId -Domain 'BENEFIT' } 'Malformed index must fail closed'
    [void](Rebuild-HistoryIndexes -Store $store)

    $badRun='run-bad-json'
    New-Item -ItemType Directory -Force -Path (Join-Path $store.RunsRoot $badRun) | Out-Null
    Set-Content -LiteralPath (Join-Path (Join-Path $store.RunsRoot $badRun) 'manifest.json') -Value '{bad-json' -Encoding utf8
    Assert-Throws { Rebuild-HistoryIndexes -Store $store } 'Malformed run manifest JSON must fail closed'
    Remove-Item -LiteralPath (Join-Path $store.RunsRoot $badRun) -Recurse -Force

    $missingArtifact = New-HistoryArtifactReference -Kind 'RAW_SOURCE_PAYLOAD' -ContentHash ('f'*64) -RelativePath ('artifacts/sha256/' + ('f'*64) + '.html')
    $obsBadRef = Write-TestObservation -Store $store -Id 'obs-bad-ref' -RunId 'run-bad-ref' -ObservedAt '2026-09-26T00:07:00Z' -Artifacts @($missingArtifact)
    Write-TestManifest -Store $store -RunId 'run-bad-ref' -CommitStatus 'COMMITTED' -Completed @($obsBadRef.BusinessId)
    Assert-Throws { Rebuild-HistoryIndexes -Store $store } 'Committed observation with missing artifact must fail closed'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'History store tests passed.'

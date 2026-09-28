Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/history/history-store.ps1')
. (Join-Path $PSScriptRoot 'lib/history/phase3-review-audit.ps1')

function Get-Phase3CommittedRunInventory {
    param([Parameter(Mandatory)]$Store)

    $committedIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($directory in @(Get-ChildItem -LiteralPath $Store.RunsRoot -Directory)) {
        $manifestPath = Get-HistoryRunManifestPath -Store $Store -RunId $directory.Name
        $manifest = Read-HistoryJsonFile -Store $Store -Path $manifestPath -Kind 'run manifest'
        if ($null -eq $manifest) { throw "Run directory has no manifest: $($directory.Name)" }
        Assert-HistoryRunManifest -Value $manifest
        if ([string]$manifest.RunId -cne [string]$directory.Name) { throw 'Run manifest identity mismatch' }
        if ([string]$manifest.RunCommitStatus -ceq 'PREPARED') { throw 'Run directory has no terminal manifest' }
        if ([string]$manifest.RunCommitStatus -ceq 'COMMITTED') { [void]$committedIds.Add([string]$manifest.RunId) }
    }
    return [pscustomobject]@{ CommittedRunIds=$committedIds; CommittedRunCount=$committedIds.Count }
}

function Get-Phase3CommittedObservationInventory {
    param([Parameter(Mandatory)]$Store,[Parameter(Mandatory)]$RunInventory)

    $byId = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $seenIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $ignoredCount = 0
    foreach ($file in @(Get-ChildItem -LiteralPath $Store.ObservationsRoot -File -Filter '*.json')) {
        $observation = Read-HistoryJsonFile -Store $Store -Path $file.FullName -Kind 'observation'
        Assert-HistoryObservation -Value $observation
        if ([string]$file.BaseName -cne [string]$observation.ObservationId) { throw 'Observation filename identity mismatch' }
        if (-not $seenIds.Add([string]$observation.ObservationId)) { throw 'Duplicate observation ID' }
        if ($RunInventory.CommittedRunIds.Contains([string]$observation.RunId)) {
            $byId.Add([string]$observation.ObservationId,$observation)
        } else {
            $ignoredCount++
        }
    }
    return [pscustomobject]@{ ObservationById=$byId; AllObservationIds=$seenIds; IgnoredCount=$ignoredCount }
}

function Get-Phase3CommittedComparisonInventory {
    param([Parameter(Mandatory)]$Store,[Parameter(Mandatory)]$RunInventory,[Parameter(Mandatory)]$ObservationInventory)

    $byCurrentId = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $seenIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $ignoredCount = 0
    foreach ($file in @(Get-ChildItem -LiteralPath $Store.ComparisonsRoot -File -Filter '*.json')) {
        $comparison = Read-HistoryJsonFile -Store $Store -Path $file.FullName -Kind 'comparison'
        Assert-ObservationComparison -Value $comparison
        if ([string]$file.BaseName -cne [string]$comparison.ComparisonId) { throw 'Comparison filename identity mismatch' }
        if (-not $seenIds.Add([string]$comparison.ComparisonId)) { throw 'Duplicate comparison ID' }
        if (-not $RunInventory.CommittedRunIds.Contains([string]$comparison.RunId)) {
            $ignoredCount++
            continue
        }

        $currentId = [string]$comparison.CurrentObservationId
        if (-not $ObservationInventory.ObservationById.ContainsKey($currentId)) { throw 'Current observation missing from committed history' }
        $current = $ObservationInventory.ObservationById[$currentId]
        foreach ($property in @('BusinessId','Domain','RunId')) {
            if ([string]$comparison.$property -cne [string]$current.$property) { throw "Current $property mismatch" }
        }
        $previousId = [string]$comparison.PreviousObservationId
        if ($previousId) {
            if (-not $ObservationInventory.AllObservationIds.Contains($previousId)) { throw 'Previous observation missing' }
            if (-not $ObservationInventory.ObservationById.ContainsKey($previousId)) { throw 'Previous observation is not committed' }
            $previous = $ObservationInventory.ObservationById[$previousId]
            foreach ($property in @('BusinessId','Domain')) {
                if ([string]$comparison.$property -cne [string]$previous.$property) { throw "Previous observation $property mismatch" }
            }
        }
        if ($byCurrentId.ContainsKey($currentId)) { throw 'Duplicate committed comparison for current observation' }
        $byCurrentId.Add($currentId,$comparison)
    }
    return [pscustomobject]@{ ComparisonByCurrentObservationId=$byCurrentId; IgnoredCount=$ignoredCount }
}

function Assert-Phase3UniqueArtifactReferences {
    param([Parameter(Mandatory)]$Store,[Parameter(Mandatory)]$ObservationInventory)

    $validatedKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($observation in $ObservationInventory.ObservationById.Values) {
        foreach ($reference in @($observation.ArtifactReferences)) {
            $key = ([string]$reference.ContentHash) + '|' + ([string]$reference.RelativePath)
            if ($validatedKeys.Add($key)) {
                Assert-HistoryArtifactReferenceExists -Store $Store -Reference $reference
            }
        }
    }
    return [pscustomobject]@{ UniqueArtifactReferenceCount=$validatedKeys.Count; UniqueArtifactsValidated=$validatedKeys.Count }
}

function Invoke-Phase3ReviewAudit {
    param([Parameter(Mandatory)]$Store)

    foreach ($root in @($Store.RunsRoot,$Store.ObservationsRoot,$Store.ComparisonsRoot,$Store.ArtifactsRoot)) {
        $safeRoot = Assert-HistoryStorePathWithinRoot -Store $Store -Path ([string]$root)
        if (-not (Test-Path -LiteralPath $safeRoot -PathType Container)) { throw "History store directory missing: $safeRoot" }
    }

    $runs = Get-Phase3CommittedRunInventory -Store $Store
    $observations = Get-Phase3CommittedObservationInventory -Store $Store -RunInventory $runs
    $comparisons = Get-Phase3CommittedComparisonInventory -Store $Store -RunInventory $runs -ObservationInventory $observations
    $artifacts = Assert-Phase3UniqueArtifactReferences -Store $Store -ObservationInventory $observations
    $items = [Collections.Generic.List[object]]::new()
    foreach ($observation in $observations.ObservationById.Values) {
        $currentId = [string]$observation.ObservationId
        if ($comparisons.ComparisonByCurrentObservationId.ContainsKey($currentId)) {
            $items.Add((New-Phase3ReviewItem -Observation $observation -Comparison $comparisons.ComparisonByCurrentObservationId[$currentId]))
        } else {
            $items.Add((New-Phase3ReviewItem -Observation $observation))
        }
    }
    $resultItems = @($items.ToArray())
    $summary = New-Phase3ReviewAuditSummary -Items $resultItems -CommittedRunCount $runs.CommittedRunCount -CommittedObservationCount $observations.ObservationById.Count -CommittedComparisonCount $comparisons.ComparisonByCurrentObservationId.Count -IgnoredUncommittedRecordCount ($observations.IgnoredCount + $comparisons.IgnoredCount) -UniqueArtifactReferenceCount $artifacts.UniqueArtifactReferenceCount -UniqueArtifactsValidated $artifacts.UniqueArtifactsValidated
    return [pscustomobject][ordered]@{ Items=$resultItems; Summary=$summary }
}

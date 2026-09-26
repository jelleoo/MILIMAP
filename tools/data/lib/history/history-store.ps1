Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'history-contracts.ps1')
. (Join-Path $PSScriptRoot 'history-fingerprints.ps1')

function Assert-HistoryStorePathWithinRoot {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)][string]$Path
    )
    $root = [IO.Path]::GetFullPath([string]$Store.Root)
    $full = [IO.Path]::GetFullPath($Path)
    $rootPrefix = $root.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($rootPrefix,[StringComparison]::Ordinal)) {
        throw "History path escapes store root: $Path"
    }
    return $full
}

function New-HistoryStoreLayout {
    param([Parameter(Mandatory)][string]$Root)

    if ([string]::IsNullOrWhiteSpace($Root)) { throw 'History root is required' }
    $fullRoot = [IO.Path]::GetFullPath($Root)
    $layout = [pscustomobject][ordered]@{
        Root=$fullRoot
        RunsRoot=(Join-Path $fullRoot 'runs')
        ObservationsRoot=(Join-Path $fullRoot 'observations')
        ComparisonsRoot=(Join-Path $fullRoot 'comparisons')
        ArtifactsRoot=(Join-Path $fullRoot 'artifacts/sha256')
        IndexesRoot=(Join-Path $fullRoot 'indexes')
        TempRoot=(Join-Path $fullRoot 'tmp')
    }
    foreach ($path in @($layout.RunsRoot,$layout.ObservationsRoot,$layout.ComparisonsRoot,$layout.ArtifactsRoot,$layout.IndexesRoot,$layout.TempRoot)) {
        [void](Assert-HistoryStorePathWithinRoot -Store $layout -Path $path)
        New-Item -ItemType Directory -Force -Path $path | Out-Null
    }
    return $layout
}

function Get-HistoryObservationPath {
    param([Parameter(Mandatory)]$Store,[Parameter(Mandatory)][string]$ObservationId)
    Assert-HistoryToken -Value $ObservationId -Name 'observation id'
    if ($ObservationId.Contains('/') -or $ObservationId.Contains('\') -or $ObservationId.Contains('..')) {
        throw 'Observation id cannot contain path separators or traversal'
    }
    return Assert-HistoryStorePathWithinRoot -Store $Store -Path (Join-Path $Store.ObservationsRoot ($ObservationId + '.json'))
}

function Get-HistoryRunManifestPath {
    param([Parameter(Mandatory)]$Store,[Parameter(Mandatory)][string]$RunId)
    Assert-HistoryToken -Value $RunId -Name 'run id'
    if ($RunId.Contains('/') -or $RunId.Contains('\') -or $RunId.Contains('..')) {
        throw 'Run id cannot contain path separators or traversal'
    }
    return Assert-HistoryStorePathWithinRoot -Store $Store -Path (Join-Path (Join-Path $Store.RunsRoot $RunId) 'manifest.json')
}

function Get-HistoryIndexPath {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)][string]$BusinessId,
        [Parameter(Mandatory)][ValidateSet('LOCATION','BENEFIT')][string]$Domain
    )
    Assert-HistoryBusinessId -Value $BusinessId
    $fileName = $BusinessId + '.' + $Domain.ToLowerInvariant() + '.json'
    return Assert-HistoryStorePathWithinRoot -Store $Store -Path (Join-Path $Store.IndexesRoot $fileName)
}

function Get-HistoryArtifactPath {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)][string]$ContentHash,
        [Parameter(Mandatory)][string]$Extension
    )
    Assert-HistoryHash -Value $ContentHash -Name 'content hash'
    if ($Extension -cnotmatch '^[a-z0-9]{1,16}$') { throw 'Invalid artifact extension' }
    return Assert-HistoryStorePathWithinRoot -Store $Store -Path (Join-Path $Store.ArtifactsRoot ($ContentHash + '.' + $Extension))
}

function Get-HistoryRelativePath {
    param([Parameter(Mandatory)]$Store,[Parameter(Mandatory)][string]$FullPath)
    $root = [IO.Path]::GetFullPath([string]$Store.Root)
    $safeFull = Assert-HistoryStorePathWithinRoot -Store $Store -Path $FullPath
    $relative = [IO.Path]::GetRelativePath($root,$safeFull)
    return ($relative -replace '\','/')
}

function Write-HistoryArtifact {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)][string]$ContentHash,
        [Parameter(Mandatory)][string]$Extension,
        [byte[]]$Bytes,
        [AllowNull()][string]$Text
    )
    Assert-HistoryHash -Value $ContentHash -Name 'content hash'
    $hasBytes = $PSBoundParameters.ContainsKey('Bytes')
    $hasText = $PSBoundParameters.ContainsKey('Text')
    if ($hasBytes -eq $hasText) { throw 'Provide exactly one of Bytes or Text' }

    $payload = if ($hasBytes) { [byte[]]$Bytes } else { [Text.Encoding]::UTF8.GetBytes([string]$Text) }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $actualHash = ([BitConverter]::ToString($sha.ComputeHash($payload)) -replace '-','').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
    if ($actualHash -cne $ContentHash) { throw 'Artifact ContentHash does not match payload' }

    $path = Get-HistoryArtifactPath -Store $Store -ContentHash $ContentHash -Extension $Extension
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $existing = [IO.File]::ReadAllBytes($path)
        $shaExisting = [Security.Cryptography.SHA256]::Create()
        try {
            $existingHash = ([BitConverter]::ToString($shaExisting.ComputeHash($existing)) -replace '-','').ToLowerInvariant()
        } finally {
            $shaExisting.Dispose()
        }
        if ($existingHash -cne $ContentHash) { throw 'Existing artifact content does not match content-addressed path' }
    } else {
        $temp = Assert-HistoryStorePathWithinRoot -Store $Store -Path (Join-Path $Store.TempRoot ('artifact-' + [Guid]::NewGuid().ToString('N') + '.tmp'))
        [IO.File]::WriteAllBytes($temp,$payload)
        try {
            [IO.File]::Move($temp,$path,$false)
        } catch [IO.IOException] {
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw }
        } finally {
            if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
        }
    }

    return New-HistoryArtifactReference -Kind 'HISTORY_ARTIFACT' -ContentHash $ContentHash -RelativePath (Get-HistoryRelativePath -Store $Store -FullPath $path)
}

function Read-HistoryJsonFile {
    param([Parameter(Mandatory)]$Store,[Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Kind)
    $safePath = Assert-HistoryStorePathWithinRoot -Store $Store -Path $Path
    if (-not (Test-Path -LiteralPath $safePath -PathType Leaf)) { return $null }
    try {
        return (Get-Content -LiteralPath $safePath -Raw -Encoding utf8 | ConvertFrom-Json)
    } catch {
        throw "Malformed $Kind JSON: $safePath"
    }
}

function Read-HistoryObservation {
    param([Parameter(Mandatory)]$Store,[Parameter(Mandatory)][string]$ObservationId)
    $path = Get-HistoryObservationPath -Store $Store -ObservationId $ObservationId
    $value = Read-HistoryJsonFile -Store $Store -Path $path -Kind 'observation'
    if ($null -eq $value) { return $null }
    Assert-HistoryObservation $value
    if ([string]$value.ObservationId -cne $ObservationId) { throw 'Observation file identity mismatch' }
    return $value
}

function Assert-HistoryArtifactReferenceExists {
    param([Parameter(Mandatory)]$Store,[Parameter(Mandatory)]$Reference)
    Assert-HistoryArtifactReference $Reference
    $candidate = Assert-HistoryStorePathWithinRoot -Store $Store -Path (Join-Path $Store.Root ([string]$Reference.RelativePath))
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw "Referenced history artifact does not exist: $($Reference.RelativePath)"
    }
    $bytes = [IO.File]::ReadAllBytes($candidate)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $actual = ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-','').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
    if ($actual -cne [string]$Reference.ContentHash) { throw 'Referenced artifact hash mismatch' }
}

function Get-HistoryLatestEntry {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)][string]$BusinessId,
        [Parameter(Mandatory)][ValidateSet('LOCATION','BENEFIT')][string]$Domain,
        [switch]$ComparableOnly
    )
    $path = Get-HistoryIndexPath -Store $Store -BusinessId $BusinessId -Domain $Domain
    $entry = Read-HistoryJsonFile -Store $Store -Path $path -Kind 'history index'
    if ($null -eq $entry) { return $null }
    Assert-HistoryIndexEntry $entry
    if ([string]$entry.BusinessId -cne $BusinessId -or [string]$entry.Domain -cne $Domain) {
        throw 'History index identity mismatch'
    }
    if ($ComparableOnly -and [string]::IsNullOrWhiteSpace([string]$entry.LatestComparableObservationId)) { return $null }
    return $entry
}

function Write-HistoryIndexEntry {
    param([Parameter(Mandatory)]$Store,[Parameter(Mandatory)]$Entry)
    Assert-HistoryIndexEntry $Entry
    $path = Get-HistoryIndexPath -Store $Store -BusinessId $Entry.BusinessId -Domain $Entry.Domain
    $temp = Assert-HistoryStorePathWithinRoot -Store $Store -Path (Join-Path $Store.TempRoot ('index-' + [Guid]::NewGuid().ToString('N') + '.tmp'))
    $json = $Entry | ConvertTo-Json -Depth 10 -Compress
    Set-Content -LiteralPath $temp -Value $json -Encoding utf8 -NoNewline
    try {
        [IO.File]::Move($temp,$path,$true)
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
}

function Rebuild-HistoryIndexes {
    param([Parameter(Mandatory)]$Store)

    $committedRuns = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($runDirectory in @(Get-ChildItem -LiteralPath $Store.RunsRoot -Directory | Sort-Object Name)) {
        $manifestPath = Get-HistoryRunManifestPath -Store $Store -RunId $runDirectory.Name
        $manifest = Read-HistoryJsonFile -Store $Store -Path $manifestPath -Kind 'run manifest'
        if ($null -eq $manifest) { throw "Run directory has no manifest: $($runDirectory.Name)" }
        Assert-HistoryRunManifest $manifest
        if ([string]$manifest.RunId -cne [string]$runDirectory.Name) { throw 'Run manifest identity mismatch' }
        if ([string]$manifest.RunCommitStatus -ceq 'COMMITTED') { [void]$committedRuns.Add([string]$manifest.RunId) }
    }

    $groups = @{}
    $committedObservationCount = 0
    foreach ($file in @(Get-ChildItem -LiteralPath $Store.ObservationsRoot -File -Filter '*.json' | Sort-Object Name)) {
        $observation = Read-HistoryJsonFile -Store $Store -Path $file.FullName -Kind 'observation'
        Assert-HistoryObservation $observation
        if ($file.BaseName -cne [string]$observation.ObservationId) { throw 'Observation filename identity mismatch' }
        if (-not $committedRuns.Contains([string]$observation.RunId)) { continue }

        foreach ($reference in @($observation.ArtifactReferences)) {
            Assert-HistoryArtifactReferenceExists -Store $Store -Reference $reference
        }

        $committedObservationCount++
        $key = ([string]$observation.BusinessId) + '|' + ([string]$observation.Domain
)
        if (-not $groups.ContainsKey($key)) { $groups[$key] = [Collections.Generic.List[object]]::new() }
        $groups[$key].Add($observation)
    }

    foreach ($existing in @(Get-ChildItem -LiteralPath $Store.IndexesRoot -File -Filter '*.json')) {
        Remove-Item -LiteralPath $existing.FullName -Force
    }

    $indexEntryCount = 0
    foreach ($key in @($groups.Keys | Sort-Object -CaseSensitive)) {
        $items = @($groups[$key] | Sort-Object @{Expression={ [DateTimeOffset]::Parse([string]$_.ObservedAt,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind) }}, @{Expression={ [string]$_.ObservationId }})
        $latest = $items[-1]
        $comparableItems = @($items | Where-Object { [bool]$_.Comparable -and [string]$_.OperationalStatus -ceq 'COMPLETE' })
        $latestComparableId = if ($comparableItems.Count -gt 0) { [string]$comparableItems[-1].ObservationId } else { '' }
        $entry = New-HistoryIndexEntry -BusinessId $latest.BusinessId -Domain $latest.Domain -LatestObservationId $latest.ObservationId -LatestComparableObservationId $latestComparableId
        Write-HistoryIndexEntry -Store $Store -Entry $entry
        $indexEntryCount++
    }

    return [pscustomobject][ordered]@{
        CommittedObservationCount=$committedObservationCount
        IndexEntryCount=$indexEntryCount
    }
}

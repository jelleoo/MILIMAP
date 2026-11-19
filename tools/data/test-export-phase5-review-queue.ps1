Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'export-phase5-review-queue.ps1')
. (Join-Path $PSScriptRoot 'lib/identity/normalize-business.ps1')
. (Join-Path $PSScriptRoot 'lib/history/compare-location-history.ps1')

function Assert-RqTestEqual {
    param([AllowNull()]$Actual, [AllowNull()]$Expected, [Parameter(Mandatory)][string]$Message)
    if ($Actual -cne $Expected) {
        throw "$Message (expected: $Expected, actual: $Actual)"
    }
}

function Assert-RqTestTrue {
    param([bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

function Assert-RqTestThrowsMatching {
    param([scriptblock]$Action, [string]$Pattern, [string]$Message)
    try {
        & $Action | Out-Null
    } catch {
        if ($_.Exception.Message -match $Pattern) { return }
        throw "$Message (wrong exception: $($_.Exception.Message))"
    }
    throw "$Message (did not throw)"
}

function Write-RqTestJsonFile {
    param([string]$Path, $Value)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        [void][IO.Directory]::CreateDirectory($parent)
    }
    $text = $Value | ConvertTo-Json -Depth 20 -Compress
    [IO.File]::WriteAllText($Path, $text, [Text.UTF8Encoding]::new($false))
}

function Get-RqTestStoreFileInventory {
    param($Store)
    return @(
        Get-ChildItem -LiteralPath $Store.Root -Recurse -File |
            Sort-Object FullName |
            ForEach-Object { $_.FullName + '|' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    )
}

function New-RqTestBusinessRow {
    param(
        [string]$BusinessId,
        [string]$Name = '테스트식당',
        [string]$RoadAddress = '경기도 양주시 테스트로 10',
        [string]$Benefit = '10% 할인',
        [string]$Status = '이용 가능',
        [string]$CoordStatus = '확인 완료'
    )
    return [pscustomobject][ordered]@{
        businessId = $BusinessId
        업종명 = '음식'
        업소명 = $Name
        시도 = '경기도'
        시군구 = '양주시'
        소재지도로명주소 = $RoadAddress
        소재지지번주소 = ''
        위도 = '37.7851'
        경도 = '127.0457'
        좌표출처 = 'API HUB'
        좌표출처URL = 'https://map.example.go.kr/1'
        좌표검증상태 = $CoordStatus
        할인정보 = $Benefit
        적용대상 = '현역 장병'
        이용조건 = '평일'
        인증방법 = '군인증'
        업소전화번호 = '031-000-0010'
        출처유형 = '지자체 공식 자료'
        출처URL = 'https://city.example.go.kr/benefit'
        최근확인일 = '2026-10-01'
        혜택상태 = $Status
        수집자 = 'test'
        비고 = ''
    }
}

function New-RqTestBenefitObservationCommit {
    param(
        $Store,
        [string]$RunId,
        [string]$BusinessId,
        [int]$RowNumber,
        [object]$Row,
        [string]$ObservedAt,
        [string]$Revision,
        [string]$BenefitState = 'ACTIVE',
        [string]$ReviewClass = 'GREEN',
        [string]$ExtractionStatus = 'COMPLETE',
        [string]$LocationStatus = 'LOCATED',
        [string[]]$ChangeCandidates = @(),
        [string[]]$ReasonCodes = @(),
        [string]$PreviousObservationId = '',
        [string]$CommitStatus = 'COMMITTED',
        [string]$RawSentinelText = '',
        [string]$ScopedSentinelJson = '',
        [switch]$NoComparison
    )

    $business = ConvertTo-NormalizedBusiness -Row $Row -SourceRowNumber $RowNumber
    $benefit = ConvertTo-Phase2CanonicalBenefitRecord -Row $Row -SourceRowNumber $RowNumber
    $claimValue = [string]$Row.할인정보
    $claimResult = if ($BenefitState -ceq 'ENDED') { 'ENDED' } else { 'CONFIRMED' }
    $validated = New-ValidatedBenefitClaim -ClaimType 'BENEFIT_DESCRIPTION' -Value $claimValue -ValidationStatus 'VALIDATED' -EvidenceText $claimValue -EvidenceReference 'TABLE_ROW:1:CELL:2' -SourceUrl 'https://city.example.go.kr/benefit'
    $claim = New-BenefitClaimVerification -ClaimType 'BENEFIT_DESCRIPTION' -CanonicalValue $claimValue -EvidenceValue $claimValue -Result $claimResult -ValidatedClaim $validated -ReasonCodes @()
    $result = New-BenefitVerificationResult -SourceRowNumber $RowNumber -BusinessIdentity $business -BenefitState $BenefitState -ReviewClass $ReviewClass -ReasonCodes $ReasonCodes -ClaimResults @($claim) -Evidence @() -Warnings @() -ProductionAction 'NONE'
    $diagnostic = [pscustomobject]@{
        Url = 'https://city.example.go.kr/benefit'
        SourceFormat = 'HTML'
        FetchStatus = 'COMPLETE'
        ContentHash = ('b' * 64)
        ObservedAt = $ObservedAt
        AdapterId = 'HTML_GENERIC'
        AdapterVersion = 1
        AdapterStatus = 'COMPLETE'
        LocationOperationalStatus = 'COMPLETE'
        LocationStatus = $LocationStatus
        CandidateReferences = @('TABLE_ROW:1')
        OfficialityStatus = 'VERIFIED_OFFICIAL'
        BusinessBindingStatus = 'STRONG'
        ExtractionStatus = $ExtractionStatus
        ValidatedClaims = @()
        ReasonCodes = @()
    }
    $pkg = New-BenefitHistoryObservationPackage `
        -Store $Store `
        -RunId $RunId `
        -BusinessId $BusinessId `
        -ObservedAt $ObservedAt `
        -RepositoryRevision $Revision `
        -Benefit $benefit `
        -BusinessIdentity $business `
        -CanonicalPhone '031-000-0010' `
        -Result $result `
        -EvidenceDiagnostics @($diagnostic) `
        -OperationalStatus ([pscustomobject]@{ DiscoveryStatus = 'COMPLETE'; ExtractionStatus = $ExtractionStatus })

    foreach ($art in @($pkg.PreparedArtifacts)) {
        [void](Write-HistoryArtifact -Store $Store -ContentHash $art.ContentHash -Extension $art.Extension -Text $art.Text)
    }

    $obs = $pkg.Observation
    if ($RawSentinelText -or $ScopedSentinelJson) {
        $extraRefs = [Collections.Generic.List[object]]::new()
        foreach ($r in @($obs.ArtifactReferences)) { [void]$extraRefs.Add($r) }
        if ($RawSentinelText) {
            $rawHash = Get-HistorySha256 -Text $RawSentinelText
            $rawRef = Write-HistoryArtifact -Store $Store -ContentHash $rawHash -Extension 'html' -Text $RawSentinelText
            $extraRefs.Add((New-HistoryArtifactReference -Kind 'RAW_SOURCE_PAYLOAD' -ContentHash $rawRef.ContentHash -RelativePath $rawRef.RelativePath))
        }
        if ($ScopedSentinelJson) {
            $scopedHash = Get-HistorySha256 -Text $ScopedSentinelJson
            $scopedRef = Write-HistoryArtifact -Store $Store -ContentHash $scopedHash -Extension 'json' -Text $ScopedSentinelJson
            $extraRefs.Add((New-HistoryArtifactReference -Kind 'BENEFIT_SCOPED_EVIDENCE' -ContentHash $scopedRef.ContentHash -RelativePath $scopedRef.RelativePath))
        }
        $obs.ArtifactReferences = @($extraRefs.ToArray())
    }

    Write-RqTestJsonFile -Path (Get-HistoryObservationPath -Store $Store -ObservationId $obs.ObservationId) -Value $obs

    if (-not $NoComparison) {
        $cmpStatus = if ($ExtractionStatus -cne 'COMPLETE') { 'UNAVAILABLE' } else { 'COMPLETE' }
        $cmpId = 'cmp-' + (Get-HistorySha256 -Text ($RunId + '|' + $obs.ObservationId)).Substring(0, 32)
        $cmpParams = @{
            ComparisonId = $cmpId
            RunId = $RunId
            BusinessId = $BusinessId
            Domain = 'BENEFIT'
            PreviousObservationId = $PreviousObservationId
            CurrentObservationId = $obs.ObservationId
            ComparisonStatus = $cmpStatus
        }
        if ($ChangeCandidates.Count -gt 0) {
            $cmpParams.ChangeCandidates = $ChangeCandidates
            if ($ChangeCandidates -cnotcontains 'BASELINE_ESTABLISHED') {
                $cmpParams.DeltaDimensions = @('SEMANTIC')
            }
        }
        if ($ReasonCodes.Count -gt 0) {
            $cmpParams.ReasonCodes = $ReasonCodes
        }
        $cmp = New-ObservationComparison @cmpParams
        Write-RqTestJsonFile -Path (Join-Path $Store.ComparisonsRoot ($cmpId + '.json')) -Value $cmp
    }

    $execStatus = if ($ExtractionStatus -ceq 'FAILED') { 'FAILED' } elseif ($ExtractionStatus -cne 'COMPLETE') { 'PARTIAL' } else { 'COMPLETE' }
    $completedAt = if ($CommitStatus -ceq 'COMMITTED') { $ObservedAt } else { '' }
    $manifestParams = @{
        RunId = $RunId
        StartedAt = $ObservedAt
        CompletedAt = $completedAt
        RepositoryRevision = $Revision
        RequestedBusinessIds = @($BusinessId)
        ExecutionStatus = $execStatus
        RunCommitStatus = $CommitStatus
    }
    if ($ExtractionStatus -ceq 'COMPLETE') {
        $manifestParams.CompletedBusinessIds = @($BusinessId)
    } else {
        $manifestParams.FailedBusinessIds = @($BusinessId)
    }
    $manifest = New-HistoryRunManifest @manifestParams
    Write-RqTestJsonFile -Path (Get-HistoryRunManifestPath -Store $Store -RunId $RunId) -Value $manifest
    return $obs
}

function New-RqTestLocationObservationCommit {
    param(
        $Store,
        [string]$RunId,
        [string]$BusinessId,
        [int]$RowNumber,
        [object]$Row,
        [string]$ObservedAt,
        [string]$Revision,
        [string]$Classification = 'GREEN',
        [string[]]$ChangeCandidates = @()
    )

    $business = ConvertTo-NormalizedBusiness -Row $Row -SourceRowNumber $RowNumber
    $discovery = New-PoiDiscoveryEvidence -StrategyCode 'NAME_FULL_ADDRESS' -Query '테스트' -QueryOrder 1 -ResultPosition 1 -ResultCount 1
    $candidate = New-PoiCandidate -CandidateKey 'naver-1' -Provider 'NAVER_API_HUB_LOCAL' -OriginalName ([string]$Row.업소명) -NormalizedName (([string]$Row.업소명) -replace '\s', '') -RoadAddress ([string]$Row.소재지도로명주소) -LotAddress '' -Latitude 37.7851 -Longitude 127.0457 -Phone '031-000-0010' -Category '음식점' -ProviderLink 'https://map.example/1' -DiscoveredBy @($discovery)
    $attempt = New-PoiQueryAttempt -StrategyCode 'NAME_FULL_ADDRESS' -Query '테스트' -QueryOrder 1 -Status 'SUCCESS' -ResultCount 1
    $batch = New-PoiDiscoveryBatch -SourceRowNumber $RowNumber -Status 'COMPLETE' -Candidates @($candidate) -QueryAttempts @($attempt)
    $selected = if ($Classification -ceq 'RED') { $null } else { $candidate }
    $keys = if ($Classification -ceq 'RED') { @() } else { @($candidate.CandidateKey) }
    $reasons = if ($Classification -ceq 'GREEN') { @('SINGLE_STRONG_CANDIDATE') } else { @('MULTIPLE_PLAUSIBLE_CANDIDATES') }
    $cnt = if ($Classification -ceq 'RED') { 0 } else { 1 }
    $result = New-PoiMatchResult -SourceRowNumber $RowNumber -EvaluationStatus 'COMPLETE' -Classification $Classification -SelectedCandidate $selected -RankedCandidateKeys $keys -ReasonCodes $reasons -ConflictCodes @() -Evidence @() -EvaluatedCandidateCount $cnt -SurvivingCandidateCount $cnt -ProductionAction 'NONE'
    $pkg = New-LocationHistoryObservationPackage -Store $Store -RunId $RunId -BusinessId $BusinessId -ObservedAt $ObservedAt -RepositoryRevision $Revision -Business $business -DiscoveryBatch $batch -Result $result
    foreach ($art in @($pkg.PreparedArtifacts)) {
        [void](Write-HistoryArtifact -Store $Store -ContentHash $art.ContentHash -Extension $art.Extension -Text $art.Text)
    }
    $obs = $pkg.Observation
    Write-RqTestJsonFile -Path (Get-HistoryObservationPath -Store $Store -ObservationId $obs.ObservationId) -Value $obs
    $cmpId = 'cmp-' + (Get-HistorySha256 -Text ($RunId + '|' + $obs.ObservationId)).Substring(0, 32)
    $locCmpParams = @{
        ComparisonId = $cmpId
        RunId = $RunId
        BusinessId = $BusinessId
        Domain = 'LOCATION'
        CurrentObservationId = $obs.ObservationId
        ComparisonStatus = 'COMPLETE'
    }
    if ($ChangeCandidates.Count -gt 0) {
        $locCmpParams.ChangeCandidates = $ChangeCandidates
    }
    $cmp = New-ObservationComparison @locCmpParams
    Write-RqTestJsonFile -Path (Join-Path $Store.ComparisonsRoot ($cmpId + '.json')) -Value $cmp
    $manifest = New-HistoryRunManifest -RunId $RunId -StartedAt $ObservedAt -CompletedAt $ObservedAt -RepositoryRevision $Revision -RequestedBusinessIds @($BusinessId) -CompletedBusinessIds @($BusinessId) -ExecutionStatus 'COMPLETE' -RunCommitStatus 'COMMITTED'
    Write-RqTestJsonFile -Path (Get-HistoryRunManifestPath -Store $Store -RunId $RunId) -Value $manifest
    return $obs
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('milimap-rq-test-' + [guid]::NewGuid().ToString('N'))
$revision = 'a' * 40
try {
    [void][IO.Directory]::CreateDirectory($tempRoot)
    $historyRoot = Join-Path $tempRoot 'history'
    $store = New-HistoryStoreLayout -Root $historyRoot
    $canonicalPath = Join-Path $tempRoot 'canonical.csv'
    $outputAllDir = Join-Path $tempRoot 'export-all'
    $outputLatestDir = Join-Path $tempRoot 'export-latest'
    $outputBenefitDir = Join-Path $tempRoot 'export-benefit'
    $outputCliDir = Join-Path $tempRoot 'export-cli'

    $bizFastBenefit = 'biz-11111111111111111111111111111111'
    $bizHumanChange = 'biz-22222222222222222222222222222222'
    $bizYellow = 'biz-33333333333333333333333333333333'
    $bizRedEnded = 'biz-44444444444444444444444444444444'
    $bizOpFailure = 'biz-55555555555555555555555555555555'
    $bizNoComparison = 'biz-66666666666666666666666666666666'
    $bizBare = 'biz-77777777777777777777777777777777'
    $bizOrphanCanonical = 'biz-99999999999999999999999999999999'

    $rows = @(
        (New-RqTestBusinessRow -BusinessId $bizFastBenefit -Name '빠른검토식당'),
        (New-RqTestBusinessRow -BusinessId $bizHumanChange -Name '변경검토식당'),
        (New-RqTestBusinessRow -BusinessId $bizYellow -Name '보류검토식당' -Status '확인 필요'),
        (New-RqTestBusinessRow -BusinessId $bizRedEnded -Name '종료검토식당' -Status '종료'),
        (New-RqTestBusinessRow -BusinessId $bizOpFailure -Name '실패보류식당'),
        (New-RqTestBusinessRow -BusinessId $bizNoComparison -Name '감사보류식당'),
        (New-RqTestBusinessRow -BusinessId $bizBare -Name '미투영보류식당')
    )
    $rows | Export-Csv -LiteralPath $canonicalPath -NoTypeInformation -Encoding utf8

    # 1) Multi-run BENEFIT (older +09:00 and newer UTC) + RAW/C_LITE sentinel leakage test
    $oldObs = New-RqTestBenefitObservationCommit -Store $store -RunId 'run-b-fast-old' -BusinessId $bizFastBenefit -RowNumber 2 -Row $rows[0] -ObservedAt '2026-10-20T09:00:00+09:00' -Revision $revision -BenefitState 'ACTIVE' -ReviewClass 'GREEN' -ChangeCandidates @('BASELINE_ESTABLISHED')
    $newObs = New-RqTestBenefitObservationCommit -Store $store -RunId 'run-b-fast-new' -BusinessId $bizFastBenefit -RowNumber 2 -Row $rows[0] -ObservedAt '2026-10-21T01:00:00Z' -Revision $revision -BenefitState 'ACTIVE' -ReviewClass 'GREEN' -ChangeCandidates @() -PreviousObservationId $oldObs.ObservationId -RawSentinelText '<html>SENTINEL_RAW_HTML_SECRET_NEVER_EXPORT</html>' -ScopedSentinelJson '{"Sentinel":"SENTINEL_SCOPED_HTML_SECRET"}'

    # Uncommitted (ABORTED) newer observation must be ignored
    [void](New-RqTestBenefitObservationCommit -Store $store -RunId 'run-b-aborted' -BusinessId $bizFastBenefit -RowNumber 2 -Row $rows[0] -ObservedAt '2026-10-25T00:00:00Z' -Revision $revision -BenefitState 'ENDED' -ReviewClass 'RED' -ChangeCandidates @('BENEFIT_CHANGE_SUSPECTED') -CommitStatus 'ABORTED')

    # 2) DOMAIN_REVIEW cases
    [void](New-RqTestBenefitObservationCommit -Store $store -RunId 'run-b-human' -BusinessId $bizHumanChange -RowNumber 3 -Row $rows[1] -ObservedAt '2026-10-21T02:00:00Z' -Revision $revision -BenefitState 'ACTIVE' -ReviewClass 'GREEN' -ChangeCandidates @('BENEFIT_CHANGE_SUSPECTED'))
    [void](New-RqTestBenefitObservationCommit -Store $store -RunId 'run-b-yellow' -BusinessId $bizYellow -RowNumber 4 -Row $rows[2] -ObservedAt '2026-10-21T03:00:00Z' -Revision $revision -BenefitState 'NEEDS_VERIFICATION' -ReviewClass 'YELLOW' -ChangeCandidates @())
    [void](New-RqTestBenefitObservationCommit -Store $store -RunId 'run-b-red' -BusinessId $bizRedEnded -RowNumber 5 -Row $rows[3] -ObservedAt '2026-10-21T04:00:00Z' -Revision $revision -BenefitState 'ENDED' -ReviewClass 'RED' -ChangeCandidates @())

    # 3) DIAGNOSTIC_HOLD cases
    [void](New-RqTestBenefitObservationCommit -Store $store -RunId 'run-b-opfail' -BusinessId $bizOpFailure -RowNumber 6 -Row $rows[4] -ObservedAt '2026-10-21T05:00:00Z' -Revision $revision -BenefitState 'NEEDS_VERIFICATION' -ReviewClass 'YELLOW' -ExtractionStatus 'FAILED' -ChangeCandidates @('OPERATIONAL_FAILURE'))
    [void](New-RqTestBenefitObservationCommit -Store $store -RunId 'run-b-nocomp' -BusinessId $bizNoComparison -RowNumber 7 -Row $rows[5] -ObservedAt '2026-10-21T06:00:00Z' -Revision $revision -BenefitState 'ACTIVE' -ReviewClass 'GREEN' -NoComparison)

    $bareObs = New-HistoryObservation -ObservationId 'obs-bare-no-proj' -RunId 'run-b-bare' -BusinessId $bizBare -Domain 'BENEFIT' -ObservedAt '2026-10-21T07:00:00Z' -OperationalStatus 'COMPLETE' -Comparable $true -InputFingerprint ('1' * 64) -EvidenceFingerprint ('2' * 64) -SemanticFingerprint ('3' * 64) -ExecutionFingerprint ('4' * 64) -ArtifactReferences @()
    Write-RqTestJsonFile -Path (Get-HistoryObservationPath -Store $store -ObservationId $bareObs.ObservationId) -Value $bareObs
    $bareCmp = New-ObservationComparison -ComparisonId 'cmp-bare-no-proj' -RunId 'run-b-bare' -BusinessId $bizBare -Domain 'BENEFIT' -CurrentObservationId $bareObs.ObservationId -ComparisonStatus 'COMPLETE' -ChangeCandidates @('BASELINE_ESTABLISHED')
    Write-RqTestJsonFile -Path (Join-Path $store.ComparisonsRoot 'cmp-bare-no-proj.json') -Value $bareCmp
    $bareManifest = New-HistoryRunManifest -RunId 'run-b-bare' -StartedAt '2026-10-21T07:00:00Z' -CompletedAt '2026-10-21T07:00:00Z' -RepositoryRevision $revision -RequestedBusinessIds @($bizBare) -CompletedBusinessIds @($bizBare) -ExecutionStatus 'COMPLETE' -RunCommitStatus 'COMMITTED'
    Write-RqTestJsonFile -Path (Get-HistoryRunManifestPath -Store $store -RunId 'run-b-bare') -Value $bareManifest

    $orphanRow = New-RqTestBusinessRow -BusinessId $bizOrphanCanonical -Name '삭제된업소'
    [void](New-RqTestBenefitObservationCommit -Store $store -RunId 'run-b-orphan' -BusinessId $bizOrphanCanonical -RowNumber 99 -Row $orphanRow -ObservedAt '2026-10-21T08:00:00Z' -Revision $revision -BenefitState 'ACTIVE' -ReviewClass 'GREEN' -ChangeCandidates @())

    # 4) LOCATION fast + domain cases (with non-Z offset to verify lossless ObservedAt)
    [void](New-RqTestLocationObservationCommit -Store $store -RunId 'run-loc-fast' -BusinessId $bizFastBenefit -RowNumber 2 -Row $rows[0] -ObservedAt '2026-10-22T01:00:00+09:00' -Revision $revision -Classification 'GREEN' -ChangeCandidates @('BASELINE_ESTABLISHED'))
    [void](New-RqTestLocationObservationCommit -Store $store -RunId 'run-loc-yellow' -BusinessId $bizYellow -RowNumber 4 -Row $rows[2] -ObservedAt '2026-10-22T02:00:00Z' -Revision $revision -Classification 'YELLOW' -ChangeCandidates @())

    # External path enforcement
    $repoRoot = (Get-Phase5BenefitRepositoryRoots)[0]
    Assert-RqTestThrowsMatching { Export-Phase5ReviewQueue -HistoryRoot $historyRoot -CanonicalCsvPath $canonicalPath -OutputDirectory (Join-Path $repoRoot 'tmp/rq-forbidden') } 'P5_OUTPUT_MUST_BE_OUTSIDE_REPOSITORY' 'Repo output path must fail closed'
    Assert-RqTestThrowsMatching { Export-Phase5ReviewQueue -HistoryRoot $historyRoot -CanonicalCsvPath $canonicalPath -OutputDirectory $historyRoot } 'RQ_OUTPUT_OVERLAPS_HISTORY_STORE' 'History store root output must fail'
    Assert-RqTestThrowsMatching { Export-Phase5ReviewQueue -HistoryRoot $historyRoot -CanonicalCsvPath $canonicalPath -OutputDirectory (Join-Path $historyRoot 'exports') } 'RQ_OUTPUT_OVERLAPS_HISTORY_STORE' 'History store child output must fail'
    Assert-RqTestThrowsMatching { Export-Phase5ReviewQueue -HistoryRoot $historyRoot -CanonicalCsvPath $canonicalPath -OutputDirectory $tempRoot } 'RQ_OUTPUT_OVERLAPS_HISTORY_STORE' 'Parent of History store must fail'

    # Read-only guarantee check + Latest / IncludeSuperseded / Domain filtering exports
    $beforeFiles = Get-RqTestStoreFileInventory -Store $store
    $script:origRqLayout = ${function:New-HistoryStoreLayout}
    $script:origRqRebuild = ${function:Rebuild-HistoryIndexes}
    function New-HistoryStoreLayout { throw 'Export must not create History store layout' }
    function Rebuild-HistoryIndexes { throw 'Export must not rebuild History indexes' }
    try {
        $latestResult = Export-Phase5ReviewQueue -HistoryRoot $historyRoot -CanonicalCsvPath $canonicalPath -OutputDirectory $outputLatestDir
        $allResult = Export-Phase5ReviewQueue -HistoryRoot $historyRoot -CanonicalCsvPath $canonicalPath -OutputDirectory $outputAllDir -IncludeSuperseded
        $benefitOnly = Export-Phase5ReviewQueue -Store $store -CanonicalCsvPath $canonicalPath -OutputDirectory $outputBenefitDir -Domain 'BENEFIT'
    } finally {
        Set-Item -Path function:New-HistoryStoreLayout -Value $script:origRqLayout
        Set-Item -Path function:Rebuild-HistoryIndexes -Value $script:origRqRebuild
    }
    $afterFiles = Get-RqTestStoreFileInventory -Store $store
    Assert-RqTestEqual ($afterFiles -join "`n") ($beforeFiles -join "`n") 'History Store must remain byte-for-byte unchanged'

    # Latest summary assertions (11 committed observations -> 1 superseded -> 10 latest items)
    Assert-RqTestEqual $latestResult.Summary.CommittedRunCount 11 '11 COMMITTED runs counted (ABORTED excluded)'
    Assert-RqTestEqual $latestResult.Summary.SupersededExcludedCount 1 'One older observation superseded'
    Assert-RqTestEqual $latestResult.Summary.ExportedItemCount 10 'Latest export count'
    Assert-RqTestEqual $latestResult.Summary.FastReviewCount 2 'FAST_REVIEW has 1 BENEFIT + 1 LOCATION'
    Assert-RqTestEqual $latestResult.Summary.DomainReviewCount 4 'DOMAIN_REVIEW count'
    Assert-RqTestEqual $latestResult.Summary.DiagnosticHoldCount 4 'DIAGNOSTIC_HOLD count'
    Assert-RqTestEqual $latestResult.Summary.BenefitItemCount 8 '8 latest BENEFIT items'
    Assert-RqTestEqual $latestResult.Summary.LocationItemCount 2 '2 latest LOCATION items'
    Assert-RqTestEqual $latestResult.Summary.ProductionAction 'NONE' 'Summary ProductionAction must stay NONE'
    Assert-RqTestTrue ([bool]$latestResult.Summary.ApprovalRequired) 'ApprovalRequired must stay true'

    Assert-RqTestEqual $allResult.Summary.SupersededExcludedCount 0 'IncludeSuperseded excludes 0'
    Assert-RqTestEqual $allResult.Summary.ExportedItemCount 11 'IncludeSuperseded exports all 11 committed observations'
    Assert-RqTestEqual $benefitOnly.Summary.ExportedItemCount 8 'Domain filter BENEFIT returns 8 items'
    Assert-RqTestEqual $benefitOnly.Summary.LocationItemCount 0 'Domain filter BENEFIT excludes LOCATION'

    $byBizDomain = @{}
    foreach ($it in $latestResult.Items) {
        Assert-RqTestEqual $it.ProductionAction 'NONE' "Item ProductionAction must be NONE ($($it.BusinessId))"
        Assert-RqTestTrue ([bool]$it.ApprovalRequired) "Item ApprovalRequired must be true ($($it.BusinessId))"
        $byBizDomain["$($it.BusinessId)|$($it.Domain)"] = $it
    }

    $fastB = $byBizDomain["$bizFastBenefit|BENEFIT"]
    Assert-RqTestEqual $fastB.OperatorBucket 'FAST_REVIEW' 'Latest unchanged GREEN ACTIVE BENEFIT -> FAST_REVIEW'
    Assert-RqTestEqual $fastB.CurrentObservationId $newObs.ObservationId 'Latest observation selected over older run'
    Assert-RqTestEqual $fastB.ObservedAt '2026-10-21T01:00:00Z' 'ISO UTC timestamp preserved'
    Assert-RqTestEqual $fastB.SourceUrls[0] 'https://city.example.go.kr/benefit' 'Evidence projection SourceUrl hydrated'
    Assert-RqTestEqual $fastB.SourceFormats[0] 'HTML' 'Evidence projection SourceFormat hydrated'

    $fastL = $byBizDomain["$bizFastBenefit|LOCATION"]
    Assert-RqTestEqual $fastL.OperatorBucket 'FAST_REVIEW' 'Latest GREEN LOCATION -> FAST_REVIEW'
    Assert-RqTestEqual $fastL.ObservedAt '2026-10-22T01:00:00+09:00' 'ISO +09:00 offset preserved losslessly'
    Assert-RqTestEqual $fastL.LocationClassification 'GREEN' 'Location semantic hydrated'

    Assert-RqTestEqual $byBizDomain["$bizHumanChange|BENEFIT"].OperatorBucket 'DOMAIN_REVIEW' 'HUMAN_DOMAIN_REVIEW even with GREEN -> DOMAIN_REVIEW'
    Assert-RqTestEqual $byBizDomain["$bizYellow|BENEFIT"].OperatorBucket 'DOMAIN_REVIEW' 'YELLOW NEEDS_VERIFICATION -> DOMAIN_REVIEW'
    Assert-RqTestEqual $byBizDomain["$bizRedEnded|BENEFIT"].OperatorBucket 'DOMAIN_REVIEW' 'RED ENDED -> DOMAIN_REVIEW'
    Assert-RqTestEqual $byBizDomain["$bizYellow|LOCATION"].OperatorBucket 'DOMAIN_REVIEW' 'YELLOW LOCATION -> DOMAIN_REVIEW'
    Assert-RqTestEqual $byBizDomain["$bizOpFailure|BENEFIT"].OperatorBucket 'DIAGNOSTIC_HOLD' 'OPERATIONAL_FAILURE -> DIAGNOSTIC_HOLD'
    Assert-RqTestEqual $byBizDomain["$bizNoComparison|BENEFIT"].OperatorBucket 'DIAGNOSTIC_HOLD' 'AUDIT_VERIFICATION missing comparison -> DIAGNOSTIC_HOLD'
    Assert-RqTestEqual $byBizDomain["$bizBare|BENEFIT"].OperatorBucket 'DIAGNOSTIC_HOLD' 'Bare observation missing projection -> DIAGNOSTIC_HOLD'
    Assert-RqTestTrue (@($byBizDomain["$bizBare|BENEFIT"].DiagnosticReasons) -ccontains 'SEMANTIC_PROJECTION_UNAVAILABLE') 'Missing projection reason recorded'
    Assert-RqTestEqual $byBizDomain["$bizOrphanCanonical|BENEFIT"].OperatorBucket 'DIAGNOSTIC_HOLD' 'Missing canonical row -> DIAGNOSTIC_HOLD'
    Assert-RqTestTrue (@($byBizDomain["$bizOrphanCanonical|BENEFIT"].DiagnosticReasons) -ccontains 'CANONICAL_ROW_MISSING') 'Missing canonical reason recorded'

    # Output files hygiene (UTF-8 no BOM, valid JSON/CSV, ZERO RAW/SCOPED leakage)
    $summaryBytes = [IO.File]::ReadAllBytes($latestResult.SummaryJsonPath)
    Assert-RqTestTrue (-not ($summaryBytes.Length -ge 3 -and $summaryBytes[0] -eq 0xEF -and $summaryBytes[1] -eq 0xBB -and $summaryBytes[2] -eq 0xBF)) 'Summary JSON must not contain UTF-8 BOM'
    $summaryRaw = [Text.Encoding]::UTF8.GetString($summaryBytes)
    $csvRaw = [IO.File]::ReadAllText($latestResult.ItemsCsvPath, [Text.Encoding]::UTF8)
    Assert-RqTestTrue (-not $summaryRaw.Contains('SENTINEL_RAW_HTML_SECRET_NEVER_EXPORT')) 'RAW HTML sentinel must never appear in JSON'
    Assert-RqTestTrue (-not $summaryRaw.Contains('SENTINEL_SCOPED_HTML_SECRET')) 'SCOPED HTML sentinel must never appear in JSON'
    Assert-RqTestTrue (-not $csvRaw.Contains('SENTINEL_RAW_HTML_SECRET_NEVER_EXPORT')) 'RAW HTML sentinel must never appear in CSV'
    Assert-RqTestTrue (-not $csvRaw.Contains('SENTINEL_SCOPED_HTML_SECRET')) 'SCOPED HTML sentinel must never appear in CSV'

    $parsedSummary = $summaryRaw | ConvertFrom-Json
    Assert-RqTestEqual $parsedSummary.ContractType 'Phase5ReviewQueueExport' 'JSON ContractType'
    Assert-RqTestEqual ([int]$parsedSummary.ContractVersion) 1 'JSON ContractVersion'
    Assert-RqTestEqual @($parsedSummary.Items).Count 10 'Parsed JSON item count'
    $parsedCsv = @(Import-Csv -LiteralPath $latestResult.ItemsCsvPath -Encoding utf8)
    Assert-RqTestEqual $parsedCsv.Count 10 'Parsed CSV row count'

    # CLI -File invocation check using current PowerShell binary
    $pwshBin = (Get-Process -Id $PID).Path
    $scriptFile = Join-Path $PSScriptRoot 'export-phase5-review-queue.ps1'
    $null | & $pwshBin -NoProfile -NonInteractive -OutputFormat Text -File $scriptFile -HistoryRoot $historyRoot -CanonicalCsvPath $canonicalPath -OutputDirectory $outputCliDir | Out-Null
    Assert-RqTestEqual $LASTEXITCODE 0 'CLI invocation exits 0'
    Assert-RqTestTrue (Test-Path -LiteralPath (Join-Path $outputCliDir 'review-queue-summary.json') -PathType Leaf) 'CLI writes JSON'
    Assert-RqTestTrue (Test-Path -LiteralPath (Join-Path $outputCliDir 'review-queue-items.csv') -PathType Leaf) 'CLI writes CSV'

    # Tampered evidence projection hash must fail closed
    $evidenceRef = @($newObs.ArtifactReferences | Where-Object { [string]$_.Kind -ceq 'BENEFIT_EVIDENCE_PROJECTION' })[0]
    $evidencePath = Assert-HistoryStorePathWithinRoot -Store $store -Path (Join-Path $store.Root ([string]$evidenceRef.RelativePath))
    [IO.File]::WriteAllText($evidencePath, '{"tampered":true}', [Text.UTF8Encoding]::new($false))
    Assert-RqTestThrowsMatching { Export-Phase5ReviewQueue -HistoryRoot $historyRoot -CanonicalCsvPath $canonicalPath -OutputDirectory (Join-Path $tempRoot 'export-tamper') } 'hash mismatch' 'Tampered projection artifact must fail closed'

    Write-Host 'PASS: Phase 5 review queue summary exporter'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

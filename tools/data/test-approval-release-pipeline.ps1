Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'validate-benefit-release-approvals.ps1')
. (Join-Path $PSScriptRoot 'build-release-benefit-seed-manifest.ps1')
. (Join-Path $PSScriptRoot 'invoke-phase2-benefit-shadow-mode.ps1')
. (Join-Path $PSScriptRoot 'lib/identity/normalize-business.ps1')
. (Join-Path $PSScriptRoot 'lib/history/compare-location-history.ps1')

function Assert-ApvTestEqual {
    param([AllowNull()]$Actual, [AllowNull()]$Expected, [Parameter(Mandatory)][string]$Message)
    if ($Actual -cne $Expected) {
        throw "$Message (expected: $Expected, actual: $Actual)"
    }
}

function Assert-ApvTestTrue {
    param([bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

function Assert-ApvTestThrowsMatching {
    param([scriptblock]$Action, [string]$Pattern, [string]$Message)
    try {
        & $Action | Out-Null
    } catch {
        if ($_.Exception.Message -match $Pattern) { return }
        throw "$Message (wrong exception: $($_.Exception.Message))"
    }
    throw "$Message (did not throw)"
}

function Write-ApvTestJsonFile {
    param([string]$Path, $Value)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        [void][IO.Directory]::CreateDirectory($parent)
    }
    $text = $Value | ConvertTo-Json -Depth 20 -Compress
    [IO.File]::WriteAllText($Path, $text, [Text.UTF8Encoding]::new($false))
}

function Write-ApvTestLedger {
    param([string]$Path, [object[]]$Records)
    $ledger = [pscustomobject][ordered]@{
        ContractType = 'BenefitReleaseApprovalLedger'
        ContractVersion = 1
        Records = @($Records)
    }
    Write-ApvTestJsonFile -Path $Path -Value $ledger
}

function New-ApvTestRow {
    param(
        [string]$BusinessId,
        [string]$Name,
        [string]$Address,
        [string]$Lat = '37.7851',
        [string]$Lon = '127.0457',
        [string]$CoordStatus = '확인 완료',
        [string]$Benefit = '10% 할인',
        [string]$BenefitStatus = '이용 가능'
    )
    return [pscustomobject][ordered]@{
        businessId = $BusinessId
        업종명 = '음식'
        업소명 = $Name
        시도 = '경기도'
        시군구 = '양주시'
        소재지도로명주소 = $Address
        소재지지번주소 = ''
        위도 = $Lat
        경도 = $Lon
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
        혜택상태 = $BenefitStatus
        수집자 = 'test'
        비고 = ''
    }
}

function Commit-ApvTestBenefitObservation {
    param(
        $Store,
        [string]$RunId,
        [string]$BusinessId,
        [int]$RowNumber,
        [object]$Row,
        [string]$Revision,
        [string]$BenefitState = 'ACTIVE',
        [string]$ReviewClass = 'GREEN',
        [string]$ExtractionStatus = 'COMPLETE',
        [string]$CommitStatus = 'COMMITTED'
    )
    $business = ConvertTo-NormalizedBusiness -Row $Row -SourceRowNumber $RowNumber
    $benefit = ConvertTo-Phase2CanonicalBenefitRecord -Row $Row -SourceRowNumber $RowNumber
    $claimVal = [string]$Row.할인정보
    $claimRes = if ($BenefitState -ceq 'ENDED') { 'ENDED' } else { 'CONFIRMED' }
    $validated = New-ValidatedBenefitClaim -ClaimType 'BENEFIT_DESCRIPTION' -Value $claimVal -ValidationStatus 'VALIDATED' -EvidenceText $claimVal -EvidenceReference 'TABLE_ROW:1:CELL:2' -SourceUrl 'https://city.example.go.kr/benefit'
    $claim = New-BenefitClaimVerification -ClaimType 'BENEFIT_DESCRIPTION' -CanonicalValue $claimVal -EvidenceValue $claimVal -Result $claimRes -ValidatedClaim $validated -ReasonCodes @()
    $result = New-BenefitVerificationResult -SourceRowNumber $RowNumber -BusinessIdentity $business -BenefitState $BenefitState -ReviewClass $ReviewClass -ReasonCodes @() -ClaimResults @($claim) -Evidence @() -Warnings @() -ProductionAction 'NONE'
    $observedAt = '2026-10-20T09:00:00+09:00'
    $diag = [pscustomobject]@{
        Url = 'https://city.example.go.kr/benefit'
        SourceFormat = 'HTML'
        FetchStatus = 'COMPLETE'
        ContentHash = ('b' * 64)
        ObservedAt = $observedAt
        AdapterId = 'HTML_GENERIC'
        AdapterVersion = 1
        AdapterStatus = 'COMPLETE'
        LocationOperationalStatus = 'COMPLETE'
        LocationStatus = 'LOCATED'
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
        -ObservedAt $observedAt `
        -RepositoryRevision $Revision `
        -Benefit $benefit `
        -BusinessIdentity $business `
        -CanonicalPhone '031-000-0010' `
        -Result $result `
        -EvidenceDiagnostics @($diag) `
        -OperationalStatus ([pscustomobject]@{ DiscoveryStatus = 'COMPLETE'; ExtractionStatus = $ExtractionStatus })
    foreach ($art in @($pkg.PreparedArtifacts)) {
        [void](Write-HistoryArtifact -Store $Store -ContentHash $art.ContentHash -Extension $art.Extension -Text $art.Text)
    }
    $obs = $pkg.Observation
    Write-ApvTestJsonFile -Path (Get-HistoryObservationPath -Store $Store -ObservationId $obs.ObservationId) -Value $obs
    $cmpId = 'cmp-' + (Get-HistorySha256 -Text ($RunId + '|' + $obs.ObservationId)).Substring(0, 32)
    $cmp = New-ObservationComparison `
        -ComparisonId $cmpId `
        -RunId $RunId `
        -BusinessId $BusinessId `
        -Domain 'BENEFIT' `
        -CurrentObservationId $obs.ObservationId `
        -ComparisonStatus $(if ($ExtractionStatus -ceq 'COMPLETE') { 'COMPLETE' } else { 'UNAVAILABLE' }) `
        -ChangeCandidates $(if ($ExtractionStatus -ceq 'COMPLETE') { @('BASELINE_ESTABLISHED') } else { @('OPERATIONAL_FAILURE') })
    Write-ApvTestJsonFile -Path (Join-Path $Store.ComparisonsRoot ($cmpId + '.json')) -Value $cmp

    $execStatus = if ($ExtractionStatus -ceq 'COMPLETE') { 'COMPLETE' } else { 'PARTIAL' }
    $manifestParams = @{
        RunId = $RunId
        StartedAt = $observedAt
        CompletedAt = $(if ($CommitStatus -ceq 'COMMITTED') { $observedAt } else { '' })
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
    Write-ApvTestJsonFile -Path (Get-HistoryRunManifestPath -Store $Store -RunId $RunId) -Value $manifest
    return [pscustomobject]@{ Observation = $obs; ReviewKey = $cmpId; RunId = $RunId }
}

function Commit-ApvTestLocationObservation {
    param(
        $Store,
        [string]$RunId,
        [string]$BusinessId,
        [int]$RowNumber,
        [object]$Row,
        [string]$Revision,
        [switch]$Failed
    )
    $business = ConvertTo-NormalizedBusiness -Row $Row -SourceRowNumber $RowNumber
    $discovery = New-PoiDiscoveryEvidence -StrategyCode 'NAME_FULL_ADDRESS' -Query '테스트' -QueryOrder 1 -ResultPosition 1 -ResultCount 1
    $cand = New-PoiCandidate -CandidateKey 'naver-1' -Provider 'NAVER_API_HUB_LOCAL' -OriginalName ([string]$Row.업소명) -NormalizedName (([string]$Row.업소명) -replace '\s', '') -RoadAddress ([string]$Row.소재지도로명주소) -LotAddress '' -Latitude 37.7851 -Longitude 127.0457 -Phone '031-000-0010' -Category '음식점' -ProviderLink 'https://map.example/1' -DiscoveredBy @($discovery)
    $attempt = New-PoiQueryAttempt -StrategyCode 'NAME_FULL_ADDRESS' -Query '테스트' -QueryOrder 1 -Status 'SUCCESS' -ResultCount 1
    $batchParams = @{
        SourceRowNumber = $RowNumber
        Status = $(if ($Failed) { 'FAILED' } else { 'COMPLETE' })
        QueryAttempts = @($attempt)
    }
    if (-not $Failed) { $batchParams.Candidates = @($cand) }
    $batch = New-PoiDiscoveryBatch @batchParams

    $matchParams = @{
        SourceRowNumber = $RowNumber
        EvaluationStatus = $(if ($Failed) { 'INCOMPLETE' } else { 'COMPLETE' })
        Classification = $(if ($Failed) { 'YELLOW' } else { 'GREEN' })
        SelectedCandidate = $(if ($Failed) { $null } else { $cand })
        ReasonCodes = $(if ($Failed) { @('DISCOVERY_FAILED') } else { @('SINGLE_STRONG_CANDIDATE') })
        EvaluatedCandidateCount = $(if ($Failed) { 0 } else { 1 })
        SurvivingCandidateCount = $(if ($Failed) { 0 } else { 1 })
        ProductionAction = 'NONE'
    }
    if (-not $Failed) { $matchParams.RankedCandidateKeys = @('naver-1') }
    $result = New-PoiMatchResult @matchParams
    $observedAt = '2026-10-20T09:05:00+09:00'
    $pkg = New-LocationHistoryObservationPackage -Store $Store -RunId $RunId -BusinessId $BusinessId -ObservedAt $observedAt -RepositoryRevision $Revision -Business $business -DiscoveryBatch $batch -Result $result
    foreach ($art in @($pkg.PreparedArtifacts)) {
        [void](Write-HistoryArtifact -Store $Store -ContentHash $art.ContentHash -Extension $art.Extension -Text $art.Text)
    }
    $obs = $pkg.Observation
    Write-ApvTestJsonFile -Path (Get-HistoryObservationPath -Store $Store -ObservationId $obs.ObservationId) -Value $obs
    $cmpId = 'cmp-' + (Get-HistorySha256 -Text ($RunId + '|' + $obs.ObservationId)).Substring(0, 32)
    $cmp = New-ObservationComparison -ComparisonId $cmpId -RunId $RunId -BusinessId $BusinessId -Domain 'LOCATION' -CurrentObservationId $obs.ObservationId -ComparisonStatus 'COMPLETE' -ChangeCandidates @('BASELINE_ESTABLISHED')
    Write-ApvTestJsonFile -Path (Join-Path $Store.ComparisonsRoot ($cmpId + '.json')) -Value $cmp
    $locManifestParams = @{
        RunId = $RunId
        StartedAt = $observedAt
        CompletedAt = $observedAt
        RepositoryRevision = $Revision
        RequestedBusinessIds = @($BusinessId)
        ExecutionStatus = $(if ($Failed) { 'FAILED' } else { 'COMPLETE' })
        RunCommitStatus = 'COMMITTED'
    }
    if ($Failed) {
        $locManifestParams.FailedBusinessIds = @($BusinessId)
    } else {
        $locManifestParams.CompletedBusinessIds = @($BusinessId)
    }
    $manifest = New-HistoryRunManifest @locManifestParams
    Write-ApvTestJsonFile -Path (Get-HistoryRunManifestPath -Store $Store -RunId $RunId) -Value $manifest
    return $obs
}

function New-ApvRecordTemplate {
    param(
        [string]$BusinessId,
        $RowNumber = 2,
        $CommitInfo,
        [string]$BenefitDecision = 'APPROVE_ACTIVE',
        [string]$CoordinateDecision = 'SUPPRESS_PIN',
        [string]$Rationale = '',
        [string]$VerifiedSourceUrl = 'https://city.example.go.kr/benefit',
        [string]$VerifiedOn = '2026-10-20',
        [string]$ApprovedBy = 'reviewer-1',
        [string]$ApprovedAt = '2026-10-21T10:00:00+09:00',
        [string]$LocationObservationId = $null
    )
    $rec = [ordered]@{
        businessId = $BusinessId
        canonicalRowNumber = $RowNumber
        reviewKey = $CommitInfo.ReviewKey
        targetRunId = $CommitInfo.RunId
        observationId = $CommitInfo.Observation.ObservationId
        benefitDecision = $BenefitDecision
        coordinateDecision = $CoordinateDecision
        verifiedSourceUrl = $VerifiedSourceUrl
        verifiedOn = $VerifiedOn
        approvedBy = $ApprovedBy
        approvedAt = $ApprovedAt
        rationale = $Rationale
    }
    if ($LocationObservationId) {
        $rec.locationObservationId = $LocationObservationId
    }
    return [pscustomobject]$rec
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('milimap-apv-test-' + [guid]::NewGuid().ToString('N'))
$revision = 'b' * 40
try {
    [void][IO.Directory]::CreateDirectory($tempRoot)

    # 1. Cross-platform SHA-256-LF-UTF8 invariance tests (CRLF vs LF vs BOM)
    $sampleLf = "{`"a`":1}`n{`"b`":2}`n"
    $sampleCrlf = "{`"a`":1}`r`n{`"b`":2}`r`n"
    $sampleCr = "{`"a`":1}`r{`"b`":2}`r"
    $hashLf = Get-ReleaseNormalizedLfSha256 -Text $sampleLf
    Assert-ApvTestEqual (Get-ReleaseNormalizedLfSha256 -Text $sampleCrlf) $hashLf 'CRLF text hash matches LF'
    Assert-ApvTestEqual (Get-ReleaseNormalizedLfSha256 -Text $sampleCr) $hashLf 'CR text hash matches LF'
    Assert-ApvTestEqual (Get-ReleaseNormalizedLfSha256 -Text (([char]0xFEFF) + $sampleCrlf)) $hashLf 'UTF-8 BOM + CRLF matches LF'

    $bomFile = Join-Path $tempRoot 'bom-crlf.json'
    $lfFile = Join-Path $tempRoot 'no-bom-lf.json'
    [IO.File]::WriteAllBytes($bomFile, [byte[]](0xEF, 0xBB, 0xBF) + [Text.Encoding]::UTF8.GetBytes($sampleCrlf))
    [IO.File]::WriteAllBytes($lfFile, [Text.Encoding]::UTF8.GetBytes($sampleLf))
    Assert-ApvTestEqual (Get-ReleaseFileNormalizedLfSha256 -Path $bomFile) (Get-ReleaseFileNormalizedLfSha256 -Path $lfFile) 'File BOM/CRLF vs no-BOM/LF hashes match'

    # 2. Approval Ledger Validator tests
    $historyRoot = Join-Path $tempRoot 'history'
    $store = New-HistoryStoreLayout -Root $historyRoot
    $canonicalPath = Join-Path $tempRoot 'canonical.csv'
    $coordReviewPath = Join-Path $tempRoot 'coord-review.csv'
    $ledgerPath = Join-Path $tempRoot 'approval-ledger.json'

    $biz1 = 'biz-11111111111111111111111111111111'
    $biz2 = 'biz-22222222222222222222222222222222'
    $biz3 = 'biz-33333333333333333333333333333333'
    $biz4 = 'biz-44444444444444444444444444444444'
    $biz5 = 'biz-55555555555555555555555555555555'

    $row1 = New-ApvTestRow -BusinessId $biz1 -Name '핀유지식당' -Address '경기도 양주시 평화로 1' -CoordStatus '확인 완료'
    $row2 = New-ApvTestRow -BusinessId $biz2 -Name '핀보류식당' -Address '경기도 파주시 중앙로 2' -Lat '' -Lon '' -CoordStatus '재확인 필요'
    $row3 = New-ApvTestRow -BusinessId $biz3 -Name '보류식당' -Address '경기도 동두천시 평화로 3' -CoordStatus '미확인' -Lat '' -Lon '' -BenefitStatus '확인 필요'
    $row4 = New-ApvTestRow -BusinessId $biz4 -Name '종료식당' -Address '서울특별시 용산구 녹사평대로 4' -CoordStatus '확인 완료' -BenefitStatus '종료'
    $row5 = New-ApvTestRow -BusinessId $biz5 -Name '실패식당' -Address '서울특별시 마포구 양화로 5' -CoordStatus '확인 완료'

    @($row1, $row2, $row3, $row4, $row5) | Export-Csv -LiteralPath $canonicalPath -NoTypeInformation -Encoding utf8
    @(
        [pscustomobject][ordered]@{ 정본CSV행번호 = 2; 업소명 = '핀유지식당'; 소재지도로명주소 = '경기도 양주시 평화로 1'; 감사판정 = '확인 후보' },
        [pscustomobject][ordered]@{ 정본CSV행번호 = 5; 업소명 = '종료식당'; 소재지도로명주소 = '서울특별시 용산구 녹사평대로 4'; 감사판정 = '제외' }
    ) | Export-Csv -LiteralPath $coordReviewPath -NoTypeInformation -Encoding utf8

    $c1 = Commit-ApvTestBenefitObservation -Store $store -RunId 'run-c1' -BusinessId $biz1 -RowNumber 2 -Row $row1 -Revision $revision -BenefitState 'ACTIVE' -ReviewClass 'GREEN'
    $loc1 = Commit-ApvTestLocationObservation -Store $store -RunId 'run-l1' -BusinessId $biz1 -RowNumber 2 -Row $row1 -Revision $revision
    $loc1Failed = Commit-ApvTestLocationObservation -Store $store -RunId 'run-l1f' -BusinessId $biz1 -RowNumber 2 -Row $row1 -Revision $revision -Failed
    $c2 = Commit-ApvTestBenefitObservation -Store $store -RunId 'run-c2' -BusinessId $biz2 -RowNumber 3 -Row $row2 -Revision $revision -BenefitState 'ACTIVE' -ReviewClass 'YELLOW'
    $c3 = Commit-ApvTestBenefitObservation -Store $store -RunId 'run-c3' -BusinessId $biz3 -RowNumber 4 -Row $row3 -Revision $revision -BenefitState 'NEEDS_VERIFICATION' -ReviewClass 'YELLOW'
    $c4 = Commit-ApvTestBenefitObservation -Store $store -RunId 'run-c4' -BusinessId $biz4 -RowNumber 5 -Row $row4 -Revision $revision -BenefitState 'ENDED' -ReviewClass 'RED'
    $c5Partial = Commit-ApvTestBenefitObservation -Store $store -RunId 'run-c5' -BusinessId $biz5 -RowNumber 6 -Row $row5 -Revision $revision -ExtractionStatus 'PARTIAL'
    $c1Aborted = Commit-ApvTestBenefitObservation -Store $store -RunId 'run-c1-abort' -BusinessId $biz1 -RowNumber 2 -Row $row1 -Revision $revision -CommitStatus 'ABORTED'

    $validRecords = @(
        (New-ApvRecordTemplate -BusinessId $biz1 -RowNumber 2 -CommitInfo $c1 -BenefitDecision 'APPROVE_ACTIVE' -CoordinateDecision 'KEEP_PIN' -LocationObservationId $loc1.ObservationId),
        (New-ApvRecordTemplate -BusinessId $biz2 -RowNumber 3 -CommitInfo $c2 -BenefitDecision 'APPROVE_ACTIVE' -CoordinateDecision 'SUPPRESS_PIN' -Rationale '공식 공지 확인 후 수동 승인' -VerifiedSourceUrl 'https://www.paju.go.kr/a | https://www.paju.go.kr/b'),
        (New-ApvRecordTemplate -BusinessId $biz3 -RowNumber 4 -CommitInfo $c3 -BenefitDecision 'HOLD_NEEDS_VERIFICATION' -CoordinateDecision 'SUPPRESS_PIN'),
        (New-ApvRecordTemplate -BusinessId $biz4 -RowNumber 5 -CommitInfo $c4 -BenefitDecision 'APPROVE_ENDED' -CoordinateDecision 'SUPPRESS_PIN' -Rationale '공식 종료 공고 확인')
    )
    Write-ApvTestLedger -Path $ledgerPath -Records $validRecords

    $script:origApvLayout = ${function:New-HistoryStoreLayout}
    $script:origApvRebuild = ${function:Rebuild-HistoryIndexes}
    function New-HistoryStoreLayout { throw 'Approval validator must not create store layout' }
    function Rebuild-HistoryIndexes { throw 'Approval validator must not rebuild indexes' }
    try {
        $valRes = Test-BenefitReleaseApprovalLedger -HistoryRoot $historyRoot -CanonicalCsvPath $canonicalPath -CoordinateReviewCsvPath $coordReviewPath -ApprovalLedgerJsonPath $ledgerPath
    } finally {
        Set-Item -Path function:New-HistoryStoreLayout -Value $script:origApvLayout
        Set-Item -Path function:Rebuild-HistoryIndexes -Value $script:origApvRebuild
    }
    Assert-ApvTestEqual $valRes.ValidationStatus 'VALID' 'Valid ledger passes'
    Assert-ApvTestEqual $valRes.RecordCount 4 'RecordCount'
    Assert-ApvTestEqual $valRes.ApproveActiveCount 2 'ApproveActiveCount'
    Assert-ApvTestEqual $valRes.HoldCount 1 'HoldCount'
    Assert-ApvTestEqual $valRes.ApproveEndedCount 1 'ApproveEndedCount'
    Assert-ApvTestEqual $valRes.KeepPinCount 1 'KeepPinCount'
    Assert-ApvTestEqual $valRes.SuppressPinCount 3 'SuppressPinCount'
    Assert-ApvTestEqual $valRes.ProductionAction 'NONE' 'ProductionAction stays NONE'

    # CLI -File invocation check for validate-benefit-release-approvals.ps1
    $pwshBin = (Get-Process -Id $PID).Path
    $valScript = Join-Path $PSScriptRoot 'validate-benefit-release-approvals.ps1'
    $null | & $pwshBin -NoProfile -NonInteractive -OutputFormat Text -File $valScript -HistoryRoot $historyRoot -CanonicalCsvPath $canonicalPath -CoordinateReviewCsvPath $coordReviewPath -ApprovalLedgerJsonPath $ledgerPath | Out-Null
    Assert-ApvTestEqual $LASTEXITCODE 0 'Approval validator CLI exits 0'

    # Fail-closed rejection suite
    $badCases = @(
        @{ Name = 'duplicate businessId'; Pattern = 'duplicate businessId'; Records = @(
            (New-ApvRecordTemplate -BusinessId $biz1 -RowNumber 2 -CommitInfo $c1),
            (New-ApvRecordTemplate -BusinessId $biz1 -RowNumber 2 -CommitInfo $c1)
        )},
        @{ Name = 'unknown businessId'; Pattern = 'CANONICAL_BUSINESS_NOT_FOUND'; Records = @(
            (New-ApvRecordTemplate -BusinessId 'biz-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' -RowNumber 2 -CommitInfo $c1)
        )},
        @{ Name = 'row number mismatch'; Pattern = 'CANONICAL_ROW_NUMBER_MISMATCH'; Records = @(
            (New-ApvRecordTemplate -BusinessId $biz1 -RowNumber 99 -CommitInfo $c1)
        )},
        @{ Name = 'uncommitted observation'; Pattern = 'NOT_COMMITTED_BENEFIT'; Records = @(
            (New-ApvRecordTemplate -BusinessId $biz1 -RowNumber 2 -CommitInfo $c1Aborted)
        )},
        @{ Name = 'reviewKey mismatch'; Pattern = 'REVIEW_KEY_MISMATCH'; Records = @(& {
            $r = New-ApvRecordTemplate -BusinessId $biz1 -RowNumber 2 -CommitInfo $c1; $r.reviewKey = 'cmp-wrong'; $r
        })},
        @{ Name = 'targetRunId mismatch'; Pattern = 'RUN_MISMATCH'; Records = @(& {
            $r = New-ApvRecordTemplate -BusinessId $biz1 -RowNumber 2 -CommitInfo $c1; $r.targetRunId = 'run-wrong'; $r
        })},
        @{ Name = 'APPROVE_ACTIVE on PARTIAL'; Pattern = 'REQUIRES_COMPLETE_COMPARABLE'; Records = @(
            (New-ApvRecordTemplate -BusinessId $biz5 -RowNumber 6 -CommitInfo $c5Partial -BenefitDecision 'APPROVE_ACTIVE')
        )},
        @{ Name = 'APPROVE_ACTIVE on YELLOW without rationale'; Pattern = 'NON_GREEN_REQUIRES_RATIONALE'; Records = @(
            (New-ApvRecordTemplate -BusinessId $biz2 -RowNumber 3 -CommitInfo $c2 -BenefitDecision 'APPROVE_ACTIVE' -Rationale '')
        )},
        @{ Name = 'APPROVE_ENDED without rationale'; Pattern = 'APPROVE_ENDED requires non-blank rationale'; Records = @(
            (New-ApvRecordTemplate -BusinessId $biz4 -RowNumber 5 -CommitInfo $c4 -BenefitDecision 'APPROVE_ENDED' -CoordinateDecision 'SUPPRESS_PIN' -Rationale '')
        )},
        @{ Name = 'APPROVE_ENDED with KEEP_PIN'; Pattern = 'APPROVE_ENDED requires coordinateDecision SUPPRESS_PIN'; Records = @(
            (New-ApvRecordTemplate -BusinessId $biz4 -RowNumber 5 -CommitInfo $c4 -BenefitDecision 'APPROVE_ENDED' -CoordinateDecision 'KEEP_PIN' -Rationale '종료')
        )},
        @{ Name = 'KEEP_PIN without canonical confirmed'; Pattern = 'REQUIRES_CONFIRMED_CANONICAL_COORDINATE'; Records = @(
            (New-ApvRecordTemplate -BusinessId $biz2 -RowNumber 3 -CommitInfo $c2 -CoordinateDecision 'KEEP_PIN' -Rationale 'override')
        )},
        @{ Name = 'KEEP_PIN without strict coordinate review'; Pattern = 'REQUIRES_STRICT_COORDINATE_REVIEW'; Records = @(
            (New-ApvRecordTemplate -BusinessId $biz5 -RowNumber 6 -CommitInfo $c5Partial -BenefitDecision 'HOLD_NEEDS_VERIFICATION' -CoordinateDecision 'KEEP_PIN')
        )},
        @{ Name = 'automated approvedBy AUTO'; Pattern = 'invalid approvedBy'; Records = @(
            (New-ApvRecordTemplate -BusinessId $biz1 -RowNumber 2 -CommitInfo $c1 -ApprovedBy 'AUTO')
        )},
        @{ Name = 'automated approvedBy SYSTEM-bot'; Pattern = 'invalid approvedBy'; Records = @(
            (New-ApvRecordTemplate -BusinessId $biz1 -RowNumber 2 -CommitInfo $c1 -ApprovedBy 'SYSTEM-job')
        )},
        @{ Name = 'invalid calendar date'; Pattern = 'invalid verifiedOn'; Records = @(
            (New-ApvRecordTemplate -BusinessId $biz1 -RowNumber 2 -CommitInfo $c1 -VerifiedOn '2026-02-30')
        )},
        @{ Name = 'timestamp without offset'; Pattern = 'invalid approvedAt'; Records = @(
            (New-ApvRecordTemplate -BusinessId $biz1 -RowNumber 2 -CommitInfo $c1 -ApprovedAt '2026-10-21T10:00:00')
        )},
        @{ Name = 'invalid URL scheme'; Pattern = 'invalid verifiedSourceUrl'; Records = @(
            (New-ApvRecordTemplate -BusinessId $biz1 -RowNumber 2 -CommitInfo $c1 -VerifiedSourceUrl 'ftp://city.example.go.kr/a')
        )},
        @{ Name = 'non-comparable locationObservationId'; Pattern = 'LOCATION_OBSERVATION_NOT_COMPLETE_COMPARABLE'; Records = @(
            (New-ApvRecordTemplate -BusinessId $biz1 -RowNumber 2 -CommitInfo $c1 -LocationObservationId $loc1Failed.ObservationId)
        )},
        @{ Name = 'locationObservationId belonging to wrong business'; Pattern = 'LOCATION_OBSERVATION_BUSINESS_MISMATCH'; Records = @(
            (New-ApvRecordTemplate -BusinessId $biz2 -RowNumber 3 -CommitInfo $c2 -Rationale 'ok' -LocationObservationId $loc1.ObservationId)
        )}
    )

    foreach ($case in $badCases) {
        $badPath = Join-Path $tempRoot 'bad-ledger.json'
        Write-ApvTestLedger -Path $badPath -Records $case.Records
        Assert-ApvTestThrowsMatching {
            Test-BenefitReleaseApprovalLedger -HistoryRoot $historyRoot -CanonicalCsvPath $canonicalPath -CoordinateReviewCsvPath $coordReviewPath -ApprovalLedgerJsonPath $badPath
        } $case.Pattern "Ledger failure case [$($case.Name)] must fail closed"
    }

    # 3. Manifest Builder tests
    $seedPath = Join-Path $tempRoot 'seed.json'
    $manualPath = Join-Path $tempRoot 'manual.json'
    $manifestPath = Join-Path $tempRoot 'seed.manifest.json'

    $seedPayload = @(
        [pscustomobject][ordered]@{ id = 'seed-1'; status = 'ACTIVE'; latitude = 37.5; longitude = 127.0 },
        [pscustomobject][ordered]@{ id = 'seed-2'; status = 'ACTIVE'; latitude = $null; longitude = $null }
    ) | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText($seedPath, $seedPayload, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($manualPath, '{"items":[]}', [Text.UTF8Encoding]::new($false))

    $builtManifest = New-ReleaseBenefitSeedManifest `
        -SeedJsonPath $seedPath `
        -ManualSeedJsonPath $manualPath `
        -CanonicalCsvPath $canonicalPath `
        -SeedVersion 8 `
        -GeneratedAt '2026-11-19T12:00:00+09:00' `
        -DestinationManifestPath $manifestPath

    Assert-ApvTestEqual ([int]$builtManifest.manifestVersion) 1 'manifestVersion'
    Assert-ApvTestEqual $builtManifest.seedName 'benefits' 'seedName'
    Assert-ApvTestEqual ([int]$builtManifest.seedVersion) 8 'seedVersion'
    Assert-ApvTestEqual $builtManifest.hashAlgorithm 'SHA-256-LF-UTF8' 'hashAlgorithm'
    Assert-ApvTestEqual ([int]$builtManifest.totalCount) 2 'totalCount'
    Assert-ApvTestEqual ([int]$builtManifest.exactPinCount) 1 'exactPinCount'
    Assert-ApvTestEqual ([int]$builtManifest.unconfirmedCoordinateCount) 1 'unconfirmedCoordinateCount'
    Assert-ApvTestEqual ([int]$builtManifest.manualSeedCount) 0 'manualSeedCount'
    Assert-ApvTestEqual $builtManifest.seedSha256 (Get-ReleaseNormalizedLfSha256 -Text $seedPayload) 'seedSha256'
    Assert-ApvTestEqual $builtManifest.manualSeedSha256 (Get-ReleaseNormalizedLfSha256 -Text '{"items":[]}') 'manualSeedSha256'

    $manifestBytes = [IO.File]::ReadAllBytes($manifestPath)
    Assert-ApvTestTrue (-not ($manifestBytes.Length -ge 3 -and $manifestBytes[0] -eq 0xEF -and $manifestBytes[1] -eq 0xBB -and $manifestBytes[2] -eq 0xBF)) 'Manifest must not have UTF-8 BOM'

    $buildScript = Join-Path $PSScriptRoot 'build-release-benefit-seed-manifest.ps1'
    $cliManifestPath = Join-Path $tempRoot 'cli.manifest.json'
    $null | & $pwshBin -NoProfile -NonInteractive -OutputFormat Text -File $buildScript -SeedJsonPath $seedPath -ManualSeedJsonPath $manualPath -CanonicalCsvPath $canonicalPath -SeedVersion 9 -GeneratedAt '2026-11-19T00:00:00Z' -DestinationManifestPath $cliManifestPath | Out-Null
    Assert-ApvTestEqual $LASTEXITCODE 0 'Manifest builder CLI exits 0'
    $cliManifest = ConvertFrom-InternalManifestJson -Text (Read-ReleaseUtf8Text -Path $cliManifestPath)
    Assert-BenefitReleaseSeedManifest -Manifest $cliManifest
    Assert-ApvTestEqual ([int]$cliManifest.seedVersion) 9 'CLI manifest seedVersion'

    # Fail-closed manifest builder cases
    $badSeedPath = Join-Path $tempRoot 'bad-seed.json'
    [IO.File]::WriteAllText($badSeedPath, '[]', [Text.UTF8Encoding]::new($false))
    Assert-ApvTestThrowsMatching { New-ReleaseBenefitSeedManifest -SeedJsonPath $badSeedPath -ManualSeedJsonPath $manualPath -CanonicalCsvPath $canonicalPath -SeedVersion 1 } 'MNF_SEED_JSON_EMPTY' 'Empty seed fails'

    [IO.File]::WriteAllText($badSeedPath, '{"id":"not-array"}', [Text.UTF8Encoding]::new($false))
    Assert-ApvTestThrowsMatching { New-ReleaseBenefitSeedManifest -SeedJsonPath $badSeedPath -ManualSeedJsonPath $manualPath -CanonicalCsvPath $canonicalPath -SeedVersion 1 } 'MNF_SEED_JSON_MUST_BE_ARRAY' 'Object seed fails'

    [IO.File]::WriteAllText($badSeedPath, '[{"id":"seed-1","status":"ENDED","latitude":null,"longitude":null}]', [Text.UTF8Encoding]::new($false))
    Assert-ApvTestThrowsMatching { New-ReleaseBenefitSeedManifest -SeedJsonPath $badSeedPath -ManualSeedJsonPath $manualPath -CanonicalCsvPath $canonicalPath -SeedVersion 1 } 'MNF_SEED_ITEM_NOT_ACTIVE' 'Non-ACTIVE seed item fails'

    [IO.File]::WriteAllText($badSeedPath, '[{"id":"seed-1","status":"ACTIVE","latitude":37.5,"longitude":null}]', [Text.UTF8Encoding]::new($false))
    Assert-ApvTestThrowsMatching { New-ReleaseBenefitSeedManifest -SeedJsonPath $badSeedPath -ManualSeedJsonPath $manualPath -CanonicalCsvPath $canonicalPath -SeedVersion 1 } 'MNF_SEED_ITEM_PARTIAL_COORDINATES' 'Partial coordinates fail'

    [IO.File]::WriteAllText($badSeedPath, '[{"id":"seed-1","status":"ACTIVE","latitude":91.0,"longitude":127.0}]', [Text.UTF8Encoding]::new($false))
    Assert-ApvTestThrowsMatching { New-ReleaseBenefitSeedManifest -SeedJsonPath $badSeedPath -ManualSeedJsonPath $manualPath -CanonicalCsvPath $canonicalPath -SeedVersion 1 } 'MNF_SEED_ITEM_INVALID_COORDINATES' 'Out-of-range coordinates fail'

    $badManifestObj = $builtManifest | Select-Object *
    $badManifestObj.exactPinCount = 2
    Assert-ApvTestThrowsMatching { Assert-BenefitReleaseSeedManifest -Manifest $badManifestObj } 'must equal totalCount' 'Mismatched pin sum fails'

    $badAlgManifest = $builtManifest | Select-Object *
    $badAlgManifest.hashAlgorithm = 'SHA-256'
    Assert-ApvTestThrowsMatching { Assert-BenefitReleaseSeedManifest -Manifest $badAlgManifest } 'hashAlgorithm must be SHA-256-LF-UTF8' 'Unsupported hashAlgorithm fails'

    Write-Host 'PASS: approval release pipeline'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

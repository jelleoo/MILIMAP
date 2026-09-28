Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/identity/normalize-business.ps1')
. (Join-Path $PSScriptRoot 'lib/history/location-history-adapter.ps1')
. (Join-Path $PSScriptRoot 'lib/history/compare-location-history.ps1')
. (Join-Path $PSScriptRoot 'lib/history/benefit-history-adapter.ps1')
. (Join-Path $PSScriptRoot 'lib/history/phase3-review-audit.ps1')

function Assert-CloseoutEqual {
    param($Actual,$Expected,[string]$Message)
    if ($Actual -cne $Expected) { throw "$Message (expected: $Expected, actual: $Actual)" }
}
function Assert-CloseoutSet {
    param([object[]]$Actual,[object[]]$Expected,[string]$Message)
    $actualSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $expectedSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($value in @($Actual)) { if (-not $actualSet.Add([string]$value)) { throw "$Message has duplicate actual value: $value" } }
    foreach ($value in @($Expected)) { if (-not $expectedSet.Add([string]$value)) { throw "$Message has duplicate expected value: $value" } }
    if (-not $actualSet.SetEquals($expectedSet)) { throw "$Message (expected: $(@($expectedSet | Sort-Object -CaseSensitive) -join ','), actual: $(@($actualSet | Sort-Object -CaseSensitive) -join ','))" }
}

$script:closeoutBusinessId = 'biz-0123456789abcdef0123456789abcdef'
$script:closeoutRevision = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
$script:closeoutRunCounter = 0
function New-CloseoutRunId {
    $script:closeoutRunCounter++
    return 'run-' + $script:closeoutRunCounter.ToString('x32')
}
function New-CloseoutBusiness {
    param([string]$Name='테스트 식당')
    New-NormalizedBusiness -SourceRowNumber 2 -OriginalName $Name -NormalizedName ($Name -replace '\s','') -BaseName $Name -OriginalRoadAddress '경기도 양주시 테스트로 10' -PreferredAddress '경기도 양주시 테스트로 10' -Province '경기도' -City '양주시' -RoadName '테스트로' -BuildingMain '10' -AddressParseStatus COMPLETE
}
function New-CloseoutCandidate {
    param([string]$RoadAddress='경기도 양주시 테스트로 10',[double]$Latitude=37.123456,[double]$Longitude=127.123456,[string]$Phone='031-0000-0010')
    $discovery = New-PoiDiscoveryEvidence -StrategyCode NAME_FULL_ADDRESS -Query '테스트 식당 경기도 양주시 테스트로 10' -QueryOrder 1 -ResultPosition 1 -ResultCount 1
    New-PoiCandidate -CandidateKey 'naver-1' -Provider NAVER_API_HUB_LOCAL -OriginalName '테스트 식당' -NormalizedName '테스트식당' -RoadAddress $RoadAddress -LotAddress '경기도 양주시 테스트동 10' -Latitude $Latitude -Longitude $Longitude -Phone $Phone -Category '음식점' -ProviderLink 'https://map.example/1' -DiscoveredBy @($discovery)
}
function New-CloseoutLocationPackage {
    param($Store,[string]$Name='테스트 식당',[string]$RoadAddress='경기도 양주시 테스트로 10',[double]$Latitude=37.123456,[double]$Longitude=127.123456,[string]$Phone='031-0000-0010',[switch]$Absent,[switch]$Failed,[string]$Revision=$script:closeoutRevision)
    $business = New-CloseoutBusiness -Name $Name
    $candidate = New-CloseoutCandidate -RoadAddress $RoadAddress -Latitude $Latitude -Longitude $Longitude -Phone $Phone
    $attempt = New-PoiQueryAttempt -StrategyCode NAME_FULL_ADDRESS -Query '테스트 식당 경기도 양주시 테스트로 10' -QueryOrder 1 -Status SUCCESS -ResultCount 1
    $batchStatus = if ($Failed) { 'FAILED' } else { 'COMPLETE' }
    $candidates = if ($Absent) { @() } else { @($candidate) }
    $batch = New-PoiDiscoveryBatch -SourceRowNumber 2 -Status $batchStatus -Candidates $candidates -QueryAttempts @($attempt)
    $evaluation = if ($Failed) { 'INCOMPLETE' } else { 'COMPLETE' }
    $classification = if ($Absent) { 'RED' } elseif ($Failed) { 'YELLOW' } else { 'GREEN' }
    $selected = if ($Absent) { $null } else { $candidate }
    $keys = if ($Absent) { @() } else { @($candidate.CandidateKey) }
    $reasons = if ($Absent) { @('NO_CANDIDATE') } else { @('SINGLE_STRONG_CANDIDATE') }
    $count = if ($Absent) { 0 } else { 1 }
    $result = New-PoiMatchResult -SourceRowNumber 2 -EvaluationStatus $evaluation -Classification $classification -SelectedCandidate $selected -RankedCandidateKeys $keys -ReasonCodes $reasons -ConflictCodes @() -Evidence @() -EvaluatedCandidateCount $count -SurvivingCandidateCount $count -ProductionAction NONE
    New-LocationHistoryObservationPackage -Store $Store -RunId (New-CloseoutRunId) -BusinessId $script:closeoutBusinessId -ObservedAt '2026-09-28T00:00:00Z' -RepositoryRevision $Revision -Business $business -DiscoveryBatch $batch -Result $result -ExecutionConfiguration ([pscustomobject]@{Mode='TEST'})
}
function New-CloseoutBenefitClaim {
    param([string]$Type='BENEFIT_DESCRIPTION',[string]$Value='10% 할인',[string]$Result='CONFIRMED')
    $validated = New-ValidatedBenefitClaim -ClaimType $Type -Value $Value -ValidationStatus VALIDATED -EvidenceText $Value -EvidenceReference 'TABLE_ROW:1:CELL:2' -SourceUrl 'https://city.example.go.kr/benefit'
    $reasons = if ($Result -ceq 'CHANGED') { @('MATERIAL_CHANGE') } else { @() }
    New-BenefitClaimVerification -ClaimType $Type -CanonicalValue $Value -EvidenceValue $Value -Result $Result -ValidatedClaim $validated -ReasonCodes $reasons
}
function New-CloseoutBenefitPackage {
    param($Store,[object[]]$Claims=@((New-CloseoutBenefitClaim)),[string]$State='ACTIVE',[string]$Review='GREEN',[string]$LocationStatus='LOCATED',[string]$ExtractionStatus='COMPLETE',[string]$EvidenceHash=('a'*64))
    $business = New-CloseoutBusiness
    $benefit = New-CanonicalBenefitRecord -SourceRowNumber 2 -BusinessName '테스트 식당' -BenefitDescription '10% 할인' -EligibleTarget '현역 장병' -UsageCondition '평일' -VerificationMethod '군인증' -ExistingSourceType '지자체 공식 자료' -ExistingSourceUrl 'https://city.example.go.kr/benefit' -ExistingVerifiedOn '2026-09-01'
    $result = New-BenefitVerificationResult -SourceRowNumber 2 -BusinessIdentity $business -BenefitState $State -ReviewClass $Review -ReasonCodes @() -ClaimResults $Claims -Evidence @() -Warnings @() -ProductionAction NONE
    $diagnostic = [pscustomobject]@{Url='https://city.example.go.kr/benefit';SourceFormat='HTML';FetchStatus='COMPLETE';ContentHash=$EvidenceHash;ObservedAt='2026-09-28T00:00:00Z';AdapterId='HTML_GENERIC';AdapterVersion=1;AdapterStatus='COMPLETE';LocationOperationalStatus='COMPLETE';LocationStatus=$LocationStatus;CandidateReferences=@('TABLE_ROW:1');OfficialityStatus='VERIFIED_OFFICIAL';BusinessBindingStatus='STRONG';ExtractionStatus=$ExtractionStatus;ValidatedClaims=@();ReasonCodes=@()}
    New-BenefitHistoryObservationPackage -Store $Store -RunId (New-CloseoutRunId) -BusinessId $script:closeoutBusinessId -ObservedAt '2026-09-28T00:00:00Z' -RepositoryRevision $script:closeoutRevision -Benefit $benefit -BusinessIdentity $business -CanonicalPhone '031-000-0000' -Result $result -EvidenceDiagnostics @($diagnostic) -OperationalStatus ([pscustomobject]@{DiscoveryStatus='COMPLETE';ExtractionStatus=$ExtractionStatus})
}
function Publish-CloseoutArtifacts {
    param($Store,$Package)
    foreach ($artifact in @($Package.PreparedArtifacts)) {
        [void](Write-HistoryArtifact -Store $Store -ContentHash $artifact.ContentHash -Extension $artifact.Extension -Text $artifact.Text)
    }
}

$matrixPath = Join-Path $PSScriptRoot 'testdata/phase3-closeout/representative-results.psd1'
if (-not (Test-Path -LiteralPath $matrixPath)) { throw 'Phase 3 representative closeout matrix is missing' }
$matrix = Import-PowerShellDataFile -LiteralPath $matrixPath

$required = @('Group','CaseId','Domain','EvidenceClass','EvidenceReference','VerifiedAt','Status','TemporalTruthStatus','ReplayStatus','ExpectedRoute','ExpectedCandidates','ExpectedReasons','ExpectedAuditFlags')
$validRoutes = @('RECORD_ONLY','HUMAN_DOMAIN_REVIEW','AUDIT_VERIFICATION','OPERATIONAL_DIAGNOSTIC')
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($case in @($matrix.Cases)) {
    foreach ($field in $required) {
        if (-not $case.ContainsKey($field)) { throw "Missing $field in $($case.CaseId)" }
    }
    if ($case.Count -ne $required.Count) { throw "Unexpected matrix fields in $($case.CaseId)" }
    if (-not $seen.Add([string]$case.CaseId)) { throw "Duplicate case ID: $($case.CaseId)" }
    if ([string]$case.Group -cnotin @('A','B','C')) { throw "Invalid Group: $($case.CaseId)" }
    if ([string]$case.Domain -cnotin @('LOCATION','BENEFIT')) { throw "Invalid Domain: $($case.CaseId)" }
    if ([string]$case.TemporalTruthStatus -cnotin @('NOT_ESTABLISHED','SYNTHETIC_GROUND_TRUTH')) { throw "Invalid temporal truth: $($case.CaseId)" }
    if ([string]$case.ReplayStatus -cnotin @('DETERMINISTIC_REPLAY','PROVENANCE_ONLY_NO_TEMPORAL_GROUND_TRUTH','REFERENCED_EXISTING_VALIDATION')) { throw "Invalid replay status: $($case.CaseId)" }
    if ([string]::IsNullOrWhiteSpace([string]$case.EvidenceReference)) { throw "Missing evidence reference: $($case.CaseId)" }
    if ([string]::IsNullOrWhiteSpace([string]$case.VerifiedAt) -or [string]::IsNullOrWhiteSpace([string]$case.Status)) { throw "Missing verification metadata: $($case.CaseId)" }
    if ([string]$case.ExpectedRoute -cnotin $validRoutes) { throw "Invalid expected route: $($case.CaseId)" }
    foreach ($field in @('ExpectedCandidates','ExpectedReasons','ExpectedAuditFlags')) {
        if ($null -eq $case[$field] -or $case[$field] -isnot [array]) { throw "Invalid expected set $field in $($case.CaseId)" }
    }
    if ([string]$case.Group -ceq 'B') {
        if ([string]$case.EvidenceClass -cne 'HISTORICAL_SOURCE_CITED_CONTROL' -or [string]$case.TemporalTruthStatus -cne 'NOT_ESTABLISHED' -or [string]$case.ReplayStatus -cne 'PROVENANCE_ONLY_NO_TEMPORAL_GROUND_TRUTH') { throw "Historical case mislabeled: $($case.CaseId)" }
    }
    if ([string]$case.Group -ceq 'C') {
        if ([string]$case.EvidenceClass -cne 'SYNTHETIC_TEMPORAL_FIXTURE' -or [string]$case.TemporalTruthStatus -cne 'SYNTHETIC_GROUND_TRUTH' -or [string]$case.ReplayStatus -cne 'DETERMINISTIC_REPLAY') { throw "Synthetic case mislabeled: $($case.CaseId)" }
    } elseif ([string]$case.Group -ceq 'A') {
        if ([string]$case.EvidenceClass -cne 'DETERMINISTIC_FIXTURE' -or [string]$case.ReplayStatus -cne 'DETERMINISTIC_REPLAY') { throw "Unchanged control mislabeled: $($case.CaseId)" }
    }
    if ([string]$case.Group -cne 'C' -and [string]$case.TemporalTruthStatus -cne 'NOT_ESTABLISHED') { throw "Non-synthetic case claims temporal truth: $($case.CaseId)" }
}
if ($seen.Count -ne 16) { throw "Expected 16 closeout cases, got $($seen.Count)" }

function Invoke-Phase3RepresentativeReplay {
    param([object[]]$Cases)

    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $golden = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'testdata/phase1-poi-shadow-golden.psd1')
    $phase2 = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'testdata/phase2-closeout/representative-results.psd1')
    $historyReport = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'docs/handover/2026-09-24-phase1-poi-shadow-validation.md')
    $root = Join-Path ([IO.Path]::GetTempPath()) ('milimap-phase3-closeout-' + [Guid]::NewGuid().ToString('N'))
    $replayed = [Collections.Generic.List[object]]::new()
    $provenanceOnly = 0
    try {
        $store = New-HistoryStoreLayout -Root $root
        $locationPrevious = New-CloseoutLocationPackage -Store $store
        $benefitPrevious = New-CloseoutBenefitPackage -Store $store
        $targetPrevious = New-CloseoutBenefitPackage -Store $store -Claims @((New-CloseoutBenefitClaim -Type ELIGIBLE_TARGET -Value '현역 장병'))
        foreach ($package in @($locationPrevious,$benefitPrevious,$targetPrevious)) { Publish-CloseoutArtifacts -Store $store -Package $package }

        foreach ($case in $Cases) {
            if ([string]$case.Group -ceq 'B') {
                $rowNumber = [string]$case.CaseId.Substring(2)
                $source = $golden[$rowNumber]
                if ($null -eq $source) { throw "Missing Phase 1 Golden row: $rowNumber" }
                Assert-CloseoutEqual ([string]$source.SourceRowNumber) $rowNumber "$($case.CaseId) Golden row identity"
                Assert-CloseoutEqual ([string]$source.SourcePath) ([string]$case.EvidenceReference) "$($case.CaseId) source path"
                if ([string]::IsNullOrWhiteSpace([string]$source.SourceNote)) { throw "$($case.CaseId) Golden source note missing" }
                $reportPath = Join-Path $repoRoot ([string]$source.SourcePath)
                $matches = @(Import-Csv -LiteralPath $reportPath | Where-Object { [string]$_.'정본CSV행번호' -ceq $rowNumber -and [string]$_.'업소명' -ceq [string]$source.CanonicalRow.'업소명' })
                Assert-CloseoutEqual $matches.Count 1 "$($case.CaseId) source-cited report identity"
                Assert-CloseoutEqual ([string]$matches[0].검토결정) ([string]$case.Status) "$($case.CaseId) historical decision"
                Assert-CloseoutEqual ([string]$matches[0].감사판정) ([string]$case.Status) "$($case.CaseId) historical audit decision"
                if (-not ([string]$matches[0].검토메모).StartsWith([string]$case.VerifiedAt,[StringComparison]::Ordinal)) { throw "$($case.CaseId) historical date not cited in report" }
                Assert-CloseoutEqual ([string]$case.EvidenceClass) 'HISTORICAL_SOURCE_CITED_CONTROL' "$($case.CaseId) evidence class"
                Assert-CloseoutEqual ([string]$case.ExpectedRoute) (Get-Phase3ReviewRoute -ChangeCandidates @()) "$($case.CaseId) no-candidate taxonomy"
                foreach ($field in @('ExpectedCandidates','ExpectedReasons','ExpectedAuditFlags')) { Assert-CloseoutSet -Actual @() -Expected @($case[$field]) -Message "$($case.CaseId) $field provenance-only" }
                $provenanceOnly++
                continue # No previous/current History observation is invented for source-cited history.
            }

            if ([string]$case.EvidenceReference -cne "tools/data/test-phase3-closeout-validation.ps1:$($case.CaseId)") { throw "$($case.CaseId) synthetic fixture reference mismatch" }
            $previous = $locationPrevious
            $current = $null
            $comparison = $null
            switch ([string]$case.CaseId) {
                'A-NO-DELTA' { $current = New-CloseoutLocationPackage -Store $store }
                'A-EVIDENCE-ONLY' { $current = New-CloseoutLocationPackage -Store $store -Phone '031-0000-9999' }
                'A-BASELINE' { $current = New-CloseoutLocationPackage -Store $store; $previous = $null }
                'C-LOCATION-ADDRESS' { $current = New-CloseoutLocationPackage -Store $store -RoadAddress '경기도 양주시 다른로 10' }
                'C-LOCATION-COORDINATE' { $current = New-CloseoutLocationPackage -Store $store -Latitude 37.999999 -Longitude 127.999999 }
                'C-LOCATION-ABSENCE' { $current = New-CloseoutLocationPackage -Store $store -Absent }
                'C-CANONICAL-INPUT' { $current = New-CloseoutLocationPackage -Store $store -Name '다른 식당' }
                'C-EXECUTION' { $current = New-CloseoutLocationPackage -Store $store -Revision ('b'*40) }
                'C-OPERATIONAL-FAILURE' { $current = New-CloseoutLocationPackage -Store $store -Failed }
                'C-BENEFIT-DESCRIPTION' {
                    $previous = $benefitPrevious
                    $current = New-CloseoutBenefitPackage -Store $store -Claims @((New-CloseoutBenefitClaim -Value '20% 할인' -Result CHANGED)) -State CHANGED -EvidenceHash ('b'*64)
                }
                'C-BENEFIT-TARGET' {
                    $previous = $targetPrevious
                    $current = New-CloseoutBenefitPackage -Store $store -Claims @((New-CloseoutBenefitClaim -Type ELIGIBLE_TARGET -Value '현역 장병 및 예비역' -Result CHANGED)) -State CHANGED -EvidenceHash ('c'*64)
                }
                'C-BENEFIT-ABSENCE' {
                    $previous = $benefitPrevious
                    $current = New-CloseoutBenefitPackage -Store $store -Claims @() -State NEEDS_VERIFICATION -Review YELLOW -LocationStatus NOT_FOUND -ExtractionStatus FAILED -EvidenceHash ('d'*64)
                }
                default { throw "No deterministic replay fixture for $($case.CaseId)" }
            }

            if ([string]$case.Domain -ceq 'LOCATION') {
                $comparison = Compare-LocationHistoryObservations -Store $store -Previous $(if ($null -eq $previous) { $null } else { $previous.Observation }) -Current $current.Observation -StagedCurrentSemanticProjection $current.SemanticProjection
            } else {
                $comparison = Compare-BenefitHistoryObservations -Store $store -Previous $previous.Observation -Current $current.Observation -StagedCurrentSemanticProjection $current.SemanticProjection
            }
            $item = New-Phase3ReviewItem -Observation $current.Observation -Comparison $comparison
            Assert-CloseoutEqual ([string]$item.ReviewRoute) ([string]$case.ExpectedRoute) "$($case.CaseId) route"
            Assert-CloseoutSet -Actual @($item.ChangeCandidates) -Expected @($case.ExpectedCandidates) -Message "$($case.CaseId) candidates"
            Assert-CloseoutSet -Actual @($item.ReasonCodes) -Expected @($case.ExpectedReasons) -Message "$($case.CaseId) reasons"
            Assert-CloseoutSet -Actual @($item.AuditFlags) -Expected @($case.ExpectedAuditFlags) -Message "$($case.CaseId) audit flags"
            $replayed.Add([pscustomobject]@{CaseId=$case.CaseId;Item=$item})
        }

        Assert-CloseoutEqual $replayed.Count 12 'Deterministic A/C replay count'
        Assert-CloseoutEqual $provenanceOnly 4 'Historical provenance-only case count'
        $domainCandidates = @('LOCATION_CHANGE_SUSPECTED','LOCATION_ABSENCE_SUSPECTED','BENEFIT_CHANGE_SUSPECTED','BENEFIT_ABSENCE_SUSPECTED')
        $unexpected = @($replayed | Where-Object { $_.CaseId -like 'A-*' -and @($_.Item.ChangeCandidates | Where-Object { $_ -cin $domainCandidates }).Count -gt 0 }).Count
        $failureAbsence = @($replayed | Where-Object { $_.CaseId -ceq 'C-OPERATIONAL-FAILURE' -and @($_.Item.ChangeCandidates | Where-Object { $_ -in @('LOCATION_ABSENCE_SUSPECTED','BENEFIT_ABSENCE_SUSPECTED') }).Count -gt 0 }).Count
        $inputDomain = @($replayed | Where-Object { $_.CaseId -ceq 'C-CANONICAL-INPUT' -and @($_.Item.ChangeCandidates | Where-Object { $_ -cin $domainCandidates }).Count -gt 0 }).Count
        $processorDomain = @($replayed | Where-Object { $_.CaseId -ceq 'C-EXECUTION' -and @($_.Item.ChangeCandidates | Where-Object { $_ -cin $domainCandidates }).Count -gt 0 }).Count
        foreach ($gate in @(@('UnexpectedDomainChangeCandidates',$unexpected),@('OperationalFailureToSemanticAbsence',$failureAbsence),@('CanonicalInputToExternalDomainChange',$inputDomain),@('ProcessorChangeToExternalDomainChange',$processorDomain))) {
            Assert-CloseoutEqual $gate[1] 0 "Aggregate $($gate[0])"
        }
        Write-Host "Representative replay: A=3 B=4(provenance only) C=9; aggregate safety: 0/0/0/0"
    } finally {
        if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    }

    Assert-CloseoutEqual ([string]$phase2.CurrentFixed12ReplayStatus) 'NOT_RUN_NO_REPLAYABLE_RAW_CAPTURE' 'Phase 2 fixed-12 replay boundary'
    Assert-CloseoutEqual ([int]$phase2.ObservedRealSourceGreenRows) 0 'Phase 2 real-source GREEN count'
    Assert-CloseoutEqual ([string]$phase2.GreenHumanAudit.Status) 'NOT_APPLICABLE' 'Phase 2 GREEN human audit status'
    foreach ($source in @($phase2.RepresentativeRows | Where-Object EvidenceClass -eq 'PRIOR_AUTHORITATIVE_BOUNDED_LIVE_RESULT')) {
        Assert-CloseoutEqual ([string]$source.ObservationTimeStatus) 'HISTORICAL' 'Phase 2 prior bounded evidence time'
    }
    foreach ($unsupported in @($phase2.UnsupportedOrFailureControls)) {
        Assert-CloseoutEqual ([string]$unsupported.BenefitState) 'NEEDS_VERIFICATION' 'Unsupported Phase 2 source remains fail-closed'
    }
    Assert-CloseoutEqual ([int]$phase2.CurrentDeterministicSafety.NonNoneProductionAction) 0 'Phase 2 ProductionAction safety evidence'
    Assert-CloseoutEqual ([int]$phase2.CurrentDeterministicSafety.ProtectedPathWrites) 0 'Phase 2 protected-path evidence'
    if ($historyReport -notmatch 'ProductionAction=NONE`: 24 / 24' -or $historyReport -notmatch 'canonical / seed / apps diff: 0') { throw 'Phase 1 production/protected-path closeout evidence missing' }

    $benefitRegression = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'test-benefit-incremental-reuse.ps1')
    $locationRegression = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'test-phase3-location-history.ps1')
    foreach ($needle in @('AvoidedParseCount 1','AvoidedExtractionCount 1','AvoidedEvaluationCount 1','ArtifactDedupHits 1')) {
        if (-not $benefitRegression.Contains($needle,[StringComparison]::Ordinal)) { throw "Missing existing Benefit efficiency regression reference: $needle" }
    }
    foreach ($needle in @('MatcherCount 0','AvoidedMatcherCount 1','ProviderCalls -gt 0')) {
        if (-not $locationRegression.Contains($needle,[StringComparison]::Ordinal)) { throw "Missing existing Location efficiency regression reference: $needle" }
    }
    Write-Host 'Phase 1/2 boundary and existing P3-4/P3-6 efficiency references verified.'
}

Invoke-Phase3RepresentativeReplay -Cases @($matrix.Cases)
Write-Host 'Phase 3 closeout validation tests passed.'

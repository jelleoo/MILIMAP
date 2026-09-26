$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-location/test-support.ps1')

$expectedRows = @(2, 4, 5, 22, 74, 75, 118, 119, 139, 280, 337, 338)
$artifactPath = Join-Path $PSScriptRoot 'testdata/phase2-closeout/representative-results.psd1'
if (-not (Test-Path -LiteralPath $artifactPath)) {
    throw 'Phase 2 closeout representative-results artifact is required'
}

$closeout = Import-PowerShellDataFile -LiteralPath $artifactPath
$canonicalPath = Join-Path $PSScriptRoot '../../data/canonical/capital-area-military-benefits.csv'
$canonicalRows = @(Import-Csv -LiteralPath $canonicalPath)
Assert-ScopeEqual $closeout.CurrentFixed12ReplayStatus NOT_RUN_NO_REPLAYABLE_RAW_CAPTURE 'Fixed-12 matrix does not claim a current-code replay without replayable raw captures'
Assert-ScopeEqual @($closeout.RepresentativeRows).Count $expectedRows.Count 'Closeout preserves exactly the fixed representative sample size'
Assert-ScopeEqual (@($closeout.RepresentativeRows | ForEach-Object { [int]$_.SourceRowNumber }) -join ',') ($expectedRows -join ',') 'Closeout preserves the preselected representative source row order'
Assert-ScopeEqual $closeout.PriorBoundedRunHarnessExceptions 0 'Prior authoritative bounded run had no harness exception'
Assert-ScopeEqual $closeout.ObservedRealSourceGreenRows 0 'Observed real-source GREEN rows remain zero'
Assert-ScopeEqual $closeout.CurrentDeterministicSafety.FalseEndedInTestedControls 0 'Current deterministic controls have no false ENDED'
Assert-ScopeEqual $closeout.CurrentDeterministicSafety.CrossBusinessLeakageInTestedControls 0 'Current deterministic controls have no cross-business leakage'
Assert-ScopeEqual $closeout.CurrentDeterministicSafety.HardConflictBypassInTestedControls 0 'Current deterministic controls have no hard-conflict bypass'
Assert-ScopeEqual $closeout.CurrentDeterministicSafety.NonNoneProductionAction 0 'Current deterministic controls retain ProductionAction NONE'
Assert-ScopeEqual $closeout.CurrentDeterministicSafety.ProtectedPathWrites 0 'Current deterministic controls write no protected path'

$expectedEvidenceClasses = @{
    2='POLICY_CAPABILITY_BOUNDARY'; 4='LATEST_FAMILY_SPECIFIC_LIVE_RESULT'; 5='LATEST_FAMILY_SPECIFIC_LIVE_RESULT'; 22='POLICY_CAPABILITY_BOUNDARY'
    74='DOCUMENTED_CAPABILITY_LIMITATION'; 75='DOCUMENTED_CAPABILITY_LIMITATION'; 118='PRIOR_AUTHORITATIVE_BOUNDED_LIVE_RESULT'; 119='PRIOR_AUTHORITATIVE_BOUNDED_LIVE_RESULT'
    139='PRIOR_AUTHORITATIVE_BOUNDED_LIVE_RESULT'; 280='DOCUMENTED_CAPABILITY_LIMITATION'; 337='COMMITTED_LIVE_ARTIFACT'; 338='COMMITTED_LIVE_ARTIFACT'
}

foreach ($row in @($closeout.RepresentativeRows)) {
    $canonical = $canonicalRows[[int]$row.SourceRowNumber - 2]
    Assert-ScopeEqual $canonical.업소명 $row.BusinessName "Representative row $($row.SourceRowNumber) remains bound to its fixed canonical business"
    Assert-ScopeEqual $canonical.출처유형 $row.SourceType "Representative row $($row.SourceRowNumber) retains its original source class"
    Assert-ScopeEqual $row.EvidenceClass $expectedEvidenceClasses[[int]$row.SourceRowNumber] "Representative row $($row.SourceRowNumber) has the correct evidence class"
    Assert-ScopeEqual $row.BenefitState NEEDS_VERIFICATION "Representative row $($row.SourceRowNumber) remains fail-closed"
    Assert-ScopeEqual $row.ReviewClass YELLOW "Representative row $($row.SourceRowNumber) remains human-reviewable"
    Assert-ScopeEqual $row.ProductionAction NONE "Representative row $($row.SourceRowNumber) has no production action"
    Assert-ScopeTrue ($row.BenefitState -ne 'ENDED') "Representative row $($row.SourceRowNumber) is never inferred ended"
    Assert-ScopeTrue ($row.ReviewClass -ne 'GREEN') "Representative row $($row.SourceRowNumber) is not an unaudited GREEN"
    Assert-ScopeTrue (-not [string]::IsNullOrWhiteSpace([string]$row.EvidenceReference)) "Representative row $($row.SourceRowNumber) keeps an auditable evidence reference"
    if ($row.EvidenceClass -eq 'COMMITTED_LIVE_ARTIFACT') {
        $evidencePath = ([string]$row.EvidenceReference -split ':', 2)[0]
        Assert-ScopeTrue (Test-Path -LiteralPath (Join-Path $PSScriptRoot "../.." $evidencePath)) "Representative row $($row.SourceRowNumber) reference is committed"
    }
}

foreach ($rowNumber in @(4,5)) {
    $mmaRow = @($closeout.RepresentativeRows | Where-Object SourceRowNumber -eq $rowNumber)[0]
    Assert-ScopeEqual $mmaRow.LocationStatus NOT_FOUND "MMA row $rowNumber preserves latest live identity absence"
    Assert-ScopeTrue ($mmaRow.EvidenceReference -match 'Issue #80 / PR #81') "MMA row $rowNumber cites the post-fix live validation"
    Assert-ScopeTrue ($mmaRow.EvidenceReference -notmatch 'mma-list\.fixture') "MMA row $rowNumber does not mislabel a fixture as row-level live evidence"
}
foreach ($rowNumber in @(118,119,139)) {
    $ddcRow = @($closeout.RepresentativeRows | Where-Object SourceRowNumber -eq $rowNumber)[0]
    Assert-ScopeEqual $ddcRow.ObservationTimeStatus HISTORICAL "DDC row $rowNumber is explicitly historical observation-time evidence"
    Assert-ScopeTrue ($ddcRow.EvidenceReference -match 'Issue #76 / PR #79') "DDC row $rowNumber cites the authoritative bounded live result"
}

foreach ($family in @('HTML','MMA_JSONP','XLSX')) {
    $control = @($closeout.SupportedFamilyControls | Where-Object Family -eq $family)
    Assert-ScopeEqual $control.Count 1 "Closeout has one $family positive control"
    Assert-ScopeEqual $control[0].OfficialityStatus VERIFIED_OFFICIAL "$family positive control has official provenance"
    Assert-ScopeEqual $control[0].LocationStatus LOCATED "$family positive control isolates its business"
    Assert-ScopeEqual $control[0].BindingStatus STRONG "$family positive control binds strongly"
    Assert-ScopeEqual $control[0].ValidationStatus VALIDATED "$family positive control validates source evidence"
    Assert-ScopeTrue (-not [string]::IsNullOrWhiteSpace([string]$control[0].EvidenceReference)) "$family positive control preserves physical evidence provenance"
}

Assert-ScopeEqual $closeout.GreenHumanAudit.Status NOT_APPLICABLE 'Zero real-source GREEN rows make human GREEN audit not applicable'
Assert-ScopeEqual $closeout.GreenHumanAudit.ObservedRealSourceGreenRows 0 'Closeout has no real-source GREEN row'

foreach ($family in @('PDF','OFFICIAL_SNS_BLOG','REVIEW_COMMUNITY','PAJU_DETAIL_INSUFFICIENT')) {
    $control = @($closeout.UnsupportedOrFailureControls | Where-Object Family -eq $family)
    Assert-ScopeEqual $control.Count 1 "Closeout explicitly records $family as fail-closed"
    Assert-ScopeTrue ($control[0].BenefitState -ne 'ENDED') "$family cannot infer ENDED"
    Assert-ScopeTrue ($control[0].SemanticStatus -ne 'NOT_FOUND' -or $control[0].ObservationStatus -eq 'COMPLETE') "$family only permits NOT_FOUND after a complete observation"
}

Write-Host 'Phase 2 closeout validation tests passed.'

@{
    EvidenceMode = 'COMMITTED_DETERMINISTIC_OR_CAPTURED_ONLY'
    CurrentFixed12ReplayStatus = 'NOT_RUN_NO_REPLAYABLE_RAW_CAPTURE'
    PriorBoundedRunHarnessExceptions = 0
    ObservedRealSourceGreenRows = 0
    RepresentativeRows = @(
        @{ SourceRowNumber = 2; BusinessName = '레드폴바버샵 강남신사점'; SourceType = '이용 후기'; EvidenceClass = 'POLICY_CAPABILITY_BOUNDARY'; BenefitState = 'NEEDS_VERIFICATION'; ReviewClass = 'YELLOW'; ProductionAction = 'NONE'; EvidenceReference = 'existing-source-policy:REVIEW_COMMUNITY_EXCLUDED' }
        @{ SourceRowNumber = 4; BusinessName = '우동명가기리야마본진'; SourceType = '공공데이터'; EvidenceClass = 'LATEST_FAMILY_SPECIFIC_LIVE_RESULT'; LocationStatus = 'NOT_FOUND'; BenefitState = 'NEEDS_VERIFICATION'; ReviewClass = 'YELLOW'; ProductionAction = 'NONE'; EvidenceReference = 'Issue #80 / PR #81 MMA post-fix live validation' }
        @{ SourceRowNumber = 5; BusinessName = '투오프커피'; SourceType = '공공데이터'; EvidenceClass = 'LATEST_FAMILY_SPECIFIC_LIVE_RESULT'; LocationStatus = 'NOT_FOUND'; BenefitState = 'NEEDS_VERIFICATION'; ReviewClass = 'YELLOW'; ProductionAction = 'NONE'; EvidenceReference = 'Issue #80 / PR #81 MMA post-fix live validation' }
        @{ SourceRowNumber = 22; BusinessName = '쵸리'; SourceType = '업체 공식 SNS'; EvidenceClass = 'POLICY_CAPABILITY_BOUNDARY'; BenefitState = 'NEEDS_VERIFICATION'; ReviewClass = 'YELLOW'; ProductionAction = 'NONE'; EvidenceReference = 'existing-source-policy:OFFICIAL_SNS_BLOG_EXCLUDED' }
        @{ SourceRowNumber = 74; BusinessName = '게이트호텔'; SourceType = '지자체 공식 자료'; EvidenceClass = 'DOCUMENTED_CAPABILITY_LIMITATION'; BenefitState = 'NEEDS_VERIFICATION'; ReviewClass = 'YELLOW'; ProductionAction = 'NONE'; EvidenceReference = 'docs/handover/2026-09-25-phase2-a2-paju-detail-capability.md:PAJU_LIST' }
        @{ SourceRowNumber = 75; BusinessName = '두둑한한판'; SourceType = '지자체 공식 자료'; EvidenceClass = 'DOCUMENTED_CAPABILITY_LIMITATION'; BenefitState = 'NEEDS_VERIFICATION'; ReviewClass = 'YELLOW'; ProductionAction = 'NONE'; EvidenceReference = 'docs/handover/2026-09-25-phase2-a2-paju-detail-capability.md:PAJU_LIST' }
        @{ SourceRowNumber = 118; BusinessName = '개성연출'; SourceType = '지자체 공식 자료'; EvidenceClass = 'PRIOR_AUTHORITATIVE_BOUNDED_LIVE_RESULT'; ObservationTimeStatus = 'HISTORICAL'; BenefitState = 'NEEDS_VERIFICATION'; ReviewClass = 'YELLOW'; ProductionAction = 'NONE'; EvidenceReference = 'Issue #76 / PR #79 historical bounded live validation' }
        @{ SourceRowNumber = 119; BusinessName = '고미나 헤어모드'; SourceType = '지자체 공식 자료'; EvidenceClass = 'PRIOR_AUTHORITATIVE_BOUNDED_LIVE_RESULT'; ObservationTimeStatus = 'HISTORICAL'; BenefitState = 'NEEDS_VERIFICATION'; ReviewClass = 'YELLOW'; ProductionAction = 'NONE'; EvidenceReference = 'Issue #76 / PR #79 historical bounded live validation' }
        @{ SourceRowNumber = 139; BusinessName = '정헤어샾'; SourceType = '지자체 공식 자료'; EvidenceClass = 'PRIOR_AUTHORITATIVE_BOUNDED_LIVE_RESULT'; ObservationTimeStatus = 'HISTORICAL'; BenefitState = 'NEEDS_VERIFICATION'; ReviewClass = 'YELLOW'; ProductionAction = 'NONE'; EvidenceReference = 'Issue #76 / PR #79 historical bounded live validation' }
        @{ SourceRowNumber = 280; BusinessName = '고려이발관'; SourceType = '지자체 공식 자료'; EvidenceClass = 'DOCUMENTED_CAPABILITY_LIMITATION'; BenefitState = 'NEEDS_VERIFICATION'; ReviewClass = 'YELLOW'; ProductionAction = 'NONE'; EvidenceReference = 'docs/handover/2026-09-26-phase2-attachment-capability-inventory.md:SUWON_PDF' }
        @{ SourceRowNumber = 337; BusinessName = '가마골 백숙'; SourceType = '지자체 공식 자료'; EvidenceClass = 'COMMITTED_LIVE_ARTIFACT'; BenefitState = 'NEEDS_VERIFICATION'; ReviewClass = 'YELLOW'; ProductionAction = 'NONE'; EvidenceReference = 'tools/data/testdata/benefit-evidence-xlsx/yangju-live-control.json:PositiveControl' }
        @{ SourceRowNumber = 338; BusinessName = '거석골'; SourceType = '지자체 공식 자료'; EvidenceClass = 'COMMITTED_LIVE_ARTIFACT'; BenefitState = 'NEEDS_VERIFICATION'; ReviewClass = 'YELLOW'; ProductionAction = 'NONE'; EvidenceReference = 'tools/data/testdata/benefit-evidence-xlsx/yangju-live-control.json:AbsenceControl' }
    )
    SupportedFamilyControls = @(
        @{ Family = 'HTML'; OfficialityStatus = 'VERIFIED_OFFICIAL'; LocationStatus = 'LOCATED'; BindingStatus = 'STRONG'; ValidationStatus = 'VALIDATED'; EvidenceReference = 'tools/data/test-phase2-scoped-html.ps1:HTML_TABLE_ROW' }
        @{ Family = 'MMA_JSONP'; OfficialityStatus = 'VERIFIED_OFFICIAL'; LocationStatus = 'LOCATED'; BindingStatus = 'STRONG'; ValidationStatus = 'VALIDATED'; EvidenceReference = 'tools/data/test-phase2-scoped-mma-jsonp.ps1:JSONP_LIST_TO_DETAIL' }
        @{ Family = 'XLSX'; OfficialityStatus = 'VERIFIED_OFFICIAL'; LocationStatus = 'LOCATED'; BindingStatus = 'STRONG'; ValidationStatus = 'VALIDATED'; EvidenceReference = 'tools/data/testdata/benefit-evidence-xlsx/yangju-live-control.json:PositiveControl' }
    )
    UnsupportedOrFailureControls = @(
        @{ Family = 'PDF'; ObservationStatus = 'UNSUPPORTED'; SemanticStatus = $null; BenefitState = 'NEEDS_VERIFICATION'; EvidenceReference = 'tools/data/test-phase2-benefit-shadow-mode.ps1:PDF_WITHOUT_ADAPTER' }
        @{ Family = 'OFFICIAL_SNS_BLOG'; ObservationStatus = 'NOT_ATTEMPTED'; SemanticStatus = $null; BenefitState = 'NEEDS_VERIFICATION'; EvidenceReference = 'existing-source-policy:OFFICIAL_SNS_BLOG_EXCLUDED' }
        @{ Family = 'REVIEW_COMMUNITY'; ObservationStatus = 'NOT_ATTEMPTED'; SemanticStatus = $null; BenefitState = 'NEEDS_VERIFICATION'; EvidenceReference = 'existing-source-policy:REVIEW_COMMUNITY_EXCLUDED' }
        @{ Family = 'PAJU_DETAIL_INSUFFICIENT'; ObservationStatus = 'COMPLETE'; SemanticStatus = 'NOT_FOUND'; BenefitState = 'NEEDS_VERIFICATION'; EvidenceReference = 'docs/handover/2026-09-25-phase2-a2-paju-detail-capability.md:PAJU_LIST' }
    )
    GreenHumanAudit = @{ Status = 'NOT_APPLICABLE'; ObservedRealSourceGreenRows = 0 }
    CurrentDeterministicSafety = @{
        FalseEndedInTestedControls = 0
        CrossBusinessLeakageInTestedControls = 0
        HardConflictBypassInTestedControls = 0
        NonNoneProductionAction = 0
        ProtectedPathWrites = 0
    }
}

@{
    'positive-paju-composite' = @{
        FixtureKind = 'REAL_SOURCE_CITED'
        Status = 'HISTORICAL_REFERENCE_ONLY'
        SourcePaths = @(
            'data/canonical/reports/official-benefit-release-candidates-20260908.csv'
            'data/canonical/capital-area-military-benefits.csv'
        )
        SourceUrl = 'https://www.paju.go.kr/user/soldier/BD_discountStoreList.do?q_ctgCd=1002'
        VerifiedOn = '2026-09-06'
        ExpectedHistoricalLabel = 'OFFICIAL_RELEASE_CANDIDATE'
        SourceNote = 'Historical release evidence only. The current BenefitState must be established by a new observation and must not be inferred from this fixture.'
    }

    'synthetic-explicit-end' = @{
        FixtureKind = 'SYNTHETIC_ALGORITHM_ONLY'
        Status = 'TEST_ONLY'
        ExpectedBenefitState = 'ENDED'
        ExpectedReviewClass = 'GREEN'
        SourceNote = 'Synthetic lifecycle case used only to protect deterministic explicit-ending behavior.'
    }

    'synthetic-source-conflict' = @{
        FixtureKind = 'SYNTHETIC_ALGORITHM_ONLY'
        Status = 'TEST_ONLY'
        ExpectedBenefitState = 'NEEDS_VERIFICATION'
        ExpectedReviewClass = 'RED'
        SourceNote = 'Synthetic conflicting official-source values used only to protect fail-closed source-conflict behavior.'
    }

    'synthetic-binding-conflict' = @{
        FixtureKind = 'SYNTHETIC_ALGORITHM_ONLY'
        Status = 'TEST_ONLY'
        ExpectedBenefitState = 'NEEDS_VERIFICATION'
        ExpectedReviewClass = 'RED'
        SourceNote = 'Synthetic business-binding mismatch used only to protect fail-closed identity behavior.'
    }
}

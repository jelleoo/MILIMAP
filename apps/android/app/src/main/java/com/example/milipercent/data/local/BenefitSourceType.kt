package com.example.milipercent.data.local

enum class BenefitSourceType {
    MMA_API,
    MANUAL_SEED,
    MANUAL_LOCAL,
    ;

    companion object {
        fun fromStorage(value: String): BenefitSourceType? =
            entries.firstOrNull { it.name == value }
    }
}

enum class ManualBenefitStatus {
    ACTIVE,
    NEEDS_VERIFICATION,
    ENDED,
    ;

    companion object {
        fun fromStorage(value: String?): ManualBenefitStatus? =
            entries.firstOrNull { it.name == value }
    }
}

val MMA_SOURCE_TYPE: String = BenefitSourceType.MMA_API.name
val MANUAL_SEED_SOURCE_TYPE: String = BenefitSourceType.MANUAL_SEED.name
val MANUAL_LOCAL_SOURCE_TYPE: String = BenefitSourceType.MANUAL_LOCAL.name

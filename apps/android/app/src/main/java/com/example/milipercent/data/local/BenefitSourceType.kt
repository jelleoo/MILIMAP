package com.example.milipercent.data.local

enum class BenefitSourceType {
    MMA_API,
    MANUAL_SEED,
    MANUAL_LOCAL,
    LOCAL_GOV,
    PUBLIC_EVIDENCE,
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

internal fun List<BenefitEntity>.uniquePublishedBenefitIdsByIdentity(): Map<String, String> =
    asSequence()
        .filter { it.sourceType == BenefitSourceType.LOCAL_GOV.name ||
            it.sourceType == BenefitSourceType.PUBLIC_EVIDENCE.name }
        .filter { it.status == ManualBenefitStatus.ACTIVE.name }
        .groupBy({ BenefitIdentity.normalizedKey(it.name, it.address) }, BenefitEntity::id)
        .mapNotNull { (identity, ids) -> ids.singleOrNull()?.let { identity to it } }
        .toMap()

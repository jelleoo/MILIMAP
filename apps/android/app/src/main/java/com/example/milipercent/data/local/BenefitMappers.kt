package com.example.milipercent.data.local

import com.example.milipercent.analysis.BenefitAnalyzer
import com.example.milipercent.model.Benefit
import com.example.milipercent.model.BenefitStatus
import com.example.milipercent.model.BenefitDetail
import com.example.milipercent.model.BenefitUiModel
import com.example.milipercent.model.MmaBenefit

fun Benefit.toEntity(syncedAt: Long): BenefitEntity {
    return BenefitEntity(
        id = id,
        sourceType = sourceType.name,
        sourceRowNumber = null,
        name = name,
        address = address,
        latitude = latitude,
        longitude = longitude,
        category = category,
        benefitType = benefitType,
        benefitDescription = benefitDescription,
        phone = phone,
        eligibleTarget = eligibleTarget,
        usageCondition = usageCondition,
        verificationMethod = verificationMethod,
        sourceLabel = sourceLabel,
        sourceUrl = sourceUrl,
        lastVerifiedAt = lastVerifiedAt,
        status = status.name,
        district = district,
        syncedAt = syncedAt,
    )
}

fun MmaBenefit.toEntity(syncedAt: Long): BenefitEntity {
    require(BenefitAnalyzer.isSeoulAddress(address)) {
        "서울 주소로 확인된 데이터만 로컬 DB에 저장할 수 있습니다."
    }
    val verifiedAddress = requireNotNull(address)

    return Benefit(
        id = BenefitIdentity.create(
            sourceType = MMA_SOURCE_TYPE,
            name = name,
            address = verifiedAddress,
        ),
        name = name,
        address = verifiedAddress,
        latitude = null,
        longitude = null,
        category = DEFAULT_CATEGORY,
        benefitType = benefitType ?: DEFAULT_BENEFIT_TYPE,
        benefitDescription = DEFAULT_BENEFIT_DESCRIPTION,
        phone = phone,
        eligibleTarget = null,
        usageCondition = null,
        verificationMethod = null,
        sourceType = BenefitSourceType.MMA_API,
        sourceLabel = MMA_SOURCE_LABEL,
        sourceUrl = null,
        lastVerifiedAt = null,
        status = BenefitStatus.NEEDS_VERIFICATION,
        district = BenefitAnalyzer.extractSeoulDistrict(verifiedAddress)
            ?: BenefitAnalyzer.UNKNOWN_DISTRICT,
    ).toEntity(syncedAt).copy(sourceRowNumber = sourceRowNumber)
}

fun BenefitEntity.toDomain(): Benefit = Benefit(
    id = id,
    name = name,
    address = address,
    latitude = latitude,
    longitude = longitude,
    category = category,
    benefitType = benefitType,
    benefitDescription = benefitDescription,
    phone = phone,
    eligibleTarget = eligibleTarget,
    usageCondition = usageCondition,
    verificationMethod = verificationMethod,
    sourceType = BenefitSourceType.fromStorage(sourceType) ?: BenefitSourceType.PUBLIC_EVIDENCE,
    sourceLabel = sourceLabel,
    sourceUrl = sourceUrl,
    lastVerifiedAt = lastVerifiedAt,
    status = BenefitStatus.entries.firstOrNull { it.name == status }
        ?: BenefitStatus.NEEDS_VERIFICATION,
    district = district,
)

fun BenefitEntity.toUiModel(): BenefitUiModel = BenefitUiModel(
    id = id,
    name = name,
    address = address,
    phone = phone,
    benefitType = benefitType,
    district = district ?: BenefitAnalyzer.UNKNOWN_DISTRICT,
    latitude = latitude,
    longitude = longitude,
)

fun BenefitEntity.toDetail(): BenefitDetail = BenefitDetail(
    id = id,
    name = name,
    address = address,
    phone = phone,
    benefitType = benefitType,
    district = district ?: BenefitAnalyzer.UNKNOWN_DISTRICT,
    sourceType = sourceType,
    benefitDescription = benefitDescription,
    eligibleTarget = eligibleTarget,
    usageCondition = usageCondition,
    verificationMethod = verificationMethod,
    sourceUrl = sourceUrl,
    lastVerifiedDate = lastVerifiedAt,
    status = status,
)

private const val DEFAULT_CATEGORY = "기타"
private const val DEFAULT_BENEFIT_TYPE = "할인·우대"
private const val DEFAULT_BENEFIT_DESCRIPTION = "혜택 내용은 업소에 확인"
private const val MMA_SOURCE_LABEL = "병무청 나라사랑가게 API"

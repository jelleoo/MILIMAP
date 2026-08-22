package com.example.milipercent.data.local

import com.example.milipercent.analysis.BenefitAnalyzer
import com.example.milipercent.model.Benefit
import com.example.milipercent.model.BenefitDetail
import com.example.milipercent.model.BenefitUiModel

fun Benefit.toEntity(syncedAt: Long): BenefitEntity {
    require(BenefitAnalyzer.isSeoulAddress(address)) {
        "서울 주소로 확인된 데이터만 로컬 DB에 저장할 수 있습니다."
    }

    return BenefitEntity(
        id = BenefitIdentity.create(
            sourceType = MMA_SOURCE_TYPE,
            name = name,
            address = address,
        ),
        sourceType = MMA_SOURCE_TYPE,
        sourceRowNumber = id,
        name = name,
        address = address,
        phone = phone,
        benefitType = benefitType,
        district = BenefitAnalyzer.extractSeoulDistrict(address)
            ?: BenefitAnalyzer.UNKNOWN_DISTRICT,
        latitude = null,
        longitude = null,
        syncedAt = syncedAt,
    )
}

fun BenefitEntity.toUiModel(): BenefitUiModel = BenefitUiModel(
    id = id,
    name = name,
    address = address,
    phone = phone,
    benefitType = benefitType,
    district = district,
    latitude = latitude,
    longitude = longitude,
)

fun BenefitEntity.toDetail(): BenefitDetail = BenefitDetail(
    id = id,
    name = name,
    address = address,
    phone = phone,
    benefitType = benefitType,
    district = district,
    sourceType = sourceType,
    benefitDescription = benefitDescription,
    eligibleTarget = eligibleTarget,
    usageCondition = usageCondition,
    verificationMethod = verificationMethod,
    sourceUrl = sourceUrl,
    lastVerifiedDate = lastVerifiedDate,
    status = status,
)

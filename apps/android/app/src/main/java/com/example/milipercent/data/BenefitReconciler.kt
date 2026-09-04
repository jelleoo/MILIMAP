package com.example.milipercent.data

import com.example.milipercent.analysis.BenefitAnalyzer
import com.example.milipercent.data.local.BenefitEntity
import com.example.milipercent.data.local.BenefitIdentity
import com.example.milipercent.data.local.BenefitSourceType
import com.example.milipercent.model.BenefitStatus
import com.example.milipercent.model.MmaBenefit

data class ReconciliationResult(
    val entities: List<BenefitEntity>,
    val matchedCount: Int,
    val addedCount: Int,
)

class BenefitReconciler {
    fun reconcile(
        existing: List<BenefitEntity>,
        remote: List<MmaBenefit>,
        syncedAt: Long,
    ): ReconciliationResult {
        require(remote.isNotEmpty()) { "빈 MMA API 응답은 기존 캐시를 교체할 수 없습니다." }

        val canonicalRemote = remote
            .groupBy { it.identityKey() }
            .toSortedMap()
            .map { (key, rows) -> key to rows.canonicalRow() }
        val existingByKey = existing
            .groupBy { BenefitIdentity.normalizedKey(it.name, it.address) }
            .mapValues { (_, rows) -> rows.sortedWith(existingComparator()).first() }

        var matched = 0
        val entities = canonicalRemote.map { (key, row) ->
            val current = existingByKey[key]
            if (current != null) {
                matched += 1
                if (current.sourceType == BenefitSourceType.MMA_API.name) {
                    current.copy(
                        phone = current.phone.takeUnless(String?::isNullOrBlank)
                            ?: row.phone.trimmedOrNull(),
                        benefitType = current.benefitType.takeIf { it.isNotBlank() }
                            ?: row.benefitType.trimmedOrNull()
                            ?: DEFAULT_BENEFIT_TYPE,
                    )
                } else {
                    current
                }
            } else {
                row.toNewEntity(syncedAt)
            }
        }
        return ReconciliationResult(
            entities = entities,
            matchedCount = matched,
            addedCount = entities.size - matched,
        )
    }

    fun isCurrentProductRegion(address: String?): Boolean {
        val normalized = address?.trim()?.replace(Regex("\\s+"), "").orEmpty()
        return normalized.startsWith("서울특별시") || normalized.startsWith("서울시") ||
            normalized.startsWith("경기도") || normalized.startsWith("경기") ||
            normalized.startsWith("인천광역시") || normalized.startsWith("인천")
    }

    private fun MmaBenefit.identityKey(): String {
        require(name.isNotBlank()) { "MMA API 업체명이 비어 있습니다." }
        require(!address.isNullOrBlank()) { "MMA API 주소가 비어 있습니다." }
        return BenefitIdentity.normalizedKey(name, address)
    }

    private fun List<MmaBenefit>.canonicalRow(): MmaBenefit {
        val phoneValues = mapNotNull { it.phone.trimmedOrNull() }.distinct()
        val typeValues = mapNotNull { it.benefitType.trimmedOrNull() }.distinct()
        if (phoneValues.size > 1 || typeValues.size > 1) {
            throw RemoteBenefitConflictException(
                "같은 업체·주소의 MMA API 행이 서로 충돌합니다.",
            )
        }
        return sortedWith(
            compareBy<MmaBenefit> { it.sourceRowNumber ?: Int.MAX_VALUE }
                .thenBy { it.name }
                .thenBy { it.address.orEmpty() },
        ).first().copy(
            phone = phoneValues.singleOrNull(),
            benefitType = typeValues.singleOrNull(),
        )
    }

    private fun MmaBenefit.toNewEntity(syncedAt: Long): BenefitEntity {
        val address = requireNotNull(address)
        return BenefitEntity(
            id = BenefitIdentity.mmaId(name, address),
            sourceType = BenefitSourceType.MMA_API.name,
            sourceRowNumber = sourceRowNumber,
            name = name.trim(),
            address = address.trim(),
            latitude = null,
            longitude = null,
            category = DEFAULT_CATEGORY,
            benefitType = benefitType.trimmedOrNull() ?: DEFAULT_BENEFIT_TYPE,
            benefitDescription = DEFAULT_BENEFIT_DESCRIPTION,
            phone = phone.trimmedOrNull(),
            eligibleTarget = null,
            usageCondition = null,
            verificationMethod = null,
            sourceLabel = MMA_SOURCE_LABEL,
            sourceUrl = null,
            lastVerifiedAt = null,
            status = BenefitStatus.NEEDS_VERIFICATION.name,
            district = BenefitAnalyzer.extractSeoulDistrict(address) ?: BenefitAnalyzer.UNKNOWN_DISTRICT,
            syncedAt = syncedAt,
        )
    }

    private fun existingComparator() = compareByDescending<BenefitEntity> {
        if (it.latitude != null && it.longitude != null) 1 else 0
    }.thenBy { it.id }

    private fun String?.trimmedOrNull(): String? = this?.trim()?.takeIf(String::isNotEmpty)

    private companion object {
        const val DEFAULT_CATEGORY = "기타"
        const val DEFAULT_BENEFIT_TYPE = "할인·우대"
        const val DEFAULT_BENEFIT_DESCRIPTION = "혜택 내용은 업소에 확인"
        const val MMA_SOURCE_LABEL = "병무청 나라사랑가게 API"
    }
}

class RemoteBenefitConflictException(message: String) : IllegalArgumentException(message)

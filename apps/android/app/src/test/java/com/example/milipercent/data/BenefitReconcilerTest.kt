package com.example.milipercent.data

import com.example.milipercent.data.local.BenefitEntity
import com.example.milipercent.data.local.BenefitSourceType
import com.example.milipercent.model.MmaBenefit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class BenefitReconcilerTest {
    @Test
    fun `matched seed retains stable id coordinates and richer local fields`() {
        val existing = seedEntity(
            id = "verified_seed",
            name = "밀리 가게",
            address = "서울특별시 마포구 월드컵로 1",
            latitude = 37.5665,
            longitude = 126.9780,
            category = "음식점",
            benefitDescription = "군인 메뉴 20퍼센트 할인",
            eligibleTarget = "현역 군인",
            usageCondition = "신분증 제시",
            verificationMethod = "전화 확인",
            sourceLabel = "검증된 지역 데이터",
            sourceUrl = "https://example.test/evidence",
            lastVerifiedAt = "2026-09-01",
            status = "ACTIVE",
        )

        val result = BenefitReconciler().reconcile(
            existing = listOf(existing),
            remote = listOf(mma("밀리가게", "서울시 마포구 월드컵로1", "02-1234", "할인")),
            syncedAt = 100L,
        )

        assertEquals(1, result.matchedCount)
        assertEquals(0, result.addedCount)
        assertEquals(existing, result.entities.single())
    }

    @Test
    fun `matched cached API row fills only blank phone and benefit type`() {
        val existing = mmaEntity(
            id = "mma_cached",
            name = "밀리 가게",
            address = "서울특별시 마포구 월드컵로 1",
            phone = "  ",
            benefitType = "",
            benefitDescription = "기존 설명",
        )

        val result = BenefitReconciler().reconcile(
            existing = listOf(existing),
            remote = listOf(mma("밀리 가게", "서울시 마포구 월드컵로1", "02-9999", "우대")),
            syncedAt = 200L,
        )

        assertEquals("mma_cached", result.entities.single().id)
        assertEquals("02-9999", result.entities.single().phone)
        assertEquals("우대", result.entities.single().benefitType)
        assertEquals("기존 설명", result.entities.single().benefitDescription)
        assertEquals(existing.syncedAt, result.entities.single().syncedAt)
    }

    @Test
    fun `repeat refresh produces the same deterministic MMA id`() {
        val remote = listOf(mma("같은 가게", "인천광역시 부평구 시장로 1", "032-1111", "할인"))

        val first = BenefitReconciler().reconcile(emptyList(), remote, syncedAt = 1L).entities.single()
        val second = BenefitReconciler().reconcile(listOf(first), remote, syncedAt = 2L).entities.single()

        assertEquals(first.id, second.id)
        assertTrue(first.id.matches(Regex("mma_[0-9a-f]{64}")))
    }

    @Test
    fun `same name at different addresses remains separate`() {
        val result = BenefitReconciler().reconcile(
            existing = emptyList(),
            remote = listOf(
                mma("같은 상호", "서울특별시 마포구 월드컵로 1", "02-1111", "할인"),
                mma("같은 상호", "서울특별시 강남구 테헤란로 1", "02-2222", "우대"),
            ),
            syncedAt = 1L,
        )

        assertEquals(2, result.addedCount)
        assertEquals(2, result.entities.map(BenefitEntity::id).toSet().size)
        assertNotEquals(result.entities[0].id, result.entities[1].id)
    }

    @Test
    fun `remote input order cannot change reconciled output`() {
        val first = mma("가", "서울특별시 마포구 1", "02-1", "할인")
        val second = mma("나", "경기도 성남시 2", "031-2", "우대")

        val forward = BenefitReconciler().reconcile(emptyList(), listOf(first, second), syncedAt = 1L)
        val reversed = BenefitReconciler().reconcile(emptyList(), listOf(second, first), syncedAt = 1L)

        assertEquals(forward, reversed)
    }

    @Test
    fun `empty remote input is rejected before any replacement`() {
        assertThrows(IllegalArgumentException::class.java) {
            BenefitReconciler().reconcile(emptyList(), emptyList(), syncedAt = 1L)
        }
    }

    @Test
    fun `materially conflicting duplicate remote rows are rejected`() {
        assertThrows(IllegalArgumentException::class.java) {
            BenefitReconciler().reconcile(
                existing = emptyList(),
                remote = listOf(
                    mma("중복", "서울특별시 마포구 1", "02-1111", "할인"),
                    mma("중 복", "서울시 마포구1", "02-2222", "우대"),
                ),
                syncedAt = 1L,
            )
        }
    }

    private fun mma(
        name: String,
        address: String,
        phone: String?,
        benefitType: String?,
    ) = MmaBenefit(
        sourceRowNumber = 1,
        name = name,
        address = address,
        phone = phone,
        benefitType = benefitType,
    )

    private fun seedEntity(
        id: String,
        name: String,
        address: String,
        latitude: Double?,
        longitude: Double?,
        category: String,
        benefitDescription: String,
        eligibleTarget: String?,
        usageCondition: String?,
        verificationMethod: String?,
        sourceLabel: String,
        sourceUrl: String?,
        lastVerifiedAt: String?,
        status: String,
    ) = entity(
        id = id,
        sourceType = BenefitSourceType.LOCAL_GOV,
        name = name,
        address = address,
        latitude = latitude,
        longitude = longitude,
        category = category,
        benefitDescription = benefitDescription,
        eligibleTarget = eligibleTarget,
        usageCondition = usageCondition,
        verificationMethod = verificationMethod,
        sourceLabel = sourceLabel,
        sourceUrl = sourceUrl,
        lastVerifiedAt = lastVerifiedAt,
        status = status,
    )

    private fun mmaEntity(
        id: String,
        name: String,
        address: String,
        phone: String?,
        benefitType: String,
        benefitDescription: String,
    ) = entity(
        id = id,
        sourceType = BenefitSourceType.MMA_API,
        name = name,
        address = address,
        phone = phone,
        benefitType = benefitType,
        benefitDescription = benefitDescription,
    )

    private fun entity(
        id: String,
        sourceType: BenefitSourceType,
        name: String,
        address: String,
        latitude: Double? = null,
        longitude: Double? = null,
        category: String = "기타",
        benefitType: String = "할인",
        benefitDescription: String = "혜택 내용은 업소에 확인",
        phone: String? = null,
        eligibleTarget: String? = null,
        usageCondition: String? = null,
        verificationMethod: String? = null,
        sourceLabel: String = "테스트 출처",
        sourceUrl: String? = null,
        lastVerifiedAt: String? = null,
        status: String = "NEEDS_VERIFICATION",
    ) = BenefitEntity(
        id = id,
        sourceType = sourceType.name,
        sourceRowNumber = 1,
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
        status = status,
        district = "마포구",
        syncedAt = 7L,
    )
}

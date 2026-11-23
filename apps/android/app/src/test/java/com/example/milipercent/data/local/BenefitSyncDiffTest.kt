package com.example.milipercent.data.local

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BenefitSyncDiffTest {
    @Test
    fun `identical incoming entity is skipped while changed or removed rows are surfaced`() {
        val unchanged = entity("keep_same", lastVerifiedAt = "2026-10-01")
        val updatedBefore = entity("keep_changed", lastVerifiedAt = "2026-10-01")
        val updatedAfter = updatedBefore.copy(lastVerifiedAt = "2026-11-23", syncedAt = 200L)
        val removed = entity("drop_me", lastVerifiedAt = "2026-10-01")
        val added = entity("add_me", lastVerifiedAt = "2026-11-23")

        val diff = computeBenefitSourceDiff(
            existing = listOf(unchanged, updatedBefore, removed),
            incoming = listOf(unchanged, updatedAfter, added),
        )

        assertEquals(listOf("drop_me"), diff.removedIds)
        assertEquals(listOf("keep_changed", "add_me"), diff.toUpsert.map(BenefitEntity::id))
    }

    @Test
    fun `empty incoming removes all existing rows without upserting`() {
        val diff = computeBenefitSourceDiff(
            existing = listOf(entity("a"), entity("b")),
            incoming = emptyList(),
        )

        assertEquals(setOf("a", "b"), diff.removedIds.toSet())
        assertTrue(diff.toUpsert.isEmpty())
    }

    @Test
    fun `computeRetiredIds handles over thousand retained ids cleanly`() {
        val retained = (1..1100).map { "seed_$it" }
        val existing = retained + listOf("retired_1", "retired_2")

        val retired = computeRetiredIds(existing, retained)

        assertEquals(listOf("retired_1", "retired_2"), retired)
    }

    private fun entity(id: String, lastVerifiedAt: String? = "2026-10-01") = BenefitEntity(
        id = id,
        sourceType = MMA_SOURCE_TYPE,
        sourceRowNumber = 1,
        name = "가게 $id",
        address = "서울특별시 마포구 테스트로 1",
        latitude = null,
        longitude = null,
        category = "기타",
        benefitType = "할인",
        benefitDescription = "혜택",
        phone = null,
        eligibleTarget = null,
        usageCondition = null,
        verificationMethod = null,
        sourceLabel = "출처",
        sourceUrl = null,
        lastVerifiedAt = lastVerifiedAt,
        status = "ACTIVE",
        district = "마포구",
        syncedAt = 100L,
    )
}

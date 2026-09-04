package com.example.milipercent.data.manual

import com.example.milipercent.data.local.BenefitEntity
import com.example.milipercent.data.local.BenefitLocalDataSource
import com.example.milipercent.data.local.BenefitSourceType
import com.example.milipercent.data.local.ManualBenefitStatus
import com.example.milipercent.model.BenefitDistrict
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class ManualBenefitRepositoryTest {
    @Test
    fun `Create Update Delete가 ID와 source 격리를 지킨다`() = runBlocking {
        val seed = entity("manual_seed_keep", BenefitSourceType.MANUAL_SEED)
        val mma = entity("mma_keep", BenefitSourceType.MMA_API)
        val local = FakeLocalDataSource(listOf(seed, mma))
        val repository = RoomManualBenefitAdminRepository(
            localDataSource = local,
            currentTimeMillis = { 777L },
            uuidFactory = { "fixed-uuid" },
        )

        val id = repository.create(input(name = "등록 업체"))
        assertEquals("manual_local_fixed-uuid", id)
        val created = local.entity(id)
        requireNotNull(created)
        assertEquals(BenefitSourceType.MANUAL_LOCAL.name, created.sourceType)
        assertNull(created.sourceRowNumber)

        repository.update(id, input(name = "수정 업체", status = ManualBenefitStatus.ENDED))
        val updated = local.entity(id)
        requireNotNull(updated)
        assertEquals(id, updated.id)
        assertEquals("수정 업체", updated.name)
        assertEquals(ManualBenefitStatus.ENDED.name, updated.status)

        assertTrue(repository.delete(id))
        assertNull(local.entity(id))
        assertFalse(repository.delete(seed.id))
        assertEquals(seed, local.entity(seed.id))
        assertEquals(mma, local.entity(mma.id))
    }

    @Test
    fun `관리 목록은 MANUAL_LOCAL만 읽는다`() = runBlocking {
        val localItem = entity("manual_local_one", BenefitSourceType.MANUAL_LOCAL)
        val local = FakeLocalDataSource(
            listOf(
                entity("mma_one", BenefitSourceType.MMA_API),
                entity("manual_seed_one", BenefitSourceType.MANUAL_SEED),
                localItem,
            ),
        )

        val records = RoomManualBenefitAdminRepository(local).observeAll().first()

        assertEquals(listOf(localItem.id), records.map { it.id })
    }

    @Test
    fun `필수 입력 날짜 URL을 검증한다`() {
        val invalidInputs = listOf(
            input(name = ""),
            input(address = ""),
            input(description = ""),
            input(verificationMethod = ""),
            input(date = "2026-02-30"),
            input(sourceUrl = "file://unsafe"),
        )

        invalidInputs.forEach { value ->
            assertThrows(ManualBenefitInputException::class.java) {
                validateManualBenefitInput(value)
            }
        }
    }

    private class FakeLocalDataSource(initial: List<BenefitEntity>) : BenefitLocalDataSource {
        private val state = MutableStateFlow(initial)

        fun entity(id: String) = state.value.firstOrNull { it.id == id }

        override fun observeBenefits(sourceType: String): Flow<List<BenefitEntity>> =
            state.map { list -> list.filter { it.sourceType == sourceType } }

        override fun observeUserVisibleBenefits(): Flow<List<BenefitEntity>> =
            state.map { list -> list.filter { it.status != ManualBenefitStatus.ENDED.name } }

        override fun observeBenefitById(id: String): Flow<BenefitEntity?> =
            state.map { list -> list.firstOrNull { it.id == id } }

        override suspend fun replaceBenefits(sourceType: String, benefits: List<BenefitEntity>) {
            state.value = state.value.filterNot { it.sourceType == sourceType } + benefits
        }

        override suspend fun countBenefits(sourceType: String): Int =
            state.value.count { it.sourceType == sourceType }

        override suspend fun upsertBenefit(benefit: BenefitEntity) {
            state.value = state.value.filterNot { it.id == benefit.id } + benefit
        }

        override suspend fun deleteBenefit(id: String, sourceType: String): Boolean {
            val before = state.value.size
            state.value = state.value.filterNot { it.id == id && it.sourceType == sourceType }
            return before != state.value.size
        }
    }

    private companion object {
        fun input(
            name: String = "TEST ONLY 업체",
            address: String = "서울특별시 마포구 테스트로 1",
            description: String = "TEST ONLY 혜택",
            verificationMethod: String = "TEST ONLY",
            date: String = "2026-08-17",
            sourceUrl: String? = "https://example.com",
            status: ManualBenefitStatus = ManualBenefitStatus.ACTIVE,
        ) = ManualBenefitInput(
            name = name,
            address = address,
            district = BenefitDistrict.MAPO,
            benefitDescription = description,
            verificationMethod = verificationMethod,
            lastVerifiedDate = date,
            sourceUrl = sourceUrl,
            status = status,
        )

        fun entity(id: String, source: BenefitSourceType) = BenefitEntity(
            id = id,
            sourceType = source.name,
            sourceRowNumber = if (source == BenefitSourceType.MMA_API) 1 else null,
            name = id,
            address = "서울특별시 마포구",
            latitude = null,
            longitude = null,
            category = "기타",
            benefitType = "할인·우대",
            benefitDescription = if (source == BenefitSourceType.MMA_API) "혜택 내용은 업소에 확인" else "혜택",
            phone = null,
            eligibleTarget = null,
            usageCondition = null,
            verificationMethod = if (source == BenefitSourceType.MMA_API) null else "확인",
            sourceLabel = "테스트 출처",
            sourceUrl = null,
            lastVerifiedAt = if (source == BenefitSourceType.MMA_API) null else "2026-08-17",
            status = if (source == BenefitSourceType.MMA_API) "NEEDS_VERIFICATION" else ManualBenefitStatus.ACTIVE.name,
            district = "마포구",
            syncedAt = 1L,
        )
    }
}

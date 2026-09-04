package com.example.milipercent.data.seed

import com.example.milipercent.data.local.BenefitEntity
import com.example.milipercent.data.local.BenefitLocalDataSource
import com.example.milipercent.data.local.BenefitSourceType
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class ManualBenefitSeedLoaderTest {
    @Test
    fun `정상 Seed를 저장하고 재실행해도 중복되지 않는다`() = runBlocking {
        val source = MutableJsonSource(seedJson(item("one"), item("two")))
        val local = FakeLocalDataSource()
        val synchronizer = synchronizer(source, local)

        assertEquals(2, synchronizer.synchronize().storedCount)
        assertEquals(2, synchronizer.synchronize().storedCount)

        val stored = local.bySource(BenefitSourceType.MANUAL_SEED)
        assertEquals(2, stored.size)
        assertTrue(stored.all { it.sourceRowNumber == null })
        assertTrue(stored.all { it.sourceType == BenefitSourceType.MANUAL_SEED.name })
    }

    @Test
    fun `Seed가 변경되면 MANUAL_SEED만 새 목록으로 교체한다`() = runBlocking {
        val source = MutableJsonSource(seedJson(item("one"), item("two")))
        val mma = entity("mma_1", BenefitSourceType.MMA_API)
        val localItem = entity("manual_local_1", BenefitSourceType.MANUAL_LOCAL)
        val local = FakeLocalDataSource(listOf(mma, localItem))
        val synchronizer = synchronizer(source, local)

        synchronizer.synchronize()
        source.json = seedJson(item("one"), item("two"), item("three"))
        synchronizer.synchronize()

        assertEquals(3, local.bySource(BenefitSourceType.MANUAL_SEED).size)
        assertEquals(listOf(mma), local.bySource(BenefitSourceType.MMA_API))
        assertEquals(listOf(localItem), local.bySource(BenefitSourceType.MANUAL_LOCAL))
    }

    @Test
    fun `invalid Seed는 기존 Seed를 부분 교체하지 않는다`() = runBlocking {
        val existing = entity("manual_seed_existing", BenefitSourceType.MANUAL_SEED)
        val local = FakeLocalDataSource(listOf(existing))
        val source = MutableJsonSource(
            seedJson(
                item("valid"),
                item("invalid", district = "부산광역시"),
            ),
        )

        assertThrows(ManualBenefitSeedValidationException::class.java) {
            runBlocking { synchronizer(source, local).synchronize() }
        }

        assertEquals(listOf(existing), local.bySource(BenefitSourceType.MANUAL_SEED))
        assertEquals(0, local.replaceCallCount)
    }

    @Test
    fun `필수값 ID 날짜 상태 URL과 중복 ID를 모두 검증한다`() {
        val invalidDocuments = listOf(
            seedJson(item("bad-id", id = "wrong_prefix")),
            seedJson(item("blank", name = "")),
            seedJson(item("date", date = "2026-02-30")),
            seedJson(item("status", status = "UNKNOWN")),
            seedJson(item("url", sourceUrl = "ftp://example.com")),
            seedJson(item("same"), item("same")),
        )

        invalidDocuments.forEach { json ->
            assertThrows(ManualBenefitSeedValidationException::class.java) {
                ManualBenefitSeedLoader(MutableJsonSource(json)).loadAndValidate()
            }
        }
    }

    @Test
    fun `trim 후 같은 Seed ID는 Room 교체 전에 중복으로 거부한다`() {
        val existing = entity("manual_seed_existing", BenefitSourceType.MANUAL_SEED)
        val local = FakeLocalDataSource(listOf(existing))
        val source = MutableJsonSource(
            seedJson(
                item("x", id = "manual_seed_x"),
                item("x-space", id = "manual_seed_x "),
            ),
        )

        assertThrows(ManualBenefitSeedValidationException::class.java) {
            runBlocking { synchronizer(source, local).synchronize() }
        }

        assertEquals(0, local.replaceCallCount)
        assertEquals(listOf(existing), local.bySource(BenefitSourceType.MANUAL_SEED))
    }

    @Test
    fun `교체 후 저장 건수가 entity 수와 다르면 성공 건수를 보고하지 않는다`() {
        val local = FakeLocalDataSource(reportedCountOverride = 0)

        assertThrows(IllegalStateException::class.java) {
            runBlocking {
                synchronizer(
                    MutableJsonSource(seedJson(item("one"))),
                    local,
                ).synchronize()
            }
        }

        assertEquals(1, local.replaceCallCount)
    }

    private fun synchronizer(source: MutableJsonSource, local: FakeLocalDataSource) =
        RoomManualSeedSynchronizer(
            loader = ManualBenefitSeedLoader(
                jsonSource = source,
                currentTimeMillis = { 123L },
            ),
            localDataSource = local,
        )

    private class MutableJsonSource(var json: String) : ManualBenefitSeedJsonSource {
        override fun readText(): String = json
    }

    private class FakeLocalDataSource(
        initial: List<BenefitEntity> = emptyList(),
        private val reportedCountOverride: Int? = null,
    ) : BenefitLocalDataSource {
        private val state = MutableStateFlow(initial)
        var replaceCallCount = 0
            private set

        fun bySource(source: BenefitSourceType) =
            state.value.filter { it.sourceType == source.name }

        override fun observeBenefits(sourceType: String): Flow<List<BenefitEntity>> =
            state.map { list -> list.filter { it.sourceType == sourceType } }

        override fun observeUserVisibleBenefits(): Flow<List<BenefitEntity>> =
            state.map { list -> list.filter { it.status != "ENDED" } }

        override fun observeBenefitById(id: String): Flow<BenefitEntity?> =
            state.map { list -> list.firstOrNull { it.id == id } }

        override suspend fun replaceBenefits(sourceType: String, benefits: List<BenefitEntity>) {
            replaceCallCount += 1
            require(benefits.all { it.sourceType == sourceType })
            state.value = state.value.filterNot { it.sourceType == sourceType } + benefits
        }

        override suspend fun countBenefits(sourceType: String): Int =
            reportedCountOverride ?: state.value.count { it.sourceType == sourceType }

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
        fun seedJson(vararg items: String) = """{"items":[${items.joinToString()}]}"""

        fun item(
            key: String,
            id: String = "manual_seed_$key",
            name: String = "TEST ONLY $key",
            district: String = "마포구",
            date: String = "2026-08-17",
            status: String = "ACTIVE",
            sourceUrl: String? = "https://example.com/$key",
        ) = """
            {
              "id":"$id",
              "name":"$name",
              "address":"서울특별시 $district 테스트로 1",
              "district":"$district",
              "benefitDescription":"TEST ONLY 혜택",
              "verificationMethod":"TEST ONLY",
              "sourceUrl":${sourceUrl?.let { "\"$it\"" } ?: "null"},
              "lastVerifiedDate":"$date",
              "status":"$status"
            }
        """.trimIndent()

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
            benefitDescription = "혜택 내용은 업소에 확인",
            phone = null,
            eligibleTarget = null,
            usageCondition = null,
            verificationMethod = null,
            sourceLabel = "테스트 출처",
            sourceUrl = null,
            lastVerifiedAt = null,
            status = "NEEDS_VERIFICATION",
            district = "마포구",
            syncedAt = 1L,
        )
    }
}

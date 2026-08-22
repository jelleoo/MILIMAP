package com.example.milipercent.data

import com.example.milipercent.data.local.BenefitEntity
import com.example.milipercent.data.local.BenefitLocalDataSource
import com.example.milipercent.data.local.BenefitSourceType
import com.example.milipercent.data.local.MMA_SOURCE_TYPE
import com.example.milipercent.model.Benefit
import com.example.milipercent.model.BenefitPage
import com.example.milipercent.model.CollectionProgress
import com.example.milipercent.network.BenefitPageSource
import java.io.IOException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class BenefitRepositoryTest {
    @Test
    fun `첫 페이지를 재요청하지 않고 모든 페이지를 순차 수집한다`() = runBlocking {
        val source = FakePageSource()
        val progress = mutableListOf<CollectionProgress>()

        val result = repository(source).collectAllBenefits(progress::add)

        assertEquals(listOf(1, 2, 3), source.requestedPages)
        assertEquals((1..250).toList(), result.benefits.map(Benefit::id))
        assertEquals(listOf(1, 2, 3), progress.map(CollectionProgress::currentPage))
        assertEquals(listOf(100, 200, 250), progress.map(CollectionProgress::collectedCount))
        assertEquals(250, result.apiTotalCount)
        assertEquals(100, result.pageSize)
        assertEquals(3, result.totalPages)
    }

    @Test
    fun `일시 실패한 페이지를 재시도한 뒤 계속 수집한다`() = runBlocking {
        val source = FakePageSource(failuresByPage = mutableMapOf(2 to 1))

        repository(source).collectAllBenefits()

        assertEquals(listOf(1, 2, 2, 3), source.requestedPages)
    }

    @Test
    fun `추가 재시도 후에도 실패하면 전체 수집을 실패 처리한다`() {
        val source = FakePageSource(failuresByPage = mutableMapOf(2 to Int.MAX_VALUE))

        assertThrows(BenefitPageCollectionException::class.java) {
            runBlocking { repository(source).collectAllBenefits() }
        }

        assertEquals(listOf(1, 2, 2, 2), source.requestedPages)
    }

    @Test
    fun `전체 API에서 서울 데이터만 변환해 로컬 저장소를 교체한다`() = runBlocking {
        val source = SinglePageSource(
            listOf(
                Benefit(10, "마포 가게", "서울특별시 마포구 월드컵로 1", "02-1", "할인"),
                Benefit(20, "강남 가게", "서울시 강남구 테헤란로 2", "02-2", "면제"),
                Benefit(30, "경기 가게", "경기도 성남시 분당구", "031-3", "할인"),
            ),
        )
        val local = FakeLocalDataSource()
        val repository = BenefitRepository(source, local) { 123_456L }

        val result = repository.refreshBenefits()

        assertEquals(3, result.analysis.collectedCount)
        assertEquals(2, result.analysis.seoulBenefits.size)
        assertEquals(2, result.roomStoredCount)
        assertEquals(1, local.replaceCallCount)
        assertEquals(MMA_SOURCE_TYPE, local.replacedSourceType)
        assertEquals(listOf(10, 20), local.current.mapNotNull(BenefitEntity::sourceRowNumber).sorted())
        assertTrue(local.current.all { it.id.startsWith("mma_") })
        assertTrue(local.current.all { it.sourceType == MMA_SOURCE_TYPE })
        assertTrue(local.current.all { it.syncedAt == 123_456L })
        assertTrue(local.current.all { it.latitude == null && it.longitude == null })
        assertEquals(setOf("마포구", "강남구"), local.current.map { it.district }.toSet())
    }

    @Test
    fun `일부 페이지 수집 실패 시 기존 캐시를 교체하지 않는다`() {
        val old = entity(id = "mma_old", sourceRowNumber = 999, name = "기존 가게")
        val local = FakeLocalDataSource(listOf(old))
        val source = FakePageSource(failuresByPage = mutableMapOf(2 to Int.MAX_VALUE))

        assertThrows(BenefitPageCollectionException::class.java) {
            runBlocking { BenefitRepository(source, local).refreshBenefits() }
        }

        assertEquals(0, local.replaceCallCount)
        assertEquals(listOf(old), local.current)
    }

    @Test
    fun `캐시 관찰은 API 응답을 기다리거나 호출하지 않는다`() = runBlocking {
        val cached = entity(id = "mma_cached", sourceRowNumber = 1, name = "저장된 가게")
        val local = FakeLocalDataSource(listOf(cached))
        val source = FakePageSource()

        val observed = BenefitRepository(source, local).observeBenefits().first()

        assertEquals(1, observed.size)
        assertEquals("mma_cached", observed.single().id)
        assertEquals("저장된 가게", observed.single().name)
        assertNull(observed.single().latitude)
        assertTrue(source.requestedPages.isEmpty())
    }

    @Test
    fun `상세 관찰은 ID에 해당하는 로컬 데이터만 반환하고 API를 호출하지 않는다`() = runBlocking {
        val cached = entity(id = "mma_detail", sourceRowNumber = 7, name = "상세 가게")
        val local = FakeLocalDataSource(listOf(cached))
        val source = FakePageSource()

        val observed = BenefitRepository(source, local)
            .observeBenefitById("mma_detail")
            .first()

        requireNotNull(observed)
        assertEquals("mma_detail", observed.id)
        assertEquals("상세 가게", observed.name)
        assertEquals(MMA_SOURCE_TYPE, observed.sourceType)
        assertTrue(source.requestedPages.isEmpty())
    }

    @Test
    fun `MMA Refresh는 MANUAL_SEED와 MANUAL_LOCAL을 유지한다`() = runBlocking {
        val seed = entity("manual_seed_keep", null, "Seed", BenefitSourceType.MANUAL_SEED)
        val localItem = entity("manual_local_keep", null, "Local", BenefitSourceType.MANUAL_LOCAL)
        val local = FakeLocalDataSource(listOf(seed, localItem))
        val source = SinglePageSource(
            listOf(Benefit(1, "새 MMA", "서울특별시 강남구 테스트로 1", null, "할인")),
        )

        BenefitRepository(source, local).refreshBenefits()

        assertTrue(local.current.any { it.id == seed.id })
        assertTrue(local.current.any { it.id == localItem.id })
        assertEquals(1, local.current.count { it.sourceType == BenefitSourceType.MMA_API.name })
    }

    @Test
    fun `사용자 Flow는 세 source를 합치고 ENDED를 제외한다`() = runBlocking {
        val local = FakeLocalDataSource(
            listOf(
                entity("mma", 1, "MMA", BenefitSourceType.MMA_API),
                entity("seed", null, "Seed", BenefitSourceType.MANUAL_SEED, status = "ACTIVE"),
                entity("local", null, "Local", BenefitSourceType.MANUAL_LOCAL, status = "NEEDS_VERIFICATION"),
                entity("ended", null, "Ended", BenefitSourceType.MANUAL_LOCAL, status = "ENDED"),
            ),
        )

        val ids = BenefitRepository(FakePageSource(), local).observeBenefits().first().map { it.id }

        assertEquals(setOf("mma", "seed", "local"), ids.toSet())
    }

    private fun repository(source: BenefitPageSource): BenefitRepository =
        BenefitRepository(source, FakeLocalDataSource())

    private class FakePageSource(
        private val failuresByPage: MutableMap<Int, Int> = mutableMapOf(),
    ) : BenefitPageSource {
        val requestedPages = mutableListOf<Int>()

        override suspend fun getBenefitPage(pageNo: Int, numOfRows: Int): BenefitPage {
            requestedPages += pageNo
            val remainingFailures = failuresByPage[pageNo] ?: 0
            if (remainingFailures > 0) {
                failuresByPage[pageNo] = remainingFailures - 1
                throw IOException("테스트용 네트워크 오류")
            }

            val start = (pageNo - 1) * numOfRows + 1
            val end = minOf(pageNo * numOfRows, TOTAL_COUNT)
            val benefits = if (start <= end) {
                (start..end).map { rowNumber ->
                    Benefit(
                        id = rowNumber,
                        name = "가게 $rowNumber",
                        address = "주소 $rowNumber",
                        phone = null,
                        benefitType = "할인",
                    )
                }
            } else {
                emptyList()
            }

            return BenefitPage(
                benefits = benefits,
                pageNo = pageNo,
                numOfRows = numOfRows,
                totalCount = TOTAL_COUNT,
            )
        }

        private companion object {
            const val TOTAL_COUNT = 250
        }
    }

    private class SinglePageSource(
        private val benefits: List<Benefit>,
    ) : BenefitPageSource {
        override suspend fun getBenefitPage(pageNo: Int, numOfRows: Int) = BenefitPage(
            benefits = benefits,
            pageNo = pageNo,
            numOfRows = numOfRows,
            totalCount = benefits.size,
        )
    }

    private class FakeLocalDataSource(
        initial: List<BenefitEntity> = emptyList(),
    ) : BenefitLocalDataSource {
        private val state = MutableStateFlow(initial)
        var replaceCallCount = 0
            private set
        var replacedSourceType: String? = null
            private set
        val current: List<BenefitEntity>
            get() = state.value

        override fun observeBenefits(sourceType: String): Flow<List<BenefitEntity>> =
            state.map { benefits -> benefits.filter { it.sourceType == sourceType } }

        override fun observeUserVisibleBenefits(): Flow<List<BenefitEntity>> =
            state.map { benefits -> benefits.filter { it.status != "ENDED" } }

        override fun observeBenefitById(id: String): Flow<BenefitEntity?> =
            state.map { benefits -> benefits.firstOrNull { it.id == id } }

        override suspend fun replaceBenefits(
            sourceType: String,
            benefits: List<BenefitEntity>,
        ) {
            replaceCallCount += 1
            replacedSourceType = sourceType
            state.value = state.value.filterNot { it.sourceType == sourceType } + benefits
        }

        override suspend fun countBenefits(sourceType: String): Int =
            state.value.count { it.sourceType == sourceType }

        override suspend fun upsertBenefit(benefit: BenefitEntity) {
            state.value = state.value.filterNot { it.id == benefit.id } + benefit
        }

        override suspend fun deleteBenefit(id: String, sourceType: String): Boolean {
            val oldSize = state.value.size
            state.value = state.value.filterNot { it.id == id && it.sourceType == sourceType }
            return state.value.size != oldSize
        }
    }

    private companion object {
        fun entity(
            id: String,
            sourceRowNumber: Int?,
            name: String,
            sourceType: BenefitSourceType = BenefitSourceType.MMA_API,
            status: String? = null,
        ) = BenefitEntity(
            id = id,
            sourceType = sourceType.name,
            sourceRowNumber = sourceRowNumber,
            name = name,
            address = "서울특별시 마포구",
            phone = null,
            benefitType = "할인",
            district = "마포구",
            latitude = null,
            longitude = null,
            syncedAt = 1L,
            status = status,
        )
    }
}

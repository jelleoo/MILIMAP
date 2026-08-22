package com.example.milipercent.data

import com.example.milipercent.analysis.BenefitAnalysisResult
import com.example.milipercent.analysis.BenefitAnalyzer
import com.example.milipercent.data.local.BenefitEntity
import com.example.milipercent.data.local.BenefitLocalDataSource
import com.example.milipercent.data.local.MMA_SOURCE_TYPE
import com.example.milipercent.data.local.toDetail
import com.example.milipercent.data.local.toEntity
import com.example.milipercent.data.local.toUiModel
import com.example.milipercent.model.BenefitCollection
import com.example.milipercent.model.BenefitDetail
import com.example.milipercent.model.BenefitPage
import com.example.milipercent.model.BenefitUiModel
import com.example.milipercent.model.CollectionProgress
import com.example.milipercent.network.BenefitPageSource
import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

interface BenefitDataRepository {
    fun observeBenefits(): Flow<List<BenefitUiModel>>

    fun observeBenefitById(id: String): Flow<BenefitDetail?>

    suspend fun refreshBenefits(
        onProgress: (CollectionProgress) -> Unit = {},
    ): BenefitSyncResult
}

class BenefitRepository(
    private val apiClient: BenefitPageSource,
    private val localDataSource: BenefitLocalDataSource,
    private val currentTimeMillis: () -> Long = System::currentTimeMillis,
) : BenefitDataRepository {
    override fun observeBenefits(): Flow<List<BenefitUiModel>> =
        localDataSource.observeUserVisibleBenefits()
            .map { entities -> entities.map { it.toUiModel() } }

    override fun observeBenefitById(id: String): Flow<BenefitDetail?> =
        localDataSource.observeBenefitById(id)
            .map { entity -> entity?.toDetail() }

    override suspend fun refreshBenefits(
        onProgress: (CollectionProgress) -> Unit,
    ): BenefitSyncResult {
        // DB에는 전국 페이지 수집과 분석이 모두 끝난 뒤에만 접근한다.
        val collection = collectAllBenefits(onProgress)
        val analysis = BenefitAnalyzer.analyze(collection)
        val syncedAt = currentTimeMillis()
        // 완전히 같은 API 행은 첫 항목을 유지하고, 서로 다른 행의 stable ID 충돌은 거부한다.
        val seoulEntities = analysis.seoulBenefits
            .distinct()
            .map { it.toEntity(syncedAt) }
        val collidingIds = seoulEntities
            .groupBy(BenefitEntity::id)
            .filterValues { entities -> entities.size > 1 }
            .keys
        if (collidingIds.isNotEmpty()) {
            throw BenefitIdentityCollisionException(collidingIds.size)
        }

        localDataSource.replaceBenefits(
            sourceType = MMA_SOURCE_TYPE,
            benefits = seoulEntities,
        )
        val roomStoredCount = localDataSource.countBenefits(MMA_SOURCE_TYPE)
        if (roomStoredCount != seoulEntities.size) {
            throw BenefitStorageCountMismatchException(
                expectedCount = seoulEntities.size,
                actualCount = roomStoredCount,
            )
        }

        return BenefitSyncResult(
            analysis = analysis,
            roomStoredCount = roomStoredCount,
        )
    }

    suspend fun collectAllBenefits(
        onProgress: (CollectionProgress) -> Unit = {},
    ): BenefitCollection {
        // 첫 페이지에서 실제 totalCount와 서버가 적용한 page size를 확인한다.
        val firstPage = requestPageWithRetry(pageNo = 1)
        val effectivePageSize = firstPage.numOfRows
        val totalPages = calculateTotalPages(firstPage.totalCount, effectivePageSize)
        val allBenefits = firstPage.benefits.toMutableList()

        onProgress(
            CollectionProgress(
                currentPage = 1,
                totalPages = totalPages,
                collectedCount = allBenefits.size,
            ),
        )

        // 첫 페이지는 이미 받았으므로 2페이지부터 순차적으로 요청한다.
        for (pageNo in 2..totalPages) {
            val page = requestPageWithRetry(pageNo)
            if (page.totalCount != firstPage.totalCount) {
                throw IncompleteBenefitCollectionException(
                    expectedCount = firstPage.totalCount,
                    actualCount = allBenefits.size,
                    detail = "수집 도중 API totalCount가 변경되었습니다.",
                )
            }
            allBenefits += page.benefits
            onProgress(
                CollectionProgress(
                    currentPage = pageNo,
                    totalPages = totalPages,
                    collectedCount = allBenefits.size,
                ),
            )
        }

        if (allBenefits.size != firstPage.totalCount) {
            throw IncompleteBenefitCollectionException(
                expectedCount = firstPage.totalCount,
                actualCount = allBenefits.size,
                detail = "API가 알린 전체 건수와 실제 수집 건수가 다릅니다.",
            )
        }

        return BenefitCollection(
            benefits = allBenefits,
            apiTotalCount = firstPage.totalCount,
            pageSize = effectivePageSize,
            totalPages = totalPages,
        )
    }

    private suspend fun requestPageWithRetry(pageNo: Int): BenefitPage {
        var lastFailure: Throwable? = null

        repeat(TOTAL_ATTEMPTS) { attemptIndex ->
            try {
                val page = apiClient.getBenefitPage(pageNo, REQUEST_PAGE_SIZE)
                if (page.pageNo != pageNo) {
                    throw IOException(
                        "요청한 페이지($pageNo)와 응답 페이지(${page.pageNo})가 다릅니다.",
                    )
                }
                return page
            } catch (exception: CancellationException) {
                throw exception
            } catch (exception: Exception) {
                lastFailure = exception
                if (attemptIndex < TOTAL_ATTEMPTS - 1) {
                    delay(RETRY_DELAY_MILLIS)
                }
            }
        }

        throw BenefitPageCollectionException(
            pageNo = pageNo,
            attempts = TOTAL_ATTEMPTS,
            cause = lastFailure,
        )
    }

    private fun calculateTotalPages(totalCount: Int, pageSize: Int): Int {
        if (totalCount == 0) return 1
        return (totalCount + pageSize - 1) / pageSize
    }

    companion object {
        const val REQUEST_PAGE_SIZE = 100
        const val ADDITIONAL_RETRY_COUNT = 2
        private const val TOTAL_ATTEMPTS = ADDITIONAL_RETRY_COUNT + 1
        private const val RETRY_DELAY_MILLIS = 500L
    }
}

data class BenefitSyncResult(
    val analysis: BenefitAnalysisResult,
    val roomStoredCount: Int,
)

class BenefitPageCollectionException(
    pageNo: Int,
    attempts: Int,
    cause: Throwable?,
) : IOException("${pageNo}페이지 수집에 실패했습니다. (${attempts}회 시도)", cause)

class IncompleteBenefitCollectionException(
    expectedCount: Int,
    actualCount: Int,
    detail: String,
) : IOException("$detail (예상: $expectedCount, 실제: $actualCount)")

class BenefitIdentityCollisionException(
    collisionCount: Int,
) : IOException("서로 다른 MMA 행의 stable ID가 충돌했습니다. (충돌 ID: ${collisionCount}개)")

class BenefitStorageCountMismatchException(
    expectedCount: Int,
    actualCount: Int,
) : IOException("Room 저장 건수가 올바르지 않습니다. (예상: $expectedCount, 실제: $actualCount)")

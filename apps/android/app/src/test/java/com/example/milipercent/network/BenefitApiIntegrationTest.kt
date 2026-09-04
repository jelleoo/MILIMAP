package com.example.milipercent.network

import com.example.milipercent.analysis.BenefitAnalyzer
import com.example.milipercent.data.BenefitRepository
import com.example.milipercent.data.local.BenefitEntity
import com.example.milipercent.data.local.BenefitLocalDataSource
import java.io.File
import java.util.Properties
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test

class BenefitApiIntegrationTest {
    @Test
    fun `실제 API의 전체 페이지를 수집하고 서울 데이터를 분석한다`() = runBlocking {
        assumeTrue(System.getenv(RUN_TEST_ENVIRONMENT) == "true")

        val propertiesFile = sequenceOf(
            File("local.properties"),
            File("../local.properties"),
        ).firstOrNull(File::isFile) ?: error("local.properties를 찾을 수 없습니다.")
        val properties = Properties().apply {
            propertiesFile.inputStream().use(::load)
        }
        val apiClient = BenefitApiClient(
            apiUrl = properties.getProperty("MMA_API_URL").orEmpty(),
            serviceKey = properties.getProperty("MMA_SERVICE_KEY").orEmpty(),
            xmlParser = BenefitXmlParser(),
        )
        val repository = BenefitRepository(apiClient, UnusedLocalDataSource)

        val collection = repository.collectAllBenefits()
        val analysis = BenefitAnalyzer.analyze(collection)

        assertEquals(BenefitRepository.REQUEST_PAGE_SIZE, collection.pageSize)
        assertTrue(collection.totalPages > 0)
        assertTrue(collection.benefits.isNotEmpty())
        println(BenefitAnalyzer.createDebugReport(analysis))
    }

    private companion object {
        const val RUN_TEST_ENVIRONMENT = "RUN_MMA_API_TEST"

        object UnusedLocalDataSource : BenefitLocalDataSource {
            override fun observeBenefits(sourceType: String): Flow<List<BenefitEntity>> =
                emptyFlow()

            override fun observeUserVisibleBenefits(): Flow<List<BenefitEntity>> =
                emptyFlow()

            override fun observeBenefitById(id: String): Flow<BenefitEntity?> =
                flowOf(null)

            override suspend fun replaceBenefits(
                sourceType: String,
                benefits: List<BenefitEntity>,
            ) = error("이 통합 테스트에서는 로컬 저장소를 사용하지 않습니다.")

            override suspend fun countBenefits(sourceType: String): Int =
                error("이 통합 테스트에서는 로컬 저장소를 사용하지 않습니다.")

            override suspend fun upsertBenefit(benefit: BenefitEntity) =
                error("이 통합 테스트에서는 로컬 저장소를 사용하지 않습니다.")

            override suspend fun deleteBenefit(id: String, sourceType: String): Boolean =
                error("이 통합 테스트에서는 로컬 저장소를 사용하지 않습니다.")
        }
    }
}

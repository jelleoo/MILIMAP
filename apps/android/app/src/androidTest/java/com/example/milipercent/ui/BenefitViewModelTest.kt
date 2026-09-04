package com.example.milipercent.ui

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.milipercent.analysis.BenefitAnalyzer
import com.example.milipercent.data.BenefitDataRepository
import com.example.milipercent.data.BenefitSyncResult
import com.example.milipercent.model.BenefitCollection
import com.example.milipercent.model.BenefitDetail
import com.example.milipercent.model.BenefitDistrict
import com.example.milipercent.model.BenefitUiModel
import com.example.milipercent.model.CollectionProgress
import com.example.milipercent.data.seed.ManualSeedSyncResult
import com.example.milipercent.data.seed.ManualSeedSynchronizer
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class BenefitViewModelTest {
    @Test
    fun districtSelectionDoesNotRefreshAndSurvivesRoomUpdate() {
        val fakeRepository = FakeBenefitRepository(
            listOf(
                benefit("gangnam", "강남구"),
                benefit("mapo", "마포구"),
                benefit("songpa", "송파구"),
            ),
        )
        lateinit var viewModel: BenefitViewModel

        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            viewModel = BenefitViewModel(fakeRepository)
        }
        awaitSuccess(viewModel) { it.benefits.size == 3 }

        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            viewModel.selectDistrict(BenefitDistrict.GANGNAM)
            viewModel.selectDistrict(BenefitDistrict.MAPO)
            viewModel.selectDistrict(BenefitDistrict.SONGPA)
            viewModel.selectDistrict(BenefitDistrict.MAPO)
            viewModel.updateSearchQuery("가게")
        }

        assertEquals(1, fakeRepository.refreshCallCount)
        val selectedMapo = awaitSuccess(viewModel) {
            it.selectedDistrict == BenefitDistrict.MAPO && it.searchQuery == "가게"
        }
        assertEquals(1, selectedMapo.benefits.size)
        assertTrue(selectedMapo.benefits.all { it.district == "마포구" })

        fakeRepository.benefits.value = fakeRepository.benefits.value +
            benefit("mapo-new", "마포구")

        val refreshedRoom = awaitSuccess(viewModel) {
            it.selectedDistrict == BenefitDistrict.MAPO &&
                it.searchQuery == "가게" &&
                it.benefits.size == 2
        }
        assertEquals(BenefitDistrict.MAPO, refreshedRoom.selectedDistrict)
        assertTrue(refreshedRoom.benefits.all { it.district == "마포구" })
        assertEquals(1, fakeRepository.refreshCallCount)

        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            viewModel.updateSearchQuery("검색결과없음")
        }
        awaitSuccess(viewModel) { it.searchQuery == "검색결과없음" && it.benefits.isEmpty() }

        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            viewModel.clearSearchQuery()
        }
        val cleared = awaitSuccess(viewModel) {
            it.searchQuery.isEmpty() && it.selectedDistrict == BenefitDistrict.MAPO
        }
        assertEquals(2, cleared.benefits.size)
        assertEquals(1, fakeRepository.refreshCallCount)
    }

    @Test
    fun appViewModelSynchronizesSeedOnceWithoutExtraRemoteRefresh() {
        val repository = FakeBenefitRepository(listOf(benefit("mapo", "마포구")))
        val seed = FakeSeedSynchronizer()
        lateinit var viewModel: BenefitViewModel

        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            viewModel = BenefitViewModel(repository, seed)
        }
        awaitSuccess(viewModel) { it.benefits.size == 1 }

        assertEquals(1, seed.callCount)
        assertEquals(1, repository.refreshCallCount)
    }

    private fun awaitSuccess(
        viewModel: BenefitViewModel,
        predicate: (BenefitUiState.Success) -> Boolean,
    ): BenefitUiState.Success = runBlocking {
        withTimeout(5_000L) {
            viewModel.uiState
                .filterIsInstance<BenefitUiState.Success>()
                .first(predicate)
        }
    }

    private class FakeBenefitRepository(
        initialBenefits: List<BenefitUiModel>,
    ) : BenefitDataRepository {
        val benefits = MutableStateFlow(initialBenefits)
        var refreshCallCount = 0
            private set

        override fun observeBenefits(): Flow<List<BenefitUiModel>> = benefits

        override fun observeBenefitById(id: String): Flow<BenefitDetail?> = flowOf(null)

        override suspend fun refreshBenefits(
            onProgress: (CollectionProgress) -> Unit,
        ): BenefitSyncResult {
            refreshCallCount += 1
            val analysis = BenefitAnalyzer.analyze(
                BenefitCollection(
                    benefits = emptyList(),
                    apiTotalCount = 0,
                    pageSize = 100,
                    totalPages = 1,
                ),
            )
            return BenefitSyncResult(
                analysis = analysis,
                roomStoredCount = benefits.value.size,
            )
        }
    }

    private class FakeSeedSynchronizer : ManualSeedSynchronizer {
        var callCount = 0
            private set

        override suspend fun synchronize(): ManualSeedSyncResult {
            callCount += 1
            return ManualSeedSyncResult(storedCount = 0)
        }
    }

    private companion object {
        fun benefit(id: String, district: String) = BenefitUiModel(
            id = id,
            name = "$district 가게",
            address = "서울특별시 $district",
            phone = null,
            benefitType = "할인",
            district = district,
            latitude = null,
            longitude = null,
        )
    }
}

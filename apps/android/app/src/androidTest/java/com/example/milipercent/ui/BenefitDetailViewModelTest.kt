package com.example.milipercent.ui

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.milipercent.data.BenefitDataRepository
import com.example.milipercent.data.BenefitSyncResult
import com.example.milipercent.data.local.MMA_SOURCE_TYPE
import com.example.milipercent.model.BenefitDetail
import com.example.milipercent.model.BenefitUiModel
import com.example.milipercent.model.CollectionProgress
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class BenefitDetailViewModelTest {
    @Test
    fun roomFlowUpdatesDetailThenDeletionBecomesNotFoundWithoutRefresh() {
        val repository = FakeDetailRepository(detail(name = "기존 업체명"))
        lateinit var viewModel: BenefitDetailViewModel

        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            viewModel = BenefitDetailViewModel("mma_detail", repository)
        }

        val initial = awaitState(viewModel) {
            it is BenefitDetailUiState.Success && it.benefit.name == "기존 업체명"
        } as BenefitDetailUiState.Success
        assertEquals("병무청 나라사랑가게", initial.benefit.sourceLabel)
        assertEquals(0, repository.refreshCallCount)

        repository.detail.value = detail(name = "갱신된 업체명")
        val updated = awaitState(viewModel) {
            it is BenefitDetailUiState.Success && it.benefit.name == "갱신된 업체명"
        } as BenefitDetailUiState.Success
        assertEquals("갱신된 업체명", updated.benefit.name)
        assertEquals(0, repository.refreshCallCount)

        repository.detail.value = null
        assertEquals(
            BenefitDetailUiState.NotFound,
            awaitState(viewModel) { it == BenefitDetailUiState.NotFound },
        )
        assertEquals(0, repository.refreshCallCount)
    }

    @Test
    fun blankIdIsNotFoundWithoutRepositoryAccess() {
        val repository = FakeDetailRepository(detail())
        lateinit var viewModel: BenefitDetailViewModel

        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            viewModel = BenefitDetailViewModel("", repository)
        }

        assertEquals(BenefitDetailUiState.NotFound, viewModel.uiState.value)
        assertTrue(repository.observedIds.isEmpty())
        assertEquals(0, repository.refreshCallCount)
    }

    private fun awaitState(
        viewModel: BenefitDetailViewModel,
        predicate: (BenefitDetailUiState) -> Boolean,
    ): BenefitDetailUiState = runBlocking {
        withTimeout(5_000L) {
            viewModel.uiState.filter(predicate).first()
        }
    }

    private class FakeDetailRepository(initial: BenefitDetail?) : BenefitDataRepository {
        val detail = MutableStateFlow(initial)
        val observedIds = mutableListOf<String>()
        var refreshCallCount = 0
            private set

        override fun observeBenefits(): Flow<List<BenefitUiModel>> = flowOf(emptyList())

        override fun observeBenefitById(id: String): Flow<BenefitDetail?> {
            observedIds += id
            return detail
        }

        override suspend fun refreshBenefits(
            onProgress: (CollectionProgress) -> Unit,
        ): BenefitSyncResult {
            refreshCallCount += 1
            error("상세 화면은 refreshBenefits를 호출하면 안 됩니다.")
        }
    }

    private companion object {
        fun detail(name: String = "테스트 업체") = BenefitDetail(
            id = "mma_detail",
            name = name,
            address = "서울특별시 강남구 테헤란로 1",
            phone = "02-1234-5678",
            benefitType = "할인",
            district = "강남구",
            sourceType = MMA_SOURCE_TYPE,
        )
    }
}

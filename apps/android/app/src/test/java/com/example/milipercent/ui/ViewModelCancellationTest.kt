package com.example.milipercent.ui

import com.example.milipercent.analysis.BenefitAnalyzer
import com.example.milipercent.data.BenefitDataRepository
import com.example.milipercent.data.BenefitSyncResult
import com.example.milipercent.data.local.ManualBenefitStatus
import com.example.milipercent.data.manual.ManualBenefitAdminRepository
import com.example.milipercent.data.manual.ManualBenefitInput
import com.example.milipercent.data.manual.ManualBenefitRecord
import com.example.milipercent.data.seed.ManualSeedSyncResult
import com.example.milipercent.data.seed.ManualSeedSynchronizer
import com.example.milipercent.model.BenefitCollection
import com.example.milipercent.model.BenefitDetail
import com.example.milipercent.model.BenefitDistrict
import com.example.milipercent.model.BenefitUiModel
import com.example.milipercent.model.CollectionProgress
import com.example.milipercent.ui.debug.ManualBenefitAdminViewModel
import com.example.milipercent.ui.debug.ManualBenefitFormViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ViewModelCancellationTest {
    @Test
    fun `BenefitViewModel seed 동기화 취소는 coroutine 취소로 전파한다`() = runTest {
        withTestMainDispatcher {
            val synchronizer = CancellingSeedSynchronizer()

            BenefitViewModel(EmptyBenefitRepository, synchronizer)
            runCurrent()

            assertTrue(requireNotNull(synchronizer.job).isCancelled)
        }
    }

    @Test
    fun `Manual form 관찰 취소는 오류 UI로 변환하지 않는다`() = runTest {
        withTestMainDispatcher {
            val repository = CancellingObserveByIdRepository()
            val viewModel = ManualBenefitFormViewModel("manual_local_test", repository)

            runCurrent()

            assertTrue(requireNotNull(repository.job).isCancelled)
            assertNull(viewModel.uiState.value.errorMessage)
        }
    }

    @Test
    fun `Manual form 저장 취소는 오류 UI로 변환하지 않는다`() = runTest {
        withTestMainDispatcher {
            val repository = CancellingCreateRepository()
            val viewModel = ManualBenefitFormViewModel(null, repository)

            viewModel.save(validInput())
            runCurrent()

            assertTrue(requireNotNull(repository.job).isCancelled)
            assertNull(viewModel.uiState.value.errorMessage)
        }
    }

    @Test
    fun `Manual admin 목록 관찰 취소는 오류 UI로 변환하지 않는다`() = runTest {
        withTestMainDispatcher {
            val repository = CancellingObserveAllRepository()
            val viewModel = ManualBenefitAdminViewModel(repository)

            runCurrent()

            assertTrue(requireNotNull(repository.job).isCancelled)
            assertNull(viewModel.uiState.value.errorMessage)
        }
    }

    @Test
    fun `Manual admin 삭제 취소는 오류 UI로 변환하지 않는다`() = runTest {
        withTestMainDispatcher {
            val repository = CancellingDeleteRepository()
            val viewModel = ManualBenefitAdminViewModel(repository)

            runCurrent()
            viewModel.delete("manual_local_test")
            runCurrent()

            assertTrue(requireNotNull(repository.job).isCancelled)
            assertNull(viewModel.uiState.value.errorMessage)
        }
    }

    private suspend fun kotlinx.coroutines.test.TestScope.withTestMainDispatcher(
        block: suspend kotlinx.coroutines.test.TestScope.() -> Unit,
    ) {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        try {
            block()
        } finally {
            Dispatchers.resetMain()
        }
    }

    private class CancellingSeedSynchronizer : ManualSeedSynchronizer {
        var job: Job? = null

        override suspend fun synchronize(): ManualSeedSyncResult {
            job = currentCoroutineContext()[Job]
            throw CancellationException(TEST_CANCELLATION)
        }
    }

    private abstract class TestManualRepository : ManualBenefitAdminRepository {
        var job: Job? = null

        override fun observeAll(): Flow<List<ManualBenefitRecord>> = flowOf(emptyList())

        override fun observeById(id: String): Flow<ManualBenefitRecord?> = flowOf(null)

        override suspend fun create(input: ManualBenefitInput): String = "manual_local_test"

        override suspend fun update(id: String, input: ManualBenefitInput) = Unit

        override suspend fun delete(id: String): Boolean = true

        suspend fun cancel(): Nothing {
            job = currentCoroutineContext()[Job]
            throw CancellationException(TEST_CANCELLATION)
        }
    }

    private class CancellingObserveByIdRepository : TestManualRepository() {
        override fun observeById(id: String): Flow<ManualBenefitRecord?> = flow { cancel() }
    }

    private class CancellingCreateRepository : TestManualRepository() {
        override suspend fun create(input: ManualBenefitInput): String = cancel()
    }

    private class CancellingObserveAllRepository : TestManualRepository() {
        override fun observeAll(): Flow<List<ManualBenefitRecord>> = flow { cancel() }
    }

    private class CancellingDeleteRepository : TestManualRepository() {
        override suspend fun delete(id: String): Boolean = cancel()
    }

    private companion object {
        const val TEST_CANCELLATION = "TEST ONLY cancellation"

        object EmptyBenefitRepository : BenefitDataRepository {
            override fun observeBenefits(): Flow<List<BenefitUiModel>> = flowOf(emptyList())

            override fun observeBenefitById(id: String): Flow<BenefitDetail?> = flowOf(null)

            override suspend fun refreshBenefits(
                onProgress: (CollectionProgress) -> Unit,
            ): BenefitSyncResult = BenefitSyncResult(
                analysis = BenefitAnalyzer.analyze(
                    BenefitCollection(
                        benefits = emptyList(),
                        apiTotalCount = 0,
                        pageSize = 100,
                        totalPages = 1,
                    ),
                ),
                roomStoredCount = 0,
            )
        }

        fun validInput() = ManualBenefitInput(
            name = "TEST ONLY 업체",
            address = "서울특별시 마포구 테스트로 1",
            district = BenefitDistrict.MAPO,
            benefitDescription = "TEST ONLY 혜택",
            verificationMethod = "TEST ONLY",
            lastVerifiedDate = "2026-08-22",
            status = ManualBenefitStatus.ACTIVE,
        )
    }
}

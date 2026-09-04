package com.example.milipercent.ui

import com.example.milipercent.analysis.BenefitAnalyzer
import com.example.milipercent.data.BenefitDataRepository
import com.example.milipercent.data.BenefitSyncResult
import com.example.milipercent.data.account.AccountRepository
import com.example.milipercent.data.admin.AdminBenefitRepository
import com.example.milipercent.data.favorite.FavoriteRepository
import com.example.milipercent.data.seed.BundledSeedInstaller
import com.example.milipercent.data.seed.BundledSeedSyncResult
import com.example.milipercent.data.session.SessionStorage
import com.example.milipercent.model.Benefit
import com.example.milipercent.model.BenefitCollection
import com.example.milipercent.model.BenefitDetail
import com.example.milipercent.data.local.BenefitSourceType
import com.example.milipercent.model.BenefitStatus
import com.example.milipercent.model.BenefitUiModel
import com.example.milipercent.model.CollectionProgress
import com.example.milipercent.model.LocalUser
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class MiliSpotViewModelTest {
    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    @Test
    fun missingMmaKeyStillInstallsSeedAndShowsCachedBenefits() = runTest(dispatcher.scheduler) {
        val seed = FakeSeedInstaller()
        val repository = FakeBenefitRepository(listOf(benefit("seed-1")))

        val viewModel = MiliSpotViewModel(repository, FakeAccountRepository(), FakeFavoriteRepository(), FakeAdminRepository(), seed, FakeSessionStorage(), mmaConfigured = false)
        advanceUntilIdle()

        assertEquals(1, seed.calls)
        assertEquals(0, repository.refreshCalls)
        assertEquals(listOf("seed-1"), viewModel.uiState.value.visibleBenefits.map { it.benefit.id })
    }

    @Test
    fun staleSessionIsClearedAndRefreshFailureKeepsCachedRows() = runTest(dispatcher.scheduler) {
        val session = FakeSessionStorage(42)
        val repository = FakeBenefitRepository(listOf(benefit("cached")), refreshError = IllegalStateException("offline"))

        val viewModel = MiliSpotViewModel(repository, FakeAccountRepository(), FakeFavoriteRepository(), FakeAdminRepository(), FakeSeedInstaller(), session, mmaConfigured = true)
        advanceUntilIdle()

        assertEquals(null, session.userId())
        assertEquals(null, viewModel.uiState.value.user)
        assertTrue(viewModel.uiState.value.refreshFailed)
        assertEquals(listOf("cached"), viewModel.uiState.value.visibleBenefits.map { it.benefit.id })
    }

    private class FakeSessionStorage(initial: Long? = null) : SessionStorage {
        private var id = initial
        override fun userId(): Long? = id
        override fun save(user: LocalUser) { id = user.id }
        override fun clear() { id = null }
    }

    private class FakeSeedInstaller : BundledSeedInstaller {
        var calls = 0
        override suspend fun synchronizeIfNeeded(): BundledSeedSyncResult {
            calls += 1
            return BundledSeedSyncResult(false, 1)
        }
    }

    private class FakeBenefitRepository(
        benefits: List<Benefit>,
        private val refreshError: Throwable? = null,
    ) : BenefitDataRepository {
        private val domain = MutableStateFlow(benefits)
        var refreshCalls = 0
        override fun observeBenefits(): Flow<List<BenefitUiModel>> = emptyFlow()
        override fun observeDomainBenefits(): Flow<List<Benefit>> = domain
        override fun observeBenefitById(id: String): Flow<BenefitDetail?> = flowOf(null)
        override suspend fun refreshBenefits(onProgress: (CollectionProgress) -> Unit): BenefitSyncResult {
            refreshCalls += 1
            throw requireNotNull(refreshError)
        }
    }

    private class FakeAccountRepository : AccountRepository {
        override fun observeUser(id: Long): Flow<LocalUser?> = flowOf(null)
        override suspend fun register(email: String, displayName: String, password: String) = Result.failure<LocalUser>(UnsupportedOperationException())
        override suspend fun login(email: String, password: String) = Result.failure<LocalUser>(UnsupportedOperationException())
    }
    private class FakeFavoriteRepository : FavoriteRepository {
        override fun observeIds(userId: Long) = flowOf(emptySet<String>())
        override suspend fun toggle(userId: Long, benefitId: String) = false
    }
    private class FakeAdminRepository : AdminBenefitRepository {
        override fun observeAll(): Flow<List<Benefit>> = flowOf(emptyList())
        override suspend fun create(input: com.example.milipercent.data.admin.AdminBenefitInput) = ""
        override suspend fun update(id: String, input: com.example.milipercent.data.admin.AdminBenefitInput) = Unit
        override suspend fun end(id: String) = Unit
        override suspend fun deleteManual(id: String) = false
    }

    private companion object {
        fun benefit(id: String) = Benefit(id, "혜택", "서울특별시 마포구", 37.5, 126.9, "기타", "할인", "설명", null, null, null, null, BenefitSourceType.LOCAL_GOV, "테스트", null, null, BenefitStatus.ACTIVE, "마포구")
    }
}

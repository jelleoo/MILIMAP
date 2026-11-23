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
import com.example.milipercent.model.BenefitDistrict
import com.example.milipercent.model.BenefitUiModel
import com.example.milipercent.model.CollectionProgress
import com.example.milipercent.model.GeoBounds
import com.example.milipercent.model.GeoPoint
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

    @Test
    fun discoverEventsRetainFiltersAndRequireLoginBeforeFavoriting() = runTest(dispatcher.scheduler) {
        val favorites = FakeFavoriteRepository()
        val viewModel = MiliSpotViewModel(
            FakeBenefitRepository(listOf(benefit("mapo"))),
            FakeAccountRepository(),
            favorites,
            FakeAdminRepository(),
            FakeSeedInstaller(),
            FakeSessionStorage(),
            mmaConfigured = false,
        )
        advanceUntilIdle()

        viewModel.updateSearchText("마포")
        viewModel.submitSearch()
        viewModel.selectCategory("기타")
        viewModel.selectDistrict(BenefitDistrict.MAPO)
        viewModel.selectBenefit("mapo")
        viewModel.toggleFavorite("mapo")
        advanceUntilIdle()

        assertEquals("마포", viewModel.uiState.value.activeSearch)
        assertEquals("기타", viewModel.uiState.value.selectedCategory)
        assertEquals(BenefitDistrict.MAPO, viewModel.uiState.value.selectedDistrict)
        assertEquals("mapo", viewModel.uiState.value.selectedBenefit?.id)
        assertEquals(AppDestination.ACCOUNT, viewModel.uiState.value.destination)
        assertEquals("찜을 저장하려면 먼저 로그인해 주세요.", viewModel.uiState.value.transientMessage)
        assertEquals(0, favorites.toggleCalls)
    }

    @Test
    fun initialStateKeepsMapCleanUntilCategoryOrSearch() = runTest(dispatcher.scheduler) {
        val viewModel = MiliSpotViewModel(
            FakeBenefitRepository(listOf(benefit("seed-1"))),
            FakeAccountRepository(),
            FakeFavoriteRepository(),
            FakeAdminRepository(),
            FakeSeedInstaller(),
            FakeSessionStorage(),
            mmaConfigured = false,
        )
        advanceUntilIdle()

        assertFalse(viewModel.uiState.value.showMapMarkers)
        assertTrue(viewModel.uiState.value.mapBenefits.isEmpty())
        assertEquals(listOf("seed-1"), viewModel.uiState.value.visibleBenefits.map { it.benefit.id })

        viewModel.selectCategory("기타")
        assertTrue(viewModel.uiState.value.showMapMarkers)
        assertEquals(listOf("seed-1"), viewModel.uiState.value.mapBenefits.map { it.id })
    }

    @Test
    fun searchMovesCameraToMatchedBenefitInsteadOfSeoulCenter() = runTest(dispatcher.scheduler) {
        val ddcBenefit = benefit(
            id = "ddc-1",
            name = "동두천 맛집",
            address = "경기도 동두천시 평화로 1",
            lat = 37.9035,
            lng = 127.0555,
            category = "음식",
            district = "동두천시",
        )
        val viewModel = MiliSpotViewModel(
            FakeBenefitRepository(listOf(ddcBenefit)),
            FakeAccountRepository(),
            FakeFavoriteRepository(),
            FakeAdminRepository(),
            FakeSeedInstaller(),
            FakeSessionStorage(),
            mmaConfigured = false,
        )
        advanceUntilIdle()

        viewModel.updateSearchText("동두천 맛집")
        viewModel.submitSearch()

        assertTrue(viewModel.uiState.value.showMapMarkers)
        assertEquals(GeoPoint(37.9035, 127.0555), viewModel.uiState.value.center)
        assertEquals(MapCameraTarget.Point(GeoPoint(37.9035, 127.0555), SINGLE_RESULT_ZOOM), viewModel.uiState.value.cameraTarget)
    }

    @Test
    fun userMapGestureEnablesSearchInMapBoundsAndAppliesViewportFilter() = runTest(dispatcher.scheduler) {
        val seoulItem = benefit("seoul-1", name = "서울 카페", address = "서울", lat = 37.56, lng = 126.97, category = "카페", district = "중구")
        val pajuItem = benefit("paju-1", name = "파주 카페", address = "파주", lat = 37.76, lng = 126.77, category = "카페", district = "파주시")
        val viewModel = MiliSpotViewModel(
            FakeBenefitRepository(listOf(seoulItem, pajuItem)),
            FakeAccountRepository(),
            FakeFavoriteRepository(),
            FakeAdminRepository(),
            FakeSeedInstaller(),
            FakeSessionStorage(),
            mmaConfigured = false,
        )
        advanceUntilIdle()

        val pajuBounds = GeoBounds(37.74, 126.75, 37.78, 126.80)
        viewModel.onMapCameraIdle(GeoPoint(37.76, 126.77), pajuBounds, byUserGesture = true)
        assertTrue(viewModel.uiState.value.isSearchInMapBoundsAvailable)

        viewModel.searchInCurrentMapBounds()
        assertFalse(viewModel.uiState.value.isSearchInMapBoundsAvailable)
        assertTrue(viewModel.uiState.value.showMapMarkers)
        assertEquals(listOf("paju-1"), viewModel.uiState.value.visibleBenefits.map { it.benefit.id })
        assertEquals(listOf("paju-1"), viewModel.uiState.value.mapBenefits.map { it.id })
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
        var toggleCalls = 0
        override fun observeIds(userId: Long) = flowOf(emptySet<String>())
        override suspend fun toggle(userId: Long, benefitId: String): Boolean {
            toggleCalls += 1
            return false
        }
    }
    private class FakeAdminRepository : AdminBenefitRepository {
        override fun observeAll(): Flow<List<Benefit>> = flowOf(emptyList())
        override suspend fun create(input: com.example.milipercent.data.admin.AdminBenefitInput) = ""
        override suspend fun update(id: String, input: com.example.milipercent.data.admin.AdminBenefitInput) = Unit
        override suspend fun end(id: String) = Unit
        override suspend fun deleteManual(id: String) = false
    }

    private companion object {
        fun benefit(
            id: String,
            name: String = "혜택",
            address: String = "서울특별시 마포구",
            lat: Double = 37.5,
            lng: Double = 126.9,
            category: String = "기타",
            district: String = "마포구",
        ) = Benefit(id, name, address, lat, lng, category, "할인", "설명", null, null, null, null, BenefitSourceType.LOCAL_GOV, "테스트", null, null, BenefitStatus.ACTIVE, district)
    }
}

package com.example.milipercent.ui

import com.example.milipercent.analysis.BenefitAnalyzer
import com.example.milipercent.data.BenefitDataRepository
import com.example.milipercent.data.BenefitSyncResult
import com.example.milipercent.data.account.AccountRepository
import com.example.milipercent.data.admin.AdminBenefitInput
import com.example.milipercent.data.admin.AdminBenefitRepository
import com.example.milipercent.data.favorite.FavoriteRepository
import com.example.milipercent.data.local.BenefitSourceType
import com.example.milipercent.data.seed.BundledSeedInstaller
import com.example.milipercent.data.seed.BundledSeedSyncResult
import com.example.milipercent.data.session.SessionStorage
import com.example.milipercent.location.LocationDataSource
import com.example.milipercent.location.LocationUpdate
import com.example.milipercent.model.Benefit
import com.example.milipercent.model.BenefitCollection
import com.example.milipercent.model.BenefitDetail
import com.example.milipercent.model.BenefitStatus
import com.example.milipercent.model.BenefitUiModel
import com.example.milipercent.model.CollectionProgress
import com.example.milipercent.model.GeoBounds
import com.example.milipercent.model.GeoPoint
import com.example.milipercent.model.LocalUser
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
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
class LocationViewModelTest {
    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    @Test
    fun passiveFixUpdatesDistanceOriginWithoutMovingCameraAndStopCancelsCollection() = runTest(dispatcher.scheduler) {
        val source = FakeLocationSource()
        val viewModel = viewModel()
        viewModel.startLocationTracking(source)
        advanceUntilIdle()
        source.emit(LocationUpdate.Position(GeoPoint(37.55, 126.92)))
        advanceUntilIdle()

        assertEquals(GeoPoint(37.55, 126.92), viewModel.uiState.value.currentLocation)
        assertEquals(0, viewModel.uiState.value.cameraRequestId)

        viewModel.stopLocationTracking()
        source.emit(LocationUpdate.Position(GeoPoint(37.56, 126.93)))
        advanceUntilIdle()
        assertEquals(GeoPoint(37.55, 126.92), viewModel.uiState.value.currentLocation)
    }

    @Test
    fun pendingFocusUsesFirstFreshFixAndUnavailableKeepsSearchStateUntilResolved() = runTest(dispatcher.scheduler) {
        val source = FakeLocationSource()
        val viewModel = viewModel()
        viewModel.updateSearchText("마포")
        viewModel.submitSearch()
        val searchCameraRequestId = viewModel.uiState.value.cameraRequestId
        assertFalse(viewModel.requestCurrentLocationFocus())
        viewModel.startLocationTracking(source)
        advanceUntilIdle()
        source.emit(LocationUpdate.Unavailable("위치를 찾을 수 없습니다."))
        advanceUntilIdle()

        assertEquals("마포", viewModel.uiState.value.activeSearch)
        assertTrue(viewModel.uiState.value.transientMessage?.contains("위치를 찾을 수 없습니다.") == true)

        source.emit(LocationUpdate.Position(GeoPoint(37.55, 126.92)))
        advanceUntilIdle()

        assertEquals("", viewModel.uiState.value.activeSearch)
        assertEquals("", viewModel.uiState.value.searchText)
        assertFalse(viewModel.uiState.value.showMapMarkers)
        assertEquals(GeoPoint(37.55, 126.92), viewModel.uiState.value.center)
        assertEquals(MapCameraTarget.Point(GeoPoint(37.55, 126.92), CURRENT_LOCATION_ZOOM), viewModel.uiState.value.cameraTarget)
        assertEquals(searchCameraRequestId + 1, viewModel.uiState.value.cameraRequestId)
    }

    @Test
    fun currentLocationFocusClearsPreviousSearchAndSubsequentCategoryShowsViewportMarkers() = runTest(dispatcher.scheduler) {
        val foodHere = benefit("food-here", "내주변 식당", "음식", 37.551, 126.921)
        val foodFar = benefit("food-far", "먼 식당", "음식", 37.905, 127.055)
        val cafeHere = benefit("cafe-here", "내주변 카페", "카페", 37.552, 126.922)
        val source = FakeLocationSource()
        val viewModel = viewModel(listOf(foodHere, foodFar, cafeHere))
        viewModel.startLocationTracking(source)
        advanceUntilIdle()
        source.emit(LocationUpdate.Position(GeoPoint(37.55, 126.92)))
        advanceUntilIdle()

        viewModel.updateSearchText("먼 식당")
        viewModel.submitSearch()
        assertTrue(viewModel.uiState.value.showMapMarkers)
        assertEquals(listOf("food-far"), viewModel.uiState.value.visibleBenefits.map { it.benefit.id })

        assertTrue(viewModel.requestCurrentLocationFocus())
        assertEquals("", viewModel.uiState.value.activeSearch)
        assertFalse(viewModel.uiState.value.showMapMarkers)
        assertTrue(viewModel.uiState.value.mapBenefits.isEmpty())

        val myBounds = GeoBounds(37.54, 126.91, 37.56, 126.93)
        viewModel.onMapCameraIdle(GeoPoint(37.55, 126.92), myBounds, byUserGesture = false)
        viewModel.selectCategory("음식")

        assertTrue(viewModel.uiState.value.showMapMarkers)
        assertEquals("음식", viewModel.uiState.value.selectedCategory)
        assertEquals(listOf("food-here"), viewModel.uiState.value.mapBenefits.map { it.id })
    }

    private fun viewModel(benefits: List<Benefit> = emptyList()) = MiliSpotViewModel(
        FakeBenefitRepository(benefits), FakeAccountRepository(), FakeFavoriteRepository(), FakeAdminRepository(),
        FakeSeedInstaller(), FakeSessionStorage(), mmaConfigured = false,
    )

    private fun benefit(id: String, name: String, category: String, lat: Double, lng: Double) = Benefit(
        id, name, "서울", lat, lng, category, "할인", "설명", null, null, null, null,
        BenefitSourceType.LOCAL_GOV, "테스트", null, null, BenefitStatus.ACTIVE, "마포구",
    )

    private class FakeLocationSource : LocationDataSource {
        private val updates = MutableSharedFlow<LocationUpdate>()
        override fun updates(): Flow<LocationUpdate> = updates
        suspend fun emit(update: LocationUpdate) = updates.emit(update)
    }
    private class FakeSeedInstaller : BundledSeedInstaller {
        override suspend fun synchronizeIfNeeded() = BundledSeedSyncResult(false, 0)
    }
    private class FakeSessionStorage : SessionStorage {
        override fun userId(): Long? = null
        override fun save(user: LocalUser) = Unit
        override fun clear() = Unit
    }
    private class FakeBenefitRepository(
        private val benefits: List<Benefit> = emptyList(),
    ) : BenefitDataRepository {
        override fun observeBenefits(): Flow<List<BenefitUiModel>> = emptyFlow()
        override fun observeDomainBenefits(): Flow<List<Benefit>> = flowOf(benefits)
        override fun observeBenefitById(id: String): Flow<BenefitDetail?> = flowOf(null)
        override suspend fun refreshBenefits(onProgress: (CollectionProgress) -> Unit): BenefitSyncResult =
            throw UnsupportedOperationException()
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
        override suspend fun create(input: AdminBenefitInput) = ""
        override suspend fun update(id: String, input: AdminBenefitInput) = Unit
        override suspend fun end(id: String) = Unit
        override suspend fun deleteManual(id: String) = false
    }
}

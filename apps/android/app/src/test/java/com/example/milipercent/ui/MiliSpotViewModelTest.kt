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
import com.example.milipercent.data.sync.BenefitSyncPolicy
import com.example.milipercent.data.sync.InMemoryBenefitSyncPreferences
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

    @Test
    fun cameraIdleRecordsSnapshotAndProgrammaticMoveAdvancesRequestId() = runTest(dispatcher.scheduler) {
        val ddcItem = benefit("ddc-1", name = "동두천 식당", address = "경기도 동두천시", lat = 37.90, lng = 127.05, category = "음식", district = "동두천시")
        val viewModel = MiliSpotViewModel(
            FakeBenefitRepository(listOf(ddcItem)),
            FakeAccountRepository(),
            FakeFavoriteRepository(),
            FakeAdminRepository(),
            FakeSeedInstaller(),
            FakeSessionStorage(),
            mmaConfigured = false,
        )
        advanceUntilIdle()

        viewModel.markCameraRequestApplied(0L)
        val bounds = GeoBounds(37.89, 127.04, 37.91, 127.06)
        viewModel.onMapCameraIdle(GeoPoint(37.90, 127.05), bounds, byUserGesture = true, zoom = 15.0)

        assertEquals(0L, viewModel.uiState.value.appliedCameraRequestId)
        assertEquals(MapCameraSnapshot(GeoPoint(37.90, 127.05), 15.0), viewModel.uiState.value.lastCameraSnapshot)

        viewModel.updateSearchText("동두천")
        viewModel.submitSearch()
        assertTrue(viewModel.uiState.value.cameraRequestId > viewModel.uiState.value.appliedCameraRequestId)
    }

    @Test
    fun savedBenefitsReflectsOnlyActiveFavoritesAndSurvivesFilterChanges() = runTest(dispatcher.scheduler) {
        val activeFav = benefit("fav-1", name = "찜한 맛집", district = "동두천시", category = "음식")
        val endedFav = Benefit(
            "fav-ended", "종료 찜", "서울", 37.5, 126.9, "기타", "할인", "설명", null, null, null, null,
            BenefitSourceType.LOCAL_GOV, "테스트", null, null, BenefitStatus.ENDED, "마포구",
        )
        val notFav = benefit("other-1", name = "비찜 맛집", district = "파주시", category = "음식")
        val user = LocalUser(1L, "user@test.com", "사용자", false)
        val viewModel = MiliSpotViewModel(
            FakeBenefitRepository(listOf(activeFav, endedFav, notFav)),
            FakeAccountRepository(user),
            FakeFavoriteRepository(flowOf(setOf("fav-1", "fav-ended"))),
            FakeAdminRepository(),
            FakeSeedInstaller(),
            FakeSessionStorage(1L),
            mmaConfigured = false,
        )
        advanceUntilIdle()

        assertEquals(listOf("fav-1"), viewModel.uiState.value.savedBenefits.map { it.benefit.id })

        viewModel.selectDistrict(BenefitDistrict.MAPO)
        viewModel.updateSearchText("비찜")
        viewModel.submitSearch()
        assertEquals(listOf("fav-1"), viewModel.uiState.value.savedBenefits.map { it.benefit.id })

        viewModel.logout()
        assertTrue(viewModel.uiState.value.savedBenefits.isEmpty())
    }

    @Test
    fun searchRecomputesDistancesRelativeToResolvedSearchCenter() = runTest(dispatcher.scheduler) {
        val ddcItem = benefit("ddc-1", name = "동두천 단독가게", address = "경기도 동두천시 평화로 10", lat = 37.9035, lng = 127.0555, category = "음식", district = "동두천시")
        val viewModel = MiliSpotViewModel(
            FakeBenefitRepository(listOf(ddcItem)),
            FakeAccountRepository(),
            FakeFavoriteRepository(),
            FakeAdminRepository(),
            FakeSeedInstaller(),
            FakeSessionStorage(),
            mmaConfigured = false,
        )
        advanceUntilIdle()

        viewModel.updateSearchText("동두천 단독가게")
        viewModel.submitSearch()

        val matched = viewModel.uiState.value.visibleBenefits.single()
        assertEquals("ddc-1", matched.benefit.id)
        assertEquals(0.0, matched.distanceKm ?: -1.0, 0.001)
    }

    @Test
    fun startupSkipsAutoRefreshWithinCooldownAndShowsFormattedTimestamp() = runTest(dispatcher.scheduler) {
        val lastSyncedAt = 1_763_900_000_000L
        val now = lastSyncedAt + BenefitSyncPolicy.DEFAULT_AUTO_REFRESH_COOLDOWN_MILLIS - 1_000L
        val syncPrefs = InMemoryBenefitSyncPreferences(initialTimestampMillis = lastSyncedAt)
        val repository = FakeBenefitRepository(listOf(benefit("seed-1")))

        val viewModel = MiliSpotViewModel(
            repository,
            FakeAccountRepository(),
            FakeFavoriteRepository(),
            FakeAdminRepository(),
            FakeSeedInstaller(),
            FakeSessionStorage(),
            mmaConfigured = true,
            syncPreferences = syncPrefs,
            currentTimeMillis = { now },
        )
        advanceUntilIdle()

        assertEquals(0, repository.refreshCalls)
        assertEquals(BenefitSyncPolicy.formatSyncLabel(lastSyncedAt), viewModel.uiState.value.lastSyncLabel)
        assertFalse(viewModel.uiState.value.refreshFailed)
    }

    @Test
    fun startupAutoRefreshesWhenCooldownExpiredAndPersistsNewTimestamp() = runTest(dispatcher.scheduler) {
        val lastSyncedAt = 1_763_800_000_000L
        val now = lastSyncedAt + BenefitSyncPolicy.DEFAULT_AUTO_REFRESH_COOLDOWN_MILLIS
        val syncPrefs = InMemoryBenefitSyncPreferences(initialTimestampMillis = lastSyncedAt)
        val repository = FakeBenefitRepository(listOf(benefit("seed-1")))

        val viewModel = MiliSpotViewModel(
            repository,
            FakeAccountRepository(),
            FakeFavoriteRepository(),
            FakeAdminRepository(),
            FakeSeedInstaller(),
            FakeSessionStorage(),
            mmaConfigured = true,
            syncPreferences = syncPrefs,
            currentTimeMillis = { now },
        )
        advanceUntilIdle()

        assertEquals(1, repository.refreshCalls)
        assertEquals(now, syncPrefs.lastSuccessfulSyncAtMillis())
        assertEquals(BenefitSyncPolicy.formatSyncLabel(now), viewModel.uiState.value.lastSyncLabel)
    }

    @Test
    fun manualRefreshBypassesCooldownAndUpdatesTimestamp() = runTest(dispatcher.scheduler) {
        val lastSyncedAt = 1_763_900_000_000L
        var now = lastSyncedAt + 60_000L
        val syncPrefs = InMemoryBenefitSyncPreferences(initialTimestampMillis = lastSyncedAt)
        val repository = FakeBenefitRepository(listOf(benefit("seed-1")))

        val viewModel = MiliSpotViewModel(
            repository,
            FakeAccountRepository(),
            FakeFavoriteRepository(),
            FakeAdminRepository(),
            FakeSeedInstaller(),
            FakeSessionStorage(),
            mmaConfigured = true,
            syncPreferences = syncPrefs,
            currentTimeMillis = { now },
        )
        advanceUntilIdle()
        assertEquals(0, repository.refreshCalls)

        now += 120_000L
        viewModel.refresh()
        advanceUntilIdle()

        assertEquals(1, repository.refreshCalls)
        assertEquals(now, syncPrefs.lastSuccessfulSyncAtMillis())
        assertEquals(BenefitSyncPolicy.formatSyncLabel(now), viewModel.uiState.value.lastSyncLabel)
    }

    @Test
    fun failedRefreshDoesNotRecordTimestampSoNextStartupRetries() = runTest(dispatcher.scheduler) {
        val syncPrefs = InMemoryBenefitSyncPreferences()
        val failingRepo = FakeBenefitRepository(listOf(benefit("cached")), refreshError = IllegalStateException("offline"))

        MiliSpotViewModel(
            failingRepo,
            FakeAccountRepository(),
            FakeFavoriteRepository(),
            FakeAdminRepository(),
            FakeSeedInstaller(),
            FakeSessionStorage(),
            mmaConfigured = true,
            syncPreferences = syncPrefs,
            currentTimeMillis = { 1_763_900_000_000L },
        )
        advanceUntilIdle()

        assertEquals(1, failingRepo.refreshCalls)
        assertEquals(null, syncPrefs.lastSuccessfulSyncAtMillis())

        val recoveryRepo = FakeBenefitRepository(listOf(benefit("cached")))
        MiliSpotViewModel(
            recoveryRepo,
            FakeAccountRepository(),
            FakeFavoriteRepository(),
            FakeAdminRepository(),
            FakeSeedInstaller(),
            FakeSessionStorage(),
            mmaConfigured = true,
            syncPreferences = syncPrefs,
            currentTimeMillis = { 1_763_900_060_000L },
        )
        advanceUntilIdle()

        assertEquals(1, recoveryRepo.refreshCalls)
        assertEquals(1_763_900_060_000L, syncPrefs.lastSuccessfulSyncAtMillis())
    }

    @Test
    fun logoutCancelsSessionObserverSoLateEmissionCannotResurrectSession() = runTest(dispatcher.scheduler) {
        val user1 = LocalUser(1L, "user1@test.com", "사용자1", false)
        val userFlow = MutableStateFlow<LocalUser?>(user1)
        val session = FakeSessionStorage(1L)
        val accountRepo = FakeAccountRepository(
            observedUsers = mapOf(1L to userFlow),
        )
        val viewModel = MiliSpotViewModel(
            FakeBenefitRepository(listOf(benefit("seed-1"))),
            accountRepo,
            FakeFavoriteRepository(),
            FakeAdminRepository(),
            FakeSeedInstaller(),
            session,
            mmaConfigured = false,
        )
        advanceUntilIdle()
        assertEquals(user1, viewModel.uiState.value.user)

        viewModel.logout()
        advanceUntilIdle()
        assertEquals(null, viewModel.uiState.value.user)
        assertEquals(null, session.userId())

        userFlow.value = user1.copy(displayName = "변경된 사용자1")
        advanceUntilIdle()

        assertEquals(null, viewModel.uiState.value.user)
        assertEquals(null, session.userId())
    }

    @Test
    fun loginCancelsPreviousSessionObserverSoOldUserCannotOverwriteNewUser() = runTest(dispatcher.scheduler) {
        val user1 = LocalUser(1L, "user1@test.com", "사용자1", false)
        val user2 = LocalUser(2L, "user2@test.com", "사용자2", true)
        val user1Flow = MutableStateFlow<LocalUser?>(user1)
        val session = FakeSessionStorage(1L)
        val accountRepo = FakeAccountRepository(
            observedUsers = mapOf(1L to user1Flow),
            loginResult = Result.success(user2),
        )
        val viewModel = MiliSpotViewModel(
            FakeBenefitRepository(listOf(benefit("seed-1"))),
            accountRepo,
            FakeFavoriteRepository(),
            FakeAdminRepository(),
            FakeSeedInstaller(),
            session,
            mmaConfigured = false,
        )
        advanceUntilIdle()
        assertEquals(user1, viewModel.uiState.value.user)

        assertTrue(viewModel.login("user2@test.com", "secret2").isSuccess)
        advanceUntilIdle()
        assertEquals(user2, viewModel.uiState.value.user)
        assertEquals(2L, session.userId())

        user1Flow.value = user1.copy(displayName = "뒤늦은 갱신")
        advanceUntilIdle()

        assertEquals(user2, viewModel.uiState.value.user)
        assertEquals(2L, session.userId())
    }

    @Test
    fun adminUserObservesAllBenefitsIncludingEndedAndLogoutClearsAdminBenefits() = runTest(dispatcher.scheduler) {
        val activeItem = benefit("manual-active", name = "활성 수동 가게")
        val endedItem = Benefit(
            "manual-ended", "종료 수동 가게", "서울", 37.5, 126.9, "음식", "할인", "설명", null, null, null, null,
            BenefitSourceType.MANUAL_LOCAL, "운영팀", null, null, BenefitStatus.ENDED, "마포구",
        )
        val adminUser = LocalUser(1L, "admin@test.com", "관리자", isAdmin = true)
        val adminRepo = FakeAdminRepository(flowOf(listOf(activeItem, endedItem)))

        val viewModel = MiliSpotViewModel(
            FakeBenefitRepository(listOf(activeItem)),
            FakeAccountRepository(adminUser),
            FakeFavoriteRepository(),
            adminRepo,
            FakeSeedInstaller(),
            FakeSessionStorage(1L),
            mmaConfigured = false,
        )
        advanceUntilIdle()

        assertEquals(listOf("manual-active"), viewModel.uiState.value.benefits.map(Benefit::id))
        assertEquals(listOf("manual-active", "manual-ended"), viewModel.uiState.value.adminBenefits.map(Benefit::id))

        viewModel.logout()
        advanceUntilIdle()

        assertTrue(viewModel.uiState.value.adminBenefits.isEmpty())
    }

    @Test
    fun buildAdminBenefitInputPreservesExistingMetadataDuringManualEdit() {
        val existing = Benefit(
            id = "manual_local_1",
            name = "기존 가게",
            address = "경기도 성남시 분당구 판교로 1",
            latitude = 37.402,
            longitude = 127.108,
            category = "음식",
            benefitType = "10% 할인",
            benefitDescription = "기존 설명",
            phone = "031-123-4567",
            eligibleTarget = "현역 장병",
            usageCondition = "신분증 제시",
            verificationMethod = "현장 확인",
            sourceType = BenefitSourceType.MANUAL_LOCAL,
            sourceLabel = "성남시 확인",
            sourceUrl = "https://www.seongnam.go.kr/notice",
            lastVerifiedAt = "2026-11-20",
            status = BenefitStatus.NEEDS_VERIFICATION,
            district = "성남시",
        )

        val edited = buildAdminBenefitInput(
            name = "수정된 가게",
            address = "경기도 성남시 분당구 판교로 2",
            description = "수정된 설명",
            existing = existing,
        )

        assertEquals("수정된 가게", edited.name)
        assertEquals("경기도 성남시 분당구 판교로 2", edited.address)
        assertEquals("수정된 설명", edited.benefitDescription)
        assertEquals(37.402, edited.latitude)
        assertEquals(127.108, edited.longitude)
        assertEquals("음식", edited.category)
        assertEquals("10% 할인", edited.benefitType)
        assertEquals("031-123-4567", edited.phone)
        assertEquals("현역 장병", edited.eligibleTarget)
        assertEquals("신분증 제시", edited.usageCondition)
        assertEquals("현장 확인", edited.verificationMethod)
        assertEquals("성남시 확인", edited.sourceLabel)
        assertEquals("https://www.seongnam.go.kr/notice", edited.sourceUrl)
        assertEquals("2026-11-20", edited.lastVerifiedAt)
        assertEquals(BenefitStatus.NEEDS_VERIFICATION, edited.status)
        assertEquals("성남시", edited.district)
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
            refreshError?.let { throw it }
            return BenefitSyncResult(
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
    }

    private class FakeAccountRepository(
        private val user: LocalUser? = null,
        private val observedUsers: Map<Long, Flow<LocalUser?>> = emptyMap(),
        private val loginResult: Result<LocalUser> = Result.failure(UnsupportedOperationException()),
    ) : AccountRepository {
        override fun observeUser(id: Long): Flow<LocalUser?> =
            observedUsers[id] ?: flowOf(user?.takeIf { it.id == id })

        override suspend fun register(email: String, displayName: String, password: String) =
            Result.failure<LocalUser>(UnsupportedOperationException())

        override suspend fun login(email: String, password: String) = loginResult
    }
    private class FakeFavoriteRepository(
        private val idsFlow: Flow<Set<String>> = flowOf(emptySet()),
    ) : FavoriteRepository {
        var toggleCalls = 0
        override fun observeIds(userId: Long) = idsFlow
        override suspend fun toggle(userId: Long, benefitId: String): Boolean {
            toggleCalls += 1
            return false
        }
    }
    private class FakeAdminRepository(
        private val allBenefits: Flow<List<Benefit>> = flowOf(emptyList()),
    ) : AdminBenefitRepository {
        override fun observeAll(): Flow<List<Benefit>> = allBenefits
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

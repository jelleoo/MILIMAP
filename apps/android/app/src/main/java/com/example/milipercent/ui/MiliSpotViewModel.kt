package com.example.milipercent.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.example.milipercent.data.BenefitDataRepository
import com.example.milipercent.data.account.AccountRepository
import com.example.milipercent.data.admin.AdminBenefitInput
import com.example.milipercent.data.admin.AdminBenefitRepository
import com.example.milipercent.data.favorite.FavoriteRepository
import com.example.milipercent.data.seed.BundledSeedInstaller
import com.example.milipercent.data.session.SessionStorage
import com.example.milipercent.data.sync.BenefitSyncPolicy
import com.example.milipercent.data.sync.BenefitSyncPreferenceStore
import com.example.milipercent.data.sync.InMemoryBenefitSyncPreferences
import com.example.milipercent.location.LocationDataSource
import com.example.milipercent.location.LocationFocusState
import com.example.milipercent.location.LocationUpdate
import com.example.milipercent.model.Benefit
import com.example.milipercent.model.GeoBounds
import com.example.milipercent.model.GeoPoint
import com.example.milipercent.model.LocalUser
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class MiliSpotViewModel(
    private val benefitRepository: BenefitDataRepository,
    private val accountRepository: AccountRepository,
    private val favoriteRepository: FavoriteRepository,
    private val adminRepository: AdminBenefitRepository,
    private val seedSynchronizer: BundledSeedInstaller,
    private val sessionStore: SessionStorage,
    private val mmaConfigured: Boolean,
    private val syncPreferences: BenefitSyncPreferenceStore = InMemoryBenefitSyncPreferences(),
    private val currentTimeMillis: () -> Long = System::currentTimeMillis,
    private val autoRefreshCooldownMillis: Long = BenefitSyncPolicy.DEFAULT_AUTO_REFRESH_COOLDOWN_MILLIS,
) : ViewModel() {
    private val _uiState = MutableStateFlow(
        MiliSpotUiState(
            lastSyncLabel = BenefitSyncPolicy.formatSyncLabel(syncPreferences.lastSuccessfulSyncAtMillis()),
        ),
    )
    val uiState: StateFlow<MiliSpotUiState> = _uiState.asStateFlow()
    private var favoriteJob: kotlinx.coroutines.Job? = null
    private var locationTrackingJob: kotlinx.coroutines.Job? = null
    private var locationFocusState = LocationFocusState()
    private var indexedBenefits: List<SearchableBenefit> = emptyList()
    private var benefitsById: Map<String, Benefit> = emptyMap()

    init {
        observeBenefits()
        restoreSession()
        installSeedThenRefresh()
    }

    fun refresh() {
        if (_uiState.value.isRefreshing) return
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isRefreshing = true, refreshFailed = false)
            try {
                benefitRepository.refreshBenefits()
                val syncedAt = currentTimeMillis()
                syncPreferences.recordSuccessfulSync(syncedAt)
                _uiState.value = _uiState.value.copy(
                    isRefreshing = false,
                    refreshFailed = false,
                    lastSyncLabel = BenefitSyncPolicy.formatSyncLabel(syncedAt),
                )
            } catch (exception: CancellationException) {
                throw exception
            } catch (_: Exception) {
                _uiState.value = _uiState.value.copy(isRefreshing = false, refreshFailed = true, lastSyncLabel = "API 확인 실패 · 내장 DB 사용 중")
            }
        }
    }

    fun navigate(destination: AppDestination) {
        if (destination == AppDestination.ADMIN && _uiState.value.user?.isAdmin != true) {
            _uiState.value = _uiState.value.copy(
                destination = AppDestination.ACCOUNT,
                transientMessage = "관리자 권한이 필요합니다.",
            )
        } else {
            _uiState.value = _uiState.value.copy(destination = destination)
        }
    }

    fun selectCategory(category: String) {
        val state = _uiState.value
        if (state.showMapMarkers &&
            state.selectedCategory == category &&
            state.activeSearch.isBlank() &&
            state.selectedDistrict == com.example.milipercent.model.BenefitDistrict.ALL
        ) {
            publish(state.copy(
                selectedCategory = "전체",
                showMapMarkers = false,
                searchBounds = null,
                selectedMapBenefitId = null,
                isSearchInMapBoundsAvailable = false,
            ))
            return
        }
        val browsingMap = state.activeSearch.isBlank() &&
            state.selectedDistrict == com.example.milipercent.model.BenefitDistrict.ALL
        val nextSearchBounds = if (browsingMap) state.mapBounds else state.searchBounds
        val nextCenter = nextSearchBounds?.center ?: state.center
        val nextLabel = if (browsingMap && nextSearchBounds != null && state.locationLabel != "현재 위치") {
            "현재 지도 영역"
        } else {
            state.locationLabel
        }
        publish(state.copy(
            selectedCategory = category,
            showMapMarkers = true,
            searchBounds = nextSearchBounds,
            center = nextCenter,
            locationLabel = nextLabel,
            selectedMapBenefitId = null,
            isSearchInMapBoundsAvailable = false,
        ))
    }

    fun selectDistrict(district: com.example.milipercent.model.BenefitDistrict) {
        val state = _uiState.value
        if (district == com.example.milipercent.model.BenefitDistrict.ALL) {
            publish(state.copy(
                selectedDistrict = district,
                searchBounds = null,
                selectedMapBenefitId = null,
                isSearchInMapBoundsAvailable = false,
            ))
            return
        }
        val matches = createBenefitListItemsFromIndex(
            indexedBenefits = indexedBenefits,
            category = state.selectedCategory,
            district = district,
            activeSearch = state.activeSearch,
            center = state.center,
            currentLocation = state.currentLocation,
            searchBounds = null,
        )
        val cameraFit = computeBoundsCameraTarget(matches)
        if (cameraFit != null) {
            val (newCenter, target) = cameraFit
            val distanceOriginChanged =
                (state.activeSearch.isNotBlank() || state.currentLocation == null) && newCenter != state.center
            val finalVisible = if (distanceOriginChanged) reRankBenefitListItems(matches, newCenter) else matches
            publish(
                state = state.copy(
                    selectedDistrict = district,
                    mapBounds = null,
                    searchBounds = null,
                    showMapMarkers = true,
                    selectedMapBenefitId = null,
                    isSearchInMapBoundsAvailable = false,
                    center = newCenter,
                    cameraTarget = target,
                    cameraRequestId = state.cameraRequestId + 1,
                    locationLabel = district.displayName,
                ),
                precomputedVisible = finalVisible,
            )
        } else {
            publish(
                state = state.copy(
                    selectedDistrict = district,
                    searchBounds = null,
                    showMapMarkers = true,
                    selectedMapBenefitId = null,
                    isSearchInMapBoundsAvailable = false,
                    locationLabel = district.displayName,
                ),
                precomputedVisible = matches,
            )
        }
    }

    fun updateSearchText(searchText: String) {
        _uiState.value = _uiState.value.copy(searchText = searchText)
    }

    fun submitSearch() {
        cancelPendingLocationFocus()
        val state = _uiState.value
        val query = state.searchText.trim()
        if (query.isBlank()) {
            clearSearch()
            return
        }
        val searchCenter = destinationCenters[query.lowercase()] ?: state.center
        val matches = createBenefitListItemsFromIndex(
            indexedBenefits = indexedBenefits,
            category = state.selectedCategory,
            district = state.selectedDistrict,
            activeSearch = query,
            center = searchCenter,
            currentLocation = state.currentLocation,
            searchBounds = null,
        )
        val (newCenter, target) = computeSearchCameraTarget(query, matches, state.center)
        val finalVisible = if (newCenter == searchCenter) matches else reRankBenefitListItems(matches, newCenter)
        publish(
            state = state.copy(
                activeSearch = query,
                mapBounds = null,
                searchBounds = null,
                showMapMarkers = true,
                selectedMapBenefitId = null,
                isSearchInMapBoundsAvailable = false,
                center = newCenter,
                cameraTarget = target,
                locationLabel = query,
                cameraRequestId = state.cameraRequestId + 1,
            ),
            precomputedVisible = finalVisible,
        )
    }

    fun selectPreset(preset: String) {
        updateSearchText(preset)
        submitSearch()
    }

    fun clearSearch() {
        cancelPendingLocationFocus()
        val state = _uiState.value
        publish(state.copy(
            searchText = "",
            activeSearch = "",
            selectedCategory = "전체",
            selectedDistrict = com.example.milipercent.model.BenefitDistrict.ALL,
            searchBounds = null,
            showMapMarkers = false,
            selectedMapBenefitId = null,
            isSearchInMapBoundsAvailable = false,
            locationLabel = if (state.currentLocation != null) "현재 위치" else "수도권",
        ))
    }

    fun onMapCameraIdle(
        center: GeoPoint,
        bounds: GeoBounds,
        byUserGesture: Boolean,
        zoom: Double = DEFAULT_MAP_ZOOM,
    ) {
        val state = _uiState.value
        _uiState.value = state.copy(
            mapBounds = bounds,
            lastCameraSnapshot = MapCameraSnapshot(center, zoom),
            isSearchInMapBoundsAvailable = if (byUserGesture) true else state.isSearchInMapBoundsAvailable,
        )
    }

    fun markCameraRequestApplied(requestId: Long) {
        if (_uiState.value.appliedCameraRequestId != requestId) {
            _uiState.value = _uiState.value.copy(appliedCameraRequestId = requestId)
        }
    }

    fun searchInCurrentMapBounds() {
        val state = _uiState.value
        val bounds = state.mapBounds
        publish(state.copy(
            searchText = "",
            activeSearch = "",
            selectedDistrict = com.example.milipercent.model.BenefitDistrict.ALL,
            searchBounds = bounds,
            center = bounds?.center ?: state.center,
            showMapMarkers = true,
            selectedMapBenefitId = null,
            isSearchInMapBoundsAvailable = false,
            locationLabel = "현재 지도 영역",
        ))
    }

    fun selectMapBenefit(benefitId: String?) {
        val state = _uiState.value
        if (benefitId == null) {
            _uiState.value = state.copy(selectedMapBenefitId = null)
        } else if (benefitId in benefitsById) {
            _uiState.value = state.copy(selectedMapBenefitId = benefitId)
        }
    }

    fun selectBenefit(benefitId: String) {
        if (benefitId in benefitsById) {
            _uiState.value = _uiState.value.copy(selectedBenefitId = benefitId)
        }
    }

    fun closeDetail() {
        _uiState.value = _uiState.value.copy(selectedBenefitId = null)
    }

    fun toggleFavorite(benefitId: String) {
        val user = _uiState.value.user
        if (user == null) {
            _uiState.value = _uiState.value.copy(
                destination = AppDestination.ACCOUNT,
                transientMessage = "찜을 저장하려면 먼저 로그인해 주세요.",
            )
            return
        }
        viewModelScope.launch {
            favoriteRepository.toggle(user.id, benefitId)
        }
    }

    suspend fun register(email: String, displayName: String, password: String): Result<LocalUser> {
        val result = accountRepository.register(email, displayName, password)
        result.onSuccess { user ->
            val message = if (user.isAdmin) "첫 계정이 관리자 권한으로 등록되었습니다." else "회원가입이 완료되었습니다."
            completeLogin(user, message)
        }.onFailure { error -> showMessage(error.message ?: "회원가입에 실패했습니다.") }
        return result
    }

    suspend fun login(email: String, password: String): Result<LocalUser> {
        val result = accountRepository.login(email, password)
        result.onSuccess { user -> completeLogin(user, "로그인되었습니다.") }
            .onFailure { error -> showMessage(error.message ?: "로그인에 실패했습니다.") }
        return result
    }

    fun logout() {
        sessionStore.clear()
        setUser(null)
        _uiState.value = _uiState.value.copy(destination = AppDestination.DISCOVER, transientMessage = "로그아웃되었습니다.")
    }

    fun saveAdmin(input: AdminBenefitInput, existingId: String? = null) {
        if (!requireAdmin()) return
        viewModelScope.launch {
            runCatching {
                if (existingId == null) adminRepository.create(input) else adminRepository.update(existingId, input)
            }.onSuccess {
                showMessage("혜택 정보를 저장했습니다.")
            }.onFailure { error ->
                showMessage(error.message ?: "혜택 저장에 실패했습니다.")
            }
        }
    }

    fun endAdminBenefit(benefitId: String) {
        if (!requireAdmin()) return
        viewModelScope.launch {
            runCatching { adminRepository.end(benefitId) }
                .onSuccess { showMessage("혜택을 종료 처리했습니다.") }
                .onFailure { error -> showMessage(error.message ?: "종료 처리에 실패했습니다.") }
        }
    }

    fun deleteManualBenefit(benefitId: String) {
        if (!requireAdmin()) return
        viewModelScope.launch {
            if (adminRepository.deleteManual(benefitId)) showMessage("수동 혜택을 삭제했습니다.")
            else showMessage("수동 등록 혜택만 삭제할 수 있습니다.")
        }
    }

    fun clearMessage() {
        _uiState.value = _uiState.value.copy(transientMessage = null)
    }

    fun startLocationTracking(dataSource: LocationDataSource) {
        if (locationTrackingJob?.isActive == true) return
        locationTrackingJob = viewModelScope.launch {
            dataSource.updates().collectLatest { update ->
                when (update) {
                    is LocationUpdate.Position -> updateLocation(update.point)
                    is LocationUpdate.Unavailable -> showMessage(update.message)
                }
            }
        }
    }

    fun stopLocationTracking() {
        locationTrackingJob?.cancel()
        locationTrackingJob = null
    }

    /** Returns true when an existing location was focused; false means a fresh fix is still needed. */
    fun requestCurrentLocationFocus(): Boolean {
        locationFocusState = locationFocusState.copy(cameraRequestId = _uiState.value.cameraRequestId).requestFocus()
        val latest = locationFocusState.latestLocation
        if (latest == null) {
            _uiState.value = _uiState.value.copy(isLocationFocusPending = true)
            return false
        }
        publish(
            state = _uiState.value.copy(
                searchText = "",
                activeSearch = "",
                selectedCategory = "전체",
                selectedDistrict = com.example.milipercent.model.BenefitDistrict.ALL,
                mapBounds = null,
                searchBounds = null,
                showMapMarkers = false,
                selectedMapBenefitId = null,
                isSearchInMapBoundsAvailable = false,
                center = latest,
                currentLocation = latest,
                cameraTarget = MapCameraTarget.Point(latest, CURRENT_LOCATION_ZOOM),
                isLocationFocusPending = false,
                cameraRequestId = locationFocusState.cameraRequestId,
                locationLabel = "현재 위치",
            ),
            recomputeSaved = true,
        )
        return true
    }

    fun locationPermissionDenied() {
        cancelPendingLocationFocus()
        showMessage("위치 권한이 없어 서울 전체를 표시합니다.")
    }

    private fun observeBenefits() {
        viewModelScope.launch {
            benefitRepository.observeDomainBenefits().collectLatest { benefits ->
                indexedBenefits = benefits.toSearchableBenefits()
                benefitsById = benefits.associateBy(Benefit::id)
                publish(
                    state = _uiState.value.copy(benefits = benefits, isLoading = false),
                    recomputeSaved = true,
                )
            }
        }
    }

    private fun restoreSession() {
        val userId = sessionStore.userId() ?: return
        viewModelScope.launch {
            accountRepository.observeUser(userId)
                .collectLatest { user ->
                    if (user == null) sessionStore.clear()
                    setUser(user)
                }
        }
    }

    private fun installSeedThenRefresh() {
        viewModelScope.launch {
            try {
                seedSynchronizer.synchronizeIfNeeded()
                if (mmaConfigured) {
                    val lastSyncedAt = syncPreferences.lastSuccessfulSyncAtMillis()
                    if (BenefitSyncPolicy.shouldAutoRefresh(lastSyncedAt, currentTimeMillis(), autoRefreshCooldownMillis)) {
                        refresh()
                    } else {
                        _uiState.value = _uiState.value.copy(
                            lastSyncLabel = BenefitSyncPolicy.formatSyncLabel(lastSyncedAt),
                        )
                    }
                }
            } catch (exception: CancellationException) {
                throw exception
            } catch (_: Exception) {
                _uiState.value = _uiState.value.copy(isLoading = false, refreshFailed = true)
            }
        }
    }

    private fun updateLocation(point: GeoPoint) {
        val previousCameraRequest = locationFocusState.cameraRequestId
        locationFocusState = locationFocusState.withLocation(point)
        val focused = locationFocusState.cameraRequestId > previousCameraRequest
        val next = if (focused) {
            _uiState.value.copy(
                searchText = "",
                activeSearch = "",
                selectedCategory = "전체",
                selectedDistrict = com.example.milipercent.model.BenefitDistrict.ALL,
                mapBounds = null,
                searchBounds = null,
                showMapMarkers = false,
                selectedMapBenefitId = null,
                isSearchInMapBoundsAvailable = false,
                currentLocation = point,
                center = point,
                cameraTarget = MapCameraTarget.Point(point, CURRENT_LOCATION_ZOOM),
                locationLabel = "현재 위치",
                cameraRequestId = locationFocusState.cameraRequestId,
                isLocationFocusPending = false,
            )
        } else {
            _uiState.value.copy(currentLocation = point, isLocationFocusPending = false)
        }
        publish(next, recomputeSaved = true)
    }

    private fun cancelPendingLocationFocus() {
        locationFocusState = locationFocusState.cancelPendingFocus()
        if (_uiState.value.isLocationFocusPending) {
            _uiState.value = _uiState.value.copy(isLocationFocusPending = false)
        }
    }

    private fun publish(
        state: MiliSpotUiState,
        precomputedVisible: List<BenefitListItem>? = null,
        recomputeSaved: Boolean = false,
    ) {
        val visible = precomputedVisible ?: createBenefitListItemsFromIndex(
            indexedBenefits = indexedBenefits,
            category = state.selectedCategory,
            district = state.selectedDistrict,
            activeSearch = state.activeSearch,
            center = state.center,
            currentLocation = state.currentLocation,
            searchBounds = state.searchBounds,
        )
        val saved = if (recomputeSaved) {
            createSavedBenefitListItems(
                benefitsById = benefitsById,
                favoriteIds = state.favoriteIds,
                center = state.center,
                currentLocation = state.currentLocation,
            )
        } else {
            state.savedBenefits
        }
        _uiState.value = state.copy(
            visibleBenefits = visible,
            savedBenefits = saved,
        )
    }

    private fun completeLogin(user: LocalUser, message: String) {
        sessionStore.save(user)
        setUser(user)
        _uiState.value = _uiState.value.copy(destination = AppDestination.DISCOVER, transientMessage = message)
    }

    private fun setUser(user: LocalUser?) {
        favoriteJob?.cancel()
        if (user == null) {
            _uiState.value = _uiState.value.copy(user = null, favoriteIds = emptySet(), savedBenefits = emptyList())
            return
        }
        _uiState.value = _uiState.value.copy(user = user, favoriteIds = emptySet(), savedBenefits = emptyList())
        favoriteJob = viewModelScope.launch {
            favoriteRepository.observeIds(user.id).collectLatest { favoriteIds ->
                val current = _uiState.value
                _uiState.value = current.copy(
                    user = user,
                    favoriteIds = favoriteIds,
                    savedBenefits = createSavedBenefitListItems(
                        benefitsById = benefitsById,
                        favoriteIds = favoriteIds,
                        center = current.center,
                        currentLocation = current.currentLocation,
                    ),
                )
            }
        }
    }

    private fun requireAdmin(): Boolean {
        if (_uiState.value.user?.isAdmin == true) return true
        navigate(AppDestination.ADMIN)
        return false
    }

    private fun showMessage(message: String) {
        _uiState.value = _uiState.value.copy(transientMessage = message)
    }

    class Factory(
        private val benefitRepository: BenefitDataRepository,
        private val accountRepository: AccountRepository,
        private val favoriteRepository: FavoriteRepository,
        private val adminRepository: AdminBenefitRepository,
        private val seedSynchronizer: BundledSeedInstaller,
        private val sessionStore: SessionStorage,
        private val mmaConfigured: Boolean,
        private val syncPreferences: BenefitSyncPreferenceStore = InMemoryBenefitSyncPreferences(),
        private val currentTimeMillis: () -> Long = System::currentTimeMillis,
        private val autoRefreshCooldownMillis: Long = BenefitSyncPolicy.DEFAULT_AUTO_REFRESH_COOLDOWN_MILLIS,
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            require(modelClass.isAssignableFrom(MiliSpotViewModel::class.java))
            return MiliSpotViewModel(
                benefitRepository,
                accountRepository,
                favoriteRepository,
                adminRepository,
                seedSynchronizer,
                sessionStore,
                mmaConfigured,
                syncPreferences,
                currentTimeMillis,
                autoRefreshCooldownMillis,
            ) as T
        }
    }
}

package com.example.milipercent.ui

import android.util.Log
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
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.abs

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
    private val computeDispatcher: CoroutineDispatcher = Dispatchers.Default,
) : ViewModel() {
    private val _uiState = MutableStateFlow(
        MiliSpotUiState(
            lastSyncLabel = BenefitSyncPolicy.formatSyncLabel(syncPreferences.lastSuccessfulSyncAtMillis()),
        ),
    )
    val uiState: StateFlow<MiliSpotUiState> = _uiState.asStateFlow()
    private var sessionJob: kotlinx.coroutines.Job? = null
    private var favoriteJob: kotlinx.coroutines.Job? = null
    private var adminBenefitsJob: kotlinx.coroutines.Job? = null
    private var refreshJob: kotlinx.coroutines.Job? = null
    private var locationTrackingJob: kotlinx.coroutines.Job? = null
    private var locationFocusTimeoutJob: kotlinx.coroutines.Job? = null
    private var locationFocusState = LocationFocusState()
    private var indexedBenefits: List<SearchableBenefit> = emptyList()
    private var benefitsById: Map<String, Benefit> = emptyMap()

    init {
        observeBenefits()
        restoreSession()
        installSeedThenRefresh()
    }

    fun refresh() {
        if (refreshJob?.isActive == true) return
        refreshJob = viewModelScope.launch {
            _uiState.update { it.copy(isRefreshing = true, refreshFailed = false) }
            try {
                benefitRepository.refreshBenefits()
                val syncedAt = currentTimeMillis()
                syncPreferences.recordSuccessfulSync(syncedAt)
                _uiState.update {
                    it.copy(
                        isRefreshing = false,
                        refreshFailed = false,
                        lastSyncLabel = BenefitSyncPolicy.formatSyncLabel(syncedAt),
                    )
                }
            } catch (exception: CancellationException) {
                throw exception
            } catch (exception: Exception) {
                runCatching { Log.w(TAG, "Benefit refresh failed: ${exception.javaClass.simpleName}") }
                _uiState.update {
                    it.copy(
                        isRefreshing = false,
                        refreshFailed = true,
                        lastSyncLabel = "API 확인 실패 · 내장 DB 사용 중",
                    )
                }
            }
        }
    }

    fun navigate(destination: AppDestination) {
        _uiState.update { current ->
            if (destination == AppDestination.ADMIN && current.user?.isAdmin != true) {
                current.copy(
                    destination = AppDestination.ACCOUNT,
                    transientMessage = "관리자 권한이 필요합니다.",
                )
            } else {
                current.copy(destination = destination)
            }
        }
        syncAdminObservation()
    }

    fun selectCategory(category: String) {
        publishUpdate { state ->
            if (state.showMapMarkers &&
                state.selectedCategory == category &&
                state.activeSearch.isBlank() &&
                state.selectedDistrict == com.example.milipercent.model.BenefitDistrict.ALL
            ) {
                state.copy(
                    selectedCategory = "전체",
                    showMapMarkers = false,
                    searchBounds = null,
                    selectedMapBenefitId = null,
                    isSearchInMapBoundsAvailable = false,
                )
            } else {
                val browsingMap = state.activeSearch.isBlank() &&
                    state.selectedDistrict == com.example.milipercent.model.BenefitDistrict.ALL
                val nextSearchBounds = if (browsingMap) state.mapBounds else state.searchBounds
                val nextCenter = nextSearchBounds?.center ?: state.center
                val nextLabel = if (browsingMap && nextSearchBounds != null && state.locationLabel != "현재 위치") {
                    "현재 지도 영역"
                } else {
                    state.locationLabel
                }
                state.copy(
                    selectedCategory = category,
                    showMapMarkers = true,
                    searchBounds = nextSearchBounds,
                    center = nextCenter,
                    locationLabel = nextLabel,
                    selectedMapBenefitId = null,
                    isSearchInMapBoundsAvailable = false,
                )
            }
        }
    }

    fun selectDistrict(district: com.example.milipercent.model.BenefitDistrict) {
        cancelPendingLocationFocus()
        if (district == com.example.milipercent.model.BenefitDistrict.ALL) {
            publishUpdate { state ->
                state.copy(
                    selectedDistrict = district,
                    searchBounds = null,
                    selectedMapBenefitId = null,
                    isSearchInMapBoundsAvailable = false,
                )
            }
            return
        }
        _uiState.update { state ->
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
                state.copy(
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
                    visibleBenefits = finalVisible,
                )
            } else {
                state.copy(
                    selectedDistrict = district,
                    searchBounds = null,
                    showMapMarkers = true,
                    selectedMapBenefitId = null,
                    isSearchInMapBoundsAvailable = false,
                    locationLabel = district.displayName,
                    visibleBenefits = matches,
                )
            }
        }
    }

    fun updateSearchText(searchText: String) {
        _uiState.update { it.copy(searchText = searchText) }
    }

    fun submitSearch() {
        cancelPendingLocationFocus()
        val query = _uiState.value.searchText.trim()
        if (query.isBlank()) {
            clearSearch()
            return
        }
        _uiState.update { state ->
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
            state.copy(
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
                visibleBenefits = finalVisible,
            )
        }
    }

    fun selectPreset(preset: String) {
        updateSearchText(preset)
        submitSearch()
    }

    fun clearSearch() {
        cancelPendingLocationFocus()
        publishUpdate { state ->
            state.copy(
                searchText = "",
                activeSearch = "",
                selectedCategory = "전체",
                selectedDistrict = com.example.milipercent.model.BenefitDistrict.ALL,
                searchBounds = null,
                showMapMarkers = false,
                selectedMapBenefitId = null,
                isSearchInMapBoundsAvailable = false,
                locationLabel = if (state.currentLocation != null) "현재 위치" else "수도권",
            )
        }
    }

    fun onMapCameraIdle(
        center: GeoPoint,
        bounds: GeoBounds,
        byUserGesture: Boolean,
        zoom: Double = DEFAULT_MAP_ZOOM,
    ) {
        if (_uiState.value.isLocationSearchPending) {
            publishUpdate { state ->
                val target = (state.cameraTarget as? MapCameraTarget.Point)?.point
                val reachedLocation = state.appliedCameraRequestId == state.cameraRequestId &&
                    target != null && center.isNear(target)
                // Ignore idle callbacks from the previous camera while the new move is in flight.
                val currentMoveApplied = state.appliedCameraRequestId == state.cameraRequestId
                val applyBounds = reachedLocation || (byUserGesture && currentMoveApplied)
                state.copy(
                    mapBounds = bounds,
                    lastCameraSnapshot = MapCameraSnapshot(center, zoom),
                    searchBounds = if (applyBounds) bounds else state.searchBounds,
                    isLocationSearchPending = !applyBounds,
                    isSearchInMapBoundsAvailable = false,
                    locationLabel = if (applyBounds && byUserGesture) "현재 지도 영역" else state.locationLabel,
                )
            }
            return
        }
        _uiState.update { state ->
            state.copy(
                mapBounds = bounds,
                lastCameraSnapshot = MapCameraSnapshot(center, zoom),
                isSearchInMapBoundsAvailable = if (byUserGesture) true else state.isSearchInMapBoundsAvailable,
            )
        }
    }

    fun markCameraRequestApplied(requestId: Long) {
        _uiState.update { state ->
            if (state.appliedCameraRequestId != requestId) {
                state.copy(appliedCameraRequestId = requestId)
            } else {
                state
            }
        }
    }

    fun searchInCurrentMapBounds() {
        cancelPendingLocationFocus()
        publishUpdate { state ->
            val bounds = state.mapBounds
            state.copy(
                searchText = "",
                activeSearch = "",
                selectedDistrict = com.example.milipercent.model.BenefitDistrict.ALL,
                searchBounds = bounds,
                center = bounds?.center ?: state.center,
                showMapMarkers = true,
                selectedMapBenefitId = null,
                isSearchInMapBoundsAvailable = false,
                locationLabel = "현재 지도 영역",
            )
        }
    }

    fun selectMapBenefit(benefitId: String?) {
        _uiState.update { state ->
            when {
                benefitId == null -> state.copy(selectedMapBenefitId = null)
                benefitId in benefitsById -> state.copy(selectedMapBenefitId = benefitId)
                else -> state
            }
        }
    }

    fun selectBenefit(benefitId: String) {
        if (benefitId in benefitsById) {
            _uiState.update { it.copy(selectedBenefitId = benefitId) }
        }
    }

    fun closeDetail() {
        _uiState.update { it.copy(selectedBenefitId = null) }
    }

    fun toggleFavorite(benefitId: String) {
        val user = _uiState.value.user
        if (user == null) {
            _uiState.update {
                it.copy(
                    destination = AppDestination.ACCOUNT,
                    transientMessage = "찜을 저장하려면 먼저 로그인해 주세요.",
                )
            }
            return
        }
        viewModelScope.launch {
            runCatching { favoriteRepository.toggle(user.id, benefitId) }
                .onFailure { exception ->
                    if (exception is CancellationException) throw exception
                    runCatching { Log.w(TAG, "Favorite toggle failed: ${exception.javaClass.simpleName}") }
                    showMessage("찜 상태를 변경하지 못했습니다.")
                }
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
        sessionJob?.cancel()
        sessionJob = null
        sessionStore.clear()
        setUser(null)
        _uiState.update { it.copy(destination = AppDestination.DISCOVER, transientMessage = "로그아웃되었습니다.") }
    }

    suspend fun saveAdmin(input: AdminBenefitInput, existingId: String? = null): Boolean {
        if (!requireAdmin()) return false
        return runCatching {
            if (existingId == null) adminRepository.create(input) else adminRepository.update(existingId, input)
        }.onSuccess {
            showMessage("혜택 정보를 저장했습니다.")
        }.onFailure { error ->
            if (error is CancellationException) throw error
            showMessage(error.message ?: "혜택 저장에 실패했습니다.")
        }.isSuccess
    }

    fun endAdminBenefit(benefitId: String) {
        if (!requireAdmin()) return
        viewModelScope.launch {
            runCatching { adminRepository.end(benefitId) }
                .onSuccess { showMessage("혜택을 종료 처리했습니다.") }
                .onFailure { error ->
                    if (error is CancellationException) throw error
                    showMessage(error.message ?: "종료 처리에 실패했습니다.")
                }
        }
    }

    fun deleteManualBenefit(benefitId: String) {
        if (!requireAdmin()) return
        viewModelScope.launch {
            runCatching { adminRepository.deleteManual(benefitId) }
                .onSuccess { deleted ->
                    if (deleted) showMessage("수동 혜택을 삭제했습니다.")
                    else showMessage("수동 등록 혜택만 삭제할 수 있습니다.")
                }.onFailure { error ->
                    if (error is CancellationException) throw error
                    runCatching { Log.w(TAG, "Manual benefit delete failed: ${error.javaClass.simpleName}") }
                    showMessage("수동 혜택 삭제에 실패했습니다.")
                }
        }
    }

    fun clearMessage() {
        _uiState.update { it.copy(transientMessage = null) }
    }

    fun startLocationTracking(dataSource: LocationDataSource, restart: Boolean = false) {
        if (restart) {
            locationTrackingJob?.cancel()
            locationTrackingJob = null
        }
        if (locationTrackingJob?.isActive == true) return
        if (locationFocusState.focusPending) {
            locationFocusTimeoutJob?.cancel()
            locationFocusTimeoutJob = viewModelScope.launch {
                delay(LOCATION_FOCUS_TIMEOUT_MILLIS)
                if (locationFocusState.focusPending) {
                    cancelPendingLocationFocus()
                    showMessage("현재 위치를 확인하지 못했습니다. 위치 설정을 확인한 후 다시 시도해 주세요.")
                }
            }
        }
        locationTrackingJob = viewModelScope.launch {
            dataSource.updates().collectLatest { update ->
                when (update) {
                    is LocationUpdate.Position -> updateLocation(update.point)
                    is LocationUpdate.Unavailable -> {
                        if (locationFocusState.focusPending) cancelPendingLocationFocus()
                        showMessage(update.message)
                    }
                }
            }
        }
    }

    fun stopLocationTracking() {
        locationTrackingJob?.cancel()
        locationTrackingJob = null
        locationFocusTimeoutJob?.cancel()
        locationFocusTimeoutJob = null
        locationFocusState = locationFocusState.cancelPendingFocus()
        _uiState.update { it.copy(isLocationFocusPending = false) }
    }

    fun requestCurrentLocationFocus() {
        locationFocusTimeoutJob?.cancel()
        locationFocusState = locationFocusState.copy(cameraRequestId = _uiState.value.cameraRequestId).requestFocus()
        _uiState.update { it.copy(isLocationFocusPending = true, transientMessage = null) }
    }

    fun locationPermissionDenied() {
        cancelPendingLocationFocus()
        showMessage("현재 위치를 보려면 위치 권한을 허용해 주세요. 기존 지도는 유지됩니다.")
    }

    private fun observeBenefits() {
        viewModelScope.launch {
            benefitRepository.observeDomainBenefits().collectLatest { benefits ->
                val (nextIndexed, nextById) = withContext(computeDispatcher) {
                    benefits.toSearchableBenefits() to benefits.associateBy(Benefit::id)
                }
                indexedBenefits = nextIndexed
                benefitsById = nextById
                publishUpdate(recomputeSaved = true) { state ->
                    state.copy(benefits = benefits, isLoading = false)
                }
            }
        }
    }

    private fun restoreSession() {
        sessionJob?.cancel()
        val userId = sessionStore.userId() ?: return
        sessionJob = viewModelScope.launch {
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
                        _uiState.update {
                            it.copy(
                                lastSyncLabel = BenefitSyncPolicy.formatSyncLabel(lastSyncedAt),
                            )
                        }
                    }
                }
            } catch (exception: CancellationException) {
                throw exception
            } catch (exception: Exception) {
                runCatching { Log.w(TAG, "Initial seed or auto-refresh failed: ${exception.javaClass.simpleName}") }
                _uiState.update { it.copy(isLoading = false, refreshFailed = true) }
            }
        }
    }

    private fun updateLocation(point: GeoPoint) {
        val previousCameraRequest = locationFocusState.cameraRequestId
        locationFocusState = locationFocusState.withLocation(point)
        val focused = locationFocusState.cameraRequestId > previousCameraRequest
        val requestId = locationFocusState.cameraRequestId
        if (focused) {
            locationFocusTimeoutJob?.cancel()
            locationFocusTimeoutJob = null
        }
        publishUpdate(recomputeSaved = true) { state ->
            if (focused) {
                val alreadyAtLocation = state.mapBounds != null && state.lastCameraSnapshot?.let {
                    it.center.isNear(point) && abs(it.zoom - CURRENT_LOCATION_ZOOM) < 0.001
                } == true
                state.copy(
                    searchText = "",
                    activeSearch = "",
                    selectedDistrict = com.example.milipercent.model.BenefitDistrict.ALL,
                    mapBounds = if (alreadyAtLocation) state.mapBounds else null,
                    searchBounds = if (alreadyAtLocation) state.mapBounds else null,
                    showMapMarkers = true,
                    selectedMapBenefitId = null,
                    isSearchInMapBoundsAvailable = false,
                    currentLocation = point,
                    center = point,
                    cameraTarget = MapCameraTarget.Point(point, CURRENT_LOCATION_ZOOM),
                    locationLabel = "현재 위치",
                    cameraRequestId = requestId,
                    isLocationFocusPending = false,
                    isLocationSearchPending = !alreadyAtLocation,
                )
            } else {
                state.copy(currentLocation = point, isLocationFocusPending = false)
            }
        }
    }

    private fun cancelPendingLocationFocus() {
        locationFocusTimeoutJob?.cancel()
        locationFocusTimeoutJob = null
        locationFocusState = locationFocusState.cancelPendingFocus()
        _uiState.update { state ->
            state.copy(isLocationFocusPending = false, isLocationSearchPending = false)
        }
    }

    private fun publishUpdate(
        recomputeSaved: Boolean = false,
        transform: (MiliSpotUiState) -> MiliSpotUiState,
    ) {
        _uiState.update { current ->
            val state = transform(current)
            val visible = if (state.isLocationSearchPending) emptyList() else createBenefitListItemsFromIndex(
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
            state.copy(
                visibleBenefits = visible,
                savedBenefits = saved,
            )
        }
    }

    private fun completeLogin(user: LocalUser, message: String) {
        sessionJob?.cancel()
        sessionJob = null
        sessionStore.save(user)
        setUser(user)
        _uiState.update { it.copy(destination = AppDestination.DISCOVER, transientMessage = message) }
    }

    private fun setUser(user: LocalUser?) {
        favoriteJob?.cancel()
        adminBenefitsJob?.cancel()
        if (user == null) {
            _uiState.update {
                it.copy(
                    user = null,
                    favoriteIds = emptySet(),
                    savedBenefits = emptyList(),
                    adminBenefits = emptyList(),
                )
            }
            return
        }
        _uiState.update {
            it.copy(
                user = user,
                favoriteIds = emptySet(),
                savedBenefits = emptyList(),
                adminBenefits = if (user.isAdmin) it.adminBenefits else emptyList(),
            )
        }
        favoriteJob = viewModelScope.launch {
            favoriteRepository.observeIds(user.id).collectLatest { favoriteIds ->
                _uiState.update { current ->
                    if (current.user?.id != user.id) return@update current
                    current.copy(
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
        syncAdminObservation()
    }

    private fun syncAdminObservation() {
        val state = _uiState.value
        val shouldObserve = state.user?.isAdmin == true && state.destination == AppDestination.ADMIN
        if (!shouldObserve) {
            adminBenefitsJob?.cancel()
            adminBenefitsJob = null
            if (state.adminBenefits.isNotEmpty() && state.user?.isAdmin != true) {
                _uiState.update { it.copy(adminBenefits = emptyList()) }
            }
            return
        }
        if (adminBenefitsJob?.isActive == true) return
        adminBenefitsJob = viewModelScope.launch {
            adminRepository.observeAll().collectLatest { allBenefits ->
                _uiState.update { current ->
                    if (current.user?.isAdmin == true) current.copy(adminBenefits = allBenefits) else current
                }
            }
        }
    }

    private fun requireAdmin(): Boolean {
        if (_uiState.value.user?.isAdmin == true) return true
        navigate(AppDestination.ADMIN)
        return false
    }

    private fun showMessage(message: String) {
        _uiState.update { it.copy(transientMessage = message) }
    }

    private fun GeoPoint.isNear(other: GeoPoint): Boolean =
        abs(latitude - other.latitude) < 0.00001 && abs(longitude - other.longitude) < 0.00001

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
        private val computeDispatcher: CoroutineDispatcher = Dispatchers.Default,
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
                computeDispatcher,
            ) as T
        }
    }

    private companion object {
        const val TAG = "MiliSpotViewModel"
        const val LOCATION_FOCUS_TIMEOUT_MILLIS = 15_000L
    }
}

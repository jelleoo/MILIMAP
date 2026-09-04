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
) : ViewModel() {
    private val _uiState = MutableStateFlow(MiliSpotUiState())
    val uiState: StateFlow<MiliSpotUiState> = _uiState.asStateFlow()
    private var favoriteJob: kotlinx.coroutines.Job? = null

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
                _uiState.value = _uiState.value.copy(isRefreshing = false, lastSyncLabel = "나라사랑가게 API 동기화 완료")
            } catch (exception: CancellationException) {
                throw exception
            } catch (_: Exception) {
                _uiState.value = _uiState.value.copy(isRefreshing = false, refreshFailed = true, lastSyncLabel = "API 확인 실패 · 내장 DB 사용 중")
            }
        }
    }

    fun navigate(destination: AppDestination) {
        if (destination == AppDestination.ADMIN && _uiState.value.user?.isAdmin != true) {
            publish(_uiState.value.copy(
                destination = AppDestination.ACCOUNT,
                transientMessage = "관리자 권한이 필요합니다.",
            ))
        } else {
            publish(_uiState.value.copy(destination = destination))
        }
    }

    fun selectCategory(category: String) {
        publish(_uiState.value.copy(selectedCategory = category))
    }

    fun selectDistrict(district: com.example.milipercent.model.BenefitDistrict) {
        publish(_uiState.value.copy(selectedDistrict = district))
    }

    fun updateSearchText(searchText: String) {
        _uiState.value = _uiState.value.copy(searchText = searchText)
    }

    fun submitSearch() {
        val query = _uiState.value.searchText.trim()
        val center = destinationCenters[query] ?: SEOUL_CENTER
        publish(_uiState.value.copy(
            activeSearch = query,
            center = center,
            locationLabel = query.ifBlank { "서울 전체" },
            cameraRequestId = _uiState.value.cameraRequestId + 1,
        ))
    }

    fun selectPreset(preset: String) {
        updateSearchText(preset)
        submitSearch()
    }

    fun clearSearch() {
        publish(_uiState.value.copy(
            searchText = "",
            activeSearch = "",
            center = SEOUL_CENTER,
            locationLabel = "서울 전체",
            cameraRequestId = _uiState.value.cameraRequestId + 1,
        ))
    }

    fun selectBenefit(benefitId: String) {
        if (_uiState.value.benefits.any { it.id == benefitId }) {
            _uiState.value = _uiState.value.copy(selectedBenefitId = benefitId)
        }
    }

    fun closeDetail() {
        _uiState.value = _uiState.value.copy(selectedBenefitId = null)
    }

    fun toggleFavorite(benefitId: String) {
        val user = _uiState.value.user
        if (user == null) {
            publish(_uiState.value.copy(
                destination = AppDestination.ACCOUNT,
                transientMessage = "찜을 저장하려면 먼저 로그인해 주세요.",
            ))
            return
        }
        viewModelScope.launch {
            favoriteRepository.toggle(user.id, benefitId)
        }
    }

    fun register(email: String, displayName: String, password: String) {
        viewModelScope.launch {
            accountRepository.register(email, displayName, password)
                .onSuccess { user -> completeLogin(user, "회원가입이 완료되었습니다.") }
                .onFailure { error -> showMessage(error.message ?: "회원가입에 실패했습니다.") }
        }
    }

    fun login(email: String, password: String) {
        viewModelScope.launch {
            accountRepository.login(email, password)
                .onSuccess { user -> completeLogin(user, "로그인되었습니다.") }
                .onFailure { error -> showMessage(error.message ?: "로그인에 실패했습니다.") }
        }
    }

    fun logout() {
        sessionStore.clear()
        setUser(null)
        publish(_uiState.value.copy(destination = AppDestination.DISCOVER, transientMessage = "로그아웃되었습니다."))
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

    private fun observeBenefits() {
        viewModelScope.launch {
            benefitRepository.observeDomainBenefits().collectLatest { benefits ->
                publish(_uiState.value.copy(benefits = benefits, isLoading = false))
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
                if (mmaConfigured) refresh()
            } catch (exception: CancellationException) {
                throw exception
            } catch (_: Exception) {
                _uiState.value = _uiState.value.copy(isLoading = false, refreshFailed = true)
            }
        }
    }

    private fun publish(state: MiliSpotUiState) {
        val visible = createBenefitListItems(
            state.benefits, state.selectedCategory, state.selectedDistrict,
            state.activeSearch, state.center, state.currentLocation,
        )
        _uiState.value = state.copy(
            visibleBenefits = visible,
            savedBenefits = visible.filter { it.benefit.id in state.favoriteIds },
        )
    }

    private fun completeLogin(user: LocalUser, message: String) {
        sessionStore.save(user)
        setUser(user)
        publish(_uiState.value.copy(destination = AppDestination.DISCOVER, transientMessage = message))
    }

    private fun setUser(user: LocalUser?) {
        favoriteJob?.cancel()
        if (user == null) {
            publish(_uiState.value.copy(user = null, favoriteIds = emptySet()))
            return
        }
        publish(_uiState.value.copy(user = user, favoriteIds = emptySet()))
        favoriteJob = viewModelScope.launch {
            favoriteRepository.observeIds(user.id).collectLatest { favoriteIds ->
                publish(_uiState.value.copy(user = user, favoriteIds = favoriteIds))
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
            ) as T
        }
    }
}

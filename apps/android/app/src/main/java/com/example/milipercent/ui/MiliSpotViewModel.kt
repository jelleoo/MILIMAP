package com.example.milipercent.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.milipercent.data.BenefitDataRepository
import com.example.milipercent.data.account.AccountRepository
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
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch

@OptIn(ExperimentalCoroutinesApi::class)
class MiliSpotViewModel(
    private val benefitRepository: BenefitDataRepository,
    private val accountRepository: AccountRepository,
    private val favoriteRepository: FavoriteRepository,
    @Suppress("unused") private val adminRepository: AdminBenefitRepository,
    private val seedSynchronizer: BundledSeedInstaller,
    private val sessionStore: SessionStorage,
    private val mmaConfigured: Boolean,
) : ViewModel() {
    private val _uiState = MutableStateFlow(MiliSpotUiState())
    val uiState: StateFlow<MiliSpotUiState> = _uiState.asStateFlow()

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
                .onEach { user -> if (user == null) sessionStore.clear() }
                .flatMapLatest { user ->
                    if (user == null) flowOf(null to emptySet())
                    else favoriteRepository.observeIds(user.id).let { favorites ->
                        favorites.flatMapLatest { ids -> flowOf(user to ids) }
                    }
                }
                .collectLatest { (user, favoriteIds) ->
                    publish(_uiState.value.copy(user = user, favoriteIds = favoriteIds))
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
}

package com.example.milipercent.ui

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.example.milipercent.analysis.BenefitAnalyzer
import com.example.milipercent.data.BenefitDataRepository
import com.example.milipercent.model.BenefitDistrict
import com.example.milipercent.model.CollectionProgress
import com.example.milipercent.data.seed.ManualSeedSynchronizer
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class BenefitViewModel(
    private val repository: BenefitDataRepository,
    private val manualSeedSynchronizer: ManualSeedSynchronizer? = null,
) : ViewModel() {
    private val _uiState = MutableStateFlow<BenefitUiState>(BenefitUiState.Loading())
    val uiState: StateFlow<BenefitUiState> = _uiState.asStateFlow()

    private var loadJob: Job? = null
    private val districtState = BenefitDistrictState()
    private var hasObservedCache = false
    private var isRefreshing = false
    private var refreshFailed = false
    private var refreshCompleted = false
    private var progress: CollectionProgress? = null
    private var latestApiCollectedCount: Int? = null

    init {
        observeCachedBenefits()
        synchronizeManualSeed()
        loadBenefits()
    }

    private fun synchronizeManualSeed() {
        val synchronizer = manualSeedSynchronizer ?: return
        viewModelScope.launch {
            runCatchingPreservingCancellation { synchronizer.synchronize() }
                .onSuccess { result ->
                    Log.d(TAG, "MANUAL_SEED 동기화 완료: ${result.storedCount}")
                }
                .onFailure { exception ->
                    Log.e(TAG, "MANUAL_SEED 동기화 실패: ${exception.javaClass.simpleName}")
                }
        }
    }

    private fun observeCachedBenefits() {
        viewModelScope.launch {
            repository.observeBenefits().collect { benefits ->
                districtState.updateBenefits(benefits)
                hasObservedCache = true
                Log.d(TAG, "UI Room 데이터: ${benefits.size}")
                publishState()
            }
        }
    }

    fun selectDistrict(district: BenefitDistrict) {
        if (!districtState.selectDistrict(district)) return

        Log.d(
            TAG,
            "지역 선택: ${district.displayName} (${districtState.filteredBenefits.size}건)",
        )
        publishState()
    }

    fun updateSearchQuery(query: String) {
        if (!districtState.updateSearchQuery(query)) return

        Log.d(
            TAG,
            "검색어 변경: ${query.length}자 (${districtState.filteredBenefits.size}건)",
        )
        publishState()
    }

    fun clearSearchQuery() {
        if (!districtState.clearSearchQuery()) return

        Log.d(TAG, "검색어 지우기 (${districtState.filteredBenefits.size}건)")
        publishState()
    }

    fun loadBenefits() {
        if (loadJob?.isActive == true) return

        isRefreshing = true
        refreshFailed = false
        progress = null
        Log.d(TAG, "API 전체 데이터 수집 시작")
        publishState()

        loadJob = viewModelScope.launch {
            try {
                val syncResult = repository.refreshBenefits { collectionProgress ->
                    progress = collectionProgress
                    publishState()
                }
                latestApiCollectedCount = syncResult.analysis.collectedCount
                refreshCompleted = true
                isRefreshing = false

                // 업체 전체 목록이나 인증정보가 아닌 집계 결과만 출력한다.
                BenefitAnalyzer.createDebugReport(syncResult.analysis)
                    .lineSequence()
                    .forEach { line -> Log.d(TAG, line) }
                Log.d(
                    TAG,
                    "Room Sync 완료: ${syncResult.roomStoredCount} " +
                        "(서울 필터: ${syncResult.analysis.seoulBenefits.size})",
                )
                publishState()
            } catch (exception: CancellationException) {
                throw exception
            } catch (exception: Exception) {
                // Exception messages are intentionally designed not to include the service key.
                Log.e(
                    TAG,
                    "최신 데이터 갱신 실패: " +
                        "${exception.javaClass.simpleName} - ${exception.message}",
                )
                isRefreshing = false
                refreshFailed = true
                publishState()
            }
        }
    }

    private fun publishState() {
        _uiState.value = createBenefitUiState(
            districtState = districtState,
            hasObservedCache = hasObservedCache,
            isRefreshing = isRefreshing,
            refreshFailed = refreshFailed,
            refreshCompleted = refreshCompleted,
            progress = progress,
            latestApiCollectedCount = latestApiCollectedCount,
        )
    }

    class Factory(
        private val repository: BenefitDataRepository,
        private val manualSeedSynchronizer: ManualSeedSynchronizer? = null,
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            if (modelClass.isAssignableFrom(BenefitViewModel::class.java)) {
                return BenefitViewModel(repository, manualSeedSynchronizer) as T
            }
            throw IllegalArgumentException("지원하지 않는 ViewModel입니다: ${modelClass.name}")
        }
    }

    private companion object {
        const val TAG = "BenefitViewModel"
    }
}

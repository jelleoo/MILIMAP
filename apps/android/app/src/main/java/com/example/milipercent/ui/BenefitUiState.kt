package com.example.milipercent.ui

import com.example.milipercent.model.BenefitDistrict
import com.example.milipercent.model.BenefitUiModel
import com.example.milipercent.model.CollectionProgress

sealed interface BenefitUiState {
    data class Loading(
        val currentPage: Int = 0,
        val totalPages: Int? = null,
        val collectedCount: Int = 0,
    ) : BenefitUiState

    data class Success(
        val benefits: List<BenefitUiModel>,
        val selectedDistrict: BenefitDistrict,
        val searchQuery: String,
        val districtCounts: Map<BenefitDistrict, Int>,
        val apiCollectedCount: Int? = null,
        val isRefreshing: Boolean = false,
        val progress: CollectionProgress? = null,
        val refreshFailed: Boolean = false,
    ) : BenefitUiState

    data object Error : BenefitUiState
}

internal fun createBenefitUiState(
    districtState: BenefitDistrictState,
    hasObservedCache: Boolean,
    isRefreshing: Boolean,
    refreshFailed: Boolean,
    refreshCompleted: Boolean,
    progress: CollectionProgress?,
    latestApiCollectedCount: Int?,
): BenefitUiState = when {
    districtState.totalBenefitCount > 0 -> BenefitUiState.Success(
        benefits = districtState.filteredBenefits,
        selectedDistrict = districtState.selectedDistrict,
        searchQuery = districtState.searchQuery,
        districtCounts = districtState.districtCounts,
        apiCollectedCount = latestApiCollectedCount,
        isRefreshing = isRefreshing,
        progress = progress,
        refreshFailed = refreshFailed,
    )

    !hasObservedCache || isRefreshing -> BenefitUiState.Loading(
        currentPage = progress?.currentPage ?: 0,
        totalPages = progress?.totalPages,
        collectedCount = progress?.collectedCount ?: 0,
    )

    refreshFailed -> BenefitUiState.Error

    refreshCompleted -> BenefitUiState.Success(
        benefits = districtState.filteredBenefits,
        selectedDistrict = districtState.selectedDistrict,
        searchQuery = districtState.searchQuery,
        districtCounts = districtState.districtCounts,
        apiCollectedCount = latestApiCollectedCount,
    )

    else -> BenefitUiState.Loading()
}

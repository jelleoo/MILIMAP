package com.example.milipercent.ui

import com.example.milipercent.model.Benefit
import com.example.milipercent.model.BenefitDistrict
import com.example.milipercent.model.GeoPoint
import com.example.milipercent.model.LocalUser

enum class AppDestination { DISCOVER, SAVED, ACCOUNT, ADMIN }

data class BenefitListItem(
    val benefit: Benefit,
    val distanceKm: Double?,
)

data class MiliSpotUiState(
    val destination: AppDestination = AppDestination.DISCOVER,
    val benefits: List<Benefit> = emptyList(),
    val visibleBenefits: List<BenefitListItem> = emptyList(),
    val savedBenefits: List<BenefitListItem> = emptyList(),
    val selectedBenefitId: String? = null,
    val user: LocalUser? = null,
    val favoriteIds: Set<String> = emptySet(),
    val selectedCategory: String = "전체",
    val selectedDistrict: BenefitDistrict = BenefitDistrict.ALL,
    val searchText: String = "",
    val activeSearch: String = "",
    val center: GeoPoint = SEOUL_CENTER,
    val currentLocation: GeoPoint? = null,
    val cameraRequestId: Long = 0,
    val locationLabel: String = "서울 전체",
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val refreshFailed: Boolean = false,
    val lastSyncLabel: String = "내장 혜택 DB",
    val transientMessage: String? = null,
) {
    val selectedBenefit: Benefit?
        get() = selectedBenefitId?.let { id -> benefits.firstOrNull { it.id == id } }
}

val SEOUL_CENTER = GeoPoint(37.5665, 126.9780)

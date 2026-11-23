package com.example.milipercent.ui

import com.example.milipercent.model.Benefit
import com.example.milipercent.model.BenefitDistrict
import com.example.milipercent.model.GeoBounds
import com.example.milipercent.model.GeoPoint
import com.example.milipercent.model.LocalUser
import com.example.milipercent.ui.map.BenefitMapItem
import com.example.milipercent.ui.map.toMapItemOrNull

enum class AppDestination { DISCOVER, SAVED, ACCOUNT, ADMIN }

const val DEFAULT_MAP_ZOOM = 13.5
const val CURRENT_LOCATION_ZOOM = 14.2
const val SINGLE_RESULT_ZOOM = 15.5

sealed interface MapCameraTarget {
    data class Point(val point: GeoPoint, val zoom: Double = DEFAULT_MAP_ZOOM) : MapCameraTarget
    data class Bounds(val bounds: GeoBounds) : MapCameraTarget
}

data class MapCameraSnapshot(
    val center: GeoPoint,
    val zoom: Double,
)

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
    val showMapMarkers: Boolean = false,
    val selectedMapBenefitId: String? = null,
    val user: LocalUser? = null,
    val favoriteIds: Set<String> = emptySet(),
    val selectedCategory: String = "전체",
    val selectedDistrict: BenefitDistrict = BenefitDistrict.ALL,
    val searchText: String = "",
    val activeSearch: String = "",
    val center: GeoPoint = SEOUL_CENTER,
    val currentLocation: GeoPoint? = null,
    val mapBounds: GeoBounds? = null,
    val searchBounds: GeoBounds? = null,
    val isSearchInMapBoundsAvailable: Boolean = false,
    val isLocationFocusPending: Boolean = false,
    val cameraRequestId: Long = 0,
    val appliedCameraRequestId: Long = -1L,
    val cameraTarget: MapCameraTarget = MapCameraTarget.Point(SEOUL_CENTER),
    val lastCameraSnapshot: MapCameraSnapshot? = null,
    val locationLabel: String = "수도권",
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val refreshFailed: Boolean = false,
    val lastSyncLabel: String = "내장 혜택 DB",
    val transientMessage: String? = null,
) {
    val selectedBenefit: Benefit?
        get() = selectedBenefitId?.let { id -> benefits.firstOrNull { it.id == id } }

    val selectedMapBenefit: BenefitListItem?
        get() = selectedMapBenefitId?.let { id ->
            visibleBenefits.firstOrNull { it.benefit.id == id }
                ?: benefits.firstOrNull { it.id == id }?.let { BenefitListItem(it, null) }
        }

    val mapBenefits: List<BenefitMapItem>
        get() = if (!showMapMarkers) emptyList() else visibleBenefits.mapNotNull { it.benefit.toMapItemOrNull() }
}

val SEOUL_CENTER = GeoPoint(37.5665, 126.9780)

package com.example.milipercent.location

import com.example.milipercent.model.GeoPoint
import kotlinx.coroutines.flow.Flow

sealed interface LocationUpdate {
    data class Position(val point: GeoPoint) : LocationUpdate
    data class Unavailable(val message: String) : LocationUpdate
}

interface LocationDataSource {
    fun updates(): Flow<LocationUpdate>
}

internal const val LOCATION_UPDATE_INTERVAL_MS = 5_000L
internal const val LOCATION_UPDATE_DISTANCE_METERS = 10f

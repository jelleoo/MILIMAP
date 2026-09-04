package com.example.milipercent.location

import com.example.milipercent.model.GeoPoint

data class LocationFocusState(
    val latestLocation: GeoPoint? = null,
    val focusPending: Boolean = false,
    val cameraRequestId: Long = 0L,
) {
    fun requestFocus(): LocationFocusState =
        if (latestLocation == null) copy(focusPending = true)
        else copy(focusPending = false, cameraRequestId = cameraRequestId + 1)

    fun cancelPendingFocus(): LocationFocusState = copy(focusPending = false)

    fun withLocation(point: GeoPoint): LocationFocusState =
        if (focusPending) copy(
            latestLocation = point,
            focusPending = false,
            cameraRequestId = cameraRequestId + 1,
        ) else {
            copy(latestLocation = point)
        }
}

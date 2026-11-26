package com.example.milipercent.location

import com.example.milipercent.model.GeoPoint

data class LocationFocusState(
    val latestLocation: GeoPoint? = null,
    val focusPending: Boolean = false,
    val cameraRequestId: Long = 0L,
) {
    // An explicit tap must recheck the device, not reuse an indefinitely cached point.
    fun requestFocus(): LocationFocusState = copy(focusPending = true)

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

package com.example.milipercent.location

import com.example.milipercent.model.GeoPoint
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LocationBehaviorTest {
    @Test
    fun passiveLocationDoesNotMoveCameraButPendingFocusDoes() {
        val passive = LocationFocusState().withLocation(GeoPoint(37.5, 126.9))
        assertEquals(0, passive.cameraRequestId)

        val focused = LocationFocusState().requestFocus().withLocation(GeoPoint(37.5, 126.9))
        assertEquals(1, focused.cameraRequestId)
        assertFalse(focused.focusPending)
    }

    @Test
    fun sameCoordinateCanBeExplicitlyFocusedAgainAndSearchCancelsPendingFocus() {
        val initial = LocationFocusState(latestLocation = GeoPoint(37.5, 126.9))
        val focused = initial.requestFocus()
        assertEquals(1, focused.cameraRequestId)
        assertEquals(2, focused.requestFocus().cameraRequestId)
        assertTrue(LocationFocusState().requestFocus().cancelPendingFocus().let { !it.focusPending })
    }
}

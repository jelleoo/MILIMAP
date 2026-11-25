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
        val pending = initial.requestFocus()
        assertTrue(pending.focusPending)
        assertEquals(0, pending.cameraRequestId)
        val focused = pending.withLocation(GeoPoint(37.5, 126.9))
        assertEquals(1, focused.cameraRequestId)
        assertEquals(2, focused.requestFocus().withLocation(GeoPoint(37.5, 126.9)).cameraRequestId)
        assertTrue(LocationFocusState().requestFocus().cancelPendingFocus().let { !it.focusPending })
    }

    @Test
    fun onlyRecentValidDeviceFixesAreUsable() {
        val now = 100_000_000_000L
        val fresh = LocationFixCandidate(GeoPoint(37.5, 126.9), "gps", 1L, 5f, now - 5_000_000_000L)
        assertTrue(LocationFixSelector.isUsable(fresh, now))
        assertTrue(LocationFixSelector.isUsable(fresh.copy(elapsedRealtimeNanos = now - 30_000_000_000L), now))
        assertFalse(LocationFixSelector.isUsable(fresh.copy(elapsedRealtimeNanos = now - 31_000_000_000L), now))
        assertFalse(LocationFixSelector.isUsable(fresh.copy(elapsedRealtimeNanos = now + 1L), now))
        assertFalse(LocationFixSelector.isUsable(fresh.copy(elapsedRealtimeNanos = 0L), now))
        assertFalse(LocationFixSelector.isUsable(fresh.copy(point = GeoPoint(Double.NaN, 126.9)), now))
        assertFalse(LocationFixSelector.isUsable(fresh.copy(point = GeoPoint(91.0, 181.0)), now))
    }

    @Test
    fun staleCoarseNetworkFixDoesNotOverwriteFresherOrMoreAccurateGpsFix() {
        val gpsFix = LocationFixCandidate(
            point = GeoPoint(37.5665, 126.9780),
            provider = "gps",
            timeMillis = 1_000_000L,
            accuracyMeters = 10f,
        )
        val coarseNetworkFix = LocationFixCandidate(
            point = GeoPoint(37.5500, 126.9200),
            provider = "network",
            timeMillis = 1_030_000L,
            accuracyMeters = 500f,
        )
        val muchNewerNetworkFix = LocationFixCandidate(
            point = GeoPoint(37.5700, 126.9800),
            provider = "network",
            timeMillis = 1_200_000L,
            accuracyMeters = 500f,
        )

        assertEquals(gpsFix, LocationFixSelector.selectBest(listOf(gpsFix, coarseNetworkFix)))
        assertFalse(LocationFixSelector.isBetterCandidate(coarseNetworkFix, gpsFix))
        assertTrue(LocationFixSelector.isBetterCandidate(muchNewerNetworkFix, gpsFix))
        assertEquals("GPS", LocationFixSelector.providerDisplayName("gps"))
        assertEquals("네트워크", LocationFixSelector.providerDisplayName("network"))
    }
}

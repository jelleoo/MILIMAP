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

    @Test
    fun registrationFailureMessageSuppressesPartialProviderFailures() {
        assertEquals(
            null,
            LocationFixSelector.registrationFailureMessage(
                registeredProviders = listOf("gps"),
                failedProviders = listOf("network"),
            ),
        )
        assertEquals(
            "네트워크 위치를 시작할 수 없습니다.",
            LocationFixSelector.registrationFailureMessage(
                registeredProviders = emptyList(),
                failedProviders = listOf("network"),
            ),
        )
        assertEquals(
            "사용 가능한 위치 제공자가 없습니다.",
            LocationFixSelector.registrationFailureMessage(
                registeredProviders = emptyList(),
                failedProviders = listOf("gps", "network"),
            ),
        )
    }
}

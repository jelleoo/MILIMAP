package com.example.milipercent.ui.map

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class NaverMapUrlTest {
    @Test
    fun placeUrlEncodesNameCoordinatesAndFinalApplicationId() {
        val url = NaverMapUrl.place("테스트 가게", 37.5, 126.9, "com.example.militarybenefits")

        assertEquals(
            "nmap://place?lat=37.5&lng=126.9&name=%ED%85%8C%EC%8A%A4%ED%8A%B8+%EA%B0%80%EA%B2%8C&appname=com.example.militarybenefits",
            url,
        )
    }

    @Test
    fun missingCoordinatesUsesEncodedSearchUrl() {
        assertEquals(
            "nmap://search?query=%ED%85%8C%EC%8A%A4%ED%8A%B8+%EA%B0%80%EA%B2%8C&appname=com.example.militarybenefits",
            NaverMapUrl.search("테스트 가게", "com.example.militarybenefits"),
        )
        assertTrue(NaverMapUrl.webSearch("테스트 가게").contains("%20"))
    }
}

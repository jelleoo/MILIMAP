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

    @Test
    fun coordinateMissingStoreSearchesByNameAndRegisteredAddress() {
        assertEquals(
            "nmap://search?query=%ED%85%8C%EC%8A%A4%ED%8A%B8+%EA%B0%80%EA%B2%8C+%EC%84%9C%EC%9A%B8%ED%8A%B9%EB%B3%84%EC%8B%9C+%EB%A7%88%ED%8F%AC%EA%B5%AC+%EC%9B%94%EB%93%9C%EC%BB%B5%EB%B6%81%EB%A1%9C+1&appname=com.example.militarybenefits",
            NaverMapUrl.search(
                "테스트 가게",
                "서울특별시 마포구 월드컵북로 1",
                "com.example.militarybenefits",
            ),
        )
    }

    @Test
    fun coordinateMissingStoreWebSearchesByNameAndRegisteredAddress() {
        assertEquals(
            "https://map.naver.com/p/search/%ED%85%8C%EC%8A%A4%ED%8A%B8%20%EA%B0%80%EA%B2%8C%20%EC%84%9C%EC%9A%B8%ED%8A%B9%EB%B3%84%EC%8B%9C%20%EB%A7%88%ED%8F%AC%EA%B5%AC%20%EC%9B%94%EB%93%9C%EC%BB%B5%EB%B6%81%EB%A1%9C%201",
            NaverMapUrl.webSearch(
                "테스트 가게",
                "서울특별시 마포구 월드컵북로 1",
            ),
        )
    }
}

package com.example.militarybenefits.ui.map

import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import org.junit.Assert.assertEquals
import org.junit.Test

class NaverMapUrlTest {
    @Test
    fun `place URL contains coordinates store name and app name`() {
        val url = NaverMapUrl.place(
            storeName = "현선이네 숭실대점",
            latitude = 37.4987842,
            longitude = 126.9520631,
            appName = "com.example.militarybenefits.debug",
        )

        assertEquals("nmap://place", url.substringBefore('?'))
        assertEquals("37.4987842", url.queryParameter("lat"))
        assertEquals("126.9520631", url.queryParameter("lng"))
        assertEquals("현선이네 숭실대점", url.queryParameter("name"))
        assertEquals("com.example.militarybenefits.debug", url.queryParameter("appname"))
    }

    @Test
    fun `search URL encodes Korean store name`() {
        val url = NaverMapUrl.search("밀리맵 카페", "com.example.militarybenefits")

        assertEquals("nmap://search", url.substringBefore('?'))
        assertEquals("밀리맵 카페", url.queryParameter("query"))
    }

    @Test
    fun `web fallback encodes spaces as path values`() {
        assertEquals(
            "https://map.naver.com/p/search/%EB%B0%80%EB%A6%AC%EB%A7%B5%20%EC%B9%B4%ED%8E%98",
            NaverMapUrl.webSearch("밀리맵 카페"),
        )
    }
}

private fun String.queryParameter(name: String): String? =
    substringAfter('?', missingDelimiterValue = "")
        .split('&')
        .mapNotNull { pair ->
            val separatorIndex = pair.indexOf('=')
            if (separatorIndex < 0) return@mapNotNull null
            pair.substring(0, separatorIndex) to pair.substring(separatorIndex + 1)
        }
        .firstOrNull { (key) -> key == name }
        ?.second
        ?.let { URLDecoder.decode(it, StandardCharsets.UTF_8.name()) }

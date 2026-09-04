package com.example.milipercent.ui.map

import java.net.URLEncoder
import java.nio.charset.StandardCharsets

internal object NaverMapUrl {
    const val PACKAGE_NAME = "com.nhn.android.nmap"

    fun place(storeName: String, latitude: Double, longitude: Double, appName: String): String =
        "nmap://place?lat=$latitude&lng=$longitude&name=${storeName.queryEncoded()}&appname=${appName.queryEncoded()}"

    fun search(storeName: String, appName: String): String =
        "nmap://search?query=${storeName.queryEncoded()}&appname=${appName.queryEncoded()}"

    fun webSearch(storeName: String): String =
        "https://map.naver.com/p/search/${storeName.pathEncoded()}"

    private fun String.queryEncoded(): String = URLEncoder.encode(this, StandardCharsets.UTF_8.name())

    private fun String.pathEncoded(): String = queryEncoded().replace("+", "%20")
}

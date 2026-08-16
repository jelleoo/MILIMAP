package com.example.militarybenefits.data

import android.util.Xml
import org.xmlpull.v1.XmlPullParser
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import kotlin.math.ceil

data class MmaStore(
    val rowNumber: String,
    val name: String,
    val address: String,
    val phone: String?,
    val benefitGroup: String?,
)

class MmaBenefitApi {
    fun fetchAll(serviceKey: String): List<MmaStore> {
        require(serviceKey.isNotBlank()) { "공공데이터포털 서비스 키가 설정되지 않았습니다." }
        val pageSize = 500
        val first = fetchPage(serviceKey, 1, pageSize)
        val pages = ceil(first.totalCount.toDouble() / pageSize).toInt().coerceAtLeast(1)
        val result = first.items.toMutableList()
        for (page in 2..pages) result += fetchPage(serviceKey, page, pageSize).items
        return result.distinctBy { it.rowNumber.ifBlank { "${it.name}|${it.address}" } }
    }

    private fun fetchPage(serviceKey: String, page: Int, rows: Int): Page {
        val key = if ('%' in serviceKey) serviceKey.trim() else URLEncoder.encode(serviceKey.trim(), "UTF-8")
        val url = URL(
            "https://apis.data.go.kr/1300000/JwctMmaUdhygigwan/getjwctMmaUdhygigwan" +
                "?numOfRows=$rows&pageNo=$page&serviceKey=$key",
        )
        val connection = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 15_000
            readTimeout = 25_000
            setRequestProperty("Accept", "application/xml")
        }
        return try {
            val stream = if (connection.responseCode in 200..299) connection.inputStream else connection.errorStream
            stream.use { parsePage(it) }
        } finally {
            connection.disconnect()
        }
    }

    private fun parsePage(input: java.io.InputStream): Page {
        val parser = Xml.newPullParser().apply {
            setFeature(XmlPullParser.FEATURE_PROCESS_NAMESPACES, false)
            setInput(input, "UTF-8")
        }
        val items = mutableListOf<MmaStore>()
        var totalCount = 0
        var currentTag = ""
        var current: MutableMap<String, String>? = null
        var resultCode: String? = null
        var resultMessage: String? = null
        var event = parser.eventType
        while (event != XmlPullParser.END_DOCUMENT) {
            when (event) {
                XmlPullParser.START_TAG -> {
                    currentTag = parser.name
                    if (currentTag == "item") current = mutableMapOf()
                }
                XmlPullParser.TEXT -> {
                    val text = parser.text.trim()
                    if (text.isNotEmpty()) {
                        when {
                            current != null && currentTag != "item" -> current[currentTag] =
                                (current[currentTag].orEmpty() + text).trim()
                            currentTag == "totalCount" -> totalCount = text.toIntOrNull() ?: totalCount
                            currentTag == "resultCode" -> resultCode = text
                            currentTag == "resultMsg" -> resultMessage = text
                        }
                    }
                }
                XmlPullParser.END_TAG -> {
                    if (parser.name == "item") {
                        current?.let { values ->
                            val name = values["udaeGgm"].orEmpty().trim()
                            val address = values["juso"].orEmpty().trim()
                            if (name.isNotBlank()) {
                                items += MmaStore(
                                    rowNumber = values["rnum"].orEmpty(),
                                    name = name,
                                    address = address,
                                    phone = values["udgigwanTelno"]?.takeIf(String::isNotBlank),
                                    benefitGroup = values["gtcdNm"]?.takeIf(String::isNotBlank),
                                )
                            }
                        }
                        current = null
                    }
                    currentTag = ""
                }
            }
            event = parser.next()
        }
        if (resultCode != null && resultCode !in setOf("00", "0", "NORMAL_SERVICE")) {
            error(resultMessage ?: "나라사랑가게 API 호출에 실패했습니다. ($resultCode)")
        }
        return Page(totalCount = totalCount.coerceAtLeast(items.size), items = items)
    }

    private data class Page(val totalCount: Int, val items: List<MmaStore>)
}

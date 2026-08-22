package com.example.milipercent.network

import com.example.milipercent.model.BenefitPage
import java.io.IOException
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URL
import java.net.URLDecoder
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

interface BenefitPageSource {
    suspend fun getBenefitPage(pageNo: Int, numOfRows: Int): BenefitPage
}

class BenefitApiClient(
    private val apiUrl: String,
    private val serviceKey: String,
    private val xmlParser: BenefitXmlParser,
) : BenefitPageSource {
    override suspend fun getBenefitPage(
        pageNo: Int,
        numOfRows: Int,
    ): BenefitPage = withContext(Dispatchers.IO) {
        require(apiUrl.isNotBlank()) { "local.properties의 MMA_API_URL을 확인하세요." }
        require(serviceKey.isNotBlank()) { "local.properties의 MMA_SERVICE_KEY를 확인하세요." }
        require(pageNo > 0) { "pageNo는 1 이상이어야 합니다." }
        require(numOfRows > 0) { "numOfRows는 1 이상이어야 합니다." }

        val connection = try {
            (buildRequestUrl(pageNo, numOfRows).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = TIMEOUT_MILLIS
                readTimeout = TIMEOUT_MILLIS
                setRequestProperty("Accept", "application/xml")
            }
        } catch (exception: Exception) {
            // URL-related exception messages can contain the complete query string.
            throw BenefitNetworkException("API 요청을 준비하지 못했습니다.", exception)
        }

        try {
            val responseCode = connection.responseCode
            if (responseCode !in 200..299) {
                runCatching { connection.errorStream?.close() }
                throw BenefitNetworkException("HTTP 오류가 발생했습니다. ($responseCode)")
            }

            connection.inputStream.use(xmlParser::parse)
        } catch (exception: BenefitApiException) {
            throw exception
        } catch (exception: BenefitParsingException) {
            throw exception
        } catch (exception: SocketTimeoutException) {
            throw BenefitNetworkException("API 요청 시간이 초과되었습니다.", exception)
        } catch (exception: IOException) {
            throw BenefitNetworkException("서버와 통신하지 못했습니다.", exception)
        } finally {
            connection.disconnect()
        }
    }

    private fun buildRequestUrl(pageNo: Int, numOfRows: Int): URL {
        val separator = if (apiUrl.contains('?')) "&" else "?"
        val query = buildString {
            append("serviceKey=")
            append(encodeServiceKey(serviceKey.trim()))
            append("&pageNo=")
            append(pageNo)
            append("&numOfRows=")
            append(numOfRows)
        }
        return URL(apiUrl.trim() + separator + query)
    }

    private fun encodeServiceKey(key: String): String {
        val decodedKey = if (PERCENT_ENCODING.containsMatchIn(key)) {
            // Preserve a literal '+' while decoding existing %XX sequences.
            runCatching {
                URLDecoder.decode(
                    key.replace("+", "%2B"),
                    StandardCharsets.UTF_8.name(),
                )
            }.getOrDefault(key)
        } else {
            key
        }

        return URLEncoder.encode(decodedKey, StandardCharsets.UTF_8.name())
            .replace("+", "%20")
    }

    private companion object {
        const val TIMEOUT_MILLIS = 10_000
        val PERCENT_ENCODING = Regex("%[0-9a-fA-F]{2}")
    }
}

class BenefitNetworkException(message: String, cause: Throwable? = null) :
    IOException(message, cause)

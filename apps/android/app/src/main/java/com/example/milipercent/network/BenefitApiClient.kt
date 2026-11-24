package com.example.milipercent.network

import com.example.milipercent.model.BenefitPage
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URL
import java.net.URLDecoder
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

interface BenefitPageSource {
    suspend fun getBenefitPage(pageNo: Int, numOfRows: Int): BenefitPage
}

class BenefitApiClient(
    private val apiUrl: String,
    private val serviceKey: String,
    private val xmlParser: BenefitXmlParser,
    private val allowedSchemes: Set<String> = DEFAULT_ALLOWED_SCHEMES,
    private val maxResponseBytes: Int = DEFAULT_MAX_RESPONSE_BYTES,
) : BenefitPageSource {
    override suspend fun getBenefitPage(
        pageNo: Int,
        numOfRows: Int,
    ): BenefitPage = withContext(Dispatchers.IO) {
        require(apiUrl.isNotBlank()) { "local.properties의 MMA_API_URL을 확인하세요." }
        require(serviceKey.isNotBlank()) { "local.properties의 MMA_SERVICE_KEY를 확인하세요." }
        require(pageNo > 0) { "pageNo는 1 이상이어야 합니다." }
        require(numOfRows > 0) { "numOfRows는 1 이상이어야 합니다." }
        require(maxResponseBytes > 0) { "maxResponseBytes는 1 이상이어야 합니다." }

        val baseUrl = try {
            URL(apiUrl.trim())
        } catch (_: Exception) {
            throw BenefitNetworkException("API 요청을 준비하지 못했습니다.")
        }
        val scheme = baseUrl.protocol.lowercase(Locale.ROOT)
        if (scheme !in allowedSchemes || baseUrl.host.isNullOrBlank()) {
            throw BenefitNetworkException("API 요청을 준비하지 못했습니다.")
        }

        val connection = try {
            (buildRequestUrl(baseUrl, pageNo, numOfRows).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                instanceFollowRedirects = false
                connectTimeout = TIMEOUT_MILLIS
                readTimeout = TIMEOUT_MILLIS
                setRequestProperty("Accept", "application/xml")
            }
        } catch (_: Exception) {
            // URL-related exception messages can contain the complete credential query.
            throw BenefitNetworkException("API 요청을 준비하지 못했습니다.")
        }

        try {
            val responseCode = connection.responseCode
            if (responseCode !in 200..299) {
                runCatching { connection.errorStream?.close() }
                throw BenefitNetworkException("HTTP 오류가 발생했습니다. ($responseCode)")
            }

            val payload = connection.inputStream.use { stream ->
                readBoundedBytes(stream, maxResponseBytes)
            }
            ByteArrayInputStream(payload).use(xmlParser::parse)
        } catch (exception: BenefitNetworkException) {
            throw exception
        } catch (exception: BenefitApiException) {
            throw exception
        } catch (exception: BenefitParsingException) {
            throw exception
        } catch (_: SocketTimeoutException) {
            throw BenefitNetworkException("API 요청 시간이 초과되었습니다.")
        } catch (_: IOException) {
            throw BenefitNetworkException("서버와 통신하지 못했습니다.")
        } finally {
            connection.disconnect()
        }
    }

    private fun readBoundedBytes(stream: InputStream, limitBytes: Int): ByteArray {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(8 * 1024)
        var total = 0
        while (true) {
            val read = stream.read(buffer)
            if (read == -1) break
            total += read
            if (total > limitBytes) {
                throw BenefitNetworkException("API 응답 크기가 허용 한도를 초과했습니다.")
            }
            output.write(buffer, 0, read)
        }
        return output.toByteArray()
    }

    private fun buildRequestUrl(baseUrl: URL, pageNo: Int, numOfRows: Int): URL {
        val baseUrlText = baseUrl.toExternalForm()
        val separator = if (baseUrlText.contains('?')) "&" else "?"
        val query = buildString {
            append("serviceKey=")
            append(encodeServiceKey(serviceKey.trim()))
            append("&pageNo=")
            append(pageNo)
            append("&numOfRows=")
            append(numOfRows)
        }
        return URL(baseUrlText + separator + query)
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
        const val DEFAULT_MAX_RESPONSE_BYTES = 10 * 1024 * 1024
        val DEFAULT_ALLOWED_SCHEMES = setOf("https")
        val PERCENT_ENCODING = Regex("%[0-9a-fA-F]{2}")
    }
}

class BenefitNetworkException(message: String) : IOException(message)

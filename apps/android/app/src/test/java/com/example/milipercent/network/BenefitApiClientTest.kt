package com.example.milipercent.network

import java.io.PrintWriter
import java.io.StringWriter
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class BenefitApiClientTest {
    @Test
    fun `잘못된 base URL 준비 실패는 service key를 throwable에 남기지 않는다`() {
        val exception = requestFailure(
            apiUrl = "http://[",
            serviceKey = SENTINEL_SERVICE_KEY,
        )

        assertEquals("API 요청을 준비하지 못했습니다.", exception.message)
        exception.assertCredentialSafe()
    }

    @Test
    fun `timeout 실패는 URL cause와 service key를 throwable에 남기지 않는다`() {
        val exception = withTestUrlHandler {
            requestFailure(
                apiUrl = "$TEST_PROTOCOL://example.test/timeout",
                serviceKey = SENTINEL_SERVICE_KEY,
            )
        }

        assertEquals("API 요청 시간이 초과되었습니다.", exception.message)
        exception.assertCredentialSafe()
    }

    @Test
    fun `IO 실패는 URL cause와 service key를 throwable에 남기지 않는다`() {
        val exception = withTestUrlHandler {
            requestFailure(
                apiUrl = "$TEST_PROTOCOL://example.test/io",
                serviceKey = SENTINEL_SERVICE_KEY,
            )
        }

        assertEquals("서버와 통신하지 못했습니다.", exception.message)
        exception.assertCredentialSafe()
    }

    private fun requestFailure(
        apiUrl: String,
        serviceKey: String,
    ): BenefitNetworkException = assertThrows(BenefitNetworkException::class.java) {
        runBlocking {
            BenefitApiClient(
                apiUrl = apiUrl,
                serviceKey = serviceKey,
                xmlParser = BenefitXmlParser(),
            ).getBenefitPage(pageNo = 1, numOfRows = 100)
        }
    }

    private fun <T> withTestUrlHandler(block: () -> T): T {
        val previous = System.getProperty(URL_HANDLER_PACKAGES_PROPERTY)
        val packages = listOfNotNull(previous, TEST_HANDLER_PACKAGE)
            .filter(String::isNotBlank)
            .distinct()
            .joinToString("|")
        System.setProperty(URL_HANDLER_PACKAGES_PROPERTY, packages)
        return try {
            block()
        } finally {
            if (previous == null) {
                System.clearProperty(URL_HANDLER_PACKAGES_PROPERTY)
            } else {
                System.setProperty(URL_HANDLER_PACKAGES_PROPERTY, previous)
            }
        }
    }

    private fun Throwable.renderCompleteThrowable(): String = StringWriter().also { writer ->
        PrintWriter(writer).use(::printStackTrace)
    }.toString()

    private fun BenefitNetworkException.assertCredentialSafe() {
        val completeCauseChain = generateSequence<Throwable>(this) { it.cause }.toList()
        assertTrue(completeCauseChain.all { it is BenefitNetworkException })
        assertFalse(renderCompleteThrowable().contains(SENTINEL_SERVICE_KEY))
    }

    private companion object {
        const val SENTINEL_SERVICE_KEY = "SENTINEL_SERVICE_KEY_MUST_NEVER_APPEAR"
        const val TEST_PROTOCOL = "milispottest"
        const val URL_HANDLER_PACKAGES_PROPERTY = "java.protocol.handler.pkgs"
        const val TEST_HANDLER_PACKAGE = "com.example.milipercent.network.protocol"
    }
}

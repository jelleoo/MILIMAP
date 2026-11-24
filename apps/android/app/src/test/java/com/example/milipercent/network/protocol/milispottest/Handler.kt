package com.example.milipercent.network.protocol.milispottest

import java.io.ByteArrayInputStream
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URL
import java.net.URLConnection
import java.net.URLStreamHandler

class Handler : URLStreamHandler() {
    override fun openConnection(url: URL): URLConnection = object : HttpURLConnection(url) {
        override fun connect() = Unit

        override fun disconnect() = Unit

        override fun usingProxy(): Boolean = false

        override fun getResponseCode(): Int = when (url.path) {
            "/timeout" -> throw SocketTimeoutException(url.toExternalForm())
            "/redirect" -> {
                if (instanceFollowRedirects) {
                    throw AssertionError("instanceFollowRedirects must be false to prevent serviceKey leakage")
                }
                HTTP_MOVED_TEMP
            }
            "/oversized" -> HTTP_OK
            else -> throw IOException(url.toExternalForm())
        }

        override fun getInputStream(): InputStream = when (url.path) {
            "/oversized" -> ByteArrayInputStream(ByteArray(4096) { 'A'.code.toByte() })
            else -> super.getInputStream()
        }
    }
}

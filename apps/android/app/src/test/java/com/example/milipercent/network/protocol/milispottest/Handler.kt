package com.example.milipercent.network.protocol.milispottest

import java.io.IOException
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
            else -> throw IOException(url.toExternalForm())
        }
    }
}

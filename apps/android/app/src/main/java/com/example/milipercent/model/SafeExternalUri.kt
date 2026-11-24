package com.example.milipercent.model

import java.net.URI
import java.util.Locale

object SafeExternalUri {
    private val ALLOWED_HTTP_SCHEMES = setOf("http", "https")
    private val CONTROL_OR_WHITESPACE = Regex("[\\s\\p{Cntrl}]")
    private val ALLOWED_DIAL_CHARS = Regex("[^0-9+*#-]")

    fun resolveSafeHttpUrl(raw: String?): String? {
        val candidate = raw
            ?.substringBefore(" | ")
            ?.trim()
            ?.takeIf(String::isNotEmpty)
            ?: return null
        if (CONTROL_OR_WHITESPACE.containsMatchIn(candidate)) return null

        val uri = runCatching { URI(candidate) }.getOrNull() ?: return null
        val scheme = uri.scheme?.lowercase(Locale.ROOT) ?: return null
        if (scheme !in ALLOWED_HTTP_SCHEMES) return null
        if (uri.host.isNullOrBlank()) return null
        if (uri.rawUserInfo != null) return null
        return candidate
    }

    fun sanitizeDialablePhone(raw: String?): String? {
        val source = raw
            ?.substringBefore(';')
            ?.substringBefore(',')
            ?.trim()
            ?.takeIf(String::isNotEmpty)
            ?: return null
        val cleaned = ALLOWED_DIAL_CHARS.replace(source, "")
        return cleaned.takeIf { value -> value.any(Char::isDigit) }
    }
}

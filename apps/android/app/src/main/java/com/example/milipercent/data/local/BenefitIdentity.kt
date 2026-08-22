package com.example.milipercent.data.local

import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.Locale

object BenefitIdentity {
    fun create(
        sourceType: String,
        name: String,
        address: String?,
    ): String {
        val identityText = listOf(
            normalize(sourceType),
            normalize(name),
            normalize(address),
        ).joinToString(separator = "\u0000")
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(identityText.toByteArray(StandardCharsets.UTF_8))
            .joinToString(separator = "") { byte -> "%02x".format(byte.toInt() and 0xff) }
        return "mma_$digest"
    }

    private fun normalize(value: String?): String = value
        ?.trim()
        ?.replace(WHITESPACE_REGEX, "")
        ?.lowercase(Locale.ROOT)
        .orEmpty()

    private val WHITESPACE_REGEX = Regex("\\s+")
}

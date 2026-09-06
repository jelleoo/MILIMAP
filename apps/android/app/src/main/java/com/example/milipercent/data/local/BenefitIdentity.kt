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

    fun mmaId(name: String, address: String?): String =
        "mma_" + sha256(normalizedKey(name, address))

    fun normalizedKey(name: String, address: String?): String =
        normalize(name) + "\u0000" + normalizeAddress(address)

    private fun sha256(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(StandardCharsets.UTF_8))
        .joinToString(separator = "") { byte -> "%02x".format(byte.toInt() and 0xff) }

    private fun normalize(value: String?): String = value
        ?.trim()
        ?.replace(PUNCTUATION_REGEX, "")
        ?.replace(WHITESPACE_REGEX, "")
        ?.lowercase(Locale.ROOT)
        .orEmpty()

    private fun normalizeAddress(value: String?): String = normalize(value)
        .replace("서울특별시", "서울")
        .replace("서울시", "서울")
        .replace("경기도", "경기")
        .replace("인천광역시", "인천")

    private val WHITESPACE_REGEX = Regex("\\s+")
    private val PUNCTUATION_REGEX = Regex("[,()]")
}

package com.example.milipercent.data.account

import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.security.SecureRandom

data class PasswordDigest(
    val saltHex: String,
    val hashHex: String,
)

class PasswordHasher(
    private val secureRandom: SecureRandom = SecureRandom(),
) {
    fun create(password: String): PasswordDigest {
        val salt = ByteArray(SALT_BYTE_COUNT).also(secureRandom::nextBytes)
        return PasswordDigest(
            saltHex = salt.toHex(),
            hashHex = hash(salt, password).toHex(),
        )
    }

    fun verify(password: String, saltHex: String, expectedHashHex: String): Boolean = runCatching {
        MessageDigest.isEqual(hash(saltHex.hexToBytes(), password), expectedHashHex.hexToBytes())
    }.getOrDefault(false)

    private fun hash(salt: ByteArray, password: String): ByteArray =
        MessageDigest.getInstance("SHA-256")
            .digest(salt + password.toByteArray(StandardCharsets.UTF_8))

    private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it.toInt() and 0xff) }

    private fun String.hexToBytes(): ByteArray {
        require(length % 2 == 0) { "16진수 길이가 올바르지 않습니다." }
        return chunked(2).map { it.toInt(16).toByte() }.toByteArray()
    }

    private companion object {
        const val SALT_BYTE_COUNT = 16
    }
}

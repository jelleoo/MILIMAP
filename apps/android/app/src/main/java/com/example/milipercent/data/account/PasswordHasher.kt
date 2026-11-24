package com.example.milipercent.data.account

import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

data class PasswordDigest(
    val saltHex: String,
    val hashHex: String,
)

class PasswordHasher(
    private val secureRandom: SecureRandom = SecureRandom(),
    private val iterations: Int = DEFAULT_PBKDF2_ITERATIONS,
) {
    init {
        require(iterations in MIN_PBKDF2_ITERATIONS..MAX_PBKDF2_ITERATIONS) {
            "PBKDF2 반복 횟수가 허용 범위를 벗어났습니다."
        }
    }

    fun create(password: String): PasswordDigest {
        val salt = ByteArray(SALT_BYTE_COUNT).also(secureRandom::nextBytes)
        val derived = pbkdf2HmacSha256(password, salt, iterations, KEY_LENGTH_BYTES)
        return PasswordDigest(
            saltHex = salt.toHex(),
            hashHex = "$PBKDF2_PREFIX\$$iterations\$${derived.toHex()}",
        )
    }

    fun verify(password: String, saltHex: String, expectedHashHex: String): Boolean = runCatching {
        val salt = saltHex.hexToBytes()
        if (salt.isEmpty() || expectedHashHex.isBlank()) return false

        if (expectedHashHex.startsWith("$PBKDF2_PREFIX\$")) {
            val parts = expectedHashHex.split('$')
            if (parts.size != 3 || parts[0] != PBKDF2_PREFIX) return false
            val storedIterations = parts[1].toIntOrNull() ?: return false
            if (storedIterations !in MIN_PBKDF2_ITERATIONS..MAX_PBKDF2_ITERATIONS) return false
            val expectedBytes = parts[2].hexToBytes()
            if (expectedBytes.isEmpty()) return false
            val actualBytes = pbkdf2HmacSha256(password, salt, storedIterations, expectedBytes.size)
            MessageDigest.isEqual(actualBytes, expectedBytes)
        } else {
            val expectedBytes = expectedHashHex.hexToBytes()
            if (expectedBytes.size != LEGACY_SHA256_BYTES) return false
            MessageDigest.isEqual(legacySha256(salt, password), expectedBytes)
        }
    }.getOrDefault(false)

    // Implemented via HmacSHA256 (RFC 2898) so PBKDF2-HMAC-SHA256 works identically on Android API 24-25 and API 26+.
    private fun pbkdf2HmacSha256(
        password: String,
        salt: ByteArray,
        iterationCount: Int,
        keyLengthBytes: Int,
    ): ByteArray {
        val mac = Mac.getInstance(HMAC_SHA256_ALGORITHM)
        val passwordBytes = password.toByteArray(StandardCharsets.UTF_8)
        // SecretKeySpec rejects an empty byte array on Java/Android; RFC 2104 pads short/empty keys with zero bytes.
        val keyBytes = if (passwordBytes.isEmpty()) ByteArray(1) else passwordBytes
        mac.init(SecretKeySpec(keyBytes, HMAC_SHA256_ALGORITHM))

        val hashLen = mac.macLength
        val blockCount = (keyLengthBytes + hashLen - 1) / hashLen
        val output = ByteArray(keyLengthBytes)
        var offset = 0

        for (blockIndex in 1..blockCount) {
            val saltWithIndex = ByteArray(salt.size + 4)
            salt.copyInto(saltWithIndex)
            saltWithIndex[salt.size] = (blockIndex ushr 24).toByte()
            saltWithIndex[salt.size + 1] = (blockIndex ushr 16).toByte()
            saltWithIndex[salt.size + 2] = (blockIndex ushr 8).toByte()
            saltWithIndex[salt.size + 3] = blockIndex.toByte()

            var u = mac.doFinal(saltWithIndex)
            val block = u.copyOf()
            for (i in 2..iterationCount) {
                u = mac.doFinal(u)
                for (j in block.indices) {
                    block[j] = (block[j].toInt() xor u[j].toInt()).toByte()
                }
            }

            val copyLen = minOf(hashLen, keyLengthBytes - offset)
            block.copyInto(output, destinationOffset = offset, startIndex = 0, endIndex = copyLen)
            offset += copyLen
        }
        return output
    }

    private fun legacySha256(salt: ByteArray, password: String): ByteArray =
        MessageDigest.getInstance("SHA-256")
            .digest(salt + password.toByteArray(StandardCharsets.UTF_8))

    private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it.toInt() and 0xff) }

    private fun String.hexToBytes(): ByteArray {
        require(length % 2 == 0) { "16진수 길이가 올바르지 않습니다." }
        return chunked(2).map { it.toInt(16).toByte() }.toByteArray()
    }

    companion object {
        const val PBKDF2_PREFIX = "pbkdf2_sha256"
        const val DEFAULT_PBKDF2_ITERATIONS = 120_000
        private const val MIN_PBKDF2_ITERATIONS = 10_000
        private const val MAX_PBKDF2_ITERATIONS = 1_000_000
        private const val SALT_BYTE_COUNT = 16
        private const val KEY_LENGTH_BYTES = 32
        private const val LEGACY_SHA256_BYTES = 32
        private const val HMAC_SHA256_ALGORITHM = "HmacSHA256"
    }
}

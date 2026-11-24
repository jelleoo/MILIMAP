package com.example.milipercent.data.account

import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PasswordHasherTest {
    @Test
    fun `same password verifies and wrong password does not`() {
        val digest = PasswordHasher(SecureRandom()).create("secret1")
        val hasher = PasswordHasher(SecureRandom())

        assertTrue(digest.hashHex.startsWith("${PasswordHasher.PBKDF2_PREFIX}\$"))
        assertTrue(hasher.verify("secret1", digest.saltHex, digest.hashHex))
        assertFalse(hasher.verify("secret2", digest.saltHex, digest.hashHex))
    }

    @Test
    fun `same password receives distinct random salts and hashes`() {
        val hasher = PasswordHasher(SecureRandom())

        val first = hasher.create("secret1")
        val second = hasher.create("secret1")

        assertFalse(first.saltHex == second.saltHex)
        assertFalse(first.hashHex == second.hashHex)
    }

    @Test
    fun `pbkdf2 digest matches jvm SecretKeyFactory PBKDF2WithHmacSHA256`() {
        val iterations = 10_000
        val hasher = PasswordHasher(SecureRandom(), iterations = iterations)
        val digest = hasher.create("군인혜택!2026")
        val saltBytes = digest.saltHex.chunked(2).map { it.toInt(16).toByte() }.toByteArray()

        val spec = PBEKeySpec("군인혜택!2026".toCharArray(), saltBytes, iterations, 256)
        val expectedKeyHex = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
            .generateSecret(spec)
            .encoded
            .joinToString("") { "%02x".format(it.toInt() and 0xff) }

        assertEquals("${PasswordHasher.PBKDF2_PREFIX}\$$iterations\$$expectedKeyHex", digest.hashHex)
        assertTrue(hasher.verify("군인혜택!2026", digest.saltHex, digest.hashHex))
    }

    @Test
    fun `legacy single round sha256 hash remains verifiable for backward compatibility`() {
        val saltHex = "00112233445566778899aabbccddeeff"
        val saltBytes = saltHex.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
        val legacyHashHex = MessageDigest.getInstance("SHA-256")
            .digest(saltBytes + "legacyPass1".toByteArray(StandardCharsets.UTF_8))
            .joinToString("") { "%02x".format(it.toInt() and 0xff) }
        val hasher = PasswordHasher(SecureRandom())

        assertTrue(hasher.verify("legacyPass1", saltHex, legacyHashHex))
        assertFalse(hasher.verify("wrongPass1", saltHex, legacyHashHex))
    }

    @Test
    fun `malformed hashes and out of range iterations fail verification`() {
        val hasher = PasswordHasher(SecureRandom())
        val saltHex = "00112233445566778899aabbccddeeff"

        assertFalse(hasher.verify("secret1", saltHex, ""))
        assertFalse(hasher.verify("secret1", saltHex, "pbkdf2_sha256\$1\$abcd"))
        assertFalse(hasher.verify("secret1", saltHex, "pbkdf2_sha256\$99999999\$abcd"))
        assertFalse(hasher.verify("secret1", "", "00".repeat(32)))
        assertFalse(hasher.verify("secret1", "zz", "00".repeat(32)))
    }
}

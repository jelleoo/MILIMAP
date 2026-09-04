package com.example.milipercent.data.account

import java.security.SecureRandom
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PasswordHasherTest {
    @Test
    fun `same password verifies and wrong password does not`() {
        val digest = PasswordHasher(SecureRandom()).create("secret1")
        val hasher = PasswordHasher(SecureRandom())

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
}

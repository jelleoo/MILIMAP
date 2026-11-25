package com.example.milipercent.data.account

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.example.milipercent.data.local.BenefitDatabase
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RoomAccountRepositoryTest {
    private lateinit var database: BenefitDatabase
    private lateinit var repository: RoomAccountRepository

    @Before
    fun createDatabase() {
        database = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(),
            BenefitDatabase::class.java,
        ).allowMainThreadQueries().build()
        repository = RoomAccountRepository(database, PasswordHasher())
    }

    @After
    fun closeDatabase() = database.close()

    @Test
    fun firstUserIsAdminAndLaterUserIsNot() = runBlocking {
        val first = repository.register(" FIRST@EXAMPLE.COM ", "첫 사용자", "secret1").getOrThrow()
        val second = repository.register("second@example.com", "둘째 사용자", "secret2").getOrThrow()

        assertTrue(first.isAdmin)
        assertFalse(second.isAdmin)
        assertEquals("first@example.com", first.email)
        assertEquals(2, database.accountDao().count())
    }

    @Test
    fun registrationValidatesInputAndNormalizesDuplicateEmail() = runBlocking {
        assertTrue(repository.register("invalid", "이름", "secret1").isFailure)
        assertTrue(repository.register("@", "이름", "secret1").isFailure)
        assertTrue(repository.register("a@b", "이름", "secret1").isFailure)
        assertTrue(repository.register("a@b.com", "가", "secret1").isFailure)
        assertTrue(repository.register("a@b.com", "이름", "short").isFailure)
        assertTrue(repository.register("a@b.com", "이름", "      ").isFailure)

        repository.register("soldier@example.com", "군인", "secret1").getOrThrow()
        val duplicate = repository.register(" SOLDIER@EXAMPLE.COM ", "군인", "secret1")

        assertTrue(duplicate.isFailure)
        assertEquals("이미 등록된 이메일입니다.", duplicate.exceptionOrNull()?.message)
    }

    @Test
    fun legacySha256AccountAutomaticallyUpgradesToPbkdf2OnLogin() = runBlocking {
        val saltHex = "00112233445566778899aabbccddeeff"
        val saltBytes = saltHex.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
        val legacyHashHex = java.security.MessageDigest.getInstance("SHA-256")
            .digest(saltBytes + "legacySecret1".toByteArray(java.nio.charset.StandardCharsets.UTF_8))
            .joinToString("") { "%02x".format(it.toInt() and 0xff) }
        database.accountDao().insert(
            com.example.milipercent.data.local.UserEntity(
                email = "legacy@example.com",
                displayName = "기존사용자",
                passwordSalt = saltHex,
                passwordHash = legacyHashHex,
                isAdmin = false,
            ),
        )

        val loggedIn = repository.login("legacy@example.com", "legacySecret1").getOrThrow()
        val upgraded = requireNotNull(database.accountDao().findByEmail("legacy@example.com"))

        assertEquals("legacy@example.com", loggedIn.email)
        assertTrue(upgraded.passwordHash.startsWith("${PasswordHasher.PBKDF2_PREFIX}\$"))
        assertTrue(repository.login("legacy@example.com", "legacySecret1").isSuccess)
    }

    @Test
    fun unknownEmailAndWrongPasswordShareOneErrorAndPlaintextIsNotStored() = runBlocking {
        repository.register("soldier@example.com", "군인", "secret1").getOrThrow()

        val unknown = repository.login("unknown@example.com", "secret1")
        val wrongPassword = repository.login("soldier@example.com", "wrong1")
        val stored = requireNotNull(database.accountDao().findByEmail("soldier@example.com"))

        assertTrue(unknown.isFailure)
        assertTrue(wrongPassword.isFailure)
        assertEquals(unknown.exceptionOrNull()?.message, wrongPassword.exceptionOrNull()?.message)
        assertFalse(stored.passwordHash.contains("secret1"))
        assertNull(database.accountDao().findByEmail("missing@example.com"))
    }
}

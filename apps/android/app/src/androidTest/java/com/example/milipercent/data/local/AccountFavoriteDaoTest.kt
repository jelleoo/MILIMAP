package com.example.milipercent.data.local

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AccountFavoriteDaoTest {
    private lateinit var database: BenefitDatabase
    private lateinit var accountDao: AccountDao
    private lateinit var favoriteDao: FavoriteDao
    private lateinit var benefitDao: BenefitDao

    @Before
    fun createDatabase() {
        database = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(),
            BenefitDatabase::class.java,
        ).allowMainThreadQueries().build()
        accountDao = database.accountDao()
        favoriteDao = database.favoriteDao()
        benefitDao = database.benefitDao()
    }

    @After
    fun closeDatabase() = database.close()

    @Test
    fun emailAndFavoritePairsAreUniqueAndUsersAreIsolated() = runBlocking {
        val firstUser = accountDao.insert(user("soldier@example.com"))
        val secondUser = accountDao.insert(user("other@example.com"))
        benefitDao.insertAll(listOf(benefit("benefit_1")))

        favoriteDao.insert(FavoriteEntity(firstUser, "benefit_1", 10))

        assertTrue(favoriteDao.contains(firstUser, "benefit_1"))
        assertFalse(favoriteDao.contains(secondUser, "benefit_1"))
        assertEquals(listOf("benefit_1"), favoriteDao.observeIds(firstUser).first())
        assertEquals(emptyList<String>(), favoriteDao.observeIds(secondUser).first())
        assertTrue(runCatching { favoriteDao.insert(FavoriteEntity(firstUser, "benefit_1", 20)) }.isFailure)
        assertTrue(runCatching { accountDao.insert(user("SOLDIER@EXAMPLE.COM")) }.isFailure)
    }

    @Test
    fun deletingEitherParentCascadesFavorite() = runBlocking {
        val userId = accountDao.insert(user("soldier@example.com"))
        benefitDao.insertAll(listOf(benefit("benefit_1"), benefit("benefit_2")))
        favoriteDao.insert(FavoriteEntity(userId, "benefit_1", 1))
        favoriteDao.insert(FavoriteEntity(userId, "benefit_2", 2))

        benefitDao.deleteByIdAndSource("benefit_1", MMA_SOURCE_TYPE)
        assertFalse(favoriteDao.contains(userId, "benefit_1"))
        assertTrue(favoriteDao.contains(userId, "benefit_2"))

        accountDao.deleteById(userId)
        assertFalse(favoriteDao.contains(userId, "benefit_2"))
    }

    private fun user(email: String) = UserEntity(
        email = email,
        displayName = "테스터",
        passwordSalt = "salt",
        passwordHash = "hash",
        isAdmin = false,
    )

    private fun benefit(id: String) = BenefitEntity(
        id = id,
        sourceType = MMA_SOURCE_TYPE,
        sourceRowNumber = null,
        name = id,
        address = "서울특별시 마포구",
        latitude = null,
        longitude = null,
        category = "기타",
        benefitType = "할인",
        benefitDescription = "설명",
        phone = null,
        eligibleTarget = null,
        usageCondition = null,
        verificationMethod = null,
        sourceLabel = "테스트",
        sourceUrl = null,
        lastVerifiedAt = null,
        status = "ACTIVE",
        district = "마포구",
        syncedAt = 1,
    )
}

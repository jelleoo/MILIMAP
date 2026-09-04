package com.example.milipercent.data.favorite

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.example.milipercent.data.local.BenefitDatabase
import com.example.milipercent.data.local.BenefitEntity
import com.example.milipercent.data.local.MMA_SOURCE_TYPE
import com.example.milipercent.data.local.UserEntity
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
class RoomFavoriteRepositoryTest {
    private lateinit var database: BenefitDatabase
    private lateinit var repository: RoomFavoriteRepository
    private var userId = 0L

    @Before
    fun setUp() = runBlocking {
        database = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(),
            BenefitDatabase::class.java,
        ).allowMainThreadQueries().build()
        userId = database.accountDao().insert(
            UserEntity(email = "user@example.com", displayName = "사용자", passwordSalt = "salt", passwordHash = "hash", isAdmin = false),
        )
        database.benefitDao().insertAll(listOf(benefit("seed-1")))
        repository = RoomFavoriteRepository(database)
    }

    @After
    fun tearDown() = database.close()

    @Test
    fun toggleAddsThenRemovesTheBenefitForOnlyThatUser() = runBlocking {
        assertTrue(repository.toggle(userId, "seed-1"))
        assertEquals(setOf("seed-1"), repository.observeIds(userId).first())
        assertFalse(repository.toggle(userId, "seed-1"))
        assertEquals(emptySet<String>(), repository.observeIds(userId).first())
    }

    private fun benefit(id: String) = BenefitEntity(
        id = id, sourceType = MMA_SOURCE_TYPE, sourceRowNumber = null, name = id,
        address = "서울특별시 마포구", latitude = null, longitude = null, category = "기타",
        benefitType = "할인", benefitDescription = "설명", phone = null, eligibleTarget = null,
        usageCondition = null, verificationMethod = null, sourceLabel = "테스트", sourceUrl = null,
        lastVerifiedAt = null, status = "ACTIVE", district = "마포구", syncedAt = 1,
    )
}

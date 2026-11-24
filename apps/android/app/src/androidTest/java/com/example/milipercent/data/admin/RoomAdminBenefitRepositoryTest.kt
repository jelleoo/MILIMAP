package com.example.milipercent.data.admin

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.example.milipercent.data.local.BenefitDatabase
import com.example.milipercent.data.local.BenefitSourceType
import com.example.milipercent.data.local.FavoriteEntity
import com.example.milipercent.data.local.UserEntity
import com.example.milipercent.model.BenefitStatus
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
class RoomAdminBenefitRepositoryTest {
    private lateinit var database: BenefitDatabase
    private lateinit var repository: RoomAdminBenefitRepository

    @Before
    fun setUp() {
        database = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(),
            BenefitDatabase::class.java,
        ).allowMainThreadQueries().build()
        repository = RoomAdminBenefitRepository(database, uuidFactory = { "fixed-id" })
    }

    @After
    fun tearDown() = database.close()

    @Test
    fun createUpdateEndAndDeleteKeepManualLocalOwnership() = runBlocking {
        val id = repository.create(input())
        assertEquals("manual_local_fixed-id", id)
        assertEquals(BenefitSourceType.MANUAL_LOCAL, database.benefitDao().getByIdOnce(id)?.let { BenefitSourceType.fromStorage(it.sourceType) })

        repository.update(id, input(name = "수정 가게"))
        assertEquals("수정 가게", database.benefitDao().getByIdOnce(id)?.name)
        repository.end(id)
        assertEquals(BenefitStatus.ENDED.name, database.benefitDao().getByIdOnce(id)?.status)
        assertTrue(repository.observeAll().first().any { it.id == id && it.status == BenefitStatus.ENDED })
        assertTrue(repository.deleteManual(id))
        assertFalse(repository.deleteManual(id))
    }

    @Test
    fun adminValidationRejectsBlankRequiredFields() = runBlocking {
        assertTrue(runCatching { repository.create(input(name = " ")) }.isFailure)
        assertTrue(runCatching { repository.create(input(benefitDescription = " ")) }.isFailure)
        assertTrue(runCatching { repository.create(input(sourceLabel = " ")) }.isFailure)
        assertTrue(runCatching { repository.create(input(sourceUrl = "file:///etc/passwd")) }.isFailure)
        assertTrue(runCatching { repository.create(input(sourceUrl = "intent://scan/#Intent;end")) }.isFailure)
        assertTrue(runCatching { repository.create(input(sourceUrl = "https://www.mma.go.kr/notice")) }.isSuccess)
        assertTrue(runCatching { repository.create(input(latitude = 37.5, longitude = null)) }.isFailure)
        assertTrue(runCatching { repository.create(input(latitude = null, longitude = 127.0)) }.isFailure)
        assertTrue(runCatching { repository.create(input(latitude = 91.0, longitude = 127.0)) }.isFailure)
        assertTrue(runCatching { repository.create(input(latitude = 37.5, longitude = 127.0)) }.isSuccess)
    }

    @Test
    fun updateAndEndPreserveFavoriteDbRowWhileEndedIsHiddenFromUserVisible() = runBlocking {
        val userId = database.accountDao().insert(
            UserEntity(email = "user@example.com", displayName = "사용자", passwordSalt = "salt", passwordHash = "hash", isAdmin = false),
        )
        val id = repository.create(input(name = "수동 가게"))
        database.favoriteDao().insert(FavoriteEntity(userId, id, 100L))

        repository.update(id, input(name = "수정된 수동 가게"))
        assertTrue(database.favoriteDao().contains(userId, id))
        assertEquals("수정된 수동 가게", database.benefitDao().getByIdOnce(id)?.name)

        repository.end(id)
        assertTrue(database.favoriteDao().contains(userId, id))
        assertTrue(database.benefitDao().observeUserVisible(BenefitStatus.ENDED.name).first().none { it.id == id })
    }

    private fun input(
        name: String = "새 가게",
        benefitDescription: String = "군인 할인",
        sourceLabel: String = "운영팀 확인",
        sourceUrl: String? = null,
        latitude: Double? = null,
        longitude: Double? = null,
    ) = AdminBenefitInput(
        name = name, address = "서울특별시 마포구", latitude = latitude, longitude = longitude,
        category = "음식점", benefitType = "할인", benefitDescription = benefitDescription,
        phone = null, eligibleTarget = null, usageCondition = null, verificationMethod = null,
        sourceLabel = sourceLabel, sourceUrl = sourceUrl, lastVerifiedAt = null,
        status = BenefitStatus.ACTIVE, district = "마포구",
    )
}

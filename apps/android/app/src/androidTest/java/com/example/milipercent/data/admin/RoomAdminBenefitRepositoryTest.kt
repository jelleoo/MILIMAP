package com.example.milipercent.data.admin

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.example.milipercent.data.local.BenefitDatabase
import com.example.milipercent.data.local.BenefitSourceType
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
    }

    private fun input(
        name: String = "새 가게",
        benefitDescription: String = "군인 할인",
        sourceLabel: String = "운영팀 확인",
    ) = AdminBenefitInput(
        name = name, address = "서울특별시 마포구", latitude = null, longitude = null,
        category = "음식점", benefitType = "할인", benefitDescription = benefitDescription,
        phone = null, eligibleTarget = null, usageCondition = null, verificationMethod = null,
        sourceLabel = sourceLabel, sourceUrl = null, lastVerifiedAt = null,
        status = BenefitStatus.ACTIVE, district = "마포구",
    )
}

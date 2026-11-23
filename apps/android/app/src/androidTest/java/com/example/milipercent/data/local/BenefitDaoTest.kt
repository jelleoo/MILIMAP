package com.example.milipercent.data.local

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class BenefitDaoTest {
    private lateinit var database: BenefitDatabase
    private lateinit var dao: BenefitDao

    @Before
    fun createDatabase() {
        database = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(),
            BenefitDatabase::class.java,
        ).allowMainThreadQueries().build()
        dao = database.benefitDao()
    }

    @After
    fun closeDatabase() {
        database.close()
    }

    @Test
    fun insertObserveCountAndDelete() = runBlocking {
        val benefits = listOf(
            entity(id = "mma_1", rowNumber = 1, name = "가게 1"),
            entity(id = "mma_2", rowNumber = 2, name = "가게 2"),
        )

        dao.insertAll(benefits)

        assertEquals(2, dao.countBySource(MMA_SOURCE_TYPE))
        assertEquals(setOf("mma_1", "mma_2"), dao.observeBySource(MMA_SOURCE_TYPE).first().map { it.id }.toSet())

        dao.deleteBySource(MMA_SOURCE_TYPE)

        assertEquals(0, dao.countBySource(MMA_SOURCE_TYPE))
        assertTrue(dao.observeBySource(MMA_SOURCE_TYPE).first().isEmpty())
    }

    @Test
    fun transactionReplacesOnlyMmaApiData() = runBlocking {
        dao.insertAll(
            listOf(
                entity(id = "mma_old", rowNumber = 1, name = "기존 가게"),
                entity(
                    id = "manual_seed_1",
                    rowNumber = null,
                    name = "Seed 가게",
                    sourceType = MANUAL_SEED_SOURCE_TYPE,
                ),
                entity(
                    id = "manual_local_1",
                    rowNumber = null,
                    name = "Local 가게",
                    sourceType = MANUAL_LOCAL_SOURCE_TYPE,
                ),
            ),
        )

        val latest = listOf(
            entity(id = "mma_new_1", rowNumber = 10, name = "새 가게 1"),
            entity(id = "mma_new_2", rowNumber = 20, name = "새 가게 2"),
        )
        dao.replaceBySource(MMA_SOURCE_TYPE, latest)

        assertEquals(latest.map { it.id }.toSet(), dao.observeBySource(MMA_SOURCE_TYPE).first().map { it.id }.toSet())
        assertEquals(1, dao.countBySource(MANUAL_SEED_SOURCE_TYPE))
        assertEquals(1, dao.countBySource(MANUAL_LOCAL_SOURCE_TYPE))
    }

    @Test
    fun invalidReplacementDoesNotDeleteExistingCache() = runBlocking {
        val old = entity(id = "mma_old", rowNumber = 1, name = "기존 가게")
        dao.insertAll(listOf(old))

        val result = runCatching {
            dao.replaceBySource(
                MMA_SOURCE_TYPE,
                listOf(
                    entity(
                        id = "manual_wrong",
                        rowNumber = 2,
                        name = "잘못된 출처",
                        sourceType = MANUAL_LOCAL_SOURCE_TYPE,
                    ),
                ),
            )
        }

        assertTrue(result.isFailure)
        assertEquals(listOf(old), dao.observeBySource(MMA_SOURCE_TYPE).first())
    }

    @Test
    fun observeByIdReturnsExistingEntity() = runBlocking {
        val expected = entity(id = "mma_detail", rowNumber = 15, name = "상세 가게")
        dao.insertAll(listOf(expected))

        assertEquals(expected, dao.observeById("mma_detail").first())
    }

    @Test
    fun observeByIdReturnsNullForUnknownId() = runBlocking {
        dao.insertAll(listOf(entity(id = "mma_known", rowNumber = 1, name = "알려진 가게")))

        assertEquals(null, dao.observeById("mma_unknown").first())
    }

    @Test
    fun userVisibleFlowCombinesSourcesAndExcludesEnded() = runBlocking {
        dao.insertAll(
            listOf(
                entity("mma", 1, "MMA"),
                entity("seed", null, "Seed", MANUAL_SEED_SOURCE_TYPE, "ACTIVE"),
                entity("local", null, "Local", MANUAL_LOCAL_SOURCE_TYPE, "NEEDS_VERIFICATION"),
                entity("ended", null, "Ended", MANUAL_LOCAL_SOURCE_TYPE, "ENDED"),
            ),
        )

        val ids = dao.observeUserVisible(ManualBenefitStatus.ENDED.name).first().map { it.id }

        assertEquals(setOf("mma", "seed", "local"), ids.toSet())
    }

    @Test
    fun deletingManualLocalCannotDeleteOtherSources() = runBlocking {
        dao.insertAll(
            listOf(
                entity("manual_seed_same", null, "Seed", MANUAL_SEED_SOURCE_TYPE),
                entity("manual_local_delete", null, "Local", MANUAL_LOCAL_SOURCE_TYPE),
            ),
        )

        assertEquals(0, dao.deleteByIdAndSource("manual_seed_same", MANUAL_LOCAL_SOURCE_TYPE))
        assertEquals(1, dao.deleteByIdAndSource("manual_local_delete", MANUAL_LOCAL_SOURCE_TYPE))
        assertEquals("manual_seed_same", dao.observeById("manual_seed_same").first()?.id)
    }

    @Test
    fun replaceBySourcePreservesFavoritesForRetainedBenefitsAndDeletesRemovedFavorites() = runBlocking {
        val userId = database.accountDao().insert(
            UserEntity(email = "fav@example.com", displayName = "사용자", passwordSalt = "salt", passwordHash = "hash", isAdmin = false),
        )
        val keptOld = entity(id = "mma_keep", rowNumber = 1, name = "유지 가게").copy(lastVerifiedAt = "2026-10-01")
        val dropped = entity(id = "mma_drop", rowNumber = 2, name = "종료 가게")
        dao.insertAll(listOf(keptOld, dropped))
        database.favoriteDao().insert(FavoriteEntity(userId, "mma_keep", 10L))
        database.favoriteDao().insert(FavoriteEntity(userId, "mma_drop", 20L))

        val keptNew = keptOld.copy(lastVerifiedAt = "2026-11-23", syncedAt = 200L)
        val addedNew = entity(id = "mma_new", rowNumber = 3, name = "신규 가게")
        dao.replaceBySource(MMA_SOURCE_TYPE, listOf(keptNew, addedNew))

        assertTrue(database.favoriteDao().contains(userId, "mma_keep"))
        assertFalse(database.favoriteDao().contains(userId, "mma_drop"))
        assertEquals("2026-11-23", dao.getByIdOnce("mma_keep")?.lastVerifiedAt)
        assertNull(dao.getByIdOnce("mma_drop"))
        assertNotNull(dao.getByIdOnce("mma_new"))
    }

    @Test
    fun deleteRetiredBundledSeedRowsHandlesOverThousandRetainedIds() = runBlocking {
        val keep = entity(id = "seed_keep_1", rowNumber = null, name = "유지 시드", sourceType = BenefitSourceType.LOCAL_GOV.name)
        val retire = entity(id = "seed_retire_1", rowNumber = null, name = "은퇴 시드", sourceType = BenefitSourceType.LOCAL_GOV.name)
        dao.insertAll(listOf(keep, retire))

        val retainedIds = listOf("seed_keep_1") + (1..1100).map { "seed_other_$it" }
        dao.deleteRetiredBundledSeedRows(
            bundledSourceTypes = listOf(
                BenefitSourceType.LOCAL_GOV.name,
                BenefitSourceType.MANUAL_SEED.name,
                BenefitSourceType.PUBLIC_EVIDENCE.name,
            ),
            retainedIds = retainedIds,
        )

        assertNotNull(dao.getByIdOnce("seed_keep_1"))
        assertNull(dao.getByIdOnce("seed_retire_1"))
    }

    private fun entity(
        id: String,
        rowNumber: Int?,
        name: String,
        sourceType: String = MMA_SOURCE_TYPE,
        status: String = "NEEDS_VERIFICATION",
    ) = BenefitEntity(
        id = id,
        sourceType = sourceType,
        sourceRowNumber = rowNumber,
        name = name,
        address = "서울특별시 마포구 월드컵로 $rowNumber",
        latitude = null,
        longitude = null,
        category = "기타",
        benefitType = "할인",
        benefitDescription = "혜택 내용은 업소에 확인",
        phone = null,
        eligibleTarget = null,
        usageCondition = null,
        verificationMethod = null,
        sourceLabel = "테스트 출처",
        sourceUrl = null,
        lastVerifiedAt = null,
        status = status,
        district = "마포구",
        syncedAt = 100L,
    )
}

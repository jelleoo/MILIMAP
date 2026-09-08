package com.example.milipercent.data.seed

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.example.milipercent.data.local.BenefitDatabase
import com.example.milipercent.data.local.BenefitEntity
import com.example.milipercent.data.local.BenefitSourceType
import com.example.milipercent.data.local.FavoriteEntity
import com.example.milipercent.data.local.SeedStateEntity
import com.example.milipercent.data.local.UserEntity
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
class BundledSeedSynchronizerTest {
    private lateinit var context: Context
    private lateinit var database: BenefitDatabase

    @Before
    fun createDatabase() {
        context = ApplicationProvider.getApplicationContext()
        database = Room.inMemoryDatabaseBuilder(context, BenefitDatabase::class.java)
            .allowMainThreadQueries()
            .build()
    }

    @After
    fun closeDatabase() {
        database.close()
    }

    @Test
    fun verifiedBundledAssetsInstallOnceAs249Rows() = runBlocking {
        val synchronizer = BundledSeedSynchronizer(
            database = database,
            sources = listOf(
                LegacyBenefitSeedLoader(AssetJsonSource(context, "benefits.seed.json")),
                ManualBenefitSeedLoader(AssetJsonSource(context, "manual_benefits_seed.json")),
            ),
            currentTimeMillis = { 123L },
        )

        val first = synchronizer.synchronizeIfNeeded()

        assertTrue(first.installed)
        assertEquals(249, first.storedCount)
        assertEquals(249, database.benefitDao().countAll())
        assertEquals(BUNDLED_SEED_VERSION, database.seedStateDao().version(BUNDLED_SEED_NAME))
        assertEquals(0, normalizedDuplicateCount(database.benefitDao().getAllOnce()))
        assertEquals(7, database.benefitDao().getAllOnce().count {
            it.latitude != null && it.longitude != null
        })

        val second = synchronizer.synchronizeIfNeeded()

        assertFalse(second.installed)
        assertEquals(249, second.storedCount)
        assertEquals(249, database.benefitDao().countAll())
    }

    @Test
    fun seedVersionUpgradeRemovesRetiredBundledRowsAndPreservesRemoteAndManualRows() = runBlocking {
        val retainedBundled = benefit("seed-95759ff51414", BenefitSourceType.LOCAL_GOV, sourceRowNumber = null)
        val retiredBundled = benefit("retired_bundled", BenefitSourceType.LOCAL_GOV, sourceRowNumber = null)
        val manualLocal = benefit("manual_local", BenefitSourceType.MANUAL_LOCAL, sourceRowNumber = null)
        val remoteMma = benefit("remote_mma", BenefitSourceType.MMA_API, sourceRowNumber = 999)
        val userId = database.accountDao().insert(user())
        database.benefitDao().insertAll(listOf(retainedBundled, retiredBundled, manualLocal, remoteMma))
        database.favoriteDao().insert(FavoriteEntity(userId, retainedBundled.id, 1L))
        database.favoriteDao().insert(FavoriteEntity(userId, retiredBundled.id, 2L))
        database.seedStateDao().upsert(
            SeedStateEntity(
                name = BUNDLED_SEED_NAME,
                version = BUNDLED_SEED_VERSION - 1,
                installedAt = 1L,
            ),
        )
        val synchronizer = BundledSeedSynchronizer(
            database = database,
            sources = listOf(
                LegacyBenefitSeedLoader(AssetJsonSource(context, "benefits.seed.json")),
                ManualBenefitSeedLoader(AssetJsonSource(context, "manual_benefits_seed.json")),
            ),
            currentTimeMillis = { 123L },
        )

        val result = synchronizer.synchronizeIfNeeded()

        assertTrue(result.installed)
        assertEquals(251, result.storedCount)
        assertTrue(database.favoriteDao().contains(userId, retainedBundled.id))
        assertFalse(database.favoriteDao().contains(userId, retiredBundled.id))
        assertNull(database.benefitDao().getByIdOnce(retiredBundled.id))
        assertEquals(manualLocal, database.benefitDao().getByIdOnce(manualLocal.id))
        assertEquals(remoteMma, database.benefitDao().getByIdOnce(remoteMma.id))
        assertEquals(BUNDLED_SEED_VERSION, database.seedStateDao().version(BUNDLED_SEED_NAME))
    }

    private fun user() = UserEntity(
        email = "soldier@example.com",
        displayName = "테스터",
        passwordSalt = "salt",
        passwordHash = "hash",
        isAdmin = false,
    )

    private fun benefit(
        id: String,
        sourceType: BenefitSourceType,
        sourceRowNumber: Int?,
    ) = BenefitEntity(
        id = id,
        sourceType = sourceType.name,
        sourceRowNumber = sourceRowNumber,
        name = id,
        address = "서울특별시 마포구 테스트로 1",
        latitude = null,
        longitude = null,
        category = "기타",
        benefitType = "할인·우대",
        benefitDescription = "테스트 혜택",
        phone = null,
        eligibleTarget = null,
        usageCondition = null,
        verificationMethod = "테스트 확인",
        sourceLabel = "테스트 출처",
        sourceUrl = "https://example.com/$id",
        lastVerifiedAt = "2026-09-06",
        status = "ACTIVE",
        district = "마포구",
        syncedAt = 1L,
    )
}

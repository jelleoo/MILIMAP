package com.example.milipercent.data.seed

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.example.milipercent.data.BenefitRepository
import com.example.milipercent.data.local.BenefitDatabase
import com.example.milipercent.data.local.BenefitEntity
import com.example.milipercent.data.local.BenefitIdentity
import com.example.milipercent.data.local.BenefitSourceType
import com.example.milipercent.data.local.FavoriteEntity
import com.example.milipercent.data.local.SeedStateEntity
import com.example.milipercent.data.local.UserEntity
import com.example.milipercent.data.local.RoomBenefitLocalDataSource
import com.example.milipercent.model.BenefitPage
import com.example.milipercent.model.MmaBenefit
import com.example.milipercent.network.BenefitPageSource
import kotlinx.coroutines.flow.first
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
    fun verifiedBundledAssetsInstallOnceAs1018Rows() = runBlocking {
        val synchronizer = BundledSeedSynchronizer(
            database = database,
            manifestSource = AssetJsonSource(context, "benefits.seed.manifest.json"),
            legacySeedSource = AssetJsonSource(context, "benefits.seed.json"),
            manualSeedSource = AssetJsonSource(context, "manual_benefits_seed.json"),
            currentTimeMillis = { 123L },
        )

        val first = synchronizer.synchronizeIfNeeded()

        assertTrue(first.installed)
        assertEquals(1018, first.storedCount)
        assertEquals(1018, database.benefitDao().countAll())
        assertEquals(BUNDLED_SEED_VERSION, database.seedStateDao().version(BUNDLED_SEED_NAME))
        assertEquals(0, normalizedDuplicateCount(database.benefitDao().getAllOnce()))
        assertEquals(998, database.benefitDao().getAllOnce().count {
            it.latitude != null && it.longitude != null
        })

        val second = synchronizer.synchronizeIfNeeded()

        assertFalse(second.installed)
        assertEquals(1018, second.storedCount)
        assertEquals(1018, database.benefitDao().countAll())
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
            manifestSource = AssetJsonSource(context, "benefits.seed.manifest.json"),
            legacySeedSource = AssetJsonSource(context, "benefits.seed.json"),
            manualSeedSource = AssetJsonSource(context, "manual_benefits_seed.json"),
            currentTimeMillis = { 123L },
        )

        val result = synchronizer.synchronizeIfNeeded()

        assertTrue(result.installed)
        assertEquals(1020, result.storedCount)
        assertTrue(database.favoriteDao().contains(userId, retainedBundled.id))
        assertFalse(database.favoriteDao().contains(userId, retiredBundled.id))
        assertNull(database.benefitDao().getByIdOnce(retiredBundled.id))
        assertEquals(manualLocal, database.benefitDao().getByIdOnce(manualLocal.id))
        assertEquals(remoteMma, database.benefitDao().getByIdOnce(remoteMma.id))
        assertEquals(BUNDLED_SEED_VERSION, database.seedStateDao().version(BUNDLED_SEED_NAME))
    }

    @Test
    fun seedUpgradeAndApiRefreshPreserveFavoritesAcrossPromotion() = runBlocking {
        val bundled = publishedMmaSeed()
        val remote = remoteVersionOf(bundled)
        val firstUser = database.accountDao().insert(user())
        val secondUser = database.accountDao().insert(user().copy(email = "second@example.com"))
        val favorites = database.favoriteDao()
        database.benefitDao().upsertAll(listOf(remote))
        favorites.insert(FavoriteEntity(firstUser, remote.id, 10L))
        favorites.insert(FavoriteEntity(secondUser, remote.id, 20L))
        database.seedStateDao().upsert(
            SeedStateEntity(BUNDLED_SEED_NAME, BUNDLED_SEED_VERSION - 1, 1L),
        )

        assertTrue(installCurrentSeed().synchronizeIfNeeded().installed)
        assertTrue(favorites.contains(firstUser, remote.id))
        favorites.insert(FavoriteEntity(secondUser, bundled.id, 30L))
        val repository = repositoryReturning(remote)

        repeat(2) { repository.refreshBenefits() }

        assertEquals(listOf(bundled.id), favorites.observeIds(firstUser).first())
        assertEquals(listOf(bundled.id), favorites.observeIds(secondUser).first())
        assertNull(database.benefitDao().getByIdOnce(remote.id))
    }

    @Test
    fun apiRefreshKeepsFavoriteWhenBundledPromotionIsAmbiguous() = runBlocking {
        val bundled = publishedMmaSeed()
        val remote = remoteVersionOf(bundled)
        val userId = database.accountDao().insert(user())
        database.benefitDao().upsertAll(listOf(remote, bundled, bundled.copy(id = "other-seed")))
        database.favoriteDao().insert(FavoriteEntity(userId, remote.id, 10L))

        repositoryReturning(remote).refreshBenefits()

        assertEquals(listOf(remote.id), database.favoriteDao().observeIds(userId).first())
    }

    private fun installCurrentSeed() = BundledSeedSynchronizer(
        database = database,
        manifestSource = AssetJsonSource(context, "benefits.seed.manifest.json"),
        legacySeedSource = AssetJsonSource(context, "benefits.seed.json"),
        manualSeedSource = AssetJsonSource(context, "manual_benefits_seed.json"),
        currentTimeMillis = { 123L },
    )

    private fun publishedMmaSeed(): BenefitEntity =
        LegacyBenefitSeedLoader(AssetJsonSource(context, "benefits.seed.json"), { 123L })
            .loadAndValidate()
            .first { it.sourceType == BenefitSourceType.PUBLIC_EVIDENCE.name }

    private fun remoteVersionOf(bundled: BenefitEntity): BenefitEntity =
        benefit(BenefitIdentity.mmaId(bundled.name, bundled.address), BenefitSourceType.MMA_API, 1)
            .copy(name = bundled.name, address = bundled.address)

    private fun repositoryReturning(remote: BenefitEntity) = BenefitRepository(
        apiClient = object : BenefitPageSource {
            override suspend fun getBenefitPage(pageNo: Int, numOfRows: Int) = BenefitPage(
                benefits = listOf(MmaBenefit(1, remote.name, remote.address, null, null)),
                pageNo = pageNo,
                numOfRows = numOfRows,
                totalCount = 1,
            )
        },
        localDataSource = RoomBenefitLocalDataSource(database.benefitDao()),
    )

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

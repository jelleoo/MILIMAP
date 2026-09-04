package com.example.milipercent.data.seed

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.example.milipercent.data.local.BenefitDatabase
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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
    fun verifiedBundledAssetsInstallOnceAs496Rows() = runBlocking {
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
        assertEquals(496, first.storedCount)
        assertEquals(496, database.benefitDao().countAll())
        assertEquals(1, database.seedStateDao().version(BUNDLED_SEED_NAME))
        assertEquals(0, normalizedDuplicateCount(database.benefitDao().getAllOnce()))
        assertEquals(484, database.benefitDao().getAllOnce().count {
            it.latitude != null && it.longitude != null
        })

        val second = synchronizer.synchronizeIfNeeded()

        assertFalse(second.installed)
        assertEquals(496, second.storedCount)
        assertEquals(496, database.benefitDao().countAll())
    }
}

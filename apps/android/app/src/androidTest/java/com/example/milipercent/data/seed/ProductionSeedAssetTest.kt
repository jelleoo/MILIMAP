package com.example.milipercent.data.seed

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.example.milipercent.data.local.BenefitSourceType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ProductionSeedAssetTest {
    @Test
    fun productionManualSeedContainsNoUnverifiedPreloadedBenefits() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val loader = ManualBenefitSeedLoader(AssetManualBenefitSeedJsonSource(context))
        val benefits = loader.loadAndValidate()

        assertTrue(benefits.isEmpty())
        assertTrue(benefits.all { it.sourceType == BenefitSourceType.MANUAL_SEED.name })
        assertTrue(benefits.all { it.sourceRowNumber == null })
    }

    @Test
    fun productionReleaseSeedContainsOnlyOfficialCandidates() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val benefits = LegacyBenefitSeedLoader(AssetJsonSource(context, "benefits.seed.json")).loadAndValidate()

        assertEquals(249, benefits.size)
        assertEquals(86, benefits.count { it.latitude != null && it.longitude != null })
        assertEquals(163, benefits.count { it.latitude == null && it.longitude == null })
        assertTrue(benefits.all { it.sourceLabel.endsWith("최신 확인") })
    }
}

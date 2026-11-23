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
        val manifest = BundledSeedManifestLoader(
            AssetJsonSource(context, "benefits.seed.manifest.json"),
        ).loadAndValidate()
        val legacyRawText = AssetJsonSource(context, "benefits.seed.json").readText()
        val manualRawText = AssetJsonSource(context, "manual_benefits_seed.json").readText()
        val benefits = LegacyBenefitSeedLoader(SeedJsonSource { legacyRawText }).loadAndValidate()

        assertEquals(BUNDLED_SEED_VERSION, manifest.seedVersion)
        assertEquals(manifest.totalCount, benefits.size)
        assertEquals(manifest.exactPinCount, benefits.count { it.latitude != null && it.longitude != null })
        assertEquals(manifest.unconfirmedCoordinateCount, benefits.count { it.latitude == null && it.longitude == null })
        assertEquals(manifest.seedSha256, sha256LfUtf8(legacyRawText))
        assertEquals(manifest.manualSeedSha256, sha256LfUtf8(manualRawText))
        assertEquals(839, benefits.size)
        assertEquals(816, benefits.count { it.latitude != null && it.longitude != null })
        assertEquals(23, benefits.count { it.latitude == null && it.longitude == null })
        assertTrue(benefits.all { it.sourceLabel.endsWith("최신 확인") })
    }
}

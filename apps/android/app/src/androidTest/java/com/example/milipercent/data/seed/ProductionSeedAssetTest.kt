package com.example.milipercent.data.seed

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.example.milipercent.data.local.BenefitSourceType
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ProductionSeedAssetTest {
    @Test
    fun productionSeedAssetExistsAndPassesValidation() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val loader = ManualBenefitSeedLoader(AssetManualBenefitSeedJsonSource(context))
        val benefits = loader.loadAndValidate()

        assertTrue(benefits.isNotEmpty())
        assertTrue(benefits.all { it.sourceType == BenefitSourceType.MANUAL_SEED.name })
        assertTrue(benefits.all { it.sourceRowNumber == null })
    }
}

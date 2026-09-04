package com.example.milipercent.ui.map

import com.example.milipercent.data.local.BenefitSourceType
import com.example.milipercent.model.Benefit
import com.example.milipercent.model.BenefitStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MarkerSetSignatureTest {
    @Test
    fun markerOrderDoesNotChangeSignatureButVisibleFieldsDo() {
        val first = item("first", "첫 가게", "음식", 37.5, 126.9)
        val second = item("second", "둘 가게", "카페", 37.6, 127.0)

        assertEquals(markerSetSignature(listOf(first, second)), markerSetSignature(listOf(second, first)))
        assertNotEquals(markerSetSignature(listOf(first)), markerSetSignature(listOf(first.copy(name = "다른 이름"))))
        assertNotEquals(markerSetSignature(listOf(first)), markerSetSignature(listOf(first.copy(latitude = 37.51))))
        assertNotEquals(markerSetSignature(listOf(first)), markerSetSignature(listOf(first.copy(category = "카페"))))
    }

    @Test
    fun benefitWithoutCoordinatesIsExcludedFromMapProjection() {
        assertNull(benefit("missing", null, null).toMapItemOrNull())
    }

    private fun item(id: String, name: String, category: String, latitude: Double, longitude: Double) =
        BenefitMapItem(id, name, category, latitude, longitude)

    private fun benefit(id: String, latitude: Double?, longitude: Double?) = Benefit(
        id = id,
        name = "테스트",
        address = "서울",
        latitude = latitude,
        longitude = longitude,
        category = "기타",
        benefitType = "할인",
        benefitDescription = "설명",
        phone = null,
        eligibleTarget = null,
        usageCondition = null,
        verificationMethod = null,
        sourceType = BenefitSourceType.LOCAL_GOV,
        sourceLabel = "테스트",
        sourceUrl = null,
        lastVerifiedAt = null,
        status = BenefitStatus.ACTIVE,
        district = null,
    )
}

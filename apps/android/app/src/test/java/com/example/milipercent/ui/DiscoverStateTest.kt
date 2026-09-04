package com.example.milipercent.ui

import com.example.milipercent.data.local.BenefitSourceType
import com.example.milipercent.model.Benefit
import com.example.milipercent.model.BenefitDistrict
import com.example.milipercent.model.BenefitStatus
import com.example.milipercent.model.GeoPoint
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DiscoverStateTest {
    @Test
    fun categoryDistrictAndKoreanSearchComposeAndEndedRowsStayHidden() {
        val result = createBenefitListItems(
            benefits = listOf(
                benefit("1", "홍대 식당", "서울특별시 마포구 와우산로", "음식점", "마포구"),
                benefit("2", "강남 식당", "서울특별시 강남구", "음식점", "강남구"),
                benefit("3", "홍대 종료", "서울특별시 마포구", "음식점", "마포구", BenefitStatus.ENDED),
            ),
            category = "음식점",
            district = BenefitDistrict.MAPO,
            activeSearch = "와우산",
            center = SEOUL_CENTER,
            currentLocation = null,
        )

        assertEquals(listOf("1"), result.map { it.benefit.id })
    }

    @Test
    fun presetSearchIncludesBenefitsWithinEightKilometers() {
        val result = createBenefitListItems(
            benefits = listOf(
                benefit("near", "좌표 혜택", "서울특별시 마포구", "기타", "마포구", latitude = 37.5572, longitude = 126.9254),
                benefit("far", "먼 혜택", "서울특별시 송파구", "기타", "송파구", latitude = 37.5133, longitude = 127.1001),
            ),
            category = "전체",
            district = BenefitDistrict.ALL,
            activeSearch = "홍대",
            center = SEOUL_CENTER,
            currentLocation = null,
        )

        assertEquals(listOf("near"), result.map { it.benefit.id })
    }

    @Test
    fun currentLocationChangesDistanceOnlyWhenSearchIsInactive() {
        val item = benefit("near", "혜택", "서울특별시 마포구", "기타", "마포구", latitude = 37.5572, longitude = 126.9254)

        val withoutSearch = createBenefitListItems(listOf(item), "전체", BenefitDistrict.ALL, "", SEOUL_CENTER, GeoPoint(37.5572, 126.9254)).single()
        val withSearch = createBenefitListItems(listOf(item), "전체", BenefitDistrict.ALL, "홍대", SEOUL_CENTER, GeoPoint(35.0, 129.0)).single()

        assertEquals(0.0, withoutSearch.distanceKm ?: -1.0, 0.001)
        assertTrue((withSearch.distanceKm ?: 0.0) > 0.0)
    }

    @Test
    fun itemsWithoutCoordinatesHaveNoDistanceAndSortLast() {
        val result = createBenefitListItems(
            listOf(
                benefit("no-coordinate", "나", "서울특별시 마포구", "기타", "마포구"),
                benefit("coordinate", "가", "서울특별시 마포구", "기타", "마포구", latitude = 37.5665, longitude = 126.9780),
            ), "전체", BenefitDistrict.ALL, "", SEOUL_CENTER, null,
        )

        assertEquals(listOf("coordinate", "no-coordinate"), result.map { it.benefit.id })
        assertNull(result.last().distanceKm)
    }

    private fun benefit(
        id: String, name: String, address: String, category: String, district: String,
        status: BenefitStatus = BenefitStatus.ACTIVE, latitude: Double? = null, longitude: Double? = null,
    ) = Benefit(
        id, name, address, latitude, longitude, category, "할인", "설명", null, null, null, null,
        BenefitSourceType.LOCAL_GOV, "테스트", null, null, status, district,
    )
}

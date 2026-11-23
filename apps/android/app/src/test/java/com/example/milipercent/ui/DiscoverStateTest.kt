package com.example.milipercent.ui

import com.example.milipercent.data.local.BenefitSourceType
import com.example.milipercent.model.Benefit
import com.example.milipercent.model.BenefitDistrict
import com.example.milipercent.model.BenefitStatus
import com.example.milipercent.model.GeoBounds
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

    @Test
    fun searchBoundsFiltersOnlyLocatedBenefitsInsideViewport() {
        val inside = benefit("in", "안쪽 식당", "서울특별시 마포구", "음식", "마포구", latitude = 37.555, longitude = 126.925)
        val outside = benefit("out", "바깥 식당", "경기도 동두천시", "음식", "동두천시", latitude = 37.905, longitude = 127.055)
        val unlocated = benefit("nocoord", "좌표없음 식당", "서울특별시 마포구", "음식", "마포구")
        val bounds = GeoBounds(southLatitude = 37.54, westLongitude = 126.91, northLatitude = 37.57, eastLongitude = 126.95)

        val result = createBenefitListItems(
            benefits = listOf(inside, outside, unlocated),
            category = "음식",
            district = BenefitDistrict.ALL,
            activeSearch = "",
            center = SEOUL_CENTER,
            currentLocation = null,
            searchBounds = bounds,
        )

        assertEquals(listOf("in"), result.map { it.benefit.id })
    }

    @Test
    fun searchCameraTargetFocusesSinglePinFitsMultiplePinsAndUsesStationPreset() {
        val singlePin = BenefitListItem(
            benefit("ddc-one", "동두천 카페", "경기도 동두천시", "카페", "동두천시", latitude = 37.903, longitude = 127.055),
            distanceKm = 0.2,
        )
        val (singleCenter, singleTarget) = computeSearchCameraTarget("동두천 카페", listOf(singlePin), SEOUL_CENTER)
        assertEquals(GeoPoint(37.903, 127.055), singleCenter)
        assertEquals(MapCameraTarget.Point(GeoPoint(37.903, 127.055), SINGLE_RESULT_ZOOM), singleTarget)

        val twoPins = listOf(
            singlePin,
            BenefitListItem(
                benefit("ddc-two", "보산 음식점", "경기도 동두천시", "음식", "동두천시", latitude = 37.915, longitude = 127.065),
                distanceKm = 1.5,
            ),
        )
        val (stationCenter, stationTarget) = computeSearchCameraTarget("동두천역", twoPins, SEOUL_CENTER)
        assertEquals(destinationCenters["동두천역"], stationCenter)
        assertEquals(MapCameraTarget.Point(destinationCenters["동두천역"]!!, DEFAULT_MAP_ZOOM), stationTarget)

        val (_, boundsTarget) = computeSearchCameraTarget("동두천", twoPins, SEOUL_CENTER)
        // "동두천" is also in destinationCenters; test non-preset multi-pin search query:
        val (_, multiMatchTarget) = computeSearchCameraTarget("치킨", twoPins, SEOUL_CENTER)
        assertTrue(multiMatchTarget is MapCameraTarget.Bounds)
        assertTrue(boundsTarget is MapCameraTarget.Point)

        val (fallbackCenter, fallbackTarget) = computeSearchCameraTarget("없는검색어", emptyList(), GeoPoint(37.5, 127.0))
        assertEquals(GeoPoint(37.5, 127.0), fallbackCenter)
        assertEquals(MapCameraTarget.Point(GeoPoint(37.5, 127.0), DEFAULT_MAP_ZOOM), fallbackTarget)
    }

    @Test
    fun orderedCategoriesPlacesPrimaryCategoriesFirstAndEtcLast() {
        val benefits = listOf(
            benefit("1", "가", "서울", "기타", "중구"),
            benefit("2", "나", "서울", "체험", "중구"),
            benefit("3", "다", "서울", "병원", "중구"),
            benefit("4", "라", "서울", "카페", "중구"),
            benefit("5", "마", "서울", "음식", "중구"),
        )

        assertEquals(
            listOf("전체", "음식", "카페", "병원", "체험", "기타"),
            orderedCategories(benefits),
        )
    }

    @Test
    fun savedBenefitListItemsFiltersOnlyFavoritesExcludesEndedAndSortsByDistance() {
        val origin = GeoPoint(37.55, 126.92)
        val far = benefit("far", "먼 가게", "서울", "음식", "강남구", latitude = 37.50, longitude = 127.03)
        val near = benefit("near", "가까운 가게", "서울", "음식", "마포구", latitude = 37.551, longitude = 126.921)
        val unfavored = benefit("other", "찜아님", "서울", "음식", "마포구", latitude = 37.5501, longitude = 126.9201)
        val endedFav = benefit("ended", "종료된 가게", "서울", "음식", "마포구", status = BenefitStatus.ENDED, latitude = 37.5501, longitude = 126.9201)
        val byId = listOf(far, near, unfavored, endedFav).associateBy(Benefit::id)

        val result = createSavedBenefitListItems(
            benefitsById = byId,
            favoriteIds = setOf("far", "near", "ended", "missing"),
            center = SEOUL_CENTER,
            currentLocation = origin,
        )

        assertEquals(listOf("near", "far"), result.map { it.benefit.id })
        assertTrue((result[0].distanceKm ?: 1.0) < 0.5)
    }

    private fun benefit(
        id: String, name: String, address: String, category: String, district: String,
        status: BenefitStatus = BenefitStatus.ACTIVE, latitude: Double? = null, longitude: Double? = null,
    ) = Benefit(
        id, name, address, latitude, longitude, category, "할인", "설명", null, null, null, null,
        BenefitSourceType.LOCAL_GOV, "테스트", null, null, status, district,
    )
}

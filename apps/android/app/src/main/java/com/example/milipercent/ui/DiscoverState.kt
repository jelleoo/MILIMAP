package com.example.milipercent.ui

import com.example.milipercent.model.Benefit
import com.example.milipercent.model.BenefitDistrict
import com.example.milipercent.model.BenefitStatus
import com.example.milipercent.model.GeoBounds
import com.example.milipercent.model.GeoPoint
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

val destinationCenters = mapOf(
    "홍대" to GeoPoint(37.5572, 126.9254),
    "홍대입구" to GeoPoint(37.5572, 126.9254),
    "성수" to GeoPoint(37.5446, 127.0559),
    "잠실" to GeoPoint(37.5133, 127.1001),
    "강남" to GeoPoint(37.4979, 127.0276),
    "강남역" to GeoPoint(37.4979, 127.0276),
    "신촌" to GeoPoint(37.5551, 126.9368),
    "건대" to GeoPoint(37.5404, 127.0692),
    "서울역" to GeoPoint(37.5547, 126.9707),
    "명동" to GeoPoint(37.5636, 126.9826),
    "종로" to GeoPoint(37.5704, 126.9922),
    "광화문" to GeoPoint(37.5716, 126.9769),
    "여의도" to GeoPoint(37.5219, 126.9245),
    "용산" to GeoPoint(37.5298, 126.9648),
    "용산역" to GeoPoint(37.5298, 126.9648),
    "이태원" to GeoPoint(37.5345, 126.9946),
    "노원" to GeoPoint(37.6542, 127.0568),
    "왕십리" to GeoPoint(37.5612, 127.0370),
    "영등포" to GeoPoint(37.5155, 126.9076),
    "구로" to GeoPoint(37.4954, 126.8876),
    "사당" to GeoPoint(37.4765, 126.9816),
    "청량리" to GeoPoint(37.5802, 127.0468),
    "동두천" to GeoPoint(37.9277, 127.0548),
    "동두천역" to GeoPoint(37.9277, 127.0548),
    "동두천중앙역" to GeoPoint(37.9016, 127.0564),
    "지행역" to GeoPoint(37.8923, 127.0557),
    "파주" to GeoPoint(37.7662, 126.7746),
    "금촌" to GeoPoint(37.7662, 126.7746),
    "금촌역" to GeoPoint(37.7662, 126.7746),
    "운정" to GeoPoint(37.7258, 126.7673),
    "운정역" to GeoPoint(37.7258, 126.7673),
    "문산" to GeoPoint(37.8546, 126.7881),
    "문산역" to GeoPoint(37.8546, 126.7881),
    "양주" to GeoPoint(37.7744, 127.0448),
    "양주역" to GeoPoint(37.7744, 127.0448),
    "덕정역" to GeoPoint(37.8432, 127.0612),
    "의정부" to GeoPoint(37.7381, 127.0460),
    "의정부역" to GeoPoint(37.7381, 127.0460),
    "수원" to GeoPoint(37.2660, 127.0001),
    "수원역" to GeoPoint(37.2660, 127.0001),
    "성남" to GeoPoint(37.4200, 127.1267),
    "분당" to GeoPoint(37.3827, 127.1189),
    "판교" to GeoPoint(37.3948, 127.1112),
    "판교역" to GeoPoint(37.3948, 127.1112),
    "용인" to GeoPoint(37.2411, 127.1776),
    "고양" to GeoPoint(37.6584, 126.7700),
    "일산" to GeoPoint(37.6584, 126.7700),
    "부천" to GeoPoint(37.4841, 126.7828),
    "안양" to GeoPoint(37.3943, 126.9568),
    "안산" to GeoPoint(37.3219, 126.8309),
    "평택" to GeoPoint(36.9921, 127.1129),
    "화성" to GeoPoint(37.2000, 127.0977),
    "동탄" to GeoPoint(37.2000, 127.0977),
    "인천" to GeoPoint(37.4563, 126.7052),
    "송도" to GeoPoint(37.3897, 126.6435),
    "부평" to GeoPoint(37.4895, 126.7244),
    "부평역" to GeoPoint(37.4895, 126.7244),
    "구월동" to GeoPoint(37.4482, 126.7016),
    "주안역" to GeoPoint(37.4649, 126.6800),
)

private val primaryCategoryOrder = listOf("전체", "음식", "카페", "병원", "미용·뷰티", "문화·여가", "숙박")

fun orderedCategories(benefits: List<Benefit>): List<String> {
    val distinct = benefits.asSequence()
        .filter { it.status != BenefitStatus.ENDED }
        .map { it.category.trim() }
        .filter { it.isNotEmpty() }
        .toSet()
    val head = primaryCategoryOrder.filter { it == "전체" || it in distinct }
    val middle = distinct
        .filter { it !in primaryCategoryOrder && it != "기타" }
        .sorted()
    val tail = if ("기타" in distinct) listOf("기타") else emptyList()
    return head + middle + tail
}

internal data class SearchableBenefit(
    val benefit: Benefit,
    val searchableText: String,
)

internal fun List<Benefit>.toSearchableBenefits(): List<SearchableBenefit> = map { benefit ->
    val text = listOfNotNull(benefit.name, benefit.address, benefit.district, benefit.category)
        .joinToString("\u0000") { it.lowercase() }
    SearchableBenefit(benefit = benefit, searchableText = text)
}

private val benefitItemComparator = compareBy<BenefitListItem> { it.distanceKm ?: Double.MAX_VALUE }
    .thenBy { it.benefit.name }

fun createBenefitListItems(
    benefits: List<Benefit>,
    category: String,
    district: BenefitDistrict,
    activeSearch: String,
    center: GeoPoint,
    currentLocation: GeoPoint?,
    searchBounds: GeoBounds? = null,
): List<BenefitListItem> = createBenefitListItemsFromIndex(
    indexedBenefits = benefits.toSearchableBenefits(),
    category = category,
    district = district,
    activeSearch = activeSearch,
    center = center,
    currentLocation = currentLocation,
    searchBounds = searchBounds,
)

internal fun createBenefitListItemsFromIndex(
    indexedBenefits: List<SearchableBenefit>,
    category: String,
    district: BenefitDistrict,
    activeSearch: String,
    center: GeoPoint,
    currentLocation: GeoPoint?,
    searchBounds: GeoBounds? = null,
): List<BenefitListItem> {
    val query = activeSearch.trim().lowercase()
    val presetCenter = destinationCenters[query]
    val distanceOrigin = when {
        query.isBlank() && searchBounds != null -> searchBounds.center
        query.isBlank() && currentLocation != null -> currentLocation
        else -> center
    }
    return indexedBenefits.asSequence()
        .filter { it.benefit.status != BenefitStatus.ENDED }
        .filter { category == "전체" || it.benefit.category == category }
        .filter { district == BenefitDistrict.ALL || it.benefit.district == district.districtName }
        .filter { entry ->
            if (searchBounds == null) return@filter true
            val lat = entry.benefit.latitude ?: return@filter false
            val lng = entry.benefit.longitude ?: return@filter false
            searchBounds.contains(lat, lng)
        }
        .filter { entry ->
            if (query.isBlank()) return@filter true
            val textMatch = entry.searchableText.contains(query)
            val presetMatch = presetCenter?.let { distanceKm(it, entry.benefit) }?.let { it <= PRESET_RADIUS_KM } ?: false
            textMatch || presetMatch
        }
        .map { entry -> BenefitListItem(entry.benefit, distanceKm(distanceOrigin, entry.benefit)) }
        .sortedWith(benefitItemComparator)
        .toList()
}

internal fun reRankBenefitListItems(
    items: List<BenefitListItem>,
    origin: GeoPoint,
): List<BenefitListItem> = items
    .map { item -> BenefitListItem(item.benefit, distanceKm(origin, item.benefit)) }
    .sortedWith(benefitItemComparator)

fun createSavedBenefitListItems(
    benefitsById: Map<String, Benefit>,
    favoriteIds: Set<String>,
    center: GeoPoint,
    currentLocation: GeoPoint?,
): List<BenefitListItem> {
    if (favoriteIds.isEmpty()) return emptyList()
    val origin = currentLocation ?: center
    return favoriteIds.asSequence()
        .mapNotNull { id -> benefitsById[id] }
        .filter { it.status != BenefitStatus.ENDED }
        .map { benefit -> BenefitListItem(benefit, distanceKm(origin, benefit)) }
        .sortedWith(benefitItemComparator)
        .toList()
}

fun computeSearchCameraTarget(
    query: String,
    visibleBenefits: List<BenefitListItem>,
    fallbackCenter: GeoPoint,
): Pair<GeoPoint, MapCameraTarget> {
    val presetCenter = destinationCenters[query.trim().lowercase()]
    val singleLocated = visibleBenefits.mapNotNull { item ->
        val lat = item.benefit.latitude
        val lng = item.benefit.longitude
        if (lat != null && lng != null) GeoPoint(lat, lng) else null
    }.singleOrNull()
    return when {
        singleLocated != null -> singleLocated to MapCameraTarget.Point(singleLocated, SINGLE_RESULT_ZOOM)
        presetCenter != null -> presetCenter to MapCameraTarget.Point(presetCenter, DEFAULT_MAP_ZOOM)
        else -> computeBoundsCameraTarget(visibleBenefits)
            ?: (fallbackCenter to MapCameraTarget.Point(fallbackCenter, DEFAULT_MAP_ZOOM))
    }
}

fun computeBoundsCameraTarget(
    visibleBenefits: List<BenefitListItem>,
): Pair<GeoPoint, MapCameraTarget>? {
    val located = visibleBenefits.mapNotNull { item ->
        val lat = item.benefit.latitude
        val lng = item.benefit.longitude
        if (lat != null && lng != null) GeoPoint(lat, lng) else null
    }
    if (located.isEmpty()) return null
    if (located.size == 1) return located[0] to MapCameraTarget.Point(located[0], SINGLE_RESULT_ZOOM)
    val bounds = GeoBounds(
        southLatitude = located.minOf { it.latitude },
        westLongitude = located.minOf { it.longitude },
        northLatitude = located.maxOf { it.latitude },
        eastLongitude = located.maxOf { it.longitude },
    )
    return if (bounds.isNearlyPoint) {
        bounds.center to MapCameraTarget.Point(bounds.center, SINGLE_RESULT_ZOOM)
    } else {
        bounds.center to MapCameraTarget.Bounds(bounds)
    }
}

fun distanceKm(origin: GeoPoint, benefit: Benefit): Double? {
    val latitude = benefit.latitude ?: return null
    val longitude = benefit.longitude ?: return null
    val latitudeDelta = Math.toRadians(latitude - origin.latitude)
    val longitudeDelta = Math.toRadians(longitude - origin.longitude)
    val a = sin(latitudeDelta / 2) * sin(latitudeDelta / 2) +
        cos(Math.toRadians(origin.latitude)) * cos(Math.toRadians(latitude)) *
        sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
    return EARTH_RADIUS_KM * 2 * atan2(sqrt(a), sqrt(1 - a))
}

private const val EARTH_RADIUS_KM = 6371.0
private const val PRESET_RADIUS_KM = 8.0

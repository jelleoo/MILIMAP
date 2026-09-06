package com.example.milipercent.ui

import com.example.milipercent.model.Benefit
import com.example.milipercent.model.BenefitDistrict
import com.example.milipercent.model.BenefitStatus
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
)

fun createBenefitListItems(
    benefits: List<Benefit>,
    category: String,
    district: BenefitDistrict,
    activeSearch: String,
    center: GeoPoint,
    currentLocation: GeoPoint?,
): List<BenefitListItem> {
    val query = activeSearch.trim().lowercase()
    val presetCenter = destinationCenters[query]
    val distanceOrigin = if (query.isBlank() && currentLocation != null) currentLocation else center
    return benefits.asSequence()
        .filter { it.status != BenefitStatus.ENDED }
        .filter { category == "전체" || it.category == category }
        .filter { district == BenefitDistrict.ALL || it.district == district.districtName }
        .filter { benefit ->
            if (query.isBlank()) return@filter true
            val textMatch = listOf(benefit.name, benefit.address, benefit.district, benefit.category)
                .filterNotNull()
                .any { it.lowercase().contains(query) }
            val presetMatch = presetCenter?.let { distanceKm(it, benefit) }?.let { it <= PRESET_RADIUS_KM } ?: false
            textMatch || presetMatch
        }
        .map { benefit -> BenefitListItem(benefit, distanceKm(distanceOrigin, benefit)) }
        .sortedWith(compareBy<BenefitListItem> { it.distanceKm ?: Double.MAX_VALUE }.thenBy { it.benefit.name })
        .toList()
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

package com.example.milipercent.model

data class GeoPoint(
    val latitude: Double,
    val longitude: Double,
)

data class GeoBounds(
    val southLatitude: Double,
    val westLongitude: Double,
    val northLatitude: Double,
    val eastLongitude: Double,
) {
    fun contains(latitude: Double, longitude: Double): Boolean =
        latitude in southLatitude..northLatitude && longitude in westLongitude..eastLongitude

    val center: GeoPoint
        get() = GeoPoint(
            (southLatitude + northLatitude) / 2.0,
            (westLongitude + eastLongitude) / 2.0,
        )

    val isNearlyPoint: Boolean
        get() = (northLatitude - southLatitude) < 0.001 && (eastLongitude - westLongitude) < 0.001
}

package com.example.militarybenefits.data

import android.content.Context
import org.json.JSONArray

internal data class MmaCoordinateEntry(
    val name: String,
    val address: String,
    val latitude: Double,
    val longitude: Double,
)

internal class MmaCoordinateIndex(entries: Iterable<MmaCoordinateEntry>) {
    private val coordinates = entries.associateBy { entry ->
        normalizedBenefitKey(entry.name, entry.address)
    }

    fun find(name: String, address: String): MmaCoordinateEntry? =
        coordinates[normalizedBenefitKey(name, address)]

    val size: Int get() = coordinates.size

    companion object {
        private const val ASSET_NAME = "mma.coordinates.seed.json"

        fun fromAssets(context: Context): MmaCoordinateIndex = runCatching {
            val json = context.assets.open(ASSET_NAME).bufferedReader().use { it.readText() }
            val array = JSONArray(json)
            val entries = buildList {
                for (index in 0 until array.length()) {
                    val item = array.getJSONObject(index)
                    val latitude = item.optDouble("latitude", Double.NaN)
                    val longitude = item.optDouble("longitude", Double.NaN)
                    if (latitude.isFinite() && longitude.isFinite()) {
                        add(
                            MmaCoordinateEntry(
                                name = item.getString("name"),
                                address = item.getString("address"),
                                latitude = latitude,
                                longitude = longitude,
                            ),
                        )
                    }
                }
            }
            MmaCoordinateIndex(entries)
        }.getOrElse { MmaCoordinateIndex(emptyList()) }
    }
}

private val benefitKeyIgnoredCharacters = Regex("[\\s,()]")

internal fun normalizedBenefitKey(name: String, address: String): String =
    (name + "|" + address).lowercase().replace(benefitKeyIgnoredCharacters, "")

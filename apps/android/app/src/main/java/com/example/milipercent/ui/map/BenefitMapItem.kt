package com.example.milipercent.ui.map

import com.example.milipercent.model.Benefit

data class BenefitMapItem(
    val id: String,
    val name: String,
    val category: String,
    val latitude: Double,
    val longitude: Double,
)

fun Benefit.toMapItemOrNull(): BenefitMapItem? {
    val latitude = latitude ?: return null
    val longitude = longitude ?: return null
    return BenefitMapItem(id, name, category, latitude, longitude)
}

package com.example.milipercent.data.local

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "benefits",
    indices = [
        Index(value = ["sourceType"]),
        Index(value = ["status", "category"]),
        Index(value = ["district"]),
    ],
)
data class BenefitEntity(
    @PrimaryKey val id: String,
    val sourceType: String,
    val sourceRowNumber: Int?,
    val name: String,
    val address: String,
    val latitude: Double?,
    val longitude: Double?,
    val category: String,
    val benefitType: String,
    val benefitDescription: String,
    val phone: String?,
    val eligibleTarget: String?,
    val usageCondition: String?,
    val verificationMethod: String?,
    val sourceLabel: String,
    val sourceUrl: String?,
    val lastVerifiedAt: String?,
    val status: String,
    val district: String?,
    val syncedAt: Long,
)

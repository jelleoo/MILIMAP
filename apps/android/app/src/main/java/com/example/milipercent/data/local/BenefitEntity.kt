package com.example.milipercent.data.local

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "benefits",
    indices = [
        Index(value = ["sourceType"]),
        Index(value = ["district"]),
    ],
)
data class BenefitEntity(
    @PrimaryKey val id: String,
    val sourceType: String,
    val sourceRowNumber: Int?,
    val name: String,
    val address: String?,
    val phone: String?,
    val benefitType: String?,
    val district: String,
    val latitude: Double?,
    val longitude: Double?,
    val syncedAt: Long,
    val benefitDescription: String? = null,
    val eligibleTarget: String? = null,
    val usageCondition: String? = null,
    val verificationMethod: String? = null,
    val sourceUrl: String? = null,
    val lastVerifiedDate: String? = null,
    val status: String? = null,
)

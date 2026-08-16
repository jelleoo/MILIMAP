package com.example.militarybenefits.data

data class Benefit(
    val id: String,
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
    val sourceType: String,
    val sourceLabel: String,
    val sourceUrl: String?,
    val lastVerifiedAt: String?,
    val status: BenefitStatus,
    val district: String?,
)

enum class BenefitStatus { ACTIVE, NEEDS_VERIFICATION, ENDED }

data class LocalUser(
    val id: Long,
    val email: String,
    val displayName: String,
    val isAdmin: Boolean,
)

data class GeoPoint(val latitude: Double, val longitude: Double)

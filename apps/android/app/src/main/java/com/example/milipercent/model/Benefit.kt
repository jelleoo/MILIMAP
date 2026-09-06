package com.example.milipercent.model

import com.example.milipercent.data.local.BenefitSourceType

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
    val sourceType: BenefitSourceType,
    val sourceLabel: String,
    val sourceUrl: String?,
    val lastVerifiedAt: String?,
    val status: BenefitStatus,
    val district: String?,
)

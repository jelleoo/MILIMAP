package com.example.milipercent.model

data class BenefitDetail(
    val id: String,
    val name: String,
    val address: String?,
    val phone: String?,
    val benefitType: String?,
    val district: String,
    val sourceType: String,
    val benefitDescription: String? = null,
    val eligibleTarget: String? = null,
    val usageCondition: String? = null,
    val verificationMethod: String? = null,
    val sourceUrl: String? = null,
    val lastVerifiedDate: String? = null,
    val status: String? = null,
)

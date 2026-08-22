package com.example.milipercent.model

data class BenefitUiModel(
    val id: String,
    val name: String,
    val address: String?,
    val phone: String?,
    val benefitType: String?,
    val district: String,
    val latitude: Double?,
    val longitude: Double?,
)

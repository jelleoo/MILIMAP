package com.example.milipercent.navigation

import kotlinx.serialization.Serializable

@Serializable
data object DiscoverRoute

@Serializable
data object SavedRoute

@Serializable
data object AccountRoute

@Serializable
data object AdminRoute

@Serializable
data object BenefitListRoute

@Serializable
data class BenefitDetailRoute(
    val benefitId: String,
)

@Serializable
data object DebugManualBenefitListRoute

@Serializable
data class DebugManualBenefitFormRoute(
    val benefitId: String? = null,
)

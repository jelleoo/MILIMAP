package com.example.milipercent.navigation

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.navigation.compose.rememberNavController
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.example.milipercent.data.local.BenefitSourceType
import com.example.milipercent.model.Benefit
import com.example.milipercent.model.BenefitStatus
import com.example.milipercent.ui.BenefitListItem
import com.example.milipercent.ui.MiliSpotUiState
import com.example.milipercent.ui.MilitaryBenefitTheme
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MiliSpotNavigationTest {
    @get:Rule val composeRule = createComposeRule()

    @Test
    fun selectedBenefitNavigatesToDetailByStableIdAndBackKeepsDiscover() {
        val benefit = Benefit(
            id = "stable-id",
            name = "상세 혜택",
            address = "서울특별시 중구 세종대로",
            latitude = null,
            longitude = null,
            category = "기타",
            benefitType = "할인",
            benefitDescription = "상세 설명",
            phone = null,
            eligibleTarget = null,
            usageCondition = null,
            verificationMethod = null,
            sourceType = BenefitSourceType.LOCAL_GOV,
            sourceLabel = "테스트",
            sourceUrl = null,
            lastVerifiedAt = null,
            status = BenefitStatus.ACTIVE,
            district = "중구",
        )
        composeRule.setContent {
            MilitaryBenefitTheme {
                MiliSpotNavHost(
                    state = MiliSpotUiState(
                        benefits = listOf(benefit),
                        visibleBenefits = listOf(BenefitListItem(benefit, null)),
                        isLoading = false,
                    ),
                    navController = rememberNavController(),
                    onNavigate = {},
                    onSearchTextChanged = {},
                    onSearch = {},
                    onPresetSelected = {},
                    onCategorySelected = {},
                    onDistrictSelected = {},
                    onBenefitSelected = {},
                    onFavorite = {},
                    onRefresh = {},
                    onCurrentLocation = {},
                    onMessageShown = {},
                )
            }
        }

        composeRule.onNodeWithTag("benefit_card_stable-id").performClick()
        composeRule.onNodeWithTag("benefit_detail_stable-id").assertIsDisplayed()
        composeRule.onNodeWithTag("detail_back").performClick()
        composeRule.onNodeWithTag("benefit_card_stable-id").assertIsDisplayed()
    }
}

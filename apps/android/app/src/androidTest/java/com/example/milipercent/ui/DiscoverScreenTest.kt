package com.example.milipercent.ui

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.navigation.compose.rememberNavController
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.example.milipercent.data.local.BenefitSourceType
import com.example.milipercent.model.Benefit
import com.example.milipercent.model.BenefitDistrict
import com.example.milipercent.model.BenefitStatus
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DiscoverScreenTest {
    @get:Rule val composeRule = createComposeRule()

    @Test
    fun discoverShowsSearchFiltersSyncAndBenefitCard() {
        composeRule.setContent {
            MilitaryBenefitTheme {
                MilitaryBenefitApp(
                    state = state(),
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

        composeRule.onNodeWithText("군 혜택 지도").assertIsDisplayed()
        composeRule.onNodeWithText("내장 혜택 DB").assertIsDisplayed()
        composeRule.onNodeWithTag("benefit_search").assertIsDisplayed()
        composeRule.onNodeWithTag("category_filter").assertIsDisplayed()
        composeRule.onNodeWithTag("district_filter").assertIsDisplayed()
        composeRule.onNodeWithTag("current_location").assertIsDisplayed()
        composeRule.onNodeWithTag("benefit_card_test-benefit").assertIsDisplayed()
    }

    private fun state(): MiliSpotUiState {
        val benefit = Benefit(
            id = "test-benefit",
            name = "테스트 나라사랑가게",
            address = "서울특별시 마포구 테스트로 1",
            latitude = 37.55,
            longitude = 126.92,
            category = "기타",
            benefitType = "할인",
            benefitDescription = "군 장병 할인",
            phone = "0212345678",
            eligibleTarget = "현역 군인",
            usageCondition = "신분증 제시",
            verificationMethod = "나라사랑카드",
            sourceType = BenefitSourceType.LOCAL_GOV,
            sourceLabel = "테스트 출처",
            sourceUrl = null,
            lastVerifiedAt = "2026-09-05",
            status = BenefitStatus.ACTIVE,
            district = "마포구",
        )
        return MiliSpotUiState(
            benefits = listOf(benefit),
            visibleBenefits = listOf(BenefitListItem(benefit, 1.2)),
            selectedCategory = "전체",
            selectedDistrict = BenefitDistrict.ALL,
            isLoading = false,
        )
    }
}

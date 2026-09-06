package com.example.milipercent.ui

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.example.milipercent.data.local.BenefitSourceType
import com.example.milipercent.model.Benefit
import com.example.milipercent.model.BenefitStatus
import com.example.milipercent.model.LocalUser
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AccountAdminScreenTest {
    @get:Rule val composeRule = createComposeRule()

    @Test
    fun loggedOutAccountCanSwitchToLoginMode() {
        composeRule.setContent {
            MilitaryBenefitTheme {
                AccountScreen(
                    user = null,
                    onRegister = { _, _, _ -> Result.failure(IllegalStateException()) },
                    onLogin = { _, _ -> Result.failure(IllegalStateException()) },
                    onLogout = {},
                )
            }
        }
        composeRule.onNodeWithTag("account_login_mode").performClick()
        composeRule.onNodeWithText("회원가입으로 전환").assertIsDisplayed()
    }

    @Test
    fun loggedInAccountCanLogout() {
        var loggedOut = false
        composeRule.setContent {
            MilitaryBenefitTheme {
                AccountScreen(
                    user = LocalUser(1, "admin@test.com", "관리자", true),
                    onRegister = { _, _, _ -> Result.failure(IllegalStateException()) },
                    onLogin = { _, _ -> Result.failure(IllegalStateException()) },
                    onLogout = { loggedOut = true },
                )
            }
        }
        composeRule.onNodeWithText("로그아웃").performClick()
        assertTrue(loggedOut)
    }

    @Test
    fun savedScreenShowsFavorite() {
        val item = BenefitListItem(benefit("saved"), null)
        composeRule.setContent {
            MilitaryBenefitTheme {
                SavedScreen(
                    items = listOf(item),
                    favoriteIds = setOf("saved"),
                    onSelect = {},
                    onFavorite = {},
                )
            }
        }
        composeRule.onNodeWithTag("saved_benefit_saved").assertIsDisplayed()
    }

    @Test
    fun adminScreenHidesControlsForNonAdmin() {
        val item = BenefitListItem(benefit("saved"), null)
        composeRule.setContent {
            MilitaryBenefitTheme {
                AdminScreen(
                    user = LocalUser(2, "user@test.com", "사용자", false),
                    benefits = listOf(item.benefit),
                    onSave = { _, _ -> },
                    onEnd = {},
                    onDeleteManual = {},
                )
            }
        }
        composeRule.onNodeWithText("관리자 권한이 필요합니다.").assertIsDisplayed()
    }

    private fun benefit(id: String) = Benefit(
        id = id,
        name = "저장된 혜택",
        address = "서울특별시 마포구",
        latitude = null,
        longitude = null,
        category = "기타",
        benefitType = "할인",
        benefitDescription = "혜택 설명",
        phone = null,
        eligibleTarget = null,
        usageCondition = null,
        verificationMethod = null,
        sourceType = BenefitSourceType.MANUAL_LOCAL,
        sourceLabel = "테스트",
        sourceUrl = null,
        lastVerifiedAt = null,
        status = BenefitStatus.ACTIVE,
        district = "마포구",
    )
}

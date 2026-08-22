package com.example.milipercent.navigation

import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.remember
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.navigation.compose.rememberNavController
import com.example.milipercent.ui.BenefitDetailScreen
import com.example.milipercent.ui.BenefitDetailUiModel
import com.example.milipercent.ui.BenefitDetailUiState
import org.junit.Rule
import org.junit.Test

class BenefitNavigationTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun listItemOpensDetailWithIdAndBackRestoresListState() {
        composeRule.setContent {
            MaterialTheme {
                val navController = rememberNavController()
                val selectedDistrict = remember { "강남구" }
                val searchQuery = remember { "롯데시네마" }

                BenefitNavigationHost(
                    navController = navController,
                    listContent = { onBenefitSelected, onDebugAdmin ->
                        Column {
                            Text("선택 지역: $selectedDistrict")
                            Text("검색어: $searchQuery")
                            Button(onClick = { onBenefitSelected("mma_route_id") }) {
                                Text("상세 열기")
                            }
                            Button(onClick = onDebugAdmin) {
                                Text("관리 열기")
                            }
                        }
                    },
                    detailContent = { benefitId, onBack ->
                        BenefitDetailScreen(
                            uiState = BenefitDetailUiState.Success(
                                BenefitDetailUiModel(
                                    id = benefitId,
                                    name = "테스트 상세",
                                    address = "주소",
                                    phone = "전화번호",
                                    benefitType = "할인",
                                    district = "강남구",
                                    sourceLabel = "병무청 나라사랑가게",
                                ),
                            ),
                            onBack = onBack,
                        )
                    },
                    debugAdminEnabled = true,
                    adminListContent = { onBack, onCreate, _ ->
                        Column {
                            Text("관리 목록")
                            Button(onClick = onCreate) { Text("등록 폼") }
                            Button(onClick = onBack) { Text("관리 닫기") }
                        }
                    },
                    adminFormContent = { benefitId, _, onSaved ->
                        Column {
                            Text("관리 폼: ${benefitId ?: "신규"}")
                            Button(onClick = onSaved) { Text("저장 완료") }
                        }
                    },
                )
            }
        }

        composeRule.onNodeWithText("상세 열기").performClick()
        composeRule.onNodeWithText("테스트 상세").assertIsDisplayed()

        composeRule.onNodeWithText("← 뒤로").performClick()
        composeRule.onNodeWithText("선택 지역: 강남구").assertIsDisplayed()
        composeRule.onNodeWithText("검색어: 롯데시네마").assertIsDisplayed()

        composeRule.onNodeWithText("관리 열기").performClick()
        composeRule.onNodeWithText("관리 목록").assertIsDisplayed()
        composeRule.onNodeWithText("등록 폼").performClick()
        composeRule.onNodeWithText("관리 폼: 신규").assertIsDisplayed()
        composeRule.onNodeWithText("저장 완료").performClick()
        composeRule.onNodeWithText("관리 목록").assertIsDisplayed()
    }
}

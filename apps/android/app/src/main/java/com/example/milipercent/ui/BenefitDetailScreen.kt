package com.example.milipercent.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BenefitDetailScreen(
    uiState: BenefitDetailUiState,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    BackHandler(onBack = onBack)

    Scaffold(
        modifier = modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = { Text("혜택 상세") },
                navigationIcon = {
                    TextButton(onClick = onBack) {
                        Text("← 뒤로")
                    }
                },
            )
        },
    ) { contentPadding ->
        when (uiState) {
            BenefitDetailUiState.Loading -> DetailCenteredContent(
                contentPadding = contentPadding,
            ) {
                CircularProgressIndicator()
            }

            BenefitDetailUiState.NotFound -> DetailCenteredContent(
                contentPadding = contentPadding,
            ) {
                Text("해당 혜택 정보를 찾을 수 없습니다.")
            }

            BenefitDetailUiState.Error -> DetailCenteredContent(
                contentPadding = contentPadding,
            ) {
                Text("혜택 정보를 불러오지 못했습니다.")
            }

            is BenefitDetailUiState.Success -> BenefitDetailContent(
                benefit = uiState.benefit,
                contentPadding = contentPadding,
            )
        }
    }
}

@Composable
private fun DetailCenteredContent(
    contentPadding: PaddingValues,
    content: @Composable () -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .padding(contentPadding)
            .padding(24.dp),
        contentAlignment = Alignment.Center,
    ) {
        content()
    }
}

@Composable
private fun BenefitDetailContent(
    benefit: BenefitDetailUiModel,
    contentPadding: PaddingValues,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(contentPadding)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 24.dp, vertical = 20.dp)
            .testTag("benefit_detail_${benefit.id}"),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        Text(
            text = benefit.name,
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
        )
        benefit.statusNotice?.let { notice ->
            Text(
                text = notice,
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.error,
                fontWeight = FontWeight.SemiBold,
            )
        }
        DetailField(label = "혜택 유형", value = benefit.benefitType)
        benefit.benefitDescription?.let {
            DetailField(label = "혜택 내용", value = it)
        }
        benefit.eligibleTarget?.let {
            DetailField(label = "적용 대상", value = it)
        }
        benefit.usageCondition?.let {
            DetailField(label = "이용 조건", value = it)
        }
        benefit.verificationMethod?.let {
            DetailField(label = "인증 방법", value = it)
        }
        benefit.lastVerifiedDate?.let {
            DetailField(label = "최근 확인일", value = it)
        }
        HorizontalDivider()
        DetailField(label = "주소", value = benefit.address)
        DetailField(label = "전화번호", value = benefit.phone)
        DetailField(label = "지역", value = benefit.district)
        DetailField(label = "정보 출처", value = benefit.sourceLabel)
        Text(
            text = benefit.sourceNotice,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun DetailField(label: String, value: String) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(text = value, style = MaterialTheme.typography.bodyLarge)
    }
}

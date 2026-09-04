package com.example.milipercent.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import com.example.milipercent.model.BenefitDistrict
import com.example.milipercent.model.BenefitUiModel

@Composable
fun BenefitScreen(
    uiState: BenefitUiState,
    benefitListState: LazyListState,
    onRetry: () -> Unit,
    onDistrictSelected: (BenefitDistrict) -> Unit,
    onSearchQueryChanged: (String) -> Unit,
    onClearSearch: () -> Unit,
    onBenefitSelected: (String) -> Unit,
    showDebugAdmin: Boolean,
    onOpenDebugAdmin: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp, vertical = 24.dp),
    ) {
        Text(
            text = "서울 군인 혜택",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
        )
        if (showDebugAdmin) {
            TextButton(onClick = onOpenDebugAdmin) {
                Text("Debug 자체 혜택 관리")
            }
        }
        Spacer(modifier = Modifier.height(16.dp))

        when (uiState) {
            is BenefitUiState.Loading -> LoadingContent(
                loading = uiState,
                modifier = Modifier.weight(1f),
            )
            BenefitUiState.Error -> ErrorContent(
                onRetry = onRetry,
                modifier = Modifier.weight(1f),
            )
            is BenefitUiState.Success -> SuccessContent(
                success = uiState,
                onDistrictSelected = onDistrictSelected,
                onSearchQueryChanged = onSearchQueryChanged,
                onClearSearch = onClearSearch,
                onBenefitSelected = onBenefitSelected,
                benefitListState = benefitListState,
                modifier = Modifier.weight(1f),
            )
        }
    }
}

@Composable
private fun LoadingContent(
    loading: BenefitUiState.Loading,
    modifier: Modifier = Modifier,
) {
    Box(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            CircularProgressIndicator()
            Spacer(modifier = Modifier.height(12.dp))
            Text("나라사랑가게 정보를 불러오는 중...")
            Spacer(modifier = Modifier.height(6.dp))
            if (loading.totalPages == null) {
                Text("첫 페이지 확인 중...")
            } else {
                Text("${loading.currentPage} / ${loading.totalPages} 페이지")
                Text("${loading.collectedCount}건 수집 중...")
            }
        }
    }
}

@Composable
private fun ErrorContent(
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("데이터를 불러오지 못했습니다.")
            Button(onClick = onRetry) {
                Text("다시 시도")
            }
        }
    }
}

@Composable
private fun SuccessContent(
    success: BenefitUiState.Success,
    onDistrictSelected: (BenefitDistrict) -> Unit,
    onSearchQueryChanged: (String) -> Unit,
    onClearSearch: () -> Unit,
    onBenefitSelected: (String) -> Unit,
    benefitListState: LazyListState,
    modifier: Modifier = Modifier,
) {
    val keyboardController = LocalSoftwareKeyboardController.current
    val isSearching = BenefitSearchMatcher.normalize(success.searchQuery).isNotEmpty()

    Column(modifier = modifier.fillMaxWidth()) {
        success.apiCollectedCount?.let { collectedCount ->
            Text(
                text = "전체 데이터: ${collectedCount}건",
                style = MaterialTheme.typography.bodyLarge,
            )
        }
        Text(
            text = "서울 데이터: ${success.districtCounts[BenefitDistrict.ALL] ?: 0}건",
            style = MaterialTheme.typography.bodyLarge,
        )
        when {
            success.isRefreshing -> {
                val refreshProgress = success.progress
                val message = if (refreshProgress?.totalPages != null) {
                    "최신 데이터 갱신 중: ${refreshProgress.currentPage} / " +
                        "${refreshProgress.totalPages} 페이지"
                } else {
                    "최신 데이터 갱신 중..."
                }
                Text(message, style = MaterialTheme.typography.bodySmall)
            }

            success.refreshFailed -> Text(
                text = "최신 데이터 갱신에 실패해 저장된 정보를 표시합니다.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
            )
        }
        Spacer(modifier = Modifier.height(12.dp))

        Text(
            text = "지역 선택",
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
        )
        Spacer(modifier = Modifier.height(6.dp))
        LazyRow(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            items(items = BenefitDistrict.entries, key = BenefitDistrict::name) { district ->
                FilterChip(
                    selected = district == success.selectedDistrict,
                    onClick = { onDistrictSelected(district) },
                    label = {
                        Text(
                            "${district.displayName} " +
                                "${success.districtCounts[district] ?: 0}",
                        )
                    },
                )
            }
        }
        Spacer(modifier = Modifier.height(12.dp))

        OutlinedTextField(
            value = success.searchQuery,
            onValueChange = onSearchQueryChanged,
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            placeholder = { Text("업체명 또는 지역을 검색하세요") },
            trailingIcon = if (success.searchQuery.isNotEmpty()) {
                {
                    TextButton(onClick = onClearSearch) {
                        Text("지우기")
                    }
                }
            } else {
                null
            },
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            keyboardActions = KeyboardActions(
                onSearch = { keyboardController?.hide() },
            ),
        )
        Spacer(modifier = Modifier.height(12.dp))

        Text(
            text = if (isSearching) {
                "${success.selectedDistrict.displayName} 검색 결과"
            } else {
                "${success.selectedDistrict.displayName} 혜택"
            },
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            text = if (isSearching) {
                "${success.benefits.size}개의 검색 결과"
            } else {
                "${success.benefits.size}개의 혜택"
            },
            style = MaterialTheme.typography.bodyMedium,
        )
        Spacer(modifier = Modifier.height(8.dp))

        if (success.benefits.isEmpty()) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    if (isSearching) {
                        "검색 결과가 없습니다. 다른 검색어를 입력해보세요."
                    } else {
                        "현재 등록된 혜택이 없습니다."
                    },
                )
            }
        } else {
            LazyColumn(
                state = benefitListState,
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f),
            ) {
                items(items = success.benefits, key = BenefitUiModel::id) { benefit ->
                    BenefitItem(
                        benefit = benefit,
                        onClick = { onBenefitSelected(benefit.id) },
                    )
                    HorizontalDivider()
                }
            }
        }
    }
}

@Composable
private fun BenefitItem(
    benefit: BenefitUiModel,
    onClick: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(vertical = 16.dp)
            .testTag("benefit_item_${benefit.id}"),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(
            text = benefit.name.ifBlank { "업체명 정보 없음" },
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
        )
        Text(benefit.address ?: "주소 정보 없음")
        Text(benefit.phone ?: "전화번호 정보 없음")
        Text("혜택 유형: ${benefit.benefitType ?: "정보 없음"}")
    }
}

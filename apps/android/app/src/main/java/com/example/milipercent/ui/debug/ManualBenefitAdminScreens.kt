package com.example.milipercent.ui.debug

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.milipercent.data.local.ManualBenefitStatus
import com.example.milipercent.data.manual.ManualBenefitInput
import com.example.milipercent.data.manual.ManualBenefitRecord
import com.example.milipercent.model.BenefitDistrict

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ManualBenefitAdminScreen(
    uiState: ManualBenefitAdminUiState,
    onBack: () -> Unit,
    onCreate: () -> Unit,
    onEdit: (String) -> Unit,
    onDelete: (String) -> Unit,
) {
    var deleteTarget by rememberSaveable { mutableStateOf<String?>(null) }
    BackHandler(onBack = onBack)

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Debug 자체 혜택 관리") },
                navigationIcon = {
                    TextButton(onClick = onBack) { Text("← 뒤로") }
                },
                actions = {
                    TextButton(onClick = onCreate) { Text("새 혜택") }
                },
            )
        },
    ) { padding ->
        when {
            uiState.isLoading -> Box(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentAlignment = Alignment.Center,
            ) { CircularProgressIndicator() }

            else -> LazyColumn(
                modifier = Modifier.fillMaxSize().padding(padding).padding(horizontal = 20.dp),
            ) {
                item {
                    Text(
                        text = "MANUAL_LOCAL ${uiState.benefits.size}건 · Debug 전용",
                        modifier = Modifier.padding(vertical = 12.dp),
                        style = MaterialTheme.typography.bodyMedium,
                    )
                    uiState.errorMessage?.let {
                        Text(it, color = MaterialTheme.colorScheme.error)
                    }
                }
                if (uiState.benefits.isEmpty()) {
                    item {
                        Text(
                            "등록된 Debug 자체 혜택이 없습니다.",
                            modifier = Modifier.padding(vertical = 32.dp),
                        )
                    }
                }
                items(uiState.benefits, key = ManualBenefitRecord::id) { record ->
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onEdit(record.id) }
                            .padding(vertical = 14.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        Text(record.input.name, fontWeight = FontWeight.SemiBold)
                        Text("${record.input.district.displayName} · ${record.input.status.name}")
                        Text(record.input.benefitDescription)
                        TextButton(onClick = { deleteTarget = record.id }) {
                            Text("삭제")
                        }
                    }
                    HorizontalDivider()
                }
            }
        }
    }

    deleteTarget?.let { id ->
        AlertDialog(
            onDismissRequest = { deleteTarget = null },
            title = { Text("혜택 삭제") },
            text = { Text("이 MANUAL_LOCAL 혜택을 삭제할까요?") },
            confirmButton = {
                TextButton(
                    onClick = {
                        onDelete(id)
                        deleteTarget = null
                    },
                ) { Text("삭제") }
            },
            dismissButton = {
                TextButton(onClick = { deleteTarget = null }) { Text("취소") }
            },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ManualBenefitFormScreen(
    uiState: ManualBenefitFormUiState,
    onBack: () -> Unit,
    onSave: (ManualBenefitInput) -> Unit,
    onSaved: () -> Unit,
) {
    BackHandler(onBack = onBack)
    LaunchedEffect(uiState.savedId) {
        if (uiState.savedId != null) onSaved()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(if (uiState.existing == null) "자체 혜택 등록" else "자체 혜택 수정") },
                navigationIcon = {
                    TextButton(onClick = onBack) { Text("← 뒤로") }
                },
            )
        },
    ) { padding ->
        if (uiState.isLoading) {
            Box(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentAlignment = Alignment.Center,
            ) { CircularProgressIndicator() }
        } else {
            key(uiState.existing?.id) {
                ManualBenefitForm(
                    existing = uiState.existing,
                    isSaving = uiState.isSaving,
                    errorMessage = uiState.errorMessage,
                    onSave = onSave,
                    modifier = Modifier.padding(padding),
                )
            }
        }
    }
}

@Composable
private fun ManualBenefitForm(
    existing: ManualBenefitRecord?,
    isSaving: Boolean,
    errorMessage: String?,
    onSave: (ManualBenefitInput) -> Unit,
    modifier: Modifier = Modifier,
) {
    val initial = existing?.input
    var name by rememberSaveable { mutableStateOf(initial?.name.orEmpty()) }
    var address by rememberSaveable { mutableStateOf(initial?.address.orEmpty()) }
    var districtName by rememberSaveable {
        mutableStateOf((initial?.district ?: BenefitDistrict.GANGNAM).name)
    }
    var phone by rememberSaveable { mutableStateOf(initial?.phone.orEmpty()) }
    var benefitType by rememberSaveable { mutableStateOf(initial?.benefitType.orEmpty()) }
    var description by rememberSaveable { mutableStateOf(initial?.benefitDescription.orEmpty()) }
    var eligibleTarget by rememberSaveable { mutableStateOf(initial?.eligibleTarget.orEmpty()) }
    var usageCondition by rememberSaveable { mutableStateOf(initial?.usageCondition.orEmpty()) }
    var verificationMethod by rememberSaveable { mutableStateOf(initial?.verificationMethod.orEmpty()) }
    var sourceUrl by rememberSaveable { mutableStateOf(initial?.sourceUrl.orEmpty()) }
    var lastVerifiedDate by rememberSaveable { mutableStateOf(initial?.lastVerifiedDate.orEmpty()) }
    var statusName by rememberSaveable {
        mutableStateOf((initial?.status ?: ManualBenefitStatus.ACTIVE).name)
    }
    val district = BenefitDistrict.valueOf(districtName)
    val status = ManualBenefitStatus.valueOf(statusName)

    LazyColumn(
        modifier = modifier.fillMaxSize().padding(horizontal = 20.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item { Text("TEST/검증용 MANUAL_LOCAL", modifier = Modifier.padding(top = 12.dp)) }
        item { FormField("업체명 *", name) { name = it } }
        item { FormField("주소 *", address) { address = it } }
        item {
            SelectionMenu(
                label = "지역 *",
                selected = district.displayName,
                options = BenefitDistrict.seoulDistricts,
                optionLabel = BenefitDistrict::displayName,
                onSelected = { districtName = it.name },
            )
        }
        item { FormField("전화번호", phone) { phone = it } }
        item { FormField("혜택 유형", benefitType) { benefitType = it } }
        item { FormField("혜택 내용 *", description, singleLine = false) { description = it } }
        item { FormField("적용 대상", eligibleTarget) { eligibleTarget = it } }
        item { FormField("이용 조건", usageCondition, singleLine = false) { usageCondition = it } }
        item { FormField("확인 방법 *", verificationMethod) { verificationMethod = it } }
        item { FormField("출처 URL", sourceUrl) { sourceUrl = it } }
        item { FormField("최근 확인일 YYYY-MM-DD *", lastVerifiedDate) { lastVerifiedDate = it } }
        item {
            SelectionMenu(
                label = "상태 *",
                selected = status.name,
                options = ManualBenefitStatus.entries,
                optionLabel = ManualBenefitStatus::name,
                onSelected = { statusName = it.name },
            )
        }
        errorMessage?.let { message ->
            item { Text(message, color = MaterialTheme.colorScheme.error) }
        }
        item {
            Button(
                onClick = {
                    onSave(
                        ManualBenefitInput(
                            name = name,
                            address = address,
                            district = district,
                            phone = phone,
                            benefitType = benefitType,
                            benefitDescription = description,
                            eligibleTarget = eligibleTarget,
                            usageCondition = usageCondition,
                            verificationMethod = verificationMethod,
                            sourceUrl = sourceUrl,
                            lastVerifiedDate = lastVerifiedDate,
                            status = status,
                        ),
                    )
                },
                modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp),
                enabled = !isSaving,
            ) {
                Text(if (isSaving) "저장 중..." else "저장")
            }
        }
    }
}

@Composable
private fun FormField(
    label: String,
    value: String,
    singleLine: Boolean = true,
    onValueChange: (String) -> Unit,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        label = { Text(label) },
        modifier = Modifier.fillMaxWidth(),
        singleLine = singleLine,
        minLines = if (singleLine) 1 else 3,
    )
}

@Composable
private fun <T> SelectionMenu(
    label: String,
    selected: String,
    options: List<T>,
    optionLabel: (T) -> String,
    onSelected: (T) -> Unit,
) {
    var expanded by rememberSaveable { mutableStateOf(false) }
    Column {
        Text(label, style = MaterialTheme.typography.labelLarge)
        Box {
            Button(onClick = { expanded = true }) { Text(selected) }
            DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                options.forEach { option ->
                    DropdownMenuItem(
                        text = { Text(optionLabel(option)) },
                        onClick = {
                            onSelected(option)
                            expanded = false
                        },
                    )
                }
            }
        }
    }
}

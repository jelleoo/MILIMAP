package com.example.milipercent.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.milipercent.data.admin.AdminBenefitInput
import com.example.milipercent.data.local.BenefitSourceType
import com.example.milipercent.model.Benefit
import com.example.milipercent.model.BenefitStatus
import com.example.milipercent.model.LocalUser
import kotlinx.coroutines.launch

@Composable
fun SavedScreen(
    items: List<BenefitListItem>,
    favoriteIds: Set<String>,
    onSelect: (String) -> Unit,
    onFavorite: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (items.isEmpty()) {
        PlaceholderScreen("찜한 혜택", "찜한 혜택이 아직 없어요.", modifier)
        return
    }
    LazyColumn(
        modifier = modifier.fillMaxSize().padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item { Text("찜한 혜택", color = Navy, fontWeight = FontWeight.ExtraBold) }
        items(items, key = { it.benefit.id }) { item ->
            val benefit = item.benefit
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("saved_benefit_${benefit.id}")
                    .clickable { onSelect(benefit.id) },
                colors = CardDefaults.cardColors(containerColor = androidx.compose.ui.graphics.Color.White),
            ) {
                Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(benefit.name, fontWeight = FontWeight.Bold, color = Navy)
                        Text(benefit.benefitDescription, color = Muted)
                    }
                    if (benefit.id in favoriteIds) {
                        TextButton(onClick = { onFavorite(benefit.id) }) { Text("♥") }
                    }
                }
            }
        }
    }
}

@Composable
fun AccountScreen(
    user: LocalUser?,
    onRegister: suspend (String, String, String) -> Result<LocalUser>,
    onLogin: suspend (String, String) -> Result<LocalUser>,
    onLogout: () -> Unit,
    modifier: Modifier = Modifier,
) {
    if (user != null) {
        Column(
            modifier = modifier.fillMaxSize().padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("MY", color = Navy, fontWeight = FontWeight.ExtraBold)
            Text(user.displayName, style = androidx.compose.material3.MaterialTheme.typography.headlineSmall)
            Text(user.email, color = Muted)
            if (user.isAdmin) Text("관리자 계정", color = PrimaryDark, fontWeight = FontWeight.Bold)
            Button(onClick = onLogout) { Text("로그아웃") }
        }
        return
    }

    val scope = rememberCoroutineScope()
    var loginMode by remember { mutableStateOf(false) }
    var email by remember { mutableStateOf("") }
    var displayName by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    Column(
        modifier = modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(if (loginMode) "로그인" else "회원가입", color = Navy, fontWeight = FontWeight.ExtraBold)
        OutlinedTextField(email, { email = it }, Modifier.fillMaxWidth(), label = { Text("이메일") })
        if (!loginMode) OutlinedTextField(displayName, { displayName = it }, Modifier.fillMaxWidth(), label = { Text("이름") })
        OutlinedTextField(password, { password = it }, Modifier.fillMaxWidth(), label = { Text("비밀번호") })
        errorMessage?.let { Text(it, color = Danger) }
        Button(
            onClick = {
                scope.launch {
                    val result = if (loginMode) onLogin(email, password) else onRegister(email, displayName, password)
                    errorMessage = result.exceptionOrNull()?.message
                }
            },
            modifier = Modifier.fillMaxWidth(),
        ) { Text(if (loginMode) "로그인" else "회원가입") }
        TextButton(
            onClick = { loginMode = !loginMode; errorMessage = null },
            modifier = Modifier.testTag("account_login_mode"),
        ) { Text(if (loginMode) "회원가입으로 전환" else "로그인으로 전환") }
    }
}

@Composable
fun AdminScreen(
    user: LocalUser?,
    benefits: List<Benefit>,
    onSave: (AdminBenefitInput, String?) -> Unit,
    onEnd: (String) -> Unit,
    onDeleteManual: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (user?.isAdmin != true) {
        PlaceholderScreen("관리", "관리자 권한이 필요합니다.", modifier)
        return
    }
    var name by remember { mutableStateOf("") }
    var address by remember { mutableStateOf("") }
    var description by remember { mutableStateOf("") }
    var editingId by remember { mutableStateOf<String?>(null) }
    LazyColumn(
        modifier = modifier.fillMaxSize().padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item {
            Text("혜택 관리", color = Navy, fontWeight = FontWeight.ExtraBold)
            OutlinedTextField(name, { name = it }, Modifier.fillMaxWidth(), label = { Text("업체명") })
            OutlinedTextField(address, { address = it }, Modifier.fillMaxWidth(), label = { Text("주소") })
            OutlinedTextField(description, { description = it }, Modifier.fillMaxWidth(), label = { Text("혜택 내용") })
            Button(
                onClick = {
                    onSave(
                        AdminBenefitInput(
                            name = name,
                            address = address,
                            latitude = null,
                            longitude = null,
                            category = "기타",
                            benefitType = "할인·우대",
                            benefitDescription = description,
                            phone = null,
                            eligibleTarget = null,
                            usageCondition = null,
                            verificationMethod = null,
                            sourceLabel = "운영팀 직접 등록",
                            sourceUrl = null,
                            lastVerifiedAt = null,
                            status = BenefitStatus.ACTIVE,
                            district = null,
                        ),
                        editingId,
                    )
                },
                modifier = Modifier.fillMaxWidth(),
            ) { Text(if (editingId == null) "수동 혜택 등록" else "수정 내용 저장") }
        }
        items(benefits, key = Benefit::id) { benefit ->
            Card(colors = CardDefaults.cardColors(containerColor = androidx.compose.ui.graphics.Color.White)) {
                Column(Modifier.padding(14.dp)) {
                    Text(benefit.name, color = Navy, fontWeight = FontWeight.Bold)
                    Text(statusLabel(benefit.status), color = if (benefit.status == BenefitStatus.ENDED) Danger else Muted)
                    if (benefit.sourceType == BenefitSourceType.MANUAL_LOCAL) {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            TextButton(
                                onClick = {
                                    editingId = benefit.id
                                    name = benefit.name
                                    address = benefit.address
                                    description = benefit.benefitDescription
                                },
                            ) { Text("수정") }
                            TextButton(onClick = { onEnd(benefit.id) }) { Text("종료") }
                            TextButton(onClick = { onDeleteManual(benefit.id) }) { Text("삭제") }
                        }
                    }
                }
            }
        }
    }
}

package com.example.militarybenefits.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import com.example.militarybenefits.AppController
import com.example.militarybenefits.AppDestination
import com.example.militarybenefits.data.Benefit
import com.example.militarybenefits.data.BenefitDatabase
import com.example.militarybenefits.data.BenefitStatus

@Composable
fun SavedScreen(controller: AppController) {
    val user = controller.user
    val saved = controller.savedBenefits()
    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(vertical = 22.dp),
        verticalArrangement = Arrangement.spacedBy(13.dp),
    ) {
        item {
            ScreenHeading(
                eyebrow = "SAVED",
                title = "찜한 혜택",
                description = if (user == null) "로그인하면 가고 싶은 혜택을 저장할 수 있어요." else "${user.displayName}님이 저장한 ${saved.size}곳",
            )
        }
        if (user == null) {
            item {
                EmptyCard("로그인이 필요해요", "이 기기의 로컬 계정으로 로그인하면 찜을 저장할 수 있어요.")
            }
            item {
                Button(
                    onClick = { controller.destination = AppDestination.ACCOUNT },
                    Modifier.fillMaxWidth().padding(horizontal = 20.dp).height(52.dp),
                    shape = RoundedCornerShape(15.dp),
                ) { Text("로그인하러 가기", fontWeight = FontWeight.Bold) }
            }
        } else if (saved.isEmpty()) {
            item { EmptyCard("아직 찜한 혜택이 없어요", "지도 마커나 혜택 카드의 하트를 눌러 저장해 보세요.") }
        } else {
            items(saved, key = { it.id }) { benefit ->
                BenefitCard(
                    benefit = benefit,
                    distance = controller.distanceFromCenter(benefit),
                    favorite = true,
                    onClick = { controller.select(benefit) },
                    onFavorite = { controller.toggleFavorite(benefit) },
                )
            }
        }
    }
}

@Composable
fun AccountScreen(controller: AppController) {
    val user = controller.user
    if (user != null) {
        LazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = PaddingValues(horizontal = 20.dp, vertical = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item { ScreenHeading("MY", "내 계정", "찜과 운영 권한을 이 기기에 안전하게 보관합니다.", horizontalPadding = 0.dp) }
            item {
                Card(
                    Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(24.dp),
                    colors = CardDefaults.cardColors(containerColor = PrimaryBlue),
                ) {
                    Row(Modifier.padding(22.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(
                            Modifier.size(58.dp).clip(CircleShape).background(Color.White),
                            contentAlignment = Alignment.Center,
                        ) { Text(user.displayName.take(1), color = Navy, fontWeight = FontWeight.Black, fontSize = 23.sp) }
                        Spacer(Modifier.width(15.dp))
                        Column(Modifier.weight(1f)) {
                            Text(user.displayName, color = Navy, fontWeight = FontWeight.Black, fontSize = 21.sp)
                            Text(user.email, color = Navy.copy(alpha = .7f), fontSize = 12.sp)
                            Text(if (user.isAdmin) "이 기기 관리자" else "일반 사용자", color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp)
                        }
                    }
                }
            }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    AccountStat(controller.favoriteIds.size.toString(), "찜", Modifier.weight(1f))
                    AccountStat(controller.benefits.size.toString(), "전체 혜택", Modifier.weight(1f))
                }
            }
            if (user.isAdmin) {
                item {
                    Button(
                        onClick = { controller.destination = AppDestination.ADMIN },
                        Modifier.fillMaxWidth().height(54.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = Navy),
                        shape = RoundedCornerShape(15.dp),
                    ) { Text("관리자 혜택 CRUD 열기", fontWeight = FontWeight.Bold) }
                }
            }
            item {
                Surface(color = PrimarySoft, shape = RoundedCornerShape(18.dp)) {
                    Column(Modifier.padding(18.dp)) {
                        Text("MVP 계정 안내", color = Navy, fontWeight = FontWeight.ExtraBold)
                        Spacer(Modifier.height(5.dp))
                        Text("현재 계정과 찜은 이 기기에 저장됩니다. 실제 출시 전 Firebase/Supabase 인증과 서버 DB로 교체할 수 있도록 기능을 분리했습니다.", color = Muted, fontSize = 12.sp)
                    }
                }
            }
            item {
                OutlinedButton(onClick = controller::logout, Modifier.fillMaxWidth(), shape = RoundedCornerShape(15.dp)) {
                    Text("로그아웃", color = Danger, fontWeight = FontWeight.Bold)
                }
            }
        }
    } else {
        LocalAuthForm(controller)
    }
}

@Composable
private fun LocalAuthForm(controller: AppController) {
    var registerMode by remember { mutableStateOf(false) }
    var email by remember { mutableStateOf("") }
    var name by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 26.dp),
    ) {
        ScreenHeading("ACCOUNT", if (registerMode) "로컬 계정 만들기" else "로그인", "찜과 관리자 기능을 사용하려면 계정이 필요해요.", horizontalPadding = 0.dp)
        Spacer(Modifier.height(20.dp))
        Surface(color = Color.White, shape = RoundedCornerShape(24.dp), shadowElevation = 2.dp) {
            Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(13.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(selected = !registerMode, onClick = { registerMode = false; error = null }, label = { Text("로그인") })
                    FilterChip(selected = registerMode, onClick = { registerMode = true; error = null }, label = { Text("회원가입") })
                }
                if (registerMode) {
                    OutlinedTextField(name, { name = it }, Modifier.fillMaxWidth(), label = { Text("이름") }, singleLine = true)
                }
                OutlinedTextField(
                    email, { email = it }, Modifier.fillMaxWidth(), label = { Text("이메일") },
                    singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                )
                OutlinedTextField(
                    password, { password = it }, Modifier.fillMaxWidth(), label = { Text("비밀번호 6자 이상") },
                    singleLine = true, visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                )
                error?.let { Text(it, color = Danger, fontSize = 12.sp) }
                Button(
                    onClick = {
                        val result = if (registerMode) controller.register(email, name, password)
                        else controller.login(email, password)
                        error = result.exceptionOrNull()?.message
                    },
                    Modifier.fillMaxWidth().height(52.dp),
                    shape = RoundedCornerShape(15.dp),
                ) { Text(if (registerMode) "계정 만들기" else "로그인", fontWeight = FontWeight.Bold) }
            }
        }
        Spacer(Modifier.height(14.dp))
        Text("첫 번째로 만든 계정에는 이 기기의 관리자 권한이 자동 부여됩니다. 비밀번호는 해시 처리해 로컬 DB에 저장합니다.", color = Muted, fontSize = 12.sp)
    }
}

@Composable
fun AdminScreen(controller: AppController) {
    if (controller.user?.isAdmin != true) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            Text("관리자 권한이 필요합니다.", color = Navy, fontWeight = FontWeight.ExtraBold)
            TextButton(onClick = { controller.destination = AppDestination.ACCOUNT }) { Text("내 계정으로 이동") }
        }
        return
    }
    val benefits = controller.adminBenefits()
    var editing by remember { mutableStateOf<Benefit?>(null) }
    var ending by remember { mutableStateOf<Benefit?>(null) }
    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 20.dp, vertical = 22.dp),
        verticalArrangement = Arrangement.spacedBy(11.dp),
    ) {
        item {
            ScreenHeading("ADMIN", "혜택 데이터 관리", "등록·조회·수정·종료 처리 ${benefits.size}건", horizontalPadding = 0.dp)
        }
        item {
            Button(
                onClick = { editing = BenefitDatabase.newManualBenefit() },
                Modifier.fillMaxWidth().height(52.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Navy),
                shape = RoundedCornerShape(15.dp),
            ) { Text("＋ 새 혜택 등록", fontWeight = FontWeight.Bold) }
        }
        items(benefits, key = { it.id }) { benefit ->
            Card(colors = CardDefaults.cardColors(containerColor = Color.White), shape = RoundedCornerShape(18.dp)) {
                Column(Modifier.padding(15.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            when (benefit.status) {
                                BenefitStatus.ACTIVE -> "이용 가능"
                                BenefitStatus.NEEDS_VERIFICATION -> "확인 필요"
                                BenefitStatus.ENDED -> "종료"
                            },
                            color = if (benefit.status == BenefitStatus.ACTIVE) Success else if (benefit.status == BenefitStatus.ENDED) Danger else Warning,
                            fontWeight = FontWeight.Bold,
                            fontSize = 11.sp,
                        )
                        Spacer(Modifier.width(8.dp))
                        Text(benefit.category, color = Muted, fontSize = 11.sp)
                    }
                    Text(benefit.name, color = Navy, fontWeight = FontWeight.ExtraBold, fontSize = 16.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(benefit.benefitDescription, color = Muted, fontSize = 12.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    Spacer(Modifier.height(10.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(onClick = { editing = benefit }, Modifier.weight(1f)) { Text("수정") }
                        OutlinedButton(onClick = { ending = benefit }, Modifier.weight(1f), enabled = benefit.status != BenefitStatus.ENDED) { Text("종료", color = Danger) }
                    }
                }
            }
        }
    }
    editing?.let { benefit ->
        BenefitEditorDialog(
            initial = benefit,
            onDismiss = { editing = null },
            onSave = { changed ->
                controller.saveBenefit(changed).onSuccess { editing = null }
            },
        )
    }
    ending?.let { benefit ->
        AlertDialog(
            onDismissRequest = { ending = null },
            title = { Text("혜택 종료 처리") },
            text = { Text("${benefit.name}을 종료 상태로 변경할까요? 데이터는 삭제하지 않고 보존합니다.") },
            confirmButton = {
                TextButton(onClick = { controller.endBenefit(benefit.id); ending = null }) { Text("종료 처리", color = Danger) }
            },
            dismissButton = { TextButton(onClick = { ending = null }) { Text("취소") } },
        )
    }
}

@Composable
private fun BenefitEditorDialog(
    initial: Benefit,
    onDismiss: () -> Unit,
    onSave: (Benefit) -> Result<Unit>,
) {
    var draft by remember(initial.id) { mutableStateOf(initial) }
    var latitude by remember(initial.id) { mutableStateOf(initial.latitude?.toString().orEmpty()) }
    var longitude by remember(initial.id) { mutableStateOf(initial.longitude?.toString().orEmpty()) }
    var error by remember { mutableStateOf<String?>(null) }
    Dialog(onDismissRequest = onDismiss) {
        Card(
            Modifier.fillMaxWidth().fillMaxHeight(.92f),
            shape = RoundedCornerShape(24.dp),
            colors = CardDefaults.cardColors(containerColor = Color.White),
        ) {
            Column(Modifier.fillMaxSize()) {
                Row(Modifier.fillMaxWidth().padding(18.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(if (initial.name.isBlank()) "NEW BENEFIT" else "EDIT BENEFIT", color = PrimaryDark, fontSize = 10.sp, fontWeight = FontWeight.Black)
                        Text(if (initial.name.isBlank()) "혜택 등록" else "혜택 수정", color = Navy, fontWeight = FontWeight.Black, fontSize = 21.sp)
                    }
                    Text("닫기", Modifier.clickable(onClick = onDismiss).padding(8.dp), color = Muted)
                }
                HorizontalDivider(color = Line)
                Column(
                    Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(18.dp),
                    verticalArrangement = Arrangement.spacedBy(11.dp),
                ) {
                    EditField("업소명*", draft.name) { draft = draft.copy(name = it) }
                    EditField("주소*", draft.address) { draft = draft.copy(address = it) }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Box(Modifier.weight(1f)) { EditField("지역", draft.district.orEmpty()) { draft = draft.copy(district = it.blankToNull()) } }
                        Box(Modifier.weight(1f)) { EditField("카테고리", draft.category) { draft = draft.copy(category = it) } }
                    }
                    EditField("혜택 내용*", draft.benefitDescription, 3) { draft = draft.copy(benefitDescription = it) }
                    EditField("전화번호", draft.phone.orEmpty()) { draft = draft.copy(phone = it.blankToNull()) }
                    EditField("적용 대상", draft.eligibleTarget.orEmpty()) { draft = draft.copy(eligibleTarget = it.blankToNull()) }
                    EditField("이용 조건", draft.usageCondition.orEmpty(), 2) { draft = draft.copy(usageCondition = it.blankToNull()) }
                    EditField("인증 방법", draft.verificationMethod.orEmpty()) { draft = draft.copy(verificationMethod = it.blankToNull()) }
                    EditField("출처 표시", draft.sourceLabel) { draft = draft.copy(sourceLabel = it) }
                    EditField("출처 URL", draft.sourceUrl.orEmpty()) { draft = draft.copy(sourceUrl = it.blankToNull()) }
                    EditField("최근 확인일 YYYY-MM-DD", draft.lastVerifiedAt.orEmpty()) { draft = draft.copy(lastVerifiedAt = it.blankToNull()) }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Box(Modifier.weight(1f)) { EditField("위도", latitude) { latitude = it } }
                        Box(Modifier.weight(1f)) { EditField("경도", longitude) { longitude = it } }
                    }
                    Text("혜택 상태", color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp)
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        BenefitStatus.entries.forEach { status ->
                            FilterChip(
                                selected = draft.status == status,
                                onClick = { draft = draft.copy(status = status) },
                                label = { Text(if (status == BenefitStatus.ACTIVE) "이용 가능" else if (status == BenefitStatus.ENDED) "종료" else "확인 필요", fontSize = 10.sp) },
                            )
                        }
                    }
                    error?.let { Text(it, color = Danger, fontSize = 12.sp) }
                }
                HorizontalDivider(color = Line)
                Button(
                    onClick = {
                        val changed = draft.copy(
                            latitude = latitude.toDoubleOrNull(),
                            longitude = longitude.toDoubleOrNull(),
                        )
                        val result = onSave(changed)
                        error = result.exceptionOrNull()?.message
                    },
                    Modifier.fillMaxWidth().padding(18.dp).height(52.dp),
                    shape = RoundedCornerShape(15.dp),
                ) { Text("저장", fontWeight = FontWeight.Bold) }
            }
        }
    }
}

@Composable
private fun EditField(label: String, value: String, lines: Int = 1, onChange: (String) -> Unit) {
    OutlinedTextField(
        value = value,
        onValueChange = onChange,
        modifier = Modifier.fillMaxWidth(),
        label = { Text(label) },
        minLines = lines,
        maxLines = if (lines == 1) 1 else lines + 1,
    )
}

@Composable
private fun ScreenHeading(
    eyebrow: String,
    title: String,
    description: String,
    horizontalPadding: androidx.compose.ui.unit.Dp = 20.dp,
) {
    Column(Modifier.padding(horizontal = horizontalPadding)) {
        Text(eyebrow, color = PrimaryDark, fontWeight = FontWeight.Black, fontSize = 10.sp, letterSpacing = 1.5.sp)
        Text(title, color = Navy, fontWeight = FontWeight.Black, fontSize = 27.sp)
        Text(description, color = Muted, fontSize = 13.sp)
    }
}

@Composable
private fun AccountStat(value: String, label: String, modifier: Modifier = Modifier) {
    Surface(modifier, color = Color.White, shape = RoundedCornerShape(18.dp)) {
        Column(Modifier.padding(18.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(value, color = Navy, fontWeight = FontWeight.Black, fontSize = 23.sp)
            Text(label, color = Muted, fontSize = 12.sp)
        }
    }
}

private fun String.blankToNull(): String? = trim().ifBlank { null }

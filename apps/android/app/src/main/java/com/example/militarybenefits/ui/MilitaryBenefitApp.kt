package com.example.militarybenefits.ui

import android.content.Intent
import android.net.Uri
import android.widget.Toast
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.militarybenefits.AppController
import com.example.militarybenefits.AppDestination
import com.example.militarybenefits.BuildConfig
import com.example.militarybenefits.R
import com.example.militarybenefits.data.Benefit
import com.example.militarybenefits.data.BenefitStatus
import com.example.militarybenefits.data.GeoPoint
import com.example.militarybenefits.ui.map.openNaverMap
import kotlin.math.hypot

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MilitaryBenefitApp(
    controller: AppController,
    requestCurrentLocation: () -> Unit,
) {
    val snackbar = remember { SnackbarHostState() }
    val message = controller.transientMessage
    LaunchedEffect(Unit) {
        requestCurrentLocation()
        controller.syncMmaApi(BuildConfig.MMA_SERVICE_KEY)
    }
    LaunchedEffect(message) {
        if (message != null) {
            snackbar.showSnackbar(message)
            controller.clearMessage()
        }
    }

    Scaffold(
        containerColor = Canvas,
        topBar = { AppTopBar(controller) },
        bottomBar = { AppBottomBar(controller) },
        snackbarHost = { SnackbarHost(snackbar) },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            when (controller.destination) {
                AppDestination.DISCOVER -> DiscoverScreen(controller, requestCurrentLocation)
                AppDestination.SAVED -> SavedScreen(controller)
                AppDestination.ACCOUNT -> AccountScreen(controller)
                AppDestination.ADMIN -> AdminScreen(controller)
            }
        }
    }

    controller.selectedBenefit?.let { benefit ->
        BenefitDetailSheet(
            benefit = benefit,
            isFavorite = benefit.id in controller.favoriteIds,
            onDismiss = controller::closeDetail,
            onFavorite = { controller.toggleFavorite(benefit) },
        )
    }
}

@Composable
private fun AppTopBar(controller: AppController) {
    Surface(color = Color.White, shadowElevation = 2.dp) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 11.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                Modifier.size(42.dp).clip(RoundedCornerShape(14.dp)).background(PrimaryBlue),
                contentAlignment = Alignment.Center,
            ) { Text("M", fontWeight = FontWeight.Black, color = Navy, fontSize = 20.sp) }
            Spacer(Modifier.width(11.dp))
            Column(Modifier.weight(1f)) {
                Text("군 혜택 지도", fontWeight = FontWeight.ExtraBold, fontSize = 17.sp)
                Text("서비스명 준비 중", color = Muted, fontSize = 11.sp)
            }
            if (controller.user?.isAdmin == true) {
                Surface(
                    modifier = Modifier.clickable { controller.destination = AppDestination.ADMIN },
                    color = PrimarySoft,
                    shape = RoundedCornerShape(50),
                ) {
                    Text("관리", Modifier.padding(horizontal = 13.dp, vertical = 8.dp), color = PrimaryDark, fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}

@Composable
private fun AppBottomBar(controller: AppController) {
    val items = listOf(
        Triple(AppDestination.DISCOVER, "⌂", "탐색"),
        Triple(AppDestination.SAVED, "♡", "찜"),
        Triple(AppDestination.ACCOUNT, "●", "MY"),
    )
    NavigationBar(containerColor = Color(0xFF292A2D), tonalElevation = 0.dp) {
        items.forEach { (destination, symbol, label) ->
            NavigationBarItem(
                selected = controller.destination == destination,
                onClick = { controller.destination = destination },
                icon = { Text(symbol, fontSize = 22.sp, fontWeight = FontWeight.Bold) },
                label = { Text(label) },
                colors = NavigationBarItemDefaults.colors(
                    selectedIconColor = Color.White,
                    selectedTextColor = Color.White,
                    indicatorColor = PrimaryDark,
                    unselectedIconColor = Color(0xFF8A8B90),
                    unselectedTextColor = Color(0xFF8A8B90),
                ),
            )
        }
    }
}

@Composable
private fun DiscoverScreen(controller: AppController, requestCurrentLocation: () -> Unit) {
    val visible = controller.visibleBenefits()
    Box(Modifier.fillMaxSize()) {
        BenefitMap(
            benefits = visible,
            center = controller.center,
            currentLocation = controller.currentLocation,
            onSelect = controller::select,
            modifier = Modifier.fillMaxSize(),
        )
        MapSearchOverlay(controller, Modifier.align(Alignment.TopCenter))
        Button(
            onClick = requestCurrentLocation,
            modifier = Modifier.align(Alignment.CenterEnd).padding(end = 16.dp).size(52.dp),
            contentPadding = PaddingValues(0.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Navy),
            shape = CircleShape,
        ) { Text("◎", fontSize = 22.sp, color = Color.White) }
        NearbyDock(
            controller = controller,
            benefits = visible,
            modifier = Modifier.align(Alignment.BottomCenter),
        )
    }
}

@Composable
private fun MapSearchOverlay(controller: AppController, modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier.fillMaxWidth().padding(14.dp),
        color = Color.White.copy(alpha = .96f),
        shape = RoundedCornerShape(20.dp),
        shadowElevation = 7.dp,
    ) {
        Column(Modifier.padding(vertical = 10.dp)) {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                OutlinedTextField(
                    value = controller.searchText,
                    onValueChange = { controller.searchText = it },
                    modifier = Modifier.weight(1f),
                    placeholder = { Text("홍대·성수·강남역·파주 검색", fontSize = 13.sp) },
                    leadingIcon = { Text("⌕", fontSize = 20.sp) },
                    singleLine = true,
                    shape = RoundedCornerShape(14.dp),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                    keyboardActions = KeyboardActions(onSearch = { controller.search() }),
                )
                Spacer(Modifier.width(8.dp))
                Button(
                    onClick = { controller.search() },
                    modifier = Modifier.height(54.dp),
                    shape = RoundedCornerShape(14.dp),
                    contentPadding = PaddingValues(horizontal = 14.dp),
                ) { Text("검색", fontWeight = FontWeight.Bold) }
            }
            Spacer(Modifier.height(8.dp))
            LazyRow(
                contentPadding = PaddingValues(horizontal = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(7.dp),
            ) {
                items(controller.categories) { label ->
                    FilterChip(
                        selected = controller.category == label,
                        onClick = { controller.category = label },
                        label = { Text("${categorySymbol(label)} $label", fontSize = 11.sp, fontWeight = FontWeight.Bold) },
                    )
                }
            }
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 2.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(controller.locationLabel, color = Navy, fontWeight = FontWeight.ExtraBold, fontSize = 12.sp)
                Spacer(Modifier.weight(1f))
                Text(
                    if (controller.syncingMma) "나라사랑가게 동기화 중…" else controller.lastSyncLabel,
                    color = if (controller.syncingMma) PrimaryDark else Muted,
                    fontSize = 10.sp,
                )
            }
        }
    }
}

@Composable
private fun NearbyDock(
    controller: AppController,
    benefits: List<Benefit>,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        color = Color.White,
        shape = RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp),
        shadowElevation = 12.dp,
    ) {
        Column(Modifier.padding(vertical = 12.dp)) {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 18.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f)) {
                    Text("내 주변 혜택", color = Navy, fontWeight = FontWeight.Black, fontSize = 17.sp)
                    Text("${benefits.size}곳 · 지도 마커 ${benefits.count { it.latitude != null }}곳", color = Muted, fontSize = 11.sp)
                }
                Text("가까운 순", color = PrimaryDark, fontWeight = FontWeight.Bold, fontSize = 11.sp)
            }
            Spacer(Modifier.height(9.dp))
            if (benefits.isEmpty()) {
                Text("검색 결과가 없어요. 지역이나 카테고리를 바꿔보세요.", Modifier.padding(horizontal = 18.dp, vertical = 18.dp), color = Muted)
            } else {
                LazyRow(
                    contentPadding = PaddingValues(horizontal = 18.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    items(benefits.take(15), key = { it.id }) { benefit ->
                        Card(
                            modifier = Modifier.width(260.dp).clickable { controller.select(benefit) },
                            colors = CardDefaults.cardColors(containerColor = Canvas),
                            shape = RoundedCornerShape(16.dp),
                        ) {
                            Row(Modifier.padding(12.dp), verticalAlignment = Alignment.Top) {
                                Box(
                                    Modifier.size(39.dp).clip(RoundedCornerShape(12.dp))
                                        .background(categoryColor(benefit.category).copy(alpha = .14f)),
                                    contentAlignment = Alignment.Center,
                                ) { Text(categorySymbol(benefit.category), color = categoryColor(benefit.category)) }
                                Spacer(Modifier.width(10.dp))
                                Column(Modifier.weight(1f)) {
                                    Text(benefit.name, color = Navy, fontWeight = FontWeight.ExtraBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    Text(benefit.benefitDescription, color = Muted, fontSize = 11.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                                    controller.distanceFromCenter(benefit)?.let {
                                        Text(if (it < 1) "${(it * 1000).toInt()}m" else "%.1fkm".format(it), color = PrimaryDark, fontWeight = FontWeight.Bold, fontSize = 11.sp)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun Hero(controller: AppController, requestCurrentLocation: () -> Unit) {
    Column(
        Modifier.fillMaxWidth().background(PrimaryBlue)
            .padding(horizontal = 20.dp, vertical = 26.dp),
    ) {
        Text("서울 군 장병 혜택 탐색", color = Navy.copy(alpha = 0.68f), fontWeight = FontWeight.Bold, fontSize = 12.sp)
        Spacer(Modifier.height(10.dp))
        Text("휴가 동선 안의 혜택을\n한눈에 찾아보세요", color = Navy, fontWeight = FontWeight.Black, fontSize = 29.sp, lineHeight = 36.sp)
        Spacer(Modifier.height(10.dp))
        Text("현재 위치나 방문할 지역을 선택하면 확인 가능한 혜택을 가까운 순으로 보여드려요.", color = Navy.copy(alpha = 0.74f), fontSize = 14.sp)
        Spacer(Modifier.height(20.dp))
        OutlinedTextField(
            value = controller.searchText,
            onValueChange = { controller.searchText = it },
            modifier = Modifier.fillMaxWidth(),
            placeholder = { Text("홍대, 성수, 강남역, 자치구 검색") },
            leadingIcon = { Text("⌕", fontSize = 21.sp) },
            trailingIcon = {
                Text(
                    "검색",
                    Modifier.clickable { controller.search() }.padding(8.dp),
                    color = PrimaryDark,
                    fontWeight = FontWeight.Bold,
                )
            },
            singleLine = true,
            shape = RoundedCornerShape(16.dp),
            colors = OutlinedTextFieldDefaults.colors(
                focusedContainerColor = Color.White,
                unfocusedContainerColor = Color.White,
                focusedBorderColor = Color.Transparent,
                unfocusedBorderColor = Color.Transparent,
            ),
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            keyboardActions = KeyboardActions(onSearch = { controller.search() }),
        )
        Spacer(Modifier.height(12.dp))
        Button(
            onClick = requestCurrentLocation,
            modifier = Modifier.fillMaxWidth().height(50.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Navy),
            shape = RoundedCornerShape(15.dp),
        ) { Text("◎  현재 위치로 찾기", fontWeight = FontWeight.Bold) }
        Spacer(Modifier.height(18.dp))
        Row(
            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp))
                .background(Color.White.copy(alpha = 0.92f)).padding(vertical = 15.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
        ) {
            HeroStat(controller.benefits.size.toString(), "서울 혜택")
            HeroStat(controller.benefits.count { it.latitude != null }.toString(), "지도 좌표")
            HeroStat(controller.benefits.count { it.sourceType == "MMA_API" }.toString(), "공식 데이터")
        }
    }
}

@Composable
private fun HeroStat(value: String, label: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, color = Navy, fontWeight = FontWeight.Black, fontSize = 22.sp)
        Text(label, color = Muted, fontSize = 11.sp)
    }
}

@Composable
private fun DestinationPresets(controller: AppController) {
    Column {
        Text("휴가 예정 지역", Modifier.padding(horizontal = 20.dp), color = Muted, fontWeight = FontWeight.Bold, fontSize = 12.sp)
        Spacer(Modifier.height(7.dp))
        LazyRow(contentPadding = PaddingValues(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(listOf("홍대", "성수", "잠실", "강남역", "신촌", "건대", "서울역")) { label ->
                Surface(
                    modifier = Modifier.clickable { controller.choosePreset(label) },
                    color = if (controller.locationLabel == label) Navy else Color.White,
                    shape = RoundedCornerShape(50),
                    border = androidx.compose.foundation.BorderStroke(1.dp, if (controller.locationLabel == label) Navy else Line),
                ) {
                    Text(
                        label,
                        Modifier.padding(horizontal = 16.dp, vertical = 9.dp),
                        color = if (controller.locationLabel == label) Color.White else Navy,
                        fontWeight = FontWeight.Bold,
                        fontSize = 13.sp,
                    )
                }
            }
        }
    }
}

@Composable
private fun CategoryFilters(controller: AppController) {
    LazyRow(contentPadding = PaddingValues(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        items(controller.categories) { label ->
            FilterChip(
                selected = controller.category == label,
                onClick = { controller.category = label },
                label = { Text(categorySymbol(label) + "  " + label, fontWeight = FontWeight.Bold) },
                shape = RoundedCornerShape(13.dp),
            )
        }
    }
}

@Composable
private fun SectionHeading(eyebrow: String, title: String, trailing: String) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 20.dp),
        verticalAlignment = Alignment.Bottom,
    ) {
        Column(Modifier.weight(1f)) {
            Text(eyebrow, color = PrimaryDark, fontWeight = FontWeight.Black, fontSize = 10.sp, letterSpacing = 1.5.sp)
            Text(title, color = Navy, fontWeight = FontWeight.ExtraBold, fontSize = 20.sp)
        }
        Text(trailing, color = Muted, fontSize = 12.sp)
    }
}

@Composable
private fun SeoulCoordinateMap(
    benefits: List<Benefit>,
    center: GeoPoint,
    currentLocation: GeoPoint?,
    onSelect: (Benefit) -> Unit,
) {
    val density = LocalDensity.current
    val tapRadius = with(density) { 28.dp.toPx() }
    Card(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp),
        shape = RoundedCornerShape(24.dp),
        colors = CardDefaults.cardColors(containerColor = PrimarySoft),
        elevation = CardDefaults.cardElevation(2.dp),
    ) {
        Box(Modifier.fillMaxWidth().height(310.dp)) {
            Canvas(
                Modifier.fillMaxSize().pointerInput(benefits) {
                    detectTapGestures { tap ->
                        benefits.asSequence()
                            .filter { it.latitude != null && it.longitude != null }
                            .map { it to mapOffset(it.latitude!!, it.longitude!!, size.width.toFloat(), size.height.toFloat()) }
                            .minByOrNull { (_, point) -> hypot(tap.x - point.x, tap.y - point.y) }
                            ?.takeIf { (_, point) -> hypot(tap.x - point.x, tap.y - point.y) <= tapRadius }
                            ?.let { (benefit) -> onSelect(benefit) }
                    }
                },
            ) {
                drawRect(PrimarySoft)
                val roadColor = Color.White.copy(alpha = 0.82f)
                repeat(7) { index ->
                    val y = size.height * (index + 1) / 8f
                    drawLine(roadColor, Offset(0f, y), Offset(size.width, y - size.height * 0.08f), strokeWidth = 7f, cap = StrokeCap.Round)
                }
                repeat(8) { index ->
                    val x = size.width * (index + 1) / 9f
                    drawLine(roadColor, Offset(x, 0f), Offset(x + size.width * 0.12f, size.height), strokeWidth = 5f, cap = StrokeCap.Round)
                }
                val river = Path().apply {
                    moveTo(-20f, size.height * 0.64f)
                    cubicTo(size.width * 0.25f, size.height * 0.48f, size.width * 0.58f, size.height * 0.82f, size.width + 20f, size.height * 0.58f)
                }
                drawPath(river, Color(0xFFBFD5FF), style = Stroke(width = 30f, cap = StrokeCap.Round))
                drawPath(river, Color.White.copy(alpha = 0.75f), style = Stroke(width = 3f, cap = StrokeCap.Round))

                benefits.forEach { benefit ->
                    if (benefit.latitude == null || benefit.longitude == null) return@forEach
                    val point = mapOffset(benefit.latitude, benefit.longitude, size.width, size.height)
                    drawCircle(Color.White, radius = 12f, center = point)
                    drawCircle(categoryColor(benefit.category), radius = 8f, center = point)
                }
                val centerPoint = mapOffset(center.latitude, center.longitude, size.width, size.height)
                drawCircle(PrimaryDark.copy(alpha = 0.16f), radius = 30f, center = centerPoint)
                drawCircle(PrimaryDark, radius = 7f, center = centerPoint)
                currentLocation?.let {
                    val point = mapOffset(it.latitude, it.longitude, size.width, size.height)
                    drawCircle(Color.White, radius = 14f, center = point)
                    drawCircle(Color(0xFF1F6FEB), radius = 9f, center = point)
                }
            }
            Surface(
                modifier = Modifier.align(Alignment.TopStart).padding(14.dp),
                color = Color.White.copy(alpha = 0.94f),
                shape = RoundedCornerShape(12.dp),
            ) { Text("임시 좌표 지도", Modifier.padding(horizontal = 11.dp, vertical = 7.dp), color = Navy, fontWeight = FontWeight.Bold, fontSize = 12.sp) }
            Text(
                "네이버 지도 Client ID 발급 후 실제 지도로 교체",
                modifier = Modifier.align(Alignment.BottomCenter).padding(12.dp)
                    .clip(RoundedCornerShape(50)).background(Navy.copy(alpha = 0.88f))
                    .padding(horizontal = 12.dp, vertical = 7.dp),
                color = Color.White,
                fontSize = 10.sp,
            )
        }
    }
}

@Composable
fun BenefitCard(
    benefit: Benefit,
    distance: Double?,
    favorite: Boolean,
    onClick: () -> Unit,
    onFavorite: () -> Unit,
) {
    Card(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp).clickable(onClick = onClick),
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = Color.White),
        elevation = CardDefaults.cardElevation(1.dp),
    ) {
        Row(Modifier.padding(16.dp), verticalAlignment = Alignment.Top) {
            Box(
                Modifier.size(48.dp).clip(RoundedCornerShape(15.dp)).background(categoryColor(benefit.category).copy(alpha = 0.14f)),
                contentAlignment = Alignment.Center,
            ) { Text(categorySymbol(benefit.category), color = categoryColor(benefit.category), fontSize = 21.sp, fontWeight = FontWeight.Bold) }
            Spacer(Modifier.width(13.dp))
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    StatusPill(benefit.status)
                    if (distance != null) {
                        Spacer(Modifier.width(7.dp))
                        Text(if (distance < 1) "${(distance * 1000).toInt()}m" else "%.1fkm".format(distance), color = Muted, fontSize = 11.sp)
                    }
                }
                Spacer(Modifier.height(7.dp))
                Text(benefit.name, color = Navy, fontWeight = FontWeight.ExtraBold, fontSize = 16.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(benefit.benefitDescription, color = Navy.copy(alpha = 0.78f), fontSize = 13.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Spacer(Modifier.height(7.dp))
                Text("${benefit.district ?: "서울"} · ${benefit.category} · ${benefit.sourceLabel}", color = Muted, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Text(
                if (favorite) "♥" else "♡",
                modifier = Modifier.clickable(onClick = onFavorite).padding(7.dp),
                color = if (favorite) PrimaryDark else Muted,
                fontSize = 23.sp,
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun BenefitDetailSheet(
    benefit: Benefit,
    isFavorite: Boolean,
    onDismiss: () -> Unit,
    onFavorite: () -> Unit,
) {
    val context = LocalContext.current
    val mapOpenFailedMessage = stringResource(R.string.naver_map_open_failed)
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = Color.White) {
        LazyColumn(
            modifier = Modifier.fillMaxWidth(),
            contentPadding = PaddingValues(start = 22.dp, end = 22.dp, bottom = 36.dp),
            verticalArrangement = Arrangement.spacedBy(15.dp),
        ) {
            item {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        Modifier.size(54.dp).clip(RoundedCornerShape(17.dp)).background(categoryColor(benefit.category).copy(alpha = 0.14f)),
                        contentAlignment = Alignment.Center,
                    ) { Text(categorySymbol(benefit.category), fontSize = 25.sp, color = categoryColor(benefit.category)) }
                    Spacer(Modifier.width(14.dp))
                    Column(Modifier.weight(1f)) {
                        StatusPill(benefit.status)
                        Text(benefit.name, color = Navy, fontWeight = FontWeight.Black, fontSize = 22.sp)
                        Text("${benefit.district ?: "서울"} · ${benefit.category}", color = Muted, fontSize = 13.sp)
                    }
                }
            }
            item {
                Surface(color = PrimarySoft, shape = RoundedCornerShape(18.dp)) {
                    Column(Modifier.padding(17.dp)) {
                        Text("받을 수 있는 혜택", color = PrimaryDark, fontWeight = FontWeight.Bold, fontSize = 12.sp)
                        Spacer(Modifier.height(7.dp))
                        Text(benefit.benefitDescription, color = Navy, fontWeight = FontWeight.ExtraBold, fontSize = 18.sp)
                    }
                }
            }
            item {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    DetailRow("주소", benefit.address)
                    DetailRow("적용 대상", benefit.eligibleTarget ?: "정보 없음")
                    DetailRow("이용 조건", benefit.usageCondition ?: "정보 없음")
                    DetailRow("인증 방법", benefit.verificationMethod ?: "방문 전 업소 확인")
                    DetailRow("전화번호", benefit.phone ?: "정보 없음")
                }
            }
            item { HorizontalDivider(color = Line) }
            item {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("정보 신뢰도", color = Navy, fontWeight = FontWeight.ExtraBold, fontSize = 16.sp)
                    DetailRow("출처", benefit.sourceLabel)
                    DetailRow("최근 확인", benefit.lastVerifiedAt?.replace("-", ".") ?: "확인일 정보 없음")
                    Text("혜택은 변경될 수 있으니 결제·예약 전에 업소에 다시 확인해 주세요.", color = Warning, fontSize = 12.sp)
                }
            }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                    OutlinedButton(onClick = onFavorite, modifier = Modifier.weight(1f), shape = RoundedCornerShape(14.dp)) {
                        Text(if (isFavorite) "♥ 찜 해제" else "♡ 찜하기", fontWeight = FontWeight.Bold)
                    }
                    if (!benefit.phone.isNullOrBlank()) {
                        OutlinedButton(
                            onClick = { context.startActivity(Intent(Intent.ACTION_DIAL, Uri.parse("tel:${benefit.phone}"))) },
                            modifier = Modifier.weight(1f), shape = RoundedCornerShape(14.dp),
                        ) { Text("전화하기", fontWeight = FontWeight.Bold) }
                    }
                }
            }
            item {
                Button(
                    onClick = {
                        if (!context.openNaverMap(benefit)) {
                            Toast.makeText(context, mapOpenFailedMessage, Toast.LENGTH_SHORT).show()
                        }
                    },
                    modifier = Modifier.fillMaxWidth().height(50.dp),
                    shape = RoundedCornerShape(14.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = PrimaryBlue),
                ) {
                    Text(
                        stringResource(R.string.open_in_naver_map),
                        color = Navy,
                        fontWeight = FontWeight.ExtraBold,
                    )
                }
            }
            if (!benefit.sourceUrl.isNullOrBlank()) {
                item {
                    Button(
                        onClick = {
                            val url = benefit.sourceUrl.substringBefore(" | ").trim()
                            runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
                        },
                        modifier = Modifier.fillMaxWidth().height(50.dp),
                        shape = RoundedCornerShape(14.dp),
                    ) { Text("출처 원문 확인", fontWeight = FontWeight.Bold) }
                }
            }
        }
    }
}

@Composable
private fun StatusPill(status: BenefitStatus) {
    val color = when (status) {
        BenefitStatus.ACTIVE -> Success
        BenefitStatus.NEEDS_VERIFICATION -> Warning
        BenefitStatus.ENDED -> Danger
    }
    val label = when (status) {
        BenefitStatus.ACTIVE -> "● 이용 가능"
        BenefitStatus.NEEDS_VERIFICATION -> "● 확인 필요"
        BenefitStatus.ENDED -> "● 종료"
    }
    Text(
        label,
        modifier = Modifier.clip(RoundedCornerShape(50)).background(color.copy(alpha = 0.11f))
            .padding(horizontal = 9.dp, vertical = 4.dp),
        color = color,
        fontWeight = FontWeight.Bold,
        fontSize = 10.sp,
    )
}

@Composable
private fun DetailRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth()) {
        Text(label, Modifier.width(78.dp), color = Muted, fontSize = 13.sp)
        Text(value, Modifier.weight(1f), color = Navy, fontSize = 13.sp, fontWeight = FontWeight.Medium)
    }
}

@Composable
fun EmptyCard(title: String, description: String) {
    Card(
        Modifier.fillMaxWidth().padding(horizontal = 20.dp),
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = Color.White),
    ) {
        Column(Modifier.fillMaxWidth().padding(28.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text("◎", color = PrimaryBlue, fontSize = 30.sp)
            Text(title, color = Navy, fontWeight = FontWeight.ExtraBold, fontSize = 17.sp)
            Text(description, color = Muted, fontSize = 13.sp)
        }
    }
}

private fun categorySymbol(category: String) = when (category) {
    "음식" -> "●"
    "카페" -> "☕"
    "미용·뷰티" -> "✂"
    "숙박" -> "▣"
    "병원" -> "+"
    "문화·여가" -> "★"
    else -> "✦"
}

private fun categoryColor(category: String) = when (category) {
    "음식" -> Color(0xFFF16D5B)
    "카페" -> Color(0xFFA7653A)
    "미용·뷰티" -> Color(0xFF8B62C7)
    "숙박" -> Color(0xFF2879B9)
    "병원" -> Color(0xFF2F9E66)
    else -> PrimaryDark
}

private fun mapOffset(latitude: Double, longitude: Double, width: Float, height: Float): Offset {
    val minLat = 37.42
    val maxLat = 37.70
    val minLon = 126.74
    val maxLon = 127.22
    val x = ((longitude - minLon) / (maxLon - minLon)).coerceIn(0.02, 0.98).toFloat() * width
    val y = (1 - ((latitude - minLat) / (maxLat - minLat)).coerceIn(0.04, 0.96)).toFloat() * height
    return Offset(x, y)
}

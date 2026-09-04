package com.example.milipercent.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.material3.FilterChip
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import com.example.milipercent.model.BenefitDistrict
import com.example.milipercent.model.BenefitStatus

@Composable
fun MilitaryBenefitApp(
    state: MiliSpotUiState,
    @Suppress("UNUSED_PARAMETER") navController: NavHostController,
    onNavigate: (AppDestination) -> Unit,
    onSearchTextChanged: (String) -> Unit,
    onSearch: () -> Unit,
    onPresetSelected: (String) -> Unit,
    onCategorySelected: (String) -> Unit,
    onDistrictSelected: (BenefitDistrict) -> Unit,
    onBenefitSelected: (String) -> Unit,
    onFavorite: (String) -> Unit,
    onRefresh: () -> Unit,
    onCurrentLocation: () -> Unit,
    onMessageShown: () -> Unit,
) {
    val snackbarHost = remember { SnackbarHostState() }
    LaunchedEffect(state.transientMessage) {
        state.transientMessage?.let { message ->
            snackbarHost.showSnackbar(message)
            onMessageShown()
        }
    }

    Scaffold(
        containerColor = Canvas,
        topBar = { AppTopBar(state, onNavigate) },
        bottomBar = { AppBottomBar(state.destination, onNavigate) },
        snackbarHost = { SnackbarHost(snackbarHost) },
    ) { padding ->
        when (state.destination) {
            AppDestination.DISCOVER -> DiscoverScreen(
                state = state,
                onSearchTextChanged = onSearchTextChanged,
                onSearch = onSearch,
                onPresetSelected = onPresetSelected,
                onCategorySelected = onCategorySelected,
                onDistrictSelected = onDistrictSelected,
                onBenefitSelected = onBenefitSelected,
                onFavorite = onFavorite,
                onRefresh = onRefresh,
                onCurrentLocation = onCurrentLocation,
                modifier = Modifier.padding(padding),
            )
            AppDestination.SAVED -> PlaceholderScreen("찜한 혜택", "로그인 후 저장한 혜택을 여기에서 확인할 수 있어요.", Modifier.padding(padding))
            AppDestination.ACCOUNT -> PlaceholderScreen("MY", "로그인과 회원가입 화면을 준비 중입니다.", Modifier.padding(padding))
            AppDestination.ADMIN -> PlaceholderScreen("관리", "관리자 혜택 관리 화면을 준비 중입니다.", Modifier.padding(padding))
        }
    }
}

@Composable
private fun AppTopBar(state: MiliSpotUiState, onNavigate: (AppDestination) -> Unit) {
    Surface(color = androidx.compose.ui.graphics.Color.White, shadowElevation = 2.dp) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 11.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                Modifier.size(42.dp).background(PrimaryBlue, RoundedCornerShape(14.dp)),
                contentAlignment = Alignment.Center,
            ) { Text("M", fontWeight = FontWeight.Black, color = Navy, fontSize = 20.sp) }
            Spacer(Modifier.width(11.dp))
            Column(Modifier.weight(1f)) {
                Text("군 혜택 지도", fontWeight = FontWeight.ExtraBold, fontSize = 17.sp)
                Text("서울 군 장병 혜택", color = Muted, fontSize = 11.sp)
            }
            if (state.user?.isAdmin == true) {
                Text(
                    "관리",
                    modifier = Modifier
                        .background(PrimarySoft, RoundedCornerShape(50))
                        .clickable { onNavigate(AppDestination.ADMIN) }
                        .padding(horizontal = 13.dp, vertical = 8.dp),
                    color = PrimaryDark,
                    fontWeight = FontWeight.Bold,
                )
            }
        }
    }
}

@Composable
private fun AppBottomBar(destination: AppDestination, onNavigate: (AppDestination) -> Unit) {
    val items = listOf(
        Triple(AppDestination.DISCOVER, "⌂", "탐색"),
        Triple(AppDestination.SAVED, "♡", "찜"),
        Triple(AppDestination.ACCOUNT, "●", "MY"),
    )
    NavigationBar(containerColor = androidx.compose.ui.graphics.Color(0xFF292A2D), tonalElevation = 0.dp) {
        items.forEach { (itemDestination, icon, label) ->
            NavigationBarItem(
                selected = destination == itemDestination,
                onClick = { onNavigate(itemDestination) },
                icon = { Text(icon, fontSize = 22.sp, fontWeight = FontWeight.Bold) },
                label = { Text(label) },
                colors = NavigationBarItemDefaults.colors(
                    selectedIconColor = androidx.compose.ui.graphics.Color.White,
                    selectedTextColor = androidx.compose.ui.graphics.Color.White,
                    indicatorColor = PrimaryDark,
                    unselectedIconColor = androidx.compose.ui.graphics.Color(0xFF8A8B90),
                    unselectedTextColor = androidx.compose.ui.graphics.Color(0xFF8A8B90),
                ),
            )
        }
    }
}

@Composable
private fun DiscoverScreen(
    state: MiliSpotUiState,
    onSearchTextChanged: (String) -> Unit,
    onSearch: () -> Unit,
    onPresetSelected: (String) -> Unit,
    onCategorySelected: (String) -> Unit,
    onDistrictSelected: (BenefitDistrict) -> Unit,
    onBenefitSelected: (String) -> Unit,
    onFavorite: (String) -> Unit,
    onRefresh: () -> Unit,
    onCurrentLocation: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier.fillMaxSize()) {
        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .height(176.dp)
                .testTag("map_slot"),
            color = PrimarySoft,
        ) {
            Box(contentAlignment = Alignment.Center) {
                Text("지도 불러오는 중", color = PrimaryDark, fontWeight = FontWeight.Bold)
            }
        }
        Surface(
            modifier = Modifier.fillMaxWidth(),
            color = androidx.compose.ui.graphics.Color.White,
            shadowElevation = 4.dp,
        ) {
            Column(Modifier.padding(horizontal = 14.dp, vertical = 10.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    OutlinedTextField(
                        value = state.searchText,
                        onValueChange = onSearchTextChanged,
                        modifier = Modifier.weight(1f).testTag("benefit_search"),
                        placeholder = { Text("홍대·성수·강남역·파주 검색", fontSize = 13.sp) },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                        keyboardActions = KeyboardActions(onSearch = { onSearch() }),
                    )
                    Spacer(Modifier.width(8.dp))
                    Button(onClick = onSearch) { Text("검색", fontWeight = FontWeight.Bold) }
                }
                FilterRow(
                    label = "카테고리",
                    modifier = Modifier.testTag("category_filter"),
                    values = listOf("전체") + state.benefits.map { it.category }.distinct().sorted(),
                    selected = state.selectedCategory,
                    onSelected = onCategorySelected,
                )
                DistrictRow(state.selectedDistrict, onDistrictSelected)
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(state.locationLabel, color = Navy, fontWeight = FontWeight.ExtraBold, fontSize = 12.sp)
                    Spacer(Modifier.weight(1f))
                    Text(
                        if (state.isRefreshing) "나라사랑가게 동기화 중…" else state.lastSyncLabel,
                        color = if (state.refreshFailed) Danger else Muted,
                        fontSize = 10.sp,
                    )
                }
            }
        }
        LazyRow(
            contentPadding = PaddingValues(horizontal = 14.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            items(listOf("홍대", "성수", "잠실", "강남역", "신촌", "건대", "서울역")) { preset ->
                FilterChip(
                    selected = state.locationLabel == preset,
                    onClick = { onPresetSelected(preset) },
                    label = { Text(preset) },
                )
            }
        }
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 18.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Text("내 주변 혜택", color = Navy, fontWeight = FontWeight.Black, fontSize = 17.sp)
                Text("${state.visibleBenefits.size}곳", color = Muted, fontSize = 11.sp)
            }
            Text(
                "새로고침",
                Modifier.clickable(onClick = onRefresh).padding(8.dp),
                color = PrimaryDark,
                fontWeight = FontWeight.Bold,
                fontSize = 12.sp,
            )
            Button(
                onClick = onCurrentLocation,
                modifier = Modifier.size(48.dp).testTag("current_location"),
                shape = CircleShape,
                contentPadding = PaddingValues(0.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Navy),
            ) { Text("◎", color = androidx.compose.ui.graphics.Color.White, fontSize = 20.sp) }
        }
        if (state.isLoading) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text("혜택을 불러오는 중…") }
        } else if (state.visibleBenefits.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text("검색 결과가 없어요. 지역이나 카테고리를 바꿔보세요.", color = Muted)
            }
        } else {
            LazyRow(
                contentPadding = PaddingValues(18.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                items(state.visibleBenefits, key = { it.benefit.id }) { item ->
                    BenefitCard(item, item.benefit.id in state.favoriteIds, onBenefitSelected, onFavorite)
                }
            }
        }
    }
}

@Composable
private fun FilterRow(
    label: String,
    values: List<String>,
    selected: String,
    onSelected: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyRow(modifier = modifier, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        items(values) { value ->
            FilterChip(selected = value == selected, onClick = { onSelected(value) }, label = { Text("$label $value", fontSize = 11.sp) })
        }
    }
}

@Composable
private fun DistrictRow(selected: BenefitDistrict, onSelected: (BenefitDistrict) -> Unit) {
    LazyRow(
        modifier = Modifier.testTag("district_filter"),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        items(BenefitDistrict.entries.toList()) { district ->
            FilterChip(
                selected = district == selected,
                onClick = { onSelected(district) },
                label = { Text(district.displayName, fontSize = 11.sp) },
            )
        }
    }
}

@Composable
private fun BenefitCard(
    item: BenefitListItem,
    favorite: Boolean,
    onBenefitSelected: (String) -> Unit,
    onFavorite: (String) -> Unit,
) {
    val benefit = item.benefit
    Card(
        modifier = Modifier
            .width(270.dp)
            .testTag("benefit_card_${benefit.id}")
            .clickable { onBenefitSelected(benefit.id) },
        colors = CardDefaults.cardColors(containerColor = androidx.compose.ui.graphics.Color.White),
        shape = RoundedCornerShape(18.dp),
    ) {
        Row(Modifier.padding(16.dp), verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f)) {
                Text(benefit.name, color = Navy, fontWeight = FontWeight.ExtraBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(benefit.benefitDescription, color = Muted, fontSize = 12.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Spacer(Modifier.height(7.dp))
                Text("${benefit.district ?: "서울"} · ${benefit.category}", color = Muted, fontSize = 11.sp)
                item.distanceKm?.let { distance ->
                    Text(if (distance < 1) "${(distance * 1000).toInt()}m" else "%.1fkm".format(distance), color = PrimaryDark, fontSize = 11.sp)
                }
            }
            Text(
                if (favorite) "♥" else "♡",
                modifier = Modifier.clickable { onFavorite(benefit.id) }.padding(start = 8.dp),
                color = if (favorite) PrimaryDark else Muted,
                fontSize = 22.sp,
            )
        }
    }
}

@Composable
private fun PlaceholderScreen(title: String, description: String, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(title, color = Navy, fontWeight = FontWeight.ExtraBold, fontSize = 20.sp)
            Text(description, color = Muted)
        }
    }
}

internal fun statusLabel(status: BenefitStatus): String = when (status) {
    BenefitStatus.ACTIVE -> "이용 가능"
    BenefitStatus.NEEDS_VERIFICATION -> "확인 필요"
    BenefitStatus.ENDED -> "종료"
}

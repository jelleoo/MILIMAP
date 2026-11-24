package com.example.milipercent.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
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
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import com.example.milipercent.data.admin.AdminBenefitInput
import com.example.milipercent.model.BenefitDistrict
import com.example.milipercent.model.BenefitStatus
import com.example.milipercent.model.GeoBounds
import com.example.milipercent.model.GeoPoint
import com.example.milipercent.ui.map.categoryAccentColorInt

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
    onRegister: suspend (String, String, String) -> Result<com.example.milipercent.model.LocalUser> = { _, _, _ -> Result.failure(UnsupportedOperationException()) },
    onLogin: suspend (String, String) -> Result<com.example.milipercent.model.LocalUser> = { _, _ -> Result.failure(UnsupportedOperationException()) },
    onLogout: () -> Unit = {},
    onAdminSave: (AdminBenefitInput, String?) -> Unit = { _, _ -> },
    onAdminEnd: (String) -> Unit = {},
    onAdminDelete: (String) -> Unit = {},
    onClearSearch: () -> Unit = {},
    onMapCameraIdle: (GeoPoint, GeoBounds, Boolean, Double) -> Unit = { _, _, _, _ -> },
    onCameraRequestApplied: (Long) -> Unit = {},
    onSearchInMapBounds: () -> Unit = {},
    onMapBenefitSelected: (String?) -> Unit = {},
) {
    val snackbarHost = remember { SnackbarHostState() }
    BackHandler(enabled = state.destination != AppDestination.DISCOVER) {
        onNavigate(AppDestination.DISCOVER)
    }
    LaunchedEffect(state.transientMessage) {
        state.transientMessage?.let { message ->
            snackbarHost.showSnackbar(message)
            onMessageShown()
        }
    }

    Scaffold(
        containerColor = Canvas,
        topBar = {
            if (state.destination != AppDestination.DISCOVER) {
                AppTopBar(state, onNavigate)
            }
        },
        bottomBar = { AppBottomBar(state.destination, onNavigate) },
        snackbarHost = { SnackbarHost(snackbarHost) },
    ) { padding ->
        when (state.destination) {
            AppDestination.DISCOVER -> DiscoverScreen(
                state = state,
                onNavigate = onNavigate,
                onSearchTextChanged = onSearchTextChanged,
                onSearch = onSearch,
                onClearSearch = onClearSearch,
                onPresetSelected = onPresetSelected,
                onCategorySelected = onCategorySelected,
                onDistrictSelected = onDistrictSelected,
                onBenefitSelected = onBenefitSelected,
                onMapBenefitSelected = onMapBenefitSelected,
                onMapCameraIdle = onMapCameraIdle,
                onCameraRequestApplied = onCameraRequestApplied,
                onSearchInMapBounds = onSearchInMapBounds,
                onFavorite = onFavorite,
                onRefresh = onRefresh,
                onCurrentLocation = onCurrentLocation,
                modifier = Modifier.padding(padding),
            )
            AppDestination.SAVED -> SavedScreen(state.savedBenefits, state.favoriteIds, onBenefitSelected, onFavorite, Modifier.padding(padding))
            AppDestination.ACCOUNT -> AccountScreen(state.user, onRegister, onLogin, onLogout, Modifier.padding(padding))
            AppDestination.ADMIN -> AdminScreen(state.user, state.adminBenefits, onAdminSave, onAdminEnd, onAdminDelete, Modifier.padding(padding))
        }
    }
}

@Composable
private fun AppTopBar(state: MiliSpotUiState, onNavigate: (AppDestination) -> Unit) {
    Surface(color = Color.White, shadowElevation = 2.dp) {
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
                Text("수도권 군 장병 혜택", color = Muted, fontSize = 11.sp)
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
    NavigationBar(containerColor = Color(0xFF292A2D), tonalElevation = 0.dp) {
        items.forEach { (itemDestination, icon, label) ->
            NavigationBarItem(
                selected = destination == itemDestination,
                onClick = { onNavigate(itemDestination) },
                icon = { Text(icon, fontSize = 22.sp, fontWeight = FontWeight.Bold) },
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
private fun DiscoverScreen(
    state: MiliSpotUiState,
    onNavigate: (AppDestination) -> Unit,
    onSearchTextChanged: (String) -> Unit,
    onSearch: () -> Unit,
    onClearSearch: () -> Unit,
    onPresetSelected: (String) -> Unit,
    onCategorySelected: (String) -> Unit,
    onDistrictSelected: (BenefitDistrict) -> Unit,
    onBenefitSelected: (String) -> Unit,
    onMapBenefitSelected: (String?) -> Unit,
    onMapCameraIdle: (GeoPoint, GeoBounds, Boolean, Double) -> Unit,
    onCameraRequestApplied: (Long) -> Unit,
    onSearchInMapBounds: () -> Unit,
    onFavorite: (String) -> Unit,
    onRefresh: () -> Unit,
    onCurrentLocation: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var isSheetExpanded by remember { mutableStateOf(false) }
    var showFilters by remember { mutableStateOf(false) }
    val focusManager = LocalFocusManager.current
    val categories = remember(state.benefits) { orderedCategories(state.benefits) }

    val handleSearch = {
        focusManager.clearFocus()
        showFilters = false
        onSearch()
    }
    val handleClearSearch = {
        focusManager.clearFocus()
        onClearSearch()
    }
    val handleCategorySelected: (String) -> Unit = { category ->
        focusManager.clearFocus()
        showFilters = false
        onCategorySelected(category)
    }
    val handlePresetSelected: (String) -> Unit = { preset ->
        focusManager.clearFocus()
        showFilters = false
        onPresetSelected(preset)
    }
    val handleDistrictSelected: (BenefitDistrict) -> Unit = { district ->
        focusManager.clearFocus()
        showFilters = false
        onDistrictSelected(district)
    }
    val handleCurrentLocation = {
        focusManager.clearFocus()
        showFilters = false
        isSheetExpanded = false
        onCurrentLocation()
    }
    val handleSearchInMapBounds = {
        focusManager.clearFocus()
        showFilters = false
        onSearchInMapBounds()
    }

    Box(modifier.fillMaxSize()) {
        BenefitMap(
            benefits = state.mapBenefits,
            center = state.center,
            currentLocation = state.currentLocation,
            cameraRequestId = state.cameraRequestId,
            onSelect = { id -> onMapBenefitSelected(id) },
            modifier = Modifier.fillMaxSize().testTag("map_slot"),
            cameraTarget = state.cameraTarget,
            appliedCameraRequestId = state.appliedCameraRequestId,
            lastCameraSnapshot = state.lastCameraSnapshot,
            selectedBenefitId = state.selectedMapBenefitId,
            onMapBlankClick = {
                focusManager.clearFocus()
                onMapBenefitSelected(null)
            },
            onCameraRequestApplied = onCameraRequestApplied,
            onCameraIdle = onMapCameraIdle,
        )

        Column(
            modifier = Modifier
                .align(Alignment.TopCenter)
                .fillMaxWidth()
                .padding(top = 10.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            FloatingSearchBar(
                searchText = state.searchText,
                hasActiveQuery = state.searchText.isNotEmpty() || state.activeSearch.isNotEmpty(),
                isAdmin = state.user?.isAdmin == true,
                onSearchTextChanged = onSearchTextChanged,
                onSearch = handleSearch,
                onClearSearch = handleClearSearch,
                onAdminClick = { onNavigate(AppDestination.ADMIN) },
            )
            FloatingCategoryChipRow(
                categories = categories,
                selectedCategory = state.selectedCategory,
                showMapMarkers = state.showMapMarkers,
                onCategorySelected = handleCategorySelected,
            )
            if (state.isSearchInMapBoundsAvailable) {
                Spacer(Modifier.height(8.dp))
                Surface(
                    modifier = Modifier
                        .testTag("search_in_map_bounds")
                        .clickable(onClick = handleSearchInMapBounds),
                    shape = RoundedCornerShape(50),
                    color = Color.White,
                    shadowElevation = 5.dp,
                    border = BorderStroke(1.dp, PrimaryBlue),
                ) {
                    Text(
                        "↻ 현 지도에서 검색",
                        modifier = Modifier.padding(horizontal = 14.dp, vertical = 7.dp),
                        color = PrimaryDark,
                        fontWeight = FontWeight.Bold,
                        fontSize = 12.sp,
                    )
                }
            }
        }

        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth(),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 14.dp, vertical = 10.dp),
                verticalAlignment = Alignment.Bottom,
            ) {
                if (state.isRefreshing || state.refreshFailed) {
                    Surface(
                        color = Color.White.copy(alpha = 0.94f),
                        shape = RoundedCornerShape(50),
                        shadowElevation = 4.dp,
                    ) {
                        Text(
                            if (state.isRefreshing) "동기화 중…" else "내장 DB 사용 중",
                            modifier = Modifier.padding(horizontal = 11.dp, vertical = 6.dp),
                            color = if (state.refreshFailed) Danger else Navy,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                }
                Spacer(Modifier.weight(1f))
                Surface(
                    modifier = Modifier
                        .size(46.dp)
                        .testTag("current_location")
                        .clickable(onClick = handleCurrentLocation),
                    shape = CircleShape,
                    color = Color.White,
                    shadowElevation = 6.dp,
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Text(
                            "◎",
                            color = if (state.isLocationFocusPending) PrimaryDark else Navy,
                            fontSize = 20.sp,
                            fontWeight = FontWeight.Bold,
                        )
                    }
                }
            }

            Surface(
                modifier = Modifier.fillMaxWidth(),
                color = Color.White,
                shape = RoundedCornerShape(topStart = 22.dp, topEnd = 22.dp),
                shadowElevation = 10.dp,
            ) {
                val selectedItem = state.selectedMapBenefit
                if (selectedItem != null) {
                    SelectedMapBenefitPreviewCard(
                        item = selectedItem,
                        favorite = selectedItem.benefit.id in state.favoriteIds,
                        onClose = { onMapBenefitSelected(null) },
                        onOpenDetail = { onBenefitSelected(selectedItem.benefit.id) },
                        onFavorite = { onFavorite(selectedItem.benefit.id) },
                    )
                } else {
                    DiscoverBottomSheetContent(
                        state = state,
                        isSheetExpanded = isSheetExpanded,
                        showFilters = showFilters,
                        onToggleExpanded = {
                            isSheetExpanded = !isSheetExpanded
                            if (isSheetExpanded) showFilters = false
                        },
                        onToggleFilters = {
                            showFilters = !showFilters
                            if (showFilters) isSheetExpanded = false
                        },
                        onPresetSelected = handlePresetSelected,
                        onDistrictSelected = handleDistrictSelected,
                        onBenefitSelected = onBenefitSelected,
                        onFavorite = onFavorite,
                        onRefresh = onRefresh,
                    )
                }
            }
        }
    }
}

@Composable
private fun FloatingSearchBar(
    searchText: String,
    hasActiveQuery: Boolean,
    isAdmin: Boolean,
    onSearchTextChanged: (String) -> Unit,
    onSearch: () -> Unit,
    onClearSearch: () -> Unit,
    onAdminClick: () -> Unit,
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp),
        color = Color.White,
        shape = RoundedCornerShape(16.dp),
        shadowElevation = 6.dp,
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 7.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                Modifier.size(32.dp).background(PrimaryBlue, RoundedCornerShape(10.dp)),
                contentAlignment = Alignment.Center,
            ) { Text("M", fontWeight = FontWeight.Black, color = Navy, fontSize = 16.sp) }
            Spacer(Modifier.width(10.dp))
            Box(
                modifier = Modifier.weight(1f),
                contentAlignment = Alignment.CenterStart,
            ) {
                if (searchText.isEmpty()) {
                    Text(
                        "장소·역·혜택 업소 검색",
                        color = Muted,
                        fontSize = 14.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                BasicTextField(
                    value = searchText,
                    onValueChange = onSearchTextChanged,
                    modifier = Modifier.fillMaxWidth().testTag("benefit_search"),
                    singleLine = true,
                    textStyle = TextStyle(
                        color = Navy,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Medium,
                    ),
                    cursorBrush = SolidColor(PrimaryDark),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                    keyboardActions = KeyboardActions(onSearch = { onSearch() }),
                )
            }
            if (hasActiveQuery) {
                Text(
                    "✕",
                    modifier = Modifier
                        .testTag("clear_search")
                        .clickable(onClick = onClearSearch)
                        .padding(horizontal = 8.dp, vertical = 4.dp),
                    color = Muted,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Bold,
                )
            }
            Surface(
                modifier = Modifier.clickable(onClick = onSearch),
                color = PrimaryDark,
                shape = RoundedCornerShape(10.dp),
            ) {
                Text(
                    "검색",
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                    color = Color.White,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                )
            }
            if (isAdmin) {
                Spacer(Modifier.width(6.dp))
                Surface(
                    modifier = Modifier.clickable(onClick = onAdminClick),
                    color = PrimarySoft,
                    shape = RoundedCornerShape(10.dp),
                ) {
                    Text(
                        "관리",
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
                        color = PrimaryDark,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }
        }
    }
}

@Composable
private fun FloatingCategoryChipRow(
    categories: List<String>,
    selectedCategory: String,
    showMapMarkers: Boolean,
    onCategorySelected: (String) -> Unit,
) {
    LazyRow(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 8.dp)
            .testTag("category_filter"),
        contentPadding = PaddingValues(horizontal = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        items(categories, key = { it }) { category ->
            val isHighlighted = showMapMarkers && selectedCategory == category
            Surface(
                modifier = Modifier.clickable { onCategorySelected(category) },
                shape = RoundedCornerShape(50),
                color = if (isHighlighted) PrimaryDark else Color.White,
                shadowElevation = 3.dp,
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 7.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(5.dp),
                ) {
                    if (!isHighlighted && category != "전체") {
                        Box(
                            Modifier
                                .size(8.dp)
                                .background(Color(categoryAccentColorInt(category)), CircleShape),
                        )
                    }
                    Text(
                        category,
                        color = if (isHighlighted) Color.White else Navy,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            }
        }
    }
}

@Composable
private fun DiscoverBottomSheetContent(
    state: MiliSpotUiState,
    isSheetExpanded: Boolean,
    showFilters: Boolean,
    onToggleExpanded: () -> Unit,
    onToggleFilters: () -> Unit,
    onPresetSelected: (String) -> Unit,
    onDistrictSelected: (BenefitDistrict) -> Unit,
    onBenefitSelected: (String) -> Unit,
    onFavorite: (String) -> Unit,
    onRefresh: () -> Unit,
) {
    Column(Modifier.fillMaxWidth()) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(onClick = onToggleExpanded)
                .padding(top = 8.dp, bottom = 4.dp),
            contentAlignment = Alignment.Center,
        ) {
            Box(Modifier.size(width = 36.dp, height = 4.dp).background(Line, RoundedCornerShape(50)))
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                val title = if (!state.showMapMarkers) {
                    "주변 혜택 · ${state.visibleBenefits.size}곳"
                } else {
                    val categoryLabel = if (state.selectedCategory == "전체") "전체" else state.selectedCategory
                    "${state.locationLabel} · $categoryLabel (${state.visibleBenefits.size}곳)"
                }
                val subtitle = if (!state.showMapMarkers) {
                    "카테고리 칩이나 검색으로 지도 핀을 띄워보세요"
                } else {
                    state.lastSyncLabel
                }
                Text(title, color = Navy, fontWeight = FontWeight.ExtraBold, fontSize = 15.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(subtitle, color = Muted, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Spacer(Modifier.width(8.dp))
            SheetActionPill(
                label = "지역",
                active = showFilters || state.selectedDistrict != BenefitDistrict.ALL,
                modifier = Modifier.testTag("toggle_filters"),
                onClick = onToggleFilters,
            )
            Spacer(Modifier.width(6.dp))
            SheetActionPill(
                label = if (isSheetExpanded) "접기" else "목록",
                active = isSheetExpanded,
                modifier = Modifier.testTag("toggle_sheet"),
                onClick = onToggleExpanded,
            )
            Spacer(Modifier.width(6.dp))
            Surface(
                modifier = Modifier.clickable(onClick = onRefresh),
                shape = RoundedCornerShape(50),
                color = Canvas,
            ) {
                Text(
                    "↻",
                    modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp),
                    color = PrimaryDark,
                    fontWeight = FontWeight.Bold,
                    fontSize = 12.sp,
                )
            }
        }

        if (showFilters) {
            Column(Modifier.padding(top = 6.dp)) {
                Text(
                    "경기 · 인천 주요 지역",
                    modifier = Modifier.padding(horizontal = 14.dp, vertical = 2.dp),
                    color = Muted,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold,
                )
                LazyRow(
                    contentPadding = PaddingValues(horizontal = 14.dp, vertical = 4.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    items(listOf("파주", "동두천", "양주", "의정부", "수원", "성남", "고양", "용인", "부천", "안양", "인천", "송도", "부평")) { preset ->
                        FilterChip(
                            selected = state.locationLabel == preset,
                            onClick = { onPresetSelected(preset) },
                            label = { Text(preset, fontSize = 11.sp) },
                        )
                    }
                }
                Text(
                    "서울 자치구",
                    modifier = Modifier.padding(horizontal = 14.dp, vertical = 2.dp),
                    color = Muted,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold,
                )
                DistrictRow(state.selectedDistrict, onDistrictSelected)
                Spacer(Modifier.height(6.dp))
                LocationVerificationSummary(
                    benefits = state.visibleBenefits,
                    onBenefitSelected = onBenefitSelected,
                )
            }
        }

        if (state.isLoading) {
            Box(Modifier.fillMaxWidth().height(96.dp), contentAlignment = Alignment.Center) {
                Text("혜택을 불러오는 중…", color = Muted)
            }
        } else if (state.visibleBenefits.isEmpty()) {
            Box(Modifier.fillMaxWidth().padding(20.dp), contentAlignment = Alignment.Center) {
                Text("조건에 맞는 혜택이 없어요. 지도를 옮기거나 필터를 바꿔보세요.", color = Muted, fontSize = 12.sp)
            }
        } else if (isSheetExpanded) {
            LazyColumn(
                modifier = Modifier.fillMaxWidth().heightIn(max = 380.dp),
                contentPadding = PaddingValues(horizontal = 14.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(state.visibleBenefits, key = { it.benefit.id }) { item ->
                    BenefitCard(
                        item = item,
                        favorite = item.benefit.id in state.favoriteIds,
                        onBenefitSelected = onBenefitSelected,
                        onFavorite = onFavorite,
                        fillWidth = true,
                    )
                }
                if (!showFilters) {
                    item(key = "location_verification_footer") {
                        LocationVerificationSummary(
                            benefits = state.visibleBenefits,
                            onBenefitSelected = onBenefitSelected,
                        )
                    }
                }
            }
        } else {
            LazyRow(
                contentPadding = PaddingValues(horizontal = 14.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                items(state.visibleBenefits, key = { it.benefit.id }) { item ->
                    BenefitCard(
                        item = item,
                        favorite = item.benefit.id in state.favoriteIds,
                        onBenefitSelected = onBenefitSelected,
                        onFavorite = onFavorite,
                    )
                }
            }
        }
    }
}

@Composable
private fun SheetActionPill(
    label: String,
    active: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    Surface(
        modifier = modifier.clickable(onClick = onClick),
        shape = RoundedCornerShape(50),
        color = if (active) PrimarySoft else Canvas,
    ) {
        Text(
            label,
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp),
            color = if (active) PrimaryDark else Navy,
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold,
        )
    }
}

@Composable
private fun SelectedMapBenefitPreviewCard(
    item: BenefitListItem,
    favorite: Boolean,
    onClose: () -> Unit,
    onOpenDetail: () -> Unit,
    onFavorite: () -> Unit,
) {
    val benefit = item.benefit
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .testTag("benefit_card_${benefit.id}")
            .clickable(onClick = onOpenDetail)
            .padding(16.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Surface(color = PrimarySoft, shape = RoundedCornerShape(50)) {
                Row(
                    modifier = Modifier.padding(horizontal = 9.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(5.dp),
                ) {
                    Box(
                        Modifier
                            .size(7.dp)
                            .background(Color(categoryAccentColorInt(benefit.category)), CircleShape),
                    )
                    Text(benefit.category, color = PrimaryDark, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                }
            }
            item.distanceKm?.let { distance ->
                Spacer(Modifier.width(8.dp))
                Text(
                    if (distance < 1) "${(distance * 1000).toInt()}m" else "%.1fkm".format(distance),
                    color = PrimaryDark,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold,
                )
            }
            Spacer(Modifier.weight(1f))
            Text(
                if (favorite) "♥" else "♡",
                modifier = Modifier.clickable(onClick = onFavorite).padding(horizontal = 6.dp),
                color = if (favorite) PrimaryDark else Muted,
                fontSize = 20.sp,
            )
            Text(
                "✕",
                modifier = Modifier.clickable(onClick = onClose).padding(horizontal = 6.dp),
                color = Muted,
                fontSize = 15.sp,
                fontWeight = FontWeight.Bold,
            )
        }
        Spacer(Modifier.height(8.dp))
        Text(benefit.name, color = Navy, fontWeight = FontWeight.ExtraBold, fontSize = 16.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Spacer(Modifier.height(4.dp))
        Text(benefit.benefitDescription, color = Muted, fontSize = 12.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
        Spacer(Modifier.height(8.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                benefit.address,
                modifier = Modifier.weight(1f),
                color = Muted,
                fontSize = 11.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.width(10.dp))
            Button(
                onClick = onOpenDetail,
                shape = RoundedCornerShape(10.dp),
                contentPadding = PaddingValues(horizontal = 14.dp, vertical = 6.dp),
                colors = ButtonDefaults.buttonColors(containerColor = PrimaryDark),
            ) {
                Text("상세 보기", fontSize = 12.sp, fontWeight = FontWeight.Bold)
            }
        }
    }
}

@Composable
private fun DistrictRow(selected: BenefitDistrict, onSelected: (BenefitDistrict) -> Unit) {
    LazyRow(
        modifier = Modifier.testTag("district_filter"),
        contentPadding = PaddingValues(horizontal = 14.dp),
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
    fillWidth: Boolean = false,
) {
    val benefit = item.benefit
    Card(
        modifier = (if (fillWidth) Modifier.fillMaxWidth() else Modifier.width(248.dp))
            .testTag("benefit_card_${benefit.id}")
            .clickable { onBenefitSelected(benefit.id) },
        colors = CardDefaults.cardColors(containerColor = Canvas),
        shape = RoundedCornerShape(16.dp),
    ) {
        Row(Modifier.padding(14.dp), verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f)) {
                Text(benefit.name, color = Navy, fontWeight = FontWeight.ExtraBold, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Spacer(Modifier.height(2.dp))
                Text(benefit.benefitDescription, color = Muted, fontSize = 12.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Spacer(Modifier.height(6.dp))
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("${benefit.district ?: "수도권"} · ${benefit.category}", color = Muted, fontSize = 11.sp)
                    item.distanceKm?.let { distance ->
                        Text(if (distance < 1) "${(distance * 1000).toInt()}m" else "%.1fkm".format(distance), color = PrimaryDark, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
                    }
                }
                if (benefit.latitude == null || benefit.longitude == null) {
                    Text("위치 확인 필요 · 지도 핀 미표시", color = Warning, fontSize = 11.sp)
                }
            }
            Text(
                if (favorite) "♥" else "♡",
                modifier = Modifier.clickable { onFavorite(benefit.id) }.padding(start = 8.dp),
                color = if (favorite) PrimaryDark else Muted,
                fontSize = 20.sp,
            )
        }
    }
}

@Composable
private fun LocationVerificationSummary(
    benefits: List<BenefitListItem>,
    onBenefitSelected: (String) -> Unit,
) {
    val unlocatedBenefits = benefits.filter { item ->
        item.benefit.latitude == null || item.benefit.longitude == null
    }
    if (unlocatedBenefits.isEmpty()) return

    Surface(
        modifier = Modifier.fillMaxWidth().testTag("location_verification_summary"),
        color = PrimarySoft,
    ) {
        Column(Modifier.padding(horizontal = 14.dp, vertical = 9.dp)) {
            Text(
                "위치 확인 필요 ${unlocatedBenefits.size}곳",
                color = Navy,
                fontWeight = FontWeight.Bold,
                fontSize = 12.sp,
            )
            Text(
                "정확한 좌표가 없어 지도 핀에는 표시하지 않습니다. 업소명과 주소를 직접 확인해 주세요.",
                color = Muted,
                fontSize = 11.sp,
            )
            LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                items(unlocatedBenefits.take(8), key = { it.benefit.id }) { item ->
                    Text(
                        item.benefit.name,
                        modifier = Modifier
                            .testTag("location_verification_${item.benefit.id}")
                            .clickable { onBenefitSelected(item.benefit.id) }
                            .padding(vertical = 4.dp),
                        color = PrimaryDark,
                        fontSize = 11.sp,
                    )
                }
            }
        }
    }
}

@Composable
internal fun PlaceholderScreen(title: String, description: String, modifier: Modifier = Modifier) {
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

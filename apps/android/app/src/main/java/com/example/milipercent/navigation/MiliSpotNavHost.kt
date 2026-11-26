package com.example.milipercent.navigation

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.toRoute
import com.example.milipercent.data.admin.AdminBenefitInput
import com.example.milipercent.model.BenefitDistrict
import com.example.milipercent.model.GeoBounds
import com.example.milipercent.model.GeoPoint
import com.example.milipercent.model.LocalUser
import com.example.milipercent.ui.AppDestination
import com.example.milipercent.ui.BenefitDetailScreen
import com.example.milipercent.ui.MiliSpotUiState
import com.example.milipercent.ui.MilitaryBenefitApp
import com.example.milipercent.ui.map.openNaverMap

@Composable
fun MiliSpotNavHost(
    state: MiliSpotUiState,
    navController: NavHostController,
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
    onRegister: suspend (String, String, String) -> Result<LocalUser> = { _, _, _ -> Result.failure(UnsupportedOperationException()) },
    onLogin: suspend (String, String) -> Result<LocalUser> = { _, _ -> Result.failure(UnsupportedOperationException()) },
    onLogout: () -> Unit = {},
    onAdminSave: suspend (AdminBenefitInput, String?) -> Boolean = { _, _ -> false },
    onAdminEnd: (String) -> Unit = {},
    onAdminDelete: (String) -> Unit = {},
    onClearSearch: () -> Unit = {},
    onMapCameraIdle: (GeoPoint, GeoBounds, Boolean, Double) -> Unit = { _, _, _, _ -> },
    onCameraRequestApplied: (Long) -> Unit = {},
    onSearchInMapBounds: () -> Unit = {},
    onMapBenefitSelected: (String?) -> Unit = {},
    onCloseDetail: () -> Unit = {},
) {
    NavHost(navController = navController, startDestination = DiscoverRoute) {
        composable<DiscoverRoute> {
            AppRoute(
                state, navController, onNavigate, onSearchTextChanged, onSearch, onPresetSelected,
                onCategorySelected, onDistrictSelected, onBenefitSelected, onFavorite, onRefresh,
                onCurrentLocation, onMessageShown, onRegister, onLogin, onLogout, onAdminSave, onAdminEnd, onAdminDelete,
                onClearSearch, onMapCameraIdle, onCameraRequestApplied, onSearchInMapBounds, onMapBenefitSelected,
            )
        }
        composable<BenefitDetailRoute> { entry ->
            val benefitId = entry.toRoute<BenefitDetailRoute>().benefitId
            val benefit = state.benefits.firstOrNull { it.id == benefitId }
            val closeDetail = {
                onCloseDetail()
                navController.popBackStack()
                Unit
            }
            if (benefit == null) {
                BenefitDetailPlaceholderScreen(
                    isLoading = state.isLoading,
                    onBack = closeDetail,
                )
            } else {
                val context = LocalContext.current
                BenefitDetailScreen(
                    benefit = benefit,
                    isFavorite = benefit.id in state.favoriteIds,
                    onBack = closeDetail,
                    onFavorite = {
                        val requiresLogin = state.user == null
                        onFavorite(benefit.id)
                        if (requiresLogin) {
                            closeDetail()
                        }
                    },
                    onOpenNaverMap = { context.openNaverMap(benefit) },
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun BenefitDetailPlaceholderScreen(
    isLoading: Boolean,
    onBack: () -> Unit,
) {
    BackHandler(onBack = onBack)
    Scaffold(
        modifier = Modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = { Text("혜택 상세") },
                navigationIcon = {
                    TextButton(onClick = onBack, modifier = Modifier.testTag("detail_back")) {
                        Text("← 뒤로")
                    }
                },
            )
        },
    ) { contentPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(contentPadding)
                .padding(24.dp),
            contentAlignment = Alignment.Center,
        ) {
            if (isLoading) {
                CircularProgressIndicator()
            } else {
                Text("해당 혜택 정보를 찾을 수 없습니다.")
            }
        }
    }
}

@Composable
private fun AppRoute(
    state: MiliSpotUiState,
    navController: NavHostController,
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
    onRegister: suspend (String, String, String) -> Result<LocalUser>,
    onLogin: suspend (String, String) -> Result<LocalUser>,
    onLogout: () -> Unit,
    onAdminSave: suspend (AdminBenefitInput, String?) -> Boolean,
    onAdminEnd: (String) -> Unit,
    onAdminDelete: (String) -> Unit,
    onClearSearch: () -> Unit,
    onMapCameraIdle: (GeoPoint, GeoBounds, Boolean, Double) -> Unit,
    onCameraRequestApplied: (Long) -> Unit,
    onSearchInMapBounds: () -> Unit,
    onMapBenefitSelected: (String?) -> Unit,
) {
    MilitaryBenefitApp(
        state = state,
        navController = navController,
        onNavigate = onNavigate,
        onSearchTextChanged = onSearchTextChanged,
        onSearch = onSearch,
        onPresetSelected = onPresetSelected,
        onCategorySelected = onCategorySelected,
        onDistrictSelected = onDistrictSelected,
        onBenefitSelected = { benefitId ->
            onBenefitSelected(benefitId)
            navController.navigate(BenefitDetailRoute(benefitId)) {
                launchSingleTop = true
            }
        },
        onFavorite = onFavorite,
        onRefresh = onRefresh,
        onCurrentLocation = onCurrentLocation,
        onMessageShown = onMessageShown,
        onRegister = onRegister,
        onLogin = onLogin,
        onLogout = onLogout,
        onAdminSave = onAdminSave,
        onAdminEnd = onAdminEnd,
        onAdminDelete = onAdminDelete,
        onClearSearch = onClearSearch,
        onMapCameraIdle = onMapCameraIdle,
        onCameraRequestApplied = onCameraRequestApplied,
        onSearchInMapBounds = onSearchInMapBounds,
        onMapBenefitSelected = onMapBenefitSelected,
    )
}

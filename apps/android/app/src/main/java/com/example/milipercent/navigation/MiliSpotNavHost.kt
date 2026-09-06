package com.example.milipercent.navigation

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.toRoute
import com.example.milipercent.data.admin.AdminBenefitInput
import com.example.milipercent.model.BenefitDistrict
import com.example.milipercent.ui.AppDestination
import com.example.milipercent.ui.BenefitDetailScreen
import com.example.milipercent.ui.MiliSpotUiState
import com.example.milipercent.ui.MilitaryBenefitApp
import com.example.milipercent.ui.map.openNaverMap
import com.example.milipercent.model.LocalUser

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
    onAdminSave: (AdminBenefitInput, String?) -> Unit = { _, _ -> },
    onAdminEnd: (String) -> Unit = {},
    onAdminDelete: (String) -> Unit = {},
) {
    NavHost(navController = navController, startDestination = DiscoverRoute) {
        composable<DiscoverRoute> { AppRoute(
            state, navController, onNavigate, onSearchTextChanged, onSearch, onPresetSelected,
            onCategorySelected, onDistrictSelected, onBenefitSelected, onFavorite, onRefresh,
            onCurrentLocation, onMessageShown, onRegister, onLogin, onLogout, onAdminSave, onAdminEnd, onAdminDelete,
        ) }
        composable<SavedRoute> { AppRoute(
            state, navController, onNavigate, onSearchTextChanged, onSearch, onPresetSelected,
            onCategorySelected, onDistrictSelected, onBenefitSelected, onFavorite, onRefresh,
            onCurrentLocation, onMessageShown, onRegister, onLogin, onLogout, onAdminSave, onAdminEnd, onAdminDelete,
        ) }
        composable<AccountRoute> { AppRoute(
            state, navController, onNavigate, onSearchTextChanged, onSearch, onPresetSelected,
            onCategorySelected, onDistrictSelected, onBenefitSelected, onFavorite, onRefresh,
            onCurrentLocation, onMessageShown, onRegister, onLogin, onLogout, onAdminSave, onAdminEnd, onAdminDelete,
        ) }
        composable<AdminRoute> { AppRoute(
            state, navController, onNavigate, onSearchTextChanged, onSearch, onPresetSelected,
            onCategorySelected, onDistrictSelected, onBenefitSelected, onFavorite, onRefresh,
            onCurrentLocation, onMessageShown, onRegister, onLogin, onLogout, onAdminSave, onAdminEnd, onAdminDelete,
        ) }
        composable<BenefitDetailRoute> { entry ->
            val benefitId = entry.toRoute<BenefitDetailRoute>().benefitId
            val benefit = state.benefits.firstOrNull { it.id == benefitId }
            if (benefit == null) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text("해당 혜택 정보를 찾을 수 없습니다.") }
            } else {
                val context = LocalContext.current
                BenefitDetailScreen(
                    benefit = benefit,
                    isFavorite = benefit.id in state.favoriteIds,
                    onBack = navController::popBackStack,
                    onFavorite = { onFavorite(benefit.id) },
                    onOpenNaverMap = { context.openNaverMap(benefit) },
                )
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
    onAdminSave: (AdminBenefitInput, String?) -> Unit,
    onAdminEnd: (String) -> Unit,
    onAdminDelete: (String) -> Unit,
) {
    MilitaryBenefitApp(
        state = state,
        navController = navController,
        onNavigate = { destination ->
            onNavigate(destination)
            when (if (destination == AppDestination.ADMIN && state.user?.isAdmin != true) AppDestination.ACCOUNT else destination) {
                AppDestination.DISCOVER -> navController.navigate(DiscoverRoute) { launchSingleTop = true; restoreState = true }
                AppDestination.SAVED -> navController.navigate(SavedRoute) { launchSingleTop = true; restoreState = true }
                AppDestination.ACCOUNT -> navController.navigate(AccountRoute) { launchSingleTop = true; restoreState = true }
                AppDestination.ADMIN -> navController.navigate(AdminRoute) { launchSingleTop = true; restoreState = true }
            }
        },
        onSearchTextChanged = onSearchTextChanged,
        onSearch = onSearch,
        onPresetSelected = onPresetSelected,
        onCategorySelected = onCategorySelected,
        onDistrictSelected = onDistrictSelected,
        onBenefitSelected = { benefitId ->
            onBenefitSelected(benefitId)
            navController.navigate(BenefitDetailRoute(benefitId))
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
    )
}

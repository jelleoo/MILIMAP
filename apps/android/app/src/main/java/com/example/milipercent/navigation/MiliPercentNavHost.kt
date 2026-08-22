package com.example.milipercent.navigation

import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.runtime.Composable
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.toRoute
import com.example.milipercent.data.BenefitDataRepository
import com.example.milipercent.data.manual.ManualBenefitAdminRepository
import com.example.milipercent.model.BenefitDistrict
import com.example.milipercent.ui.BenefitDetailScreen
import com.example.milipercent.ui.BenefitDetailViewModel
import com.example.milipercent.ui.BenefitScreen
import com.example.milipercent.ui.BenefitUiState
import com.example.milipercent.ui.debug.ManualBenefitAdminScreen
import com.example.milipercent.ui.debug.ManualBenefitAdminViewModel
import com.example.milipercent.ui.debug.ManualBenefitFormScreen
import com.example.milipercent.ui.debug.ManualBenefitFormViewModel

@Composable
fun MiliPercentNavHost(
    navController: NavHostController,
    repository: BenefitDataRepository,
    manualAdminRepository: ManualBenefitAdminRepository,
    showDebugAdmin: Boolean,
    listUiState: BenefitUiState,
    benefitListState: LazyListState,
    onRetry: () -> Unit,
    onDistrictSelected: (BenefitDistrict) -> Unit,
    onSearchQueryChanged: (String) -> Unit,
    onClearSearch: () -> Unit,
) {
    BenefitNavigationHost(
        navController = navController,
        listContent = { onBenefitSelected, onDebugAdmin ->
            BenefitScreen(
                uiState = listUiState,
                benefitListState = benefitListState,
                onRetry = onRetry,
                onDistrictSelected = onDistrictSelected,
                onSearchQueryChanged = onSearchQueryChanged,
                onClearSearch = onClearSearch,
                onBenefitSelected = onBenefitSelected,
                showDebugAdmin = showDebugAdmin,
                onOpenDebugAdmin = onDebugAdmin,
            )
        },
        detailContent = { benefitId, onBack ->
            val detailViewModel: BenefitDetailViewModel = viewModel(
                factory = BenefitDetailViewModel.Factory(
                    benefitId = benefitId,
                    repository = repository,
                ),
            )
            val detailUiState = detailViewModel.uiState.collectAsStateWithLifecycle()

            BenefitDetailScreen(
                uiState = detailUiState.value,
                onBack = onBack,
            )
        },
        debugAdminEnabled = showDebugAdmin,
        adminListContent = { onBack, onCreate, onEdit ->
            val adminViewModel: ManualBenefitAdminViewModel = viewModel(
                factory = ManualBenefitAdminViewModel.Factory(manualAdminRepository),
            )
            val adminState = adminViewModel.uiState.collectAsStateWithLifecycle()
            ManualBenefitAdminScreen(
                uiState = adminState.value,
                onBack = onBack,
                onCreate = onCreate,
                onEdit = onEdit,
                onDelete = adminViewModel::delete,
            )
        },
        adminFormContent = { benefitId, onBack, onSaved ->
            val formViewModel: ManualBenefitFormViewModel = viewModel(
                factory = ManualBenefitFormViewModel.Factory(
                    benefitId = benefitId,
                    repository = manualAdminRepository,
                ),
            )
            val formState = formViewModel.uiState.collectAsStateWithLifecycle()
            ManualBenefitFormScreen(
                uiState = formState.value,
                onBack = onBack,
                onSave = formViewModel::save,
                onSaved = onSaved,
            )
        },
    )
}

@Composable
internal fun BenefitNavigationHost(
    navController: NavHostController,
    listContent: @Composable (
        onBenefitSelected: (String) -> Unit,
        onDebugAdmin: () -> Unit,
    ) -> Unit,
    detailContent: @Composable (benefitId: String, onBack: () -> Unit) -> Unit,
    debugAdminEnabled: Boolean = false,
    adminListContent: @Composable (
        onBack: () -> Unit,
        onCreate: () -> Unit,
        onEdit: (String) -> Unit,
    ) -> Unit = { _, _, _ -> },
    adminFormContent: @Composable (
        benefitId: String?,
        onBack: () -> Unit,
        onSaved: () -> Unit,
    ) -> Unit = { _, _, _ -> },
) {
    NavHost(
        navController = navController,
        startDestination = BenefitListRoute,
    ) {
        composable<BenefitListRoute> {
            listContent(
                { benefitId -> navController.navigate(BenefitDetailRoute(benefitId)) },
                { if (debugAdminEnabled) navController.navigate(DebugManualBenefitListRoute) },
            )
        }
        composable<BenefitDetailRoute> { backStackEntry ->
            val route = backStackEntry.toRoute<BenefitDetailRoute>()
            detailContent(
                route.benefitId,
                navController::popBackStack,
            )
        }
        if (debugAdminEnabled) {
            composable<DebugManualBenefitListRoute> {
                adminListContent(
                    navController::popBackStack,
                    { navController.navigate(DebugManualBenefitFormRoute()) },
                    { id -> navController.navigate(DebugManualBenefitFormRoute(id)) },
                )
            }
            composable<DebugManualBenefitFormRoute> { backStackEntry ->
                val route = backStackEntry.toRoute<DebugManualBenefitFormRoute>()
                adminFormContent(
                    route.benefitId,
                    navController::popBackStack,
                    navController::popBackStack,
                )
            }
        }
    }
}

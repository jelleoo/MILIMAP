package com.example.milipercent

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.compose.rememberNavController
import com.example.milipercent.data.BenefitRepository
import com.example.milipercent.data.account.PasswordHasher
import com.example.milipercent.data.account.RoomAccountRepository
import com.example.milipercent.data.admin.RoomAdminBenefitRepository
import com.example.milipercent.data.favorite.RoomFavoriteRepository
import com.example.milipercent.data.local.BenefitDatabase
import com.example.milipercent.data.local.RoomBenefitLocalDataSource
import com.example.milipercent.data.seed.AssetJsonSource
import com.example.milipercent.data.seed.BundledSeedSynchronizer
import com.example.milipercent.data.seed.LegacyBenefitSeedLoader
import com.example.milipercent.data.seed.ManualBenefitSeedLoader
import com.example.milipercent.data.session.SessionStore
import com.example.milipercent.location.AndroidLocationDataSource
import com.example.milipercent.navigation.MiliSpotNavHost
import com.example.milipercent.network.BenefitApiClient
import com.example.milipercent.network.BenefitXmlParser
import com.example.milipercent.ui.MiliSpotViewModel
import com.example.milipercent.ui.MilitaryBenefitTheme

class MainActivity : ComponentActivity() {
    private val database by lazy { BenefitDatabase.getInstance(applicationContext) }
    private val localDataSource by lazy { RoomBenefitLocalDataSource(database.benefitDao()) }
    private val benefitRepository by lazy {
        BenefitRepository(
            apiClient = BenefitApiClient(BuildConfig.MMA_API_URL, BuildConfig.MMA_SERVICE_KEY, BenefitXmlParser()),
            localDataSource = localDataSource,
        )
    }
    private val locationDataSource by lazy { AndroidLocationDataSource(applicationContext) }
    private var locationTrackingRequested = false

    private val viewModel: MiliSpotViewModel by viewModels {
        MiliSpotViewModel.Factory(
            benefitRepository = benefitRepository,
            accountRepository = RoomAccountRepository(database, PasswordHasher()),
            favoriteRepository = RoomFavoriteRepository(database),
            adminRepository = RoomAdminBenefitRepository(database),
            seedSynchronizer = BundledSeedSynchronizer(
                database,
                listOf(
                    LegacyBenefitSeedLoader(AssetJsonSource(applicationContext, "benefits.seed.json")),
                    ManualBenefitSeedLoader(AssetJsonSource(applicationContext, "manual_benefits_seed.json")),
                ),
            ),
            sessionStore = SessionStore(applicationContext),
            mmaConfigured = BuildConfig.MMA_API_URL.isNotBlank() && BuildConfig.MMA_SERVICE_KEY.isNotBlank(),
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            val state by viewModel.uiState.collectAsStateWithLifecycle()
            val locationPermissionLauncher = rememberLauncherForActivityResult(
                ActivityResultContracts.RequestMultiplePermissions(),
            ) { permissions ->
                if (permissions.values.any { it }) {
                    locationTrackingRequested = true
                    viewModel.startLocationTracking(locationDataSource)
                } else {
                    viewModel.locationPermissionDenied()
                }
            }
            MilitaryBenefitTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    MiliSpotNavHost(
                        state = state,
                        navController = rememberNavController(),
                        onNavigate = viewModel::navigate,
                        onSearchTextChanged = viewModel::updateSearchText,
                        onSearch = viewModel::submitSearch,
                        onPresetSelected = viewModel::selectPreset,
                        onCategorySelected = viewModel::selectCategory,
                        onDistrictSelected = viewModel::selectDistrict,
                        onBenefitSelected = viewModel::selectBenefit,
                        onFavorite = viewModel::toggleFavorite,
                        onRefresh = viewModel::refresh,
                        onCurrentLocation = {
                            if (!viewModel.requestCurrentLocationFocus()) {
                                if (hasLocationPermission()) {
                                    locationTrackingRequested = true
                                    viewModel.startLocationTracking(locationDataSource)
                                } else {
                                    locationPermissionLauncher.launch(LOCATION_PERMISSIONS)
                                }
                            }
                        },
                        onMessageShown = viewModel::clearMessage,
                        onRegister = viewModel::register,
                        onLogin = viewModel::login,
                        onLogout = viewModel::logout,
                        onAdminSave = viewModel::saveAdmin,
                        onAdminEnd = viewModel::endAdminBenefit,
                        onAdminDelete = viewModel::deleteManualBenefit,
                    )
                }
            }
        }
    }

    override fun onStart() {
        super.onStart()
        if (locationTrackingRequested && hasLocationPermission()) {
            viewModel.startLocationTracking(locationDataSource)
        }
    }

    override fun onStop() {
        viewModel.stopLocationTracking()
        super.onStop()
    }

    private fun hasLocationPermission(): Boolean = LOCATION_PERMISSIONS.any { permission ->
        ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED
    }

    private companion object {
        val LOCATION_PERMISSIONS = arrayOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        )
    }
}

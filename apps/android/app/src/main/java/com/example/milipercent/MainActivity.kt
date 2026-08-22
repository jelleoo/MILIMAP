package com.example.milipercent

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.compose.rememberNavController
import com.example.milipercent.data.BenefitRepository
import com.example.milipercent.data.BenefitDataRepository
import com.example.milipercent.data.manual.RoomManualBenefitAdminRepository
import com.example.milipercent.data.local.BenefitDatabase
import com.example.milipercent.data.local.RoomBenefitLocalDataSource
import com.example.milipercent.data.seed.AssetManualBenefitSeedJsonSource
import com.example.milipercent.data.seed.ManualBenefitSeedLoader
import com.example.milipercent.data.seed.RoomManualSeedSynchronizer
import com.example.milipercent.network.BenefitApiClient
import com.example.milipercent.network.BenefitXmlParser
import com.example.milipercent.navigation.MiliPercentNavHost
import com.example.milipercent.ui.BenefitUiState
import com.example.milipercent.ui.BenefitViewModel

class MainActivity : ComponentActivity() {
    private val localDataSource by lazy {
        val database = BenefitDatabase.getInstance(applicationContext)
        RoomBenefitLocalDataSource(database.benefitDao())
    }

    private val repository: BenefitDataRepository by lazy {
        val apiClient = BenefitApiClient(
            apiUrl = BuildConfig.MMA_API_URL,
            serviceKey = BuildConfig.MMA_SERVICE_KEY,
            xmlParser = BenefitXmlParser(),
        )
        BenefitRepository(
            apiClient = apiClient,
            localDataSource = localDataSource,
        )
    }

    private val manualAdminRepository by lazy {
        RoomManualBenefitAdminRepository(localDataSource)
    }

    private val viewModelFactory by lazy {
        val seedSynchronizer = RoomManualSeedSynchronizer(
            loader = ManualBenefitSeedLoader(
                AssetManualBenefitSeedJsonSource(applicationContext),
            ),
            localDataSource = localDataSource,
        )
        BenefitViewModel.Factory(repository, seedSynchronizer)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    val benefitViewModel: BenefitViewModel = viewModel(factory = viewModelFactory)
                    val uiState by benefitViewModel.uiState.collectAsStateWithLifecycle()
                    val navController = rememberNavController()
                    val benefitListState = rememberLazyListState()
                    val listFilter = (uiState as? BenefitUiState.Success)?.let { success ->
                        success.selectedDistrict to success.searchQuery
                    }

                    LaunchedEffect(listFilter) {
                        val success = uiState as? BenefitUiState.Success
                        if (success != null && success.benefits.isNotEmpty()) {
                            benefitListState.scrollToItem(0)
                        }
                    }

                    MiliPercentNavHost(
                        navController = navController,
                        repository = repository,
                        manualAdminRepository = manualAdminRepository,
                        showDebugAdmin = BuildConfig.DEBUG,
                        listUiState = uiState,
                        benefitListState = benefitListState,
                        onRetry = benefitViewModel::loadBenefits,
                        onDistrictSelected = benefitViewModel::selectDistrict,
                        onSearchQueryChanged = benefitViewModel::updateSearchQuery,
                        onClearSearch = benefitViewModel::clearSearchQuery,
                    )
                }
            }
        }
    }
}

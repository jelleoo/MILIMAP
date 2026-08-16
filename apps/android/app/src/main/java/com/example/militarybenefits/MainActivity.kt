package com.example.militarybenefits

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.remember
import androidx.core.content.ContextCompat
import com.example.militarybenefits.data.GeoPoint
import com.example.militarybenefits.ui.MilitaryBenefitApp
import com.example.militarybenefits.ui.MilitaryBenefitTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MilitaryBenefitTheme {
                val controller = remember { AppController(applicationContext) }
                val permissionLauncher = rememberLauncherForActivityResult(
                    ActivityResultContracts.RequestMultiplePermissions(),
                ) { grants ->
                    if (grants.values.any { it }) locate(controller)
                    else controller.locationFailed("위치 권한이 없어 지역 검색으로 보여드릴게요.")
                }
                MilitaryBenefitApp(
                    controller = controller,
                    requestCurrentLocation = {
                        val fine = ContextCompat.checkSelfPermission(
                            this, Manifest.permission.ACCESS_FINE_LOCATION,
                        ) == PackageManager.PERMISSION_GRANTED
                        val coarse = ContextCompat.checkSelfPermission(
                            this, Manifest.permission.ACCESS_COARSE_LOCATION,
                        ) == PackageManager.PERMISSION_GRANTED
                        if (fine || coarse) locate(controller)
                        else permissionLauncher.launch(
                            arrayOf(
                                Manifest.permission.ACCESS_FINE_LOCATION,
                                Manifest.permission.ACCESS_COARSE_LOCATION,
                            ),
                        )
                    },
                )
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun locate(controller: AppController) {
        val manager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val providers = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
            .filter { runCatching { manager.isProviderEnabled(it) }.getOrDefault(false) }
        val cached = providers.mapNotNull { provider ->
            runCatching { manager.getLastKnownLocation(provider) }.getOrNull()
        }.maxByOrNull(Location::getTime)
        if (cached != null) {
            controller.applyCurrentLocation(GeoPoint(cached.latitude, cached.longitude))
            return
        }
        val provider = providers.firstOrNull()
        if (provider == null) {
            controller.locationFailed("기기의 위치 서비스가 꺼져 있어요.")
            return
        }
        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                manager.removeUpdates(this)
                controller.applyCurrentLocation(GeoPoint(location.latitude, location.longitude))
            }

            override fun onProviderDisabled(provider: String) {
                controller.locationFailed("위치 서비스를 켜고 다시 시도해 주세요.")
            }
        }
        runCatching { manager.requestSingleUpdate(provider, listener, Looper.getMainLooper()) }
            .onFailure { controller.locationFailed("현재 위치를 확인하지 못했어요. 다시 시도해 주세요.") }
    }
}

package com.example.milipercent.location

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Looper
import androidx.core.content.ContextCompat
import com.example.milipercent.model.GeoPoint
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow

class AndroidLocationDataSource(context: Context) : LocationDataSource {
    private val appContext = context.applicationContext

    @SuppressLint("MissingPermission") // Runtime permission gates above distinguish fine GPS from coarse network access.
    override fun updates(): Flow<LocationUpdate> = callbackFlow {
        val manager = appContext.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val hasFine = appContext.hasPermission(Manifest.permission.ACCESS_FINE_LOCATION)
        val hasCoarse = appContext.hasPermission(Manifest.permission.ACCESS_COARSE_LOCATION)
        if (!hasFine && !hasCoarse) {
            trySend(LocationUpdate.Unavailable("위치 권한이 필요합니다."))
            close()
            return@callbackFlow
        }

        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                trySend(LocationUpdate.Position(location.toGeoPoint()))
            }

            override fun onProviderDisabled(provider: String) {
                trySend(LocationUpdate.Unavailable("${provider} 위치 제공자를 사용할 수 없습니다."))
            }
        }
        var registered = false
        fun register(provider: String) {
            runCatching {
                manager.requestLocationUpdates(
                    provider,
                    LOCATION_UPDATE_INTERVAL_MS,
                    LOCATION_UPDATE_DISTANCE_METERS,
                    listener,
                    Looper.getMainLooper(),
                )
                registered = true
                manager.getLastKnownLocation(provider)?.let { location ->
                    trySend(LocationUpdate.Position(location.toGeoPoint()))
                }
            }.onFailure {
                trySend(LocationUpdate.Unavailable("$provider 위치를 시작할 수 없습니다."))
            }
        }
        if (hasFine) register(LocationManager.GPS_PROVIDER)
        if (hasFine || hasCoarse) register(LocationManager.NETWORK_PROVIDER)
        if (!registered) trySend(LocationUpdate.Unavailable("사용 가능한 위치 제공자가 없습니다."))

        awaitClose { manager.removeUpdates(listener) }
    }

    private fun Context.hasPermission(permission: String): Boolean =
        ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED

    private fun Location.toGeoPoint(): GeoPoint = GeoPoint(latitude, longitude)
}

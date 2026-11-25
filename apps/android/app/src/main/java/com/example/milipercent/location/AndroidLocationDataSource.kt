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

internal data class LocationFixCandidate(
    val point: GeoPoint,
    val provider: String,
    val timeMillis: Long,
    val accuracyMeters: Float,
)

internal object LocationFixSelector {
    private const val SIGNIFICANT_TIME_DELTA_MS = 2 * 60 * 1_000L
    private const val SIGNIFICANT_ACCURACY_WORSE_METERS = 200f

    fun isBetterCandidate(
        candidate: LocationFixCandidate,
        current: LocationFixCandidate?,
    ): Boolean {
        if (current == null) return true

        val timeDelta = candidate.timeMillis - current.timeMillis
        val isSignificantlyNewer = timeDelta > SIGNIFICANT_TIME_DELTA_MS
        val isSignificantlyOlder = timeDelta < -SIGNIFICANT_TIME_DELTA_MS
        val isNewer = timeDelta > 0L

        if (isSignificantlyNewer) return true
        if (isSignificantlyOlder) return false

        val accuracyDelta = candidate.accuracyMeters - current.accuracyMeters
        val isMoreAccurate = accuracyDelta < 0f
        val isLessAccurate = accuracyDelta > 0f
        val isSignificantlyLessAccurate = accuracyDelta > SIGNIFICANT_ACCURACY_WORSE_METERS
        val isSameProvider = candidate.provider == current.provider

        return when {
            isMoreAccurate -> true
            isNewer && !isLessAccurate -> true
            isNewer && !isSignificantlyLessAccurate && isSameProvider -> true
            else -> false
        }
    }

    fun selectBest(candidates: Iterable<LocationFixCandidate>): LocationFixCandidate? {
        var best: LocationFixCandidate? = null
        for (candidate in candidates) {
            if (isBetterCandidate(candidate, best)) {
                best = candidate
            }
        }
        return best
    }

    fun providerDisplayName(provider: String): String = when (provider) {
        LocationManager.GPS_PROVIDER -> "GPS"
        LocationManager.NETWORK_PROVIDER -> "네트워크"
        LocationManager.PASSIVE_PROVIDER -> "보조"
        else -> "기기"
    }

    fun registrationFailureMessage(
        registeredProviders: Collection<String>,
        failedProviders: Collection<String>,
    ): String? {
        if (registeredProviders.isNotEmpty()) return null
        return if (failedProviders.size == 1) {
            "${providerDisplayName(failedProviders.single())} 위치를 시작할 수 없습니다."
        } else {
            "사용 가능한 위치 제공자가 없습니다."
        }
    }
}

class AndroidLocationDataSource(context: Context) : LocationDataSource {
    private val appContext = context.applicationContext

    @SuppressLint("MissingPermission") // Runtime permission gates above distinguish fine GPS from coarse network access.
    override fun updates(): Flow<LocationUpdate> = callbackFlow {
        val manager = appContext.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
        if (manager == null) {
            trySend(LocationUpdate.Unavailable("위치 서비스를 사용할 수 없습니다."))
            close()
            return@callbackFlow
        }
        val hasFine = appContext.hasPermission(Manifest.permission.ACCESS_FINE_LOCATION)
        val hasCoarse = appContext.hasPermission(Manifest.permission.ACCESS_COARSE_LOCATION)
        if (!hasFine && !hasCoarse) {
            trySend(LocationUpdate.Unavailable("위치 권한이 필요합니다."))
            close()
            return@callbackFlow
        }

        var bestCandidate: LocationFixCandidate? = null
        val registeredProviders = mutableListOf<String>()
        val failedProviders = mutableListOf<String>()

        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                val candidate = location.toCandidate()
                if (LocationFixSelector.isBetterCandidate(candidate, bestCandidate)) {
                    bestCandidate = candidate
                    trySend(LocationUpdate.Position(candidate.point))
                }
            }

            override fun onProviderDisabled(provider: String) {
                val otherEnabled = registeredProviders.any { other ->
                    other != provider && runCatching { manager.isProviderEnabled(other) }.getOrDefault(false)
                }
                if (!otherEnabled) {
                    val label = LocationFixSelector.providerDisplayName(provider)
                    trySend(LocationUpdate.Unavailable("$label 위치를 사용할 수 없습니다."))
                }
            }
        }

        val lastKnownCandidates = mutableListOf<LocationFixCandidate>()
        fun register(provider: String) {
            runCatching {
                manager.requestLocationUpdates(
                    provider,
                    LOCATION_UPDATE_INTERVAL_MS,
                    LOCATION_UPDATE_DISTANCE_METERS,
                    listener,
                    Looper.getMainLooper(),
                )
            }.onSuccess {
                registeredProviders += provider
                runCatching { manager.getLastKnownLocation(provider) }.getOrNull()?.let { location ->
                    lastKnownCandidates += location.toCandidate(fallbackProvider = provider)
                }
            }.onFailure {
                failedProviders += provider
            }
        }

        if (hasFine) register(LocationManager.GPS_PROVIDER)
        if (hasFine || hasCoarse) register(LocationManager.NETWORK_PROVIDER)

        LocationFixSelector.selectBest(lastKnownCandidates)?.let { best ->
            bestCandidate = best
            trySend(LocationUpdate.Position(best.point))
        }
        LocationFixSelector.registrationFailureMessage(registeredProviders, failedProviders)?.let { message ->
            trySend(LocationUpdate.Unavailable(message))
        }

        awaitClose { runCatching { manager.removeUpdates(listener) } }
    }

    private fun Context.hasPermission(permission: String): Boolean =
        ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED

    private fun Location.toCandidate(fallbackProvider: String = ""): LocationFixCandidate =
        LocationFixCandidate(
            point = GeoPoint(latitude, longitude),
            provider = provider ?: fallbackProvider,
            timeMillis = time,
            accuracyMeters = if (hasAccuracy()) accuracy else Float.MAX_VALUE,
        )
}

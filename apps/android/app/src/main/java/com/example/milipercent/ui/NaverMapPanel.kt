package com.example.milipercent.ui

import android.graphics.PointF
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.example.milipercent.BuildConfig
import com.example.milipercent.model.GeoPoint
import com.example.milipercent.ui.map.BenefitMapItem
import com.example.milipercent.ui.map.createBenefitMarkerIcon
import com.example.milipercent.ui.map.markerSetSignature
import com.naver.maps.geometry.LatLng
import com.naver.maps.map.CameraAnimation
import com.naver.maps.map.CameraUpdate
import com.naver.maps.map.MapView
import com.naver.maps.map.overlay.Marker
import kotlin.math.hypot

@Composable
fun BenefitMap(
    benefits: List<BenefitMapItem>,
    center: GeoPoint,
    currentLocation: GeoPoint?,
    cameraRequestId: Long,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (BuildConfig.NAVER_MAP_NCP_KEY_ID.isBlank()) {
        OfflineCoordinateMap(benefits, center, currentLocation, onSelect, modifier)
    } else {
        NaverMapView(benefits, center, currentLocation, cameraRequestId, onSelect, modifier)
    }
}

@Composable
private fun NaverMapView(
    benefits: List<BenefitMapItem>,
    center: GeoPoint,
    currentLocation: GeoPoint?,
    cameraRequestId: Long,
    onSelect: (String) -> Unit,
    modifier: Modifier,
) {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val latestOnSelect by rememberUpdatedState(onSelect)
    val mapView = remember { MapView(context).also { it.onCreate(null) } }
    val markerIcon = remember(context) { createBenefitMarkerIcon(context) }
    val markers = remember { mutableListOf<Marker>() }
    var renderedSignature by remember { mutableStateOf("") }
    var cameraCenter by remember { mutableStateOf<GeoPoint?>(null) }
    var handledCameraRequestId by remember { mutableLongStateOf(-1L) }

    DisposableEffect(lifecycle, mapView) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_START -> mapView.onStart()
                Lifecycle.Event.ON_RESUME -> mapView.onResume()
                Lifecycle.Event.ON_PAUSE -> mapView.onPause()
                Lifecycle.Event.ON_STOP -> mapView.onStop()
                Lifecycle.Event.ON_DESTROY -> mapView.onDestroy()
                else -> Unit
            }
        }
        lifecycle.addObserver(observer)
        onDispose {
            lifecycle.removeObserver(observer)
            markers.forEach { it.map = null }
            markers.clear()
            mapView.onDestroy()
        }
    }

    AndroidView(
        modifier = modifier,
        factory = { mapView },
        update = { view ->
            view.getMapAsync { map ->
                map.uiSettings.isZoomControlEnabled = false
                map.uiSettings.isLocationButtonEnabled = false
                if (cameraCenter != center || handledCameraRequestId != cameraRequestId) {
                    map.moveCamera(
                        CameraUpdate.scrollAndZoomTo(LatLng(center.latitude, center.longitude), 13.5)
                            .animate(CameraAnimation.Easing, 450),
                    )
                    cameraCenter = center
                    handledCameraRequestId = cameraRequestId
                }
                map.locationOverlay.apply {
                    isVisible = currentLocation != null
                    currentLocation?.let { position = LatLng(it.latitude, it.longitude) }
                }
                val candidates = benefits.take(500)
                val signature = markerSetSignature(candidates)
                if (signature != renderedSignature) {
                    markers.forEach { it.map = null }
                    markers.clear()
                    candidates.forEach { benefit ->
                        markers += Marker().apply {
                            position = LatLng(benefit.latitude, benefit.longitude)
                            icon = markerIcon
                            anchor = PointF(0.5f, 1f)
                            captionText = benefit.name
                            captionMinZoom = 13.0
                            captionTextSize = 11f
                            setOnClickListener { latestOnSelect(benefit.id); true }
                            this.map = map
                        }
                    }
                    renderedSignature = signature
                }
            }
        },
    )
}

@Composable
private fun OfflineCoordinateMap(
    benefits: List<BenefitMapItem>,
    center: GeoPoint,
    currentLocation: GeoPoint?,
    onSelect: (String) -> Unit,
    modifier: Modifier,
) {
    val radius = with(LocalDensity.current) { 28.dp.toPx() }
    Box(modifier.background(PrimarySoft)) {
        Canvas(Modifier.fillMaxSize().pointerInput(benefits) {
            detectTapGestures { tap ->
                benefits.map { item -> item to mapPoint(item.latitude, item.longitude, size.width.toFloat(), size.height.toFloat()) }
                    .minByOrNull { (_, point) -> hypot(tap.x - point.x, tap.y - point.y) }
                    ?.takeIf { (_, point) -> hypot(tap.x - point.x, tap.y - point.y) <= radius }
                    ?.let { (item) -> onSelect(item.id) }
            }
        }) {
            drawRect(PrimarySoft)
            benefits.forEach { item ->
                val point = mapPoint(item.latitude, item.longitude, size.width, size.height)
                drawCircle(Color.White, 13f, point)
                drawCircle(PrimaryDark, 8f, point)
            }
            val focus = mapPoint(center.latitude, center.longitude, size.width, size.height)
            drawCircle(PrimaryDark.copy(alpha = .18f), 28f, focus)
            drawCircle(PrimaryDark, 8f, focus)
            currentLocation?.let { location ->
                val point = mapPoint(location.latitude, location.longitude, size.width, size.height)
                drawCircle(Color.White, 15f, point)
                drawCircle(Color(0xFF1F6FEB), 9f, point)
            }
        }
        Surface(
            modifier = Modifier.align(Alignment.TopCenter).padding(12.dp),
            color = Navy.copy(alpha = .9f),
            shape = RoundedCornerShape(50),
        ) {
            Text(
                "네이버 지도 키 확인 중 · 좌표 지도 ${benefits.size}곳",
                Modifier.padding(horizontal = 13.dp, vertical = 8.dp),
                color = Color.White,
                fontSize = 11.sp,
            )
        }
    }
}

private fun mapPoint(latitude: Double, longitude: Double, width: Float, height: Float): Offset {
    val x = ((longitude - 126.45) / (127.35 - 126.45)).coerceIn(.01, .99).toFloat() * width
    val y = (1 - ((latitude - 36.85) / (38.30 - 36.85)).coerceIn(.01, .99)).toFloat() * height
    return Offset(x, y)
}

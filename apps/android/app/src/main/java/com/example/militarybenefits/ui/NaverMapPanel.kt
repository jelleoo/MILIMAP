package com.example.militarybenefits.ui

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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
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
import com.example.militarybenefits.BuildConfig
import com.example.militarybenefits.data.Benefit
import com.example.militarybenefits.data.GeoPoint
import com.example.militarybenefits.ui.map.createBenefitMarkerIcon
import com.naver.maps.geometry.LatLng
import com.naver.maps.map.CameraAnimation
import com.naver.maps.map.CameraUpdate
import com.naver.maps.map.MapView
import com.naver.maps.map.overlay.Marker
import kotlin.math.hypot

@Composable
fun BenefitMap(
    benefits: List<Benefit>,
    center: GeoPoint,
    currentLocation: GeoPoint?,
    onSelect: (Benefit) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (BuildConfig.NAVER_MAP_NCP_KEY_ID.isBlank()) {
        OfflineCoordinateMap(benefits, center, currentLocation, onSelect, modifier)
    } else {
        NaverMapView(benefits, center, currentLocation, onSelect, modifier)
    }
}

@Composable
private fun NaverMapView(
    benefits: List<Benefit>,
    center: GeoPoint,
    currentLocation: GeoPoint?,
    onSelect: (Benefit) -> Unit,
    modifier: Modifier,
) {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val mapView = remember { MapView(context).also { it.onCreate(null) } }
    val benefitMarkerIcon = remember(context) { createBenefitMarkerIcon(context) }
    val markers = remember { mutableListOf<Marker>() }
    val renderedSignature = remember { mutableStateOf("") }
    val cameraCenter = remember { mutableStateOf<GeoPoint?>(null) }

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
                if (cameraCenter.value != center) {
                    map.moveCamera(
                        CameraUpdate.scrollAndZoomTo(LatLng(center.latitude, center.longitude), 13.5)
                            .animate(CameraAnimation.Easing, 450),
                    )
                    cameraCenter.value = center
                }
                map.locationOverlay.apply {
                    isVisible = currentLocation != null
                    currentLocation?.let { position = LatLng(it.latitude, it.longitude) }
                }

                val signature = benefits.joinToString("|") { it.id } + "@${benefits.size}"
                if (signature != renderedSignature.value) {
                    markers.forEach { it.map = null }
                    markers.clear()
                    benefits.asSequence()
                        .filter { it.latitude != null && it.longitude != null }
                        .take(500)
                        .forEach { benefit ->
                            markers += Marker().apply {
                                position = LatLng(benefit.latitude!!, benefit.longitude!!)
                                icon = benefitMarkerIcon
                                anchor = PointF(0.5f, 1f)
                                captionText = benefit.name
                                captionMinZoom = 13.0
                                captionTextSize = 11f
                                setOnClickListener {
                                    onSelect(benefit)
                                    true
                                }
                                this.map = map
                            }
                        }
                    renderedSignature.value = signature
                }
            }
        },
    )
}

@Composable
private fun OfflineCoordinateMap(
    benefits: List<Benefit>,
    center: GeoPoint,
    currentLocation: GeoPoint?,
    onSelect: (Benefit) -> Unit,
    modifier: Modifier,
) {
    val radius = with(LocalDensity.current) { 28.dp.toPx() }
    Box(modifier.background(PrimarySoft)) {
        Canvas(
            Modifier.fillMaxSize().pointerInput(benefits) {
                detectTapGestures { tap ->
                    benefits.asSequence()
                        .filter { it.latitude != null && it.longitude != null }
                        .map { it to mapPoint(it.latitude!!, it.longitude!!, size.width.toFloat(), size.height.toFloat()) }
                        .minByOrNull { (_, point) -> hypot(tap.x - point.x, tap.y - point.y) }
                        ?.takeIf { (_, point) -> hypot(tap.x - point.x, tap.y - point.y) <= radius }
                        ?.let { onSelect(it.first) }
                }
            },
        ) {
            repeat(9) { index ->
                val x = size.width * (index + 1) / 10
                drawLine(Color.White.copy(alpha = 0.8f), Offset(x, 0f), Offset(x + 70f, size.height), 6f)
            }
            repeat(8) { index ->
                val y = size.height * (index + 1) / 9
                drawLine(Color.White.copy(alpha = 0.8f), Offset(0f, y), Offset(size.width, y - 45f), 7f)
            }
            drawLine(Color(0xFFBFD5FF), Offset(0f, size.height * .62f), Offset(size.width, size.height * .56f), 38f)
            benefits.forEach { benefit ->
                if (benefit.latitude == null || benefit.longitude == null) return@forEach
                val point = mapPoint(benefit.latitude, benefit.longitude, size.width, size.height)
                drawCircle(Color.White, 13f, point)
                drawCircle(Color(android.graphics.Color.parseColor(categoryHex(benefit.category))), 8f, point)
            }
            val focus = mapPoint(center.latitude, center.longitude, size.width, size.height)
            drawCircle(PrimaryDark.copy(alpha = .18f), 28f, focus)
            drawCircle(PrimaryDark, 8f, focus)
            currentLocation?.let {
                val location = mapPoint(it.latitude, it.longitude, size.width, size.height)
                drawCircle(Color.White, 15f, location)
                drawCircle(Color(0xFF1F6FEB), 9f, location)
            }
        }
        Surface(
            modifier = Modifier.align(Alignment.TopCenter).padding(top = 116.dp),
            color = Navy.copy(alpha = .9f),
            shape = RoundedCornerShape(50),
        ) {
            Text(
                "네이버 지도 키 등록 전 · 좌표 지도 ${benefits.count { it.latitude != null }}곳",
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

private fun categoryHex(category: String) = when (category) {
    "음식" -> "#F16D5B"
    "카페" -> "#A7653A"
    "미용·뷰티" -> "#8B62C7"
    "숙박" -> "#2879B9"
    "병원" -> "#2F9E66"
    else -> "#315FCB"
}

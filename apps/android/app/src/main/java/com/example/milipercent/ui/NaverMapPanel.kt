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
import com.example.milipercent.model.GeoBounds
import com.example.milipercent.model.GeoPoint
import com.example.milipercent.ui.map.BenefitMapItem
import com.example.milipercent.ui.map.DEFAULT_MAX_RENDERED_MARKERS
import com.example.milipercent.ui.map.MapViewLifecycleController
import com.example.milipercent.ui.map.categoryAccentColorInt
import com.example.milipercent.ui.map.computeMarkerDiff
import com.example.milipercent.ui.map.createBenefitMarkerIcon
import com.example.milipercent.ui.map.selectMapMarkerCandidates as selectBoundedMarkerCandidates
import com.naver.maps.geometry.LatLng
import com.naver.maps.geometry.LatLngBounds
import com.naver.maps.map.CameraAnimation
import com.naver.maps.map.CameraUpdate
import com.naver.maps.map.MapView
import com.naver.maps.map.overlay.Marker
import com.naver.maps.map.overlay.OverlayImage
import kotlin.math.hypot
import kotlin.math.roundToInt

@Composable
fun BenefitMap(
    benefits: List<BenefitMapItem>,
    center: GeoPoint,
    currentLocation: GeoPoint?,
    cameraRequestId: Long,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
    cameraTarget: MapCameraTarget = MapCameraTarget.Point(center),
    appliedCameraRequestId: Long = -1L,
    lastCameraSnapshot: MapCameraSnapshot? = null,
    selectedBenefitId: String? = null,
    onMapBlankClick: () -> Unit = {},
    onCameraRequestApplied: (Long) -> Unit = {},
    onCameraIdle: (GeoPoint, GeoBounds, Boolean, Double) -> Unit = { _, _, _, _ -> },
) {
    if (BuildConfig.NAVER_MAP_NCP_KEY_ID.isBlank()) {
        OfflineCoordinateMap(
            benefits = benefits,
            center = center,
            currentLocation = currentLocation,
            selectedBenefitId = selectedBenefitId,
            onSelect = onSelect,
            onMapBlankClick = onMapBlankClick,
            modifier = modifier,
        )
    } else {
        NaverMapView(
            benefits = benefits,
            cameraTarget = cameraTarget,
            currentLocation = currentLocation,
            cameraRequestId = cameraRequestId,
            appliedCameraRequestId = appliedCameraRequestId,
            lastCameraSnapshot = lastCameraSnapshot,
            selectedBenefitId = selectedBenefitId,
            onSelect = onSelect,
            onMapBlankClick = onMapBlankClick,
            onCameraRequestApplied = onCameraRequestApplied,
            onCameraIdle = onCameraIdle,
            modifier = modifier,
        )
    }
}

@Composable
private fun NaverMapView(
    benefits: List<BenefitMapItem>,
    cameraTarget: MapCameraTarget,
    currentLocation: GeoPoint?,
    cameraRequestId: Long,
    appliedCameraRequestId: Long,
    lastCameraSnapshot: MapCameraSnapshot?,
    selectedBenefitId: String?,
    onSelect: (String) -> Unit,
    onMapBlankClick: () -> Unit,
    onCameraRequestApplied: (Long) -> Unit,
    onCameraIdle: (GeoPoint, GeoBounds, Boolean, Double) -> Unit,
    modifier: Modifier,
) {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val density = LocalDensity.current.density
    val latestOnSelect by rememberUpdatedState(onSelect)
    val latestOnMapBlankClick by rememberUpdatedState(onMapBlankClick)
    val latestOnCameraRequestApplied by rememberUpdatedState(onCameraRequestApplied)
    val latestOnCameraIdle by rememberUpdatedState(onCameraIdle)
    val mapView = remember { MapView(context).also { it.onCreate(null) } }
    val lifecycleController = remember(mapView) {
        MapViewLifecycleController(
            onStart = mapView::onStart,
            onResume = mapView::onResume,
            onPause = mapView::onPause,
            onStop = mapView::onStop,
            onDestroy = mapView::onDestroy,
        )
    }
    val iconCache = remember(context) { mutableMapOf<Pair<String, Boolean>, OverlayImage>() }
    val markerPool = remember { LinkedHashMap<String, Marker>() }
    val renderedItems = remember { LinkedHashMap<String, BenefitMapItem>() }
    val selectionState = remember {
        object {
            var lastSelectedId: String? = null
        }
    }
    var initializedCamera by remember { mutableStateOf(false) }
    var handledCameraRequestId by remember { mutableLongStateOf(-1L) }
    var listenersAttached by remember { mutableStateOf(false) }
    val gestureState = remember {
        object {
            var sawUserGesture = false
        }
    }

    DisposableEffect(lifecycle, mapView) {
        val observer = LifecycleEventObserver { _, event ->
            lifecycleController.onEvent(event)
        }
        lifecycle.addObserver(observer)
        onDispose {
            lifecycle.removeObserver(observer)
            markerPool.values.forEach { it.map = null }
            markerPool.clear()
            renderedItems.clear()
            lifecycleController.dispose()
        }
    }

    AndroidView(
        modifier = modifier,
        factory = { mapView },
        update = { view ->
            if (lifecycleController.isDestroyed) return@AndroidView
            view.getMapAsync { map ->
                if (lifecycleController.isDestroyed) return@getMapAsync
                map.uiSettings.isZoomControlEnabled = false
                map.uiSettings.isLocationButtonEnabled = false
                if (!listenersAttached) {
                    listenersAttached = true
                    map.addOnCameraChangeListener { reason, _ ->
                        if (reason == CameraUpdate.REASON_GESTURE) {
                            gestureState.sawUserGesture = true
                        }
                    }
                    map.addOnCameraIdleListener {
                        if (lifecycleController.isDestroyed) return@addOnCameraIdleListener
                        val position = map.cameraPosition
                        val bounds = map.contentBounds
                        val byGesture = gestureState.sawUserGesture
                        gestureState.sawUserGesture = false
                        latestOnCameraIdle(
                            GeoPoint(position.target.latitude, position.target.longitude),
                            GeoBounds(bounds.southLatitude, bounds.westLongitude, bounds.northLatitude, bounds.eastLongitude),
                            byGesture,
                            position.zoom,
                        )
                    }
                    map.setOnMapClickListener { _, _ -> latestOnMapBlankClick() }
                }
                if (!initializedCamera && appliedCameraRequestId == cameraRequestId && lastCameraSnapshot != null) {
                    map.moveCamera(
                        CameraUpdate.scrollAndZoomTo(
                            LatLng(lastCameraSnapshot.center.latitude, lastCameraSnapshot.center.longitude),
                            lastCameraSnapshot.zoom,
                        ),
                    )
                    initializedCamera = true
                    handledCameraRequestId = cameraRequestId
                } else if (!initializedCamera || handledCameraRequestId != cameraRequestId) {
                    val baseUpdate = when (cameraTarget) {
                        is MapCameraTarget.Point -> CameraUpdate.scrollAndZoomTo(
                            LatLng(cameraTarget.point.latitude, cameraTarget.point.longitude),
                            cameraTarget.zoom,
                        )
                        is MapCameraTarget.Bounds -> {
                            val b = cameraTarget.bounds
                            if (b.southLatitude >= b.northLatitude || b.westLongitude >= b.eastLongitude || b.isNearlyPoint) {
                                CameraUpdate.scrollAndZoomTo(
                                    LatLng(b.center.latitude, b.center.longitude),
                                    SINGLE_RESULT_ZOOM,
                                )
                            } else {
                                CameraUpdate.fitBounds(
                                    LatLngBounds(
                                        LatLng(b.southLatitude, b.westLongitude),
                                        LatLng(b.northLatitude, b.eastLongitude),
                                    ),
                                    (48f * density).roundToInt(),
                                    (136f * density).roundToInt(),
                                    (48f * density).roundToInt(),
                                    (200f * density).roundToInt(),
                                )
                            }
                        }
                    }
                    val cameraUpdate = if (initializedCamera || cameraRequestId > 0L) {
                        baseUpdate.animate(CameraAnimation.Easing, 450)
                    } else {
                        baseUpdate
                    }
                    map.moveCamera(cameraUpdate)
                    initializedCamera = true
                    handledCameraRequestId = cameraRequestId
                    latestOnCameraRequestApplied(cameraRequestId)
                }
                map.locationOverlay.apply {
                    isVisible = currentLocation != null
                    currentLocation?.let { position = LatLng(it.latitude, it.longitude) }
                }
                val contentBounds = map.contentBounds
                val candidates = selectMapMarkerCandidates(benefits, contentBounds, selectedBenefitId)
                val diff = computeMarkerDiff(
                    renderedItems = renderedItems,
                    previousSelectedId = selectionState.lastSelectedId,
                    nextItems = candidates,
                    nextSelectedId = selectedBenefitId,
                )
                diff.toRemoveIds.forEach { id ->
                    markerPool.remove(id)?.map = null
                    renderedItems.remove(id)
                }
                diff.toUpdate.forEach { item ->
                    val existing = markerPool[item.id]
                    if (existing != null) {
                        applyMarkerAppearance(
                            marker = existing,
                            benefit = item,
                            isSelected = item.id == selectedBenefitId,
                            iconCache = iconCache,
                            context = context,
                        )
                        renderedItems[item.id] = item
                    }
                }
                diff.toAdd.forEach { item ->
                    val marker = Marker().apply {
                        applyMarkerAppearance(
                            marker = this,
                            benefit = item,
                            isSelected = item.id == selectedBenefitId,
                            iconCache = iconCache,
                            context = context,
                        )
                        setOnClickListener { latestOnSelect(item.id); true }
                        this.map = map
                    }
                    markerPool[item.id] = marker
                    renderedItems[item.id] = item
                }
                selectionState.lastSelectedId = selectedBenefitId
            }
        },
    )
}

private fun applyMarkerAppearance(
    marker: Marker,
    benefit: BenefitMapItem,
    isSelected: Boolean,
    iconCache: MutableMap<Pair<String, Boolean>, OverlayImage>,
    context: android.content.Context,
) {
    marker.position = LatLng(benefit.latitude, benefit.longitude)
    marker.icon = iconCache.getOrPut(benefit.category to isSelected) {
        createBenefitMarkerIcon(context, benefit.category, isSelected)
    }
    marker.anchor = PointF(0.5f, 1f)
    marker.captionText = benefit.name
    marker.captionMinZoom = if (isSelected) 0.0 else 14.0
    marker.captionTextSize = if (isSelected) 12f else 11f
    marker.isHideCollidedSymbols = true
    marker.isHideCollidedCaptions = !isSelected
    marker.zIndex = if (isSelected) 100 else 0
}

private fun selectMapMarkerCandidates(
    benefits: List<BenefitMapItem>,
    contentBounds: LatLngBounds,
    selectedBenefitId: String?,
): List<BenefitMapItem> = selectBoundedMarkerCandidates(
    benefits = benefits,
    selectedBenefitId = selectedBenefitId,
    maxMarkers = DEFAULT_MAX_RENDERED_MARKERS,
) { item ->
    contentBounds.contains(LatLng(item.latitude, item.longitude))
}

@Composable
private fun OfflineCoordinateMap(
    benefits: List<BenefitMapItem>,
    center: GeoPoint,
    currentLocation: GeoPoint?,
    selectedBenefitId: String?,
    onSelect: (String) -> Unit,
    onMapBlankClick: () -> Unit,
    modifier: Modifier,
) {
    val radius = with(LocalDensity.current) { 28.dp.toPx() }
    Box(modifier.background(PrimarySoft)) {
        Canvas(Modifier.fillMaxSize().pointerInput(benefits) {
            detectTapGestures { tap ->
                val hit = benefits.map { item -> item to mapPoint(item.latitude, item.longitude, size.width.toFloat(), size.height.toFloat()) }
                    .minByOrNull { (_, point) -> hypot(tap.x - point.x, tap.y - point.y) }
                    ?.takeIf { (_, point) -> hypot(tap.x - point.x, tap.y - point.y) <= radius }
                if (hit != null) onSelect(hit.first.id) else onMapBlankClick()
            }
        }) {
            drawRect(PrimarySoft)
            benefits.forEach { item ->
                val point = mapPoint(item.latitude, item.longitude, size.width, size.height)
                val accent = Color(categoryAccentColorInt(item.category))
                val isSelected = item.id == selectedBenefitId
                drawCircle(Color.White, if (isSelected) 16f else 12f, point)
                drawCircle(accent, if (isSelected) 11f else 8f, point)
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
            modifier = Modifier.align(Alignment.BottomStart).padding(12.dp),
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

package com.example.militarybenefits

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.example.militarybenefits.data.Benefit
import com.example.militarybenefits.data.BenefitDatabase
import com.example.militarybenefits.data.BenefitStatus
import com.example.militarybenefits.data.GeoPoint
import com.example.militarybenefits.data.LocalUser
import com.example.militarybenefits.data.MmaBenefitApi
import com.example.militarybenefits.data.SessionStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

enum class AppDestination { DISCOVER, SAVED, ACCOUNT, ADMIN }

class AppController(context: Context) {
    private val database = BenefitDatabase(context.applicationContext)
    private val session = SessionStore(context.applicationContext)

    var destination by mutableStateOf(AppDestination.DISCOVER)
    var benefits by mutableStateOf(database.allBenefits())
        private set
    var user by mutableStateOf(session.userId()?.let(database::user))
        private set
    var favoriteIds by mutableStateOf(user?.let { database.favoriteIds(it.id) }.orEmpty())
        private set
    var selectedBenefit by mutableStateOf<Benefit?>(null)
    var category by mutableStateOf("전체")
    var searchText by mutableStateOf("")
    var activeSearch by mutableStateOf("")
        private set
    var center by mutableStateOf(SEOUL_CENTER)
        private set
    var locationLabel by mutableStateOf("서울 전체")
        private set
    var currentLocation by mutableStateOf<GeoPoint?>(null)
        private set
    var transientMessage by mutableStateOf<String?>(null)
        private set
    var syncingMma by mutableStateOf(false)
        private set
    var lastSyncLabel by mutableStateOf("내장 수도권 DB")
        private set

    val categories: List<String>
        get() = listOf("전체") + benefits.map { it.category }.distinct().sorted()

    fun visibleBenefits(): List<Benefit> {
        val query = activeSearch.trim().lowercase()
        val presetCenter = destinationCenters[query]
        return benefits.asSequence()
            .filter { category == "전체" || it.category == category }
            .filter { benefit ->
                if (query.isBlank()) return@filter true
                val textual = listOfNotNull(
                    benefit.name, benefit.address, benefit.district, benefit.category,
                ).any { it.lowercase().contains(query) }
                val distance = presetCenter?.let { distanceKm(it, benefit) }
                val nearby = distance != null && distance <= 8.0
                textual || nearby
            }
            .sortedWith(compareBy<Benefit> { distanceKm(center, it) ?: Double.MAX_VALUE }.thenBy { it.name })
            .toList()
    }

    fun distanceFromCenter(benefit: Benefit): Double? = distanceKm(center, benefit)

    fun search(value: String = searchText) {
        val normalized = value.trim()
        searchText = normalized
        activeSearch = normalized
        val preset = destinationCenters[normalized.lowercase()]
        center = preset ?: SEOUL_CENTER
        locationLabel = normalized.ifBlank { "서울 전체" }
    }

    fun choosePreset(label: String) {
        searchText = label
        search(label)
    }

    fun applyCurrentLocation(point: GeoPoint) {
        currentLocation = point
        center = point
        activeSearch = ""
        searchText = ""
        locationLabel = "현재 위치 주변"
        transientMessage = "현재 위치를 기준으로 가까운 혜택부터 정렬했어요."
    }

    fun locationFailed(message: String) {
        transientMessage = message
    }

    fun clearMessage() {
        transientMessage = null
    }

    fun select(benefit: Benefit) {
        selectedBenefit = benefit
    }

    fun closeDetail() {
        selectedBenefit = null
    }

    fun toggleFavorite(benefit: Benefit) {
        val signedIn = user
        if (signedIn == null) {
            transientMessage = "찜을 저장하려면 먼저 로그인해 주세요."
            destination = AppDestination.ACCOUNT
            selectedBenefit = null
            return
        }
        database.toggleFavorite(signedIn.id, benefit.id)
        favoriteIds = database.favoriteIds(signedIn.id)
        transientMessage = if (benefit.id in favoriteIds) "찜에 저장했어요." else "찜에서 삭제했어요."
    }

    fun savedBenefits(): List<Benefit> = benefits.filter { it.id in favoriteIds }

    fun register(email: String, name: String, password: String): Result<LocalUser> =
        database.register(email, name, password).onSuccess(::completeLogin)

    fun login(email: String, password: String): Result<LocalUser> =
        database.login(email, password).onSuccess(::completeLogin)

    fun logout() {
        session.clear()
        user = null
        favoriteIds = emptySet()
        destination = AppDestination.DISCOVER
        transientMessage = "로그아웃했습니다."
    }

    fun saveBenefit(benefit: Benefit): Result<Unit> = runCatching {
        require(user?.isAdmin == true) { "관리자 권한이 필요합니다." }
        require(benefit.name.isNotBlank()) { "업소명을 입력해 주세요." }
        require(benefit.address.isNotBlank()) { "주소를 입력해 주세요." }
        require(benefit.benefitDescription.isNotBlank()) { "혜택 내용을 입력해 주세요." }
        if (database.benefit(benefit.id) == null) database.createBenefit(benefit)
        else database.updateBenefit(benefit)
        reload()
        transientMessage = "혜택 정보를 저장했습니다."
    }

    fun endBenefit(id: String) {
        if (user?.isAdmin != true) return
        database.endBenefit(id)
        reload()
        transientMessage = "혜택을 종료 상태로 변경했습니다."
    }

    suspend fun syncMmaApi(serviceKey: String) {
        if (serviceKey.isBlank() || syncingMma) return
        syncingMma = true
        runCatching {
            withContext(Dispatchers.IO) {
                val stores = MmaBenefitApi().fetchAll(serviceKey)
                val result = database.mergeMmaStores(stores)
                Triple(stores.size, result.first, result.second)
            }
        }.onSuccess { (total, added, matched) ->
            reload()
            lastSyncLabel = "나라사랑가게 API 동기화 완료"
            transientMessage = "나라사랑가게 ${total}건 확인 · 수도권 신규 ${added}건 · 기존 ${matched}건 연결"
        }.onFailure { error ->
            lastSyncLabel = "API 확인 실패 · 내장 DB 사용 중"
            transientMessage = error.message ?: "나라사랑가게 API를 확인하지 못했어요."
        }
        syncingMma = false
    }

    fun adminBenefits(): List<Benefit> = if (user?.isAdmin == true) database.allBenefits(true) else emptyList()

    private fun completeLogin(localUser: LocalUser) {
        session.save(localUser)
        user = localUser
        favoriteIds = database.favoriteIds(localUser.id)
        transientMessage = if (localUser.isAdmin) {
            "첫 계정이므로 이 기기의 관리자 권한이 부여됐어요."
        } else {
            "로그인했습니다."
        }
        destination = AppDestination.DISCOVER
    }

    private fun reload() {
        benefits = database.allBenefits(false)
    }

    companion object {
        val SEOUL_CENTER = GeoPoint(37.5665, 126.9780)
        val destinationCenters = mapOf(
            "홍대" to GeoPoint(37.5572, 126.9254),
            "홍대입구" to GeoPoint(37.5572, 126.9254),
            "성수" to GeoPoint(37.5446, 127.0559),
            "잠실" to GeoPoint(37.5133, 127.1001),
            "강남" to GeoPoint(37.4979, 127.0276),
            "강남역" to GeoPoint(37.4979, 127.0276),
            "신촌" to GeoPoint(37.5551, 126.9368),
            "건대" to GeoPoint(37.5404, 127.0692),
            "서울역" to GeoPoint(37.5547, 126.9707),
        )
    }
}

fun distanceKm(from: GeoPoint, benefit: Benefit): Double? {
    val latitude = benefit.latitude ?: return null
    val longitude = benefit.longitude ?: return null
    val earthRadius = 6371.0
    val latDelta = Math.toRadians(latitude - from.latitude)
    val lonDelta = Math.toRadians(longitude - from.longitude)
    val a = sin(latDelta / 2) * sin(latDelta / 2) +
        cos(Math.toRadians(from.latitude)) * cos(Math.toRadians(latitude)) *
        sin(lonDelta / 2) * sin(lonDelta / 2)
    return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a))
}

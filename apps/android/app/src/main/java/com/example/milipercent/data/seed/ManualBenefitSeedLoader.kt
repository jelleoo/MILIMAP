package com.example.milipercent.data.seed

import android.content.Context
import com.example.milipercent.data.local.BenefitEntity
import com.example.milipercent.data.local.BenefitLocalDataSource
import com.example.milipercent.data.local.BenefitSourceType
import com.example.milipercent.data.local.ManualBenefitStatus
import com.example.milipercent.model.BenefitDistrict
import java.net.URI
import java.text.ParsePosition
import java.text.SimpleDateFormat
import java.util.Locale
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json

private const val PRODUCTION_SEED_ASSET = "manual_benefits_seed.json"
private const val MANUAL_SEED_ID_PREFIX = "manual_seed_"

@Serializable
data class ManualBenefitSeedDocument(
    val items: List<ManualBenefitSeedItem>,
)

@Serializable
data class ManualBenefitSeedItem(
    val id: String,
    val name: String,
    val address: String,
    val district: String,
    val phone: String? = null,
    val benefitType: String? = null,
    val benefitDescription: String,
    val eligibleTarget: String? = null,
    val usageCondition: String? = null,
    val verificationMethod: String,
    val sourceUrl: String? = null,
    val lastVerifiedDate: String,
    val status: String,
)

fun interface ManualBenefitSeedJsonSource {
    fun readText(): String
}

class AssetManualBenefitSeedJsonSource(
    context: Context,
    private val assetName: String = PRODUCTION_SEED_ASSET,
) : ManualBenefitSeedJsonSource {
    private val assets = context.applicationContext.assets

    override fun readText(): String =
        assets.open(assetName).bufferedReader(Charsets.UTF_8).use { it.readText() }
}

class ManualBenefitSeedLoader(
    private val jsonSource: ManualBenefitSeedJsonSource,
    private val currentTimeMillis: () -> Long = System::currentTimeMillis,
    private val json: Json = Json {
        ignoreUnknownKeys = true
    },
) {
    fun loadAndValidate(): List<BenefitEntity> {
        val document = try {
            json.decodeFromString<ManualBenefitSeedDocument>(jsonSource.readText())
        } catch (exception: SerializationException) {
            throw ManualBenefitSeedValidationException("Seed JSON 형식이 올바르지 않습니다.", exception)
        }

        val normalizedItems = document.items.map { item ->
            item.copy(id = item.id.trim())
        }
        validateAll(normalizedItems)
        val syncedAt = currentTimeMillis()
        return normalizedItems.map { item -> item.toEntity(syncedAt) }
    }

    private fun validateAll(items: List<ManualBenefitSeedItem>) {
        val duplicatedIds = items.groupingBy { it.id }.eachCount().filterValues { it > 1 }.keys
        if (duplicatedIds.isNotEmpty()) {
            throw ManualBenefitSeedValidationException("Seed ID가 중복되었습니다.")
        }

        items.forEachIndexed { index, item ->
            val record = "Seed ${index + 1}번"
            validateRequired(item.id, "$record ID")
            if (!item.id.startsWith(MANUAL_SEED_ID_PREFIX)) {
                throw ManualBenefitSeedValidationException("$record ID prefix가 올바르지 않습니다.")
            }
            validateRequired(item.name, "$record 업체명")
            validateRequired(item.address, "$record 주소")
            if (item.district !in BenefitDistrict.seoulDistrictNames) {
                throw ManualBenefitSeedValidationException("$record 자치구가 서울 25개 구에 없습니다.")
            }
            validateRequired(item.benefitDescription, "$record 혜택 내용")
            validateRequired(item.verificationMethod, "$record 확인 방법")
            if (!isValidDate(item.lastVerifiedDate)) {
                throw ManualBenefitSeedValidationException("$record 최근 확인일 형식이 올바르지 않습니다.")
            }
            if (ManualBenefitStatus.fromStorage(item.status) == null) {
                throw ManualBenefitSeedValidationException("$record 상태 값이 올바르지 않습니다.")
            }
            if (!item.sourceUrl.isNullOrBlank() && !isHttpUrl(item.sourceUrl)) {
                throw ManualBenefitSeedValidationException("$record 출처 URL이 올바르지 않습니다.")
            }
        }
    }

    private fun ManualBenefitSeedItem.toEntity(syncedAt: Long) = BenefitEntity(
        id = id.trim(),
        sourceType = BenefitSourceType.MANUAL_SEED.name,
        sourceRowNumber = null,
        name = name.trim(),
        address = address.trim(),
        latitude = null,
        longitude = null,
        category = "기타",
        benefitType = benefitType.cleanOptional() ?: "할인·우대",
        benefitDescription = benefitDescription.trim(),
        phone = phone.cleanOptional(),
        eligibleTarget = eligibleTarget.cleanOptional(),
        usageCondition = usageCondition.cleanOptional(),
        verificationMethod = verificationMethod.trim(),
        sourceLabel = "검증된 내장 데이터",
        sourceUrl = sourceUrl.cleanOptional(),
        lastVerifiedAt = lastVerifiedDate,
        status = status,
        district = district,
        syncedAt = syncedAt,
    )
}

interface ManualSeedSynchronizer {
    suspend fun synchronize(): ManualSeedSyncResult
}

class RoomManualSeedSynchronizer(
    private val loader: ManualBenefitSeedLoader,
    private val localDataSource: BenefitLocalDataSource,
) : ManualSeedSynchronizer {
    override suspend fun synchronize(): ManualSeedSyncResult {
        // 전체 parsing/validation이 성공하기 전에는 Room을 변경하지 않는다.
        val entities = loader.loadAndValidate()
        localDataSource.replaceBenefits(
            sourceType = BenefitSourceType.MANUAL_SEED.name,
            benefits = entities,
        )
        val storedCount = localDataSource.countBenefits(
            BenefitSourceType.MANUAL_SEED.name,
        )
        if (storedCount != entities.size) {
            throw ManualBenefitSeedStorageException(
                expectedCount = entities.size,
                actualCount = storedCount,
            )
        }
        return ManualSeedSyncResult(storedCount)
    }
}

data class ManualSeedSyncResult(
    val storedCount: Int,
)

class ManualBenefitSeedValidationException(
    message: String,
    cause: Throwable? = null,
) : IllegalArgumentException(message, cause)

class ManualBenefitSeedStorageException(
    expectedCount: Int,
    actualCount: Int,
) : IllegalStateException(
    "MANUAL_SEED 저장 건수가 올바르지 않습니다. (예상: $expectedCount, 실제: $actualCount)",
)

internal fun validateRequired(value: String, label: String) {
    if (value.isBlank()) throw ManualBenefitSeedValidationException("$label 값이 비어 있습니다.")
}

internal fun isValidDate(value: String): Boolean {
    if (!DATE_PATTERN.matches(value)) return false
    val parser = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).apply { isLenient = false }
    val position = ParsePosition(0)
    return parser.parse(value, position) != null && position.index == value.length
}

internal fun isHttpUrl(value: String): Boolean = runCatching {
    val uri = URI(value)
    uri.scheme?.lowercase(Locale.ROOT) in setOf("http", "https") && !uri.host.isNullOrBlank()
}.getOrDefault(false)

internal fun String?.cleanOptional(): String? = this?.trim()?.takeIf { it.isNotEmpty() }

private val DATE_PATTERN = Regex("\\d{4}-\\d{2}-\\d{2}")

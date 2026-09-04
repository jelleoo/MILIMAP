package com.example.milipercent.data.seed

import android.content.Context
import com.example.milipercent.data.local.BenefitEntity
import com.example.milipercent.data.local.BenefitSourceType
import com.example.milipercent.data.local.ManualBenefitStatus
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json

fun interface SeedJsonSource {
    fun readText(): String
}

class AssetJsonSource(
    context: Context,
    private val assetName: String,
) : SeedJsonSource {
    private val assets = context.applicationContext.assets

    override fun readText(): String =
        assets.open(assetName).bufferedReader(Charsets.UTF_8).use { it.readText() }
}

fun interface BenefitSeedSource {
    fun loadAndValidate(): List<BenefitEntity>
}

@Serializable
data class LegacyBenefitSeedItem(
    val id: String,
    val name: String,
    val address: String,
    val latitude: Double?,
    val longitude: Double?,
    val category: String,
    val benefitType: String,
    val benefitDescription: String,
    val phone: String? = null,
    val eligibleTarget: String? = null,
    val usageCondition: String? = null,
    val verificationMethod: String,
    val sourceType: String,
    val sourceLabel: String,
    val sourceUrl: String,
    val lastVerifiedAt: String,
    val status: String,
    val district: String,
)

class LegacyBenefitSeedLoader(
    private val jsonSource: SeedJsonSource,
    private val currentTimeMillis: () -> Long = System::currentTimeMillis,
    private val json: Json = Json { ignoreUnknownKeys = true },
) : BenefitSeedSource {
    override fun loadAndValidate(): List<BenefitEntity> {
        val normalizedItems = try {
            json.decodeFromString<List<LegacyBenefitSeedItem>>(jsonSource.readText())
        } catch (exception: SerializationException) {
            throw LegacyBenefitSeedValidationException("Legacy seed JSON 형식이 올바르지 않습니다.", exception)
        }.map { item ->
            item.copy(
                id = item.id.trim(),
                name = item.name.trim(),
                address = item.address.trim(),
                category = item.category.trim(),
                benefitType = item.benefitType.trim(),
                benefitDescription = item.benefitDescription.trim(),
                verificationMethod = item.verificationMethod.trim(),
                sourceType = item.sourceType.trim(),
                sourceLabel = item.sourceLabel.trim(),
                sourceUrl = item.sourceUrl.trim(),
                lastVerifiedAt = item.lastVerifiedAt.trim(),
                status = item.status.trim(),
                district = item.district.trim(),
            )
        }
        validateAll(normalizedItems)
        val syncedAt = currentTimeMillis()
        return normalizedItems.map { item -> item.toEntity(syncedAt) }
    }

    private fun validateAll(items: List<LegacyBenefitSeedItem>) {
        if (items.groupingBy { it.id }.eachCount().any { (_, count) -> count > 1 }) {
            throw LegacyBenefitSeedValidationException("Legacy seed ID가 중복되었습니다.")
        }

        items.forEachIndexed { index, item ->
            val record = "Legacy seed ${index + 1}번"
            validateLegacyRequired(item.id, "$record ID")
            validateLegacyRequired(item.name, "$record 업체명")
            validateLegacyRequired(item.address, "$record 주소")
            validateLegacyRequired(item.category, "$record 분류")
            validateLegacyRequired(item.benefitType, "$record 혜택 유형")
            validateLegacyRequired(item.benefitDescription, "$record 혜택 내용")
            validateLegacyRequired(item.verificationMethod, "$record 확인 방법")
            validateLegacyRequired(item.sourceType, "$record 출처 유형")
            validateLegacyRequired(item.sourceLabel, "$record 출처 라벨")
            validateLegacyRequired(item.sourceUrl, "$record 출처 URL")
            validateLegacyRequired(item.lastVerifiedAt, "$record 최근 확인일")
            validateLegacyRequired(item.status, "$record 상태")
            validateLegacyRequired(item.district, "$record 자치구")
            if (BenefitSourceType.fromStorage(item.sourceType) == null) {
                throw LegacyBenefitSeedValidationException("$record 출처 유형 값이 올바르지 않습니다.")
            }
            if (ManualBenefitStatus.fromStorage(item.status) == null) {
                throw LegacyBenefitSeedValidationException("$record 상태 값이 올바르지 않습니다.")
            }
            if (!isValidDate(item.lastVerifiedAt)) {
                throw LegacyBenefitSeedValidationException("$record 최근 확인일 형식이 올바르지 않습니다.")
            }
            if (item.sourceUrl.split(" | ").any { url -> !isHttpUrl(url) }) {
                throw LegacyBenefitSeedValidationException("$record 출처 URL이 올바르지 않습니다.")
            }
            if (
                item.latitude == null ||
                item.longitude == null ||
                item.latitude !in -90.0..90.0 ||
                item.longitude !in -180.0..180.0
            ) {
                throw LegacyBenefitSeedValidationException("$record 좌표 범위가 올바르지 않습니다.")
            }
        }
    }

    private fun LegacyBenefitSeedItem.toEntity(syncedAt: Long) = BenefitEntity(
        id = id,
        sourceType = sourceType,
        sourceRowNumber = null,
        name = name,
        address = address,
        latitude = latitude,
        longitude = longitude,
        category = category,
        benefitType = benefitType,
        benefitDescription = benefitDescription,
        phone = phone.cleanOptional(),
        eligibleTarget = eligibleTarget.cleanOptional(),
        usageCondition = usageCondition.cleanOptional(),
        verificationMethod = verificationMethod,
        sourceLabel = sourceLabel,
        sourceUrl = sourceUrl,
        lastVerifiedAt = lastVerifiedAt,
        status = status,
        district = district,
        syncedAt = syncedAt,
    )
}

class LegacyBenefitSeedValidationException(
    message: String,
    cause: Throwable? = null,
) : IllegalArgumentException(message, cause)

private fun validateLegacyRequired(value: String, label: String) {
    if (value.isBlank()) throw LegacyBenefitSeedValidationException("$label 값이 비어 있습니다.")
}

package com.example.milipercent.data.manual

import com.example.milipercent.data.local.BenefitEntity
import com.example.milipercent.data.local.BenefitLocalDataSource
import com.example.milipercent.data.local.BenefitSourceType
import com.example.milipercent.data.local.ManualBenefitStatus
import com.example.milipercent.data.seed.cleanOptional
import com.example.milipercent.data.seed.isHttpUrl
import com.example.milipercent.data.seed.isValidDate
import com.example.milipercent.model.BenefitDistrict
import java.util.UUID
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

data class ManualBenefitInput(
    val name: String,
    val address: String,
    val district: BenefitDistrict,
    val phone: String? = null,
    val benefitType: String? = null,
    val benefitDescription: String,
    val eligibleTarget: String? = null,
    val usageCondition: String? = null,
    val verificationMethod: String,
    val sourceUrl: String? = null,
    val lastVerifiedDate: String,
    val status: ManualBenefitStatus,
)

data class ManualBenefitRecord(
    val id: String,
    val input: ManualBenefitInput,
)

interface ManualBenefitAdminRepository {
    fun observeAll(): Flow<List<ManualBenefitRecord>>

    fun observeById(id: String): Flow<ManualBenefitRecord?>

    suspend fun create(input: ManualBenefitInput): String

    suspend fun update(id: String, input: ManualBenefitInput)

    suspend fun delete(id: String): Boolean
}

class RoomManualBenefitAdminRepository(
    private val localDataSource: BenefitLocalDataSource,
    private val currentTimeMillis: () -> Long = System::currentTimeMillis,
    private val uuidFactory: () -> String = { UUID.randomUUID().toString() },
) : ManualBenefitAdminRepository {
    override fun observeAll(): Flow<List<ManualBenefitRecord>> =
        localDataSource.observeBenefits(BenefitSourceType.MANUAL_LOCAL.name)
            .map { entities -> entities.map(BenefitEntity::toManualRecord) }

    override fun observeById(id: String): Flow<ManualBenefitRecord?> =
        localDataSource.observeBenefitById(id).map { entity ->
            entity
                ?.takeIf { it.sourceType == BenefitSourceType.MANUAL_LOCAL.name }
                ?.toManualRecord()
        }

    override suspend fun create(input: ManualBenefitInput): String {
        validateManualBenefitInput(input)
        val id = "manual_local_${uuidFactory()}"
        localDataSource.upsertBenefit(input.toEntity(id, currentTimeMillis()))
        return id
    }

    override suspend fun update(id: String, input: ManualBenefitInput) {
        validateManualBenefitInput(input)
        require(id.startsWith("manual_local_")) { "MANUAL_LOCAL ID만 수정할 수 있습니다." }
        val current = localDataSource.observeBenefitById(id).first()
        require(current?.sourceType == BenefitSourceType.MANUAL_LOCAL.name) {
            "수정할 MANUAL_LOCAL 혜택을 찾을 수 없습니다."
        }
        localDataSource.upsertBenefit(input.toEntity(id, currentTimeMillis()))
    }

    override suspend fun delete(id: String): Boolean =
        localDataSource.deleteBenefit(id, BenefitSourceType.MANUAL_LOCAL.name)

    private fun ManualBenefitInput.toEntity(id: String, syncedAt: Long) = BenefitEntity(
        id = id,
        sourceType = BenefitSourceType.MANUAL_LOCAL.name,
        sourceRowNumber = null,
        name = name.trim(),
        address = address.trim(),
        phone = phone.cleanOptional(),
        benefitType = benefitType.cleanOptional(),
        district = requireNotNull(district.districtName),
        latitude = null,
        longitude = null,
        syncedAt = syncedAt,
        benefitDescription = benefitDescription.trim(),
        eligibleTarget = eligibleTarget.cleanOptional(),
        usageCondition = usageCondition.cleanOptional(),
        verificationMethod = verificationMethod.trim(),
        sourceUrl = sourceUrl.cleanOptional(),
        lastVerifiedDate = lastVerifiedDate,
        status = status.name,
    )
}

fun validateManualBenefitInput(input: ManualBenefitInput) {
    if (input.name.isBlank()) throw ManualBenefitInputException("업체명을 입력하세요.")
    if (input.address.isBlank()) throw ManualBenefitInputException("주소를 입력하세요.")
    if (input.district == BenefitDistrict.ALL) {
        throw ManualBenefitInputException("서울 자치구를 선택하세요.")
    }
    if (input.benefitDescription.isBlank()) {
        throw ManualBenefitInputException("혜택 내용을 입력하세요.")
    }
    if (input.verificationMethod.isBlank()) {
        throw ManualBenefitInputException("확인 방법을 입력하세요.")
    }
    if (!isValidDate(input.lastVerifiedDate)) {
        throw ManualBenefitInputException("최근 확인일을 YYYY-MM-DD 형식으로 입력하세요.")
    }
    if (!input.sourceUrl.isNullOrBlank() && !isHttpUrl(input.sourceUrl)) {
        throw ManualBenefitInputException("출처 URL은 http 또는 https 형식이어야 합니다.")
    }
}

private fun BenefitEntity.toManualRecord() = ManualBenefitRecord(
    id = id,
    input = ManualBenefitInput(
        name = name,
        address = address.orEmpty(),
        district = BenefitDistrict.seoulDistricts.firstOrNull { it.districtName == district }
            ?: BenefitDistrict.GANGNAM,
        phone = phone,
        benefitType = benefitType,
        benefitDescription = benefitDescription.orEmpty(),
        eligibleTarget = eligibleTarget,
        usageCondition = usageCondition,
        verificationMethod = verificationMethod.orEmpty(),
        sourceUrl = sourceUrl,
        lastVerifiedDate = lastVerifiedDate.orEmpty(),
        status = ManualBenefitStatus.fromStorage(status) ?: ManualBenefitStatus.NEEDS_VERIFICATION,
    ),
)

class ManualBenefitInputException(message: String) : IllegalArgumentException(message)

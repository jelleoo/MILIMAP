package com.example.milipercent.data.admin

import androidx.room.withTransaction
import com.example.milipercent.data.local.BenefitDatabase
import com.example.milipercent.data.local.BenefitEntity
import com.example.milipercent.data.local.BenefitSourceType
import com.example.milipercent.data.local.toDomain
import com.example.milipercent.model.Benefit
import com.example.milipercent.model.BenefitStatus
import java.util.UUID
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

data class AdminBenefitInput(
    val name: String,
    val address: String,
    val latitude: Double?,
    val longitude: Double?,
    val category: String,
    val benefitType: String,
    val benefitDescription: String,
    val phone: String?,
    val eligibleTarget: String?,
    val usageCondition: String?,
    val verificationMethod: String?,
    val sourceLabel: String,
    val sourceUrl: String?,
    val lastVerifiedAt: String?,
    val status: BenefitStatus,
    val district: String?,
)

interface AdminBenefitRepository {
    fun observeAll(): Flow<List<Benefit>>

    suspend fun create(input: AdminBenefitInput): String

    suspend fun update(id: String, input: AdminBenefitInput)

    suspend fun end(id: String)

    suspend fun deleteManual(id: String): Boolean
}

class RoomAdminBenefitRepository(
    private val database: BenefitDatabase,
    private val uuidFactory: () -> String = { UUID.randomUUID().toString() },
    private val currentTimeMillis: () -> Long = System::currentTimeMillis,
) : AdminBenefitRepository {
    override fun observeAll(): Flow<List<Benefit>> =
        database.benefitDao().observeAll().map { entities -> entities.map(BenefitEntity::toDomain) }

    override suspend fun create(input: AdminBenefitInput): String {
        validate(input)
        val id = "manual_local_${uuidFactory()}"
        database.benefitDao().insertAll(
            listOf(input.toEntity(id, currentTimeMillis(), BenefitSourceType.MANUAL_LOCAL.name)),
        )
        return id
    }

    override suspend fun update(id: String, input: AdminBenefitInput) {
        validate(input)
        database.withTransaction {
            val current = requireManual(id)
            database.benefitDao().insertAll(
                listOf(input.toEntity(current.id, current.syncedAt, current.sourceType)),
            )
        }
    }

    override suspend fun end(id: String) {
        database.withTransaction {
            val current = requireManual(id)
            database.benefitDao().insertAll(listOf(current.copy(status = BenefitStatus.ENDED.name)))
        }
    }

    override suspend fun deleteManual(id: String): Boolean =
        database.benefitDao().deleteByIdAndSource(id, BenefitSourceType.MANUAL_LOCAL.name) == 1

    private suspend fun requireManual(id: String): BenefitEntity {
        val current = requireNotNull(database.benefitDao().getByIdOnce(id)) {
            "수정할 수동 혜택을 찾을 수 없습니다."
        }
        require(current.sourceType == BenefitSourceType.MANUAL_LOCAL.name) {
            "MANUAL_LOCAL 혜택만 관리할 수 있습니다."
        }
        return current
    }

    private fun validate(input: AdminBenefitInput) {
        require(input.name.isNotBlank()) { "업체명을 입력하세요." }
        require(input.address.isNotBlank()) { "주소를 입력하세요." }
        require(input.category.isNotBlank()) { "카테고리를 입력하세요." }
        require(input.benefitType.isNotBlank()) { "혜택 유형을 입력하세요." }
        require(input.benefitDescription.isNotBlank()) { "혜택 내용을 입력하세요." }
        require(input.sourceLabel.isNotBlank()) { "출처를 입력하세요." }
    }

    private fun AdminBenefitInput.toEntity(id: String, syncedAt: Long, sourceType: String) = BenefitEntity(
        id = id,
        sourceType = sourceType,
        sourceRowNumber = null,
        name = name.trim(),
        address = address.trim(),
        latitude = latitude,
        longitude = longitude,
        category = category.trim(),
        benefitType = benefitType.trim(),
        benefitDescription = benefitDescription.trim(),
        phone = phone.trimmedOrNull(),
        eligibleTarget = eligibleTarget.trimmedOrNull(),
        usageCondition = usageCondition.trimmedOrNull(),
        verificationMethod = verificationMethod.trimmedOrNull(),
        sourceLabel = sourceLabel.trim(),
        sourceUrl = sourceUrl.trimmedOrNull(),
        lastVerifiedAt = lastVerifiedAt.trimmedOrNull(),
        status = status.name,
        district = district.trimmedOrNull(),
        syncedAt = syncedAt,
    )

    private fun String?.trimmedOrNull(): String? = this?.trim()?.takeIf(String::isNotEmpty)
}

package com.example.milipercent.data.seed

import androidx.room.withTransaction
import com.example.milipercent.data.local.BenefitDatabase
import com.example.milipercent.data.local.BenefitEntity
import com.example.milipercent.data.local.SeedStateEntity
import java.util.Locale

const val BUNDLED_SEED_NAME = "benefits"
const val BUNDLED_SEED_VERSION = 1
private const val BUNDLED_SEED_EXPECTED_COUNT = 496

data class BundledSeedSyncResult(
    val installed: Boolean,
    val storedCount: Int,
)

interface BundledSeedInstaller {
    suspend fun synchronizeIfNeeded(): BundledSeedSyncResult
}

class BundledSeedSynchronizer(
    private val database: BenefitDatabase,
    private val sources: List<BenefitSeedSource>,
    private val currentTimeMillis: () -> Long = System::currentTimeMillis,
) : BundledSeedInstaller {
    override suspend fun synchronizeIfNeeded(): BundledSeedSyncResult {
        // 모든 입력은 transaction 진입 전에 parsing과 validation을 끝낸다.
        val entities = sources.flatMap { source -> source.loadAndValidate() }
        require(entities.size == BUNDLED_SEED_EXPECTED_COUNT) {
            "내장 seed 건수가 올바르지 않습니다. (예상: $BUNDLED_SEED_EXPECTED_COUNT, 실제: ${entities.size})"
        }

        return database.withTransaction {
            val benefitDao = database.benefitDao()
            val seedStateDao = database.seedStateDao()
            if (seedStateDao.version(BUNDLED_SEED_NAME) == BUNDLED_SEED_VERSION) {
                return@withTransaction BundledSeedSyncResult(
                    installed = false,
                    storedCount = benefitDao.countAll(),
                )
            }

            validateCombinedEntities(entities)
            benefitDao.insertAll(entities)
            seedStateDao.upsert(
                SeedStateEntity(
                    name = BUNDLED_SEED_NAME,
                    version = BUNDLED_SEED_VERSION,
                    installedAt = currentTimeMillis(),
                ),
            )
            val storedCount = benefitDao.countAll()
            check(storedCount == BUNDLED_SEED_EXPECTED_COUNT) {
                "내장 seed 저장 건수가 올바르지 않습니다. (예상: $BUNDLED_SEED_EXPECTED_COUNT, 실제: $storedCount)"
            }
            BundledSeedSyncResult(installed = true, storedCount = storedCount)
        }
    }

    private fun validateCombinedEntities(entities: List<BenefitEntity>) {
        if (entities.groupingBy { entity -> entity.id.trim() }.eachCount().any { (_, count) -> count > 1 }) {
            throw BundledSeedValidationException("내장 seed ID가 중복되었습니다.")
        }
        if (normalizedDuplicateCount(entities) != 0) {
            throw BundledSeedValidationException("내장 seed 업체명과 주소가 중복되었습니다.")
        }
    }
}

internal fun normalizedDuplicateCount(benefits: List<BenefitEntity>): Int = benefits
    .groupingBy { benefit ->
        listOf(benefit.name, benefit.address)
            .joinToString("\u0000") { value -> normalizeIdentityPart(value) }
    }
    .eachCount()
    .values
    .sumOf { count -> (count - 1).coerceAtLeast(0) }

private fun normalizeIdentityPart(value: String): String = value
    .trim()
    .replace(Regex("\\s+"), "")
    .lowercase(Locale.ROOT)

class BundledSeedValidationException(message: String) : IllegalArgumentException(message)

package com.example.milipercent.data.seed

import androidx.room.withTransaction
import com.example.milipercent.data.local.BenefitDatabase
import com.example.milipercent.data.local.BenefitEntity
import com.example.milipercent.data.local.BenefitSourceType
import com.example.milipercent.data.local.SeedStateEntity
import java.util.Locale
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

const val BUNDLED_SEED_NAME = "benefits"
const val BUNDLED_SEED_VERSION = 14
private val BUNDLED_SEED_SOURCE_TYPES = listOf(
    BenefitSourceType.LOCAL_GOV.name,
    BenefitSourceType.MANUAL_SEED.name,
    BenefitSourceType.PUBLIC_EVIDENCE.name,
)

data class BundledSeedSyncResult(
    val installed: Boolean,
    val storedCount: Int,
)

interface BundledSeedInstaller {
    suspend fun synchronizeIfNeeded(): BundledSeedSyncResult
}

internal interface BundledSeedTransactionScope {
    suspend fun seedVersion(name: String): Int?

    suspend fun countAllBenefits(): Int

    suspend fun countBundledSeedRows(bundledSourceTypes: List<String>): Int

    suspend fun deleteRetiredBundledSeedRows(
        bundledSourceTypes: List<String>,
        retainedIds: List<String>,
    )

    suspend fun upsertAllBenefits(benefits: List<BenefitEntity>)

    suspend fun upsertSeedState(state: SeedStateEntity)
}

internal interface BundledSeedStore {
    suspend fun seedVersion(name: String): Int?

    suspend fun countAllBenefits(): Int

    suspend fun <T> inTransaction(block: suspend BundledSeedTransactionScope.() -> T): T
}

private class RoomBundledSeedStore(
    private val database: BenefitDatabase,
) : BundledSeedStore {
    override suspend fun seedVersion(name: String): Int? = database.seedStateDao().version(name)

    override suspend fun countAllBenefits(): Int = database.benefitDao().countAll()

    override suspend fun <T> inTransaction(block: suspend BundledSeedTransactionScope.() -> T): T =
        database.withTransaction {
            val benefitDao = database.benefitDao()
            val seedStateDao = database.seedStateDao()
            val scope = object : BundledSeedTransactionScope {
                override suspend fun seedVersion(name: String): Int? = seedStateDao.version(name)

                override suspend fun countAllBenefits(): Int = benefitDao.countAll()

                override suspend fun countBundledSeedRows(bundledSourceTypes: List<String>): Int =
                    benefitDao.countBundledSeedRows(bundledSourceTypes)

                override suspend fun deleteRetiredBundledSeedRows(
                    bundledSourceTypes: List<String>,
                    retainedIds: List<String>,
                ) = benefitDao.deleteRetiredBundledSeedRows(bundledSourceTypes, retainedIds)

                override suspend fun upsertAllBenefits(benefits: List<BenefitEntity>) =
                    benefitDao.upsertAll(benefits)

                override suspend fun upsertSeedState(state: SeedStateEntity) =
                    seedStateDao.upsert(state)
            }
            scope.block()
        }
}

class BundledSeedSynchronizer internal constructor(
    private val store: BundledSeedStore,
    private val manifestSource: SeedJsonSource,
    private val legacySeedSource: SeedJsonSource,
    private val manualSeedSource: SeedJsonSource,
    private val currentTimeMillis: () -> Long = System::currentTimeMillis,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
) : BundledSeedInstaller {
    constructor(
        database: BenefitDatabase,
        manifestSource: SeedJsonSource,
        legacySeedSource: SeedJsonSource,
        manualSeedSource: SeedJsonSource,
        currentTimeMillis: () -> Long = System::currentTimeMillis,
        ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
    ) : this(
        store = RoomBundledSeedStore(database),
        manifestSource = manifestSource,
        legacySeedSource = legacySeedSource,
        manualSeedSource = manualSeedSource,
        currentTimeMillis = currentTimeMillis,
        ioDispatcher = ioDispatcher,
    )

    private data class PreparedBundledSeed(
        val manifest: BundledSeedManifest,
        val entities: List<BenefitEntity>,
        val expectedTotalCount: Int,
    )

    override suspend fun synchronizeIfNeeded(): BundledSeedSyncResult {
        val manifest = withContext(ioDispatcher) {
            BundledSeedManifestLoader(manifestSource).loadAndValidate()
        }
        val installedBeforeLoad = store.seedVersion(manifest.seedName)
        if (installedBeforeLoad != null && installedBeforeLoad >= manifest.seedVersion) {
            return BundledSeedSyncResult(
                installed = false,
                storedCount = store.countAllBenefits(),
            )
        }

        // 모든 입력은 transaction 진입 전에 IO 스레드에서 단일 읽기, checksum, parsing과 validation을 끝낸다.
        val prepared = withContext(ioDispatcher) { prepareBundledSeed(manifest) }
        val entities = prepared.entities
        val expectedTotalCount = prepared.expectedTotalCount

        return store.inTransaction {
            val installedVersion = seedVersion(manifest.seedName)
            if (installedVersion != null && installedVersion >= manifest.seedVersion) {
                return@inTransaction BundledSeedSyncResult(
                    installed = false,
                    storedCount = countAllBenefits(),
                )
            }

            deleteRetiredBundledSeedRows(
                bundledSourceTypes = BUNDLED_SEED_SOURCE_TYPES,
                retainedIds = entities.map(BenefitEntity::id),
            )
            upsertAllBenefits(entities)
            upsertSeedState(
                SeedStateEntity(
                    name = manifest.seedName,
                    version = manifest.seedVersion,
                    installedAt = currentTimeMillis(),
                ),
            )
            val bundledStoredCount = countBundledSeedRows(BUNDLED_SEED_SOURCE_TYPES)
            check(bundledStoredCount == expectedTotalCount) {
                "내장 seed 저장 건수가 올바르지 않습니다. (예상: $expectedTotalCount, 실제: $bundledStoredCount)"
            }
            BundledSeedSyncResult(installed = true, storedCount = countAllBenefits())
        }
    }

    private fun prepareBundledSeed(manifest: BundledSeedManifest): PreparedBundledSeed {

        val legacyRawText = legacySeedSource.readText()
        val actualSeedSha256 = sha256LfUtf8(legacyRawText)
        if (actualSeedSha256 != manifest.seedSha256) {
            throw BundledSeedValidationException(
                "내장 seed SHA-256 checksum이 manifest와 일치하지 않습니다.",
            )
        }

        val manualRawText = manualSeedSource.readText()
        val actualManualSha256 = sha256LfUtf8(manualRawText)
        if (actualManualSha256 != manifest.manualSeedSha256) {
            throw BundledSeedValidationException(
                "내장 manual seed SHA-256 checksum이 manifest와 일치하지 않습니다.",
            )
        }

        val legacyEntities = LegacyBenefitSeedLoader(
            jsonSource = SeedJsonSource { legacyRawText },
            currentTimeMillis = currentTimeMillis,
        ).loadAndValidate()
        if (legacyEntities.size != manifest.totalCount) {
            throw BundledSeedValidationException(
                "내장 seed 건수가 manifest와 일치하지 않습니다. (예상: ${manifest.totalCount}, 실제: ${legacyEntities.size})",
            )
        }
        val actualExactPins = legacyEntities.count { it.latitude != null && it.longitude != null }
        val actualUnconfirmed = legacyEntities.count { it.latitude == null && it.longitude == null }
        if (actualExactPins != manifest.exactPinCount ||
            actualUnconfirmed != manifest.unconfirmedCoordinateCount
        ) {
            throw BundledSeedValidationException(
                "내장 seed 지도 핀 건수가 manifest와 일치하지 않습니다. " +
                    "(예상: ${manifest.exactPinCount}/${manifest.unconfirmedCoordinateCount}, " +
                    "실제: $actualExactPins/$actualUnconfirmed)",
            )
        }

        val manualEntities = ManualBenefitSeedLoader(
            jsonSource = SeedJsonSource { manualRawText },
            currentTimeMillis = currentTimeMillis,
        ).loadAndValidate()
        if (manualEntities.size != manifest.manualSeedCount) {
            throw BundledSeedValidationException(
                "내장 manual seed 건수가 manifest와 일치하지 않습니다. (예상: ${manifest.manualSeedCount}, 실제: ${manualEntities.size})",
            )
        }

        val entities = legacyEntities + manualEntities
        val expectedTotalCount = manifest.totalCount + manifest.manualSeedCount
        validateCombinedEntities(entities)
        return PreparedBundledSeed(
            manifest = manifest,
            entities = entities,
            expectedTotalCount = expectedTotalCount,
        )
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
    .replace(WHITESPACE_REGEX, "")
    .lowercase(Locale.ROOT)

private val WHITESPACE_REGEX = Regex("\\s+")

class BundledSeedValidationException(message: String) : IllegalArgumentException(message)

package com.example.milipercent.data.seed

import com.example.milipercent.data.local.BenefitEntity
import com.example.milipercent.data.local.BenefitSourceType
import com.example.milipercent.data.local.SeedStateEntity
import java.util.concurrent.Executors
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class BundledSeedSynchronizerUnitTest {
    @Test
    fun `하드코딩 건수 없이 동적 건수 시드를 설치하고 버전 업그레이드 시 퇴출 행만 정리한다`() = runBlocking {
        val mma = entity("mma_1", BenefitSourceType.MMA_API, sourceRowNumber = 10)
        val local = entity("manual_local_1", BenefitSourceType.MANUAL_LOCAL, sourceRowNumber = null)
        val store = FakeBundledSeedStore(initialBenefits = listOf(mma, local))

        val legacyV1 = legacySeedJson(
            legacyItem(id = "seed-1", name = "업체1", address = "서울특별시 마포구 테스트로 1", latitude = 37.5, longitude = 127.0),
            legacyItem(id = "seed-retired", name = "은퇴업체", address = "서울특별시 마포구 테스트로 2", latitude = null, longitude = null),
        )
        val manualV1 = """{"items":[]}"""
        val manifestV1 = buildManifestJson(
            seedVersion = 1,
            legacyText = legacyV1,
            manualText = manualV1,
            totalCount = 2,
            exactPinCount = 1,
            unconfirmedCoordinateCount = 1,
            manualSeedCount = 0,
        )

        val syncV1 = synchronizer(store, manifestV1, legacyV1, manualV1)
        val resV1 = syncV1.synchronizeIfNeeded()

        assertTrue(resV1.installed)
        assertEquals(4, resV1.storedCount)
        assertEquals(1, store.seedStateVersion(BUNDLED_SEED_NAME))
        assertEquals(1, store.transactionCount)

        // 동일 버전 재실행 시 idempotent skip
        val secondV1 = syncV1.synchronizeIfNeeded()
        assertFalse(secondV1.installed)
        assertEquals(4, secondV1.storedCount)

        // v2: 3건 legacy(2 핀 + 1 미확정, retired 삭제) + 1건 manual seed
        val legacyV2 = legacySeedJson(
            legacyItem(id = "seed-1", name = "업체1", address = "서울특별시 마포구 테스트로 1", latitude = 37.5, longitude = 127.0),
            legacyItem(id = "seed-2", name = "업체2", address = "서울특별시 용산구 테스트로 3", latitude = 37.53, longitude = 126.99),
            legacyItem(id = "seed-3", name = "업체3", address = "경기도 파주시 테스트로 4", latitude = null, longitude = null),
        )
        val manualV2 = """
            {
              "items": [
                {
                  "id": "manual_seed_1",
                  "name": "수동업체",
                  "address": "서울특별시 강남구 테스트로 5",
                  "district": "강남구",
                  "benefitDescription": "15% 할인",
                  "verificationMethod": "공식 확인",
                  "sourceUrl": "https://example.com/manual",
                  "lastVerifiedDate": "2026-10-01",
                  "status": "ACTIVE"
                }
              ]
            }
        """.trimIndent()
        val manifestV2 = buildManifestJson(
            seedVersion = 2,
            legacyText = legacyV2,
            manualText = manualV2,
            totalCount = 3,
            exactPinCount = 2,
            unconfirmedCoordinateCount = 1,
            manualSeedCount = 1,
        )

        val resV2 = synchronizer(store, manifestV2, legacyV2, manualV2).synchronizeIfNeeded()
        assertTrue(resV2.installed)
        assertEquals(6, resV2.storedCount)
        assertEquals(2, store.seedStateVersion(BUNDLED_SEED_NAME))
        assertNull(store.findById("seed-retired"))
        assertEquals(mma, store.findById("mma_1"))
        assertEquals(local, store.findById("manual_local_1"))
        assertEquals("수동업체", store.findById("manual_seed_1")?.name)
    }

    @Test
    fun `이미 설치된 seedVersion이 manifest보다 높으면 downgrade를 건너뛴다`() = runBlocking {
        val store = FakeBundledSeedStore(
            initialBenefits = listOf(entity("seed-existing", BenefitSourceType.LOCAL_GOV, sourceRowNumber = null)),
            initialStates = listOf(SeedStateEntity(name = BUNDLED_SEED_NAME, version = 8, installedAt = 10L)),
        )
        val legacy = legacySeedJson(legacyItem(id = "seed-1", name = "업체1", address = "서울특별시 마포구 테스트로 1", latitude = null, longitude = null))
        val manual = """{"items":[]}"""
        val manifest = buildManifestJson(
            seedVersion = 7,
            legacyText = legacy,
            manualText = manual,
            totalCount = 1,
            exactPinCount = 0,
            unconfirmedCoordinateCount = 1,
            manualSeedCount = 0,
        )

        val result = synchronizer(store, manifest, legacy, manual).synchronizeIfNeeded()

        assertFalse(result.installed)
        assertEquals(1, result.storedCount)
        assertEquals(8, store.seedStateVersion(BUNDLED_SEED_NAME))
        assertNull(store.findById("seed-1"))
    }

    @Test
    fun `checksum 건수 핀수 중복 검증 실패는 transaction 진입 전에 fail-closed 처리한다`() {
        val validLegacy = legacySeedJson(
            legacyItem(id = "seed-1", name = "업체1", address = "서울특별시 마포구 테스트로 1", latitude = 37.5, longitude = 127.0),
        )
        val validManual = """{"items":[]}"""
        val validManifest = buildManifestJson(
            seedVersion = 1,
            legacyText = validLegacy,
            manualText = validManual,
            totalCount = 1,
            exactPinCount = 1,
            unconfirmedCoordinateCount = 0,
            manualSeedCount = 0,
        )

        val cases = listOf(
            // manifest 손상
            Triple("{bad-json", validLegacy, validManual) to BundledSeedManifestValidationException::class.java,
            // legacy seed sha256 불일치
            Triple(
                validManifest,
                validLegacy.replace("업체1", "변조업체"),
                validManual,
            ) to BundledSeedValidationException::class.java,
            // manual seed sha256 불일치
            Triple(
                validManifest,
                validLegacy,
                """{ "items" : [] }""",
            ) to BundledSeedValidationException::class.java,
            // totalCount 불일치 (해시는 맞췄으나 건수 조작)
            Triple(
                buildManifestJson(1, validLegacy, validManual, totalCount = 2, exactPinCount = 2, unconfirmedCoordinateCount = 0, manualSeedCount = 0),
                validLegacy,
                validManual,
            ) to BundledSeedValidationException::class.java,
            // exactPinCount 불일치 (해시는 맞췄으나 핀 수 조작)
            Triple(
                buildManifestJson(1, validLegacy, validManual, totalCount = 1, exactPinCount = 0, unconfirmedCoordinateCount = 1, manualSeedCount = 0),
                validLegacy,
                validManual,
            ) to BundledSeedValidationException::class.java,
            // manualSeedCount 불일치 (해시는 맞췄으나 수동 시드 건수 조작)
            Triple(
                buildManifestJson(1, validLegacy, validManual, totalCount = 1, exactPinCount = 1, unconfirmedCoordinateCount = 0, manualSeedCount = 1),
                validLegacy,
                validManual,
            ) to BundledSeedValidationException::class.java,
        )

        cases.forEach { (inputs, expectedException) ->
            val store = FakeBundledSeedStore()
            val sync = synchronizer(store, inputs.first, inputs.second, inputs.third)
            assertThrows(expectedException) {
                runBlocking { sync.synchronizeIfNeeded() }
            }
            assertEquals(0, store.transactionCount)
        }

        // legacy + manual 사이 ID 중복 및 (업체명, 주소) 중복도 transaction 전에 거부한다
        val dupIdLegacy = legacySeedJson(
            legacyItem(id = "manual_seed_dup", name = "업체A", address = "서울특별시 마포구 테스트로 10", latitude = null, longitude = null),
        )
        val dupIdManual = """
            {
              "items": [
                {
                  "id": "manual_seed_dup",
                  "name": "다른업체",
                  "address": "서울특별시 강동구 테스트로 20",
                  "district": "강동구",
                  "benefitDescription": "10% 할인",
                  "verificationMethod": "공식 확인",
                  "sourceUrl": "https://example.com/a",
                  "lastVerifiedDate": "2026-10-01",
                  "status": "ACTIVE"
                }
              ]
            }
        """.trimIndent()
        val dupIdManifest = buildManifestJson(1, dupIdLegacy, dupIdManual, totalCount = 1, exactPinCount = 0, unconfirmedCoordinateCount = 1, manualSeedCount = 1)
        val dupIdStore = FakeBundledSeedStore()
        assertThrows(BundledSeedValidationException::class.java) {
            runBlocking { synchronizer(dupIdStore, dupIdManifest, dupIdLegacy, dupIdManual).synchronizeIfNeeded() }
        }
        assertEquals(0, dupIdStore.transactionCount)

        val dupBizLegacy = legacySeedJson(
            legacyItem(id = "seed-a", name = "테스트 상호", address = "서울특별시 마포구 테스트로 99", latitude = null, longitude = null),
        )
        val dupBizManual = """
            {
              "items": [
                {
                  "id": "manual_seed_b",
                  "name": "테스트상호",
                  "address": "서울특별시 마포구 테스트로 99",
                  "district": "마포구",
                  "benefitDescription": "10% 할인",
                  "verificationMethod": "공식 확인",
                  "sourceUrl": "https://example.com/b",
                  "lastVerifiedDate": "2026-10-01",
                  "status": "ACTIVE"
                }
              ]
            }
        """.trimIndent()
        val dupBizManifest = buildManifestJson(1, dupBizLegacy, dupBizManual, totalCount = 1, exactPinCount = 0, unconfirmedCoordinateCount = 1, manualSeedCount = 1)
        val dupBizStore = FakeBundledSeedStore()
        assertThrows(BundledSeedValidationException::class.java) {
            runBlocking { synchronizer(dupBizStore, dupBizManifest, dupBizLegacy, dupBizManual).synchronizeIfNeeded() }
        }
        assertEquals(0, dupBizStore.transactionCount)
    }

    @Test
    fun `저장 후 bundled 건수가 일치하지 않으면 예외를 발생시킨다`() {
        val store = FakeBundledSeedStore(bundledCountOverride = 999)
        val legacy = legacySeedJson(
            legacyItem(id = "seed-1", name = "업체1", address = "서울특별시 마포구 테스트로 1", latitude = null, longitude = null),
        )
        val manual = """{"items":[]}"""
        val manifest = buildManifestJson(1, legacy, manual, totalCount = 1, exactPinCount = 0, unconfirmedCoordinateCount = 1, manualSeedCount = 0)

        assertThrows(IllegalStateException::class.java) {
            runBlocking { synchronizer(store, manifest, legacy, manual).synchronizeIfNeeded() }
        }
        assertEquals(1, store.transactionCount)
    }

    @Test
    fun `single-read 보장은 각 입력 소스를 1회만 읽는다`() {
        var manifestReads = 0
        var legacyReads = 0
        var manualReads = 0
        val legacy = legacySeedJson(
            legacyItem(id = "seed-1", name = "업체1", address = "서울특별시 마포구 테스트로 1", latitude = null, longitude = null),
        )
        val manual = """{"items":[]}"""
        val manifest = buildManifestJson(1, legacy, manual, totalCount = 1, exactPinCount = 0, unconfirmedCoordinateCount = 1, manualSeedCount = 0)
        val store = FakeBundledSeedStore()

        val result = runBlocking {
            BundledSeedSynchronizer(
                store = store,
                manifestSource = SeedJsonSource { manifestReads++; manifest },
                legacySeedSource = SeedJsonSource { legacyReads++; legacy },
                manualSeedSource = SeedJsonSource { manualReads++; manual },
                currentTimeMillis = { 500L },
            ).synchronizeIfNeeded()
        }

        assertTrue(result.installed)
        assertEquals(1, manifestReads)
        assertEquals(1, legacyReads)
        assertEquals(1, manualReads)
    }

    @Test
    fun `이미 설치된 버전이 최신이면 시드 본문을 읽거나 쓰기 트랜잭션을 열지 않고 건너뛴다`() {
        var manifestReads = 0
        var legacyReads = 0
        var manualReads = 0
        val legacy = legacySeedJson(
            legacyItem(id = "seed-1", name = "업체1", address = "서울특별시 마포구 테스트로 1", latitude = null, longitude = null),
        )
        val manual = """{"items":[]}"""
        val manifest = buildManifestJson(
            seedVersion = 5,
            legacyText = legacy,
            manualText = manual,
            totalCount = 1,
            exactPinCount = 0,
            unconfirmedCoordinateCount = 1,
            manualSeedCount = 0,
        )
        val store = FakeBundledSeedStore(
            initialBenefits = listOf(entity("seed-1", BenefitSourceType.LOCAL_GOV, sourceRowNumber = null)),
            initialStates = listOf(SeedStateEntity(name = BUNDLED_SEED_NAME, version = 5, installedAt = 10L)),
        )

        val result = runBlocking {
            BundledSeedSynchronizer(
                store = store,
                manifestSource = SeedJsonSource { manifestReads++; manifest },
                legacySeedSource = SeedJsonSource { legacyReads++; legacy },
                manualSeedSource = SeedJsonSource { manualReads++; manual },
                currentTimeMillis = { 500L },
            ).synchronizeIfNeeded()
        }

        assertFalse(result.installed)
        assertEquals(1, result.storedCount)
        assertEquals(1, manifestReads)
        assertEquals(0, legacyReads)
        assertEquals(0, manualReads)
        assertEquals(0, store.transactionCount)
    }

    @Test
    fun `시드 읽기와 무결성 검증은 주입된 ioDispatcher에서 실행된다`() {
        val observedThreads = mutableSetOf<String>()
        val legacy = legacySeedJson(
            legacyItem(id = "seed-1", name = "업체1", address = "서울특별시 마포구 테스트로 1", latitude = null, longitude = null),
        )
        val manual = """{"items":[]}"""
        val manifest = buildManifestJson(1, legacy, manual, totalCount = 1, exactPinCount = 0, unconfirmedCoordinateCount = 1, manualSeedCount = 0)
        val store = FakeBundledSeedStore()
        val callerThread = Thread.currentThread().name
        val executor = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "seed-io-worker")
        }
        val dispatcher = executor.asCoroutineDispatcher()

        try {
            val result = runBlocking {
                BundledSeedSynchronizer(
                    store = store,
                    manifestSource = SeedJsonSource { observedThreads += Thread.currentThread().name; manifest },
                    legacySeedSource = SeedJsonSource { observedThreads += Thread.currentThread().name; legacy },
                    manualSeedSource = SeedJsonSource { observedThreads += Thread.currentThread().name; manual },
                    currentTimeMillis = { 500L },
                    ioDispatcher = dispatcher,
                ).synchronizeIfNeeded()
            }

            assertTrue(result.installed)
            assertEquals(1, observedThreads.size)
            assertTrue(observedThreads.all { it.startsWith("seed-io-worker") })
            assertTrue(!callerThread.startsWith("seed-io-worker"))
        } finally {
            executor.shutdownNow()
        }
    }

    private fun synchronizer(
        store: FakeBundledSeedStore,
        manifestJson: String,
        legacyJson: String,
        manualJson: String,
    ) = BundledSeedSynchronizer(
        store = store,
        manifestSource = SeedJsonSource { manifestJson },
        legacySeedSource = SeedJsonSource { legacyJson },
        manualSeedSource = SeedJsonSource { manualJson },
        currentTimeMillis = { 123L },
    )

    private fun buildManifestJson(
        seedVersion: Int,
        legacyText: String,
        manualText: String,
        totalCount: Int,
        exactPinCount: Int,
        unconfirmedCoordinateCount: Int,
        manualSeedCount: Int,
    ): String {
        val seedSha = sha256LfUtf8(legacyText)
        val manualSha = sha256LfUtf8(manualText)
        return """
            {
              "manifestVersion": 1,
              "seedName": "benefits",
              "seedVersion": $seedVersion,
              "hashAlgorithm": "$BUNDLED_SEED_HASH_ALGORITHM",
              "generatedAt": "2026-11-19T12:00:00+09:00",
              "canonicalCsvSha256": "${"a".repeat(64)}",
              "totalCount": $totalCount,
              "exactPinCount": $exactPinCount,
              "unconfirmedCoordinateCount": $unconfirmedCoordinateCount,
              "seedSha256": "$seedSha",
              "manualSeedCount": $manualSeedCount,
              "manualSeedSha256": "$manualSha"
            }
        """.trimIndent()
    }

    private fun legacySeedJson(vararg items: String) = "[${items.joinToString(",")}]"

    private fun legacyItem(
        id: String,
        name: String,
        address: String,
        latitude: Double?,
        longitude: Double?,
    ) = """
        {
          "id": "$id",
          "name": "$name",
          "address": "$address",
          "latitude": ${latitude ?: "null"},
          "longitude": ${longitude ?: "null"},
          "category": "음식",
          "benefitType": "할인·우대",
          "benefitDescription": "10% 할인",
          "verificationMethod": "지자체 확인",
          "sourceType": "LOCAL_GOV",
          "sourceLabel": "지자체 공식 자료 · 최신 확인",
          "sourceUrl": "https://city.example.go.kr/$id",
          "lastVerifiedAt": "2026-10-01",
          "status": "ACTIVE",
          "district": "마포구"
        }
    """.trimIndent()

    private fun entity(
        id: String,
        sourceType: BenefitSourceType,
        sourceRowNumber: Int?,
    ) = BenefitEntity(
        id = id,
        sourceType = sourceType.name,
        sourceRowNumber = sourceRowNumber,
        name = id,
        address = "서울특별시 마포구",
        latitude = null,
        longitude = null,
        category = "기타",
        benefitType = "할인·우대",
        benefitDescription = "혜택",
        phone = null,
        eligibleTarget = null,
        usageCondition = null,
        verificationMethod = "확인",
        sourceLabel = "출처",
        sourceUrl = "https://example.com/$id",
        lastVerifiedAt = "2026-10-01",
        status = "ACTIVE",
        district = "마포구",
        syncedAt = 1L,
    )

    private class FakeBundledSeedStore(
        initialBenefits: List<BenefitEntity> = emptyList(),
        initialStates: List<SeedStateEntity> = emptyList(),
        private val bundledCountOverride: Int? = null,
    ) : BundledSeedStore {
        private val benefits = initialBenefits.associateBy(BenefitEntity::id).toMutableMap()
        private val seedStates = initialStates.associateBy(SeedStateEntity::name).toMutableMap()
        var transactionCount: Int = 0
            private set

        fun seedStateVersion(name: String): Int? = seedStates[name]?.version

        fun findById(id: String): BenefitEntity? = benefits[id]

        override suspend fun seedVersion(name: String): Int? = seedStates[name]?.version

        override suspend fun countAllBenefits(): Int = benefits.size

        override suspend fun <T> inTransaction(block: suspend BundledSeedTransactionScope.() -> T): T {
            transactionCount += 1
            val scope = object : BundledSeedTransactionScope {
                override suspend fun seedVersion(name: String): Int? = seedStates[name]?.version

                override suspend fun countAllBenefits(): Int = benefits.size

                override suspend fun countBundledSeedRows(bundledSourceTypes: List<String>): Int =
                    bundledCountOverride ?: benefits.values.count {
                        it.sourceRowNumber == null && it.sourceType in bundledSourceTypes
                    }

                override suspend fun deleteRetiredBundledSeedRows(
                    bundledSourceTypes: List<String>,
                    retainedIds: List<String>,
                ) {
                    val retainedSet = retainedIds.toSet()
                    val toDelete = benefits.values
                        .filter {
                            it.sourceRowNumber == null &&
                                it.sourceType in bundledSourceTypes &&
                                it.id !in retainedSet
                        }
                        .map(BenefitEntity::id)
                    toDelete.forEach(benefits::remove)
                }

                override suspend fun upsertAllBenefits(benefits: List<BenefitEntity>) {
                    benefits.forEach { entity -> this@FakeBundledSeedStore.benefits[entity.id] = entity }
                }

                override suspend fun upsertSeedState(state: SeedStateEntity) {
                    seedStates[state.name] = state
                }
            }
            return scope.block()
        }
    }
}

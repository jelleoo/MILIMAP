package com.example.milipercent.data.seed

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class BundledSeedManifestLoaderTest {
    @Test
    fun `정상 manifest를 로드하고 검증한다`() {
        val manifest = BundledSeedManifestLoader(SeedJsonSource { manifestJson() }).loadAndValidate()

        assertEquals(1, manifest.manifestVersion)
        assertEquals(BUNDLED_SEED_NAME, manifest.seedName)
        assertEquals(7, manifest.seedVersion)
        assertEquals(BUNDLED_SEED_HASH_ALGORITHM, manifest.hashAlgorithm)
        assertEquals(249, manifest.totalCount)
        assertEquals(111, manifest.exactPinCount)
        assertEquals(138, manifest.unconfirmedCoordinateCount)
        assertEquals(0, manifest.manualSeedCount)
    }

    @Test
    fun `CRLF LF CR과 UTF-8 BOM 차이에 관계없이 동일한 SHA-256-LF-UTF8 해시를 생성한다`() {
        val lf = "{\"a\":1}\n{\"b\":2}\n"
        val crlf = "{\"a\":1}\r\n{\"b\":2}\r\n"
        val cr = "{\"a\":1}\r{\"b\":2}\r"
        val bomCrlf = "\uFEFF$crlf"

        val expected = sha256LfUtf8(lf)
        assertEquals(expected, sha256LfUtf8(crlf))
        assertEquals(expected, sha256LfUtf8(cr))
        assertEquals(expected, sha256LfUtf8(bomCrlf))
        assertEquals(64, expected.length)
    }

    @Test
    fun `ISO-8601 offset 검증은 유효한 offset 날짜만 허용한다`() {
        assertTrue(isValidIso8601WithOffset("2026-09-10T00:00:00+09:00"))
        assertTrue(isValidIso8601WithOffset("2026-11-19T12:34:56Z"))
        assertTrue(isValidIso8601WithOffset("2024-02-29T23:59:59.123456-05:00"))

        assertFalse(isValidIso8601WithOffset("2026-09-10T00:00:00"))
        assertFalse(isValidIso8601WithOffset("2026-02-30T00:00:00Z"))
        assertFalse(isValidIso8601WithOffset("2026-09-10T24:00:00Z"))
        assertFalse(isValidIso8601WithOffset("2026-09-10T00:00:00+14:30"))
        assertFalse(isValidIso8601WithOffset(" 2026-09-10T00:00:00Z"))
    }

    @Test
    fun `유효하지 않은 manifest 필드는 fail-closed 거부한다`() {
        val invalidManifests = listOf(
            "{broken",
            manifestJson(manifestVersion = 2),
            manifestJson(seedName = "other"),
            manifestJson(seedVersion = 0),
            manifestJson(hashAlgorithm = "SHA-256"),
            manifestJson(generatedAt = "2026-09-10T00:00:00"),
            manifestJson(generatedAt = "2026-02-30T00:00:00+09:00"),
            manifestJson(canonicalCsvSha256 = "abcd"),
            manifestJson(seedSha256 = "A".repeat(64)),
            manifestJson(manualSeedSha256 = "z".repeat(64)),
            manifestJson(totalCount = 0, exactPinCount = 0, unconfirmedCoordinateCount = 0),
            manifestJson(exactPinCount = -1),
            manifestJson(unconfirmedCoordinateCount = -1),
            manifestJson(exactPinCount = 100, unconfirmedCoordinateCount = 100),
            manifestJson(manualSeedCount = -1),
        )

        invalidManifests.forEach { raw ->
            assertThrows(BundledSeedManifestValidationException::class.java) {
                BundledSeedManifestLoader(SeedJsonSource { raw }).loadAndValidate()
            }
        }
    }

    @Test
    fun `커밋된 Android assets 시드 파일들이 manifest와 정확히 일치한다`() {
        val assetsDir = resolveAssetsDir()
        val manifestText = File(assetsDir, "benefits.seed.manifest.json").readText(Charsets.UTF_8)
        val legacyRaw = File(assetsDir, "benefits.seed.json").readText(Charsets.UTF_8)
        val manualRaw = File(assetsDir, "manual_benefits_seed.json").readText(Charsets.UTF_8)

        val manifest = BundledSeedManifestLoader(SeedJsonSource { manifestText }).loadAndValidate()
        val legacyEntities = LegacyBenefitSeedLoader(SeedJsonSource { legacyRaw }).loadAndValidate()
        val manualEntities = ManualBenefitSeedLoader(SeedJsonSource { manualRaw }).loadAndValidate()

        assertEquals(BUNDLED_SEED_VERSION, manifest.seedVersion)
        assertEquals(sha256LfUtf8(legacyRaw), manifest.seedSha256)
        assertEquals(sha256LfUtf8(manualRaw), manifest.manualSeedSha256)
        assertEquals(manifest.totalCount, legacyEntities.size)
        assertEquals(manifest.exactPinCount, legacyEntities.count { it.latitude != null && it.longitude != null })
        assertEquals(manifest.unconfirmedCoordinateCount, legacyEntities.count { it.latitude == null && it.longitude == null })
        assertEquals(manifest.manualSeedCount, manualEntities.size)
    }

    private fun resolveAssetsDir(): File = listOf(
        File("src/main/assets"),
        File("app/src/main/assets"),
        File("apps/android/app/src/main/assets"),
    ).first { it.isDirectory }

    private fun manifestJson(
        manifestVersion: Int = 1,
        seedName: String = "benefits",
        seedVersion: Int = 7,
        hashAlgorithm: String = BUNDLED_SEED_HASH_ALGORITHM,
        generatedAt: String = "2026-09-10T00:00:00+09:00",
        canonicalCsvSha256: String = "a".repeat(64),
        totalCount: Int = 249,
        exactPinCount: Int = 111,
        unconfirmedCoordinateCount: Int = 138,
        seedSha256: String = "b".repeat(64),
        manualSeedCount: Int = 0,
        manualSeedSha256: String = "c".repeat(64),
    ) = """
        {
          "manifestVersion": $manifestVersion,
          "seedName": "$seedName",
          "seedVersion": $seedVersion,
          "hashAlgorithm": "$hashAlgorithm",
          "generatedAt": "$generatedAt",
          "canonicalCsvSha256": "$canonicalCsvSha256",
          "totalCount": $totalCount,
          "exactPinCount": $exactPinCount,
          "unconfirmedCoordinateCount": $unconfirmedCoordinateCount,
          "seedSha256": "$seedSha256",
          "manualSeedCount": $manualSeedCount,
          "manualSeedSha256": "$manualSeedSha256"
        }
    """.trimIndent()
}

package com.example.milipercent.data.seed

import java.nio.ByteBuffer
import java.nio.CharBuffer
import java.nio.charset.CodingErrorAction
import java.security.MessageDigest
import java.util.Locale
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json

const val BUNDLED_SEED_MANIFEST_VERSION = 1
const val BUNDLED_SEED_HASH_ALGORITHM = "SHA-256-LF-UTF8"

@Serializable
data class BundledSeedManifest(
    val manifestVersion: Int,
    val seedName: String,
    val seedVersion: Int,
    val hashAlgorithm: String,
    val generatedAt: String,
    val canonicalCsvSha256: String,
    val totalCount: Int,
    val exactPinCount: Int,
    val unconfirmedCoordinateCount: Int,
    val seedSha256: String,
    val manualSeedCount: Int,
    val manualSeedSha256: String,
)

class BundledSeedManifestLoader(
    private val jsonSource: SeedJsonSource,
    private val json: Json = Json { ignoreUnknownKeys = true },
) {
    fun loadAndValidate(): BundledSeedManifest {
        val manifest = try {
            json.decodeFromString<BundledSeedManifest>(jsonSource.readText())
        } catch (exception: SerializationException) {
            throw BundledSeedManifestValidationException(
                "Seed manifest JSON 형식이 올바르지 않습니다.",
                exception,
            )
        }
        validate(manifest)
        return manifest
    }

    private fun validate(manifest: BundledSeedManifest) {
        if (manifest.manifestVersion != BUNDLED_SEED_MANIFEST_VERSION) {
            throw BundledSeedManifestValidationException(
                "지원하지 않는 manifestVersion 입니다: ${manifest.manifestVersion}",
            )
        }
        if (manifest.seedName != BUNDLED_SEED_NAME) {
            throw BundledSeedManifestValidationException(
                "올바르지 않은 seedName 입니다: ${manifest.seedName}",
            )
        }
        if (manifest.seedVersion < 1) {
            throw BundledSeedManifestValidationException(
                "seedVersion은 1 이상이어야 합니다: ${manifest.seedVersion}",
            )
        }
        if (manifest.hashAlgorithm != BUNDLED_SEED_HASH_ALGORITHM) {
            throw BundledSeedManifestValidationException(
                "지원하지 않는 hashAlgorithm 입니다: ${manifest.hashAlgorithm}",
            )
        }
        if (!isValidIso8601WithOffset(manifest.generatedAt)) {
            throw BundledSeedManifestValidationException(
                "generatedAt 형식이 올바르지 않습니다: ${manifest.generatedAt}",
            )
        }
        validateSha256Hex(manifest.canonicalCsvSha256, "canonicalCsvSha256")
        validateSha256Hex(manifest.seedSha256, "seedSha256")
        validateSha256Hex(manifest.manualSeedSha256, "manualSeedSha256")
        if (manifest.totalCount < 1) {
            throw BundledSeedManifestValidationException(
                "totalCount는 1 이상이어야 합니다: ${manifest.totalCount}",
            )
        }
        if (manifest.exactPinCount < 0 || manifest.unconfirmedCoordinateCount < 0) {
            throw BundledSeedManifestValidationException("좌표 건수는 0 미만일 수 없습니다.")
        }
        if (
            manifest.exactPinCount.toLong() + manifest.unconfirmedCoordinateCount.toLong() !=
            manifest.totalCount.toLong()
        ) {
            throw BundledSeedManifestValidationException(
                "exactPinCount + unconfirmedCoordinateCount 합계가 totalCount와 일치하지 않습니다.",
            )
        }
        if (manifest.manualSeedCount < 0) {
            throw BundledSeedManifestValidationException(
                "manualSeedCount는 0 이상이어야 합니다: ${manifest.manualSeedCount}",
            )
        }
    }
}

internal fun sha256LfUtf8(text: String): String {
    val digest = MessageDigest.getInstance("SHA-256")
    val startIndex = if (text.startsWith("\uFEFF")) 1 else 0
    val charArray = CharArray(8192)
    val charBuffer = CharBuffer.wrap(charArray)
    val byteArray = ByteArray(8192 * 3)
    val byteBuffer = ByteBuffer.wrap(byteArray)
    val encoder = Charsets.UTF_8.newEncoder()
        .onMalformedInput(CodingErrorAction.REPLACE)
        .onUnmappableCharacter(CodingErrorAction.REPLACE)

    var bufferedChars = 0
    var i = startIndex
    val length = text.length
    while (i < length) {
        val ch = text[i]
        val normalized = if (ch == '\r') {
            if (i + 1 < length && text[i + 1] == '\n') {
                i += 1
            }
            '\n'
        } else {
            ch
        }
        charArray[bufferedChars++] = normalized
        i += 1
        if (bufferedChars == charArray.size) {
            flushUtf8Chunk(charBuffer, byteBuffer, byteArray, bufferedChars, endOfInput = false, encoder, digest)
            bufferedChars = 0
        }
    }
    flushUtf8Chunk(charBuffer, byteBuffer, byteArray, bufferedChars, endOfInput = true, encoder, digest)

    return digest.digest().joinToString(separator = "") { byte ->
        "%02x".format(Locale.ROOT, byte.toInt() and 0xFF)
    }
}

private fun flushUtf8Chunk(
    charBuffer: CharBuffer,
    byteBuffer: ByteBuffer,
    byteArray: ByteArray,
    charCount: Int,
    endOfInput: Boolean,
    encoder: java.nio.charset.CharsetEncoder,
    digest: MessageDigest,
) {
    charBuffer.limit(charCount)
    charBuffer.position(0)
    while (true) {
        byteBuffer.clear()
        val result = encoder.encode(charBuffer, byteBuffer, endOfInput)
        val written = byteBuffer.position()
        if (written > 0) {
            digest.update(byteArray, 0, written)
        }
        if (result.isOverflow) continue
        break
    }
    if (endOfInput) {
        while (true) {
            byteBuffer.clear()
            val flushResult = encoder.flush(byteBuffer)
            val written = byteBuffer.position()
            if (written > 0) {
                digest.update(byteArray, 0, written)
            }
            if (flushResult.isOverflow) continue
            break
        }
    }
}

internal fun isValidIso8601WithOffset(value: String): Boolean {
    if (value.isBlank() || value != value.trim()) return false
    val match = ISO8601_OFFSET_PATTERN.matchEntire(value) ?: return false
    val datePart = match.groupValues[1]
    if (!isValidDate(datePart)) return false
    val hour = match.groupValues[2].toIntOrNull() ?: return false
    val minute = match.groupValues[3].toIntOrNull() ?: return false
    val second = match.groupValues[4].toIntOrNull() ?: return false
    if (hour !in 0..23 || minute !in 0..59 || second !in 0..59) return false
    val offset = match.groupValues[5]
    if (offset == "Z") return true
    val offsetHour = match.groupValues[6].toIntOrNull() ?: return false
    val offsetMinute = match.groupValues[7].toIntOrNull() ?: return false
    if (offsetMinute !in 0..59 || offsetHour !in 0..14) return false
    if (offsetHour == 14 && offsetMinute != 0) return false
    return true
}

private fun validateSha256Hex(value: String, fieldName: String) {
    if (!SHA256_HEX_PATTERN.matches(value)) {
        throw BundledSeedManifestValidationException("$fieldName 값이 올바른 SHA-256 hex가 아닙니다.")
    }
}

class BundledSeedManifestValidationException(
    message: String,
    cause: Throwable? = null,
) : IllegalArgumentException(message, cause)

private val SHA256_HEX_PATTERN = Regex("^[0-9a-f]{64}$")
private val ISO8601_OFFSET_PATTERN =
    Regex("^(\\d{4}-\\d{2}-\\d{2})T(\\d{2}):(\\d{2}):(\\d{2})(?:\\.\\d{1,9})?(Z|[+-](\\d{2}):(\\d{2}))$")

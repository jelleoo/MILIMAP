package com.example.milipercent.data.seed

import com.example.milipercent.data.local.BenefitSourceType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class LegacyBenefitSeedLoaderTest {
    @Test
    fun `정상 legacy 시드는 보존된 필드를 entity로 변환한다`() {
        val benefits = loader(seedJson(item())).loadAndValidate()

        assertEquals(1, benefits.size)
        assertEquals("legacy_1", benefits.single().id)
        assertEquals(BenefitSourceType.LOCAL_GOV.name, benefits.single().sourceType)
        assertEquals(37.5, benefits.single().latitude)
        assertEquals(127.0, benefits.single().longitude)
    }

    @Test
    fun `필수값 enum 날짜 URL 좌표와 trim 중복 ID를 거부한다`() {
        val invalidSeeds = listOf(
            seedJson(item(name = "  ")),
            seedJson(item(sourceType = "UNKNOWN")),
            seedJson(item(status = "UNKNOWN")),
            seedJson(item(date = "2026-02-30")),
            seedJson(item(sourceUrl = "https://example.com/ok | ftp://example.com/bad")),
            seedJson(item(latitude = 90.1)),
            seedJson(item(), item(id = " legacy_1 ")),
        )

        invalidSeeds.forEach { seed ->
            assertThrows(LegacyBenefitSeedValidationException::class.java) {
                loader(seed).loadAndValidate()
            }
        }
    }

    private fun loader(seed: String) = LegacyBenefitSeedLoader(
        jsonSource = SeedJsonSource { seed },
        currentTimeMillis = { 123L },
    )

    private fun seedJson(vararg items: String) = "[${items.joinToString()}]"

    private fun item(
        id: String = "legacy_1",
        name: String = "테스트 업체",
        sourceType: String = "LOCAL_GOV",
        status: String = "ACTIVE",
        date: String = "2026-08-17",
        sourceUrl: String = "https://example.com/source",
        latitude: Double = 37.5,
        longitude: Double = 127.0,
    ) = """
        {
          "id":"$id",
          "name":"$name",
          "address":"서울특별시 마포구 테스트로 1",
          "latitude":$latitude,
          "longitude":$longitude,
          "category":"기타",
          "benefitType":"할인",
          "benefitDescription":"테스트 혜택",
          "verificationMethod":"테스트 확인",
          "sourceType":"$sourceType",
          "sourceLabel":"테스트 출처",
          "sourceUrl":"$sourceUrl",
          "lastVerifiedAt":"$date",
          "status":"$status",
          "district":"마포구"
        }
    """.trimIndent()
}

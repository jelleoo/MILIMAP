package com.example.milipercent.data.local

import com.example.milipercent.model.Benefit
import com.example.milipercent.model.BenefitStatus
import org.junit.Assert.assertEquals
import org.junit.Test

class BenefitMappersTest {
    @Test
    fun `domain benefit retains every field through Room entity round trip`() {
        val benefit = Benefit(
            id = "benefit-99",
            name = "전체 필드 매장",
            address = "서울특별시 마포구 월드컵로 99",
            latitude = 37.5665,
            longitude = 126.9780,
            category = "문화",
            benefitType = "10% 할인",
            benefitDescription = "현장 결제 시 할인",
            phone = "02-1234-5678",
            eligibleTarget = "병역의무자",
            usageCondition = "신분증 제시",
            verificationMethod = "전화 확인",
            sourceType = BenefitSourceType.LOCAL_GOV,
            sourceLabel = "마포구청",
            sourceUrl = "https://example.com/benefit/99",
            lastVerifiedAt = "2026-09-04",
            status = BenefitStatus.ACTIVE,
            district = "마포구",
        )

        assertEquals(benefit, benefit.toEntity(99L).toDomain())
    }

    @Test
    fun `unknown stored status defaults to needs verification`() {
        val entity = Benefit(
            id = "unknown-status",
            name = "상태 확인 매장",
            address = "서울특별시 강남구 테헤란로 1",
            latitude = null,
            longitude = null,
            category = "기타",
            benefitType = "할인·우대",
            benefitDescription = "업소 확인 필요",
            phone = null,
            eligibleTarget = null,
            usageCondition = null,
            verificationMethod = null,
            sourceType = BenefitSourceType.MMA_API,
            sourceLabel = "병무청 나라사랑가게 API",
            sourceUrl = null,
            lastVerifiedAt = null,
            status = BenefitStatus.NEEDS_VERIFICATION,
            district = "강남구",
        ).toEntity(1L).copy(status = "RETIRED")

        assertEquals(BenefitStatus.NEEDS_VERIFICATION, entity.toDomain().status)
    }
}

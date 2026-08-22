package com.example.milipercent.analysis

import com.example.milipercent.model.Benefit
import com.example.milipercent.model.BenefitCollection
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BenefitAnalyzerTest {
    @Test
    fun `서울 주소 판단과 자치구 추출은 공백 유무를 무시한다`() {
        assertTrue(BenefitAnalyzer.isSeoulAddress("서울특별시 마포구 월드컵로 1"))
        assertEquals(
            "마포구",
            BenefitAnalyzer.extractSeoulDistrict("서울특별시마포구월드컵로1"),
        )
        assertEquals(
            "강남구",
            BenefitAnalyzer.extractSeoulDistrict("서울시 강남구 테헤란로 1"),
        )
        assertFalse(BenefitAnalyzer.isSeoulAddress("경기도 성남시 분당구"))
        assertFalse(BenefitAnalyzer.isSeoulAddress(null))
        assertFalse(BenefitAnalyzer.isSeoulAddress("   "))
        assertNull(BenefitAnalyzer.extractSeoulDistrict("경기도 성남시 분당구"))
    }

    @Test
    fun `서울 목록과 품질 분포 및 중복을 한 번에 분석한다`() {
        val collection = BenefitCollection(
            benefits = listOf(
                benefit(1, " 같은 가게 ", "서울특별시 마포구 월드컵로 1", null, "할인"),
                benefit(2, "같은가게", "서울특별시마포구월드컵로1", "02-111-1111", "할인"),
                benefit(3, "강남점", "서울시 강남구 테헤란로 1", "02-222-2222", "우대"),
                benefit(4, "", "서울특별시 알수없는동 1", null, null),
                benefit(5, "경기점", "경기도 성남시 분당구", "031-111-1111", "할인"),
                benefit(6, "주소없음", null, null, null),
            ),
            apiTotalCount = 6,
            pageSize = 100,
            totalPages = 1,
        )

        val result = BenefitAnalyzer.analyze(collection)

        assertEquals(6, result.collectedCount)
        assertEquals(4, result.seoulBenefits.size)
        assertEquals(DataQuality(1, 3, 1), result.allDataQuality)
        assertEquals(DataQuality(0, 2, 1), result.seoulDataQuality)
        assertEquals(2, result.districtCounts.getValue("마포구"))
        assertEquals(1, result.districtCounts.getValue("강남구"))
        assertEquals(1, result.unclassifiedDistrictCount)
        assertEquals(DuplicateAnalysis(1, 1), result.duplicateAnalysis)
        assertEquals(3, result.allBenefitTypeCounts.getValue("할인"))
        assertEquals(2, result.allBenefitTypeCounts.getValue("(없음)"))
        assertEquals(2, result.seoulBenefitTypeCounts.getValue("할인"))
    }

    private fun benefit(
        id: Int,
        name: String,
        address: String?,
        phone: String?,
        benefitType: String?,
    ) = Benefit(id, name, address, phone, benefitType)
}

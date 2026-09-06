package com.example.milipercent.ui

import com.example.milipercent.model.BenefitDistrict
import com.example.milipercent.model.BenefitUiModel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BenefitDistrictStateTest {
    @Test
    fun `전체 외에 서울 25개 자치구 선택값을 제공한다`() {
        assertEquals(25, BenefitDistrict.seoulDistricts.size)
        assertEquals(25, BenefitDistrict.seoulDistrictNames.distinct().size)
    }

    @Test
    fun `초기 전체 선택은 모든 서울 혜택을 반환한다`() {
        val benefits = testBenefits()
        val state = BenefitDistrictState()

        state.updateBenefits(benefits)

        assertEquals(BenefitDistrict.ALL, state.selectedDistrict)
        assertEquals(benefits, state.filteredBenefits)
        assertEquals(benefits.size, state.districtCounts.getValue(BenefitDistrict.ALL))
    }

    @Test
    fun `강남구와 마포구 선택은 해당 district만 반환한다`() {
        val state = BenefitDistrictState().apply { updateBenefits(testBenefits()) }

        state.selectDistrict(BenefitDistrict.GANGNAM)
        assertEquals(2, state.filteredBenefits.size)
        assertTrue(state.filteredBenefits.all { it.district == "강남구" })

        state.selectDistrict(BenefitDistrict.MAPO)
        assertEquals(1, state.filteredBenefits.size)
        assertTrue(state.filteredBenefits.all { it.district == "마포구" })
    }

    @Test
    fun `전체 count는 25개 district count 합계와 같다`() {
        val counts = BenefitDistrictFilter.calculateCounts(testBenefits())
        val districtSum = BenefitDistrict.seoulDistricts.sumOf(counts::getValue)

        assertEquals(counts.getValue(BenefitDistrict.ALL), districtSum)
    }

    @Test
    fun `Room 데이터가 갱신되어도 선택한 마포구를 유지한다`() {
        val state = BenefitDistrictState().apply { updateBenefits(testBenefits()) }
        state.selectDistrict(BenefitDistrict.MAPO)
        state.updateSearchQuery("롯데시네마")

        state.updateBenefits(
            testBenefits() + benefit(
                id = "mapo-new",
                district = "마포구",
                name = "롯데시네마 합정점",
            ),
        )

        assertEquals(BenefitDistrict.MAPO, state.selectedDistrict)
        assertEquals("롯데시네마", state.searchQuery)
        assertEquals(2, state.filteredBenefits.size)
        assertTrue(state.filteredBenefits.all { it.district == "마포구" })
    }

    @Test
    fun `빈 검색어는 현재 district 결과를 그대로 반환한다`() {
        val state = BenefitDistrictState().apply { updateBenefits(testBenefits()) }
        state.selectDistrict(BenefitDistrict.GANGNAM)

        state.updateSearchQuery("   ")

        assertEquals(2, state.filteredBenefits.size)
        assertTrue(state.filteredBenefits.all { it.district == "강남구" })
    }

    @Test
    fun `업체명은 공백과 대소문자 차이를 무시해 검색한다`() {
        val benefits = testBenefits() + benefit(
            id = "english",
            district = "종로구",
            name = "Mili Store",
        )
        val state = BenefitDistrictState().apply { updateBenefits(benefits) }

        state.updateSearchQuery("롯데 시네마")
        assertEquals(2, state.filteredBenefits.size)

        state.updateSearchQuery("mili store")
        assertEquals(listOf("english"), state.filteredBenefits.map { it.id })
    }

    @Test
    fun `공백 없는 주소에서도 주소 키워드를 검색한다`() {
        val state = BenefitDistrictState().apply { updateBenefits(testBenefits()) }

        state.updateSearchQuery("강남구")

        assertEquals(2, state.filteredBenefits.size)
        assertTrue(state.filteredBenefits.all { it.district == "강남구" })
    }

    @Test
    fun `null 주소는 검색 중 안전하게 처리한다`() {
        val state = BenefitDistrictState().apply { updateBenefits(testBenefits()) }

        state.updateSearchQuery("존재하지않는주소")

        assertTrue(state.filteredBenefits.isEmpty())
    }

    @Test
    fun `district와 검색어를 함께 적용한다`() {
        val state = BenefitDistrictState().apply { updateBenefits(testBenefits()) }
        state.selectDistrict(BenefitDistrict.GANGNAM)

        state.updateSearchQuery("치과")

        assertEquals(listOf("gangnam-2"), state.filteredBenefits.map { it.id })
    }

    @Test
    fun `검색어 clear는 현재 district 전체 목록으로 복귀한다`() {
        val state = BenefitDistrictState().apply { updateBenefits(testBenefits()) }
        state.selectDistrict(BenefitDistrict.MAPO)
        state.updateSearchQuery("롯데")

        state.clearSearchQuery()

        assertEquals("", state.searchQuery)
        assertEquals(1, state.filteredBenefits.size)
        assertTrue(state.filteredBenefits.all { it.district == "마포구" })
    }

    private fun testBenefits() = listOf(
        benefit(
            id = "gangnam-1",
            district = "강남구",
            name = "롯데시네마 도곡",
            address = "서울특별시강남구테헤란로1",
        ),
        benefit(
            id = "gangnam-2",
            district = "강남구",
            name = "행복 치과",
            address = "서울특별시 강남구 선릉로 2",
        ),
        benefit(
            id = "mapo-1",
            district = "마포구",
            name = "롯데시네마 홍대입구",
            address = "서울특별시 마포구 홍대로 3",
        ),
        benefit(
            id = "seodaemun-1",
            district = "서대문구",
            name = "주소 없는 가게",
            address = null,
        ),
    )

    private fun benefit(
        id: String,
        district: String,
        name: String = "$district 가게",
        address: String? = "서울특별시 $district",
    ) = BenefitUiModel(
        id = id,
        name = name,
        address = address,
        phone = null,
        benefitType = "할인",
        district = district,
        latitude = null,
        longitude = null,
    )
}

package com.example.milipercent.ui

import com.example.milipercent.data.local.MMA_SOURCE_TYPE
import com.example.milipercent.data.local.BenefitSourceType
import com.example.milipercent.model.BenefitDetail
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BenefitDetailUiStateTest {
    @Test
    fun `Room 상세 데이터를 Success 표시 값으로 변환한다`() {
        val state = createBenefitDetailUiState(detail())

        assertTrue(state is BenefitDetailUiState.Success)
        val success = state as BenefitDetailUiState.Success
        assertEquals("테스트 가게", success.benefit.name)
        assertEquals("할인", success.benefit.benefitType)
        assertEquals("병무청 나라사랑가게", success.benefit.sourceLabel)
    }

    @Test
    fun `Room 상세가 null이면 NotFound다`() {
        assertEquals(
            BenefitDetailUiState.NotFound,
            createBenefitDetailUiState(null),
        )
    }

    @Test
    fun `nullable 필드는 null 문자열 없이 안전한 안내로 변환한다`() {
        val state = createBenefitDetailUiState(
            detail(address = null, phone = null, benefitType = null),
        ) as BenefitDetailUiState.Success

        assertEquals("주소 정보 없음", state.benefit.address)
        assertEquals("전화번호 정보 없음", state.benefit.phone)
        assertEquals("혜택 유형 정보 없음", state.benefit.benefitType)
    }

    @Test
    fun `알 수 없는 sourceType도 raw 값을 노출하지 않는다`() {
        val state = createBenefitDetailUiState(
            detail(sourceType = "UNKNOWN_RAW"),
        ) as BenefitDetailUiState.Success

        assertEquals("정보 출처 확인 불가", state.benefit.sourceLabel)
    }

    @Test
    fun `MANUAL 상세 필드와 확인 필요 상태를 실제 값으로 표시한다`() {
        val state = createBenefitDetailUiState(
            detail(
                sourceType = BenefitSourceType.MANUAL_SEED.name,
                benefitDescription = "실제 확인된 혜택 내용",
                verificationMethod = "전화 문의",
                lastVerifiedDate = "2026-08-17",
                status = "NEEDS_VERIFICATION",
            ),
        ) as BenefitDetailUiState.Success

        assertEquals("직접 확인한 혜택", state.benefit.sourceLabel)
        assertEquals("실제 확인된 혜택 내용", state.benefit.benefitDescription)
        assertEquals("전화 문의", state.benefit.verificationMethod)
        assertEquals("2026-08-17", state.benefit.lastVerifiedDate)
        assertEquals("정보 확인 필요", state.benefit.statusNotice)
    }

    private fun detail(
        address: String? = "서울특별시 강남구 테헤란로 1",
        phone: String? = "02-1234-5678",
        benefitType: String? = "할인",
        sourceType: String = MMA_SOURCE_TYPE,
        benefitDescription: String? = null,
        verificationMethod: String? = null,
        lastVerifiedDate: String? = null,
        status: String? = null,
    ) = BenefitDetail(
        id = "mma_detail",
        name = "테스트 가게",
        address = address,
        phone = phone,
        benefitType = benefitType,
        district = "강남구",
        sourceType = sourceType,
        benefitDescription = benefitDescription,
        verificationMethod = verificationMethod,
        lastVerifiedDate = lastVerifiedDate,
        status = status,
    )
}

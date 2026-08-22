package com.example.milipercent.data.local

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BenefitIdentityTest {
    @Test
    fun `같은 출처 업체명 주소는 공백과 대소문자 차이에도 같은 ID를 만든다`() {
        val first = BenefitIdentity.create(
            sourceType = MMA_SOURCE_TYPE,
            name = "  Mili  Store ",
            address = "서울특별시   마포구 월드컵로 1",
        )
        val second = BenefitIdentity.create(
            sourceType = "mma_api",
            name = "milistore",
            address = "서울특별시마포구월드컵로1",
        )

        assertEquals(first, second)
        assertTrue(first.matches(Regex("mma_[0-9a-f]{64}")))
    }

    @Test
    fun `주소가 다르면 다른 ID를 만든다`() {
        val first = BenefitIdentity.create(MMA_SOURCE_TYPE, "가게", "서울특별시 마포구 1")
        val second = BenefitIdentity.create(MMA_SOURCE_TYPE, "가게", "서울특별시 마포구 2")

        assertNotEquals(first, second)
    }
}

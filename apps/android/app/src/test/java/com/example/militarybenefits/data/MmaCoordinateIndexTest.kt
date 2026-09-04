package com.example.militarybenefits.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MmaCoordinateIndexTest {
    private val index = MmaCoordinateIndex(
        listOf(
            MmaCoordinateEntry(
                name = "샘플 식당",
                address = "서울특별시 마포구 월드컵로 1 (성산동)",
                latitude = 37.5665,
                longitude = 126.9780,
            ),
        ),
    )

    @Test
    fun `find ignores case spaces commas and parentheses`() {
        val result = index.find(" 샘플식당 ", "서울특별시마포구 월드컵로1, 성산동")

        assertEquals(37.5665, result?.latitude ?: 0.0, 0.000001)
        assertEquals(126.9780, result?.longitude ?: 0.0, 0.000001)
    }

    @Test
    fun `find does not guess a different address`() {
        assertNull(index.find("샘플 식당", "서울특별시 마포구 월드컵로 2"))
    }

    @Test
    fun `duplicate normalized entries keep the last coordinate`() {
        val duplicateIndex = MmaCoordinateIndex(
            listOf(
                MmaCoordinateEntry("업소", "서울 중구 세종대로 1", 37.1, 126.1),
                MmaCoordinateEntry("업 소", "서울 중구 세종대로 1", 37.2, 126.2),
            ),
        )

        assertEquals(1, duplicateIndex.size)
        assertEquals(37.2, duplicateIndex.find("업소", "서울 중구 세종대로 1")?.latitude ?: 0.0, 0.0)
    }
}

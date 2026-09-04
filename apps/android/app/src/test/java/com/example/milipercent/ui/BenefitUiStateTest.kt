package com.example.milipercent.ui

import com.example.milipercent.model.BenefitUiModel
import com.example.milipercent.model.CollectionProgress
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BenefitUiStateTest {
    @Test
    fun `캐시가 있으면 refresh 중에도 목록을 표시한다`() {
        val state = createBenefitUiState(
            districtState = districtState(cachedBenefit()),
            hasObservedCache = true,
            isRefreshing = true,
            refreshFailed = false,
            refreshCompleted = false,
            progress = CollectionProgress(2, 23, 200),
            latestApiCollectedCount = null,
        ) as BenefitUiState.Success

        assertEquals(1, state.benefits.size)
        assertTrue(state.isRefreshing)
        assertEquals(2, state.progress?.currentPage)
    }

    @Test
    fun `캐시가 있으면 refresh 실패 후에도 목록을 유지한다`() {
        val state = createBenefitUiState(
            districtState = districtState(cachedBenefit()),
            hasObservedCache = true,
            isRefreshing = false,
            refreshFailed = true,
            refreshCompleted = false,
            progress = null,
            latestApiCollectedCount = null,
        ) as BenefitUiState.Success

        assertEquals("mma_cached", state.benefits.single().id)
        assertTrue(state.refreshFailed)
        assertFalse(state.isRefreshing)
    }

    @Test
    fun `캐시가 없고 refresh가 실패하면 Error다`() {
        val state = createBenefitUiState(
            districtState = districtState(),
            hasObservedCache = true,
            isRefreshing = false,
            refreshFailed = true,
            refreshCompleted = false,
            progress = null,
            latestApiCollectedCount = null,
        )

        assertEquals(BenefitUiState.Error, state)
    }

    private fun cachedBenefit() = BenefitUiModel(
        id = "mma_cached",
        name = "저장된 가게",
        address = "서울특별시 마포구",
        phone = null,
        benefitType = "할인",
        district = "마포구",
        latitude = null,
        longitude = null,
    )

    private fun districtState(
        vararg benefits: BenefitUiModel,
    ) = BenefitDistrictState().apply {
        updateBenefits(benefits.toList())
    }
}

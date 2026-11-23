package com.example.milipercent.data.sync

import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BenefitSyncPolicyTest {
    @Test
    fun `shouldAutoRefresh respects missing timestamps, 6h cooldown boundary, and clock rollback`() {
        val cooldown = BenefitSyncPolicy.DEFAULT_AUTO_REFRESH_COOLDOWN_MILLIS
        val base = 1_700_000_000_000L

        assertEquals(6L * 60L * 60L * 1000L, cooldown)
        assertTrue(BenefitSyncPolicy.shouldAutoRefresh(null, base))
        assertTrue(BenefitSyncPolicy.shouldAutoRefresh(0L, base))
        assertTrue(BenefitSyncPolicy.shouldAutoRefresh(-1L, base))

        assertFalse(BenefitSyncPolicy.shouldAutoRefresh(base, base))
        assertFalse(BenefitSyncPolicy.shouldAutoRefresh(base, base + cooldown - 1L))
        assertTrue(BenefitSyncPolicy.shouldAutoRefresh(base, base + cooldown))
        assertTrue(BenefitSyncPolicy.shouldAutoRefresh(base, base + cooldown + 60_000L))
        assertTrue(BenefitSyncPolicy.shouldAutoRefresh(base, base - 1_000L))
    }

    @Test
    fun `formatSyncLabel formats missing timestamp and KST timestamp consistently`() {
        val kst = TimeZone.getTimeZone("Asia/Seoul")
        val millis = Calendar.getInstance(kst, Locale.KOREA).apply {
            clear()
            set(2026, Calendar.NOVEMBER, 23, 21, 5, 0)
        }.timeInMillis

        assertEquals("내장 혜택 DB", BenefitSyncPolicy.formatSyncLabel(null, kst))
        assertEquals("내장 혜택 DB", BenefitSyncPolicy.formatSyncLabel(0L, kst))
        assertEquals("나라사랑가게 API 동기화 · 11/23 21:05", BenefitSyncPolicy.formatSyncLabel(millis, kst))
    }

    @Test
    fun `inMemorySyncPreferences ignores non-positive timestamps and clears cleanly`() {
        val store = InMemoryBenefitSyncPreferences()
        assertNull(store.lastSuccessfulSyncAtMillis())

        store.recordSuccessfulSync(0L)
        store.recordSuccessfulSync(-50L)
        assertNull(store.lastSuccessfulSyncAtMillis())

        store.recordSuccessfulSync(1_700_000_000_000L)
        assertEquals(1_700_000_000_000L, store.lastSuccessfulSyncAtMillis())

        store.clear()
        assertNull(store.lastSuccessfulSyncAtMillis())
    }
}

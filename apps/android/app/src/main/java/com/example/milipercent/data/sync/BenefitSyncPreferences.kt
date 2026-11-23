package com.example.milipercent.data.sync

import android.content.Context
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

interface BenefitSyncPreferenceStore {
    fun lastSuccessfulSyncAtMillis(): Long?

    fun recordSuccessfulSync(timestampMillis: Long)

    fun clear()
}

class BenefitSyncPreferences(context: Context) : BenefitSyncPreferenceStore {
    private val preferences = context.applicationContext.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    override fun lastSuccessfulSyncAtMillis(): Long? = preferences
        .takeIf { it.contains(LAST_SUCCESSFUL_SYNC_AT_KEY) }
        ?.getLong(LAST_SUCCESSFUL_SYNC_AT_KEY, 0L)
        ?.takeIf { it > 0L }

    override fun recordSuccessfulSync(timestampMillis: Long) {
        if (timestampMillis <= 0L) return
        preferences.edit().putLong(LAST_SUCCESSFUL_SYNC_AT_KEY, timestampMillis).apply()
    }

    override fun clear() {
        preferences.edit().remove(LAST_SUCCESSFUL_SYNC_AT_KEY).apply()
    }

    private companion object {
        const val PREFERENCES_NAME = "benefit-sync-state"
        const val LAST_SUCCESSFUL_SYNC_AT_KEY = "last_successful_sync_at_millis"
    }
}

class InMemoryBenefitSyncPreferences(
    initialTimestampMillis: Long? = null,
) : BenefitSyncPreferenceStore {
    private var lastSyncAtMillis: Long? = initialTimestampMillis?.takeIf { it > 0L }

    override fun lastSuccessfulSyncAtMillis(): Long? = lastSyncAtMillis

    override fun recordSuccessfulSync(timestampMillis: Long) {
        if (timestampMillis > 0L) {
            lastSyncAtMillis = timestampMillis
        }
    }

    override fun clear() {
        lastSyncAtMillis = null
    }
}

object BenefitSyncPolicy {
    const val DEFAULT_AUTO_REFRESH_COOLDOWN_MILLIS: Long = 6L * 60L * 60L * 1000L

    fun shouldAutoRefresh(
        lastSuccessfulSyncAtMillis: Long?,
        nowMillis: Long,
        cooldownMillis: Long = DEFAULT_AUTO_REFRESH_COOLDOWN_MILLIS,
    ): Boolean {
        if (cooldownMillis <= 0L) return true
        if (lastSuccessfulSyncAtMillis == null || lastSuccessfulSyncAtMillis <= 0L) return true
        if (nowMillis < lastSuccessfulSyncAtMillis) return true
        return (nowMillis - lastSuccessfulSyncAtMillis) >= cooldownMillis
    }

    fun formatSyncLabel(
        lastSuccessfulSyncAtMillis: Long?,
        timeZone: TimeZone = TimeZone.getTimeZone("Asia/Seoul"),
    ): String {
        if (lastSuccessfulSyncAtMillis == null || lastSuccessfulSyncAtMillis <= 0L) {
            return "내장 혜택 DB"
        }
        val formatter = SimpleDateFormat("MM/dd HH:mm", Locale.KOREA).apply {
            this.timeZone = timeZone
        }
        return "나라사랑가게 API 동기화 · ${formatter.format(Date(lastSuccessfulSyncAtMillis))}"
    }
}

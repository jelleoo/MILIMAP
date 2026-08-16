package com.example.militarybenefits.data

import android.content.Context

class SessionStore(context: Context) {
    private val preferences = context.getSharedPreferences("local-session", Context.MODE_PRIVATE)

    fun userId(): Long? = preferences.getLong("user_id", -1L).takeIf { it >= 0L }
    fun save(user: LocalUser) = preferences.edit().putLong("user_id", user.id).apply()
    fun clear() = preferences.edit().remove("user_id").apply()
}

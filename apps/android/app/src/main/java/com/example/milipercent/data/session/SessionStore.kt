package com.example.milipercent.data.session

import android.content.Context
import com.example.milipercent.model.LocalUser

interface SessionStorage {
    fun userId(): Long?

    fun save(user: LocalUser)

    fun clear()
}

class SessionStore(context: Context) : SessionStorage {
    private val preferences = context.applicationContext.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    override fun userId(): Long? = preferences.takeIf { it.contains(USER_ID_KEY) }
        ?.getLong(USER_ID_KEY, 0L)

    override fun save(user: LocalUser) {
        preferences.edit().putLong(USER_ID_KEY, user.id).apply()
    }

    override fun clear() {
        preferences.edit().remove(USER_ID_KEY).apply()
    }

    private companion object {
        const val PREFERENCES_NAME = "local-session"
        const val USER_ID_KEY = "user_id"
    }
}

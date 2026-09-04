package com.example.milipercent

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class AppBuildContractTest {
    @Test
    fun `application id matches registered map package`() {
        assertEquals("com.example.militarybenefits", BuildConfig.APPLICATION_ID)
    }

    @Test
    fun `all local configuration fields exist`() {
        assertNotNull(BuildConfig.NAVER_MAP_NCP_KEY_ID)
        assertNotNull(BuildConfig.MMA_API_URL)
        assertNotNull(BuildConfig.MMA_SERVICE_KEY)
    }
}

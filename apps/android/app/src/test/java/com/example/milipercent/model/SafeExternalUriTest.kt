package com.example.milipercent.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SafeExternalUriTest {
    @Test
    fun `resolveSafeHttpUrl accepts http and https including pipe delimited first link`() {
        assertEquals(
            "https://www.mma.go.kr/board/notice?id=1",
            SafeExternalUri.resolveSafeHttpUrl(" https://www.mma.go.kr/board/notice?id=1 "),
        )
        assertEquals(
            "http://example.go.kr/info",
            SafeExternalUri.resolveSafeHttpUrl("http://example.go.kr/info | https://backup.go.kr"),
        )
    }

    @Test
    fun `resolveSafeHttpUrl rejects non http schemes userinfo and whitespace`() {
        assertNull(SafeExternalUri.resolveSafeHttpUrl(null))
        assertNull(SafeExternalUri.resolveSafeHttpUrl("   "))
        assertNull(SafeExternalUri.resolveSafeHttpUrl("file:///data/data/com.example.militarybenefits/databases/mili_percent.db"))
        assertNull(SafeExternalUri.resolveSafeHttpUrl("content://com.example.provider/secret"))
        assertNull(SafeExternalUri.resolveSafeHttpUrl("intent://scan/#Intent;scheme=zxing;end"))
        assertNull(SafeExternalUri.resolveSafeHttpUrl("javascript:alert(1)"))
        assertNull(SafeExternalUri.resolveSafeHttpUrl("tel:02-1234-5678"))
        assertNull(SafeExternalUri.resolveSafeHttpUrl("https://user:pass@example.com/path"))
        assertNull(SafeExternalUri.resolveSafeHttpUrl("https://example.com/with space"))
    }

    @Test
    fun `sanitizeDialablePhone strips unsafe characters and requires at least one digit`() {
        assertEquals("02-1234-5678", SafeExternalUri.sanitizeDialablePhone("02-1234-5678"))
        assertEquals("+8210-1234-5678", SafeExternalUri.sanitizeDialablePhone("+82 (10)-1234-5678;ext=9"))
        assertEquals("031-123-4567", SafeExternalUri.sanitizeDialablePhone("031-123-4567 (평일)"))
        assertNull(SafeExternalUri.sanitizeDialablePhone(null))
        assertNull(SafeExternalUri.sanitizeDialablePhone("문의 바람"))
        assertNull(SafeExternalUri.sanitizeDialablePhone("---"))
    }
}

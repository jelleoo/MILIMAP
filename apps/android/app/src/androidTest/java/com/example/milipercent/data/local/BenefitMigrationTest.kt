package com.example.milipercent.data.local

import androidx.room.testing.MigrationTestHelper
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class BenefitMigrationTest {
    @get:Rule
    val helper = MigrationTestHelper(
        InstrumentationRegistry.getInstrumentation(),
        BenefitDatabase::class.java,
    )

    @Test
    fun migrate1To2PreservesMmaRowAndAddsNullableColumns() {
        var database = helper.createDatabase(TEST_DATABASE, 1)
        database.execSQL(
            """
            INSERT INTO benefits (
                id, sourceType, sourceRowNumber, name, address, phone, benefitType,
                district, latitude, longitude, syncedAt
            ) VALUES (
                'mma_fixture', 'MMA_API', 37, '기존 업체', '서울특별시 마포구',
                '02-1234-5678', '면제', '마포구', 37.5, 126.9, 123456
            )
            """.trimIndent(),
        )
        database.close()

        database = helper.runMigrationsAndValidate(
            TEST_DATABASE,
            2,
            true,
            MIGRATION_1_2,
        )

        database.query("SELECT * FROM benefits WHERE id = 'mma_fixture'").use { cursor ->
            assertEquals(1, cursor.count)
            cursor.moveToFirst()
            assertEquals("mma_fixture", cursor.getString(cursor.getColumnIndexOrThrow("id")))
            assertEquals("MMA_API", cursor.getString(cursor.getColumnIndexOrThrow("sourceType")))
            assertEquals(37, cursor.getInt(cursor.getColumnIndexOrThrow("sourceRowNumber")))
            assertEquals("기존 업체", cursor.getString(cursor.getColumnIndexOrThrow("name")))
            assertEquals("서울특별시 마포구", cursor.getString(cursor.getColumnIndexOrThrow("address")))
            assertEquals("02-1234-5678", cursor.getString(cursor.getColumnIndexOrThrow("phone")))
            assertEquals("면제", cursor.getString(cursor.getColumnIndexOrThrow("benefitType")))
            assertEquals("마포구", cursor.getString(cursor.getColumnIndexOrThrow("district")))
            assertEquals(37.5, cursor.getDouble(cursor.getColumnIndexOrThrow("latitude")), 0.0)
            assertEquals(126.9, cursor.getDouble(cursor.getColumnIndexOrThrow("longitude")), 0.0)
            assertEquals(123456L, cursor.getLong(cursor.getColumnIndexOrThrow("syncedAt")))

            NEW_COLUMNS.forEach { column ->
                assertNull(cursor.getString(cursor.getColumnIndexOrThrow(column)))
            }
        }

        database.query("PRAGMA table_info(benefits)").use { cursor ->
            var foundSourceRowNumber = false
            while (cursor.moveToNext()) {
                if (cursor.getString(cursor.getColumnIndexOrThrow("name")) == "sourceRowNumber") {
                    foundSourceRowNumber = true
                    assertEquals(0, cursor.getInt(cursor.getColumnIndexOrThrow("notnull")))
                }
            }
            assertTrue(foundSourceRowNumber)
        }
        database.close()
    }

    @Test
    fun migrate2To3PreservesOldFieldsAndAddsFinalContract() {
        var database = helper.createDatabase(TEST_DATABASE, 2)
        database.execSQL(
            """
            INSERT INTO benefits (
                id, sourceType, sourceRowNumber, name, address, phone, benefitType,
                district, latitude, longitude, syncedAt, benefitDescription, eligibleTarget,
                usageCondition, verificationMethod, sourceUrl, lastVerifiedDate, status
            ) VALUES (
                'mma_v2_fixture', 'MMA_API', 37, '기존 업체', '서울특별시 마포구',
                '02-1234-5678', '면제', '마포구', 37.5, 126.9, 123456,
                '기존 설명', '병역의무자', '신분증 제시', '전화 확인',
                'https://example.com/v2', '2026-08-31', NULL
            )
            """.trimIndent(),
        )
        database.close()

        database = helper.runMigrationsAndValidate(
            TEST_DATABASE,
            3,
            true,
            MIGRATION_2_3,
        )

        database.query("SELECT * FROM benefits WHERE id = 'mma_v2_fixture'").use { cursor ->
            assertEquals(1, cursor.count)
            cursor.moveToFirst()
            assertEquals("기존 업체", cursor.getString(cursor.getColumnIndexOrThrow("name")))
            assertEquals("서울특별시 마포구", cursor.getString(cursor.getColumnIndexOrThrow("address")))
            assertEquals("면제", cursor.getString(cursor.getColumnIndexOrThrow("benefitType")))
            assertEquals("기존 설명", cursor.getString(cursor.getColumnIndexOrThrow("benefitDescription")))
            assertEquals("병역의무자", cursor.getString(cursor.getColumnIndexOrThrow("eligibleTarget")))
            assertEquals("신분증 제시", cursor.getString(cursor.getColumnIndexOrThrow("usageCondition")))
            assertEquals("전화 확인", cursor.getString(cursor.getColumnIndexOrThrow("verificationMethod")))
            assertEquals("https://example.com/v2", cursor.getString(cursor.getColumnIndexOrThrow("sourceUrl")))
            assertEquals("기타", cursor.getString(cursor.getColumnIndexOrThrow("category")))
            assertEquals("병무청 나라사랑가게 API", cursor.getString(cursor.getColumnIndexOrThrow("sourceLabel")))
            assertEquals("2026-08-31", cursor.getString(cursor.getColumnIndexOrThrow("lastVerifiedAt")))
            assertEquals("NEEDS_VERIFICATION", cursor.getString(cursor.getColumnIndexOrThrow("status")))
        }
        database.close()
    }

    private companion object {
        const val TEST_DATABASE = "benefit-migration-test"
        val NEW_COLUMNS = listOf(
            "benefitDescription",
            "eligibleTarget",
            "usageCondition",
            "verificationMethod",
            "sourceUrl",
            "lastVerifiedDate",
            "status",
        )
    }
}

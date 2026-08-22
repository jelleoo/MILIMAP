package com.example.milipercent.data.local

import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

val MIGRATION_1_2 = object : Migration(1, 2) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS `benefits_new` (
                `id` TEXT NOT NULL,
                `sourceType` TEXT NOT NULL,
                `sourceRowNumber` INTEGER,
                `name` TEXT NOT NULL,
                `address` TEXT,
                `phone` TEXT,
                `benefitType` TEXT,
                `district` TEXT NOT NULL,
                `latitude` REAL,
                `longitude` REAL,
                `syncedAt` INTEGER NOT NULL,
                `benefitDescription` TEXT,
                `eligibleTarget` TEXT,
                `usageCondition` TEXT,
                `verificationMethod` TEXT,
                `sourceUrl` TEXT,
                `lastVerifiedDate` TEXT,
                `status` TEXT,
                PRIMARY KEY(`id`)
            )
            """.trimIndent(),
        )
        db.execSQL(
            """
            INSERT INTO `benefits_new` (
                `id`, `sourceType`, `sourceRowNumber`, `name`, `address`, `phone`,
                `benefitType`, `district`, `latitude`, `longitude`, `syncedAt`
            )
            SELECT
                `id`, `sourceType`, `sourceRowNumber`, `name`, `address`, `phone`,
                `benefitType`, `district`, `latitude`, `longitude`, `syncedAt`
            FROM `benefits`
            """.trimIndent(),
        )
        db.execSQL("DROP TABLE `benefits`")
        db.execSQL("ALTER TABLE `benefits_new` RENAME TO `benefits`")
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS `index_benefits_sourceType` " +
                "ON `benefits` (`sourceType`)",
        )
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS `index_benefits_district` " +
                "ON `benefits` (`district`)",
        )
    }
}

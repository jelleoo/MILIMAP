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

val MIGRATION_2_3 = object : Migration(2, 3) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS `benefits_new` (
                `id` TEXT NOT NULL,
                `sourceType` TEXT NOT NULL,
                `sourceRowNumber` INTEGER,
                `name` TEXT NOT NULL,
                `address` TEXT NOT NULL,
                `latitude` REAL,
                `longitude` REAL,
                `category` TEXT NOT NULL,
                `benefitType` TEXT NOT NULL,
                `benefitDescription` TEXT NOT NULL,
                `phone` TEXT,
                `eligibleTarget` TEXT,
                `usageCondition` TEXT,
                `verificationMethod` TEXT,
                `sourceLabel` TEXT NOT NULL,
                `sourceUrl` TEXT,
                `lastVerifiedAt` TEXT,
                `status` TEXT NOT NULL,
                `district` TEXT,
                `syncedAt` INTEGER NOT NULL,
                PRIMARY KEY(`id`)
            )
            """.trimIndent(),
        )
        db.execSQL(
            """
            INSERT INTO `benefits_new` (
                `id`, `sourceType`, `sourceRowNumber`, `name`, `address`, `latitude`,
                `longitude`, `category`, `benefitType`, `benefitDescription`, `phone`,
                `eligibleTarget`, `usageCondition`, `verificationMethod`, `sourceLabel`,
                `sourceUrl`, `lastVerifiedAt`, `status`, `district`, `syncedAt`
            )
            SELECT
                `id`, `sourceType`, `sourceRowNumber`, `name`,
                COALESCE(`address`, '주소 확인 필요'), `latitude`, `longitude`, '기타',
                COALESCE(`benefitType`, '할인·우대'),
                COALESCE(`benefitDescription`, '혜택 내용은 업소에 확인'), `phone`,
                `eligibleTarget`, `usageCondition`, `verificationMethod`,
                CASE `sourceType`
                    WHEN 'MMA_API' THEN '병무청 나라사랑가게 API'
                    WHEN 'MANUAL_SEED' THEN '검증된 내장 데이터'
                    ELSE '운영팀 직접 확인'
                END,
                `sourceUrl`, `lastVerifiedDate`, COALESCE(`status`, 'NEEDS_VERIFICATION'),
                `district`, `syncedAt`
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
            "CREATE INDEX IF NOT EXISTS `index_benefits_status_category` " +
                "ON `benefits` (`status`, `category`)",
        )
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS `index_benefits_district` " +
                "ON `benefits` (`district`)",
        )
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS `seed_state` (
                `name` TEXT NOT NULL,
                `version` INTEGER NOT NULL,
                `installedAt` INTEGER NOT NULL,
                PRIMARY KEY(`name`)
            )
            """.trimIndent(),
        )
    }
}

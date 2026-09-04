package com.example.milipercent.data.local

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

@Database(
    entities = [BenefitEntity::class, SeedStateEntity::class],
    version = 3,
    exportSchema = true,
)
abstract class BenefitDatabase : RoomDatabase() {
    abstract fun benefitDao(): BenefitDao

    abstract fun seedStateDao(): SeedStateDao

    companion object {
        private const val DATABASE_NAME = "mili_percent.db"

        @Volatile
        private var instance: BenefitDatabase? = null

        fun getInstance(context: Context): BenefitDatabase =
            instance ?: synchronized(this) {
                instance ?: Room.databaseBuilder(
                    context.applicationContext,
                    BenefitDatabase::class.java,
                    DATABASE_NAME,
                )
                    .addMigrations(MIGRATION_1_2, MIGRATION_2_3)
                    .build()
                    .also { instance = it }
            }
    }
}

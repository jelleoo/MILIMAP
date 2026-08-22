package com.example.milipercent.data.local

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

@Database(
    entities = [BenefitEntity::class],
    version = 2,
    exportSchema = true,
)
abstract class BenefitDatabase : RoomDatabase() {
    abstract fun benefitDao(): BenefitDao

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
                    .addMigrations(MIGRATION_1_2)
                    .build()
                    .also { instance = it }
            }
    }
}

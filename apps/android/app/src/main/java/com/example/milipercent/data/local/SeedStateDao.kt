package com.example.milipercent.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query

@Dao
interface SeedStateDao {
    @Query("SELECT version FROM seed_state WHERE name = :name LIMIT 1")
    suspend fun version(name: String): Int?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(state: SeedStateEntity)
}

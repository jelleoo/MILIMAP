package com.example.milipercent.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface FavoriteDao {
    @Query("SELECT benefitId FROM favorites WHERE userId = :userId ORDER BY createdAt DESC")
    fun observeIds(userId: Long): Flow<List<String>>

    @Query("SELECT EXISTS(SELECT 1 FROM favorites WHERE userId = :userId AND benefitId = :benefitId)")
    suspend fun contains(userId: Long, benefitId: String): Boolean

    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insert(favorite: FavoriteEntity)

    @Query("DELETE FROM favorites WHERE userId = :userId AND benefitId = :benefitId")
    suspend fun delete(userId: Long, benefitId: String): Int
}

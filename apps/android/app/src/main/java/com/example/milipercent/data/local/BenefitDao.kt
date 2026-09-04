package com.example.milipercent.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import kotlinx.coroutines.flow.Flow

@Dao
interface BenefitDao {
    @Query("SELECT * FROM benefits ORDER BY district ASC, name COLLATE NOCASE ASC, id ASC")
    fun observeAll(): Flow<List<BenefitEntity>>

    @Query(
        """
        SELECT * FROM benefits
        WHERE sourceType = :sourceType
        ORDER BY district ASC, name COLLATE NOCASE ASC, id ASC
        """,
    )
    fun observeBySource(sourceType: String): Flow<List<BenefitEntity>>

    @Query(
        """
        SELECT * FROM benefits
        WHERE sourceType = :sourceType
        ORDER BY district ASC, name COLLATE NOCASE ASC, id ASC
        """,
    )
    suspend fun getBySource(sourceType: String): List<BenefitEntity>

    @Query("SELECT * FROM benefits ORDER BY district ASC, name COLLATE NOCASE ASC, id ASC")
    suspend fun getAllOnce(): List<BenefitEntity>

    @Query("SELECT COUNT(*) FROM benefits")
    suspend fun countAll(): Int

    @Query(
        """
        SELECT * FROM benefits
        WHERE status != :endedStatus
        ORDER BY district ASC, name COLLATE NOCASE ASC, id ASC
        """,
    )
    fun observeUserVisible(endedStatus: String): Flow<List<BenefitEntity>>

    @Query("SELECT * FROM benefits WHERE id = :id LIMIT 1")
    fun observeById(id: String): Flow<BenefitEntity?>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(benefits: List<BenefitEntity>)

    @Query("DELETE FROM benefits WHERE sourceType = :sourceType")
    suspend fun deleteBySource(sourceType: String)

    @Query("SELECT COUNT(*) FROM benefits WHERE sourceType = :sourceType")
    suspend fun countBySource(sourceType: String): Int

    @Query("DELETE FROM benefits WHERE id = :id AND sourceType = :sourceType")
    suspend fun deleteByIdAndSource(id: String, sourceType: String): Int

    @Transaction
    suspend fun replaceBySource(
        sourceType: String,
        benefits: List<BenefitEntity>,
    ) {
        require(benefits.all { it.sourceType == sourceType }) {
            "교체하려는 데이터의 sourceType이 일치하지 않습니다."
        }
        deleteBySource(sourceType)
        insertAll(benefits)
    }
}

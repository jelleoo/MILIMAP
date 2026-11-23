package com.example.milipercent.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import androidx.room.Upsert
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

    @Query("SELECT * FROM benefits WHERE id = :id LIMIT 1")
    suspend fun getByIdOnce(id: String): BenefitEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(benefits: List<BenefitEntity>)

    @Upsert
    suspend fun upsertAll(benefits: List<BenefitEntity>)

    @Query("DELETE FROM benefits WHERE sourceType = :sourceType")
    suspend fun deleteBySource(sourceType: String)

    @Query(
        """
        DELETE FROM benefits
        WHERE sourceType = :sourceType
          AND id IN (:ids)
        """,
    )
    suspend fun deleteBySourceAndIds(sourceType: String, ids: List<String>)

    @Query(
        """
        SELECT id FROM benefits
        WHERE sourceRowNumber IS NULL
          AND sourceType IN (:bundledSourceTypes)
        """,
    )
    suspend fun getBundledSeedIds(bundledSourceTypes: List<String>): List<String>

    @Query(
        """
        DELETE FROM benefits
        WHERE sourceRowNumber IS NULL
          AND sourceType IN (:bundledSourceTypes)
          AND id IN (:ids)
        """,
    )
    suspend fun deleteBundledSeedRowsByIds(
        bundledSourceTypes: List<String>,
        ids: List<String>,
    )

    @Transaction
    suspend fun deleteRetiredBundledSeedRows(
        bundledSourceTypes: List<String>,
        retainedIds: List<String>,
    ) {
        val existingIds = getBundledSeedIds(bundledSourceTypes)
        val retiredIds = computeRetiredIds(existingIds, retainedIds)
        retiredIds.chunked(SQLITE_DELETE_CHUNK_SIZE).forEach { chunk ->
            deleteBundledSeedRowsByIds(bundledSourceTypes, chunk)
        }
    }

    @Query("SELECT COUNT(*) FROM benefits WHERE sourceType = :sourceType")
    suspend fun countBySource(sourceType: String): Int

    @Query(
        """
        SELECT COUNT(*) FROM benefits
        WHERE sourceRowNumber IS NULL
          AND sourceType IN (:bundledSourceTypes)
        """,
    )
    suspend fun countBundledSeedRows(bundledSourceTypes: List<String>): Int

    @Query("DELETE FROM benefits WHERE id = :id AND sourceType = :sourceType")
    suspend fun deleteByIdAndSource(id: String, sourceType: String): Int

    @Query(
        """
        INSERT OR IGNORE INTO favorites (userId, benefitId, createdAt)
        SELECT userId, :replacementId, createdAt FROM favorites WHERE benefitId = :previousId
        """,
    )
    suspend fun copyFavoritesToReplacement(previousId: String, replacementId: String)

    @Transaction
    suspend fun replaceBySource(
        sourceType: String,
        benefits: List<BenefitEntity>,
    ) {
        require(benefits.all { it.sourceType == sourceType }) {
            "교체하려는 데이터의 sourceType이 일치하지 않습니다."
        }
        val existing = getBySource(sourceType)
        val diff = computeBenefitSourceDiff(existing, benefits)
        if (sourceType == MMA_SOURCE_TYPE && diff.removedIds.isNotEmpty()) {
            val publishedIds = getAllOnce().uniquePublishedBenefitIdsByIdentity()
            val removedIds = diff.removedIds.toHashSet()
            for (previous in existing) {
                if (previous.id !in removedIds) continue
                val replacementId = publishedIds[BenefitIdentity.normalizedKey(previous.name, previous.address)]
                    ?: continue
                copyFavoritesToReplacement(previous.id, replacementId)
            }
        }
        diff.removedIds.chunked(SQLITE_DELETE_CHUNK_SIZE).forEach { chunk ->
            deleteBySourceAndIds(sourceType, chunk)
        }
        if (diff.toUpsert.isNotEmpty()) {
            upsertAll(diff.toUpsert)
        }
    }
}

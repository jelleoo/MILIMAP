package com.example.milipercent.data.local

import kotlinx.coroutines.flow.Flow

interface BenefitLocalDataSource {
    fun observeBenefits(sourceType: String): Flow<List<BenefitEntity>>

    fun observeUserVisibleBenefits(): Flow<List<BenefitEntity>>

    fun observeBenefitById(id: String): Flow<BenefitEntity?>

    suspend fun getBenefits(sourceType: String): List<BenefitEntity> = emptyList()

    suspend fun replaceBenefits(sourceType: String, benefits: List<BenefitEntity>)

    suspend fun countBenefits(sourceType: String): Int

    suspend fun upsertBenefit(benefit: BenefitEntity)

    suspend fun deleteBenefit(id: String, sourceType: String): Boolean
}

class RoomBenefitLocalDataSource(
    private val dao: BenefitDao,
) : BenefitLocalDataSource {
    override fun observeBenefits(sourceType: String): Flow<List<BenefitEntity>> =
        dao.observeBySource(sourceType)

    override fun observeUserVisibleBenefits(): Flow<List<BenefitEntity>> =
        dao.observeUserVisible(ManualBenefitStatus.ENDED.name)

    override fun observeBenefitById(id: String): Flow<BenefitEntity?> =
        dao.observeById(id)

    override suspend fun getBenefits(sourceType: String): List<BenefitEntity> =
        dao.getBySource(sourceType)

    override suspend fun replaceBenefits(
        sourceType: String,
        benefits: List<BenefitEntity>,
    ) = dao.replaceBySource(sourceType, benefits)

    override suspend fun countBenefits(sourceType: String): Int =
        dao.countBySource(sourceType)

    override suspend fun upsertBenefit(benefit: BenefitEntity) {
        dao.insertAll(listOf(benefit))
    }

    override suspend fun deleteBenefit(id: String, sourceType: String): Boolean =
        dao.deleteByIdAndSource(id, sourceType) == 1
}

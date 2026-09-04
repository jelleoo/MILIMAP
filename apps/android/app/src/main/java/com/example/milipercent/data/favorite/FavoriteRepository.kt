package com.example.milipercent.data.favorite

import androidx.room.withTransaction
import com.example.milipercent.data.local.BenefitDatabase
import com.example.milipercent.data.local.FavoriteEntity
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

interface FavoriteRepository {
    fun observeIds(userId: Long): Flow<Set<String>>

    suspend fun toggle(userId: Long, benefitId: String): Boolean
}

class RoomFavoriteRepository(
    private val database: BenefitDatabase,
    private val currentTimeMillis: () -> Long = System::currentTimeMillis,
) : FavoriteRepository {
    override fun observeIds(userId: Long): Flow<Set<String>> =
        database.favoriteDao().observeIds(userId).map(List<String>::toSet)

    override suspend fun toggle(userId: Long, benefitId: String): Boolean = database.withTransaction {
        val dao = database.favoriteDao()
        if (dao.contains(userId, benefitId)) {
            dao.delete(userId, benefitId)
            false
        } else {
            dao.insert(FavoriteEntity(userId, benefitId, currentTimeMillis()))
            true
        }
    }
}

package com.example.milipercent.data.local

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index

@Entity(
    tableName = "favorites",
    primaryKeys = ["userId", "benefitId"],
    foreignKeys = [
        ForeignKey(
            entity = UserEntity::class,
            parentColumns = ["id"],
            childColumns = ["userId"],
            onDelete = ForeignKey.CASCADE,
        ),
        ForeignKey(
            entity = BenefitEntity::class,
            parentColumns = ["id"],
            childColumns = ["benefitId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [Index("userId"), Index("benefitId")],
)
data class FavoriteEntity(
    val userId: Long,
    val benefitId: String,
    val createdAt: Long,
)

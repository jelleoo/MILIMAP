package com.example.milipercent.data.local

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "seed_state")
data class SeedStateEntity(
    @PrimaryKey val name: String,
    val version: Int,
    val installedAt: Long,
)

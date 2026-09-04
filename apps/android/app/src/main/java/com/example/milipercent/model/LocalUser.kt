package com.example.milipercent.model

data class LocalUser(
    val id: Long,
    val email: String,
    val displayName: String,
    val isAdmin: Boolean,
)

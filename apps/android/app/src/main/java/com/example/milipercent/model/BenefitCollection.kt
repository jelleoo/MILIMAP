package com.example.milipercent.model

data class BenefitPage(
    val benefits: List<Benefit>,
    val pageNo: Int,
    val numOfRows: Int,
    val totalCount: Int,
)

data class BenefitCollection(
    val benefits: List<Benefit>,
    val apiTotalCount: Int,
    val pageSize: Int,
    val totalPages: Int,
)

data class CollectionProgress(
    val currentPage: Int,
    val totalPages: Int,
    val collectedCount: Int,
)

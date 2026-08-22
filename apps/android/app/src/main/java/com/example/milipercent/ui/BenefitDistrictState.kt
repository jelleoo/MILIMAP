package com.example.milipercent.ui

import com.example.milipercent.model.BenefitDistrict
import com.example.milipercent.model.BenefitUiModel
import java.util.Locale

internal class BenefitDistrictState {
    private var allBenefits: List<BenefitUiModel> = emptyList()

    var selectedDistrict: BenefitDistrict = BenefitDistrict.ALL
        private set

    var searchQuery: String = ""
        private set

    var districtCounts: Map<BenefitDistrict, Int> =
        BenefitDistrictFilter.calculateCounts(emptyList())
        private set

    var filteredBenefits: List<BenefitUiModel> = emptyList()
        private set

    val totalBenefitCount: Int
        get() = allBenefits.size

    fun updateBenefits(benefits: List<BenefitUiModel>) {
        allBenefits = benefits
        districtCounts = BenefitDistrictFilter.calculateCounts(benefits)
        updateFilteredBenefits()
    }

    fun selectDistrict(district: BenefitDistrict): Boolean {
        if (district == selectedDistrict) return false

        selectedDistrict = district
        updateFilteredBenefits()
        return true
    }

    fun updateSearchQuery(query: String): Boolean {
        if (query == searchQuery) return false

        searchQuery = query
        updateFilteredBenefits()
        return true
    }

    fun clearSearchQuery(): Boolean = updateSearchQuery("")

    private fun updateFilteredBenefits() {
        filteredBenefits = BenefitDistrictFilter.filter(
            benefits = allBenefits,
            selectedDistrict = selectedDistrict,
            searchQuery = searchQuery,
        )
    }
}

internal object BenefitDistrictFilter {
    fun filter(
        benefits: List<BenefitUiModel>,
        selectedDistrict: BenefitDistrict,
        searchQuery: String = "",
    ): List<BenefitUiModel> {
        val districtName = selectedDistrict.districtName
        val normalizedQuery = BenefitSearchMatcher.normalize(searchQuery)

        return benefits.filter { benefit ->
            val matchesDistrict = districtName == null || benefit.district == districtName
            matchesDistrict && BenefitSearchMatcher.matches(benefit, normalizedQuery)
        }
    }

    fun calculateCounts(
        benefits: List<BenefitUiModel>,
    ): Map<BenefitDistrict, Int> {
        val counts = linkedMapOf<BenefitDistrict, Int>().apply {
            BenefitDistrict.entries.forEach { district -> put(district, 0) }
            put(BenefitDistrict.ALL, benefits.size)
        }
        val districtByName = BenefitDistrict.seoulDistricts.associateBy { it.districtName }

        benefits.forEach { benefit ->
            districtByName[benefit.district]?.let { district ->
                counts[district] = counts.getValue(district) + 1
            }
        }

        return counts
    }
}

internal object BenefitSearchMatcher {
    fun matches(
        benefit: BenefitUiModel,
        normalizedQuery: String,
    ): Boolean {
        if (normalizedQuery.isEmpty()) return true

        return normalize(benefit.name).contains(normalizedQuery) ||
            normalize(benefit.address).contains(normalizedQuery)
    }

    fun normalize(value: String?): String = value
        ?.trim()
        ?.lowercase(Locale.ROOT)
        ?.replace(WHITESPACE_REGEX, "")
        .orEmpty()

    private val WHITESPACE_REGEX = Regex("\\s+")
}

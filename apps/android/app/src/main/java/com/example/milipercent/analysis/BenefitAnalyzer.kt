package com.example.milipercent.analysis

import com.example.milipercent.model.BenefitCollection
import com.example.milipercent.model.BenefitDistrict
import com.example.milipercent.model.MmaBenefit

data class DataQuality(
    val missingAddressCount: Int,
    val missingPhoneCount: Int,
    val missingNameCount: Int,
)

data class DuplicateAnalysis(
    val groupCount: Int,
    val duplicateRecordCount: Int,
)

data class BenefitAnalysisResult(
    val apiTotalCount: Int,
    val collectedCount: Int,
    val pageSize: Int,
    val totalPages: Int,
    val seoulBenefits: List<MmaBenefit>,
    val allDataQuality: DataQuality,
    val seoulDataQuality: DataQuality,
    val unclassifiedDistrictCount: Int,
    val duplicateAnalysis: DuplicateAnalysis,
    val districtCounts: Map<String, Int>,
    val allBenefitTypeCounts: Map<String, Int>,
    val seoulBenefitTypeCounts: Map<String, Int>,
) {
    val totalCountDifference: Int
        get() = collectedCount - apiTotalCount
}

object BenefitAnalyzer {
    const val UNKNOWN_DISTRICT = "UNKNOWN"
    const val MISSING_BENEFIT_TYPE = "(없음)"

    val seoulDistricts: List<String> = BenefitDistrict.seoulDistrictNames

    fun analyze(collection: BenefitCollection): BenefitAnalysisResult {
        val allBenefits = collection.benefits
        val seoulBenefits = allBenefits.filter { isSeoulAddress(it.address) }
        val districtCounts = linkedMapOf<String, Int>().apply {
            seoulDistricts.forEach { put(it, 0) }
            put(UNKNOWN_DISTRICT, 0)
        }

        seoulBenefits.forEach { benefit ->
            val district = extractSeoulDistrict(benefit.address) ?: UNKNOWN_DISTRICT
            districtCounts[district] = districtCounts.getValue(district) + 1
        }

        return BenefitAnalysisResult(
            apiTotalCount = collection.apiTotalCount,
            collectedCount = allBenefits.size,
            pageSize = collection.pageSize,
            totalPages = collection.totalPages,
            seoulBenefits = seoulBenefits,
            allDataQuality = analyzeDataQuality(allBenefits),
            seoulDataQuality = analyzeDataQuality(seoulBenefits),
            unclassifiedDistrictCount = districtCounts.getValue(UNKNOWN_DISTRICT),
            duplicateAnalysis = findSuspectedDuplicates(allBenefits),
            districtCounts = districtCounts,
            allBenefitTypeCounts = countBenefitTypes(allBenefits),
            seoulBenefitTypeCounts = countBenefitTypes(seoulBenefits),
        )
    }

    fun isSeoulAddress(address: String?): Boolean {
        val normalizedAddress = normalizeForComparison(address) ?: return false
        return normalizedAddress.startsWith("서울특별시") ||
            normalizedAddress.startsWith("서울시")
    }

    fun extractSeoulDistrict(address: String?): String? {
        val normalizedAddress = normalizeForComparison(address) ?: return null
        if (!isSeoulAddress(normalizedAddress)) return null
        return seoulDistricts.firstOrNull(normalizedAddress::contains)
    }

    fun findSuspectedDuplicates(benefits: List<MmaBenefit>): DuplicateAnalysis {
        val duplicateGroups = benefits.mapNotNull { benefit ->
            val normalizedName = normalizeForComparison(benefit.name)
            val normalizedAddress = normalizeForComparison(benefit.address)
            if (normalizedName == null || normalizedAddress == null) {
                null
            } else {
                "$normalizedName\u0000$normalizedAddress"
            }
        }.groupingBy { it }
            .eachCount()
            .filterValues { it > 1 }

        return DuplicateAnalysis(
            groupCount = duplicateGroups.size,
            duplicateRecordCount = duplicateGroups.values.sumOf { it - 1 },
        )
    }

    fun createDebugReport(result: BenefitAnalysisResult): String = buildString {
        appendLine("================================")
        appendLine("나라사랑가게 데이터 분석")
        appendLine("================================")
        appendLine("[전체]")
        appendLine("Page size: ${result.pageSize}")
        appendLine("전체 페이지: ${result.totalPages}")
        appendLine("API totalCount: ${result.apiTotalCount}")
        appendLine("실제 수집: ${result.collectedCount}")
        appendLine("차이: ${result.totalCountDifference}")
        appendLine("주소 누락: ${result.allDataQuality.missingAddressCount}")
        appendLine("전화번호 누락: ${result.allDataQuality.missingPhoneCount}")
        appendLine("업체명 누락: ${result.allDataQuality.missingNameCount}")
        appendLine()
        appendLine("[서울]")
        appendLine("서울 데이터: ${result.seoulBenefits.size}")
        appendLine("주소 누락: ${result.seoulDataQuality.missingAddressCount}")
        appendLine("전화번호 누락: ${result.seoulDataQuality.missingPhoneCount}")
        appendLine("업체명 누락: ${result.seoulDataQuality.missingNameCount}")
        appendLine("자치구 미분류: ${result.unclassifiedDistrictCount}")
        appendLine()
        appendLine("[중복]")
        appendLine("중복 의심 그룹: ${result.duplicateAnalysis.groupCount}")
        appendLine("중복 의심 추가 레코드: ${result.duplicateAnalysis.duplicateRecordCount}")
        appendLine()
        appendLine("[서울 구별]")
        result.districtCounts.forEach { (district, count) ->
            appendLine("$district: $count")
        }
        appendLine()
        appendLine("[혜택 유형 - 전체]")
        result.allBenefitTypeCounts.forEach { (type, count) ->
            appendLine("$type: $count")
        }
        appendLine()
        appendLine("[혜택 유형 - 서울]")
        result.seoulBenefitTypeCounts.forEach { (type, count) ->
            appendLine("$type: $count")
        }
    }

    private fun analyzeDataQuality(benefits: List<MmaBenefit>): DataQuality = DataQuality(
        missingAddressCount = benefits.count { it.address.isNullOrBlank() },
        missingPhoneCount = benefits.count { it.phone.isNullOrBlank() },
        missingNameCount = benefits.count { it.name.isBlank() },
    )

    private fun countBenefitTypes(benefits: List<MmaBenefit>): Map<String, Int> =
        benefits.groupingBy { benefit ->
            benefit.benefitType?.trim()?.takeIf(String::isNotEmpty)
                ?: MISSING_BENEFIT_TYPE
        }.eachCount().toSortedMap()

    private fun normalizeForComparison(value: String?): String? =
        value?.trim()
            ?.replace(WHITESPACE_REGEX, "")
            ?.takeIf(String::isNotEmpty)

    private val WHITESPACE_REGEX = Regex("\\s+")
}

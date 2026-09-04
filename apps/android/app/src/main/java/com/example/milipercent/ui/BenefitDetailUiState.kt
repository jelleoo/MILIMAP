package com.example.milipercent.ui

import com.example.milipercent.data.local.BenefitSourceType
import com.example.milipercent.data.local.ManualBenefitStatus
import com.example.milipercent.model.BenefitDetail

sealed interface BenefitDetailUiState {
    data object Loading : BenefitDetailUiState

    data class Success(
        val benefit: BenefitDetailUiModel,
    ) : BenefitDetailUiState

    data object NotFound : BenefitDetailUiState

    data object Error : BenefitDetailUiState
}

data class BenefitDetailUiModel(
    val id: String,
    val name: String,
    val address: String,
    val phone: String,
    val benefitType: String,
    val district: String,
    val sourceLabel: String,
    val sourceNotice: String,
    val benefitDescription: String? = null,
    val eligibleTarget: String? = null,
    val usageCondition: String? = null,
    val verificationMethod: String? = null,
    val lastVerifiedDate: String? = null,
    val statusNotice: String? = null,
)

internal fun createBenefitDetailUiState(
    benefit: BenefitDetail?,
): BenefitDetailUiState = if (benefit == null) {
    BenefitDetailUiState.NotFound
} else {
    BenefitDetailUiState.Success(
        benefit = BenefitDetailUiModel(
            id = benefit.id,
            name = benefit.name.ifBlank { "업체명 정보 없음" },
            address = benefit.address.displayOr("주소 정보 없음"),
            phone = benefit.phone.displayOr("전화번호 정보 없음"),
            benefitType = benefit.benefitType.displayOr("혜택 유형 정보 없음"),
            district = benefit.district.ifBlank { "지역 정보 없음" },
            sourceLabel = BenefitSourceLabelMapper.toDisplayName(benefit.sourceType),
            sourceNotice = BenefitSourceLabelMapper.toNotice(benefit.sourceType),
            benefitDescription = benefit.benefitDescription.displayOptional(),
            eligibleTarget = benefit.eligibleTarget.displayOptional(),
            usageCondition = benefit.usageCondition.displayOptional(),
            verificationMethod = benefit.verificationMethod.displayOptional(),
            lastVerifiedDate = benefit.lastVerifiedDate.displayOptional(),
            statusNotice = when (ManualBenefitStatus.fromStorage(benefit.status)) {
                ManualBenefitStatus.NEEDS_VERIFICATION -> "정보 확인 필요"
                ManualBenefitStatus.ENDED -> "종료된 혜택입니다."
                else -> null
            },
        ),
    )
}

private fun String?.displayOr(fallback: String): String =
    this?.takeIf(String::isNotBlank) ?: fallback

private fun String?.displayOptional(): String? = this?.takeIf(String::isNotBlank)

internal object BenefitSourceLabelMapper {
    fun toDisplayName(sourceType: String): String = when (sourceType) {
        BenefitSourceType.MMA_API.name -> "병무청 나라사랑가게"
        BenefitSourceType.MANUAL_SEED.name,
        BenefitSourceType.MANUAL_LOCAL.name,
        -> "직접 확인한 혜택"
        else -> "정보 출처 확인 불가"
    }

    fun toNotice(sourceType: String): String = when (sourceType) {
        BenefitSourceType.MMA_API.name ->
            "병무청 API 제공 정보이며, 이용 전 업체에 최신 내용을 확인하세요."
        BenefitSourceType.MANUAL_SEED.name,
        BenefitSourceType.MANUAL_LOCAL.name,
        -> "직접 확인하거나 입력한 정보이며, 이용 전 업체에 최신 내용을 확인하세요."
        else -> "출처를 확인할 수 없는 정보이므로, 이용 전 업체에 최신 내용을 확인하세요."
    }
}

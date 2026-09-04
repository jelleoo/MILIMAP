package com.example.milipercent.model

enum class BenefitDistrict(
    val displayName: String,
    val districtName: String?,
) {
    ALL("전체", null),
    GANGNAM("강남구", "강남구"),
    GANGDONG("강동구", "강동구"),
    GANGBUK("강북구", "강북구"),
    GANGSEO("강서구", "강서구"),
    GWANAK("관악구", "관악구"),
    GWANGJIN("광진구", "광진구"),
    GURO("구로구", "구로구"),
    GEUMCHEON("금천구", "금천구"),
    NOWON("노원구", "노원구"),
    DOBONG("도봉구", "도봉구"),
    DONGDAEMUN("동대문구", "동대문구"),
    DONGJAK("동작구", "동작구"),
    MAPO("마포구", "마포구"),
    SEODAEMUN("서대문구", "서대문구"),
    SEOCHO("서초구", "서초구"),
    SEONGDONG("성동구", "성동구"),
    SEONGBUK("성북구", "성북구"),
    SONGPA("송파구", "송파구"),
    YANGCHEON("양천구", "양천구"),
    YEONGDEUNGPO("영등포구", "영등포구"),
    YONGSAN("용산구", "용산구"),
    EUNPYEONG("은평구", "은평구"),
    JONGNO("종로구", "종로구"),
    JUNG("중구", "중구"),
    JUNGNANG("중랑구", "중랑구"),
    ;

    companion object {
        val seoulDistricts: List<BenefitDistrict> = entries.filterNot { it == ALL }
        val seoulDistrictNames: List<String> = seoulDistricts.mapNotNull { it.districtName }
    }
}

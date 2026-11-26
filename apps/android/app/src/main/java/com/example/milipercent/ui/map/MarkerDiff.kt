package com.example.milipercent.ui.map

internal data class MarkerDiffPlan(
    val toRemoveIds: List<String>,
    val toAdd: List<BenefitMapItem>,
    val toUpdate: List<BenefitMapItem>,
)

internal const val DEFAULT_MAX_RENDERED_MARKERS = 300

internal fun selectMapMarkerCandidates(
    benefits: List<BenefitMapItem>,
    selectedBenefitId: String?,
    maxMarkers: Int = DEFAULT_MAX_RENDERED_MARKERS,
    isInView: (BenefitMapItem) -> Boolean,
): List<BenefitMapItem> {
    if (maxMarkers <= 0) return emptyList()
    if (benefits.size <= maxMarkers) return benefits

    val result = ArrayList<BenefitMapItem>(maxMarkers)
    val includedIds = HashSet<String>(maxMarkers)
    if (selectedBenefitId != null) {
        benefits.firstOrNull { it.id == selectedBenefitId }?.let { selected ->
            result += selected
            includedIds += selected.id
        }
    }
    for (item in benefits) {
        if (result.size == maxMarkers) break
        if (item.id !in includedIds && isInView(item)) {
            result += item
            includedIds += item.id
        }
    }
    if (result.size < maxMarkers) {
        for (item in benefits) {
            if (result.size == maxMarkers) break
            if (item.id !in includedIds) {
                result += item
                includedIds += item.id
            }
        }
    }
    return result
}

internal fun computeMarkerDiff(
    renderedItems: Map<String, BenefitMapItem>,
    previousSelectedId: String?,
    nextItems: List<BenefitMapItem>,
    nextSelectedId: String?,
): MarkerDiffPlan {
    val nextById = nextItems.associateBy(BenefitMapItem::id)
    val toRemoveIds = renderedItems.keys.filter { it !in nextById }
    val toAdd = mutableListOf<BenefitMapItem>()
    val toUpdate = mutableListOf<BenefitMapItem>()
    for (item in nextItems) {
        val prev = renderedItems[item.id]
        if (prev == null) {
            toAdd += item
        } else {
            val selectionChanged = (item.id == previousSelectedId) != (item.id == nextSelectedId)
            if (prev != item || selectionChanged) {
                toUpdate += item
            }
        }
    }
    return MarkerDiffPlan(toRemoveIds = toRemoveIds, toAdd = toAdd, toUpdate = toUpdate)
}

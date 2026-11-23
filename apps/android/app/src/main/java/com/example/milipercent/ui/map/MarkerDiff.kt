package com.example.milipercent.ui.map

internal data class MarkerDiffPlan(
    val toRemoveIds: List<String>,
    val toAdd: List<BenefitMapItem>,
    val toUpdate: List<BenefitMapItem>,
)

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

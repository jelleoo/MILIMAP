package com.example.milipercent.ui.map

internal fun markerSetSignature(items: Iterable<BenefitMapItem>): String =
    items.sortedBy(BenefitMapItem::id).joinToString("|") { item ->
        "${item.id}\u0000${item.name}\u0000${item.category}\u0000${item.latitude}\u0000${item.longitude}"
    }

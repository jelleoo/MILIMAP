package com.example.milipercent.data.local

internal const val SQLITE_DELETE_CHUNK_SIZE = 500

internal data class BenefitSourceDiff(
    val toUpsert: List<BenefitEntity>,
    val removedIds: List<String>,
)

internal fun computeBenefitSourceDiff(
    existing: List<BenefitEntity>,
    incoming: List<BenefitEntity>,
): BenefitSourceDiff {
    val existingById = existing.associateBy(BenefitEntity::id)
    val incomingIds = incoming.mapTo(HashSet(incoming.size), BenefitEntity::id)
    val removedIds = existingById.keys.filterNot { it in incomingIds }
    val toUpsert = incoming.filter { item -> existingById[item.id] != item }
    return BenefitSourceDiff(toUpsert = toUpsert, removedIds = removedIds)
}

internal fun computeRetiredIds(
    existingIds: List<String>,
    retainedIds: List<String>,
): List<String> {
    val retainedSet = retainedIds.toHashSet()
    return existingIds.filterNot { it in retainedSet }
}

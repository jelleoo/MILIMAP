package com.example.milipercent.ui.map

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MarkerDiffTest {
    @Test
    fun `selection change updates only previously and newly selected markers`() {
        val items = (1..200).map { item("id-$it") }
        val rendered = items.associateBy(BenefitMapItem::id)

        val selectOne = computeMarkerDiff(rendered, previousSelectedId = null, nextItems = items, nextSelectedId = "id-42")
        assertTrue(selectOne.toRemoveIds.isEmpty())
        assertTrue(selectOne.toAdd.isEmpty())
        assertEquals(listOf("id-42"), selectOne.toUpdate.map(BenefitMapItem::id))

        val switchSelection = computeMarkerDiff(rendered, previousSelectedId = "id-42", nextItems = items, nextSelectedId = "id-99")
        assertTrue(switchSelection.toRemoveIds.isEmpty())
        assertTrue(switchSelection.toAdd.isEmpty())
        assertEquals(setOf("id-42", "id-99"), switchSelection.toUpdate.map(BenefitMapItem::id).toSet())
    }

    @Test
    fun `identical items and selection produce empty diff`() {
        val items = listOf(item("a"), item("b"))
        val rendered = items.associateBy(BenefitMapItem::id)

        val diff = computeMarkerDiff(rendered, previousSelectedId = "a", nextItems = items, nextSelectedId = "a")

        assertTrue(diff.toRemoveIds.isEmpty())
        assertTrue(diff.toAdd.isEmpty())
        assertTrue(diff.toUpdate.isEmpty())
    }

    @Test
    fun `updated properties and viewport changes target only affected markers`() {
        val a = item("a", name = "A")
        val b = item("b", name = "B")
        val rendered = mapOf("a" to a, "b" to b)
        val bUpdated = item("b", name = "B 리뉴얼", latitude = 37.56)
        val cAdded = item("c", name = "C")

        val diff = computeMarkerDiff(rendered, previousSelectedId = null, nextItems = listOf(bUpdated, cAdded), nextSelectedId = null)

        assertEquals(listOf("a"), diff.toRemoveIds)
        assertEquals(listOf("c"), diff.toAdd.map(BenefitMapItem::id))
        assertEquals(listOf("b"), diff.toUpdate.map(BenefitMapItem::id))
    }

    @Test
    fun `selected marker is always retained even beyond marker cap`() {
        val items = (1..350).map { item("id-$it") }

        val selected = selectMapMarkerCandidates(
            benefits = items,
            selectedBenefitId = "id-340",
            isInView = { true },
        )

        assertEquals(DEFAULT_MAX_RENDERED_MARKERS, selected.size)
        assertEquals(DEFAULT_MAX_RENDERED_MARKERS, selected.map(BenefitMapItem::id).toSet().size)
        assertTrue(selected.any { it.id == "id-340" })
    }

    @Test
    fun `out-of-view selected marker is retained when in-view markers exceed cap`() {
        val items = listOf(item("selected")) + (1..350).map { item("id-$it") }

        val selected = selectMapMarkerCandidates(
            benefits = items,
            selectedBenefitId = "selected",
            isInView = { it.id != "selected" },
        )

        assertEquals(DEFAULT_MAX_RENDERED_MARKERS, selected.size)
        assertEquals("selected", selected.first().id)
        assertEquals(DEFAULT_MAX_RENDERED_MARKERS, selected.map(BenefitMapItem::id).toSet().size)
    }

    private fun item(
        id: String,
        name: String = "가게 $id",
        category: String = "음식",
        latitude: Double = 37.55,
        longitude: Double = 126.92,
    ) = BenefitMapItem(id, name, category, latitude, longitude)
}

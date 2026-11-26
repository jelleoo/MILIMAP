package com.example.milipercent.ui.map

import androidx.lifecycle.Lifecycle
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MapViewLifecycleTest {
    @Test
    fun `resumed dispose unwinds pause stop destroy in order`() {
        val calls = mutableListOf<String>()
        val controller = controller(calls)

        controller.onEvent(Lifecycle.Event.ON_START)
        controller.onEvent(Lifecycle.Event.ON_RESUME)
        controller.dispose()

        assertEquals(listOf("start", "resume", "pause", "stop", "destroy"), calls)
        assertTrue(controller.isDestroyed)
    }

    @Test
    fun `onDestroy followed by dispose invokes destroy only once`() {
        val calls = mutableListOf<String>()
        val controller = controller(calls)

        controller.onEvent(Lifecycle.Event.ON_START)
        controller.onEvent(Lifecycle.Event.ON_RESUME)
        controller.onEvent(Lifecycle.Event.ON_PAUSE)
        controller.onEvent(Lifecycle.Event.ON_STOP)
        controller.onEvent(Lifecycle.Event.ON_DESTROY)
        controller.dispose()

        assertEquals(listOf("start", "resume", "pause", "stop", "destroy"), calls)
        assertEquals(1, calls.count { it == "destroy" })
        assertTrue(controller.isDestroyed)
    }

    @Test
    fun `started dispose calls stop then destroy without pause`() {
        val calls = mutableListOf<String>()
        val controller = controller(calls)

        controller.onEvent(Lifecycle.Event.ON_START)
        controller.dispose()

        assertEquals(listOf("start", "stop", "destroy"), calls)
        assertTrue(controller.isDestroyed)
    }

    @Test
    fun `duplicate and post-destroy events are ignored`() {
        val calls = mutableListOf<String>()
        val controller = controller(calls)

        assertFalse(controller.isDestroyed)
        controller.onEvent(Lifecycle.Event.ON_START)
        controller.onEvent(Lifecycle.Event.ON_START)
        controller.onEvent(Lifecycle.Event.ON_RESUME)
        controller.onEvent(Lifecycle.Event.ON_RESUME)
        controller.onEvent(Lifecycle.Event.ON_PAUSE)
        controller.onEvent(Lifecycle.Event.ON_PAUSE)
        controller.onEvent(Lifecycle.Event.ON_STOP)
        controller.onEvent(Lifecycle.Event.ON_STOP)
        controller.onEvent(Lifecycle.Event.ON_DESTROY)
        controller.onEvent(Lifecycle.Event.ON_START)
        controller.onEvent(Lifecycle.Event.ON_RESUME)

        assertEquals(listOf("start", "resume", "pause", "stop", "destroy"), calls)
        assertTrue(controller.isDestroyed)
    }

    private fun controller(calls: MutableList<String>) = MapViewLifecycleController(
        onStart = { calls += "start" },
        onResume = { calls += "resume" },
        onPause = { calls += "pause" },
        onStop = { calls += "stop" },
        onDestroy = { calls += "destroy" },
    )
}

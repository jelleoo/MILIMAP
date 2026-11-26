package com.example.milipercent.ui.map

import androidx.lifecycle.Lifecycle

internal class MapViewLifecycleController(
    private val onStart: () -> Unit,
    private val onResume: () -> Unit,
    private val onPause: () -> Unit,
    private val onStop: () -> Unit,
    private val onDestroy: () -> Unit,
) {
    enum class State {
        CREATED,
        STARTED,
        RESUMED,
        DESTROYED,
    }

    var state: State = State.CREATED
        private set

    val isDestroyed: Boolean
        get() = state == State.DESTROYED

    fun onEvent(event: Lifecycle.Event) {
        when (event) {
            Lifecycle.Event.ON_START -> {
                if (state == State.CREATED) {
                    state = State.STARTED
                    onStart()
                }
            }

            Lifecycle.Event.ON_RESUME -> {
                when (state) {
                    State.CREATED -> {
                        state = State.STARTED
                        onStart()
                        state = State.RESUMED
                        onResume()
                    }

                    State.STARTED -> {
                        state = State.RESUMED
                        onResume()
                    }

                    State.RESUMED, State.DESTROYED -> Unit
                }
            }

            Lifecycle.Event.ON_PAUSE -> {
                if (state == State.RESUMED) {
                    state = State.STARTED
                    onPause()
                }
            }

            Lifecycle.Event.ON_STOP -> {
                when (state) {
                    State.RESUMED -> {
                        state = State.STARTED
                        onPause()
                        state = State.CREATED
                        onStop()
                    }

                    State.STARTED -> {
                        state = State.CREATED
                        onStop()
                    }

                    State.CREATED, State.DESTROYED -> Unit
                }
            }

            Lifecycle.Event.ON_DESTROY -> destroy()
            else -> Unit
        }
    }

    fun dispose() {
        destroy()
    }

    private fun destroy() {
        if (state == State.DESTROYED) return
        if (state == State.RESUMED) {
            state = State.STARTED
            onPause()
        }
        if (state == State.STARTED) {
            state = State.CREATED
            onStop()
        }
        state = State.DESTROYED
        onDestroy()
    }
}

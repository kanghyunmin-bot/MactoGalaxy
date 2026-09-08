package com.mtog.core

import kotlinx.serialization.Serializable
import kotlin.math.hypot

@Serializable
data class GestureEvent(
    val kind: String,
    val timeMs: Long,
    val pointers: Int,
    val x: Double,
    val y: Double
)

@Serializable
data class GestureCommand(
    val kind: String,
    val x: Double? = null,
    val y: Double? = null,
    val deltaX: Double? = null,
    val deltaY: Double? = null,
    val button: String? = null,
    val tapCount: Int? = null
)

class GestureStateMachine {
    companion object {
        const val doubleTapDelayMs = 480L
        const val longPressDelayMs = 700L
    }

    private val tapMoveTolerance = 0.025
    private val doubleTapTolerance = 0.04
    private val tapMaxDurationMs = 350L

    private var down: GestureEvent? = null
    private var dragging = false
    private var longPressFired = false
    private var pendingTap: GestureEvent? = null
    private var twoFingerPoint: Pair<Double, Double>? = null

    fun process(event: GestureEvent): List<GestureCommand> {
        val commands = mutableListOf<GestureCommand>()
        if (event.kind == "tick") {
            commands += flushTimers(event.timeMs)
            return commands
        }

        pendingTap?.let {
            if (event.timeMs > it.timeMs + doubleTapDelayMs) {
                commands += emitPendingTap()
            }
        }

        if (event.pointers >= 2 || event.kind == "pointerDown" || event.kind == "pointerUp") {
            commands += processTwoFinger(event)
            return commands
        }

        when (event.kind) {
            "down" -> {
                pendingTap?.let { if (distance(it, event) > doubleTapTolerance) commands += emitPendingTap() }
                down = event
                dragging = false
                longPressFired = false
                twoFingerPoint = null
            }
            "move" -> down?.let { start ->
                if (longPressFired) {
                    Unit
                } else if (dragging) {
                    commands += GestureCommand("drag", event.x, event.y, button = "left")
                } else if (distance(start, event) > tapMoveTolerance) {
                    commands += emitPendingTap()
                    dragging = true
                    commands += GestureCommand("buttonDown", start.x, start.y, button = "left")
                    commands += GestureCommand("drag", event.x, event.y, button = "left")
                } else {
                    commands += fireLongPressIfNeeded(event.timeMs)
                }
            }
            "up" -> {
                val start = down
                if (dragging) {
                    commands += GestureCommand("buttonUp", event.x, event.y, button = "left")
                } else if (!longPressFired && start != null &&
                    event.timeMs - start.timeMs <= tapMaxDurationMs &&
                    distance(start, event) <= tapMoveTolerance
                ) {
                    val previous = pendingTap
                    if (previous != null && event.timeMs <= previous.timeMs + doubleTapDelayMs &&
                        distance(previous, event) <= doubleTapTolerance
                    ) {
                        pendingTap = null
                        commands += GestureCommand("click", event.x, event.y, button = "left", tapCount = 2)
                    } else {
                        commands += emitPendingTap()
                        pendingTap = event
                    }
                }
                clearContact()
            }
            "cancel" -> {
                if (dragging) commands += GestureCommand("buttonUp", event.x, event.y, button = "left")
                reset()
            }
        }
        return commands
    }

    fun cancel(x: Double, y: Double, timeMs: Long): List<GestureCommand> =
        process(GestureEvent("cancel", timeMs, 1, x, y))

    private fun flushTimers(timeMs: Long): List<GestureCommand> {
        val commands = fireLongPressIfNeeded(timeMs).toMutableList()
        pendingTap?.let {
            if (timeMs > it.timeMs + doubleTapDelayMs) commands += emitPendingTap()
        }
        return commands
    }

    private fun fireLongPressIfNeeded(timeMs: Long): List<GestureCommand> {
        val start = down ?: return emptyList()
        if (dragging || longPressFired || timeMs < start.timeMs + longPressDelayMs) return emptyList()
        longPressFired = true
        return emitPendingTap() + GestureCommand("click", start.x, start.y, button = "right", tapCount = 1)
    }

    private fun emitPendingTap(): List<GestureCommand> {
        val tap = pendingTap ?: return emptyList()
        pendingTap = null
        return listOf(GestureCommand("click", tap.x, tap.y, button = "left", tapCount = 1))
    }

    private fun processTwoFinger(event: GestureEvent): List<GestureCommand> {
        val commands = mutableListOf<GestureCommand>()
        if (dragging) commands += GestureCommand("buttonUp", event.x, event.y, button = "left")
        clearContact()
        commands += emitPendingTap()
        when (event.kind) {
            "pointerDown", "down" -> twoFingerPoint = event.x to event.y
            "move" -> {
                twoFingerPoint?.let { previous ->
                    commands += GestureCommand(
                        "scroll",
                        deltaX = rounded(previous.first - event.x),
                        deltaY = rounded(previous.second - event.y)
                    )
                }
                twoFingerPoint = event.x to event.y
            }
            "pointerUp", "up", "cancel" -> twoFingerPoint = null
        }
        return commands
    }

    private fun clearContact() {
        down = null
        dragging = false
        longPressFired = false
    }

    private fun reset() {
        clearContact()
        pendingTap = null
        twoFingerPoint = null
    }

    private fun distance(lhs: GestureEvent, rhs: GestureEvent): Double = hypot(lhs.x - rhs.x, lhs.y - rhs.y)

    private fun rounded(value: Double): Double = kotlin.math.round(value * 1_000_000) / 1_000_000
}

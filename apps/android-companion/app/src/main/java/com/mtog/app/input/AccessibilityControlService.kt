package com.mtog.app.input

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.ClipData
import android.content.ClipboardManager
import android.graphics.Path
import android.graphics.PointF
import android.os.Bundle
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

class AccessibilityControlService : AccessibilityService() {
    companion object {
        private const val tag = "MtoG.Accessibility"
        private const val touchMoveDurationMs = 24L
        private const val touchHoldDurationMs = 48L
        private const val touchReleaseDurationMs = 24L
        private const val touchDeltaThresholdPx = 1.5f
        private const val pinchTouchDownDurationMs = 28L
        private const val pinchMoveDurationMs = 136L
    }

    private var remoteCursorOverlay: RemoteCursorOverlay? = null
    private val touchLock = Any()
    private var touchStroke: GestureDescription.StrokeDescription? = null
    private var touchInFlight = false
    private var touchPressed = false
    private var pendingRelease = false
    private var finalSegmentDispatched = false
    private var lastTouchPoint: PointF? = null
    private var pendingTouchPoint: PointF? = null
    @Volatile
    private var pinchInFlight = false

    override fun onServiceConnected() {
        super.onServiceConnected()
        remoteCursorOverlay = RemoteCursorOverlay(this)
        RemoteInputBridge.attach(this)
        ControlServiceRuntime.markConnected(canPerformGestures = true)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Remote-control mode does not require event inspection for MVP.
    }

    override fun onInterrupt() {
        resetTouchState()
        remoteCursorOverlay?.hide()
        RemoteInputBridge.detach(this)
        ControlServiceRuntime.markDisconnected()
    }

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        resetTouchState()
        remoteCursorOverlay?.hide()
        RemoteInputBridge.detach(this)
        ControlServiceRuntime.markDisconnected()
        return super.onUnbind(intent)
    }

    fun performBack(): Boolean {
        return performGlobalAction(GLOBAL_ACTION_BACK)
    }

    fun performHome(): Boolean {
        return performGlobalAction(GLOBAL_ACTION_HOME)
    }

    fun dispatchTap(x: Float, y: Float): Boolean {
        val path = Path().apply {
            moveTo(x, y)
        }
        val stroke = GestureDescription.StrokeDescription(path, 0, 40)
        val gesture = GestureDescription.Builder()
            .addStroke(stroke)
            .build()

        return dispatchGesture(gesture, null, null)
    }

    fun dispatchNormalizedTap(normalizedX: Float, normalizedY: Float): Boolean {
        val clampedX = normalizedX.coerceIn(0f, 1f)
        val clampedY = normalizedY.coerceIn(0f, 1f)
        return dispatchTap(
            x = DisplayGeometry.currentWidth(this) * clampedX,
            y = DisplayGeometry.currentHeight(this) * clampedY
        )
    }

    fun dispatchNormalizedGesture(
        startX: Float,
        startY: Float,
        endX: Float,
        endY: Float,
        durationMs: Long
    ): Boolean {
        val clampedStartX = startX.coerceIn(0f, 1f)
        val clampedStartY = startY.coerceIn(0f, 1f)
        val clampedEndX = endX.coerceIn(0f, 1f)
        val clampedEndY = endY.coerceIn(0f, 1f)
        val width = DisplayGeometry.currentWidth(this).toFloat()
        val height = DisplayGeometry.currentHeight(this).toFloat()
        val actualStartX = width * clampedStartX
        val actualStartY = height * clampedStartY
        val actualEndX = width * clampedEndX
        val actualEndY = height * clampedEndY
        val stationary = kotlin.math.abs(actualStartX - actualEndX) < 1.5f &&
            kotlin.math.abs(actualStartY - actualEndY) < 1.5f

        val path = Path().apply {
            moveTo(actualStartX, actualStartY)
            if (!stationary) {
                lineTo(actualEndX, actualEndY)
            }
        }
        val stroke = GestureDescription.StrokeDescription(
            path,
            0,
            durationMs.coerceIn(if (stationary) 120L else 40L, 1800L)
        )
        val gesture = GestureDescription.Builder()
            .addStroke(stroke)
            .build()

        return dispatchGesture(gesture, null, null)
    }

    fun dispatchNormalizedLongPress(
        normalizedX: Float,
        normalizedY: Float,
        durationMs: Long
    ): Boolean {
        return dispatchNormalizedGesture(
            startX = normalizedX,
            startY = normalizedY,
            endX = normalizedX,
            endY = normalizedY,
            durationMs = durationMs.coerceAtLeast(420L)
        )
    }

    fun dispatchNormalizedPinch(
        centerX: Float,
        centerY: Float,
        magnification: Float
    ): Boolean {
        if (pinchInFlight) {
            Log.d(tag, "Ignored overlapping pinch center=($centerX,$centerY) magnification=$magnification")
            return false
        }

        val width = DisplayGeometry.currentWidth(this).toFloat()
        val height = DisplayGeometry.currentHeight(this).toFloat()
        val centerPoint = normalizedPoint(centerX, centerY)
        val safeCenterX = centerPoint.x.coerceIn(width * 0.18f, width * 0.82f)
        val safeCenterY = centerPoint.y.coerceIn(height * 0.18f, height * 0.82f)
        val clampedMagnification = magnification.coerceIn(-1.2f, 1.2f)
        val baseSpan = minOf(width, height) * 0.11f
        val zoomIn = clampedMagnification >= 0f
        val magnitude = kotlin.math.abs(clampedMagnification)
        val maxHorizontalSpan = minOf(safeCenterX, width - safeCenterX) * 0.68f
        val maxVerticalSpan = minOf(safeCenterY, height - safeCenterY) * 0.68f
        val startSpan = (
            baseSpan * if (zoomIn) 0.42f else (1.0f + (magnitude * 0.42f))
            ).coerceIn(40f, minOf(maxHorizontalSpan, maxVerticalSpan))
        val endSpan = (
            baseSpan * if (zoomIn) (1.0f + (magnitude * 0.54f)) else 0.38f
            ).coerceIn(28f, minOf(maxHorizontalSpan, maxVerticalSpan))

        val leftStart = PointF(safeCenterX - startSpan, safeCenterY - startSpan)
        val rightStart = PointF(safeCenterX + startSpan, safeCenterY + startSpan)
        val leftEnd = PointF(safeCenterX - endSpan, safeCenterY - endSpan)
        val rightEnd = PointF(safeCenterX + endSpan, safeCenterY + endSpan)

        val leftHoldPath = Path().apply {
            moveTo(leftStart.x, leftStart.y)
        }
        val rightHoldPath = Path().apply {
            moveTo(rightStart.x, rightStart.y)
        }
        val leftHoldStroke = GestureDescription.StrokeDescription(
            leftHoldPath,
            0,
            pinchTouchDownDurationMs,
            true
        )
        val rightHoldStroke = GestureDescription.StrokeDescription(
            rightHoldPath,
            0,
            pinchTouchDownDurationMs,
            true
        )
        val initialGesture = GestureDescription.Builder()
            .addStroke(leftHoldStroke)
            .addStroke(rightHoldStroke)
            .build()

        pinchInFlight = true
        val phaseOneAccepted = dispatchGesture(
            initialGesture,
            object : GestureResultCallback() {
                override fun onCompleted(gestureDescription: GestureDescription?) {
                    val leftMovePath = Path().apply {
                        moveTo(leftStart.x, leftStart.y)
                        lineTo(leftEnd.x, leftEnd.y)
                    }
                    val rightMovePath = Path().apply {
                        moveTo(rightStart.x, rightStart.y)
                        lineTo(rightEnd.x, rightEnd.y)
                    }
                    val moveGesture = GestureDescription.Builder()
                        .addStroke(leftHoldStroke.continueStroke(leftMovePath, 0, pinchMoveDurationMs, false))
                        .addStroke(rightHoldStroke.continueStroke(rightMovePath, 0, pinchMoveDurationMs, false))
                        .build()
                    val phaseTwoAccepted = dispatchGesture(
                        moveGesture,
                        object : GestureResultCallback() {
                            override fun onCompleted(gestureDescription: GestureDescription?) {
                                pinchInFlight = false
                                Log.d(
                                    tag,
                                    "Pinch completed center=($centerX,$centerY) magnification=$magnification zoomIn=$zoomIn"
                                )
                            }

                            override fun onCancelled(gestureDescription: GestureDescription?) {
                                pinchInFlight = false
                                Log.w(
                                    tag,
                                    "Pinch cancelled during move center=($centerX,$centerY) magnification=$magnification"
                                )
                            }
                        },
                        null
                    )
                    if (!phaseTwoAccepted) {
                        pinchInFlight = false
                    }
                    Log.d(
                        tag,
                        "Pinch phase2 accepted=$phaseTwoAccepted center=($centerX,$centerY) magnification=$magnification"
                    )
                }

                override fun onCancelled(gestureDescription: GestureDescription?) {
                    pinchInFlight = false
                    Log.w(
                        tag,
                        "Pinch cancelled during hold center=($centerX,$centerY) magnification=$magnification"
                    )
                }
            },
            null
        )
        if (!phaseOneAccepted) {
            pinchInFlight = false
        }
        Log.d(
            tag,
            "Pinch phase1 accepted=$phaseOneAccepted center=($centerX,$centerY) magnification=$magnification startSpan=$startSpan endSpan=$endSpan"
        )
        return phaseOneAccepted
    }

    fun beginNormalizedTouch(normalizedX: Float, normalizedY: Float): Boolean {
        synchronized(touchLock) {
            resetTouchStateLocked()
            val point = normalizedPoint(normalizedX, normalizedY)
            touchPressed = true
            pendingRelease = false
            lastTouchPoint = point
            pendingTouchPoint = point
            return dispatchNextTouchSegmentLocked()
        }
    }

    fun moveNormalizedTouch(normalizedX: Float, normalizedY: Float): Boolean {
        synchronized(touchLock) {
            if (lastTouchPoint == null && touchStroke == null && !touchInFlight) {
                return false
            }

            pendingTouchPoint = normalizedPoint(normalizedX, normalizedY)
            if (!touchInFlight) {
                return dispatchNextTouchSegmentLocked()
            }
            return true
        }
    }

    fun endNormalizedTouch(normalizedX: Float, normalizedY: Float): Boolean {
        synchronized(touchLock) {
            if (lastTouchPoint == null && touchStroke == null && !touchInFlight) {
                return false
            }

            touchPressed = false
            pendingRelease = true
            pendingTouchPoint = normalizedPoint(normalizedX, normalizedY)
            if (!touchInFlight) {
                return dispatchNextTouchSegmentLocked()
            }
            return true
        }
    }

    fun insertText(text: String): Boolean {
        if (text.isEmpty()) {
            return false
        }

        val target = findEditableTarget() ?: return false
        val current = target.text?.toString().orEmpty()
        val start = target.textSelectionStart.takeIf { it >= 0 } ?: current.length
        val end = target.textSelectionEnd.takeIf { it >= 0 } ?: start
        val safeStart = start.coerceIn(0, current.length)
        val safeEnd = end.coerceIn(safeStart, current.length)
        val updated = current.replaceRange(safeStart, safeEnd, text)
        return setNodeText(target, updated, selectionIndex = safeStart + text.length)
    }

    fun deleteBackward(): Boolean {
        val target = findEditableTarget() ?: return false
        val current = target.text?.toString().orEmpty()
        if (current.isEmpty()) {
            return false
        }

        val start = target.textSelectionStart.takeIf { it >= 0 } ?: current.length
        val end = target.textSelectionEnd.takeIf { it >= 0 } ?: start
        val safeStart = start.coerceIn(0, current.length)
        val safeEnd = end.coerceIn(safeStart, current.length)

        val updated: String
        val selectionIndex: Int
        if (safeStart != safeEnd) {
            updated = current.removeRange(safeStart, safeEnd)
            selectionIndex = safeStart
        } else if (safeStart > 0) {
            val deleteStart = current.offsetByCodePoints(safeStart, -1)
            updated = current.removeRange(deleteStart, safeStart)
            selectionIndex = deleteStart
        } else {
            return false
        }

        return setNodeText(target, updated, selectionIndex = selectionIndex)
    }

    fun performEnter(): Boolean {
        val target = findEditableTarget() ?: return false
        val imeActionId = AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER.id
        if (target.actionList.any { it.id == imeActionId } && target.performAction(imeActionId)) {
            return true
        }

        return insertText("\n")
    }

    fun pasteFromClipboard(): Boolean {
        val target = findEditableTarget() ?: return false
        if (!target.isFocused) {
            target.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
        }

        val pasteActionId = AccessibilityNodeInfo.AccessibilityAction.ACTION_PASTE.id
        if (target.actionList.any { it.id == pasteActionId } && target.performAction(pasteActionId)) {
            return true
        }

        val clipboardManager = getSystemService(ClipboardManager::class.java)
        val text = clipboardManager?.primaryClip?.getItemAt(0)?.coerceToText(this)?.toString().orEmpty()
        if (text.isEmpty()) {
            return false
        }

        return insertText(text)
    }

    private fun findEditableTarget(): AccessibilityNodeInfo? {
        val focused = rootInActiveWindow?.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        if (focused?.isEditable == true) {
            return focused
        }

        return rootInActiveWindow?.let { findEditableDescendant(it) }
    }

    private fun findEditableDescendant(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        if (node.isEditable && node.isFocused) {
            return node
        }

        for (index in 0 until node.childCount) {
            val child = node.getChild(index) ?: continue
            val match = findEditableDescendant(child)
            if (match != null) {
                return match
            }
        }

        return null
    }

    private fun setNodeText(
        target: AccessibilityNodeInfo,
        text: String,
        selectionIndex: Int
    ): Boolean {
        val textBundle = Bundle().apply {
            putCharSequence(
                AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                text
            )
        }

        if (!target.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, textBundle)) {
            return false
        }

        val selectionBundle = Bundle().apply {
            putInt(
                AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT,
                selectionIndex.coerceAtLeast(0)
            )
            putInt(
                AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT,
                selectionIndex.coerceAtLeast(0)
            )
        }
        target.performAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, selectionBundle)
        return true
    }

    fun showRemoteCursor(normalizedX: Float, normalizedY: Float, pressed: Boolean) {
        remoteCursorOverlay?.show(normalizedX, normalizedY, pressed)
    }

    fun hideRemoteCursor() {
        remoteCursorOverlay?.hide()
    }

    private fun normalizedPoint(normalizedX: Float, normalizedY: Float): PointF {
        val clampedX = normalizedX.coerceIn(0f, 1f)
        val clampedY = normalizedY.coerceIn(0f, 1f)
        return PointF(
            DisplayGeometry.currentWidth(this) * clampedX,
            DisplayGeometry.currentHeight(this) * clampedY
        )
    }

    private fun dispatchNextTouchSegmentLocked(): Boolean {
        val start = lastTouchPoint ?: pendingTouchPoint ?: return false
        val target = pendingTouchPoint ?: start
        val stationary = distanceBetween(start, target) < touchDeltaThresholdPx
        val releaseNow = pendingRelease && !touchPressed
        val durationMs = when {
            releaseNow -> touchReleaseDurationMs
            stationary -> touchHoldDurationMs
            else -> touchMoveDurationMs
        }
        val path = Path().apply {
            moveTo(start.x, start.y)
            if (!stationary) {
                lineTo(target.x, target.y)
            }
        }

        val nextStroke = if (touchStroke == null) {
            GestureDescription.StrokeDescription(
                path,
                0,
                durationMs,
                !releaseNow
            )
        } else {
            touchStroke!!.continueStroke(
                path,
                0,
                durationMs,
                !releaseNow
            )
        }

        val gesture = GestureDescription.Builder()
            .addStroke(nextStroke)
            .build()

        touchStroke = nextStroke
        touchInFlight = true
        finalSegmentDispatched = releaseNow
        lastTouchPoint = target
        pendingTouchPoint = null

        return dispatchGesture(
            gesture,
            object : GestureResultCallback() {
                override fun onCompleted(gestureDescription: GestureDescription?) {
                    synchronized(touchLock) {
                        touchInFlight = false
                        if (finalSegmentDispatched) {
                            resetTouchStateLocked()
                            return
                        }
                        dispatchNextTouchSegmentLocked()
                    }
                }

                override fun onCancelled(gestureDescription: GestureDescription?) {
                    synchronized(touchLock) {
                        resetTouchStateLocked()
                    }
                }
            },
            null
        )
    }

    private fun resetTouchState() {
        synchronized(touchLock) {
            resetTouchStateLocked()
        }
    }

    private fun resetTouchStateLocked() {
        touchStroke = null
        touchInFlight = false
        touchPressed = false
        pendingRelease = false
        finalSegmentDispatched = false
        lastTouchPoint = null
        pendingTouchPoint = null
    }

    private fun distanceBetween(start: PointF, end: PointF): Float {
        val deltaX = end.x - start.x
        val deltaY = end.y - start.y
        return kotlin.math.sqrt((deltaX * deltaX) + (deltaY * deltaY))
    }
}

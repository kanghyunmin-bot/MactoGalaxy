package com.mtog.app.input

import java.lang.ref.WeakReference

object RemoteInputBridge {
    private var serviceRef: WeakReference<AccessibilityControlService>? = null

    fun attach(service: AccessibilityControlService) {
        serviceRef = WeakReference(service)
    }

    fun detach(service: AccessibilityControlService) {
        val current = serviceRef?.get()
        if (current === service) {
            serviceRef?.clear()
            serviceRef = null
        }
    }

    fun isReady(): Boolean {
        return serviceRef?.get() != null
    }

    fun performBack(): Boolean {
        return serviceRef?.get()?.performBack() ?: false
    }

    fun performHome(): Boolean {
        return serviceRef?.get()?.performHome() ?: false
    }

    fun dispatchTap(x: Float, y: Float): Boolean {
        return serviceRef?.get()?.dispatchTap(x, y) ?: false
    }

    fun dispatchNormalizedTap(normalizedX: Float, normalizedY: Float): Boolean {
        return serviceRef?.get()?.dispatchNormalizedTap(normalizedX, normalizedY) ?: false
    }

    fun dispatchNormalizedGesture(
        startX: Float,
        startY: Float,
        endX: Float,
        endY: Float,
        durationMs: Long
    ): Boolean {
        return serviceRef?.get()?.dispatchNormalizedGesture(startX, startY, endX, endY, durationMs) ?: false
    }

    fun dispatchNormalizedLongPress(normalizedX: Float, normalizedY: Float, durationMs: Long): Boolean {
        return serviceRef?.get()?.dispatchNormalizedLongPress(normalizedX, normalizedY, durationMs) ?: false
    }

    fun dispatchNormalizedPinch(centerX: Float, centerY: Float, magnification: Float): Boolean {
        return serviceRef?.get()?.dispatchNormalizedPinch(centerX, centerY, magnification) ?: false
    }

    fun beginNormalizedTouch(normalizedX: Float, normalizedY: Float): Boolean {
        return serviceRef?.get()?.beginNormalizedTouch(normalizedX, normalizedY) ?: false
    }

    fun moveNormalizedTouch(normalizedX: Float, normalizedY: Float): Boolean {
        return serviceRef?.get()?.moveNormalizedTouch(normalizedX, normalizedY) ?: false
    }

    fun endNormalizedTouch(normalizedX: Float, normalizedY: Float): Boolean {
        return serviceRef?.get()?.endNormalizedTouch(normalizedX, normalizedY) ?: false
    }

    fun insertText(text: String): Boolean {
        return serviceRef?.get()?.insertText(text) ?: false
    }

    fun pasteFromClipboard(): Boolean {
        return serviceRef?.get()?.pasteFromClipboard() ?: false
    }

    fun deleteBackward(): Boolean {
        return serviceRef?.get()?.deleteBackward() ?: false
    }

    fun performEnter(): Boolean {
        return serviceRef?.get()?.performEnter() ?: false
    }

    fun showRemoteCursor(normalizedX: Float, normalizedY: Float, pressed: Boolean) {
        serviceRef?.get()?.showRemoteCursor(normalizedX, normalizedY, pressed)
    }

    fun hideRemoteCursor() {
        serviceRef?.get()?.hideRemoteCursor()
    }
}

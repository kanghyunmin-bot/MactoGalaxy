package com.mtog.app.input

import java.lang.ref.WeakReference

object RemoteKeyboardBridge {
    private var serviceRef: WeakReference<RemoteKeyboardService>? = null

    fun attach(service: RemoteKeyboardService) {
        serviceRef = WeakReference(service)
    }

    fun detach(service: RemoteKeyboardService) {
        val current = serviceRef?.get()
        if (current === service) {
            serviceRef?.clear()
            serviceRef = null
        }
    }

    fun commitText(text: String): Boolean {
        return serviceRef?.get()?.commitRemoteText(text) ?: false
    }

    fun deleteBackward(): Boolean {
        return serviceRef?.get()?.deleteRemoteBackward() ?: false
    }

    fun performEnter(): Boolean {
        return serviceRef?.get()?.performRemoteEnter() ?: false
    }
}

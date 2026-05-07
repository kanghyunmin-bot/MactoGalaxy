package com.mtog.app.input

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update

data class KeyboardRuntimeState(
    val isEnabled: Boolean = false,
    val isSelected: Boolean = false,
    val isActive: Boolean = false,
    val statusText: String = "MtoG Keyboard not enabled",
    val detailText: String = "Enable and select MtoG Keyboard for reliable Korean and Unicode input.",
    val canCommitRemotely: Boolean = false
)

object RemoteKeyboardRuntime {
    private val _state = MutableStateFlow(KeyboardRuntimeState())
    val state: StateFlow<KeyboardRuntimeState> = _state

    private var appContext: Context? = null
    private var serviceAttached = false

    fun initialize(context: Context) {
        appContext = context.applicationContext
        refresh()
    }

    fun refresh(context: Context? = appContext) {
        val safeContext = context ?: return
        appContext = safeContext.applicationContext

        val component = ComponentName(safeContext, RemoteKeyboardService::class.java)
        val inputMethodIntent = Intent("android.view.InputMethod").setComponent(component)
        @Suppress("DEPRECATION")
        val isInstalled = safeContext.packageManager.queryIntentServices(inputMethodIntent, 0).isNotEmpty()
        val isEnabled = isInstalled
        val isSelected = serviceAttached
        val isActive = serviceAttached

        _state.update {
            it.copy(
                isEnabled = isEnabled,
                isSelected = isSelected,
                isActive = isActive,
                statusText = when {
                    isActive -> "MtoG Keyboard active"
                    isInstalled -> "MtoG Keyboard installed"
                    else -> "MtoG Keyboard unavailable"
                },
                detailText = when {
                    isActive -> "Remote text is using the hidden IME path. Korean and Unicode input should be more reliable without covering the screen."
                    isInstalled -> "Android 15 blocks apps from reading the full enabled-keyboard list. Open keyboard settings, enable MtoG Keyboard, choose it, then focus a text field."
                    else -> "Remote keyboard service is not visible to the system."
                },
                canCommitRemotely = isActive
            )
        }
    }

    fun markServiceAttached(context: Context) {
        serviceAttached = true
        refresh(context)
    }

    fun markServiceDetached(context: Context) {
        serviceAttached = false
        refresh(context)
    }
}

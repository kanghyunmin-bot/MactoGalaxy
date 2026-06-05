package com.mtog.app.input

import android.content.ComponentName
import android.content.Context
import android.provider.Settings
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update

data class AccessibilityRuntimeState(
    val isEnabled: Boolean = false,
    val statusText: String = "접근성 서비스가 꺼져 있습니다",
    val canPerformGestures: Boolean = false
)

object ControlServiceRuntime {
    private val _state = MutableStateFlow(AccessibilityRuntimeState())
    val state: StateFlow<AccessibilityRuntimeState> = _state

    private var appContext: Context? = null

    fun initialize(context: Context) {
        appContext = context.applicationContext
        refresh()
    }

    fun refresh(context: Context? = appContext) {
        val safeContext = context ?: return
        appContext = safeContext.applicationContext

        val serviceName = ComponentName(safeContext, AccessibilityControlService::class.java).flattenToString()
        val enabled = Settings.Secure.getInt(
            safeContext.contentResolver,
            Settings.Secure.ACCESSIBILITY_ENABLED,
            0
        ) == 1
        val enabledServices = Settings.Secure.getString(
            safeContext.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ).orEmpty()
        val serviceListed = enabledServices.split(':').any { it.equals(serviceName, ignoreCase = true) }

        if (!enabled || !serviceListed) {
            _state.value = AccessibilityRuntimeState(
                isEnabled = false,
                statusText = "접근성 꺼짐: 원격 커서와 제스처를 사용할 수 없습니다",
                canPerformGestures = false
            )
        }
    }

    fun markConnected(canPerformGestures: Boolean) {
        _state.update {
            it.copy(
                isEnabled = true,
                statusText = "접근성 서비스 연결됨",
                canPerformGestures = canPerformGestures
            )
        }
    }

    fun markDisconnected() {
        _state.update { AccessibilityRuntimeState() }
    }
}

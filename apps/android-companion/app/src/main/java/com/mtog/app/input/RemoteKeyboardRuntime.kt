package com.mtog.app.input

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update

data class KeyboardRuntimeState(
    val isEnabled: Boolean = false,
    val isSelected: Boolean = false,
    val isActive: Boolean = false,
    val statusText: String = "MtoG 키보드가 꺼져 있습니다",
    val detailText: String = "한글과 유니코드 입력을 안정적으로 쓰려면 MtoG 키보드를 켜고 선택하세요.",
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
        val isInstalled = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                safeContext.packageManager.getServiceInfo(component, PackageManager.ComponentInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                safeContext.packageManager.getServiceInfo(component, 0)
            }
            true
        }.getOrDefault(false)
        val isEnabled = isInstalled
        val isSelected = serviceAttached
        val isActive = serviceAttached

        _state.update {
            it.copy(
                isEnabled = isEnabled,
                isSelected = isSelected,
                isActive = isActive,
                statusText = when {
                    isActive -> "MtoG 키보드 사용 중"
                    isInstalled -> "MtoG 키보드 설치됨"
                    else -> "MtoG 키보드를 사용할 수 없습니다"
                },
                detailText = when {
                    isActive -> "원격 텍스트가 MtoG 입력기 경로로 들어갑니다. 화면을 가리지 않고 한글/유니코드 입력이 더 안정적으로 동작합니다."
                    isInstalled -> "Android 정책상 앱이 입력기 선택 상태를 완전히 읽지 못할 수 있습니다. 키보드 설정에서 MtoG 키보드를 켜고 선택한 뒤 입력창을 눌러주세요."
                    else -> "원격 키보드 서비스가 시스템에 표시되지 않습니다."
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

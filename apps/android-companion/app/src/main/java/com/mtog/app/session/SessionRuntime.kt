package com.mtog.app.session

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update

data class SessionRuntimeState(
    val serviceState: String = "중지됨",
    val lanEndpoint: String = "Wi-Fi 주소를 아직 확인하지 못했습니다",
    val peerDeviceName: String = "연결된 Mac 없음",
    val lastInboundType: String = "없음",
    val lastOutboundType: String = "없음",
    val lastControlEvent: String = "없음",
    val lastClipboardEvent: String = "클립보드 동기화 대기 중",
    val discoveryState: String = "Wi-Fi 검색 대기 중",
    val lastError: String? = null
)

object SessionRuntime {
    private val _state = MutableStateFlow(SessionRuntimeState())
    val state: StateFlow<SessionRuntimeState> = _state

    fun markStarting() {
        _state.update { it.copy(serviceState = "수신 서버 시작 중", lastError = null) }
    }

    fun markListening(port: Int, lanEndpoint: String) {
        _state.update {
            it.copy(
                serviceState = "USB/Wi-Fi 수신 중 · 포트 $port",
                lanEndpoint = lanEndpoint,
                lastError = null
            )
        }
    }

    fun markConnected(peerDeviceName: String) {
        _state.update { it.copy(serviceState = "연결됨", peerDeviceName = peerDeviceName, lastError = null) }
    }

    fun markInbound(type: String) {
        _state.update { it.copy(lastInboundType = type, lastError = null) }
    }

    fun markOutbound(type: String) {
        _state.update { it.copy(lastOutboundType = type, lastError = null) }
    }

    fun markControlEvent(description: String) {
        _state.update { it.copy(lastControlEvent = description, lastError = null) }
    }

    fun markClipboardEvent(description: String) {
        _state.update { it.copy(lastClipboardEvent = description, lastError = null) }
    }

    fun markDiscovery(description: String) {
        _state.update { it.copy(discoveryState = description, lastError = null) }
    }

    fun markDisconnected() {
        _state.update {
            it.copy(
                serviceState = "재연결 대기 중",
                peerDeviceName = "연결된 Mac 없음"
            )
        }
    }

    fun markStopped() {
        _state.update { SessionRuntimeState() }
    }

    fun markError(message: String) {
        _state.update { it.copy(serviceState = "오류", lastError = message) }
    }
}

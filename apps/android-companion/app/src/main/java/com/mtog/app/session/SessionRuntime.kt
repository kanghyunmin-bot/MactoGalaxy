package com.mtog.app.session

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update

data class SessionRuntimeState(
    val serviceState: String = "Stopped",
    val lanEndpoint: String = "Wireless LAN endpoint unavailable",
    val peerDeviceName: String = "No peer",
    val lastInboundType: String = "None",
    val lastOutboundType: String = "None",
    val lastControlEvent: String = "None",
    val lastClipboardEvent: String = "Manual clipboard sync idle",
    val lastError: String? = null
)

object SessionRuntime {
    private val _state = MutableStateFlow(SessionRuntimeState())
    val state: StateFlow<SessionRuntimeState> = _state

    fun markStarting() {
        _state.update { it.copy(serviceState = "Starting listener", lastError = null) }
    }

    fun markListening(port: Int, lanEndpoint: String) {
        _state.update {
            it.copy(
                serviceState = "Listening on USB loopback + Wi-Fi/LAN:$port",
                lanEndpoint = lanEndpoint,
                lastError = null
            )
        }
    }

    fun markConnected(peerDeviceName: String) {
        _state.update { it.copy(serviceState = "Connected", peerDeviceName = peerDeviceName, lastError = null) }
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

    fun markDisconnected() {
        _state.update {
            it.copy(
                serviceState = "Waiting for reconnect",
                peerDeviceName = "No peer"
            )
        }
    }

    fun markStopped() {
        _state.update { SessionRuntimeState() }
    }

    fun markError(message: String) {
        _state.update { it.copy(serviceState = "Error", lastError = message) }
    }
}

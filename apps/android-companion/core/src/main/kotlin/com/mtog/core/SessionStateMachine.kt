package com.mtog.core

enum class SessionState { Idle, Connecting, Connected, Reconnecting, StoppedByUser, Failed }
enum class SessionEvent { Start, Connected, TransportFailed, Retry, UserStopped, Exhausted }

class SessionStateMachine {
    var state: SessionState = SessionState.Idle
        private set

    fun handle(event: SessionEvent) {
        if (state == SessionState.StoppedByUser) return
        state = when (event) {
            SessionEvent.Start -> SessionState.Connecting
            SessionEvent.Connected -> SessionState.Connected
            SessionEvent.TransportFailed, SessionEvent.Retry -> SessionState.Reconnecting
            SessionEvent.UserStopped -> SessionState.StoppedByUser
            SessionEvent.Exhausted -> SessionState.Failed
        }
    }
}

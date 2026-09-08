package com.mtog.core

class SessionReplayGuard {
    private var activeSessionId: String? = null
    private var activeToken: String? = null
    private var activeClientNonce: String? = null
    private var activeServerNonce: String? = null
    private var activeGeneration: Long? = null
    private var highestSequence = 0L

    fun begin(
        sessionId: String,
        token: String,
        clientNonce: String,
        serverNonce: String,
        generation: Long
    ) {
        activeSessionId = sessionId
        activeToken = token
        activeClientNonce = clientNonce
        activeServerNonce = serverNonce
        activeGeneration = generation
        highestSequence = 0
    }

    fun reset() {
        activeSessionId = null
        activeToken = null
        activeClientNonce = null
        activeServerNonce = null
        activeGeneration = null
        highestSequence = 0
    }

    fun accept(
        sessionId: String,
        token: String,
        clientNonce: String,
        serverNonce: String,
        sequence: Long,
        generation: Long
    ): Boolean {
        if (sessionId != activeSessionId || token != activeToken ||
            clientNonce != activeClientNonce || serverNonce != activeServerNonce ||
            generation != activeGeneration || sequence <= highestSequence
        ) {
            return false
        }
        highestSequence = sequence
        return true
    }
}

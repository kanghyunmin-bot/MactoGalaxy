package com.mtog.app.session

class SessionReplayGuard {
    private val highestSequenceBySession = mutableMapOf<String, Long>()

    fun reset() {
        highestSequenceBySession.clear()
    }

    fun accept(message: SessionEnvelope): Boolean {
        val previous = highestSequenceBySession[message.sessionId]
        if (previous != null && message.sequenceNo <= previous) {
            return false
        }

        highestSequenceBySession[message.sessionId] = message.sequenceNo
        return true
    }
}

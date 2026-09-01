package com.mtog.core

sealed class ClipboardReceiveResult {
    data class Accepted(val content: String) : ClipboardReceiveResult()
    data object LocalSource : ClipboardReceiveResult()
    data object StaleSession : ClipboardReceiveResult()
    data object Replayed : ClipboardReceiveResult()
    data object InvalidHash : ClipboardReceiveResult()
    data object ContentTooLarge : ClipboardReceiveResult()
    data object InvalidEvent : ClipboardReceiveResult()
    data object Loop : ClipboardReceiveResult()
}

class ClipboardSyncEngine(
    val sourceID: String,
    sessionID: String,
    private val recentHashCapacity: Int = 128
) {
    var sessionID: String = sessionID
        private set
    private var nextSequence = 0L
    private val highestSequenceBySource = mutableMapOf<String, Long>()
    private val recentHashes = ArrayDeque<String>()

    init {
        require(sourceID.isNotBlank() && sessionID.isNotBlank() && recentHashCapacity > 0)
    }

    fun begin(sessionID: String) {
        require(sessionID.isNotBlank())
        this.sessionID = sessionID
        nextSequence = 0
        highestSequenceBySource.clear()
    }

    fun makeLocalEvent(kind: AutomaticClipboardKind, content: String): ClipboardEvent {
        nextSequence += 1
        return ClipboardEvent.make(sourceID, sessionID, nextSequence, kind, content).also {
            remember(it.contentHash)
        }
    }

    fun receive(event: ClipboardEvent): ClipboardReceiveResult {
        if (event.sourceID.isBlank() || event.sessionID.isBlank() || event.sequence <= 0 || event.content.isEmpty()) {
            return ClipboardReceiveResult.InvalidEvent
        }
        if (event.sourceID == sourceID) return ClipboardReceiveResult.LocalSource
        if (event.sessionID != sessionID) return ClipboardReceiveResult.StaleSession
        val highest = highestSequenceBySource[event.sourceID]
        if (highest != null && event.sequence <= highest) return ClipboardReceiveResult.Replayed
        if (event.content.toByteArray(Charsets.UTF_8).size > ProtocolLimits.AUTOMATIC_CLIPBOARD_BYTES) {
            return ClipboardReceiveResult.ContentTooLarge
        }
        if (event.contentHash != ClipboardEvent.hash(event.content)) return ClipboardReceiveResult.InvalidHash
        highestSequenceBySource[event.sourceID] = event.sequence
        if (event.contentHash in recentHashes) return ClipboardReceiveResult.Loop
        remember(event.contentHash)
        return ClipboardReceiveResult.Accepted(event.content)
    }

    private fun remember(hash: String) {
        recentHashes.remove(hash)
        recentHashes.addLast(hash)
        while (recentHashes.size > recentHashCapacity) recentHashes.removeFirst()
    }
}

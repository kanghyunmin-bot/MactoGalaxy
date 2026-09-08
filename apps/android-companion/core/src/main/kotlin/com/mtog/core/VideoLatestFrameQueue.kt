package com.mtog.core

import java.util.UUID

class VideoLatestFrameQueue(val capacity: Int) {
    private val storage = ArrayDeque<VideoPacket>()
    var needsKeyframeRecovery = false
        private set
    private var recoverySessionID: UUID? = null
    private var recoveryAfterSequence = 0L
    val count: Int get() = storage.size

    init { require(capacity > 0) }

    fun append(packet: VideoPacket): VideoPacket? {
        require(packet.kind == VideoPacketKind.AccessUnit)
        val dropped = if (storage.size == capacity) storage.removeFirst() else null
        if (dropped != null) {
            needsKeyframeRecovery = true
            if (recoverySessionID != dropped.sessionID) {
                recoverySessionID = dropped.sessionID
                recoveryAfterSequence = dropped.sequence
            } else {
                recoveryAfterSequence = maxOf(recoveryAfterSequence, dropped.sequence)
            }
        }
        storage.addLast(packet)
        return dropped
    }

    fun removeFirstOrNull(): VideoPacket? = if (storage.isEmpty()) null else storage.removeFirst()

    fun acknowledgeDecoded(packet: VideoPacket) {
        if (!packet.isKeyframe || packet.sessionID != recoverySessionID || packet.sequence <= recoveryAfterSequence) return
        needsKeyframeRecovery = false
        recoverySessionID = null
        recoveryAfterSequence = 0
    }

    fun reset() {
        storage.clear()
        needsKeyframeRecovery = false
        recoverySessionID = null
        recoveryAfterSequence = 0
    }
}

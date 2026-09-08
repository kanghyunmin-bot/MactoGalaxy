package com.mtog.core

import java.util.UUID

sealed class VideoReceiverAction {
    data class Configure(val packet: VideoPacket) : VideoReceiverAction()
    data class Decode(val packet: VideoPacket) : VideoReceiverAction()
    data object RequestKeyframe : VideoReceiverAction()
    data class Control(val packet: VideoPacket) : VideoReceiverAction()
    data object Reject : VideoReceiverAction()
}

class VideoReceiverStateMachine(sessionID: UUID) {
    private var sessionID: UUID = sessionID
    private var codec: VideoCodec? = null
    private var highestSequence = 0L
    private var hasConfig = false
    private var needsKeyframe = true

    fun begin(sessionID: UUID) {
        this.sessionID = sessionID
        reset()
    }

    fun reset() {
        codec = null; highestSequence = 0; hasConfig = false; needsKeyframe = true
    }

    fun markFrameDropped() { needsKeyframe = true }

    fun receive(packet: VideoPacket): VideoReceiverAction {
        if (packet.sessionID != sessionID) return VideoReceiverAction.Reject
        if (packet.sequence <= highestSequence) return VideoReceiverAction.Reject
        return when (packet.kind) {
            VideoPacketKind.Config -> {
                codec = packet.codec
                highestSequence = packet.sequence
                hasConfig = true
                needsKeyframe = true
                VideoReceiverAction.Configure(packet)
            }
            VideoPacketKind.AccessUnit -> {
                if (!hasConfig || packet.codec != codec) {
                    highestSequence = packet.sequence
                    needsKeyframe = true
                    VideoReceiverAction.RequestKeyframe
                } else {
                    highestSequence = packet.sequence
                    if (needsKeyframe && !packet.isKeyframe) VideoReceiverAction.RequestKeyframe
                    else {
                        if (packet.isKeyframe) needsKeyframe = false
                        VideoReceiverAction.Decode(packet)
                    }
                }
            }
            VideoPacketKind.Control -> {
                highestSequence = packet.sequence
                VideoReceiverAction.Control(packet)
            }
        }
    }
}

class CodecFallbackState {
    private var usedFallback = false
    fun requestFallback(codec: VideoCodec): VideoCodec? {
        if (codec != VideoCodec.Hevc || usedFallback) return null
        usedFallback = true
        return VideoCodec.H264
    }
}

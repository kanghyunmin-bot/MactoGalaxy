package com.mtog.app.externaldisplay

import com.mtog.core.VideoCodec
import com.mtog.core.VideoPacket
import com.mtog.core.VideoPacketKind
import java.util.UUID

enum class DecoderState {
    Idle,
    WaitingSurface,
    WaitingConfig,
    Configured,
    Streaming,
    Recovering,
    Stopped,
    Failed
}

sealed class DecoderCommand {
    data object None : DecoderCommand()
    data class Configure(val packet: VideoPacket) : DecoderCommand()
    data class ResetAndConfigure(val packet: VideoPacket) : DecoderCommand()
    data class Decode(val packet: VideoPacket) : DecoderCommand()
    data object RequestKeyframe : DecoderCommand()
    data object Reset : DecoderCommand()
    data object Stop : DecoderCommand()
    data object Reject : DecoderCommand()
}

class DecoderStateMachine(private val expectedSessionID: UUID? = null) {
    var state: DecoderState = DecoderState.WaitingSurface
        private set
    private var surfaceAvailable = false
    private var config: VideoPacket? = null
    private var activeSession: UUID? = null
    private val retiredSessions = mutableSetOf<UUID>()
    private var highestSequence = 0L
    private var needsKeyframe = true
    private var fallbackUsed = false
    private var fallbackPending = false
    private var hasRenderedFrame = false

    fun onSurfaceAvailable(): DecoderCommand {
        if (state == DecoderState.Stopped || state == DecoderState.Failed) return DecoderCommand.Reject
        surfaceAvailable = true
        val config = config
        return if (config == null) {
            state = DecoderState.WaitingConfig
            DecoderCommand.None
        } else {
            state = DecoderState.Configured
            DecoderCommand.Configure(config)
        }
    }

    fun onSurfaceLost(): DecoderCommand {
        if (state == DecoderState.Stopped) return DecoderCommand.Reject
        surfaceAvailable = false
        state = DecoderState.WaitingSurface
        needsKeyframe = true
        hasRenderedFrame = false
        return DecoderCommand.Reset
    }

    fun onConfigured() {
        if (surfaceAvailable && config != null) {
            state = DecoderState.Recovering
            needsKeyframe = true
        }
    }

    fun onPacket(packet: VideoPacket): DecoderCommand {
        if (state == DecoderState.Stopped || state == DecoderState.Failed) return DecoderCommand.Reject
        if (expectedSessionID != null && packet.sessionID != expectedSessionID) return DecoderCommand.Reject
        if (packet.kind == VideoPacketKind.Config) {
            if (fallbackPending && packet.codec != VideoCodec.H264) return DecoderCommand.Reject
            if (packet.sessionID in retiredSessions) return DecoderCommand.Reject
            val previousSession = activeSession
            val sessionChanged = previousSession != null && packet.sessionID != previousSession
            if (sessionChanged) retiredSessions += previousSession
            if (!sessionChanged && packet.sessionID == activeSession && packet.sequence <= highestSequence) {
                return DecoderCommand.Reject
            }
            if (packet.codec == VideoCodec.H264) fallbackPending = false
            activeSession = packet.sessionID
            highestSequence = packet.sequence
            config = packet
            needsKeyframe = true
            hasRenderedFrame = false
            if (!surfaceAvailable) {
                state = DecoderState.WaitingSurface
                return DecoderCommand.None
            }
            state = DecoderState.Configured
            return if (sessionChanged) DecoderCommand.ResetAndConfigure(packet) else DecoderCommand.Configure(packet)
        }

        if (fallbackPending) return DecoderCommand.Reject
        val activeSession = activeSession
        if (activeSession == null) {
            state = if (surfaceAvailable) DecoderState.WaitingConfig else DecoderState.WaitingSurface
            return if (packet.kind == VideoPacketKind.AccessUnit) DecoderCommand.RequestKeyframe else DecoderCommand.Reject
        }
        if (packet.sessionID != activeSession) return DecoderCommand.Reject
        if (packet.sequence <= highestSequence) return DecoderCommand.Reject
        if (packet.kind != VideoPacketKind.AccessUnit) return DecoderCommand.None
        if (!surfaceAvailable || config == null) {
            state = if (surfaceAvailable) DecoderState.WaitingConfig else DecoderState.WaitingSurface
            return DecoderCommand.RequestKeyframe
        }
        highestSequence = packet.sequence
        if (needsKeyframe && !packet.isKeyframe) {
            state = DecoderState.Recovering
            return DecoderCommand.RequestKeyframe
        }
        if (packet.isKeyframe) needsKeyframe = false
        state = if (hasRenderedFrame) DecoderState.Streaming else DecoderState.Configured
        return DecoderCommand.Decode(packet)
    }

    fun onFrameRendered() {
        hasRenderedFrame = true
        state = DecoderState.Streaming
    }

    fun onDisconnected(): DecoderCommand {
        activeSession?.let(retiredSessions::add)
        activeSession = null
        config = null
        highestSequence = 0
        needsKeyframe = true
        hasRenderedFrame = false
        fallbackUsed = false
        fallbackPending = false
        state = if (surfaceAvailable) DecoderState.WaitingConfig else DecoderState.WaitingSurface
        return DecoderCommand.Reset
    }

    fun markFrameDropped() {
        needsKeyframe = true
        state = DecoderState.Recovering
    }

    fun requestFallback(codec: VideoCodec): VideoCodec? {
        if (codec != VideoCodec.Hevc || fallbackUsed) return null
        fallbackUsed = true
        fallbackPending = true
        state = DecoderState.Recovering
        return VideoCodec.H264
    }

    fun fail() {
        state = DecoderState.Failed
    }

    fun stop(): DecoderCommand {
        state = DecoderState.Stopped
        surfaceAvailable = false
        return DecoderCommand.Stop
    }
}

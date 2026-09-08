package com.mtog.app.externaldisplay

import com.mtog.core.VideoCodec
import com.mtog.core.VideoControlCode
import com.mtog.core.VideoPacket
import com.mtog.core.VideoPacketKind
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class DecoderStateMachineTest {
    private val session = UUID.fromString("40000000-0000-0000-0000-000000000001")
    private val config = packet(VideoPacketKind.Config, 1, keyframe = false)
    private val keyframe = packet(VideoPacketKind.AccessUnit, 2, keyframe = true)
    private val delta = packet(VideoPacketKind.AccessUnit, 3, keyframe = false)

    @Test
    fun requiresSurfaceConfigAndRecoveryKeyframe() {
        val machine = DecoderStateMachine()
        assertEquals(DecoderCommand.RequestKeyframe, machine.onPacket(delta))
        assertEquals(DecoderState.WaitingSurface, machine.state)
        assertEquals(DecoderCommand.None, machine.onPacket(config))
        assertEquals(DecoderCommand.Configure(config), machine.onSurfaceAvailable())
        machine.onConfigured()
        assertEquals(DecoderCommand.RequestKeyframe, machine.onPacket(delta.copy(sequence = 4)))
        assertEquals(DecoderCommand.Decode(keyframe.copy(sequence = 5)), machine.onPacket(keyframe.copy(sequence = 5)))
        assertEquals(DecoderState.Configured, machine.state)
        machine.onFrameRendered()
        assertEquals(DecoderState.Streaming, machine.state)
        assertEquals(DecoderCommand.Decode(delta.copy(sequence = 6)), machine.onPacket(delta.copy(sequence = 6)))
        machine.markFrameDropped()
        assertEquals(DecoderCommand.RequestKeyframe, machine.onPacket(delta.copy(sequence = 7)))
        assertEquals(DecoderCommand.Reset, machine.onDisconnected())
        assertEquals(DecoderCommand.Reject, machine.onPacket(config.copy(sequence = 8)))
        val restarted = config.copy(sessionID = UUID.randomUUID(), sequence = 1)
        assertEquals(DecoderCommand.Configure(restarted), machine.onPacket(restarted))
    }

    @Test
    fun surfaceAndSessionChangesResetDecoder() {
        val machine = DecoderStateMachine()
        machine.onPacket(config)
        machine.onSurfaceAvailable()
        machine.onConfigured()
        machine.onPacket(keyframe)
        assertEquals(DecoderCommand.Reset, machine.onSurfaceLost())
        assertEquals(DecoderState.WaitingSurface, machine.state)
        assertEquals(DecoderCommand.Configure(config), machine.onSurfaceAvailable())
        val nextConfig = config.copy(sessionID = UUID.randomUUID(), sequence = 1)
        assertEquals(DecoderCommand.ResetAndConfigure(nextConfig), machine.onPacket(nextConfig))
        assertEquals(DecoderCommand.Reject, machine.onPacket(config.copy(sequence = 9)))
    }

    @Test
    fun duplicateStopAndFallbackAreBounded() {
        val machine = DecoderStateMachine()
        machine.onPacket(config)
        machine.onSurfaceAvailable()
        machine.onConfigured()
        assertEquals(DecoderCommand.Decode(keyframe), machine.onPacket(keyframe))
        assertEquals(DecoderCommand.Reject, machine.onPacket(keyframe))
        assertEquals(VideoCodec.H264, machine.requestFallback(VideoCodec.Hevc))
        assertEquals(DecoderCommand.Reject, machine.onPacket(keyframe.copy(codec = VideoCodec.Hevc, sequence = 3)))
        assertEquals(DecoderCommand.Configure(config.copy(sequence = 3)), machine.onPacket(config.copy(sequence = 3)))
        assertNull(machine.requestFallback(VideoCodec.Hevc))
        assertEquals(DecoderCommand.Stop, machine.stop())
        assertEquals(DecoderCommand.Reject, machine.onPacket(delta.copy(sequence = 9)))
    }

    private fun packet(kind: VideoPacketKind, sequence: Long, keyframe: Boolean): VideoPacket = VideoPacket(
        kind = kind,
        codec = VideoCodec.H264,
        flags = if (keyframe) VideoPacket.KEYFRAME_FLAG else 0,
        sessionID = session,
        sequence = sequence,
        presentationTimeUs = sequence * 16_666,
        width = 1920,
        height = 1200,
        controlCode = VideoControlCode.None,
        payload = byteArrayOf(0, 0, 0, 1, if (keyframe) 0x65 else 0x41)
    )
}

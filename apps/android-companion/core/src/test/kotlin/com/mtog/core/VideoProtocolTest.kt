package com.mtog.core

import java.io.File
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue

class VideoProtocolTest {
    private val fixtureRoot = File(requireNotNull(System.getProperty("mtog.fixtureRoot")), "protocol-v2/video")

    @Test
    fun sharedFixturesRoundTrip() {
        listOf("h264-config", "h264-keyframe", "h264-delta").forEach { name ->
            val bytes = File(fixtureRoot, "$name.packet").readBytes()
            val packet = BoundedVideoParser().parsing(bytes).single()
            assertContentEquals(bytes, VideoPacketCodec.encode(packet))
        }
    }

    @Test
    fun parsesFragmentationAndConsecutivePackets() {
        val bytes = File(fixtureRoot, "h264-keyframe.packet").readBytes()
        val parser = BoundedVideoParser()
        val packets = mutableListOf<VideoPacket>()
        (bytes + bytes).forEach { packets += parser.append(byteArrayOf(it)) }
        parser.finish()
        assertEquals(2, packets.size)
    }

    @Test
    fun rejectsMalformedOversizedAndTruncatedPackets() {
        val valid = File(fixtureRoot, "h264-keyframe.packet").readBytes()
        listOf(0 to 0, 4 to 1, 5 to 255, 6 to 255).forEach { (offset, value) ->
            val invalid = valid.copyOf()
            invalid[offset] = value.toByte()
            assertFailsWith<VideoProtocolException> {
                BoundedVideoParser().append(invalid.copyOf(VideoPacket.HEADER_BYTES))
            }
        }
        val reserved = valid.copyOf()
        reserved[53] = 1
        assertFailsWith<VideoProtocolException.InvalidPayload> {
            BoundedVideoParser().append(reserved.copyOf(VideoPacket.HEADER_BYTES))
        }
        val signedOverflow = valid.copyOf()
        signedOverflow[24] = 0x80.toByte()
        assertFailsWith<VideoProtocolException.InvalidSequence> {
            BoundedVideoParser().append(signedOverflow.copyOf(VideoPacket.HEADER_BYTES))
        }
        val oversized = valid.copyOf(VideoPacket.HEADER_BYTES)
        oversized.fill(0xff.toByte(), 48, 52)
        assertFailsWith<VideoProtocolException> { BoundedVideoParser().append(oversized) }
        val parser = BoundedVideoParser()
        parser.append(valid.copyOf(valid.size - 1))
        assertFailsWith<VideoProtocolException.TruncatedPacket> { parser.finish() }
    }

    @Test
    fun stateQueueAndFallbackRules() {
        val config = packet("h264-config")
        val keyframe = packet("h264-keyframe")
        val delta = packet("h264-delta")
        val receiver = VideoReceiverStateMachine(config.sessionID)
        assertEquals(VideoReceiverAction.RequestKeyframe, receiver.receive(delta))
        receiver.reset()
        assertEquals(VideoReceiverAction.Configure(config), receiver.receive(config))
        assertEquals(VideoReceiverAction.Decode(keyframe), receiver.receive(keyframe))
        assertEquals(VideoReceiverAction.Decode(delta), receiver.receive(delta))
        assertEquals(VideoReceiverAction.Reject, receiver.receive(delta))
        assertEquals(VideoReceiverAction.Reject, receiver.receive(delta.copy(sessionID = UUID.randomUUID(), sequence = 4)))
        receiver.begin(UUID.randomUUID())
        assertEquals(VideoReceiverAction.Reject, receiver.receive(config))
        receiver.begin(config.sessionID)
        receiver.receive(config)
        receiver.receive(keyframe)
        receiver.markFrameDropped()
        assertEquals(VideoReceiverAction.RequestKeyframe, receiver.receive(delta.copy(sequence = 4)))
        assertEquals(VideoReceiverAction.Decode(keyframe.copy(sequence = 5)), receiver.receive(keyframe.copy(sequence = 5)))

        receiver.reset()
        assertEquals(VideoReceiverAction.RequestKeyframe, receiver.receive(delta.copy(sequence = 1)))

        val control = VideoPacket(
            VideoPacketKind.Control, VideoCodec.H264, 0, delta.sessionID, 4,
            delta.presentationTimeUs, delta.width, delta.height,
            VideoControlCode.RequestKeyframe, byteArrayOf(1)
        )
        assertEquals(control, VideoPacketCodec.decode(VideoPacketCodec.encode(control)))
        assertFailsWith<VideoProtocolException.InvalidDimensions> {
            VideoPacketCodec.encode(delta.copy(width = 0))
        }
        assertFailsWith<VideoProtocolException.InvalidTimestamp> {
            VideoPacketCodec.encode(delta.copy(presentationTimeUs = -1))
        }
        assertFailsWith<VideoProtocolException.InvalidFlags> {
            VideoPacketCodec.encode(delta.copy(flags = 256))
        }
        assertFailsWith<VideoProtocolException.InvalidSession> {
            VideoPacketCodec.encode(delta.copy(sessionID = UUID(0, 0)))
        }

        val queue = VideoLatestFrameQueue(2)
        assertNull(queue.append(delta.copy(sequence = 1)))
        assertNull(queue.append(delta.copy(sequence = 2)))
        assertEquals(1, queue.append(delta.copy(sequence = 3))?.sequence)
        assertEquals(2, queue.count)
        assertTrue(queue.needsKeyframeRecovery)
        queue.acknowledgeDecoded(keyframe)
        assertTrue(!queue.needsKeyframeRecovery)
        queue.reset()
        queue.append(keyframe.copy(sequence = 4))
        queue.append(delta.copy(sequence = 5))
        assertTrue(queue.append(delta.copy(sequence = 6))?.isKeyframe == true)
        assertTrue(queue.needsKeyframeRecovery)
        queue.acknowledgeDecoded(keyframe.copy(sequence = 4))
        assertTrue(queue.needsKeyframeRecovery)
        queue.acknowledgeDecoded(keyframe.copy(sessionID = UUID.randomUUID(), sequence = 100))
        assertTrue(queue.needsKeyframeRecovery)
        queue.reset()
        assertTrue(!queue.needsKeyframeRecovery)
        queue.append(keyframe.copy(sequence = 4))
        queue.append(delta.copy(sequence = 5))
        queue.append(delta.copy(sequence = 6))
        queue.acknowledgeDecoded(keyframe.copy(sequence = 7))
        assertTrue(!queue.needsKeyframeRecovery)
        val fallback = CodecFallbackState()
        assertEquals(VideoCodec.H264, fallback.requestFallback(VideoCodec.Hevc))
        assertNull(fallback.requestFallback(VideoCodec.Hevc))
    }

    private fun packet(name: String): VideoPacket =
        BoundedVideoParser().parsing(File(fixtureRoot, "$name.packet").readBytes()).single()
}

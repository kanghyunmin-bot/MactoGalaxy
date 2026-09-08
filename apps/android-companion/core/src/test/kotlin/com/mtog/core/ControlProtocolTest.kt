package com.mtog.core

import java.io.File
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class ControlProtocolTest {
    private val fixtureRoot = File(requireNotNull(System.getProperty("mtog.fixtureRoot")), "protocol-v2")

    @Test
    fun canonicalFixtureEncodesAndDecodes() {
        val semantic = File(fixtureRoot, "control/hello.json").readBytes()
        val expected = File(fixtureRoot, "control/hello.frame").readBytes()
        val envelope = ControlFrameCodec.decodePayload(semantic)

        assertContentEquals(expected, ControlFrameCodec.encode(envelope))
        val frames = BoundedFrameParser().parsing(expected)
        assertEquals(1, frames.size)
        assertEquals(envelope, ControlFrameCodec.decode(frames.single()))
    }

    @Test
    fun parsesFragmentedAndConsecutiveFrames() {
        val bytes = File(fixtureRoot, "control/hello.frame").readBytes()
        val parser = BoundedFrameParser()
        val frames = mutableListOf<ControlFrame>()
        (bytes + bytes).forEach { frames += parser.append(byteArrayOf(it)) }
        parser.finish()
        assertEquals(2, frames.size)
    }

    @Test
    fun reportsLegacyJsonAsVersionOne() {
        val error = assertFailsWith<ControlProtocolException.UnsupportedVersion> {
            BoundedFrameParser().append("{\"legacy\":1}".toByteArray())
        }
        assertEquals(1, error.version)
    }

    @Test
    fun acceptsMaximumFrameFollowedByAnotherFrame() {
        val fixture = File(fixtureRoot, "control/hello.frame").readBytes()
        val header = byteArrayOf(0x4d, 0x54, 0x47, 0x32, 2, 1, 1, 0, 2, 0x40, 0, 0)
        val bytes = header + ByteArray(ProtocolLimits.CONTROL_PAYLOAD_BYTES) + fixture
        val frames = BoundedFrameParser().parsing(bytes)
        assertEquals(2, frames.size)
        assertEquals(ProtocolLimits.CONTROL_PAYLOAD_BYTES, frames.first().payload.size)
    }

    @Test
    fun rejectsMalformedFrames() {
        val valid = File(fixtureRoot, "control/hello.frame").readBytes()
        listOf(0 to 0, 4 to 1, 5 to 2, 6 to 255).forEach { (offset, value) ->
            val invalid = valid.copyOf()
            invalid[offset] = value.toByte()
            assertFailsWith<ControlProtocolException> {
                BoundedFrameParser().append(invalid.copyOf(ControlFrame.HEADER_BYTES))
            }
        }
        val oversized = valid.copyOf(ControlFrame.HEADER_BYTES)
        oversized.fill(0xff.toByte(), 8, 12)
        assertFailsWith<ControlProtocolException> { BoundedFrameParser().append(oversized) }
        listOf(1, 4, 11).forEach { length ->
            val parser = BoundedFrameParser()
            parser.append(valid.copyOf(length))
            assertFailsWith<ControlProtocolException> { parser.finish() }
        }
    }

    @Test
    fun rejectsInvalidUtf8JsonTimestampAndSequence() {
        assertFailsWith<ControlProtocolException> {
            ControlFrameCodec.decode(ControlFrame(0, byteArrayOf(0xff.toByte())))
        }
        assertFailsWith<ControlProtocolException> {
            ControlFrameCodec.decode(ControlFrame(0, "{}".toByteArray()))
        }
        val semantic = File(fixtureRoot, "control/hello.json").readText()
        val fractional = semantic.replace("2026-09-01T00:00:00Z", "2026-09-01T00:00:00.123Z")
        assertEquals(1, ControlFrameCodec.decodePayload(fractional.toByteArray()).sequenceNo)
        listOf(
            semantic.replace("2026-09-01T00:00:00Z", "not-a-time"),
            semantic.replace("\"sequenceNo\": 1", "\"sequenceNo\": 0"),
            semantic.replace("00000000-0000-0000-0000-000000000001", "not-a-uuid"),
            semantic.replace("00000000-0000-0000-0000-000000000001", "1-1-1-1-1")
        ).forEach { invalid ->
            assertFailsWith<ControlProtocolException> {
                ControlFrameCodec.decodePayload(invalid.toByteArray())
            }
        }
    }
}

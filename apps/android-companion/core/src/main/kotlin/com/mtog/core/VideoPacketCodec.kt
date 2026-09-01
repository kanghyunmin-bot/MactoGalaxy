package com.mtog.core

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.UUID

sealed class VideoProtocolException : Exception() {
    data object InvalidMagic : VideoProtocolException()
    data class UnsupportedVersion(val version: Int) : VideoProtocolException()
    data class InvalidKind(val kind: Int) : VideoProtocolException()
    data class InvalidCodec(val codec: Int) : VideoProtocolException()
    data object InvalidFlags : VideoProtocolException()
    data object InvalidSession : VideoProtocolException()
    data object InvalidSequence : VideoProtocolException()
    data object InvalidTimestamp : VideoProtocolException()
    data object InvalidDimensions : VideoProtocolException()
    data class InvalidControlCode(val code: Int) : VideoProtocolException()
    data object InvalidPayload : VideoProtocolException()
    data class PayloadTooLarge(val length: Long) : VideoProtocolException()
    data object TruncatedPacket : VideoProtocolException()
}

object VideoPacketCodec {
    fun encode(packet: VideoPacket): ByteArray {
        validate(packet)
        return ByteBuffer.allocate(VideoPacket.HEADER_BYTES + packet.payload.size)
            .order(ByteOrder.BIG_ENDIAN)
            .put(VideoPacket.MAGIC)
            .put(ProtocolLimits.VERSION.toByte())
            .put(packet.kind.wire.toByte())
            .put(codecByte(packet.codec).toByte())
            .put(packet.flags.toByte())
            .putLong(packet.sessionID.mostSignificantBits)
            .putLong(packet.sessionID.leastSignificantBits)
            .putLong(packet.sequence)
            .putLong(packet.presentationTimeUs)
            .putInt(packet.width)
            .putInt(packet.height)
            .putInt(packet.payload.size)
            .put(packet.controlCode.wire.toByte())
            .put(ByteArray(11))
            .put(packet.payload)
            .array()
    }

    fun decode(bytes: ByteArray): VideoPacket {
        if (bytes.size < VideoPacket.HEADER_BYTES) throw VideoProtocolException.TruncatedPacket
        val length = declaredPayloadLength(bytes.copyOf(VideoPacket.HEADER_BYTES))
        if (bytes.size != VideoPacket.HEADER_BYTES + length) throw VideoProtocolException.TruncatedPacket
        val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.BIG_ENDIAN)
        buffer.position(5)
        val kind = kind(buffer.get().toInt() and 0xff)
        val codec = codec(buffer.get().toInt() and 0xff)
        val flags = buffer.get().toInt() and 0xff
        if (flags and VideoPacket.KEYFRAME_FLAG.inv() != 0) throw VideoProtocolException.InvalidFlags
        val session = UUID(buffer.long, buffer.long)
        if (session == UUID(0, 0)) throw VideoProtocolException.InvalidSession
        val sequence = buffer.long
        val pts = buffer.long
        val width = buffer.int
        val height = buffer.int
        buffer.int
        val control = controlCode(buffer.get().toInt() and 0xff)
        buffer.position(VideoPacket.HEADER_BYTES)
        val payload = ByteArray(length)
        buffer.get(payload)
        return VideoPacket(kind, codec, flags, session, sequence, pts, width, height, control, payload).also(::validate)
    }

    fun declaredPayloadLength(header: ByteArray): Int {
        if (header.size < VideoPacket.HEADER_BYTES) throw VideoProtocolException.TruncatedPacket
        if (!header.copyOfRange(0, 4).contentEquals(VideoPacket.MAGIC)) throw VideoProtocolException.InvalidMagic
        val version = header[4].toInt() and 0xff
        if (version != ProtocolLimits.VERSION) throw VideoProtocolException.UnsupportedVersion(version)
        val kind = kind(header[5].toInt() and 0xff)
        codec(header[6].toInt() and 0xff)
        val flags = header[7].toInt() and 0xff
        if (flags and VideoPacket.KEYFRAME_FLAG.inv() != 0) throw VideoProtocolException.InvalidFlags
        val fields = ByteBuffer.wrap(header).order(ByteOrder.BIG_ENDIAN)
        fields.position(8)
        val session = UUID(fields.long, fields.long)
        if (session == UUID(0, 0)) throw VideoProtocolException.InvalidSession
        if (fields.long <= 0) throw VideoProtocolException.InvalidSequence
        if (fields.long < 0) throw VideoProtocolException.InvalidTimestamp
        val width = fields.int
        val height = fields.int
        if (width !in 1..ProtocolLimits.MAXIMUM_VIDEO_DIMENSION ||
            height !in 1..ProtocolLimits.MAXIMUM_VIDEO_DIMENSION
        ) throw VideoProtocolException.InvalidDimensions
        fields.int
        val control = controlCode(fields.get().toInt() and 0xff)
        if ((kind == VideoPacketKind.Control && control == VideoControlCode.None) ||
            (kind != VideoPacketKind.Control && control != VideoControlCode.None)
        ) throw VideoProtocolException.InvalidPayload
        if ((53 until 64).any { header[it].toInt() != 0 }) throw VideoProtocolException.InvalidPayload
        val declared = ((header[48].toLong() and 0xff) shl 24) or
            ((header[49].toLong() and 0xff) shl 16) or
            ((header[50].toLong() and 0xff) shl 8) or (header[51].toLong() and 0xff)
        val limit = when (kind) {
            VideoPacketKind.Config -> ProtocolLimits.VIDEO_CONFIG_BYTES
            VideoPacketKind.AccessUnit -> ProtocolLimits.VIDEO_PAYLOAD_BYTES
            VideoPacketKind.Control -> ProtocolLimits.VIDEO_CONTROL_BYTES
        }
        if (declared <= 0) throw VideoProtocolException.InvalidPayload
        if (declared > limit) throw VideoProtocolException.PayloadTooLarge(declared)
        return declared.toInt()
    }

    private fun validate(packet: VideoPacket) {
        if (packet.flags and VideoPacket.KEYFRAME_FLAG.inv() != 0) throw VideoProtocolException.InvalidFlags
        if (packet.sessionID == UUID(0, 0)) throw VideoProtocolException.InvalidSession
        if (packet.sequence <= 0) throw VideoProtocolException.InvalidSequence
        if (packet.presentationTimeUs < 0) throw VideoProtocolException.InvalidTimestamp
        if (packet.width !in 1..ProtocolLimits.MAXIMUM_VIDEO_DIMENSION ||
            packet.height !in 1..ProtocolLimits.MAXIMUM_VIDEO_DIMENSION
        ) throw VideoProtocolException.InvalidDimensions
        if (packet.payload.isEmpty()) throw VideoProtocolException.InvalidPayload
        val limit = when (packet.kind) {
            VideoPacketKind.Config -> {
                if (packet.controlCode != VideoControlCode.None) throw VideoProtocolException.InvalidPayload
                ProtocolLimits.VIDEO_CONFIG_BYTES
            }
            VideoPacketKind.AccessUnit -> {
                if (packet.controlCode != VideoControlCode.None) throw VideoProtocolException.InvalidPayload
                ProtocolLimits.VIDEO_PAYLOAD_BYTES
            }
            VideoPacketKind.Control -> {
                if (packet.controlCode == VideoControlCode.None) throw VideoProtocolException.InvalidPayload
                ProtocolLimits.VIDEO_CONTROL_BYTES
            }
        }
        if (packet.payload.size > limit) throw VideoProtocolException.PayloadTooLarge(packet.payload.size.toLong())
    }

    private fun kind(value: Int): VideoPacketKind = VideoPacketKind.entries.firstOrNull { it.wire == value }
        ?: throw VideoProtocolException.InvalidKind(value)
    private fun codec(value: Int): VideoCodec = when (value) {
        1 -> VideoCodec.H264
        2 -> VideoCodec.Hevc
        else -> throw VideoProtocolException.InvalidCodec(value)
    }
    private fun codecByte(codec: VideoCodec): Int = if (codec == VideoCodec.H264) 1 else 2
    private fun controlCode(value: Int): VideoControlCode = VideoControlCode.entries.firstOrNull { it.wire == value }
        ?: throw VideoProtocolException.InvalidControlCode(value)
}

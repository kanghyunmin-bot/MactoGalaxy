package com.mtog.core

import java.util.UUID

enum class VideoPacketKind(val wire: Int) { Config(1), AccessUnit(2), Control(3) }
enum class VideoControlCode(val wire: Int) { None(0), RequestKeyframe(1), StreamStart(2), StreamStop(3), Capabilities(4), FallbackH264(5) }

data class VideoPacket(
    val kind: VideoPacketKind,
    val codec: VideoCodec,
    val flags: Int,
    val sessionID: UUID,
    val sequence: Long,
    val presentationTimeUs: Long,
    val width: Int,
    val height: Int,
    val controlCode: VideoControlCode = VideoControlCode.None,
    val payload: ByteArray
) {
    val isKeyframe: Boolean get() = flags and KEYFRAME_FLAG != 0

    override fun equals(other: Any?): Boolean = other is VideoPacket &&
        kind == other.kind && codec == other.codec && flags == other.flags &&
        sessionID == other.sessionID && sequence == other.sequence &&
        presentationTimeUs == other.presentationTimeUs && width == other.width &&
        height == other.height && controlCode == other.controlCode && payload.contentEquals(other.payload)

    override fun hashCode(): Int = 31 * sequence.hashCode() + payload.contentHashCode()

    companion object {
        const val HEADER_BYTES = 64
        const val KEYFRAME_FLAG = 1
        val MAGIC = byteArrayOf(0x4d, 0x54, 0x47, 0x56)
    }
}

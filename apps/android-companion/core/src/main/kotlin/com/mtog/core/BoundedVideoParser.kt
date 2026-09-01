package com.mtog.core

class BoundedVideoParser {
    private var storage = ByteArray(4_096)
    private var start = 0
    private var end = 0
    private var expectedPayloadBytes: Int? = null

    fun append(bytes: ByteArray): List<VideoPacket> {
        val packets = mutableListOf<VideoPacket>()
        var offset = 0
        while (offset < bytes.size) {
            val target = expectedPayloadBytes?.let { VideoPacket.HEADER_BYTES + it } ?: VideoPacket.HEADER_BYTES
            val needed = (target - available).coerceAtLeast(1)
            val count = minOf(needed, bytes.size - offset)
            appendStorage(bytes, offset, count)
            offset += count
            drain(packets)
        }
        return packets
    }

    fun parsing(bytes: ByteArray): List<VideoPacket> = append(bytes).also { finish() }

    fun finish() {
        if (available != 0 || expectedPayloadBytes != null) throw VideoProtocolException.TruncatedPacket
    }

    fun reset() {
        start = 0; end = 0; expectedPayloadBytes = null
    }

    private val available: Int get() = end - start

    private fun drain(packets: MutableList<VideoPacket>) {
        while (true) {
            if (expectedPayloadBytes == null) {
                if (available < VideoPacket.HEADER_BYTES) return
                expectedPayloadBytes = VideoPacketCodec.declaredPayloadLength(
                    storage.copyOfRange(start, start + VideoPacket.HEADER_BYTES)
                )
            }
            val expected = expectedPayloadBytes ?: return
            val size = VideoPacket.HEADER_BYTES + expected
            if (available < size) return
            packets += VideoPacketCodec.decode(storage.copyOfRange(start, start + size))
            consume(size)
            expectedPayloadBytes = null
        }
    }

    private fun appendStorage(source: ByteArray, offset: Int, count: Int) {
        ensureCapacity(available + count)
        source.copyInto(storage, end, offset, offset + count)
        end += count
    }

    private fun ensureCapacity(required: Int) {
        if (storage.size - end >= required - available) return
        if (start > 0) {
            val remaining = available
            storage.copyInto(storage, 0, start, end)
            start = 0; end = remaining
        }
        if (storage.size >= required) return
        var capacity = storage.size
        while (capacity < required) capacity = minOf(capacity * 2, ProtocolLimits.VIDEO_PAYLOAD_BYTES + VideoPacket.HEADER_BYTES)
        storage = storage.copyOf(capacity)
    }

    private fun consume(count: Int) {
        start += count
        if (start == end) { start = 0; end = 0 }
    }
}

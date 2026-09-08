package com.mtog.core

class BoundedFrameParser {
    private var storage = ByteArray(4_096)
    private var start = 0
    private var end = 0
    private var expectedPayloadBytes: Int? = null
    private var currentFlags: Int = 0

    fun append(bytes: ByteArray): List<ControlFrame> {
        val frames = mutableListOf<ControlFrame>()
        var sourceOffset = 0
        while (sourceOffset < bytes.size) {
            val needed = bytesNeededForCurrentStep()
            val count = minOf(needed, bytes.size - sourceOffset)
            appendToStorage(bytes, sourceOffset, count)
            sourceOffset += count
            drainCompleteSteps(frames)
        }
        return frames
    }

    fun parsing(bytes: ByteArray): List<ControlFrame> {
        val frames = append(bytes)
        finish()
        return frames
    }

    fun finish() {
        if (availableBytes != 0 || expectedPayloadBytes != null) {
            throw ControlProtocolException.TruncatedFrame
        }
    }

    fun reset() {
        start = 0
        end = 0
        expectedPayloadBytes = null
        currentFlags = 0
    }

    private val availableBytes: Int get() = end - start

    private fun bytesNeededForCurrentStep(): Int {
        val target = expectedPayloadBytes ?: ControlFrame.HEADER_BYTES
        return (target - availableBytes).coerceAtLeast(1)
    }

    private fun drainCompleteSteps(frames: MutableList<ControlFrame>) {
        while (true) {
            if (expectedPayloadBytes == null) {
                if (availableBytes < ControlFrame.HEADER_BYTES) return
                parseHeader()
                consume(ControlFrame.HEADER_BYTES)
            }
            val expected = expectedPayloadBytes ?: return
            if (availableBytes < expected) return
            val payload = storage.copyOfRange(start, start + expected)
            consume(expected)
            frames += ControlFrame(currentFlags, payload)
            expectedPayloadBytes = null
        }
    }

    private fun appendToStorage(source: ByteArray, sourceOffset: Int, count: Int) {
        ensureCapacity(availableBytes + count)
        source.copyInto(storage, destinationOffset = end, startIndex = sourceOffset, endIndex = sourceOffset + count)
        end += count
    }

    private fun ensureCapacity(required: Int) {
        if (storage.size - end >= required - availableBytes) return
        if (start > 0) {
            val remaining = availableBytes
            storage.copyInto(storage, destinationOffset = 0, startIndex = start, endIndex = end)
            start = 0
            end = remaining
        }
        if (storage.size >= required) return
        var capacity = storage.size
        while (capacity < required) {
            capacity = minOf(capacity * 2, ProtocolLimits.CONTROL_PAYLOAD_BYTES)
            if (capacity < required && capacity == ProtocolLimits.CONTROL_PAYLOAD_BYTES) {
                throw ControlProtocolException.PayloadTooLarge(required.toLong())
            }
        }
        storage = storage.copyOf(capacity)
    }

    private fun consume(count: Int) {
        start += count
        if (start == end) {
            start = 0
            end = 0
        }
    }

    private fun parseHeader() {
        if (storage[start] == '{'.code.toByte() || storage[start] == '['.code.toByte()) {
            throw ControlProtocolException.UnsupportedVersion(1)
        }
        if (!(0 until 4).all { storage[start + it] == ControlFrame.MAGIC[it] }) {
            throw ControlProtocolException.InvalidMagic
        }
        val version = unsigned(4)
        if (version != ProtocolLimits.VERSION) {
            throw ControlProtocolException.UnsupportedVersion(version)
        }
        val channel = unsigned(5)
        if (channel != ControlFrame.CHANNEL) {
            throw ControlProtocolException.InvalidChannel(channel)
        }
        val type = unsigned(6)
        if (type != ControlFrame.ENVELOPE_TYPE) {
            throw ControlProtocolException.InvalidType(type)
        }
        currentFlags = unsigned(7)
        val declared = (unsigned(8).toLong() shl 24) or
            (unsigned(9).toLong() shl 16) or
            (unsigned(10).toLong() shl 8) or
            unsigned(11).toLong()
        if (declared > ProtocolLimits.CONTROL_PAYLOAD_BYTES.toLong()) {
            throw ControlProtocolException.PayloadTooLarge(declared)
        }
        expectedPayloadBytes = declared.toInt()
    }

    private fun unsigned(offset: Int): Int = storage[start + offset].toInt() and 0xff
}

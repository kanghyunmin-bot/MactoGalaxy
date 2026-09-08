package com.mtog.app.externaldisplay

import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Handler
import android.os.Looper
import android.view.Surface
import com.mtog.core.VideoCodec
import com.mtog.core.VideoPacket
import java.nio.ByteBuffer

sealed class DecoderFeedResult {
    data object Queued : DecoderFeedResult()
    data object InputUnavailable : DecoderFeedResult()
}

class MediaCodecVideoDecoder {
    var frameRenderedHandler: ((Long) -> Unit)? = null
    private var codecGeneration = 0L
    private var codec: MediaCodec? = null
    private var surface: Surface? = null
    private var configuredCodec: VideoCodec? = null

    fun setSurface(surface: Surface?) {
        this.surface = surface
    }

    fun configure(packet: VideoPacket) {
        val surface = requireNotNull(surface) { "Surface is not available" }
        reset()
        val mime = packet.codec.mimeType
        val format = MediaFormat.createVideoFormat(mime, packet.width, packet.height)
        val units = annexBNalUnits(packet.payload)
        if (packet.codec == VideoCodec.H264) {
            val sps = requireNotNull(units.firstOrNull { it.nalTypeH264() == 7 }) { "H.264 SPS missing" }
            val pps = requireNotNull(units.firstOrNull { it.nalTypeH264() == 8 }) { "H.264 PPS missing" }
            format.setByteBuffer("csd-0", ByteBuffer.wrap(withStartCode(sps)))
            format.setByteBuffer("csd-1", ByteBuffer.wrap(withStartCode(pps)))
        } else {
            val parameterSets = units.filter { it.nalTypeHevc() in 32..34 }
            require(parameterSets.map { it.nalTypeHevc() }.containsAll(listOf(32, 33, 34))) {
                "HEVC VPS/SPS/PPS missing"
            }
            format.setByteBuffer("csd-0", ByteBuffer.wrap(parameterSets.flatMap { withStartCode(it).asIterable() }.toByteArray()))
        }
        val decoder = MediaCodec.createDecoderByType(mime)
        codec = decoder
        val configuredGeneration = ++codecGeneration
        decoder.setOnFrameRenderedListener(
            { activeDecoder, _, _ ->
                if (codec === activeDecoder && codecGeneration == configuredGeneration) {
                    frameRenderedHandler?.invoke(configuredGeneration)
                }
            },
            Handler(Looper.getMainLooper())
        )
        try {
            decoder.configure(format, surface, null, 0)
            decoder.start()
            configuredCodec = packet.codec
        } catch (error: Throwable) {
            runCatching { decoder.release() }
            codec = null
            configuredCodec = null
            codecGeneration += 1
            throw error
        }
    }

    fun decode(packet: VideoPacket): DecoderFeedResult {
        val decoder = requireNotNull(codec) { "Decoder is not configured" }
        require(packet.codec == configuredCodec) { "Codec changed without config" }
        val inputIndex = decoder.dequeueInputBuffer(10_000)
        if (inputIndex < 0) return DecoderFeedResult.InputUnavailable
        val input = requireNotNull(decoder.getInputBuffer(inputIndex))
        input.clear()
        require(packet.payload.size <= input.remaining()) { "Access unit exceeds codec input buffer" }
        input.put(packet.payload)
        decoder.queueInputBuffer(
            inputIndex,
            0,
            packet.payload.size,
            packet.presentationTimeUs,
            if (packet.isKeyframe) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0
        )
        drain(decoder)
        return DecoderFeedResult.Queued
    }

    fun isGenerationActive(generation: Long): Boolean = codec != null && codecGeneration == generation

    fun reset() {
        codecGeneration += 1
        codec?.let { decoder ->
            runCatching { decoder.stop() }
            decoder.release()
        }
        codec = null
        configuredCodec = null
    }

    fun stop() {
        reset()
        surface = null
    }

    private fun drain(decoder: MediaCodec) {
        val info = MediaCodec.BufferInfo()
        while (true) {
            when (val outputIndex = decoder.dequeueOutputBuffer(info, 0)) {
                MediaCodec.INFO_TRY_AGAIN_LATER -> return
                MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> Unit
                else -> if (outputIndex >= 0) {
                    decoder.releaseOutputBuffer(outputIndex, true)
                }
            }
        }
    }

    private fun annexBNalUnits(data: ByteArray): List<ByteArray> {
        val starts = mutableListOf<Pair<Int, Int>>()
        var index = 0
        while (index + 3 <= data.size) {
            if (index + 4 <= data.size && data[index] == 0.toByte() && data[index + 1] == 0.toByte() &&
                data[index + 2] == 0.toByte() && data[index + 3] == 1.toByte()
            ) {
                starts += index to 4
                index += 4
            } else if (data[index] == 0.toByte() && data[index + 1] == 0.toByte() && data[index + 2] == 1.toByte()) {
                starts += index to 3
                index += 3
            } else index += 1
        }
        require(starts.isNotEmpty() && starts.first().first == 0) { "Annex-B config malformed" }
        return starts.mapIndexed { position, (start, length) ->
            val payloadStart = start + length
            val end = starts.getOrNull(position + 1)?.first ?: data.size
            require(end > payloadStart) { "Empty NAL unit" }
            data.copyOfRange(payloadStart, end)
        }
    }

    private fun withStartCode(unit: ByteArray): ByteArray = byteArrayOf(0, 0, 0, 1) + unit
    private fun ByteArray.nalTypeH264(): Int = first().toInt() and 0x1f
    private fun ByteArray.nalTypeHevc(): Int = (first().toInt() shr 1) and 0x3f
    private val VideoCodec.mimeType: String get() = if (this == VideoCodec.H264) "video/avc" else "video/hevc"
}

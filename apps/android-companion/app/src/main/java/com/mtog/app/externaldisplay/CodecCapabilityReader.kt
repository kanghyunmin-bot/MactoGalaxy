package com.mtog.app.externaldisplay

import android.media.MediaCodecInfo
import android.media.MediaCodecList
import com.mtog.core.CodecCapabilities
import com.mtog.core.VideoCodec

object CodecCapabilityReader {
    fun read(): CodecCapabilities {
        val decoderInfos = MediaCodecList(MediaCodecList.ALL_CODECS).codecInfos.filterNot(MediaCodecInfo::isEncoder)
        val results = buildList {
            bestFor(decoderInfos, "video/hevc")?.let { add(VideoCodec.Hevc to it) }
            bestFor(decoderInfos, "video/avc")?.let { add(VideoCodec.H264 to it) }
        }
        if (results.isEmpty()) return CodecCapabilities(emptyList(), 1, 1, 1)
        return CodecCapabilities(
            codecs = results.map { it.first },
            maxWidth = results.minOf { it.second.width },
            maxHeight = results.minOf { it.second.height },
            maxFramesPerSecond = results.minOf { it.second.framesPerSecond }
        )
    }

    private fun bestFor(infos: List<MediaCodecInfo>, mime: String): VideoLimit? {
        val candidates = listOf(
            2560 to 1600,
            1920 to 1200,
            1920 to 1080,
            1280 to 720,
            720 to 480
        )
        for (info in infos) {
            val supported = info.supportedTypes.firstOrNull { it.equals(mime, ignoreCase = true) } ?: continue
            val video = runCatching { info.getCapabilitiesForType(supported).videoCapabilities }.getOrNull() ?: continue
            for ((width, height) in candidates) {
                if (!video.isSizeSupported(width, height)) continue
                val fps = runCatching { video.getSupportedFrameRatesFor(width, height).upper.toInt() }
                    .getOrDefault(30)
                    .coerceIn(1, 60)
                if (video.areSizeAndRateSupported(width, height, fps.toDouble())) {
                    return VideoLimit(width, height, fps)
                }
            }
        }
        return null
    }

    private data class VideoLimit(val width: Int, val height: Int, val framesPerSecond: Int)
}

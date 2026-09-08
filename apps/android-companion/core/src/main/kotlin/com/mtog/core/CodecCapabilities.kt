package com.mtog.core

enum class VideoCodec { Hevc, H264 }
data class CodecCapabilities(
    val codecs: List<VideoCodec>,
    val maxWidth: Int,
    val maxHeight: Int,
    val maxFramesPerSecond: Int
)
data class NegotiatedCodec(val codec: VideoCodec, val width: Int, val height: Int, val framesPerSecond: Int)

object CodecNegotiator {
    fun negotiate(sender: CodecCapabilities, receiver: CodecCapabilities): NegotiatedCodec {
        require(sender.maxWidth > 0 && sender.maxHeight > 0 && sender.maxFramesPerSecond > 0)
        require(receiver.maxWidth > 0 && receiver.maxHeight > 0 && receiver.maxFramesPerSecond > 0)
        val codec = listOf(VideoCodec.Hevc, VideoCodec.H264).firstOrNull {
            it in sender.codecs && it in receiver.codecs
        } ?: throw IllegalArgumentException("unsupported codec")
        return NegotiatedCodec(
            codec,
            minOf(sender.maxWidth, receiver.maxWidth),
            minOf(sender.maxHeight, receiver.maxHeight),
            minOf(sender.maxFramesPerSecond, receiver.maxFramesPerSecond)
        )
    }
}

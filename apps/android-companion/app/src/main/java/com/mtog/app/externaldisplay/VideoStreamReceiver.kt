package com.mtog.app.externaldisplay

import com.mtog.core.BoundedVideoParser
import com.mtog.core.VideoCodec
import com.mtog.core.VideoControlCode
import com.mtog.core.VideoPacket
import com.mtog.core.VideoPacketCodec
import com.mtog.core.VideoPacketKind
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.UUID

class VideoStreamReceiver(private val port: Int) {
    @Volatile private var serverSocket: ServerSocket? = null
    @Volatile private var clientSocket: Socket? = null
    private val writerLock = Any()
    private var controlSequence = 0L

    suspend fun run(
        onConnected: suspend () -> Unit,
        onDisconnected: suspend () -> Unit,
        onPacket: suspend (VideoPacket) -> Unit
    ) = withContext(Dispatchers.IO) {
        serverSocket = ServerSocket(port, 1, InetAddress.getByName("127.0.0.1"))
        try {
            while (currentCoroutineContext().isActive) {
                val socket = serverSocket?.accept() ?: break
                clientSocket = socket
                socket.tcpNoDelay = true
                controlSequence = 0
                val parser = BoundedVideoParser()
                try {
                    sendCapabilities()
                    onConnected()
                    val input = socket.getInputStream()
                    val buffer = ByteArray(16 * 1024)
                    while (currentCoroutineContext().isActive) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        parser.append(buffer.copyOf(count)).forEach { onPacket(it) }
                    }
                    parser.finish()
                } catch (_: Throwable) {
                    // The accept loop owns reconnect; this client is discarded below.
                } finally {
                    runCatching { socket.close() }
                    if (clientSocket === socket) clientSocket = null
                    onDisconnected()
                }
            }
        } finally {
            stop()
        }
    }

    fun requestKeyframe(packet: VideoPacket) {
        runCatching { sendControl(packet, VideoControlCode.RequestKeyframe) }
    }

    fun requestH264Fallback(packet: VideoPacket) {
        runCatching { sendControl(packet, VideoControlCode.FallbackH264) }
    }

    fun stop() {
        runCatching { clientSocket?.close() }
        clientSocket = null
        runCatching { serverSocket?.close() }
        serverSocket = null
    }

    private fun sendCapabilities() {
        val capabilities = CodecCapabilityReader.read()
        val mask = (if (VideoCodec.H264 in capabilities.codecs) 1 else 0) or
            (if (VideoCodec.Hevc in capabilities.codecs) 2 else 0)
        val payload = ByteBuffer.allocate(11).order(ByteOrder.BIG_ENDIAN)
            .put(mask.toByte())
            .putInt(capabilities.maxWidth)
            .putInt(capabilities.maxHeight)
            .putShort(capabilities.maxFramesPerSecond.toShort())
            .array()
        val codec = capabilities.codecs.firstOrNull() ?: VideoCodec.H264
        sendPacket(
            VideoPacket(
                kind = VideoPacketKind.Control,
                codec = codec,
                flags = 0,
                sessionID = UUID.randomUUID(),
                sequence = nextControlSequence(),
                presentationTimeUs = 0,
                width = capabilities.maxWidth,
                height = capabilities.maxHeight,
                controlCode = VideoControlCode.Capabilities,
                payload = payload
            )
        )
    }

    private fun sendControl(packet: VideoPacket, code: VideoControlCode) {
        sendPacket(
            VideoPacket(
                kind = VideoPacketKind.Control,
                codec = packet.codec,
                flags = 0,
                sessionID = packet.sessionID,
                sequence = nextControlSequence(),
                presentationTimeUs = packet.presentationTimeUs,
                width = packet.width,
                height = packet.height,
                controlCode = code,
                payload = byteArrayOf(1)
            )
        )
    }

    private fun nextControlSequence(): Long = synchronized(writerLock) { ++controlSequence }

    private fun sendPacket(packet: VideoPacket) {
        val socket = clientSocket ?: return
        val bytes = VideoPacketCodec.encode(packet)
        synchronized(writerLock) {
            socket.getOutputStream().write(bytes)
            socket.getOutputStream().flush()
        }
    }
}

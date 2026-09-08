package com.mtog.app.service

import android.content.Context
import com.mtog.app.clipboard.ClipboardHistoryStore
import com.mtog.app.clipboard.ClipboardSyncManager
import com.mtog.app.clipboard.ClipboardTransferPayload
import com.mtog.app.input.DisplayGeometry
import com.mtog.app.pairing.PairingStore
import com.mtog.app.session.DeviceIdentityStore
import com.mtog.app.session.SessionRuntime
import com.mtog.core.BoundedFrameParser
import com.mtog.core.ControlFrameCodec
import com.mtog.core.ControlProtocolException
import com.mtog.core.ProtocolLimits
import com.mtog.core.SessionEnvelope
import com.mtog.core.SessionMessageType
import com.mtog.core.SessionReplayGuard
import com.mtog.app.transport.WirelessServiceAdvertiser
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.OutputStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketException
import java.util.UUID

class AdbLoopbackServer(
    private val appContext: Context,
    private val scope: CoroutineScope
) {
    companion object {
        const val port: Int = 46001
    }

    private val deviceId: String by lazy { DeviceIdentityStore.getOrCreateDeviceId(appContext) }
    private val deviceName: String by lazy { DeviceIdentityStore.deviceName() }
    private val publicKeyBase64: String by lazy { DeviceIdentityStore.getOrCreatePublicKeyBase64() }
    private val clipboardSyncManager = ClipboardSyncManager(appContext)
    private val wirelessAdvertiser = WirelessServiceAdvertiser(appContext)

    private var serverSocket: ServerSocket? = null
    private var acceptJob: Job? = null
    private var clientJob: Job? = null
    private var clientSocket: Socket? = null
    private var outboundStream: OutputStream? = null
    private val writerLock = Any()
    private val replayGuard = SessionReplayGuard()
    private var activeSessionId: String? = null
    private var activeSessionToken: String? = null
    private var activeClientNonce: String? = null
    private var connectionGeneration: Long = 0
    private var serverNonce: String = ""
    private var handshakeConfirmed = false
    private var activePeerTrusted = false
    private var outboundSequenceNo: Long = 0

    fun start() {
        if (acceptJob?.isActive == true) {
            return
        }

        ClipboardHistoryStore.initialize(appContext)
        PairingStore.initialize(appContext)
        clipboardSyncManager.start()
        SessionRuntime.markStarting()
        acceptJob = scope.launch(Dispatchers.IO) {
            try {
                val server = ServerSocket()
                server.reuseAddress = true
                server.bind(InetSocketAddress(InetAddress.getByName("0.0.0.0"), port))
                serverSocket = server
                SessionRuntime.markListening(port, wirelessEndpointLabel())
                wirelessAdvertiser.start(port, deviceName, deviceId)

                while (isActive) {
                    val socket = server.accept()
                    socket.tcpNoDelay = true
                    attachClient(socket)
                }
            } catch (error: Exception) {
                if (scope.isActive) {
                    SessionRuntime.markError("연결 수신기를 시작하지 못했습니다: ${error.message ?: "알 수 없음"}")
                }
            }
        }
    }

    fun stop() {
        connectionGeneration += 1
        clientJob?.cancel()
        clientJob = null
        closeClient(clientSocket)
        clipboardSyncManager.stop()
        wirelessAdvertiser.stop()
        outboundStream = null
        activeSessionId = null
        activeSessionToken = null
        activeClientNonce = null
        handshakeConfirmed = false
        activePeerTrusted = false
        outboundSequenceNo = 0
        replayGuard.reset()
        acceptJob?.cancel()
        acceptJob = null
        serverSocket?.close()
        serverSocket = null
        SessionRuntime.markStopped()
    }

    fun syncCurrentClipboard(): Boolean {
        val payload = clipboardSyncManager.currentPayload() ?: run {
            SessionRuntime.markClipboardEvent("읽을 수 있는 갤럭시 클립보드가 없습니다. 먼저 복사한 뒤 클립보드 동기화를 누르세요.")
            return false
        }
        val accepted = handleLocalClipboardPayload(payload)
        if (accepted) {
            clipboardSyncManager.recordManualLocalPayload(payload)
            SessionRuntime.markClipboardEvent("갤럭시 ${kindLabel(payload.kind)} 클립보드 동기화를 요청했습니다")
        }
        return accepted
    }

    private suspend fun attachClient(socket: Socket) {
        val previousJob = clientJob
        val previousSocket = clientSocket

        previousJob?.cancel()
        closeClient(previousSocket)
        previousJob?.cancelAndJoin()

        activeSessionId = null
        activeSessionToken = null
        activeClientNonce = null
        handshakeConfirmed = false
        activePeerTrusted = false
        outboundSequenceNo = 0
        connectionGeneration += 1
        val generation = connectionGeneration
        serverNonce = UUID.randomUUID().toString()
        replayGuard.reset()
        clientSocket = socket
        clientJob = scope.launch(Dispatchers.IO) {
            try {
                handleClient(socket, generation)
            } catch (_: SocketException) {
                if (scope.isActive && generation == connectionGeneration && clientSocket === socket) {
                    SessionRuntime.markDisconnected()
                }
            } catch (error: Exception) {
                if (scope.isActive && generation == connectionGeneration && clientSocket === socket) {
                    SessionRuntime.markError("Mac 연결 처리 중 오류가 발생했습니다: ${error.message ?: "알 수 없음"}")
                }
            }
        }
    }

    private fun currentDisplaySize(): Pair<Int, Int> {
        return DisplayGeometry.currentWidth(appContext) to DisplayGeometry.currentHeight(appContext)
    }

    private suspend fun handleClient(socket: Socket, generation: Long) {
        try {
            val input = socket.getInputStream()
            val writer = socket.getOutputStream()
            val parser = BoundedFrameParser()
            val readBuffer = ByteArray(4_096)
            if (clientSocket === socket) {
                outboundStream = writer
            }

            while (scope.isActive && isActiveConnection(socket, generation)) {
                val count = withContext(Dispatchers.IO) { input.read(readBuffer) }
                if (count < 0 || !isActiveConnection(socket, generation)) break
                val frames = parser.append(readBuffer.copyOf(count))
                for (frame in frames) {
                    if (!isActiveConnection(socket, generation)) return
                    val inbound = ControlFrameCodec.decode(frame)
                    val token = inbound.payload["sessionToken"].orEmpty()
                    val clientNonce = inbound.payload["clientNonce"].orEmpty()
                    val inboundServerNonce = inbound.payload["serverNonce"].orEmpty()
                    if (activeSessionId == null) {
                        if (inbound.type != SessionMessageType.Hello ||
                            inbound.payload["protocolVersion"] != ProtocolLimits.VERSION.toString() ||
                            token.isBlank() || clientNonce.isBlank() || inboundServerNonce.isNotEmpty()
                        ) {
                            throw ControlProtocolException.InvalidJson
                        }
                        activeSessionId = inbound.sessionId
                        activeSessionToken = token
                        activeClientNonce = clientNonce
                        replayGuard.begin(inbound.sessionId, token, clientNonce, serverNonce, generation)
                    } else if (inbound.type == SessionMessageType.Hello ||
                        clientNonce != activeClientNonce || inboundServerNonce != serverNonce
                    ) {
                        SessionRuntime.markError("예상하지 못한 세션의 메시지를 거절했습니다")
                        continue
                    }
                    if (inbound.sessionId != activeSessionId || token != activeSessionToken) {
                        SessionRuntime.markError("예상하지 못한 세션의 메시지를 거절했습니다")
                        continue
                    }
                    if (!replayGuard.accept(
                            inbound.sessionId,
                            token,
                            activeClientNonce.orEmpty(),
                            serverNonce,
                            inbound.sequenceNo,
                            generation
                        )
                    ) {
                        PairingStore.markStatus("오래되었거나 재전송된 메시지를 무시했습니다")
                        continue
                    }
                    SessionRuntime.markInbound(inbound.type.wireName)

                    if (handshakeConfirmed && inbound.type in setOf(
                            SessionMessageType.Hello,
                            SessionMessageType.HelloAck,
                            SessionMessageType.HelloConfirm,
                            SessionMessageType.HelloConfirmed
                        )
                    ) {
                        throw ControlProtocolException.InvalidJson
                    }
                    if (!handshakeConfirmed &&
                        inbound.type != SessionMessageType.Hello &&
                        inbound.type != SessionMessageType.HelloConfirm
                    ) {
                        send(
                            writer,
                generation,
                            buildEnvelope(
                                type = SessionMessageType.Error,
                                payload = mapOf("code" to "handshake_required")
                            )
                        )
                        continue
                    }

                if (requiresTrustedPeer(inbound.type) && !activePeerTrusted) {
                    PairingStore.markStatus("먼저 이 Mac을 페어링하고 신뢰해야 합니다: ${inbound.type.wireName}")
                    send(
                        writer,
                generation,
                        buildEnvelope(
                            type = SessionMessageType.Error,
                            payload = mapOf(
                                "code" to "peer_not_trusted",
                                "reason" to "제어 또는 클립보드 동기화 전에 이 Mac을 페어링하고 신뢰해야 합니다."
                            )
                        )
                    )
                    continue
                }

                if (isDeprecatedAccessibilityInput(inbound.type)) {
                    SessionRuntime.markControlEvent("네이티브 HID 입력이 필요해 ${inbound.type.wireName} 요청을 막았습니다")
                    send(
                        writer,
                generation,
                        buildEnvelope(
                            type = SessionMessageType.Error,
                            payload = mapOf(
                                "code" to "native_hid_required",
                                "reason" to "접근성 기반 제어는 비활성화되었습니다. USB AOA HID 또는 scrcpy UHID를 사용하세요."
                            )
                        )
                    )
                    continue
                }

                when (inbound.type) {
                    SessionMessageType.Hello -> {
                        val peerPublicKey = inbound.payload["publicKey"].orEmpty()
                        val trusted = peerPublicKey.isNotEmpty() &&
                            PairingStore.isTrustedPeer(inbound.deviceId, peerPublicKey)
                        activePeerTrusted = trusted
                        PairingStore.markPeerSeen(inbound.deviceName, trusted)
                        val (displayWidth, displayHeight) = currentDisplaySize()
                        send(
                            writer,
                generation,
                            buildEnvelope(
                                type = SessionMessageType.HelloAck,
                                payload = mapOf(
                                    "role" to "android-companion",
                                    "protocolVersion" to ProtocolLimits.VERSION.toString(),
                                    "clientNonce" to inbound.payload["clientNonce"].orEmpty(),
                                    "serverNonce" to serverNonce,
                                    "transport" to "usb-adb-dev",
                                    "transportCandidates" to "usb-adb-dev,usb-aoa-candidate,secure-lan-candidate",
                                    "clipboardKinds" to "text,image,video,file",
                                    "frameProtection" to "session-sequence-replay-guard",
                                    "encryptedAppSession" to "not-enabled-in-dev-build",
                                    "publicKey" to publicKeyBase64,
                                    "trusted" to trusted.toString(),
                                    "displayWidth" to displayWidth.toString(),
                                    "displayHeight" to displayHeight.toString()
                                )
                            )
                        )
                    }

                    SessionMessageType.HelloConfirm -> {
                        handshakeConfirmed = true
                        SessionRuntime.markConnected(inbound.deviceName.ifBlank { "Mac 제어기" })
                        send(
                            writer,
                generation,
                            buildEnvelope(
                                type = SessionMessageType.HelloConfirmed,
                                payload = mapOf(
                                    "protocolVersion" to ProtocolLimits.VERSION.toString(),
                                    "replyTo" to inbound.id
                                )
                            )
                        )
                    }

                    SessionMessageType.PairRequest -> {
                        val expectedCode = PairingStore.currentCode()
                        val receivedCode = inbound.payload["code"].orEmpty()
                        val peerPublicKey = inbound.payload["publicKey"].orEmpty()

                        if (expectedCode.length != 4) {
                            PairingStore.markStatus("페어링 전에 Android에서 4자리 코드를 설정하세요")
                            send(
                                writer,
                generation,
                                buildEnvelope(
                                    type = SessionMessageType.PairResult,
                                    payload = mapOf(
                                        "status" to "rejected",
                                        "reason" to "Android 페어링 코드가 설정되지 않았습니다"
                                    )
                                )
                            )
                        } else if (receivedCode != expectedCode) {
                            PairingStore.markStatus("페어링이 거절되었습니다. 4자리 코드가 다릅니다.")
                            send(
                                writer,
                generation,
                                buildEnvelope(
                                    type = SessionMessageType.PairResult,
                                    payload = mapOf(
                                        "status" to "rejected",
                                        "reason" to "4자리 코드가 일치하지 않습니다"
                                    )
                                )
                            )
                        } else if (peerPublicKey.isBlank()) {
                            PairingStore.markStatus("페어링이 거절되었습니다. 상대 기기 키가 없습니다.")
                            send(
                                writer,
                generation,
                                buildEnvelope(
                                    type = SessionMessageType.PairResult,
                                    payload = mapOf(
                                        "status" to "rejected",
                                        "reason" to "상대 기기 공개 키가 없습니다"
                                    )
                                )
                            )
                        } else {
                            PairingStore.upsertTrustedPeer(
                                deviceId = inbound.deviceId,
                                deviceName = inbound.deviceName,
                                publicKeyBase64 = peerPublicKey
                            )
                            activePeerTrusted = true
                            send(
                                writer,
                generation,
                                buildEnvelope(
                                    type = SessionMessageType.PairResult,
                                    payload = mapOf(
                                        "status" to "accepted",
                                        "publicKey" to publicKeyBase64
                                    )
                                )
                            )
                        }
                    }

                    SessionMessageType.Ping -> {
                        send(
                            writer,
                generation,
                            buildEnvelope(
                                type = SessionMessageType.Pong,
                                payload = mapOf("replyTo" to inbound.id)
                            )
                        )
                    }

                    SessionMessageType.ClipboardPreview -> {
                        clipboardSyncManager.applyRemotePayload(inbound.payload, inbound.deviceName)
                    }

                    else -> Unit
                    }
                }
            }
            if (isActiveConnection(socket, generation)) parser.finish()
            if (isActiveConnection(socket, generation)) {
                SessionRuntime.markDisconnected()
            }
        } catch (_: SocketException) {
            // Expected when the previous client is replaced or the adb tunnel closes.
        } catch (error: ControlProtocolException.UnsupportedVersion) {
            if (isActiveConnection(socket, generation)) {
                SessionRuntime.markError("프로토콜 버전이 맞지 않습니다: ${error.version}")
            }
        } catch (error: Exception) {
            if (scope.isActive && isActiveConnection(socket, generation)) {
                SessionRuntime.markError("연결 세션이 종료되었습니다: ${error.message ?: "알 수 없음"}")
            }
        } finally {
            if (isActiveConnection(socket, generation)) {
                outboundStream = null
                clientSocket = null
                SessionRuntime.markDisconnected()
            }
            closeClient(socket)
        }
    }

    private fun isActiveConnection(socket: Socket, generation: Long): Boolean =
        generation == connectionGeneration && clientSocket === socket

    private suspend fun send(
        writer: OutputStream,
        generation: Long,
        message: SessionEnvelope
    ) {
        if (generation != connectionGeneration || outboundStream !== writer) return
        withContext(Dispatchers.IO) {
            synchronized(writerLock) {
                if (generation != connectionGeneration || outboundStream !== writer) return@synchronized
                outboundSequenceNo += 1
                val encoded = ControlFrameCodec.encode(
                    message.copy(sequenceNo = outboundSequenceNo)
                )
                writer.write(encoded)
                writer.flush()
            }
        }
        if (generation == connectionGeneration && outboundStream === writer) {
            SessionRuntime.markOutbound(message.type.wireName)
        }
    }

    private fun handleLocalClipboardPayload(payload: ClipboardTransferPayload): Boolean {
        val writer = outboundStream ?: run {
            SessionRuntime.markClipboardEvent("Mac 연결 세션을 기다리는 중입니다")
            return false
        }
        if (!handshakeConfirmed || !activePeerTrusted) {
            SessionRuntime.markClipboardEvent("신뢰된 Mac 연결이 준비되어야 클립보드를 보낼 수 있습니다")
            return false
        }
        val generation = connectionGeneration
        scope.launch(Dispatchers.IO) {
            send(
                writer,
                generation,
                buildEnvelope(
                    type = SessionMessageType.ClipboardPreview,
                    payload = payload.toWirePayload()
                )
            )
            if (generation == connectionGeneration && outboundStream === writer) {
                SessionRuntime.markClipboardEvent("갤럭시 ${kindLabel(payload.kind)} 클립보드를 Mac으로 보냈습니다")
            }
        }
        return true
    }

    private fun closeClient(socket: Socket?) {
        if (socket == null) {
            return
        }

        runCatching {
            socket.close()
        }

        if (clientSocket === socket) {
            clientSocket = null
        }
    }

    private fun requiresTrustedPeer(type: SessionMessageType): Boolean {
        return when (type) {
            SessionMessageType.Hello,
            SessionMessageType.HelloAck,
            SessionMessageType.HelloConfirm,
            SessionMessageType.HelloConfirmed,
            SessionMessageType.PairRequest,
            SessionMessageType.PairResult,
            SessionMessageType.Ping,
            SessionMessageType.Pong,
            SessionMessageType.Error -> false
            else -> true
        }
    }

    private fun isDeprecatedAccessibilityInput(type: SessionMessageType): Boolean {
        return when (type) {
            SessionMessageType.EnterControlMode,
            SessionMessageType.ExitControlMode,
            SessionMessageType.RemoteTap,
            SessionMessageType.RemoteGesture,
            SessionMessageType.RemotePinch,
            SessionMessageType.RemoteTouchStart,
            SessionMessageType.RemoteTouchMove,
            SessionMessageType.RemoteTouchEnd,
            SessionMessageType.RemoteBack,
            SessionMessageType.RemoteHome,
            SessionMessageType.RemotePointerUpdate,
            SessionMessageType.RemoteText,
            SessionMessageType.RemoteDeleteBackward,
            SessionMessageType.RemoteEnterKey -> true
            else -> false
        }
    }

    private fun wirelessEndpointLabel(): String {
        val addresses = runCatching {
            NetworkInterface.getNetworkInterfaces()
                .toList()
                .filter { it.isUp && !it.isLoopback }
                .flatMap { networkInterface ->
                    networkInterface.inetAddresses.toList()
                }
                .map { it.hostAddress.orEmpty() }
                .filter { address ->
                    address.isNotBlank() &&
                        !address.contains(":") &&
                        !address.startsWith("127.")
                }
        }.getOrDefault(emptyList())

        return addresses
            .distinct()
            .joinToString(separator = " · ") { "$it:$port" }
            .ifBlank { "두 기기를 같은 개인 네트워크에 연결한 뒤 새로고침하세요." }
    }

    private fun buildEnvelope(
        type: SessionMessageType,
        payload: Map<String, String> = emptyMap(),
        requiresAck: Boolean = false
    ): SessionEnvelope {
        val boundPayload = payload + mapOf(
            "sessionToken" to activeSessionToken.orEmpty(),
            "clientNonce" to activeClientNonce.orEmpty(),
            "serverNonce" to serverNonce
        )
        return SessionEnvelope(
            sessionId = activeSessionId ?: "bootstrap",
            sequenceNo = 0,
            requiresAck = requiresAck,
            type = type,
            deviceId = deviceId,
            deviceName = deviceName,
            payload = boundPayload
        )
    }

    private fun kindLabel(kind: String): String {
        return when (kind.lowercase()) {
            "url" -> "URL"
            "image" -> "이미지"
            "video" -> "영상"
            "file" -> "파일"
            else -> "텍스트"
        }
    }
}

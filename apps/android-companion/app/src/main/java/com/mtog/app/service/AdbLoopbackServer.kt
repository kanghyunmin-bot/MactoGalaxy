package com.mtog.app.service

import android.content.Context
import com.mtog.app.clipboard.ClipboardHistoryStore
import com.mtog.app.clipboard.ClipboardSyncManager
import com.mtog.app.clipboard.ClipboardTransferPayload
import com.mtog.app.input.DisplayGeometry
import com.mtog.app.input.RemoteInputBridge
import com.mtog.app.input.RemoteKeyboardBridge
import com.mtog.app.pairing.PairingStore
import com.mtog.app.session.DeviceIdentityStore
import com.mtog.app.session.SessionCodec
import com.mtog.app.session.SessionEnvelope
import com.mtog.app.session.SessionMessageType
import com.mtog.app.session.SessionReplayGuard
import com.mtog.app.session.SessionRuntime
import com.mtog.app.transport.WirelessServiceAdvertiser
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketException

class AdbLoopbackServer(
    private val appContext: Context,
    private val scope: CoroutineScope
) {
    companion object {
        const val port: Int = 46001
        private const val maxFrameCharacters: Int = 48 * 1_024 * 1_024
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
    private var outboundWriter: BufferedWriter? = null
    private val writerLock = Any()
    private val replayGuard = SessionReplayGuard()
    private var activeSessionId: String? = null
    private var activePeerTrusted = false
    private var outboundSequenceNo: Long = 0

    fun start() {
        if (acceptJob?.isActive == true) {
            return
        }

        ClipboardHistoryStore.initialize(appContext)
        PairingStore.initialize(appContext)
        clipboardSyncManager.start { payload ->
            handleLocalClipboardPayload(payload)
        }
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
        clientJob?.cancel()
        clientJob = null
        closeClient(clientSocket)
        clipboardSyncManager.stop()
        wirelessAdvertiser.stop()
        outboundWriter = null
        activeSessionId = null
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

    private fun attachClient(socket: Socket) {
        val previousJob = clientJob
        val previousSocket = clientSocket

        previousJob?.cancel()
        closeClient(previousSocket)

        activeSessionId = null
        activePeerTrusted = false
        outboundSequenceNo = 0
        replayGuard.reset()
        clientSocket = socket
        clientJob = scope.launch(Dispatchers.IO) {
            try {
                handleClient(socket)
            } catch (_: SocketException) {
                if (scope.isActive) {
                    SessionRuntime.markDisconnected()
                }
            } catch (error: Exception) {
                if (scope.isActive) {
                    SessionRuntime.markError("Mac 연결 처리 중 오류가 발생했습니다: ${error.message ?: "알 수 없음"}")
                }
            }
        }
    }

    private fun currentDisplaySize(): Pair<Int, Int> {
        return DisplayGeometry.currentWidth(appContext) to DisplayGeometry.currentHeight(appContext)
    }

    private suspend fun handleClient(socket: Socket) {
        try {
            val reader = BufferedReader(InputStreamReader(socket.getInputStream(), Charsets.UTF_8))
            val writer = BufferedWriter(OutputStreamWriter(socket.getOutputStream(), Charsets.UTF_8))
            if (clientSocket === socket) {
                outboundWriter = writer
            }

            while (scope.isActive) {
                val line = withContext(Dispatchers.IO) { reader.readLine() } ?: break
                if (line.length > maxFrameCharacters) {
                    SessionRuntime.markError("너무 큰 수신 메시지를 거절했습니다")
                    break
                }
                val inbound = SessionCodec.decodeLine(line)
                if (activeSessionId == null) {
                    activeSessionId = inbound.sessionId
                }
                if (inbound.sessionId != activeSessionId) {
                    SessionRuntime.markError("예상하지 못한 세션의 메시지를 거절했습니다: ${inbound.sessionId}")
                    continue
                }
                if (!replayGuard.accept(inbound)) {
                    PairingStore.markStatus("오래되었거나 재전송된 메시지를 무시했습니다")
                    continue
                }
                SessionRuntime.markConnected(inbound.deviceName.ifBlank { "Mac 제어기" })
                SessionRuntime.markInbound(inbound.type.wireName)

                if (requiresTrustedPeer(inbound.type) && !activePeerTrusted) {
                    PairingStore.markStatus("먼저 이 Mac을 페어링하고 신뢰해야 합니다: ${inbound.type.wireName}")
                    send(
                        writer,
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
                            buildEnvelope(
                                type = SessionMessageType.HelloAck,
                                payload = mapOf(
                                    "role" to "android-companion",
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
                        clipboardSyncManager.currentPayload()?.let { payload ->
                            send(
                                writer,
                                buildEnvelope(
                                    type = SessionMessageType.ClipboardPreview,
                                    payload = payload.toWirePayload()
                                )
                            )
                        }
                    }

                    SessionMessageType.PairRequest -> {
                        val expectedCode = PairingStore.currentCode()
                        val receivedCode = inbound.payload["code"].orEmpty()
                        val peerPublicKey = inbound.payload["publicKey"].orEmpty()

                        if (expectedCode.length != 4) {
                            PairingStore.markStatus("페어링 전에 Android에서 4자리 코드를 설정하세요")
                            send(
                                writer,
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
                            buildEnvelope(
                                type = SessionMessageType.Pong,
                                payload = mapOf("replyTo" to inbound.id)
                            )
                        )
                    }

                    SessionMessageType.EnterControlMode -> {
                        val edge = inbound.payload["edge"].orEmpty()
                        val initialX = when (edge) {
                            "topLeft", "bottomLeft", "left" -> 0.02f
                            else -> 0.98f
                        }
                        val initialY = when (edge) {
                            "bottomLeft", "bottomRight", "bottom" -> 0.98f
                            else -> 0.02f
                        }
                        RemoteInputBridge.showRemoteCursor(initialX, initialY, false)
                        SessionRuntime.markControlEvent(
                                if (edge.isBlank()) "제어 모드에 들어갔습니다" else "$edge 코너에서 제어 모드에 들어갔습니다"
                        )
                    }

                    SessionMessageType.ExitControlMode -> {
                        val reason = inbound.payload["reason"].orEmpty()
                        RemoteInputBridge.hideRemoteCursor()
                        SessionRuntime.markControlEvent(
                                if (reason.isBlank()) "제어 모드에서 나왔습니다" else "제어 모드 종료: $reason"
                        )
                    }

                    SessionMessageType.RemoteBack -> {
                        val ok = RemoteInputBridge.performBack()
                        SessionRuntime.markControlEvent(
                            if (ok) "뒤로 가기 실행" else "뒤로 가기 실패"
                        )
                    }

                    SessionMessageType.RemoteHome -> {
                        val ok = RemoteInputBridge.performHome()
                        SessionRuntime.markControlEvent(
                            if (ok) "홈 실행" else "홈 실행 실패"
                        )
                    }

                    SessionMessageType.RemoteTap -> {
                        val normalizedX = inbound.payload["normalizedX"]?.toFloatOrNull() ?: 0.5f
                        val normalizedY = inbound.payload["normalizedY"]?.toFloatOrNull() ?: 0.5f
                        val ok = RemoteInputBridge.dispatchNormalizedTap(normalizedX, normalizedY)
                        SessionRuntime.markControlEvent(
                            if (ok) {
                                "탭 실행 ${"%.2f".format(normalizedX)}, ${"%.2f".format(normalizedY)}"
                            } else {
                                "탭 실패"
                            }
                        )
                    }

                    SessionMessageType.RemoteTouchStart -> {
                        val normalizedX = inbound.payload["normalizedX"]?.toFloatOrNull() ?: 0.5f
                        val normalizedY = inbound.payload["normalizedY"]?.toFloatOrNull() ?: 0.5f
                        val ok = RemoteInputBridge.beginNormalizedTouch(normalizedX, normalizedY)
                        SessionRuntime.markControlEvent(
                            if (ok) {
                                "터치 시작 ${"%.2f".format(normalizedX)}, ${"%.2f".format(normalizedY)}"
                            } else {
                                "터치 시작 실패"
                            }
                        )
                    }

                    SessionMessageType.RemoteTouchMove -> {
                        val normalizedX = inbound.payload["normalizedX"]?.toFloatOrNull() ?: 0.5f
                        val normalizedY = inbound.payload["normalizedY"]?.toFloatOrNull() ?: 0.5f
                        val ok = RemoteInputBridge.moveNormalizedTouch(normalizedX, normalizedY)
                        SessionRuntime.markControlEvent(
                            if (ok) {
                                "터치 이동 ${"%.2f".format(normalizedX)}, ${"%.2f".format(normalizedY)}"
                            } else {
                                "터치 이동 실패"
                            }
                        )
                    }

                    SessionMessageType.RemoteTouchEnd -> {
                        val normalizedX = inbound.payload["normalizedX"]?.toFloatOrNull() ?: 0.5f
                        val normalizedY = inbound.payload["normalizedY"]?.toFloatOrNull() ?: 0.5f
                        val ok = RemoteInputBridge.endNormalizedTouch(normalizedX, normalizedY)
                        SessionRuntime.markControlEvent(
                            if (ok) {
                                "터치 종료 ${"%.2f".format(normalizedX)}, ${"%.2f".format(normalizedY)}"
                            } else {
                                "터치 종료 실패"
                            }
                        )
                    }

                    SessionMessageType.RemoteGesture -> {
                        val kind = inbound.payload["kind"].orEmpty()
                        val startX = inbound.payload["startX"]?.toFloatOrNull() ?: 0.5f
                        val startY = inbound.payload["startY"]?.toFloatOrNull() ?: 0.5f
                        val endX = inbound.payload["endX"]?.toFloatOrNull() ?: startX
                        val endY = inbound.payload["endY"]?.toFloatOrNull() ?: startY
                        val durationMs = inbound.payload["durationMs"]?.toLongOrNull() ?: 90L
                        val ok = if (kind == "longPress" || kind == "contextPress") {
                            RemoteInputBridge.dispatchNormalizedLongPress(
                                normalizedX = startX,
                                normalizedY = startY,
                                durationMs = durationMs
                            )
                        } else {
                            RemoteInputBridge.dispatchNormalizedGesture(
                                startX = startX,
                                startY = startY,
                                endX = endX,
                                endY = endY,
                                durationMs = durationMs
                            )
                        }
                        SessionRuntime.markControlEvent(
                            if (ok) {
                                "제스처 $kind ${"%.2f".format(startX)}, ${"%.2f".format(startY)} → ${"%.2f".format(endX)}, ${"%.2f".format(endY)}"
                            } else {
                                "제스처 $kind 실패"
                            }
                        )
                    }

                    SessionMessageType.RemotePinch -> {
                        val centerX = inbound.payload["centerX"]?.toFloatOrNull() ?: 0.5f
                        val centerY = inbound.payload["centerY"]?.toFloatOrNull() ?: 0.5f
                        val magnification = inbound.payload["magnification"]?.toFloatOrNull() ?: 0f
                        val ok = RemoteInputBridge.dispatchNormalizedPinch(
                            centerX = centerX,
                            centerY = centerY,
                            magnification = magnification
                        )
                        SessionRuntime.markControlEvent(
                            if (ok) {
                                "핀치 ${"%.2f".format(centerX)}, ${"%.2f".format(centerY)} 배율=${"%.2f".format(magnification)}"
                            } else {
                                "핀치 실패"
                            }
                        )
                    }

                    SessionMessageType.RemotePointerUpdate -> {
                        val normalizedX = inbound.payload["normalizedX"]?.toFloatOrNull() ?: 0.5f
                        val normalizedY = inbound.payload["normalizedY"]?.toFloatOrNull() ?: 0.5f
                        val pressed = inbound.payload["primaryButtonDown"] == "true"
                        RemoteInputBridge.showRemoteCursor(normalizedX, normalizedY, pressed)
                        SessionRuntime.markControlEvent(
                            "원격 커서 ${"%.2f".format(normalizedX)}, ${"%.2f".format(normalizedY)}"
                        )
                    }

                    SessionMessageType.RemoteText -> {
                        val text = inbound.payload["text"].orEmpty()
                        val usedIme = text.isNotEmpty() && RemoteKeyboardBridge.commitText(text)
                        val usedAccessibilityInsert = !usedIme && text.isNotEmpty() && RemoteInputBridge.insertText(text)
                        val usedNativePaste = !usedIme &&
                            !usedAccessibilityInsert &&
                            text.isNotEmpty() &&
                            clipboardSyncManager.withTemporaryPlainText(text) {
                                RemoteInputBridge.pasteFromClipboard()
                            }
                        val ok = usedIme || usedAccessibilityInsert || usedNativePaste
                        SessionRuntime.markControlEvent(
                            if (ok) {
                                when {
                                    usedIme -> "MtoG 키보드 입력기로 텍스트를 입력했습니다"
                                    usedAccessibilityInsert -> "접근성 보조 방식으로 텍스트를 입력했습니다"
                                    else -> "임시 클립보드 붙여넣기로 텍스트를 입력했습니다"
                                }
                            } else {
                                "텍스트 입력 실패"
                            }
                        )
                    }

                    SessionMessageType.RemoteDeleteBackward -> {
                        val usedIme = RemoteKeyboardBridge.deleteBackward()
                        val usedAccessibilityDelete = !usedIme && RemoteInputBridge.deleteBackward()
                        val ok = usedIme || usedAccessibilityDelete
                        SessionRuntime.markControlEvent(
                            if (ok) {
                                if (usedIme) "MtoG 키보드 입력기로 이전 글자를 삭제했습니다"
                                else "Android 편집 동작으로 이전 글자를 삭제했습니다"
                            } else {
                                "삭제 실패"
                            }
                        )
                    }

                    SessionMessageType.RemoteEnterKey -> {
                        val usedIme = RemoteKeyboardBridge.performEnter()
                        val usedAccessibilityEnter = !usedIme && RemoteInputBridge.performEnter()
                        val ok = usedIme || usedAccessibilityEnter
                        SessionRuntime.markControlEvent(
                            if (ok) {
                                if (usedIme) "MtoG 키보드 입력기로 Enter를 실행했습니다"
                                else "Android 편집 동작으로 Enter를 실행했습니다"
                            } else {
                                "Enter 실행 실패"
                            }
                        )
                    }

                    SessionMessageType.ClipboardPreview -> {
                        clipboardSyncManager.applyRemotePayload(inbound.payload, inbound.deviceName)
                    }

                    else -> Unit
                }
            }
            if (clientSocket === socket) {
                SessionRuntime.markDisconnected()
            }
        } catch (_: SocketException) {
            // Expected when the previous client is replaced or the adb tunnel closes.
        } catch (error: Exception) {
            if (scope.isActive) {
                SessionRuntime.markError("연결 세션이 종료되었습니다: ${error.message ?: "알 수 없음"}")
            }
        } finally {
            if (clientSocket === socket) {
                outboundWriter = null
                clientSocket = null
                SessionRuntime.markDisconnected()
            }
            closeClient(socket)
        }
    }

    private suspend fun send(
        writer: BufferedWriter,
        message: SessionEnvelope
    ) {
        withContext(Dispatchers.IO) {
            val encoded = String(SessionCodec.encodeLine(message), Charsets.UTF_8)
            if (encoded.length > maxFrameCharacters) {
                SessionRuntime.markError("너무 큰 송신 메시지를 거절했습니다")
                return@withContext
            }
            synchronized(writerLock) {
                writer.write(encoded)
                writer.flush()
            }
        }
        SessionRuntime.markOutbound(message.type.wireName)
    }

    private fun handleLocalClipboardPayload(payload: ClipboardTransferPayload): Boolean {
        val writer = outboundWriter ?: run {
            SessionRuntime.markClipboardEvent("Mac 연결 세션을 기다리는 중입니다")
            return false
        }
        if (!activePeerTrusted) {
            SessionRuntime.markClipboardEvent("Mac을 신뢰 기기로 등록해야 클립보드를 보낼 수 있습니다")
            return false
        }
        scope.launch(Dispatchers.IO) {
            send(
                writer,
                buildEnvelope(
                    type = SessionMessageType.ClipboardPreview,
                    payload = payload.toWirePayload()
                )
            )
            SessionRuntime.markClipboardEvent("갤럭시 ${kindLabel(payload.kind)} 클립보드를 Mac으로 보냈습니다")
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
        outboundSequenceNo += 1
        return SessionEnvelope(
            sessionId = activeSessionId ?: "bootstrap",
            sequenceNo = outboundSequenceNo,
            requiresAck = requiresAck,
            type = type,
            deviceId = deviceId,
            deviceName = deviceName,
            payload = payload
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

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

                while (isActive) {
                    val socket = server.accept()
                    socket.tcpNoDelay = true
                    attachClient(socket)
                }
            } catch (error: Exception) {
                if (scope.isActive) {
                    SessionRuntime.markError("ADB listener failed: ${error.message ?: "unknown"}")
                }
            }
        }
    }

    fun stop() {
        clientJob?.cancel()
        clientJob = null
        closeClient(clientSocket)
        clipboardSyncManager.stop()
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
            SessionRuntime.markClipboardEvent("No readable Android clipboard item. Copy first, then tap Sync Clipboard.")
            return false
        }
        val accepted = handleLocalClipboardPayload(payload)
        if (accepted) {
            clipboardSyncManager.recordManualLocalPayload(payload)
            SessionRuntime.markClipboardEvent("Manual Android ${payload.kind} clipboard sync requested")
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
                    SessionRuntime.markError("Client loop failed: ${error.message ?: "unknown"}")
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
                    SessionRuntime.markError("Rejected oversized inbound frame")
                    break
                }
                val inbound = SessionCodec.decodeLine(line)
                if (activeSessionId == null) {
                    activeSessionId = inbound.sessionId
                }
                if (inbound.sessionId != activeSessionId) {
                    SessionRuntime.markError("Rejected frame from unexpected session ${inbound.sessionId}")
                    continue
                }
                if (!replayGuard.accept(inbound)) {
                    PairingStore.markStatus("Ignored stale or replayed frame")
                    continue
                }
                SessionRuntime.markConnected(inbound.deviceName.ifBlank { "Mac controller" })
                SessionRuntime.markInbound(inbound.type.wireName)

                if (requiresTrustedPeer(inbound.type) && !activePeerTrusted) {
                    PairingStore.markStatus("Blocked ${inbound.type.wireName}. Pair and trust this Mac first.")
                    send(
                        writer,
                        buildEnvelope(
                            type = SessionMessageType.Error,
                            payload = mapOf(
                                "code" to "peer_not_trusted",
                                "reason" to "Pair and trust this Mac before control or clipboard sync."
                            )
                        )
                    )
                    continue
                }

                if (isDeprecatedAccessibilityInput(inbound.type)) {
                    SessionRuntime.markControlEvent("Blocked ${inbound.type.wireName}: native HID input is required")
                    send(
                        writer,
                        buildEnvelope(
                            type = SessionMessageType.Error,
                            payload = mapOf(
                                "code" to "native_hid_required",
                                "reason" to "Accessibility-based control is disabled. Use USB AOA HID or scrcpy UHID."
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
                            PairingStore.markStatus("Set the 4-digit code on Android before pairing")
                            send(
                                writer,
                                buildEnvelope(
                                    type = SessionMessageType.PairResult,
                                    payload = mapOf(
                                        "status" to "rejected",
                                        "reason" to "Android pairing code is not set"
                                    )
                                )
                            )
                        } else if (receivedCode != expectedCode) {
                            PairingStore.markStatus("Pairing rejected. 4-digit code mismatch.")
                            send(
                                writer,
                                buildEnvelope(
                                    type = SessionMessageType.PairResult,
                                    payload = mapOf(
                                        "status" to "rejected",
                                        "reason" to "4-digit code mismatch"
                                    )
                                )
                            )
                        } else if (peerPublicKey.isBlank()) {
                            PairingStore.markStatus("Pairing rejected. Peer key missing.")
                            send(
                                writer,
                                buildEnvelope(
                                    type = SessionMessageType.PairResult,
                                    payload = mapOf(
                                        "status" to "rejected",
                                        "reason" to "Peer public key missing"
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
                            if (edge.isBlank()) "Control mode entered" else "Control mode entered from $edge edge"
                        )
                    }

                    SessionMessageType.ExitControlMode -> {
                        val reason = inbound.payload["reason"].orEmpty()
                        RemoteInputBridge.hideRemoteCursor()
                        SessionRuntime.markControlEvent(
                            if (reason.isBlank()) "Control mode exited" else "Control mode exited: $reason"
                        )
                    }

                    SessionMessageType.RemoteBack -> {
                        val ok = RemoteInputBridge.performBack()
                        SessionRuntime.markControlEvent(
                            if (ok) "Executed Back action" else "Back action failed"
                        )
                    }

                    SessionMessageType.RemoteHome -> {
                        val ok = RemoteInputBridge.performHome()
                        SessionRuntime.markControlEvent(
                            if (ok) "Executed Home action" else "Home action failed"
                        )
                    }

                    SessionMessageType.RemoteTap -> {
                        val normalizedX = inbound.payload["normalizedX"]?.toFloatOrNull() ?: 0.5f
                        val normalizedY = inbound.payload["normalizedY"]?.toFloatOrNull() ?: 0.5f
                        val ok = RemoteInputBridge.dispatchNormalizedTap(normalizedX, normalizedY)
                        SessionRuntime.markControlEvent(
                            if (ok) {
                                "Tapped Android at ${"%.2f".format(normalizedX)}, ${"%.2f".format(normalizedY)}"
                            } else {
                                "Tap failed"
                            }
                        )
                    }

                    SessionMessageType.RemoteTouchStart -> {
                        val normalizedX = inbound.payload["normalizedX"]?.toFloatOrNull() ?: 0.5f
                        val normalizedY = inbound.payload["normalizedY"]?.toFloatOrNull() ?: 0.5f
                        val ok = RemoteInputBridge.beginNormalizedTouch(normalizedX, normalizedY)
                        SessionRuntime.markControlEvent(
                            if (ok) {
                                "Touch start ${"%.2f".format(normalizedX)}, ${"%.2f".format(normalizedY)}"
                            } else {
                                "Touch start failed"
                            }
                        )
                    }

                    SessionMessageType.RemoteTouchMove -> {
                        val normalizedX = inbound.payload["normalizedX"]?.toFloatOrNull() ?: 0.5f
                        val normalizedY = inbound.payload["normalizedY"]?.toFloatOrNull() ?: 0.5f
                        val ok = RemoteInputBridge.moveNormalizedTouch(normalizedX, normalizedY)
                        SessionRuntime.markControlEvent(
                            if (ok) {
                                "Touch move ${"%.2f".format(normalizedX)}, ${"%.2f".format(normalizedY)}"
                            } else {
                                "Touch move failed"
                            }
                        )
                    }

                    SessionMessageType.RemoteTouchEnd -> {
                        val normalizedX = inbound.payload["normalizedX"]?.toFloatOrNull() ?: 0.5f
                        val normalizedY = inbound.payload["normalizedY"]?.toFloatOrNull() ?: 0.5f
                        val ok = RemoteInputBridge.endNormalizedTouch(normalizedX, normalizedY)
                        SessionRuntime.markControlEvent(
                            if (ok) {
                                "Touch end ${"%.2f".format(normalizedX)}, ${"%.2f".format(normalizedY)}"
                            } else {
                                "Touch end failed"
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
                                "Gesture $kind ${"%.2f".format(startX)}, ${"%.2f".format(startY)} -> ${"%.2f".format(endX)}, ${"%.2f".format(endY)}"
                            } else {
                                "Gesture $kind failed"
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
                                "Pinch ${"%.2f".format(centerX)}, ${"%.2f".format(centerY)} scale=${"%.2f".format(magnification)}"
                            } else {
                                "Pinch failed"
                            }
                        )
                    }

                    SessionMessageType.RemotePointerUpdate -> {
                        val normalizedX = inbound.payload["normalizedX"]?.toFloatOrNull() ?: 0.5f
                        val normalizedY = inbound.payload["normalizedY"]?.toFloatOrNull() ?: 0.5f
                        val pressed = inbound.payload["primaryButtonDown"] == "true"
                        RemoteInputBridge.showRemoteCursor(normalizedX, normalizedY, pressed)
                        SessionRuntime.markControlEvent(
                            "Remote cursor ${"%.2f".format(normalizedX)}, ${"%.2f".format(normalizedY)}"
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
                                    usedIme -> "Inserted text through MtoG Keyboard IME path"
                                    usedAccessibilityInsert -> "Inserted text through accessibility fallback"
                                    else -> "Inserted text through temporary clipboard paste fallback"
                                }
                            } else {
                                "Text input failed"
                            }
                        )
                    }

                    SessionMessageType.RemoteDeleteBackward -> {
                        val usedIme = RemoteKeyboardBridge.deleteBackward()
                        val usedAccessibilityDelete = !usedIme && RemoteInputBridge.deleteBackward()
                        val ok = usedIme || usedAccessibilityDelete
                        SessionRuntime.markControlEvent(
                            if (ok) {
                                if (usedIme) "Deleted previous character through MtoG Keyboard IME path"
                                else "Deleted previous character through native accessibility action"
                            } else {
                                "Delete failed"
                            }
                        )
                    }

                    SessionMessageType.RemoteEnterKey -> {
                        val usedIme = RemoteKeyboardBridge.performEnter()
                        val usedAccessibilityEnter = !usedIme && RemoteInputBridge.performEnter()
                        val ok = usedIme || usedAccessibilityEnter
                        SessionRuntime.markControlEvent(
                            if (ok) {
                                if (usedIme) "Executed Enter through MtoG Keyboard IME path"
                                else "Executed Enter through native editor action"
                            } else {
                                "Enter failed"
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
                SessionRuntime.markError("ADB session closed: ${error.message ?: "unknown"}")
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
                SessionRuntime.markError("Rejected oversized outbound frame")
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
            SessionRuntime.markClipboardEvent("Manual clipboard sync waiting for Mac session")
            return false
        }
        if (!activePeerTrusted) {
            SessionRuntime.markClipboardEvent("Manual clipboard sync blocked until Mac is trusted")
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
            SessionRuntime.markClipboardEvent("Sent Android ${payload.kind} clipboard to Mac")
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
            .ifBlank { "Connect both devices to the same private network, then refresh." }
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
}

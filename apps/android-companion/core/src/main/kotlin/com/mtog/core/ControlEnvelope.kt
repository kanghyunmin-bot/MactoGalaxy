package com.mtog.core

import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.UUID

enum class SessionMessageType(val wireName: String) {
    Hello("hello"),
    HelloAck("helloAck"),
    HelloConfirm("helloConfirm"),
    HelloConfirmed("helloConfirmed"),
    PairRequest("pairRequest"),
    PairResult("pairResult"),
    EnterControlMode("enterControlMode"),
    ExitControlMode("exitControlMode"),
    RemoteTap("remoteTap"),
    RemoteGesture("remoteGesture"),
    RemotePinch("remotePinch"),
    RemoteTouchStart("remoteTouchStart"),
    RemoteTouchMove("remoteTouchMove"),
    RemoteTouchEnd("remoteTouchEnd"),
    RemoteBack("remoteBack"),
    RemoteHome("remoteHome"),
    RemotePointerUpdate("remotePointerUpdate"),
    RemoteText("remoteText"),
    RemoteDeleteBackward("remoteDeleteBackward"),
    RemoteEnterKey("remoteEnterKey"),
    Ping("ping"),
    Pong("pong"),
    ClipboardPreview("clipboardPreview"),
    Error("error");

    companion object {
        fun fromWireName(value: String): SessionMessageType =
            entries.firstOrNull { it.wireName == value }
                ?: throw ControlProtocolException.InvalidJson
    }
}

data class SessionEnvelope(
    val id: String = UUID.randomUUID().toString(),
    val sessionId: String = UUID.randomUUID().toString(),
    val sequenceNo: Long = 0,
    val requiresAck: Boolean = false,
    val type: SessionMessageType,
    val sentAt: String = Instant.now().truncatedTo(ChronoUnit.SECONDS).toString(),
    val deviceId: String,
    val deviceName: String,
    val payload: Map<String, String> = emptyMap()
)

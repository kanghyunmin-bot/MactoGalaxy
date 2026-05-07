package com.mtog.app.session

import org.json.JSONObject
import java.time.Instant
import java.util.UUID

enum class SessionMessageType(val wireName: String) {
    Hello("hello"),
    HelloAck("helloAck"),
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
        fun fromWireName(value: String): SessionMessageType {
            return entries.firstOrNull { it.wireName == value } ?: Error
        }
    }
}

data class SessionEnvelope(
    val id: String = UUID.randomUUID().toString(),
    val sessionId: String = UUID.randomUUID().toString(),
    val sequenceNo: Long = 0,
    val requiresAck: Boolean = false,
    val type: SessionMessageType,
    val sentAt: String = Instant.now().toString(),
    val deviceId: String,
    val deviceName: String,
    val payload: Map<String, String> = emptyMap()
)

object SessionCodec {
    fun encodeLine(message: SessionEnvelope): ByteArray {
        val payloadObject = JSONObject()
        message.payload.forEach { (key, value) ->
            payloadObject.put(key, value)
        }

        val root = JSONObject()
            .put("id", message.id)
            .put("sessionId", message.sessionId)
            .put("sequenceNo", message.sequenceNo)
            .put("requiresAck", message.requiresAck)
            .put("type", message.type.wireName)
            .put("sentAt", message.sentAt)
            .put("deviceId", message.deviceId)
            .put("deviceName", message.deviceName)
            .put("payload", payloadObject)

        return (root.toString() + "\n").toByteArray(Charsets.UTF_8)
    }

    fun decodeLine(line: String): SessionEnvelope {
        val root = JSONObject(line)
        val payloadObject = root.optJSONObject("payload") ?: JSONObject()
        val payload = buildMap {
            val keys = payloadObject.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                put(key, payloadObject.optString(key))
            }
        }

        return SessionEnvelope(
            id = root.getString("id"),
            sessionId = root.optString("sessionId", UUID.randomUUID().toString()),
            sequenceNo = root.optLong("sequenceNo", 0),
            requiresAck = root.optBoolean("requiresAck", false),
            type = SessionMessageType.fromWireName(root.getString("type")),
            sentAt = root.getString("sentAt"),
            deviceId = root.getString("deviceId"),
            deviceName = root.optString("deviceName", "Unknown peer"),
            payload = payload
        )
    }
}

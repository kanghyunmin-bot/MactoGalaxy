package com.mtog.core

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.charset.CodingErrorAction
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long


data class ControlFrame(val flags: Int, val payload: ByteArray) {
    companion object {
        const val HEADER_BYTES = 12
        val MAGIC = byteArrayOf(0x4d, 0x54, 0x47, 0x32)
        const val CHANNEL = 1
        const val ENVELOPE_TYPE = 1
    }

    override fun equals(other: Any?): Boolean =
        other is ControlFrame && flags == other.flags && payload.contentEquals(other.payload)

    override fun hashCode(): Int = 31 * flags + payload.contentHashCode()
}

sealed class ControlProtocolException : Exception() {
    data object InvalidMagic : ControlProtocolException()
    data class UnsupportedVersion(val version: Int) : ControlProtocolException()
    data class InvalidChannel(val channel: Int) : ControlProtocolException()
    data class InvalidType(val type: Int) : ControlProtocolException()
    data class PayloadTooLarge(val length: Long) : ControlProtocolException()
    data object TruncatedFrame : ControlProtocolException()
    data object InvalidUtf8 : ControlProtocolException()
    data object InvalidJson : ControlProtocolException()
}

object ControlFrameCodec {
    private val json = Json { explicitNulls = false }

    fun encode(envelope: SessionEnvelope, flags: Int = 0): ByteArray {
        val payload = encodePayload(envelope)
        if (payload.size > ProtocolLimits.CONTROL_PAYLOAD_BYTES) {
            throw ControlProtocolException.PayloadTooLarge(payload.size.toLong())
        }
        return ByteBuffer.allocate(ControlFrame.HEADER_BYTES + payload.size)
            .order(ByteOrder.BIG_ENDIAN)
            .put(ControlFrame.MAGIC)
            .put(ProtocolLimits.VERSION.toByte())
            .put(ControlFrame.CHANNEL.toByte())
            .put(ControlFrame.ENVELOPE_TYPE.toByte())
            .put(flags.toByte())
            .putInt(payload.size)
            .put(payload)
            .array()
    }

    fun encodePayload(envelope: SessionEnvelope): ByteArray {
        val root = JsonObject(
            mapOf(
                "deviceId" to JsonPrimitive(envelope.deviceId),
                "deviceName" to JsonPrimitive(envelope.deviceName),
                "id" to JsonPrimitive(envelope.id),
                "payload" to JsonObject(envelope.payload.mapValues { JsonPrimitive(it.value) }),
                "requiresAck" to JsonPrimitive(envelope.requiresAck),
                "sentAt" to JsonPrimitive(envelope.sentAt),
                "sequenceNo" to JsonPrimitive(envelope.sequenceNo),
                "sessionId" to JsonPrimitive(envelope.sessionId),
                "type" to JsonPrimitive(envelope.type.wireName)
            )
        )
        return json.encodeToString(JsonElement.serializer(), canonical(root)).toByteArray(Charsets.UTF_8)
    }

    fun decode(frame: ControlFrame): SessionEnvelope = decodePayload(frame.payload)

    fun decodePayload(payload: ByteArray): SessionEnvelope {
        val text = try {
            Charsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(payload))
                .toString()
        } catch (_: Exception) {
            throw ControlProtocolException.InvalidUtf8
        }
        return try {
            val root = json.parseToJsonElement(text).jsonObject
            val payloadObject = root.getValue("payload").jsonObject
            val envelope = SessionEnvelope(
                id = root.requiredString("id"),
                sessionId = root.requiredString("sessionId"),
                sequenceNo = root.getValue("sequenceNo").jsonPrimitive.long,
                requiresAck = root.getValue("requiresAck").jsonPrimitive.boolean,
                type = SessionMessageType.fromWireName(root.requiredString("type")),
                sentAt = root.requiredString("sentAt"),
                deviceId = root.requiredString("deviceId"),
                deviceName = root.requiredString("deviceName"),
                payload = payloadObject.mapValues { (_, value) ->
                    value.jsonPrimitive.contentOrNull ?: throw ControlProtocolException.InvalidJson
                }
            )
            if (envelope.sequenceNo <= 0 || envelope.sessionId.isBlank() ||
                envelope.deviceId.isBlank() || envelope.deviceName.isBlank()
            ) {
                throw ControlProtocolException.InvalidJson
            }
            val parsedId = java.util.UUID.fromString(envelope.id)
            if (!parsedId.toString().equals(envelope.id, ignoreCase = true)) {
                throw ControlProtocolException.InvalidJson
            }
            java.time.Instant.parse(envelope.sentAt)
            envelope
        } catch (error: ControlProtocolException) {
            throw error
        } catch (_: Exception) {
            throw ControlProtocolException.InvalidJson
        }
    }

    private fun canonical(element: JsonElement): JsonElement = when (element) {
        is JsonObject -> JsonObject(element.entries.sortedBy { it.key }.associate { it.key to canonical(it.value) })
        else -> element
    }

    private fun JsonObject.requiredString(key: String): String =
        getValue(key).jsonPrimitive.contentOrNull ?: throw ControlProtocolException.InvalidJson
}

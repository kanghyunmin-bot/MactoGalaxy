package com.mtog.core

import java.io.File
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals

class ProtocolFixtureWalkingTest {
    @Test
    fun sharedManifestMatchesCoreLimits() {
        val fixtureRoot = requireNotNull(System.getProperty("mtog.fixtureRoot"))
        val manifest = Json.parseToJsonElement(
            File(fixtureRoot, "protocol-v2/manifest.json").readText()
        ).jsonObject
        val limits = manifest.getValue("limits").jsonObject

        assertEquals(ProtocolLimits.VERSION, manifest.getValue("protocolVersion").jsonPrimitive.int)
        assertEquals(
            ProtocolLimits.CONTROL_PAYLOAD_BYTES,
            limits.getValue("controlPayloadBytes").jsonPrimitive.int
        )
        assertEquals(
            ProtocolLimits.VIDEO_PAYLOAD_BYTES,
            limits.getValue("videoPayloadBytes").jsonPrimitive.int
        )
        assertEquals(ProtocolLimits.VIDEO_CONFIG_BYTES, limits.getValue("videoConfigBytes").jsonPrimitive.int)
        assertEquals(ProtocolLimits.VIDEO_CONTROL_BYTES, limits.getValue("videoControlBytes").jsonPrimitive.int)
        assertEquals(ProtocolLimits.MAXIMUM_VIDEO_DIMENSION, limits.getValue("maximumVideoDimension").jsonPrimitive.int)
        assertEquals(
            ProtocolLimits.AUTOMATIC_CLIPBOARD_BYTES,
            limits.getValue("automaticClipboardBytes").jsonPrimitive.int
        )
    }
}

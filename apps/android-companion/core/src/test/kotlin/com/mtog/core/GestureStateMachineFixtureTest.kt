package com.mtog.core

import java.io.File
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals

@Serializable
private data class GestureFixture(val vectors: List<GestureVector>)

@Serializable
private data class GestureVector(
    val name: String,
    val events: List<GestureEvent>,
    val commands: List<GestureCommand>
)

class GestureStateMachineFixtureTest {
    @Test
    fun sharedGestureVectorsMatch() {
        val root = File(requireNotNull(System.getProperty("mtog.fixtureRoot")), "protocol-v2/input/gestures.json")
        val fixture = Json { ignoreUnknownKeys = false }.decodeFromString<GestureFixture>(root.readText())
        fixture.vectors.forEach { vector ->
            val machine = GestureStateMachine()
            val commands = vector.events.flatMap(machine::process)
            assertEquals(vector.commands, commands, "gesture vector failed: ${vector.name}")
        }
    }
}

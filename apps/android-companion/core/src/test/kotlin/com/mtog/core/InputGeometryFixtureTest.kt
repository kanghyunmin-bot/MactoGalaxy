package com.mtog.core

import java.io.File
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals

class InputGeometryFixtureTest {
    @Test
    fun sharedAspectFitVectorsMatch() {
        val root = File(requireNotNull(System.getProperty("mtog.fixtureRoot")), "protocol-v2/input/geometry.json")
        val vectors = Json.parseToJsonElement(root.readText()).jsonObject.getValue("vectors").jsonArray
        vectors.forEach { element ->
            val vector = element.jsonObject
            fun number(key: String) = vector.getValue(key).jsonPrimitive.double
            val rect = DisplayGeometry.aspectFit(
                number("containerWidth"), number("containerHeight"),
                number("contentWidth"), number("contentHeight")
            )
            assertEquals(DisplayRect(number("left"), number("top"), number("width"), number("height")), rect)
            assertEquals(
                DisplayPoint(number("mappedX").toInt(), number("mappedY").toInt()),
                DisplayGeometry.mapNormalized(number("normalizedX"), number("normalizedY"), rect)
            )
        }
    }
}

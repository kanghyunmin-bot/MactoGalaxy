package com.mtog.core

import kotlin.math.roundToInt

data class DisplayPoint(val x: Int, val y: Int)

object DisplayGeometry {
    fun mapNormalized(x: Double, y: Double, width: Int, height: Int): DisplayPoint {
        require(width > 0 && height > 0)
        require(x.isFinite() && y.isFinite() && x in 0.0..1.0 && y in 0.0..1.0)
        return DisplayPoint((x * width).roundToInt(), (y * height).roundToInt())
    }
}

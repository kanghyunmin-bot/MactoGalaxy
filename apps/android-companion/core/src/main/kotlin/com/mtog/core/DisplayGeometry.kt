package com.mtog.core

import kotlin.math.roundToInt

data class DisplayPoint(val x: Int, val y: Int)
data class DisplayRect(val left: Double, val top: Double, val width: Double, val height: Double)

object DisplayGeometry {
    fun aspectFit(containerWidth: Double, containerHeight: Double, contentWidth: Double, contentHeight: Double): DisplayRect {
        require(containerWidth > 0 && containerHeight > 0 && contentWidth > 0 && contentHeight > 0)
        val scale = minOf(containerWidth / contentWidth, containerHeight / contentHeight)
        val width = contentWidth * scale
        val height = contentHeight * scale
        return DisplayRect((containerWidth - width) / 2, (containerHeight - height) / 2, width, height)
    }

    fun mapNormalized(x: Double, y: Double, rect: DisplayRect): DisplayPoint {
        require(x.isFinite() && y.isFinite() && x in 0.0..1.0 && y in 0.0..1.0)
        return DisplayPoint((rect.left + x * rect.width).roundToInt(), (rect.top + y * rect.height).roundToInt())
    }

    fun mapNormalized(x: Double, y: Double, width: Int, height: Int): DisplayPoint {
        require(width > 0 && height > 0)
        require(x.isFinite() && y.isFinite() && x in 0.0..1.0 && y in 0.0..1.0)
        return DisplayPoint((x * width).roundToInt(), (y * height).roundToInt())
    }
}

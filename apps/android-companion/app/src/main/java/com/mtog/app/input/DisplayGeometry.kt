package com.mtog.app.input

import android.content.Context
import android.graphics.Rect
import android.view.WindowManager

object DisplayGeometry {
    fun currentBounds(context: Context): Rect {
        val windowManager = context.getSystemService(WindowManager::class.java)
        return windowManager.currentWindowMetrics.bounds
    }

    fun currentWidth(context: Context): Int = currentBounds(context).width()

    fun currentHeight(context: Context): Int = currentBounds(context).height()
}
